"""Input checks plus opt-in installed-Kahlua source regression tests.

Set PZ_GAME (the installed Java directory) and PZ_JDK (a JDK 25 root) to run
the real compiler tests. These tests never launch a game or execute source Lua.
"""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools.lua_compatibility import check_sources, LuaCompatibilityError


class LuaCompatibilityInputTests(unittest.TestCase):
    def test_sources_require_explicit_nonempty_file_collection(self):
        for sources in (None, [], 'module.lua', Path('module.lua'), [None], [123]):
            with self.subTest(sources=sources), self.assertRaises(ValueError):
                check_sources(sources, game=None, jdk=None)

    def test_missing_directory_and_non_lua_sources_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            other = root / 'source.txt'
            other.write_text('return true', encoding='utf-8')
            for source in (root / 'missing.lua', root, other):
                with self.subTest(source=source), self.assertRaises(ValueError):
                    check_sources([source], game=None, jdk=None)

    def test_requires_real_game_and_compiler(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source.lua'
            source.write_text('return true', encoding='utf-8')
            for game, jdk in ((None, None), (root, root)):
                with self.subTest(game=game), self.assertRaises(ValueError):
                    check_sources([source], game=game, jdk=jdk)

    @unittest.skipIf(os.name == 'nt', 'Windows does not permit newlines in file names')
    def test_manifest_paths_cannot_contain_newlines(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'line\nbreak.lua'
            source.write_text('return true', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'must not contain newlines'):
                check_sources([source], game=None, jdk=None)


@unittest.skipUnless(os.environ.get('PZ_GAME') and os.environ.get('PZ_JDK'),
                     'PZ_GAME/PZ_JDK required for installed Kahlua source checks')
class InstalledKahluaCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='pz-source-check-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.game = Path(os.environ['PZ_GAME'])
        self.jdk = Path(os.environ['PZ_JDK'])

    def source(self, name, text):
        path = self.root / name
        path.write_text(text, encoding='utf-8')
        return path

    def check(self, sources, **kwargs):
        return check_sources(sources, game=self.game, jdk=self.jdk, **kwargs)

    def test_missing_next_nested_read_has_precise_source_and_line(self):
        source = self.source('missing.lua', '-- next is not implemented\nreturn function()\n return next({})\nend\n')
        output = self.root / 'compatibility.json'
        with self.assertRaises(LuaCompatibilityError) as caught:
            self.check([source], output=output)
        report = caught.exception.report
        self.assertEqual(report, json.loads(output.read_text(encoding='utf-8')))
        diagnostic, = report['sources'][0]['diagnostics']
        self.assertEqual(diagnostic['global'], 'next')
        self.assertEqual(diagnostic['line'], 3)
        self.assertEqual(diagnostic['function'], 'chunk/1')
        self.assertIn(str(source.resolve()) + ':3', str(caught.exception))
        self.assertIn('next', report['missing_standard_globals'])

    def test_local_comments_strings_and_arbitrary_game_globals_are_accepted(self):
        source = self.source('legal.lua', '''
-- next({})
local text = "next({})"
local next = function(value) return value end
local object = {next = function() end}
return function()
    object.next()
    GameProvidedSymbol(text)
    return next(text)
end
''')
        report = self.check([source, source])
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(len(report['sources']), 1)
        row = report['sources'][0]
        self.assertEqual(row['diagnostics'], [])
        self.assertEqual(row['sha256'], hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertGreater(len(row['functions']), 1)

    def test_sources_are_not_executed_and_game_require_is_discovered(self):
        source = self.source('never-run.lua', 'error("must not execute")\nrequire("missing/project/module")\nreturn loadstring("invalid Lua @@@")\n')
        report = self.check([source])
        self.assertEqual(report['status'], 'passed')
        self.assertIn('require', report['game_supplied_standard_globals'])
        self.assertIn('loadstring', report['present_standard_globals'])
        self.assertEqual(len(report['runtime']['stdlib_sha256']), 64)

    def test_native_compiler_rejects_61_upvalues_but_accepts_60(self):
        def closure(count):
            names = [f'value{i}' for i in range(count)]
            return ('\n'.join(f'local {name} = {i}' for i, name in enumerate(names))
                    + '\nreturn function()\n return ' + ' + '.join(names) + '\nend\n')
        legal = self.source('legal-closure.lua', closure(60))
        illegal = self.source('too-many-upvalues.lua', closure(61))
        with self.assertRaises(LuaCompatibilityError) as caught:
            self.check([legal, illegal])
        passed, failed = caught.exception.report['sources']
        self.assertEqual(passed['status'], 'passed')
        self.assertEqual(max(row['upvalues'] for row in passed['functions']), 60)
        diagnostic, = failed['diagnostics']
        self.assertEqual(diagnostic['kind'], 'compile_error')
        self.assertIn('upvalue', diagnostic['message'].lower())
        self.assertGreater(diagnostic['line'], 0)

    def test_native_compiler_rejects_syntax_and_writes_failure_report(self):
        source = self.source('syntax.lua', 'local function broken(\nend\n')
        with self.assertRaises(LuaCompatibilityError) as caught:
            self.check([source])
        self.assertEqual(caught.exception.report['sources'][0]['diagnostics'][0]['kind'], 'compile_error')

    def test_report_cannot_overwrite_source(self):
        source = self.source('safe.lua', 'return true\n')
        with self.assertRaisesRegex(ValueError, 'must not overwrite'):
            self.check([source], output=source)
        self.assertEqual(source.read_text(), 'return true\n')

    def test_sources_use_manifest_and_inherited_java_instrumentation_is_removed(self):
        from tools import lua_compatibility
        real_run = lua_compatibility.subprocess.run
        sources = [self.source('a space.lua', 'return true'), self.source('unicode-Я.lua', 'return true')]
        commands = []

        def run(command, **kwargs):
            for key in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS'):
                self.assertNotIn(key, kwargs['env'])
            commands.append(command)
            if 'KahluaCompatibilityChecks' in command:
                self.assertEqual(len(command), 7)
                manifest = Path(command[-1])
                self.assertEqual(manifest.read_text(encoding='utf-8').splitlines(),
                                 [str(source.resolve()) for source in sources])
                self.assertNotIn(str(sources[0]), command)
            return real_run(command, **kwargs)

        with mock.patch.dict(os.environ, {'JAVA_TOOL_OPTIONS': '-invalid-test-option',
                                         'JDK_JAVA_OPTIONS': '-invalid-test-option',
                                         '_JAVA_OPTIONS': '-invalid-test-option'}), \
                mock.patch.object(lua_compatibility.subprocess, 'run', side_effect=run):
            self.assertEqual(self.check(sources)['status'], 'passed')
        self.assertEqual(len(commands), 2)


if __name__ == '__main__':
    unittest.main()
