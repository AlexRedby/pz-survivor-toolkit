"""Real pre-Host SP world save followed by the current warehouse migration."""
import json
from pathlib import Path
import re

from .. import receipts

CASES = ('legacy-seed', 'legacy-reload')
MARKER = '[WAREHOUSE_LEGACY] '


def validate(selection):
    from .warehouse_manifest import MODS
    options = selection.get('options', {})
    case = selection.get('cases')
    if (case not in ([CASES[0]], [CASES[1]]) or selection.get('kind') != 'sp'
            or selection.get('clients', 1) != 1 or type(selection.get('clients', 1)) is not int
            or selection.get('mode') != 'toolkit' or selection.get('languages') not in (['EN'], ['RU'])
            or not set(MODS) <= set(selection.get('mods', []))
            or not isinstance(options, dict) or any(options.get(k) for k in ('mp_host', 'seed_run', 'startup_connection'))
            or bool(options.get('world_template')) != (case == [CASES[1]])):
        raise ValueError('Legacy Warehouse requires one SP EN/RU client, legacy seed or sealed-world reload')


def _records(text, event):
    return receipts.records(text, MARKER, event)


def _one(text, event):
    values = _records(text, event)
    if len(values) != 1:
        raise ValueError('Missing/duplicate legacy ' + event)
    return values[0]


def complete(selection, role, text):
    return role == 'client1' and _records(text, 'COMPLETE') == [{'case': selection['cases'][0], 'role': role}]


def _state(row):
    if (type(row) is not dict or any(type(row.get(k)) is not int for k in ('schema', 'far', 'loaded'))
            or row['schema'] != 0 or row['far'] != 5 or row['loaded'] != 4
            or type(row.get('ids')) is not list or len(row['ids']) != 4
            or any(type(item) is not int for item in row['ids']) or len(set(row['ids'])) != 4):
        raise ValueError('Invalid original legacy world identities/counts/schema')


def verify(root, selection, catalog):
    root = Path(root)
    case, issues, receipts, screenshots = selection['cases'][0], [], {}, []
    try:
        from .warehouse_manifest import _exact, _shot
        text = (root / 'client1-launch.log').read_text(errors='replace')
        if not _exact(_one(text, 'SETUP'), {'case': case, 'role': 'client1'}) or not complete(selection, 'client1', text):
            raise ValueError('Legacy setup/completion absent')
        sequence = re.findall(re.escape(MARKER) + r'([A-Z_]+) ', text)
        if case == 'legacy-seed':
            saved = _one(text, 'SAVED'); _state(saved)
            if sequence != ['SETUP', 'SAVED', 'COMPLETE']:
                raise ValueError('Legacy seed lifecycle differs')
            receipts = {'saved': saved}
        else:
            cold = _one(text, 'COLD'); _state(cold)
            restored = _one(text, 'RESTORED')
            if not _exact(restored, dict(cold, schema=2, ui=9, unknownAge=True, native=True)):
                raise ValueError('Migrated native items/UI or last-known age differ')
            if sequence != ['COLD', 'SETUP', 'RESTORED', 'COMPLETE']:
                raise ValueError('Legacy migration did not observe disk state before startup')
            template = json.loads((root / 'world-template.json').read_text())
            if template['source_suite'] != 'warehouse-manifest' or template['source_cases'] != ['legacy-seed'] or template['kind'] != 'sp':
                raise ValueError('Migration requires the completed legacy seed world')
            seed = Path(template['source_run'])
            seed_selection = json.loads((seed / 'selection.json').read_text())
            seed_text = (seed / 'client1-launch.log').read_text(errors='replace')
            if not complete(seed_selection, 'client1', seed_text) or not _exact(_one(seed_text, 'SAVED'), cold):
                raise ValueError('Restored world changed original legacy identities')
            screenshots = [_shot(root, 'client1', 'legacy-reload')]
            receipts = {'cold': cold, 'restored': restored}
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': case,
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'receipts': receipts, 'screenshots': screenshots,
                         'limits': ['Native SP legacy world migration; Host persistence is a separate case.']}}
