"""Sealed disposable world templates, copied into fresh run caches."""
import hashlib
import os
from pathlib import Path
import re
import shutil

from . import adapters, report


SERVER_SETTINGS = ('Map', 'PVP', 'DoLuaChecksum', 'SleepAllowed', 'SleepNeeded')


def files(root):
    from .native import hashes
    if root.is_symlink() or any(path.is_symlink() for path in root.rglob('*')):
        raise ValueError('World template cannot contain symlinks')
    return hashes(root)


def _selection(value):
    if not isinstance(value, dict) or value.get('kind') not in ('sp', 'mp'):
        raise ValueError('Invalid world source selection')
    if not isinstance(value.get('suite'), str) or not value['suite']:
        raise ValueError('Invalid world source suite')
    for key in ('cases', 'mods'):
        items = value.get(key)
        if not isinstance(items, list) or not items or any(not isinstance(item, str) or not item for item in items) or len(set(items)) != len(items):
            raise ValueError('Invalid world source ' + key)
    ports = value.get('ports')
    if not isinstance(ports, list) or len(ports) != 2 or any(type(port) is not int or not 1024 <= port <= 65535 for port in ports) or ports[0] == ports[1]:
        raise ValueError('Invalid world source ports')
    clients = value.get('clients', 2 if value['kind'] == 'mp' else 1)
    if type(clients) is not int or clients not in (1, 2) or value['kind'] == 'sp' and clients != 1:
        raise ValueError('Invalid world source client count')
    return adapters.roles(value)


def _manifest(value):
    if not isinstance(value, dict) or type(value.get('schema_version')) is not int or value['schema_version'] != 1:
        raise ValueError('Invalid world template manifest')
    roles = value.get('roles')
    if roles not in (['client1'], ['server', 'client1'], ['server', 'client1', 'client2']):
        raise ValueError('Invalid world template roles')
    expected = _selection({'suite': value.get('source_suite'), 'cases': value.get('source_cases'),
                           'kind': value.get('kind'), 'mods': value.get('mods'), 'ports': value.get('ports'),
                           'clients': len(roles) - (1 if roles[0] == 'server' else 0)})
    if roles != expected or not isinstance(value.get('source_run'), str) or not Path(value['source_run']).is_absolute() or not isinstance(value.get('server_name'), str) or not value['server_name']:
        raise ValueError('Invalid world template metadata')
    if not isinstance(value.get('game_sha256'), str) or not re.fullmatch('[0-9a-f]{64}', value['game_sha256']):
        raise ValueError('Invalid world template game hash')
    if 'sandbox_sha256' not in value or (value['kind'] == 'sp' and value['sandbox_sha256'] is not None) or (value['kind'] == 'mp' and
            (not isinstance(value['sandbox_sha256'], str) or not re.fullmatch('[0-9a-f]{64}', value['sandbox_sha256']))):
        raise ValueError('Invalid world template sandbox hash')
    settings = value.get('server_settings')
    if 'server_settings' not in value or (value['kind'] == 'sp' and settings is not None) or (value['kind'] == 'mp' and
            (not isinstance(settings, dict) or set(settings) != set(SERVER_SETTINGS) or
             any(not isinstance(item, str) or not item for item in settings.values()) or
             any(settings[key] not in ('true', 'false') for key in SERVER_SETTINGS[1:]))):
        raise ValueError('Invalid world template server settings')
    state = value.get('files')
    if not isinstance(state, dict) or not state:
        raise ValueError('Invalid world template files')
    allowed = {role + '/' + sub for role in roles for sub in ('Saves', 'db')}
    for name, digest in state.items():
        if not isinstance(name, str):
            raise ValueError('Invalid world template path')
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or len(path.parts) < 3 or path.as_posix() != name or '/'.join(path.parts[:2]) not in allowed:
            raise ValueError('World template path escapes owned Saves/db: ' + name)
        if not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest):
            raise ValueError('Invalid world template file hash: ' + name)
    _require_world(state, value['kind'], value['server_name'])


def _state(run, roles):
    state = {}
    for role in roles:
        if (run / role).is_symlink():
            raise ValueError('World source cannot contain symlink caches')
        for sub in ('Saves', 'db'):
            source = run / role / sub
            if source.is_symlink():
                raise ValueError('World source cannot contain symlinks')
            if source.is_dir():
                state.update({role + '/' + sub + '/' + name: digest for name, digest in files(source).items()})
    return state


