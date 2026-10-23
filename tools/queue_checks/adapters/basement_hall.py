"""Disposable SP corridor traversal through the shared native runner."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import zipfile
from .auxiliary import _load, _path


MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']
WORLD = 'QueueBasementHall'
MARKER = '[BASEMENT_HALL] '


def definitions():
    return {'basement-hall': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
            'game_inputs': ['media/maps/Muldraugh, KY/41_37.lotheader',
                            'media/basement_access/ba_exterior_north_westside_13.pzby',
                            'media/scripts/generated/items/drainable.txt',
                            'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'],
            'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                       'kinds': ['sp'], 'languages': ['EN'], 'modes': ['toolkit'],
                       'control_reason': 'Explicit fresh native-control uses JavaPatches 0.1.17; other cases require the candidate'}
                      for case in ('fresh', 'reload', 'native-control')]}}


def validate(selection):
    if (selection.get('cases') not in (['fresh'], ['reload'], ['native-control']) or selection.get('kind') != 'sp'
            or selection.get('mode') != 'toolkit' or selection.get('languages') != ['EN']
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or not set(MODS) <= set(selection.get('mods', []))):
        raise ValueError('Basement hall requires fresh/reload/native-control, toolkit SP, one EN client and the Java patch')
    template = selection.get('options', {}).get('world_template')
    if bool(template) != (selection['cases'] == ['reload']):
        raise ValueError('Basement hall reload requires a sealed world_template; fresh must create its own world')
    for key in ('ffmpeg', 'ffprobe'):
        _path(selection, key, executable=True)


def environment(selection, role, cache):
    if selection.get('suite') == 'basement-hall' and role == 'client1' and selection.get('kind') == 'sp':
        return {'PZ_BASEMENT_HALL_CACHE': Path(cache)}
    return {}


def sources(project, selection):
    return (sorted(path for path in (Path(project) / 'tests/native_queue/contributions/basement-hall').rglob('*')
                  if path.is_file() and path.suffix in ('.java', '.lua', '.py', '.md'))
            + [Path(__file__).with_name('auxiliary.py'),
               Path(project) / 'tests/native_queue/contributions/video-recording/verify.py',
               *[_path(selection, key, executable=True) for key in ('ffmpeg', 'ffprobe')]])


def stage(project, output, game, jdk, selection, locations, runtime):
    from ..native import _lua, _metadata
    validate(selection)
    if selection['cases'] == ['native-control']:
        info = Path(locations['PZToolkitJavaPatches']) / '42/mod.info'
        if _metadata(info).get('version') != '0.1.17':
            raise ValueError('Basement hall native-control requires sealed JavaPatches 0.1.17')
    intake = Path(project) / 'tests/native_queue/contributions/basement-hall'
    classes = Path(output) / 'basement-hall-classes'
    classes.mkdir()
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp',
                    os.pathsep.join(str(Path(game) / jar) for jar in ('projectzomboid.jar', 'ZombieBuddy.jar')),
                    '-d', str(classes), str(intake / 'Main.java')], check=True, capture_output=True,
                   text=True, timeout=60, env={key: value for key, value in os.environ.items()
                   if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')})
    if not (classes / 'net/alexredby/basementhallfixture/Main.class').is_file():
        raise ValueError('Basement hall javac did not produce its test helper')
    cache = Path(runtime['roles']['client1']['cache'])
    helper = cache / 'mods/BasementHallFixture'
    jar = helper / '42/media/java/BasementHallFixture.jar'
    jar.parent.mkdir(parents=True)
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for source in sorted(classes.rglob('*.class')):
            archive.write(source, source.relative_to(classes).as_posix())
    (helper / '42/mod.info').write_text('name=Test-only basement hall fixture\nid=BasementHallFixture\n'
        'versionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.basementhallfixture\n'
        'javaJarFile=media/java/BasementHallFixture.jar\n')
    for layer in ('common', '42'):
        for directory in ('AnimSets', 'actiongroups'):
            (helper / layer / 'media' / directory).mkdir(parents=True, exist_ok=True)
    lua = cache / 'mods/ActionQueueTest/42/media/lua'
    shutil.copy2(intake / 'client.lua', lua / 'client/ZZBasementHall.lua')
    config = dict(selection, port=selection['ports'][0], disposable=True, world=WORLD,
                  video={'directory': str(cache / 'videos'), 'ffmpeg': str(_path(selection, 'ffmpeg', True))})
    (lua / 'shared/QueueTestSelection.lua').write_text('QueueTestSelection=' + _lua(config) + '\nreturn QueueTestSelection\n')
    runtime.setdefault('fixture', {}).update(mods=['BasementHallFixture'], failure_markers=[MARKER + 'FAIL '])
    runtime['roles']['client1'].setdefault('env', {}).update(
        {name: str(value) for name, value in environment(selection, 'client1', cache).items()})


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(MARKER) + 'COMPLETE case='
            + selection['cases'][0] + r'(?:\s|$)', text)) == 1


def _video(root, selection, text):
    utility = _load(Path(__file__).resolve().parents[3] / 'tests/native_queue/contributions/video-recording/verify.py')
    results = utility.RESULT.findall(text.replace(MARKER + 'VIDEO_RESULT ', '[VIDEO_TEST] RESULT '))
    stops = re.findall(re.escape(MARKER) + r'VIDEO_STOP elapsedMs=(\d+)', text)
    points = re.findall(re.escape(MARKER) + r'VIDEO_PHASE phase=(\w+) elapsedMs=(\d+)', text)
    if len(results) != 1 or len(stops) != 1 or [name for name, _ in points] != ['surface', 'basement', 'returned']:
        raise ValueError('Missing completed presented video; earlier load/traversal evidence alone is not visual acceptance')
    state, file, frames, seconds, captured, dropped, width, height, error = results[0]
    if state != 'completed' or error.strip():
        raise ValueError('Presented video recording failed: ' + error)
    times = [int(ms) for _, ms in points]
    if times != sorted(set(times)) or times[0] < 300 or times[-1] > int(stops[0]):
        raise ValueError('Presented video phase times are out of order or outside the capture interval')
    record = dict(file=file, frames=int(frames), seconds=float(seconds), captured=int(captured),
                  dropped=int(dropped), width=int(width), height=int(height), elapsed_ms=int(stops[0]))
    video = Path(file).resolve(strict=True)
    cache = root / 'client1'
    if not video.is_relative_to((cache / 'videos').resolve()):
        raise ValueError('Presented video escapes the owned cache/videos')
    ffmpeg, ffprobe = (_path(selection, key, True) for key in ('ffmpeg', 'ffprobe'))
    probe = subprocess.run([str(ffprobe), '-v', 'error', '-count_frames', '-show_streams', '-of', 'json', str(video)],
                           check=True, capture_output=True, text=True, timeout=30)
    metadata = json.loads(probe.stdout)
    utility.validate_metadata(record, metadata)
    subprocess.run([str(ffmpeg), '-v', 'error', '-xerror', '-i', str(video), '-f', 'null', '-'], check=True, timeout=30)
    output = cache / 'verification'
    output.mkdir(exist_ok=True)
    images = []
    for (phase, _), elapsed in zip(points, times):
        # Capture the settled pose just before the marker, before the next walk can start.
        frame = max(0, elapsed * 30 // 1000 - 6)
        image = output / ('presented-' + phase + '.png')
        subprocess.run([str(ffmpeg), '-v', 'error', '-y', '-i', str(video), '-vf', f'select=eq(n\\,{frame})',
                        '-frames:v', '1', str(image)], check=True, timeout=30)
        if not image.is_file() or image.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
            raise ValueError('Presented frame extraction failed: ' + phase)
        images.append(str(image))
    return dict(record, phases=dict(points), presented_frames=images, probe=metadata)


def verify(root, selection, catalog):
    root = Path(root)
    issues, positions, probes, shots, video = [], [], [], [], None
    lights = []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        activation = r'\[PZToolkitJavaPatches\] Experimental B42\.21 patch:[^\r\n]*\bbasementHall=true(?:,|\s|$)'
        separated = ('[PZToolkitJavaPatches] Basement hall key separated: original=107, key='
                     + str(0x505A0000000C00D3) + ', accessKey=786643')
        native_control = selection['cases'] == ['native-control']
        duplicate = 'duplicate RoomDef.metaID for room at 10707,9484,0'
        if native_control:
            old_activation = r'\[PZToolkitJavaPatches\] Experimental B42\.21 patch:[^\r\n]*\bbasementRooms=true(?:,|\s|$)'
            if (len(re.findall(old_activation, text)) != 1 or re.search(activation, text)
                    or '[PZToolkitJavaPatches] Basement hall key separated:' in text or text.count(duplicate) != 1):
                issues.append('Native control did not reproduce the unseparated hall collision with the old patch')
        else:
            if len(re.findall(activation, text)) != 1 or text.count(separated) != 1:
                issues.append('Candidate patch did not activate and separate the exact hall key once')
            if duplicate in text:
                issues.append('Candidate still reports the target hall collision')
        for marker in ('READY', 'SURFACE', 'BASEMENT', 'RETURNED', 'SAVED', 'COMPLETE case=' + selection['cases'][0]):
            found = list(re.finditer(re.escape(MARKER + marker) + r'(?:\s|$)', text))
            if len(found) != 1:
                issues.append('Missing or duplicate basement hall evidence: ' + marker)
            else:
                positions.append(found[0].start())
        if positions != sorted(set(positions)):
            issues.append('Basement hall evidence is out of order')
        for match in re.finditer(re.escape(MARKER) + r'LIGHT phase=(\w+) held=true active=true charge=([0-9.eE+-]+) distance=15 strength=2 cone=false', text):
            phase, charge = match.groups()
            if not 0 < float(charge) <= 1:
                issues.append('Native held lantern is depleted or has invalid charge')
            lights.append({'phase': phase, 'charge': float(charge)})
        if [value['phase'] for value in lights] != ['surface', 'basement', 'returned']:
            issues.append('Missing ordered held active native lantern evidence')
        for match in re.finditer(re.escape(MARKER) + r'PROBE (.+)', text):
            value = json.loads(match[1])
            if (value.get('baseIndex') != 107 or type(value.get('accessIndex')) is not int
                    or value['accessIndex'] < 0 or value['accessIndex'] == 107
                    or value.get('nativeControl') is not native_control
                    or value.get('baseKey') != ('c00d3' if native_control else '505a0000000c00d3')
                    or value.get('accessKey') != 'c00d3'
                    or value.get('ownerIndex') != 16 or value.get('stable') is not True
                    or value.get('canSee') is not True
                    or value.get('z') != (-1 if value.get('phase') == 'basement' else 0)):
                issues.append('Invalid live native room identity/lookup evidence')
            probes.append(value)
        if len(probes) != 3 or [probe.get('phase') for probe in probes] != ['surface', 'basement', 'returned']:
            issues.append('Missing ordered live room probes')
        for name in ('surface', 'basement', 'returned'):
            found = list((root / 'client1').rglob('basement-hall-' + name + '.png'))
            if len(found) != 1 or found[0].read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                issues.append('Missing native screenshot: ' + name)
            else:
                shots.append(str(found[0]))
        if MARKER + 'FAIL ' in text or '[QUEUE_TEST] FAIL ' in text:
            issues.append('Fixture or common preflight failed')
        save = root / 'client1/Saves/Sandbox' / WORLD / 'map_meta.bin'
        if not save.is_file() or save.read_bytes()[:4] != b'META':
            issues.append('Native world metadata was not saved')
        video = _video(root, selection, text)
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': selection['cases'][0],
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues),
            'outcome': {'native_traversal': not issues}}],
            'evidence': {'probes': probes, 'lights': lights, 'screenshots': shots, 'video': video, 'limits': [
                'Presented video frames require separate visual review; successful decoding does not establish cutaway equivalence.',
                'Core.TakeFullScreenshot PNGs are retained only for comparison; their current read FBO may omit the world.',
                'Live probe checks native index/ID consistency and stability during traversal; native regression owns pre-patch all-ID comparison.',
                'Reload repeats traversal in a sealed same-suite SP template; independent flag roundtrips are covered by the native regression.']}}
