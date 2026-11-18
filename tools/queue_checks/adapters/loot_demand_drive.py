"""Paired isolated SP driving cadence measurement, using one sealed seed world."""
from pathlib import Path
import csv
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import zipfile
import optimizer_profile
from .optimizer_benchmark import route_source, metrics


def definitions():
    return {'loot-demand-drive': {'status': 'ready', 'clients': 1,
        'default_mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'PZDrivingBench', 'FurniturePushPull'],
        'cases': [dict(id=name, producer='fixture', capability='capture' if name == 'drive' else 'effect',
                       kinds=['sp'], languages=['EN'], modes=['native']) for name in ('seed', 'drive')]}}


def validate(selection):
    options = selection.get('options', {})
    if (selection['kind'] != 'sp' or selection['clients'] != 1 or selection['mode'] != 'native'
            or selection['languages'] != ['EN'] or selection['cases'] not in (['seed'], ['drive'])
            or not {'ZombieBuddy','PZToolkitJavaPatches','PZSurvivorToolkit','PZDrivingBench','FurniturePushPull'} <= set(selection['mods'])
            or type(options.get('optimizer_enabled')) is not bool or options.get('mp_host')
            or not selection.get('resources', {}).get('exclusive')):
        raise ValueError('Requires exclusive native EN SP, one seed/drive case and explicit optimizer_enabled')
    if selection['cases'] == ['drive'] and not options.get('world_template'):
        raise ValueError('Measured drive requires a sealed seed world')
    if selection['cases'] == ['seed'] and (options.get('world_template') or options['optimizer_enabled']):
        raise ValueError('Seed must be fresh and unoptimized')
    profile = options.get('stage_profile', False)
    if type(profile) is not bool or profile and selection['cases'] != ['drive']:
        raise ValueError('stage_profile must be an explicit boolean and is only supported for a drive')
    callbacks = options.get('callback_profile', False)
    if type(callbacks) is not bool or callbacks and not profile:
        raise ValueError('callback_profile must be an explicit boolean and requires stage_profile')
    details = options.get('callback_detail_profile', False)
    if type(details) is not bool or details and not callbacks:
        raise ValueError('callback_detail_profile must be an explicit boolean and requires callback_profile')
    chain = options.get('callback_chain_profile', False)
    if type(chain) is not bool or chain and not details:
        raise ValueError('callback_chain_profile must be an explicit boolean and requires callback_detail_profile')
    perf = options.get('driving_perf', {})
    if (perf.get('scenario') != 'muldraugh-extinction' or perf.get('population_mode') != 'native'
            or perf.get('vehicle_script') != 'Base.SportsCar' or perf.get('full_throttle') is not True):
        raise ValueError('Requires Muldraugh native population and full-throttle sports car')
    if options.get('optimizer_enabled') is not False or any(options.get(k) for k in ('optimizer_archive', 'stage_profile', 'callback_profile', 'callback_detail_profile', 'callback_chain_profile')):
        raise ValueError('Route experiment requires no optimizer or legacy profilers')
    if selection['cases'] == ['drive'] and options.get('loot_demand_arm') not in ('observe', 'defer'):
        raise ValueError('Drive requires observe or defer arm')
    if selection['cases'] == ['seed'] and options.get('loot_demand_arm'):
        raise ValueError('Seed must not activate the demand experiment')


def sources(project, selection):
    root = Path(project)
    probe = root / 'tests/native_queue/loot-demand-drive/java'
    from . import loot_demand
    legacy = root / 'tests/native_queue/optimizer-benchmark'
    return [*loot_demand.sources(project, selection), *sorted(probe.glob('*')),
            Path(__file__).with_name('optimizer_benchmark.py'),
            legacy / 'client/ZZDrivingPerfWorld.lua', legacy / 'java/ApproachClearance.java',
            legacy / 'java/mod.info.template', legacy / 'ApproachLane.lua',
            *sorted((root / 'tests/driving_benchmark/mods').rglob('*.lua')),
            root / 'tools/optimizer_profile.py', root / 'tests/native_queue/support/viewport/Main.java']


