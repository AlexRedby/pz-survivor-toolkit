local Checks=require 'QueueScenarioChecks'
local Queue=require 'PZSurvivorToolkit/ActionQueue'
local Policy=require 'PZSurvivorToolkit/ActionQueuePolicy'
local Full={}
function Full.dispatch(player,ids,case,mode,q,anchor,eat,commands,observed,evidence)
 local quarter=case=='food-full-replacement-after-quarter'and eat(.25,true)or nil
 local full=eat(1,true);observed[#observed].label='full'
 if quarter then observed[1].label='quarter'end
 local tailItem=assert(player:getInventory():getItemById(ids.tailId))
 local tail=ISDrinkFluidAction:new(player,tailItem,.5)
 local command={id=ids.tailId,portion=.5,baseHunger=0,dispatchRemaining=0,dispatchSource='root',
  menuDispatched=false,nativeDuration=tail.maxTime,progress=false,cancelled=false,pickupObserved=false}
 assert(tail.maxTime==tail:getDuration()and tail.maxTime==460,'independent native drink duration differs')
 ISTimedActionQueue.add(tail);commands[#commands+1]=command;observed[#observed+1]={eat=tail,tail=true,label='tail'}
 evidence.startOrder={'anchor'};evidence.completionOrder={};evidence.denialReason='not-requested'
 if mode=='toolkit'then
  for _,entry in ipairs(observed)do local contract=Policy.inspect(entry.eat);assert(contract and contract.edit,'full/tail native edit contract missing')end
  evidence.contractsVerified=true
  if quarter then
   Checks.deniedMove(q,Queue,Policy,full,quarter,false,'edit_resource_amount')
   Checks.unchanged(q,{anchor,quarter,full,tail});evidence.moveRejected=true;evidence.denialReason='edit_resource_amount'
  elseif case=='food-full-replacement-cancel-pending'then
   Checks.waitingCancel(q,Queue,Policy,full,{full},{anchor,tail});commands[1].cancelled=true;evidence.waitingCancel=true
  else
   assert(Policy.evaluateMove(q,tail,full,false).allowed,'independent water cannot precede full food')
   assert(Queue.move(q,tail,full,false),'independent water move failed')
   Checks.unchanged(q,{anchor,tail,full});evidence.reordered=true
  end
 end
 local labels={[anchor]='anchor',[full]='full',[tail]='tail'};if quarter then labels[quarter]='quarter'end
 local prior,own=q.onCompleted,nil
 for key,value in pairs(q)do if key=='onCompleted'then own=value;break end end
 local observer={full=true,queue=q,previous=own,failed=false,requests={},byAction={},labels=labels,started={}}
 Full.started(observer,anchor)
 local function observe(fn)
  local ok,problem=pcall(fn)
  if not ok then observer.failed=observer.failed or tostring(problem)end
 end
 observer.callback=function(self,action)
  local owned=labels[action]and self.current==action and self.queue[1]==action
  -- onCompleted is a request, not the native removal boundary. Toolkit may
  -- defer it until Java drops the same action, then invoke it again from tick.
  observe(function()
   if owned and not observer.byAction[action]then
    local request={action=action,native=observer.started[action],label=labels[action]}
    observer.requests[#observer.requests+1]=request;observer.byAction[action]=request
    if not request.native then observer.failed=observer.failed or 'completion callback has no observed native start'
    elseif request.native~=action.action then observer.failed=observer.failed or 'completion callback native handle changed'end
   end
  end)
  local result=prior(self,action)
  observe(function()
   local request=observer.byAction[action]
   if owned and request and self:indexOf(action)==-1 and self.current~=action then request.released=true end
   Full.poll(observer,evidence)
  end)
  return result
 end
 q.onCompleted=observer.callback
 return observer
end
function Full.started(observer,action)
 local native=action and action.action
 if not native then observer.failed=observer.failed or 'started action has no native handle';return end
 if observer.started[action]and observer.started[action]~=native then
  observer.failed=observer.failed or 'started native handle changed';return
 end
 observer.started[action]=native
end
function Full.poll(observer,evidence)
 local q=observer.queue
 if q.onCompleted~=observer.callback then observer.failed=observer.failed or 'queue completion callback replaced';return end
 for _,request in ipairs(observer.requests)do
  if not request.completed then
   -- Require both the exact native completion request and observed absence
   -- from Lua/Java. Pending cancellation or eventual item effects cannot count.
   if not request.released or not request.native or q:indexOf(request.action)~=-1 or q.current==request.action
    or q.character:getCharacterActions():contains(request.native)then return end
   request.completed=true;evidence.completionOrder[#evidence.completionOrder+1]=request.label
  end
 end
end
function Full.finish(observer,evidence)
 local q=observer.queue
 local replaced=q.onCompleted~=observer.callback
 local ok,problem=pcall(Full.poll,observer,evidence)
 if not ok then observer.failed=observer.failed or tostring(problem)end
 if replaced or observer.failed or #evidence.startOrder~=#evidence.completionOrder then
  local requests={}
  for _,request in ipairs(observer.requests)do
   requests[#requests+1]={label=request.label,native=request.native~=nil,released=request.released==true,completed=request.completed==true,
    queued=q:indexOf(request.action)~=-1,current=q.current==request.action,
    nativePresent=request.native~=nil and q.character:getCharacterActions():contains(request.native)}
  end
  print('[FOOD_TEST] COMPLETION_OBSERVER '..require('QueueHealthEvents').encode({callbackReplaced=replaced,
   observerFailure=observer.failed or false,startOrder=evidence.startOrder,completionOrder=evidence.completionOrder,requests=requests}))
 end
 if not replaced then q.onCompleted=observer.previous end
 assert(not replaced,'full native completion callback replaced')
 assert(not observer.failed,'full native completion observation failed: '..tostring(observer.failed))
 assert(#evidence.startOrder==#evidence.completionOrder,'full native start/completion count differs')
 for index,label in ipairs(evidence.startOrder)do assert(evidence.completionOrder[index]==label,'full native completion order differs')end
end
return Full
