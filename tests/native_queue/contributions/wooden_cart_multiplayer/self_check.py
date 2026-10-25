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


def fixture(root, fast=False, actions=False, variant=None):
    epoch = 100000
    matrix = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    variants = {'shopping-cart': ('SaucedCarts.ShoppingCart', 'ShoppingCartFullModel'),
                'wooden-wheelbarrow': ('SaucedWheelbarrow.WheelbarrowWood', 'WheelbarrowWood'),
                'metal-wheelbarrow': ('SaucedWheelbarrow.WheelbarrowMetal', 'WheelbarrowMetal')}
    item, model = variants[variant or 'wooden-wheelbarrow']
    for role in ('server', 'client1', 'client2'):
        lines = ['[CART_MP] START epoch=' + str(epoch)]
        if fast:
            pad=dict(minX=-15,minY=-15,z=7,bankVersion=3,size=31,margin=2,vegetationFree=True,elevated=True,floorSprite='carpentry_02_57')
            lines.append('[CART_MP] '+('CART_PAD ' if role=='server' else 'SETUP ')+json.dumps(pad))
            if role!='server': lines.append('[CART_MP] PAD_READY '+json.dumps(dict(bankVersion=3,floors=961,z=7,minX=-15,minY=-15,size=31,wall=epoch-5000)))
        if variant is not None and role == 'server':
            lines.append('[CART_MP] CART_SPEC ' + json.dumps(dict(variant=variant, cartType=item, id=42, cargoCount=1, cargoID=99, cargoWeight=70)))
        poses = []
        duration = 26000 if fast else 15000
        for elapsed in range(0, duration+1, 100):
            row = dict(wall=epoch + elapsed, id=7, user='client1', local_=role == 'client1',
                       enabled=role == 'client1', x=1., y=2., z=0., heading=0., run=False,
                       sprint=False, primary=42, secondary=42, item=item,
                       motion=role != 'server', pivot=role == 'client1', stepX=0., stepY=.5,
                       pace=1.04, bank=0., tracks='Bob_Walk=1.04@1.0;')
            row['local'] = row.pop('local_')
            if fast: row['z']=7
            if variant is not None: row.update(cargoCount=1, cargoID=99, cargoWeight=70,
                modelProbeVersion=1,heldModel=model,overridePrimary=None,overrideSecondary=None)
            if fast and elapsed >= 15000:
                run = 15000 <= elapsed < 16500
                sprint = 16500 <= elapsed < 18500
                row.update(x=1+min(6, (elapsed-15000)/1000), y=2-min(3, max(0, (elapsed-16500)/1000)),
                           heading=-min(3, max(0, (elapsed-16500)/1000)), run=run, sprint=sprint)
            lines.append('[CART_MP_STATE] ' + json.dumps(row))
            if role != 'server':
                poses.append(dict(wallTimeMillis=epoch + elapsed, id=7, primary=42, secondary=42,
                                  local_=role == 'client1', enabled=role == 'client1', female=False,
                                  cart=matrix, bones={side: matrix for side in ('Bip01_L_Hand', 'Bip01_R_Hand')}))
                poses[-1]['local'] = poses[-1].pop('local_')
                if variant is not None: poses[-1].update(model=model,modelProbeVersion=1,heldModel=model,
                    overridePrimary=None,overrideSecondary=None)
        if role != 'server':
            phases = [('idle', 0), ('walk', 2000), ('turn', 5000), ('stop', 8000), ('reverse', 10000), ('stop-back', 12000)]
            if fast: phases += [('run', 15000), ('sprint-turn', 16500), ('fast-stop', 18500)]
            for name, elapsed in phases:
                lines.append(f'[CART_MP] PHASE {name} wall={epoch + elapsed} elapsed={elapsed}')
            events = [dict(event='setup', expected=1, cases=['owner_observer_motion']),
                      dict(event='case', id='owner_observer_motion', status='captured'),
                      dict(event='complete', expected=1, performed=1, skipped=0, failed=0)]
            if actions: events[1]['cartActions'] = True
            for event in events:
                event.update(actor=role, suite='cart_motion_mp', kind='mp', mode='toolkit')
                lines.append('[QUEUE_CHECK] ' + json.dumps(event))
            (root / role).mkdir()
            (root / role / 'body-clearance.jsonl').write_text('\n'.join(map(json.dumps, poses)) + '\n')
        (root / (role + '-launch.log')).write_text('\n'.join(lines) + '\n')
    (root / 'execution.json').write_text('{"status":"completed"}')
    options = dict(cart_fast_motion=fast, cart_actions=actions) if fast or actions else {}
    if variant is not None: options['cart_variant'] = variant
    (root / 'selection.json').write_text(json.dumps(dict(suite='cart_motion_mp', kind='mp', mode='toolkit', cases=['owner_observer_motion'], options=options)))
    if actions: action_fixture(root, epoch, duration, matrix, model if variant is not None else None)