def stage(project, output, game, jdk, selection, locations, runtime):
    project, output, game, jdk = map(Path, (project, output, game, jdk))
    validate(selection)
    cache = output / 'client1'; classes = cache / 'classes'
    guards = {
        'zombie/core/physics/CarController.class': 'c32ecbf047a2fc6e6b321d6b15ea1a51a3dd549d06b29296878d47894d3f2a60',
        'org/lwjglx/opengl/Display.class': '3b49c8639b52dcfe11daa70c3d397ea8b55c22fb09b9ede2f7b523fee3b7b525',
        'zombie/GameWindow.class': '044f9832aadb0dd23c7018e07c5e0bcc743987a23b0e0566777f11733fba65a1',
        'zombie/vehicles/BaseVehicle.class': '354b166db919f8de692a5327b7afd01fefdbfb8021f0c99e2b2b44a3fe606de3',
        'zombie/iso/IsoGridSquare.class': 'b8cef32a10bb76433bad174397b51f1a046be1eef47997dc1e79dd8547d726c5'}
    with zipfile.ZipFile(game / 'projectzomboid.jar') as z:
        for name, expected in guards.items():
            if hashlib.sha256(z.read(name)).hexdigest() != expected:
                raise ValueError('Unsupported current route input: ' + name)
    optimizer_profile.stage_viewport(project, output / 'optimizer-benchmark-inputs', game, jdk, runtime, guards)
    # The same generated probe mod and input controller are in both arms and the seed.
    source = project / 'tests/native_queue/loot-demand-drive/java'
    legacy = project / 'tests/native_queue/optimizer-benchmark'
    shutil.copy2(legacy / 'client/ZZDrivingPerfWorld.lua',
                 cache / 'mods/ActionQueueTest/42/media/lua/client/ZZDrivingPerfWorld.lua')
    mod = cache / 'mods/PZDrivingPerfProbe/42'
    (mod / 'media/java').mkdir(parents=True)
    metadata = (legacy / 'java/mod.info.template').read_text()
    if metadata.count('versionMin=42.21\n') != 1 or metadata.count('versionMax=42.21\n') != 1:
        raise ValueError('Shared driving probe version metadata changed')
    (mod / 'mod.info').write_text(metadata.replace('versionMin=42.21\n', 'versionMin=42.22\n')
                               .replace('versionMax=42.21\n', 'versionMax=42.22\n'))
    with tempfile.TemporaryDirectory(prefix='pz-driving-probe-build-') as temporary:
        build = Path(temporary)
        subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp',
                        str(game / 'projectzomboid.jar') + ':' + str(game / 'ZombieBuddy.jar'),
                        '-d', str(build), str(source / 'Main.java'), str(legacy / 'java/ApproachClearance.java')], check=True, capture_output=True)
        with zipfile.ZipFile(mod / 'media/java/PZDrivingPerfProbe.jar', 'w', zipfile.ZIP_DEFLATED) as jar:
            jar.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\n\n')
            for path in sorted(build.rglob('*.class')): jar.write(path, path.relative_to(build).as_posix())
    runtime['fixture']['mods'].append('PZDrivingPerfProbe')
    # Only the copied test starter changes: the fixture owns native create/load below.
    (cache / 'mods/PZDrivingBench/42/media/lua/client/DrivingBenchStart.lua').write_text('-- World lifecycle owned by isolated benchmark fixture.\n')
    client = cache / 'mods/PZDrivingBench/42/media/lua/client/DrivingBenchClient.lua'
    text = client.read_text()
    anchor = 'if C.ready or C.stage=="failed" or not isIngameState() or not F.allowed() then return end'
    if text.count(anchor) != 1: raise ValueError('Starter preparation guard changed')
    client.write_text(text.replace(anchor, 'if PZDrivingPerfSeeding then return end\n    ' + anchor))
    route = cache / 'mods/PZDrivingBench/42/media/lua/shared/DrivingBenchFixture.lua'
    scenario = selection['options'].get('driving_perf', {}).get('scenario')
    replacement = route.with_name(route.name + '.approach.tmp')
    replacement.write_text(route_source(route.read_text(), scenario))
    replacement.replace(route)
    if scenario == 'muldraugh-extinction':
        helper = mod / 'media/lua/shared/DrivingApproachLane.lua'
        helper.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(project / 'tests/native_queue/optimizer-benchmark/ApproachLane.lua', helper)
    (cache / 'Lua/DrivingBench-run.txt').write_text('PZDrivingBench-Perf\n')
    settings = cache / 'options.ini'
    settings.write_text(settings.read_text() + 'vsync=false\nframeRate=144\nautozoom=false,false,false,false\n')
    launcher = classes / 'ToolkitSmokeLauncher.java'
    text = launcher.read_text(); anchor = 'public static void main(String[] args) throws Exception {'
    if text.count(anchor) != 1: raise ValueError('Native launcher signature changed')
    props = {'pz.drivingPerf.cachedir': str(cache)}
    assignments = '\n'.join('System.setProperty(' + json.dumps(k) + ', ' + json.dumps(v) + ');' for k,v in props.items())
    launcher.write_text(text.replace(anchor, anchor + '\n' + assignments))
    subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp',
                    str(classes) + ':' + str(game / 'projectzomboid.jar'),
                    str(classes / 'ToolkitWindowBootstrap.java'), str(launcher)], check=True, capture_output=True)
    runtime['fixture'].setdefault('failure_markers', []).extend(['[DRIVING_PERF] FAIL ', '[PZDrivingBench] FAIL ', '[DRIVING_PERF_WORLD] FAIL '])
    if selection['cases'] == ['drive']:
        from . import loot_demand
        loot_demand.stage_probe(project, output, game, jdk, selection, locations, runtime, selection['options']['loot_demand_arm'])
        runtime['fixture']['failure_markers'].extend(['[LOOT_DEMAND] FAILURE '])


