-- Test-only scalar observation. Saved native/Ack identities never leave this module.
local JSON=require 'QueueHealthEvents'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local D={}
local writer,context,roles,filenameReader,lineReader
local serial,actions,records,before=0,{},{},false
local specs={
 {role='Clothing',key='ActionQueueClothing',file='ActionQueueClothing.lua',apis={'capacityFresh','lookupSafe','inspect','bindingsTrusted','bindNative','installObserver'}},
 {role='Policy',key='ActionQueuePolicy',file='ActionQueuePolicy.lua',apis={'matchesNative'}},
 {role='Acks',key='ActionQueueAcknowledgements',file='ActionQueueAcknowledgements.lua',apis={'capture','observe','reset'}},
 {role='Lifecycle',key='ActionQueueLifecycle',file='ActionQueueLifecycle.lua',apis={'registerObserver','started','begin','finish','flush','reset'}},
 {role='Unequip',file='ISUnequipAction.lua',apis={'new','isValid','start','update','perform','stop','complete'}},
 {role='Wear',file='ISWearClothing.lua',apis={'new','isValid','start','update','perform','complete'}},
 {role='Proof',file='SourceProof.lua',apis={'closure','matches'}}}
local function number(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge and value or false end
local function stringValue(value)return type(value)=='string'and value or false end
local function enabled()return isClient()and writer and context end
local function owner(spec)if spec.role=='Unequip'then return ISUnequipAction elseif spec.role=='Wear'then return ISWearClothing elseif spec.role=='Proof'then return Proof end;return PZSurvivorToolkit[spec.key]end
local function output(point,value)
 local case,phase=context();value.point=point;value.case=value.case or case;value.fixturePhase=phase;writer(value)
end
local function protect(point,callback)
 if not enabled()then return end
 local ok,error=pcall(callback)
 if not ok then output(point,{diagnosticError=type(error)=='string'and error or'test diagnostic reader failed: '..type(error)})end
end
local function api(role,name)
 local row=roles and roles[role];local current=row and owner(row.spec)
 if row and current==row.owner and current and current[name]==row.methods[name]then return current[name]end
end
local function metadata()
 local out={}
 for _,spec in ipairs(specs)do
  local saved=roles[spec.role];local current=owner(spec)
  for _,name in ipairs(spec.apis)do
   local callback=current and current[name];local file,line=false,false;local origin=api('Proof','closure')
   if type(callback)=='function'and getFilenameOfClosure==filenameReader and getFirstLineOfClosure==lineReader then
    local ok,path=pcall(filenameReader,callback);if ok and type(path)=='string'then file=path:gsub('\\','/'):match('([^/]+)$')or false end
    local valid,value=pcall(lineReader,callback);if valid then line=number(value)end
   end
   out[#out+1]={role=spec.role,api=name,file=file,line=line,ownerSame=current==saved.owner,readerSame=callback==saved.methods[name],readerPresent=type(callback)=='function',
    closureMatch=type(callback)=='function'and origin and origin(callback,spec.file)==true or false}
  end
 end
 return out
end
local function physical(action)
 local actor,item=action.character,action.item
 if not actor or not item or not instanceof(actor,'IsoPlayer')then return{ownActor=actor==getPlayer(),actorPlayer=false,itemPresent=item~=nil,nativeAllocated=action.action~=nil}end
 local queue=ISTimedActionQueue.queues[actor];local root=actor:getInventory()
 local clothing=instanceof(item,'Clothing');local slot=clothing and item:getBodyLocation()or nil;local worn=slot and actor:getWornItem(slot)
 return{ownActor=actor==getPlayer(),actorCanonical=getSpecificPlayer(actor:getPlayerNum())==actor,actorAlive=not actor:isDead(),
  player=number(actor:getPlayerNum()),online=number(actor:getOnlineID()),item=number(item:getID()),type=stringValue(item:getFullType()),class=getClassSimpleName(item),
  rootOwned=item:getContainer()==root,canonicalRoot=root:getItemWithID(item:getID())==item,worn=actor:getWornItems():contains(item)==true,
  primary=actor:getPrimaryHandItem()==item,secondary=actor:getSecondaryHandItem()==item,slot=slot and tostring(slot)or false,
  slotId=worn and number(worn:getID())or false,slotSame=worn==item,attachedSlot=number(item:getAttachedSlot()),
  wetness=clothing and number(item:getWetness())or false,actualWeight=number(item:getActualWeight()),
  unequippedWeight=number(item:getUnequippedWeight()),equippedWeight=number(item:getEquippedWeight()),inventoryWeight=number(actor:getInventoryWeight()),
  nativeAllocated=action.action~=nil,nativeClass=action.action and getClassSimpleName(action.action)or false,
  queueCanonical=queue~=nil and queue.character==actor,current=queue and queue.current==action or false,index=queue and number(queue:indexOf(action))or false,
  queueSize=queue and #queue.queue or false,generation=queue and number(queue.toolkitOperationGeneration or 0)or false,
  transaction=number(action.toolkitNativeTransaction),kind=stringValue(action.toolkitNativeKind),
  maxTime=number(action.maxTime),maxTimeInit=number(action.maxTimeInit),animSpeed=number(action.animSpeed),fromHotbar=action.fromHotbar==true,
  reason=stringValue(action.reason),reasonType=type(action.reason),clothingAction=action.clothingAction==true,ignoreHandsWounds=action.ignoreHandsWounds==true,
  stopOnAim=action.stopOnAim==true,stopOnWalk=action.stopOnWalk==true,stopOnRun=action.stopOnRun==true}
end
local function identify(action)
 if not actions[action]then serial=serial+1;actions[action]=serial end
 return actions[action]
end
local function classify(action)
 local matches,lookup,inspect=api('Policy','matchesNative'),api('Clothing','lookupSafe'),api('Clothing','inspect')
 local contract=inspect and inspect(action)
 return{matchesNative=matches and matches(action)==true or false,lookupSafe=lookup and lookup(action)==true or false,
  inspectPresent=contract~=nil,pendingEditEligible=contract and type(contract.edit)=='table'and contract.edit.complete==true or false,
  pendingCapacity=contract and contract.edit and stringValue(contract.edit.capacity)or false}
end
local function fresh()
 local callback=api('Clothing','capacityFresh');local queue=ISTimedActionQueue.getTimedActionQueue(getPlayer())
 if not callback then return{fresh=false,reason=roles and'diagnostic:reader-changed'or'diagnostic:not-ready'}end
 local value,reason=callback(queue)
 return{fresh=value==true,reason=stringValue(reason),reasonPresent=type(reason)=='string'}
end
function D.configure(emit,where)writer,context=emit,where end
function D.setup()
 protect('setup',function()
  filenameReader,lineReader=getFilenameOfClosure,getFirstLineOfClosure;roles={}
  for _,spec in ipairs(specs)do local current=owner(spec);local row={spec=spec,owner=current,methods={}}
   for _,name in ipairs(spec.apis)do row.methods[name]=current and current[name]end;roles[spec.role]=row
  end
  local value=fresh();value.roles=metadata();value.metadataReadersPresent=type(filenameReader)=='function'and type(lineReader)=='function'
  value.sourceChecks={
   {role='Lifecycle',file='ActionQueueLifecycle.lua',checksumMatch=Proof.matches('media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua',573091080,'PZSurvivorToolkit',true)==true},
   {role='Acks',file='ActionQueueAcknowledgements.lua',checksumMatch=Proof.matches('media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua',4157001195,'PZSurvivorToolkit',true)==true}}
  output('setup',value)
 end)
end
function D.freshness(point)
 protect(point,function()local value=fresh();value.roles=metadata();output(point,value)end)
end
function D.before(action,producer)
 if before or not action or action.Type~='ISUnequipAction'then return end
 protect('before-first-unequip',function()before=true;local value=fresh();value.action=identify(action);value.producerCaptured=producer==true;value.physical=physical(action);value.classification=classify(action);output('before-first-unequip',value)end)
end
function D.started(action,tracked)
 if not action or(action.Type~='ISUnequipAction'and action.Type~='ISWearClothing')then return end
 protect('unequip-start',function()
  if action.Type=='ISUnequipAction'then D.before(action)end;output(action.Type=='ISWearClothing'and'wear-start'or'unequip-start',{action=identify(action),tracked=tracked==true,physical=physical(action),classification=classify(action)})
 end)
end
local function observe(record,point,force)
 local action=record.action;local callback=api('Acks','observe');local state=callback and record.receipt and callback(action,record.receipt)or nil
 local p=physical(action);local queue=ISTimedActionQueue.queues[action.character]
 local value={case=record.case,action=identify(action),boundary=record.phase,capturePresent=record.receipt~=nil,
  ackState=stringValue(state),recordState=record.receipt and stringValue(record.receipt.state)or false,observeReaderSame=callback~=nil,
  captureGeneration=record.generation,receiptGeneration=record.receipt and number(record.receipt.generation)or false,
  receiptTransaction=record.receipt and number(record.receipt.transaction)or false,receiptKind=record.receipt and stringValue(record.receipt.kind)or false,
  nativeSame=action.action==record.native,actorSame=action.character==record.actor,itemSame=action.item==record.item,queueSame=queue==record.queue,
  rootSame=action.character:getInventory()==record.root,physical=p}
 local signature=JSON.encode({value.ackState,value.recordState,value.observeReaderSame,value.nativeSame,value.actorSame,value.itemSame,value.queueSame,value.rootSame,
  p.generation,p.transaction,p.kind,p.canonicalRoot,p.rootOwned,p.worn,p.primary,p.secondary,p.slotId,p.current})
 if force or record.signature~=signature then record.signature=signature;output(point,value)end
end
function D.begin(action,phase)
 if not action or(action.Type~='ISUnequipAction'and action.Type~='ISWearClothing')or action.character~=getPlayer()or(phase~='perform'and phase~='stop')then return end
 protect('receipt-capture',function()
  local capture=api('Acks','capture');local actor=action.character;local queue=ISTimedActionQueue.queues[actor];local case=context()
  local record={action=action,actor=actor,item=action.item,queue=queue,root=actor:getInventory(),native=action.action,
   generation=queue and number(queue.toolkitOperationGeneration or 0)or false,phase=phase,case=case,receipt=capture and capture(action)or nil}
  records[#records+1]=record;observe(record,'receipt-capture',true)
 end)
 -- Do not accept a Lifecycle phase or create production phaseEntries for diagnostics.
end
function D.finish(action,phase,succeeded)
 if not action or(action.Type~='ISUnequipAction'and action.Type~='ISWearClothing')then return end
 protect('receipt-finish',function()
  for _,record in ipairs(records)do if record.action==action and record.phase==phase then observe(record,succeeded and'receipt-finish'or'receipt-failed',true)end end
 end)
end
function D.receipt(action)
 if not isClient()then return{client=false,capturePresent=false,ackState=false}end
 local result={client=true,capturePresent=false,ackState=false}
 protect('receipt-summary',function()
  for _,record in ipairs(records)do if record.action==action and record.phase=='perform'then
   local reader=api('Acks','observe');local status=reader and record.receipt and reader(action,record.receipt);local p=physical(action)
   result={client=true,capturePresent=record.receipt~=nil,ackState=stringValue(status),generation=record.generation,
    transaction=number(action.toolkitNativeTransaction),kind=stringValue(action.toolkitNativeKind),
    nativeSame=action.action==record.native,itemSame=action.item==record.item,actorSame=action.character==record.actor,
    rootSame=action.character:getInventory()==record.root,queueSame=ISTimedActionQueue.queues[action.character]==record.queue,
    canonicalRoot=p.canonicalRoot,rootOwned=p.rootOwned,worn=p.worn,slotSame=p.slotSame,slotId=p.slotId}
  end end
 end)
 return result
end
function D.poll()
 protect('receipt-poll',function()for _,record in ipairs(records)do observe(record,'receipt-poll',false)end end)
end
function D.finalWait()
 protect('final-wait',function()
  local value=fresh();local signature=JSON.encode(value)
  if D.finalSignature~=signature then D.finalSignature=signature;value.roles=metadata();output('final-wait',value)
   for _,record in ipairs(records)do observe(record,'final-receipt',true)end
  end
 end)
end
return D
