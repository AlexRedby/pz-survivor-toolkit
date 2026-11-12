-- Full public decisions, not just a family's inspector. Java state remains a
-- fixture; the same vectors also run in installed Kahlua with its real tables.
if not NativeActionRoot then
 if TestCoverage then TestCoverage('source-contract','skipped','Queue lookup checks require --game.')end
 return
end
NativeKahluaTableLookup=true
local function setup(withoutPrimitive)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 for _,path in ipairs({'shared/ISBaseObject.lua','shared/TimedActions/ISBaseTimedAction.lua',
  'client/TimedActions/ISTimedActionQueue.lua','client/TimedActions/ISQueueActionsAction.lua',
  'shared/TimedActions/ISReadABook.lua','client/TimedActions/ISInventoryTransferAction.lua'})do f.native(path)end
 if withoutPrimitive then toolkitLuaMetatableMatches=nil end
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 isClient=function()return false end
 f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
 local policy=f.project('ActionQueuePolicy')
 local class=ISBaseTimedAction:derive('LookupFixtureAction')
 local inspections=0
 PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('fixture.lookup',{
  types={'LookupFixtureAction'},matches=function(action)return getmetatable(action)==class end,
  inspect=function(action)
   inspections=inspections+1
   return {items={},itemTypes={},targets={},cancelWaiting=true,
    edit={version=1,complete=true,capacity='unchanged',resources={{domain='lookup-fixture',key=action.resource,
     facts={value=false},requires={},effects={}}}}}
  end})
 local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
 local a=f.action(class,{resource={}});local b=f.action(class,{resource={}})
 local q=f.queue(head,a,b)
 assert(policy.evaluateMove(q,b,a).allowed,'ordinary registered native inheritance lost move permission')
 assert(policy.evaluateCancel(q,b,true).allowed,'ordinary pending operation lost cancel permission')
 local snapshot=policy.evaluateMove(q,b,a).snapshot
 assert(policy.editUnchanged(q,snapshot),'healthy snapshot rejected')
 return {f=f,policy=policy,class=class,q=q,a=a,b=b,head=head,snapshot=snapshot,
  inspections=function()return inspections end}
end
local function decisions(s)
 return {
  function()return s.policy.evaluateMove(s.q,s.b,s.a).allowed==false end,
  function()return s.policy.evaluateCancel(s.q,s.b,true).allowed==false end,
  function()return s.policy.evaluateCancel(s.q,s.b,false).allowed==false end,
  function()return s.policy.previewMove(s.q,s.b,s.a).reason~=nil end,
  function()return s.policy.previewCancel(s.q,s.b,true).reason~=nil end,
  function()return s.policy.moveReason(s.q,s.b,s.a)~=nil end,
  function()return s.policy.cancelReason(s.q,s.b)~=nil end,
  function()return s.policy.cancelOperationReason(s.q,s.b)~=nil end,
  function()return not s.policy.editUnchanged(s.q,s.snapshot)end,
  function()return s.policy.observeActiveEdit(s.q,{kind='cancel',action=s.b}).status=='unhandled'end,
  function()return s.policy.rejectedPickupPlan(s.q,s.head)==nil end,
  function()return s.policy.evaluatePriority(s.q,s.b,true).allowed==false end,
  function()return s.policy.priorityIntent(s.q,s.b,true).reason~=nil end,
  function()return s.policy.returnFailureIndependent(s.q,s.b)==false end,
 }
end
-- Revalidation must retain the original ancestry, even when a newly attached
-- harmless prototype supplies exactly the same selected metadata values.
do
 local s=setup();setmetatable(s.b.toolkitQueueOperation,{__index={}})
 assert(not s.policy.editUnchanged(s.q,s.snapshot),'safe ancestry replacement escaped the original snapshot')
 assert(s.policy.evaluateMove(s.q,s.b,s.a).allowed,'a fresh decision reused the old ancestry refusal')
