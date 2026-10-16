"""Source and analyzer checks only; no game launch or profile preparation."""
from pathlib import Path
import argparse
import copy
import json
import os
import re
import runpy
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def fixture(root):
    epoch = 100000
    matrix = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    for role in ('server', 'client1', 'client2'):
        lines = ['[CART_MP] START epoch=' + str(epoch)]
        poses = []
        for elapsed in range(0, 15001, 100):
            row = dict(wall=epoch + elapsed, id=7, user='client1', local_=role == 'client1',
                       enabled=role == 'client1', x=1., y=2., z=0., heading=0., run=False,
                       sprint=False, primary=42, secondary=42, item='SaucedWheelbarrow.WheelbarrowWood',
                       motion=role != 'server', pivot=role == 'client1', stepX=0., stepY=.5,
                       pace=1.04, bank=0., tracks='Bob_Walk=1.04@1.0;')
            row['local'] = row.pop('local_')
            lines.append('[CART_MP_STATE] ' + json.dumps(row))
            if role != 'server':
                poses.append(dict(wallTimeMillis=epoch + elapsed, id=7, primary=42, secondary=42,
                                  local_=role == 'client1', enabled=role == 'client1', female=False,
                                  cart=matrix, bones={side: matrix for side in ('Bip01_L_Hand', 'Bip01_R_Hand')}))
                poses[-1]['local'] = poses[-1].pop('local_')
        if role != 'server':
            for name, elapsed in zip(('idle', 'walk', 'turn', 'stop', 'reverse', 'stop-back'), (0, 2000, 5000, 8000, 10000, 12000)):
                lines.append(f'[CART_MP] PHASE {name} wall={epoch + elapsed} elapsed={elapsed}')
            events = [dict(event='setup', expected=1, cases=['owner_observer_motion']),
                      dict(event='case', id='owner_observer_motion', status='captured'),
                      dict(event='complete', expected=1, performed=1, skipped=0, failed=0)]
            for event in events:
                event.update(actor=role, suite='cart_motion_mp', kind='mp', mode='toolkit')
                lines.append('[QUEUE_CHECK] ' + json.dumps(event))
            (root / role).mkdir()
            (root / role / 'body-clearance.jsonl').write_text('\n'.join(map(json.dumps, poses)) + '\n')
        (root / (role + '-launch.log')).write_text('\n'.join(lines) + '\n')
    (root / 'execution.json').write_text('{"status":"completed"}')
    (root / 'selection.json').write_text(json.dumps(dict(suite='cart_motion_mp', kind='mp', mode='toolkit', cases=['owner_observer_motion'])))


