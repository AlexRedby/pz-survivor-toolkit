"""Bounded native setter and certified remote Equip resnapshot evidence; no runtime PASS."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import runpy

HELD=runpy.run_path(str(Path(__file__).with_name('analyze-lease.py')))
require,parse,integer,text=(HELD[name] for name in ('require','parse','integer','text'))
ROLES=('server','client1','client2'); CLIENTS=ROLES[1:]
MARKER='[CART_LEASE_LIFETIME] '; NATIVE='[CART_EQUIPMENT] '
MAX=9007199254740991
IDENTITY=('session','grant','lease','cart')
PHASES=('baseline','release-reacquire','same-id-replacement')
CHAIN_EVENTS=('request','bind','bound','echo','receipt','reply-refused')


def token(value):
    require(isinstance(value,str) and len(value)<=160,'Missing native lifetime token')
    match=re.fullmatch(r'1\|([^|\s]{1,120})\|([1-9][0-9]*)\|([1-9][0-9]*)\|([1-9][0-9]*)',value)
    require(match is not None,'Invalid/default native lifetime token')
    process,actor,connection,revision=match.groups(); numbers=tuple(map(int,(actor,connection,revision)))
    require(all(n<=MAX for n in numbers),'Native lifetime token overflow')
    return (process,*numbers)


def records(log,marker,limit):
    result=[]
    for line,value in enumerate(log.splitlines()):
        if marker in value:
            row=parse(value.split(marker,1)[1]); require(isinstance(row,dict),'Expected evidence JSON object')
            result.append((line,row)); require(len(result)<=limit,'Evidence record limit exceeded')
    return result


def identity(row):
    text(row,'session',80)
    integer(row,'grant',1,2147483647); integer(row,'lease',1,2147483647); integer(row,'cart',-2147483648,2147483647)
    return tuple(row[field] for field in IDENTITY)


def native_trace(log,selected,owner,cart,cutoff):
    """Replay exact actor scopes, retaining hard fences and whole-parse certificates."""
    process,actor,connection,_=selected
    target,clocks=[],{}
    for line,row in records(log,NATIVE,8192):
        if line>cutoff: continue
        require(row.get('event')!='error','Native equipment trace error')
        proc=text(row,'process',120); mono=integer(row,'monoNs',-9223372036854775808,9223372036854775807)
        require(proc not in clocks or mono>=clocks[proc],'Native monotonic clock regressed'); clocks[proc]=mono
        if proc==process and row.get('ownerID')==owner:
            require(row.get('actorEpoch')==actor,'Native owner actor incarnation changed')
        if proc==process and row.get('actorEpoch')==actor: target.append((line,row))
    require(target,'Missing exact native lifetime trace')
    stack,snapshots,certificates=[],{},{}
    revision,current,prior_serial,hard,prior_parse,prior_ingress=None,None,0,1,0,0
    for line,row in target:
        require(integer(row,'ownerID',0,32767)==owner,'Native owner changed')
        require(integer(row,'connectionEpoch',1,MAX)==connection,'Native connection changed')
        rev=integer(row,'revision',1,MAX); depth=integer(row,'depth',0,2147483647); serial=integer(row,'mutationSerial',0,MAX)
        hard_now=integer(row,'hardRevision',1,rev)
        require(hard_now>=hard,'Native hard revision regressed'); hard=hard_now
        parse_serial=integer(row,'parseSerial',0,MAX); ingress=integer(row,'ingressGeneration',0,MAX)
        require((parse_serial==0)==(ingress==0),'Native parse/ingress scope mismatch')
        for key in ('oldPrimaryEpoch','oldSecondaryEpoch','primaryEpoch','secondaryEpoch'): integer(row,key,0,MAX)
        state=tuple(row[key] for key in ('primaryEpoch','secondaryEpoch','primaryID','secondaryID'))
        for epoch,id_ in ((state[0],state[2]),(state[1],state[3])):
            require((epoch==0 and id_ is None) or (epoch>0 and type(id_) is int and -2147483648<=id_<=2147483647),'Native hand epoch/ID mismatch')
        require(row.get('success') is True and row.get('poisoned') is False and row.get('retired') is False,'Failed/poisoned/retired native lifetime cannot heal')
        event,reason=row.get('event'),text(row,'reason',80)
        if event=='baseline':
            require(revision is None and not stack and serial==0 and depth==0 and reason=='admitted-current' and parse_serial==0,'Repeated or invalid native baseline')
            require(rev==hard==1 and state[0]==state[1] and state[0]>0 and state[2]==state[3]==cart,'Invalid native held baseline')
            revision,current=rev,state
        elif event=='mutation-enter':
            require(revision is not None and rev==revision+1 and depth==len(stack)+1,'Native mutation entry revision/depth differs')
            require(serial>prior_serial,'Native mutation serial reused/reordered'); prior_serial=serial
            require(parse_serial>0 or hard==rev,'Generic native mutation did not advance hard fence')
            if not stack: require(state==current,'Unobserved native equipment mutation')
            require((row['oldPrimaryEpoch'],row['oldSecondaryEpoch'])==state[:2],'Native mutation entry old references differ')
            stack.append(row); revision=rev
        elif event=='mutation-exit':
            require(stack and rev==revision and depth==len(stack)-1,'Unpaired native mutation exit')
            entry=stack.pop()
            require(all(row[k]==entry[k] for k in ('mutationSerial','reason','oldPrimaryEpoch','oldSecondaryEpoch','parseSerial','ingressGeneration')),'Native mutation scope mismatch')
            if not stack: current=state
        elif event=='resnapshot':
            require(not stack and depth==serial==0 and revision==rev and state==current,'Incomplete native Equip parse certificate')
            before=integer(row,'beforeRevision',1,rev-1); after=integer(row,'afterRevision',before+1,rev)
            require(after==rev and after==before+2 and hard<=before and row.get('certified') is True
                    and reason=='remote-equip-resnapshot' and parse_serial>prior_parse and ingress>prior_ingress,
                    'Uncertified/reused native Equip resnapshot')
            require(before in snapshots,'Native certificate missing preparse snapshot')
            integer(row,'directCalls',2,2); integer(row,'genericCalls',0,0)
            original=snapshots[before][1]
            require(original[0]==original[1]>0 and original[2]==original[3]==cart
                    and (row['oldPrimaryEpoch'],row['oldSecondaryEpoch'])==original[:2]
                    and state[0]==state[1]>0 and state[0]!=original[0] and state[2]==state[3]==cart,
                    'Native resnapshot is not exact same-ID new-reference Equip')
            window=[r for n,r in target if n<line and before<r.get('revision',0)<=after and r.get('event') in ('mutation-enter','mutation-exit')]
            require(len(window)==4 and [r['event'] for r in window]==['mutation-enter','mutation-exit']*2
                    and [r['reason'] for r in window]==['primary','primary','secondary','secondary']
                    and [r['depth'] for r in window]==[1,0,1,0]
                    and all(r['parseSerial']==parse_serial and r['ingressGeneration']==ingress and r['hardRevision']==hard for r in window),
                    'Native Equip certificate contains generic/nested/unknown mutation')
            primary=window[1]
            require(primary['primaryEpoch']==state[0] and primary['secondaryEpoch']==original[1]
                    and primary['primaryID']==primary['secondaryID']==cart,'Native Equip primary write differs')
            require(before not in certificates,'Overlapping native Equip certificates')
            certificates[before]=(after,line,row); prior_parse,prior_ingress=parse_serial,ingress
        else: raise ValueError('Unknown/retired native event: '+str(event))
        if not stack: snapshots[revision]=(line,current)
    require(not stack,'Unfinished native mutation scope')
    return target,snapshots,certificates


def analyze(root):
    root=Path(root); selection=parse((root/'selection.json').read_text())
    require(isinstance(selection,dict) and isinstance(selection.get('options'),dict)
            and selection['options'].get('cart_lease_lifetimes') is True and selection['options'].get('cart_lease_control') is True,
            'Explicit lifetime and held lease control selection required')
    control=HELD['analyze'](root); require(control.get('evidenceComplete') is True and control.get('roundsPerClient')==3,'Held lease control prerequisite failed')
    owner,cart=control['ownerID'],control['cartID']
    logs={role:(root/(role+'-launch.log')).read_text() for role in ROLES}
    require(all(len(log)<=32*1024*1024 for log in logs.values()),'Capture log size limit exceeded')
    rows,index,positions={},{},{}
    fixed_server=Counter(ready=2,begin=1,cycle=2,prepare=4,stale=4,done=2,**{'complete-offer':1,'finished':2,'complete':1})
    fixed_client=Counter(ready=1,begin=1,cycle=2,prepare=2,done=1,**{'complete-offer':1,'complete':1})
    for role in ROLES:
        rows[role]=records(logs[role],MARKER,256); counts=Counter()
        wall,phases=-1,[]
        for line,row in rows[role]:
            require(row.get('actor')==role and integer(row,'owner',0,32767)==owner,role+': foreign lifetime owner/actor')
            event=row.get('event'); require(isinstance(event,str) and event!='error',role+': lifetime probe error/unknown event')
            counts[event]+=1
            now=integer(row,'wall',0,MAX); require(now>=wall,role+': lifetime wall clock regressed'); wall=now
            phase=integer(row,'phase',0,3); phases.append(phase)
            require(phase==0 if event=='ready' else phase==3 if event in ('done','complete-offer','finished','complete') else phase>=0 if event=='resnapshot' else phase>=1,role+': invalid event phase')
            requester=row.get('requester') if role=='server' and event in ('ready','bind','echo','prepare','stale','done','finished') else role
            require(requester in CLIENTS or requester=='server','Unknown native requester')
            attempt=integer(row,'attempt',1,8) if event in CHAIN_EVENTS else None
            key=role,phase,requester,event,attempt
            require(key not in index or event=='resnapshot','Duplicate lifetime event')
            if event!='resnapshot': index[key]=row; positions[key]=line
            if event in ('bind','bound','echo','receipt','reply-refused','stale') or role=='server' and event in ('ready','prepare','done','finished'):
                require(row.get('guarded') is True,'Actual native lifetime guard missing')
            if event in ('bind','bound','echo','receipt','reply-refused','stale') or event=='prepare' and role=='server':
                require(identity(row)[3]==cart,'Native lifetime cart differs')
            if event in CHAIN_EVENTS or event=='prepare': text(row,'nonce',120)
            if event in ('ready','request','bound','bind','prepare','finished') or event=='complete' and role!='server': token(row.get('lifetime'))
            if event in ('echo','receipt'):
                require(type(row.get('accepted')) is bool and row['accepted'] is (requester=='client1'),'Exact native source authority differs')
                integer(row,'seq',1,2147483647)
            if event in ('stale','reply-refused'): require(row.get('accepted') is False,'Retired payload/reply was not refused')
        require(phases==sorted(phases),role+': lifetime phase order regressed')
        require(rows[role] and rows[role][-1][1]['event']=='complete',role+': lifetime completion must be final')
        require(rows[role][-1][1]['wall']-rows[role][0][1]['wall']<=20000,'Lifetime fixture deadline exceeded')
        variable=('bind','echo') if role=='server' else ('request','bound','receipt','reply-refused','resnapshot')
        require(Counter({k:v for k,v in counts.items() if k not in variable})==(fixed_server if role=='server' else fixed_client),role+': lifetime event counts differ')
        if role!='server':
            require(3<=counts['request']<=8 and counts['bound']==counts['receipt']>=3 and counts['request']==counts['bound']+counts['reply-refused'] and counts['resnapshot']<=16,'Bounded client resync counts differ')

    def get(role,phase,event,requester=None,attempt=None):
        key=role,phase,requester or role,event,attempt
        require(key in index,'Missing exact lifetime event: '+str(key)); return index[key],positions[key]

    # Match every native mutation to an explicit local cycle or a certified remote parse.
    cycles,gaps,live_tokens=[],[],{}
    processes=set(); cargo_identity=None
    for role in ROLES:
        ready=[row for _,row in rows[role] if row['event']=='ready']; initial=ready[0]['lifetime']; selected=token(initial)
        require(all(row['lifetime']==initial for row in ready),'Server initial native lifetime changed between Ready')
        require(selected[0] not in processes,'Native process identity reused across roles'); processes.add(selected[0])
        _,cutoff=get(role,3,'complete'); trace,snapshots,certificates=native_trace(logs[role],selected,owner,cart,cutoff)
        current=initial; covered=set(); used_certificates=set(); live_tokens[role]={}
        def eligible(value,line):
            tok=token(value); require(tok[:3]==selected[:3] and tok[3] in snapshots,'Unknown/stale native token revision')
            start,state=snapshots[tok[3]]
            require(state[0]==state[1]>0 and state[2]==state[3]==cart,'Native token does not resolve exact held cart')
            next_enter=min((n for n,r in trace if r['event']=='mutation-enter' and r['revision']>tok[3]),default=cutoff+1)
            require(start<line<next_enter,'Lifetime token used outside completed native revision window')
            return tok
        for line,row in rows[role]:
            event,phase=row['event'],row['phase']
            if event in ('cycle','resnapshot'):
                before,after=token(row.get('before')),token(row.get('after'))
                require(row['before']==current and before[:3]==after[:3]==selected[:3] and after[3]>before[3],'Cycle/resnapshot token boundary differs')
                require(integer(row,'cart',-2147483648,2147483647)==cart,'Setter fixture cart changed')
                cid=integer(row,'cargoID',-2147483648,2147483647); weight=row.get('cargoWeight')
                require(type(weight) in (int,float) and 0<weight<=100000,'Invalid fixture cargo weight')
                require(cargo_identity is None or cargo_identity==(cid,weight),'Fixture cargo identity/weight changed'); cargo_identity=(cid,weight)
                eligible(row['after'],line)
                if event=='resnapshot':
                    require(role!='server' and row.get('nativeCertified') is True,'Native resnapshot certificate guard missing')
                    revision=before[3]; certs=[]
                    while revision<after[3]:
                        require(revision in certificates,'Uncertified native equipment gap')
                        end,native_line,certificate=certificates[revision]
                        require(native_line<line and end<=after[3] and revision not in used_certificates,'Unmatched/reused native Equip certificate')
                        used_certificates.add(revision); certs.append(certificate['parseSerial'])
                        covered.update(range(revision+1,end+1)); revision=end
                    require(revision==after[3],'Incomplete native resnapshot interval')
                    gaps.append(dict(actor=role,phase=phase,before=row['before'],after=row['after'],parseSerials=certs))
                else:
                    require(phase in (2,3) and row.get('name')==PHASES[phase-1] and row.get('sameItem') is True,'Setter fixture original cart restoration missing')
                    require(before[3] in snapshots and snapshots[before[3]][1]==snapshots[after[3]][1],'Native setter original references not restored before cycle')
                    window=[(n,r) for n,r in trace if before[3]<r['revision']<=after[3]]
                    require(window and all(r['event'] in ('mutation-enter','mutation-exit') and r['reason'] in ('primary','secondary') and r['parseSerial']==r['ingressGeneration']==0 for _,r in window),'Unknown/interleaving mutation in setter cycle')
                    completed=[r for _,r in window if r['event']=='mutation-exit']; exits=[r for r in completed if r['depth']==0]
                    require(len(completed)>=4 and {r['reason'] for r in completed}=={'primary','secondary'},'Completed native setter writes missing')
                    original=snapshots[before[3]][1]
                    intermediate=[r for r in exits if r['primaryEpoch']==r['secondaryEpoch']==0 and r['primaryID'] is None and r['secondaryID'] is None] if phase==2 else [r for r in exits if r['primaryEpoch']==r['secondaryEpoch']>0 and r['primaryEpoch']!=original[0] and r['primaryID']==r['secondaryID']==cart]
                    require(intermediate,'No completed native both-hands release' if phase==2 else 'No completed same-ID different-reference replacement')
                    require(exits.index(intermediate[0])<len(exits)-1,'Intermediate setter state was not later restored')
                    covered.update(range(before[3]+1,after[3]+1))
                    cycles.append(dict(actor=role,phase=phase,name=row['name'],before=row['before'],after=row['after'],completedSetterWrites=len(completed),nativeLineStart=window[0][0]+1,nativeLineEnd=snapshots[after[3]][0]+1))
                current=row['after']
            if event in ('ready','request','bind','bound','prepare'):
                require(row['lifetime']==current,'Native lifetime evidence skipped local mutation'); eligible(current,line)
            if event=='receipt':
                require(row.get('currentLifetime')==current,'Receipt current native lifetime differs'); eligible(current,line)
            if event=='reply-refused':
                require(row.get('after')==current and row.get('before')!=current,'Unqualified native reply race'); eligible(current,line)
            if event=='complete' and role!='server':
                require(row.get('lifetime')==current,'Completion retained stale native token'); eligible(current,line)
            live_tokens[role][line]=current
        require({r['revision'] for _,r in trace if r['event']=='mutation-enter'}==covered,'Unlinked native mutation before final lifetime completion')
        require(set(certificates)==used_certificates,'Unlinked native Equip certificate')

    chains,refused,nonces=[],[],set()
    successful={}; server_binding={}
    for role in CLIENTS:
        requests=[row for _,row in rows[role] if row['event']=='request']
        require([r['attempt'] for r in requests]==list(range(1,len(requests)+1)),'Fresh lifetime attempts reused/reordered')
        for phase in (1,2,3):
            phase_requests=[r for r in requests if r['phase']==phase]; require(phase_requests,'Missing native lifetime phase bind')
            successful[role,phase]=[]; previous_seq=0
            for request in phase_requests:
                attempt=request['attempt']; nonce=request['nonce']; require(nonce not in nonces,'Fresh/pending lifetime nonce reused'); nonces.add(nonce)
                _,rp=get(role,phase,'request',attempt=attempt); bind,sb=get('server',phase,'bind',role,attempt)
                require(bind['nonce']==nonce,'Fresh server challenge nonce differs'); ident=identity(bind)
                require(ident[1]==1 and ident[2]==phase,'Server grant/lease did not follow exact fixture lifetime')
                if server_binding:
                    require(ident[0]==next(iter(server_binding.values()))[0],'Server session changed during setter fixture')
                require(phase not in server_binding or server_binding[phase]==ident,'Authoritative phase binding differs by requester'); server_binding[phase]=ident
                if phase==1:
                    _,begin=get(role,1,'begin'); _,server_begin=get('server',1,'begin'); require(begin<rp and server_begin<sb,'Lifetime bind preceded fixture begin')
                else:
                    _,cp=get(role,phase,'cycle'); _,sc=get('server',phase,'cycle'); require(cp<rp and sc<sb,'Fresh binding preceded planned native cycle')
                reject_key=(role,phase,role,'reply-refused',attempt)
                if reject_key in index:
                    race,position=get(role,phase,'reply-refused',attempt=attempt)
                    require(rp<position and race['nonce']==nonce and identity(race)==ident and race['before']==request['lifetime'],'Refused native race identity differs')
                    require(any(g['actor']==role and token(g['before'])[3]>=token(request['lifetime'])[3] and token(g['after'])[3]<=token(race['after'])[3] for g in gaps),'Refused reply lacks certified native resnapshot')
                    for event,target in (('bound',role),('receipt',role),('echo','server')):
                        require((target,phase,role,event,attempt) not in index,'Refused native reply also admitted')
                    refused.append(dict(requester=role,phase=phase,attempt=attempt,nonce=nonce)); continue
                bound,bp=get(role,phase,'bound',attempt=attempt); echo,se=get('server',phase,'echo',role,attempt); receipt,ep=get(role,phase,'receipt',attempt=attempt)
                require(rp<bp<ep and sb<se,'Lifetime callback chain reordered')
                require(all(row['nonce']==nonce and identity(row)==ident for row in (bound,echo,receipt)),'Exact lifetime session/binding/nonce chain differs')
                require(bound['lifetime']==receipt['lifetime']==request['lifetime'],'Accepted request crossed native revision')
                require(bound.get('seq')==echo['seq']==receipt['seq']==previous_seq+1,'Same-lease sequence floor reset/skipped'); previous_seq=receipt['seq']
                chain=dict(requester=role,phase=phase,attempt=attempt,nonce=nonce,session=ident[0],grant=ident[1],lease=ident[2],seq=receipt['seq'],accepted=receipt['accepted'],lifetime=request['lifetime'])
                chains.append(chain); successful[role,phase].append((chain,ep))
            require(successful[role,phase],'Phase has no complete exact guarded chain')
            latest,latest_pos=successful[role,phase][-1]
            if phase<3:
                prepared,pp=get(role,phase,'prepare'); sprep,sp=get('server',phase,'prepare',role)
                require(latest_pos<pp and prepared.get('afterAttempt')==sprep.get('afterAttempt')==latest['attempt'],'Pending challenge preparation preceded latest receipt')
                require(prepared['nonce']==sprep['nonce'] and prepared['nonce'] not in nonces and identity(sprep)==server_binding[phase],'Prepared challenge identity differs'); nonces.add(prepared['nonce'])
                require(all(positions[role,phase,role,'request',r['attempt']]<pp for r in phase_requests),'Fresh request after preparation')
            if phase>1:
                cycle,_=get(role,phase,'cycle'); prepared,_=get(role,phase-1,'prepare'); stale,ss=get('server',phase,'stale',role)
                _,first_bind=get('server',phase,'bind',role,phase_requests[0]['attempt'])
                require(ss<first_bind and stale.get('attempt')==phase_requests[0]['attempt'] and identity(stale)==server_binding[phase-1],'Stale server payload identity/order differs')
                require(cycle.get('staleReplyAccepted') is False and cycle.get('stalePayloadAccepted') is False and cycle.get('staleNonce')==prepared['nonce'],'Retired pending reply/payload was not refused')
        done,dp=get(role,3,'done'); offer,op=get(role,3,'complete-offer'); complete,cp=get(role,3,'complete')
        latest,last_pos=successful[role,3][-1]
        require(dp<op<cp and last_pos<cp and complete.get('afterAttempt')==latest['attempt'] and complete['lifetime']==latest['lifetime'],'Final native resync did not settle latest acknowledged token')
        require(requests[-1]['attempt']==latest['attempt'],'Final native request was not completed')
        done_attempt=done.get('afterAttempt'); require(any(c['attempt']==done_attempt and p<dp for c,p in successful[role,3]),'Done preceded exact receipt')
        sd,sdp=get('server',3,'done',role); finished,fp=get('server',3,'finished',role); _,sop=get('server',3,'complete-offer'); _,scp=get('server',3,'complete')
        require(sd.get('afterAttempt')==done_attempt and sdp<sop<fp<scp and finished.get('afterAttempt')==latest['attempt'] and finished['lifetime']==latest['lifetime'],'Server final settlement differs')
    expected_bindings=sum(1 for _,r in rows['server'] if r['event']=='bind')
    expected_echoes=sum(1 for _,r in rows['server'] if r['event']=='echo')
    require(expected_bindings==len(chains)+len(refused) and expected_echoes==len(chains),'Unmatched extra server lifetime attempt')
    require(len(cycles)==6,'Six exact native setter cycles required')
    c2s=expected_bindings+expected_echoes+10; s2c=expected_bindings+expected_echoes+8
    return dict(schema=2,diagnosticOnly=True,evidenceComplete=True,ownerID=owner,cartID=cart,phases=list(PHASES),completeChains=len(chains),completedNativeCycles=6,
                certifiedResnapshots=len(gaps),refusedRacedReplies=len(refused),stalePreparedRepliesRefused=4,staleClientPayloadsRefused=4,staleServerPayloadsRefused=4,
                heldLeaseControl=dict(evidenceComplete=True,roundsPerClient=3,completeChains=control['completeChains']),
                logicalCommandMessages=dict(fixture=c2s+s2c,clientToServer=c2s,serverToClient=s2c,includingHeldControl=c2s+s2c+24,maximumFixture=82),
                chains=chains,refusedReplies=refused,cycles=cycles,resnapshots=gaps,sourceFiles={role:role+'-launch.log' for role in ROLES},
                qualification='Native setter fixture and strictly certified remote Equip resnapshot only, with exact restored original cart/cargo, guarded fresh binds, preserved same-lease sequence floors and stale refusals. No normal menu release, complete reconnect lifecycle, production migration or runtime PASS is established. Logical command counts are not wire bytes or delivery acknowledgements.')


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--profile',required=True,type=Path)
    print(json.dumps(analyze(parser.parse_args().profile),indent=2))


if __name__=='__main__': main()
