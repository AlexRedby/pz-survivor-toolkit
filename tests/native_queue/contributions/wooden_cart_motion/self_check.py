"""Contribution-local checks only. Never prepares a profile or launches the game."""
from pathlib import Path
import argparse
import json
import os
import runpy
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def check_manifest():
    manifest = json.loads((HERE / "manifest.json").read_text())
    assert manifest["schema_version"] == 1
    assert manifest["id"] == "wooden_cart_motion"
    assert manifest["status"] == "intake_only" and manifest["runner_adapter"] is None
    assert manifest["live_after_parameterization"] == "reverse_only_2026-10-16"
    assert manifest["exclusive_native_process"] is True
    assert manifest["sources"] == {
        "java": "Main.java", "kahlua_checks": "KahluaChecks.java", "test_area": "test-area.lua",
        "bootstrap": "bootstrap.lua", "scenario": "scenario-clips.lua", "reverse_scenario": "scenario-reverse.lua", "reverse_analyzer": "analyze-reverse.py", "reversal_scenario": "scenario-reversal.lua", "stop_scenario": "scenario-stop.lua", "stop_analyzer": "analyze-stop.py",
        "evidence": "evidence/README.md",
        "reversal_analyzer": "analyze-reversal.py", "stationary_scenario": "scenario-stationary.lua", "stationary_analyzer": "analyze-stationary.py",
        "maneuvers_scenario": "scenario-maneuvers.lua", "maneuvers_analyzer": "analyze-maneuvers.py",
        "obstacles": "obstacles.lua", "collision_scenario": "scenario-collision.lua", "collision_analyzer": "analyze-collision.py",
        "footprint_analyzer": "analyze-footprint.py", "impact_analyzer": "analyze-impact.py",
        "interaction_scenario": "scenario-interaction.lua", "interaction_analyzer": "analyze-interaction.py",
        "interruption_analyzer": "analyze-interruption.py", "repeat_analyzer": "analyze-repeat.py", "wheel_cycle_analyzer": "analyze-wheel-cycle.py",
        "path_scenario": "scenario-path.lua", "path_analyzer": "analyze-path.py",
        "scene_selection": "scene-selection.lua",
        "vehicles": "vehicles.lua", "vehicle_scenario": "scenario-vehicles.lua", "vehicle_analyzer": "analyze-vehicles.py",
        "brace_analyzer": "analyze-brace.py",
        "controls_scenario": "scenario-controls.lua", "variants_scenario": "scenario-variants.lua",
    }
    for name in manifest["sources"].values():
        assert (HERE / name).is_file(), name
    assert manifest["dependencies"]["compile_jdk_minimum"] == 25
    assert manifest["dependencies"]["compile_release"] == 17
    assert manifest["dependencies"]["required_project_versions"]["PZSurvivorToolkit"] == ">=0.1.58"
    assert manifest["dependencies"]["required_project_versions"]["PZToolkitJavaPatches"] == ">=0.1.15"
    assert manifest["required_environment"] == ["PZ_CART_RUNTIME_FILE", "PZ_CART_COMMAND_FILE", "PZ_CART_TEST_PAD"]
    assert manifest["required_lua_fields"] == ["disposable", "videoRoot", "ffmpeg", "area"]
    assert manifest["runtime_contract"]["world_name"] == "CartTestArea"
    assert manifest["runtime_contract"]["fresh_owned_profile"] is True
    assert manifest["scenario"]["case_count"] == 16
    axes = manifest["scenario"]["axes"]
    assert len(axes["sex"]) * len(axes["cargo"]) * len(axes["spec"]) == 16
    assert set(manifest["criteria"]) == {"completion", "grip", "geometry", "native_pose", "floor", "gait", "diagnostics"}
    allowed = {"Main.java", "KahluaChecks.java", "test-area.lua", "bootstrap.lua", "scenario-clips.lua", "manifest.json", "README.md", "self_check.py", "scenario-reverse.lua", "analyze-reverse.py", "scenario-reversal.lua", "analyze-reversal.py", "scenario-stop.lua", "analyze-stop.py", "scenario-stationary.lua", "analyze-stationary.py", "scenario-maneuvers.lua", "analyze-maneuvers.py", "obstacles.lua", "scenario-collision.lua", "analyze-collision.py", "analyze-footprint.py"}
    allowed |= {"scenario-interaction.lua", "analyze-interaction.py", "analyze-interruption.py", "analyze-repeat.py",
                "analyze-wheel-cycle.py", "scenario-path.lua", "analyze-path.py", "scene-selection.lua", "analyze-impact.py", "analyze-stop-timing.py", "vehicles.lua", "scenario-vehicles.lua", "analyze-vehicles.py", "analyze-brace.py"}
    allowed |= {"scenario-controls.lua", "scenario-variants.lua", "scenario-native-e.lua"}
    assert {p.name for p in HERE.iterdir() if p.is_file()} == allowed
    for path in HERE.rglob("*"):
        if path.is_file():
            assert path.suffix not in {".jar", ".class", ".zip", ".mp4", ".png", ".bin", ".log"}, path
    for name in manifest["sources"].values():
        text = (HERE / name).read_text()
        assert not re.search(r"/(?:Users|home|private/tmp|opt/homebrew)/", text), name
        assert all(line.rstrip() == line for line in text.splitlines()), name
    for name in ("test-area.lua", "bootstrap.lua", "scenario-clips.lua", "scenario-reverse.lua", "scenario-reversal.lua", "scenario-stop.lua", "scenario-stationary.lua", "scenario-maneuvers.lua", "obstacles.lua", "scenario-collision.lua", "scenario-interaction.lua", "scenario-path.lua", "scene-selection.lua", "vehicles.lua", "scenario-vehicles.lua", "scenario-controls.lua", "scenario-variants.lua"):
        first = next(line for line in (HERE / name).read_text().splitlines() if line.strip() and not line.startswith("--"))
        assert first.startswith("local config=assert(CartMotionConfig,"), name
    assert manifest['reverse_scenario']['case_count'] == 20
    assert manifest['reversal_scenario']['case_count'] == 20
    assert manifest['stop_scenario']['case_count'] == 24
    assert manifest['stop_scenario']['required_candidate_versions'] == {'PZSurvivorToolkit':'>=0.1.61','PZToolkitJavaPatches':'>=0.1.18'}
    assert manifest['stationary_scenario']['case_count'] == 20
    assert manifest['stationary_scenario']['required_candidate_versions'] == {'PZSurvivorToolkit':'>=0.1.61','PZToolkitJavaPatches':'>=0.1.19'}
    assert manifest['maneuvers_scenario']['case_count'] == 32
    assert manifest['maneuvers_scenario']['axes']['spec'] == ['idle-swap-left','idle-swap-right','moving-swap-left','moving-swap-right','reverse-rest','reverse-moving','uturn-left','uturn-right']
    assert manifest['collision_scenario']['case_count'] == 16
    assert manifest['collision_scenario']['native_bare_controls'] == ['wall','corner','passage']
    assert manifest['footprint_scenario']['native_bare_controls'] == ['wall','corner','passage','wall-slide-left','wall-slide-right']
    assert manifest['footprint_scenario']['case_count'] == 24
    assert manifest['footprint_scenario']['required_candidate_versions']['PZToolkitJavaPatches']=='>=0.1.20'
    fast_slide=manifest['fast_slide_scenario']
    assert fast_slide['case_count']==16 and fast_slide['record_seconds_per_case']==12
    assert fast_slide['native_bare_controls']==manifest['footprint_scenario']['native_bare_controls']
    assert fast_slide['axes']['spec']==['run-wall-slide','run-wall-slide-right','sprint-wall-slide','sprint-wall-slide-right']
    assert fast_slide['analyzer']=='analyze-footprint.py --fast-slide'
    footprint=runpy.run_path(str(HERE/'analyze-footprint.py'))
    assert len(footprint['EXPECTED'])==24 and len(footprint['FAST_SLIDE_EXPECTED'])==16
    assert footprint['steps']('male-empty-sprint-wall-slide-right', True)==[(1000,2,1),(6000,0,0),(7000,0,None),(9500,0,0)]
    for empty in ('','[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=16'):
        try: footprint['selected'](empty, True)
        except AssertionError: pass
        else: raise AssertionError('Empty fast slide evidence must fail')
    wall_exit=manifest['wall_exit_scenario']
    assert wall_exit['case_count']==24 and wall_exit['record_seconds_per_case']==12
    assert wall_exit['native_bare_controls']==manifest['footprint_scenario']['native_bare_controls']
    assert wall_exit['axes']==dict(sex=['male'],cargo=['empty','full'],gait=['walk','run','sprint'],spec=['wall-slide','wall-slide-right'],outward_angle_degrees=[45,90])
    assert wall_exit['analyzer']=='analyze-footprint.py --wall-exit'
    assert len(footprint['WALL_EXIT_EXPECTED'])==24
    for name in footprint['WALL_EXIT_EXPECTED']:
        planned=footprint['steps'](name,wall_exit=True)
        assert [e[0] for e in planned]==[1000,5500,10000] and planned[0][1]==planned[1][1]
        assert planned[0][2] in (1,2) and planned[1][2] in (3,4,7) and planned[-1]==(10000,0,0)
    for empty in ('','[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=24'):
        try: footprint['selected'](empty,wall_exit=True)
        except AssertionError: pass
        else: raise AssertionError('Empty wall exit evidence must fail')
    manual_exit=manifest['wall_manual_exit_scenario']
    assert manual_exit['case_count']==8 and manual_exit['record_seconds_per_case']==29
    assert manual_exit['native_bare_controls']==manifest['footprint_scenario']['native_bare_controls']
    assert manual_exit['axes']==dict(sex=['male'],cargo=['empty','full'],gait=['walk'],spec=['wall-slide','wall-slide-right'],outward_angle_degrees=[45,90])
    assert manual_exit['analyzer']=='analyze-footprint.py --wall-manual-exit'
    assert len(footprint['WALL_MANUAL_EXIT_EXPECTED'])==8
    assert footprint['steps']('male-empty-walk-wall-slide-manual-out45',wall_manual_exit=True)==[(1000,0,2),(9500,0,8),(12000,0,3),(15500,0,0),(16000,0,4),(26000,0,0)]
    assert footprint['steps']('male-full-walk-wall-slide-right-manual-out90',wall_manual_exit=True)==[(1000,0,1),(9500,0,6),(12000,0,4),(15500,0,0),(16000,0,3),(21000,0,7),(26000,0,0)]
    assert footprint['steps']('male-empty-walk-wall-slide-manual-out45',wall_manual_exit=True,relative=True)==[(1000,0,1),(9500,0,4),(12000,0,6),(15500,0,0),(16000,0,5),(26000,0,0)]
    assert footprint['steps']('male-full-walk-wall-slide-right-manual-out90',wall_manual_exit=True,relative=True)==[(1000,0,1),(9500,0,4),(12000,0,7),(15500,0,0),(16000,0,8),(21000,0,8),(26000,0,0)]
    manual_source=(HERE/'scenario-collision.lua').read_text()
    assert 'local relativeManual=wallManualExit\n' in manual_source
    assert '[CART_RELATIVE_MANUAL] VERSION 1' in manual_source and 'cartLabSteeringHeading()' in manual_source
    assert 'Manual controls changed cart ownership' in manual_source and 'Manual controls changed cargo' in manual_source
    for empty in ('','[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=8'):
        try: footprint['selected'](empty,wall_manual_exit=True)
        except AssertionError: pass
        else: raise AssertionError('Empty manual wall exit evidence must fail')
    fast_manual_exit=manifest['wall_fast_manual_exit_scenario']
    assert fast_manual_exit['case_count']==16 and fast_manual_exit['record_seconds_per_case']==29
    assert fast_manual_exit['native_bare_controls']==manual_exit['native_bare_controls']
    assert fast_manual_exit['axes']==dict(manual_exit['axes'],gait=['run','sprint'])
    assert fast_manual_exit['analyzer']=='analyze-footprint.py --wall-fast-manual-exit'
    assert fast_manual_exit['input_schedule_ms']==manual_exit['input_schedule_ms']
    assert fast_manual_exit['input_scheme']=='relative-keyboard-v1'
    assert fast_manual_exit['steering_gates']==dict(opposite_yaw_radians_max=.02,released_heading_drift_radians_max=.025,sample_gap_ms_max=500)
    assert fast_manual_exit['wall_reach_tiles']==40 and fast_manual_exit['owned_wall_segments']==81 and fast_manual_exit['finite_wall_span_verified'] is True
    assert fast_manual_exit['start_offset_from_center_tiles']==20
    assert len(footprint['WALL_FAST_MANUAL_EXIT_EXPECTED'])==16
    for name in footprint['WALL_FAST_MANUAL_EXIT_EXPECTED']:
        planned=footprint['steps'](name,wall_fast_manual_exit=True)
        walk=footprint['steps'](name.replace('-run-','-walk-').replace('-sprint-','-walk-'),wall_manual_exit=True)
        assert planned[0]==(1000,1 if '-run-' in name else 2,walk[0][2]) and planned[1:]==walk[1:]
        relative=footprint['steps'](name,wall_fast_manual_exit=True,relative=True)
        relative_walk=footprint['steps'](name.replace('-run-','-walk-').replace('-sprint-','-walk-'),wall_manual_exit=True,relative=True)
        assert relative[0]==(1000,planned[0][1],1) and relative[1:]==relative_walk[1:]
    for empty in ('','[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=16'):
        try: footprint['selected'](empty,wall_fast_manual_exit=True)
        except AssertionError: pass
        else: raise AssertionError('Empty fast manual wall exit evidence must fail')
    assert manifest['brace_scenario']['case_count']==8 and manifest['brace_scenario']['record_seconds_per_case']==18 and manifest['brace_scenario']['release_wall_segments']==3
    brace=runpy.run_path(str(HERE/'analyze-brace.py'))
    assert len(brace['EXPECTED'])==8 and brace['DURATION']==18000
    for empty in ('','[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=8'):
        try: brace['parse'](empty)
        except AssertionError: pass
        else: raise AssertionError('Empty brace evidence must fail')
    assert manifest['vehicle_scenario']['case_count']==12
    vehicles=runpy.run_path(str(HERE/'analyze-vehicles.py'))
    assert len(vehicles['EXPECTED'])==12 and len(vehicles['CONTROLS'])==4
    for empty in ('','[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=12'):
        try: vehicles['parse'](empty)
        except AssertionError: pass
        else: raise AssertionError('Empty vehicle evidence must fail')
    stationary = runpy.run_path(str(HERE/'analyze-stationary.py'))
    assert len(stationary['STEPS']) == 5
    for empty in ('', '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=20'):
        try:
            stationary['analyze'](empty, [])
        except AssertionError:
            pass
        else:
            raise AssertionError('Empty stationary evidence must fail')
    assert abs(stationary['wrap'](6.283185307179586)) < 1e-10
    row = stationary['sample']('[WOOD_BANK_SAMPLE] case=probe wall=1 elapsed=0 x=1 y=2 run=false sprint=false drive=0 requestedGait=0 stepX=0 stepY=0 bank=0 stationary=heading:0,target:0,stationary:false,stationaryRoot:false,actualDistance:0,axle:1,rootTracks: tracks=Bob_SprintToStop2h_Heavy=1@.5;y=999 heading=nan')
    assert row['x'] == 1 and row['y'] == 2 and row['heading'] == 0
    analyzer = runpy.run_path(str(HERE/'analyze-reverse.py'))
    for empty in ['', '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=20']:
        try:
            analyzer['analyze'](empty)
        except AssertionError:
            pass
        else:
            raise AssertionError('Empty motion evidence must fail')
    assert abs(analyzer['wrap'](3.141592653589793*2)) < 1e-10
    check_reverse_analyzer(analyzer)
    return manifest



