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
             'organizedCategories_core']
INVENTORY_MODS = list(ITEM_MODS)
PNG = b'\x89PNG\r\n\x1a\n'


def definitions():
    result = {}
    for suite, cases, kind, languages, mods in (
        ('video-recording', ['captures'], 'sp', ['EN', 'RU'], ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']),
        ('item-tags', ['scenes'], 'sp', ['RU'], ITEM_MODS),
        ('inventory-presentation', ['scenes'], 'sp', ['EN'], INVENTORY_MODS),
        ('smart-deposit', ['partial'], 'sp', ['EN'], INVENTORY_MODS),
        ('inventory-tooltips', ['scenes'], 'sp', ['EN'], INVENTORY_MODS + ['VHSSkillNameInTooltip', 'EURY_CLOTHINGINFO']),
        ('animal-trailer', list(ANIMAL_CASES), 'mp', ['EN'], ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']),
    ):
        result[suite] = {'status': 'ready', 'clients': 1, 'default_mods': list(mods),
                         'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                    'kinds': [kind], 'languages': languages, 'modes': ['toolkit', 'native']}
                                   for case in cases]}
    result['item-tags']['window_size'] = [1280, 900]
    result['inventory-presentation']['window_size'] = [1280, 900]
    result['smart-deposit']['window_size'] = [1280, 900]
    result['inventory-tooltips']['window_size'] = [1280, 900]
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
    cases = selection['cases']
    if not cases or len(set(cases)) != len(cases) or any(case not in [row['id'] for row in spec['cases']] for case in cases) or suite != 'animal-trailer' and len(cases) != 1:
        raise ValueError('Auxiliary fixtures require exactly one supported case per fresh run')
    case = spec['cases'][0]
    if selection['kind'] not in case['kinds'] or len(selection['languages']) != 1 or selection['languages'][0] not in case['languages']:
        raise ValueError('Unsupported kind/language for ' + suite)
    required = set(ITEM_MODS if suite == 'item-tags' else ['ZombieBuddy', 'PZSurvivorToolkit'])
    if suite in ('inventory-presentation', 'smart-deposit', 'inventory-tooltips'):
        required = set(INVENTORY_MODS)
        if suite == 'inventory-tooltips':
            required.update(('VHSSkillNameInTooltip', 'EURY_CLOTHINGINFO'))
        forbidden = {'ContainerCapacityIndicator', 'BravoItemDetails', 'Quartermaster', 'HasResearch', 'SeedSeasonIndicator'} & set(selection['mods'])
        if forbidden:
            raise ValueError('External inventory owners must be omitted: ' + ', '.join(sorted(forbidden)))
    if suite == 'video-recording':
        required.add('PZToolkitJavaPatches')
        for key in ('ffmpeg', 'ffprobe'):
            _path(selection, key, executable=True)
    if suite == 'animal-trailer':
        _path(selection, 'patch_jar')
        if type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1:
            raise ValueError('Animal fixtures require one actual client')
        environments = {case == 'equipment-missing' for case in cases}
        timers = {ANIMAL_CASES[case][0] in ('timer', 'combined') and ANIMAL_CASES[case][1] == 'shared' for case in cases}
        if len(environments) != 1 or len(timers) != 1 or len(cases) > 1 and cases[0] == 'equipment-missing':
            raise ValueError('Animal cases require the same immutable patch/timer JAR environment; missing controls stay isolated')
        scenario, timer, hands = ANIMAL_CASES[cases[0]]
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
        if selected != ITEM_MODS and not selection.get('options', {}).get('pack_lock'):
            raise ValueError('Item-tag dependencies must retain the manifest load order')


def sources(project, selection):
    paths = [path for path in _intake(project, selection['suite']).rglob('*')
             if path.is_file() and path.suffix in ('.py', '.java', '.lua', '.json', '.md')]
    if selection['suite'] == 'video-recording':
        paths += [_path(selection, key, executable=True) for key in ('ffmpeg', 'ffprobe')]
    if selection['suite'] == 'animal-trailer':
        paths.append(_path(selection, 'patch_jar'))
        if len(selection['cases']) > 1:
            paths.append(Path(project) / 'tests/native_queue/support/QueueFixtureSession.lua')
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
            config = {'output': str(cache / 'videos'), 'ffmpeg': str(_path(selection, 'ffmpeg', True))}
            _write(client / 'ToolkitVideoConfig.lua', 'return {' + ','.join(key + '=' + json.dumps(value, ensure_ascii=False) for key, value in config.items()) + '}\n')
    elif suite in ('inventory-presentation', 'smart-deposit', 'inventory-tooltips'):
        manifest = json.loads((intake / 'manifest.json').read_text())
        identifier = manifest['helper_mod_id']
        fixture['mods'] = [identifier]
        fixture['failure_markers'] = [manifest['failure_marker']]
        for cache in caches:
            _load(intake / 'prepare.py').prepare(locations['PZSurvivorToolkit'], cache / 'mods' / identifier)
    elif suite == 'item-tags':
        fixture['mods'] = ['QuartermasterScreens']
        prepare = _load(intake / 'prepare.py')
        for cache in caches:
            helper = cache / 'mods/QuartermasterScreens'
            prepare.prepare(locations['PZSurvivorToolkit'], helper)
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
        builder = _load(intake / 'build.py')
        if len(selection['cases']) > 1:
            builder.build(Path(game), Path(jdk), _path(selection, 'patch_jar'), staged, scenario, cases=selection['cases'])
        else:
            builder.build(Path(game), Path(jdk), _path(selection, 'patch_jar'), staged, scenario)
        manifest = json.loads((staged / 'runtime-manifest.json').read_text())
        fixture['mods'] = manifest['helper_mod_ids']
        fixture['server_ready'] = '[ANIMAL_TRAILER] SERVER READY'
        fixture['failure_markers'] = ['[ANIMAL_TRAILER] CLIENT MISSING ']
        if len(selection['cases']) > 1:
            fixture['failure_markers'].append('[QUEUE_SESSION] QUARANTINE ')
        for cache in caches:
            for identifier in fixture['mods']:
                shutil.copytree(staged / 'mods' / identifier, cache / 'mods' / identifier)
            config = cache / 'mods/AnimalTrailerBaseline/42/media/lua/shared/ZAnimalTrailerConfig.lua'
            username = 'client1' if len(selection['cases']) > 1 else 'animal-fixture'
            config.write_text(config.read_text() + 'AnimalTrailerFixtureConfig.connect={host="127.0.0.1",port=' + str(selection['ports'][0]) + ',username="' + username + '",password="isolated-native-only"}\n', encoding='utf-8')
    for cache in caches:
        for identifier in fixture['mods']:
            for layer in ('common', '42'):
                for directory in ('AnimSets', 'actiongroups'):
                    (cache / 'mods' / identifier / layer / 'media' / directory).mkdir(parents=True, exist_ok=True)


def complete(selection, role, text):
    if selection['suite'] == 'animal-trailer' and len(selection['cases']) > 1:
        return bool(re.search(r'\[QUEUE_SESSION\] COMPLETE case=' + re.escape(selection['cases'][-1]) + ' epoch=' +
                              str(len(selection['cases'])) + ' actor=' + re.escape(role) + r' cases=' + str(len(selection['cases'])) + r'(?:\s|$)', text))
    marker = {'video-recording': '[VIDEO_TEST] PASSED', 'item-tags': '[QM_SCREEN] COMPLETE',
              'inventory-presentation': '[INVENTORY_SCREEN] COMPLETE',
              'smart-deposit': '[SMART_DEPOSIT] COMPLETE',
              'inventory-tooltips': '[INVENTORY_TOOLTIP] COMPLETE',
              'animal-trailer': '[ANIMAL_TRAILER] CLIENT COMPLETE'}[selection['suite']]
    return marker in text


def _client_text(root):
    # console.txt is the source expected by the retained recorder verifier.
    cache = Path(root) / 'client1'
    console = cache / 'console.txt'
    return console.read_text(errors='replace') if console.is_file() else (Path(root) / 'client1-launch.log').read_text(errors='replace')


def _verify_animal_session(root, selection, intake):
    issues, outcomes, proofs = [], [], {}
    try:
        logs = {role: (root / (role + '-launch.log')).read_text(errors='replace') for role in ('server', 'client1')}
    except OSError as error:
        issues.append(str(error))
        logs = {'server': '', 'client1': ''}
    verifier = _load(intake / 'verify.py')
    timer_activation = [line for line in logs['server'].splitlines() if '[AnimalTrailerSyncMPFix] ACTIVE 1.3' in line]
    for epoch, case in enumerate(selection['cases'], 1):
        local, windows = [], {}
        for role, text in logs.items():
            receipt = 'case=' + case + ' epoch=' + str(epoch) + ' actor='
            begin = '[QUEUE_SESSION] BEGIN ' + receipt + role
            found = list(re.finditer(re.escape(begin) + r'(?:\s|$)', text))
            if len(found) != 1:
                local.append(role + ': expected one session BEGIN for ' + case)
                windows[role] = ''
                continue
            start = found[0].start()
            following = re.search(r'\[QUEUE_SESSION\] BEGIN ', text[found[0].end():])
            end = found[0].end() + following.start() if following else len(text)
            window = windows[role] = text[start:end]
            events = [('PREPARE', 'client1'), ('START', 'server'), ('FINISH', 'client1'), ('CLEANUP', 'server'),
                      ('CLEANUP', 'client1'), ('JOINT_CLEAN', 'server')] if role == 'server' else [
                          (event, 'client1') for event in ('PREPARE', 'START', 'FINISH', 'LOCAL_CLEAN', 'CLEANUP', 'JOINT_CLEAN')]
            positions = []
            for event, actor in events:
                suffix = ' ok=true' if event in ('FINISH', 'LOCAL_CLEAN', 'CLEANUP', 'JOINT_CLEAN') else ''
                pattern = re.escape('[QUEUE_SESSION] ' + event + ' ' + receipt + actor + suffix) + r'(?:\s|$)'
                matches = list(re.finditer(pattern, window))
                if len(matches) != 1 or len(re.findall(pattern, text)) != 1:
                    local.append(role + ': missing/duplicate/failed ' + case + ' ' + event)
                else:
                    positions.append(matches[0].start())
            if positions != sorted(set(positions)):
                local.append(role + ': reordered lifecycle for ' + case)
            if '[QUEUE_SESSION] QUARANTINE ' in window:
                local.append(role + ': quarantined ' + case)
            for marker in ('[ANIMAL_TRAILER] ' + ('SERVER' if role == 'server' else 'CLIENT') + ' OWNED_RESET animals=3 items=4 trailer=1',
                           '[ANIMAL_TRAILER] ' + ('SERVER' if role == 'server' else 'CLIENT') + ' PROBE_RESET clean=true'):
                if window.count(marker) != 1:
                    local.append(role + ': missing exact owned reset proof for ' + case)
        scenario, timer, hands = ANIMAL_CASES[case]
        try:
            server = windows['server']
            if scenario in ('timer', 'combined') and timer == 'shared':
                if len(timer_activation) != 1:
                    raise ValueError('Expected exactly one real timer 1.3 activation in the session')
                server = timer_activation[0] + '\n' + server
            proofs[case] = verifier.verify(server, windows['client1'], scenario, timer, hands)
        except ValueError as error:
            local.append(case + ': ' + str(error))
        if epoch == len(selection['cases']):
            for role, text in logs.items():
                if not complete(selection, role, text) or len(re.findall(r'\[QUEUE_SESSION\] COMPLETE ', text)) != 1:
                    local.append(role + ': missing/duplicate final session completion')
        issues.extend(local)
        outcomes.append({'actor': 'client1', 'case': case, 'status': 'failed' if local else 'passed',
                         'reason': '; '.join(local), 'outcome': {'fixture': 'animal-trailer', 'epoch': epoch}})
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'verification': proofs,
            'limits': ['Same immutable production JAR environment; owned fixture reset is separate from a fresh save.']}}


def verify(root, selection, catalog):
    root = Path(root)
    suite = selection['suite']
    project = Path(__file__).resolve().parents[3]
    intake = _intake(project, suite)
    if suite == 'animal-trailer' and len(selection['cases']) > 1:
        return _verify_animal_session(root, selection, intake)
    issues, evidence = [], {}
    try:
        text = _client_text(root)
        if not complete(selection, 'client1', text):
            raise ValueError('Missing fixture completion marker')
        if suite == 'video-recording':
            evidence['clips'] = _load(intake / 'verify.py').verify(root / 'client1', _path(selection, 'ffmpeg', True), _path(selection, 'ffprobe', True))
        elif suite in ('inventory-presentation', 'smart-deposit', 'inventory-tooltips'):
            evidence.update(_load(intake / 'verify.py').verify(root, text))
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
