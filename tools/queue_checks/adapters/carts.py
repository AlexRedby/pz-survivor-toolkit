"""Cart captures keep source probes and diagnostics separate from a functional pass."""
import hashlib
import importlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

from .auxiliary import _load, _path, _write

MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit',
        'SaucedCarts', 'saucedwheelbarrow']
SP = 'wooden_cart_motion'
MP = 'wooden_cart_multiplayer'
SP_CASES = {'sprint': ('scenario-clips.lua', 16), 'reverse': ('scenario-reverse.lua', 20),
            'reversal': ('scenario-reversal.lua', 20), 'stop': ('scenario-stop.lua', 24),
            'stop-timing': ('scenario-stop.lua', 4),
            'stationary': ('scenario-stationary.lua', 20), 'maneuvers': ('scenario-maneuvers.lua', 32),
            'collision': ('scenario-collision.lua', 24), 'footprint': ('scenario-collision.lua', 24),
            'vehicles': ('scenario-vehicles.lua', 12),
            'brace': ('scenario-collision.lua', 8),
            'fast-slide': ('scenario-collision.lua', 16),
            'wall-exit': ('scenario-collision.lua', 24),
            'wall-manual-exit': ('scenario-collision.lua', 16),
            'wall-fast-manual-exit': ('scenario-collision.lua', 32),
            'impact': ('scenario-collision.lua', 8),
            'wheel': ('scenario-interaction.lua', 1), 'interaction': ('scenario-interaction.lua', 4),
            'interruption': ('scenario-interaction.lua', 12), 'interruption-matrix': ('scenario-interaction.lua', 48),
            'repeat': ('scenario-interaction.lua', 12), 'hotkey': ('scenario-interaction.lua', 12), 'manual': ('bootstrap.lua', 0),
            'path': ('scenario-path.lua', 24), 'variants': ('scenario-variants.lua', 3),
            'controls': ('scenario-controls.lua', 3), 'native-e': ('scenario-native-e.lua', 1)}
AREA = dict(x=10825.5, y=10142.5, z=7, minX=10777, minY=10094, size=96, margin=2, floorSprite='carpentry_02_57')
SCENE_SPECS = {
    'sprint': ('comparison', 'direct', 'gait', 'runstop'),
    'reverse': ('back-modifiers', 'back-arc-left', 'back-arc-right', 'u-turn-control', 'start-turn-control'),
    'reversal': ('walk-switch', 'run-switch', 'sprint-switch', 'cancel-switch', 'arc-switch'),
    'stop': ('run-stop', 'sprint-stop', 'short-release', 'run-resume-reverse', 'sprint-resume-turn', 'arc-stop'),
    'stationary': ('left', 'right', 'cancel-restart', 'run-exit', 'sprint-sequence'),
    'maneuvers': ('idle-swap-left', 'idle-swap-right', 'moving-swap-left', 'moving-swap-right',
                  'reverse-rest', 'reverse-moving', 'uturn-left', 'uturn-right'),
    'footprint': ('wall-block', 'wall-slide', 'wall-slide-right', 'corner-pivot', 'passage'),
    'impact': ('sprint-wall', 'native-impact'),
    'brace': ('wall-release', 'wall-restart'),
    'fast-slide': ('run-wall-slide', 'run-wall-slide-right', 'sprint-wall-slide', 'sprint-wall-slide-right'),
    'path': ('straight', 'corner', 'door-open', 'door-closed', 'overlap', 'cancel'),
}


VARIANTS = {'shopping-cart': 'SaucedCarts.ShoppingCart',
            'wooden-wheelbarrow': 'SaucedWheelbarrow.WheelbarrowWood',
            'metal-wheelbarrow': 'SaucedWheelbarrow.WheelbarrowMetal'}
VARIANT_PHASES = ('inventory-equip', 'walk', 'run', 'sprint', 'drop-near', 'pickup-near',
                  'drop-far', 'pickup-far', 'drop-repeat', 'pickup-repeat')
CONTROL_PHASES = (
    ('forward-0', 1, 0, 1000), ('forward-angle', 1, 0, 1000),
    ('left-held', 5, 1, 4000), ('left-release', 1, 0, 600),
    ('right-held', 8, 1, 4000), ('right-release', 1, 0, 600),
    ('pivot-left', 2, 0, 1300), ('pivot-right', 3, 0, 1300), ('pivot-release', 0, 0, 700),
    ('reverse', 4, 0, 1200), ('reverse-left', 6, 0, 1500), ('reverse-right', 7, 0, 1500),
    ('moving-forward', 1, 0, 1000), ('moving-reverse', 4, 0, 1800),
    ('run', 1, 1, 1000), ('run-stop', 0, 0, 1200),
    ('sprint', 1, 2, 1000), ('sprint-stop', 0, 0, 1500))
CONTROL_POSES = {'forward-0': 0, 'forward-angle': 2.1, 'left-held': 0, 'right-held': 0,
                 'pivot-left': 0, 'pivot-right': 0, 'reverse': .8, 'reverse-left': .8,
                 'reverse-right': .8, 'moving-forward': 1.3, 'run': 1.3, 'sprint': 1.3}


def scene_names(case):
    if case in ('variants', 'controls'):
        return list(VARIANTS)
    if case == 'native-e':
        return ['native-e']
    if case == 'manual':
        return []
    if case == 'stop-timing':
        return ['male-' + load + '-' + spec for load in ('empty', 'full') for spec in ('run-stop', 'sprint-stop')]
    if case == 'vehicles':
        return [f'male-{load}-vehicle-yaw{yaw}-{spec}' for load in ('empty', 'full')
                for yaw in (0, 45) for spec in ('front', 'slide-left', 'slide-right')]
    if case in ('wall-exit','wall-manual-exit','wall-fast-manual-exit'):
        manual=case in ('wall-manual-exit','wall-fast-manual-exit')
        return [f'{sex}-{load}-{gait}-{spec}'+('-manual' if manual else '')+f'-out{angle}' for sex in (('male','female') if manual else ('male',)) for load in ('empty','full')
                for gait in (('run','sprint') if case=='wall-fast-manual-exit' else ('walk',) if manual else ('walk','run','sprint')) for spec in ('wall-slide','wall-slide-right') for angle in (45,90)]
    if case in ('repeat', 'hotkey'):
        return [sex + '-' + load + '-' + spec for sex in ('male', 'female')
                for load in ('empty', 'full') for spec in ('complete-chain', 'pickup-restart', 'drop-restart')]
    if case in ('interruption', 'interruption-matrix'):
        prefixes = ('male-full-', 'male-empty-', 'female-full-', 'female-empty-') if case.endswith('-matrix') else ('',)
        return [prefix + action + '-' + phase + '-' + route for prefix in prefixes
                for phase in ('late', 'contact', 'early') for action in ('drop', 'pickup') for route in ('cancel', 'walk')]
    if case == 'interaction':
        return ['male-empty-yaw0', 'male-empty-yaw135', 'female-full-yaw90', 'male-full-yaw270']
    if case == 'wheel':
        return ['wood-wheel-cycle']
    case = 'footprint' if case == 'collision' else case
    names = [sex + '-' + load + '-' + spec
             for sex in ('male', 'female') for load in ('empty', 'full') for spec in SCENE_SPECS[case]]
    if case == 'sprint':
        names = [name + ('-right' if '-full-' in name else '-left') for name in names]
    if case == 'footprint':
        names += ['male-empty-' + spec for spec in ('door-closed', 'door-open', 'overlap', 'gait-contact')]
    return names