def complete(selection, role, text):
    marker = '[DRIVING_PERF_WORLD] SEED_SAVED' if selection['cases'] == ['seed'] else '[DRIVING_PERF] LUA_COMPLETE'
    return role == 'client1' and text.count(marker) == 1


def verify(root, selection, catalog):
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    issues, evidence = [], {}
    if not complete(selection, 'client1', text): issues.append('Missing seed or measured-route completion')
    if re.search(r'\[(?:DRIVING_PERF(?:_WORLD)?|PZDrivingBench)\] FAIL ', text): issues.append('Fixture failed')
    if '[PZToolkitJavaPatches] Experimental B42.22.2 patch:' not in text: issues.append('Toolkit Java patches did not activate')
    lane = '[DRIVING_APPROACH] SELECTED ' if selection['cases'] == ['seed'] else '[DRIVING_APPROACH] RESTORED '
    if text.count(lane) != 1: issues.append('Missing or duplicate lane receipt')
    if selection['cases'] == ['drive']:
        try:
            evidence['timings'] = metrics(root / 'client1/driving-perf.csv')
            evidence['census'] = census(root / 'client1/Lua', selection['options']['loot_demand_arm'], text)
        except (OSError, ValueError, KeyError, csv.Error) as error:
            issues.append('Drive evidence: ' + str(error))
        for marker in ('[DRIVING_PERF] BEGIN ', '[DRIVING_PERF] MEASURE ', '[DRIVING_PERF] END ', '[DRIVING_PERF] COMPLETE '):
            if text.count(marker) != 1: issues.append('Missing or duplicate route marker: ' + marker)
        if text.count('[LOOT_DEMAND] INSTALLED isolated=true') != 1: issues.append('Missing or duplicate demand activation')
    evidence['limits'] = ['SP only; streaming RNG, traffic and NPCs may diverge despite the same sealed seed.',
                          'No first-access, Host, rendered-presentation or Windows claim.']
    return dict(issues=issues, outcomes=[dict(actor='client1', case=selection['cases'][0],
        status='failed' if issues else 'captured' if selection['cases']==['drive'] else 'passed', reason='; '.join(issues))], evidence=evidence)


