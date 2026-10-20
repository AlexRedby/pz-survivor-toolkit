"""Open-road night capture through the shared native lifecycle; no lighting replacements."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import zipfile

MARKER = '[VEHICLE_LIGHTS] '
PHASES = ['off', 'original_low', 'original_high', 'low', 'high', 'reverse_low', 'reverse_high', 'restored', 'close_low', 'close_no_spill', 'off_after']


def definitions():
    return {'vehicle-lights': {'status': 'ready', 'clients': 1,
        'default_mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'NepHighBeams', 'ReverseDriveLights'],
        'cases': [{'id': 'road', 'producer': 'fixture', 'capability': 'capture',
                   'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit']}]}}


def validate(selection):
    required = set(definitions()['vehicle-lights']['default_mods'])
    if (selection['cases'] != ['road'] or selection['kind'] not in ('sp', 'mp')
            or selection['mode'] != 'toolkit' or selection['clients'] != 1
            or selection['languages'] != ['EN'] or not required <= set(selection['mods'])
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Vehicle lights requires one EN client, fresh SP/Host, road and both light mods')
    if selection['kind'] == 'mp' and not selection.get('options', {}).get('mp_host'):
        raise ValueError('Vehicle lights MP uses native menu Host')
    for key in ('ffmpeg', 'ffprobe'):
        value = Path(selection['options'][key])
        if not value.is_absolute() or not os.access(value, os.X_OK):
            raise ValueError('Vehicle lights needs an absolute executable ' + key)


def sources(project, selection):
    base = Path(project) / 'tests/native_queue'
    return [*sorted((base / 'vehicle-lights').rglob('*.lua')), base / 'vehicle-lights/Main.java',
            *sorted((base / 'startup').rglob('*.lua')),
            *[Path(selection['options'][key]) for key in ('ffmpeg', 'ffprobe')]]


def stage(project, output, game, jdk, selection, locations, runtime):
    from ..native import _lua
    validate(selection)
    classes = Path(output) / 'vehicle-lights-classes'; classes.mkdir()
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '17', '-cp',
        os.pathsep.join(str(Path(game) / jar) for jar in ('projectzomboid.jar', 'ZombieBuddy.jar')),
        '-d', str(classes), str(Path(project) / 'tests/native_queue/vehicle-lights/Main.java')],
        check=True, capture_output=True, text=True, timeout=60)
    for role, settings in runtime['roles'].items():
        cache = Path(settings['cache']); lua = cache / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            text = (Path(project) / 'tests/native_queue/startup' / side / name).read_text()
            # Fresh test-only highway spawn, with grid power off; no live settings touched.
            text = text.replace('posX=10835,posY=10144', 'posX=10640,posY=10144')
            text = text.replace("getSandboxOptions():getOptionByName('Zombies'):setValue(6);", "getSandboxOptions():getOptionByName('ElecShutModifier'):setValue(0);getSandboxOptions():getOptionByName('NightDarkness'):setValue(1);getSandboxOptions():getOptionByName('StartTime'):setValue(8);getSandboxOptions():getOptionByName('StartYear'):setValue(1);getSandboxOptions():getOptionByName('StartMonth'):setValue(7);getSandboxOptions():getOptionByName('StartDay'):setValue(20);getSandboxOptions():getOptionByName('Zombies'):setValue(6);")
            (lua / side / name).write_text(text)
        (lua / 'shared/QueueLightsConfig.lua').write_text('return ' + _lua({
            'directory': str(cache / 'videos'), 'ffmpeg': selection['options']['ffmpeg'],
            'dashboard': selection['options'].get('dashboard', False),
            'origins': selection['options'].get('origins', False),
            'dashboardCompare': selection['options'].get('dashboard_compare', False),
            'rotary': selection['options'].get('rotary', False),
            'rocker': selection['options'].get('rocker', False),
            'push': selection['options'].get('push', False)}) + '\n')
        helper = cache / 'mods/VehicleLightsFixture'; jar = helper / '42/media/java/VehicleLightsFixture.jar'
        jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
            for source in sorted(classes.rglob('*.class')):
                archive.write(source, source.relative_to(classes).as_posix())
        (helper / '42/mod.info').write_text('name=Disposable vehicle lighting fixture\nid=VehicleLightsFixture\n'
            'versionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.vehiclelightsfixture\n'
            'javaJarFile=media/java/VehicleLightsFixture.jar\n')
        if role == 'client1':
            settings.setdefault('env', {})['PZ_LIGHTS_TEST_CACHE'] = str(cache)
    if selection['kind'] == 'mp':
        ini = Path(output) / 'server/Server/queue-smoke.ini'
        ini.write_text(ini.read_text().replace('SpawnPoint=10835,10144,0', 'SpawnPoint=10640,10144,0'))
    runtime.setdefault('fixture', {}).update(mods=['VehicleLightsFixture'],
        server_ready='[STARTUP_TEST] SERVER_READY', failure_markers=[MARKER + 'FAIL ', '[ReverseDriveLights] error:'],
        sandbox={'ElecShutModifier': 0, 'NightDarkness': 1, 'StartTime': 8, 'StartYear': 1, 'StartMonth': 7, 'StartDay': 20})


def complete(selection, role, text):
    return role == 'client1' and text.count(MARKER + 'COMPLETE road') == 1


def verify(root, selection, catalog):
    root = Path(root); text = (root / 'client1-launch.log').read_text(errors='replace')
    phases = re.findall(re.escape(MARKER) + r'PHASE (\w+) elapsedMs=(\d+) probe=(.+)', text)
    issues = []
    if [row[0] for row in phases] != PHASES or not complete(selection, 'client1', text) or MARKER + 'FAIL ' in text:
        issues.append('Missing ordered night road comparison or completion')
    if len(phases) == len(PHASES):
        for name, _, probe in phases:
            value = json.loads(probe)
            if not value['vehicle'] or not value['driver'] or value['battery'] <= 0:
                issues.append('No actual driver/battery at ' + name)
            high = name in ('high', 'original_high', 'reverse_high')
            front = value['HeadlightLeft']
            if abs(front['distance'] - (54 if high else 36)) > .01:
                issues.append('Front range differs at ' + name)
            rear = value['HeadlightRearLeft']; reversing = name.startswith('reverse_')
            if reversing and (value['transmission'] != 'R' or abs(rear['distance'] - 12) > .01 or abs(rear['intensity'] - .3) > .001 or rear['g'] != 1):
                issues.append('Native reverse gear/white beam absent at ' + name)
            if name == 'restored' and (value['transmission'] == 'R' or rear['distance'] != 3 or abs(rear['g'] - .2) > .001):
                issues.append('Rear light restoration absent')
    if not re.search(r'\[VEHICLE_LIGHTS\] ENV time=2(?:\.0+)? nightDarkness=1(?:\.0+)? ', text):
        issues.append('Missing live Pitch Black/time observation')
    if selection['options'].get('rotary'):
        clicks = re.findall(re.escape(MARKER) + r'ROTARY_CLICK (off|low|high) (off|low|high)', text)
        expected = [('off', 'low'), ('low', 'high'), ('high', 'off'), ('off', 'low'), ('low', 'high')]
        if selection['kind'] == 'sp':
            expected += [('off', 'low'), ('low', 'high'), ('high', 'off')] * 4
            for scale in ('0.75x', '1x', '1.4x', '2x'):
                for mode, angle in (('off', 0), ('low', 45), ('high', 90)):
                    if not re.search(re.escape(MARKER + 'DASHBOARD standard_scale_' + scale + '_' + mode)
                                     + r' .*family=standard .*scale=' + re.escape(scale)
                                     + r' .*angle=' + str(angle) + r'(?:\.0)?\s', text):
                        issues.append('Missing standard rotary position ' + scale + ' ' + mode)
        if clicks != expected:
            issues.append('Missing native ISImage rotary OFF/LOW/HIGH/OFF sequence')
    if selection['options'].get('push'):
        expected = [('off', 'low'), ('low', 'high'), ('high', 'off'), ('off', 'low'), ('low', 'high')]
        if selection['kind'] == 'sp':
            expected += [('off', 'low'), ('low', 'high'), ('high', 'off')] * 4
            for scale in ('0.75x', '1x', '1.4x', '2x'):
                for mode in ('off', 'low', 'high'):
                    for name, pressed in ((mode, 'false'), ('pressed_' + mode, 'true')):
                        if not re.search(re.escape(MARKER + 'PUSH_VIEW sport_scale_' + scale + '_' + name)
                                         + ' pressed=' + pressed + ' ', text):
                            issues.append('Missing sport press/release view ' + scale + ' ' + name)
        elif any(MARKER + 'HOST_PUSH_POWER ' + mode + ' on=' not in text for mode in ('off', 'low', 'high')):
            issues.append('Missing sport server headlight power acknowledgement')
        if re.findall(re.escape(MARKER) + r'PUSH_CLICK (off|low|high) (off|low|high)', text) != expected:
            issues.append('Missing sport native click cycle')
    if selection['options'].get('rocker'):
        clicks = re.findall(re.escape(MARKER) + r'ROCKER_CLICK (off|low|high) (off|low|high)', text)
        if clicks != [('off', 'low'), ('low', 'high'), ('high', 'low'), ('low', 'off')]:
            issues.append('Missing truck ISImage upper/lower OFF/LOW/HIGH/LOW/OFF sequence')
        for scale in (('0.75x', '1x', '1.4x', '2x') if selection['kind'] == 'sp' else ()):
            if not re.search(re.escape(MARKER) + r'DASHBOARD heavy_scale_' + re.escape(scale)
                             + r' .*family=heavy .*scale=' + re.escape(scale) + r' ', text):
                issues.append('Missing actual truck rocker scale ' + scale)
        if selection['kind'] == 'mp':
            for mode in ('off', 'low', 'high'):
                if MARKER + 'HOST_ROCKER_POWER ' + mode + ' on=' not in text:
                    issues.append('Missing server headlight acknowledgement for truck ' + mode)
    results = re.findall(re.escape(MARKER) + r'VIDEO_RESULT (.+)', text)
    record = json.loads(results[0]) if len(results) == 1 else {}
    if record.get('state') != 'completed' or record.get('error') or not record.get('frames'):
        issues.append('No completed presented-frame recording')
    elif not Path(record['file']).is_relative_to(root / 'client1/videos') or not Path(record['file']).is_file():
        issues.append('Recording escapes owned cache or is missing')
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'road',
        'status': 'failed' if issues else 'captured', 'reason': '; '.join(issues)}],
        'evidence': {'phases': phases, 'video': record,
        'limits': ['Actual native reverse input; one local driver, no remote passenger sync acceptance.',
                   'Presented frames require visual review; configured ranges are not measured rendered distances.']}}
