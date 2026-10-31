#!/usr/bin/env python3
"""Strict within-JVM whole-roll receipts. Capture/equivalence is separate from timing qualification."""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import statistics

SOURCE=Path(__file__).resolve().parent
_spec=importlib.util.spec_from_file_location('_operations_base_receipts',SOURCE/'compare.py')
base=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(base)
values=base.values
rng=base.rng
RNG_ACTIVATION=base.RNG_ACTIVATION
CONTRACT={'scope':'owner-window-paired-roll-v1','warmup_pairs':64,'measured_pairs':24,'storage_limit':4096,
 'groups':[{'id':'direct-CrateMetalwork-main','batch':2,'distribution':'CrateMetalwork','path':'public-doRollItem-main-only'},
 {'id':'bag-FirstAidKit-with-native-junk','batch':4,'distribution':'FirstAidKit','path':'public-rollContainerItem-with-junk'}],
 'callback_admission':'itemconfig-null;LuaCreate-empty-or-exact-native-gasmask','semantic_accept_observer':False,'headless_operations_checks':True}
GROUPS={g['id']:g for g in CONTRACT['groups']}
FIELDS='phase group pair order variant batch window_id wall_start wall_end cpu_start cpu_end allocated selections created increments null_returns digest next_rng created_types cold_types cleanup'.split()
EVENT_FIELDS='kind start_ns end_ns thread_id method level compile_id window_id detail'.split()
EVENTS={'jdk.Compilation','jdk.Deoptimization','jdk.GarbageCollection','jdk.GCPhasePause','jdk.SafepointBegin','jdk.DataLoss','pz.loot.RollWindow'}


def limits(bank='operations'):
 return ['whole public roll calls only; direct excludes outer distribution selection and separate junk; bag includes its native junk',
 'shared selector/native RNG/identity observers add overhead; no subtraction or uninstrumented baseline claim',
 'detached public direct roll can emit native ItemPickInfo identity diagnostics; logger cost is included, percentage is not ordinary world-container fill speedup',
 'detached fixture containers and cleanup/GC interactions are not live fillContainer/vehicle/driving work',
 'only the admitted two item/callback graphs; arbitrary callback globals, Java transformations and concurrent script mutation unsupported',
 'owner current-thread CPU excludes background GC/Host CPU; full runtime-log/source audit still required',
 'observed warmup creation types and compilation levels do not prove every lazy path or callback is warmed',
 'no frame/FPS, hitch or production-adoption inference']


def _rows(path,fields):
 with path.open(newline='') as stream:
  reader=csv.DictReader(stream,delimiter='\t')
  if reader.fieldnames!=fields:raise ValueError('Operations receipt header differs: '+path.name)
  result=list(reader)
 if any(None in row or any(v is None for v in row.values()) for row in result):raise ValueError('Operations malformed row')
 return result


def _integer(value,minimum=0):
 if not re.fullmatch(r'0|[1-9][0-9]*',value):raise ValueError('Operations noncanonical integer')
 value=int(value)
 if value<minimum:raise ValueError('Operations integer out of range')
 return value


def _types(value):
 if value=='-':return set()
 names=value.split(',')
 if names!=sorted(set(names)) or any(not re.fullmatch('[A-Za-z0-9_.-]+',n) for n in names):raise ValueError('Operations malformed type coverage')
 return set(names)


def parse_windows(path):
 rows=_rows(path,FIELDS)
 expected=[]
 for phase,count in [('warmup',64),('measure',24)]:
  for pair in range(count):
   for position in range(2):
    index=(position+pair)%2;group=list(GROUPS)[index];first=bool((pair+index)&1);order='BA' if first else 'AB'
    for candidate in (first,not first):expected.append((phase,group,pair,order,'resolved' if candidate else 'native'))
 if len(rows)!=len(expected):raise ValueError('Operations missing/duplicate warmup/measured windows')
 numeric=set(FIELDS)-{'phase','group','order','variant','digest','created_types','cold_types','cleanup'}
 warm=set()
 for index,(row,identity) in enumerate(zip(rows,expected)):
  for key in numeric:row[key]=_integer(row[key])
  if tuple(row[k] for k in ('phase','group','pair','order','variant'))!=identity or row['window_id']!=index or row['batch']!=GROUPS[row['group']]['batch']:
   raise ValueError('Operations order/owner-variant/window identity differs')
  if row['wall_end']<row['wall_start'] or row['cpu_end']<row['cpu_start'] or row['cleanup']!='verified':raise ValueError('Operations clock/cleanup invalid')
  if not re.fullmatch('[0-9a-f]{64}',row['digest']) or not 0<=row['next_rng']<1_000_000 or not 0<row['selections']<1_000_000:
   raise ValueError('Operations identity/RNG/selector proof invalid')
  if not 0<=row['created']<=CONTRACT['storage_limit'] or not 0<=row['increments']<=row['created'] or row['null_returns']!=0:
   raise ValueError('Operations observer bounds/null factory return differ')
  made=_types(row['created_types']);cold=_types(row['cold_types'])
  if bool(made)!=bool(row['created']):raise ValueError('Operations created type/count mismatch')
  if row['phase']=='warmup':
   if cold:raise ValueError('Operations warmup cold label invalid')
   warm.update(made)
  elif cold!=made-warm:raise ValueError('Operations measured cold-type proof differs')
  row['cpu_ns']=row['cpu_end']-row['cpu_start'];row['wall_ns']=row['wall_end']-row['wall_start']
 for first,second in zip(rows[::2],rows[1::2]):
  for key in ('digest','next_rng','selections','created','increments','null_returns','created_types'):
   if first[key]!=second[key]:raise ValueError('Operations paired actual contents/RNG/observer mismatch: '+key)
 for group in GROUPS:
  actual=[r for r in rows if r['group']==group and r['phase']=='measure']
  if not any(r['created']>0 for r in actual):raise ValueError('Operations selected graph never reached successful creation')
 return rows


