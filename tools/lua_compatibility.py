"""Compile Lua with installed Kahlua and reject absent standard global reads.

Only the installation's stdlib.lbc is executed. Project chunks and nested
functions are compiled and inspected, never executed. This is a source preflight,
not a proof of game API availability, library-member support or runtime behavior.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / 'tests/native_queue/support/KahluaCompatibilityChecks.java'


class LuaCompatibilityError(ValueError):
    """Source incompatibility, with its full JSON-serializable report attached."""

    def __init__(self, report):
        self.report = report
        messages = []
        for source in report['sources']:
            for diagnostic in source['diagnostics']:
                messages.append(f"{source['path']}:{diagnostic['line']} "
                                f"[{diagnostic['function']}]: {diagnostic['message']}")
        super().__init__('Installed Kahlua source compatibility failed:\n' + '\n'.join(messages))


def _file(value, label, *, executable=False):
    if value is None:
        raise ValueError(f'{label} is required')
    path = Path(value).expanduser().resolve()
    if not path.is_file() or not os.access(path, os.R_OK):
        raise ValueError(f'{label} must be a readable file: {path}')
    if executable and not os.access(path, os.X_OK):
        raise ValueError(f'{label} must be executable: {path}')
    return path


def _run(command, label):
    try:
        return subprocess.run([str(part) for part in command], capture_output=True,
                              text=True, timeout=120,
                              env={key: value for key, value in os.environ.items()
                                   if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')})
    except (OSError, subprocess.TimeoutExpired) as problem:
        raise ValueError(f'{label} could not run: {problem}') from problem


def check_sources(sources, *, game, jdk, output=None):
    """Check explicit .lua files; raise ValueError on invalid setup or incompatibility.

    ``game`` contains projectzomboid.jar and stdlib.lbc; ``jdk`` contains bin/java
    and bin/javac. ``output`` optionally names a JSON report file (written on
    source incompatibility too). Compilation products are always temporary.
    """
    if isinstance(sources, (str, bytes, os.PathLike)) or sources is None:
        raise ValueError('sources must be a nonempty iterable of Lua file paths')
    try:
        paths = list(dict.fromkeys(_file(path, 'Lua source') for path in sources))
    except TypeError as problem:
        raise ValueError('sources must be a nonempty iterable of Lua file paths') from problem
    if not paths:
        raise ValueError('sources must not be empty')
    if any(path.suffix.lower() != '.lua' for path in paths):
        raise ValueError('sources must contain only .lua files')
    if any('\n' in str(path) or '\r' in str(path) for path in paths):
        raise ValueError('Lua source paths must not contain newlines')
    if game is None or jdk is None:
        raise ValueError('Installed game and JDK paths are required for Kahlua compatibility')
    game, jdk = Path(game).expanduser().resolve(), Path(jdk).expanduser().resolve()
    jar = _file(game / 'projectzomboid.jar', 'Installed Kahlua jar')
    library = _file(game / 'stdlib.lbc', 'Installed Kahlua standard library')
    suffix = '.exe' if os.name == 'nt' else ''
    javac = _file(jdk / f'bin/javac{suffix}', 'JDK compiler', executable=True)
    java = _file(jdk / f'bin/java{suffix}', 'JDK runtime', executable=True)
    harness = _file(HARNESS, 'Kahlua compatibility harness')
    if output is not None:
        output = Path(output).expanduser().resolve()
        if output in (*paths, jar, library, java, javac, harness):
            raise ValueError('Kahlua report output must not overwrite a source or runtime input')
    # Bind the report to checked bytes and detect concurrent edits during preflight.
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    with tempfile.TemporaryDirectory(prefix='pz-kahlua-compatibility-') as temporary:
        build = Path(temporary)
        compiled = _run([javac, '-cp', jar, '-d', build, harness], 'Kahlua harness compilation')
        if compiled.returncode:
            raise ValueError('Kahlua harness compilation failed:\n' + compiled.stdout + compiled.stderr)
        report_path = build / 'report.json'
        # Real MP snapshots contain thousands of long staged paths. Keep argv
        # bounded on macOS/Windows instead of depending on platform ARG_MAX.
        source_manifest = build / 'sources.txt'
        source_manifest.write_text(''.join(str(path) + '\n' for path in paths), encoding='utf-8')
        result = _run([java, '-cp', os.pathsep.join(map(str, (build, jar))),
                       'KahluaCompatibilityChecks', report_path, library, source_manifest],
                      'Installed Kahlua source check')
        if result.returncode not in (0, 1) or not report_path.is_file():
            raise ValueError('Installed Kahlua source check failed:\n' + result.stdout + result.stderr)
        try:
            report = json.loads(report_path.read_text(encoding='utf-8'))
        except (OSError, ValueError) as problem:
            raise ValueError(f'Invalid Kahlua compatibility report: {problem}') from problem
    for source in report['sources']:
        path = Path(source['path'])
        if hashlib.sha256(path.read_bytes()).hexdigest() != hashes[str(path)]:
            raise ValueError(f'Lua source changed during compatibility check: {path}')
        source['sha256'] = hashes[str(path)]
    report['scope'] = 'compile-only project sources; installed standard-global availability'
    report['runtime'] = {
        'game_jar_sha256': hashlib.sha256(jar.read_bytes()).hexdigest(),
        'stdlib_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
    }
    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    if report['status'] != 'passed':
        raise LuaCompatibilityError(report)
    return report