def action_fixture(root, epoch, duration, matrix, model=None):
    phases = ('drop-complete', 'pickup-complete', 'drop-cancel', 'drop-repeat', 'pickup-cancel', 'pickup-repeat')
    grounds = (True, False, False, True, True, False)
    logs = {role: [] for role in ('server', 'client1', 'client2')}
    poses = {'client1': [], 'client2': []}
    def emit(role, kind, row): logs[role].append('[CART_MP_ACTION] ' + kind + ' ' + json.dumps(row))
    for index, (phase, ground) in enumerate(zip(phases, grounds), 1):
        begin = epoch+duration+500+(index-1)*2500
        cancelled = index in (3, 5)
        base = dict(index=index, phase=phase, id=42)
        emit('client1', 'BEGIN', dict(base, actor='client1', wall=begin, cancel=cancelled))
        emit('server', 'SERVER_BEGIN', dict(base, wall=begin+5))
        server = dict(base, actor='server', wall=begin+1500, cargoID=99, cargoWeight=70, cargoPreserved=True,
                      inventoryCount=int(not ground), worldCount=int(ground), primaryID=-1 if ground else 42,
                      secondaryID=-1 if ground else 42, nativeActions=0, hasPath=False, held=not ground, ground=ground,
                      ok=True, holdMs=100)
        for role in ('client1', 'client2'):
            emit(role, 'WINDOW', dict(base, wall=begin+15, serverWall=begin+5))
            schedule = [(100, .1, True, False), (200, .15, True, False), (300, .2, True, False),
                        (400, .28, True, False), (500, .35, True, False)]
            schedule += [(600, .3, False, True), (800, .1, False, True)] if cancelled else [(700, .6, True, False), (1000, .9, True, False)]
            schedule += [(1200, 0, False, False)]
            for delta, progress, active, recovering in schedule:
                hands = (-1 if phase.startswith('pickup') else 42) if active or recovering else (-1 if ground else 42)
                row = dict(base, actor=role, wall=begin+delta, active=active, recovering=recovering, progress=progress,
                           pickup=phase.startswith('pickup') if active or recovering else False,
                           rendered=active or recovering, ik=active or recovering, primaryID=hands, secondaryID=hands)
                emit(role, 'PRESENTATION', row)
                if role == 'client1' and cancelled and delta == 500:
                    emit(role, 'CANCEL', dict(base, actor=role, wall=begin+500, progress=.35))
                if active:
                    pose = dict(wallTimeMillis=begin+delta, id=7, primary=hands, secondary=hands,
                                enabled=False, female=False, cart=matrix,
                                bones={side: matrix for side in ('Bip01_L_Hand', 'Bip01_R_Hand')})
                    pose['local'] = role == 'client1'; poses[role].append(pose)
                    if model is not None: pose['model'] = model
            if role == 'client1':
                receipt = dict(server, actor=role, wall=begin+1400, luaActions=0, cancelled=cancelled,
                               nativeProgress=True, presentationProgress=True, recoveryEnded=True,
                               recoveryObserved=cancelled, elapsed=1400)
                emit(role, 'RECEIPT', receipt)
            emit(role, 'SERVER_ACK', dict(server, wall=begin+1510, serverWall=server['wall']))
        emit('server', 'SERVER_RECEIPT', server)
    done = dict(id=42, phases=6, wall=server['wall']+1)
    emit('server', 'ALL_COMPLETE', done)
    for role in ('client1', 'client2'):
        emit(role, 'SERVER_DONE', dict(done, ok=True, wall=done['wall']+19, serverWall=done['wall']))
        for delta in (130, 230, 330):
            emit(role, 'PRESENTATION', dict(index=6, phase=phases[-1], id=42, actor=role, wall=done['wall']+19+delta,
                 active=False, recovering=False, progress=0, pickup=False, rendered=False, ik=False, primaryID=42, secondaryID=42))
        with (root / role / 'body-clearance.jsonl').open('a') as output:
            output.write('\n'.join(map(json.dumps, poses[role])) + '\n')
    for role, lines in logs.items():
        with (root / (role+'-launch.log')).open('a') as output: output.write('\n'.join(lines) + '\n')


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