def check_analyzer():
    analyzer = runpy.run_path(str(HERE / 'analyze.py'))
    with tempfile.TemporaryDirectory(prefix='cart-mp-self-check-') as directory:
        root = Path(directory)
        fixture(root)
        report = analyzer['analyze'](root)
        assert report['evidenceComplete'] and report['ownerOnlineID'] == 7 and report['cartID'] == 42 and report['modeSource'] == 'selection.json'
        assert len(report['phases']) == 6 and 'animationEquivalencePass' not in report
        files = {p: p.read_text() for p in root.rglob('*') if p.is_file()}
        def rejected(path, content):
            path.write_text(content)
            try:
                analyzer['analyze'](root)
            except (ValueError, KeyError, json.JSONDecodeError):
                pass
            else:
                raise AssertionError('Invalid evidence accepted: ' + str(path))
            finally:
                for source, original in files.items():
                    source.write_text(original)
        selection = root / 'selection.json'
        selection.unlink()
        try:
            analyzer['analyze'](root)
        except FileNotFoundError:
            pass
        else:
            raise AssertionError('Missing frozen selection accepted')
        selection.write_text(files[selection])
        for key, value in (('mode', 'vanilla'), ('cases', ['other']), ('suite', 'health'), ('kind', 'sp')):
            invalid = json.loads(files[selection]); invalid[key] = value
            rejected(selection, json.dumps(invalid))
        registered = json.loads(files[selection]); registered['suite'] = 'wooden_cart_multiplayer'
        selection.write_text(json.dumps(registered))
        assert analyzer['analyze'](root)['evidenceComplete']
        selection.write_text(files[selection])
        log = root / 'client2-launch.log'
        log.write_text(files[log].replace(', "mode": "toolkit"', ''))
        assert analyzer['analyze'](root)['modeSource'] == 'selection.json'
        log.write_text(files[log])
        rejected(log, files[log].replace('"mode": "toolkit"', '"mode": "vanilla"'))
        rejected(log, files[log].replace('epoch=100000', 'epoch=100001'))
        rejected(log, files[log].replace('"status": "captured"', '"status": "passed"'))
        rejected(log, files[log].replace('[CART_MP] PHASE reverse', '[CART_MP] PHASE unknown'))
        rejected(log, files[log].replace('"local": false', '"local": "false"'))
        rejected(log, files[log].replace('"primary": 42', '"primary": 43'))
        rejected(log, files[log].replace('"id": 7', '"id": 8'))
        rejected(log, files[log] + '\n[CLEARANCE_PROBE] ERROR broken')
        rejected(log, files[log].replace('"x": 1.0', '"x": NaN'))
        pose = root / 'client2/body-clearance.jsonl'
        rejected(pose, '')
        rejected(pose, files[pose].replace('"female": false', '"female": 0'))
        rejected(pose, files[pose].replace('"primary": 42', '"primary": -1'))
        rejected(pose, files[pose].replace('"cart": [1,', '"cart": [1e999,'))
        # Many samples overall cannot cover a missing steady reverse window.
        rows = [json.loads(line) for line in files[pose].splitlines()]
        rejected(pose, '\n'.join(json.dumps(r) for r in rows if not 110500 <= r['wallTimeMillis'] <= 111500))
        # Five clustered frames satisfy a count gate but fail timing coverage.
        clustered = [r for r in rows if not 105500 <= r['wallTimeMillis'] <= 107500]
        for time in (106000, 106001, 106002, 106003, 106004):
            row = copy.deepcopy(rows[0]); row['wallTimeMillis'] = time; clustered.append(row)
        rejected(pose, '\n'.join(map(json.dumps, clustered)))
        # Well-spread edges with a large internal hole must also fail.
        rejected(pose, '\n'.join(json.dumps(r) for r in rows if not 105900 <= r['wallTimeMillis'] <= 106600))
        for text in ('{"x":NaN}', '{"x":1e999}', '{"x":1,"x":2}'):
            try:
                analyzer['parse'](text)
            except ValueError:
                pass
            else:
                raise AssertionError('Malformed JSON accepted')
    return 'PASS (valid capture and 24 malformed/missing/selection/identity/timing cases)'



def check_placement(lua):
    placement = json.dumps(str(HERE / 'placement.lua'))
    code = """
package.preload.QueueTestSelection=function() return {disposable=true} end
local mode='decorations'
local square={}
function square:getX() return 0 end
function square:getY() return 0 end
function square:getZ() return 0 end
function square:getFloor() return mode~='missingfloor' and {} or nil end
function square:TreatAsSolidFloor() return true end
function square:isFree() return mode~='blocked' end
function square:getRoom() return mode=='room' and {} or nil end
function square:isVehicleIntersecting() return mode=='vehicle' end
function square:getObjects() error('Decoration count must not be used as collision') end
function square:testCollideAdjacent(_,x,y,z) return mode=='edgewall' and x==1 and y==0 and z==0 end
getCell=function() return {getGridSquare=function() return square end} end
local player={getCurrentSquare=function() return square end}
local place=assert(dofile(PLACEMENT))
local area=place(player);assert(area.size==13,'Decorations should be allowed')
for _,value in ipairs({'edgewall','vehicle','missingfloor','blocked','room'}) do
 mode=value;local ok,err=pcall(place,player)
 assert(not ok and tostring(err):find('No loaded clear13x13',1,true),value..': '..tostring(err))
end
package.loaded.QueueTestSelection={disposable=false}
local ok,err=pcall(dofile,PLACEMENT)
assert(not ok and tostring(err):find('disposable',1,true),'Missing disposable guard')
""".replace('PLACEMENT', placement)
    subprocess.run([lua, '-e', code], check=True)
    return 'PASS (decorations allowed; wall/vehicle/floor/free-space/room and disposable refusal)'