end
for _,mutation in ipairs({'base-index','class-index','class-parent','instance','queue','list','token',
 'suffix','masked-instance','masked-token','masked-nil','cycle'})do
 local s=setup();local calls=0
 local function foreign()calls=calls+1;error('foreign lookup invoked: '..mutation)end
 if mutation=='base-index'then ISBaseTimedAction.__index=foreign
 elseif mutation=='class-index'then s.class.__index=foreign
 elseif mutation=='class-parent'then setmetatable(s.class,{__index=foreign})
 elseif mutation=='instance'then setmetatable(s.b,{__index=foreign})
 elseif mutation=='queue'then setmetatable(s.q,{__index=foreign})
 elseif mutation=='list'then setmetatable(s.q.queue,{__index=foreign})
 elseif mutation=='token'then setmetatable(s.b.toolkitQueueOperation,{__index=foreign})
 elseif mutation=='suffix'then
  local tail=s.f.action(s.class,{resource={}});s.q.queue[4]=tail;setmetatable(tail,{__index=foreign})
 elseif mutation=='masked-instance'then setmetatable(s.b,{__index=foreign,__metatable=s.class})
 elseif mutation=='masked-token'then setmetatable(s.b.toolkitQueueOperation,{__index=foreign,__metatable={}})
 elseif mutation=='masked-nil'then setmetatable(s.b,{__index=foreign,__metatable=false})
 elseif mutation=='cycle'then local meta={};meta.__index=meta;setmetatable(meta,meta);setmetatable(s.b,meta)end
 local before=s.inspections()
 for index,check in ipairs(decisions(s))do
  local ok,denied=pcall(check)
  assert(ok and denied,'public decision did not reject lookup mutation '..mutation..'/'..index..': '..tostring(denied))
  assert(calls==0,'public decision invoked lookup before rejection: '..mutation..'/'..index)
 end
 assert(s.inspections()==before,'unsupported lookup reached a behavior inspector')
 assert(s.q.queue[1]==s.head and s.q.queue[2]==s.a and s.q.queue[3]==s.b,'rejection mutated the queue')
 if mutation=='base-index'then ISBaseTimedAction.__index=ISBaseTimedAction end
end
-- The gate must accept harmless table dispatch as well as native self dispatch.
-- It is not a replacement for a family's stricter source/class proof.
do
 local s=setup();local parent={toolkitStarted=false};parent.__index=parent
 setmetatable(s.b.toolkitQueueOperation,parent)
 assert(s.policy.evaluateMove(s.q,s.b,s.a).allowed,'ordinary inherited token metadata lost move permission')
 local classMeta={__index=ISBaseTimedAction}
 setmetatable(s.class,classMeta)
 assert(s.policy.evaluateMove(s.q,s.b,s.a).allowed,'ordinary table-dispatch inheritance was rejected')
 local decision=s.policy.evaluateMove(s.q,s.b,s.a)
 parent.toolkitCancelled=true
 assert(not s.policy.editUnchanged(s.q,decision.snapshot),'inherited token state change escaped snapshot recheck')
end
-- Optional Java absence preserves legacy reported-chain decisions. It cannot
-- authenticate a class or enable any new source-bound edit capability.
do
 local s=setup(true);local calls=0
 ISBaseTimedAction.__index=function()calls=calls+1;error('legacy foreign lookup')end
 assert(not s.policy.evaluateMove(s.q,s.b,s.a).allowed and calls==0,'reported-chain fallback called functional dispatch')
 ISBaseTimedAction.__index=ISBaseTimedAction
end
-- A replacement helper is rejected before it can act as a new lookup oracle.
do
 local s=setup();local calls=0
 toolkitLuaMetatableMatches=function()calls=calls+1;error('foreign primitive')end
 assert(not s.policy.evaluateMove(s.q,s.b,s.a).allowed and calls==0,'changed native primitive was invoked')
end
if TestCoverage then TestCoverage('source-contract','passed')end
print('Queue lookup: public edit/snapshot gates reject unsafe ancestry before lookup; native/table inheritance and optional-Java legacy controls passed.')