def check_extended_analyzer():
    analyzer = runpy.run_path(str(HERE / 'analyze.py'))
    checked = 0
    for fast, actions in ((True, False), (False, True), (True, True)):
        with tempfile.TemporaryDirectory(prefix='cart-mp-extra-check-') as directory:
            root = Path(directory); fixture(root, fast=fast, actions=actions)
            report = analyzer['analyze'](root)
            assert report['evidenceComplete'] and len(report['phases']) == (10 if fast else 6)
            assert ('fastMotion' in report) == fast and ('actions' in report) == actions
            assert 'animationEquivalencePass' not in report
            files = {p: p.read_text() for p in root.rglob('*') if p.is_file()}
            def rejected(path, content):
                nonlocal checked
                path.write_text(content)
                try:
                    analyzer['analyze'](root)
                except (ValueError, KeyError, json.JSONDecodeError):
                    checked += 1
                else:
                    raise AssertionError('Invalid extended evidence accepted: ' + str(path))
                finally:
                    for source, original in files.items(): source.write_text(original)
            def edit(role, kind, change):
                path = root / (role+'-launch.log'); marker = '[CART_MP_ACTION] '+kind+' '
                lines = []
                for line in files[path].splitlines():
                    if marker in line:
                        row = json.loads(line.split(marker, 1)[1]); row = change(row)
                        if row is None: continue
                        line = marker+json.dumps(row)
                    lines.append(line)
                rejected(path, '\n'.join(lines)+'\n')
            def changed(row, **values): return dict(row, **values)
            selection = root / 'selection.json'
            invalid = json.loads(files[selection]); invalid['options']['cart_fast_motion' if fast else 'cart_actions'] = 1
            rejected(selection, json.dumps(invalid))
            if fast:
                owner = root/'client1-launch.log'
                server = root/'server-launch.log'
                rejected(server,files[server].replace('[CART_MP] CART_PAD ','[CART_MP] MISSING_PAD '))
                rejected(server,files[server].replace('"vegetationFree": true','"vegetationFree": false'))
                rejected(owner,files[owner].replace('"size": 31','"size": 13'))
                rejected(owner,files[owner].replace('"floors": 961','"floors": 960'))
                rejected(owner,files[owner].replace('[CART_MP] PAD_READY ','[CART_MP] MISSING_PAD_READY '))
                rejected(owner,files[owner].replace('"x": 1.0','"x": -14.0'))
                rejected(owner, files[owner].replace('[CART_MP] PHASE run ', '[CART_MP] PHASE missing '))
                rejected(owner, files[owner].replace('"run": true', '"run": false'))
                rejected(owner, files[owner].replace('"sprint": true', '"sprint": false'))
                for wrong in ('movement', 'yaw'):
                    lines = []
                    for line in files[owner].splitlines():
                        if '[CART_MP_STATE] ' in line:
                            row = json.loads(line.split('[CART_MP_STATE] ', 1)[1])
                            if wrong == 'movement' and 115300 <= row['wall'] <= 116200: row.update(x=1, y=2)
                            if wrong == 'yaw' and 117000 <= row['wall'] <= 118200: row['heading'] = -row['heading']
                            line = '[CART_MP_STATE] '+json.dumps(row)
                        lines.append(line)
                    rejected(owner, '\n'.join(lines)+'\n')
                probe = root/'client2/body-clearance.jsonl'
                rejected(probe, '\n'.join(line for line in files[probe].splitlines()
                         if not 117000 <= json.loads(line)['wallTimeMillis'] <= 118200))
            if actions:
                # The next native action may start after Ack but before its server phase marker arrives.
                path=root/'client1-launch.log';marker='[CART_MP_ACTION] PRESENTATION '
                lines=files[path].splitlines()
                ack=next(json.loads(line.split('[CART_MP_ACTION] SERVER_ACK ',1)[1]) for line in lines
                         if '[CART_MP_ACTION] SERVER_ACK ' in line and json.loads(line.split('[CART_MP_ACTION] SERVER_ACK ',1)[1])['index']==2)
                prior=next(json.loads(line.split(marker,1)[1]) for line in lines if marker in line
                           and json.loads(line.split(marker,1)[1])['index']==2)
                spill=dict(prior,wall=ack['wall']+1,active=True,pickup=False,progress=.01)
                at=max(i for i,line in enumerate(lines) if marker in line and json.loads(line.split(marker,1)[1])['index']==2)+1
                lines.insert(at,marker+json.dumps(spill));path.write_text('\n'.join(lines)+'\n')
                assert analyzer['analyze'](root)['actions']['evidenceComplete']
                path.write_text(files[path])
                edit('client1','PRESENTATION',lambda r: changed(r,pickup=False) if r['index']==2 and r['active'] else r)
                edit('client1', 'RECEIPT', lambda r: None if r['index']==3 else r)
                edit('client1', 'RECEIPT', lambda r: changed(r, id=43))
                edit('client1', 'RECEIPT', lambda r: {key: value for key, value in r.items() if key != 'id'})
                edit('client1', 'RECEIPT', lambda r: changed(r, cargoID=100) if r['index']==2 else r)
                edit('server', 'SERVER_RECEIPT', lambda r: changed(r, ground=False) if r['index']==1 else r)
                edit('client1', 'RECEIPT', lambda r: changed(r, nativeProgress=False))
                edit('client1', 'RECEIPT', lambda r: changed(r, cancelled=False))
                edit('client1', 'RECEIPT', lambda r: changed(r, recoveryObserved=False))
                edit('client1', 'RECEIPT', lambda r: changed(r, recoveryEnded=False))
                edit('client1', 'CANCEL', lambda r: changed(r, progress=.9))
                edit('server', 'SERVER_BEGIN', lambda r: changed(r, index=7-r['index']))
                edit('client2', 'SERVER_ACK', lambda r: changed(r, cargoWeight=0))
                edit('client2', 'SERVER_DONE', lambda r: None)
                edit('client2', 'PRESENTATION', lambda r: changed(r, progress=0))
                edit('client2', 'PRESENTATION', lambda r: changed(r, progress=1-r['progress']) if r['active'] else r)
                edit('client2', 'PRESENTATION', lambda r: changed(r, ik=False))
                edit('client2', 'PRESENTATION', lambda r: changed(r, rendered=False))
                edit('client2', 'PRESENTATION', lambda r: changed(r, recovering=False))
                edit('client2', 'PRESENTATION', lambda r: changed(r, active='true'))
                edit('client2', 'PRESENTATION', lambda r: changed(r, active=True, pickup=True) if r['index']==6 and r['progress']==0 else r)
                probe = root/'client2/body-clearance.jsonl'
                start = 100000+(26000 if fast else 15000)+500
                rejected(probe, '\n'.join(line for line in files[probe].splitlines()
                         if not start <= json.loads(line)['wallTimeMillis'] <= start+1400))
    return 'PASS (fast/actions/combined captures and '+str(checked)+' rejected lifecycle/progress/identity/recovery/probe cases)'


