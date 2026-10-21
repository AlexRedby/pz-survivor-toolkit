-- Raw native pending-empty actions. The shared fluid suite owns preparation and authority.
require 'Fluids/ISFluidEmptyAction'
local Checks=require 'QueueScenarioChecks'
local Queue=require 'PZSurvivorToolkit/ActionQueue'
local Policy=require 'PZSurvivorToolkit/ActionQueuePolicy'
local Operations=require 'PZSurvivorToolkit/ActionQueueOperations'
local Fixture=require 'QueueFluidFixture'
local JSON=require 'QueueHealthEvents'
local Empty={}
local function current(run,index)
 local bottle=assert(run.player:getInventory():getItemById(run.ids.bottles[index].id),'empty bottle ID missing')
 assert(bottle:getFullType()=='Base.WaterBottle'and bottle:getContainer()==run.player:getInventory(),'empty bottle endpoint differs')
 return bottle
end
local function command(run,index,kind)
 local bottle=current(run,index);local fluid=bottle:getFluidContainer()
 local action=kind=='empty'and ISFluidEmptyAction:new(run.player,fluid)or ISDrinkFluidAction:new(run.player,bottle,.5)
 local row={kind=kind,id=bottle:getID(),source='root',dispatchAmount=fluid:getAmount(),dispatchWeight=bottle:getUnequippedWeight(),
  nativeDuration=action.maxTime,progress=false,cancelled=false,rawDispatched=true}
 assert(action.maxTime==action:getDuration(),'native fluid duration differs at construction')
 if kind=='empty'then
  row.capturedAmount=action.amount;row.transferRate=fluid:getTransferRate()
  row.timePerLiter=ISFluidUtil.getTransferActionTimePerLiter();row.minTime=ISFluidUtil.getMinTransferActionTime()
  local expected=action.amount*row.timePerLiter
  if row.transferRate>0 then expected=expected/row.transferRate end
  expected=math.max(row.minTime,expected)
  assert(action.amount==row.dispatchAmount and action.maxTime==expected
   and action.containerObject==fluid and action.container:getFluidContainer()==fluid,'native empty capture/duration differs')
 else row.portion=.5;assert(action.maxTime==460,'native clean-water drink duration differs')end
 ISTimedActionQueue.add(action)
 local first,last=Operations.bounds(run.queue,action)
 assert(first==last and first==run.queue:indexOf(action),'raw fluid action is not standalone')
 run.commands[#run.commands+1]=row;run.actions[#run.actions+1]={action=action,command=row,index=index,kind=kind}
 return action,row
end
function Empty.start(player,ids,state,config,queue)
 local run={player=player,ids=ids,state=state,config=config,queue=queue,commands={},actions={},dispatched=false,
  evidence={emptyStart=true,anchorRunning=false,contractsVerified=false,reordered=false,waitingCancel=false,
   moveRejected=false,denialReason='not-requested',untouchedBefore=false,nativeDurationsUnchanged=false,order={},
   drinkBCompleted=false,drinkBRemaining=-1,drinkBBoundaryFailed=false}}
 assert(#queue.queue==0 and not player:hasTimedActions(),'empty case must begin with empty native queue')
 run.anchor=command(run,1,'drink')
 return run
end
local function dispatch(run)
 local evidence=run.evidence;local dependency=run.ids.case=='fluid-empty-drink-dependency'
 assert(run.queue.current==run.anchor and run.anchor:isStarted()and run.anchor:getJobDelta()>0,'empty needs real running drink anchor')
 evidence.anchorRunning=true
 local first,second
 if dependency then
  run.drinkB=command(run,2,'drink');first=command(run,2,'empty')
 else first=command(run,2,'empty');second=command(run,3,'empty')end
 if dependency then
  local q=run.queue;local previous,raw=q.onCompleted,rawget(q,'onCompleted')
  local callback
  callback=function(self,action)
   if action==run.drinkB and self.current==action and self.queue[1]==action and self.queue[2]==first then
    local ok,amount=pcall(function()return current(run,2):getFluidContainer():getAmount()end)
    if ok then evidence.drinkBRemaining=amount;evidence.drinkBCompleted=true else evidence.drinkBBoundaryFailed=true end
   end
   return previous(self,action)
  end
  q.onCompleted=callback;run.observer={queue=q,callback=callback,previous=raw}
 end
 local before=Checks.snapshot(run.queue)
 -- Native create() may already have adjusted the running anchor for temperature/moodles.
 -- Preserve each actual pre-edit duration; constructor receipts remain unchanged.
 local durations={}
 for _,entry in ipairs(run.actions)do durations[entry.action]=entry.action.maxTime end
 if run.config.mode=='toolkit'then
  -- Inspect before editing. A later dependent-state bound can still deny a proposed edit.
  for _,entry in ipairs(run.actions)do
   if entry.action~=run.anchor then local contract=Policy.inspect(entry.action);assert(contract and contract.edit,'pending fluid contract missing')end
  end
  evidence.contractsVerified=true
  if dependency then
   Checks.deniedMove(run.queue,Queue,Policy,first,run.drinkB,false,'edit_resource_amount')
   evidence.moveRejected=true;evidence.denialReason='edit_resource_amount'
  elseif run.ids.case=='fluid-empty-cancel-waiting'then
   Checks.waitingCancel(run.queue,Queue,Policy,first,{first},{run.anchor,second})
   run.commands[2].cancelled=true;evidence.waitingCancel=true
  else
   local decision=Policy.evaluateMove(run.queue,second,first,false)
   assert(decision.allowed,'independent pending empty move denied '..tostring(decision.reason))
   assert(Queue.move(run.queue,second,first,false),'independent pending empty move failed')
   Checks.unchanged(run.queue,{run.anchor,second,first});evidence.reordered=true
  end
 else Checks.unchanged(run.queue,before)end
 for index=2,3 do
  local bottle=current(run,index)
  assert(bottle:getFluidContainer():getAmount()==run.ids.bottles[index].amount
   and bottle:getUnequippedWeight()==run.ids.bottles[index].weight,'pending edits touched fluid state')
 end
 evidence.untouchedBefore=true
 for _,entry in ipairs(run.actions)do
  assert(entry.action.maxTime==durations[entry.action],'pending edits changed native fluid duration')
  if entry.kind=='empty'then assert(entry.action.amount==entry.command.capturedAmount,'pending edits changed captured empty amount')end
 end
 evidence.nativeDurationsUnchanged=true;run.dispatched=true
end
function Empty.tick(run)
 local active=run.queue.queue[1]
 for position,entry in ipairs(run.actions)do
  if active==entry.action and active:isStarted()and active:getJobDelta()>0 and not entry.command.progress then
   assert(not entry.command.cancelled,'cancelled empty action started')
   entry.command.progress=true;run.evidence.order[#run.evidence.order+1]=position
  end
  if entry.kind=='empty'then
   local amount=current(run,entry.index):getFluidContainer():getAmount()
   assert(amount>=0 and amount<=entry.command.capturedAmount+.000001,'empty exceeded its constructor-captured amount')
  end
 end
 if not run.dispatched and active==run.anchor and run.anchor:isStarted()and run.anchor:getJobDelta()>0 then dispatch(run)end
end
local function same(expected,actual,path,differences)
 for field,value in pairs(expected)do
  local observed=actual and actual[field];local key=path..'.'..tostring(field)
  if type(value)=='table'then
   if type(observed)~='table'then differences[#differences+1]=key..':table-missing'else same(value,observed,key,differences)end
  elseif type(value)=='number'then
   local tolerance=field=='thirst'and .01 or .0001
   if type(observed)~='number'or observed~=observed or math.abs(observed-value)>tolerance then
    differences[#differences+1]=key..':'..tostring(observed)..'!='..tostring(value)
   end
  elseif observed~=value then differences[#differences+1]=key..':'..tostring(observed)..'!='..tostring(value)end
 end
end
function Empty.finish(run,receipt)
 local currentReceipt=Fixture.snapshot(run.player,run.ids);local differences={}
 if currentReceipt then same(receipt,currentReceipt,'receipt',differences)else differences={'snapshot-unavailable'}end
 if #differences>0 then
  local now=getTimestampMs()
  if not run.receiptDiagnosticAt or now-run.receiptDiagnosticAt>10000 then
   print('[FLUID_TEST] EMPTY_RECEIPT_WAIT '..JSON.encode({case=run.ids.case,differences=differences,client=currentReceipt,authority=receipt}))
   run.receiptDiagnosticAt=now
  end
  return
 end
 if run.observer then
  assert(run.observer.queue.onCompleted==run.observer.callback,'empty observer replaced')
  run.observer.queue.onCompleted=run.observer.previous;run.observer=nil
 end
 assert(run.dispatched and run.evidence.anchorRunning and not run.evidence.drinkBBoundaryFailed,'empty dispatch/boundary missing')
 local dependency=run.ids.case=='fluid-empty-drink-dependency'
 if dependency then assert(run.evidence.drinkBCompleted,'dependent native drink completion boundary missing')end
 for position,entry in ipairs(run.actions)do
  assert(entry.command.progress~=entry.command.cancelled,'native fluid progress/cancel evidence differs '..JSON.encode({
   commandIndex=position,kind=entry.kind,id=entry.command.id,progress=entry.command.progress,cancelled=entry.command.cancelled,
   observedOrder=run.evidence.order,receiptAmount=currentReceipt.bottles[entry.index].amount}))
  if entry.kind=='empty'and not entry.command.cancelled then
   assert(currentReceipt.bottles[entry.index].amount==0,'native empty did not finish at zero')
  end
 end
 local row={event='case',id=run.ids.case,status='passed',commands=run.commands,editEvidence=run.evidence,client=currentReceipt,
  waitingCancelVerified=run.evidence.waitingCancel,independentMoveVerified=run.evidence.reordered}
 for key,value in pairs(receipt)do row[key]=value end
 return row
end
return Empty
