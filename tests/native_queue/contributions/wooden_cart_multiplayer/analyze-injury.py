"""Native Host injury evidence, including remote tracks and actual rendered owner/cart."""
from pathlib import Path
import math
import runpy

HERE = Path(__file__).resolve().parent
ORACLE = runpy.run_path(str(HERE.parent / 'wooden_cart_motion/analyze-injury.py'))
PHASES = (
    ('injury-healthy', 26000, 1, 0), ('injury-apply', 28000, 1, 0),
    ('injury-left', 30000, 5, 0), ('injury-right', 32400, 8, 0),
    ('injury-run', 34800, 5, 1), ('injury-sprint', 37200, 8, 2),
    ('injury-moving', 39600, 1, 0), ('injury-heal', 41000, 1, 0), ('injury-stop', 43000, 0, 0),
)
DURATION = 45000
FOOT = ('leftScratch', 'rightScratch', 'leftFracture', 'rightFracture')


def validate_options(options, require):
    enabled=options.get('cart_injury', False)
    require(type(enabled) is bool, 'cart_injury must be boolean')
    if enabled:
        require(options.get('mp_host') is True and options.get('cart_fast_motion') is True,
                'Injury bank requires native fast-motion Host')
        require(not options.get('cart_wall_exit') and not options.get('cart_actions') and not options.get('cart_hotkey_setdown'),
                'Injury bank cannot combine wall/actions')
        require(options.get('cart_injury_side') in ('left', 'right') and options.get('cart_injury_severity') in ('mild', 'heavy'),
                'Exact injury side and severity required')
    else:
        require('cart_injury_side' not in options and 'cart_injury_severity' not in options,
                'Injury side/severity require cart_injury')
    return enabled


