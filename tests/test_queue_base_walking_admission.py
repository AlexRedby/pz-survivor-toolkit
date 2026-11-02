"""Walking timing isolation through adapter, CLI, batch and prepared-run admission."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import admission, native, runner
from queue_checks.adapters import base_walking_profile as profile

spec = importlib.util.spec_from_file_location('walking_admission_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class WalkingAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        sandbox = self.root / 'SandboxVars.lua'
        sandbox.write_text('SandboxVars={}\n')
        self.selection = dict(suite='base-walking-profile', cases=['walk'], kind='mp', mode='toolkit',
            clients=1, languages=['EN'], mods=sorted(profile.REQUIRED), resources={'exclusive': True},
            options=dict(mp_host=True, world_template=str(self.root / 'world'),
                         pack_lock=str(self.root / 'pack.json'), external_sandbox_path=str(sandbox)))

    def test_only_explicit_boolean_exclusive_is_accepted(self):
        invalid = [None, [], False, {}, {'exclusive': False}, {'exclusive': None},
                   {'exclusive': 1}, {'exclusive': 'true'}]
        selection = copy.deepcopy(self.selection)
        del selection['resources']
        with self.assertRaisesRegex(ValueError, '--exclusive'):
            profile.validate(selection)
        for resources in invalid:
            with self.subTest(resources=resources):
                selection = dict(self.selection, resources=resources)
                with self.assertRaisesRegex(ValueError, 'resources.exclusive=true'):
                    profile.validate(selection)
        for language in ('EN', 'RU'):
            selection = dict(self.selection, languages=[language])
            before = copy.deepcopy(selection)
            profile.validate(selection)
            self.assertEqual(selection, before)
            self.assertIs(admission.budget(selection)['exclusive'], True)

    def test_prepare_cli_requires_flag_and_preserves_explicit_exclusivity(self):
        config = self.root / 'options.json'
        config.write_text(json.dumps(self.selection['options']))
        command = ['prepare', str(self.root / 'run'), '--suite', 'base-walking-profile',
                   '--game', '/game', '--jdk', '/jdk', '--config', str(config),
                   '--mods', ','.join(self.selection['mods'])]
        def prepare(project, output, game, jdk, selection, workshop):
            profile.validate(selection)
        with patch.object(cli.native, 'prepare', side_effect=prepare) as prepared, \
                patch.object(cli.runner, 'run') as launched, \
                patch('sys.stdout', io.StringIO()), patch('sys.stderr', io.StringIO()) as errors:
            self.assertEqual(1, cli.main(command))
            self.assertIn('--exclusive', errors.getvalue())
            self.assertFalse((self.root / 'run').exists())
            self.assertEqual(0, cli.main(command + ['--exclusive']))
            selected = prepared.call_args.args[4]
            self.assertIs(selected['resources']['exclusive'], True)
            self.assertIs(admission.budget(selected)['exclusive'], True)
            launched.assert_not_called()

    def test_real_preparation_rejects_shared_selection_before_creating_snapshot(self):
        game, jdk = self.root / 'game', self.root / 'jdk'
        (game / 'media/lua').mkdir(parents=True)
        for path in (game / 'projectzomboid.jar', game / 'ZombieBuddy.jar',
                     game / 'jre64/bin/java.exe', native.jdk_binary(jdk, 'java'), native.jdk_binary(jdk, 'javac')):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('unused synthetic input')
            path.chmod(0o755)
        selection = dict(self.selection, schema_version=1, resources={'exclusive': False},
                         ports=[17343, 17344], timeout_seconds=60, expected_checks=3)
        output = self.root / 'rejected'
        with patch.object(native.subprocess, 'run') as compiled:
            with self.assertRaisesRegex(ValueError, '--exclusive'):
                native.prepare(ROOT, output, game, jdk, selection)
            compiled.assert_not_called()
        self.assertFalse(output.exists())

    def test_batch_requires_explicit_plan_or_job_resource_and_respects_overrides(self):
        catalog = {'suites': profile.definitions()}
        plan = dict(options=self.selection['options'], mods=self.selection['mods'])
        job = dict(id='walking', suite='base-walking-profile')
        for plan_resources, job_resources, accepted in (
                ({}, {}, False), ({'exclusive': True}, {}, True),
                ({}, {'exclusive': True}, True), ({'exclusive': True}, {'exclusive': False}, False)):
            with self.subTest(plan=plan_resources, job=job_resources):
                selected = cli.batch_selection(dict(plan, resources=plan_resources),
                    dict(job, resources=job_resources), catalog, None, {})
                if accepted:
                    profile.validate(selected)
                    self.assertIs(admission.budget(selected)['exclusive'], True)
                else:
                    with self.assertRaisesRegex(ValueError, '--exclusive'):
                        profile.validate(selected)

    def test_resume_rejects_shared_snapshot_before_live_inputs_gui_or_admission(self):
        (self.root / 'runtime.json').write_text('{}')
        selection = dict(self.selection, resources={'exclusive': False})
        (self.root / 'selection.json').write_text(json.dumps(selection))
        with patch.object(runner.sys, 'platform', 'darwin'), \
                patch.object(runner, 'verify_manifest', return_value=[]), \
                patch.object(runner, '_verify_live_inputs') as inputs, \
                patch.object(runner.desktop, 'require_gui_access') as gui, \
                patch.object(runner.admission, 'acquire') as lease, \
                patch.object(runner.subprocess, 'Popen') as process:
            with self.assertRaisesRegex(ValueError, 'fresh exclusive snapshot'):
                runner.run(self.root)
            inputs.assert_not_called()
            gui.assert_not_called()
            lease.assert_not_called()
            process.assert_not_called()


if __name__ == '__main__':
    unittest.main()
