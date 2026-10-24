local O=require 'QueueFitnessObservation'
local F={}
function F.restorationCase(id)return id=='active-cancel-restore'or id=='pickup-cancel-restore'or id=='placement-cancel-restore'end
function F.borrowedCase(id)return id=='closed-ui-restore'or F.restorationCase(id)end
function F.activation(player)
 local rows={}
 local function scan(container)
  for i=0,container:getItems():size()-1 do
   local item=container:getItems():get(i)
   if item:canBeActivated()then rows[tostring(item:getID())]=item:isActivated()end
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer())end
  end
 end
 scan(player:getInventory())
 return rows
end
-- A start witness is independent of the later completed native borrowing receipt.
-- Resolve live endpoints by exact ID/type; Host may replace the original item replicas.
function F.observeReturnStart(state,action,seen)
 if not state or not seen or not action or seen[action]or action.character~=state.player
  or action.Type~='ISInventoryTransferAction'or getmetatable(action)~=ISInventoryTransferAction or not action.item then return end
 local player=state.player;local inventory=player:getInventory();local ids=state.ids.items
 local item=inventory:getItemById(ids.dumbbell);local bag=inventory:getItemById(ids.bag)
 if action.item:getID()~=ids.dumbbell or action.item:getFullType()~='Base.DumbBell'
  or not item or item:getID()~=ids.dumbbell or item:getFullType()~='Base.DumbBell'or item:getContainer()~=inventory
  or not bag or bag:getID()~=ids.bag or bag:getFullType()~='Base.Bag_Schoolbag'
  or action.srcContainer~=inventory or action.destContainer~=bag:getItemContainer()then return end
 seen[action]=true
 return {id=ids.dumbbell,kind='Base.DumbBell',source='root',destination=ids.bag,
  callback='ISBaseTimedAction.begin',nativeClock=O.clock()}
end
-- Exact carried/world storage witnesses; never infer a placement from queue removal.
function F.storage(player,id)
 local inventory=player:getInventory();local bag=inventory:getItemById(id);local count=0;local endpoint,world=false,false
 if bag and bag:getContainer()==inventory then count=1;endpoint='root'else bag=nil end
 local square=player:getCurrentSquare();local objects=square and square:getWorldObjects()
 for i=0,(objects and objects:size()or 0)-1 do
  local object=objects:get(i);local item=instanceof(object,'IsoWorldInventoryObject')and object:getItem()
  if item and item:getID()==id then
   count=count+1;bag=item;endpoint='world'
   world={x=square:getX(),y=square:getY(),z=square:getZ(),linked=object:getSquare()==square and item:getWorldItem()==object}
  end
 end
 local contents={}
 local function scan(container,parent)
  for i=0,container:getItems():size()-1 do
   local item=container:getItems():get(i);contents[#contents+1]={id=item:getID(),kind=item:getFullType(),container=parent}
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID())end
  end
 end
 if bag and instanceof(bag,'InventoryContainer')then scan(bag:getItemContainer(),id)end
 table.sort(contents,function(a,b)return a.id<b.id end)
 return {id=id,kind=bag and bag:getFullType()or false,favorite=bag and bag:isFavorite()or false,
  endpoint=endpoint,occurrences=count,contents=contents,world=world}
end
function F.observeRecoveryStart(state,action,seen)
 if not state or not seen or not action or seen[action]or action.character~=state.player
  or action.Type~='ISInventoryTransferAction'or getmetatable(action)~=ISInventoryTransferAction or not action.item then return end
 local bag=state.ids.items.bag;local player=state.player
 if action.item:getID()~=bag or action.item:getFullType()~='Base.Bag_Schoolbag'
  or not action.srcContainer or action.srcContainer:getType()~='floor'or action.destContainer~=player:getInventory()then return end
 local storage=F.storage(player,bag)
 if storage.endpoint~='world'or storage.occurrences~=1 or storage.kind~='Base.Bag_Schoolbag'or not storage.world.linked then return end
 seen[action]=true
 return {id=bag,kind='Base.Bag_Schoolbag',source='world',destination='root',storage=storage,inventory=F.inventory(player),
  callback='ISBaseTimedAction.begin',nativeClock=O.clock()}