def selected_scenes(selection):
    names = scene_names(selection['cases'][0])
    options = selection.get('options', {})
    if 'cart_scenes' not in options:
        return names
    chosen = options['cart_scenes']
    if not isinstance(chosen, list) or not chosen or any(not isinstance(name, str) or name not in names for name in chosen) or len(set(chosen)) != len(chosen):
        raise ValueError('cart_scenes requires nonempty unique exact scene IDs from the selected SP cart bank')
    return [name for name in names if name in chosen]


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
    for case in result[SP]['cases']:
        case['scenes'] = scene_names(case['id'])
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
    if suite == SP:
        selected_scenes(selection)
    elif 'cart_scenes' in selection.get('options', {}):
        raise ValueError('cart_scenes supports SP cart captures only')
    if 'cart_authored_clip' in selection.get('options', {}):
        if suite != SP or type(selection['options']['cart_authored_clip']) is not bool:
            raise ValueError('cart_authored_clip requires an SP boolean pilot selection')
    for flag in ('cart_fast_motion', 'cart_actions', 'cart_hotkey_setdown'):
        if flag in selection.get('options', {}) and (suite != MP or type(selection['options'][flag]) is not bool):
            raise ValueError(flag + ' requires an MP boolean selection')
    options = selection.get('options', {})
    if 'cart_variant' in options and (suite != MP or not isinstance(options['cart_variant'], str) or options['cart_variant'] not in VARIANTS):
        raise ValueError('cart_variant requires an exact MP cart variant: ' + ', '.join(VARIANTS))
    if options.get('cart_actions') and options.get('cart_variant', 'wooden-wheelbarrow') != 'wooden-wheelbarrow':
        raise ValueError('cart_actions requires wooden-wheelbarrow')
    if options.get('cart_hotkey_setdown') and not options.get('cart_actions'):
        raise ValueError('cart_hotkey_setdown requires cart_actions')
    if 'cart_hotkey_key' in options:
        key = options['cart_hotkey_key']
        if type(key) is not int or not 0 < key < 256 or not (suite == SP and selection['cases'] == ['hotkey'] or suite == MP and options.get('cart_hotkey_setdown')):
            raise ValueError('cart_hotkey_key requires an enabled hotkey scenario and a key code in 1..255')
    overrides = selection.get('options', {}).get('mod_sources', {})
    for identifier in ('PZSurvivorToolkit', 'PZToolkitJavaPatches'):
        value = overrides.get(identifier)
        if not isinstance(value, str) or not Path(value).is_absolute() or not Path(value).is_dir():
            raise ValueError('Explicit candidate options.mod_sources.' + identifier + ' is required')
    for key in ('patch_jar', 'ffmpeg', 'ffprobe'):
        _path(selection, key, executable=key != 'patch_jar')
    if suite == SP and selection['cases'][0] not in ('variants', 'controls', 'native-e'):
        _path(selection, 'mesh_fbx')
        try:
            importlib.import_module('numpy')
        except ImportError as error:
            raise ValueError('SP cart analyzers require working NumPy in ' + sys.executable) from error


