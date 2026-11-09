"""Opt-in native book control bank: exact source, real Panel gesture and authority effects."""
import json
import os
from .. import preparation_process
import zipfile
from pathlib import Path
import re
import shutil

from .tv_controls import MODS


SOURCES = ('root', 'worn-bag', 'world')
CONTROLS = ('header-cancel', 'reader-child-cancel', 'move-equip', 'move-volume')
CASES = tuple(source + '.' + control for source in SOURCES for control in CONTROLS) + tuple(source + '.return-child-cancel' for source in SOURCES if source != 'root')
CAPACITY_CASES = tuple(source + '.' + control + '-capacity-lost' for source in SOURCES if source != 'root' for control in ('header-cancel', 'move-volume'))
FAVORITE_CASES = ('world.header-cancel-favorite', 'world.move-volume-favorite')
PROMOTE_DEVICE_ONLY_CASES = tuple(source + '.move-volume-device-only' for source in SOURCES)
DEMOTE_DEVICE_ONLY_CASES = tuple(source + '.demote-reader-device-only' for source in SOURCES)
DEVICE_ONLY_CASES = PROMOTE_DEVICE_ONLY_CASES + DEMOTE_DEVICE_ONLY_CASES
CASES += CAPACITY_CASES + FAVORITE_CASES
DECLARED_CASES = CASES + DEVICE_ONLY_CASES
PREFIX = '[BOOK_CONTROLS] '
ACTIVE_EDIT_CASES = tuple(source + '.header-cancel' for source in SOURCES)


GAME_INPUTS = (
    'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua',
    'media/lua/shared/TimedActions/ISReadABook.lua',
    'media/lua/shared/TimedActions/ISBaseTimedAction.lua',
    'media/lua/client/TimedActions/ISInventoryTransferAction.lua',
    'media/lua/shared/TimedActions/ISTransferAction.lua',
    'media/lua/shared/TimedActions/ISEquipWeaponAction.lua',
    'media/lua/shared/RadioCom/ISRadioAction.lua',
    'media/lua/client/RadioCom/RadioWindowModules/RWMVolume.lua',
    'media/lua/client/RadioCom/RadioWindowModules/RWMPanel.lua',
    'media/lua/client/ISUI/ISScrollingListBox.lua',
    'media/lua/client/TimedActions/ISTimedActionQueue.lua',
    'media/scripts/generated/items/container.txt',
)


