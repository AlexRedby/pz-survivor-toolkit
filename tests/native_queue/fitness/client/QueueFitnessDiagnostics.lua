-- Optional value-only observation. Never grants completion/cancellation rights.
local D={}
function D.install(config,context)
 if not config.options or config.options.fitness_diagnostics~=true then return end
 local T=PZSurvivorToolkit;local L=assert(T.ActionQueueLifecycle)
 local JSON=require 'QueueHealthEvents'
 local unpackValues=unpack or table.unpack
 local function pack(...)return {n=select('#',...),...}end
 local caseID,seen,identities,nextID,count,wire=nil,{},setmetatable({},{__mode='k'}),0,0,{}
 local function identity(value)
  if value==nil then return false end
  if not identities[value]then nextID=nextID+1;identities[value]=nextID end
  return identities[value]
 end
 local function active()
  if not context.active()then return end
  local id=context.case()
  if id~=caseID then
   caseID,seen,identities,nextID,count,wire=id,{},setmetatable({},{__mode='k'}),0,0,{}
  end
  local player=context.player();local queue=player and ISTimedActionQueue.queues[player]
  if queue and queue.character==player then return player,queue end
 end
 local function endpoint(container,player)
  if not container then return false end
  if container==player:getInventory()then return 'root'end
  local holder=type(container.getContainingItem)=='function'and container:getContainingItem()
  return {kind=container:getType(),itemId=holder and holder:getID()or false,itemType=holder and holder:getFullType()or false}
 end
 local function step(action,player)
  if not action then return false end
  local transaction=action.transactionId
  local result={ref=identity(action),kind=action.Type or false,nativeRef=identity(action.action),
   actorMatches=action.character==player,operationRef=identity(action.toolkitQueueOperation),itemId=action.item and action.item:getID()or false,
   itemType=action.item and action.item:getFullType()or false,source=endpoint(action.srcContainer,player),destination=endpoint(action.destContainer,player),
   transaction=transaction or 0,genericTransaction=action.toolkitNativeTransaction or 0,genericKind=action.toolkitNativeKind or false,
   wireState=wire[action.toolkitNativeTransaction]or false}
  if action.Type=='ISInventoryTransferAction'then
   result.itemRef=identity(action.item);result.members={}
   for _,group in ipairs(action.queueList or {})do
    for _,item in ipairs(group.items or {})do
     result.members[#result.members+1]={id=item:getID(),kind=item:getFullType(),ref=identity(item),
      sameAsAction=item==action.item,container=endpoint(item:getContainer(),player)}
    end
   end
  end
  if type(transaction)=='number'and transaction~=0 and type(isItemTransactionDone)=='function'and type(isItemTransactionRejected)=='function'then
   result.transactionDone=isItemTransactionDone(transaction)==true;result.transactionRejected=isItemTransactionRejected(transaction)==true
  end
  return result
 end
 local function snapshot(queue,player)
  local ordered={};for _,action in ipairs(queue.queue or {})do ordered[#ordered+1]=step(action,player)end
  return {ordered=ordered,current=step(queue.current,player),head=step(queue.queue and queue.queue[1],player),
   currentIsHead=queue.current~=nil and queue.current==queue.queue[1],generation=queue.toolkitOperationGeneration or 0,
   flags={cancel=not not queue.toolkitCancel,stopIntent=not not queue.toolkitStopIntent,outcomeWait=not not queue.toolkitOutcomeWait,
    groupCancel=not not queue.toolkitGroupCancel,resume=not not queue.toolkitResume,operationsInvalid=not not queue.toolkitOperationsInvalid}}
 end
 local function emit(boundary,action,extra,queue)
  local player,owned=active();queue=queue or owned
  if not player or queue~=owned or action and action.character~=player then return end
  local row={case=caseID,boundary=boundary,action=step(action,player),queue=snapshot(queue,player),detail=extra or false}
  local key=JSON.encode(row)
  if seen[key]then return end
  if count>=512 then
   if count==512 then context.emit('NATIVE_TRACE_LIMIT',{case=caseID,limit=512})end
   count=513;return
  end
  seen[key]=true;count=count+1;row.wallClock=getTimestampMs();context.emit('NATIVE_TRACE',row)
 end
 local function safe(...)pcall(emit,...)end
 assert(L.registerObserver('fitness-native-diagnostics',{
  started=function(action)safe('Lifecycle.started',action)end,
  begin=function(action,phase)
   safe('Lifecycle.begin.'..phase,action)
   local player,queue=active()
   return player~=nil and action~=nil and action.character==player and queue.current==action and queue.queue[1]==action
  end,
  finish=function(action,phase,succeeded)safe('Lifecycle.finish.'..phase,action,{succeeded=succeeded==true})end
 }),'fitness diagnostic observer unavailable')
 local original=L.allowNativeCompletion
 L.allowNativeCompletion=function(...)
  local action,native=...
  local results=pack(original(...))
  pcall(function()
   local player,queue=active();if not player or not action or action.character~=player then return end
   local candidate=wire[action.toolkitNativeTransaction]
   emit('Lifecycle.allowNativeCompletion',action,{returned=results[1]==true,returnedKind=type(results[1]),nativeArgumentRef=identity(native),
    nativeArgumentMatches=action.action==native,queueOwnsAction=queue.current==action and queue.queue[1]==action,
    operationCancelled=action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitCancelled==true or false,
    nativeDoneRead=false,callerContract='native Java completion gate; no diagnostic Done probe',
    genericAck={sealed=false,source='untrusted wire observation',candidate=candidate or false,
     transactionMatches=candidate~=nil and candidate.transaction==action.toolkitNativeTransaction,
     kindMatches=candidate~=nil and candidate.kind==action.toolkitNativeKind,
     generationMatches=candidate~=nil and candidate.generation==(queue.toolkitOperationGeneration or 0)}},queue)
  end)
  return unpackValues(results,1,results.n)
 end
 for _,name in ipairs({'resetQueue','cancelQueue'})do
  local originalQueue=assert(ISTimedActionQueue[name]);local boundary='ISTimedActionQueue.'..name
  ISTimedActionQueue[name]=function(...)
   local queue=...
   pcall(function()
    local player,owned=active()
    if player and queue==owned then emit(boundary..'.before',queue.current or queue.queue[1],nil,queue)end
   end)
   return originalQueue(...)
  end
 end
 Events.OnServerCommand.Add(function(module,command,args)
  if module~='PZSurvivorToolkitActions'or command~='State'or type(args)~='table'then return end
  pcall(function()
   local player,queue=active();if not player or args.player~=player:getOnlineID()then return end
   local function scalar(value)local kind=type(value);return (kind=='number'or kind=='boolean'or kind=='string')and value or false end
   local value={protocol=scalar(args.protocol),player=scalar(args.player),transaction=scalar(args.transaction),kind=scalar(args.kind),
    token=scalar(args.token),state=scalar(args.state),generation=queue.toolkitOperationGeneration or 0,sealed=false,source='untrusted wire observation'}
   if type(args.transaction)=='number'and args.transaction%1==0 and args.transaction>=-128 and args.transaction<=127 and args.transaction~=0 then wire[args.transaction]=value end
   emit('WIRE_STATE',queue.current or queue.queue[1],value,queue)
  end)
 end)
 return {poll=function()
  pcall(function()
   local player,queue=active();if player then emit('poll',queue.current or queue.queue[1],nil,queue)end
  end)
 end}
end
return D