end
function F.placement(player,id,callback,succeeded)
 return {callback=callback,succeeded=succeeded,nativeClock=O.clock(),storage=F.storage(player,id),inventory=F.inventory(player)}
end
local function identity(item)return item and item:getID()or false end
function F.requestedAction(action,panel,native,exercise)
 if action.Type=='ISFitnessAction'or action.toolkitFitnessStage=='request'then return action,false end
 if not native or action.Type~='ISWaitWhileGettingUp'or action.onCompleteFunc~=ISTimedActionQueue.add then return end
 local deferred=action.onCompleteArgs and action.onCompleteArgs.p1
 if deferred and deferred.Type=='ISFitnessAction'and deferred.character==panel.player and deferred.fitnessUI==panel
  and deferred.exercise==exercise and deferred.timeToExe==tonumber(panel.exeTime:getInternalText()) then return deferred,true end
end
function F.menuReady(panel,current,gate,now)
 gate.since=gate.since or now
 panel:updateButtons(current)
 gate.ticks=panel.ok.enable and (gate.ticks or 0)+1 or 0
 if gate.ticks>=2 then return 'ready' end
 if now-gate.since>=15000 then return 'expired' end
 return 'waiting'
end
function F.menuDiagnostic(panel,id,waitMilliseconds,status)
 local player=panel.player;local moodles=player:getMoodles()
 return {case=id,exercise=panel.selectedExe,waitMilliseconds=waitMilliseconds,status=status or 'waiting',enabled=panel.ok.enable==true,
  tooltip=panel.ok.tooltip and tostring(panel.ok.tooltip)or false,
  endurance=player:getStats():get(CharacterStat.ENDURANCE),enduranceMoodle=moodles:getMoodleLevel(MoodleType.ENDURANCE),
  heavyLoadMoodle=moodles:getMoodleLevel(MoodleType.HEAVY_LOAD),painMoodle=moodles:getMoodleLevel(MoodleType.PAIN),
  sittingGround=player:getVariableBoolean('sitonground'),sittingFurniture=player:isSittingOnFurniture(),
  vehicle=player:getVehicle()~=nil,climbing=player:isClimbing(),fitnessPresent=player:getFitness():getCurrentExe()~=nil}
