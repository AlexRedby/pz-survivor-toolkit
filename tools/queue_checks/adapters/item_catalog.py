"""Manual native item-category catalogue inspection in a disposable SP profile."""
from pathlib import Path
import re


SUITE = 'item-catalog'
MARKER = '[ITEM_CATALOG] '
MODS = ['PZSurvivorToolkit']
READY = re.compile(r'^\[ITEM_CATALOG\] READY items=(\d+) crates=(\d+) skipped=(\d+)$')


def definitions():
    return {SUITE: {'status': 'ready', 'native_validation': 'not-run', 'clients': 1,
                    'default_mods': list(MODS),
                    'cases': [{'id': 'browse', 'producer': 'fixture', 'capability': 'capture',
                               'kinds': ['sp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}],
                    'limits': ['Manual category inspection only; no functional pass is inferred.']}}


def validate(selection):
    options = selection.get('options', {})
    if (selection.get('suite') != SUITE or selection.get('cases') != ['browse']
            or selection.get('kind') != 'sp' or selection.get('mode') != 'toolkit'
            or selection.get('clients', 1) != 1
            or selection.get('languages') not in (['EN'], ['RU'])
            or not isinstance(selection.get('mods'), list) or not set(MODS) <= set(selection['mods'])
            or not isinstance(options, dict)
            or options.get('seed_run') or options.get('startup_connection') or options.get('mp_host')):
        raise ValueError('Item catalogue requires one EN/RU SP client, browse, and PZSurvivorToolkit')
    # world_template is intentionally allowed for same-suite sealed-world reuse.


def sources(project, selection):
    validate(selection)
    return sorted(path for path in (Path(project) / 'tests/native_queue' / SUITE).rglob('*')
                  if path.is_file() and path.suffix in ('.lua', '.json'))


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    roles = runtime.get('roles', {})
    if set(roles) != {'client1'}:
        raise ValueError('Item catalogue requires exactly one disposable client profile')
    fixture = runtime.setdefault('fixture', {})
    fixture['manual'] = True
    fixture['failure_markers'] = [MARKER + 'FAIL ']


def complete(selection, role, text):
    # This is a browse-and-exit fixture; the user controls its lifetime.
    return False


def verify(root, selection, catalog):
    root = Path(root)
    path = root / 'client1-launch.log'
    text = path.read_text(errors='replace') if path.is_file() else ''
    ready_lines = []
    for line in text.splitlines():
        offset = line.find(MARKER + 'READY')
        if offset >= 0:
            ready_lines.append(line[offset:])
    rows = [match for line in ready_lines if (match := READY.fullmatch(line))]
    issues = []
    if MARKER + 'FAIL ' in text:
        issues.append('Item catalogue fixture reported failure')
    if len(ready_lines) != 1 or len(rows) != 1:
        issues.append('Expected exactly one item catalogue READY receipt')
        counts = None
    else:
        counts = tuple(int(value) for value in rows[0].groups())
        if counts[0] <= 0 or counts[1] <= 0 or counts[2] < 0:
            issues.append('Item catalogue READY receipt has invalid counts')
    if issues:
        status = 'failed'
    else:
        status = 'captured'
    outcome = {'manualReview': True, 'evidenceComplete': False}
    if counts is not None:
        outcome.update(items=counts[0], crates=counts[1], skipped=counts[2])
    return {'issues': issues, 'evidence': {'manualReview': True, 'readyCounts': counts},
            'outcomes': [{'actor': 'client1', 'case': 'browse', 'status': status,
                          'reason': 'Manual item category inspection; no functional result is asserted',
                          'outcome': outcome}]}