def check_reverse_analyzer(analyzer):
    import math
    lines = ['[WOOD_BANK] RUN_STARTED']
    for index, (sex, cargo, spec) in enumerate(
        (sex, cargo, spec) for sex in ('male', 'female')
        for cargo in ('empty', 'full') for spec in analyzer['SPECS']
    ):
        name = f'{sex}-{cargo}-{spec}'
        start = 100000 + index*15000
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start}')
        for elapsed in range(0, 12000, 100):
            heading = math.pi*.75
            stop = 6000 if 'start-turn' in spec else 10500 if 'u-turn' in spec else 9500
            if 'back-arc' in spec:
                heading += (1 if 'left' in spec else -1)*math.pi/8*max(0, 1-elapsed/4000)
            elif 'turn-control' in spec:
                heading += (math.pi if 'u-turn' in spec else math.pi/2)*min(1, max(0, (elapsed-1000)/(stop-1000)))
            distance = max(0, min(elapsed, stop)-1000)/1000*(.3 if cargo == 'full' else .5)
            x, y = -distance*math.cos(math.pi*.75), -distance*math.sin(math.pi*.75)
            speed = .36 if cargo == 'full' else .56
            gait = (1 if 3500 <= elapsed < 5500 else 2 if 5500 <= elapsed < 7500 else 0) if spec == 'back-modifiers' else (2 if 'back-arc' in spec and 3500 <= elapsed < 6500 else 0)
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+elapsed} elapsed={elapsed} run=false sprint=false requestedGait={gait} speed={speed} pace=1.04 stepY=-0.56 x={x} y={y} ramp=heading:{heading}')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=20')
    valid = '\n'.join(lines)
    assert analyzer['analyze'](valid)['motionPass']
    invalid = valid.replace('run=false', 'run=true')
    assert not analyzer['analyze'](invalid)['motionPass']
    for invalid in (valid.replace('pace=1.04', 'pace=nan'), valid.replace('male-empty-back-modifiers', 'unexpected')):
        try:
            analyzer['analyze'](invalid)
        except AssertionError:
            pass
        else:
            raise AssertionError('Malformed motion evidence must fail')
    missing_modifiers = '\n'.join(line for line in lines if not (
        '[WOOD_BANK_SAMPLE]' in line and 'back-modifiers' in line
        and 3500 <= int(re.search(r'elapsed=(\d+)', line)[1]) < 7500))
    stationary_arcs = '\n'.join(re.sub(r'x=([^ ]+) y=([^ ]+)', 'x=0 y=0', line)
                                if '[WOOD_BANK_SAMPLE]' in line and 'back-arc' in line else line for line in lines)
    forward_arcs = '\n'.join(re.sub(r'x=([^ ]+) y=([^ ]+)', lambda m: f'x={-float(m[1])} y={-float(m[2])}', line)
                             if '[WOOD_BANK_SAMPLE]' in line and 'back-arc' in line else line for line in lines)
    false_passes = []
    for label, invalid in [('missing modifier stages', missing_modifiers), ('stationary arcs', stationary_arcs),
                           ('forward arcs', forward_arcs), ('wrong requested gait', re.sub(r'requestedGait=[12]', 'requestedGait=0', valid)),
                           ('invalid native boolean', valid.replace('run=false', 'run=unknown'))]:
        try:
            passed = analyzer['analyze'](invalid)['motionPass']
        except AssertionError:
            passed = False
        if passed:
            false_passes.append(label)
    assert not false_passes, 'Invalid motion evidence passed: '+', '.join(false_passes)