end
function F.inventory(player)
 local rows={}
 local function scan(container,parent)
  for i=0,container:getItems():size()-1 do
   local item=container:getItems():get(i)
   rows[#rows+1]={id=item:getID(),kind=item:getFullType(),container=parent}
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID())end
  end
 end
 scan(player:getInventory(),'root');table.sort(rows,function(a,b)return a.id<b.id end)
 local worn={};for i=0,player:getWornItems():size()-1 do
  local value=player:getWornItems():get(i);worn[#worn+1]={location=tostring(value:getLocation()),id=value:getItem():getID()}
 end
 table.sort(worn,function(a,b)return a.location<b.location end)
 return {items=rows,primary=identity(player:getPrimaryHandItem()),secondary=identity(player:getSecondaryHandItem()),worn=worn}
end
local types={front='Base.BookCarpentry1',tail='Base.BookFirstAid1',bag='Base.Bag_Schoolbag',hammer='Base.Hammer',screwdriver='Base.Screwdriver',dumbbell='Base.DumbBell'}
function F.prepare(player,id,previous)
 assert(not player:getFitness():getCurrentExe(),'fitness not idle before prepare')
 if previous then
  assert(previous.verified,'unverified previous fitness fixture')
  for _,item in pairs(previous.items)do
   local live=player:getInventory():getItemById(item:getID())
   if live then
    assert(not player:isEquipped(live),'previous fixture equipment still worn/held')
    local container=live:getContainer();container:Remove(live);if isServer()then sendRemoveItemFromContainer(container,live)end
   end
  end
 end
 local state={case=id,player=player,items={},ids={case=id,items={}}}
 local order=F.restorationCase(id)and {'bag','front','tail','hammer','screwdriver','dumbbell'}or {'front','tail','bag','hammer','screwdriver','dumbbell'}
 for _,name in ipairs(order)do
  local destination=(F.borrowedCase(id)and name=='dumbbell'or F.restorationCase(id)and name=='front')and state.items.bag:getItemContainer()or player:getInventory()
  local item=assert(destination:AddItem(F.restorationCase(id)and name=='hammer'and 'Base.Torch'or types[name]),'missing fitness fixture item '..name)
  state.items[name]=item;state.ids.items[name]=item:getID()
 end
 for name,perk in pairs({front=Perks.Woodwork,tail=Perks.Doctor})do
  local book=state.items[name];player:setPerkLevelDebug(perk,0)
  local pages=name=='front'and 6 or 1
  book:setAlreadyReadPages(book:getNumberOfPages()-pages);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-pages)
 end
 player:getStats():set(CharacterStat.ENDURANCE,1);player:getStats():set(CharacterStat.FATIGUE,0)
 if F.borrowedCase(id)then
  player:setWornItem(state.items.bag:canBeEquipped(),state.items.bag)
  player:setPrimaryHandItem(state.items.hammer);player:setSecondaryHandItem(state.items.screwdriver)
 end
 if F.restorationCase(id)then
  assert(state.items.hammer:canBeActivated(),'fitness activation fixture requires native Torch')
  state.items.bag:setFavorite(true)
  state.items.hammer:setCurrentUses(state.items.hammer:getMaxUses());state.items.hammer:setActivated(true)
 end
 O.reset(player,id);O.tailID=state.ids.items.tail;O.bagID=state.ids.items.bag;O.captureStorage=F.borrowedCase(id);state.ids.before=O.clinical(player);state.ids.inventory=F.inventory(player);state.ids.activation=F.activation(player);if F.borrowedCase(id)then state.ids.storage=F.storage(player,state.ids.items.bag)end
 if isServer()then
  -- InventoryContainer serialization includes its children. Send the owning root bag
  -- once; sending the nested dumbbell again would create a duplicate replica.
  for _,item in pairs(state.items)do
   if item:getContainer()==player:getInventory()then sendAddItemToContainer(item:getContainer(),item)end
  end
  sendClothing(player,state.items.bag:canBeEquipped(),player:getWornItem(state.items.bag:canBeEquipped()));sendEquip(player)
  if F.restorationCase(id)then syncItemActivated(player,state.items.hammer)end
 end
 return state
end
function F.resolve(player,ids)
 local state={case=ids.case,player=player,ids=ids,items={}}
 for name in pairs(types)do
  local id=ids.items[name];if type(id)~='number'then return end
  local item=player:getInventory():getItemById(id);if not item or item:getID()~=id then return end
  if item:getFullType()~=(F.restorationCase(ids.case)and name=='hammer'and 'Base.Torch'or types[name])then error('fitness ID/type differs '..name)end
  state.items[name]=item
 end
 return state
end
function F.prepareReady(state)
 if not state then return false end
 local player,items=state.player,state.items
 if F.restorationCase(state.case)and (not items.hammer:isActivated()or not items.bag:isFavorite())then return false end
 return not F.borrowedCase(state.case)or (player:getPrimaryHandItem()==items.hammer
  and player:getSecondaryHandItem()==items.screwdriver and player:getWornItem(items.bag:canBeEquipped())==items.bag)
