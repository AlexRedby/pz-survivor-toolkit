require 'ISUI/ISFitnessUI'
require 'Definitions/FitnessExercises'
require 'TimedActions/ISFitnessAction'
require 'TimedActions/ISWearClothing'
require 'TimedActions/ISWaitWhileGettingUp'
require 'TimedActions/ISInventoryTransferUtil'
local Toolkit=PZSurvivorToolkit
local Fitness={}
Toolkit.ActionQueueFitness=Fitness
local Ops,Definitions=Toolkit.ActionQueueOperations,Toolkit.ActionQueueDefinitions
local Settlement=require 'PZSurvivorToolkit/ActionQueueSettlement'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Equipment=require 'PZSurvivorToolkit/FitnessEquipment'
Equipment.install(ISFitnessUI)
local records={}
local native,classes,exercises={},{},{}
local class=ISFitnessAction
local ui=ISFitnessUI
local click=ui.onClick
local activate=ISInventoryPaneContextMenu.onActivateItem
local trusted=Proof.matches('media/lua/shared/TimedActions/ISFitnessAction.lua',1524582630)
 and Proof.matches('media/lua/client/ISUI/ISFitnessUI.lua',219506148)
 and Proof.matches('media/lua/shared/Definitions/FitnessExercises.lua',4259913378)
 and Proof.closure(click,'ISFitnessUI.lua')
 and Proof.closure(activate,'ISInventoryPaneContextMenu.lua')
for name,callback in pairs(class) do
 if type(callback)=='function' then
  native[name]=callback
  if name~='derive' then trusted=trusted and Proof.closure(callback,'ISFitnessAction.lua') end
 end
end
local childSources={ISEquipWeaponAction=1814269902,ISUnequipAction=229487418,ISWearClothing=762204314,
 ISInventoryTransferAction=3843678860,ISWaitWhileGettingUp=1725489935,ISDropWorldItemAction=2862163534}
local function approvedChange(kind,name)
 local carts=Toolkit.ActionQueueCarts
 if kind=='ISInventoryTransferAction' and name=='checkQueueList' then
  local intent=Toolkit.ActionQueueTidyIntent
  return intent and intent.isQueueObserver(classes[kind].methods[name],ISInventoryTransferAction[name])
 end
 if kind=='ISInventoryTransferAction' and (name=='new' or name=='perform' or name=='transferItem') then
  return carts and carts.isTransferConstructor(classes[kind].methods.new) and carts.isTransferConstructor(ISInventoryTransferAction.new)
 elseif kind=='ISUnequipAction' and (name=='new' or name=='complete') then
  return carts and carts.isUnequipConstructor(classes[kind].methods.new) and carts.isUnequipConstructor(ISUnequipAction.new)
 end
 return false
end
for _,kind in ipairs({'ISFitnessAction','ISEquipWeaponAction','ISUnequipAction','ISWearClothing','ISInventoryTransferAction','ISWaitWhileGettingUp','ISDropWorldItemAction'}) do
 local owner=_G[kind];local methods={}
 if childSources[kind] then
  trusted=trusted and Proof.matches('media/lua/'..(kind=='ISInventoryTransferAction' and 'client' or 'shared')..'/TimedActions/'..kind..'.lua',childSources[kind])
 end
 for name,callback in pairs(owner) do
  if type(callback)=='function' then
   methods[name]=callback
   -- Transfers already have source-approved Better Containers, P4 and Manifest hooks in Policy.
   if kind~='ISFitnessAction' and kind~='ISInventoryTransferAction' and name~='derive' and not Proof.closure(callback,kind..'.lua') then
    local carts=Toolkit.ActionQueueCarts
    local approved=kind=='ISUnequipAction' and (name=='new' or name=='complete') and carts and carts.isUnequipConstructor(owner.new)
    trusted=trusted and approved==true
   end
  end
 end
 for _,name in ipairs({'new','isValid','isValidStart','waitToStart','start','update','stop','perform','complete','forceCancel','forceStop'}) do methods[name]=owner[name] end
 classes[kind]={owner=owner,methods=methods}
end
for kind,data in pairs(FitnessExercises.exercisesType) do
 local copy={};for key,value in pairs(data) do copy[key]=value end
 exercises[kind]={data=data,fields=copy}
end
local function enabled() return Toolkit.Settings.actionQueue() end
local function now() return getGameTime():getCalender():getTimeInMillis() end
local function identity(item)
 if not item then return false end
 return {id=item:getID(),kind=item:getFullType(),active=item:canBeActivated() and item:isActivated() or false}
