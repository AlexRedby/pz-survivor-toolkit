"""Execute the read-only Fitness witnesses around real callback delegations."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tests/native_queue/fitness/shared/QueueFitnessObservation.lua'
LUA = shutil.which('luajit') or shutil.which('lua')

HARNESS = r'''
package.preload['TimedActions/ISFitnessAction']=function()return true end
package.preload['TimedActions/ISReadABook']=function()return true end
package.preload['TimedActions/ISDropWorldItemAction']=function()return true end
function isServer()return server end
function isClient()return client end
MoodleType={ENDURANCE='endurance'};CharacterStat={ENDURANCE='endurance'}
Perks={Fitness='fitness',Strength='strength'}
ISFitnessUI={enduranceLevelThreshold=2}
calendar,hour,fitnessXP,strengthXP,endurance,regularity,stiffness,moodle=1000,9,10,20,1,0,0,0
local fitness={}
function fitness:getRegularity()return regularity end
function fitness:getCurrentExeStiffnessInc()return stiffness end
function fitness:getCurrentExeStiffnessTimer()return 10 end
function fitness:getCurrentExe()return currentExercise end
local stats={get=function()return endurance end,getEnduranceDangerWarning=function()return .25 end}
local xp={getXP=function(_,perk)return perk=='fitness'and fitnessXP or strengthXP end}
local moodles={getMoodleLevel=function()return moodle end}
local xpHandlers={}
Events={AddXP={Add=function(callback)xpHandlers[#xpHandlers+1]=callback end}}
local function xpEvent(actor,perk,amount)
 for _,callback in ipairs(xpHandlers)do callback(actor,perk,amount)end
end
local function award(perk,amount)
 if perk==Perks.Fitness then fitnessXP=fitnessXP+amount else strengthXP=strengthXP+amount end
 xpEvent(player,perk,amount)
end
player={}
local nativePresent=false
function player:getCharacterActions()return {contains=function(_,action)return nativePresent end}end
function player:getFitness()return fitness end
function player:getXp()return xp end
function player:getStats()return stats end
function player:getMoodles()return moodles end
function player:pressedMovement(flag)assert(flag==true);return false end
function player:isPlayerMoving()return false end
function player:isAiming()return false end
function player:isClimbing()return false end
function player:isSittingOnFurniture()return false end
function player:getVehicle()return nil end
function player:isDead()return false end
function player:isAsleep()return false end
function player:pressedCancelAction()return false end
function player:getVariableBoolean(key)return key=='ExerciseEnded' end
function getGameTime()return {
 getCalender=function()return {getTimeInMillis=function()return calendar end}end,
 getTimeOfDay=function()return hour end,getNightsSurvived=function()return 0 end,
 getGameWorldSecondsSinceLastUpdate=function()return .1 end,
 getRealworldSecondsSinceLastUpdate=function()return .02 end}end
ISReadABook={serverStart=function()end};ISDropWorldItemAction={complete=function()return true end}
local calls={start=0,rep=0,stop=0,complete=0}
ISFitnessAction={}
function ISFitnessAction:serverStart(arg)
 assert(arg=='start-argument');calls.start=calls.start+1;currentExercise='burpees';return 'started'
end
function ISFitnessAction:exeLooped(arg)
 assert(arg=='rep-argument');if repeatError then error('native-repeat-failed')end
 calls.rep=calls.rep+1;self.repnb=self.repnb+1;fitnessXP=fitnessXP+2;strengthXP=strengthXP+3
 endurance=endurance-.2;regularity=regularity+.1;stiffness=stiffness+.2;moodle=3;calendar=calendar+100
 return 'repeated'
end
function ISFitnessAction:serverStop(arg)
 assert(arg=='stop-argument');if stopError then error('native-stop-failed')end
 calls.stop=calls.stop+1;currentExercise=nil;calendar=calendar+100;return 'stopped'
end
function ISFitnessAction:complete(arg)
 assert(arg=='complete-argument');calls.complete=calls.complete+1;currentExercise=nil;return true
end
local originals={};for key,value in pairs(ISFitnessAction)do originals[key]=value end
local action={action={},character=player,Type='ISFitnessAction',exeDataType='burpees',timeToExe=30,repnb=0,startMS=1000}
function action:getDuration()return 5000000 end
function action:isStarted()return true end
'''


@unittest.skipUnless(LUA, 'Lua runtime unavailable')
class FitnessStopObservationTests(unittest.TestCase):
    def run_lua(self, body, *, server=False, client=False):
        script = f'server={str(server).lower()};client={str(client).lower()}\n' + HARNESS
        script += '\nlocal O=dofile(' + json.dumps(str(SOURCE)) + ')\n' + body
        result = subprocess.run([LUA, '-'], input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_client_snapshot_keeps_source_guarded_methods_and_state(self):
        self.run_lua(r'''
for key,value in pairs(originals)do assert(ISFitnessAction[key]==value,'client native method replaced')end
O.reset(player,'late-exhaustion');moodle=3;endurance=.24
local state=O.noteStop(action)
assert(state.type=='ISFitnessAction'and state.exercise=='burpees'and state.minutes==30 and state.started)
assert(state.enduranceMoodle==3 and state.threshold==2 and state.clinical.endurance==.24)
assert(state.calendarMS==1000 and state.durationMS==7200000)
for _,key in ipairs({'pressedMovement','moving','aiming','climbing','sittingFurniture','vehicle','dead','asleep','pressedCancel','exerciseStarted'})do
 assert(state[key]==false,'unexpected predicate '..key)
end
assert(state.exerciseEnded and not action.fitnessWitness and #O.records==0)
assert(fitnessXP==10 and strengthXP==20 and endurance==.24 and calls.start==0 and calls.rep==0 and calls.stop==0)
''', client=True)

    def test_server_records_real_rep_delta_and_stop_entry_before_delegate(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion')
assert(ISFitnessAction.serverStart(action,'start-argument')=='started')
assert(ISFitnessAction.exeLooped(action,'rep-argument')=='repeated')
local row=action.fitnessWitness
assert(row.reps==1 and calls.rep==1 and action.repnb==1)
assert(row.repSampleDelta==1 and row.repObservationSource=='server exeLooped')
assert(row.lastRepBefore.fitnessXP==10 and row.lastRep.fitnessXP==12)
assert(row.lastRepBefore.strengthXP==20 and row.lastRep.strengthXP==23)
assert(row.lastRepBefore.endurance==1 and row.lastRep.endurance==.8)
assert(row.lastRepBeforeEnduranceMoodle==0 and row.lastRepEnduranceMoodle==3)
assert(row.lastRepDurationMS==7200000)
ISFitnessUI=nil
assert(ISFitnessAction.serverStop(action,'stop-argument')=='stopped')
assert(row.stopEntry.threshold==false and row.stopEntry.enduranceMoodle==3)
assert(row.stopEntry.calendarMS==1100 and row.stopMS==1200 and row.stopEntry.durationMS<=row.durationStopMS)
assert(row.after.fitnessXP==row.lastRep.fitnessXP and row.after.strengthXP==row.lastRep.strengthXP)
assert(row.currentExerciseCleared and row.serverStopReturned and row.stopCallbacks.serverStop==1)
assert(row.postStopXP.baseline.fitnessXP==12 and #row.postStopXP.events==0 and row.afterXPEventCount==0)
assert(calls.start==1 and calls.stop==1 and not O.active)
''', server=True)

    def test_native_exceptions_do_not_forge_repetition_or_settlement(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');ISFitnessAction.serverStart(action,'start-argument')
repeatError=true
local ok,error=pcall(ISFitnessAction.exeLooped,action,'rep-argument')
assert(not ok and tostring(error):find('native-repeat-failed',1,true))
local row=action.fitnessWitness
assert(row.reps==0 and row.lastRep==nil and row.lastRepBefore==nil and calls.rep==0)
stopError=true
ok,error=pcall(ISFitnessAction.serverStop,action,'stop-argument')
assert(not ok and tostring(error):find('native-stop-failed',1,true))
assert(row.stopEntry and not row.stopMS and row.stopCallbacks.serverStop==1 and O.active==action)
assert(currentExercise=='burpees'and calls.stop==0 and fitnessXP==10 and strengthXP==20)
''', server=True)

    def test_legacy_cases_keep_existing_evidence_schema(self):
        self.run_lua(r'''
O.reset(player,'burpees-30');ISFitnessAction.serverStart(action,'start-argument')
ISFitnessAction.exeLooped(action,'rep-argument');ISFitnessAction.complete(action,'complete-argument')
local row=action.fitnessWitness
assert(row.reps==1 and row.stopMethod=='complete'and row.stopCallbacks.complete==1 and calls.complete==1)
assert(row.lastRepBefore==nil and row.lastRepBeforeEnduranceMoodle==nil and row.lastRepEnduranceMoodle==nil)
assert(row.lastRepDurationMS==nil and row.stopEntry==nil and row.repSampleDelta==nil and row.repObservationSource==nil)
assert(row.postStopXP==nil and row.afterXPEventCount==nil)
O.noteStop(action);assert(row.stopEntry==nil)
local receipt=O.receipt(player)
assert(receipt.records==O.records and receipt.receiptCalendarMS==nil and receipt.receiptDurationMS==nil)
''', server=True)

    def test_sp_note_stop_preserves_first_boundary_and_native_methods(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');O.sample(action)
local first=O.noteStop(action);calendar=calendar+100
local second=O.noteStop(action)
assert(action.fitnessWitness.stopEntry==first and first.calendarMS==1000 and second.calendarMS==1100)
for key,value in pairs(originals)do assert(ISFitnessAction[key]==value,'SP native method replaced')end
assert(calls.start==0 and calls.rep==0 and calls.stop==0 and fitnessXP==10 and strengthXP==20)
''')


    def test_sp_adjacent_samples_reject_skipped_repetition_boundary(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');O.sample(action)
-- Refresh even without a repetition so the predecessor is the adjacent sample.
endurance=.95;O.sample(action)
action.repnb=1;fitnessXP=12;strengthXP=23;endurance=.75;moodle=3;calendar=1100
O.sample(action)
local row=action.fitnessWitness
assert(row.repSampleDelta==1 and row.repObservationSource=='SP adjacent native samples')
assert(row.lastRepBefore.fitnessXP==10 and row.lastRepBefore.endurance==.95)
assert(row.lastRepBeforeEnduranceMoodle==0 and row.lastRepEnduranceMoodle==3)
assert(row.lastRep.fitnessXP==12 and row.lastRepDurationMS==7200000)
-- A missed interval must revoke the previously valid predecessor proof.
action.repnb=3;fitnessXP=16;strengthXP=29;O.sample(action)
assert(row.reps==3 and row.repSampleDelta==2 and row.repObservationSource=='SP skipped native samples')
assert(row.lastRepBefore==nil and row.lastRepBeforeEnduranceMoodle==nil)
assert(row.lastRep.fitnessXP==16)
for key,value in pairs(originals)do assert(ISFitnessAction[key]==value,'SP native method replaced')end
assert(calls.rep==0 and calls.start==0 and calls.stop==0)
''')

    def test_sp_first_sample_cannot_invent_preceding_rep_state(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');action.repnb=1;fitnessXP=12
O.sample(action)
local row=action.fitnessWitness
assert(row.reps==1 and row.repSampleDelta==false and row.lastRepBefore==nil)
assert(row.repObservationSource=='SP skipped native samples')
''')


    def test_sp_post_stop_ledger_covers_delayed_removal_sample_and_exact_prefix(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');O.sample(action)
endurance=.24;O.noteStop(action)
local row=action.fitnessWitness
assert(row.postStopXP.baseline.fitnessXP==10 and #row.postStopXP.events==0)
-- Native removal precedes the polling observer; this event must not be lost.
nativePresent=false;calendar=1100;award(Perks.Fitness,1)
assert(#row.postStopXP.events==1 and row.postStopXP.events[1].observerActive==true)
O.sample(nil)
assert(row.afterXPEventCount==1 and row.after.fitnessXP==11 and row.stopEntry.clinical.fitnessXP==10)
calendar=1200;award(Perks.Fitness,1)
local ledger=row.postStopXP
assert(#ledger.events==2 and ledger.events[2].observerActive==false)
assert(row.afterXPEventCount==1 and row.after.fitnessXP==11)
for index,event in ipairs(ledger.events)do
 assert(event.perk=='Fitness'and event.amount==1 and event.clinical.fitnessXP==10+index)
 assert(event.clinical.strengthXP==20 and event.calendarMS==1000+index*100)
 assert(event.durationMS==7200000 and event.currentExerciseCleared and event.nativeAbsent)
 assert(event.reps==0 and event.enduranceWarning==.25 and event.clinical.endurance==.24)
end
assert(ledger.baseline.fitnessXP+ledger.events[1].amount+ledger.events[2].amount==fitnessXP)
assert(calls.rep==0 and calls.stop==0)
''')

    def test_post_stop_ledger_records_invalid_strength_and_unexplained_deltas(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');O.sample(action);O.noteStop(action)
local row=action.fitnessWitness
nativePresent=true;currentExercise='burpees';award(Perks.Strength,3)
local event=row.postStopXP.events[1]
assert(event.perk=='Strength'and event.amount==3 and event.clinical.strengthXP==23)
assert(not event.currentExerciseCleared and not event.nativeAbsent and event.observerActive)
-- A raw mutation is not fabricated into an event or hidden in the baseline.
fitnessXP=fitnessXP+7;award(Perks.Fitness,1)
event=row.postStopXP.events[2]
assert(event.amount==1 and event.clinical.fitnessXP-row.postStopXP.baseline.fitnessXP==8)
assert(#row.postStopXP.events==2 and row.postStopXP.baseline.fitnessXP==10)
''')

    def test_post_stop_ledger_ignores_foreign_actors_cases_and_client_replicas(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');O.sample(action);O.noteStop(action)
local row=action.fitnessWitness
xpEvent({},Perks.Fitness,1);xpEvent(player,'unrelated-perk',1)
client=true;xpEvent(player,Perks.Fitness,1);client=false
assert(#row.postStopXP.events==0)
O.case='burpees-30';xpEvent(player,Perks.Fitness,1)
assert(#row.postStopXP.events==0)
O.case='late-exhaustion';O.sample(nil);O.reset(player,'late-exhaustion')
xpEvent(player,Perks.Fitness,1);assert(#row.postStopXP.events==0)
''')

    def test_post_stop_observer_failure_is_evidence_and_cannot_abort_native_award(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');O.sample(action);O.noteStop(action)
local row=action.fitnessWitness
player.getCharacterActions=function()error('read-only-witness-failed')end
award(Perks.Fitness,1)
assert(fitnessXP==11 and row.postStopXP.error:find('read-only-witness-failed',1,true))
assert(#row.postStopXP.events==0)
''')


    def test_receipt_freezes_record_values_and_xp_event_horizon(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');O.sample(action);endurance=.24;O.noteStop(action)
calendar=1100;award(Perks.Fitness,1);O.sample(nil)
local receipt=O.receipt(player);local recorded=receipt.records[1]
assert(receipt.records~=O.records and recorded~=action.fitnessWitness)
assert(receipt.receiptCalendarMS==1100 and receipt.receiptDurationMS==7200000)
assert(receipt.clinical.fitnessXP==11 and #recorded.postStopXP.events==1 and recorded.afterXPEventCount==1)
calendar=1200;award(Perks.Fitness,1)
assert(#action.fitnessWitness.postStopXP.events==2 and fitnessXP==12)
assert(#recorded.postStopXP.events==1 and receipt.clinical.fitnessXP==11)
assert(recorded.postStopXP.events[1].calendarMS<=receipt.receiptCalendarMS)
action.fitnessWitness.postStopXP.events[1].clinical.fitnessXP=999
assert(recorded.postStopXP.events[1].clinical.fitnessXP==11)
''')


    def test_server_net_action_never_probes_or_claims_base_action_absence(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');action.action=nil;action.netAction={}
ISFitnessAction.serverStart(action,'start-argument');O.noteStop(action)
ISFitnessAction.serverStop(action,'stop-argument')
local callsToList=0
player.getCharacterActions=function()
 callsToList=callsToList+1
 return {contains=function(_,value)assert(value~=nil,'contains(nil) is not a native body witness');return false end}
end
local stopCallback=ISFitnessAction.serverStop
award(Perks.Fitness,1)
local row=action.fitnessWitness;local event=row.postStopXP.events[1]
assert(event and event.nativeAbsent==false and event.observerActive==false)
assert(row.postStopXP.error==nil and callsToList==0 and ISFitnessAction.serverStop==stopCallback)
assert(action.netAction~=nil and action.action==nil)
''', server=True)

    def test_sp_absence_requires_the_exact_nonmissing_native_pointer(self):
        self.run_lua(r'''
O.reset(player,'late-exhaustion');O.sample(action);O.noteStop(action)
local native=action.action;local containsCalls=0
player.getCharacterActions=function()return {contains=function(_,candidate)
 containsCalls=containsCalls+1;assert(candidate==native,'wrong native pointer');return false
end}end
award(Perks.Fitness,1)
assert(action.fitnessWitness.postStopXP.events[1].nativeAbsent==true and containsCalls==1)
action.action=nil;award(Perks.Fitness,1)
assert(action.fitnessWitness.postStopXP.events[2].nativeAbsent==false and containsCalls==1)
for key,value in pairs(originals)do assert(ISFitnessAction[key]==value,'SP native callback changed')end
''')


if __name__ == '__main__':
    unittest.main()