def sources(project, selection):
    paths = [Path(__file__), Path(__file__).with_name('auxiliary.py')]
    for suite in (SP, MP) if selection['suite'] == MP else (SP,):
        paths += [path for path in _intake(project, suite).rglob('*') if path.is_file()
                  and path.suffix in ('.py', '.lua', '.java', '.json', '.md', '.mf', '.methods')]
    if selection['suite'] == SP:
        paths += [Path(project) / 'tests/native_queue/support/QueueCartStartup.lua']
        if selection['cases'][0] not in ('variants', 'controls', 'native-e'):
            paths.append(_path(selection, 'mesh_fbx'))
    if selection['suite'] == MP:
        paths.append(Path(project) / 'tests/native_queue/startup/client/ZZStartup.lua')
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
    manual = selection['suite'] == SP and selection['cases'] == ['manual']
    simple = selection['suite'] == SP and selection['cases'][0] in ('variants', 'controls', 'native-e')
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
    if not manual and not simple:
        _compile(jdk, classpath, build / 'probe-classes', [*probe_sources, evidence / 'AttachWoodenWheelProbe.java'])
    probes = [] if manual or simple else ['ClearanceProbe'] if selection['suite'] == MP else ['WoodenWheelNativeProbe', 'GripPoseProbe', 'ClearanceProbe']
    for name in probes:
        _jar(build / (name + '.jar'), build / 'probe-classes', (mp if selection['suite'] == MP else evidence) / (name + '.mf'))
    fixture = runtime.setdefault('fixture', {})
    fixture['mods'] = ['CartLab']
    fixture['attach'] = {}
    if manual:
        fixture['manual'] = True
    fixture['failure_markers'] = ['[WOOD_PROTOTYPE] BOOTSTRAP_FAIL', '[WOOD_BANK] FAIL', '[CART_VARIANT] FAIL', '[CART_CONTROLS] FAIL', '[CART_NATIVE_E] FAIL']
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
            if role != 'server':
                _write(lua / 'client/QueueCartMPStartup.lua', (project / 'tests/native_queue/startup/client/ZZStartup.lua').read_text())
            for origin, target in [('client.lua', 'client/ZZCartMP.lua'), ('actions.lua', 'client/CartMPActions.lua'), ('server.lua', 'server/ZZCartMP_Server.lua'),
                                   ('placement.lua', 'shared/CartMPPlacement.lua'), ('json.lua', 'shared/CartMPJSON.lua')]:
                _write(lua / target, (mp / origin).read_text())
        elif role != 'server':
            _write(lua / 'client/QueueCartStartup.lua', (project / 'tests/native_queue/support/QueueCartStartup.lua').read_text())
        runtime_lua = cache / 'Lua/cart-runtime.lua'
        spec['env'] = dict(spec.get('env', {}), PZ_CART_RUNTIME_FILE=str(runtime_lua), PZ_CART_COMMAND_FILE=str(cache / 'Lua/cart-command.txt'))
        spec['env']['PZ_CART_TEST_PAD'] = 'true' if selection['suite'] == SP else 'false'
        if role == 'server':
            _write(runtime_lua, 'return true\n')
            sandbox = cache / 'Server' / (runtime['server_name'] + '_SandboxVars.lua')
            _write(sandbox, 'SandboxVars={VERSION=6,Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2}\n')
            continue
        classes = Path(spec['classes'])
        if simple:
            # An empty attachment list releases the existing startup gate without wooden probes.
            fixture['attach'][role] = []
        if not manual and not simple:
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
            if 'cart_authored_clip' in selection.get('options', {}):
                motion['authoredClip'] = selection['options']['cart_authored_clip']
            if 'cart_scenes' in selection.get('options', {}):
                motion['scenes'] = selected_scenes(selection)
            if selection['cases'][0] in ('collision','footprint','brace','fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit'): motion['footprint']=True
            if selection['cases'][0] == 'brace': motion['brace']=True
            if selection['cases'][0] == 'fast-slide': motion['fastSlide']=True
            if selection['cases'][0] in ('wall-exit','wall-manual-exit','wall-fast-manual-exit'): motion['wallExit']=True
            if selection['cases'][0] in ('wall-manual-exit','wall-fast-manual-exit'): motion['wallManualExit']=True
            if selection['cases'][0] == 'wall-fast-manual-exit': motion['wallFastManualExit']=True
            if selection['cases'][0] == 'impact': motion['impact']=True
            if selection['cases'][0] == 'vehicles': motion['vehicles']=True
            if selection['cases'][0] in ('interruption', 'interruption-matrix'): motion['interruptions']=True
            if selection['cases'][0] == 'interruption-matrix': motion['interruptionMatrix']=True
            if selection['cases'][0] in ('repeat', 'hotkey'): motion['rapidRepeats']=True
            if selection['cases'][0] == 'hotkey':
                motion['hotkeySetdown']=True
                if 'cart_hotkey_key' in selection['options']: motion['hotkeyKey']=selection['options']['cart_hotkey_key']
            if selection['cases'][0] == 'wheel': motion['wheelCycle']=True
            if selection['cases'][0] == 'stop-timing': motion['stopTiming']=True
            runtime_source = 'CartMotionConfig=' + _lua(motion) + '\n(function()\n' + (sp / 'scene-selection.lua').read_text() + '\nend)()\nif not CartAdapterBootstrapped then\nCartAdapterBootstrapped=true\n'
            runtime_source += '(function()\n' + (sp / 'test-area.lua').read_text() + '\nend)();\n(function()\n' + (sp / 'obstacles.lua').read_text() + '\nend)();\n(function()\n' + (sp / 'bootstrap.lua').read_text() + '\nend)()'
            if selection['cases'][0] == 'vehicles':
                runtime_source += ';\n(function()\n' + (sp / 'vehicles.lua').read_text() + '\nend)()'
            runtime_source += '\nend\n' if manual else '\nelse\n(function()\n' + (sp / SP_CASES[selection['cases'][0]][0]).read_text() + '\nend)()\nend\n'
            _write(runtime_lua, runtime_source)
        else:
            _write(runtime_lua, 'return true\n')


def complete(selection, role, text):
    if selection['suite'] == SP and selection['cases'] == ['manual']:
        return False
    if selection['suite'] == SP:
        log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
        expected = selected_scenes(selection)
        if 'cart_scenes' in selection.get('options', {}):
            recorded = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=\d+', log)
            if recorded != expected or '[WOOD_BANK] FAIL' in log:
                return False
        return re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=' + str(len(expected)) + r'(?:\s|$)', log) is not None
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
    expected = 1 if selection['suite'] == MP else len(selected_scenes(selection))
    if selection['suite'] == SP and selection['cases'] == ['controls'] and [row[0] for row in records] != selected_scenes(selection):
        raise ValueError('Missing, duplicate or reordered controls videos')
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


def _mesh_proof(cache, moving=True):
    proof = _json(cache / 'wood-wheel-mesh-proof.json')
    native = (cache / 'WheelbarrowWood.bin').read_bytes()
    if proof.get('matchesOriginal') is not True or moving and proof.get('proofAfterPhaseChanged') is not True or proof.get('sha256') != hashlib.sha256(native).hexdigest() or proof.get('bytes') != len(native):
        raise ValueError('Native cart mesh proof does not match the calibrated moving VBO')


def _debug_action_coverage(log, name, start, seconds, probes):
    from bisect import bisect_left

    rows = []
    for line in log.splitlines():
        if '[WOOD_INTERACTION_SAMPLE] ' not in line:
            continue
        sample = json.loads(line.split('[WOOD_INTERACTION_SAMPLE] ', 1)[1])
        if not isinstance(sample, dict) or not isinstance(sample.get('case'), str) or type(sample.get('start')) is not int:
            raise ValueError('Invalid selected-scene action telemetry: ' + name)
        if sample['case'] != name or sample['start'] != start:
            continue
        if (any(type(sample.get(key)) is not int for key in ('wall', 'elapsed', 'id', 'heldID'))
                or any(type(sample.get(key)) is not bool for key in ('rendered', 'ToolkitCartMotion'))
                or any(isinstance(value, float) and not math.isfinite(value) for value in sample.values())
                or sample['id'] < 0 or abs(sample['wall'] - start - sample['elapsed']) > 5
                or not 0 <= sample['elapsed'] <= seconds * 1000 + 500):
            raise ValueError('Invalid selected-scene action telemetry: ' + name)
        rows.append(sample)
    if (len(rows) < 100 or rows[0]['elapsed'] > 500 or rows[-1]['elapsed'] < seconds * 1000 - 500
            or any(not 0 < b['wall'] - a['wall'] <= 500 for a, b in zip(rows, rows[1:]))
            or len({row['id'] for row in rows}) != 1):
        raise ValueError('Incomplete selected-scene action telemetry window: ' + name)
    summary = {'telemetrySamples': len(rows)}
    for kind in ('body', 'grip'):
        times = []
        for probe in probes[kind]:
            wall = probe.get('wallTimeMillis')
            if type(wall) is not int:
                raise ValueError('Invalid selected-scene ' + kind + ' timestamp: ' + name)
            if start <= wall < start + seconds * 1000:
                times.append(wall)
        times.sort()
        # Transition rendering may use reach() directly, bypassing the grip() probe.
        expected = [row['wall'] for row in rows
                    if ((row['rendered'] or row['heldID'] == row['id']) if kind == 'body'
                        else row['ToolkitCartMotion'] and not row['rendered'])]
        if len(expected) < 5:
            raise ValueError('Missing selected-scene ' + kind + ' action phase: ' + name)
        for wall in expected:
            index = bisect_left(times, wall)
            nearest = times[max(0, index - 1):index + 1]
            if not nearest or min(abs(value - wall) for value in nearest) > 250:
                raise ValueError('Missing selected-scene ' + kind + ' phase coverage: ' + name)
        summary[kind + 'RequiredSamples'] = len(expected)
    return summary


