"""Load-only native readiness; the shared runner owns launch, audit and cleanup."""
from pathlib import Path
import json
import math
import re
import shutil
import zlib


def definitions():
    return {'startup': {'status': 'ready', 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
                        'cases': [{'id': 'loaded', 'producer': 'fixture', 'capability': 'effect',
                                   'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'],
                                   'modes': ['toolkit', 'native']}]}}


def validate(selection):
    if (selection.get('cases') != ['loaded'] or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('toolkit', 'native')
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or selection.get('languages') not in (['EN'], ['RU'])):
        raise ValueError('Startup requires loaded, SP/MP, native/toolkit and one EN/RU client')
    if selection['kind'] == 'sp' and selection.get('options', {}).get('world_template'):
        raise ValueError('Startup SP creates a fresh world; restored SP worlds are unsupported')
    options = selection.get('options', {})
    if 'startup_recovery_probe' in options:
        if (options['startup_recovery_probe'] is not True or selection['mode'] != 'toolkit'
                or not {'PZSurvivorToolkit', 'PeekAView', 'SaucedCarts'}.issubset(selection.get('mods', []))):
            raise ValueError('startup_recovery_probe requires Toolkit, Peek a View and SaucedCarts')
    if 'startup_world' in options:
        expected = options['startup_world']
        if (selection['kind'] != 'mp' or options.get('mp_host') is not True
                or not isinstance(expected, dict) or set(expected) not in ({'name'}, {'name', 'items', 'primary', 'secondary', 'worn'})
                or not isinstance(expected.get('name'), str) or not expected['name'].strip()
                or len(expected['name']) > 256 or not expected['name'].isprintable()):
            raise ValueError('startup_world requires a Host saved-character name and optional complete inventory witness')
        if 'items' in expected:
            _validate_witness(expected)
    if 'startup_connection' in options:
        connection = options['startup_connection']
        if (selection['kind'] != 'mp' or not isinstance(connection, dict)
                or set(connection) != {'username', 'password'}
                or not isinstance(connection['username'], str)
                or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}', connection['username'])
                or not isinstance(connection['password'], str) or not 1 <= len(connection['password']) <= 256
                or not connection['password'].isprintable()):
            raise ValueError('startup_connection requires MP, a safe username and a printable password of 1..256 characters')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    result = sorted((root / 'startup').rglob('*.lua'))
    if selection.get('options', {}).get('startup_world'):
        result += [root / 'support/QueueStartupWorld.lua', root / 'health/shared/QueueHealthEvents.lua']
    if selection.get('options', {}).get('startup_recovery_probe'):
        result += [root / 'support/QueueStartupRecoverySeed.lua', root / 'support/QueueStartupRecovery.lua']
    return result


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    runtime.setdefault('fixture', {})['server_ready'] = '[STARTUP_TEST] SERVER_READY'
    if selection.get('options', {}).get('startup_world'):
        destination = Path(runtime['roles']['client1']['cache']) / 'mods/ActionQueueTest/42/media/lua/shared'
        destination.mkdir(parents=True, exist_ok=True)
        root = Path(project) / 'tests/native_queue'
        for source in (root / 'support/QueueStartupWorld.lua', root / 'health/shared/QueueHealthEvents.lua'):
            shutil.copy2(source, destination / source.name)
    if selection.get('options', {}).get('startup_recovery_probe'):
        from ..native import _lua
        lua = Path(runtime['roles']['client1']['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for branch in ('client', 'shared'):
            (lua / branch).mkdir(parents=True, exist_ok=True)
        root = Path(project) / 'tests/native_queue/support'
        shutil.copy2(root / 'QueueStartupRecoverySeed.lua', lua / 'client/00000QueueStartupRecoverySeed.lua')
        shutil.copy2(root / 'QueueStartupRecovery.lua', lua / 'shared/QueueStartupRecovery.lua')
        before = ['tickbox|PeekAView|treeFadeActiveInVehicle|true', 'tickbox|PeekAView|fixB42Adjacency|true',
                  'keybind|SaucedCarts|PushCart|47', 'textentry|ToolkitRecoveryProbe|Note|retained',
                  'tickbox|AbsentRecoveryProbe|Enabled|false']
        checksum = zlib.adler32(('\n'.join(before) + '\n').encode())
        recovery = [f'PZST ModOptions recovery 1|{len(before)}|{checksum}', *before, f'SEALED|{checksum}']
        data = {'partial': 'keybind|SaucedCarts|PushCart|18\r\n', 'recovery': '\r\n'.join(recovery) + '\r\n'}
        (lua / 'shared/QueueStartupRecoveryConfig.lua').write_text('return ' + _lua(data) + '\n')


def _validate_witness(value):
    def item_id(value):
        return type(value) in (int, float) and math.isfinite(value) and value == int(value) and value != -1
    if (not isinstance(value.get('items'), list) or not isinstance(value.get('worn'), list)
            or any(type(value.get(slot)) is not bool and not item_id(value.get(slot)) for slot in ('primary', 'secondary'))
            or any(value.get(slot) is True for slot in ('primary', 'secondary'))):
        raise ValueError('Invalid saved-character inventory witness')
    ids = set()
    for row in value['items']:
        if (not isinstance(row, dict) or set(row) != {'id', 'fullType', 'parent', 'count'}
                or not item_id(row['id']) or row['id'] in ids
                or not isinstance(row['fullType'], str) or not row['fullType']
                or not item_id(row['count']) or row['count'] < 1
                or row['parent'] != 'root' and not item_id(row['parent'])):
            raise ValueError('Invalid saved-character item identity')
        ids.add(row['id'])
    if any(row['parent'] != 'root' and row['parent'] not in ids for row in value['items']):
        raise ValueError('Saved-character item parent is missing')
    parents = {row['id']: row['parent'] for row in value['items']}
    for item in ids:
        seen = set()
        while item != 'root':
            if item in seen:
                raise ValueError('Saved-character item ancestry is cyclic')
            seen.add(item)
            item = parents[item]
    if any(value[slot] is not False and value[slot] not in ids for slot in ('primary', 'secondary')):
        raise ValueError('Saved-character hand identity is missing')
    slots = set()
    for row in value['worn']:
        if (not isinstance(row, dict) or set(row) != {'id', 'location'} or not item_id(row['id'])
                or row['id'] not in ids or not isinstance(row['location'], str) or not row['location']
                or row['location'] in slots):
            raise ValueError('Invalid saved-character worn identity')
        slots.add(row['location'])


def _inventory(value):
    return {**value, 'items': sorted(value['items'], key=lambda row: row['id']),
            'worn': sorted(value['worn'], key=lambda row: row['location'])}


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[STARTUP_TEST\] COMPLETE case=loaded(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    issues, positions, witness = [], [], None
    try:
        text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
        patterns = [r'\[QUEUE_TEST\] ' + ('NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP') + r'(?:\s|$)',
                    r'\[QUEUE_TEST\] PREFLIGHT_COMPLETE mods=' + str(len(selection['mods'])) + ' mode=' + selection['mode'] + r'(?:\s|$)',
                    r'\[STARTUP_TEST\] GAME_START kind=' + selection['kind'] + ' mode=' + selection['mode'] + r'(?:\s|$)',
                    r'\[STARTUP_TEST\] PLAYER_READY square=-?\d+,-?\d+,-?\d+ tick=true(?:\s|$)',
                    r'\[STARTUP_TEST\] COMPLETE case=loaded(?:\s|$)']
        for pattern in patterns:
            matches = list(re.finditer(pattern, text))
            if len(matches) != 1:
                issues.append('Missing or duplicate startup readiness: ' + pattern)
            else:
                positions.append(matches[0].start())
        if positions != sorted(set(positions)):
            issues.append('Startup readiness preceded preflight or native game start')
        if '[QUEUE_TEST] FAIL ' in text:
            issues.append('Startup bootstrap/preflight failed')
        if selection.get('options', {}).get('startup_recovery_probe'):
            rows = list(re.finditer(r'\[STARTUP_TEST\] RECOVERY_READY preferences=true java=true cart=true(?:\s|$)', text))
            if len(rows) != 1 or len(positions) != len(patterns) or not positions[-2] < rows[0].start() < positions[-1]:
                issues.append('Native configuration recovery/preset evidence missing, duplicate or out of order')
        expected = selection.get('options', {}).get('startup_world')
        if expected:
            rows = list(re.finditer(r'\[STARTUP_TEST\] WORLD_WITNESS ([^\r\n]+)', text))
            if len(rows) != 1:
                issues.append('Missing or duplicate saved-character witness')
            else:
                try:
                    witness = json.loads(rows[0][1])
                    if not isinstance(witness, dict) or set(witness) != {'name', 'items', 'primary', 'secondary', 'worn'}:
                        raise ValueError('Invalid saved-character witness fields')
                    _validate_witness(witness)
                    if witness['name'] != expected['name'] or 'items' in expected and _inventory(witness) != _inventory(expected):
                        issues.append('Saved-character identity/inventory differs from its baseline')
                    if len(positions) == len(patterns) and not positions[-2] < rows[0].start() < positions[-1]:
                        issues.append('Saved-character witness is outside readiness/completion')
                except (ValueError, TypeError, KeyError) as error:
                    issues.append(str(error))
        if selection['kind'] == 'mp':
            server = (Path(root) / 'server-launch.log').read_text(errors='replace')
            if len(re.findall(r'\[STARTUP_TEST\] SERVER_READY(?:\s|$)', server)) != 1:
                issues.append('Missing or duplicate native server readiness')
    except OSError as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'loaded',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues),
            'outcome': {'loaded': not issues}}],
            'evidence': {'world_witness': witness, 'limits': [
                'Read-only character/inventory identity capture; no gameplay behavior is exercised.' if witness
                else 'Load-only player/square readiness; no gameplay behavior is exercised.']}}
