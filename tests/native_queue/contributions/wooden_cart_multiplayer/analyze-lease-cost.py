"""Exact delivered native command serialization; excludes RakNet/IP/UDP and retransmits."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import runpy

LIFE=runpy.run_path(str(Path(__file__).with_name('analyze-lease-lifetimes.py')))
require,parse,integer,text=(LIFE['HELD'][name] for name in ('require','parse','integer','text'))
ROLES=LIFE['ROLES']; MAX=9007199254740991
NATIVE='[CART_LEASE_BYTES] '
INBOUND={
 'CartLeaseProbe':{'server':{'bind':'Bind','echo':'Echo'},'client':{'bound':'Bound','receipt':'Receipt'}},
 'CartLeaseLifetimes':{'server':{'ready':'Ready','bind':'Bind','echo':'Echo','prepare':'Prepare','done':'Done','finished':'Finished'},
  'client':{'begin':'Begin','cycle':'Cycle','bound':'Bound','reply-refused':'Bound','receipt':'Receipt','complete-offer':'Complete'}}}
MARKERS={'[CART_LEASE] ':'CartLeaseProbe',LIFE['MARKER']:'CartLeaseLifetimes'}

def stats(rows):
    sizes=[r['engineBytes'] for r in rows]
    return dict(messages=len(rows),payloadBytes=sum(r['payloadBytes'] for r in rows),engineBytes=sum(sizes),minimumEngineBytes=min(sizes),maximumEngineBytes=max(sizes))

def burst(rows):
    """A sliding one-second window in one process' own native monotonic clock."""
    begin=0; size=0; peak=0; count=0
    for end,row in enumerate(rows):
        size+=row['engineBytes']
        while row['monoNs']-rows[begin]['monoNs']>=1000000000:
            size-=rows[begin]['engineBytes'];begin+=1
        peak=max(peak,size);count=max(count,end-begin+1)
    return dict(windowMs=1000,maximumMessages=count,maximumEngineBytes=peak)

def analyze(root):
    root=Path(root); life=LIFE['analyze'](root)
    logs={role:(root/(role+'-launch.log')).read_text() for role in ROLES}
    native={}; all_rows=[]; grouped=defaultdict(list); bursts={}; peer_epochs={}
    for role in ROLES:
        rows=LIFE['records'](logs[role],NATIVE,1024)
        require(rows,role+': native serialized command receipts missing')
        process=LIFE['token'](next(c['before'] for c in life['cycles'] if c['actor']==role))[0]
        prior=-9223372036854775808; generations=set(); native[role]={}
        for line,row in rows:
            require(row.get('event')!='error','Native serialized cost error')
            require(text(row,'process',120)==process,'Native cost process differs from native equipment')
            receipt=text(row,'receipt',160); generation=integer(row,'ingressGeneration',1,MAX)
            epoch=integer(row,'connectionEpoch',1,MAX); mono=integer(row,'monoNs',-9223372036854775808,9223372036854775807)
            require(mono>=prior,'Native command cost clock regressed');prior=mono
            require(generation not in generations and receipt not in native[role],'Native receipt generation reused');generations.add(generation)
            module=text(row,'module',80); command=text(row,'command',40)
            direction='client-to-server' if role=='server' else 'server-to-client'
            require(row.get('direction')==direction and module in INBOUND and command in INBOUND[module]['server' if role=='server' else 'client'].values(),'Foreign native cost direction/module/command')
            payload=integer(row,'payloadBytes',1,1048576)
            require(integer(row,'engineBytes',4,1048579)==payload+3,'Engine header must be exactly3bytes; not UDP framing')
            native[role][receipt]=(line,row);all_rows.append(row);grouped[direction,module,command].append(row)
        bursts[role]=burst([row for _,row in rows])
        seen=set()
        for marker,module in MARKERS.items():
            for line,row in LIFE['records'](logs[role],marker,256):
                command=INBOUND[module]['server' if role=='server' else 'client'].get(row.get('event'))
                if not command:continue
                receipt=text(row,'receipt',160)
                require(receipt in native[role] and receipt not in seen,'Missing/duplicate original native command receipt')
                native_line,original=native[role][receipt]
                require(native_line<line and original['module']==module and original['command']==command,'Native receipt is not exact callback command')
                requester=row.get('requester') if role=='server' else role
                require(requester in ('client1','client2'),'Exact cost requester missing')
                key=(role,requester);epoch=original['connectionEpoch']
                require(key not in peer_epochs or peer_epochs[key]==epoch,'Cost requester native connection changed');peer_epochs[key]=epoch
                if role=='server' and requester=='client1':
                    source=LIFE['token'](next(c['before'] for c in life['cycles'] if c['actor']=='server'))
                    require(epoch==source[2],'Server owner cost connection differs from equipment authority')
                if role!='server':
                    source=LIFE['token'](next(c['before'] for c in life['cycles'] if c['actor']==role))
                    require(epoch==source[2],'Client cost connection differs from equipment authority')
                seen.add(receipt)
        require(seen==set(native[role]),'Unmatched extra native command cost receipt')
    require(peer_epochs['server','client1']!=peer_epochs['server','client2'],'Independent guest and owner cost connections alias')
    expected=life['logicalCommandMessages']['includingHeldControl']
    require(len(all_rows)==expected,'Native serialized command count differs from guarded chains')
    commands=[dict(direction=d,module=m,command=c,**stats(rows)) for (d,m,c),rows in sorted(grouped.items())]
    return dict(schema=1,diagnosticOnly=True,evidenceComplete=True,scope='Delivered application payload plus3byte engine header; excludes RakNet/IP/UDP, lost sends and retransmission wire bytes',
                totals=stats(all_rows),directions={d:stats([r for r in all_rows if r['direction']==d]) for d in ('client-to-server','server-to-client')},
                commands=commands,perProcessOneSecondBursts=bursts,
                equipmentFixtureLogicalMessages=life['logicalCommandMessages'],
                qualification='Verbose diagnostic bind/echo tables are measured directly, not a compact production codec or production send-rate budget. Bursts use one native process clock at a time. No animation equivalence or full lifecycle PASS.')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--profile',type=Path,required=True)
    print(json.dumps(analyze(p.parse_args().profile),indent=2))
