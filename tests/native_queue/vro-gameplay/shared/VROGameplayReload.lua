-- Persisted identities, never old network IDs, own reload verification and cleanup.
local F=require 'VROGameplayFixture'
local W=require 'QueueFixtureWorldCleanup'
local C=require 'QueueFixtureItemCleanup'
local R={}
local state
local restores={}
local function clone(value)
 if type(value)~='table'then return value end
 local result={};for k,v in pairs(value)do result[k]=clone(v)end;return result
end
local function ground(ids)
 local square=getCell():getGridSquare(ids.x,ids.y,ids.z);local rows={}
 for i=0,square:getWorldObjects():size()-1 do local item=square:getWorldObjects():get(i):getItem()
  if item then rows[#rows+1]={id=item:getID(),fullType=item:getFullType()}end
 end
 table.sort(rows,function(a,b)return a.id<b.id end);return rows
end
local function identify(checkpoint)
 for _,name in ipairs({'repair','salvage'})do local ids=checkpoint.packet[name]
  for dx=-3,3 do for dy=-3,3 do
   if not getCell():getGridSquare(ids.x+dx,ids.y+dy,ids.z)then return nil end
  end end
 end
 local found={};local vehicles=getCell():getVehicles():iterator()
 while vehicles:hasNext()do local vehicle=vehicles:next()
  if not vehicle:isRemovedFromWorld()then
   local part=vehicle:getPartById('EngineDoor');local tag=part and part:getModData()[F.key]
   if tag=='repair'or tag=='salvage'then
    assert(not found[tag],'duplicate persisted VRO vehicle tag: '..tag)
    local item=part:getInventoryItem()
    assert(item and item:getID()==checkpoint.packet[tag].installedID,'persisted VRO installed identity changed: '..tag)
    found[tag]=vehicle
   end
  end
 end
 return found
end
local function snapshotWorld(checkpoint,found,name)
 local ids=checkpoint.packet[name];local vehicle=found[name]
 local row={vehicleKey=name,vehicleID=vehicle and vehicle:getId()or ids.vehicleID,
  removed=vehicle==nil,ground=ground(ids)}
 if vehicle then
  local part=vehicle:getPartById('EngineDoor');local item=part:getInventoryItem()
  row.itemID=item:getID();row.condition=part:getCondition();row.itemCondition=item:getCondition();row.hbr=item:getHaveBeenRepaired()
 end
 return row
end
function R.worlds(checkpoint)
 local found=identify(checkpoint);if not found then return nil end
 return {repair=snapshotWorld(checkpoint,found,'repair'),salvage=snapshotWorld(checkpoint,found,'salvage')}
end
local function compareWorld(actual,expected)
 local a,b=clone(actual),clone(expected);a.vehicleID=nil;b.vehicleID=nil
 return F.same(a,b)
end
local function actorCore(actor)
 local row=clone(actor);row.x=nil;row.y=nil;row.z=nil
 table.sort(row.items,function(a,b)return a.id<b.id end);table.sort(row.worn,function(a,b)return a.id<b.id end)
 return row
end
local function item(player,id)return player:getInventory():getItemById(id)end
function R.actorMatches(actual,expected)
 return F.same(actorCore(actual),actorCore(expected))
  and math.abs(actual.x-expected.x)<=.001 and math.abs(actual.y-expected.y)<=.001 and actual.z==expected.z
end
function R.cleanedActor(player,original,checkpoint)
 local actual=F.actor(player)
 if not R.actorMatches(actual,original)then return nil end
 for _,saved in ipairs(checkpoint.owned)do
  if player:getInventory():getItemWithIDRecursiv(saved.id)then return nil end
 end
 return actual
end
local function resources(player,checkpoint)
 local packet=checkpoint.packet
 local repair=assert(checkpoint.receipts[2],'repair completion receipt missing').after
 local salvage=assert(checkpoint.receipts[4],'salvage completion receipt missing').after
 local result={metal={}}
 for name,entry in pairs({repairTorch={id=packet.repairTorchID,uses=repair.torch.uses},
  salvageTorch={id=packet.salvageTorchID,uses=salvage.torchUses}})do
  local actual=assert(item(player,entry.id),'persisted paid torch missing: '..name)
  assert(actual:getFullType()=='Base.BlowTorch'and actual:getCurrentUses()==entry.uses,'persisted paid torch changed: '..name)
  result[name]={id=actual:getID(),fullType=actual:getFullType(),uses=actual:getCurrentUses()}
 end
 local mask=assert(item(player,packet.maskID),'persisted kept mask missing')
 assert(mask:getFullType()=='Base.WeldingMask','persisted kept mask type changed')
 result.mask={id=mask:getID(),fullType=mask:getFullType()}
 for _,id in ipairs(packet.metalIDs)do
  assert(not item(player,id),'consumed repair material reappeared')
  result.metal[#result.metal+1]={id=id,present=false}
 end
 return result
end
function R.begin(player,providedCheckpoint)
 if state then assert(state.player==player,'reload actor changed');return state.checkpoint end
 local checkpoint=assert(providedCheckpoint or ModData.get(F.key),'persisted VRO checkpoint missing')
 assert(checkpoint.version==1 and checkpoint.packet and checkpoint.original and checkpoint.finalActor
  and checkpoint.worlds and checkpoint.owned and checkpoint.receipts and checkpoint.clientOriginals
  and checkpoint.clientOriginals.client1,'persisted VRO checkpoint incomplete')
 state={player=player,checkpoint=checkpoint};return checkpoint
end
function R.verify(player,providedCheckpoint)
 local checkpoint=R.begin(player,providedCheckpoint)
 if state.verified then return state.verified end
 local worlds=R.worlds(checkpoint);if not worlds then return nil end
 assert(compareWorld(worlds.repair,checkpoint.worlds.repair),'persisted repair condition/history/ground changed')
 assert(compareWorld(worlds.salvage,checkpoint.worlds.salvage),'persisted salvage absence/ground changed')
 local actor=F.actor(player)
 assert(F.same(actorCore(actor),actorCore(checkpoint.finalActor)),'persisted actor inventory/equipment/XP changed')
 local paid=resources(player,checkpoint)
 local found=assert(identify(checkpoint))
 -- Only this exact installed-item identity can refresh the transient wire ID.
 checkpoint.packet.repair.vehicleID=found.repair:getId()
 F.packet=checkpoint.packet;F.vehicles.repair=found.repair
 state.vehicle=found.repair
 state.verified={role='authority',actor=actor,worlds=worlds,owned=clone(checkpoint.owned),resources=paid}
 return state.verified
end
local function originals(checkpoint)
 local ids={};for _,entry in ipairs(checkpoint.original.items)do ids[entry.id]=entry.fullType end;return ids
end
local function owned(checkpoint)
 local ids={};for _,entry in ipairs(checkpoint.owned)do
  assert(not ids[entry.id],'duplicate saved owned item ID');ids[entry.id]=entry.fullType
 end;return ids
end
local function rootGuard(player,checkpoint,journal)
 local keep,ours=originals(checkpoint),owned(checkpoint);local seen={}
 local inventory=player:getInventory();local entries=inventory:getItems()
 for i=0,entries:size()-1 do local value=entries:get(i);local id=value:getID()
  assert(not seen[id],'duplicate actor inventory identity during cleanup');seen[id]=true
  assert((keep[id]or ours[id])==value:getFullType(),'foreign or changed actor inventory item during cleanup')
 end
 for id,ft in pairs(keep)do local value=item(player,id)
  assert(value and value:getFullType()==ft,'original actor item missing before restoration')
 end
end
local function restore(player,checkpoint,remote)
 local original=checkpoint.original;local inventory=player:getInventory()
 local keep=originals(checkpoint)
 local function originalItem(id)
  if id==false then return nil end
  local value=assert(inventory:getItemById(id),'original equipment identity missing')
  assert(keep[id]==value:getFullType(),'original equipment type changed');return value
 end
 if not remote then
 -- Change only fixture-owned worn items, then restore every saved original slot.
 local ours=owned(checkpoint);local worn=player:getWornItems();local remove={}
 for i=0,worn:size()-1 do local value=worn:get(i):getItem()
  if ours[value:getID()]then remove[#remove+1]=value
  else assert(keep[value:getID()]==value:getFullType(),'foreign worn item blocks original restoration')end
 end
 for _,value in ipairs(remove)do player:removeWornItem(value)end
 for _,saved in ipairs(original.worn)do
  local value=originalItem(saved.id)
  local location=assert(ItemBodyLocation.get(ResourceLocation.of(saved.location)),'saved original worn slot is unavailable')
  player:setWornItem(location,value)
 end
 local primary,secondary=originalItem(original.primary),originalItem(original.secondary)
 local changed=player:getPrimaryHandItem()~=primary or player:getSecondaryHandItem()~=secondary
 player:setPrimaryHandItem(primary);player:setSecondaryHandItem(secondary)
 if isClient()and changed then player:updateHandEquips()end
 end
 local xp=player:getXp()
 for _,name in ipairs({'Mechanics','MetalWelding'})do local saved=original.xp[name];local perk=Perks[name]
  xp:setXPToLevel(perk,saved.level)
  xp:AddXP(perk,saved.xp-xp:getXP(perk),false,false,false,false)
  player:setPerkLevelDebug(perk,saved.level)
 end
 xp:setTotalXP(original.total)
 if not remote then
 player:teleportTo(original.x,original.y,original.z);player:setX(original.x);player:setY(original.y)
 player:setNextX(original.x);player:setNextY(original.y);player:setLastX(original.x);player:setLastY(original.y)
 end
end
function R.restoreActor(player,original,checkpoint)
 checkpoint=checkpoint or(state and state.checkpoint)or ModData.get(F.key)
 assert(checkpoint and checkpoint.owned,'restore requires exact fixture ownership')
 local remote=isServer();local pending=restores[player]
 if not pending or pending.remote~=remote then
  if player:getCharacterActions():size()~=0 or player:hasPath()then return nil end
  if remote then
   local actual,expected=actorCore(F.actor(player)),actorCore(original)
   actual.items=nil;expected.items=nil;actual.xp=nil;expected.xp=nil;actual.total=nil;expected.total=nil
   if not F.same(actual,expected)then return nil end
  end
  pending={original=original,remote=remote,since=getTimestampMs()};restores[player]=pending
  restore(player,{original=original,owned=checkpoint.owned},remote)
 else assert(F.same(pending.original,original),'restore original checkpoint changed')end
 local actual=F.actor(player);local a,b=actorCore(actual),actorCore(original);a.items=nil;b.items=nil
 local square=player:getCurrentSquare()
 local position=math.abs(actual.x-original.x)<=.001 and math.abs(actual.y-original.y)<=.001 and actual.z==original.z
  and square and square:getX()==math.floor(original.x)and square:getY()==math.floor(original.y)and square:getZ()==original.z
 local quiet=player:getCharacterActions():size()==0 and not player:hasPath()
 if not F.same(a,b)or not position or not quiet then
  pending.quietSince=nil
  assert(getTimestampMs()-pending.since<20000,'original actor restoration did not settle')
  return nil
 end
 pending.quietSince=pending.quietSince or getTimestampMs()
 if getTimestampMs()-pending.quietSince<500 then return nil end
 return {restored=true,actor=actual}
end

local function dropEntries(checkpoint)
 local before=checkpoint.receipts[4].before.ground;local existing={};local expected={};local result={}
 for _,entry in ipairs(before)do existing[entry.id]=entry.fullType end
 for _,entry in ipairs(checkpoint.worlds.salvage.ground)do
  if not existing[entry.id]then expected[entry.id]=entry.fullType end
 end
 local ids=checkpoint.packet.salvage;local square=getCell():getGridSquare(ids.x,ids.y,ids.z)
 for i=0,square:getWorldObjects():size()-1 do local object=square:getWorldObjects():get(i);local value=object:getItem()
  if value and expected[value:getID()]then
   assert(value:getFullType()==expected[value:getID()],'owned salvage drop type changed')
   result[#result+1]={object=object,item=value,square=square};expected[value:getID()]=nil
  end
 end
 for _ in pairs(expected)do error('owned salvage drop missing before cleanup')end
 return result
end
function R.cleanup(player)
 local checkpoint=R.begin(player)
 assert(state.verified,'reload must be verified before cleanup')
 if state.cleanup then return state.cleanup end
 if not state.prepared then
  if not R.worlds(checkpoint)then return nil end
  rootGuard(player,checkpoint)
  local actor=actorCore(F.actor(player))
  if isServer()then
   local ours=owned(checkpoint);local kept={}
   for _,entry in ipairs(actor.items)do if not ours[entry.id]then kept[#kept+1]=entry end end;actor.items=kept
   local expected=actorCore(checkpoint.original);actor.xp=nil;expected.xp=nil;actor.total=nil;expected.total=nil
   if not F.same(actor,expected)then return nil end
  else assert(F.same(actor,actorCore(checkpoint.finalActor)),'actor changed after reload verification')end
  local worlds=assert(R.worlds(checkpoint))
  assert(compareWorld(worlds.repair,checkpoint.worlds.repair)and compareWorld(worlds.salvage,checkpoint.worlds.salvage),
   'fixture world changed before cleanup')
  local found=assert(identify(checkpoint));assert(found.repair==state.vehicle and not found.salvage,'cleanup vehicle ownership changed')
  F.safeVehicle(state.vehicle)
  state.prepared=true
 end
 if not state.started then
  -- Original equipment and native position replication settle before any destruction.
  if not R.restoreActor(player,checkpoint.original,checkpoint)then return nil end
  local current=R.worlds(checkpoint);if not current then return nil end
  assert(compareWorld(current.repair,checkpoint.worlds.repair)and compareWorld(current.salvage,checkpoint.worlds.salvage),
   'fixture world changed while restoring actor')
  assert(identify(checkpoint).repair==state.vehicle,'cleanup vehicle reference changed while restoring actor')
  rootGuard(player,checkpoint)
  assert(F.same(actorCore(F.actor(player)).items,actorCore(checkpoint.finalActor).items),
   'paid actor inventory changed before cleanup')
  F.safeVehicle(state.vehicle)
  local groundEntries=dropEntries(checkpoint)
  local entries={};for _,saved in ipairs(checkpoint.owned)do local value=item(player,saved.id)
   if value then
    assert(value:getFullType()==saved.fullType,'owned cleanup inventory type changed')
    entries[#entries+1]={id=saved.id,item=value,container=player:getInventory(),ft=saved.fullType}
   end
  end
  state.ground=W.new(groundEntries,{server=isServer(),guard=function()rootGuard(player,checkpoint);return true end})
  state.items=C.new(entries,{containers={player:getInventory()},server=isServer(),
   guard=function(journal)rootGuard(player,checkpoint,journal)end,
   check=function(entry)assert(entry.item:getID()==entry.id and entry.item:getFullType()==entry.ft,'owned cleanup identity rebound')end})
  state.started=true
  state.groundReceipt=W.run(state.ground)
  state.itemReceipt=C.run(state.items)
  F.safeVehicle(state.vehicle)
  state.vehicleReceipt={vehicleKey='repair',installedID=checkpoint.packet.repair.installedID,vehicleID=state.vehicle:getId()}
  state.vehicle:permanentlyRemove()
 end
 local worlds=R.worlds(checkpoint);if not worlds then return nil end
 if not worlds.repair.removed or not worlds.salvage.removed then return nil end
 rootGuard(player,checkpoint)
 local actual=F.actor(player)
 local a,b=actorCore(actual),actorCore(checkpoint.original)
 assert(F.same(a,b),'original actor inventory/equipment/XP restoration failed')
 if math.abs(actual.x-checkpoint.original.x)>.001 or math.abs(actual.y-checkpoint.original.y)>.001
  or actual.z~=checkpoint.original.z then return nil end
 state.cleanup={role='authority',restored=true,actor=actual,vehicles={removed={state.vehicleReceipt}},
  items=state.itemReceipt,ground=state.groundReceipt,worlds=worlds}
 return state.cleanup
end
return R
