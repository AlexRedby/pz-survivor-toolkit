from pathlib import Path
import argparse,csv,json,math,re,statistics
import importlib.util

_clip_spec = importlib.util.spec_from_file_location('cart_native_clip_names', Path(__file__).with_name('clip_names.py'))
_clip_names = importlib.util.module_from_spec(_clip_spec)
_clip_spec.loader.exec_module(_clip_names)
native_clip = _clip_names.native_clip


def temporal_return(frames,start,release,end):
 """Describe sampled wheel pullback after actor translation stops; no calibrated gate."""
 selected=[r for r in frames if start+release<r['wallTimeMillis']<start+end]
 if len(selected)<4:return {'available':False,'reason':'Insufficient native wheel samples'}
 rest=max((i for i in range(1,len(selected)) if
  (selected[i]['playerX'],selected[i]['playerY'])!=(selected[i-1]['playerX'],selected[i-1]['playerY'])),default=0)
 tail=selected[rest:]
 axis=tail[0]['forwardX'],tail[0]['forwardY']
 offsets=[(r['wheelX']-r['playerX'])*axis[0]+(r['wheelY']-r['playerY'])*axis[1]for r in tail]
 peak=max(range(len(tail)),key=offsets.__getitem__)
 returning=tail[peak:];offsets=offsets[peak:]
 pairs=[];skipped=0
 for i,(a,b)in enumerate(zip(returning,returning[1:])):
  dt=b['time']-a['time']
  if dt<=0:skipped+=1;continue
  pairs.append((i,dt,(offsets[i+1]-offsets[i])/dt))
 if len(pairs)<2:return {'available':False,'reason':'Insufficient final-return intervals'}
 fastest=min(pairs,key=lambda p:p[2])
 averages=[];left=segment=0
 for right in range(1,len(returning)):
  if returning[right]['time']<=returning[right-1]['time']:
   left=segment=right;continue
  target=returning[right]['time']-.1
  if target<returning[segment]['time']:continue
  while left+1<right and returning[left+1]['time']<=target:left+=1
  fraction=(target-returning[left]['time'])/(returning[left+1]['time']-returning[left]['time'])
  initial=offsets[left]+fraction*(offsets[left+1]-offsets[left])
  averages.append(max(0,(initial-offsets[right])/.1))
 return {'available':True,'source':'wood-wheel-native.csv grounded wheel relative to player; fixed forward axis',
  'clock':'System.nanoTime time; wallTimeMillis only selects the input window',
  'actorRestAfterReleaseMs':tail[0]['wallTimeMillis']-start-release,
  'returnStartAfterReleaseMs':returning[0]['wallTimeMillis']-start-release,
  'windowEndAfterReleaseMs':returning[-1]['wallTimeMillis']-start-release,
  'samples':len(returning),'intervalMs':{'min':min(p[1]for p in pairs)*1000,
   'median':statistics.median(p[1]for p in pairs)*1000,'max':max(p[1]for p in pairs)*1000},
  'skippedNonIncreasingTimes':skipped,'returnExcursionTiles':max(0,offsets[0]-offsets[-1]),
  'sampledMaxReturnSpeedTilesPerSecond':max(0,max(-p[2]for p in pairs)),
  'sampledMax100msAverageReturnSpeedTilesPerSecond':max(averages,default=None),
  'average100msWindows':len(averages),
  'peakSpeedIntervalMs':fastest[1]*1000,
  'sampledMaxAdjacentSpeedJumpTilesPerSecond':max((abs(b[2]-a[2])for a,b in zip(pairs,pairs[1:])if b[0]==a[0]+1),default=None),
  'limit':'Descriptive finite differences at the reported cadence; short/irregular intervals and discrete pose updates affect peaks. The 100ms mean linearly interpolates the covered window start without extrapolation; null means insufficient coverage. Unresolved inter-sample peaks, no calibrated PASS threshold. Actor rest is the last observed position change, not a physics assertion.'}

