"""Keep unsupported Lua globals out of shipped sources (Java methods are allowed)."""
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
# Skip Lua comments and strings before inspecting identifiers and punctuation.
TOKENS = re.compile(
    r'(?P<ignored>--\[(?P<comment_eq>=*)\[.*?\](?P=comment_eq)\]'
    r'|--[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    r'|\[(?P<string_eq>=*)\[.*?\](?P=string_eq)\])'
    r'|(?P<token>[A-Za-z_]\w*|[^\s])', re.DOTALL,
)


def global_next_calls(source):
    tokens = [match for match in TOKENS.finditer(source) if match.group('token')]
    for index, match in enumerate(tokens[:-1]):
        if (match.group() == 'next' and tokens[index + 1].group() == '('
                and (index == 0 or tokens[index - 1].group() not in ('.', ':'))):
            yield source.count('\n', 0, match.start()) + 1


class KahluaGlobalsTests(unittest.TestCase):
    def test_detects_bare_calls_with_spacing_and_comments(self):
        self.assertEqual(list(global_next_calls('next(t)\nnext -- note\n (t)')), [1, 2])

    def test_ignores_comments_strings_and_member_calls(self):
        source = '''-- next(t)
--[=[ next(t) ]=]
local a = "next(t)"; local b = 'next(t)'
local c = [==[ next(t) ]==]
local escaped = "a\\\"next(t)"
iterator:next(); iterator : next (); object.next(t)
nextItem(t); local next = value
'''
        self.assertEqual(list(global_next_calls(source)), [])

    def test_shipped_lua_has_no_bare_next_calls(self):
        paths = sorted((ROOT / 'PZSurvivorToolkit').rglob('*.lua'))
        self.assertTrue(paths, 'shipped Lua sources must be present')
        violations = [f'{path.relative_to(ROOT)}:{line}'
                      for path in paths
                      for line in global_next_calls(path.read_text(encoding='utf-8'))]
        self.assertEqual(violations, [], 'Kahlua has no global next; use pairs or a boolean')


if __name__ == '__main__':
    unittest.main()
