local Bulk={}
function Bulk.isCase(id) return id=='bulk-pickup' or id=='bulk-waiting-cancel' or id=='bulk-mixed' end
function Bulk.prepare(state,seed)
 seed('bulkHeavyA','Base.Plank',state.source)
 for i=1,3 do seed('bulkLight'..i,'Base.Nails',state.source) end
 seed('bulkHeavyB','Base.Plank',state.source)
 if state.id=='bulk-mixed' then seed('bulkBorrowed','Base.Nails',state.source) end
 if state.id=='bulk-waiting-cancel' then
  seed('bulkSurvivor','Base.Nails',state.source)
 end
 assert(state.bulkHeavyA:getWeight()>0.1 and state.bulkLight1:getWeight()<=0.1,'bulk fixture requires native heavy/light weights')
end
local function transfers(queue,before,items,source,root)
 local result={}
 for i=before+1,#queue.queue do
  local action=queue.queue[i]
  assert(action.Type=='ISInventoryTransferAction' and action.srcContainer==source and action.destContainer==root,
   'bulk UI callback added unexpected action/container')
  assert(action.item==items[#result+1],'bulk UI callback changed item order/identity')
  result[#result+1]=action
 end
 assert(#result==#items,'bulk UI callback missed item');return result
end
function Bulk.enqueue(state,context)
 local queue=context.queue();state.bulkActions={};state.bulkGroups={}
 local function grab(items)
  local before=#queue.queue
  context.run(ISInventoryPaneContextMenu.onGrabItems,items,state.player:getPlayerNum())
  local actions=transfers(queue,before,items,state.source,state.root)
  for _,action in ipairs(actions) do state.bulkActions[#state.bulkActions+1]=action end
 end
 -- A real context-menu click shares one operation scope even with the queue disabled.
 PZSurvivorToolkit.ActionQueueOperations.run(function()
 if state.id=='bulk-mixed' then
  grab({state.bulkHeavyA})
  local action=ISInventoryTransferUtil.newInventoryTransferAction(state.player,state.bulkBorrowed,state.source,state.root)
  ISTimedActionQueue.add(action);state.bulkActions[#state.bulkActions+1]=action
  grab({state.bulkLight1,state.bulkLight2,state.bulkLight3,state.bulkHeavyB})
 else grab({state.bulkHeavyA,state.bulkLight1,state.bulkLight2,state.bulkLight3,state.bulkHeavyB}) end
 end)
 state.bulkExecutor=state.bulkActions[1]
 if state.id=='bulk-waiting-cancel' then
  local before=#queue.queue
  context.run(ISInventoryPaneContextMenu.onGrabItems,{state.bulkSurvivor},state.player:getPlayerNum())
  state.bulkSurvivorAction=transfers(queue,before,{state.bulkSurvivor},state.source,state.root)[1]
 end
end
function Bulk.controls(state,context)
 if state.id~='bulk-waiting-cancel' then return end
 local queue=context.queue()
 if context.native then
  for _,action in ipairs(state.bulkActions) do queue:removeFromQueue(action) end
 else
  local decision=context.policy.evaluateCancel(queue,state.bulkExecutor,true)
  assert(decision.allowed,'waiting bulk pickup cancellation denied '..tostring(decision.reason))
  assert(context.api.cancelOperation(queue,state.bulkExecutor),'waiting bulk pickup cancellation failed')
 end
 for _,action in ipairs(state.bulkActions) do assert(queue:indexOf(action)==-1,'waiting bulk child survived cancellation') end
 assert(queue:indexOf(state.bulkSurvivorAction)~=-1 and queue:indexOf(state.frontAction)~=-1 and queue:indexOf(state.tailAction)~=-1,
  'bulk cancellation removed unrelated transfer/books')
 state.bulkCancelled=true;state.unrelatedTailPreserved=true
end
function Bulk.observe(state,queue)
 if state.id=='bulk-waiting-cancel' then return end
 local executor=state.bulkExecutor
 local heavyA,heavyB=false,false
 for _,group in ipairs(executor.queueList or {}) do
  local ids={}
  for _,item in ipairs(group.items) do ids[#ids+1]=tostring(item:getID()) end
  state.bulkGroups[table.concat(ids,',')]=true
  if #group.items==(state.id=='bulk-mixed' and 4 or 3) then
   local expected={[state.bulkLight1:getID()]=true,[state.bulkLight2:getID()]=true,[state.bulkLight3:getID()]=true}
   if state.bulkBorrowed then expected[state.bulkBorrowed:getID()]=true end
   for _,item in ipairs(group.items) do assert(expected[item:getID()],'light merge acquired unexpected ID');expected[item:getID()]=nil end
   for _ in pairs(expected) do error('light merge omitted exact ID') end;state.bulkLightMerged=true
  end
  if #group.items==1 then
   if group.items[1]==state.bulkHeavyA then heavyA=true end
   if group.items[1]==state.bulkHeavyB then heavyB=true end
  end
 end
 local wiped=true
 for i=2,#state.bulkActions do
  local action=state.bulkActions[i]
  for _ in pairs(action) do wiped=false end
  if queue:indexOf(action)~=-1 then wiped=false end
 end
 if wiped then
  state.bulkChildrenWiped=true
  if heavyB and (heavyA or state.bulkHeavyA:getContainer()==state.root) then state.bulkHeavySeparate=true end
 end
end
function Bulk.container(state,name,postprocess,tidy)
 if state.id=='bulk-waiting-cancel' and name~='bulkSurvivor' then return state.source end
 if name=='bulkBorrowed' and postprocess and tidy then return state.source end
 return state.root
end
function Bulk.verify(state,postprocess,tidy)
 for name,item in pairs(state.items) do
  if name:match('^bulk') then
   assert(item:getContainer()==Bulk.container(state,name,postprocess,tidy) and not item:getWorldItem(),
    'bulk exact source/destination differs '..name..' id='..item:getID())
  end
 end
 return {bulkPickup=true,exactBulkContainers=true}
end
function Bulk.evidence(state)
 if state.id=='bulk-waiting-cancel' then
  assert(state.bulkCancelled and state.unrelatedTailPreserved,'bulk cancellation evidence missing')
  return {bulkCancelled=true,unrelatedTailPreserved=true}
 end
 assert(state.bulkLightMerged and state.bulkHeavySeparate and state.bulkChildrenWiped,'native bulk merge evidence missing light='..tostring(state.bulkLightMerged)..' heavy='..tostring(state.bulkHeavySeparate)..' wiped='..tostring(state.bulkChildrenWiped))
 return {lightMerged=true,heavySeparate=true,childrenWiped=true,sharedExecutor=state.id=='bulk-mixed'}
end
return Bulk
