"""Native SP hutch inspection and queued ground butchering through the common runner."""
from pathlib import Path

CASES = ['animal-info', 'ground-butchering']
SHOTS = ['animal-fixes-dead-info.png', 'animal-fixes-live-info.png', 'animal-fixes-queue.png']


def definitions():
    return {'animal-fixes': {'status': 'ready', 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
                            'cases': [{'id': case, 'producer': 'menu', 'capability': 'effect',
                                       'kinds': ['sp'], 'languages': ['EN'], 'modes': ['toolkit']}
                                      for case in CASES]}}


def validate(selection):
    if (selection['cases'] != CASES or selection['kind'] != 'sp' or selection['mode'] != 'toolkit'
            or selection.get('clients', 1) != 1 or selection['languages'] != ['EN']):
        raise ValueError('Animal fixes require both cases in EN/SP/toolkit mode with one client')


def sources(project, selection):
    return sorted((Path(project) / 'tests/native_queue/animal-fixes').rglob('*.lua'))


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)


def complete(selection, role, text):
    return role == 'client1' and text.count('[ANIMAL_FIX_TEST] COMPLETE') == 1


def verify(root, selection, catalog):
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    issues, screenshots = [], []
    markers = ['[QUEUE_TEST] PASS ' + case for case in CASES] + ['[ANIMAL_FIX_TEST] COMPLETE']
    positions = [text.find(marker) for marker in markers]
    if any(text.count(marker) != 1 for marker in markers) or positions != sorted(positions):
        issues.append('Missing, duplicate or reordered animal-fix completion markers')
    if '[QUEUE_TEST] FAIL ' in text:
        issues.append('Native animal fixture failed')
    for name in SHOTS:
        matches = list((root / 'client1').rglob(name))
        if len(matches) != 1 or not matches[0].read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
            issues.append('Missing or invalid screenshot: ' + name)
        else:
            screenshots.append(str(matches[0]))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': case,
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)} for case in CASES],
            'evidence': {'screenshots': screenshots,
                         'limits': ['Fresh EN single-player world; callbacks invoked programmatically.']}}
