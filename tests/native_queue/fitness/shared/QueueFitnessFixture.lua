local O=require 'QueueFitnessObservation'
local F={}
function F.restorationCase(id)return id=='active-cancel-restore'or id=='pickup-cancel-restore'end
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
 for _,name in ipairs({'front','tail','bag','hammer','screwdriver','dumbbell'})do
  local destination=F.borrowedCase(id)and name=='dumbbell'and state.items.bag:getItemContainer()or player:getInventory()
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
  state.items.hammer:setCurrentUses(state.items.hammer:getMaxUses());state.items.hammer:setActivated(true)
 end
 O.reset(player,id);O.tailID=state.ids.items.tail;state.ids.before=O.clinical(player);state.ids.inventory=F.inventory(player);state.ids.activation=F.activation(player)
 if isServer()then
  -- InventoryContainer serialization includes its children. Send the owning root bag
  -- once; sending the nested dumbbell again would create a duplicate replica.
  for _,item in pairs(state.items)do
   if item:getContainer()==player:getInventory()then sendAddItemToContainer(item:getContainer(),item)end
  end
  sendClothing(player,state.items.bag:canBeEquipped(),player:getWornItem(state.items.bag:canBeEquipped()));sendEquip(player)
 end
 return state
end
function F.resolve(player,ids)
 local state={case=ids.case,player=player,ids=ids,items={}}
 for name,id in pairs(ids.items)do
  local item=player:getInventory():getItemById(id);if not item then return end
  if item:getFullType()~=(F.restorationCase(ids.case)and name=='hammer'and 'Base.Torch'or types[name])then error('fitness ID/type differs '..name)end
  state.items[name]=item
 end
 return state
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
 result.activation=F.activation(player);result.before=state.ids.before;result.peerConnected=not isServer()
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
function F.releaseEquipment(state)
 -- Fixture cleanup only after a recorded case and the real native queue has settled.
 local player=state.player
 player:setPrimaryHandItem(nil);player:setSecondaryHandItem(nil)
 local bag=player:getInventory():getItemById(state.ids.items.bag)
 if bag and player:isEquipped(bag)then player:removeWornItem(bag,false)end
 if isServer()then sendClothing(player,state.items.bag:canBeEquipped(),player:getWornItem(state.items.bag:canBeEquipped()));sendEquip(player)end
end
O.inventory=F.inventory;O.activation=F.activation
return F
