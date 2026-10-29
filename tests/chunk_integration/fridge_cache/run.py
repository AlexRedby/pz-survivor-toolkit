#!/usr/bin/env python3
"""Research-only exact-source numeric negative-cache candidate in native game Kahlua."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LIGHT_HASH = '25c9d181b0fa17196aba08bd34c7bcd424630adaa60029d910359e636900cc21'
LOOKUP = '''    local key = x .. "," .. y .. "," .. z
    if noFridge[key] then return end'''
NUMERIC = '''    local plane = noFridge[z]
    local column = plane and plane[x]
    if column and column[y] then return end'''
INSERT = '    if not found then noFridge[key] = true end'
NUMERIC_INSERT = '''    if not found then
        if not plane then plane = {}; noFridge[z] = plane end
        if not column then column = {}; plane[x] = column end
        column[y] = true
    end'''

def sha(data):
    return hashlib.sha256(data).hexdigest()

def run(command, cwd, log):
    result = subprocess.run(list(map(str, command)), cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
    return result.stdout

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('game','jdk','upstream','output'):
        parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--measure',action='store_true')
    parser.add_argument('--forks',type=int,default=5)
    parser.add_argument('--sweeps',type=int,default=100)
    parser.add_argument('--rounds',type=int,default=5)
    parser.add_argument('--warmup',type=int,default=50)
    parser.add_argument('--resource-wait',type=int,default=900)
    args=parser.parse_args()
    if not (1<=args.forks<=10 and 1<=args.sweeps<=500 and 1<=args.rounds<=20
            and 1<=args.warmup<=50 and 0<=args.resource_wait<=900):
        parser.error('out-of-range bounded workload')
    game,jdk,upstream,out=(getattr(args,k).resolve() for k in ('game','jdk','upstream','output'))
    if out.exists() or out==game or game in out.parents or out==upstream or upstream in out.parents:
        parser.error('output must be a new directory outside game/upstream')
    paths={'TOF_Light.lua':'client/TurnOffFridges/TOF_Light.lua',
           'TOF_Client.lua':'client/TurnOffFridges/TOF_Client.lua',
           'TOF_Core.lua':'shared/TurnOffFridges/TOF_Core.lua'}
    inputs={name:(upstream/'common/media/lua'/path).read_bytes() for name,path in paths.items()}
    light=inputs['TOF_Light.lua'].decode()
    if sha(inputs['TOF_Light.lua'])!=LIGHT_HASH or light.count(LOOKUP)!=1 or light.count(INSERT)!=1:
        parser.error('unsupported upstream light source')
    candidate=light.replace(LOOKUP,NUMERIC).replace(INSERT,NUMERIC_INSERT).encode()
    out.mkdir(parents=True)
    for name in ('work','classes','stock','candidate','client1','home'):
        (out/name).mkdir()
    for mode in ('stock','candidate'):
        for name,data in inputs.items():
            (out/mode/name).write_bytes(candidate if mode=='candidate' and name=='TOF_Light.lua' else data)
        (out/mode/'fixture.lua').write_bytes((HERE/'fixture.lua').read_bytes())
    (out/'work/stdlib.lua').write_bytes((game/'stdlib.lua').read_bytes())
    native=game/'projectzomboid.jar'
    with zipfile.ZipFile(native) as archive:
        hashes={name:sha(archive.read(name)) for name in archive.namelist()
                if (name.startswith(('se/krka/kahlua/','org/luaj/kahluafork/')) and name.endswith('.class'))
                or name=='zombie/core/BoxedStaticValues.class'}
    for name in ('run.py','fixture.lua','FridgeCacheCheck.java'):
        (out/name).write_bytes((HERE/name).read_bytes())
    run([jdk/'bin/javac','--release','25','-cp',native,'-d',out/'classes',HERE/'FridgeCacheCheck.java'],
        out/'work',out/'compile.log')
    receipt=dict(research_only=True,stdlib_sha256=sha((game/'stdlib.lua').read_bytes()),upstream={k:sha(v) for k,v in inputs.items()},
                 candidate_sha256=sha(candidate),native_kahlua=hashes,
                 game_jar_sha256=sha(native.read_bytes()),
                 fixtures={n:sha((HERE/n).read_bytes()) for n in ('run.py','fixture.lua','FridgeCacheCheck.java')},
                 java_version=run([jdk/'bin/java','-version'],out/'work',out/'java-version.log').strip(),
                 parameters={k:getattr(args,k) for k in ('measure','forks','sweeps','rounds','warmup')})
    (out/'input-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    rows=[]; vectors=None; consumed=None; overlap=[]
    def invoke(mode,fork,measure):
        nonlocal vectors,consumed
        tag=f'{fork}-{mode}'
        command=[jdk/'bin/java','-Xms256m','-Xmx256m','-Xbatch','-Djava.awt.headless=true',
                 '-Duser.home='+str(out/'home'),
                 '-Xlog:jit+compilation=debug:file='+str(out/(tag+'-jit.log')),
                 '-Xlog:gc,safepoint:file='+str(out/(tag+'-gc.log')),
                 '-cp',os.pathsep.join(map(str,(out/'classes',native))),'FridgeCacheCheck',out/mode]
        if measure: command.extend(map(str,(args.sweeps,args.rounds,args.warmup)))
        log=run(command,out/'work',out/(tag+'.log'))
        got=[v for v in log.splitlines() if v.startswith('VECTOR ')]
        if not got or vectors is not None and vectors!=got: raise RuntimeError('semantic vectors mismatch '+tag)
        vectors=got
        if measure:
            got=[v for v in log.splitlines() if v.startswith('CONSUMED ')]
            if not got or consumed is not None and consumed!=got: raise RuntimeError('consumed work mismatch '+tag)
            consumed=got
            windows=[]
            for line in log.splitlines():
                if line.startswith('WINDOW '):
                    _,label,round_,begin,end=line.split(); windows.append((int(begin),int(end)))
                if line.startswith('MEASURE '):
                    _,label,round_,count,wall,cpu,allocation=line.split()
                    rows.append(dict(mode=mode,fork=fork,label=label,round=int(round_),sweeps=int(count),
                                     wall_ns=int(wall),cpu_ns=int(cpu),allocated_bytes=int(allocation)))
            for line in (out/(tag+'-jit.log')).read_text().splitlines():
                at=re.match(r'\[([0-9.]+)s\]',line)
                if at and ('kahlua.' in line or 'kahluafork.' in line or 'FridgeCacheCheck' in line):
                    if any(begin<=float(at[1])*1000<=end for begin,end in windows): overlap.append(dict(run=tag,line=line))
        print('PASS '+tag,flush=True)
    for mode in ('stock','candidate'): invoke(mode,'check',False)
    context=nullcontext(None)
    if args.measure:
        sys.path.insert(0,str(ROOT/'tools'))
        from queue_checks import admission
        selection={'kind':'sp','clients':1,'suite':'fridge-cache-headless',
                   'resources':{'heap_mib':256,'native_mib':256,'cpu_per_instance':1.0,'exclusive':True}}
        runtime={'roles':{'client1':{'cache':str(out/'client1')}}}
        context=admission.acquire(out,selection,runtime,args.resource_wait)
    with context as resources:
        if args.measure:
            (out/'admission.json').write_text(json.dumps(resources,indent=2)+'\n')
            for fork in range(args.forks):
                for mode in (('stock','candidate') if fork%2==0 else ('candidate','stock')): invoke(mode,fork,True)
    summary=[]
    for label in sorted({r['label'] for r in rows}):
        medians={}
        for mode in ('stock','candidate'):
            medians[mode]=[{key:statistics.median(r[key]/r['sweeps'] for r in rows
                           if r['mode']==mode and r['label']==label and r['fork']==fork)
                           for key in ('wall_ns','cpu_ns','allocated_bytes')} for fork in range(args.forks)]
        summary.append(dict(label=label,fork_medians=medians,
            median={mode:{key:statistics.median(r[key] for r in medians[mode])
                          for key in ('wall_ns','cpu_ns','allocated_bytes')} for mode in medians},
            paired_percent={key:[100*(after[key]/before[key]-1) for before,after in zip(medians['stock'],medians['candidate'])]
                            for key in ('wall_ns','cpu_ns','allocated_bytes')}))
    receipt['compiled_lua']={mode:{p.name:sha(p.read_bytes()) for p in (out/mode).glob('*.luac')} for mode in ('stock','candidate')}
    (out/'result.json').write_text(json.dumps(dict(receipt=receipt,vectors=vectors,consumed=consumed,
        measurements=rows,summary=summary,relevant_compilation_in_measurement=overlap),indent=2)+'\n')
    if overlap: raise RuntimeError('relevant compilation in timed windows; results unqualified')
    print('FRIDGE_CACHE_CHECK_PASS '+str(out/'result.json'))

if __name__=='__main__': main()