def parse_events(path,windows,owner):
 events=_rows(path,EVENT_FIELDS);markers={};sentinel=[];jit=[];gc=[];loss=[]
 for event in events:
  if event['kind'] not in EVENTS:raise ValueError('Operations unreviewed JFR event')
  for key in ('start_ns','end_ns','thread_id','level','compile_id'):event[key]=_integer(event[key])
  if event['end_ns']<event['start_ns']:raise ValueError('Operations JFR interval backwards')
  if event['kind']=='pz.loot.RollWindow':
   if event['window_id']=='-2':sentinel.append(event);continue
   index=_integer(event['window_id'])
   if index in markers or index>=len(windows):raise ValueError('Operations duplicate/foreign JFR window')
   row=windows[index]
   expected='group='+row['group']+',variant='+row['variant']+',phase='+row['phase']+',pair='+str(row['pair'])+',batch='+str(row['batch'])
   if event['detail']!=expected or event['thread_id']!=owner:raise ValueError('Operations JFR/CSV owner/window binding differs')
   markers[index]=event
  elif event['window_id']!='-1':raise ValueError('Operations native JFR event mislabeled')
  elif event['kind'] in ('jdk.Compilation','jdk.Deoptimization'):jit.append(event)
  elif event['kind']=='jdk.DataLoss':loss.append(event)
  else:gc.append(event)
 if len(sentinel)!=1 or set(markers)!=set(range(len(windows))) or sentinel[0]['start_ns']>markers[0]['start_ns']:
  raise ValueError('Operations startup/JFR history missing or rotated')
 ordered=[markers[i] for i in range(len(windows))]
 if any(a['end_ns']>b['start_ns'] for a,b in zip(ordered,ordered[1:])):raise ValueError('Operations overlapping/reordered owner windows')
 def overlaps(event,marker):return event['start_ns']<=marker['end_ns'] and event['end_ns']>=marker['start_ns']
 for row in windows:
  marker=markers[row['window_id']]
  row['jit_events']=[event for event in jit if overlaps(event,marker)]
  row['gc_safepoint_events']=[event for event in gc if overlaps(event,marker)]
 first=next(markers[row['window_id']]['start_ns'] for row in windows if row['phase']=='measure')
 compiled=[e for e in jit if e['kind']=='jdk.Compilation' and e['end_ns']<first and e['detail'].startswith('success=true,')]
 prefixes=('zombie.inventory.ItemPickerJava.doRollItemInternal(', 'zombie.inventory.ItemPickerJava.rollContainerItemInternal(', 'toolkit.lootresolved.runtime.OperationsMain.half(')
 entries={prefix:[e for e in compiled if e['method'].startswith(prefix) and e['level']>=1 and e['detail']=='success=true,osr=false'] for prefix in prefixes}
 return dict(sentinel=sentinel[0],data_loss=loss,compiled_before_measure=compiled,compiled_normal_entries=entries,
             note='literal observed successful compilation levels/OSR, not universal C2 entry or lazy-path warmth')


