"""Grouped native root-magazine unload controls with exact ammo identity receipts."""
import json
from pathlib import Path
import re
import shutil
import zlib

from ..mod_selection import lua_sources
from .tv_controls import MODS

CASES = ('direct', 'bulk')
NAMES = ('front', 'target', 'cancelled', 'tail', 'unrelated')
LOADS = dict(front=5, target=3, cancelled=4, tail=2, unrelated=6)
AMMO = 'Base.Bullets9mm'
OTHER = 'Base.ShotgunShells'
PREFIX = '[MAGAZINE_UNLOAD] '
PRODUCERS = dict(direct='native ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine',
                 bulk='BulkFirearms.unloadEntries + queueUnload')
NATIVE_CRC = {
    'media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua': 641621167,
    'media/lua/shared/TimedActions/ISReloadWeaponAction.lua': 547021931,
    'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua': 2574700613,
}
SELECTED_CRC = {'CleanUI': ('ISInventoryPaneContextMenu.lua', 2066944516),
                'P4TidyUpMeister': ('P4TidyUpMeister.lua', 945150908)}


def definitions():
    effects = {case: dict(effectsVerified=True, serverAuthorityVerified=True, tailCompleted=True) for case in CASES}
    edits = {case: dict(effectsVerified=True, pendingEditsVerified=True) for case in CASES}
    return {'magazine-unload': dict(status='ready', clients=1, default_mods=list(MODS),
        scenario_actions={'native-magazine-unload': dict(mods=list(MODS),
            checks={'success-queued': effects, 'server-authority': effects, 'cancel-waiting': edits, 'move-independent': edits},
            toolkit_only=['cancel-waiting', 'move-independent'],
            scope='Grouped full selected pack fresh SP/menu Host direct native inventory callback and public BulkFirearms unloadEntries/queueUnload controls. Plain exact root magazines, natural -1-duration native animation/server loops, untouched native callbacks and only the exact owned bulk start guard. Queue-on cancels a waiting loaded magazine and moves independent tail before target while front is active. Separately requested same-front repeats constructed while loaded must enter native start at zero, finish native perform without extra debit/output, and preserve the independent tail; read-only Lifecycle receipts identify actual native episodes (SP complete, Host perform plus server authority). Native starts and partial loaded-count progress for nonempty commands, final canonical magazine identities, authoritative new ammo IDs and per-output uses1, exact loose-plus-loaded round conservation, unchanged baseline/unrelated inputs and independent tail. Loose round units use getCurrentUses; getCount is factory metadata and is never multiplied into output credit. No active edits, recovery, group fetch, future output capacity authority or physical-input coverage.')},
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'], modes=['native', 'toolkit'], languages=['EN']) for case in CASES])}


def validate(selection):
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp', 'mp')
        or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
        or type(selection.get('clients')) is not int or selection['clients'] != 1 or selection.get('mods') != MODS
        or selection.get('options', {}).get('world_template')
        or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Magazine unload requires ordered direct/bulk cases, fresh full-selected-pack SP/menu Host and one EN client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'magazine-unload').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            *verifier_sources(project, selection)]


def audit_native(game):
    result = {}
    for relative, expected in NATIVE_CRC.items():
        actual = zlib.crc32((Path(game) / relative).read_bytes())
        if actual != expected: raise ValueError('Magazine native source audit requires review: ' + relative)
        result[relative] = actual
    return result


def audit_selected(locations):
    result = {}
    for identifier, (name, expected) in SELECTED_CRC.items():
        files = [path for path in lua_sources(Path(locations[identifier])) if path.name == name]
        if len(files) != 1 or zlib.crc32(files[0].read_bytes()) != expected:
            raise ValueError('Magazine selected producer audit requires review: ' + identifier)
        result[identifier] = expected
    return result


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection); audit = audit_native(game); audit.update(audit_selected(locations))
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL magazine-unload'], native_magazine_audit=audit, sandbox={'Zombies': 6})


def _raw(text, marker):
    return [json.loads(match.group(1)) for match in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]


def complete(selection, role, text):
    return role == 'client1' and _raw(text, 'COMPLETE') == [dict(cases=list(CASES))]


def verifier_sources(project, selection):
    return [Path(__file__).with_name('magazine_unload_verifier.py'), Path(__file__).parents[1] / 'placement.py',
            Path(project) / 'tests/test_queue_magazine_unload.py']


def check_case(row, selection, prepared, verified):
    from .magazine_unload_verifier import check_case as check
    return check(row, selection, prepared, verified)


def verify(root, selection, catalog):
    from ..provenance import run_verifier
    return run_verifier(Path(__file__).with_name('magazine_unload_verifier.py'), __package__, root, selection, catalog)
