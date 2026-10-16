"""No game processes: validate preparation and catch misleading clip reports."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE/(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare, verify = load('prepare'), load('verify')


class FixtureChecks(unittest.TestCase):
    def test_prepare_only_and_refuse_existing_profile(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = SimpleNamespace(game=root/'game', jdk=root/'jdk', java=root/'java', zombie_buddy_mod=root/'buddy',
                                   patch_mod=root/'patch', ffmpeg=root/'ffmpeg', profile=root/'new profile', language='EN')
            for file in [args.game/'projectzomboid.jar', args.game/'ZombieBuddy.jar', args.zombie_buddy_mod/'42/mod.info',
                         args.zombie_buddy_mod/'libs/ZombieBuddy.jar', args.patch_mod/'42/mod.info',
                         args.patch_mod/'42/media/java/PZToolkitJavaPatches.jar', args.java, args.jdk/'bin/javac', args.ffmpeg]:
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(b'fixture dependency')
                file.chmod(0o700)
            with patch.object(prepare.sys, 'platform', 'darwin'), patch.object(prepare.subprocess, 'run',
                    return_value=subprocess.CompletedProcess([], 0, stdout='javac 25.0.1')) as run:
                descriptor = prepare.prepare(args)
                self.assertEqual(len(run.call_args_list), 2)
                self.assertTrue(all(call.args[0][0] == str((args.jdk/'bin/javac').resolve()) for call in run.call_args_list))
                launch = json.loads(descriptor.read_text())
                self.assertIn('-novoip', launch['argv'])
                self.assertIn('JDK_JAVA_OPTIONS=', launch['argv'])
                agent = next(arg for arg in launch['argv'] if arg.startswith('-javaagent:'))
                self.assertIn('config_dir=' + str(args.profile.resolve()/'zombie-buddy'), agent)
                self.assertIn('policy=deny-new', agent)
                self.assertIn('voiceEnable=false', (args.profile/'options.ini').read_text())
                approvals = json.loads((args.profile/'zombie-buddy/mod_approvals.json').read_text())
                self.assertEqual([entry['id'] for entry in approvals['mods']], ['PZToolkitJavaPatches'])
                self.assertEqual(len(approvals['mods'][0]['jar_hash']), 64)
                with self.assertRaisesRegex(ValueError, 'nonexistent'):
                    prepare.prepare(args)
                self.assertEqual(len(run.call_args_list), 2)

    def test_clip_reports_and_metadata(self):
        text = '[VIDEO_TEST] VOICE_DISABLED\n[VIDEO_TEST] RESTART\n'
        for name in ('first capture.mp4', 'second.mp4'):
            text += '[VIDEO_TEST] STOP wallMs=3515\n'
            text += f'[VIDEO_TEST] RESULT state=completed file=/test/videos/{name} frames=106 seconds=3.533333333333333 captured=106 dropped=0 width=63 height=47 error=\n'
        records = verify.parse_results(text)
        self.assertEqual(records[0]['file'], '/test/videos/first capture.mp4')
        video = dict(codec_type='video', codec_name='h264', width=64, height=48, r_frame_rate='30/1',
                     avg_frame_rate='30/1', nb_read_frames='106', duration='3.533333')
        verify.validate_metadata(records[0], {'streams': [video]})
        for change in ({'nb_read_frames': '105'}, {'duration': '3.7'}, {'width': 63}, {'avg_frame_rate': '24/1'}):
            modified = copy.deepcopy(video)
            modified.update(change)
            with self.assertRaises(ValueError):
                verify.validate_metadata(records[0], {'streams': [modified]})
        with self.assertRaisesRegex(ValueError, 'no audio'):
            verify.validate_metadata(records[0], {'streams': [video, {'codec_type': 'audio'}]})
        with self.assertRaisesRegex(ValueError, 'VOIP'):
            verify.parse_results(text.replace('VOICE_DISABLED', 'VOICE_UNKNOWN'))
        with self.assertRaisesRegex(ValueError, 'reused'):
            verify.parse_results(text.replace('second.mp4', 'first capture.mp4'))
        with self.assertRaisesRegex(ValueError, 'failed'):
            verify.parse_results(text.replace('state=completed', 'state=failed', 1))


if __name__ == '__main__':
    unittest.main()
