local P=require 'QueueEnergyPlacement'
local function capacityModule()return require 'QueueWringCapacityProfile'end
local F={names={'front','target','tail','cancelled'},wornPrepared={
 target={type='Base.Scarf_White',slot='base:scarf',weight=.2},
 cancelled={type='Base.Gloves_LeatherGloves',slot='base:hands',weight=.1}}}
F.swapNames={'front','target','tail','incoming','displaced'}
F.swapCatalog={target=F.wornPrepared.target,displaced={type='Base.Gloves_BurlapWrap',slot='base:hands',weight=.2},incoming=F.wornPrepared.cancelled}
function F.namesFor(ids)return ids.wearSwap and F.swapNames or F.names end
function F.observesClothing(ids)return ids.wornPrepared or ids.wearSwap end
function F.readyWetness(ids,name,wetness)
 if ids.wearSwap then
  return wetness>=0 and wetness<=ids.items[name].initial and((name=='incoming'or name=='displaced')or wetness>10)
 end
 return wetness>80
end
-- Native transfer can start before later P4 returns merge into its queueList.
-- Refresh the observed existing-item membership at each real callback boundary.
function F.returnMembers(action,rows)
 local seen={};for _,row in ipairs(rows)do seen[row.id]=row.type end
 for _,group in ipairs(action.queueList or {})do for _,item in ipairs(group.items or {})do
  local id,kind=item:getID(),item:getFullType()
  if seen[id]then assert(seen[id]==kind,'native return ID changed type')
  else rows[#rows+1]={id=id,type=kind};seen[id]=kind end
 end end
 table.sort(rows,function(a,b)return a.id<b.id end);return rows
end
function F.nativeWetnessContract(item)
 local location=item:getBodyLocation();local nativeShoe=location=='Shoes'
 return{bodyLocation=tostring(location),bodyLocationClass=getClassSimpleName(location),
  nativeShoe=nativeShoe,cap=nativeShoe and 60 or 10}
end
local function identity(o)local s=o:getSquare();return{x=s:getX(),y=s:getY(),z=s:getZ(),index=o:getObjectIndex()}end
local function sourceFor(player,ids,preparingWear)
 local root=player:getInventory()
 if ids.source.kind=='root'or ids.source.kind=='worn'or ids.source.kind=='worn-prepared'or ids.source.kind=='wear-swap'then return root end
 if ids.source.kind=='worn-bag'then
  local bag=root:getItemById(ids.source.bag)
  if bag and bag:getContainer()==root and bag:getFullType()=='Base.Bag_Military'
   and(preparingWear or player:getWornItems():contains(bag))then return bag:getItemContainer(),bag end
 elseif ids.source.kind=='world'then
  local id=ids.source.world;local square=getCell():getGridSquare(id.x,id.y,id.z)
  if square then for i=0,square:getObjects():size()-1 do local object=square:getObjects():get(i)
   if object:getObjectIndex()==id.index and instanceof(object,'IsoThumpable')then return object:getContainer(),nil,object end
  end end
 end
end
local function find(container,id)
 local values=container:getItems()
 for i=0,values:size()-1 do local item=values:get(i)
  if item:getID()==id then return item end
  if instanceof(item,'InventoryContainer')then local found=find(item:getItemContainer(),id);if found then return found end end
 end
end
-- Read-only exact native equipment state; no hand or worn-slot repair.
function F.equipment(player)
 local worn=player:getWornItems();local rows={}
 for i=0,worn:size()-1 do local entry=worn:get(i);local item=entry:getItem()
  assert(item and item:getContainer()==player:getInventory(),'worn fixture equipment is not root-owned')
  rows[#rows+1]={slot=tostring(entry:getLocation()),id=item:getID(),type=item:getFullType()}
 end
 table.sort(rows,function(a,b)if a.slot==b.slot then return a.id<b.id end;return a.slot<b.slot end)
 local function hand(item)return item and{id=item:getID(),type=item:getFullType()}or false end
 return{worn=rows,primary=hand(player:getPrimaryHandItem()),secondary=hand(player:getSecondaryHandItem())}
end
-- Previous-case Host cleanup may reach the clothing channel after new item IDs.
-- Compare physical state to authority's new baseline; never repair a stale slot.
function F.equipmentMatches(player,expected)
 local ok,value=pcall(F.equipment,player);if not ok then return false end
 for _,hand in ipairs({'primary','secondary'})do local actual,wanted=value[hand],expected[hand]
  if actual==false then if wanted~=false then return false end
  elseif wanted==false or actual.id~=wanted.id or actual.type~=wanted.type then return false end
 end
 if #value.worn~=#expected.worn then return false end
 for index,row in ipairs(value.worn)do local wanted=expected.worn[index]
  if row.slot~=wanted.slot or row.id~=wanted.id or row.type~=wanted.type then return false end
 end
 return true
end
function F.unequipSnapshot(s,name)
 local snapshot=F.snapshot(s);local item=snapshot.items[name]
 return{item=item,equipment=snapshot.equipment,inventoryWeight=snapshot.inventoryWeight}
end
function F.clothingTransition(s)
 if not F.observesClothing(s.ids)or not s.wearBaseline then return end
 s.unequipTransitions=s.unequipTransitions or{};s.transitionSeen=s.transitionSeen or{}
 local value=F.snapshot(s)
 for _,name in ipairs(s.ids.wearSwap and{'target'}or{'target','cancelled'})do
  if s.wearBaseline.items[name].worn and not value.items[name].worn and not s.transitionSeen[name]then
   s.transitionSeen[name]=true
   s.unequipTransitions[#s.unequipTransitions+1]={name=name,item=value.items[name],equipment=value.equipment,inventoryWeight=value.inventoryWeight}
  end
 end
 if s.ids.wearSwap and not s.swapTransition then
  if value.items.incoming.worn and not value.items.displaced.worn then s.swapTransition=value end
 end
end
function F.swapPhysical(s)
 local value=F.snapshot(s)
 return value.items.incoming.worn and not value.items.displaced.worn and value.items.incoming.slotId==s.ids.items.incoming.id, value
end
function F.snapshot(s)
 local root=s.player:getInventory();local source,bag,shelf=sourceFor(s.player,s.ids)
 assert(source==s.source and bag==s.bag and shelf==s.shelf,'wring source identity changed')
 local out={case=s.ids.case,source=s.ids.source,items={}}
 for _,name in ipairs(F.namesFor(s.ids))do
  local spec=s.ids.items[name];local counts={actor=0,root=0,source=0};local canonical,found=nil,0
  local function count(container,actor)
   local values=container:getItems()
   for i=0,values:size()-1 do local value=values:get(i)
    if value:getID()==spec.id then
     assert(instanceof(value,'Clothing')and value:getFullType()==spec.type,'fixture item changed type')
     assert(value:getContainer()==container,'fixture clothing owner changed')
     canonical=value;found=found+1;if actor then counts.actor=counts.actor+1 end
     if container==root then counts.root=counts.root+1 end
     if container==source then counts.source=counts.source+1 end
    end
    if instanceof(value,'InventoryContainer')then count(value:getItemContainer(),actor)end
   end
  end
  count(root,true);if shelf then count(source,false)end
  -- Native Host transfer replaces handles; only the unique owned ID/type may rebind.
  assert(found==1,'missing or duplicate exact clothing identity');local item=canonical;s.items[name]=item
  local native=F.nativeWetnessContract(item)
  assert(native.bodyLocation==spec.bodyLocation and native.bodyLocationClass==spec.bodyLocationClass
   and native.nativeShoe==spec.nativeShoe and native.cap==spec.cap,'native wring body-location contract changed')
  out.items[name]={id=item:getID(),type=item:getFullType(),wetness=item:getWetness(),weight=item:getActualWeight(),
   worn=s.player:getWornItems():contains(item),counts=counts,native=native}
  if F.observesClothing(s.ids)then
   out.items[name].slot=tostring(item:getBodyLocation());out.items[name].slotId=(s.player:getWornItem(item:getBodyLocation())and s.player:getWornItem(item:getBodyLocation()):getID())or false
   out.items[name].capacityWeight=item:getUnequippedWeight();out.items[name].equippedWeight=item:getEquippedWeight()
  end
  if s.ids.preparedGroups then out.items[name].wetWeight=item:getWeight();out.items[name].capacityWeight=item:getUnequippedWeight()end
 end
 if F.observesClothing(s.ids)then out.equipment=F.equipment(s.player);out.inventoryWeight=s.player:getInventoryWeight()end
 if s.ids.capacityProfile then out.capacityPayload=capacityModule().snapshot(s)end
 return out
end
-- Fixed naturally wet cotton scarf/leather gloves; never displace starter gear.
function F.assertPreparedSlots(player,items,catalog)
 catalog=catalog or F.wornPrepared
 local group=assert(player:getBodyLocationGroup(),'prepared native body-location group missing')
 for _,name in ipairs(catalog==F.swapCatalog and{'target','displaced'}or{'target','cancelled'})do
  local item,spec=items[name],catalog[name];local slot=item:getBodyLocation()
  assert(getClassSimpleName(item)=='Clothing'and item:getFullType()==spec.type and tostring(slot)==spec.slot
   and item:getBloodClothingType()and item:getBloodClothingType():size()>0,'prepared natural clothing catalog differs '..name)
  assert(group:getLocation(slot)and group:isMultiItem(slot)==false,'prepared native slot is not single '..tostring(slot))
  local occupied=player:getWornItem(slot)
  assert(not occupied,'prepared clothing slot occupied: requested='..spec.type..' slot='..tostring(slot)
   ..' occupant='..(occupied and occupied:getFullType()..'#'..tostring(occupied:getID())or'none'))
  local worn=player:getWornItems()
  for index=0,worn:size()-1 do local entry=worn:get(index);local other=entry:getLocation()
   assert(group:isExclusive(slot,other)==false,'prepared clothing exclusive slot: requested='..spec.type..' slot='..tostring(slot)
    ..' otherSlot='..tostring(other)..' occupant='..entry:getItem():getFullType()..'#'..tostring(entry:getItem():getID()))
  end
 end
end
function F.prepare(player,case,mode,placement,proof,previous,profile,restoration)
 assert(profile==nil or type(profile)=='boolean','invalid capacity profile selection')
 profile=profile==true and case=='worn-bag'
 assert((case=='root'or case=='worn'or case=='worn-bag'or case=='worn-prepared'or case=='wear-swap'or case=='world')and P.atCentered(player,placement))
 if previous then F.dispose(previous)end
 local precipitation=assert(getClimateManager():getClimateFloat(ClimateManager.FLOAT_PRECIPITATION_INTENSITY))
 precipitation:setEnableAdmin(true);precipitation:setAdminValue(0);precipitation:setFinalValue(0)
 local root=player:getInventory();local source,bag,shelf=root,nil,nil
 if case=='worn-bag'then
  bag=assert(root:AddItem('Base.Bag_Military'));assert(not player:getWornItem(bag:canBeEquipped()),'wring bag slot occupied')
  if not isServer()and not profile then player:setWornItem(bag:canBeEquipped(),bag)end
  source=bag:getItemContainer();source:setExplored(true)
 elseif case=='world'then
  local square=assert(getCell():getGridSquare(placement.x,placement.y-1,placement.z))
  shelf=IsoThumpable.new(getCell(),square,'furniture_storage_01_8',false,{})
  shelf:setCanPassThrough(true);shelf:setIsContainer(true);shelf:setName('Wring fixture');square:AddSpecialObject(shelf)
  source=assert(shelf:getContainer());source:setType('shelf');source:setCapacity(100);source:setExplored(true)
 end
 local ids={case=case,mode=mode,restoration=restoration==true,origin=placement,placementProof=proof,items={},source={kind=case,bag=bag and bag:getID()or false,world=shelf and identity(shelf)or false}}
 if case=='wear-swap'then ids.wearSwap=true;ids.nativeWearSetup=true;ids.initialEquipment=F.equipment(player)end
 local state={player=player,ids=ids,source=source,bag=bag,shelf=shelf,items={}}
 for _,name in ipairs(F.namesFor(ids))do
  local shoes=name=='tail'or name=='target'and(case=='worn'or case=='world')
  local owner=(name=='target'or case=='worn-bag'and name=='cancelled')and source or root
  local garment=case=='wear-swap'and F.swapCatalog[name]or case=='worn-prepared'and F.wornPrepared[name]
  local gloves=case=='wear-swap'and(name=='incoming'or name=='displaced')or case=='worn-prepared'and name=='cancelled'
  local scarf=(case=='worn-prepared'or case=='wear-swap')and name=='target'
  local item=assert(owner:AddItem(garment and garment.type or shoes and'Base.Shoes_FlipFlop'or'Base.Socks_Ankle'))
  assert(instanceof(item,'Clothing'));item:setWetness(100)
  -- B42 returns ItemBodyLocation userdata. Preserve the native string comparison,
  -- including its current false result for real shoes; do not repair vanilla here.
  assert(item:getBodyLocation()==(scarf and ItemBodyLocation.SCARF or gloves and ItemBodyLocation.HANDS or shoes and ItemBodyLocation.SHOES or ItemBodyLocation.SOCKS),'fixture body location differs')
  local spec=F.nativeWetnessContract(item)
  spec.id=item:getID();spec.type=item:getFullType();spec.initial=item:getWetness();spec.weight=item:getActualWeight()
  if case=='worn-bag'then spec.wetWeight=item:getWeight();spec.capacityWeight=item:getUnequippedWeight()end
  state.items[name]=item;ids.items[name]=spec
 end
 if case=='worn-bag'then ids.preparedGroups=true end
 if profile then capacityModule().seed(state);ids.nativeWearSetup=true end
 if case=='wear-swap'then
  F.assertPreparedSlots(player,state.items,F.swapCatalog)
  for _,name in ipairs(F.namesFor(ids))do local item=state.items[name];ids.items[name].capacityWeight=item:getUnequippedWeight();ids.items[name].equippedWeight=item:getEquippedWeight()end
 end
 if case=='worn-prepared'then
  ids.wornPrepared=true;ids.nativeWearSetup=true;ids.initialEquipment=F.equipment(player)
  F.assertPreparedSlots(player,state.items)
  for _,name in ipairs(F.namesFor(ids))do local item=state.items[name];ids.items[name].capacityWeight=item:getUnequippedWeight();ids.items[name].equippedWeight=item:getEquippedWeight()end
 end
 if case=='worn'then
  local item=state.items.target;local slot=item:getBodyLocation();state.original=player:getWornItem(slot)
  if not isServer()then player:setWornItem(slot,item)end
  ids.original=state.original and{id=state.original:getID(),type=state.original:getFullType()}or false
 end
 -- SyncClothing can retain a same-ID worn proxy if it arrives before AddItem.
 -- The owning Host client instead wears the exact replicated item natively.
 if isServer()and(case=='worn'or case=='worn-bag')then ids.nativeWearSetup=true end
 assert(player:getInventoryWeight()<player:getMaxWeight(),'fixture actor lacks ordinary inventory headroom')
 if isServer()then
  if shelf then shelf:transmitCompleteItemToClients()end
  if bag then sendAddItemToContainer(root,bag)end
  -- Bag and furniture complete-state packets already contain their target item.
  for _,name in ipairs(F.namesFor(ids))do local item=state.items[name]
   if item:getContainer()==root then sendAddItemToContainer(root,item)end
  end
 end
 if not ids.nativeWearSetup then state.input=F.snapshot(state)end
 return state
end
function F.resolve(player,ids,preparingWear)
 assert(not preparingWear or ids.nativeWearSetup==true,'native wear setup was not declared by authority')
 local source,bag,shelf=sourceFor(player,ids,preparingWear);if not source or not P.atCentered(player,ids.origin)then return end
 local state={player=player,ids=ids,source=source,bag=bag,shelf=shelf,items={}}
 for _,name in ipairs(F.namesFor(ids))do
  local spec=ids.items[name];local owner=(name=='target'or ids.case=='worn-bag'and name=='cancelled')and source or player:getInventory();local item=find(owner,spec.id)
  if not item or item:getContainer()~=owner or item:getFullType()~=spec.type or not F.readyWetness(ids,name,item:getWetness())then return end
  state.items[name]=item
 end
 if (ids.case=='worn-prepared'or ids.wearSwap)and not preparingWear then
  for _,name in ipairs(ids.wearSwap and{'target','displaced'}or{'target','cancelled'})do if player:getWornItem(state.items[name]:getBodyLocation())~=state.items[name]then return end end
 end
 if ids.capacityProfile and not pcall(capacityModule().snapshot,state)then return end
 if ids.case=='worn'and not preparingWear and not player:getWornItems():contains(state.items.target)then return end
 return state
end
function F.wearBaseline(s)
 local source,bag,shelf=sourceFor(s.player,s.ids)
 if source~=s.source or bag~=s.bag or shelf~=s.shelf then return end
 if F.observesClothing(s.ids)then
  for _,name in ipairs(s.ids.wearSwap and{'target','displaced'}or{'target','cancelled'})do if s.player:getWornItem(s.items[name]:getBodyLocation())~=s.items[name]then return end end
 end
 if s.ids.case=='worn'and s.player:getWornItem(s.items.target:getBodyLocation())~=s.items.target then return end
 local value=F.snapshot(s)
 for _,name in ipairs(F.namesFor(s.ids))do
  local item=value.items[name];local borrowed=(name=='target'or s.ids.case=='worn-bag'and name=='cancelled')and(s.ids.case=='worn-bag'or s.ids.case=='world')
  if item.counts.root~=(borrowed and 0 or 1)or item.counts.actor~=(name=='target'and s.ids.case=='world'and 0 or 1)
   or item.counts.source~=((s.ids.case=='root'or s.ids.case=='worn'or s.ids.case=='worn-prepared'or s.ids.wearSwap or name=='target'or borrowed)and 1 or 0)
   or item.worn~=((s.ids.case=='worn'and name=='target')or(s.ids.case=='worn-prepared'and(name=='target'or name=='cancelled'))or(s.ids.wearSwap==true and(name=='target'or name=='displaced')))or not F.readyWetness(s.ids,name,item.wetness)then return end
 end
 s.wearBaseline=value;return value
end
function F.preparedDiagnostic(player,ids)
 local root=player:getInventory();local source,bag=sourceFor(player,ids,true)
 local value={case=ids.case,atCentered=P.atCentered(player,ids.origin),sourcePresent=source~=nil,items={}}
 if bag then
  local slot=player:getWornItem(bag:canBeEquipped())
  value.bag={id=bag:getID(),root=bag:getContainer()==root,canonicalWorn=player:getWornItems():contains(bag),
   slotId=slot and slot:getID()or false,slotSame=slot==bag}
 end
 for _,name in ipairs(F.namesFor(ids))do
  local spec=ids.items[name];local owner=(name=='target'or ids.case=='worn-bag'and name=='cancelled')and source or root;local item=owner and find(owner,spec.id)
  local worn=player:getWornItems():getItemById(spec.id)
  local slot=item and player:getWornItem(item:getBodyLocation())
  value.items[name]={id=spec.id,present=item~=nil,type=item and item:getFullType()or false,
   exactOwner=item and item:getContainer()==owner or false,wetness=item and item:getWetness()or false,
   canonicalWorn=item and player:getWornItems():contains(item)or false,wornId=worn and worn:getID()or false,
   wornSame=item~=nil and worn==item,slotId=slot and slot:getID()or false,slotSame=item~=nil and slot==item}
 end
 if ids.capacityProfile then
  local ok,payload=pcall(function()assert(source and bag,'canonical profile bag missing');return capacityModule().snapshot({player=player,ids=ids,source=source,bag=bag})end)
  value.capacityPayload={ready=ok,detail=ok and payload or tostring(payload)}
 end
 return value
end
function F.verify(s)
 if s.ids.nativeWearSetup and not s.wearBaseline then return end
 local value=F.snapshot(s)
 for _,name in ipairs(F.namesFor(s.ids))do
  local item=value.items[name];local cap=s.ids.items[name].cap
  local restored=(name=='target'or s.ids.case=='worn-bag'and name=='cancelled')and(s.ids.case=='worn-bag'or s.ids.case=='world')
  if s.ids.restoration and s.ids.mode=='native' then restored=false end
  local expectedRoot=restored and 0 or 1
  local expectedActor=restored and s.ids.case=='world'and 0 or 1
  local expectedSource=(s.ids.case=='root'or s.ids.case=='worn'or s.ids.case=='worn-prepared'or restored)and 1 or 0
  if s.ids.wearSwap then
   if item.counts.root~=1 or item.counts.actor~=1 or item.counts.source~=1 or item.worn~=(name=='incoming')then return end
   if name=='incoming'or name=='displaced'then if not(item.wetness>=0 and item.wetness<=s.ids.items[name].initial)then return end
   elseif not(item.wetness>=0 and item.wetness<=cap+.01)then return end
  elseif item.counts.root~=expectedRoot or item.counts.actor~=expectedActor or item.counts.source~=expectedSource or item.worn~=(s.ids.wornPrepared and name=='cancelled'and s.ids.mode=='toolkit'or false)then return end
  if s.ids.wearSwap then -- Above branch owns this case's exact final outcomes.
  elseif name=='cancelled'and s.ids.wornPrepared and s.ids.mode=='toolkit'then
   -- Still-worn ClothingWetness keeps drying naturally after pending cancellation.
   -- Zero paid effect is proved by the cancelled native members, not wetness.
   if not(item.wetness>=0 and item.wetness<=s.ids.items[name].initial)then return end
  elseif name=='cancelled'and not((s.ids.case=='worn-bag'or s.ids.wornPrepared)and s.ids.mode=='native')then if item.wetness<=80 then return end
  elseif item.wetness<cap-5 or item.wetness>cap+.01 then return end
 end
 if F.observesClothing(s.ids)then value.unequipTransitions=s.unequipTransitions or{} end
 if s.ids.wearSwap then if not s.swapTransition then return end;value.swapTransition=s.swapTransition end
 return value
end
function F.dispose(s)
 assert(F.verify(s),'wring fixture must verify before cleanup');local root=s.player:getInventory()
 if s.original then
  local item=s.items.target;assert(not s.player:getWornItems():contains(item));s.player:setWornItem(item:getBodyLocation(),s.original)
  if isServer()then sendClothing(s.player,item:getBodyLocation(),s.original)end
 end
 if F.observesClothing(s.ids)then for _,name in ipairs(s.ids.wearSwap and F.swapNames or{'target','cancelled'})do local item=s.items[name]
  if s.player:getWornItems():contains(item)then s.player:removeWornItem(item);if isServer()then sendClothing(s.player,item:getBodyLocation(),nil)end end
 end end
 if s.bag then s.player:removeWornItem(s.bag,false);if isServer()then sendClothing(s.player,s.bag:canBeEquipped(),nil)end end
 for _,name in ipairs(F.namesFor(s.ids))do local item=s.items[name];local owner=(name=='target'or s.ids.case=='worn-bag'and name=='cancelled')and s.source or root
  assert(item:getContainer()==owner);owner:Remove(item);if isServer()then sendRemoveItemFromContainer(owner,item)end
 end
 if s.bag then root:Remove(s.bag);if isServer()then sendRemoveItemFromContainer(root,s.bag)end end
 if s.shelf then s.shelf:getSquare():transmitRemoveItemFromSquare(s.shelf)end
end
return F
