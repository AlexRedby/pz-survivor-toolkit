"""Execute the disposable menu driver with native menu/queue/receipt doubles."""
from pathlib import Path
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer/lease-menu-actions.lua'
LUA = shutil.which('luajit') or shutil.which('lua')
HARNESS = r'''
local config={disposable=true,options={cart_lease_lifetimes=true,cart_lease_menu=true}}
local source={}; local operation={}; local events={}; local clock=1000
local nativeList={size=function(self) return self.count or 0 end,isEmpty=function(self) return self:size()==0 end}
local item={getID=function() return 42 end,getFullType=function() return 'SaucedWheelbarrow.WheelbarrowWood' end}
local world={getItem=function() return item end}
item.getWorldItem=function() return item.world end
local p={primary=item,secondary=item,getUsername=function() return 'client1' end,getPlayerNum=function() return 0 end,
 getCharacterActions=function() return nativeList end,hasPath=function(self) return self.path==true end,
 isTimedActionInstant=function() return false end,getPrimaryHandItem=function(self) return self.primary end,
 getSecondaryHandItem=function(self) return self.secondary end}
local localPlayer=p
getPlayer=function() return localPlayer end
cartLeaseCurrent=function() return source end
getText=function(key) return key end
local q={queue={},toolkitOperationGeneration=3}
ISTimedActionQueue={queues={[p]=q},getTimedActionQueue=function(player) assert(player==p);return q end}
local scope=false
PZSurvivorToolkit={ActionQueueOperations={run=function(callback)
 assert(not scope);scope=true;callback();scope=false
end}}
local receipt={token='10000000-0000-4000-8000-000000000042',transaction=3,generation=3,state='started'}
local Ack={capture=function(action) assert(q.current==action and action.action);return receipt end,
 observe=function(action,r) assert(r==receipt);return receipt.state end}
local function makeAction(pickup)
 return {character=p,Type=pickup and 'ToolkitWoodCartPickup' or 'ToolkitWoodCartSetdown',item=item,itemId=42,
  toolkitQueueOperation=operation,findWorldItem=function() return world end,maxTime=70}
end
local deferred=false;local badOption=false;local extraAction=false;local fillCount=0;local callbackCount=0
local function enqueueAction(pickup)
 assert(scope,'callback must run in existing native operation scope');callbackCount=callbackCount+1
 local action=makeAction(pickup)
 if pickup and deferred then action={character=p,Type='ISWalkToTimedActionF',toolkitWoodCartItem=item,toolkitQueueOperation=operation} end
 q.queue={action};if extraAction then q.queue[2]=makeAction(pickup) end
end
local function context(options)
 return {options=options or {},getSubMenu=function(self,key) return self.children[key] end,
  hideAndChildren=function(self) self.hidden=true end}
end
ISInventoryPaneContextMenu={onUnEquip=function(items,num)
 assert(items[1]==item and #items==1 and num==0);enqueueAction(false)
end}
ISInventoryPaneContextMenu.createMenu=function(num,inInventory,items,x,y)
 assert(num==0 and inInventory==true and items[1]==item and #items==1 and x==50 and y==50)
 fillCount=fillCount+1
 local option={name='ContextMenu_Unequip',target=items,param1=num,
  onSelect=badOption and function() error('foreign callback') end or ISInventoryPaneContextMenu.onUnEquip}
 local root=context({{subOption=1}});root.children={[1]=context({option})};return root
end
ISContextMenu={get=function(num,x,y) assert(num==0 and x==50 and y==50);return context() end}
triggerEvent=function(name,num,menu,objects,test)
 assert(name=='OnFillWorldObjectContextMenu' and num==0 and objects[1]==world and #objects==1 and test==false)
 fillCount=fillCount+1
 menu.options={{name='UI_SaucedCarts_PushCart',target=objects,param1=num,param2=badOption and {} or world,
  onSelect=function(actual,num2,actualWorld) assert(actual==objects and num2==0 and actualWorld==world);enqueueAction(true) end}}
end
package.preload['QueueTestSelection']=function() return config end
package.preload['PZSurvivorToolkit/ActionQueueAcknowledgements']=function() return Ack end
for _,name in ipairs({'SaucedCarts/ContextMenu','ISUI/ISContextMenu','ISUI/ISInventoryPaneContextMenu','TimedActions/ISTimedActionQueue'}) do
 package.preload[name]=function() return true end
end
local M=assert(loadfile(HELPER))()
local function emit(event,row) clock=clock+1;row.wall=clock;events[#events+1]={event=event,row=row} end
local function pickup() p.primary=nil;p.secondary=nil;item.world=world end
local function start(s)
 q.current=s.action;s.action.action={};nativeList.count=1
 assert(not M.poll(s));assert(events[#events].event=='start')
end
local function finish(s)
 receipt.state='completed';q.queue={};q.current=nil;nativeList.count=0
 assert(M.poll(s));assert(events[#events].event=='terminal')
end
local function fails(callback,pattern)
 local ok,err=pcall(callback);assert(not ok,'failure expected');assert(tostring(err):find(pattern),tostring(err))
end
'''


