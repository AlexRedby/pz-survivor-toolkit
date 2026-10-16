"""Stage the retained video, item-tag and animal fixtures without launching them."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


ANIMAL_CASES = {
    'equipment-fixed': ('equipment', 'shared', 'held'),
    'equipment-missing': ('equipment', 'shared', 'missing'),
    'ghost': ('ghost', 'shared', 'held'),
    'timer-shared': ('timer', 'shared', 'held'),
    'timer-starved': ('timer', 'starved', 'held'),
    'combined-shared': ('combined', 'shared', 'held'),
    'combined-starved': ('combined', 'starved', 'held'),
}
ITEM_MODS = ['NeatUI_Framework', 'CleanUI', 'PZSurvivorToolkit', 'EURY_CONTAINERS',
             'Quartermaster', 'BravoItemDetails', 'organizedCategories_core']
PNG = b'\x89PNG\r\n\x1a\n'


def definitions():
    result = {}
    for suite, cases, kind, languages, mods in (
        ('video-recording', ['captures'], 'sp', ['EN', 'RU'], ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']),
        ('item-tags', ['scenes'], 'sp', ['RU'], ITEM_MODS),
        ('animal-trailer', list(ANIMAL_CASES), 'mp', ['EN'], ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']),
    ):
        result[suite] = {'status': 'ready', 'clients': 1, 'default_mods': list(mods),
                         'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                    'kinds': [kind], 'languages': languages, 'modes': ['toolkit', 'native']}
                                   for case in cases]}
    return result


def _intake(project, suite):
    return Path(project) / 'tests/native_queue/contributions' / suite


def _load(path):
    spec = importlib.util.spec_from_file_location('auxiliary_' + path.parent.name.replace('-', '_') + '_' + path.stem, path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module


def _path(selection, key, executable=False):
    value = selection.get('options', {}).get(key)
    if not isinstance(value, str) or not Path(value).is_absolute():
        raise ValueError('Explicit absolute options.' + key + ' is required')
    path = Path(value).resolve(strict=True)
    if not path.is_file() or executable and not os.access(path, os.X_OK):
        raise ValueError('Missing executable/file for options.' + key)
    return path


def validate(selection):
    suite = selection['suite']
    if selection.get('mode') not in ('toolkit', 'native'):
        raise ValueError('Unsupported auxiliary queue mode')
    spec = definitions()[suite]
    if len(selection['cases']) != 1 or selection['cases'][0] not in [case['id'] for case in spec['cases']]:
        raise ValueError('Auxiliary fixtures require exactly one supported case per fresh run')
    case = spec['cases'][0]
    if selection['kind'] not in case['kinds'] or len(selection['languages']) != 1 or selection['languages'][0] not in case['languages']:
        raise ValueError('Unsupported kind/language for ' + suite)
    required = set(ITEM_MODS if suite == 'item-tags' else ['ZombieBuddy', 'PZSurvivorToolkit'])
    if suite == 'video-recording':
        required.add('PZToolkitJavaPatches')
        for key in ('ffmpeg', 'ffprobe'):
            _path(selection, key, executable=True)
    if suite == 'animal-trailer':
        _path(selection, 'patch_jar')
        scenario, timer, hands = ANIMAL_CASES[selection['cases'][0]]
        if hands == 'missing':
            if 'PZToolkitJavaPatches' in selection['mods']:
                raise ValueError('Equipment missing-hands control must omit PZToolkitJavaPatches')
        else:
            required.add('PZToolkitJavaPatches')
        if scenario in ('timer', 'combined') and timer == 'shared':
            required.add('AnimalTrailerSyncMPFix')
        elif 'AnimalTrailerSyncMPFix' in selection['mods']:
            raise ValueError('This control must omit AnimalTrailerSyncMPFix')
    if not required <= set(selection['mods']):
        raise ValueError('Required fixture mods missing: ' + ', '.join(sorted(required - set(selection['mods']))))
    if suite == 'item-tags':
        selected = [mod for mod in selection['mods'] if mod in ITEM_MODS]
        if selected != ITEM_MODS:
            raise ValueError('Item-tag dependencies must retain the manifest load order')


def sources(project, selection):
    paths = [path for path in _intake(project, selection['suite']).rglob('*')
             if path.is_file() and path.suffix in ('.py', '.java', '.lua', '.json', '.md')]
    if selection['suite'] == 'video-recording':
        paths += [_path(selection, key, executable=True) for key in ('ffmpeg', 'ffprobe')]
    if selection['suite'] == 'animal-trailer':
        paths.append(_path(selection, 'patch_jar'))
    return paths


def _write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    suite = selection['suite']
    intake = _intake(project, suite)
    fixture = runtime.setdefault('fixture', {})
    caches = [Path(config['cache']) for config in runtime['roles'].values()]
    if suite == 'video-recording':
        fixture['mods'] = ['VideoFixture']
        for cache in caches:
            helper = cache / 'mods/VideoFixture/42'
            _write(helper / 'mod.info', 'name=Video Fixture\nid=VideoFixture\nversionMin=42.21\n')
            client = helper / 'media/lua/client'
            client.mkdir(parents=True)
            shutil.copy2(intake / 'VideoFixture.lua', client / 'ZZVideoFixture.lua')
            config = {'output': str(cache / 'videos'), 'outside': str(output.parent), 'ffmpeg': str(_path(selection, 'ffmpeg', True))}
            _write(client / 'ToolkitVideoConfig.lua', 'return {' + ','.join(key + '=' + json.dumps(value, ensure_ascii=False) for key, value in config.items()) + '}\n')
    elif suite == 'item-tags':
        fixture['mods'] = ['QuartermasterScreens']
        prepare = _load(intake / 'prepare.py')
        for cache in caches:
            helper = cache / 'mods/QuartermasterScreens'
            prepare.prepare(locations['PZSurvivorToolkit'], helper)
            options = cache / 'options.ini'
            options.write_text(options.read_text().replace('height=720', 'height=900'), encoding='utf-8')
            _write(helper / '42/media/lua/client/ZZQuartermasterSetup.lua', """local function setup()
 Events.OnTick.Remove(setup)
 PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ItemTags'):setValue(true)
 local options=require 'BetterContainers/_Options'
 local helpers=require 'BetterContainers/Helpers'
 PZAPI.ModOptions:getOptions(helpers.MODULE_ID):getOption('showAdvancedDisplayCategories'):setValue(false)
 options.showAdvancedDisplayCategories=false
 assert(PZSurvivorToolkit.ItemTags.enabled() and not options.showAdvancedDisplayCategories)
 print('[QM_SCREEN] SETTINGS_READY')
