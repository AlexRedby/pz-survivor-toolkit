"""Later intent uses the genuine producer seam, never a manual loan waiver."""
import unittest
from pathlib import Path
from tests import test_queue_wring_control_fixture as control_fixture


class WringIntentFixtureTests(unittest.TestCase):
    def test_native_request_recording_and_delayed_debt_retirement(self):
        lua=control_fixture.WringControlFixtureTests().runtime()
        lua.execute('''
package.loaded['TimedActions/ISEquipWeaponAction']={}
local invoked=0;local primary
player.getPlayerNum=function()return 0 end
player.getPrimaryHandItem=function()return primary end
ISEquipWeaponAction={}
for _,name in ipairs({'new','isValid','start','update','perform','complete','getDuration','stop'})do ISEquipWeaponAction[name]=function()end end
ISTimedActionQueue={add=function(action)queue.queue[#queue.queue+1]=action;return action end}
ISInventoryPaneContextMenu={OnPrimaryWeapon=function(items,playerNum)
 assert(items[1]==root:getItemById(7)and playerNum==0)
 local action={Type='ISEquipWeaponAction',character=player,item=items[1],primary=true,twoHands=false,maxTime=50}
 for name,method in pairs(ISEquipWeaponAction)do action[name]=method end
 ISTimedActionQueue.add(action)
end}
package.loaded['PZSurvivorToolkit/ActionQueueOperations']={run=function(callback,items,playerNum)
 invoked=invoked+1;assert(callback==ISInventoryPaneContextMenu.OnPrimaryWeapon);return callback(items,playerNum)
end}
state.ids.case='worn-bag-intent';state.ids.returnControl='intent'
PZSurvivorToolkit.ActionQueue.cancel=function()error('explicit request used manual Keep')end
PZSurvivorToolkit.ActionQueueExecution.keepReturn=function()error('native effect replaced with footer Keep')end
local native,token=body.action,body.toolkitQueueOperation
profile={pendingReturn={body=body,action=returned,ref='saved-return'}}
C.begin(profile,state,queue,body,false,function()error('intent mutated source authority')end,'saved-body')
assert(invoked==1 and queue.current==body and body.action==native and body.toolkitQueueOperation==token)
local equip=profile.intentAction;local row=profile.controlEvidence.intent
assert(queue.queue[4]==equip and row.duration==50 and row.primary and not row.twoHands)
assert(not row.started and not row.progress and row.producer=='native ISInventoryPaneContextMenu.OnPrimaryWeapon')
PZSurvivorToolkit.ActionQueueSettlement={operationState=function(value)assert(value==body);return{borrowings={{id=7,state='active'}}}end}
queue.current=equip;queue.queue={equip}
C.intentStarted(profile,state,queue,equip)
assert(row.beforeEffect.loanState=='active'and row.beforeEffect.debt.id==81 and row.beforeEffect.canonicalRoot)
equip.action={};equip.isStarted=function()return true end;equip.getJobDelta=function()return .1 end
C.observeIntent(profile,state,queue)
assert(row.started and row.progress and row.nativeRef==tostring(equip.action))
assert(C.intentBoundary(profile,state,{},'begin','complete')==nil)
assert(C.intentBoundary(profile,state,equip,'begin','complete')==true,'native observer did not enroll finish notifications')
primary=root:getItemById(7)
C.intentBoundary(profile,state,equip,'finish','complete',true)
assert(row.events[1].phase=='complete'and row.events[2].primary.id==7 and row.events[2].succeeded)
queue.queue={};queue.current=nil
assert(not C.ready(profile,state,queue,false),'visible hands alone hid unsettled native debt')
PZSurvivorToolkit.ActionQueueExecution.blockedReturns=function()return{}end
assert(C.ready(profile,state,queue,false)and profile.controlEvidence.finalPrimarySame)
assert(profile.controlEvidence.blocked==false and profile.controlEvidence.kept==false)
''')

    def test_registered_observer_enrolls_native_finish_with_queue_disabled(self):
        root=Path(__file__).resolve().parents[1]
        client=(root/'tests/native_queue/wring-clothing/client/ZZWringClothing.lua').read_text()
        observer=client.split("registerObserver('prepared-carried-wring-return',{",1)[1]
        begin=observer.split('begin=function(action,phase)\n',1)[1].split('\n end,\n settled=function(action)',1)[0]
        finish=observer.split('finish=function(action,phase,succeeded)\n',1)[1].split('\n end}))',1)[0]
        lua=control_fixture.WringControlFixtureTests().runtime()
        lua.execute("""
package.loaded['TimedActions/ISQueueActionsAction']={}
package.loaded['PZSurvivorToolkit/ActionQueueOperations']={}
package.loaded['PZSurvivorToolkit/ActionQueueTransfers']={}
ISQueueActionsAction={start=function()end}
PZSurvivorToolkit.Settings={actionQueue=function()return false end}
ISTimedActionQueue={queues={[player]=queue}}
queue.character=player
player.getPrimaryHandItem=function()return nil end
profile={intentAction={character=player,action={}},controlEvidence={intent={events={}}},controls=C}
tracks={};returnTracks={};ids=state.ids
""")
        lifecycle=lua.execute((root/'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua').read_text())
        begin_callback=lua.execute('return function(action,phase)\n'+begin+'\nend')
        finish_callback=lua.execute('return function(action,phase,succeeded)\n'+finish+'\nend')
        callbacks=lua.table_from({'begin':begin_callback,'finish':finish_callback})
        self.assertTrue(lifecycle.registerObserver('actual-wring-observer',callbacks))
        lua.globals().Lifecycle=lifecycle
        lua.execute("""
local action=profile.intentAction
-- Mirrors the native bridge: an unenrolled begin receives no finish callback.
for _,phase in ipairs({'perform','complete'})do
 local enrolled=Lifecycle.begin(action,phase)
 assert(enrolled==true,'actual registered callback failed native finish gate')
 if enrolled then Lifecycle.finish(action,phase,true)end
end
local events=profile.controlEvidence.intent.events
assert(#events==4 and events[2].boundary=='finish'and events[4].boundary=='finish')
assert(events[2].succeeded and events[4].succeeded)
""")


if __name__=='__main__':unittest.main()