end
function F.prepareDiagnostic(player,ids,cached,id,elapsed)
 local function ref(item)return item and {id=item:getID(),kind=item:getFullType()}or false end
 local result={case=id,elapsedMilliseconds=elapsed,idsReceived=ids~=nil,cachedResolved=cached~=nil,items={},
  primary=ref(player:getPrimaryHandItem()),secondary=ref(player:getSecondaryHandItem()),
  currentExercisePresent=player:getFitness():getCurrentExe()~=nil}
 for name,kind in pairs(types)do
  local expected=ids and ids.items and ids.items[name];local live=expected and player:getInventory():getItemById(expected)
  local previous=cached and cached.items[name]
  result.items[name]={expectedID=expected or false,expectedType=F.restorationCase(id)and name=='hammer'and 'Base.Torch'or kind,
   live=ref(live),cached=ref(previous),sameReplica=live~=nil and live==previous}
  if name=='hammer'then
   result.torch={liveActivated=live and live:isActivated()or false,cachedActivated=previous and previous:isActivated()or false,
    liveUses=live and F.restorationCase(id)and live:getCurrentUses()or false,liveMaxUses=live and F.restorationCase(id)and live:getMaxUses()or false,
    primaryMatchesLive=live~=nil and player:getPrimaryHandItem()==live}
  elseif name=='bag'then
   local slot=live and live:canBeEquipped()
   result.bag={liveFavorite=live and live:isFavorite()or false,cachedFavorite=previous and previous:isFavorite()or false,
    slot=slot or false,worn=ref(slot and player:getWornItem(slot)),wornMatchesLive=live~=nil and player:getWornItem(slot)==live}
  elseif name=='screwdriver'then result.secondaryMatchesLive=live~=nil and player:getSecondaryHandItem()==live end
 end
 local queue=ISTimedActionQueue.queues[player]
 result.luaQueue=queue and #queue.queue or false;result.nativeActions=player:getCharacterActions():size()
 return result
end
function F.mutate(state)
 if state.case=='missing-dumbbell'then
  local item=assert(state.player:getInventory():getItemById(state.ids.items.dumbbell));local source=item:getContainer()
  source:Remove(item);if isServer()then sendRemoveItemFromContainer(source,item)end
  state.removed=item:getID()
 elseif state.case=='exhaustion'then state.exhausted=true;state.player:getStats():set(CharacterStat.ENDURANCE,.01)else error('unknown fitness mutation')end
 return {case=state.case,removed=state.removed or false,endurance=state.player:getStats():get(CharacterStat.ENDURANCE)}
end
function F.receipt(state)
 local player=state.player;local result=O.receipt(player)
 state.strandedCurrent=player:getFitness():getCurrentExe()
 result.case=state.case;result.inventory=F.inventory(player);result.removed=state.removed or false
 result.tailRead=player:getAlreadyReadPages(state.items.tail:getFullType())==state.items.tail:getNumberOfPages()
 result.frontRead=player:getAlreadyReadPages(state.items.front:getFullType())==state.items.front:getNumberOfPages()
 result.activation=F.activation(player);if F.borrowedCase(state.case)then result.storage=F.storage(player,state.ids.items.bag)end;result.before=state.ids.before;result.peerConnected=not isServer()
 if isServer()then
  local online=getOnlinePlayers()
  for i=0,online:size()-1 do if online:get(i):getUsername()=='client2'then result.peerConnected=true end end
 end
 return result
