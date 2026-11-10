local P=require 'QueueEnergyPlacement'
local F={names={'front','target','tail','cancelled'}}
function F.nativeWetnessContract(item)
 local location=item:getBodyLocation();local nativeShoe=location=='Shoes'
 return{bodyLocation=tostring(location),bodyLocationClass=getClassSimpleName(location),
  nativeShoe=nativeShoe,cap=nativeShoe and 60 or 10}
end
local function identity(o)local s=o:getSquare();return{x=s:getX(),y=s:getY(),z=s:getZ(),index=o:getObjectIndex()}end
local function sourceFor(player,ids,preparingWear)
 local root=player:getInventory()
 if ids.source.kind=='root'or ids.source.kind=='worn'then return root end
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
function F.snapshot(s)
 local root=s.player:getInventory();local source,bag,shelf=sourceFor(s.player,s.ids)
 assert(source==s.source and bag==s.bag and shelf==s.shelf,'wring source identity changed')
 local out={case=s.ids.case,source=s.ids.source,items={}}
 for _,name in ipairs(F.names)do
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
 end
 return out
end
function F.prepare(player,case,mode,placement,proof,previous)
 assert((case=='root'or case=='worn'or case=='worn-bag'or case=='world')and P.atCentered(player,placement))
 if previous then F.dispose(previous)end
 local precipitation=assert(getClimateManager():getClimateFloat(ClimateManager.FLOAT_PRECIPITATION_INTENSITY))
 precipitation:setEnableAdmin(true);precipitation:setAdminValue(0);precipitation:setFinalValue(0)
 local root=player:getInventory();local source,bag,shelf=root,nil,nil
 if case=='worn-bag'then
  bag=assert(root:AddItem('Base.Bag_Military'));assert(not player:getWornItem(bag:canBeEquipped()),'wring bag slot occupied')
  if not isServer()then player:setWornItem(bag:canBeEquipped(),bag)end
  source=bag:getItemContainer();source:setExplored(true)
 elseif case=='world'then
  local square=assert(getCell():getGridSquare(placement.x,placement.y-1,placement.z))
  shelf=IsoThumpable.new(getCell(),square,'furniture_storage_01_8',false,{})
  shelf:setCanPassThrough(true);shelf:setIsContainer(true);shelf:setName('Wring fixture');square:AddSpecialObject(shelf)
  source=assert(shelf:getContainer());source:setType('shelf');source:setCapacity(100);source:setExplored(true)
 end
 local ids={case=case,mode=mode,origin=placement,placementProof=proof,items={},source={kind=case,bag=bag and bag:getID()or false,world=shelf and identity(shelf)or false}}
 local state={player=player,ids=ids,source=source,bag=bag,shelf=shelf,items={}}
 for _,name in ipairs(F.names)do
  local shoes=name=='tail'or name=='target'and(case=='worn'or case=='world')
  local owner=name=='target'and source or root
  local item=assert(owner:AddItem(shoes and'Base.Shoes_FlipFlop'or'Base.Socks_Ankle'))
  assert(instanceof(item,'Clothing'));item:setWetness(100)
  -- B42 returns ItemBodyLocation userdata. Preserve the native string comparison,
  -- including its current false result for real shoes; do not repair vanilla here.
  assert(item:getBodyLocation()==(shoes and ItemBodyLocation.SHOES or ItemBodyLocation.SOCKS),'fixture body location differs')
  local spec=F.nativeWetnessContract(item)
  spec.id=item:getID();spec.type=item:getFullType();spec.initial=item:getWetness();spec.weight=item:getActualWeight()
  state.items[name]=item;ids.items[name]=spec
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
  for _,name in ipairs(F.names)do local item=state.items[name]
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
 for _,name in ipairs(F.names)do
  local spec=ids.items[name];local owner=name=='target'and source or player:getInventory();local item=find(owner,spec.id)
  if not item or item:getContainer()~=owner or item:getFullType()~=spec.type or item:getWetness()<=80 then return end
  state.items[name]=item
 end
 if ids.case=='worn'and not preparingWear and not player:getWornItems():contains(state.items.target)then return end
 return state
end
function F.wearBaseline(s)
 local source,bag,shelf=sourceFor(s.player,s.ids)
 if source~=s.source or bag~=s.bag or shelf~=s.shelf then return end
 if s.ids.case=='worn'and s.player:getWornItem(s.items.target:getBodyLocation())~=s.items.target then return end
 local value=F.snapshot(s)
 for _,name in ipairs(F.names)do
  local item=value.items[name];local borrowed=name=='target'and(s.ids.case=='worn-bag'or s.ids.case=='world')
  if item.counts.root~=(borrowed and 0 or 1)or item.counts.actor~=(name=='target'and s.ids.case=='world'and 0 or 1)
   or item.counts.source~=((s.ids.case=='root'or s.ids.case=='worn'or name=='target')and 1 or 0)
   or item.worn~=(s.ids.case=='worn'and name=='target')or item.wetness<=80 then return end
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
 for _,name in ipairs(F.names)do
  local spec=ids.items[name];local owner=name=='target'and source or root;local item=owner and find(owner,spec.id)
  local worn=player:getWornItems():getItemById(spec.id)
  local slot=item and player:getWornItem(item:getBodyLocation())
  value.items[name]={id=spec.id,present=item~=nil,type=item and item:getFullType()or false,
   exactOwner=item and item:getContainer()==owner or false,wetness=item and item:getWetness()or false,
   canonicalWorn=item and player:getWornItems():contains(item)or false,wornId=worn and worn:getID()or false,
   wornSame=item~=nil and worn==item,slotId=slot and slot:getID()or false,slotSame=item~=nil and slot==item}
 end
 return value
end
function F.verify(s)
 if s.ids.nativeWearSetup and not s.wearBaseline then return end
 local value=F.snapshot(s)
 for _,name in ipairs(F.names)do
  local item=value.items[name];local cap=s.ids.items[name].cap
  local restored=name=='target'and(s.ids.case=='worn-bag'or s.ids.case=='world')
  local expectedRoot=restored and 0 or 1
  local expectedActor=restored and s.ids.case=='world'and 0 or 1
  local expectedSource=(s.ids.case=='root'or s.ids.case=='worn'or restored)and 1 or 0
  if item.counts.root~=expectedRoot or item.counts.actor~=expectedActor or item.counts.source~=expectedSource or item.worn then return end
  if name=='cancelled'then if item.wetness<=80 then return end
  elseif item.wetness<cap-5 or item.wetness>cap+.01 then return end
 end
 return value
end
function F.dispose(s)
 assert(F.verify(s),'wring fixture must verify before cleanup');local root=s.player:getInventory()
 if s.original then
  local item=s.items.target;assert(not s.player:getWornItems():contains(item));s.player:setWornItem(item:getBodyLocation(),s.original)
  if isServer()then sendClothing(s.player,item:getBodyLocation(),s.original)end
 end
 if s.bag then s.player:removeWornItem(s.bag,false);if isServer()then sendClothing(s.player,s.bag:canBeEquipped(),nil)end end
 for _,name in ipairs(F.names)do local item=s.items[name];local owner=name=='target'and s.source or root
  assert(item:getContainer()==owner);owner:Remove(item);if isServer()then sendRemoveItemFromContainer(owner,item)end
 end
 if s.bag then root:Remove(s.bag);if isServer()then sendRemoveItemFromContainer(root,s.bag)end end
 if s.shelf then s.shelf:getSquare():transmitRemoveItemFromSquare(s.shelf)end
end
return F
