"""Qualify declared VSO settings at real SP/client/server initialization boundaries."""
from pathlib import Path
import shutil

from .. import receipts

SUITE = 'vro-settings'
MARKER = '[VRO_SETTINGS] '
PATCH_MARKER = '[PZToolkitJavaPatches] VRO salvage sandbox compiler input corrected'
MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'VehicleRepairOverhaul', 'VehicleSalvageOverhaulB42']
SANDBOX = {'VSO_EnableFullVehicleSalvaging': False, 'VSO_SalvageTime_Doors': 120}


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                   'cases': [{'id': 'custom-controls', 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit', 'native']}]}}


def validate(selection):
    options = selection.get('options', {})
    if (selection.get('cases') != ['custom-controls'] or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('toolkit', 'native')
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or selection.get('languages') != ['EN'] or not set(MODS).issubset(selection.get('mods', []))
            or options.get('world_template') or options.get('seed_run')
            or selection['kind'] == 'mp' and options.get('mp_host') is not True):
        raise ValueError('VRO settings requires fresh one-client EN SP/menu Host with both VRO modules and Java Patches')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'startup/server/ZZStartupServer.lua', 'server'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared')]:
            target = lua / side / source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            if selection['kind'] == 'sp' and source.name == 'ZZStartup.lua':
                text = target.read_text()
                anchor = "  getSandboxOptions():getOptionByName('Zombies'):setValue(6);getSandboxOptions():toLua()"
                if text.count(anchor) != 1:
                    raise ValueError('Common SP sandbox initialization changed')
                settings = "\n".join("  getSandboxOptions():getOptionByName('" + key + "'):setValue("
                                     + ('false' if value is False else str(value)) + ')' for key, value in SANDBOX.items())
                target.write_text(text.replace(anchor, anchor + '\n' + settings + '\n  getSandboxOptions():toLua()'))
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY',
                          'failure_markers': [MARKER + 'FAIL '], 'sandbox': {'Zombies': 6, **SANDBOX}}


def complete(selection, role, text):
    return receipts.records(text, MARKER, 'COMPLETE') == [{'case': 'custom-controls', 'role': role}]


def expected(role):
    return {'role': role, 'optionEnabled': False, 'optionTime': 120,
            'luaEnabled': False, 'luaTime': 120, 'legacyAbsent': True,
            'effectiveEnabled': False, 'effectiveTime': 120, 'recipeTime': 120}


def matches(rows, role):
    wanted = expected(role)
    return (len(rows) == 1 and set(rows[0]) == set(wanted)
            and all(type(rows[0][key]) is type(value) and rows[0][key] == value for key, value in wanted.items()))


def verify(root, selection, catalog):
    issues = []
    roles = ['client1'] if selection['kind'] == 'sp' else ['server', 'client1']
    for role in roles:
        try:
            text = (Path(root) / (role + '-launch.log')).read_text(errors='replace')
            # Native Lua environments may load the helper more than once. Host
            # forwarding of child output is not evidence for the client's hook.
            own_lines = [line for line in text.splitlines() if 'SERVER:' not in line and '[CoopMaster]' not in line]
            own_text = '\n'.join(own_lines)
            if not any(line.rstrip().endswith(PATCH_MARKER) for line in own_lines):
                issues.append(role + ': missing owned VRO compiler correction')
            rows = receipts.records(text, MARKER, 'OBSERVE')
            if not matches(rows, role) or not complete(selection, role, text) or MARKER + 'FAIL ' in text:
                issues.append(role + ': missing, duplicate or incorrect native VRO settings receipt')
            events = [PATCH_MARKER, MARKER + 'OBSERVE ']
            if selection['kind'] == 'mp' and role == 'client1':
                if not matches(receipts.records(text, MARKER, 'AUTHORITY'), 'server'):
                    issues.append('client1: missing authoritative settings acknowledgement')
                events.append(MARKER + 'AUTHORITY ')
            events.append(MARKER + 'COMPLETE ')
            positions = [own_text.find(event) for event in events]
            if any(position < 0 for position in positions) or positions != sorted(set(positions)):
                issues.append(role + ': invalid compiler/settings/completion order')
        except (OSError, ValueError, TypeError) as error:
            issues.append(role + ': ' + str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'custom-controls',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'limits': ['Native settings/recipe initialization only; no repair, salvage effects, reload or remote vehicle coverage.']}}