end
function F.recoverStranded(state)
 local selection=require 'QueueTestSelection'
 local player=state.player;local receipt=assert(state.lastReceipt,'recovery requires recorded receipt')
 assert(selection.mode=='native'and (state.case=='missing-dumbbell'or state.case=='exhaustion'),'recovery outside known native constructor cases')
 assert(state.verified and state.failedCaseRecorded and not receipt.currentExerciseCleared and #receipt.records==0,
  'recovery must follow an unchanged failed case receipt')
 assert(not O.active and #O.records==0 and not player:hasTimedActions()and player:getCharacterActions():isEmpty(),
  'cannot recover while native actions or observer are active')
 if not isServer()then
  local queue=ISTimedActionQueue.getTimedActionQueue(player)
  assert(#queue.queue==0 and not queue.current,'cannot recover a nonempty actor Lua queue')
 end
 local current=player:getFitness():getCurrentExe()
 assert(current and current==state.strandedCurrent,'stranded constructor identity changed after receipt')
 local result={case=state.case,mode='native',actor=isServer()and 'server'or 'client1',
  failedCaseRecorded=true,queueEmpty=true,nativeActions=0,observerRecords=0,observerActive=false,exactObjectMatched=true,
  before=O.clinical(player),inventoryBefore=F.inventory(player)}
 player:getFitness():setCurrentExercise(nil)
 result.cleared=not player:getFitness():getCurrentExe();result.after=O.clinical(player);result.inventoryAfter=F.inventory(player)
 assert(result.cleared,'stranded fitness constructor did not clear')
 return result
end
local function sameValues(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for key,value in pairs(a)do if not sameValues(value,b[key])then return false end end
 for key in pairs(b)do if a[key]==nil then return false end end
 return true
end
local function unchangedFailure(state)
 local JSON=require 'QueueHealthEvents'
 return state.failedRow and state.failedCaseRecorded and state.failedRow.status=='failed'
  and JSON.encode(state.failedRow)==state.failedRowEncoding
end
-- Compare real carried/world item identities, allowing native endpoint/hand differences.
function F.conservedStorage(state,inventory,storage,rootRequired)
 if storage.id~=state.ids.items.bag or storage.kind~='Base.Bag_Schoolbag'or storage.occurrences~=1
  or storage.favorite~=state.ids.storage.favorite or (rootRequired and storage.endpoint~='root')
  or (storage.endpoint~='root'and (storage.endpoint~='world'or not storage.world or not storage.world.linked))then return false end
 local expected,actual,contents={},{},{}
 for _,row in ipairs(state.ids.inventory.items)do expected[row.id]=row.kind end
 local function add(row)
  if actual[row.id]or expected[row.id]~=row.kind then return false end
  actual[row.id]=row.kind;return true
 end
 for _,row in ipairs(inventory.items)do
  if not add(row)then return false end
  if row.container==storage.id then contents[#contents+1]=row end
 end
 if storage.endpoint=='world'then
  if not add({id=storage.id,kind=storage.kind})then return false end
  for _,row in ipairs(storage.contents)do if not add(row)then return false end end
 else
  if storage.world~=false or not sameValues(contents,storage.contents)then return false end
 end
 for id in pairs(expected)do if not actual[id]then return false end end
 return true
end
function F.beginNativeIsolation(state,authority)
 local selection=require 'QueueTestSelection';local player=state.player;local row=state.failedRow
 assert(selection.mode=='native'and selection.kind=='mp'and isClient()and not isServer()
  and F.borrowedCase(state.case),'isolation outside exact native Host restoration case')
 assert(not state.isolation and unchangedFailure(state),'isolation requires unchanged published failure and no repeat')
 assert(row.id==state.case and row.receipt==state.lastReceipt and row.receipt.currentExerciseCleared==true
  and row.receipt.serverStopSettled==true and #row.receipt.records==0 and #row.receipt.violations==0
  and row.command.queueDrained==true and row.command.clientCurrentExerciseCleared==false
  and row.command.activeObserved==false and #row.command.startedOrder==0,'isolation cannot clear a started workout')
 assert(authority and authority.phase=='before'and authority.case==state.case and sameValues(authority.items,state.ids.items)
  and authority.serverIdle==true and authority.currentExerciseCleared==true and authority.records==0
  and authority.observerActive==false and authority.nativeActions==0 and authority.failedCaseRecorded==true,
  'isolation requires fresh exact server idle/zero-workout witness')
 local queue=ISTimedActionQueue.getTimedActionQueue(player)
 assert(#queue.queue==0 and not queue.current and not player:hasTimedActions()and player:getCharacterActions():isEmpty()
  and not O.active and #O.records==0,'isolation requires empty local native/Lua queues and observer')
 local current=player:getFitness():getCurrentExe()
 assert(current and current==state.requestedCurrent and current==state.strandedCurrent,'isolation constructor object changed')
 local storage=F.storage(player,state.ids.items.bag)
 assert(storage.occurrences==1 and storage.id==state.ids.items.bag and storage.kind=='Base.Bag_Schoolbag'
  and (storage.endpoint=='root'or storage.endpoint=='world'and storage.world.linked),'isolation exact storage missing or ambiguous')
 local before=O.clinical(player);local inventory=F.inventory(player);local activation=F.activation(player)
 assert(F.conservedStorage(state,inventory,storage,false)and F.conservedStorage(state,authority.inventory,authority.storage,false),'isolation lost or duplicated exact original items')
 state.isolation={status='started',since=getTimestampMs(),seen={},begins={},authoritySnapshot=authority,storage=storage,
  before=before,recoveryRequired=storage.endpoint=='world',callbacks=0}
 player:getFitness():setCurrentExercise(nil)
 local after=O.clinical(player);local inventoryAfter=F.inventory(player);local activationAfter=F.activation(player)
 assert(not player:getFitness():getCurrentExe()and sameValues(before,after)and sameValues(inventory,inventoryAfter)
  and sameValues(activation,activationAfter),'isolation clear changed measured gameplay state')
 return {case=state.case,actor='client1',mode='native',kind='mp',phase='started',failedCaseRecorded=true,failedRowUnchanged=true,
  exactObjectMatched=true,queueEmpty=true,nativeActions=0,observerActive=false,localRecords=0,cleared=true,authority=authority,
  before=before,after=after,inventoryBefore=inventory,inventoryAfter=inventoryAfter,activationBefore=activation,
  activationAfter=activationAfter,storageBefore=storage,recoveryRequired=state.isolation.recoveryRequired}
end
function F.isolationStarted(state,action)
 local isolation=state and state.isolation
 if not isolation or isolation.status~='started'or not action or action.character~=state.player or isolation.seen[action]then return end
 if action.Type=='ISFitnessAction'then isolation.invalid=true;error('isolation cannot start a native workout')end
 isolation.seen[action]=true
 isolation.begins[#isolation.begins+1]={kind=action.Type,id=action.item and action.item:getID()or false,callback='ISBaseTimedAction.begin'}
 if action.Type=='ISInventoryTransferAction'and getmetatable(action)==ISInventoryTransferAction and action.item
  and action.item:getID()==state.ids.items.bag and action.item:getFullType()=='Base.Bag_Schoolbag'
  and action.srcContainer and action.srcContainer:getType()=='floor'and action.destContainer==state.player:getInventory()then
  local storage=F.storage(state.player,state.ids.items.bag)
  assert(storage.occurrences==1 and storage.endpoint=='world'and storage.world.linked,'isolation recovery lacks exact live world bag')
  if isolation.recoveryAction then isolation.invalid=true;error('isolation native bag recovery repeated')end
  isolation.recoveryStart=assert(F.observeRecoveryStart(state,action,{}),'isolation recovery lacks real native start witness')
  isolation.recoveryAction=action
 end
end
function F.isolationBegin(state,action,phase)
 local isolation=state and state.isolation
 if not isolation or isolation.status~='started'or isolation.recoveryAction~=action or phase~='perform'then return false end
 local id=action.transactionId
 isolation.transaction=id;isolation.authority=id and id~=0 and isItemTransactionDone(id)==true and isItemTransactionRejected(id)==false
 return true
end
function F.isolationFinish(state,action,phase,succeeded)
 local isolation=state and state.isolation
 if isolation and isolation.status=='started'and isolation.recoveryAction==action and phase=='perform'then
  isolation.callbacks=isolation.callbacks+1;isolation.callbackSucceeded=succeeded==true
 end
end
function F.finishNativeIsolation(state,authority)
 local isolation=assert(state.isolation);local player=state.player;local queue=ISTimedActionQueue.getTimedActionQueue(player)
 assert(isolation.status=='started'and not isolation.invalid and unchangedFailure(state),'isolation failed row changed or phase repeated')
 assert(#queue.queue==0 and not queue.current and not player:hasTimedActions()and player:getCharacterActions():isEmpty()
  and not player:getFitness():getCurrentExe()and not O.active and #O.records==0,'isolation native cleanup not idle')
 assert(#isolation.begins>0 and (not isolation.recoveryRequired or isolation.recoveryAction and isolation.callbacks==1
  and isolation.callbackSucceeded and isolation.authority and type(isolation.transaction)=='number'and isolation.transaction~=0),
  'isolation native recovery callback/transaction not completed')
 local clinical=O.clinical(player);local inventory=F.inventory(player);local activation=F.activation(player)
 local storage=F.storage(player,state.ids.items.bag)
 assert(F.conservedStorage(state,inventory,storage,true),'isolation native cleanup lost or duplicated original equipment')
 assert(authority and authority.phase=='after'and authority.case==state.case and sameValues(authority.items,state.ids.items)
  and authority.serverIdle==true and authority.currentExerciseCleared==true and authority.records==0
  and authority.observerActive==false and authority.nativeActions==0 and authority.failedCaseRecorded==true
  and F.conservedStorage(state,authority.inventory,authority.storage,true),'isolation authority cleanup not replicated/idle/conserved')
 assert(clinical.fitnessXP==isolation.before.fitnessXP and clinical.strengthXP==isolation.before.strengthXP,'isolation replayed workout XP')
 assert(authority.clinical.fitnessXP==isolation.authoritySnapshot.clinical.fitnessXP and authority.clinical.strengthXP==isolation.authoritySnapshot.clinical.strengthXP,'isolation authority replayed XP')
 for _,group in ipairs({'regularity','stiffness'})do for key,value in pairs(isolation.authoritySnapshot.clinical[group])do
  assert(authority.clinical[group][key]<=value,'isolation authority replayed training effects')
 end end
 for _,group in ipairs({'regularity','stiffness'})do for key,value in pairs(isolation.before[group])do
  assert(clinical[group][key]<=value,'isolation replayed training effects')
 end end
 isolation.status='settled'
 return {case=state.case,actor='client1',mode='native',kind='mp',phase='settled',failedCaseRecorded=true,failedRowUnchanged=true,
  queueEmpty=true,nativeActions=0,observerActive=false,localRecords=0,currentExerciseCleared=true,
  nativeBegins=isolation.begins,recoveryRequired=isolation.recoveryRequired,recoveryCallbacks=isolation.callbacks,
  recoveryCallbackSucceeded=isolation.callbackSucceeded or false,recoveryTransaction=isolation.transaction or 0,
  recoveryAuthorityCompleted=isolation.authority or false,recoveryStart=isolation.recoveryStart or false,authority=authority,clinical=clinical,inventory=inventory,activation=activation,storage=storage}
end
function F.releaseEquipment(state)
 -- Fixture cleanup only after a recorded case and the real native queue has settled.
 local player=state.player
 player:setPrimaryHandItem(nil);player:setSecondaryHandItem(nil)
 local bag=player:getInventory():getItemById(state.ids.items.bag)
 if bag and player:isEquipped(bag)then player:removeWornItem(bag,false)end
 if isServer()then sendClothing(player,state.items.bag:canBeEquipped(),player:getWornItem(state.items.bag:canBeEquipped()));sendEquip(player)end
end
O.inventory=F.inventory;O.activation=F.activation
O.storage=function(player)return F.storage(player,O.bagID)end
O.placement=function(player,callback,succeeded)return F.placement(player,O.bagID,callback,succeeded)end
return F
