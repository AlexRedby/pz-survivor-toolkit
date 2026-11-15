"""Wring return interventions retain native ownership and real source capacity."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

SHARED=Path(__file__).resolve().parent/'native_queue/wring-clothing/shared'


class WringControlFixtureTests(unittest.TestCase):
    def runtime(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
function isClient()return false end
function getTimestampMs()return 123 end
local item={getID=function()return 7 end,getFullType=function()return 'Base.Socks_Ankle'end}
root={getItemById=function(_,id)if id==7 then return item end end}
item.getContainer=function()return root end
player={getInventory=function()return root end,hasTimedActions=function()return false end}
source={};local native={}
body={Type='ISWringClothing',item=item,action=native,toolkitQueueOperation={},isStarted=function()return true end,getJobDelta=function()return .1 end}
returned={Type='ISInventoryTransferAction',srcContainer=root,destContainer=source}
tail={Type='ISWringClothing'}
queue={queue={body,returned,tail},current=body,indexOf=function(self,wanted)for i,v in ipairs(self.queue)do if v==wanted then return i end end;return -1 end}
state={player=player,source=source,ids={case='worn-bag-keep',returnControl='keep',items={target={id=7,type='Base.Socks_Ankle'}}}}
local facts={marker='unchanged physical inventory'}
package.loaded.QueueWringClothing={snapshot=function()return facts end,returnMembers=function()return{{id=7,type='Base.Socks_Ankle'}}end}
local failure={id=81,itemId=7,itemType='Base.Socks_Ankle',state='blocked',reason='admission'}
PZSurvivorToolkit={ActionQueuePolicy={evaluateCancel=function(q,a)assert(q==queue and a==returned);return{allowed=true,mode='pending-return'}end},
 ActionQueue={cancel=function(q,a)assert(q==queue and a==returned and not a.action);table.remove(q.queue,2);return true end},
 ActionQueueExecution={blockedReturns=function(p)assert(p==player);return{failure}end,keepReturn=function(p,id)assert(p==player and id==81,'Keep must use failure identity, not item identity');return true end}}
''')
        lua.globals().C=lua.execute((SHARED/'QueueWringReturnControls.lua').read_text())
        return lua

    def test_pending_keep_retires_only_generated_request_after_real_progress(self):
        lua=self.runtime()
        lua.execute('''
local original=body.action;local token=body.toolkitQueueOperation
profile={pendingReturn={body=body,action=returned,ref=tostring(returned)}};C.begin(profile,state,queue,body,false,function()error('Keep sent authority mutation')end,tostring(body))
local value=profile.controlEvidence
assert(value.kind=='keep'and value.accepted and value.policyMode=='pending-return'and value.bodyUnchanged)
assert(queue.current==body and body.action==original and body.toolkitQueueOperation==token)
assert(#queue.queue==2 and queue.queue[2]==tail and value.before==value.after)
local first=value;C.begin(profile,state,queue,body,false,function()error('duplicate intervention')end,tostring(body));assert(profile.controlEvidence==first)
''')

    def test_control_does_not_act_before_native_body_or_repurpose_denied_cancel(self):
        lua=self.runtime()
        lua.execute('''
body.action=nil
assert(not pcall(C.begin,{},state,queue,body,false,function()end))
body.action={};PZSurvivorToolkit.ActionQueuePolicy.evaluateCancel=function()return{allowed=false,reason='dependent'}end
assert(not pcall(C.begin,{pendingReturn={body=body,action=returned,ref=tostring(returned)}},state,queue,body,false,function()end,tostring(body)))
assert(#queue.queue==3 and queue.queue[2]==returned)
''')

    def test_full_waits_for_authority_and_keeps_exact_debt_only_after_tail_drains(self):
        lua=self.runtime()
        lua.execute('''
state.ids.case='worn-bag-full';state.ids.returnControl='full'
local capacity=18
source.getCapacity=function()return capacity end;source.setCapacity=function(_,v)capacity=v end
profile={pendingReturn={body=body,action=returned,ref=tostring(returned)}};local requested
C.begin(profile,state,queue,body,false,function(command)requested=command end,tostring(body))
assert(requested=='CapacityLost'and not C.ready(profile,state,queue,false))
function isClient()return true end
C.capacityAccepted(profile,state,{case=state.ids.case,itemId=7,itemType='Base.Socks_Ankle',beforeCapacity=18,afterCapacity=0,roomBefore=true,roomAfter=false,root=true,authority=true,at=123})
assert(capacity==0 and state.controlCapacityBefore==18 and profile.controlEvidence.accepted)
assert(not C.ready(profile,state,queue,false),'cleanup raced body/tail')
queue.queue={};queue.current=nil
assert(C.ready(profile,state,queue,false))
assert(profile.controlEvidence.blocked.id==81 and profile.controlEvidence.kept)
PZSurvivorToolkit.ActionQueueExecution.keepReturn=function()error('duplicate Keep')end
assert(C.ready(profile,state,queue,false))
''')

    def test_disabled_queue_does_not_invent_optional_request_or_keep(self):
        lua=self.runtime()
        lua.execute('''
queue.queue={body,tail};profile={}
PZSurvivorToolkit.ActionQueue.cancel=function()error('queue-off cancellation')end
C.begin(profile,state,queue,body,true,function()error('unrequested mutation')end,tostring(body))
assert(not profile.controlEvidence.accepted and profile.controlEvidence.generatedRef==false)
assert(not profile.controlEvidence.enabled and profile.controlEvidence.bodyUnchanged)
''')

    def test_mutable_lua_rendering_does_not_rewrite_captured_action_references(self):
        lua=self.runtime()
        lua.execute('''
local native,token=body.action,body.toolkitQueueOperation
setmetatable(body,{__tostring=function(value)return 'body:action='..tostring(value.action)..':sound='..tostring(value.sound)end})
setmetatable(returned,{__tostring=function(value)return 'return:action='..tostring(value.action)..':sound='..tostring(value.sound)end})
-- Match native Kahlua's content-bearing table strings: the producer records
-- the body before begin, and the body sample records the return before begin.
body.action=nil
local bodyRef=tostring(body)
body.action=native;body.sound='native wring sound'
local returnRef=tostring(returned)
profile={pendingReturn={body=body,action=returned,ref=returnRef}}
returned.sound='later mutation'
assert(tostring(body)~=bodyRef and tostring(returned)~=returnRef)
C.begin(profile,state,queue,body,false,function()error('Keep sent authority mutation')end,bodyRef)
assert(profile.controlEvidence.bodyRef==bodyRef and profile.controlEvidence.generatedRef==returnRef)
assert(queue.current==body and body.action==native and body.toolkitQueueOperation==token)
assert(profile.controlEvidence.bodyUnchanged and queue.queue[2]==tail)
-- The later native return-start observer must reuse the sample's label, too.
returned.action={}
assert(C.returnRef(profile,returned)==returnRef)
local foreign={};assert(C.returnRef(profile,foreign)==tostring(foreign))
-- Labels do not authorize a substituted object even when its rendering agrees.
local replacement={Type='ISInventoryTransferAction',srcContainer=root,destContainer=source}
queue.queue={body,replacement,tail};profile={pendingReturn={body=body,action=returned,ref=returnRef}}
assert(not pcall(C.begin,profile,state,queue,body,false,function()end,bodyRef))
assert(queue.queue[2]==replacement and body.action==native and body.toolkitQueueOperation==token)
''')

    def test_capacity_intervention_changes_real_authority_container_and_rejects_duplicate(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute("package.loaded.QueueEnergyPlacement={}")
        lua.globals().F=lua.execute((SHARED/'QueueWringClothing.lua').read_text())
        lua.execute('''
function isClient()return false end
function getTimestampMs()return 123 end
local cap=18;local root={};local item={getID=function()return 7 end,getFullType=function()return 'Base.Socks_Ankle'end,
 getWetness=function()return 99 end,getContainer=function()return root end}
local source={getCapacity=function()return cap end,setCapacity=function(_,v)cap=v end,hasRoomFor=function()return cap>0 end}
local player={getInventory=function()return root end}
local state={player=player,source=source,items={target=item},ids={case='worn-bag-full',returnControl='full'}}
F.snapshot=function()return{items={target={counts={root=1}}}}end
local value=F.capacityLost(state)
assert(cap==0 and state.controlCapacityBefore==18 and value.beforeCapacity==18 and not value.roomAfter and value.root and value.authority)
assert(not pcall(F.capacityLost,state),'duplicate intervention accepted')
function isClient()return true end
assert(not pcall(F.capacityLost,state),'client manufactured authority')
''')


if __name__=='__main__':unittest.main()
