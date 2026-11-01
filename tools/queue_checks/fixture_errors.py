"""Detect confirmed failures of selected Lua files during native loading.

Kahlua logs even errors later caught by Lua pcall. Only LuaManager's outer
failed protectedCall diagnostics (or its compile-failure diagnostic) prove a
load failure. A complete subsequent record must close the JUL message cluster.
"""
from collections import defaultdict
from pathlib import Path
import posixpath
import re
import sys

from . import coop
from .mod_selection import lua_sources
from .native import runtime_lua_sources
from .report import RECORD, STAMP, read_json


# SimpleFormatter localizes timestamps and level names, but keeps source class
# and method names. Never mistake a DebugLog/Lua payload for a JUL header.
JUL_STAMP = r'[^>\r\n]*\d[^>\r\n]*?'
LOAD_HEADER = re.compile(r'^' + JUL_STAMP + r' zombie\.Lua\.LuaManager RunLuaInternal\s*$')
JUL_HEADER = re.compile(r'^' + JUL_STAMP + r' (?:[\w$]+\.)+[\w$]+ [\w$<>]+\s*$')
LEVEL = re.compile(r'^[^\W\d_][\w -]*:\s*(.*)$')
COMPILE = 'Error found in LUA file: '
FRAME = re.compile(r'^\s*at\s+(.+?\.lua):(\d+)\s*$')


def _payload(line):
    if JUL_HEADER.fullmatch(line) or FRAME.match(line):
        return None
    match = LEVEL.match(line)
    return match[1] if match else None


def _path(value):
    value = posixpath.normpath(str(value).replace('\\', '/'))
    return value.casefold() if sys.platform == 'win32' else value


class FixtureLoadMonitor:
    def __init__(self, root, runtime, selection):
        self.root = Path(root).resolve()
        self.catalogs = {}
        game_names = set()
        game_seal = self.root / 'game-inputs.json'
        if game_seal.is_file():
            trees = read_json(game_seal).get('trees', {})
            game_names.update(Path(name).name.casefold() for name in trees.get('media/lua', {}))
        for role, config in runtime['roles'].items():
            if role == 'server' and coop.enabled(selection):
                config = runtime['roles']['client1']
            cache = Path(config['cache'])
            fixture_runtime = {'roles': {role: config}, 'fixture': runtime.get('fixture', {})}
            selected = runtime_lua_sources(fixture_runtime, selection, fixtures_only=True)
            allowed = {}
            for path in selected:
                canonical = path.resolve()
                canonical.relative_to(self.root)
                allowed[_path(path)] = allowed[_path(canonical)] = canonical
            names = defaultdict(set)
            mods = cache / 'mods'
            for mod in mods.iterdir() if mods.is_dir() else ():
                if mod.is_dir():
                    for path in lua_sources(mod):
                        names[path.name.casefold()].add(_path(path.resolve()))
            aliases = {}
            for path in selected:
                name = path.name.casefold()
                if name not in game_names and names[name] == {_path(path.resolve())}:
                    aliases[name] = path.resolve()
            self.catalogs[role] = (allowed, aliases)

    def _finding(self, role, lines, number):
        allowed, aliases = self.catalogs[role]
        source, kind = None, None
        for line in lines:
            payload = _payload(line)
            if payload is not None and payload.startswith(COMPILE):
                source = allowed.get(_path(payload[len(COMPILE):].strip()))
                kind = 'compile'
                break
        if kind is None:
            if not any(_payload(line) is not None for line in lines):
                return None
            # failed protectedCall logs error text, optional Java exception,
            # then its Lua stack in separate JUL records. Attribute only the
            # final record, never a filename embedded in earlier error text.
            last_header = max(index for index, line in enumerate(lines) if LOAD_HEADER.fullmatch(line))
            for line in lines[last_header + 1:]:
                frame = FRAME.match(line) or FRAME.match(_payload(line) or '')
                if frame:
                    # The first Lua source owns the failure. Do not attribute a
                    # foreign callee's exception to a later fixture caller.
                    name = frame[1].replace('\\', '/')
                    source = allowed.get(_path(name)) if '/' in name else aliases.get(name.casefold())
                    kind = 'runtime'
                    break
        if source is None:
            return None
        block = '\n'.join(lines)
        return {'role': role, 'file': source.relative_to(self.root).as_posix(),
                'line': number, 'kind': kind,
                'message': next(line for line in lines if _payload(line) is not None),
                'block': block}

    def find(self, role, text):
        if role not in self.catalogs:
            return None
        # Do not classify a writer's unterminated last line or infer a completed
        # exception from EOF. Interleaved/cut blocks remain for the final audit.
        complete = text.rsplit('\n', 1)[0].splitlines() if '\n' in text else []
        cluster, start, compile_stack = [], None, False
        for number, raw in enumerate(complete, 1):
            line = STAMP.sub('', raw)
            if not RECORD.match(line) and LOAD_HEADER.fullmatch(line):
                if start is not None:
                    last_header = max(index for index, item in enumerate(cluster) if LOAD_HEADER.fullmatch(item))
                    finished = (any((_payload(item) or '').startswith(COMPILE) for item in cluster)
                                or any(FRAME.match(item) or FRAME.match(_payload(item) or '')
                                       for item in cluster[last_header + 1:]))
                    if finished:
                        finding = self._finding(role, cluster, start)
                        if finding is not None:
                            return finding
                        cluster, start, compile_stack = [], None, False
                if start is None:
                    start = number
                cluster.append(line)
                continue
            if start is not None and (RECORD.match(line) or JUL_HEADER.fullmatch(line)):
                if (not compile_stack and any((_payload(item) or '').startswith(COMPILE) for item in cluster)
                        and re.match(r'^\s*ERROR\s*:', line)
                        and 'LuaManager.RunLuaInternal> Exception thrown' in line):
                    compile_stack = True
                    cluster.append(line)
                    continue
                finding = self._finding(role, cluster, start)
                if finding is not None:
                    return finding
                cluster, start, compile_stack = [], None, False
            if start is not None:
                cluster.append(line)
        return None

    def check(self, logs):
        return next((finding for role, text in logs.items() if (finding := self.find(role, text))), None)


def check_fixture_loading(monitor, logs, execution, phase):
    finding = monitor.check(logs)
    if finding is not None:
        execution['fixture_load_error'] = dict(finding, phase=phase)
        raise RuntimeError(f"Fixture Lua {finding['kind']} failed during {phase}: "
                           f"{finding['role']} {finding['file']} (log line {finding['line']})")
