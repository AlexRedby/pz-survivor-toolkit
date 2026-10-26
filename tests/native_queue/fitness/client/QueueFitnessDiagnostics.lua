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
 local faultStart,pendingReceipt,faultResult,releasing
 local function faultCase()
  return config.options.fitness_editor_toggles and config.options.fitness_editor_toggles[context.case()]=='off-pending-outcome'
 end
 local function faultTarget()
  if context.case()=='active-cancel-restore'then return 'ISFitnessAction','canceled'end
  if context.case()=='placement-cancel-restore'then return 'ISDropWorldItemAction','completed'end
 end
 local function fingerprint(args)
  return table.concat({tostring(args.protocol),tostring(args.player),tostring(args.transaction),tostring(args.kind),tostring(args.token),tostring(args.state)},'|')
 end
 local function observed(saved)
  return T.ActionQueueAcknowledgements.observe(saved.action,saved.record)or false
 end
 local function faultRow(saved,phase,extra,before)
  local player,queue=active()
  assert(player==saved.player and queue==saved.queue and context.case()==saved.case,'receipt fault escaped its case/actor')
  assert(saved.action.action==saved.native and fingerprint(saved.args)==saved.fingerprint,'retained receipt/native identity changed')
  local previous=before;if previous==nil then previous=observed(saved)end
  local row={case=saved.case,sequence=#saved.rows+1,phase=phase,at=phase=='retained'and saved.at or getTimestampMs(),deadline=saved.deadline,
   protocol=saved.args.protocol,player=saved.args.player,transaction=saved.args.transaction,kind=saved.args.kind,token=saved.args.token,state=saved.args.state,
   actionRef=saved.actionRef,nativeRef=saved.nativeRef,packetRef=saved.packetRef,fingerprint=saved.fingerprint,
   ackBefore=previous,ackAfter=observed(saved),
   currentMatches=queue.current==saved.action,headMatches=queue.queue[1]==saved.action,
   nativeAbsent=not player:getCharacterActions():contains(saved.native)}
  for key,value in pairs(extra or {})do row[key]=value end
  saved.rows[#saved.rows+1]=row;context.emit('RECEIPT_FAULT',row)
 end
 local function captureFaultStart(module,command,args)
  if not faultCase()or module~='PZSurvivorToolkitActions'or command~='State'or type(args)~='table'or args.state~='started'then return end
  local kind=faultTarget();local player,queue=active();local action=queue and queue.current
  if not player or not action or action~=queue.queue[1]or action.character~=player or not action.action
   or args.protocol~=1 or args.player~=player:getOnlineID()or args.kind~=kind or action.Type~=kind
   or action.toolkitNativeTransaction~=args.transaction or action.toolkitNativeKind~=args.kind then return end
  local record=T.ActionQueueAcknowledgements.capture(action)
  if not record or record.state~='started'or record.token~=args.token then return end
  if faultStart and faultStart.case==context.case()then return end
  faultStart={case=context.case(),player=player,queue=queue,action=action,native=action.action,record=record,
   protocol=args.protocol,online=args.player,transaction=args.transaction,kind=args.kind,token=args.token}
 end
 assert(L.registerObserver('fitness-native-diagnostics',{
  started=function(action)safe('Lifecycle.started',action)end,
  begin=function(action,phase)
   safe('Lifecycle.begin.'..phase,action)
   local player,queue=active()
   return player~=nil and action~=nil and action.character==player and queue.current==action and queue.queue[1]==action
  end,
  finish=function(action,phase,succeeded)safe('Lifecycle.finish.'..phase,action,{succeeded=succeeded==true})end
 }),'fitness diagnostic observer unavailable')
 -- Only delivery of a genuine terminal is reordered. Native Done and effects run normally.
 local delay=config.options.fitness_receipt_delay_ms
 local delayed={}
 if config.options.fitness_receipt_duplicate~=nil then
  assert(config.options.fitness_receipt_duplicate==true and config.kind=='mp'and delay==1000,
   'duplicate receipt fault requires explicit Host and 1000 milliseconds')
 end
 if delay~=nil then
  assert(type(delay)=='number'and delay%1==0 and delay>=50 and delay<=1000 and config.kind=='mp',
   'fitness receipt delay requires Host and 50..1000 integer milliseconds')
  L.delayNativeReceipt=function(module,command,args)
   if releasing or module~='PZSurvivorToolkitActions'or command~='State'or type(args)~='table'then return false end
   local player,queue=active();local action=queue and queue.current
   if faultCase()then
    local kind,terminal=faultTarget();local started=faultStart
    if not started or started.case~=context.case()or started.player~=player or started.queue~=queue
     or started.action.action~=started.native or args.state~=terminal or args.kind~=kind
     or args.protocol~=started.protocol or args.player~=started.online or args.transaction~=started.transaction
     or args.kind~=started.kind or args.token~=started.token or delayed[args.token]or pendingReceipt then return false end
    assert(delay==1000 and config.options.fitness_receipt_duplicate==true,'pending fault requires bounded duplicate delivery')
    local retainedAt=getTimestampMs()
    local saved={at=retainedAt,case=started.case,player=player,queue=queue,action=started.action,native=started.native,record=started.record,
     actionRef=tostring(started.action),nativeRef=tostring(started.native),packetRef=tostring(args),
     module=module,command=command,args=args,deadline=retainedAt+delay,fingerprint=fingerprint(args),rows={}}
    delayed[args.token]=true;pendingReceipt=saved;faultResult=saved
    faultRow(saved,'retained');return true
   end
   if args.state~='completed'or args.kind~='ISDropWorldItemAction'then return false end
   if not player or not action or action.Type~=args.kind or action.toolkitNativeTransaction~=args.transaction
    or args.player~=player:getOnlineID()or type(args.token)~='string'or delayed[args.token]or pendingReceipt then return false end
   delayed[args.token]=true
   pendingReceipt={module=module,command=command,args=args,action=action,deadline=getTimestampMs()+delay}
   safe('Receipt.delayed',action,{transaction=args.transaction,delayMilliseconds=delay})
   return true
  end
  Events.OnTick.Add(function()
   local saved=pendingReceipt
   if not saved or getTimestampMs()<saved.deadline then return end
   if saved.rows then
    assert(saved.observed,'genuine terminal receipt pending window was not observed before deadline')
    assert(fingerprint(saved.args)==saved.fingerprint,'retained receipt contents changed before dispatch')
    local before=observed(saved)
    releasing=true
    triggerEvent('OnServerCommand',saved.module,saved.command,saved.args)
    releasing=false
    if not saved.released then
     saved.released=true;faultRow(saved,'released',nil,before)
    else
     faultRow(saved,'duplicate',nil,before);pendingReceipt=nil
    end
   else
    pendingReceipt=nil;releasing=true
    safe('Receipt.released',saved.action,{transaction=saved.args.transaction})
    triggerEvent('OnServerCommand',saved.module,saved.command,saved.args)
    releasing=false
   end
  end)
 end
 -- Installed only by the opt-in test JAR. Values observe native manager state;
 -- this callback returns no permission and cannot replace the validity result.
 L.observeNativeValidation=function(action,native,values)
  pcall(function()
   local player,queue=active()
   if not player or not action or action.character~=player then return end
   values.nativeArgumentRef=identity(native)
   values.nativeArgumentMatches=action.action==native
   emit('Native.validityDecision',action,values,queue)
  end)
 end
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
  captureFaultStart(module,command,args)
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
 return {pendingFault=function()
  if pendingReceipt and pendingReceipt.rows and not pendingReceipt.released and not pendingReceipt.observed then
   assert(getTimestampMs()<pendingReceipt.deadline,'pending receipt window expired before fixture observation')
   return pendingReceipt.action,pendingReceipt.record,pendingReceipt.native
  end
 end,markPending=function(extra)
  local saved=assert(pendingReceipt,'no genuine retained terminal')
  assert(saved.rows and not saved.observed and not saved.released and getTimestampMs()<saved.deadline,'terminal pending boundary is no longer available')
  saved.observed=true;faultRow(saved,'pending',extra)
 end,faultComplete=function()
  if not faultCase()then return end
  local saved=assert(faultResult,'selected receipt fault never retained a genuine terminal')
  assert(saved.case==context.case()and saved.observed and saved.released and #saved.rows==4 and not pendingReceipt,'selected receipt fault did not finish hold/release/duplicate')
  return saved.rows
 end,poll=function()
  pcall(function()
   local player,queue=active();if player then emit('poll',queue.current or queue.queue[1],nil,queue)end
  end)
 end}
end
return D