def census(directory, arm, log):
    status = {}
    for line in (directory / 'loot-demand-drive-status.txt').read_text().splitlines():
        key, value = line.split('=', 1)
        if key in status: raise ValueError('Duplicate census status')
        status[key] = value
    if set(status) != {'schema','arm','capacity','objects','overflow','active'} or status['schema'] != '1' or status['arm'] != arm:
        raise ValueError('Invalid census status or arm')
    if int(status['overflow']) != 0 or int(status['active']) != 0: raise ValueError('Incomplete census')
    markers = re.findall(r'^(?:LOG\s*:\s*(?:Lua|General)\b[^\r\n>]*> )?\[LOOT_ROUTE\] (START|END) clock=(\d+)$', log, re.MULTILINE)
    if len(markers) != 2 or [x[0] for x in markers] != ['START', 'END']:
        raise ValueError('Missing or duplicate measured-window clocks')
    begin, end = (int(x[1]) for x in markers)
    if begin <= 0 or begin >= end: raise ValueError('Invalid window clocks')
    columns = ['type','x','y','z','object_index','sprite','auto_visits','first_auto_ns','first_fill_ns','fill_kind','fill_ns','fill_failed','reentries','repeat_fills','active_depth']
    with (directory / 'loot-demand-drive-census.csv').open(newline='') as stream:
        reader = csv.DictReader(stream, strict=True)
        if reader.fieldnames != columns: raise ValueError('Unexpected census columns')
        rows = list(reader)
    if len(rows) != int(status['objects']) or len(rows) > int(status['capacity']): raise ValueError('Census object count mismatch')
    keys = set(); window = []
    for row in rows:
        if set(row) != set(columns) or row['type'] not in ('bin','dumpster') or not row['sprite']:
            raise ValueError('Malformed census object')
        key = tuple(row[k] for k in ('type','x','y','z','object_index','sprite'))
        if key in keys: raise ValueError('Ambiguous duplicate world object')
        keys.add(key)
        for k in ('x','y','z','object_index','auto_visits','first_auto_ns','first_fill_ns','fill_ns','fill_failed','reentries','repeat_fills','active_depth'):
            row[k] = int(row[k])
        if row['auto_visits'] < 1 or row['first_auto_ns'] <= 0 or row['active_depth'] != 0 or row['fill_failed'] != 0:
            raise ValueError('Invalid or incomplete object observation')
        if row['fill_kind'] not in ('none','automatic','demand'):
            raise ValueError('Invalid fill kind')
        if row['fill_kind'] == 'none':
            if row['first_fill_ns'] != 0 or row['fill_ns'] != -1: raise ValueError('Invalid pending object')
        elif row['first_fill_ns'] < row['first_auto_ns'] or row['fill_ns'] < 0:
            raise ValueError('Invalid fill timing')
        if begin <= row['first_auto_ns'] < end: window.append(row)
    return {'arm':arm, 'window_start_ns':begin, 'window_end_ns':end, 'objects_total':len(rows),
            'window_objects':window, 'all_objects':rows}


def compare(observe_run, defer_run):
    """Strict pair gate; do not turn unmatched natural objects into zero-duration samples."""
    def load(root, arm):
        root = Path(root)
        selection = json.loads((root / 'selection.json').read_text())
        report = json.loads((root / 'report.json').read_text())
        if (report.get('status') != 'needs-review' or report.get('functional', {}).get('status') != 'captured'
                or report.get('execution_issues') != [] or report.get('selection') != selection
                or report.get('execution', {}).get('status') != 'completed'
                or report.get('runtime', {}).get('status') not in ('clean', 'background-only')
                or report.get('provenance', {}).get('verified') is not True):
            raise ValueError('Runner did not qualify the ' + arm + ' run')
        if selection.get('suite') != 'loot-demand-drive' or selection.get('cases') != ['drive'] or selection.get('options', {}).get('loot_demand_arm') != arm:
            raise ValueError('Incorrect arm or suite')
        verified = verify(root, selection, {})
        if verified['issues']: raise ValueError('Unqualified ' + arm + ': ' + '; '.join(verified['issues']))
        config = selection.pop('config_source', None)
        selection['options'].pop('loot_demand_arm')
        sources = json.loads((root / 'source-manifest.json').read_text())
        if config and sources.pop(config, None) is None:
            raise ValueError('Missing config source receipt')
        return (selection, json.loads((root / 'world-template.json').read_text()),
                json.loads((root / 'game-inputs.json').read_text()), sources, verified['evidence']['census'])
    left, right = load(observe_run, 'observe'), load(defer_run, 'defer')
    for label, a, b in zip(('selection','sealed world','game inputs','source manifest'), left[:4], right[:4]):
        if a != b: raise ValueError('Pair differs: ' + label)
    def keyed(rows):
        return {tuple(str(r[k]) for k in ('type','x','y','z','object_index','sprite')):r for r in rows}
    a, b = keyed(left[4]['window_objects']), keyed(right[4]['window_objects'])
    only_a, only_b = sorted(a.keys()-b.keys()), sorted(b.keys()-a.keys())
    common = a.keys() & b.keys()
    return {'identical_cohort':not only_a and not only_b and bool(a), 'matched_objects':len(common),
            'observe_only':only_a, 'defer_only':only_b,
            'observe_automatic_fills':sum(a[k]['fill_kind']=='automatic' for k in common),
            'defer_automatic_fills':sum(b[k]['fill_kind']=='automatic' for k in common),
            'defer_demand_fills':sum(b[k]['fill_kind']=='demand' for k in common),
            'limits':['Matched object identity and route gates do not guarantee equivalent NPC, RNG or streaming state.',
                      'First-access after the drive was not measured.']}
