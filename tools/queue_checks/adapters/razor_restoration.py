"""Live native razor producer and newer explicit primary intent."""
from pathlib import Path
import shutil
import zipfile

from .tv_controls import MODS as SELECTED_MODS

CASES = ('restore-success', 'empty-primary', 'new-primary-intent', 'cancel-active', 'full-origin', 'unavailable-origin', 'keep-return', 'trim-scissors', 'cut-hair-scissors', 'two-handed-axe', 'two-handed-axe-new-primary-intent', 'one-handed-axe', 'one-handed-axe-new-primary-intent')
MODS = [identifier for identifier in SELECTED_MODS if identifier != 'P4TidyUpMeister']
PREFIX = '[RAZOR_RESTORATION] '


def definitions():
    return {'razor-restoration': dict(status='ready', clients=1, default_mods=list(MODS),
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                    modes=['toolkit'], languages=['EN']) for case in CASES])}


def validate(selection):
    cases = selection.get('cases')
    editor = selection.get('options', {}).get('queue_editor_enabled', True)
    delay = selection.get('options', {}).get('razor_hand_ack_delay_ms')
    if delay is not None and (type(delay) is not int or delay != 1000 or cases != ['restore-success']
                              or selection.get('kind') != 'mp' or editor is not True):
        raise ValueError('Delayed hand authority requires isolated restore-success, menu Host, editor on and 1000ms')
    if type(editor) is not bool or not editor and (type(cases) is not list or any(case not in ('restore-success', 'empty-primary', 'trim-scissors', 'cut-hair-scissors') for case in cases)):
        raise ValueError('queue_editor_enabled must be boolean; editor-off requires ordinary restore cases')
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') != 'toolkit'
            or selection.get('languages') != ['EN'] or type(selection.get('clients')) is not int
            or selection['clients'] != 1 or selection.get('mods') != MODS
            or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Razor restoration requires ordered Toolkit cases, full selected pack without P4, fresh SP/menu Host and one EN client')


def verifier_sources(project, selection):
    return [Path(__file__).with_name('razor_restoration_verifier.py'),
            Path(__file__).with_name('claimed_return_verifier.py'), Path(__file__).parents[1] / 'receipts.py', Path(__file__).parents[1] / 'placement.py',
            Path(project) / 'tests/test_queue_razor_restoration.py',
            Path(project) / 'tests/test_queue_razor_hand_authority.py']


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'razor-restoration').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            root / 'support/QueuePreflight.lua', *([root / 'fitness/java/Main.java', Path(__file__).with_name('fitness.py')]
                if selection.get('options', {}).get('razor_hand_ack_delay_ms') is not None else []), *verifier_sources(project, selection)]


def audit_bridge(locations):
    """Require the selected native lifecycle/ACK artifact, never installed fallback."""
    jar = Path(locations['PZToolkitJavaPatches']) / '42/media/java/PZToolkitJavaPatches.jar'
    required = {'ActionCompletion', 'ActionAcknowledgements', 'ActionAcknowledgementLogic'}
    with zipfile.ZipFile(jar) as archive:
        available = {Path(name).stem for name in archive.namelist()
                     if name.startswith('net/alexredby/pztoolkitjavapatches/') and name.endswith('.class')}
    if not required <= available:
        raise ValueError('Razor restoration requires the selected native lifecycle and acknowledgement bridge JAR')


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    audit_bridge(locations)
    root = Path(project) / 'tests/native_queue'
    probe = None
    if selection.get('options', {}).get('razor_hand_ack_delay_ms') is not None:
        from .fitness import _validity_probe
        probe = _validity_probe(project, output, game, jdk, locations)
        runtime.setdefault('fixture', {})['mods'] = ['FitnessValidityProbe']
    for role in runtime['roles'].values():
        if probe:
            layer = Path(role['cache']) / 'mods/FitnessValidityProbe/42'
            (layer / 'media/java').mkdir(parents=True, exist_ok=True)
            (layer / 'mod.info').write_text('name=Isolated receipt delay probe\nid=FitnessValidityProbe\nversionMin=42.22\n'
                'require=\\ZombieBuddy\njavaPkgName=net.alexredby.fitnessprobe\njavaJarFile=media/java/FitnessValidityProbe.jar\n')
            shutil.copy2(probe, layer / 'media/java/FitnessValidityProbe.jar')
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        (lua / 'shared').mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL razor-restoration'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    from ..receipts import records
    try:
        return role == 'client1' and records(text, PREFIX, 'COMPLETE') == [dict(cases=selection['cases'])]
    except (ValueError, TypeError):
        return False


def verify(root, selection, catalog):
    from ..provenance import run_verifier
    return run_verifier(Path(__file__).with_name('razor_restoration_verifier.py'), __package__, root, selection, catalog)