def _require_world(state, kind, server_name):
    if kind == 'mp':
        _server_path(server_name, '.ini')
    prefix = 'server/Saves/Multiplayer/' + server_name + '/' if kind == 'mp' else 'client1/Saves/'
    if not any(name.startswith(prefix) for name in state):
        raise ValueError('No saved authoritative world exists: ' + prefix)


def _server_path(server_name, suffix):
    if not isinstance(server_name, str) or not re.fullmatch('[A-Za-z0-9_.-]+', server_name) or server_name in ('.', '..'):
        raise ValueError('Invalid world server name')
    return 'server/Server/' + server_name + suffix


def _server_settings(text):
    result = {}
    for key in SERVER_SETTINGS:
        values = re.findall(r'^\s*' + key + r'\s*=([^\n\r]*)$', text, re.M)
        if len(values) != 1 or not values[0].strip():
            raise ValueError('Invalid world server settings: missing/duplicate ' + key)
        result[key] = values[0].strip()
    if any(result[key] not in ('true', 'false') for key in SERVER_SETTINGS[1:]):
        raise ValueError('Invalid world server settings: expected explicit booleans')
    return result


def verify_settings(value, output, runtime):
    """Check the effective staged MP settings after adapter overrides, before sealing a new run."""
    from .native import sha256
    _manifest(value)
    if value['kind'] == 'sp':
        return
    if not isinstance(runtime, dict) or runtime.get('server_name') != value['server_name']:
        raise ValueError('World template server name differs')
    path = Path(output) / _server_path(runtime['server_name'], '_SandboxVars.lua')
    if path.is_symlink() or not path.is_file() or sha256(path) != value['sandbox_sha256']:
        raise ValueError('World template sandbox settings differ from this run')
    path = Path(output) / _server_path(runtime['server_name'], '.ini')
    if path.is_symlink() or not path.is_file() or _server_settings(path.read_text(encoding='utf-8')) != value['server_settings']:
        raise ValueError('World template server settings differ from this run')


def export(run, output):
    from .native import sha256
    run, output = Path(run), Path(output)
    if run.is_symlink() or output.is_symlink():
        raise ValueError('World source/output cannot be a symlink')
    run, output = run.resolve(), output.resolve()
    if output.exists() or output.is_relative_to(run):
        raise ValueError('World template requires a fresh directory outside its source run')
    selection = report.read_json(run / 'selection.json')
    runtime = report.read_json(run / 'runtime.json')
    execution = report.read_json(run / 'execution.json')
    roles = _selection(selection)
    if not isinstance(runtime, dict) or not isinstance(runtime.get('game'), str) or not Path(runtime['game']).is_absolute() or not isinstance(runtime.get('server_name'), str) or not runtime['server_name'] or not isinstance(runtime.get('roles'), dict) or set(runtime['roles']) != set(roles):
        raise ValueError('Invalid world source runtime')
    for role, config in runtime['roles'].items():
        if not isinstance(config, dict) or not isinstance(config.get('cache'), str) or not Path(config['cache']).is_absolute() or Path(config['cache']).resolve() != run / role:
            raise ValueError('World source must use disposable owned caches')
    if not isinstance(execution, dict) or execution.get('status') != 'completed' or not isinstance(execution.get('processes'), dict) or set(execution['processes']) != set(roles):
        raise ValueError('Export requires a completed disposable run with all owned roles stopped')
    for process in execution['processes'].values():
        if not isinstance(process, dict) or type(process.get('exit_code')) is not int or type(process.get('pid')) is not int or process['pid'] <= 0:
            raise ValueError('World source has an unstopped process')
        try:
            os.kill(process['pid'], 0)
        except ProcessLookupError:
            pass
        else:
            raise ValueError('World source PID is still alive; export refused')
    changed = report.verify_manifest(run, 'snapshot-hashes.json')
    if changed:
        raise ValueError('World source snapshot changed: ' + '\n'.join(changed))
    state = _state(run, roles)
    _require_world(state, selection['kind'], runtime['server_name'])
    game_file = Path(runtime['game']) / 'projectzomboid.jar'
    game_hash = sha256(game_file)
    source_manifest = report.read_json(run / 'source-manifest.json')
    if not isinstance(source_manifest, dict) or source_manifest.get(str(game_file)) != game_hash:
        raise ValueError('World source game build differs from its prepared snapshot')
    sandbox_hash, server_settings = None, None
    if selection['kind'] == 'mp':
        sandbox_path = _server_path(runtime['server_name'], '_SandboxVars.lua')
        server_path = _server_path(runtime['server_name'], '.ini')
        initial = report.read_json(run / 'initial-settings.json')
        frozen = report.read_json(run / 'snapshot-hashes.json')
        if frozen.get('initial-settings.json') != sha256(run / 'initial-settings.json'):
            raise ValueError('World source initial settings are not pinned in its prepared snapshot')
        # The engine rewrites live Server files; initial-settings.json is the sealed input.
        for path, label in ((sandbox_path, 'sandbox'), (server_path, 'server')):
            if not isinstance(initial, dict) or not isinstance(initial.get(path), str):
                raise ValueError('World source initial ' + label + ' settings are missing')
        sandbox_hash = hashlib.sha256(initial[sandbox_path].encode('utf-8')).hexdigest()
        server_settings = _server_settings(initial[server_path])
    output.mkdir(parents=True)
    for name, digest in state.items():
        target = output / 'state' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(run / name, target)
        if sha256(target) != digest:
            raise ValueError('World changed during export: ' + name)
    if _state(run, roles) != state or report.verify_manifest(run, 'snapshot-hashes.json') or sha256(Path(runtime['game']) / 'projectzomboid.jar') != game_hash:
        raise ValueError('World changed during export')
    value = {'schema_version': 1, 'source_run': str(run), 'source_suite': selection['suite'],
             'source_cases': selection['cases'], 'kind': selection['kind'], 'roles': roles,
             'mods': selection['mods'], 'ports': selection['ports'], 'server_name': runtime['server_name'],
             'game_sha256': game_hash, 'sandbox_sha256': sandbox_hash, 'server_settings': server_settings, 'files': state}
    report.write_json(output / 'world.json', value)
    return value


