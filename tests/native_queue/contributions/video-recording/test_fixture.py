"""No game processes: catch misleading clip reports and metadata."""
import copy
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE/(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


verify = load('verify')


class FixtureChecks(unittest.TestCase):
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

    def test_mp4_duration_quantization_preserves_exact_frames_and_interval(self):
        record = dict(frames=320, seconds=320/30, captured=206, dropped=5,
                      width=1728, height=990, elapsed_ms=10667)
        video = dict(codec_type='video', codec_name='h264', width=1728, height=990,
                     r_frame_rate='30/1', avg_frame_rate='30/1', nb_read_frames='320', duration='10.666016')
        verify.validate_metadata(record, {'streams': [video]})
        for change in ({'duration': '10.633333'}, {'duration': '10.668'}, {'nb_read_frames': '319'}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                verify.validate_metadata(record, {'streams': [dict(video, **change)]})
        for change in ({'seconds': 319/30}, {'elapsed_ms': 11000}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                verify.validate_metadata(dict(record, **change), {'streams': [video]})


if __name__ == '__main__':
    unittest.main()