def definitions():
    checks = {name: {case: dict(effectsVerified=True, serverAuthorityVerified=True) for case in DECLARED_CASES}
              for name in ('success-queued', 'server-authority')}
    return {'book-controls': dict(status='ready', clients=1, default_mods=list(MODS), game_inputs=list(GAME_INPUTS),
        scenario_actions={'source-bound-book-controls': dict(checks=checks,
            scope='Opt-in ordered twenty-case source/control bank. Carpentry skillbook from root, worn military bag or direct world shelf, with explicit mode-specific favorite-world probes; native onLiteratureItems/readItem owns pickup/read/return. Real Panel hit-tested singleton/header/reader-child cross, exact optional-return child cancellation that keeps reading and the book carried, or pending native Pen equip/TV RWM SetVolume drag before the progressed active reader. Empty authority hands and exact root Pen expose unrelated equipment/borrowed-return interactions. Queue-off controls run unchanged native producers naturally. Fresh reader and saved page, old Java drain, exact returned item/container, final explicit Pen hand intent, native durations/callback identity, Host equipment/radio outcomes, full inventory/worn/hands/appearance snapshots and independent native reader tail. All functional control denials are collected through normal native clear/drain, then the aggregate fails. One EN actor, full selected pack, disposable macOS SP/menu Host. Programmatic widget gestures, no physical pointer/rendering claim.')},
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'], modes=['native', 'toolkit'], languages=['EN']) for case in DECLARED_CASES])}


def selected_cases(selection):
    cases = selection.get('cases')
    if (not isinstance(cases, list) or not cases or any(not isinstance(case, str) or case not in DECLARED_CASES for case in cases)
            or len(set(cases)) != len(cases) or cases != [case for case in DECLARED_CASES if case in cases]):
        raise ValueError('Book controls require a nonempty unique ordered subset of the declared cases')
    return cases


def validate(selection):
    if type(selection.get('options', {}).get('precise_timing', False)) is not bool:
        raise ValueError('precise_timing must be boolean')
    requests = selection.get('options', {}).get('require_native_requests', False)
    if type(requests) is not bool:
        raise ValueError('require_native_requests must be boolean')
    flag = selection.get('options', {}).get('require_native_bindings', False)
    if type(flag) is not bool:
        raise ValueError('require_native_bindings must be boolean')
    extended = selection.get('options', {}).get('require_extended_native_bindings', False)
    if type(extended) is not bool or extended and flag is not True:
        raise ValueError('require_extended_native_bindings requires boolean true require_native_bindings')
    active = selection.get('options', {}).get('active_edit_observation', False)
    if type(active) is not bool:
        raise ValueError('active_edit_observation must be boolean')
    cases = selected_cases(selection)
    if any(case in DEVICE_ONLY_CASES for case in cases) and not active:
        raise ValueError('device-only variants require active_edit_observation=true')
    if active and (selection.get('options', {}).get('precise_timing') is not True
                   or not any(case in ACTIVE_EDIT_CASES + DEVICE_ONLY_CASES for case in cases)):
        raise ValueError('active_edit_observation requires precise_timing=true and at least one exact header-cancel or device-only case')
    if (selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('book_controls') is not True
            or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Book controls require book_controls=true, an ordered nonempty case selection, full selected EN pack, fresh SP/menu Host and one client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    code = Path(project) / 'PZSurvivorToolkit/42/media/lua'
    return [Path(__file__).with_name('tv_controls.py'), Path(__file__).parents[1] / 'mod_selection.py',
            *sorted(path for path in (root / 'book-controls').rglob('*') if path.suffix in ('.lua', '.java')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            code / 'client/PZSurvivorToolkit/ActionQueuePanel.lua', code / 'client/PZSurvivorToolkit/ActionQueueProjection.lua',
            code / 'shared/PZSurvivorToolkit/SourceProof.lua']


def _stop_probe(project, output, game, jdk):
    classes = Path(output) / 'book-stop-probe/classes'
    classes.mkdir(parents=True)
    classpath = os.pathsep.join(str(Path(game) / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar'))
    preparation_process.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', classpath, '-d', str(classes),
                    str(Path(project) / 'tests/native_queue/book-controls/java/Main.java')],
                   check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted(classes.rglob('*.class'))
    if not compiled:
        raise ValueError('Book stop observation probe compilation produced no classes')
    jar = classes.parent / 'BookControlsStopProbe.jar'
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in compiled:
            archive.write(path, path.relative_to(classes).as_posix())
    return jar


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    probe = _stop_probe(project, output, game, jdk)
    runtime.setdefault('fixture', {}).setdefault('mods', []).append('BookControlsStopProbe')
    for role in runtime['roles'].values():
        layer = Path(role['cache']) / 'mods/BookControlsStopProbe/42'
        (layer / 'media/java').mkdir(parents=True, exist_ok=True)
        (layer / 'mod.info').write_text('name=Disposable book stop observation probe\nid=BookControlsStopProbe\nversionMin=42.21\n'
                                      'require=\\ZombieBuddy\njavaPkgName=net.alexredby.bookcontrolsprobe\n'
                                      'javaJarFile=media/java/BookControlsStopProbe.jar\n')
        shutil.copy2(probe, layer / 'media/java/BookControlsStopProbe.jar')
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for package in ('book-controls', 'startup'):
            for path in sorted((root / package).rglob('*.lua')):
                target = lua / path.relative_to(root / package)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
        for path in (root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua'):
            target = lua / 'shared' / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL book-controls'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def raw(text, marker):
    return [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]


def complete(selection, role, text):
    """A complete diagnostic bank terminates even when feature cases were denied."""
    try:
        values = raw(text, 'COMPLETE')
        return (role == 'client1' and len(values) == 1 and values[0].get('cases') == selected_cases(selection)
                and type(values[0].get('failed')) is int and 0 <= values[0]['failed'] <= len(selected_cases(selection)))
    except (ValueError, TypeError):
        return False


def verifier_sources(project, selection):
    return [Path(__file__).with_name('book_controls_verifier.py'), Path(__file__).parents[1] / 'placement.py',
            Path(project) / 'tests/test_queue_book_controls.py']


def verify(root, selection, catalog):
    from ..provenance import run_verifier
    return run_verifier(Path(__file__).with_name('book_controls_verifier.py'), __package__, root, selection, catalog)