def check_lua(executable):
    if not executable:
        return "SKIPPED (supply --lua or install Lua/LuaJIT)"
    for name in ("test-area.lua", "bootstrap.lua", "scenario-clips.lua", "scenario-reverse.lua", "scenario-reversal.lua", "scenario-stop.lua", "scenario-stationary.lua", "scenario-maneuvers.lua", "obstacles.lua", "scenario-collision.lua", "scenario-interaction.lua", "scenario-path.lua", "scene-selection.lua", "vehicles.lua", "scenario-vehicles.lua", "scenario-controls.lua", "scenario-variants.lua"):
        path = json.dumps(str(HERE / name), ensure_ascii=False)
        # loadfile parses without executing game APIs; missing config must fail first.
        code = f"assert(loadfile({path})); local ok,err=pcall(dofile,{path}); assert(not ok and tostring(err):find('CartMotionConfig',1,true),tostring(err))"
        subprocess.run([executable, "-e", code], check=True, cwd=HERE)
    area = json.dumps(str(HERE / "test-area.lua"), ensure_ascii=False)
    code = "CartMotionConfig={disposable=true,area={x=10825.5,y=10142.5,z=7,minX=10777,minY=10094,size=96,margin=2,floorSprite='carpentry_02_57'}}; "
    code += f"local a=dofile({area}); assert(a.size==96 and a.contains(a.x,a.y,a.z) and not a.contains(a.minX,a.minY,a.z)); "
    code += "getWorld=function() return {getWorld=function() return 'PlayerSave' end} end; local ok,err=pcall(a.prepare); assert(not ok and tostring(err):find('non-test save',1,true),tostring(err))"
    subprocess.run([executable, "-e", code], check=True, cwd=HERE)
    return "PASS (syntax, missing config, area bounds and non-test-save refusal)"


