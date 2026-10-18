from pathlib import Path
from collections import Counter
import bisect,csv,json,re,sys,math,io

import argparse
parser=argparse.ArgumentParser(description="Analyze the existing 16-case WOOD_BANK protocol; never launches a game")
parser.add_argument('--profile',type=Path,required=True,help='Owned capture/profile directory containing console.txt and probe outputs')
parser.add_argument('--log',type=Path,help='Full native stdout; defaults to profile/console.txt')
parser.add_argument('--output',type=Path,required=True,help='Result directory; may already contain the two mesh intersection JSON files')
parser.add_argument('--partial',action='store_true')
parser.add_argument('--stop-timing',action='store_true',help='Cover all three stops in the 16-second timing bank')
parser.add_argument('--vehicles',action='store_true',help='Include the extended full-load vehicle slide and release')
args=parser.parse_args()
end_ms=15800 if args.stop_timing else 11800
def measurement_end(name):
 return 14800 if args.vehicles and '-full-vehicle-' in name and '-slide-' in name else end_ms
ROOT=args.profile
HERE=args.output
HERE.mkdir(parents=True,exist_ok=True)
assert not any((HERE/name).exists() for name in ['native-metrics.json','native-body-cases.jsonl','selected']), 'Preserve existing analysis output first'
log=(args.log if args.log is not None else ROOT/'console.txt').read_text().rsplit('[WOOD_BANK] RUN_STARTED',1)[-1]
complete='[WOOD_BANK] ALL_COMPLETE cases=16' in log
cases={name:int(start) for name,start in re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)',log)}
if args.partial:
 cases={name:int(start) for name,start in re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)',log)}
if not args.partial:
 assert complete and len(cases)==16,(complete,len(cases))
assert len(cases)==16 or args.partial

def stage(elapsed,name=''):
 if args.vehicles:
  extra=measurement_end(name)-11800
  if elapsed<1000:return 'idle'
  if elapsed<8500+extra:return 'vehicle-forward'
  if elapsed<9300+extra:return 'release'
  if elapsed<11000+extra:return 'vehicle-reverse'
  return 'release'
 spec=name.split('-')[2] if name else 'comparison'
 if spec=='direct':
  if elapsed<1000:return 'idle'
  if elapsed<4000:return 'sprint-start'
  if elapsed<6000:return 'turns'
  if elapsed<8000:return 'stop'
  if elapsed<9500:return 'walk-return'
  if elapsed<11000:return 'sprint-restart'
  return 'stop'
 if spec=='gait':
  if elapsed<700:return 'idle'
  if elapsed<1800:return 'walk-straight'
  if elapsed<3200:return 'run-start'
  if elapsed<4500:return 'sprint-start'
  if elapsed<6300:return 'turns'
  if elapsed<8500:return 'sprint-to-run'
  if elapsed<10000:return 'run-to-walk'
  return 'stop'
 if elapsed<700:return 'idle'
 if elapsed<1800:return 'walk-straight'
 if elapsed<3000:return 'gait-straight'
 if elapsed<9000:return 'turns'
 if elapsed<10000:return 'stop'
 if elapsed<11500:return 'walk-return'
 return 'stop'

def read_rows(name):
 for line in (ROOT/name).read_text().splitlines():
  try:yield json.loads(line)
  except json.JSONDecodeError:
   if complete:raise

samples={name:[]for name in cases}
for line in log.splitlines():
 if '[WOOD_BANK_SAMPLE]' not in line:continue
 data=dict(re.findall(r'(case|wall|run|sprint)=([^ ]+)',line))
 if data.get('case') in samples:
  samples[data['case']].append((int(data['wall']),data['run']=='true',data['sprint']=='true'))

def label(name,wall):
 rows=samples[name]
 if not rows:return 'unobserved'
 i=bisect.bisect_right([r[0]for r in rows],wall)-1
 return 'sprint'if rows[max(i,0)][2]else 'run'if rows[max(i,0)][1]else 'walk/idle'

def window(wall):
 for name,start in cases.items():
  if start+800<wall<start+measurement_end(name):return name,start
 return None

def wheel_lowest(row):
 c=row['cart']
 return c[1]*(-6.642862e-6)+c[5]*(-.0041269097)+c[9]*(-.0010569958)+c[13]-.001062454*math.hypot(c[5],c[9])-.00024333253*abs(c[1])

selected=HERE/'selected';selected.mkdir(exist_ok=True)
body=[row for row in read_rows('body-clearance.jsonl')if window(row['wallTimeMillis'])]
assert all(len(row['cart'])==16 and all(math.isfinite(value) for value in row['cart']) for row in body), 'Nonfinite or invalid cart matrix'
(HERE/'native-body-cases.jsonl').write_text(''.join(json.dumps(row)+'\n'for row in body))
grip=[];failures=[]
for row in read_rows('wood-grip-poses.jsonl'):
 match=window(row['wallTimeMillis'])
 if not match:continue
 name,start=match;row.update(case=name,elapsed=row['wallTimeMillis']-start)
 row['stage']=stage(row['elapsed'],name);row['gait']=label(name,row['wallTimeMillis']);grip.append(row)
 if not row['result']:failures.append(row)
