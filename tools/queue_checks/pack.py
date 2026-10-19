"""Lock the actual selected modpack and reject drift before native launch."""
from pathlib import Path

from . import report
from .mod_selection import mod_ids, mod_info


def create(project, output, game, workshop=(), overrides=None):
    from .native import _locations, _metadata, hashes, sha256
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
        rows.append({'id': id, 'source': str(root), 'version': metadata.get('version') or metadata.get('modversion'), 'files': hashes(root)})
    value = {'schema_version': 1, 'selected_ini_sha256': sha256(ini), 'selected_settings': settings,
             'workshop_ids': [id for id in settings.get('WorkshopItems', '').split(';') if id],
             'game_sha256': sha256(game / 'projectzomboid.jar'), 'mods': rows}
    output.parent.mkdir(parents=True, exist_ok=True)
    report.write_json(output, value)
    return value


def validate(path, project, game, mods):
    from .native import hashes, sha256, MOD_ID, _metadata
    path = Path(path)
    if not path.is_absolute():
        raise ValueError('pack_lock must be an absolute lock-file path')
    value = report.read_json(path)
    if not isinstance(value, dict):
        raise ValueError('Invalid pack lock')
    rows = value.get('mods')
    if value.get('schema_version') != 1 or not isinstance(rows, list) or not rows:
        raise ValueError('Invalid pack lock')
    if any(not isinstance(row, dict) or not isinstance(row.get('id'), str) or not MOD_ID.fullmatch(row['id']) or row['id'] in ('.', '..')
           or not isinstance(row.get('source'), str) or not Path(row['source']).is_absolute()
           or not isinstance(row.get('files'), dict) or not row['files'] for row in rows):
        raise ValueError('Invalid pack lock mod entry')
    identifiers = [row['id'] for row in rows]
    if len(identifiers) != len(set(identifiers)) or identifiers != mods:
        raise ValueError('Pack lock ordered Mod IDs differ from selection')
    if sha256(Path(project) / 'SurvivorQoL-selected.ini') != value.get('selected_ini_sha256'):
        raise ValueError('Selected INI differs from pack lock; regenerate the lock explicitly')
    settings = _metadata(Path(project) / 'SurvivorQoL-selected.ini')
    if value.get('selected_settings') != settings or identifiers != mod_ids(settings.get('Mods', '')):
        raise ValueError('Pack lock fields differ from the actual selected INI')
    if sha256(Path(game) / 'projectzomboid.jar') != value.get('game_sha256'):
        raise ValueError('Game build differs from pack lock')
    for row in rows:
        if not Path(row['source']).is_dir() or hashes(Path(row['source'])) != row['files']:
            raise ValueError('Missing or changed locked mod: ' + row['id'])
    return {row['id']: row['source'] for row in rows}