def read(cache,mode='candidate'):
 cache=Path(cache);status=values(cache/'loot-resolved-runtime-status.txt');pid=status.get('pid','')
 required=dict(status='complete',mode='candidate',bank='operations',cases='2',reason='',runtime_profile_checked='true',
               rng_scope=base.RNG_SCOPE,rng_scope_complete='true',operations_scope=CONTRACT['scope'],windows='352')
 if mode!='candidate' or any(status.get(k)!=v for k,v in required.items()) or not pid.isdecimal():raise ValueError('Unqualified operations capture status')
 activation=values(cache/f'loot-resolved-runtime-activation-{pid}.txt')
 expected=dict(state='active',mode='candidate',bank='operations',pid=pid,definitions='1',runtime_profile_checked='true',
               resource_profile=status.get('resource_profile'),optimizer_manifest_sha256=status.get('optimizer_manifest_sha256'),
               operations_factory_definitions='1',operations_spawner_definitions='1',**RNG_ACTIVATION)
 if any(activation.get(k)!=v for k,v in expected.items()):raise ValueError('Operations activation/observed definition mismatch')
 if any(not re.fullmatch('[0-9a-f]{64}',activation.get(k,'')) for k in ('input','output')) or activation['input']==activation['output']:
  raise ValueError('Operations true native input/paired output proof missing')
 if status.get('resource_profile') not in ('native','native-host','optimized-client'):raise ValueError('Operations resource profile absent')
 manifest=status.get('optimizer_manifest_sha256','')
 if (manifest!='none' if status['resource_profile']=='native' else not re.fullmatch('[0-9a-f]{64}',manifest)):
  raise ValueError('Operations manifest profile proof differs')
 rng(cache,pid)
 report(cache)
 return status,activation,(cache/'loot-operations.tsv').read_text().splitlines(keepends=True)


def report(cache):
 cache=Path(cache);inputs=values(cache/'loot-operations-inputs.properties');owner=_integer(inputs.get('owner_thread_id',''),1)
 if inputs.get('callback_admission')!=CONTRACT['callback_admission'] or inputs.get('callback_binding') not in ('none','native:ItemCodeOnCreate.onCreateGasMask(Clothing)'):
  raise ValueError('Operations reviewed callback binding admission missing')
 for group in GROUPS:
  graph=inputs.get(group+'.graph','');digest=inputs.get(group+'.sha256','')
  if not graph or hashlib.sha256(graph.encode()).hexdigest()!=digest:raise ValueError('Operations actual parsed graph digest differs')
 options=inputs.get('ordinary_options','')
 if not options or hashlib.sha256(options.encode()).hexdigest()!=inputs.get('ordinary_options_sha256'):raise ValueError('Operations ordinary option proof missing')
 if any(inputs.get(k)!=v for k,v in {'container_identity':'detached-no-native-world-object-id','native_identity_logger':'unchanged-diagnostics-included-if-emitted','direct_public_calls':'352','bag_public_calls':'704'}.items()):raise ValueError('Operations detached native-identity/logging scope missing')
 empty={key:_integer(inputs.get(key,'')) for key in ('empty1000_cpu_ns','empty1000_wall_ns')}
 windows=parse_windows(cache/'loot-operations.tsv');events=parse_events(cache/'loot-operations-events.tsv',windows,owner)
 measured=[row for row in windows if row['phase']=='measure'];contaminated=[r['window_id'] for r in measured if r['jit_events']]
 cold=[r['window_id'] for r in measured if r['cold_types']!='-'];summary={}
 for group in GROUPS:
  pairs=[]
  for a,b in zip(measured[::2],measured[1::2]):
   if a['group']!=group:continue
   native,resolved=(a,b) if a['variant']=='native' else (b,a)
   pairs.append(dict(pair=a['pair'],order=a['order'],native_cpu_ns_per_roll=native['cpu_ns']/native['batch'],resolved_cpu_ns_per_roll=resolved['cpu_ns']/resolved['batch'],
                     saved_cpu_ns_per_roll=(native['cpu_ns']-resolved['cpu_ns'])/native['batch'],native_wall_ns_per_roll=native['wall_ns']/native['batch'],resolved_wall_ns_per_roll=resolved['wall_ns']/resolved['batch']))
  summary[group]=dict(pairs=pairs,median_saved_cpu_ns_per_roll=statistics.median(p['saved_cpu_ns_per_roll'] for p in pairs),
                      positive_pairs=sum(p['saved_cpu_ns_per_roll']>0 for p in pairs),total_pairs=len(pairs))
 return dict(format=1,scope=CONTRACT['scope'],capture='paired-equivalent',timing_qualified=not(events['data_loss'] or contaminated or cold or any(not v for v in events['compiled_normal_entries'].values())),
             timing_scope='literal observed compiled entry levels; never universal C2 or lazy-path warmth',
             jit_contaminated_windows=contaminated,cold_created_type_windows=cold,events=events,empty_timer_baseline=empty,
             inputs=inputs,summary=summary,windows=windows,limits=limits())


def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--cache',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
 if args.output.exists():parser.error('Comparison output must be new')
 read(args.cache);result=report(args.cache)
 args.output.write_text(json.dumps(result,indent=2)+'\n')
 print('LOOT_OPERATIONS_CAPTURE_PASS timing_qualified='+str(result['timing_qualified']).lower())
 print('Whole rolls only; all raw windows retained; no driving/FPS/adoption claim')

if __name__=='__main__':main()