@unittest.skipUnless(LUA, 'Requires LuaJIT or Lua')
class CartLeaseMenuActionsTests(unittest.TestCase):
    def run_lua(self, body):
        script = 'local HELPER=' + repr(str(HELPER)) + '\n' + HARNESS + '\n' + body
        result = subprocess.run([LUA, '-'], input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_release_records_exact_native_receipts_and_allows_empty_hands_barrier(self):
        self.run_lua(r'''
local s=M.enqueue(p,item,false,2,emit)
assert(fillCount==1 and callbackCount==1 and p.primary==item and p.secondary==item)
assert(s.action.maxTime==70 and events[1].event=='queued' and events[1].row.kind=='release')
start(s);finish(s)
local rows=#events;assert(M.poll(s) and #events==rows)
assert(events[2].row.token==receipt.token and events[3].row.state=='completed')
assert(events[2].row.localNativeEpoch==events[3].row.localNativeEpoch)
assert(events[1].row.localActionEpoch==events[3].row.localActionEpoch)
assert(events[1].row.source==tostring(source) and events[1].row.queuedSource=='ToolkitWoodCartSetdown')
assert(events[1].row.wall<events[2].row.wall and events[2].row.wall<events[3].row.wall)
-- A native completed action alone does not assert or synthesize its gameplay effect.
assert(p.primary==item);p.primary=nil;p.secondary=nil;item.world=world
assert(callbackCount==1 and #q.queue==0)
''')

    def test_ground_pickup_uses_filled_sauced_option_and_preserves_native_duration(self):
        self.run_lua(r'''
pickup();local s=M.enqueue(p,item,true,2,emit)
assert(fillCount==1 and callbackCount==1 and s.action.maxTime==70 and item.world==world)
assert(events[1].row.kind=='pickup' and events[1].row.cart==42)
start(s);finish(s);assert(p.primary==nil and item.world==world)
''')

    def test_native_approach_continuation_retains_exact_operation_and_source(self):
        self.run_lua(r'''
pickup();deferred=true;local s=M.enqueue(p,item,true,2,emit)
assert(s.walk and not s.action and #events==0 and not M.poll(s))
local action=makeAction(true);q.queue={s.walk,action}
assert(not M.poll(s) and not s.action)
q.queue={action};assert(not M.poll(s) and s.action==action and s.walk==nil)
assert(events[1].row.queuedSource=='ISWalkToTimedActionF')
q.queue={action};start(s);finish(s)
''')

    def test_explicit_scope_owner_item_and_preexisting_work_are_required(self):
        for mutation, error in (
            ("localPlayer={}", 'Exact local menu owner'),
            ("p.getUsername=function() return 'client2' end", 'Exact local menu owner'),
            ("item.getFullType=function() return 'Base.Log' end", 'Exact wooden menu cart'),
            ("p.secondary=nil", 'exact held menu cart'),
            ("q.queue={makeAction(false)}", 'empty native/Lua'),
            ("nativeList.count=1", 'empty native/Lua'),
            ("p.path=true", 'empty native/Lua'),
            ("p.isTimedActionInstant=function() return true end", 'Native menu action duration'),
        ):
            with self.subTest(mutation=mutation):
                self.run_lua(mutation + "\nfails(function() M.enqueue(p,item,false,2,emit) end," + repr(error) + ')')
        for mutation in ('config.disposable=false', 'config.options.cart_lease_menu=false',
                         'config.options.cart_lease_lifetimes=false'):
            self.run_lua(mutation + "\nfails(function() assert(loadfile(HELPER))() end,'Explicit disposable')")

    def test_unfilled_wrong_source_or_duplicate_callback_work_fails(self):
        self.run_lua("badOption=true;fails(function() M.enqueue(p,item,false,2,emit) end,'menu option unavailable');assert(callbackCount==0)")
        self.run_lua("pickup();badOption=true;fails(function() M.enqueue(p,item,true,2,emit) end,'menu option unavailable');assert(callbackCount==0)")
        self.run_lua("extraAction=true;fails(function() M.enqueue(p,item,false,2,emit) end,'exactly one action')")

    def test_source_owner_operation_queue_and_exact_action_replacements_fail(self):
        for mutation, error in (
            ('source={}', 'owner/source/operation changed'),
            ('localPlayer={}', 'owner/source/operation changed'),
            ('ISTimedActionQueue.queues[p]={}', 'owner/source/operation changed'),
            ('q.toolkitOperationGeneration=4', 'owner/source/operation changed'),
            ('item.getID=function() return 43 end', 'cart identity changed'),
            ("item.getFullType=function() return 'Base.Log' end", 'cart identity changed'),
            ('operation.toolkitCancelled=true', 'owner/source/operation changed'),
            ('s.action.item={}', 'action binding changed'),
            ('s.action.character={}', 'action binding changed'),
            ('q.queue={makeAction(false)}', 'action replaced'),
        ):
            with self.subTest(mutation=mutation):
                self.run_lua('local s=M.enqueue(p,item,false,2,emit)\n' + mutation +
                             '\nfails(function() M.poll(s) end,' + repr(error) + ')')

    def test_cancel_revoke_native_replacement_and_unobserved_start_fail(self):
        for mutation, error in (
            ("receipt.state='canceled'", 'did not complete'),
            ("receipt.state='rejected'", 'did not complete'),
            ("receipt.state=nil", 'receipt revoked'),
            ("s.action.action={}", 'identity changed'),
        ):
            with self.subTest(mutation=mutation):
                self.run_lua('local s=M.enqueue(p,item,false,2,emit);start(s)\n' + mutation +
                             '\nfails(function() M.poll(s) end,' + repr(error) + ')')
        self.run_lua("local s=M.enqueue(p,item,false,2,emit);q.queue={};fails(function() M.poll(s) end,'without captured start')")

    def test_completed_receipt_waits_for_both_queues_and_path_to_clear(self):
        self.run_lua(r'''
local s=M.enqueue(p,item,false,2,emit);start(s);receipt.state='completed';q.queue={};q.current=nil
assert(not M.poll(s));nativeList.count=0;p.path=true;assert(not M.poll(s));p.path=false
assert(M.poll(s) and events[#events].event=='terminal')
''')

    def test_deferred_source_operation_world_replacement_and_disappearance_fail(self):
        for mutation, error in (
            ('q.queue={}', 'pickup disappeared'),
            ('s.walk.toolkitQueueOperation={}', 'source changed'),
            ('s.walk.toolkitWoodCartItem={}', 'source changed'),
            ('local a=makeAction(true);a.toolkitQueueOperation={};q.queue={a}', 'menu action changed'),
            ('local a=makeAction(true);a.findWorldItem=function() return {} end;q.queue={a}', 'world source changed'),
            ('q.queue={makeAction(false)}', 'Unexpected deferred'),
        ):
            with self.subTest(mutation=mutation):
                self.run_lua('pickup();deferred=true;local s=M.enqueue(p,item,true,2,emit)\n' + mutation +
                             '\nfails(function() M.poll(s) end,' + repr(error) + ')')


if __name__ == '__main__':
    unittest.main()
