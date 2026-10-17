"""Cart captures keep source probes and diagnostics separate from a functional pass."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

from .auxiliary import _load, _path, _write

MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'PZSurvivorWishlist',
        'SaucedCarts', 'saucedwheelbarrow']
SP = 'wooden_cart_motion'
MP = 'wooden_cart_multiplayer'
SP_CASES = {'sprint': ('scenario-clips.lua', 16), 'reverse': ('scenario-reverse.lua', 20),
            'reversal': ('scenario-reversal.lua', 20), 'stop': ('scenario-stop.lua', 24),
            'stationary': ('scenario-stationary.lua', 20), 'maneuvers': ('scenario-maneuvers.lua', 32),
            'collision': ('scenario-collision.lua', 20), 'footprint': ('scenario-collision.lua', 20),
            'interaction': ('scenario-interaction.lua', 4)}
AREA = dict(x=10825.5, y=10142.5, z=7, minX=10777, minY=10094, size=96, margin=2, floorSprite='carpentry_02_57')


def definitions():
    result = {suite: {'status': 'ready', 'clients': 1 if suite == SP else 2, 'default_mods': MODS,
                    'cases': [{'id': case, 'producer': 'fixture', 'capability': 'capture',
                               'kinds': ['sp' if suite == SP else 'mp'], 'modes': ['toolkit'],
                               'control_reason': 'Preserved candidate capture requires toolkit mode; it does not assess animation equivalence',
                               'languages': ['RU'] if suite == SP else ['EN', 'RU']}
                              for case in (SP_CASES if suite == SP else ['owner_observer_motion'])]}
            for suite in (SP, MP)}
    result[SP]['game_inputs'] = ['media/models_X/Skinned/MaleBody.x', 'media/models_X/Skinned/FemaleBody.x',
        'media/models_X/Skinned/Clothes/Bob_Trousers.x', 'media/models_X/Skinned/Clothes/Kate_Trousers.x']
    return result


def _intake(project, suite):
    return Path(project) / 'tests/native_queue/contributions' / suite


def validate(selection):
    suite = selection['suite']
    cases = SP_CASES if suite == SP else ['owner_observer_motion']
    if len(selection['cases']) != 1 or selection['cases'][0] not in cases or selection['mode'] != 'toolkit':
        raise ValueError('Cart candidates support one capture case in toolkit mode only')
    if selection['kind'] != ('sp' if suite == SP else 'mp') or selection['languages'] != (['RU'] if suite == SP else ['EN', 'RU']):
        raise ValueError('Unsupported cart kind/languages')
    if not set(MODS) <= set(selection['mods']):
        raise ValueError('Missing required cart fixture mods')
    overrides = selection.get('options', {}).get('mod_sources', {})
    for identifier in ('PZSurvivorToolkit', 'PZToolkitJavaPatches'):
        value = overrides.get(identifier)
        if not isinstance(value, str) or not Path(value).is_absolute() or not Path(value).is_dir():
            raise ValueError('Explicit candidate options.mod_sources.' + identifier + ' is required')
    for key in ('patch_jar', 'ffmpeg', 'ffprobe'):
        _path(selection, key, executable=key != 'patch_jar')
    if suite == SP:
        _path(selection, 'mesh_fbx')


def sources(project, selection):
    paths = [Path(__file__), Path(__file__).with_name('auxiliary.py')]
    for suite in (SP, MP) if selection['suite'] == MP else (SP,):
        paths += [path for path in _intake(project, suite).rglob('*') if path.is_file()
                  and path.suffix in ('.py', '.lua', '.java', '.json', '.md', '.mf', '.methods')]
    if selection['suite'] == SP:
        paths += [Path(project) / 'tests/native_queue/support/QueueCartStartup.lua', _path(selection, 'mesh_fbx')]
    paths += [_path(selection, key, key != 'patch_jar') for key in ('patch_jar', 'ffmpeg', 'ffprobe')]
    return paths


def _compile(jdk, classpath, classes, sources):
    classes.mkdir(parents=True)
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '17', '-cp', classpath, '-d', str(classes),
                    *map(str, sources)], check=True, capture_output=True, text=True, timeout=120,
                   env={key: value for key, value in os.environ.items() if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')})
    if not list(classes.rglob('*.class')):
        raise ValueError('Cart javac produced no classes')


def _jar(path, classes, manifest=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'x', zipfile.ZIP_DEFLATED) as output:
        if manifest:
            output.writestr('META-INF/MANIFEST.MF', manifest.read_bytes())
        for source in sorted(classes.rglob('*.class')):
            output.write(source, source.relative_to(classes).as_posix())


def stage(project, output, game, jdk, selection, locations, runtime):
    from ..native import _lua
    validate(selection)
    project, output, game = map(Path, (project, output, game))
    sp, mp = _intake(project, SP), _intake(project, MP)
    patch = _path(selection, 'patch_jar')
    if not any(hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(patch.read_bytes()).digest()
               for path in Path(locations['PZToolkitJavaPatches']).rglob('*.jar')):
        raise ValueError('Compile patch_jar must match the selected candidate patch mod')
    classpath = os.pathsep.join(map(str, (game / 'projectzomboid.jar', game / 'ZombieBuddy.jar', patch)))
    build = output / 'cart-build'
    build.mkdir()
    main = (sp / 'Main.java').read_text()
    if selection['suite'] == MP:
        anchor = '    public static void main(String[] args)'
        if main.count(anchor) != 1:
            raise ValueError('CartLab composition anchor changed')
        main = main.replace(anchor, (mp / 'MPMain.methods').read_text() + '\n' + anchor)
    source = build / 'Main.java'
    source.write_text(main, encoding='utf-8')
    _compile(jdk, classpath, build / 'lab-classes', [source])
    _jar(build / 'CartLab.jar', build / 'lab-classes')
    evidence = sp / 'evidence'
    probe_sources = ([mp / 'ClearanceProbe.java'] if selection['suite'] == MP else
                     [evidence / (name + '.java') for name in ('WoodenWheelNativeProbe', 'GripPoseProbe', 'ClearanceProbe')])
    _compile(jdk, classpath, build / 'probe-classes', [*probe_sources, evidence / 'AttachWoodenWheelProbe.java'])
    probes = ['ClearanceProbe'] if selection['suite'] == MP else ['WoodenWheelNativeProbe', 'GripPoseProbe', 'ClearanceProbe']
    for name in probes:
        _jar(build / (name + '.jar'), build / 'probe-classes', (mp if selection['suite'] == MP else evidence) / (name + '.mf'))
    fixture = runtime.setdefault('fixture', {})
    fixture['mods'] = ['CartLab']
    fixture['attach'] = {}
    fixture['failure_markers'] = ['[WOOD_PROTOTYPE] BOOTSTRAP_FAIL', '[WOOD_BANK] FAIL']
    videos = {role: str(Path(config['cache']) / 'videos') for role, config in runtime['roles'].items() if role != 'server'}
    config = dict(selection, port=selection['ports'][0], disposable=True, ffmpeg=str(_path(selection, 'ffmpeg', True)), videoRoot=videos)
    for role, spec in runtime['roles'].items():
        cache = Path(spec['cache'])
        mod = cache / 'mods/CartLab'
        _write(mod / '42/mod.info', 'name=Test-only Cart Lab\nid=CartLab\nversionMin=42.21\nrequire=\\ZombieBuddy\nZBVersionMin=2.3.4\njavaPkgName=net.alexredby.cartlab\njavaJarFile=media/java/CartLab.jar\n')
        (mod / '42/media/java').mkdir(parents=True)
        shutil.copy2(build / 'CartLab.jar', mod / '42/media/java/CartLab.jar')
        for layer in ('common', '42'):
            for sub in ('AnimSets', 'actiongroups'):
                (mod / layer / 'media' / sub).mkdir(parents=True, exist_ok=True)
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        _write(lua / 'shared/QueueTestSelection.lua', 'QueueTestSelection=' + _lua(config) + '\nreturn QueueTestSelection\n')
        options = cache / 'options.ini'
        _write(options, options.read_text() + 'toggleToRun=false\ntoggleToSprint=false\ndblTapJogToSprint=false\npauseOnFocusLoss=false\n')
        if selection['suite'] == MP:
            for origin, target in [('client.lua', 'client/ZZCartMP.lua'), ('server.lua', 'server/ZZCartMP_Server.lua'),
                                   ('placement.lua', 'shared/CartMPPlacement.lua'), ('json.lua', 'shared/CartMPJSON.lua')]:
                _write(lua / target, (mp / origin).read_text())
        elif role != 'server':
            _write(lua / 'client/QueueCartStartup.lua', (project / 'tests/native_queue/support/QueueCartStartup.lua').read_text())
        runtime_lua = cache / 'Lua/cart-runtime.lua'
        spec['env'] = dict(spec.get('env', {}), PZ_CART_RUNTIME_FILE=str(runtime_lua), PZ_CART_COMMAND_FILE=str(cache / 'Lua/cart-command.txt'))
        if role == 'server':
            _write(runtime_lua, 'return true\n')
            sandbox = cache / 'Server' / (runtime['server_name'] + '_SandboxVars.lua')
            _write(sandbox, 'SandboxVars={VERSION=6,Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2}\n')
            continue
        classes = Path(spec['classes'])
        shutil.copy2(build / 'probe-classes/AttachWoodenWheelProbe.class', classes / 'AttachWoodenWheelProbe.class')
        for name in probes:
            target = classes / 'probes' / (name + '.jar')
            target.parent.mkdir(exist_ok=True)
            shutil.copy2(build / (name + '.jar'), target)
            fixture['attach'].setdefault(role, []).append({'jar': str(target), 'output': str(cache),
                'classpath': str(classes) + os.pathsep + classpath, 'class': 'AttachWoodenWheelProbe',
                'ready': '[CART_MP] CONNECTED' if selection['suite'] == MP else '[CART_ADAPTER] PROBE_ATTACH_READY'})
        if selection['suite'] == SP:
            motion = dict(disposable=True, ffmpeg=config['ffmpeg'], videoRoot=videos[role], area=AREA)
            if selection['cases'][0] in ('collision','footprint'): motion['footprint']=True
            runtime_source = 'CartMotionConfig=' + _lua(motion) + '\nif not CartAdapterBootstrapped then\nCartAdapterBootstrapped=true\n'
            runtime_source += '(function()\n' + (sp / 'test-area.lua').read_text() + '\nend)();\n(function()\n' + (sp / 'obstacles.lua').read_text() + '\nend)();\n(function()\n' + (sp / 'bootstrap.lua').read_text() + '\nend)()'
            runtime_source += '\nelse\n(function()\n' + (sp / SP_CASES[selection['cases'][0]][0]).read_text() + '\nend)()\nend\n'
            _write(runtime_lua, runtime_source)
        else:
            _write(runtime_lua, 'return true\n')


def complete(selection, role, text):
    if selection['suite'] == SP:
        log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
        return re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=' + str(SP_CASES[selection['cases'][0]][1]) + r'(?:\s|$)', log) is not None
    return '"event":"complete"' in text.replace(' ', '') and '[CART_MP] VIDEO_FINAL' in text


def _json(path):
    return json.loads(path.read_text())


def _run(command, directory, name):
    result = subprocess.run(command, capture_output=True, text=True, timeout=240)
    _write(directory / (name + '.stdout.txt'), result.stdout)
    _write(directory / (name + '.stderr.txt'), result.stderr)
    return {'exit_code': result.returncode, 'stdout': str(directory / (name + '.stdout.txt')), 'stderr': str(directory / (name + '.stderr.txt'))}


def _videos(root, selection, role, text):
    if selection['suite'] == SP:
        text = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    records = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+) file=(.+?) frames=(\d+) seconds=([\d.]+)', text)
    if selection['suite'] == MP:
        rows = re.findall(r'\[CART_MP\] VIDEO_FINAL (\{[^\n]+\})', text)
        if len(rows) != 1:
            raise ValueError('Expected one final MP video receipt')
        item = json.loads(rows[0]); records = [(role, '0', item['file'], str(item['frames']), str(item['seconds']))]
    expected = 1 if selection['suite'] == MP else SP_CASES[selection['cases'][0]][1]
    if len(records) != expected or len({row[2] for row in records}) != expected:
        raise ValueError('Missing/duplicate completed cart clips')
    output = []
    for _, _, filename, frames, seconds in records:
        video = Path(filename).resolve(strict=True)
        if not video.is_relative_to((root / role / 'videos').resolve()):
            raise ValueError('Cart video escapes its profile')
        probe = subprocess.run([str(_path(selection, 'ffprobe', True)), '-v', 'error', '-count_frames', '-show_streams', '-of', 'json', str(video)], check=True, capture_output=True, text=True, timeout=60)
        streams = json.loads(probe.stdout)['streams']
        if len(streams) != 1 or streams[0].get('codec_type') != 'video' or streams[0].get('codec_name') != 'h264':
            raise ValueError('Expected one silent H264 cart video')
        stream = streams[0]
        if int(stream['nb_read_frames']) != int(frames) or int(frames) <= 0 or abs(float(stream['duration']) - float(seconds)) > .001:
            raise ValueError('Cart clip metadata differs from native receipt')
        subprocess.run([str(_path(selection, 'ffmpeg', True)), '-v', 'error', '-xerror', '-i', str(video), '-f', 'null', '-'], check=True, capture_output=True, text=True, timeout=120)
        output.append({'file': str(video), 'frames': int(frames), 'seconds': float(seconds), 'metadata': stream})
    return output


def _coverage(cache, text, count, metrics):
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    if len(completed) != count or len({row[0] for row in completed}) != count or '[WOOD_BANK] FAIL' in log:
        raise ValueError('Missing/duplicate cart cases or scenario failure')
    body = [json.loads(line) for line in (cache / 'body-clearance.jsonl').read_text().splitlines()]
    grip = [json.loads(line) for line in (cache / 'wood-grip-poses.jsonl').read_text().splitlines()]
    rows = metrics['cases']
    if len(rows) != count or {row['case'] for row in rows} != {name for name, _ in completed}:
        raise ValueError('Native metrics do not cover every completed cart case')
    for name, start in completed:
        start = int(start)
        for kind, samples in (('body', body), ('grip', grip)):
            times = sorted(set(row['wallTimeMillis'] for row in samples if start + 800 < row['wallTimeMillis'] < start + 11800))
            if len(times) < 5 or times[0] > start + 1500 or times[-1] < start + 11100 or max(b-a for a, b in zip(times, times[1:])) > 1000:
                raise ValueError('Incomplete ' + kind + ' probe window for ' + name)
        row = next(row for row in rows if row['case'] == name)
        if row['gripSamples'] <= 0 or row['wheelFloorMaxError'] is None or any(row.get(kind, {}).get('samples', 0) <= 0 for kind in ('body', 'pants')):
            raise ValueError('Missing pose/mesh evidence for ' + name)
    proof = _json(cache / 'wood-wheel-mesh-proof.json')
    native = (cache / 'WheelbarrowWood.bin').read_bytes()
    if proof.get('matchesOriginal') is not True or proof.get('proofAfterPhaseChanged') is not True or proof.get('sha256') != hashlib.sha256(native).hexdigest() or proof.get('bytes') != len(native):
        raise ValueError('Native cart mesh proof does not match the calibrated moving VBO')


def verify(root, selection, catalog):
    root = Path(root)
    project = Path(__file__).resolve().parents[3]
    intake = _intake(project, selection['suite'])
    roles = ['client1'] if selection['suite'] == SP else ['client1', 'client2']
    issues, evidence = [], {}
    parent = root / 'analysis'; parent.mkdir(exist_ok=True)
    analysis = Path(tempfile.mkdtemp(prefix='cart-', dir=parent))
    try:
        logs = {}
        for role in roles:
            launch, console = root / (role + '-launch.log'), root / role / 'console.txt'
            logs[role] = launch if selection['suite'] == SP and launch.is_file() else console if console.is_file() else launch
        texts = {role: path.read_text(errors='replace') for role, path in logs.items()}
        if any(not complete(selection, role, text) for role, text in texts.items()):
            raise ValueError('Cart capture did not complete')
        for text in texts.values():
            if any(marker in text for marker in ('[WOOD_PROTOTYPE] BOOTSTRAP_FAIL', '[WOOD_BANK] FAIL', '[QUEUE_TEST] FAIL', '[CLEARANCE_PROBE] ERROR', '[GRIP_POSE_PROBE] ERROR', '[WOOD_WHEEL_NATIVE_PROBE] ERROR')):
                raise ValueError('Cart capture contains fixture/probe errors')
        evidence['videos'] = {role: _videos(root, selection, role, text) for role, text in texts.items()}
        if selection['suite'] == MP:
            report = _load(intake / 'analyze.py').analyze(root)
            evidence['comparison'] = report
            _write(analysis / 'mp-comparison.json', json.dumps(report, indent=2, allow_nan=False))
        else:
            case = selection['cases'][0]
            runtime = _json(root / 'runtime.json')
            game = Path(runtime['game'])
            cache = root / 'client1'
            ev = intake / 'evidence'
            commands = [
                ('aabb', [sys.executable, str(ev / 'check-clearance.py'), '--game-java-dir', str(game), '--mesh-vbo', str(cache / 'WheelbarrowWood.bin'), '--capture', str(cache / 'body-clearance.jsonl'), '--output', str(analysis)]),
                ('body', [sys.executable, str(ev / 'check-hip-actual.py'), '--game-java-dir', str(game), '--mesh', str(_path(selection, 'mesh_fbx')), '--mesh-vbo', str(cache / 'WheelbarrowWood.bin'), '--capture', str(cache / 'body-clearance.jsonl'), '--output', str(analysis)]),
            ]
            commands.append(('pants', commands[1][1] + ['--pants']))
            if case != 'interaction':
                commands.append(('native', [sys.executable, str(ev / 'analyze-native.py'), '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis)] + (['--partial'] if case != 'sprint' else [])))
            evidence['analyzers'] = {name: _run(command, analysis, name) for name, command in commands}
            if case == 'interaction':
                evidence['analyzers'][case] = _run([sys.executable, str(intake / 'analyze-interaction.py'),
                    '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis / 'interaction.json')], analysis, case)
                report = _json(analysis / 'interaction.json')
                evidence['interaction'] = report
                if not report['functionalPass'] or not report['ikCoverageVerified']:
                    raise ValueError('Interaction functional/rendered IK verification failed: ' + str(report['failures']))
                if not report['worldHandoff']['pass']:
                    raise ValueError('Interaction world/held handoff failed: ' + str(report['worldHandoff']['failures']))
                proof = _json(cache / 'wood-wheel-mesh-proof.json')
                native = (cache / 'WheelbarrowWood.bin').read_bytes()
                if proof.get('matchesOriginal') is not True or proof.get('sha256') != hashlib.sha256(native).hexdigest() or proof.get('bytes') != len(native):
                    raise ValueError('Interaction native cart mesh proof is missing or mismatched')
                evidence['nativeMotionNotApplicable'] = True
            else:
                metrics = _json(analysis / 'native-metrics.json')
                evidence['native'] = metrics
            evidence['analysis'] = str(analysis)
            if case == 'reverse':
                motion = _load(intake / 'analyze-reverse.py').analyze(texts['client1'])
                evidence['motion'] = motion
                _write(analysis / 'reverse-motion.json', json.dumps(motion, indent=2, allow_nan=False))
            elif case in ('stop', 'stationary', 'maneuvers', 'collision', 'footprint'):
                analyzer='footprint' if case=='collision' else case
                evidence['analyzers'][case] = _run([sys.executable, str(intake / ('analyze-' + analyzer + '.py')),
                    '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis / (case + '-motion.json'))], analysis, case)
                evidence['motion'] = _json(analysis / (case + '-motion.json'))
            elif case == 'reversal':
                motion = _load(intake / 'analyze-reversal.py').analyze(texts['client1'])
                evidence['motion'] = motion
                _write(analysis / 'reversal-motion.json', json.dumps(motion, indent=2, allow_nan=False))
            if case != 'interaction':
                _coverage(cache, texts['client1'], SP_CASES[case][1], metrics)
                evidence['nativePartialDiagnostic'] = case != 'sprint'
            evidence['evidenceComplete'] = True
        evidence['analysis'] = str(analysis)
    except (ValueError, OSError, KeyError, TypeError, AssertionError, subprocess.SubprocessError) as error:
        issues.append(str(error))
    return {'issues': issues, 'evidence': evidence, 'outcomes': [
        {'actor': role, 'case': selection['cases'][0], 'status': 'failed' if issues else 'captured',
         'reason': '; '.join(issues) if issues else ('Native pickup/setdown functional and render coverage verified; geometry and videos require review'
             if selection['suite'] == SP and selection['cases'] == ['interaction'] else 'Capture coverage verified; motion, geometry and replication diagnostics require review'),
         'outcome': {'animationEquivalencePass': False, 'evidenceComplete': not issues}} for role in roles]}