end
Events.OnGameStart.Add(function() Events.OnTick.Add(setup) end)
""")
    else:
        scenario, timer, hands = ANIMAL_CASES[selection['cases'][0]]
        if scenario in ('timer', 'combined') and timer == 'shared':
            expected = json.loads((intake / 'manifest.json').read_text())['dependencies']['timer_fixed']['jar_sha256']
            jars = list(Path(locations['AnimalTrailerSyncMPFix']).rglob('*.jar'))
            if not any(hashlib.sha256(jar.read_bytes()).hexdigest() == expected for jar in jars):
                raise ValueError('AnimalTrailerSyncMPFix must contain the exact tested 1.3 JAR')
        staged = Path(output) / 'animal-fixtures'
        _load(intake / 'build.py').build(Path(game), Path(jdk), _path(selection, 'patch_jar'), staged, scenario)
        manifest = json.loads((staged / 'runtime-manifest.json').read_text())
        fixture['mods'] = manifest['helper_mod_ids']
        fixture['server_ready'] = '[ANIMAL_TRAILER] SERVER READY'
        fixture['failure_markers'] = ['[ANIMAL_TRAILER] CLIENT MISSING ']
        for cache in caches:
            for identifier in fixture['mods']:
                shutil.copytree(staged / 'mods' / identifier, cache / 'mods' / identifier)
            config = cache / 'mods/AnimalTrailerBaseline/42/media/lua/shared/ZAnimalTrailerConfig.lua'
            config.write_text(config.read_text() + 'AnimalTrailerFixtureConfig.connect={host="127.0.0.1",port=' + str(selection['ports'][0]) + ',username="animal-fixture",password="isolated-native-only"}\n', encoding='utf-8')
    for cache in caches:
        for identifier in fixture['mods']:
            for layer in ('common', '42'):
                for directory in ('AnimSets', 'actiongroups'):
                    (cache / 'mods' / identifier / layer / 'media' / directory).mkdir(parents=True, exist_ok=True)


def complete(selection, role, text):
    marker = {'video-recording': '[VIDEO_TEST] PASSED', 'item-tags': '[QM_SCREEN] COMPLETE',
              'animal-trailer': '[ANIMAL_TRAILER] CLIENT COMPLETE'}[selection['suite']]
    return marker in text


def _client_text(root):
    # console.txt is the source expected by the retained recorder verifier.
    cache = Path(root) / 'client1'
    console = cache / 'console.txt'
    return console.read_text(errors='replace') if console.is_file() else (Path(root) / 'client1-launch.log').read_text(errors='replace')


def verify(root, selection, catalog):
    root = Path(root)
    suite = selection['suite']
    project = Path(__file__).resolve().parents[3]
    intake = _intake(project, suite)
    issues, evidence = [], {}
    try:
        text = _client_text(root)
        if not complete(selection, 'client1', text):
            raise ValueError('Missing fixture completion marker')
        if suite == 'video-recording':
            evidence['clips'] = _load(intake / 'verify.py').verify(root / 'client1', _path(selection, 'ffmpeg', True), _path(selection, 'ffprobe', True))
        elif suite == 'item-tags':
            manifest = json.loads((intake / 'manifest.json').read_text())
            if '[QM_SCREEN] FAIL' in text or 'KahluaException' in text:
                raise ValueError('Item-tag fixture reported a failure')
            for marker in ('[QM_SCREEN] SETTINGS_READY', '[QM_SCREEN] VISUAL ', '[QM_SCREEN] SAVE exact IDs and reopen passed', '[QM_SCREEN] GEOM list ', '[QM_SCREEN] GEOM clean '):
                if marker not in text:
                    raise ValueError('Missing item-tag assertion evidence: ' + marker)
            shots = re.findall(r'\[QM_SCREEN\] SHOT (\S+)', text)
            expected = [name.removeprefix('tags-').removesuffix('.png') for name in manifest['expected_screenshots']]
            if shots != expected:
                raise ValueError('Expected exactly five ordered item-tag screenshot markers')
            screenshots = []
            for name in manifest['expected_screenshots']:
                path = root / 'client1/Screenshots' / name
                if not path.is_file() or path.read_bytes()[:8] != PNG:
                    raise ValueError('Missing/invalid screenshot: ' + str(path))
                screenshots.append(str(path))
            evidence['screenshots'] = screenshots
        else:
            scenario, timer, hands = ANIMAL_CASES[selection['cases'][0]]
            server = (root / 'server-launch.log').read_text(errors='replace')
            evidence['verification'] = _load(intake / 'verify.py').verify(server, text, scenario, timer, hands)
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': selection['cases'][0],
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues),
            'outcome': {'fixture': suite}}], 'evidence': evidence}