def _debug_coverage(cache, text, selection):
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    clips = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+) file=.+? frames=\d+ seconds=([\d.]+)', log)
    if [row[0] for row in clips] != selected_scenes(selection):
        raise ValueError('Selected cart scene receipts differ from the snapshot')
    bank = selection['cases'][0]
    windows = _load(Path(__file__).resolve().parents[3] / 'tests/native_queue/contributions/wooden_cart_motion/evidence/scene_windows.py')
    probes = {kind: [json.loads(line) for line in (cache / file).read_text().splitlines()]
              for kind, file in (('body', 'body-clearance.jsonl'), ('grip', 'wood-grip-poses.jsonl'))}
    result = []
    for name, start, duration in clips:
        seconds = windows.record_seconds(bank, name)
        if abs(float(duration) - seconds) > .2:
            raise ValueError('Selected cart clip has an incomplete recording window: ' + name)
        start = int(start)
        row = {'scene': name, 'recordSeconds': float(duration)}
        for kind, records in probes.items():
            selected = [r for r in records if start <= r['wallTimeMillis'] < start + seconds * 1000]
            if len({r['wallTimeMillis'] for r in selected}) < 5:
                raise ValueError('Missing selected-scene ' + kind + ' probe samples: ' + name)
            if kind == 'body' and any(len(r['cart']) != 16 or not all(math.isfinite(v) for v in r['cart']) for r in selected):
                raise ValueError('Invalid selected-scene cart matrices: ' + name)
            if kind == 'body' and any(r.get('female') is not name.startswith('female-') for r in selected):
                raise ValueError('Selected-scene body model differs from the requested scene: ' + name)
            row[kind + 'Samples'] = len(selected)
            if kind == 'grip':
                if any(type(r['result']) is not bool for r in selected):
                    raise ValueError('Invalid selected-scene grip result: ' + name)
                row['gripFailures'] = sum(not r['result'] for r in selected)
        if bank in ('interaction', 'wheel', 'interruption', 'interruption-matrix', 'repeat', 'hotkey'):
            row['actionCoverage'] = _debug_action_coverage(log, name, start, seconds, probes)
        result.append(row)
    _mesh_proof(cache, moving=bank not in ('interaction', 'wheel', 'interruption', 'interruption-matrix', 'repeat', 'hotkey'))
    return result


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
        row = next(row for row in rows if row['case'] == name)
        end_ms=row.get('measurementEndAfterCaseMs',metrics.get('measurementEndAfterCaseMs',11800))
        if type(end_ms) is not int or end_ms not in (11800,14800,15800,17800,28800):
            raise ValueError('Invalid native measurement window for ' + name)
        for kind, samples in (('body', body), ('grip', grip)):
            times = sorted(set(row['wallTimeMillis'] for row in samples if start + 800 < row['wallTimeMillis'] < start + end_ms))
            if len(times) < 5 or times[0] > start + 1500 or times[-1] < start + end_ms - 700 or max(b-a for a, b in zip(times, times[1:])) > 1000:
                raise ValueError('Incomplete ' + kind + ' probe window for ' + name)
        if row['gripSamples'] <= 0 or row['wheelFloorMaxError'] is None or any(row.get(kind, {}).get('samples', 0) <= 0 for kind in ('body', 'pants')):
            raise ValueError('Missing pose/mesh evidence for ' + name)
    _mesh_proof(cache)


def _variant_coverage(text, scenes):
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    records = [json.loads(line.split('[CART_VARIANT] PHASE ', 1)[1])
               for line in log.splitlines() if '[CART_VARIANT] PHASE ' in line]
    if [(row['case'], row['phase']) for row in records] != [(name, phase) for name in scenes for phase in VARIANT_PHASES]:
        raise ValueError('Missing, duplicate or reordered cart variant phases')
    result = []
    for name in scenes:
        rows = [row for row in records if row['case'] == name]
        first = rows[0]
        if (type(first['id']) is not int or first['id'] < 0 or not first['cargoIDs']
                or not isinstance(first['cargoWeight'], (int, float)) or not math.isfinite(first['cargoWeight'])
                or first['cargoWeight'] <= 0):
            raise ValueError('Missing exact cart/cargo identity: ' + name)
        for row in rows:
            ground = row['phase'].startswith('drop-')
            expected_id = -1 if ground else first['id']
            if (row['kind'] != VARIANTS[name] or row['id'] != first['id']
                    or row['cargoIDs'] != first['cargoIDs'] or row['cargoWeight'] != first['cargoWeight']
                    or row['primaryID'] != expected_id or row['secondaryID'] != expected_id
                    or row['inventoryCount'] != (0 if ground else 1) or row['worldCount'] != (1 if ground else 0)
                    or row['luaActions'] != 0 or row['nativeActions'] != 0 or row['hasPath'] is not False
                    or not isinstance(row['elapsed'], (int, float)) or not 0 < row['elapsed'] < 15000):
                raise ValueError('Cart variant ownership/terminal queue failed: ' + name + '/' + row['phase'])
            if row['phase'] in ('walk', 'run', 'sprint'):
                if (not isinstance(row['distance'], (int, float)) or not math.isfinite(row['distance'])
                        or row['distance'] < .25 or row['gaitSeen'] is not True):
                    raise ValueError('Cart variant native gait did not move: ' + name + '/' + row['phase'])
            if row['phase'] in ('pickup-near', 'pickup-far'):
                distance = row['approachDistance']
                if (not isinstance(distance, (int, float)) or not math.isfinite(distance)
                        or (distance < 2 if row['phase'] == 'pickup-far' else distance > 1)):
                    raise ValueError('Cart variant pickup approach not exercised: ' + name + '/' + row['phase'])
        result.append({'case': name, 'kind': VARIANTS[name], 'id': first['id'], 'phases': len(rows)})
    return {'functionalPass': True, 'cases': result}


