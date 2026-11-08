"""Exercise source coverage and its exit gate through real isolated Lua states."""
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import re
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch

from lupa.lua51 import LuaRuntime

from tools import mod_integrations, run_tests


class LuaCoverageTests(unittest.TestCase):
    name = 'test_coverage_fixture.lua'

    def setUp(self):
        temporary = self.enterContext(tempfile.TemporaryDirectory())
        self.root = Path(temporary)
        (self.root / 'tests').mkdir()
        self.sources = self.root / 'upstream'
        self.sources.mkdir()
        (self.sources / 'source.lua').write_text('return {fixture = true}\n', encoding='utf-8')
        self.report = self.root / 'report.json'
        self.registry = {
            'FixtureIntegration': {
                'owners': ['fixture.lua'],
                'option': 'cleanui_inventory_pane',
                'root': '.',
                'tests': {self.name: (mod_integrations.Source('FixtureSource', 'source.lua'),)},
            },
        }
        self.enterContext(patch.object(run_tests, 'ROOT', self.root))
        self.enterContext(patch.object(run_tests, 'NATIVE_TAG_TESTS', ()))
        self.enterContext(patch.object(run_tests, 'SOURCE_CHECKS', {self.name: ('upstream',)}, create=True))
        self.enterContext(patch.object(mod_integrations, 'INTEGRATIONS', self.registry))

    def write_lua(self, source):
        (self.root / 'tests' / self.name).write_text(source, encoding='utf-8')

    def invoke(self, *arguments, selected=True):
        options = ['--keep-going', '--report', str(self.report)]
        if selected:
            options += ['--test', self.name]
        options += list(map(str, arguments))
        output, errors = io.StringIO(), io.StringIO()
        code = 0
        with patch.object(sys, 'argv', ['run_tests.py', *options]), \
                redirect_stdout(output), redirect_stderr(errors):
            try:
                run_tests.main()
            except SystemExit as error:
                code = error.code
        report = json.loads(self.report.read_text(encoding='utf-8')) if self.report.exists() else None
        return code, report, output.getvalue() + errors.getvalue()

    def with_sources(self):
        return ('--cleanui-inventory-pane', self.sources)

    def test_absent_sources_are_partial_without_a_printed_skip(self):
        self.write_lua("if FixtureSource then TestCoverage('upstream', 'passed') end")
        code, report, output = self.invoke()
        self.assertEqual(0, code)
        self.assertEqual('partial', report['status'])
        result = report['results'][0]
        self.assertEqual('partial', result['status'])
        self.assertEqual('missing', result['source_inputs'][0]['status'])
        self.assertTrue(result['source_inputs'][0]['required'])
        self.assertEqual('not-run', result['checks'][0]['status'])
        self.assertIn('PARTIAL', output)

    def test_required_source_omission_remains_partial_after_completion_callback(self):
        self.write_lua("TestCoverage('upstream', 'passed')")
        code, report, _ = self.invoke()
        self.assertEqual(0, code)
        self.assertEqual('partial', report['results'][0]['status'])
        self.assertEqual('passed', report['results'][0]['checks'][0]['status'])
        self.assertEqual('missing', report['results'][0]['source_inputs'][0]['status'])

    def test_bound_input_and_completed_checks_pass_strict_gate(self):
        self.write_lua("assert(FixtureSource:find('fixture', 1, true)); TestCoverage('upstream', 'passed')")
        code, report, _ = self.invoke(*self.with_sources(), '--require-complete')
        self.assertEqual(0, code)
        self.assertEqual('passed', report['status'])
        result = report['results'][0]
        self.assertEqual('passed', result['status'])
        source = result['source_inputs'][0]
        self.assertEqual('FixtureIntegration', source['integration'])
        self.assertEqual('FixtureSource', source['variable'])
        self.assertEqual('bound', source['status'])
        self.assertTrue(source['required'])
        self.assertEqual('passed', result['checks'][0]['status'])

    def test_input_presence_without_callback_is_partial(self):
        self.write_lua("assert(FixtureSource)")
        code, report, _ = self.invoke(*self.with_sources(), '--require-complete')
        self.assertNotEqual(0, code)
        self.assertEqual('partial', report['results'][0]['status'])
        self.assertEqual('bound', report['results'][0]['source_inputs'][0]['status'])
        self.assertEqual('not-run', report['results'][0]['checks'][0]['status'])

    def test_each_declared_check_requires_its_own_completion(self):
        self.write_lua("TestCoverage('upstream', 'passed')")
        with patch.object(run_tests, 'SOURCE_CHECKS', {self.name: ('upstream', 'second-path')}):
            code, report, _ = self.invoke(*self.with_sources(), '--require-complete')
        self.assertNotEqual(0, code)
        result = report['results'][0]
        self.assertEqual('partial', result['status'])
        self.assertEqual(['passed', 'not-run'], [check['status'] for check in result['checks']])

    def test_structured_skip_survives_a_test_replacing_print(self):
        self.write_lua("print = function() end; TestCoverage('upstream', 'skipped', 'fixture dependency unavailable')")
        code, report, _ = self.invoke(*self.with_sources(), '--require-complete')
        self.assertNotEqual(0, code)
        result = report['results'][0]
        self.assertEqual('partial', result['status'])
        self.assertEqual('skipped', result['checks'][0]['status'])
        self.assertEqual('fixture dependency unavailable', result['checks'][0]['reason'])

    def test_log_text_cannot_supply_a_missing_completion(self):
        self.registry.clear()
        for message in ('PASS all checks', 'SKIP optional dependency', 'source checks skipped.'):
            with self.subTest(message=message):
                self.write_lua('print(' + json.dumps(message) + ')')
                code, report, _ = self.invoke('--require-complete')
                self.assertNotEqual(0, code)
                self.assertEqual('partial', report['results'][0]['status'])
                self.assertEqual('not-run', report['results'][0]['checks'][0]['status'])

    def test_omitted_completion_is_partial_without_strict_gate(self):
        self.registry.clear()
        self.write_lua("print('PASS only the fixture model')")
        code, report, output = self.invoke()
        self.assertEqual(0, code)
        self.assertEqual('partial', report['status'])
        self.assertIn('PARTIAL', output)

    def test_skip_text_in_an_ordinary_log_is_not_a_coverage_event(self):
        self.registry.clear()
        self.write_lua("TestCoverage('upstream','passed'); print('SKIP is ordinary log text here')")
        code, report, _ = self.invoke('--require-complete')
        self.assertEqual(0, code)
        self.assertEqual('passed', report['status'])

    def test_assertion_failure_cannot_be_downgraded_to_partial(self):
        self.write_lua("TestCoverage('upstream', 'skipped', 'optional fixture'); assert(false, 'broken contract')")
        code, report, _ = self.invoke(*self.with_sources())
        self.assertNotEqual(0, code)
        self.assertEqual('failed', report['status'])
        self.assertEqual('failed', report['results'][0]['status'])
        self.assertIn('broken contract', report['results'][0]['error'])

    def test_missing_lua_dependency_is_a_failure(self):
        self.write_lua("require('coverage_fixture_dependency_that_does_not_exist')")
        code, report, _ = self.invoke(*self.with_sources())
        self.assertNotEqual(0, code)
        self.assertEqual('failed', report['results'][0]['status'])
        self.assertIn('coverage_fixture_dependency_that_does_not_exist', report['results'][0]['error'])

    def test_invalid_and_duplicate_completions_fail(self):
        invalid_sources = (
            "TestCoverage('unknown', 'passed')",
            "TestCoverage('upstream', 'failed')",
            "TestCoverage('upstream', 'skipped')",
            "TestCoverage('upstream', 'passed'); TestCoverage('upstream', 'passed')",
        )
        for source in invalid_sources:
            with self.subTest(source=source):
                self.write_lua(source)
                code, report, _ = self.invoke(*self.with_sources())
                self.assertNotEqual(0, code)
                self.assertEqual('failed', report['results'][0]['status'])
                self.assertTrue(report['results'][0]['error'])

    def test_lua_pcall_cannot_swallow_invalid_completion(self):
        invalid_sources = (
            "pcall(TestCoverage, 'unknown', 'passed'); TestCoverage('upstream', 'passed')",
            "TestCoverage('upstream', 'passed'); pcall(TestCoverage, 'upstream', 'passed')",
        )
        for source in invalid_sources:
            with self.subTest(source=source):
                self.write_lua(source)
                code, report, _ = self.invoke(*self.with_sources())
                self.assertNotEqual(0, code)
                self.assertEqual('failed', report['results'][0]['status'])
                self.assertIn('coverage receipt', report['results'][0]['error'])

    def test_missing_required_strict_source_rejects_before_lua_runs(self):
        self.write_lua("error('must not run without required input')")
        with patch.object(run_tests, '_run_variant', wraps=run_tests._run_variant) as variant:
            code, _, _ = self.invoke('--require-complete')
        self.assertNotEqual(0, code)
        variant.assert_not_called()

    def test_explicit_missing_source_file_is_a_failure(self):
        (self.sources / 'source.lua').unlink()
        self.write_lua("TestCoverage('upstream', 'passed')")
        code, report, _ = self.invoke(*self.with_sources())
        self.assertNotEqual(0, code)
        self.assertEqual('failed', report['results'][0]['status'])

    def test_strict_missing_file_prevents_even_an_earlier_ready_test_from_running(self):
        (self.sources / 'source.lua').unlink()
        (self.root / 'tests/test_aaa_ready.lua').write_text("error('earlier test must not run')")
        self.write_lua("error('source-backed test must not run')")
        with patch.object(run_tests, '_run_variant', wraps=run_tests._run_variant) as variant:
            code, _, output = self.invoke(*self.with_sources(), '--require-complete',
                                          '--test', 'test_aaa_ready')
        self.assertEqual(2, code)
        self.assertIn('source preparation failed', output)
        variant.assert_not_called()

    def test_integration_and_pack_lock_automatically_require_completion(self):
        self.write_lua("assert(FixtureSource)")
        with patch.object(mod_integrations, 'configure'):
            for option in (('--integration', 'FixtureIntegration'), ('--pack-lock', 'fixture-lock.json')):
                with self.subTest(option=option):
                    code, report, _ = self.invoke(*self.with_sources(), *option)
                    self.assertNotEqual(0, code)
                    self.assertEqual('partial', report['results'][0]['status'])

    def test_automatic_strict_mode_rejects_missing_inputs_before_lua(self):
        self.write_lua("error('must not run')")
        with patch.object(mod_integrations, 'configure'), \
                patch.object(run_tests, '_run_variant', wraps=run_tests._run_variant) as variant:
            for option in (('--integration', 'FixtureIntegration'), ('--pack-lock', 'fixture-lock.json')):
                with self.subTest(option=option):
                    code, _, _ = self.invoke(*option)
                    self.assertNotEqual(0, code)
            variant.assert_not_called()

    def test_skipped_default_selection_fails_only_under_strict_gate(self):
        self.registry.clear()
        self.write_lua("error('default native-only check should not execute')")
        with patch.object(run_tests, 'DEFAULT_NATIVE_ONLY', {self.name}), \
                patch.object(run_tests, 'SOURCE_CHECKS', {}):
            for arguments, expected in (((), 0), (('--require-complete',), 1)):
                with self.subTest(arguments=arguments):
                    code, report, _ = self.invoke(*arguments, selected=False)
                    self.assertEqual(expected, code)
                    self.assertEqual('partial', report['status'])
                    self.assertEqual('skipped', report['results'][0]['status'])

    def test_binding_reports_optional_locked_absence_without_requiring_it(self):
        sources = self.registry['FixtureIntegration']['tests']
        sources[self.name] += (mod_integrations.Source('OptionalFixtureSource', 'optional.lua', optional=True),)
        args = SimpleNamespace(cleanui_inventory_pane=None, integration_sources={
            self.name: {'FixtureSource': self.sources / 'source.lua', 'OptionalFixtureSource': None},
        })
        lua = LuaRuntime(unpack_returned_tuples=True)
        bound = mod_integrations.bind_sources(lua, self.name, args)
        self.assertEqual('return {fixture = true}\n', lua.globals().FixtureSource)
        self.assertIsNone(lua.globals().OptionalFixtureSource)
        by_variable = {source['variable']: source for source in bound}
        self.assertEqual('bound', by_variable['FixtureSource']['status'])
        self.assertEqual('not-applicable', by_variable['OptionalFixtureSource']['status'])
        self.assertFalse(by_variable['OptionalFixtureSource']['required'])

    def test_absent_optional_input_does_not_make_completed_checks_partial(self):
        self.registry['FixtureIntegration']['tests'][self.name] += (
            mod_integrations.Source('OptionalFixtureSource', 'optional.lua', optional=True),
        )
        self.write_lua("assert(FixtureSource); assert(OptionalFixtureSource == nil); TestCoverage('upstream', 'passed')")
        code, report, _ = self.invoke(*self.with_sources(), '--require-complete')
        self.assertEqual(0, code)
        self.assertEqual('passed', report['status'])
        self.assertEqual(['bound', 'not-applicable'],
                         [source['status'] for source in report['results'][0]['source_inputs']])


