"""Native wring UI producer, exact clothing identity and authoritative wetness caps."""
import json
from pathlib import Path
import re
import shutil
import zlib

from ..mod_selection import lua_sources
from .tv_controls import MODS

CASES = ('root', 'worn-prepared', 'wear-swap', 'worn', 'worn-bag', 'world')
CONTROL_CASES = ('worn-bag-keep', 'worn-bag-full')


def base_case(case):
    return 'worn-bag' if case in CONTROL_CASES else case

NAMES = ('front', 'target', 'tail', 'cancelled')
PREFIX = '[WRING_CLOTHING] '
PRODUCER = 'native ISInventoryPaneContextMenu.onWringClothing'
NATIVE_CRC = {
    'media/scripts/generated/items/clothing.txt': 3753683896,
    'media/lua/shared/NPCs/BodyLocations.lua': 2265789823,
    'media/lua/shared/TimedActions/ISWringClothing.lua': 2805730431,
    'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua': 2574700613,
    'media/lua/shared/TimedActions/ISUnequipAction.lua': 2061668308,
    'media/lua/shared/TimedActions/ISWearClothing.lua': 3766730028,
    'media/lua/client/TimedActions/ISInventoryTransferAction.lua': 3908838083,
}
PROFILE_CRC = {'media/scripts/generated/items/normal.txt': 1928498276, 'media/scripts/generated/items/container.txt': 2378263796}
SELECTED_CRC = {'CleanUI': ('ISInventoryPaneContextMenu.lua', 2066944516),
                'P4TidyUpMeister': ('P4TidyUpMeister.lua', 945150908),
                'SaucedCarts': ('ContainerRestrictions.lua', 442705836)}