parser=argparse.ArgumentParser(description="Check native wooden-cart stop motion; separate pose/geometry evidence required")
parser.add_argument("--profile",type=Path,required=True)
parser.add_argument("--log",type=Path,help="Full native stdout; defaults to profile/native-launch.log")
parser.add_argument("--output",type=Path,required=True)
args=parser.parse_args()
assert args.profile.is_dir()
assert not args.output.exists(), "Refuse to overwrite an existing report"

ROOT=args.profile
wheelFile=ROOT/'wood-wheel-native.csv';wheel=[]
if wheelFile.exists():
 with wheelFile.open()as stream:
  for row in csv.DictReader(stream):
   if row.get('event')!='grounding':continue
   point={k:float(row[k])for k in ['time','wallTimeMillis','wheelX','wheelY','playerX','playerY','forwardX','forwardY']}
   assert all(math.isfinite(v)for v in point.values()),'Nonfinite native wheel measurement'
   wheel.append(point)
log=(args.log if args.log is not None else ROOT/'native-launch.log').read_text().rsplit('[WOOD_BANK] RUN_STARTED',1)[-1]
assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=24(?:\s|$)',log)
assert '[WOOD_BANK] FAIL' not in log
completed=re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)',log)
assert len(completed)==24,'Require exactly one completed recording per case'
starts={n:int(t) for n,t in completed}
steps={
 'run-stop':[(1,2),(0,0),(1,2),(0,2),(0,0),(1,2),(1,0),(0,0)],
 'sprint-stop':[(2,2),(0,0),(2,2),(0,2),(0,0),(2,2),(2,0),(0,0)],
 'short-release':[(2,2),(0,0),(1,2),(0,0),(2,2),(0,0)],
 'run-resume-reverse':[(1,2),(0,0),(1,2),(0,0),(0,3),(0,0)],
 'sprint-resume-turn':[(2,2),(0,0),(2,1),(0,0)],
 'arc-stop':[(1,2),(1,1),(0,0),(2,2),(2,4),(0,0)]}
expected={f'{sex}-{cargo}-{spec}' for sex in ('male','female') for cargo in ('empty','full') for spec in steps}
assert set(starts)==expected,'Missing or unexpected stop cases'
cases={n:[] for n in starts}
events={n:[] for n in starts}
for name,e,gait,drive,frame,keyRun,keySprint,keyMove in re.findall(r'\[WOOD_RAMP_EVENT\] case=(\S+) elapsed=(\d+) gait=(\d+) drive=(\d+) frame=(\d+) keyRun=(true|false) keySprint=(true|false) keyMove=(true|false)',log):
 if name in events:events[name].append(dict(elapsed=int(e),gait=int(gait),drive=int(drive),frame=int(frame),
  keyRun=keyRun=='true',keySprint=keySprint=='true',keyMove=keyMove=='true'))
for line in log.splitlines():
 if '[WOOD_BANK_SAMPLE]' not in line:continue
 row=dict(re.findall(r'([A-Za-z]+)=([^ ]+)',line));name=row.get('case')
 if name not in starts or not starts[name]<=int(row['wall'])<starts[name]+12000:continue
 assert row['item']=='SaucedWheelbarrow.WheelbarrowWood' and row['cartMotion']=='true','Wrong cart or disabled visual gate'
 row['elapsed']=int(row['elapsed']);row['wall']=int(row['wall'])
 for key in ['x','y','pace']:row[key]=float(row[key])
 row.update(re.findall(r'(direction|requested|active|braking|actualDistance|speed|stop_braking|stop_brakeLimit|stop_brakeWait|nativeSpeed|tickDt):([^, ]+)',line))
 row['actualDistance']=float(row['actualDistance']);row['dt']=float(row['tickDt'])
 assert all(math.isfinite(row[k]) for k in ['x','y','pace','actualDistance','dt'])
 native=re.search(r'tracks:(.*?),bones:',row['native'])[1]
 row['stops']=[{'name':n,'weight':float(w),'time':float(t),'rate':float(rate)}
  for n,w,t,rate in re.findall(r'([^;@]+)@([^/]+)/([^/]+)/([^/]+)/[^;]+;',native)
  if native_clip(n) in ['Bob_RunToStop2H_Heavy','Bob_SprintToStop2h_Heavy'] and float(w)>.001]
 cases[name].append(row)

