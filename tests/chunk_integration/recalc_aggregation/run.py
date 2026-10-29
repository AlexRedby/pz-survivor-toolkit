#!/usr/bin/env python3
"""Reproduce synchronous parity and the shared-input counterexample rejecting aggregation reuse."""
import argparse,hashlib,json,os,subprocess,zipfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
NATIVE={'zombie/iso/IsoGridSquare.class':'e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467','zombie/core/properties/PropertyContainer.class':'bc236f8e9e4e0da8a86b0d1fd19ad8d44a040fe4f67d1baac77401b3b148bd77','zombie/iso/IsoObject.class':'22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2','zombie/iso/sprite/IsoSprite.class':'68c01e6b1c914f662621743e09c8dd8a62c0258392ce1a75654a713e1034067f'}
OFFICIAL={'zombie/iso/IsoGridSquare.class':'557646359c35a309c786c24c7d7fd522d2877f9ad64aea1315a29052d76920a6','zombie/core/properties/PropertyContainer.class':'bdb0ac0f09b7ae3ab9a2b72486e3e5f419cb3e25bc03a4245ba9e6b43d5010bb','zombie/iso/IsoObject.class':'78e9c2248c12bb8d230fa790c4b0cd11539ced3c4542f59901badc8b6297f0a4','zombie/iso/sprite/IsoSprite.class':'b096996bf29387be71f507975437dee8ed75df3ed52871d66db9f7fba09a1871'}
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for n in ('game','jdk','official-overlay','manifest','output'):p.add_argument('--'+n,type=Path,required=True)
 a=p.parse_args();game,jdk,overlay,manifest,out=[getattr(a,n).resolve() for n in ('game','jdk','official_overlay','manifest','output')]
 if out.exists() or out==game or game in out.parents:p.error('Output must be new and outside installed game')
 jar,buddy=game/'projectzomboid.jar',game/'ZombieBuddy.jar'
 with zipfile.ZipFile(jar) as z:
  for n,h in NATIVE.items():
   if sha(z.read(n))!=h:p.error('Native guard mismatch: '+n)
 for n,h in OFFICIAL.items():
  if sha((overlay/n).read_bytes())!=h:p.error('Official guard mismatch: '+n)
 profile=json.loads(manifest.read_text())['profile']['properties']
 for n in ('handoffRecalcFast','handoffRecalcMemo','handoffRecalcParallel'):
  if profile[n]!='false':p.error('Unexpected active profile '+n)
 out.mkdir(parents=True)
 for n in ('source','classes','home','work'): (out/n).mkdir()
 for f in HERE.glob('*.java'):(out/'source'/f.name).write_bytes(f.read_bytes())
 (out/'source'/'run.py').write_bytes(Path(__file__).read_bytes())
 receipt={'candidate_rejected':True,'semantic_only':True,'observer_calls':True,'timing_qualified':False,'runtime_qualified':False,'game_jar_sha256':sha(jar.read_bytes()),'native_guards':NATIVE,'official_guards':OFFICIAL,'manifest_sha256':sha(manifest.read_bytes()),'sources':{f.name:sha(f.read_bytes()) for f in HERE.iterdir() if f.suffix in ('.java','.py')},'runs':{}}
 (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 def run(cmd,label):
  r=subprocess.run(list(map(str,cmd)),cwd=out/'work',text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
  (out/(label+'.log')).write_text(r.stdout)
  if r.returncode:raise RuntimeError(label+' failed: '+r.stdout[-7000:])
  return r.stdout
 receipt['java_version']=run([jdk/'bin/java','-version'],'java-version').strip()
 cp=os.pathsep.join(map(str,(out/'classes',jar,buddy)))
 run([jdk/'bin/javac','--release','25','-cp',cp,'-d',out/'classes',*sorted((out/'source').glob('*.java'))],'compile')
 for mode in ('native','official'):
  source=out/(mode+'-original.class')
  if mode=='native':
   with zipfile.ZipFile(jar) as z:source.write_bytes(z.read('zombie/iso/IsoGridSquare.class'))
  else:source.write_bytes((overlay/'zombie/iso/IsoGridSquare.class').read_bytes())
  gen_cp=os.pathsep.join(map(str,(out/'classes',overlay,jar,buddy)))
  run([jdk/'bin/java','-cp',gen_cp,'AggregationGenerator',source,out/(mode+'-overlay'),'observed'],mode+'-splice')
  parts=[out/(mode+'-overlay'),out/'classes']+([overlay] if mode=='official' else [])+[jar,buddy]
  command=[jdk/'bin/java','-Xms256m','-Xmx256m','-Djava.awt.headless=true','-Duser.home='+str(out/'home'),'-Drecalc.official='+str(mode=='official').lower()]
  if mode=='official':command += ['-Dpzopt.'+k+'='+v for k,v in profile.items()]
  command += ['-cp',os.pathsep.join(map(str,parts)),'NeighborChecks']
  log=run(command,mode+'-checks')
  if 'NEIGHBOR_SEMANTICS_PASS' not in log:raise RuntimeError('No semantic completion '+mode)
  negative=run(command[:-1]+['SharedSourceMutationCheck'],mode+'-shared-source-negative')
  if 'SHARED_SOURCE_MUTATION_COUNTEREXAMPLE' not in negative:raise RuntimeError('Missing rejection proof '+mode)
  plain=out/(mode+'-plain-overlay')
  run([jdk/'bin/java','-cp',gen_cp,'AggregationGenerator',source,plain,'plain'],mode+'-plain-splice')
  equivalent=run([jdk/'bin/java','-cp',cp,'ObserveEquivalence',out/(mode+'-overlay')/'zombie/iso/IsoGridSquare.class',plain/'zombie/iso/IsoGridSquare.class'],mode+'-observer-equivalence')
  if 'OBSERVER_FREE_EQUIVALENCE_PASS methods=2' not in equivalent:raise RuntimeError('Missing observer equivalence '+mode)
  receipt['runs'][mode]={'shared_source_counterexample':True,'observer_free_instruction_equivalence':True,'passed':True,'summary':[l for l in log.splitlines() if l.startswith(('AGGREGATION_','NEIGHBOR_'))], 'patched_sha256':sha((out/(mode+'-overlay')/'zombie/iso/IsoGridSquare.class').read_bytes())}
  (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 prefix=run([jdk/'bin/java','-Xmx256m','-Djava.awt.headless=true','-Duser.home='+str(out/'home'),'-cp',cp,'WindowAliasCheck',jar],'window-alias-prefix')
 if 'WINDOW_NATIVE_PREFIX_ALIAS_CHECK_PASS' not in prefix:raise RuntimeError('Missing native writer proof')
 receipt['native_window_prefix_counterexample']=True
 (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('AGGREGATION_REJECTION_REGRESSION_PASS '+str(out/'receipt.json'))
if __name__=='__main__':main()
