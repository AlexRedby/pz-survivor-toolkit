"""Pending world-radio edits with real setters and separate local/network receipts."""
import json
import math
from pathlib import Path
import re
import shutil

from .. import report
from ..mod_selection import metadata, mod_ids

MODS = mod_ids(metadata(Path(__file__).resolve().parents[3] / 'SurvivorQoL-selected.ini')['Mods'])
CASES = ('reorder', 'cancel', 'barrier')
PREFIX = '[RADIO_SETTINGS] '


def definitions():
    checks = {
        'success-queued': {case: {'effectsVerified': True, 'pendingRequestsVerified': True} for case in CASES},
        'repeat-same': {'reorder': {'effectsVerified': True, 'pendingRequestsVerified': True}},
        'move-independent': {'reorder': {'effectsVerified': True, 'pendingEditsVerified': True}},
        'move-dependent': {'barrier': {'effectsVerified': True, 'pendingEditsVerified': True}},
        'cancel-waiting': {'cancel': {'effectsVerified': True, 'pendingEditsVerified': True}},
        'server-authority': {case: {'effectsVerified': True, 'serverAuthorityVerified': True} for case in CASES},
    }
    return {'radio-settings': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
        'scenario_actions': {'world-radio-settings': {'mods': MODS, 'checks': checks,
            'scope': 'Native RWM callbacks on two adjacent mains-powered world radios. Reorder repeated volume and independent microphone/channel setters, cancel pending volume/microphone setters, and retain the native channel-before-power-off dependency (followed by power restoration and mute). Native controls execute the original order. Host authority covers volume/channel; world-device microphone mute is a native client-local field.'}},
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                      modes=['native', 'toolkit'], languages=['EN']) for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (not isinstance(cases, list) or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('languages') != ['EN'] or type(selection.get('clients')) is not int
            or selection['clients'] != 1 or selection.get('mods') != MODS
            or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Radio settings require ordered cases, fresh full-selected-pack SP/menu Host and one EN client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'radio-settings').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL radio-settings'], sandbox={'Zombies': 6})


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(PREFIX) + r'COMPLETE(?:\s|$)', text)) == 1


def _close(actual, expected):
    return type(actual) in (int, float) and math.isfinite(actual) and abs(actual - expected) < .0001


def _receipt(value, ids, case, mode, server=False):
    if (not isinstance(value, dict) or value.get('case') != case
            or not isinstance(value.get('devices'), dict) or set(value['devices']) != {'a', 'b'}):
        return False
    for name, row in value['devices'].items():
        if not isinstance(row, dict) or set(row) != {'x', 'y', 'z', 'index', 'volume', 'channel', 'micMuted', 'on', 'powered'}:
            return False
        if any(type(row.get(key)) is not int or row[key] != ids[name][key] for key in ('x', 'y', 'z', 'index')):
            return False
        volume = .25 if name == 'b' else 0 if case == 'barrier' else .25 if mode == 'toolkit' else .75
        channel = 96000 if name == 'b' else 95000
        mute = name == 'a' and not server and case != 'barrier' and (case != 'cancel' or mode == 'native')
        if (not _close(row['volume'], volume) or type(row['channel']) is not int or row['channel'] != channel
                or row['micMuted'] is not mute or row['on'] is not True or row['powered'] is not True):
            return False
    return True


def _raw(text, marker):
    rows = [json.loads(match.group(1)) for match in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]
    if any(not isinstance(row, dict) for row in rows):
        raise ValueError('Invalid radio authority record: ' + marker)
    return rows