end
local function same(item,ref) return item and ref and item:getID()==ref.id and item:getFullType()==ref.kind end
local function find(container,ref)
 if not ref then return end
 local items=container:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  if same(item,ref) then return item end
  if instanceof(item,'InventoryContainer') then local found=find(item:getInventory(),ref);if found then return found end end
 end
end
local function first(container,kind)
 local items=container:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  if item:getFullType()==kind then return item end
  if instanceof(item,'InventoryContainer') then local found=first(item:getInventory(),kind);if found then return found end end
 end
end
local function root(player,ref)
 local item=find(player:getInventory(),ref)
 return item and item:getContainer()==player:getInventory() and item or nil
end
local function unchanged()
 if not trusted or ISFitnessAction~=class or ISFitnessUI~=ui or ui.onClick~=Fitness.onClick
  or ISInventoryPaneContextMenu.onActivateItem~=activate then return false end
 for kind,snapshot in pairs(classes) do
  if _G[kind]~=snapshot.owner then return false end
  for name,callback in pairs(snapshot.methods) do
   if snapshot.owner[name]~=callback and not approvedChange(kind,name) then return false end
  end
 end
 for kind,entry in pairs(exercises) do
  if FitnessExercises.exercisesType[kind]~=entry.data then return false end
  for key,value in pairs(entry.fields) do if entry.data[key]~=value then return false end end
  for key in pairs(entry.data) do if entry.fields[key]==nil then return false end end
 end
 return true
end
local function validRecord(action)
 local record=records[action]
 if not record or action.character~=record.saved.player or not unchanged()
  or action.toolkitFitnessExercise~=record.saved.exercise or action.toolkitFitnessMinutes~=record.saved.minutes
  or action.toolkitFitnessStage~=record.stage then return end
 if action.Type=='ISQueueActionsAction' then
  if not Ops.isCommand(action) then return end
 elseif not classes[action.Type] or getmetatable(action)~=classes[action.Type].owner then return
 else
  local bulk=Toolkit.BulkActions
  local guarded=action.Type=='ISInventoryTransferAction' and bulk and bulk.isGuardedTransfer
   and bulk.isGuardedTransfer(action,classes[action.Type].methods.stop)
  for name,callback in pairs(classes[action.Type].methods) do
   if action[name]~=callback and not (name=='stop' and guarded) and (action[name]~=classes[action.Type].owner[name]
    or not approvedChange(action.Type,name)) then return end
  end
  if action.onStartFunc or action.onCancelFunc or action.retriggerLastAction or action.onFailFunc or action.additionalTest
   or action.onCompleteFunc and not (guarded and action.onCompleteFunc==action.toolkitQueueSafeOnComplete) then return end
  if record.item and not same(action.item,record.item) then return end
  if action.Type=='ISInventoryTransferAction' and not Toolkit.ActionQueuePolicy.matchesNative(action) then return end
  if action.Type=='ISFitnessAction' and (action.exercise~=record.saved.exercise or action.timeToExe~=record.saved.minutes
   or action.exeData~=record.saved.data or action.exeDataType~=record.saved.exercise) then return end
 end
 return record
end
function Fitness.isManaged(action) return validRecord(action)~=nil end
local function tag(action,saved,stage)
 action.toolkitFitnessExercise,action.toolkitFitnessMinutes,action.toolkitFitnessStage=saved.exercise,saved.minutes,stage
 records[action]={saved=saved,stage=stage,item=action.item and identity(action.item)}
 return action
end
local function add(action,saved,stage)
 local queue=ISTimedActionQueue.queues[saved.player]
 local parent=queue and queue.current
 ISTimedActionQueue.add(tag(action,saved,stage))
 Settlement.track(action,stage=='preparation' and 'prepare' or stage=='cleanup' and 'cleanup' or 'body')
 if stage=='cleanup' and parent then Settlement.inheritCleanup(action,parent) end
 return action
end
local function command(player,callback,saved,stage)
 return tag(Ops.command(player,callback,saved),saved,stage)
end
local function available(player)
 return not player:isDead() and not player:getVehicle() and not player:isClimbing()
  and player:getMoodles():getMoodleLevel(MoodleType.ENDURANCE)<=ISFitnessUI.enduranceLevelThreshold
  and player:getMoodles():getMoodleLevel(MoodleType.HEAVY_LOAD)<=2
  and player:getMoodles():getMoodleLevel(MoodleType.PAIN)<=3