def check_java(game, jdk, patch):
    if game is None and jdk is None and patch is None:
        return 'SKIPPED (supply --game-java-dir, --jdk, --patch-jar)'
    assert all(value is not None for value in (game, jdk, patch)), 'Supply all three Java dependencies'
    javac = jdk / 'bin' / ('javac.exe' if os.name == 'nt' else 'javac')
    version = subprocess.run([str(javac), '-version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
    assert int(re.search(r'javac (\d+)', version)[1]) >= 25
    jars = [game / 'projectzomboid.jar', game / 'ZombieBuddy.jar', patch]
    assert all(p.is_file() for p in jars), 'Missing explicit compile JAR'
    base = (HERE.parent / 'wooden_cart_motion/Main.java').read_text()
    anchor = '    public static void main(String[] args)'
    assert base.count(anchor) == 1, 'Java base integration anchor changed'
    with tempfile.TemporaryDirectory(prefix='cart-mp-compile-') as directory:
        root = Path(directory)
        main = root / 'Main.java'
        main.write_text(base.replace(anchor, (HERE / 'MPMain.methods').read_text() + '\n' + anchor))
        subprocess.run([str(javac), '--release', '17', '-cp', os.pathsep.join(map(str, jars)), '-d', str(root), str(main), str(HERE / 'ClearanceProbe.java')], check=True)
        assert (root / 'net/alexredby/cartlab/Main.class').is_file() and (root / 'ClearanceProbe.class').is_file()
    return 'PASS (composed keyboard fixture and render agent)'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua')
    parser.add_argument('--game-java-dir', type=Path)
    parser.add_argument('--jdk', type=Path)
    parser.add_argument('--patch-jar', type=Path)
    args = parser.parse_args()
    manifest = json.loads((HERE / 'manifest.json').read_text())
    assert manifest['runner_adapter'] is None and manifest['live_after_parameterization'] is False
    assert set(manifest['sources']) == {p.name for p in HERE.iterdir() if p.is_file()}
    for path in HERE.rglob('*'):
        if not path.is_file():
            continue
        assert path.suffix not in {'.jar', '.class', '.mp4', '.png', '.log', '.zip', '.pyc'}, path
        assert not re.search(r'/(?:Users|home|private/tmp|opt/homebrew)/', path.read_text()), path
    print('Sources: PASS')
    print('Analyzer:', check_analyzer())
    lua = args.lua or shutil.which('luajit') or shutil.which('lua')
    if lua:
        for name in ('client.lua', 'server.lua', 'placement.lua', 'json.lua'):
            subprocess.run([lua, '-e', 'assert(loadfile(' + json.dumps(str(HERE / name)) + '))'], check=True)
        subprocess.run([lua, '-e', 'local J=dofile(' + json.dumps(str(HERE / 'json.lua')) + '); assert(J.encode({true,false})=="[true,false]"); assert(not pcall(J.encode,0/0))'], check=True)
        print('Lua: PASS (syntax and JSON values)')
        print('Placement:', check_placement(lua))
    else:
        print('Lua: SKIPPED (supply --lua or install Lua/LuaJIT)')
    print('Java:', check_java(args.game_java_dir, args.jdk, args.patch_jar))


if __name__ == '__main__':
    main()