def check_case(row, case, selection, prepared, verified):
    issues = []
    mode = selection['mode']
    ids = row.get('ids', {})
    if (row.get('status') != 'passed' or row.get('queueIdle') is not True
            or type(row.get('settleMilliseconds')) not in (int, float)
            or not math.isfinite(row['settleMilliseconds']) or row['settleMilliseconds'] < 500):
        issues.append('Missing completed native execution and idle settling')
    if (not isinstance(ids, dict) or set(ids) != {'case', 'mode', 'a', 'b'} or ids.get('case') != case
            or ids.get('mode') != mode or prepared != ids):
        issues.append('Preparation does not match authoritative case/device identities')
    try:
        for name in ('a', 'b'):
            if (not isinstance(ids[name], dict) or set(ids[name]) != {'x', 'y', 'z', 'index'}
                    or any(type(v) is not int for v in ids[name].values())
                    or ids[name]['index'] < 0):
                raise ValueError('invalid world identity')
        if ids['a']['x'] - ids['b']['x'] != 2 or any(ids['a'][k] != ids['b'][k] for k in ('y', 'z')):
            raise ValueError('radios are not adjacent to the common player square')
    except (KeyError, TypeError, ValueError):
        return issues + ['Invalid exact radio identities']
    specs = [('anchor', 'SetVolume', 'b', .25), ('firstVolume', 'SetVolume', 'a', .25)]
    if case == 'barrier':
        specs += [('channel', 'SetChannel', 'a', 95000), ('powerOff', 'ToggleOnOff', 'a', None),
                      ('powerOn', 'ToggleOnOff', 'a', None), ('legacyMute', 'MuteVolume', 'a', True)]
    else:
        specs += [('channel', 'SetChannel', 'a', 95000), ('lastVolume', 'SetVolume', 'a', .75),
                  ('mic', 'MuteMicrophone', 'a', True)]
    specs += [('tail', 'SetChannel', 'b', 96000)]
    original = [s[0] for s in specs]
    cancelled = ['lastVolume', 'mic'] if mode == 'toolkit' and case == 'cancel' else []
    expected = ([name for name in original if name not in cancelled] if case != 'reorder' or mode != 'toolkit'
                else ['anchor', 'lastVolume', 'firstVolume', 'mic', 'channel', 'tail'])
    if row.get('initialQueue') != original or row.get('editedQueue') != expected or row.get('order') != expected:
        issues.append('Native dispatch/edit/start order differs')
    commands = row.get('commands', [])
    if not isinstance(commands, list) or len(commands) != len(specs):
        issues.append('Missing exact native commands')
    else:
        for command, (name, action, target, value) in zip(commands, specs):
            removed = name in cancelled
            if (not isinstance(command, dict) or command.get('name') != name or command.get('mode') != action
                    or command.get('target') != target or type(command.get('value')) is not type(value)
                    or command['value'] != value or command.get('producer') != 'native RWM callback'
                    or not _close(command.get('duration'), 30) or command.get('started') is not (not removed)
                    or command.get('progress') is not (not removed) or command.get('cancelled') is not removed
                    or not removed and (type(command.get('effectiveDuration')) not in (int, float)
                                        or not math.isfinite(command['effectiveDuration']) or command['effectiveDuration'] <= 0
                                        or type(command.get('nativeDurationExpected')) not in (int, float)
                                        or not math.isfinite(command['nativeDurationExpected'])
                                        or abs(command['effectiveDuration'] - command['nativeDurationExpected']) >= .001
                                        or type(command.get('startedAt')) not in (int, float)
                                        or not math.isfinite(command['startedAt']))):
                issues.append('Native command/duration/cancellation evidence differs: ' + name)
    edit = row.get('edit', {})
    if (not isinstance(edit, dict) or edit.get('untouchedBefore') is not True or edit.get('nativeDurations') is not True
            or edit.get('reordered') is not (mode == 'toolkit' and case == 'reorder')
            or edit.get('cancelled') != cancelled or edit.get('denied') is not (mode == 'toolkit' and case == 'barrier')
            or mode == 'toolkit' and case == 'barrier'
            and (not isinstance(edit.get('reason'), str) or not edit['reason'].strip())):
        issues.append('Missing exact edit or unchanged-state evidence')
    before = edit.get('before', {}) if isinstance(edit, dict) else {}
    initial = before.get('devices', {}) if isinstance(before, dict) else {}
    if not isinstance(before, dict) or before.get('case') != case or not isinstance(initial, dict) or set(initial) != {'a', 'b'}:
        issues.append('Missing pre-edit native device snapshots')
    else:
        for name, value in initial.items():
            if (not isinstance(value, dict) or any(value.get(k) != ids[name][k] for k in ('x', 'y', 'z', 'index'))
                    or not _close(value.get('volume'), .5) or value.get('channel') != 90000
                    or value.get('micMuted') is not False or value.get('on') is not True or value.get('powered') is not True):
                issues.append('Device mutated before pending edits: ' + name)
    if not _receipt(row.get('client'), ids, case, mode):
        issues.append('Client native radio effects differ')
    if row.get('server') != verified or not _receipt(verified, ids, case, mode, selection['kind'] == 'mp'):
        issues.append('Authoritative radio effects/identity differ')
    return issues


def verify(root, selection, catalog):
    root = Path(root)
    issues, outcomes = [], []
    try:
        client = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
        rows = [r for r in report.events(client) if r.get('suite') == 'radio-settings' and r.get('event') == 'case']
        prepared, verified = _raw(authority, 'PREPARED'), _raw(authority, 'VERIFIED')
        if [r.get('id') for r in rows] != selection['cases']:
            issues.append('Radio case evidence missing, duplicated or out of order')
        if [r.get('case') for r in prepared] != selection['cases'] or [r.get('case') for r in verified] != selection['cases']:
            issues.append('Authoritative preparation/results missing, duplicated or out of order')
        for index, case in enumerate(selection['cases']):
            row = rows[index] if index < len(rows) else {}
            errors = check_case(row, case, selection, prepared[index] if index < len(prepared) else None,
                                verified[index] if index < len(verified) else None)
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('Case actor/kind/mode differs')
            issues += [case + ': ' + error for error in errors]
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                                 outcome=dict(effectsVerified=not errors, pendingRequestsVerified=not errors,
                                              pendingEditsVerified=not errors and selection['mode'] == 'toolkit',
                                              serverAuthorityVerified=not errors)))
        if not complete(selection, 'client1', client):
            issues.append('Missing unique radio-settings completion')
    except (OSError, ValueError, TypeError, KeyError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': outcomes,
            'evidence': {'limits': ['Programmatic native RWM callbacks, not physical input or UI rendering.',
                'One EN client in full-pack SP/menu Host. Host authority covers volume/channel; native world-radio microphone mute remains client-local.']}}