def definitions():
    checks = {case: dict(effectsVerified=True, serverAuthorityVerified=True, tailCompleted=True) for case in (*CASES, *CONTROL_CASES)}
    edits = {case: dict(effectsVerified=True, pendingEditsVerified=True) for case in ('root','worn-bag','worn-prepared','wear-swap',*CONTROL_CASES)}
    return {'wring-clothing': dict(status='ready', clients=1, default_mods=list(MODS),
        scenario_actions={'native-wring-clothing': dict(mods=list(MODS),
            checks={'success-queued': checks, 'server-authority': checks, 'cancel-waiting': {case:value for case,value in edits.items() if case!='wear-swap'},
                    'move-independent': edits, 'move-dependent': {'root': edits['root']}},
            toolkit_only=['cancel-waiting', 'move-independent', 'move-dependent'],
            scope='Grouped full selected pack fresh SP/menu Host controls. Native inventory context-menu producer with root, worn, worn-bag and adjacent furniture clothing; real durations, untouched callbacks, exact identities/source counts and authoritative wetness caps with bounded passive drying. Current B42 ItemBodyLocation userdata fails the native legacy string comparison even for shoes, so real socks and shoes both cap at10; prepared and final receipts prove the exact native predicate, class and location. Selected Tidy Up Meister restores borrowed items to their exact original source; worn clothing stays unequipped. Host worn and worn-bag setup uses a real own-client native wear before a strict server canonical-identity baseline; Default SP setup is unchanged; optional capacity profiling uses a genuine native bag Wear baseline in SP as well. Independent front and tail wrings on other clothes. Queue-on root pending cancellation and independent moves; same ordinary-clothing dependency denial. Carried worn-bag uses genuine Operations.run producer groups: enabled source-owned deferred container prep/fetch/wring (disabled native fetch/wring), source-bound no-position-effect lease, real resolver with no unexpected walking children, pending full-group cancellation and fetch/body-selected whole-group move/restore, exact source->root descriptors and native/P4 return. UI Clothing.getWeight wet interpolation is observed separately from native capacity. Source-bound nonincrease traversal preserves the current native getUnequippedWeight bound and external/native admission, with no drying credit. Selectable worn-prepared uses genuine native wear of distinct cotton scarf/leather gloves before a canonical authority baseline, then Operations.run native unequip/wring groups with pending whole-group cancellation and unequip/body-selected moves. Executed items stay unworn; cancelled clothing stays worn, with exact unchanged other slots/hands, native capacity weights and server clothing-update transitions. Selectable wear-swap natively replaces fixture-owned heavier BurlapWrap gloves with light leather gloves, preserves a scarf in another slot, proves positive native load delta and exact displaced/root/incoming/worn identities, then source-owned freshness refusal or child-selected retained Unequip/Wring moves, exact saved terminal Ack at the canonical permission boundary during the real front, and final canonical physical outcome/freshness. This case has no cancellation claim; that remains worn-prepared. Optional profile_capacity on worn-bag adds exact native Nails instances and coarse idle wall-clock samples of legacy versus numeric-zero qualified capacity on the real Java-backed player inventory. No performance threshold, FPS claim or inventory-size extrapolation. Historical worn/world groups retain execution-only scope. Opt-in P4-free carried Keep and authority capacity-loss cases preserve the native body and independent tail, with explicit blocked-debt Keep after refusal. Detached-source and later explicit-intent controls and magazine moves remain outside this bank. No active edits, recovery or physical input coverage.')},
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'], modes=['native', 'toolkit'], languages=['EN']) for case in (*CASES, *CONTROL_CASES)])}


def validate(selection):
    chosen = selection.get('cases')
    provider = selection.get('options', {}).get('wring_restoration_provider', 'selected')
    if not isinstance(provider, str) or provider not in ('selected', 'native-returns'):
        raise ValueError('wring_restoration_provider must be selected or native-returns')
    if provider == 'native-returns' and (not isinstance(chosen, list) or not chosen or any(base_case(case) != 'worn-bag' for case in chosen)):
        raise ValueError('native-returns requires carried wring cases')
    if provider != 'native-returns' and isinstance(chosen, list) and any(case in CONTROL_CASES for case in chosen):
        raise ValueError('return controls require native-returns')
    mods = MODS if provider == 'selected' else [mod for mod in MODS if mod != 'P4TidyUpMeister']
    profile = selection.get('options', {}).get('profile_capacity', False)
    if type(profile) is not bool or profile and (type(chosen) is not list or 'worn-bag' not in chosen or any(case in CONTROL_CASES for case in chosen)):
        raise ValueError('Capacity profiling requires profile_capacity boolean and selected worn-bag')
    if (type(chosen) is not list or not chosen or chosen != [case for case in (*CASES, *CONTROL_CASES) if case in chosen] or selection.get('kind') not in ('sp', 'mp')
        or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
        or type(selection.get('clients')) is not int or selection['clients'] != 1 or selection.get('mods') != mods
        or selection.get('options', {}).get('world_template')
        or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Wring clothing requires ordered grouped cases, fresh full-selected-pack SP/menu Host and one EN client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'wring-clothing').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            *verifier_sources(project, selection)]


def audit_native(game, profile=False):
    """Gate the actual installed producer, native durations, caps and prep actions."""
    result = {}
    for relative, expected in {**NATIVE_CRC, **(PROFILE_CRC if profile else {})}.items():
        actual = zlib.crc32((Path(game) / relative).read_bytes())
        if actual != expected:
            raise ValueError('Wring native source audit requires review: ' + relative)
        result[relative] = actual
    return result


def audit_selected(locations, provider='selected'):
    result = {}
    for identifier, (name, expected) in SELECTED_CRC.items():
        if provider == 'native-returns' and identifier == 'P4TidyUpMeister':
            continue
        selected = [path for path in lua_sources(Path(locations[identifier])) if path.name == name]
        if len(selected) != 1 or zlib.crc32(selected[0].read_bytes()) != expected:
            raise ValueError('Wring selected producer/restore audit requires review: ' + identifier)
        result[identifier] = expected
    return result


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    audit = audit_native(game, selection.get('options', {}).get('profile_capacity', False))
    audit.update(audit_selected(locations, selection.get('options', {}).get('wring_restoration_provider', 'selected')))
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL wring-clothing'], native_wring_audit=audit, sandbox={'Zombies': 6})


def _raw(text, marker):
    return [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]


def complete(selection, role, text):
    return role == 'client1' and _raw(text, 'COMPLETE') == [dict(cases=selection['cases'])]


def verifier_sources(project, selection):
    return [Path(__file__).with_name('wring_clothing_verifier.py'), Path(__file__).parents[1] / 'placement.py',
            *[Path(project) / 'tests' / name for name in ('test_queue_wring_clothing.py',
                'test_queue_wring_fixture_diagnostics.py', 'test_queue_wring_verifier_diagnostics.py',
                'test_queue_wring_control_fixture.py', 'test_queue_wring_return_controls.py')]]


def _counts(case, name, final):
    from .wring_clothing_verifier import _counts as counts
    return counts(case, name, final)


def check_case(row, selection, prepared, verified, wear_baseline=None):
    from .wring_clothing_verifier import check_case as check
    return check(row, selection, prepared, verified, wear_baseline)


def verify(root, selection, catalog):
    from ..provenance import run_verifier
    return run_verifier(Path(__file__).with_name('wring_clothing_verifier.py'), __package__, root, selection, catalog)
