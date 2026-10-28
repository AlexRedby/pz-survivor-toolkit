"""Opt-in Host coverage and ordinary native movement control; no visual verdict."""
import math

MOTION_DURATION=31000
CONTROL_DURATION=15800
MOTION_PHASES=[('idle',0),('walk',2000),('turn',5000),('stop',8000),('reverse',10000),('stop-back',12000),
               ('short-correction',15000),('correction-stop',16500),('run-forward',18000),('run-turn',19500),
               ('run-stop',21000),('sprint-forward',23000),('sprint-turn',24500),('sprint-stop',26000)]
MOTION_WINDOWS={'short-correction':(15100,16200),'correction-stop':(17000,17800),'run-forward':(18300,19300),
                'run-turn':(19700,20800),'run-stop':(21500,22500),'sprint-forward':(23300,24300),
                'sprint-turn':(24700,25800),'sprint-stop':(28500,30500)}
CONTROL_PHASES=[('control-idle',0,0,0),('control-walk',1200,1,0),('control-walk-stop',2800,0,0),
                ('control-run',4000,3,1),('control-run-stop',5600,0,0),('control-sprint',8600,1,2),
                ('control-turn',10200,5,2),('control-stop',11800,0,0)]
ACTION_PHASES=('drop-complete','pickup-complete','drop-cancel','drop-repeat','pickup-cancel','pickup-repeat','control-release')
ACTION_GROUND=(True,False,False,True,True,False,True)
CONFLICTS=('cart_wall_exit','cart_injury','cart_inventory_equip','cart_lease_control','cart_lease_lifetimes',
           'cart_lease_inventory','cart_lease_menu','cart_action_invalidation','cart_hotkey_setdown','cart_action_admission',
           'cart_time_alignment','cart_timeline','cart_observer_association')


def control_route(pad):
    x,y=pad['minX']+pad['size']/2+4,pad['minY']+pad['size']/2+4
    d=math.sqrt(.5)
    return dict(owner=dict(x=x,y=y,z=pad['z']),observer=dict(x=x+2,y=y+3,z=pad['z']),heading=-math.pi*.75,
                bounds=dict(minX=-(3*1.6+1)*d-8*1.6*d-(8*1.6+5),maxX=(6*1.6+3)*d,
                            minY=-(3*1.6+1)*d-(6*1.6+3)*d-8*1.6*d-8*.35-5,maxY=0))


def same_route(actual,expected):
    # Native Lua tostring and JSON encode can round float descriptors differently.
    if isinstance(expected,dict):
        return isinstance(actual,dict) and actual.keys()==expected.keys() and all(same_route(actual[k],v) for k,v in expected.items())
    return type(actual) in (int,float) and math.isfinite(actual) and abs(actual-expected)<1e-9


def validate_options(selection,require):
    options=selection.get('options',{})
    value=options.get('cart_visual_extended',False)
    require(type(value) is bool,'cart_visual_extended must be boolean')
    if not value:return False
    require(selection.get('kind')=='mp' and options.get('mp_host') is True
            and options.get('cart_variant')=='shopping-cart' and options.get('cart_fast_motion') is True
            and options.get('cart_actions') is True,'Extended visual bank requires shopping-cart Host, fast motion and native actions')
    require(not any(options.get(key) for key in CONFLICTS),'Extended visual bank has conflicting options')
    return True


def control_end(logs):
    import json
    starts=[json.loads(line.split('[CART_MP_VISUAL] CONTROL_START ',1)[1]) for line in logs['server'].splitlines()
            if '[CART_MP_VISUAL] CONTROL_START ' in line]
    if len(starts)!=1 or type(starts[0].get('epoch')) is not int:raise ValueError('Unique authoritative control epoch required')
    return starts[0]['epoch']+CONTROL_DURATION


