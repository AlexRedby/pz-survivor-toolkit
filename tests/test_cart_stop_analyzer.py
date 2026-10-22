"""Reject incomplete or mislabeled native stop evidence."""
from pathlib import Path
import csv
import json
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT=Path(__file__).parent/'native_queue/contributions/wooden_cart_motion/analyze-stop.py'
STEPS={
 'run-stop':[(1000,1,2),(2500,0,0),(4000,1,2),(5500,0,2),(5525,0,0),(7000,1,2),(8500,1,0),(8525,0,0)],
 'sprint-stop':[(1000,2,2),(2500,0,0),(4000,2,2),(5500,0,2),(5525,0,0),(7000,2,2),(8500,2,0),(8525,0,0)],
 'short-release':[(1000,2,2),(1250,0,0),(4000,1,2),(4250,0,0),(6500,2,2),(7000,0,0)],
 'run-resume-reverse':[(1000,1,2),(4000,0,0),(4150,1,2),(7000,0,0),(7150,0,3),(10000,0,0)],
 'sprint-resume-turn':[(1000,2,2),(4000,0,0),(4150,2,1),(8500,0,0)],
 'arc-stop':[(1000,1,2),(2500,1,1),(3000,0,0),(5500,2,2),(6500,2,4),(7000,0,0)]}


