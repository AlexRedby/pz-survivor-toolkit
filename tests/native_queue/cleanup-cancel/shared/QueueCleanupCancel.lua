-- All fixture writes occur before baseline; snapshots only read native state.
local F={cases={'mask-after-removal','p4-after-pickup'}}
local resolving={}
local function recurse(container,rows,where)
 local values=container:getItems()
 for i=0,values:size()-1 do local item=values:get(i)
  rows[#rows+1]={id=item:getID(),type=item:getFullType(),container=where}
  if instanceof(item,'InventoryContainer')then recurse(item:getItemContainer(),rows,'bag:'..item:getID())end
 end
end
local function find(player,id)
 local function search(container)
  local values=container:getItems()
  for i=0,values:size()-1 do local item=values:get(i)
   if item:getID()==id then return item end
   if instanceof(item,'InventoryContainer')then local found=search(item:getItemContainer());if found then return found end end
  end
 end
 return search(player:getInventory())
end
F.find=find
-- Stock transfer construction keeps its unadjusted time in the first exact
-- native queue member even if observation first occurs after Base.begin.
function F.constructorDuration(action)
 if action.Type~='ISInventoryTransferAction'then return action.maxTime end
 local group=assert(action.queueList and action.queueList[1],'native transfer constructor member missing')
 assert(group.items and #group.items==1 and group.items[1]==action.item and type(group.time)=='number','native transfer constructor member differs')
 return group.time
end
function F.itemMatches(state,name,item)
 local id=state.ids.items[name]
 if not item or not id or item:getID()~=id then return false end
 for _,entry in ipairs(state.ids.baseline.items)do
  if entry.id==id then return item:getFullType()==entry.type end
 end
 return false
end
-- Native Host item transactions may replace item/container instances. Refresh
-- only observation references from exact authority IDs/types; never copy state.
function F.refresh(state)
 local values={}
 for name,id in pairs(state.ids.items)do
  local item=find(state.player,id)
  if not F.itemMatches(state,name,item)then
   return false,{case=state.ids.case,reason='exact live item unavailable',name=name,id=id,actualType=item and item:getFullType()or false}
  end
  values[name]=item
 end
 for name,item in pairs(values)do state[name]=item end
 if state.bag then state.source=state.bag:getItemContainer()end
 return true
end
function F.sourceMatches(state,container)
 if not state.bag or not container then return false end
 if container==state.source then return true end
 local bag=container:getContainingItem()
 return F.itemMatches(state,'bag',bag)and bag:getItemContainer()==container
  and bag:getContainer()==state.player:getInventory()and state.bag:getContainer()==state.player:getInventory()
end
function F.snapshot(state)
 if state.ids.baseline then
  local ready,detail=F.refresh(state)
  assert(ready,'exact live fixture identity missing '..tostring(detail and detail.name)..':'..tostring(detail and detail.id))
 end
 local player=state.player;local rows={};recurse(player:getInventory(),rows,'root')
 table.sort(rows,function(a,b)return a.id<b.id end)
 local result={case=state.ids.case,items=rows,primary=player:getPrimaryHandItem()and player:getPrimaryHandItem():getID()or false,
  secondary=player:getSecondaryHandItem()and player:getSecondaryHandItem():getID()or false,
  book=state.book:getAlreadyReadPages(),
  maskWorn=state.mask and player:isEquippedClothing(state.mask)or false,
  food=state.food and{hunger=state.food:getHungChange(),base=state.food:getBaseHunger(),uses=state.food:getCurrentUses()}or false,
  borrowedContainer=state.borrowed and(F.sourceMatches(state,state.borrowed:getContainer())and'bag'or state.borrowed:getContainer()==player:getInventory()and'root'or'other')or false,
  torchActive=state.torch and state.torch:isActivated()or false,
  borrowed=state.borrowed and{pages=state.borrowed:getAlreadyReadPages(),characterPages=player:getAlreadyReadPages(state.borrowed:getFullType()),total=state.borrowed:getNumberOfPages()}or false}
 return result
end
local function clearHeadwear(player)
 local worn=player:getWornItems();local old={}
 for i=0,worn:size()-1 do old[#old+1]={item=worn:get(i):getItem(),location=worn:get(i):getLocation()}end
 for _,v in ipairs(old)do
  local slot=tostring(v.location)
  if slot=='base:mask'or slot=='base:maskeyes'or slot=='base:maskfull'or slot=='base:fullhat'or slot=='base:hat'or slot=='base:fullsuithead'or slot=='base:scba'or slot=='base:scbanotank'then
   player:removeWornItem(v.item,false);if isServer()then sendClothing(player,v.location,nil)end
  end
 end
end
function F.prepare(player,id)
 assert(not isClient(),'cleanup fixture writes require SP/server authority')
 player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
 require('QueueEnergyPlacement')(player)
 -- Normalize only disposable headwear, retaining every native item in inventory.
 clearHeadwear(player)
 local root=player:getInventory();local ids={case=id,actor=player:getOnlineID(),items={},spawn={x=player:getX(),y=player:getY(),z=player:getZ()}}
 local state={player=player,ids=ids}
 local function seed(name,kind,container)
  local item=assert((container or root):AddItem(kind));state[name]=item;ids.items[name]=item:getID();return item
 end
 seed('book','Base.BookCarpentry1');ids.pages=state.book:getNumberOfPages();ids.initial=ids.pages-1
 player:getXp():setXPToLevel(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Woodwork,0)
 state.book:setAlreadyReadPages(ids.initial);player:setAlreadyReadPages(state.book:getFullType(),ids.initial)
 if id=='mask-after-removal'then
  seed('mask','Base.Hat_GasMask_nofilter');seed('food','Base.Cereal')
  assert(not state.mask:hasTag(ItemTag.CAN_EAT),'mask must obstruct native eating')
  player:setWornItem(state.mask:getBodyLocation(),state.mask)
  assert(ISInventoryPaneContextMenu==nil or ISInventoryPaneContextMenu.getEatingMask(player,false)==state.mask,'fixture mask is not the native eating mask')
  player:getStats():set(CharacterStat.HUNGER,.5)
  ids.maskLocation=tostring(state.mask:getBodyLocation())
 elseif id=='p4-after-pickup'then
  seed('bag','Base.Bag_Schoolbag');state.source=state.bag:getItemContainer();state.source:setExplored(true)
  player:setWornItem(state.bag:canBeEquipped(),state.bag)
  seed('borrowed','Base.BookFirstAid1',state.source);seed('torch','Base.Torch');seed('secondary','Base.Screwdriver')
  state.torch:setUsedDelta(1);state.torch:setActivated(true)
  player:setPrimaryHandItem(state.torch);player:setSecondaryHandItem(state.secondary)
  player:getXp():setXPToLevel(Perks.Doctor,0);player:setPerkLevelDebug(Perks.Doctor,0)
  ids.borrowedType=state.borrowed:getFullType();ids.borrowedPages=state.borrowed:getNumberOfPages();ids.borrowedInitial=ids.borrowedPages-1
  assert(state.borrowed:getFullType()~=state.book:getFullType(),'borrowed and independent books must have distinct page caches')
  state.borrowed:setAlreadyReadPages(ids.borrowedInitial);player:setAlreadyReadPages(state.borrowed:getFullType(),ids.borrowedInitial)
  ids.bagLocation=tostring(state.bag:canBeEquipped())
 else error('unknown cleanup cancellation case')end
 if isServer()then
  -- A root bag serializes its nested contents; a second child packet duplicates setup.
  for _,itemID in pairs(ids.items)do local item=assert(find(player,itemID));if item:getContainer()==root then sendAddItemToContainer(root,item)end end
  if state.mask then sendClothing(player,state.mask:getBodyLocation(),state.mask)end
  if state.bag then sendClothing(player,state.bag:canBeEquipped(),state.bag);sendEquip(player)end
 end
 ids.baseline=F.snapshot(state);return state
end
local function baselineDifference(state,actual)
 local expected=state.ids.baseline;local fields={}
 for _,name in ipairs({'primary','secondary','book','maskWorn','borrowedContainer','torchActive'})do
  if actual[name]~=expected[name]then fields[#fields+1]={name=name,expected=expected[name],actual=actual[name]}end
 end
 for _,name in ipairs({'food','borrowed'})do
  local a,b=actual[name],expected[name]
  if type(a)=='table'and type(b)=='table'then
   for key,value in pairs(b)do if type(a[key])~='number'or math.abs(a[key]-value)>.0001 then fields[#fields+1]={name=name..'.'..key,expected=value,actual=a[key]}end end
  elseif a~=b then fields[#fields+1]={name=name,expected=b,actual=a}end
 end
 if not F.sameItems(expected.items,actual.items)then fields[#fields+1]={name='items',expected=expected.items,actual=actual.items}end
 if #fields>0 then return{case=state.ids.case,reason='baseline differs',fields=fields}end
end
F.baselineDifference=baselineDifference
function F.resolve(player,ids)
 if isClient()and player:getOnlineID()~=ids.actor then return nil,{case=ids.case,reason='actor differs',expected=ids.actor,actual=player:getOnlineID()}end
 local state=resolving[ids]
 if not state then
  state={player=player,ids=ids};local missing={}
  for name,id in pairs(ids.items)do state[name]=find(player,id);if not state[name]then missing[#missing+1]={name=name,id=id}end end
  if #missing>0 then
   table.sort(missing,function(a,b)return a.name<b.name end)
   return nil,{case=ids.case,reason='exact seeded items not replicated',missing=missing}
  end
  if state.bag then state.source=state.bag:getItemContainer()end
  -- This is disposable pre-baseline setup. Native hands packets deliberately
  -- ignore the local actor; seed only the exact authority-owned fixture items.
  local expected=assert(ids.baseline,'authority baseline missing')
  assert(expected.case==ids.case and expected.book==ids.initial,'authority tail seed differs')
  clearHeadwear(player)
  state.book:setAlreadyReadPages(expected.book);player:setAlreadyReadPages(state.book:getFullType(),expected.book)
  player:getXp():setXPToLevel(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Woodwork,0)
  if state.mask then
   assert(expected.maskWorn and tostring(state.mask:getBodyLocation())==ids.maskLocation,'authority mask seed differs')
   player:setWornItem(state.mask:getBodyLocation(),state.mask)
   assert(ISInventoryPaneContextMenu==nil or ISInventoryPaneContextMenu.getEatingMask(player,false)==state.mask,'local fixture mask is not the native eating mask')
  end
  if state.bag then
   assert(expected.primary==state.torch:getID()and expected.secondary==state.secondary:getID()and expected.torchActive
    and expected.borrowedContainer=='bag'and expected.borrowed.pages==ids.borrowedInitial
    and expected.borrowed.characterPages==ids.borrowedInitial and tostring(state.bag:canBeEquipped())==ids.bagLocation,'authority borrowed/equipment seed differs')
   player:setWornItem(state.bag:canBeEquipped(),state.bag)
   state.borrowed:setAlreadyReadPages(expected.borrowed.pages);player:setAlreadyReadPages(state.borrowed:getFullType(),expected.borrowed.characterPages)
   player:getXp():setXPToLevel(Perks.Doctor,0);player:setPerkLevelDebug(Perks.Doctor,0)
   state.torch:setUsedDelta(1);state.torch:setActivated(expected.torchActive)
   player:setPrimaryHandItem(state.torch);player:setSecondaryHandItem(state.secondary)
   if isClient()then player:updateHandEquips()end -- native client Equip sender; global sendEquip is server-only
  end
  resolving[ids]=state -- never re-seed a later gameplay/equipment change
 end
 local difference=baselineDifference(state,F.snapshot(state))
 if difference then return nil,difference end
 return state
end
function F.sameItems(before,after)
 if #before~=#after then return false end
 for i,a in ipairs(before)do local b=after[i];if a.id~=b.id or a.type~=b.type or a.container~=b.container then return false end end
 return true
end
-- Only the exact operation-owned cleanup must precede unrelated work. P4's
-- original hand/activation restoration retains its native idle-session timing.
function F.ownedCleanupBeforeTail(state,snapshot)
 if state.mask then return snapshot.maskWorn end
 return snapshot.borrowedContainer=='bag'
end
function F.restored(state,snapshot)
 if state.mask then return F.ownedCleanupBeforeTail(state,snapshot)end
 return F.ownedCleanupBeforeTail(state,snapshot)and snapshot.primary==state.torch:getID()
  and snapshot.secondary==state.secondary:getID()and snapshot.torchActive
end
return F