def check_java(game, jdk):
    if game is None and jdk is None:
        return "SKIPPED (supply --game-java-dir and --jdk)"
    assert game is not None and jdk is not None, "Supply both Java dependency paths"
    game, jdk = game.resolve(), jdk.resolve()
    compiler = jdk / "bin" / ("javac.exe" if os.name == "nt" else "javac")
    version = subprocess.run([str(compiler), "-version"], check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout
    match = re.search(r"javac (\d+)", version)
    assert match and int(match[1]) >= 25, version
    jars = [game / name for name in ("projectzomboid.jar", "ZombieBuddy.jar")]
    assert all(path.is_file() for path in jars), "Local game/ZombieBuddy JARs required"
    with tempfile.TemporaryDirectory(prefix="wooden-cart-compile-") as output:
        subprocess.run([str(compiler), "--release", "17", "-cp", os.pathsep.join(map(str, jars)), "-d", output, str(HERE / "Main.java"), str(HERE / "KahluaChecks.java")], check=True)
        assert (Path(output) / "net/alexredby/cartlab/Main.class").is_file()
        runtime = jdk / "bin" / ("java.exe" if os.name == "nt" else "java")
        for pad in ('false', 'true'):
            subprocess.run([str(runtime), "-cp", os.pathsep.join([output, *map(str, jars)]), "KahluaChecks", str(HERE.parents[3])],
                           check=True, cwd=game, env=dict(os.environ, PZ_CART_TEST_PAD=pad,
                            PZ_CART_RUNTIME_FILE=str(Path(output)/'runtime.lua'),
                            PZ_CART_COMMAND_FILE=str(Path(output)/'commands.txt')))
    return "PASS (compile, chunk-window bounds/guard and stock Kahlua obstacle checks; native game not launched)"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-java-dir", type=Path)
    parser.add_argument("--jdk", type=Path)
    parser.add_argument("--lua", default=shutil.which("luajit") or shutil.which("lua"))
    args = parser.parse_args()
    check_manifest()
    lua = check_lua(args.lua)
    java = check_java(args.game_java_dir, args.jdk)
    print(f"WOODEN_CART_FIXTURE_CHECK: schema/files=PASS; Lua={lua}; Java={java}; live=NOT_RUN")


if __name__ == "__main__":
    main()