def evidence():
 lines=['[WOOD_BANK] RUN_STARTED']
 for sex in ('male','female'):
  for cargo in ('empty','full'):
   for spec,events in STEPS.items():
    name=f'{sex}-{cargo}-{spec}';start=100000+len(lines)*15000
    lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start}')
    for t,g,d in events:lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed={t} gait={g} drive={d} frame={t//25} keyRun={str(g==1).lower()} keySprint={str(g==2).lower()} keyMove={str(d!=0).lower()}')
    for t in range(0,12000,25):
     prior=[event for event in events if event[0]<=t]
     event=prior[-1]if prior else (0,0,0)
     stopping=event[2]==0 and event[0]>0
     coasting=stopping and t-event[0]<700
     sprint=spec=='sprint-stop'
     clip='Bob_SprintToStop2h_Heavy'if sprint else 'Bob_RunToStop2H_Heavy'
     tracks=f'{clip}@1/.4/1/true;'if stopping and t-event[0]<1000 else ''
     lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x=0 y=0 pace=1 item=SaucedWheelbarrow.WheelbarrowWood cartMotion=true brakeArmed=false native=tracks:{tracks},bones: reversal=direction:1,requested:1,active:false,braking:false,actualDistance:{.01 if coasting else 0}, brake=stop_braking:{str(coasting).lower()},stop_brakeLimit:1,stop_brakeWait:0,tickDt:.025, ramp=speed:0,')
 lines.append('[WOOD_BANK] ALL_COMPLETE cases=24')
 return '\n'.join(lines)


class CartStopAnalyzerTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.log=evidence()

 def analyze(self,log,wheel=None,explicit_log=False):
  with tempfile.TemporaryDirectory()as directory:
   root=Path(directory);(root/'native-launch.log').write_text(log)
   log_path=root/'client1-launch.log'
   if explicit_log:
    log_path.write_text(log)
    (root/'native-launch.log').write_text('Wrong legacy log must not be read')
   if wheel:
    with (root/'wood-wheel-native.csv').open('w')as stream:
     writer=csv.DictWriter(stream,fieldnames=wheel[0]);writer.writeheader();writer.writerows(wheel)
   output=root/'result.json'
   command=[sys.executable,str(SCRIPT),'--profile',str(root),'--output',str(output)]
   if explicit_log:command+=['--log',str(log_path)]
   result=subprocess.run(command,capture_output=True,text=True)
   if explicit_log:self.assertEqual(log_path.read_text(),log)
   report=json.loads(output.read_text())if output.exists()else None
   return result,report

 def test_canonical_stops_keep_raw_names_and_reject_unknown_or_wrong_stop(self):
  log=self.log.replace('Bob_RunToStop2H_Heavy','Toolkit_CartPivot_StopRun').replace('Bob_SprintToStop2h_Heavy','Toolkit_CartPivot_StopSprint')
  result,report=self.analyze(log)
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual(report['cases'][0]['stops'][0]['stopClips'],['Toolkit_CartPivot_StopRun'])
  for wrong in ('Toolkit_CartPivot_StopRnu','Toolkit_CartPivot_StopSprint','Toolkit_CartPivot_Run'):
   self.assertNotEqual(self.analyze(log.replace('Toolkit_CartPivot_StopRun',wrong))[0].returncode,0)

 def test_complete_protocol(self):
  result,report=self.analyze(self.log)
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual(len(report['cases']),24)
  self.assertEqual(report['problems'],[])
  self.assertEqual([s['releaseOrder']for s in report['cases'][0]['stops']],
   ['same-frame','modifier-first','direction-first'])
  self.assertFalse(report['cases'][0]['stops'][0]['temporalReturn']['available'])

 def test_explicit_stdout_path_overrides_legacy_log_without_rewriting_it(self):
  result,report=self.analyze(self.log,explicit_log=True)
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual(len(report['cases']),24)

 def test_missing_explicit_stdout_does_not_fall_back(self):
  with tempfile.TemporaryDirectory()as directory:
   root=Path(directory);(root/'native-launch.log').write_text(self.log)
   output=root/'result.json'
   result=subprocess.run([sys.executable,str(SCRIPT),'--profile',str(root),
    '--log',str(root/'missing.log'),'--output',str(output)],capture_output=True,text=True)
   self.assertNotEqual(result.returncode,0)
   self.assertFalse(output.exists())

 def test_wrong_completion_count_is_rejected(self):
  for count in (16,20,240):
   with self.subTest(count=count):
    self.assertNotEqual(self.analyze(self.log.replace('ALL_COMPLETE cases=24',f'ALL_COMPLETE cases={count}'))[0].returncode,0)

 def test_return_uses_native_clock_and_wheel_offset_after_actor_rest(self):
  start=int(re.search(r'COMPLETE male-empty-run-stop wall=(\d+)',self.log)[1])
  wheel=[]
  for i,(time,player,offset)in enumerate(zip([0,.01,.03,.07,.11,.15],[0,.01,.01,.01,.01,.01],[.2,.3,.28,.24,.24,.24])):
   wheel.append(dict(event='grounding',time=time,wallTimeMillis=start+2600+i*10,
    playerX=player,playerY=0,wheelX=player+offset,wheelY=0,forwardX=1,forwardY=0))
  result,report=self.analyze(self.log,wheel)
  self.assertEqual(result.returncode,0,result.stderr)
  metric=report['cases'][0]['stops'][0]['temporalReturn']
  self.assertTrue(metric['available'])
  self.assertEqual(metric['actorRestAfterReleaseMs'],110)
  self.assertAlmostEqual(metric['returnExcursionTiles'],.06)
  self.assertAlmostEqual(metric['sampledMaxReturnSpeedTilesPerSecond'],1)
  self.assertAlmostEqual(metric['sampledMaxAdjacentSpeedJumpTilesPerSecond'],1)
  self.assertAlmostEqual(metric['intervalMs']['min'],20)
  self.assertAlmostEqual(metric['intervalMs']['max'],40)
  self.assertNotIn('pass',metric)

 def test_100ms_return_average_is_stable_with_unequal_sample_intervals(self):
  start=int(re.search(r'COMPLETE male-empty-run-stop wall=(\d+)',self.log)[1])
  for times in ([i*.02 for i in range(11)],[0,.011,.043,.069,.1,.131,.157,.2],[0,.01,.03,.06,.08]):
   with self.subTest(times=times):
    wheel=[dict(event='grounding',time=t,wallTimeMillis=start+2600+i*10,
     playerX=0,playerY=0,wheelX=1-2*t,wheelY=0,forwardX=1,forwardY=0)for i,t in enumerate(times)]
    result,report=self.analyze(self.log,wheel)
    self.assertEqual(result.returncode,0,result.stderr)
    metric=report['cases'][0]['stops'][0]['temporalReturn']
    if times[-1]<.1:
     self.assertIsNone(metric['sampledMax100msAverageReturnSpeedTilesPerSecond'])
     self.assertEqual(metric['average100msWindows'],0)
    else:
     self.assertAlmostEqual(metric['sampledMax100msAverageReturnSpeedTilesPerSecond'],2)
     self.assertGreater(metric['average100msWindows'],0)

 def test_empty_evidence(self):
  self.assertNotEqual(self.analyze('[WOOD_BANK] ALL_COMPLETE cases=24')[0].returncode,0)

 def test_unknown_cases(self):
  self.assertNotEqual(self.analyze(self.log.replace('male-empty-run-stop','unknown-case'))[0].returncode,0)

 def test_wrong_cart(self):
  self.assertNotEqual(self.analyze(self.log.replace('SaucedWheelbarrow.WheelbarrowWood','SaucedCarts.ShoppingCart',1))[0].returncode,0)

 def test_sprint_must_select_sprint_stop(self):
  self.assertNotEqual(self.analyze(self.log.replace('Bob_SprintToStop2h_Heavy','Bob_RunToStop2H_Heavy'))[0].returncode,0)

 def test_missing_input_event(self):
  self.assertNotEqual(self.analyze(self.log.replace('[WOOD_RAMP_EVENT]','[MISSING]',1))[0].returncode,0)

 def test_release_order_requires_distinct_adjacent_game_ticks(self):
  for replacement in ('elapsed=5525 gait=0 drive=0 frame=220',
   'elapsed=5525 gait=0 drive=0 frame=222','elapsed=5575 gait=0 drive=0 frame=221'):
   with self.subTest(replacement=replacement):
    self.assertNotEqual(self.analyze(self.log.replace('elapsed=5525 gait=0 drive=0 frame=221',replacement,1))[0].returncode,0)

 def test_actual_keys_must_match_each_release_stage(self):
  for current,replacement in (
   ('drive=0 frame=340 keyRun=true keySprint=false keyMove=false',
    'drive=0 frame=340 keyRun=false keySprint=false keyMove=false'),
   ('drive=0 frame=340 keyRun=false keySprint=true keyMove=false',
    'drive=0 frame=340 keyRun=false keySprint=false keyMove=false'),
   ('drive=2 frame=220 keyRun=false keySprint=false keyMove=true',
    'drive=2 frame=220 keyRun=false keySprint=false keyMove=false'),
   ('keyRun=true keySprint=false keyMove=true','keyRun=true keySprint=false keyMove=unknown')):
   with self.subTest(replacement=replacement):
    self.assertIn(current,self.log)
    self.assertNotEqual(self.analyze(self.log.replace(current,replacement,1))[0].returncode,0)

 def test_each_release_order_requires_a_native_stop(self):
  lines=self.log.splitlines()
  for i,line in enumerate(lines):
   if '[WOOD_BANK_SAMPLE] case=male-empty-run-stop 'in line and 5525<int(re.search(r'elapsed=(\d+)',line)[1])<7000:
    lines[i]=re.sub(r'Bob_RunToStop2H_Heavy@[^;]+;','',line)
  self.assertNotEqual(self.analyze('\n'.join(lines))[0].returncode,0)

 def test_failure_marker(self):
  self.assertNotEqual(self.analyze(self.log+'\n[WOOD_BANK] FAIL recorder')[0].returncode,0)