def validate(template, selection, game):
    from .native import sha256
    template = Path(template)
    if template.is_symlink() or (template / 'world.json').is_symlink():
        raise ValueError('World template cannot be a symlink')
    template = template.resolve()
    value = report.read_json(template / 'world.json')
    _manifest(value)
    roles = _selection(selection)
    if value['kind'] != selection['kind'] or value['roles'] != roles:
        raise ValueError('World template kind/client count differs from this run')
    if value['kind'] == 'sp' and value['source_suite'] != selection['suite']:
        raise ValueError('SP world template belongs to a different suite')
    if value['mods'] != selection['mods'] or value['ports'] != selection['ports']:
        raise ValueError('World template ordered mods/ports differ from this run')
    if value['game_sha256'] != sha256(Path(game) / 'projectzomboid.jar'):
        raise ValueError('World template uses a different game build')
    if files(template / 'state') != value['files']:
        raise ValueError('World template changed or contains unexpected files')
    return template, value


def restore(template, value, output, runtime):
    from .native import sha256
    template, output = Path(template), Path(output)
    _manifest(value)
    if template.is_symlink() or (template / 'world.json').is_symlink() or output.is_symlink() or output.resolve().is_relative_to(template.resolve()):
        raise ValueError('World restore requires an independent owned output directory')
    if not isinstance(runtime, dict) or value['server_name'] != runtime.get('server_name'):
        raise ValueError('World template server name differs')
    if files(template / 'state') != value['files'] or report.read_json(template / 'world.json') != value:
        raise ValueError('World template changed before copying')
    for name, digest in value['files'].items():
        target = output / name
        if target.exists() or any((output / Path(*Path(name).parts[:index])).is_symlink() for index in range(1, len(Path(name).parts) + 1)):
            raise ValueError('World template would overwrite fixture state: ' + name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(template / 'state' / name, target)
        if sha256(target) != digest:
            raise ValueError('World template changed while copying: ' + name)
    if files(template / 'state') != value['files'] or report.read_json(template / 'world.json') != value:
        raise ValueError('World template changed while copying')
    report.write_json(output / 'world-template.json', dict(value, template=str(template)))
    runtime['world_template'] = {'template': str(template), 'source_suite': value['source_suite'],
                                 'source_cases': value['source_cases'], 'files': len(value['files'])}