class CoverageConsumerTests(unittest.TestCase):
    """The migrated scripts must keep declarations, receipts and syntax aligned."""

    def receipt_outcomes(self, name, source):
        receipt = re.compile(r'''TestCoverage\(\s*(?:(['"])([^'"]*)\1|(\w+))\s*,\s*(['"])([^'"]*)\4(?=\s*[,\)])''')
        matches = list(receipt.finditer(source))
        self.assertEqual(len(matches), len(re.findall(r'\bTestCoverage\s*\(', source)),
                         'Every receipt needs a supported ID producer and a literal state')
        outcomes, dynamic = {}, []
        for match in matches:
            if match[2] is not None:
                outcomes.setdefault(match[2], set()).add(match[5])
            else:
                dynamic.append((match[3], match[5]))
        if dynamic:
            # The composition bank has a finite skipped list and one passed
            # receipt inside a literal mode loop. Resolve those actual producers
            # rather than requiring duplicate literal receipts in the Lua test.
            self.assertEqual(name, 'test_action_queue_borrowing_composition.lua')
            self.assertEqual(dynamic, [('id', 'skipped'), ('mode', 'passed')])
            lua = LuaRuntime(unpack_returned_tuples=True)
            # Only ipairs and the receipt sink are available. A missing early
            # return cannot read files, load project code or fake bound inputs.
            execute = lua.eval('''function(source)
                local receipts={}
                local function sink(id,state,reason)
                    receipts[#receipts+1]={id=id,state=state,reason=reason}
                end
                local body=assert(loadstring(source))
                setfenv(body,{ipairs=ipairs,TestCoverage=sink})
                body()
                return receipts
            end''')
            receipts = execute(source)
            skipped = [(receipts[i]['id'], receipts[i]['state'], receipts[i]['reason'])
                       for i in range(1, len(receipts) + 1)]
            self.assertEqual(len(skipped), len({row[0] for row in skipped}))
            for identifier, state, reason in skipped:
                self.assertEqual(state, 'skipped')
                self.assertTrue(isinstance(reason, str) and reason.strip())
                outcomes.setdefault(identifier, set()).add(state)
            loops = re.finditer(r"(?ms)^for _,mode in ipairs\((\{[^}\n]+\})\)do\n(.*?)^end\b", source)
            passed = [match for match in loops if re.search(r"TestCoverage\(\s*mode\s*,\s*['\"]passed['\"]\)", match[2])]
            self.assertEqual(len(passed), 1, 'Dynamic pass receipt needs one bounded literal mode loop')
            literal = passed[0][1]
            ids = re.findall(r'''(['"])([\w-]+)\1''', literal)
            remainder = re.sub(r'''(['"])[\w-]+\1''', '', literal)
            self.assertRegex(remainder, r'^\{[\s,]*\}$', 'Mode enumeration must contain only literal receipt IDs')
            self.assertTrue(0 < len(ids) <= 32)
            self.assertEqual(len(ids), len({identifier for _, identifier in ids}))
            for _, identifier in ids:
                outcomes.setdefault(identifier, set()).add('passed')
        return outcomes

    def assert_receipts(self, name, source, expected):
        outcomes = self.receipt_outcomes(name, source)
        self.assertEqual(set(expected), set(outcomes))
        for values in outcomes.values():
            self.assertIn('passed', values)
            self.assertLessEqual(values, {'passed', 'skipped'})
            if name not in run_tests.REQUIRED_INPUTS:
                self.assertIn('skipped', values)

    def test_declared_source_checks_compile_and_have_required_outcomes(self):
        root = Path(__file__).resolve().parents[1]
        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_source = lua.eval('function(source) local f,err=loadstring(source); return f~=nil,err end')
        for name, expected in run_tests.SOURCE_CHECKS.items():
            with self.subTest(test=name):
                source = (root / 'tests' / name).read_text()
                ok, error = compile_source(source)
                self.assertTrue(ok, error)
                if name == 'test_inventory_refresh.lua':
                    # This fixture uses sourceCheck/completed helpers; its seven
                    # paths also have direct source-backed execution coverage.
                    continue
                self.assert_receipts(name, source, expected)

    def test_dynamic_receipt_ids_and_states_are_checked_without_source_inputs(self):
        root = Path(__file__).resolve().parents[1]
        name = 'test_action_queue_borrowing_composition.lua'
        source = (root / 'tests' / name).read_text()
        expected = set(run_tests.SOURCE_CHECKS[name])
        self.assertEqual(set(self.receipt_outcomes(name, source)), expected)
        changed_modes = source.replace("ipairs({'plain','singleton-guarded','merge-preserving'})", "ipairs({'unknown','singleton-guarded','merge-preserving'})", 1)
        self.assertNotEqual(set(self.receipt_outcomes(name, changed_modes)), expected)
        for changed in (source.replace("TestCoverage(mode,'passed')", "TestCoverage(mode,'failed')"),
                        source.replace("TestCoverage(id,'skipped'", "TestCoverage(id,'passed'")):
            with self.assertRaises(AssertionError):
                self.receipt_outcomes(name, changed)

    def test_mandatory_input_tests_need_pass_receipts_without_fake_skips(self):
        name = 'required.lua'
        passed = "TestCoverage('actual','passed')"
        with patch.dict(run_tests.REQUIRED_INPUTS, {name: ('native_action_root', '--game')}):
            self.assert_receipts(name, passed, ('actual',))
            for invalid in ("TestCoverage('actual','skipped','unavailable')",
                            passed + "; TestCoverage('actual','failed')",
                            passed + "; TestCoverage('actual','unexpected state')",
                            passed + "; TestCoverage('unknown','passed')",
                            passed + "; TestCoverage('actual',state)"):
                with self.subTest(invalid=invalid), self.assertRaises(AssertionError):
                    self.assert_receipts(name, invalid, ('actual',))
        with self.assertRaises(AssertionError):
            self.assert_receipts(name, passed, ('actual',))

    def test_runnable_lua_checks_do_not_report_coverage_by_printing_skip(self):
        root = Path(__file__).resolve().parents[1]
        prints = re.compile(r'''\bprint\(\s*(['"])(.*?)\1\s*\)''')
        old_skip = re.compile(r'(?<![A-Za-z0-9_])SKIP(?:PED)?(?![A-Za-z0-9_])|\b(?:checks?|tests?|contracts?) skipped\b')
        for name in run_tests.discover_tests(root):
            with self.subTest(test=name):
                source = (root / 'tests' / name).read_text()
                self.assertFalse([match[2] for match in prints.finditer(source) if old_skip.search(match[2])],
                                 'Declare a structured source check and emit TestCoverage receipts instead.')


if __name__ == '__main__':
    unittest.main()
