"""Native TV media/control receipts, exact new VHS identity and unrelated book tail."""
import json
import math
from pathlib import Path
import re
import shutil

from .. import report
from . import tv_controls as tv
from ..mod_selection import metadata, mod_ids

PROJECT = Path(__file__).resolve().parents[3]
MODS = mod_ids(metadata(PROJECT / 'SurvivorQoL-selected.ini')['Mods'])
CASES = ('eject-idle', 'eject-playing')
PREFIX = '[DEVICE_BINDING] '
ORIGINAL = ['front', 'volume', 'redundant', 'mute', 'unmute', 'channel', 'eject', 'tail']
EDITED = ['front', 'volume', 'mute', 'unmute', 'eject', 'channel', 'tail']
MODES = {'insert': '', 'play': 'TogglePlayMedia', 'front': '', 'volume': 'SetVolume',
         'redundant': 'SetVolume', 'mute': 'MuteVolume', 'unmute': 'UnMuteVolume',
         'channel': 'SetChannel', 'eject': '', 'tail': ''}


def definitions():
    checks = {name: {case: {'effectsVerified': True, 'tailCompleted': True,
                            'serverAuthorityVerified': True} for case in CASES}
              for name in ('success-queued', 'server-authority')}
    for name in ('move-independent', 'cancel-waiting'):
        checks[name] = {case: {'effectsVerified': True, 'pendingEditsVerified': True} for case in CASES}
    return {'device-binding': {'status': 'ready', 'clients': 1, 'default_mods': list(MODS),
        'scenario_actions': {'device-binding-controls': {'mods': list(MODS), 'checks': checks,
            'scope': 'Two same-square TVs; all native commands target the second while the first is checked unchanged. Two ordered full-selected-pack SP/menu-Host cases: native UI insertion and optional playback before baseline; eject across a channel setter and redundant pending volume cancellation only with queue enabled. Actual volume/mute/unmute/channel callbacks and two naturally completed root books. Exact new VHS ID/index/type, independent authoritative media/settings/pages and ordered native Host control receipts. Main adjacent TV requires no emitted walk. No late-loss/failure, physical input, video/audio rendering, arbitrary inventory output capacity or playback-toggle projection coverage implied.'}},
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       modes=['native', 'toolkit'], languages=['EN']) for case in CASES]}}


def validate(selection):
    spatial = selection.get('options', {}).get('tv_spatial_controls', False)
    if spatial is not False:
        raise ValueError('device binding does not support spatial controls')
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('TV controls require both ordered cases, full selected EN pack, fresh SP/menu Host and one client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted(path for path in (root / 'device-binding').rglob('*') if path.suffix in ('.lua', '.java')),
            *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            Path(__file__).resolve().parents[1] / 'placement.py']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL device-binding'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    if role != 'client1':
        return False
    try:
        values = _raw(text, 'COMPLETE')
        return len(values) == 1 and values[0].get('cases') == selection['cases']
    except (ValueError, TypeError):
        return False


def check_case(row, case, selection, prepared, authority_baseline, verified, acks):
    issues = tv.check_case(row, case, selection, prepared, authority_baseline, verified, acks)
    ids = row.get('ids', {})
    try:
        wrong, target = ids['wrong'], ids['tv']
        if (set(wrong) != {'x', 'y', 'z', 'index'} or any(type(v) is not int for v in wrong.values())
                or any(wrong[k] != target[k] for k in ('x', 'y', 'z'))
                or wrong['index'] < 0 or wrong['index'] >= target['index']):
            raise ValueError('invalid same-square first TV')
        for key in ('input', 'baseline', 'authorityBaseline', 'client', 'server'):
            value = row[key]['wrong']
            if (value['identity'] != wrong or value['on'] is not True or value['powerable'] is not True
                    or not tv._number(value['power']) or value['power'] <= 0
                    or not tv._close(value['volume'], .5) or value['channel'] != 90000
                    or value['hasMedia'] is not False or value['mediaIndex'] != -1 or value['playing'] is not False):
                raise ValueError('wrong-device state changed: ' + key)
    except (KeyError, TypeError, ValueError):
        issues.append('Same-square first TV identity or unchanged state differs')
    return issues


def _raw(text, marker):
    values = [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]
    if any(not isinstance(v, dict) for v in values): raise ValueError('Malformed TV raw ' + marker)
    return values


def verify(root, selection, catalog):
    root = Path(root);issues, outcomes = [], []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [r for r in report.events(text) if r.get('suite') == 'device-binding']
        rows = [r for r in events if r.get('event') == 'case']
        setups = [r for r in events if r.get('event') == 'setup']
        completions = [r for r in events if r.get('event') == 'complete']
        if (len(setups) != 1 or setups[0].get('cases') != selection['cases']
                or setups[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
                or setups[0].get('nativeDurations') is not True
                or len(completions) != 1 or completions[0].get('cases') != selection['cases']
                or completions[0].get('performed') != len(selection['cases'])
                or completions[0].get('failed') != 0 or completions[0].get('skipped') != 0):
            issues.append('Missing exact TV setup/completion gate')
        prepared, baseline, verified = (_raw(authority, m) for m in ('PREPARED', 'BASELINE', 'VERIFIED'))
        acks = _raw(text, 'ACK')
        placements = _raw(text, 'CLIENT_PLACEMENT')
        if [value.get('case') for value in placements] != selection['cases']:
            issues.append('Client TV placement missing, duplicated or out of order')
        if ([r.get('id') for r in rows] != selection['cases'] or any([r.get('case') for r in values] != selection['cases'] for values in (prepared, baseline, verified))):
            issues.append('TV case/authority evidence missing, duplicated or out of order')
        for i, case in enumerate(selection['cases']):
            row = rows[i] if i < len(rows) else {}
            errors = check_case(row, case, selection, prepared[i] if i < len(prepared) else None,
                                baseline[i] if i < len(baseline) else None, verified[i] if i < len(verified) else None,
                                [a for a in acks if a.get('case') == case])
            if i >= len(placements) or placements[i] != {'case': case, 'proof': row.get('clientPlacement')}:
                errors.append('Raw client TV placement differs from case proof')
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('TV actor/kind/mode differs')
            issues += [case + ': ' + e for e in errors]
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors, tailCompleted=not errors, serverAuthorityVerified=not errors,
                             pendingEditsVerified=not errors and selection['mode'] == 'toolkit')))
        if any(a.get('case') not in selection['cases'] for a in acks): issues.append('Unknown-case TV wire receipt')
        if not complete(selection, 'client1', text): issues.append('Missing unique TV completion marker')
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        issues.append('TV verifier ' + type(error).__name__ + ': ' + str(error))
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Native UI callbacks are invoked programmatically; no physical input, audio or video rendering claim.',
        'Adjacent powered TV, exact retail VHS and two native root books in one-client full-pack SP/menu Host.',
        'The second TV is selected on a square containing a first TV; both are checked on the authority.']}}