def check_variants():
    analyzer = runpy.run_path(str(HERE / 'analyze.py'))
    for variant in analyzer['VARIANTS']:
        with tempfile.TemporaryDirectory(prefix='cart-mp-variant-check-') as directory:
            root = Path(directory); fixture(root, fast=True, actions=variant in ('wooden-wheelbarrow', 'metal-wheelbarrow'), variant=variant)
            report = analyzer['analyze'](root)
            assert report['cartVariant'] == variant and report['cargo']['id'] == 99 and len(report['phases']) == 10
            render = report['phases']['run']['client2']['render']
            assert ('wheelFloorRange' in render) == (variant=='wooden-wheelbarrow')
            assert ('rawTransformCoverage' in render) == (variant!='wooden-wheelbarrow')
            if variant == 'metal-wheelbarrow':
                assert report['actions']['evidenceComplete']
                for role in ('client1', 'client2'):
                    for phase in report['actions']['phases'][role]:
                        assert phase['models'] == ['WheelbarrowMetal'] and phase['rawTransformCoverage']
                        assert 'wheelFloorRange' not in phase and 'palmHandleErrorMax' not in phase
            files = {p: p.read_text() for p in root.rglob('*') if p.is_file()}
            model=analyzer['FILLED_MODELS'][variant]
            try:
                for path,content in files.items():
                    path.write_text(content.replace('"heldModel": "'+model+'"','"heldModel": "Base.'+model+'"'))
                aliased=analyzer['analyze'](root)
                assert aliased['phases']['run']['client2']['render']['models']==[model]
            finally:
                for path,content in files.items():path.write_text(content)
            def rejected(path, content):
                path.write_text(content)
                try: analyzer['analyze'](root)
                except (ValueError, KeyError): pass
                else: raise AssertionError('Invalid variant evidence accepted: '+str(path))
                finally:
                    for source, original in files.items(): source.write_text(original)
            selection = root/'selection.json'
            for invalid in (None, True, 'unknown', 'SaucedCarts.ShoppingCart'):
                value = json.loads(files[selection]); value['options']['cart_variant'] = invalid
                rejected(selection, json.dumps(value))
            if variant == 'shopping-cart':
                value = json.loads(files[selection]); value['options']['cart_actions'] = True
                rejected(selection, json.dumps(value))
            server = root/'server-launch.log'
            rejected(server, '\n'.join(line for line in files[server].splitlines() if '[CART_MP] CART_SPEC ' not in line))
            observer = root/'client2-launch.log'
            rejected(observer, files[observer].replace('"cargoID": 99', '"cargoID": 100'))
            rejected(observer, files[observer].replace('"cargoWeight": 70', '"cargoWeight": 0'))
            rejected(observer, files[observer].replace('"cargoCount": 1', '"cargoCount": 0'))
            probe = root/'client2/body-clearance.jsonl'
            rejected(probe, '')
            rows = [json.loads(line) for line in files[probe].splitlines()]
            rows[0]['model'] = 'WrongCartModel'
            rejected(probe, '\n'.join(map(json.dumps, rows)))
            for field,value in (('heldModel','WrongCartModel'),('heldModel',None),('overridePrimary',7),('modelProbeVersion',True)):
                rows=[json.loads(line) for line in files[probe].splitlines()]
                rows[10][field]=value
                rejected(probe,'\n'.join(map(json.dumps,rows)))
            for wrong in ('Other.'+model,'Base.Other.'+model,'Base.Base.'+model,
                          'Base.ShoppingCartPartialModel','Base.WheelbarrowMetal' if variant=='wooden-wheelbarrow' else 'Base.WheelbarrowWood'):
                rows=[json.loads(line) for line in files[probe].splitlines()]
                rows[10]['heldModel']=wrong
                rejected(probe,'\n'.join(map(json.dumps,rows)))
                rejected(observer,files[observer].replace('"heldModel": "'+model+'"','"heldModel": "'+wrong+'"'))
            rows=[json.loads(line) for line in files[probe].splitlines()]
            rows[10]['model']='Base.'+model
            rejected(probe,'\n'.join(map(json.dumps,rows)))
            rows=[json.loads(line) for line in files[probe].splitlines()]
            del rows[10]['heldModel']
            rejected(probe,'\n'.join(map(json.dumps,rows)))
            if variant=='shopping-cart':
                for wrong in ('ShoppingCartModel','ShoppingCartPartialModel','ShoppingCartFlashlightFullModel'):
                    rows=[json.loads(line) for line in files[probe].splitlines()]
                    for row in rows:row['model']=wrong
                    rejected(probe,'\n'.join(map(json.dumps,rows)))
                rejected(observer,files[observer].replace('"heldModel": "ShoppingCartFullModel"','"heldModel": "ShoppingCartModel"'))
    return 'PASS (three exact cart variants, strict cargo/full render/held models and diagnostics, default wood geometry and invalid options)'



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
IsoObjectType={tree={}}
function square:has(kind) assert(kind==IsoObjectType.tree);return mode=='tree' end
function square:hasBush() return mode=='bush' end
function square:getProperties() return {get=function(_,key) assert(key=='Movement');return mode=='hedge' and 'HedgeHigh' or nil end} end
function square:getObjects() error('Decoration count must not be used as collision') end
function square:testCollideAdjacent(_,x,y,z) return mode=='edgewall' and x==1 and y==0 and z==0 end
getCell=function() return {getGridSquare=function() return square end} end
local player={getCurrentSquare=function() return square end}
local place=assert(dofile(PLACEMENT))
local area=place(player);assert(area.size==13 and area.x==-7.5 and area.y==-7.5,'Default native placement changed')
assert(area.x>=area.minX+area.margin and area.x<=area.minX+area.size-area.margin and area.y>=area.minY+area.margin and area.y<=area.minY+area.size-area.margin,'Default start outside interior')
for _,value in ipairs({'edgewall','vehicle','missingfloor','blocked','room'}) do
 mode=value;local ok,err=pcall(place,player)
 assert(not ok and tostring(err):find('No loaded clear13x13',1,true),value..': '..tostring(err))
end
package.loaded.QueueTestSelection.options={cart_fast_motion=true,mp_host=true}
package.loaded.QueueTestSelection.kind='mp'
local host=true
isServer=function() return true end
isClient=function() return false end
cartMPPadHost=function() return host end
local writes,floors,probe=0,0,16
local empty={size=function() return 0 end}
local occupied={size=function() return 1 end}
local upper={}
local chunk={}
local cell={}
function cell:getChunkForGridSquare(x,y,z) return not (mode=='unloaded' and x==probe and y==probe) and chunk or nil end
function cell:getGridSquare(x,y,z)
 if z==0 then return not (mode=='unloaded-ground' and x==probe and y==probe) and square or nil end
 if x==probe and y==probe and mode~='empty' then return {
  getFloor=function() return mode=='floor' and {} or nil end,
  getObjects=function() return mode=='occupied' and occupied or empty end,
  getSpecialObjects=function() return mode=='special' and occupied or empty end,
  getWorldObjects=function() return mode=='item' and occupied or empty end,
  getStaticMovingObjects=function() return mode=='corpse' and occupied or empty end,
  getMovingObjects=function() return mode=='actor' and occupied or empty end,
  getRoom=function() return mode=='upper-room' and {} or nil end,
  isVehicleIntersecting=function() return mode=='upper-vehicle' end,
 } end
 return upper[x..','..y]
end
function cell:createNewGridSquare(x,y,z)
 writes=writes+1;assert(z==7)
 local sq={addFloor=function(_,sprite) assert(sprite=='carpentry_02_57');writes=writes+1;floors=floors+1;return {} end}
 upper[x..','..y]=sq;return sq
end
function cell:setCacheGridSquare(x,y,z,sq) writes=writes+1;assert(z==7 and upper[x..','..y]==sq) end
function cell:setCacheChunk(value) writes=writes+1;assert(value==chunk) end
getCell=function() return cell end
for _,value in ipairs({'guard','unloaded','floor','occupied','special','item','corpse','actor','upper-room','upper-vehicle'}) do
 mode=value;host=value~='guard';writes=0
 local ok,err=pcall(assert(dofile(PLACEMENT)),player)
 assert(not ok and writes==0,'Invalid upper footprint edited before whole preflight: '..value..' '..tostring(err))
