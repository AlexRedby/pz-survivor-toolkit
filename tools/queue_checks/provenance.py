"""Prepared source roles and post-cleanup seals for native observations."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
from types import ModuleType

from . import adapters, progress


SOURCE_ROLES = 'source-roles.json'
EXECUTION_SEAL = 'execution-seal.json'


def _regular_file(path):
    flags = os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(path, flags)
    stream = os.fdopen(descriptor, 'rb')
    if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
        stream.close()
        raise ValueError('Native evidence must be a regular file: ' + str(path))
    return stream


def read_json(path):
    with _regular_file(path) as stream:
        return json.load(stream)


def run_verifier(path, package, root, selection, catalog):
    """Execute the current source bytes, independent of imported modules and pyc files."""
    path = Path(path)
    module = ModuleType(package + '.' + path.stem)
    module.__file__, module.__package__ = str(path), package
    with _regular_file(path) as stream:
        code = compile(stream.read(), str(path), 'exec')
    exec(code, module.__dict__)
    return module.verify(root, selection, catalog)


def digest(path):
    value = hashlib.sha256()
    with _regular_file(path) as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
            progress.pulse(path)
    return value.hexdigest()


def verifier_sources(project, selection):
    adapter = adapters.get(selection['suite'])
    declare = getattr(adapter, 'verifier_sources', None)
    if declare is None:
        return []
    # Only explicitly separated verifiers opt into report-only reanalysis.
    return [Path(__file__).with_name('reanalysis.py'), *map(Path, declare(project, selection))]


def source_roles(project, selection, manifest):
    verifiers = {str(path.resolve()) for path in verifier_sources(project, selection)}
    if not verifiers <= manifest.keys():
        raise ValueError('Verifier inputs must be included in the original source manifest')
    return dict(schema_version=1, project=str(Path(project).resolve()),
                runtime={name: value for name, value in manifest.items() if name not in verifiers},
                verifier={name: value for name, value in manifest.items() if name in verifiers})


def _hashes(value, absolute):
    return (isinstance(value, dict) and all(
        isinstance(name, str) and bool(name) and Path(name).is_absolute() is absolute
        and (absolute or '..' not in Path(name).parts)
        and isinstance(sha, str) and re.fullmatch('[0-9a-f]{64}', sha)
        for name, sha in value.items()))


def _roles(root):
    # Refuse special metadata files before JSON readers can block on them.
    for name in (SOURCE_ROLES, 'source-manifest.json', 'snapshot-hashes.json', 'selection.json',
                 'runtime.json', 'game-inputs.json'):
        digest(root / name)
    value = read_json(root / SOURCE_ROLES)
    original = read_json(root / 'source-manifest.json')
    if (not isinstance(value, dict) or type(value.get('schema_version')) is not int or value['schema_version'] != 1
            or not isinstance(value.get('project'), str) or not Path(value['project']).is_absolute()
            or not _hashes(value.get('runtime'), True) or not value['runtime']
            or not _hashes(value.get('verifier'), True)
            or value['runtime'].keys() & value['verifier'].keys()
            or {**value['runtime'], **value['verifier']} != original):
        raise ValueError('Invalid prepared source roles; prepare a fresh snapshot')
    return value


@progress.operation('verify-runtime-inputs')
def runtime_issues(root):
    """Verify all prepared bytes while allowing only the declared verifier to change."""
    from . import report
    root = Path(root).resolve()
    value = _roles(root)
    errors = report.verify_manifest(root, 'snapshot-hashes.json') + report.verify_game_inputs(root)
    frozen = read_json(root / 'snapshot-hashes.json')
    if SOURCE_ROLES not in frozen:
        errors.append('Prepared source roles are not sealed; prepare a fresh snapshot')
    for name, expected in value['runtime'].items():
        path = Path(name)
        if not path.is_file() or path.is_symlink() or digest(path) != expected:
            errors.append('Changed or missing runtime/fixture input: ' + name)
        progress.file(path)
    return errors


def observation_files(root):
    """Exact common evidence set; opted-in adapters must use these observations only."""
    from . import report
    root = Path(root).resolve()
    selection = read_json(root / 'selection.json')
    paths = {root / 'execution.json', *root.glob('*-launch.log'), *root.glob('*-probes.log'),
             *root.glob('*-setup-threads.log')}
    for role in adapters.roles(selection):
        paths.update(report.log_paths(root, role))
    result = {}
    for path in sorted(paths):
        relative = path.relative_to(root)
        if not path.resolve().is_relative_to(root) or any((root / Path(*relative.parts[:i])).is_symlink()
                for i in range(1, len(relative.parts) + 1)):
            raise ValueError('Observation path escapes owned run or uses a symlink: ' + str(relative))
        result[relative.as_posix()] = digest(path)
    return result


@progress.operation('seal-execution-observations')
def seal_execution(root):
    """Called once by the runner after process cleanup, log closure and final execution."""
    root = Path(root).resolve()
    if not (root / SOURCE_ROLES).exists():
        return  # Legacy captures remain usable by the strict report command only.
    value = dict(schema_version=1, snapshot_sha256=digest(root / 'snapshot-hashes.json'),
                 input_issues=runtime_issues(root), files=observation_files(root))
    with (root / EXECUTION_SEAL).open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(value, indent=2) + '\n')


def observation_issues(root):
    root = Path(root).resolve()
    try:
        digest(root / EXECUTION_SEAL)
        value = read_json(root / EXECUTION_SEAL)
        if (not isinstance(value, dict) or type(value.get('schema_version')) is not int or value['schema_version'] != 1
                or not _hashes(value.get('files'), False) or 'execution.json' not in value['files']
                or value.get('snapshot_sha256') != digest(root / 'snapshot-hashes.json')
                or value.get('input_issues') != []):
            return ['Invalid execution observation seal; a fresh native run is required']
        if value['files'] != observation_files(root):
            return ['Execution observations changed: log/evidence file set or content differs']
        return []
    except (OSError, ValueError, KeyError, TypeError) as error:
        return ['Cannot verify execution observations; a fresh native run is required: ' + str(error)]


def reanalysis_provenance(root):
    root = Path(root).resolve()
    try:
        if not (root / SOURCE_ROLES).is_file() or not (root / EXECUTION_SEAL).is_file():
            raise ValueError('Capture lacks prepared source roles or sealed execution observations; a fresh native run is required')
        original = _roles(root)
        if not original['verifier']:
            raise ValueError('Suite has no separated verifier contract')
        errors = runtime_issues(root) + observation_issues(root)
        declared = {str(path.resolve()) for path in verifier_sources(
            original['project'], read_json(root / 'selection.json'))}
        if declared != original['verifier'].keys():
            errors.append('Verifier dependency set changed; prepare a fresh snapshot')
        if errors:
            raise ValueError('\n'.join(errors))
        current = {name: digest(name) for name in sorted(declared)}
        return dict(mode='recorded-runtime', execution_seal_sha256=digest(root / EXECUTION_SEAL),
                    snapshot_sha256=digest(root / 'snapshot-hashes.json'),
                    original_verifier=original['verifier'], current_verifier=current)
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise ValueError('Cannot reanalyze native run: ' + str(error)) from error