def analyze(profile, selection, base_report):
    common=runpy.run_path(str(HERE / 'analyze.py'))
    require,parse,coverage=common['require'],common['parse'],common['coverage']
    profile=Path(profile);options=selection['options']
    require(validate_options(options, require), 'Injury bank not selected')
    epoch=base_report['epoch'];identity=base_report['ownerOnlineID'];cart=base_report['cartID']
    side,severity=options['cart_injury_side'],options['cart_injury_severity']
    logs={role:(profile/(role+'-launch.log')).read_text() for role in common['ROLES']}
    def records(role, marker):
        return [parse(line.split(marker,1)[1]) for line in logs[role].splitlines() if marker in line]
    events=records('client1','[CART_MP_INJURY] PHASE ')
    require([r.get('phase') for r in events]==[p[0] for p in PHASES], 'Missing/duplicate/reordered injury mutations/phases')
    require(not records('client2','[CART_MP_INJURY] PHASE ') and not records('server','[CART_MP_INJURY] PHASE '),
            'Remote/server local injury mutation is forbidden')
    for row,(name,target,drive,gait) in zip(events, PHASES):
        mutation='injure' if name=='injury-apply' else 'heal' if name=='injury-heal' else 'none'
        require(row.get('side')==side and row.get('severity')==severity and row.get('mutation')==mutation and row.get('authority')=='server-request'
                and row.get('drive')==drive and row.get('gait')==gait and common['number'](row.get('wall'))
                and common['number'](row.get('elapsed')) and target<=row['elapsed']<=target+600
                and row['wall']==epoch+row['elapsed'], 'Injury mutation/phase identity or timing differs')
    mutation_names=('injury-healthy','injury-apply','injury-heal')
    authority=records('server','[CART_MP_INJURY] SERVER_MUTATION ')
    acknowledgements=records('client1','[CART_MP_INJURY] ACK ')
    require([r.get('phase') for r in authority]==list(mutation_names)
            and [r.get('phase') for r in acknowledgements]==list(mutation_names),'Missing/duplicate/reordered native injury authority or acknowledgement')
    require(not records('client2','[CART_MP_INJURY] SERVER_MUTATION ')
            and not records('client1','[CART_MP_INJURY] SERVER_MUTATION ')
            and not records('client2','[CART_MP_INJURY] ACK '),'Observer/local injury authority is forbidden')
    for receipt,ack in zip(authority,acknowledgements):
        phase=next(r for r in events if r['phase']==receipt['phase'])
        require(receipt.get('source')=='NetworkPlayerAI.syncDamage' and receipt.get('id')==cart
                and receipt.get('side')==side and receipt.get('severity')==severity
                and common['number'](receipt.get('wall')) and phase['wall']<=receipt['wall']<=phase['wall']+1000
                and all(common['number'](receipt.get(k)) for k in (*FOOT,'walkInjury')),
                'Native injury authority source/identity/timing missing')
        require(ack.get('serverWall')==receipt['wall'] and ack.get('requestWall')==phase['wall']
                and common['number'](ack.get('wall')) and receipt['wall']<=ack['wall']<=phase['wall']+1000
                and all(ack.get(k)==v for k,v in receipt.items() if k!='wall'),
                'Native injury acknowledgement differs from authoritative snapshot')
        injured=receipt['phase']=='injury-apply'
        key=side+('Scratch' if severity=='mild' else 'Fracture')
        require((receipt[key]>(5 if severity=='mild' else 20)
                 and (receipt['walkInjury']>.15 if side=='left' else receipt['walkInjury']<-.15)) if injured
                else all(receipt[k]<=.01 for k in FOOT) and abs(receipt['walkInjury'])<=.01,
                'Native server did not derive injury/healing from authoritative BodyDamage')
    states={role:[common['state'](r) for r in records(role,'[CART_MP_STATE] ')
                  if r.get('id')==identity and r.get('user')=='client1'] for role in common['ROLES']}
    poses={role:[common['pose'](parse(line)) for line in (profile/role/'body-clearance.jsonl').read_text().splitlines()]
           for role in ('client1','client2')}
    spec=base_report.get('cargo')
    require(spec is not None, 'Injury bank requires authoritative exact cargo descriptor')
    inputs=records('client1','[CART_MP_INJURY] INPUT ')
    for row in inputs:
        require(type(row.get('elapsed')) is int and row.get('wall')==epoch+row['elapsed']
                and row.get('id')==cart and row.get('cargoID')==spec['id']
                and common['number'](row.get('cargoWeight')) and abs(row['cargoWeight']-spec['weight'])<.001
                and row.get('inventoryCount')==1 and row.get('luaActions')==row.get('nativeActions')==0
                and row.get('hasPath') is False and row.get('god') is False and row.get('dead') is False,
                'Injury owner inventory/cargo/queue or living actor differs')
    for role, rows in states.items():
        for row in rows:
            if not 26000<=row['wall']-epoch<DURATION: continue
            require(row.get('primary')==row.get('secondary')==cart and row.get('item')==base_report['cartType']
                    and row.get('cargoCount')==1 and row.get('cargoID')==spec['id']
                    and common['number'](row.get('cargoWeight')) and abs(row['cargoWeight']-spec['weight'])<.001
                    and row.get('worldID')==-1 and row.get('characterActions')==0 and row.get('hasPath') is False
                    and row.get('performing') is False, role+': injury cart/cargo/queue changed')
            if role!='client2':
                require(row.get('inventoryCount')==1 and row.get('primaryInInventory') is True,
                        role+': exact injury cart left owner inventory')
            if role=='client1':
                require(row.get('injuryProbeVersion')==1 and row.get('god') is False and row.get('dead') is False
                        and all(common['number'](row.get(key)) for key in FOOT), 'Missing real living owner BodyDamage evidence')
    runtime=profile/'runtime.json'
    game=parse(runtime.read_text()).get('game') if runtime.is_file() else None
    source=ORACLE['_walk_source'](game)
    summaries=[]
    def track_check(row, injured, moving, gait, label):
        require(common['number'](row.get('walkInjury')) and common['number'](row.get('walkSpeed'))
                and isinstance(row.get('tracks'),str), label+': missing native injury animation fields')
        clips=ORACLE['tracks'](row['tracks'])
        active=[c for c in clips if c['weight']>.1 and abs(c['speed'])>.001]
        if not injured:
            require(abs(row['walkInjury'])<=.01 and not any('Limp' in c['name'] for c in active),
                    label+': injury/limp remained in healthy or healed actor')
        else:
            require(row['walkInjury']>.15 if side=='left' else row['walkInjury']<-.15,
                    label+': native injury side/scalar missing')
            if moving:
                run=row.get('run',False);sprint=row.get('sprint',False)
                # Native gait eligibility owns these flags; heavy Walk may remain during Run.
                if not sprint:
                    if run:
                        suffix='R' if side=='left' else 'L'
                        expected={'Bob_WalkLightLimp'+suffix,'Bob_WalkHeavyLimp'+suffix,'Bob_RunLightLimp'+suffix}
                        require(any(c['name'] in expected and c['weight']>1e-4 and abs(c['speed'])>.001 for c in clips), label+': native final gait lost limp')
                    else:
                        require(ORACLE['_walk_mix'](dict(injury=row['walkInjury'],walkSpeed=row['walkSpeed'],clips=clips)),
                                label+': native limp blend differs from WalkInjury/WalkSpeed')
        return active
    for index,(name,target,drive,gait) in enumerate(PHASES):
        end=PHASES[index+1][1] if index+1<len(PHASES) else DURATION
        window=(target+500,end-100)
        injured=name not in ('injury-healthy','injury-heal','injury-stop')
        phase={'phase':name,'requestedGait':gait,'roles':{}}
        chosen=coverage(inputs,'wall',epoch,window,name+'/input')
        require(all(r.get('phase')==name and r.get('drive')==drive and r.get('gait')==gait for r in chosen),name+': input phase differs')
        for role,rows in states.items():
            # WalkInjury rides ordinary movement packets: native has a200ms
            # send gate and600ms reliable timer, without a scalar-change trigger.
            # Keep raw onset/latency below; sample settled observer gait after1s.
            settle=1000 if role=='client2' and name in ('injury-apply','injury-heal') else 500
            # The passive server has no animation transition to settle. Its
            # unchanged wound/identity can use the whole non-mutation phase.
            if role=='server' and name in ('injury-left','injury-right','injury-run','injury-sprint','injury-moving'):
                settle=0
            role_window=(target+settle,end-100)
            selected=coverage(rows,'wall',epoch,role_window,name+'/'+role+'/state')
            if role in ('client1','server'):
                key=side+('Scratch' if severity=='mild' else 'Fracture')
                other='right' if side=='left' else 'left'
                require(all((r[key]>(5 if severity=='mild' else 20) and r[other+'Scratch']==0 and r[other+'Fracture']==0)
                            if injured else all(r[k]<=.01 for k in FOOT) for r in selected),name+'/'+role+': real owner BodyDamage differs')
            if role!='server':
                for row in selected: track_check(row,injured,drive!=0,gait,name+'/'+role)
                require(all(r['motion'] and r.get('visualEnabled') is True for r in selected),name+'/'+role+': cart animation stopped')
                if role=='client1': require(all(r['enabled'] for r in selected),name+': owner steering disabled')
                if injured and drive and not all(r['sprint'] for r in selected):
                    progress=[]
                    for row in selected:
                        tracks=row.get('trackProgress')
                        require(isinstance(tracks,list) and tracks,name+'/'+role+': missing native track clock')
                        require(all(isinstance(t,dict) and isinstance(t.get('name'),str)
                                    and all(common['number'](t.get(k)) for k in ('time','duration','weight'))
                                    and t['duration']>=0 and -.001<=t['time']<=t['duration']+.001 for t in tracks),
                                name+'/'+role+': invalid native track clock')
                        progress.append({t['name']:t for t in tracks if 'Limp' in t['name'] and t['weight']>1e-4 and t['duration']>0})
                    require(any(0.001<(b[key]['time']-a[key]['time'])%a[key]['duration']<a[key]['duration']*.75
                                for a,b in zip(progress,progress[1:]) for key in a.keys()&b.keys()),
                            name+'/'+role+': native limp track remained frozen')
            distance=sum(math.hypot(b['x']-a['x'],b['y']-a['y']) for a,b in zip(selected,selected[1:]))
            yaw=sum(math.atan2(math.sin(b['heading']-a['heading']),math.cos(b['heading']-a['heading'])) for a,b in zip(selected,selected[1:]))
            # The server repeats native movement-packet snapshots between updates;
            # a short turn can fit entirely between two packets. Both clients
            # simulate continuously and must show real per-phase movement/yaw.
            if drive and role!='server': require(distance>.03,name+'/'+role+': cart did not move')
            if role!='server' and name in ('injury-left','injury-right','injury-run','injury-sprint'):
                require(yaw<-.015 if drive==5 else yaw>.015,name+'/'+role+': injured steering did not turn expected way')
            if not drive:
                tail=[r for r in selected if r['wall']>=epoch+end-900]
                require(len(tail)>=3 and all(not r['run'] and not r['sprint'] for r in tail)
                        and math.hypot(tail[-1]['x']-tail[0]['x'],tail[-1]['y']-tail[0]['y'])<=.025,
                        role+': injured/healed cart did not settle')
            phase['roles'][role]={'samples':len(selected),'distance':distance,'yaw':yaw,
                                  'actualRun':any(r['run'] for r in selected),'actualSprint':any(r['sprint'] for r in selected)}
            if role!='server':
                frames=coverage(poses[role],'wallTimeMillis',epoch,role_window,name+'/'+role+'/render')
                require(all(r['id']==identity and r['primary']==r['secondary']==cart
                            and r['local'] is (role=='client1') and r.get('model')==common['FILLED_MODELS'][base_report['cartVariant']]
                            for r in frames),name+'/'+role+': rendered injury owner/cart differs')
                for row in frames:
                    # Render probes retain the exact native tracks plus matrices in the same row.
                    nearest=min(selected,key=lambda r:abs(r['wall']-row['wallTimeMillis']))
                    require(abs(nearest['wall']-row['wallTimeMillis'])<=350,name+'/'+role+': render lacks nearby native gait')
                    track_check(dict(row,run=nearest['run'],sprint=nearest['sprint']),injured,drive!=0,gait,name+'/'+role+'/render')
                phase['roles'][role]['renderFrames']=len(frames)
        summaries.append(phase)
    server_progress=coverage(states['server'],'wall',epoch,(26500,DURATION-500),'injury/server/progress')
    require(sum(math.hypot(b['x']-a['x'],b['y']-a['y']) for a,b in zip(server_progress,server_progress[1:]))>.5,
            'Authoritative injury bank movement was not received')
    final={role:coverage(rows,'wall',epoch,(DURATION-1200,DURATION-100),'injury/'+role+'/final')[-1]
           for role,rows in states.items()}
    require(all(math.hypot(row['x']-final['client1']['x'],row['y']-final['client1']['y'])<=.25
                for row in final.values()),'Injury stop positions did not reconcile with owner')
    transitions={}
    for name in ('injury-apply','injury-heal'):
        event=next(r for r in events if r['phase']==name)
        candidates=[r for r in states['client2'] if r['wall']>=event['wall'] and r['wall']<event['wall']+2000]
        matches=[r for r in candidates if (abs(r['walkInjury'])>.15 if name=='injury-apply' else abs(r['walkInjury'])<=.01)]
        require(matches and matches[0]['wall']-event['wall']<=1100,name+': native observer injury relay exceeded1100ms')
        transitions[name]={'firstObservedNativeScalarMs':matches[0]['wall']-event['wall'],'observerSettleMs':1000}
        event=next(r for r in events if r['phase']==name);t=event['elapsed']
        rows=coverage(states['client1'],'wall',epoch,(t-900,t-100),name+'/before')
        after=coverage(states['client1'],'wall',epoch,(t+100,t+900),name+'/after')
        require(all(r['stepY']>.01 for r in rows+after)
                and math.hypot(rows[-1]['x']-rows[0]['x'],rows[-1]['y']-rows[0]['y'])>.01
                and math.hypot(after[-1]['x']-after[0]['x'],after[-1]['y']-after[0]['y'])>.01
                and math.hypot(after[0]['x']-rows[-1]['x'],after[0]['y']-rows[-1]['y'])<.75,
                name+': mutation was not continuous forward walking')
    return dict(injuryVerified=True,side=side,severity=severity,phases=summaries,nativeWalkSource=source,
                serverAuthorityVerified=True,nativeDamageSnapshots=len(authority),
                ownerBodyDamageVerified=True,observerNativeLimpVerified=True,renderCoverageVerified=True,nativeObserverTransitions=transitions,
                geometryVerified=False,animationEquivalencePass=False,
                scope='Real server-authoritative owner BodyDamage and native damage snapshots, owner/observer injury tracks and actual cart/bone render coverage; geometry and videos need review')
