"""Exact disposable guest death/Coop respawn/menu rejoin evidence, not animation equivalence."""
import argparse
import json
from pathlib import Path
import runpy

L=runpy.run_path(str(Path(__file__).with_name('analyze-lease-lifetimes.py')))
require,parse,integer,text=(L['HELD'][k] for k in ('require','parse','integer','text'))
token,records=L['token'],L['records']
ROLES=('server','client1','client2');CLIENTS=ROLES[1:]
MARKER='[CART_LIFECYCLE] ';NATIVE='[CART_EQUIPMENT] ';MAX=9007199254740991
EVENTS=set('setup phase-setup cart-setup binding-wait native-equip native-eligibility native-binding request bind-wait stale-control rejoin-ui bind bound echo receipt receipt-resnapshot prepare prepared transition-start native-kill native-death native-death-progress native-player-death unavailable unavailable-replay native-removed cart-disposition observer-absent respawn-offer respawn-ui native-create native-connection transition resnapshot reply-refused native-exit native-reconnect native-rejoin fresh-nonce-replay fresh-replay done complete-offer final-ack complete'.split())


def identity(row):
    return (text(row,'session',120),integer(row,'grant',1,2147483647),integer(row,'lease',1,2147483647),integer(row,'cart',-2147483648,2147483647))


