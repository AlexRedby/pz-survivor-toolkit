next=nil -- The game VM exposes pairs but no global next.
local Bulk=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentBulk.lua'))()
local nextID=0
local function item(name,container)
 nextID=nextID+1;local identity=nextID
 return {getID=function() return identity end,getFullType=function() return name end,
  getContainer=function() return container end,getWorldItem=function() return nil end}
end
local function fixture(id)
 local state={id=id,source={},root={},items={},bulkGroups={}}
 for _,name in ipairs({'bulkHeavyA','bulkLight1','bulkLight2','bulkLight3','bulkHeavyB','bulkBorrowed'}) do
  local value=item(name,state.root)
  state[name]=value;state.items[name]=value
 end
 if id~='bulk-mixed' then state.items.bulkBorrowed=nil;state.bulkBorrowed=nil end
 state.bulkActions={{},{},{},{},{}}
 state.bulkExecutor=state.bulkActions[1]
 state.bulkExecutor.queueList={{items={state.bulkLight1,state.bulkLight2,state.bulkLight3}},{items={state.bulkHeavyB}}}
 local queue={queue={state.bulkExecutor},indexOf=function(self,action)
  for i,value in ipairs(self.queue) do if value==action then return i end end;return -1
 end}
 return state,queue
end
local state,queue=fixture('bulk-pickup')
assert(not pcall(Bulk.evidence,state),'completion without native merge evidence must fail')
Bulk.observe(state,queue)
assert(Bulk.evidence(state).childrenWiped,'SP remaining groups must prove real wipe/removal')
local child={item=state.bulkLight1};state.bulkActions[2]=child;state.bulkChildrenWiped=nil
Bulk.observe(state,queue);assert(not pcall(Bulk.evidence,state),'removed but unwiped child is not native merge evidence')
state.bulkActions[2]={};queue.queue[2]=state.bulkActions[2]
Bulk.observe(state,queue);assert(not pcall(Bulk.evidence,state),'wiped child still in queue is not native merge evidence')
local mixed,mixedQueue=fixture('bulk-mixed')
mixed.bulkExecutor.queueList[1].items[4]=mixed.bulkBorrowed
Bulk.observe(mixed,mixedQueue);assert(Bulk.evidence(mixed).sharedExecutor,'borrowed and explicit IDs must share exact light group')
local missing,missingQueue=fixture('bulk-mixed')
Bulk.observe(missing,missingQueue);assert(not pcall(Bulk.evidence,missing),'separate borrowed executor must not satisfy shared group')
local wrong,wrongQueue=fixture('bulk-pickup');wrong.bulkExecutor.queueList[1].items[3]=wrong.bulkHeavyA
assert(not pcall(Bulk.observe,wrong,wrongQueue),'wrong light ID must fail immediately')
for _,native in ipairs({true,false}) do
 local cancelled,cancelQueue=fixture('bulk-waiting-cancel')
 cancelled.frontAction={};cancelled.tailAction={};cancelled.bulkSurvivorAction={}
 cancelQueue.queue={cancelled.frontAction}
 for _,action in ipairs(cancelled.bulkActions) do cancelQueue.queue[#cancelQueue.queue+1]=action end
 cancelQueue.queue[#cancelQueue.queue+1]=cancelled.bulkSurvivorAction;cancelQueue.queue[#cancelQueue.queue+1]=cancelled.tailAction
 function cancelQueue:removeFromQueue(action) local i=self:indexOf(action);if i~=-1 then table.remove(self.queue,i) end end
 local api={cancelOperation=function(q,action)
  assert(action==cancelled.bulkExecutor)
  for _,entry in ipairs(cancelled.bulkActions) do q:removeFromQueue(entry) end;return true
 end}
 Bulk.controls(cancelled,{native=native,queue=function() return cancelQueue end,api=api,policy={evaluateCancel=function() return {allowed=true} end}})
 assert(Bulk.evidence(cancelled).unrelatedTailPreserved and #cancelQueue.queue==3,'cancel must retain native unrelated tails')
end
for _,native in ipairs({true,false}) do for _,id in ipairs({'bulk-pickup','bulk-mixed','bulk-waiting-cancel'}) do
 local state,queue=fixture(id);state.player={getPlayerNum=function() return 0 end}
 state.bulkSurvivor=item('survivor',state.source)
 local scope
 local function run(callback,...)
  local previous=scope;scope=scope or {};callback(...);scope=previous
 end
 PZSurvivorToolkit={ActionQueueOperations={run=run}}
 ISInventoryTransferUtil={newInventoryTransferAction=function(player,value,source,destination)
  return {Type='ISInventoryTransferAction',character=player,item=value,srcContainer=source,destContainer=destination}
 end}
 ISTimedActionQueue={add=function(action) action.toolkitQueueOperation=scope or {};queue.queue[#queue.queue+1]=action end}
 ISInventoryPaneContextMenu={onGrabItems=function(items)
  for _,value in ipairs(items) do
   local action=ISInventoryTransferUtil.newInventoryTransferAction(state.player,value,state.source,state.root)
   action.explicit=true;ISTimedActionQueue.add(action)
  end
 end}
 queue.queue={}
 Bulk.enqueue(state,{queue=function() return queue end,run=function(callback,...)
  if native then return callback(...) end;return run(callback,...)
 end})
 for _,action in ipairs(state.bulkActions) do
  assert(action.toolkitQueueOperation==state.bulkExecutor.toolkitQueueOperation,'one menu click must permit native bulk merge')
  assert(action.explicit==(action.item~=state.bulkBorrowed and true or nil),'borrowed helper must not enter explicit grab callback')
 end
 if state.bulkSurvivorAction then
  assert(state.bulkSurvivorAction.toolkitQueueOperation~=state.bulkExecutor.toolkitQueueOperation,'survivor must remain independently cancellable')
 end
end end
print('Equipment bulk checks passed: exact merged IDs, real child wipe/removal and waiting cancellation isolation.')
if NativeActionRoot then
 local path=NativeActionRoot..'/client/TimedActions/ISInventoryTransferAction.lua'
 local native
 if NativeReadText then native=NativeReadText(path) else
  local source=assert(io.open(path,'r'));native=source:read('*a');source:close()
 end
 local methods=assert(native:match('(function ISInventoryTransferAction:canMergeAction.-)\n%-%- This is to support returning'))
 ISInventoryTransferAction={};assert(loadstring(methods))()
 table.wipe=function(value) for key in pairs(value) do value[key]=nil end end
 round=function(value) return value end
 for _,id in ipairs({'bulk-pickup','bulk-mixed'}) do
  local live,liveQueue=fixture(id)
  local items={live.bulkHeavyA,live.bulkLight1,live.bulkLight2,live.bulkLight3,live.bulkHeavyB}
  if live.bulkBorrowed then table.insert(items,2,live.bulkBorrowed) end
  live.bulkActions={};liveQueue.queue={}
  for _,value in ipairs(items) do
   local light=value~=live.bulkHeavyA and value~=live.bulkHeavyB
   value.getFullType=function() return light and 'Base.Nails' or 'Base.Plank' end
   value.getWeight=function() return light and 0.01 or 3 end
   local action=setmetatable({Type='ISInventoryTransferAction',item=value,srcContainer=live.source,destContainer=live.root,
    maxTime=49,queueList={{items={value},time=49,type=value:getFullType()}}},{__index=ISInventoryTransferAction})
   live.bulkActions[#live.bulkActions+1]=action;liveQueue.queue[#liveQueue.queue+1]=action
  end
  live.bulkExecutor=live.bulkActions[1]
  ISTimedActionQueue={getTimedActionQueue=function() return liveQueue end}
  live.bulkExecutor:checkQueueList()
  assert(#liveQueue.queue==1 and #live.bulkExecutor.queueList==3,'native merge must keep three heavy/light/heavy groups')
  Bulk.observe(live,liveQueue);assert(Bulk.evidence(live).childrenWiped,'native MP merge must retain exact intent evidence')
  live.bulkHeavySeparate=nil;live.bulkLightMerged=nil;table.remove(live.bulkExecutor.queueList,1)
  Bulk.observe(live,liveQueue);assert(Bulk.evidence(live).heavySeparate,'SP observer must prove groups after first perform')
 end
 print('Equipment bulk fixture also passed installed native checkQueueList merging in SP/MP observation phases.')
end