end
local function equipmentReady(saved)
 local player=saved.player
 if saved.item then
  local item=root(player,saved.item)
  if not item or not player:isHandItem(item) then return false end
  if saved.data.prop=='twohands' and (player:getPrimaryHandItem()~=item or player:getSecondaryHandItem()~=item) then return false end
 elseif player:getPrimaryHandItem() or player:getSecondaryHandItem() then return false end
 return true
end
local function startExercise(player,saved)
 if not enabled() or not unchanged() or saved.unavailable or not available(player) or not equipmentReady(saved)
  or not Equipment.stowed(player,saved.storage or {}) then return end
 local action=class:new(player,saved.exercise,saved.minutes,saved.data,saved.exercise)
 saved.action=action
 add(action,saved,'exercise')
 records[action].fitnessState=action.fitness:getCurrentExe()
end
local function activation(player,saved)
 if not unchanged() then return end
 local seen={}
 for _,ref in pairs(saved.restoreHands or {}) do
  local item=root(player,ref)
  if item and not seen[item] and item:canBeActivated() then
   seen[item]=true
   if item:isActivated()~=ref.active then activate(item,player:getPlayerNum()) end
  end
 end
end
-- A captured preparation is intent until its exact native effect earns the handle.
local function preparation(action,saved,kind,storage)
 add(action,saved,'preparation')
 if storage then records[action].storage=storage end
 local ref=identity(action.item)
 local mode={primary=action.primary,twoHands=action.twoHands,source=action.srcContainer,destination=action.destContainer,
  square=action.sq,x=action.xoffset,y=action.yoffset,z=action.zoffset,rotation=action.rotation,
  place=action.isPlaceItem,multiple=action.isMultiple}
 local entry={kind=kind,ref=ref,storage=storage}
 entry.handle=Settlement.observePreparation(action,{
  guard=function(value)
   return validRecord(value)~=nil and same(value.item,ref) and value.primary==mode.primary
    and value.twoHands==mode.twoHands and value.srcContainer==mode.source and value.destContainer==mode.destination
    and value.sq==mode.square and value.xoffset==mode.x and value.yoffset==mode.y and value.zoffset==mode.z
    and value.rotation==mode.rotation and value.isPlaceItem==mode.place and value.isMultiple==mode.multiple
  end,
  capture=function(value)
   local player=value.character;local item=root(player,ref)
   if kind=='pickup' then
    item=find(player:getInventory(),ref)
    return item and item:getContainer()==mode.source and {source=mode.source} or nil
   end
   if not item then return end
   if kind=='drop' then
    return player:getCurrentSquare()==mode.square and {square=mode.square} or nil
   end
   if kind=='unequip' then
    local before={primary=player:getPrimaryHandItem()==item,secondary=player:getSecondaryHandItem()==item,
     worn=player:getWornItems():contains(item)}
    local expectedPrimary=saved.before.hands.primary and same(item,saved.before.hands.primary) or false
    local expectedSecondary=saved.before.hands.secondary and same(item,saved.before.hands.secondary) or false
    local expectedWorn=false
    for _,bag in ipairs(saved.before.bags) do if same(item,bag) then expectedWorn=true end end
    if before.primary~=expectedPrimary or before.secondary~=expectedSecondary or before.worn~=expectedWorn then return end
    return (before.primary or before.secondary or before.worn) and before or nil
   end
   if mode.twoHands and player:getPrimaryHandItem()==item and player:getSecondaryHandItem()==item
    or not mode.twoHands and (mode.primary and player:getPrimaryHandItem() or player:getSecondaryHandItem())==item then return end
   if player:getPrimaryHandItem() or player:getSecondaryHandItem() then return end
   return {primary=mode.primary,twoHands=mode.twoHands}
  end,
  observed=function(value,before)
   local player=value.character;local item=root(player,ref)
   if kind=='drop' then
    local grounded=Equipment.ground(player,ref)
    return not item and grounded~=nil and grounded:getWorldItem():getSquare()==before.square
   end
   if not item then return false end
   if kind=='pickup' then return item:getContainer()==mode.destination end
   if kind=='unequip' then
    return (not before.primary or player:getPrimaryHandItem()~=item)
     and (not before.secondary or player:getSecondaryHandItem()~=item)
     and (not before.worn or not player:getWornItems():contains(item))
   end
   return mode.twoHands and player:getPrimaryHandItem()==item and player:getSecondaryHandItem()==item
    or not mode.twoHands and (mode.primary and player:getPrimaryHandItem() or player:getSecondaryHandItem())==item
  end,
 })
 saved.preparations[#saved.preparations+1]=entry
 if entry.handle then saved.handles[#saved.handles+1]=entry.handle end
 return entry
end
local function restore(player,saved)
 if not saved.before or saved.restored or not unchanged() or player:isDead() then return end
 saved.restored=true
 local hands,bags,prop={}, {}, false
 for _,entry in ipairs(saved.preparations) do
  if Settlement.earned(entry.handle) then
   if entry.kind=='unequip' then
    for slot,ref in pairs(saved.before.hands) do if ref and entry.ref.id==ref.id and entry.ref.kind==ref.kind then hands[slot]=ref end end
    for _,ref in ipairs(saved.before.bags) do if entry.ref.id==ref.id and entry.ref.kind==ref.kind then bags[#bags+1]=ref end end
   elseif entry.kind=='equip' then prop=true end
  end
 end
 saved.restoreHands=hands
 local primary,secondary=root(player,hands.primary),root(player,hands.secondary)
 if prop then
  local item=root(player,saved.item)
  if item and player:isHandItem(item) and (item~=primary and item~=secondary
   or player:getPrimaryHandItem()==item and not primary or player:getSecondaryHandItem()==item and not secondary) then
   add(ISUnequipAction:new(player,item,50),saved,'cleanup')
  end
 end
 if primary then add(ISEquipWeaponAction:new(player,primary,50,true,primary==secondary),saved,'cleanup') end
 if secondary and secondary~=primary then add(ISEquipWeaponAction:new(player,secondary,50,false,false),saved,'cleanup') end
 for _,ref in ipairs(bags) do
  local item=root(player,ref)
  if item and Equipment.canWear(player,ref) and not player:getWornItems():contains(item) then add(ISWearClothing:new(player,item),saved,'cleanup') end
 end
 -- Native re-equipping may autoactivate an originally off item.
 if primary or secondary then add(command(player,activation,saved,'cleanup'),saved,'cleanup') end
 for _,entry in ipairs(saved.preparations) do
  if entry.kind=='pickup' and Settlement.earned(entry.handle) then
   local action=Settlement.enqueueBorrowedReturn(entry.handle)
   if action then tag(action,saved,'cleanup');Settlement.track(action,'cleanup') end
  end
 end
end
local function cleanup(player,saved)
 if not saved.before or saved.cleanupQueued or not unchanged() or player:isDead() then return end
 saved.cleanupQueued=true
 local storage={}
 for _,entry in ipairs(saved.preparations) do
  if entry.kind=='drop' and Settlement.earned(entry.handle) then storage[#storage+1]=entry.storage end
 end
 local parent=ISTimedActionQueue.queues[player].current
 Equipment.pickups(player,storage,function(action,ref)
  add(action,saved,'cleanup');records[action].storage=ref
  Settlement.observeCleanupTransfer(action,parent)
 end)
 add(command(player,restore,saved,'cleanup'),saved,'cleanup')
end
local function prepare(player,saved)
 if not enabled() or not unchanged() or not available(player) then return end
 local item=saved.item and find(player:getInventory(),saved.item)
 if saved.item and not item then return end
 local primary,secondary=player:getPrimaryHandItem(),player:getSecondaryHandItem()
 if primary and primary:isForceDropHeavyItem() or secondary and secondary:isForceDropHeavyItem() then return end
 saved.storage=Equipment.capture(player)
 local drops=Equipment.drops(player,saved.storage)
 if not drops then return end
 if player:isSitting() then add(ISWaitWhileGettingUp:new(player),saved,'preparation') end
 saved.before={hands={primary=identity(primary),secondary=identity(secondary)},bags={}}
 saved.preparations,saved.handles={},{}
 if item and item:getContainer()~=player:getInventory() then
  -- Fetch the prop before removing its carrier's weight reduction or grounding it.
  preparation(ISInventoryTransferUtil.newInventoryTransferAction(player,item,item:getContainer(),player:getInventory()),saved,'pickup')
 end
 local seen={}
 local function unequip(value)
  if value and not seen[value] then seen[value]=true;preparation(ISUnequipAction:new(player,value,50),saved,'unequip') end
 end
 unequip(primary);unequip(secondary)
 local worn=player:getWornItems()
 for i=0,worn:size()-1 do
  local value=worn:get(i):getItem()
  if instanceof(value,'InventoryContainer') then
   local ref=identity(value);ref.slot=worn:get(i):getLocation()
   saved.before.bags[#saved.before.bags+1]=ref;unequip(value)
  end
 end
 for i,drop in ipairs(drops) do preparation(drop,saved,'drop',saved.storage[i]) end
 if item then
  preparation(ISEquipWeaponAction:new(player,item,50,true,saved.data.prop=='twohands'),saved,'equip')
 end
 add(command(player,startExercise,saved,'preparation'),saved,'preparation')
 local restoration=add(command(player,cleanup,saved,'cleanup'),saved,'cleanup')
 Settlement.cleanupAfter(restoration,saved.handles)
end
function Fitness.onClick(panel,button,...)
 if not enabled() or not unchanged() or not Settlement.preparationAvailable() then return click(panel,button,...) end
 if button.internal=='OK' then
  local data=exercises[panel.selectedExe]
  local minutes=tonumber(panel.exeTime:getInternalText())
  if not data or panel.exeData~=data.data or not minutes or minutes~=minutes or minutes<10 or minutes>60 then return end
  local item=data.data.item and first(panel.player:getInventory(),data.data.item)
  if data.data.item and not item then return end
  local saved={player=panel.player,exercise=panel.selectedExe,minutes=minutes,data=data.data,item=identity(item)}
  -- Leave the window out of the operation: its update/close must not own required cleanup.
  return Ops.run(function() return add(command(panel.player,prepare,saved,'request'),saved,'request') end)
 elseif button.internal=='CANCEL' then
  local queue=ISTimedActionQueue.getTimedActionQueue(panel.player)
  if Fitness.isManaged(queue.current) then return Toolkit.ActionQueue.cancelOperation(queue,queue.current) end
 end
 return click(panel,button,...)
end
ui.onClick=Fitness.onClick
local function preserve(action,pendingStart)
 local record=validRecord(action)
 if not record or action.Type~='ISFitnessAction' or not enabled() then return false end
 local player=action.character;local queue=ISTimedActionQueue.queues[player]
 if not queue or queue.current~=action or queue.queue[1]~=action or player:isDead()
  or player:isPlayerMoving() or player:pressedMovement(false) then return false end
 if queue.toolkitCancel==action then return true end
 local receipt=Toolkit.ActionQueueAcknowledgements.capture(action)
 if isClient() and not receipt and not pendingStart then return false end
 queue.toolkitCancel=action
 queue.toolkitStopIntent={reason='fitness-ended',scope='action'}
 if receipt or isClient() then
  queue.toolkitOutcomeWait={acknowledgement=receipt,generic=true,deadline=getTimestampMs()+30000}
  if not receipt then
   queue.toolkitOutcomeWait.pendingStart={native=action.action,transaction=action.toolkitNativeTransaction,
    kind=action.toolkitNativeKind,generation=queue.toolkitOperationGeneration or 0}
  end
 end
 return true
end
function Fitness.canPreserveStop(action) return preserve(action) end
class.start=function(action)
 if validRecord(action) then
  action.startMS=now();action.endMS=action.startMS+action.timeToExe*60000
  records[action].started=true
 end
 return native.start(action)
end
class.forceStop=function(action)
 -- Stop native repetitions immediately. A late started/terminal receipt gates
 -- continuation, never the outgoing native stop request.
 if preserve(action,true) then records[action].stopping=isClient() end
 return native.forceStop(action)
end

local forceCancel=class.forceCancel
class.forceCancel=function(action)
 local record=validRecord(action)
 if record and not record.started and record.saved.action==action
  and action.fitness:getCurrentExe()==record.fitnessState then action.fitness:setCurrentExercise(nil) end
 return forceCancel(action)
end
classes.ISFitnessAction.methods.forceCancel=class.forceCancel
classes.ISFitnessAction.methods.start=class.start
classes.ISFitnessAction.methods.forceStop=class.forceStop
function Fitness.canSkip(action)
 local record=validRecord(action)
 if not record or record.started or (action.action and action:isStarted()) then return false end
 if record.storage then
  if action.Type=='ISDropWorldItemAction' then
   if not Equipment.canDrop(action.character,record.storage,action.sq) then record.saved.unavailable=true;return true end
  elseif action.Type=='ISInventoryTransferAction' then
   return not Equipment.canWear(action.character,record.storage)
    or Equipment.ground(action.character,record.storage)~=action.item
  end
 end
 if record.item and not find(action.character:getInventory(),record.item) then
  if record.stage~='cleanup' then record.saved.unavailable=true end
  return true
 end
 if action.Type=='ISFitnessAction' then return not available(action.character) or not equipmentReady(record.saved) end
 if action.Type=='ISUnequipAction' and not action.character:isHandItem(action.item)
  and not action.character:getWornItems():contains(action.item) then return true end
 return false
end
function Fitness.skipUnavailable(queue)
 local action=queue.queue[2]
 while action and Fitness.canSkip(action) do
  table.remove(queue.queue,2);action:forceCancel();action=queue.queue[2]
 end
end
local function contract(action)
 local record=validRecord(action);if not record then return end
 local saved=record.saved
 local result={items={},itemTypes={},targets={},knownInputs=true,hands=saved.before and saved.player or nil,cancelWaiting=record.stage~='cleanup',
  preparation=record.stage~='request',preparationFinish=true,deferred=action.Type=='ISQueueActionsAction',interrupt='finish-step'}
 if saved.item then result.items[saved.item.id]=true;result.itemTypes[saved.item.kind]=true end
 for _,ref in pairs(saved.before and saved.before.hands or {}) do if ref then result.items[ref.id]=true end end
 for _,ref in ipairs(saved.before and saved.before.bags or {}) do result.items[ref.id]=true end
 if action.Type=='ISFitnessAction' then
  result.forceCancel=class.forceCancel
  local receipt=Toolkit.ActionQueueAcknowledgements.capture(action)
  if not isClient() or receipt then result.interrupt='audited-stop' end
  if isClient() and action.action and not receipt then result.cancelOperation=false end
 end
 return result
end
Definitions.registerBehavior('toolkit.fitness',{types={'ISQueueActionsAction','ISFitnessAction','ISWaitWhileGettingUp','ISWearClothing','ISDropWorldItemAction'},matches=Fitness.isManaged,inspect=contract})
local keys={squats='IGUI_Squats',pushups='IGUI_PushUps',situp='IGUI_SitUps',burpees='IGUI_Burpees',
 barbellcurl='IGUI_BarbellCurl',dumbbellpress='IGUI_DumbbellPress',bicepscurl='IGUI_BicepsCurl'}
function Fitness.progress(action)
 local record=validRecord(action)
 if not record or action.Type~='ISFitnessAction' or not record.started then return end
 local elapsed=math.max(0,math.min(record.saved.minutes,(now()-action.startMS)/60000))
 return {elapsed=elapsed,total=record.saved.minutes,fraction=elapsed/record.saved.minutes,stopping=record.stopping==true}
end
function Fitness.describe(action)
 local record=validRecord(action)
 if not record or (action.Type~='ISQueueActionsAction' and action.Type~='ISFitnessAction') then return end
 local saved=record.saved;local progress=Fitness.progress(action)
 local role=record.stage=='cleanup' and 'return' or record.stage=='preparation' and 'preparation' or nil
 local title=role and getText('UI_PZSurvivorToolkit_queue_fitness_'..record.stage) or getText(keys[saved.exercise])
 local text
 if not role then
  text=progress and progress.stopping and getText('UI_PZSurvivorToolkit_queue_fitness_stopping')
   or progress and getText('UI_PZSurvivorToolkit_queue_fitness_progress',string.format('%.1f',progress.elapsed),saved.minutes)
   or getText('UI_PZSurvivorToolkit_queue_fitness_duration',saved.minutes)
 end
 return {id='toolkit.fitness',title=title,signature='fitness:'..saved.exercise,
  target=text,role=role,
  icon=function() return getItemTex(saved.data.item or 'Base.DumbBell') or getTexture('media/ui/Entity/Icon_Tools_48x48.png') end}
end
Events.OnTick.Add(function()
 -- Kahlua ignores weak tables; retain proofs through receipt waits and cleanup while queued.
 local queues
 for action,record in pairs(records) do
  local queue=ISTimedActionQueue.queues[record.saved.player]
  if not queue then records[action]=nil
  else
   queues=queues or {}
   local group=queues[queue]
   if not group then group={pending={},remaining=0};queues[queue]=group end
   group.pending[action],group.remaining=true,group.remaining+1
  end
 end
 if queues then
  for queue,group in pairs(queues) do
   -- Stop after the last tracked member, rather than scanning an unrelated tail.
   for _,action in ipairs(queue.queue) do
    if group.pending[action] then
     group.pending[action],group.remaining=nil,group.remaining-1
     if group.remaining==0 then break end
    end
   end
   for action in pairs(group.pending) do records[action]=nil end
  end
 end
end)
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() records={} end) end
return Fitness
