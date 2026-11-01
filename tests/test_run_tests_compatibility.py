"""The runtime-source gate must not treat offline helpers as game Lua."""
from contextlib import redirect_stderr, redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools import run_tests


class LuaRunnerCompatibilityTests(unittest.TestCase):
    def invoke(self, arguments):
        with patch.object(sys, 'argv', ['run_tests.py', *map(str, arguments)]), \
                redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            run_tests.main()

    def test_runtime_only_check_does_not_discover_or_run_offline_helpers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = root / 'runtime'
            (runtime / 'shared').mkdir(parents=True)
            source = runtime / 'shared/owner.lua'
            source.write_text('return {}\n')
            (root / 'harness.lua').write_text('assert(next({value=true}))\n')
            report = root / 'compatibility.json'
            with patch.object(run_tests.lua_compatibility, 'check_sources', return_value={'sources': [str(source)]}) as check, \
                    patch.object(run_tests, '_run_variant') as behavioral:
                self.invoke(['--check-lua', runtime, '--game', root / 'game', '--jdk', root / 'jdk', '--lua-report', report])
            self.assertEqual([source], check.call_args.args[0])
            self.assertEqual(report, check.call_args.kwargs['output'])
            behavioral.assert_not_called()

    def test_incompatible_runtime_stops_before_selected_behavioral_test(self):
        with patch.object(run_tests, 'discover_tests', return_value=['harness.lua']), \
                patch.object(run_tests.lua_compatibility, 'check_sources', side_effect=ValueError('owner.lua:7: absent next')), \
                patch.object(run_tests, '_run_variant') as behavioral:
            with self.assertRaises(SystemExit) as result:
                self.invoke(['--check-lua', 'owner.lua', '--game', 'game', '--jdk', 'jdk', '--test', 'harness'])
            self.assertEqual(2, result.exception.code)
            behavioral.assert_not_called()

    def test_explicit_behavioral_tests_run_after_successful_source_gate(self):
        order = []
        def check(*args, **kwargs):
            order.append('compatibility')
            return {'sources': ['owner.lua']}
        def run(*args):
            order.append('behavioral')
            return {'status': 'passed'}
        with patch.object(run_tests, 'discover_tests', return_value=['harness.lua']), \
                patch.object(run_tests.lua_compatibility, 'check_sources', side_effect=check), \
                patch.object(run_tests, 'configure_game_sources'), \
                patch.object(run_tests, '_run_variant', side_effect=run):
            self.invoke(['--check-lua', 'owner.lua', '--game', 'game', '--jdk', 'jdk', '--test', 'harness'])
        self.assertEqual(['compatibility', 'behavioral'], order)

    def test_missing_inputs_and_empty_source_directory_fail_without_checker(self):
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(run_tests.lua_compatibility, 'check_sources') as check:
            for arguments in (['--check-lua', temporary], ['--lua-report', 'report.json'],
                              ['--check-lua', temporary, '--game', 'game', '--jdk', 'jdk']):
                with self.subTest(arguments=arguments), self.assertRaises(SystemExit):
                    self.invoke(arguments)
            check.assert_not_called()


if __name__ == '__main__':
    unittest.main()