end
mode='empty';host=true;local elevated=assert(dofile(PLACEMENT))(player)
assert(elevated.minX==-15 and elevated.minY==-15 and elevated.x==4.5 and elevated.y==.5 and elevated.size==31 and elevated.margin==2 and elevated.bankVersion==3 and elevated.elevated==true and elevated.z==7 and floors==961,'Native elevated floor creation/cache count')
assert(elevated.x>=elevated.minX+elevated.margin and elevated.x+2<=elevated.minX+elevated.size-elevated.margin and elevated.y>=elevated.minY+elevated.margin and elevated.y+3<=elevated.minY+elevated.size-elevated.margin,'Extended owner/observer start outside interior')
package.loaded.QueueTestSelection.options.cart_injury=true
upper={};writes=0;floors=0;probe=32
for _,value in ipairs({'guard','unloaded','unloaded-ground','floor','occupied','special','item','corpse','actor','upper-room','upper-vehicle'}) do
 mode=value;host=value~='guard';writes=0
 local ok,result=pcall(assert(dofile(PLACEMENT)),player)
 if value=='unloaded' or value=='unloaded-ground' then
  assert(ok and result==nil and writes==0,'Injury pad must retry missing ground/chunks before mutation: '..value)
 else assert(not ok and writes==0,'Invalid injury pad halo edited before whole preflight: '..value..' '..tostring(result)) end
end
mode='empty';host=true;local injured=assert(dofile(PLACEMENT))(player)
assert(injured.minX==-31 and injured.minY==-31 and injured.size==63 and injured.bankVersion==5
 and injured.z==7 and injured.elevated==true and injured.margin==2 and floors==3969,'Native63x63 injury floor creation/cache count')
package.loaded.QueueTestSelection={disposable=false}
local ok,err=pcall(dofile,PLACEMENT)
assert(not ok and tostring(err):find('disposable',1,true),'Missing disposable guard')
""".replace('PLACEMENT', placement)
    subprocess.run([lua, '-e', code], check=True)
    return 'PASS (default13x13; fast31x31 and injury63x63 native creation/cache, missing injury chunk/ground retries and whole preflight refusal with zero edits)'


def check_capture_environment(lua):
    client=(HERE/'client.lua').read_text()
    bridge=(HERE/'MPMain.methods').read_text()
    assert "local expectedZoom=user=='client2' and 1 or .25" in client
    assert "assert(cartMPZoom(user=='client2')==expectedZoom" in client
    assert 'core.setAutoZoom(0,false);' in bridge and 'core.offscreenBuffer.setZoomAndTargetZoom(0,observer?1f:.25f);' in bridge
    assert 'doZoomScroll' not in client
    assert "' zoom='..getCore():getZoom(0)" in client
    assert 'p:getStats():reset(CharacterStat.ENDURANCE)\n    cartLabGait(steps[stage][3]);if not wallSide then cartLabDrive(steps[stage][2]) end' in client
    assert 'setSprinting(' not in client and 'setForceSprint(' not in client
    assert 'setPerkLevelDebug(' not in client and 'setXPToLevel(' not in client
    assert "p:getPerkLevel(Perks.Sprinting)==10" in client and 'Authoritative Sprinting snapshot deadline' in client
    assert 'zombie.network.GameServer.server || zombie.network.GameClient.client' in bridge
    assert 'p.getNetworkCharacterAI().updateXpChecker();' in bridge
    assert 'INetworkPacket.send(p,zombie.network.PacketTypes.PacketType.PlayerXp,p)' in bridge
    assert 'worldExistedAtStartup' in bridge and 'zombie.network.CoopSlave.instance==null' in bridge
    assert 'cartMPBrace(p,setup.cartId,setup.wallX,setup.y)' in client
    assert "assert(type(brace)=='string','Native brace diagnostics missing for exact fixture owner/cart')" in client
    assert client.index('if count~=setup.size*setup.size then return end')<client.index('position(p,setup.x,setup.y,setup.z)')
    assert "padFloors=padReady and setup.size*setup.size or 0,padWalls=wallSide and 49 or 0,padVersion=setup.bankVersion" in client
    code="""
local started,command,startCount
startCount=0
print=function(value) assert(not tostring(value):find('[QUEUE_TEST] FAIL',1,true),value)
 if tostring(value):find('[CART_MP] START epoch=',1,true) then startCount=startCount+1 end
end
Events={}
for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'}) do
 Events[name]={Add=function(fn) if name=='OnServerStarted' then started=fn elseif name=='OnClientCommand' then command=fn end end}
end
package.preload.QueueTestSelection=function() return {disposable=true} end
package.preload.CartMPJSON=function() return {} end
ClimateManager={FLOAT_FOG_INTENSITY=1,FLOAT_PRECIPITATION_INTENSITY=2,FLOAT_CLOUD_INTENSITY=3}
local values={}
getClimateManager=function() return {getClimateFloat=function(_,index)
 assert(index>=1 and index<=3 and not values[index]);values[index]={}
 return {setEnableAdmin=function(_,enabled) values[index].enabled=enabled end,
         setAdminValue=function(_,value) values[index].value=value end}
end} end
dofile(SOURCE)
assert(started);started()
for index=1,3 do assert(values[index].enabled==true and values[index].value==0) end
Perks={Sprinting={}}
getTimestampMs=function() return 1000 end
local owner={level=0,getUsername=function() return 'client1' end,getPerkLevel=function(self,perk) assert(perk==Perks.Sprinting);return self.level end}
local seed=0
cartMPSeedSprinting=function(player) assert(player==owner);seed=seed+1;player.level=10;return 10 end
command('CartMP','Armed',owner,{sprintLevel=0})
assert(seed==1 and owner.level==10 and startCount==0,'Transient old skill must request authoritative native snapshot')
local observer={getUsername=function() return 'client2' end}
command('CartMP','Armed',observer,{sprintLevel=0})
assert(startCount==0,'Owner was armed before its native level matched')
command('CartMP','Armed',owner,{sprintLevel=10})
assert(startCount==1,'Matching server/client native skill did not arm')
""".replace('SOURCE',json.dumps(str(HERE/'server.lua')))
    subprocess.run([lua,'-e',code],check=True,capture_output=True)
    return 'PASS (server weather/authoritative XP native snapshot, transient skill wait, close owner/wide observer native zoom, endurance; no forced sprint)'


def check_action_windows(lua):
    code=r"""
