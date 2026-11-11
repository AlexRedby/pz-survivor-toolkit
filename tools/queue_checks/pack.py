"""Lock the actual selected modpack and reject drift before native launch."""
from pathlib import Path
import re

from . import report, progress, mod_inputs
from .mod_selection import MOD_ID, mod_ids, mod_info


def create(project, output, game, workshop=(), overrides=None):
    from .native import _locations, _metadata, sha256
    project, output, game = Path(project), Path(output), Path(game)
    if output.exists():
        raise FileExistsError('Fresh pack lock output required')
    ini = project / 'SurvivorQoL-selected.ini'
    settings = _metadata(ini)
    mods = mod_ids(settings.get('Mods', ''))
    locations = _locations(project, list(map(Path, workshop)), mods, overrides)
    if any(output.resolve().is_relative_to(root) for root in locations.values()):
        raise ValueError('Pack lock output must be outside selected mod sources')
    rows = []
    for id, root in locations.items():
        metadata = _metadata(mod_info(root))
        rows.append({'id': id, 'source': str(root), 'version': metadata.get('version') or metadata.get('modversion'),
                     'files': mod_inputs.hashes(root)})
    value = {'schema_version': 2, 'input_policy': mod_inputs.POLICY,
             'selected_ini_sha256': sha256(ini), 'selected_settings': settings,
             'workshop_ids': [id for id in settings.get('WorkshopItems', '').split(';') if id],
             'game_sha256': sha256(game / 'projectzomboid.jar'), 'mods': rows}
    output.parent.mkdir(parents=True, exist_ok=True)
    report.write_json(output, value)
    return value


def read(path):
    """Read declared IDs/maps without reinterpreting a legacy whole-tree lock."""
    path = Path(path)
    if not path.is_absolute():
        raise ValueError('pack_lock must be an absolute lock-file path')
    value = report.read_json(path)
    if not isinstance(value, dict):
        raise ValueError('Invalid pack lock')
    version = value.get('schema_version')
    if type(version) is int and version == 1:
        raise ValueError('Pack lock schema 1 uses legacy whole-tree membership; regenerate with lock-pack for schema 2')
    rows = value.get('mods')
    if type(version) is not int or version != 2 or not isinstance(rows, list) or not rows:
        raise ValueError('Invalid pack lock')
    if value.get('input_policy') != mod_inputs.POLICY:
        raise ValueError('Unsupported pack lock input_policy; regenerate with lock-pack')
    if any(not isinstance(row, dict) or not isinstance(row.get('id'), str) or not MOD_ID.fullmatch(row['id']) or row['id'] in ('.', '..')
           or not isinstance(row.get('source'), str) or not Path(row['source']).is_absolute()
           or not isinstance(row.get('files'), dict) or not row['files'] for row in rows):
        raise ValueError('Invalid pack lock mod entry')
    for row in rows:
        for name, digest in row['files'].items():
            if (not isinstance(name, str) or not name or Path(name).is_absolute() or '..' in Path(name).parts
                    or mod_inputs.excluded(name) or not isinstance(digest, str)
                    or not re.fullmatch('[0-9a-f]{64}', digest)):
                raise ValueError('Invalid pack lock mod file entry')
    identifiers = [row['id'] for row in rows]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError('Pack lock ordered Mod IDs contain duplicates')
    return value


@progress.operation('verify-selected-pack')
def validate(path, project, game, mods):
    from .native import sha256, _metadata
    value = read(path)
    rows = value['mods']
    identifiers = [row['id'] for row in rows]
    if identifiers != mods:
        raise ValueError('Pack lock ordered Mod IDs differ from selection')
    if sha256(Path(project) / 'SurvivorQoL-selected.ini') != value.get('selected_ini_sha256'):
        raise ValueError('Selected INI differs from pack lock; regenerate the lock explicitly')
    settings = _metadata(Path(project) / 'SurvivorQoL-selected.ini')
    if value.get('selected_settings') != settings or identifiers != mod_ids(settings.get('Mods', '')):
        raise ValueError('Pack lock fields differ from the actual selected INI')
    if sha256(Path(game) / 'projectzomboid.jar') != value.get('game_sha256'):
        raise ValueError('Game build differs from pack lock')
    for row in rows:
        if not Path(row['source']).is_dir() or mod_inputs.hashes(Path(row['source'])) != row['files']:
            raise ValueError('Missing or changed locked mod: ' + row['id'])
    return {row['id']: row['source'] for row in rows}