def analyze(profile,selection,result,logs,states,common):
    require,parse,coverage,number=(common[key] for key in ('require','parse','coverage','number'))
    def rows(role,kind):
        marker='[CART_MP_VISUAL] '+kind+' '
        values=[parse(line.split(marker,1)[1]) for line in logs[role].splitlines() if marker in line]
        require(all(type(row) is dict and row.get('version')==1 and number(row.get('wall')) for row in values),role+'/'+kind+': malformed visual provenance')
        return values
    def one(role,kind):
        values=rows(role,kind);require(len(values)==1,role+'/'+kind+': unique receipt required');return values[0]
    start=one('server','CONTROL_START');epoch=start.get('epoch');spec=start.get('spec',{})
    require(type(epoch) is int and start.get('duration')==CONTROL_DURATION and start['wall']<epoch
            and spec.get('id')==result['cartID'] and spec.get('cargoID')==result['cargo']['id']
            and spec.get('cargoWeight')==result['cargo']['weight'],'Control authority cart/cargo/epoch mismatch')
    require(type(spec.get('worldPose')) is dict and all(number(spec['worldPose'].get(key)) for key in ('x','y','z','rotation')),
            'Control authoritative world pose missing')
    completed=[parse(line.split('[CART_MP_ACTION] ALL_COMPLETE ',1)[1]) for line in logs['server'].splitlines()
               if '[CART_MP_ACTION] ALL_COMPLETE ' in line]
    require(len(completed)==1 and completed[0].get('phases')==7 and completed[0]['wall']<=start['wall'],
            'No-cart control preceded actual native release completion')
    ready=rows('server','READY')
    require(sorted(row.get('actor') for row in ready)==['client1','client2']
            and all(row.get('id')==spec['id'] and completed[0]['wall']<=row['wall']<=start['wall'] for row in ready),
            'Control requires both native action/presentation readiness receipts')
    route=control_route(result['checkedPad']);setup=one('server','CONTROL_SETUP')
    require(setup.get('id')==spec['id'] and setup.get('spec')==spec and same_route(setup.get('route'),route)
            and completed[0]['wall']<=setup['wall']<start['wall'] and same_route(start.get('route'),route)
            and epoch-start['wall']==3000 and start['wall']-setup['wall']<5000,
            'Independent native control setup/route authority missing')
    positioned=rows('server','CONTROL_POSITIONED')
    require(sorted(row.get('actor') for row in positioned)==['client1','client2'],'Both authoritative control setup receipts required')
    for role in ('client1','client2'):
        target=route['owner' if role=='client1' else 'observer'];local=one(role,'CONTROL_POSITIONED')
        accepted=next(row for row in positioned if row['actor']==role)
        for row in (local,accepted):
            require(row.get('id')==spec['id'] and number(row.get('heading'))
                    and abs(math.atan2(math.sin(row['heading']-route['heading']),math.cos(row['heading']-route['heading'])))<.001
                    and all(number(row.get(k)) for k in ('x','y','z'))
                    and abs(row['x']-target['x'])+abs(row['y']-target['y'])<.2 and abs(row['z']-target['z'])<.25
                    and setup['wall']<=local['wall']<=row['wall']<=start['wall'],role+': control setup receipt differs')
    phase_results={};settlements={}
    for role in ('client1','client2'):
        actual=one(role,'CONTROL_START')
        require(actual.get('epoch')==epoch and actual.get('spec')==spec and same_route(actual.get('route'),route) and actual.get('duration')==CONTROL_DURATION
                and start['wall']<=actual['wall']<epoch,role+': authoritative control start differs')
        phases=rows(role,'CONTROL_PHASE')
        require([row.get('phase') for row in phases]==[p[0] for p in CONTROL_PHASES],role+': missing/reordered no-cart phases')
        for row,(name,target,drive,gait) in zip(phases,CONTROL_PHASES):
            require(row.get('actor')==role and row.get('epoch')==epoch and row.get('drive')==drive and row.get('gait')==gait
                    and number(row.get('elapsed')) and target<=row['elapsed']<=target+600 and row['wall']-epoch==row['elapsed'],
                    role+'/'+name+': native input phase provenance differs')
        finish=one(role,'CONTROL_COMPLETE')
        require(finish.get('actor')==role and finish.get('id')==spec['id'] and finish.get('epoch')==epoch
                and finish.get('inputReleased') is True and number(finish.get('elapsed'))
                and CONTROL_DURATION<=finish['elapsed']<=CONTROL_DURATION+600 and finish['wall']-epoch==finish['elapsed'],
                role+': bounded control/input completion missing')
        video_start,video_stop=one(role,'VIDEO_START'),one(role,'VIDEO_STOP')
        require(video_start.get('actor')==video_stop.get('actor')==role and video_start.get('epoch')==result['epoch']
                and video_stop.get('epoch')==epoch and video_start['wall']<=result['epoch']
                and video_stop['wall']>=finish['wall'],role+': video does not cover full no-cart tail')
        finals=[parse(line.split('[CART_MP] VIDEO_FINAL ',1)[1]) for line in logs[role].splitlines() if '[CART_MP] VIDEO_FINAL ' in line]
        require(len(finals)==1 and finals[0].get('file')==video_start.get('file') and number(finals[0].get('seconds'))
                and finals[0]['seconds']>=(video_stop['wall']-video_start['wall'])/1000-.75
                and type(finals[0].get('captured')) is int and finals[0]['captured']>0
                and type(finals[0].get('frames')) is int and finals[0]['frames']>0,role+': video duration/frames omit extended control')
        done=one(role,'DONE');clean=one(role,'CLEANUP_READY')
        require(done.get('actor')==clean.get('actor')==role and done.get('id')==clean.get('id')==spec['id']
                and done.get('epoch')==clean.get('epoch')==epoch and done.get('inputReleased') is True
                and done.get('videoCompleted') is True and done['wall']>=video_stop['wall']
                and clean['wall']>=done['wall'] and clean.get('cargoID')==spec['cargoID']
                and clean.get('floors')==clean.get('worldCount')==0,role+': owned pad/cart cleanup receipt missing')
    cleanup=one('server','CLEANUP');done=rows('server','DONE')
    require(sorted(row.get('actor') for row in done)==['client1','client2'] and cleanup.get('id')==spec['id']
            and cleanup.get('cargoID')==spec['cargoID'] and cleanup.get('floors')==3969 and cleanup.get('epoch')==epoch
            and all(row.get('id')==spec['id'] and row.get('epoch')==epoch and epoch+CONTROL_DURATION<=row['wall']<=cleanup['wall'] for row in done),
            'Native owned floor/cart cleanup authority missing')
    for role in ('client1','client2'):
        require(one(role,'CLEANUP_READY')['wall']>=cleanup['wall'],role+': cleanup preceded authority')
    for role in ('server','client1','client2'):
        endpoints=coverage(rows(role,'CONTROL_ENDPOINT'),'wall',epoch,(300,CONTROL_DURATION-100),role+'/control exact cart')
        require(all(row.get('actor')==role and row.get('epoch')==epoch and row.get('elapsed')==row['wall']-epoch
                    and row.get('id')==spec['id'] and row.get('cargoID')==spec['cargoID'] and row.get('cargoWeight')==spec['cargoWeight']
                    and row.get('worldPose')==spec['worldPose'] and row.get('primaryID')==row.get('secondaryID')==-1
                    and row.get('worldCount')==1 and row.get('cargoPreserved') is True
                    and row.get('queueScope')==('native-server' if role=='server' else 'client-lua-and-native')
                    and row.get('luaActions')==(None if role=='server' else 0)
                    and row.get('nativeActions')==0 and type(row.get('hasPath')) is bool
                    and row.get('pathScope')==('remote-network' if role=='client2' else 'authoritative-approach')
                    and (role=='client2' or row['hasPath'] is False) for row in endpoints),
                role+': no-cart ground/cargo endpoint changed')
        measured=coverage(states[role],'wall',epoch,(0,CONTROL_DURATION-100),role+'/native route')
        centre=route['owner'];bounds=route['bounds']
        require(all(centre['x']+bounds['minX']-.2<=row['x']<=centre['x']+bounds['maxX']+.2
                    and centre['y']+bounds['minY']-.2<=row['y']<=centre['y']+.2 for row in measured),
                role+': native control escaped planned route envelope')
        idle=coverage(states[role],'wall',epoch,(500,1100),role+'/centred control idle')
        require(all(abs(row['x']-centre['x'])+abs(row['y']-centre['y'])<.2 for row in idle),role+': native control did not start at centre')
        phase_results[role]={}
        for i,(name,target,drive,gait) in enumerate(CONTROL_PHASES):
            end=CONTROL_PHASES[i+1][1] if i+1<len(CONTROL_PHASES) else CONTROL_DURATION
            quiet_start=end-900 if name in ('control-run-stop','control-stop') else target+500
            selected=coverage(states[role],'wall',epoch,(quiet_start,end-100),role+'/'+name)
            require(all(row['primary']==row['secondary']==-1 and row['item']=='none' and row['enabled'] is False
                        and row.get('visualEnabled') is False and row['motion'] is False
                        and row.get('characterActions')==0 and type(row.get('hasPath')) is bool
                        and (role=='client2' or row['hasPath'] is False) for row in selected),
                    role+'/'+name+': native movement control retained cart/action state')
            distance=sum(math.hypot(b['x']-a['x'],b['y']-a['y']) for a,b in zip(selected,selected[1:]))
            if drive:
                require(distance>.15 and sum(row.get('nativeMoving') is True for row in selected)>=len(selected)/2,
                        role+'/'+name+': ordinary native movement missing')
                if role!='server':
                    require(all(type(row.get('trackProgress')) is list and row['trackProgress'] for row in selected),role+'/'+name+': native animation clocks missing')
                    clocks={}
                    for row in selected:
                        for track in row['trackProgress']:
                            require(type(track.get('name')) is str and number(track.get('time')) and number(track.get('duration'))
                                    and number(track.get('weight')),role+'/'+name+': malformed native animation clock')
                            if track['weight']>.1:clocks.setdefault(track['name'],set()).add(track['time'])
                    require(any(len(values)>=3 for values in clocks.values()),role+'/'+name+': native animation clocks frozen')
            else:
                require(max(math.hypot(row['x']-selected[0]['x'],row['y']-selected[0]['y']) for row in selected)<.15
                        and all(not row['run'] and not row['sprint'] and row.get('nativeMoving') is False for row in selected),role+'/'+name+': ordinary native stop did not settle')
            if not drive and name!='control-idle':
                phase=coverage(states[role],'wall',epoch,(target+100,end-100),role+'/'+name+'/braking')
                # Flags can stop before deferred native motion and remote catch-up finish.
                # Keep an independent 800ms static tail; report the actual physical settle time.
                candidates=[i for i,row in enumerate(phase) if phase[-1]['wall']-row['wall']>=(800 if name in ('control-run-stop','control-stop') else 500)
                            and all(not r['run'] and not r['sprint'] and r.get('nativeMoving') is False
                                    and math.hypot(r['x']-row['x'],r['y']-row['y'])<.15 for r in phase[i:])]
                require(candidates,role+'/'+name+': bounded native physical settlement missing')
                settlements.setdefault(name,{})[role]=phase[candidates[0]]['wall']-(epoch+target)
            if gait:
                require(sum(row['run' if gait==1 else 'sprint'] for row in selected)>=len(selected)/2,
                        role+'/'+name+': ordinary native fast mode missing')
            phase_results[role][name]={'samples':len(selected),'distance':distance}
    inputs=rows('client1','INPUT')
    require(inputs and all(row.get('actor')=='client1' and row.get('id')==spec['id'] and row.get('epoch')==result['epoch']
                           and row.get('elapsed')==row['wall']-result['epoch'] for row in inputs),'Exact motion input provenance missing')
    drive_gait={'short-correction':({1,5},0),'correction-stop':({0},0),'run-forward':({1},1),
                'run-turn':({1,5},1),'run-stop':({0},0),'sprint-forward':({1},2),'sprint-turn':({1,8},2),'sprint-stop':({0},0)}
    for index,(name,target) in enumerate(MOTION_PHASES[6:],6):
        end=MOTION_PHASES[index+1][1] if index+1<len(MOTION_PHASES) else MOTION_DURATION
        selected=coverage([row for row in inputs if row.get('phase')==name],'wall',result['epoch'],(target+50,end-50),name+'/native input')
        drives,gait=drive_gait[name]
        require(all(row.get('drive') in drives and row.get('gait')==gait and number(row.get('heading'))
                    and target<=row['elapsed']<end for row in selected),name+': native input mask/gait differs')
    correction=[row for row in inputs if row.get('phase')=='short-correction']
    require(len(correction)>=5 and correction[0].get('drive')==5 and any(row.get('drive')==1 for row in correction)
            and all(row.get('gait')==0 and row.get('drive') in (1,5) for row in correction),'Bounded short steering input missing')
    released=False
    for row in correction:
        if row['drive']==1:released=True
        require(not released or row['drive']==1,'Short steering re-pressed after release')
        require(row['elapsed']<15350 or row['drive']==1,'Short correction became broad pivot')
    def yaw(rows):
        return sum(math.atan2(math.sin(b['heading']-a['heading']),math.cos(b['heading']-a['heading'])) for a,b in zip(rows,rows[1:]))
    correction_state=coverage(states['client1'],'wall',result['epoch'],(15000,16400),'short correction yaw')
    correction_yaw=yaw(correction_state)
    require(-.4<correction_yaw<-.035,'Short correction native yaw missing or broad')
    fast={}
    for name,gait,turn in [('run-forward','run',0),('run-turn','run',-1),('sprint-forward','sprint',0),('sprint-turn','sprint',1)]:
        selected=coverage(states['client1'],'wall',result['epoch'],MOTION_WINDOWS[name],name+'/native fast motion')
        distance=sum(math.hypot(b['x']-a['x'],b['y']-a['y']) for a,b in zip(selected,selected[1:]))
        yaw_rows=coverage(states['client1'],'wall',result['epoch'],(dict(MOTION_PHASES)[name],MOTION_WINDOWS[name][1]),name+'/native turn onset') if turn else selected
        actual_yaw=yaw(yaw_rows)
        require(distance>.25 and sum(row[gait] for row in selected)>=len(selected)/2,name+': forward native fast mode missing')
        require(not turn or .04<actual_yaw*turn<1.2,name+': native fast turn missing or broad')
        fast[name]={'distance':distance,'yaw':actual_yaw}
    # Report the observed native packet/animation onset; the historical ~0.2-0.3s is a hypothesis, not an acceptance target.
    transitions={}
    for index,(name,target,drive,gait) in enumerate(CONTROL_PHASES[1:],1):
        if name=='control-turn':continue
        phase_end=CONTROL_PHASES[index+1][1] if index+1<len(CONTROL_PHASES) else CONTROL_DURATION
        seen={}
        for role in ('client1','client2'):
            candidates=[row for row in states[role] if epoch+target<=row['wall']<=epoch+phase_end-100
                        and row.get('nativeMoving') is bool(drive)
                        and (not gait or row['run' if gait==1 else 'sprint'])]
            require(candidates,role+'/'+name+': native onset/stop transition missing')
            seen[role]=min(row['wall'] for row in candidates)-(epoch+target)
        transitions[name]={**seen,'observerMinusOwnerMs':seen['client2']-seen['client1']}
    return {'evidenceComplete':True,'controlEpoch':epoch,'controlDurationMs':CONTROL_DURATION,'shortCorrectionYaw':correction_yaw,
            'fastMotion':fast,'ordinaryNativeMovement':phase_results,'nativeTransitionsMs':transitions,'physicalSettlementMs':settlements,
            'visualVerdict':'unreviewed','scope':'Native inputs, identities, lifecycle and recording coverage only; animation delay cause and visual quality require video review'}