def analyze(root):
    root=Path(root);selection=parse((root/'selection.json').read_text());options=selection.get('options',{})
    require(selection.get('suite')=='wooden_cart_multiplayer' and selection.get('kind')=='mp' and selection.get('mode')=='toolkit'
            and selection.get('cases')==['lease_lifecycle'] and options.get('mp_host') is True,'Frozen isolated menu Host lifecycle selection required')
    require(all(options.get(k,False) is False for k in ('cart_timeline','cart_time_alignment','cart_fast_motion','cart_actions','cart_hotkey_setdown',
            'cart_lease_control','cart_lease_lifetimes','cart_action_admission','cart_observer_association','cart_inventory_equip'))
            and 'cart_wall_exit' not in options and options.get('cart_variant','wooden-wheelbarrow')=='wooden-wheelbarrow','Mixed lifecycle banks')
    logs={r:(root/(r+'-launch.log')).read_text() for r in ROLES}
    require(all(len(log)<=32*1024*1024 for log in logs.values()),'Capture log size limit exceeded')
    rows={};native={}
    for role,log in logs.items():
        # Text completion markers are intentionally outside the structured JSON stream.
        stream='\n'.join(s for s in log.splitlines() if MARKER+'COMPLETE ' not in s)
        rows[role]=records(stream,MARKER,1024);native[role]=records(log,NATIVE,8192)
        require(rows[role] and native[role],role+': missing fixture/native evidence')
        prior=0;clocks={}
        for line,row in rows[role]:
            require(row.get('actor')==role and row.get('event') in EVENTS,'Foreign/error lifecycle record')
            phase=integer(row,'phase',0,3);wall=integer(row,'wall',1,MAX)
            require(wall>=prior,'Lifecycle clock regressed');prior=wall
        for _,row in native[role]:
            require(row.get('event')!='error' and row.get('poisoned') is False
                    and (row.get('success') is True or row.get('event')=='resnapshot' and row.get('success') is False and row.get('certified') is False),'Native equipment error/poison')
            process=text(row,'process',120);mono=integer(row,'monoNs',-9223372036854775808,9223372036854775807)
            require(process not in clocks or mono>=clocks[process],'Native clock regressed');clocks[process]=mono
        complete=[r for _,r in rows[role] if r['event']=='complete']
        require(len(complete)==1 and complete[0].get('phase')==3 and complete[0].get('ok') is True,'Premature/duplicate lifecycle completion')
        require('[CART_LIFECYCLE] COMPLETE actor='+role in log,'Missing role completion marker')
    def get(role,event,phase=None):
        return [(n,r) for n,r in rows[role] if r['event']==event and (phase is None or r['phase']==phase)]
    def one(role,event,phase=None):
        result=get(role,event,phase);require(len(result)==1,f'{role}: expected one {event} phase={phase}');return result[0]
    def exact(role,event,phase,**fields):
        result=[(n,r) for n,r in get(role,event,phase) if all(r.get(k)==v for k,v in fields.items())]
        require(len(result)==1,f'{role}: missing/duplicate {event} phase={phase} {fields}');return result[0]
    def native_binding(role,lifetime,owner,cart,cutoff):
        proc,actor,conn,revision=token(lifetime)
        actor_rows=[(n,r) for n,r in native[role] if r.get('process')==proc and r.get('actorEpoch')==actor]
        match=[(n,r) for n,r in actor_rows if n<cutoff and r.get('revision')==revision and r.get('ownerID')==owner
               and r.get('connectionEpoch')==conn and r.get('primaryID')==r.get('secondaryID')==cart
               and r.get('primaryEpoch')==r.get('secondaryEpoch') and r.get('primaryEpoch',0)>0
               and r.get('depth')==0 and r.get('success') is True and r.get('retired') is False and r.get('event') in ('baseline','mutation-exit','resnapshot')]
        require(match,role+': token not backed by exact native held state')
        # Reuse the complete setter/parse replay, filtering only other actor incarnations.
        filtered='\n'.join(line if NATIVE not in line or parse(line.split(NATIVE,1)[1]).get('process')==proc
                         and parse(line.split(NATIVE,1)[1]).get('actorEpoch')==actor else '' for line in logs[role].splitlines())
        _,snapshots,_=L['native_trace'](filtered,(proc,actor,conn,revision),owner,cart,cutoff-1)
        require(revision in snapshots and max(snapshots)==revision,'Native token is not the current complete mutation/parse state')
        require(not any(n<cutoff and r.get('event')=='retire' for n,r in actor_rows),'Retired native actor readmitted')
        require(all(r.get('connectionEpoch')==conn and r.get('ownerID')==owner for _,r in actor_rows if r.get('event')=='retire'),'Native tombstone targets wrong connection/actor ID')
        return (proc,actor,conn,revision),actor_rows
    phase_data=[];tokens={r:[] for r in ROLES};sources={};completed_chains=0;prepared={}
    for phase in (1,2,3):
        _,spec=one('server','cart-setup',phase)
        owner=integer(spec,'ownerID',0,32767);cart=integer(spec,'cart',-2147483648,2147483647);cargo=integer(spec,'cargoID',-2147483648,2147483647)
        require(spec.get('cargoWeight')==30 and spec.get('sameCartPreservationClaim') is False,'Invalid native fixture cart scope')
        phase_data.append(dict(phase=phase,ownerID=owner,cart=cart,cargoID=cargo,reusedNativeCart=spec.get('reusedNativeCart')))
        serverbinds=get('server','bind',phase);require(serverbinds,'Missing server native admission')
        line,serverbind=serverbinds[0]
        t,scope=native_binding('server',text(serverbind,'lifetime',160),owner,cart,line);tokens['server'].append(t);sources['server',phase]=scope
        for role in CLIENTS:
            _,setup=one(role,'phase-setup',phase)
            require(all(setup.get(k)==spec.get(k) for k in ('ownerID','cart','cargoID')),'Client native setup differs')
            line,b=one(role,'native-binding',phase)
            require(b.get('ownerID')==owner and b.get('cart')==cart and b.get('cargoID')==cargo and b.get('cargoWeight')==30
                    and b.get('localOwner')==(role=='client2'),'Native client cart/cargo binding differs')
            t,scope=native_binding(role,text(b,'lifetime',160),owner,cart,line);tokens[role].append(t);sources[role,phase]=scope
            requests=get(role,'request',phase);require(0<len(requests)<=12,'Missing/unbounded lifecycle challenges')
            successful=[];nonces=set()
            for number,(request_line,request) in enumerate(requests,1):
                attempt=integer(request,'attempt',1,12);require(attempt==number,'Reused/reordered challenge attempt')
                nonce=text(request,'nonce',200);require(nonce not in nonces,'Repeated challenge nonce');nonces.add(nonce)
                wait=[r for _,r in get(role,'bind-wait',phase) if r.get('attempt')==attempt]
                if wait:
                    require(len(wait)==1 and wait[0].get('serverEquipmentPending') is True,'Invalid native pending bind')
                    require(not any(r.get('attempt')==attempt for _,r in get('server','bind',phase) if r.get('requester')==role),'Pending bind also granted')
                    continue
                bind_line,bind=exact('server','bind',phase,requester=role,attempt=attempt)
                require(bind.get('guarded') is True and bind.get('nonce')==nonce and bind.get('ownerID')==owner and bind.get('cart')==cart,'Guarded bind differs from challenge')
                identity(bind);native_binding('server',text(bind,'lifetime',160),owner,cart,bind_line)
                bound=[(n,r) for n,r in get(role,'bound',phase) if r.get('attempt')==attempt]
                refused=[(n,r) for n,r in get(role,'reply-refused',phase) if r.get('attempt')==attempt]
                require(len(bound)+len(refused)==1,'Challenge must settle once')
                if refused:
                    require(refused[0][1].get('accepted') is False and refused[0][1].get('before')!=refused[0][1].get('after'),'Unexplained grant refusal')
                    continue
                bound_line,bound=bound[0];echo_line,echo=exact('server','echo',phase,requester=role,attempt=attempt)
                settled=[(n,r) for event in ('receipt','receipt-resnapshot') for n,r in get(role,event,phase) if r.get('attempt')==attempt]
                require(len(settled)==1,'Echo must settle exactly once')
                receipt_line,receipt=settled[0]
                require(request_line<bound_line<receipt_line and bind_line<echo_line,'Reordered guarded chain')
                require(all(identity(r)==identity(bind) and r.get('nonce')==nonce and r.get('ownerID')==owner and r.get('guarded') is True for r in (bound,echo,receipt)),'Fresh guarded chain differs')
                require(echo.get('accepted') is (role=='client2') and receipt.get('accepted') is (role=='client2'),'Native owner/observer authority differs')
                require(integer(bound,'seq',1,2147483647)==echo.get('seq')==receipt.get('seq'),'Echo sequence changed')
                native_binding(role,text(bound,'lifetime',160),owner,cart,bound_line)
                if receipt['event']=='receipt-resnapshot':
                    before=token(text(receipt,'before',160));after=token(text(receipt,'after',160))
                    require(receipt.get('before')==bound.get('lifetime') and receipt.get('lifetime')==receipt.get('after')
                            and before[:3]==after[:3] and after[3]>before[3] and receipt.get('nativeCertified') is True
                            and receipt.get('freshNativeProof') is False,'Old echo became fresh native proof')
                    _,trace=native_binding(role,receipt['after'],owner,cart,receipt_line)
                    revision=before[3]
                    while revision<after[3]:
                        certificate=[r for n,r in trace if n<receipt_line and r.get('event')=='resnapshot' and r.get('certified') is True and r.get('beforeRevision')==revision]
                        require(len(certificate)==1,'Receipt retry lacks exact whole-parse certificate')
                        revision=integer(certificate[0],'afterRevision',revision+1,after[3])
                    continue
                require(receipt.get('lifetime')==bound.get('lifetime'),'Receipt settled for another native lifetime')
                native_binding(role,text(receipt,'lifetime',160),owner,cart,receipt_line)
                successful.append((attempt,nonce,identity(bind)));completed_chains+=1
            require(successful,'No settled native chain')
            if phase<3:
                _,pending=one(role,'prepare',phase);_,saved=exact('server','prepared',phase,requester=role)
                require(saved.get('guarded') is True and saved.get('nonce')==pending.get('nonce') and saved.get('nonce') not in nonces
                        and saved.get('attempt')==pending.get('attempt')==successful[-1][0] and identity(saved)==successful[-1][2],'Prepared stale reply lacks exact native origin')
                prepared[role,phase]=saved
            else:one(role,'done',phase)
            if phase>1:
                for _,replay in get(role,'fresh-nonce-replay',phase):
                    stale=prepared[role,phase-1]
                    require(replay.get('guarded') is True and replay.get('staleReplyAccepted') is False and replay.get('stalePayloadAccepted') is False
                            and identity(replay)==identity(stale) and replay.get('staleNonce')==stale['nonce'] and replay.get('freshNonce') in nonces
                            and replay.get('freshNonce')!=replay['staleNonce'],'Stale reply escaped fresh nonce fence')
                require(get(role,'fresh-nonce-replay',phase),'Missing stale prepared reply test after fresh namespace')
        if phase>1:
            _,connection=one('server','native-connection',phase)
            require(connection.get('guarded') is True and type(connection.get('oldConnectionActive')) is bool
                    and connection['oldConnectionActive']==(phase==2) and connection.get('sameTransport')==(phase==2)
                    and connection.get('oldOwnerID')==phase_data[phase-2]['ownerID'] and connection.get('ownerID')==owner,'Unknown/wrong old native transport activity')
            require(get('server','fresh-replay',phase),'Server stale native-source test missing after fresh bind')
    require(len({ts[0][0] for ts in tokens.values()})==3,'Native role processes alias')
    for role in ROLES:
        t=tokens[role];require(len({x[0] for x in t})==1 and len({x[1] for x in t})==3,'Process changed or native actor reused')
        require(t[0][2]==t[1][2] and (t[1][2]==t[2][2])==(role=='client1'),'Respawn/reconnect used wrong role transport')
        for phase in (1,2):
            transition_line,_=one(role,'transition-start',phase)
            # Server death may replicate before the diagnostic Transition control.
            # Clients already retained the exact old native binding at Prepare.
            start=one(role,'prepare',phase)[0] if role!='server' else transition_line
            removed_line,removed=one(role,'native-removed',phase)
            require(start<removed_line,'Native removal precedes transition')
            require(removed.get('ownerID')==phase_data[phase-1]['ownerID'],'Removed wrong native actor')
            if phase==1:require(removed.get('nativeCorpse') is True and removed.get('nativeRemovalWitness')=='new-native-corpse' and integer(removed,'corpseCount',1,100)>=1,'No native player corpse')
            if role!='server':
                _,change=one(role,'transition',phase+1)
                before,after=token(text(change,'before',160)),token(text(change,'after',160))
                require(before[:3]==tokens[role][phase-1][:3] and after==tokens[role][phase] and change.get('actorChanged') is True
                        and change.get('sameTransport')==(phase==1 or role=='client1'),'Fixture transition differs from native epochs')
            oldscope=sources[role,phase]
            retires=[(n,r) for n,r in oldscope if r.get('event')=='retire']
            require(any(start<n<removed_line and r.get('reason')=='actor-remove' for n,r in retires),'Missing original native actor removal hook')
            if phase==1:
                death_line,death=one(role,'native-death',phase)
                require(start<death_line<removed_line and death.get('nativeLifetimeAbsent') is True and death.get('eventSource')=='OnCharacterDeath','Native death did not revoke before callback')
                require(any(start<n<death_line and r.get('reason')=='actor-death' for n,r in retires),'Missing original death-entry fence')
            if phase==2 and role!='client1':
                require(any(n>start and r.get('reason')=='connection-remove' for n,r in retires),'Missing old native transport removal')
            replays=get(role,'unavailable-replay',phase)
            require(replays or role=='client2' and phase==2,'No stale payload refusal during native absence')
            for _,replay in replays:
                require(replay.get('stalePayloadAccepted') is False,'Stale payload accepted during absence')
                stale=prepared['client2' if role=='server' else role,phase]
                require(identity(replay)==identity(stale),'Absence replay is not the exact prepared lease')
                if role!='server':
                    require(replay.get('staleReplyAccepted') is False,'Stale pending reply accepted during absence')
                    require(replay.get('guarded') is True or role=='client2' and phase==2 and replay.get('nativeMenu') is True and replay.get('nilIngress') is True,'Absence replay lacks exact ingress or actual menu suspension')
                    require(replay.get('nativeLifetimeAbsent') is True or replay.get('authoritativeAbsence') is True and replay.get('guarded') is True,'Unknown local state cannot prove absence without guarded server revocation')
            for _,d in get(role,'cart-disposition',phase):
                require(d.get('sameCartPreservationClaim') is False and d.get('cartLocation') in ('world-item','native-container','unattached','corpse-container'),'Unsupported cart preservation claim')
        if role=='client1':
            require(get(role,'fresh-replay',2) and get(role,'fresh-replay',3),'Host missing retired replay after fresh receipt')
        if role=='client2':require(get(role,'fresh-replay',2),'Guest missing retired replay after respawn receipt')
        for _,r in get(role,'fresh-replay'):
            require(r.get('stalePayloadAccepted') is False and (role=='server' or r.get('staleReplyAccepted') is False),'Retired source revived after rebind')
    for role in CLIENTS:
        setup=one(role,'setup')[1];require(setup.get('nativeMenuHost') is True,'No initial native Host setup')
        _,ack=one(role,'final-ack',3);require(ack.get('guarded') is True,'No final native ingress acknowledgement')
        _,server_ack=exact('server','final-ack',3,requester=role)
        require(server_ack.get('guarded') is True and server_ack.get('lifetime')==ack.get('lifetime'),'Final source acknowledgement lost native ingress/binding')
    guest=get('client2','native-create');require(any(r.get('phase')==1 and r.get('eventSource')=='OnCreatePlayer' and r.get('newNativeActor') is True for _,r in guest),'No actual Coop respawn create event')
    panels={r.get('panel') for _,r in get('client2','respawn-ui',1) if r.get('nativeCallback') is True}
    require({'post-death','profession','character'}<=panels,'Native visible respawn panels not advanced')
    kill=one('client2','native-kill',1)[1];require(kill.get('programmaticNativeKill') is True,'Missing native Kill trigger')
    require(one('client2','native-exit',2)[1].get('nativeExitToMenu') is True,'No native menu exit')
    require(one('client2','native-reconnect',3)[1].get('nativeConnectToServer') is True,'No real menu reconnect')
    require(one('client2','native-rejoin',3)[1].get('nativeConnected') is True,'No native rejoin event')
    require((root/'client2/Lua/cart-lease-lifecycle-rejoin.txt').read_text()=='verified','Rejoin checkpoint incomplete')
    return dict(schema=1,diagnosticOnly=True,evidenceComplete=True,nativeLifecycleVerified=True,animationEquivalencePass=False,
                phases=phase_data,settledNativeChains=completed_chains,nativeEpochs={r:[list(t) for t in ts] for r,ts in tokens.items()},
                scope='Programmatic native Kill, visible Coop respawn, real menu exit/rejoin and exact stale admission; fresh fixture cart may be supplied after transition. No natural-damage, same-cart, wire-cost or animation-equivalence certification.')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--profile',type=Path,required=True)
    print(json.dumps(analyze(p.parse_args().profile),indent=2))
