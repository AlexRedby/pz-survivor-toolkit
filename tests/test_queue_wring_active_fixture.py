"""Active interventions use public cancellation and preserve native lifecycle evidence."""
import unittest
from tests import test_queue_wring_control_fixture as fixtures


class WringActiveFixture(unittest.TestCase):
    def runtime(self, kind='cancel', native=False):
        lua=fixtures.WringControlFixtureTests().runtime()
        lua.execute('''
clock=123;function getTimestampMs()return clock end
state.ids.returnControl=...;state.ids.case='worn-bag-'..state.ids.returnControl
state.tailAction=tail;tail.character=player
local enabled=not select(2,...)
PZSurvivorToolkit.Settings={actionQueue=function()return enabled end}
queue.toolkitOperationsInvalid=not enabled;queue.toolkitOperationGeneration=enabled and 0 or 1
PZAPI={ModOptions={getOptions=function()return{getOption=function()return{setValue=function(_,value)enabled=value end}end}end}}
PZSurvivorToolkit.ActionQueue.updateOperationState=function(q)
 if not enabled and not q.toolkitOperationsInvalid then q.toolkitOperationGeneration=(q.toolkitOperationGeneration or 0)+1;q.toolkitOperationsInvalid=true
 elseif enabled then q.toolkitOperationsInvalid=nil end
end
PZSurvivorToolkit.ActionQueuePolicy.evaluateCancel=function(q,value,whole)
 assert(q==queue and value==body and whole==true);return{allowed=true,mode='active'}
end
PZSurvivorToolkit.ActionQueue.cancelOperation=function(q,value)
 assert(q==queue and value==body and value.action and value:getJobDelta()>0)
 q.toolkitGroupCancel={};table.remove(q.queue,2);return true
end
local own=not select(2,...)
fixtureDebt={id=81,itemId=7,itemType='Base.Socks_Ankle',title='Base.Socks_Ankle',reason='producer',state='revoked'}
PZSurvivorToolkit.ActionQueueExecution.blockedReturns=function()
 if own and profile and profile.controlEvidence and(state.ids.returnControl=='toggle'or state.ids.returnControl=='toggle-off')then return{fixtureDebt}end
 return{}
end
profile={pendingReturn=not select(2,...)and{body=body,action=returned,ref='original-optional'}or nil,
 controlTailRef='saved-tail',activeBodyRow={},activeTailRow={started=false,progress=false}}
stopDetails=function(returned)return{source='disposable-jvm-stop',probeClass='net.alexredby.wringstopprobe.Main',
 nativeClass='zombie.characters.CharacterTimedActions.LuaTimedActionNew',callbackObserved=returned,callbackSucceeded=returned,callbackUnchanged=true}end
body.character=player;body.forceStop=function(self)assert(self==body);self.action.stopRequested=true end
function deliverNativeStop()
 local self=body;assert(self.action.stopRequested);C.active.nativeStop(profile,state,self,self.action,'entry',false,stopDetails(false))
 queue.queue={};queue.current=nil
 C.active.nativeStop(profile,state,self,self.action,'returned',true,stopDetails(true))
end
''',kind,native)
        return lua

    def test_stop_probe_rejects_failed_lua_callback_and_wrong_native_episode(self):
        lua=self.runtime()
        lua.execute("""
C.begin(profile,state,queue,body,false,function()end,'saved-body')
assert(not pcall(C.active.nativeStop,profile,state,body,{},'entry',false,stopDetails(false)))
C.active.nativeStop(profile,state,body,body.action,'entry',false,stopDetails(false))
assert(not pcall(C.active.nativeStop,profile,state,body,body.action,'entry',false,stopDetails(false)))
local failed=stopDetails(true);failed.callbackSucceeded=false
assert(not pcall(C.active.nativeStop,profile,state,body,body.action,'returned',false,failed))
assert(not profile.controlEvidence.stopped and #profile.controlEvidence.stopEvents==1)
C.active.nativeStop(profile,state,body,body.action,'returned',true,stopDetails(true))
assert(profile.controlEvidence.stopped)
assert(not pcall(C.active.nativeStop,profile,state,body,body.action,'returned',true,stopDetails(true)))
""")

    def test_accepted_cancel_requires_new_return_and_exact_stop(self):
        lua=self.runtime()
        lua.execute('''
local original=body.action;C.begin(profile,state,queue,body,false,function()error('authority mutation')end,'saved-body')
local e=profile.controlEvidence
assert(e.accepted and e.policyMode=='active'and not e.stopped and e.bodyUnchanged)
assert(e.originalReturn.actionRef=='original-optional'and not e.originalReturn.allocated)
assert(not C.ready(profile,state,queue,false))
C.active.nativeStop(profile,state,body,body.action,'entry',false,stopDetails(false))
C.active.nativeStop(profile,state,body,body.action,'returned',true,stopDetails(true))
assert(e.stopped and #e.stopEvents==2 and #e.lifecycleEvents==0 and profile.activeBodyRow.lifecycleEvents==e.lifecycleEvents)
local new={Type='ISInventoryTransferAction',srcContainer=root,destContainer=source}
C.active.started(profile,state,queue,new)
local captured=C.returnRef(profile,new);new.action={};assert(C.returnRef(profile,new)==captured and captured~='original-optional')
queue.queue={};queue.current=nil
profile.activeTailRow.started=true;profile.activeTailRow.progress=true
assert(C.ready(profile,state,queue,false)and e.requiredRef==captured and e.tailPreserved)
assert(body.action==original and #e.originalReturn.events==0)
''')

    def test_native_stop_uses_real_force_stop_seam_and_loses_tail(self):
        lua=self.runtime(native=True)
        lua.execute('''
C.begin(profile,state,queue,body,true,function()error('native control used mod cancellation')end,'saved-body')
local e=profile.controlEvidence
assert(e.accepted and e.policyMode==false and not e.stopped and body.action.stopRequested and queue.current==body)
deliverNativeStop()
assert(e.stopped and #e.stopEvents==2)
assert(e.originalReturn==false and e.generatedRef==false)
assert(C.ready(profile,state,queue,true)and not e.requiredRef and not e.tailPreserved)
''')

    def test_native_cancel_disable_records_request_before_engine_stops_tail(self):
        lua=self.runtime(kind='cancel-toggle',native=True)
        lua.execute("""
C.begin(profile,state,queue,body,true,function()end,'saved-body')
local e=profile.controlEvidence
assert(e.accepted and body.action.stopRequested and not e.stopped and #e.stopEvents==0)
assert(e.settings[1].tailRetained and e.settings[1].bodySame and e.settings[1].nativeSame)
deliverNativeStop()
assert(e.stopped and #queue.queue==0 and not e.tailPreserved)
assert(C.ready(profile,state,queue,true))
""")

    def test_editor_cycle_waits_for_next_tick_and_does_not_stop_or_keep(self):
        lua=self.runtime(kind='toggle')
        lua.execute('''
C.begin(profile,state,queue,body,false,function()error('toggle sent authority mutation')end,'saved-body')
local e=profile.controlEvidence
assert(not PZSurvivorToolkit.Settings.actionQueue()and #e.settings==1 and not e.stopped)
assert(e.settings[1].generationAfter==1 and e.settings[1].bodySame and e.settings[1].nativeSame)
C.active.tick(profile,state,queue,false);assert(#e.settings==1,'cycle did not wait a native tick')
clock=124;C.active.tick(profile,state,queue,false)
assert(PZSurvivorToolkit.Settings.actionQueue()and #e.settings==2 and e.settings[2].label=='re-enable')
assert(e.settings[2].generationBefore==1 and e.settings[2].generationAfter==1 and not e.requiredRef)
clock=125;C.active.tick(profile,state,queue,false)
assert(not PZSurvivorToolkit.Settings.actionQueue()and #e.settings==3 and e.settings[3].label=='disable'and e.settings[3].generationAfter==2)
clock=126;C.active.tick(profile,state,queue,false)
assert(PZSurvivorToolkit.Settings.actionQueue()and #e.settings==4 and e.settings[4].label=='re-enable'and e.settings[4].generationAfter==2)
queue.queue={};queue.current=nil
profile.activeTailRow.started=true;profile.activeTailRow.progress=true
assert(C.ready(profile,state,queue,false)and e.blocked==fixtureDebt and not e.kept and e.tailPreserved)
''')

    def test_editor_disabled_body_has_no_return_or_reenable(self):
        lua=self.runtime(kind='toggle-off')
        lua.execute('''
C.begin(profile,state,queue,body,false,function()error('source mutation')end,'saved-body')
local e=profile.controlEvidence;clock=124;C.active.tick(profile,state,queue,false)
assert(not PZSurvivorToolkit.Settings.actionQueue()and #e.settings==1 and not e.reenabledDuringBody)
assert(not e.stopped and not e.requiredRef and #e.originalReturn.events==0)
queue.queue={};queue.current=nil;profile.activeTailRow.started=true;profile.activeTailRow.progress=true
assert(C.ready(profile,state,queue,false)and e.tailPreserved and not e.kept)
''')

    def test_editor_retirement_requires_exact_unpaid_notice_and_never_keeps_it(self):
        lua=self.runtime(kind='toggle-off')
        lua.execute("""
C.begin(profile,state,queue,body,false,function()end,'saved-body')
queue.queue={};queue.current=nil;profile.activeTailRow.started=true;profile.activeTailRow.progress=true
fixtureDebt.state='blocked'
assert(not pcall(C.ready,profile,state,queue,false))
fixtureDebt.state='revoked';fixtureDebt.itemType='Other.Item'
assert(not pcall(C.ready,profile,state,queue,false))
fixtureDebt.itemType='Base.Socks_Ankle'
assert(C.ready(profile,state,queue,false)and profile.controlEvidence.blocked==fixtureDebt and not profile.controlEvidence.kept)
PZSurvivorToolkit.ActionQueueExecution.blockedReturns=function()return{}end
assert(not pcall(C.ready,profile,state,queue,false),'missing unpaid notice accepted')
""")

    def test_never_accept_original_return_or_changed_stop_episode(self):
        lua=self.runtime()
        lua.execute('''
C.begin(profile,state,queue,body,false,function()end,'saved-body')
body.action={};assert(not pcall(C.active.lifecycle,profile,state,body,'finish','stop',true))
assert(not pcall(C.active.started,profile,state,queue,returned))
''')


if __name__=='__main__':unittest.main()