def _controls_paused_gap(a, b, reference=None):
    gap=b['elapsed']-a['elapsed']
    if gap <= 500:
        return None
    frames=b['frame']-a['frame']
    distance=math.hypot(b['x']-a['x'],b['y']-a['y'])
    yaw=max(abs(math.atan2(math.sin(b[key]-a[key]),math.cos(b[key]-a[key])))
            for key in ('heading','acceptedHeading'))
    # Few native world updates plus a small pose change distinguish a stalled game from missing motion samples.
    if not (gap <= 2000 and 1 <= frames <= 4 and yaw <= .15):
        raise ValueError('Controls native sample gap lacks paused-frame evidence')
    proof = {'startElapsed':a['elapsed'],'wallGapMs':gap,'nativeFrames':frames,'distance':distance,'yaw':yaw}
    if distance <= .2:
        return proof
    if reference is None or a.get('phase') != 'sprint' or b.get('phase') != 'sprint' or a.get('case') not in VARIANTS:
        raise ValueError('Controls native sample gap lacks paused-frame evidence')
    c,d = reference
    ref_gap,ref_frames = d['elapsed']-c['elapsed'],d['frame']-c['frame']
    if (any(row.get('case') != a['case'] or row.get('phase') != 'sprint' for row in (b,c,d))
            or not 0 < ref_gap <= 500 or ref_frames <= 0 or d['elapsed'] > a['elapsed'] or d['frame'] > a['frame']):
        raise ValueError('Controls native sample gap lacks paused-frame evidence')
    # Native coordinates/accepted yaw are float32. Bound both endpoint rounding errors, not wall-clock speed.
    def spacing(value):
        return math.ldexp(1., max(-149, math.frexp(abs(value))[1]-24)) if value else math.ldexp(1.,-149)
    def position_error(first,last):
        return math.hypot(*(max(spacing(first[key]),spacing(last[key])) for key in ('x','y')))
    heading = a['acceptedHeading']
    heading_error = 2*max(spacing(row[key]) for row in (a,b,c,d) for key in ('heading','acceptedHeading'))
    if any(abs(math.atan2(math.sin(row[key]-heading),math.cos(row[key]-heading))) > heading_error
           for row in (a,b,c,d) for key in ('heading','acceptedHeading')):
        raise ValueError('Controls native sample gap lacks paused-frame evidence')
    def straight(first,last):
        dx,dy = last['x']-first['x'],last['y']-first['y']
        forward = dx*math.cos(heading)+dy*math.sin(heading)
        lateral = abs(-dx*math.sin(heading)+dy*math.cos(heading))
        return forward > 0 and lateral <= position_error(first,last)+math.hypot(dx,dy)*math.sin(heading_error)
    ref_distance = math.hypot(d['x']-c['x'],d['y']-c['y'])
    allowance = position_error(a,b)+frames*position_error(c,d)/ref_frames
    limit = frames*ref_distance/ref_frames+allowance
    if not straight(c,d) or not straight(a,b) or distance > limit:
        raise ValueError('Controls native sample gap lacks paused-frame evidence')
    proof.update(method='straight-sprint-native-budget',referenceStartElapsed=c['elapsed'],referenceWallGapMs=ref_gap,
                 referenceFrames=ref_frames,referenceDistance=ref_distance,referencePerUpdate=ref_distance/ref_frames,
                 float32Allowance=allowance,maxDistance=limit)
    return proof


