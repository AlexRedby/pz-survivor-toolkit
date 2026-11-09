"""Explicit mod-removal imports and Host-world overlays into sealed stand templates."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import sqlite3
import zipfile
from contextlib import closing

from . import progress, report, worlds
from .mod_selection import mod_ids

PLAYER_DB_CLASS = 'zombie/savefile/ServerPlayerDB.class'
# B42.21: non-Steam native lookup uses username/world/playerIndex; data stays opaque.
PLAYER_DB_SHA256 = 'aeb328c4dfbd436c372b3c2d350ac533dcd4e692b6ee58a5f8c24807ecf31379'
PLAYER_COLUMNS = ('id', 'world', 'username', 'playerIndex', 'name', 'steamid', 'x', 'y', 'z',
                  'worldversion', 'data', 'isDead', 'splitUsername')
PLAYER_TYPES = ('INTEGER', 'TEXT', 'TEXT', 'INTEGER', 'STRING', 'STRING', 'FLOAT', 'FLOAT', 'FLOAT',
                'INTEGER', 'BLOB', 'BOOLEAN', 'STRING')
HEADER = ('source_suite', 'source_cases', 'kind', 'roles', 'mp_host', 'ports', 'server_name',
          'game_sha256', 'sandbox_sha256', 'server_settings')
DIGEST = re.compile('[0-9a-f]{64}')


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def _hash(value):
    return isinstance(value, str) and DIGEST.fullmatch(value) is not None


def _absolute(value):
    return isinstance(value, str) and Path(value).is_absolute()


def _path(value, label, *, directory=False):
    path = Path(value).absolute()
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError(label + ' cannot use symlinks')
    if not (path.is_dir() if directory else path.is_file()):
        raise ValueError(label + ' must be an existing ' + ('directory' if directory else 'regular file'))
    return path.resolve()


def _tree(root):
    if not root.is_dir():
        raise ValueError('Missing source world directory')
    for path in root.rglob('*'):
        if path.is_symlink() or not (path.is_dir() or path.is_file()):
            raise ValueError('External world requires regular files/directories without symlinks')
        if path.name.endswith(('-wal', '-shm', '-journal')):
            raise ValueError('External world must be closed without SQLite journal sidecars')
    return worlds.files(root)


def _selection(base):
    return dict(suite=base['source_suite'], cases=base['source_cases'], kind=base['kind'], mods=base['mods'],
                ports=base['ports'], clients=len(base['roles']) - (base['kind'] == 'mp'),
                options={'mp_host': base.get('mp_host', False)})


def _removed(mods, removals):
    if (not isinstance(removals, list) or any(not isinstance(item, str) or item not in mods for item in removals)
            or len(set(removals)) != len(removals)):
        raise ValueError('Mod removals must name distinct mods present in the original template')
    return [mod for mod in mods if mod in removals]


def _source_files(value):
    if not isinstance(value, dict) or not value or 'players.db' not in value:
        raise ValueError('External Host world requires players.db and world files')
    for name, digest in value.items():
        path = Path(name) if isinstance(name, str) else None
        if (path is None or path.is_absolute() or '..' in path.parts or path.as_posix() != name
                or not path.parts or not _hash(digest) or path.name.endswith(('-wal', '-shm', '-journal'))):
            raise ValueError('Invalid external source world file seal')


def validate_origin(value):
    """Validate self-contained provenance, without needing original inputs to survive."""
    origin = value.get('origin')
    if (not isinstance(origin, dict) or set(origin) != {'kind', 'base_template', 'base_manifest',
            'base_manifest_sha256', 'base_world_json_sha256', 'removed_mods', 'external'}
            or origin.get('kind') != 'world-import' or not _absolute(origin.get('base_template'))
            or not _hash(origin.get('base_world_json_sha256'))):
        raise ValueError('Invalid imported world origin')
    base = origin['base_manifest']
    if not isinstance(base, dict) or base.get('schema_version') != 1 or 'origin' in base:
        raise ValueError('World import requires an original exported schema1 base template')
    worlds._manifest(base)
    if origin['base_manifest_sha256'] != _digest(base):
        raise ValueError('Imported base manifest seal differs')
    removed = _removed(base['mods'], origin['removed_mods'])
    if removed != origin['removed_mods'] or value['mods'] != [mod for mod in base['mods'] if mod not in removed]:
        raise ValueError('Imported mods must preserve order with exactly the declared removals')
    if any(value.get(key, False if key == 'mp_host' else None) != base.get(key, False if key == 'mp_host' else None) for key in HEADER):
        raise ValueError('Imported world changes the base topology, build or settings')
    expected = dict(base['files'])
    external = origin['external']
    if external is not None:
        if (base['kind'] != 'mp' or base.get('mp_host') is not True
                or not isinstance(external, dict) or set(external) != {'world_path', 'world_files',
                    'server_settings_path', 'server_settings_sha256', 'source_mods', 'server_settings',
                    'sandbox_path', 'sandbox_sha256', 'player_db_class_sha256', 'players', 'players_db_sha256',
                    'source_game_build_verified'}
                or any(not _absolute(external.get(key)) for key in ('world_path', 'server_settings_path', 'sandbox_path'))
                or not _hash(external.get('server_settings_sha256')) or not _hash(external.get('players_db_sha256'))
                or external.get('source_mods') != base['mods'] or external.get('server_settings') != base['server_settings']
                or external.get('sandbox_sha256') != base['sandbox_sha256']
                or external.get('source_game_build_verified') is not False
                or external.get('player_db_class_sha256') != PLAYER_DB_SHA256):
            raise ValueError('Invalid external Host import provenance')
        _source_files(external['world_files'])
        players = external['players']
        roles = [role for role in base['roles'] if role != 'server']
        if (not isinstance(players, list) or len(players) != len(roles)
                or [row.get('role') if isinstance(row, dict) else None for row in players] != roles):
            raise ValueError('Imported player mappings must cover every fixture client')
        source_ids, target_ids = set(), set()
        for row in players:
            if (set(row) != {'role', 'source_id', 'target_id', 'blob_sha256'}
                    or any(type(row[key]) is not int or row[key] <= 0 for key in ('source_id', 'target_id'))
                    or row['source_id'] in source_ids or row['target_id'] in target_ids or not _hash(row['blob_sha256'])):
                raise ValueError('Invalid or duplicate imported player mapping')
            source_ids.add(row['source_id']); target_ids.add(row['target_id'])
        prefix = 'client1/Saves/Multiplayer/' + base['server_name'] + '/'
        expected = {name: digest for name, digest in expected.items() if not name.startswith(prefix)}
        expected.update({prefix + name: digest for name, digest in external['world_files'].items()})
        expected[prefix + 'players.db'] = external['players_db_sha256']
    if value['files'] != expected:
        raise ValueError('Imported state differs from declared copies and player transformation')


def _settings(path, base):
    text = path.read_text(encoding='utf-8-sig')
    entries = re.findall(r'^\s*Mods\s*=([^\r\n]*)$', text, re.M)
    if len(entries) != 1 or mod_ids(entries[0].strip()) != base['mods']:
        raise ValueError('External server Mods must match the original template in exact order')
    settings = worlds._server_settings(text)
    if settings != base['server_settings']:
        raise ValueError('External server settings differ from the base template')
    return settings


def verify_player_api(game):
    try:
        with zipfile.ZipFile(Path(game) / 'projectzomboid.jar') as archive:
            digest = hashlib.sha256(archive.read(PLAYER_DB_CLASS)).hexdigest()
    except (OSError, KeyError, zipfile.BadZipFile) as error:
        raise ValueError('Cannot verify native Host player database API') from error
    if digest != PLAYER_DB_SHA256:
        raise ValueError('External player import requires the reviewed B42.21 native database API')
    return digest


def _player_mappings(roles, mappings):
    if (not isinstance(mappings, dict) or set(mappings) != set(roles)
            or any(type(row) is not int or row <= 0 for row in mappings.values())
            or len(set(mappings.values())) != len(mappings)):
        raise ValueError('Explicit distinct player row IDs are required for every fixture client')


def _clone_players(path, roles, mappings, server_name):
    _player_mappings(roles, mappings)
    # Only the disposable copy is opened writable. Never open the source DB through SQLite.
    try:
        with closing(sqlite3.connect(path)) as connection, connection:
            connection.execute('PRAGMA journal_mode=DELETE')
            connection.row_factory = sqlite3.Row
            columns = connection.execute('PRAGMA table_info(networkPlayers)').fetchall()
            if (tuple(row['name'] for row in columns) != PLAYER_COLUMNS
                    or tuple(row['type'].upper() for row in columns) != PLAYER_TYPES
                    or tuple((row['notnull'], row['pk']) for row in columns) != ((1, 1),) + ((0, 0),) * 12):
                raise ValueError('Unsupported native networkPlayers schema')
            if connection.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise ValueError('Invalid source player database')
            if any(row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='trigger'")):
                raise ValueError('Player database triggers are unsupported')
            original = [tuple(row) for row in connection.execute('SELECT * FROM networkPlayers ORDER BY id')]
            original_ids = {row[0] for row in original}
            if any(identifier not in original_ids for identifier in mappings.values()):
                raise ValueError('Selected source player must be a living native character with an opaque blob')
            receipts = []
            for role in roles:
                row = connection.execute('SELECT * FROM networkPlayers WHERE id=?', (mappings[role],)).fetchone()
                if (row is None or row['isDead'] != 0 or not isinstance(row['data'], bytes) or not row['data']
                        or any(type(row[key]) not in (int, float) or not math.isfinite(row[key]) for key in ('x', 'y', 'z'))
                        or type(row['worldversion']) is not int or row['worldversion'] <= 0):
                    raise ValueError('Selected source player must be a living native character with an opaque blob')
                if connection.execute('SELECT id FROM networkPlayers WHERE world=? AND username=? AND playerIndex=0',
                                      (server_name, role)).fetchone():
                    raise ValueError('Imported fixture player identity already exists; refusing to overwrite it')
                data = dict(row)
                data.update(world=server_name, username=role, playerIndex=0, steamid=None, splitUsername=role)
                columns = PLAYER_COLUMNS[1:]
                cursor = connection.execute('INSERT INTO networkPlayers (' + ','.join(columns) + ') VALUES ('
                                            + ','.join('?' for _ in columns) + ')', [data[key] for key in columns])
                receipts.append(dict(role=role, source_id=row['id'], target_id=cursor.lastrowid,
                                     blob_sha256=hashlib.sha256(row['data']).hexdigest()))
            for row in original:
                if tuple(connection.execute('SELECT * FROM networkPlayers WHERE id=?', (row[0],)).fetchone()) != row:
                    raise ValueError('Player import changed an original row')
        return receipts
    except sqlite3.Error as error:
        raise ValueError('Cannot import the native player database: ' + str(error)) from error


def _copy(source, target, digest):
    from .native import sha256
    if target.exists() or target.is_symlink():
        raise ValueError('Import would overwrite output state')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    if sha256(target) != digest:
        raise ValueError('Source changed during world import')
    progress.file(target)


@progress.operation('import-world')
def create(template, output, game, removals=(), *, external_world=None, server_settings=None, sandbox=None, players=None):
    """Derive a fresh template; raw overlays use a known Host stand as their environment."""
    from .native import sha256
    template = _path(template, 'Base template', directory=True)
    output = Path(output).absolute()
    if any(path.is_symlink() for path in (output, *output.parents)):
        raise ValueError('World import output cannot use symlinks')
    output = output.resolve()
    if output.exists() or output.is_relative_to(template) or output.is_relative_to(Path(game).resolve()):
        raise ValueError('World import requires a fresh independent output directory')
    base = report.read_json(template / 'world.json')
    if not isinstance(base, dict) or base.get('schema_version') != 1 or 'origin' in base:
        raise ValueError('Use the original exported schema1 base template for every import')
    worlds._manifest(base)
    template, base = worlds.validate(template, _selection(base), game)
    base_hash = sha256(template / 'world.json')
    game_hash = sha256(Path(game) / 'projectzomboid.jar')
    removed = _removed(base['mods'], list(removals))
    value = {key: item for key, item in base.items() if key != 'source_run'}
    value.update(schema_version=2, mods=[mod for mod in base['mods'] if mod not in removed])
    worlds._selection(dict(_selection(base), mods=value['mods']))
    origin = dict(kind='world-import', base_template=str(template), base_manifest=base,
                  base_manifest_sha256=_digest(base), base_world_json_sha256=base_hash,
                  removed_mods=removed, external=None)
    value['origin'] = origin
    external = None
    prefix = 'client1/Saves/Multiplayer/' + base['server_name'] + '/'
    if external_world is not None:
        if base['kind'] != 'mp' or base.get('mp_host') is not True:
            raise ValueError('Raw external world overlays require an exported menu-Host base template')
        external = _path(external_world, 'External world', directory=True)
        settings_path = _path(server_settings, 'External server settings') if server_settings is not None else None
        sandbox_path = _path(sandbox, 'External sandbox') if sandbox is not None else None
        if settings_path is None or sandbox_path is None:
            raise ValueError('External world import requires explicit server settings and sandbox files')
        if output.is_relative_to(external):
            raise ValueError('World import output must be outside all external input directories')
        _player_mappings([role for role in base['roles'] if role != 'server'], players)
        source_state = _tree(external)
        _source_files(source_state)
        settings = _settings(settings_path, base)
        if sha256(sandbox_path) != base['sandbox_sha256']:
            raise ValueError('External sandbox differs from the original template')
        origin['external'] = dict(world_path=str(external), world_files=source_state,
            server_settings_path=str(settings_path), server_settings_sha256=sha256(settings_path),
            source_mods=base['mods'], server_settings=settings, sandbox_path=str(sandbox_path),
            sandbox_sha256=sha256(sandbox_path), player_db_class_sha256=verify_player_api(game),
            players=[], players_db_sha256='', source_game_build_verified=False)
    elif any(item is not None for item in (server_settings, sandbox, players)):
        raise ValueError('External settings and player mappings require --external-world')
    output.mkdir(parents=True)
    for name, digest in base['files'].items():
        if external is None or not name.startswith(prefix):
            _copy(template / 'state' / name, output / 'state' / name, digest)
    if external is not None:
        for name, digest in source_state.items():
            _copy(external / name, output / 'state' / prefix / name, digest)
        copied_db = output / 'state' / prefix / 'players.db'
        roles = [role for role in base['roles'] if role != 'server']
        origin['external']['players'] = _clone_players(copied_db, roles, players, base['server_name'])
        origin['external']['players_db_sha256'] = sha256(copied_db)
        if (_tree(external) != source_state or sha256(settings_path) != origin['external']['server_settings_sha256']
                or sha256(sandbox_path) != origin['external']['sandbox_sha256']):
            raise ValueError('External inputs changed during world import')
    value['files'] = worlds.files(output / 'state')
    worlds._manifest(value)
    if ((template / 'world.json').is_symlink() or sha256(template / 'world.json') != base_hash or report.read_json(template / 'world.json') != base
            or worlds.files(template / 'state') != base['files'] or sha256(Path(game) / 'projectzomboid.jar') != game_hash):
        raise ValueError('Base template or game changed during world import')
    # Publication is last: an interrupted/failed import cannot become a usable template.
    report.write_json(output / 'world.json', value)
    return value