(selected/'failed-grip-poses.jsonl').write_text(''.join(json.dumps(row)+'\n'for row in failures))
mesh={}
for kind,file in [('body','hip-triangle-frames.json'),('pants','pants-triangle-frames.json')]:
 if (HERE/file).exists():
  mesh[kind]=json.loads((HERE/file).read_text())
  assert all(all(math.isfinite(row[key]) for key in ['time','L','R']) and row['L']>=0 and row['R']>=0 for row in mesh[kind]), 'Invalid mesh intersection measurement'
summary={'measurementEndAfterCaseMs':end_ms,'complete':complete,'completedScenes':len(re.findall(r'\[WOOD_BANK\] COMPLETE ',log)),'validatedCartCases':len(cases),'cases':[],'gripSamples':len(grip),'gripFailures':len(failures),'meshSamples':len(body)}
for name,start in cases.items():
 g=[r for r in grip if r['case']==name];f=[r for r in g if not r['result']]
 row={'case':name,'measurementEndAfterCaseMs':measurement_end(name),'gripSamples':len(g),'gripFailures':len(f),'failureStages':dict(Counter(r['stage']for r in f)),
      'failureGaits':dict(Counter(r['gait']for r in f)),'failureElapsedRange':([min(r['elapsed']for r in f),max(r['elapsed']for r in f)]if f else [])}
 for kind,rows in mesh.items():
  frames=[r for r in rows if start+800<r['time']<start+measurement_end(name)]
  row[kind]={'samples':len(frames),'shaftIntersections':{s:sum(r[s]>0 for r in frames)for s in 'LR'},
   'intersectionStages':dict(Counter(stage(r['time']-start,name)for r in frames if r['L']or r['R'])),
   'intersectionGaits':dict(Counter(label(name,r['time'])for r in frames if r['L']or r['R']))}
 cart=[r for r in body if start+800<r['wallTimeMillis']<start+measurement_end(name)]
 row['wheelFloorMaxError']=max((abs(wheel_lowest(r)-.008)for r in cart),default=None)
 feet=[r for r in cart if start+2300<r['wallTimeMillis']<start+2900]
 row['steadyFastFootSamples']=len(feet)
 row['steadyFastFootZRange']={side:(max(r['bones'][f'Bip01_{side}_Foot'][14]for r in feet)-min(r['bones'][f'Bip01_{side}_Foot'][14]for r in feet))if feet else None for side in 'LR'}
 summary['cases'].append(row)
if complete:
 assert len(summary['cases'])==16
 assert all(r['gripSamples']>0 for r in summary['cases'])
 assert all(r['wheelFloorMaxError'] is not None for r in summary['cases']), 'Missing body/cart frames in a completed case'
nativeText=(ROOT/'wood-wheel-native.csv').read_text()
if not nativeText.endswith('\n'):nativeText=nativeText.rsplit('\n',1)[0]+'\n'
native=[r for r in csv.DictReader(io.StringIO(nativeText))if r['event']=='grounding']
required=['spineRootOrientationMaxDelta','spineRootDx','spineRootDy','spineRootDz','maxLegMatrixDelta',
          'leftArmLengthBefore','leftArmLengthAfter','rightArmLengthBefore','rightArmLengthAfter','contactLocalY']
assert native and all(math.isfinite(float(row[key])) for row in native for key in required), 'Missing or nonfinite native grounding measurement'
summary.update(nativeFrames=len(native),hipMatrixMaxDelta=max(abs(float(r['spineRootOrientationMaxDelta']))for r in native),
 hipTranslationMaxDelta=max(abs(float(r[k]))for r in native for k in ['spineRootDx','spineRootDy','spineRootDz']),
 legMatrixMaxDelta=max(abs(float(r['maxLegMatrixDelta']))for r in native),
 armLengthMaxDelta=max(abs(float(r[f'{s}ArmLengthBefore'])-float(r[f'{s}ArmLengthAfter']))for r in native for s in ['left','right']))
summary['csvScope']='Includes setup/reset frames; wheel floor gate uses only actual post-render matrices in validated case windows'
summary['csvWheelContactYRange']=[min(float(r['contactLocalY'])for r in native),max(float(r['contactLocalY'])for r in native)]
summary['wheelFloorSource']='Actual post-render body-clearance cart matrices in selected case windows'
summary['wheelContactYRange']=[min((wheel_lowest(r)for r in body),default=None),max((wheel_lowest(r)for r in body),default=None)]
summary['wheelContactMaxFloorError']=max((abs(wheel_lowest(r)-.008)for r in body),default=0)
summary['checks']={'complete':complete,'body':False,'pants':False,'grip':not failures,'hips':summary['hipMatrixMaxDelta']<1e-6 and summary['hipTranslationMaxDelta']<1e-6,
 'legs':summary['legMatrixMaxDelta']==0,'armLinks':summary['armLengthMaxDelta']<1e-5,'wheelFloor':summary['wheelContactMaxFloorError']<1e-5}
summary['steadyFastFootMinimumZRange']=min((value for row in summary['cases']for value in row['steadyFastFootZRange'].values()if value is not None),default=None)
if complete:
 summary['nativeFootMotionNote']='Per-case short-window ranges are descriptive; native leg matrices are checked unchanged and full moving cycles inspected.'
for kind in mesh:
 summary['checks'][kind]=all(r[kind]['samples']>0 and not any(r[kind]['shaftIntersections'].values())for r in summary['cases'])
(HERE/'native-metrics.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))

if not args.partial and not all(summary['checks'].values()):
 raise SystemExit(1)