def _controls_coverage(text, scenes):
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    records = [json.loads(line.split('[CART_CONTROLS] PHASE ', 1)[1])
               for line in log.splitlines() if '[CART_CONTROLS] PHASE ' in line]
    required = {'case', 'phase', 'kind', 'id', 'cargoID', 'cargoWeight', 'primaryID', 'secondaryID',
                'inventoryCount', 'worldCount', 'luaActions', 'nativeActions', 'hasPath',
                'drive', 'gait', 'gaitSeen', 'elapsed', 'samples'}
    if any(not isinstance(row, dict) or not required <= row.keys() for row in records):
        raise ValueError('Missing controls receipt identity/fields')
    expected = [(name, phase[0]) for name in scenes for phase in CONTROL_PHASES]
    if [(row['case'], row['phase']) for row in records] != expected:
        raise ValueError('Missing, duplicate or reordered controls phases')
    samples = {}
    for line in log.splitlines():
        if '[CART_CONTROLS] SAMPLE ' in line:
            row = json.loads(line.split('[CART_CONTROLS] SAMPLE ', 1)[1])
            if not isinstance(row, dict) or not {'case', 'phase', 'sample', 'elapsed', 'frame', 'x', 'y', 'heading', 'acceptedHeading'} <= row.keys():
                raise ValueError('Missing controls sample identity/fields')
            samples.setdefault((row['case'], row['phase']), []).append(row)
    if list(samples) != expected:
        raise ValueError('Missing, unexpected or reordered controls sample phases')
    wrap = lambda angle: math.atan2(math.sin(angle), math.cos(angle))
    result = []
    last_frame = None
    for name in scenes:
        identity = None
        previous = None
        measured = []
        for receipt, (phase, drive, gait, duration) in zip((row for row in records if row['case'] == name), CONTROL_PHASES):
            exact = tuple(receipt[key] for key in ('id', 'cargoID', 'cargoWeight'))
            if identity is None:
                identity = exact
            if (any(type(value) is not int or value < 0 for value in exact[:2])
                    or type(exact[2]) not in (int, float) or not math.isfinite(exact[2]) or abs(exact[2]-1) > .001
                    or exact != identity or receipt['kind'] != VARIANTS[name]
                    or receipt['primaryID'] != exact[0] or receipt['secondaryID'] != exact[0]
                    or receipt['inventoryCount'] != 1 or receipt['worldCount'] != 0
                    or receipt['luaActions'] != 0 or receipt['nativeActions'] != 0 or receipt['hasPath'] is not False
                    or receipt['drive'] != drive or receipt['gait'] != gait or receipt['gaitSeen'] is not True):
                raise ValueError('Controls identity, ownership, queue or native gait failed: ' + name + '/' + phase)
            rows = samples[name, phase]
            if (len(rows) < 4 or receipt['samples'] != len(rows)
                    or [row['sample'] for row in rows] != list(range(len(rows)))
                    or any(type(row[key]) not in (int, float) or not math.isfinite(row[key])
                           for row in rows for key in ('elapsed', 'x', 'y', 'heading', 'acceptedHeading'))
                    or any(type(row['frame']) is not int or row['frame'] < 0 for row in rows)
                    or last_frame is not None and rows[0]['frame'] < last_frame
                    or rows[0]['elapsed'] != 0 or not duration <= rows[-1]['elapsed'] < duration+2000
                    or receipt['elapsed'] != rows[-1]['elapsed']
                    or any(b['elapsed'] <= a['elapsed'] or b['frame'] <= a['frame'] for a, b in zip(rows, rows[1:]))):
                raise ValueError('Incomplete or reordered controls native samples: ' + name + '/' + phase)
            paused_gaps,reference = [],None
            for a,b in zip(rows,rows[1:]):
                proof = _controls_paused_gap(a,b,reference)
                if proof is not None:
                    paused_gaps.append(proof)
                elif b['elapsed']-a['elapsed'] <= 500:
                    reference = (a,b)
            if phase in CONTROL_POSES:
                if any(abs(wrap(rows[0][key]-CONTROL_POSES[phase])) > .02 for key in ('heading', 'acceptedHeading')):
                    raise ValueError('Controls initial heading not exercised: ' + name + '/' + phase)
            elif previous is None or any(abs(rows[0][key]-previous[key]) > .001 for key in ('x', 'y', 'heading', 'acceptedHeading')):
                raise ValueError('Controls continuous transition was repositioned: ' + name + '/' + phase)
            yaw = travel = 0
            segments = []
            for a, b in zip(rows, rows[1:]):
                turn = wrap(b['heading']-a['heading'])
                if abs(turn) > 1:
                    raise ValueError('Controls yaw sample gap/snap: ' + name + '/' + phase)
                dx, dy = b['x']-a['x'], b['y']-a['y']
                mid = a['heading']+turn/2
                forward = dx*math.cos(mid)+dy*math.sin(mid)
                yaw += turn; travel += forward
                segments.append((b['elapsed'], forward, math.hypot(dx, dy), b['elapsed']-a['elapsed']))
            if phase in ('left-held', 'right-held'):
                correct = yaw*(-1 if drive == 5 else 1) > math.pi and travel > .4
            elif phase in ('pivot-left', 'pivot-right'):
                correct = yaw*(-1 if drive == 2 else 1) > .25 and abs(travel) < .12
            elif phase == 'pivot-release':
                correct = abs(yaw) < .1 and abs(travel) < .05
            elif phase in ('left-release', 'right-release'):
                accepted = rows[1:]
                accepted_arc = sum(abs(wrap(b['acceptedHeading']-a['acceptedHeading'])) for a, b in zip(accepted, accepted[1:]))
                visual_arc = sum(abs(wrap(b['heading']-a['heading'])) for a, b in zip(rows, rows[1:]))
                late = [row for row in rows if row['elapsed'] >= 350]
                late_arc = sum(abs(wrap(b['heading']-a['heading'])) for a, b in zip(late, late[1:]))
                # Accepted yaw must stop; the native animated body can finish its existing blend.
                correct = (accepted_arc < .02 and visual_arc < .5 and travel > .1
                           and len(late) >= 2 and late[-1]['elapsed']-late[0]['elapsed'] >= 100
                           and late_arc < .02 and all(abs(wrap(row['heading']-row['acceptedHeading'])) < .03 for row in late))
            elif phase in ('reverse-left', 'reverse-right'):
                correct = yaw*(1 if drive == 6 else -1) > .2 and travel < -.15
            elif phase == 'moving-reverse':
                correct = sum(row[1] for row in segments if row[0] > duration/2) < -.1 and abs(yaw) < .25
                if name == 'wooden-wheelbarrow':
                    correct = correct and any(row[1] > .001 for row in segments[:3])
            elif phase.endswith('-stop'):
                tail = [row for row in segments if row[0] > rows[-1]['elapsed']-300]
                correct = abs(yaw) < .25 and sum(row[2] for row in tail)/sum(row[3] for row in tail)*1000 < .1
            else:
                correct = abs(yaw) < .25 and (travel < -.15 if drive == 4 else travel > .1)
            if not correct:
                release = (' acceptedYawArc=' + str(accepted_arc) + ' visualYawArc=' + str(visual_arc)
                           + ' lateVisualYawArc=' + str(late_arc)) if phase in ('left-release', 'right-release') else ''
                raise ValueError('Controls relative movement/yaw failed: ' + name + '/' + phase
                                 + ' travel=' + str(travel) + ' yaw=' + str(yaw) + release)
            detail = {'phase': phase, 'travel': travel, 'yaw': yaw, 'samples': len(rows)}
            if paused_gaps:
                detail['pausedFrameGaps'] = paused_gaps
            if phase in ('left-release', 'right-release'):
                detail.update(acceptedYawArc=accepted_arc, visualYawArc=visual_arc, lateVisualYawArc=late_arc)
            measured.append(detail)
            previous = rows[-1]
            last_frame = rows[-1]['frame']
        result.append({'case': name, 'kind': VARIANTS[name], 'id': identity[0], 'phases': measured})
    return {'controlsVerified': True, 'cases': result}


NATIVE_E_PHASES = ('native-before', 'pickup', 'drop-long', 'pickup-cancel', 'pickup-repeat', 'drop-repeat', 'native-after')


def _native_e_coverage(text):
    records = [json.loads(line.split('[CART_NATIVE_E] RECEIPT ', 1)[1])
               for line in text.splitlines() if '[CART_NATIVE_E] RECEIPT ' in line]
    if [row.get('phase') for row in records] != list(NATIVE_E_PHASES):
        raise ValueError('Missing, duplicate or reordered native E phases')
    first = records[0]
    if any(type(first.get(key)) is not int or first[key] < 0 for key in ('id', 'cargoID')):
        raise ValueError('Missing exact native E cart/cargo identity')
    for row in records:
        phase = row['phase']
        native = phase in ('native-before', 'native-after')
        ground = phase not in ('pickup', 'pickup-repeat')
        expected_id = -1 if ground else first['id']
        if (row.get('id') != first['id'] or row.get('cargoID') != first['cargoID'] or row.get('key') != 18
                or row.get('cargoWeight') != 1 or row.get('cargoType') != 'Base.Log'
                or row.get('doorOpen') is not native or row.get('capturedSeen') is not (not native)
                or row.get('ignoreRestored') is not True or row.get('nativeDownSeen') is not True
                or row.get('inventoryCount') != int(not ground) or row.get('worldCount') != int(ground)
                or row.get('primaryID') != expected_id or row.get('secondaryID') != expected_id
                or row.get('luaActions') != 0 or row.get('nativeActions') != 0 or row.get('hasPath') is not False
                or row.get('cancelled') is not (phase == 'pickup-cancel')
                or not isinstance(row.get('elapsed'), (int, float)) or not math.isfinite(row['elapsed'])
                or row['elapsed'] < (900 if phase == 'drop-long' else 150)
                or phase == 'drop-long' and row.get('longSeen') is not True):
            raise ValueError('Native E door priority/input/ownership/release proof failed: ' + phase)
    return {'nativeEVerified': True, 'phases': records}