for _,name in ipairs({'SaucedCarts/ContextMenu','ISUI/ISContextMenu','ISUI/ISInventoryPaneContextMenu','TimedActions/ISTimedActionQueue'}) do package.preload[name]=function() return {} end end
package.preload.CartMPJSON=function() return {encode=function() return '{}' end} end
package.preload.QueueTestSelection=function() return {options={}} end
local count=0
print=function(line) if line:find('PRESENTATION',1,true) then count=count+1 end end
getTimestampMs=function() return 1000 end
toolkitWoodCartStatus=function() return {active=true,progress=.1} end
local player={getPrimaryHandItem=function() end,getSecondaryHandItem=function() end}
local actions=dofile(SOURCE)
actions.command('ActionPhase',{index=2,phase='pickup-complete',id=42})
actions.sample(player,'client1');assert(count==1)
actions.command('ActionAck',{index=2,id=43,ok=true});actions.sample(player,'client1');assert(count==2,'Foreign Ack closed window')
actions.command('ActionAck',{index=1,id=42,ok=true});actions.sample(player,'client1');assert(count==3,'Old Ack closed newer window')
actions.command('ActionAck',{index=2,id=42,ok=true});actions.sample(player,'client1');assert(count==3,'Next action sampled under closed phase')
actions.command('ActionPhase',{index=6,phase='pickup-repeat',id=42})
actions.command('ActionAck',{index=6,id=42,ok=true});actions.sample(player,'client1');assert(count==4,'Final quiescence lost')
""".replace('SOURCE',json.dumps(str(HERE/'actions.lua')))
    subprocess.run([lua,'-e',code],check=True,capture_output=True)
    return 'PASS (matching Ack closes completed phase; old/foreign Ack and final quiet preserved)'


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
        checks=root/'ModelProbeCheck.java'
        checks.write_text(r'''
public final class ModelProbeCheck {
    private static final class BracePlayer extends zombie.characters.IsoPlayer {
        boolean local=true,dead;
        String user="client1";
        short online;
        zombie.inventory.InventoryItem primary,secondary;
        zombie.inventory.ItemContainer inventory;
        zombie.iso.IsoGridSquare square;
        BracePlayer(){super(null,null,0,0,0);}
        @Override public float getX(){return 10;}
        @Override public float getY(){return 20;}
        @Override public float getZ(){return 7;}
        @Override public float getDirectionAngleRadians(){return 0;}
        @Override public zombie.core.skinnedmodel.animation.AnimationPlayer getAnimationPlayer(){return null;}
        @Override public boolean isLocalPlayer(){return local;}
        @Override public boolean isDead(){return dead;}
        @Override public String getUsername(){return user;}
        @Override public short getOnlineID(){return online;}
        @Override public zombie.inventory.InventoryItem getPrimaryHandItem(){return primary;}
        @Override public zombie.inventory.InventoryItem getSecondaryHandItem(){return secondary;}
        @Override public zombie.inventory.ItemContainer getInventory(){return inventory;}
        @Override public zombie.iso.IsoGridSquare getCurrentSquare(){return square;}
    }
    private static final class BraceItem extends zombie.inventory.InventoryItem {
        int identity;
        String type;
        zombie.inventory.ItemContainer container;
        BraceItem(){super("SaucedWheelbarrow","WheelbarrowWood","WheelbarrowWood",(String)null);}
        @Override public int getID(){return identity;}
        @Override public String getFullType(){return type;}
        @Override public zombie.inventory.ItemContainer getContainer(){return container;}
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var main=Class.forName("net.alexredby.cartlab.Main");
        var host=main.getDeclaredMethod("padHost");
        if((boolean)host.invoke(null))throw new AssertionError("Non-server pad mutation permission");
        var fresh=zombie.network.GameServer.class.getDeclaredField("worldExistedAtStartup");fresh.setAccessible(true);
        var unsafeField=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)unsafeField.get(null);
        boolean previousServer=zombie.network.GameServer.server,previousClient=zombie.network.GameClient.client,previousWorld=fresh.getBoolean(null);
        String previousName=zombie.network.GameServer.serverName;var previousCoop=zombie.network.CoopSlave.instance;
        try {
            zombie.network.GameServer.server=true;zombie.network.GameClient.client=false;
            zombie.network.GameServer.serverName="queue-smoke";zombie.network.CoopSlave.instance=(zombie.network.CoopSlave)unsafe.allocateInstance(zombie.network.CoopSlave.class);
            fresh.setBoolean(null,false);
            if(!(boolean)host.invoke(null))throw new AssertionError("Fresh native Host pad gate refused");
            fresh.setBoolean(null,true);
            if((boolean)host.invoke(null))throw new AssertionError("Existing native world allowed pad mutation");
            fresh.setBoolean(null,false);zombie.network.GameServer.serverName="user-save";
            if((boolean)host.invoke(null))throw new AssertionError("Foreign native Host allowed pad mutation");
        } finally {
            zombie.network.GameServer.server=previousServer;zombie.network.GameClient.client=previousClient;
            zombie.network.GameServer.serverName=previousName;zombie.network.CoopSlave.instance=previousCoop;fresh.setBoolean(null,previousWorld);
        }
        var ownerGuard=main.getDeclaredMethod("mpBraceOwner",zombie.characters.IsoPlayer.class,int.class);ownerGuard.setAccessible(true);
        var previousPlayer=zombie.characters.IsoPlayer.getInstance();var previousConnection=zombie.network.GameClient.connection;
        boolean previousHandshake=zombie.network.GameClient.instance.connected;
        var owner=(BracePlayer)unsafe.allocateInstance(BracePlayer.class);owner.local=true;owner.user="client1";
        owner.square=(zombie.iso.IsoGridSquare)unsafe.allocateInstance(zombie.iso.IsoGridSquare.class);
        owner.inventory=(zombie.inventory.ItemContainer)unsafe.allocateInstance(zombie.inventory.ItemContainer.class);
        var cart=(BraceItem)unsafe.allocateInstance(BraceItem.class);cart.identity=42;cart.type="SaucedWheelbarrow.WheelbarrowWood";cart.container=owner.inventory;
        owner.primary=owner.secondary=cart;
        try {
            zombie.network.GameClient.client=true;zombie.network.GameServer.server=false;zombie.network.GameClient.instance.connected=true;
            zombie.characters.IsoPlayer.setInstance(owner);
            zombie.network.GameClient.connection=(zombie.core.raknet.UdpConnection)unsafe.allocateInstance(zombie.core.raknet.UdpConnection.class);
            if(zombie.network.GameClient.connection.isFullyConnected())throw new AssertionError("Expected native Host transport flag false");
            if(!(boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Armed exact owner blocked by native Host transport flag");
            zombie.network.GameClient.instance.connected=false;if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Disconnected client sampled");zombie.network.GameClient.instance.connected=true;
            if((boolean)ownerGuard.invoke(null,owner,43) || (boolean)ownerGuard.invoke(null,null,42))throw new AssertionError("Foreign cart/null owner sampled");
            owner.local=false;if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Remote actor sampled");owner.local=true;
            owner.user="client2";if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Observer sampled");owner.user="client1";
            owner.dead=true;if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Dead owner sampled");owner.dead=false;
            owner.online=-1;if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Offline actor sampled");owner.online=0;
            var square=owner.square;owner.square=null;if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Unloaded owner sampled");owner.square=square;
            owner.secondary=null;if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Unequipped cart sampled");owner.secondary=cart;
            cart.container=null;if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Non-owned cart sampled");cart.container=owner.inventory;
            cart.type="SaucedWheelbarrow.WheelbarrowMetal";if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Foreign cart type sampled");cart.type="SaucedWheelbarrow.WheelbarrowWood";
            zombie.characters.IsoPlayer.setInstance(null);if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Different local instance sampled");zombie.characters.IsoPlayer.setInstance(owner);
            zombie.network.GameServer.server=true;if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Server sampled as local owner");
            zombie.network.GameServer.server=false;zombie.network.GameClient.client=false;
            if((boolean)ownerGuard.invoke(null,owner,42))throw new AssertionError("Single-player actor sampled");
        } finally {
            zombie.characters.IsoPlayer.setInstance(previousPlayer);zombie.network.GameClient.connection=previousConnection;
            zombie.network.GameClient.instance.connected=previousHandshake;
            zombie.network.GameServer.server=previousServer;zombie.network.GameClient.client=previousClient;
        }
        String raw="quote\"slash\\\n\r\t"+(char)1;
        for(String[] target:new String[][]{{"ClearanceProbe","jsonString"},{"net.alexredby.cartlab.Main","mpJsonString"}}) {
            var method=Class.forName(target[0]).getDeclaredMethod(target[1],String.class);method.setAccessible(true);
            System.out.println(method.invoke(null,raw));
            if(!"null".equals(method.invoke(null,(Object)null)))throw new AssertionError("null model JSON");
        }
        var probe=Class.forName("ClearanceProbe");
        var preparedWriter=probe.getDeclaredField("output");preparedWriter.setAccessible(true);
        var cameraWriter=probe.getDeclaredField("cameras");cameraWriter.setAccessible(true);
        var drawText=new java.io.StringWriter();preparedWriter.set(null,new java.io.BufferedWriter(new java.io.StringWriter()));
        cameraWriter.set(null,new java.io.BufferedWriter(drawText));
        var renderSlot=(zombie.core.skinnedmodel.model.ModelSlotRenderData)unsafe.allocateInstance(zombie.core.skinnedmodel.model.ModelSlotRenderData.class);
        renderSlot.character=owner;renderSlot.x=10.25f;renderSlot.y=20;renderSlot.z=7;renderSlot.animPlayerAngle=(float)(Math.PI/2);renderSlot.squareDepth=.25f;
        var sourceSlot=(zombie.core.skinnedmodel.ModelManager.ModelSlot)unsafe.allocateInstance(zombie.core.skinnedmodel.ModelManager.ModelSlot.class);sourceSlot.character=owner;
        ClearanceProbe.rememberNative(renderSlot,sourceSlot);
        var originalMap=probe.getDeclaredField("nativePoses");originalMap.setAccessible(true);
        var nativePose=((java.util.Map<?,?>)originalMap.get(null)).get(renderSlot);
        var originalX=nativePose.getClass().getDeclaredMethod("x");originalX.setAccessible(true);
        if((float)originalX.invoke(nativePose)!=10)throw new AssertionError("Cosmetic slot coordinate replaced original native capture");
        var bodyModel=(zombie.core.skinnedmodel.model.ModelInstance)unsafe.allocateInstance(zombie.core.skinnedmodel.model.ModelInstance.class);
        var cartModel=(zombie.core.skinnedmodel.model.ModelInstance)unsafe.allocateInstance(zombie.core.skinnedmodel.model.ModelInstance.class);
        var prepareDraw=probe.getDeclaredMethod("prepareDraw",zombie.core.skinnedmodel.model.ModelSlotRenderData.class,
            zombie.core.skinnedmodel.model.ModelInstance.class,zombie.core.skinnedmodel.model.ModelInstance.class);prepareDraw.setAccessible(true);
        prepareDraw.invoke(null,renderSlot,bodyModel,cartModel);
        var bodyData=(zombie.core.skinnedmodel.model.ModelInstanceRenderData)unsafe.allocateInstance(zombie.core.skinnedmodel.model.ModelInstanceRenderData.class);bodyData.modelInstance=bodyModel;
        var cartData=(zombie.core.skinnedmodel.model.ModelInstanceRenderData)unsafe.allocateInstance(zombie.core.skinnedmodel.model.ModelInstanceRenderData.class);cartData.modelInstance=cartModel;
        var previousCamera=zombie.core.skinnedmodel.ModelCamera.instance;
        var camera=(zombie.core.opengl.CharacterModelCamera)unsafe.allocateInstance(zombie.core.opengl.CharacterModelCamera.class);
        camera.x=10.25f;camera.y=20;camera.z=7;camera.useAngle=(float)(Math.PI/2);camera.useWorldIso=true;
        try {
            zombie.core.skinnedmodel.ModelCamera.instance=camera;ClearanceProbe.beginCamera(camera);
            ClearanceProbe.draw(renderSlot,bodyData);ClearanceProbe.draw(renderSlot,bodyData);
            camera.x=11;ClearanceProbe.draw(renderSlot,cartData);
            var recorded=drawText.toString();
            if(recorded.lines().count()!=2 || !recorded.contains("\"part\":\"body\"") || !recorded.contains("\"part\":\"cart\"")
                || !recorded.contains("\"cameraX\":10.25") || !recorded.contains("\"currentCameraX\":11.0"))
                throw new AssertionError("Consumed camera/body/cart draw identity was not independently captured");
            ClearanceProbe.endCamera();prepareDraw.invoke(null,renderSlot,bodyModel,cartModel);
            try {ClearanceProbe.draw(renderSlot,bodyData);throw new AssertionError("Draw without consumed camera was accepted");}
            catch(IllegalStateException expected) {}
        } finally {
            ClearanceProbe.endCamera();zombie.core.skinnedmodel.ModelCamera.instance=previousCamera;
            preparedWriter.set(null,null);cameraWriter.set(null,null);
        }
        var traceField=probe.getDeclaredField("solve");traceField.setAccessible(true);
        var trace=(ThreadLocal<StringBuilder>)traceField.get(null);
        var outputField=probe.getDeclaredField("solves");outputField.setAccessible(true);
        var text=new java.io.StringWriter();outputField.set(null,new java.io.BufferedWriter(text));
        if(ClearanceProbe.reachInput(null)!=null)throw new AssertionError("Unscoped solver diagnostic");
        for(boolean ok:new boolean[]{true,false}) {
            trace.set(new StringBuilder("{\"failures\":["));
            if(!ok) {ClearanceProbe.refusal("reach", "\"bone\":\"Bip01_R_Hand\"");ClearanceProbe.refusal("transitionGrip",null);}
            ClearanceProbe.finishSolve(ok);
            if(trace.get()!=null)throw new AssertionError("Solver scope leaked into next frame");
        }
        ClearanceProbe.finishSolve(false);System.out.print(text);outputField.set(null,null);
        var family=probe.getDeclaredMethod("cartFamily",String.class,String.class);family.setAccessible(true);
        for(String model:new String[]{"ShoppingCartModel","ShoppingCartPartialModel","ShoppingCartFullModel"})
            if(!(boolean)family.invoke(null,"SaucedCarts.ShoppingCart",model))throw new AssertionError("same-family mismatch was filtered");
        if((boolean)family.invoke(null,"SaucedCarts.ShoppingCart","WheelbarrowWood")
            || (boolean)family.invoke(null,"Base.Log","ShoppingCartFullModel"))throw new AssertionError("wrong cart family");
        var capture=probe.getDeclaredMethod("captureModel",zombie.inventory.InventoryItem.class,String.class);capture.setAccessible(true);
        for(String model:new String[]{"WheelbarrowWood","WheelbarrowMetal"}) {
            if(!(boolean)capture.invoke(null,null,model))throw new AssertionError("Empty native pickup hands filtered presentation model: "+model);
            cart.type="SaucedWheelbarrow."+model;
            if(!(boolean)capture.invoke(null,cart,model))throw new AssertionError("Exact held cart presentation filtered: "+model);
            String other=model.equals("WheelbarrowWood")?"WheelbarrowMetal":"WheelbarrowWood";
            if((boolean)capture.invoke(null,cart,other) || (boolean)capture.invoke(null,cart,"ShoppingCartFullModel"))
                throw new AssertionError("Held item acquired another cart family: "+model);
        }
        for(String model:new String[]{"ShoppingCartModel","ShoppingCartFullModel","WheelbarrowMetalExtra","Other.WheelbarrowMetal"})
            if((boolean)capture.invoke(null,null,model))throw new AssertionError("Unrelated empty-hand model captured: "+model);
        cart.type="Base.Log";
        if((boolean)capture.invoke(null,cart,"WheelbarrowMetal"))throw new AssertionError("Foreign held item acquired metal presentation");
        var known=probe.getDeclaredMethod("cartModel",String.class);known.setAccessible(true);
        if((boolean)known.invoke(null,"ShoppingCartUnknownModel"))throw new AssertionError("unknown attachment");
    }
}
''')
        classpath=os.pathsep.join([str(root),*map(str,jars)])
        subprocess.run([str(javac),'--release','17','-cp',classpath,'-d',str(root),str(checks)],check=True)
        java=jdk/'bin'/('java.exe' if os.name=='nt' else 'java')
        result=subprocess.run([str(java),'-cp',classpath,'ModelProbeCheck'],capture_output=True,text=True,
            env=dict(os.environ,PZ_CART_RUNTIME_FILE=str(root/'runtime.lua'),PZ_CART_COMMAND_FILE=str(root/'commands.txt')))
        assert result.returncode==0,result.stdout+'\n'+result.stderr
        parsed=[json.loads(line) for line in result.stdout.splitlines()]
        assert parsed[:2]==['quote"slash\\\n\r\t\x01']*2
        assert parsed[2:]==[dict(failures=[],ok=True), dict(failures=[dict(method='reach',bone='Bip01_R_Hand'),dict(method='transitionGrip')],ok=False)]
    return 'PASS (composed keyboard fixture, native Host read-only brace ownership/lifecycle guard, original native pose and consumed body/cart camera capture, render family mismatch capture, wood/metal empty-hand pickup selection and JSON escaping)'


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
    print('Extended analyzer:', check_extended_analyzer())
    print('Variants:', check_variants())
    lua = args.lua or shutil.which('luajit') or shutil.which('lua')
    if lua:
        for name in ('client.lua', 'server.lua', 'placement.lua', 'json.lua', 'actions.lua', 'wall.lua', 'wall-input.lua', 'injury.lua'):
            subprocess.run([lua, '-e', 'assert(loadfile(' + json.dumps(str(HERE / name)) + '))'], check=True)
        subprocess.run([lua, '-e', 'local J=dofile(' + json.dumps(str(HERE / 'json.lua')) + '); assert(J.encode({true,false})=="[true,false]"); assert(not pcall(J.encode,0/0))'], check=True)
        print('Lua: PASS (syntax and JSON values)')
        print('Placement:', check_placement(lua))
        print('Capture environment:', check_capture_environment(lua))
        print('Action windows:', check_action_windows(lua))
    else:
        print('Lua: SKIPPED (supply --lua or install Lua/LuaJIT)')
    print('Java:', check_java(args.game_java_dir, args.jdk, args.patch_jar))


if __name__ == '__main__':
    main()