results=[];problems=[]
for name,rows in cases.items():
 assert len(rows)>250,(name,len(rows))
 spec=name.split('-',2)[2]
 assert [(e['gait'],e['drive'])for e in events[name]]==steps[spec],(name,'missing or reordered input events')
 for event in events[name]:
  assert (event['keyRun'],event['keySprint'],event['keyMove'])==(event['gait']==1,event['gait']==2,event['drive']!=0),(name,'actual native key flags differ from requested input',event)
 if spec in ('run-stop','sprint-stop'):
  for index in (4,7):
   first,second=events[name][index-1:index+1]
   assert second['frame']==first['frame']+1 and 0<second['elapsed']-first['elapsed']<=50,(name,'releases must use adjacent game ticks within 50ms')
 reports=[]
 for i,event in enumerate(events[name]):
  if event['drive']!=0 or i>0 and events[name][i-1]['drive']==0:continue
  end=next((e['elapsed']for e in events[name][i+1:]if e['drive']!=0),11800)
  stop=[r for r in rows if event['elapsed']<r['elapsed']<end]
  clips=[t for r in stop for t in r['stops']]
  positions=[r for r in stop if r['elapsed']<=event['elapsed']+2500]
  report={'eventMs':event['elapsed'],'nextInputMs':end,'stopClips':sorted({t['name'] for t in clips}),
   'maxStopWeight':max((t['weight'] for t in clips),default=0),'rates':sorted({round(t['rate'],5) for t in clips}),
   'observedCoastingFrames':sum(r['actualDistance']>.001 for r in stop),
   'pathTiles':sum(math.hypot(b['x']-a['x'],b['y']-a['y']) for a,b in zip(positions,positions[1:])),
   'lastMovementAfterReleaseMs':max((r['elapsed']-event['elapsed'] for r in stop if r['actualDistance']>.001),default=0)}
  if name.endswith(('run-stop','sprint-stop')):
   report['releaseOrder']='same-frame'if i==1 else 'modifier-first'if i==4 else 'direction-first'
   report['temporalReturn']=temporal_return(wheel,starts[name],event['elapsed'],end)if wheel else {
    'available':False,'reason':'Native wheel CSV unavailable; sparse bodyShift log is not a peak-speed substitute'}
   expectedClip='Bob_RunToStop2H_Heavy'if spec=='run-stop'else 'Bob_SprintToStop2h_Heavy'
   if not any(native_clip(t['name'])==expectedClip and t['weight']>=.8 for t in clips):problems.append((name,'missing full native stop',report))
   if not report['observedCoastingFrames']:problems.append((name,'no coasting',report))
   if report['lastMovementAfterReleaseMs']>2500:problems.append((name,'did not settle',report))
  reports.append(report)
 for i,event in enumerate(events[name]):
  if event['drive']==0:continue
  end=events[name][i+1]['elapsed']if i+1<len(events[name])else 11800
  check=[r for r in rows if event['elapsed']+60<r['elapsed']<min(end,event['elapsed']+180)]
  if any(r['brakeArmed']=='true' for r in check):problems.append((name,'input kept stop armed',event))
 for previous,current in zip(rows,rows[1:]):
  if current['direction']!=previous['direction'] and (float(previous['speed'])>1e-6 or previous['actualDistance']>1e-6):
   problems.append((name,'reverse before measured rest',current['elapsed']))
 results.append({'case':name,'samples':len(rows),'stops':reports})
summary={'complete':True,'cases':results,'problems':problems,
 'limit':'Native log samples follow game updates, not a guaranteed 25ms cadence. Optional wheel temporal metrics report their own measured cadence and do not gate quality; sole contact and visual quality inspected separately.'}
args.output.write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
assert not problems,'Native brake gates failed'