def verify(root, selection, catalog):
    root = Path(root)
    if selection['suite'] == SP and selection['cases'] == ['manual']:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        ready = '[WOOD_PROTOTYPE] BOOTSTRAP_READY' in text and '[WOOD_PROTOTYPE] BOOTSTRAP_FAIL' not in text
        issues = [] if ready else ['Manual cart world did not become ready']
        return {'issues': issues, 'evidence': {'manualReview': True}, 'outcomes': [
            {'actor': 'client1', 'case': 'manual', 'status': 'captured' if ready else 'failed',
             'reason': 'Manual human review only; no automated animation verification',
             'outcome': {'manualReview': True, 'animationEquivalencePass': False, 'evidenceComplete': False}}]}
    project = Path(__file__).resolve().parents[3]
    intake = _intake(project, selection['suite'])
    roles = ['client1'] if selection['suite'] == SP else ['client1', 'client2']
    debug = selection['suite'] == SP and 'cart_scenes' in selection.get('options', {})
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
            if any(marker in text for marker in ('[WOOD_PROTOTYPE] BOOTSTRAP_FAIL', '[WOOD_BANK] FAIL', '[CART_VARIANT] FAIL', '[CART_CONTROLS] FAIL', '[CART_NATIVE_E] FAIL', '[QUEUE_TEST] FAIL', '[CLEARANCE_PROBE] ERROR', '[GRIP_POSE_PROBE] ERROR', '[WOOD_WHEEL_NATIVE_PROBE] ERROR')):
                raise ValueError('Cart capture contains fixture/probe errors')
        evidence['videos'] = {role: _videos(root, selection, role, text) for role, text in texts.items()}
        if selection['suite'] == SP and selection['cases'] == ['native-e']:
            report = _native_e_coverage(texts['client1'])
            _write(analysis / 'native-e.json', json.dumps(report, indent=2, allow_nan=False))
            evidence.update(nativeE=report, analysis=str(analysis), evidenceComplete=True,
                            scope='SP native E against a real door; cart priority, long hold, cancellation/repeat and restored ordinary interaction')
            return {'issues': [], 'evidence': evidence, 'outcomes': [
                {'actor': 'client1', 'case': 'native-e', 'status': 'captured',
                 'reason': 'Native held E input and registered callbacks retain cart priority and restore ordinary door interaction',
                 'outcome': {'animationEquivalencePass': False, 'evidenceComplete': True,
                             'nativeEVerified': True, 'functionalPass': True}}]}
        if selection['suite'] == SP and selection['cases'] == ['controls']:
            report = _controls_coverage(texts['client1'], selected_scenes(selection))
            _write(analysis / 'controls.json', json.dumps(report, indent=2, allow_nan=False))
            evidence.update(controls=report, analysis=str(analysis), evidenceComplete=True,
                            scope='SP physical keyboard controls with light cargo; animation and mesh equivalence are not assessed')
            return {'issues': [], 'evidence': evidence, 'outcomes': [
                {'actor': 'client1', 'case': 'controls', 'status': 'captured',
                 'reason': 'Native relative keyboard movement, held/released yaw, reverse and stops captured',
                 'outcome': {'animationEquivalencePass': False, 'evidenceComplete': True,
                             'controlsVerified': True, 'partialCoverage': debug,
                             'selectedScenes': selected_scenes(selection)}}]}
        if selection['suite'] == SP and selection['cases'] == ['variants']:
            report = _variant_coverage(texts['client1'], selected_scenes(selection))
            _write(analysis / 'variants.json', json.dumps(report, indent=2, allow_nan=False))
            evidence.update(variants=report, analysis=str(analysis), evidenceComplete=True,
                            scope='SP usability; wooden mesh, IK and cosmetic equivalence are not assessed')
            return {'issues': [], 'evidence': evidence, 'outcomes': [
                {'actor': 'client1', 'case': 'variants', 'status': 'captured',
                 'reason': 'Native cart menu pickup/equip, Walk/Run/Sprint and drop/repeat ownership verified',
                 'outcome': {'animationEquivalencePass': False, 'evidenceComplete': True,
                             'functionalPass': True, 'partialCoverage': debug,
                             'selectedScenes': selected_scenes(selection)}}]}
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
            if case not in ('interaction', 'interruption', 'interruption-matrix', 'wheel', 'repeat', 'hotkey', 'impact'):
                scene_contract = analysis / 'selected-scenes.json'
                windows = _load(ev / 'scene_windows.py')
                _write(scene_contract, json.dumps(windows.contract(case, selected_scenes(selection)), indent=2))
                commands.append(('native', [sys.executable, str(ev / 'analyze-native.py'), '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis), '--scenes', str(scene_contract)]))
            evidence['analyzers'] = {name: _run(command, analysis, name) for name, command in commands}
            if case == 'impact':
                impact = _load(intake / 'analyze-impact.py').analyze(cache, texts['client1'], selected_scenes(selection))
                _write(analysis / 'impact.json', json.dumps(impact, indent=2, allow_nan=False))
                if not impact['functionalPass']:
                    raise ValueError('Native impact recovery failed: ' + str(impact['failures']))
                evidence.update(impact=impact, analysis=str(analysis), evidenceComplete=True)
                return {'issues': [], 'evidence': evidence, 'outcomes': [
                    {'actor': 'client1', 'case': case, 'status': 'captured',
                     'reason': 'Guarded Sprint contact and explicitly injected native collision event; visual review remains separate',
                     'outcome': {'animationEquivalencePass': False, 'evidenceComplete': True,
                                 'partialCoverage': debug, 'nativeRecoveryVerified': True}}]}
            if debug:
                if case not in ('interaction', 'interruption', 'interruption-matrix', 'wheel', 'repeat', 'hotkey'):
                    _coverage(cache, texts['client1'], len(selected_scenes(selection)), _json(analysis / 'native-metrics.json'))
                evidence.update(scope='selected-scenes', selectedScenes=selected_scenes(selection),
                                fullSceneCount=SP_CASES[case][1], diagnosticOnly=True, evidenceComplete=True,
                                sceneProbes=_debug_coverage(cache, texts['client1'], selection), analysis=str(analysis))
                return {'issues': [], 'evidence': evidence, 'outcomes': [
                    {'actor': 'client1', 'case': case, 'status': 'captured',
                     'reason': 'Selected-scene debug capture only; full matrix and motion gates were not run',
                     'outcome': {'animationEquivalencePass': False, 'evidenceComplete': True,
                                 'partialCoverage': True, 'selectedScenes': selected_scenes(selection),
                                 'fullSceneCount': SP_CASES[case][1]}}]}
            if case == 'wheel':
                evidence['analyzers'][case] = _run([sys.executable, str(intake / 'analyze-wheel-cycle.py'),
                    '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis / 'wheel-cycle.json')], analysis, case)
                evidence['wheel'] = _json(analysis / 'wheel-cycle.json')
                if not evidence['wheel']['pass']:
                    raise ValueError('Wheel cycle verification failed: ' + str(evidence['wheel']['failures']))
                evidence['nativeMotionNotApplicable'] = True
            elif case in ('repeat', 'hotkey'):
                evidence['analyzers'][case] = _run([sys.executable, str(intake / 'analyze-repeat.py'),
                    '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis / 'repeat.json')] + (['--hotkey'] if case == 'hotkey' else []), analysis, case)
                evidence['repeat'] = _json(analysis / 'repeat.json')
                if not all(evidence['repeat'].get(key) for key in ('functionalPass', 'clockVerified', 'recoveryVerified', 'wheelCoverageVerified')):
                    raise ValueError('Rapid repeat verification failed: ' + str(evidence['repeat']['failures']))
                evidence['nativeMotionNotApplicable'] = True
            elif case in ('interruption', 'interruption-matrix'):
                evidence['analyzers'][case] = _run([sys.executable, str(intake / 'analyze-interruption.py'),
                    '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis / 'interruption.json')] + (['--matrix'] if case == 'interruption-matrix' else []), analysis, case)
                evidence['interruption'] = _json(analysis / 'interruption.json')
                if not all(evidence['interruption'].get(key) for key in ('functionalPass','recoveryVerified','wheelCoverageVerified')):
                    raise ValueError('Interruption verification failed: ' + str(evidence['interruption']['failures']))
                evidence['nativeMotionNotApplicable'] = True
            elif case == 'interaction':
                evidence['analyzers'][case] = _run([sys.executable, str(intake / 'analyze-interaction.py'),
                    '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis / 'interaction.json')], analysis, case)
                report = _json(analysis / 'interaction.json')
                evidence['interaction'] = report
                if not report['functionalPass'] or not report['ikCoverageVerified']:
                    raise ValueError('Interaction functional/rendered IK verification failed: ' + str(report['failures']))
                if not report['worldHandoff']['pass']:
                    raise ValueError('Interaction world/held handoff failed: ' + str(report['worldHandoff']['failures']))
                if not report['entryMotion']['pass']:
                    raise ValueError('Interaction pickup entry motion failed: ' + str(report['entryMotion']['failures']))
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
            elif case in ('stop', 'stop-timing', 'stationary', 'maneuvers', 'collision', 'footprint', 'path', 'vehicles', 'brace', 'fast-slide', 'wall-exit', 'wall-manual-exit', 'wall-fast-manual-exit'):
                analyzer='footprint' if case in ('collision','fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit') else case
                evidence['analyzers'][case] = _run([sys.executable, str(intake / ('analyze-' + analyzer + '.py')),
                    '--profile', str(cache), '--log', str(logs['client1']), '--output', str(analysis / (case + '-motion.json'))] + (['--'+case] if case in ('fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit') else []), analysis, case)
                evidence['motion'] = _json(analysis / (case + '-motion.json'))
                if case == 'stop-timing' and not evidence['motion'].get('timingVerified'):
                    raise ValueError('Stop timing capture did not verify its measurement windows')
                if case == 'stop-timing' and not evidence['motion'].get('residualBrakingVerified'):
                    raise ValueError('Native residual-speed stop transitions were not verified')
                if case == 'path' and not all(evidence['motion'].get(key) for key in ('motionPass', 'footprintVerified')):
                    raise ValueError('Native path/footprint verification failed: ' + str(evidence['motion'].get('failures')))
                if case in ('vehicles','brace','fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit') and not all(evidence['motion'].get(key) for key in ('motionPass', 'footprintPass')):
                    raise ValueError('Native '+case+' motion/footprint verification failed: ' + str({key: evidence['motion'].get(key) for key in ('motionFailures', 'footprintFailures')}))
            elif case == 'reversal':
                motion = _load(intake / 'analyze-reversal.py').analyze(texts['client1'])
                evidence['motion'] = motion
                _write(analysis / 'reversal-motion.json', json.dumps(motion, indent=2, allow_nan=False))
            if case not in ('interaction', 'interruption', 'interruption-matrix', 'wheel', 'repeat', 'hotkey'):
                _coverage(cache, texts['client1'], SP_CASES[case][1], metrics)
                evidence['nativeSelectedScenes'] = selected_scenes(selection)
            evidence['evidenceComplete'] = True
        evidence['analysis'] = str(analysis)
    except (ValueError, OSError, KeyError, TypeError, AssertionError, subprocess.SubprocessError) as error:
        issues.append(str(error))
    outcome = {'animationEquivalencePass': False, 'evidenceComplete': not issues}
    if debug:
        outcome.update(partialCoverage=True, selectedScenes=selection['options']['cart_scenes'],
                       fullSceneCount=SP_CASES[selection['cases'][0]][1])
    return {'issues': issues, 'evidence': evidence, 'outcomes': [
        {'actor': role, 'case': selection['cases'][0], 'status': 'failed' if issues else 'captured',
         'reason': '; '.join(issues) if issues else ('Native pickup/setdown functional and render coverage verified; geometry and videos require review'
             if selection['suite'] == SP and selection['cases'] == ['interaction'] else 'Capture coverage verified; motion, geometry and replication diagnostics require review'),
         'outcome': outcome} for role in roles]}
