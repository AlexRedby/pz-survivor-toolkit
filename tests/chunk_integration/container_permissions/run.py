#!/usr/bin/env python3
"""Guard, snapshot and run an isolated selected-source Kahlua permissions experiment."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import zipfile
from candidate import candidate, PERMISSIONS_SHA256

SOURCE=Path(__file__).resolve().parent
ROOT=SOURCE.parents[2]

def sha(data): return hashlib.sha256(data).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('game','jdk','permissions','output'): p.add_argument('--'+key,type=Path,required=True)
    p.add_argument('--measure',action='store_true')
    p.add_argument('--forks',type=int,default=5)
    p.add_argument('--iterations',type=int,default=20000)
    p.add_argument('--resource-wait',type=int,default=900)
    a=p.parse_args()
    game,jdk,source,out=(getattr(a,key).resolve() for key in ('game','jdk','permissions','output'))
    if out.exists() or out==game or game in out.parents: p.error('Output must be new and outside game')
    if min(a.forks,a.iterations)<1: p.error('Positive forks/iterations required')
    raw=source.read_bytes(); optimized=candidate(raw)
    lua_root=source.parents[2]
    page=(lua_root/'client/BetterContainers/Proximity/Proximity_ISInventoryPage.lua').read_bytes()
    proximity=(lua_root/'client/BetterContainers/Proximity.lua').read_bytes()
    if sha(page)!='c04e7bb999deb12f74dcbe35b78e5c02d10fb0adeaaac41b81ad4ca36908d0dd' or sha(proximity)!='cc4838096861abdf9051dbb666c5155932756c4923532554255c08389ab0074f': p.error('Unsupported selected Proximity sources')
    autolock='local Options = require("BetterContainers/_Options")\nfunction Proximity.DoAutoLock'+proximity.decode().split('function Proximity.DoAutoLock',1)[1].split('function Proximity.OnAutoLockTick()',1)[0]
    out.mkdir(parents=True); (out/'classes').mkdir(); (out/'work').mkdir(); (out/'home').mkdir(); (out/'client1').mkdir()
    (out/'work'/'stdlib.lua').write_bytes((game/'stdlib.lua').read_bytes())
    (out/'inventory-page.lua').write_bytes(page); (out/'autolock.lua').write_text(autolock)
    (out/'stock.lua').write_bytes(raw); (out/'candidate.lua').write_text(optimized)
    for name in ('candidate.py','ContainerPermissionsCheck.java','checks.lua','run.py'):
        (out/name).write_bytes((SOURCE/name).read_bytes())
    native=game/'projectzomboid.jar'
    guards={}
    with zipfile.ZipFile(native) as z:
        for name in ('se/krka/kahlua/vm/KahluaThread.class','se/krka/kahlua/luaj/compiler/LuaCompiler.class','se/krka/kahlua/j2se/J2SEPlatform.class','se/krka/kahlua/j2se/KahluaTableImpl.class'):
            guards[name]=sha(z.read(name))
    cp=os.pathsep.join(map(str,(out/'classes',native)))
    def command(args,log):
        r=subprocess.run(list(map(str,args)),cwd=out/'work',text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
        (out/log).write_text(r.stdout)
        if r.returncode: raise RuntimeError('Failed: '+str(out/log)+'\n'+r.stdout[-3000:])
        return r.stdout
    command([jdk/'bin/javac','--release','25','-cp',native,'-d',out/'classes',out/'ContainerPermissionsCheck.java'],'compile.log')
    receipt={'research_only':True,'permissions_sha256':PERMISSIONS_SHA256,'inventory_page_sha256':sha(page),'proximity_sha256':sha(proximity),'stdlib_lua_sha256':sha((game/'stdlib.lua').read_bytes()),'native_classes':guards,'game_jar_sha256':sha(native.read_bytes()),'sources':{n:sha((out/n).read_bytes()) for n in ('candidate.py','ContainerPermissionsCheck.java','checks.lua','run.py')},'candidate_sha256':sha(optimized.encode()),'platform':sys.platform,'forks':a.forks,'iterations':a.iterations}
    receipt['java_version']=command([jdk/'bin/java','-version'],'java-version.log')
    (out/'input-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    rows=[]; consumed={}
    def invoke(mode,fork,measure):
        args=[jdk/'bin/java','-Xms256m','-Xmx256m','-Xbatch','-Djava.awt.headless=true','-Duser.home='+str(out/'home'),'-cp',cp,'ContainerPermissionsCheck',out/'stock.lua',out/(mode+'.lua'),out/'checks.lua',out/'inventory-page.lua',out/'autolock.lua']
        if measure: args.append(a.iterations)
        log=command(args,str(fork)+'-'+mode+'.log')
        if 'CONTAINER_PERMISSIONS_CHECK_PASS' not in log: raise RuntimeError('Missing check pass')
        for line in log.splitlines():
            if line.startswith('RESULT '):
                _,label,round_,count,wall,cpu,alloc=line.split()
                rows.append(dict(mode=mode,fork=fork,label=label,round=int(round_),iterations=int(count),wall_ns=int(wall),cpu_ns=int(cpu),allocated_bytes=int(alloc)))
            if line.startswith('CONSUMED '):
                _,label,value=line.split()
                if label in consumed and consumed[label]!=value: raise RuntimeError('Consumption mismatch')
                consumed[label]=value
        print('PASS',fork,mode,flush=True)
    for mode in ('stock','candidate'): invoke(mode,'check',False)
    context=nullcontext(None)
    if a.measure:
        sys.path.insert(0,str(ROOT/'tools'))
        from queue_checks import admission
        selection={'kind':'sp','clients':1,'suite':'container-permissions-headless','resources':{'heap_mib':256,'native_mib':256,'cpu_per_instance':1.0,'exclusive':True}}
        runtime={'roles':{'client1':{'cache':str(out/'client1')}}}
        context=admission.acquire(out,selection,runtime,a.resource_wait)
    with context as resource:
        if a.measure:
            (out/'admission.json').write_text(json.dumps(resource,indent=2)+'\n')
            for fork in range(a.forks):
                for mode in (('stock','candidate') if fork%2==0 else ('candidate','stock')): invoke(mode,fork,True)
    summary=[]; paired=[]
    for label in sorted({r['label'] for r in rows}):
        bymode={}
        for mode in ('stock','candidate'):
            medians=[{key:statistics.median(r[key]/r['iterations'] for r in rows if r['label']==label and r['mode']==mode and r['fork']==fork) for key in ('wall_ns','cpu_ns','allocated_bytes')} for fork in range(a.forks)]
            bymode[mode]=medians
            summary.append(dict(label=label,mode=mode,fork_medians=medians,median={key:statistics.median(r[key] for r in medians) for key in medians[0]}))
        paired.append(dict(label=label,deltas=[{key:c[key]-s[key] for key in s} for s,c in zip(bymode['stock'],bymode['candidate'])]))
    (out/'result.json').write_text(json.dumps(dict(receipt=receipt,measurements=rows,summary=summary,paired=paired,consumed=consumed),indent=2)+'\n')
if __name__=='__main__': main()
