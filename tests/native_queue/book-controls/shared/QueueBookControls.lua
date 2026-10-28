-- Only SP/server authority writes the disposable scene and equipment. Replica
-- admission observes exact IDs; actor-local read counters are seeded once before baseline.
local F={sources={'root','worn-bag','world'}}
function F.same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not F.same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function id(item)return item and item:getID()or false end
function F.find(container,wanted)
 local items=container:getItems()
 for i=0,items:size()-1 do local item=items:get(i)
  if item:getID()==wanted then return item end
  if instanceof(item,'InventoryContainer')then local found=F.find(item:getItemContainer(),wanted);if found then return found end end
 end
end
local function object(spec,kind)
 local square=getCell():getGridSquare(spec.x,spec.y,spec.z)
 if not square then return end
 for i=0,square:getObjects():size()-1 do local value=square:getObjects():get(i)
  if value:getObjectIndex()==spec.index and instanceof(value,kind)then return value end
 end
end
local function identity(value)local s=value:getSquare();return{x=s:getX(),y=s:getY(),z=s:getZ(),index=value:getObjectIndex()}end
function F.refresh(s)
 local root=s.player:getInventory();s.bag=s.ids.bag and F.find(root,s.ids.bag.id)or nil
 s.tv=object(s.ids.tv,'IsoTelevision');s.shelf=object(s.ids.shelf,'IsoThumpable')
 if not s.tv or not s.shelf or s.ids.bag and not s.bag then return false end
 s.data=s.tv:getDeviceData();s.source=s.ids.source=='root'and root or s.ids.source=='worn-bag'and s.bag:getItemContainer()or s.shelf:getContainer()
 s.front=F.find(root,s.ids.front.id)or F.find(s.shelf:getContainer(),s.ids.front.id)
 s.tail=F.find(root,s.ids.tail.id);s.pen=F.find(root,s.ids.pen.id)
 return s.pen~=nil and s.pen:getFullType()==s.ids.pen.type and s.front~=nil and s.tail~=nil and s.front:getFullType()==s.ids.front.type and s.tail:getFullType()==s.ids.tail.type
end
function F.snapshot(s)
 assert(F.refresh(s),'exact book/scene replica identity missing')
 local p,root=s.player,s.player:getInventory();local items,worn={},{}
 local function scan(container,where)
  local values=container:getItems()
  for i=0,values:size()-1 do local item=values:get(i)
   items[#items+1]={id=id(item),type=item:getFullType(),container=where,condition=item:getCondition(),favorite=item:isFavorite(),count=item:getCount()}
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID())end
  end
 end
 scan(root,'root');scan(s.shelf:getContainer(),'world');table.sort(items,function(a,b)return a.id<b.id end)
 local values=p:getWornItems()
 for i=0,values:size()-1 do local v=values:get(i);worn[#worn+1]={id=id(v:getItem()),location=tostring(v:getLocation())}end
 table.sort(worn,function(a,b)return a.location<b.location end)
 local v=p:getHumanVisual();local hair,beard=v:getHairColor(),v:getBeardColor()
 local result={case=s.ids.case,items=items,worn=worn,hands={primary=id(p:getPrimaryHandItem()),secondary=id(p:getSecondaryHandItem())},
  appearance={hair=v:getHairModel()or'',beard=v:getBeardModel()or'',hairColor={r=hair:getRedFloat(),g=hair:getGreenFloat(),b=hair:getBlueFloat()},beardColor={r=beard:getRedFloat(),g=beard:getGreenFloat(),b=beard:getBlueFloat()}},
  books={},volume=s.data:getDeviceVolume(),powered=s.data:getIsTurnedOn(),bagWorn=s.bag and p:getWornItem(s.bag:canBeEquipped())==s.bag or false}
 for _,name in ipairs({'front','tail'})do local book=s[name]
  result.books[name]={id=id(book),type=book:getFullType(),pages=book:getAlreadyReadPages(),characterPages=p:getAlreadyReadPages(book:getFullType()),total=book:getNumberOfPages(),
   container=book:getContainer()==root and'root'or book:getContainer()==s.source and s.ids.source or'other',favorite=book:isFavorite()}
 end
 return result
end
function F.dispose(s)
 assert(not isClient(),'fixture disposal requires authority')
 local p=s.player
 F.restoreCapacity(s)
 if s.bag and p:getWornItem(s.bag:canBeEquipped())==s.bag then p:removeWornItem(s.bag,false);if isServer()then sendClothing(p,s.bag:canBeEquipped(),nil)end end
 for _,name in ipairs({'front','tail','pen','bag'})do local spec=s.ids[name];local item=spec and(F.find(p:getInventory(),spec.id)or F.find(s.shelf:getContainer(),spec.id))
  if item then
   if p:getPrimaryHandItem()==item then p:setPrimaryHandItem(nil)end
   if p:getSecondaryHandItem()==item then p:setSecondaryHandItem(nil)end
   local owner=item:getContainer();owner:Remove(item);if isServer()then sendRemoveItemFromContainer(owner,item)end
  end
 end
 for _,value in ipairs({s.shelf,s.tv,s.generator})do value:getSquare():transmitRemoveItemFromSquare(value)end
 if isServer()then sendEquip(p)end
end
function F.prepare(player,case,previous)
 assert(not isClient(),'book controls scene requires authority')
 if previous then F.dispose(previous)end
 local source,control=case:match('^(.-)/(.+)$');local base=control and control:gsub('%-capacity%-lost$','');assert(source and(base=='header-cancel'or base=='reader-child-cancel'or base=='move-volume'or base=='move-equip'or base=='return-child-cancel'),'unknown book controls case')
 assert((base~='return-child-cancel'and control==base)or source~='root','a root book has no native borrowed return')
 assert(control==base or control==base..'-capacity-lost'and(base=='header-cancel'or base=='move-volume'),'unknown capacity control')
 player:setPrimaryHandItem(nil);player:setSecondaryHandItem(nil)
 player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
 local origin=require('QueueEnergyPlacement')(player);local x,y,z=origin:getX(),origin:getY(),origin:getZ()
 local shelfSquare=assert(getCell():getGridSquare(x,y-1,z));local tvSquare=assert(getCell():getGridSquare(x-1,y,z))
 local generator=IsoGenerator.new(assert(instanceItem('Base.Generator')),getCell(),assert(getCell():getGridSquare(x,y+1,z)))
 generator:setCondition(100);generator:setFuel(10);generator:setActivated(true)
 local shelf=IsoThumpable.new(getCell(),shelfSquare,'furniture_storage_01_8',false,{})
 shelf:setCanPassThrough(true);shelf:setIsContainer(true);shelf:setName('Book controls fixture');shelfSquare:AddSpecialObject(shelf)
 local world=assert(shelf:getContainer());world:setType('shelf');world:setCapacity(100);world:setExplored(true)
 local tv=IsoTelevision.new(getCell(),tvSquare,assert(getSprite('appliances_television_01_4')));tvSquare:AddSpecialObject(tv)
 local data=assert(tv:getDeviceData());data:setIsBatteryPowered(false);data:setIsPortable(false);data:setPower(1);data:setTurnedOnRaw(true);data:setDeviceVolumeRaw(.5)
 getGameTime():setTimeOfDay(12);assert(data:canBePoweredHere()and tvSquare:haveElectricity(),'authority TV power absent')
 local root=player:getInventory();local bag
 if source=='worn-bag'then
  bag=assert(root:AddItem('Base.Bag_Military'));local slot=bag:canBeEquipped();local old=player:getWornItem(slot)
  if old then player:removeWornItem(old,false)end
  player:setWornItem(slot,bag);bag:getItemContainer():setExplored(true)
 end
 local container=source=='root'and root or source=='worn-bag'and bag:getItemContainer()or world
 assert(source=='root'or source=='worn-bag'or source=='world','unknown source')
 local ids={case=case,source=source,control=control,actor=player:getOnlineID(),tv=identity(tv),shelf=identity(shelf),
  origin={x=x,y=y,z=z},targetVolume=.25,initialVolume=.5,bag=bag and{id=id(bag),type=bag:getFullType(),location=tostring(bag:canBeEquipped())}or false}
 local pen=assert(root:AddItem('Base.Pen'));pen:setFavorite(true);ids.pen={id=id(pen),type=pen:getFullType()}
 for _,name in ipairs({'front','tail'})do
  local kind=name=='front'and'Base.BookCarpentry1'or'Base.BookCooking1';local item=assert((name=='front'and container or root):AddItem(kind));item:setFavorite(true)
  local total=item:getNumberOfPages();local initial=total-(name=='front'and 2 or 1);assert(initial>0)
  item:setAlreadyReadPages(initial);player:setAlreadyReadPages(kind,initial);ids[name]={id=id(item),type=kind,total=total,initial=initial}
 end
 player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Cooking,0)
 if isServer()then
  shelf:transmitCompleteItemToClients();tv:transmitCompleteItemToClients()
  if bag then sendAddItemToContainer(root,bag);sendClothing(player,bag:canBeEquipped(),bag)end
  for _,name in ipairs({'front','tail','pen'})do local item=F.find(root,ids[name].id);if item and item:getContainer()==root then sendAddItemToContainer(root,item)end end
 end
 if isServer()then sendEquip(player)end
 local s={player=player,ids=ids,shelf=shelf,tv=tv,data=data,generator=generator,bag=bag};ids.baseline=F.snapshot(s);return s
end
local seeded={}
function F.resolve(player,ids)
 if isClient()and player:getOnlineID()~=ids.actor then return end
 local s={player=player,ids=ids};if not F.refresh(s)then return end
 if not seeded[ids]then
  -- Actor-local reading caches are not equipment replication. First wait for
  -- all authoritative inventory, hands, worn slots and visual values verbatim.
  local actual=F.snapshot(s)
  for _,name in ipairs({'items','worn','hands','appearance','bagWorn','volume','powered'})do if not F.same(actual[name],ids.baseline[name])then return end end
  for _,name in ipairs({'front','tail'})do s[name]:setAlreadyReadPages(ids[name].initial);player:setAlreadyReadPages(ids[name].type,ids[name].initial)end
  player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Cooking,0);seeded[ids]=true
 end
 if F.same(F.snapshot(s),ids.baseline)then return s end
end
function F.expected(s,boundary,native)
 local function copy(value)
  if type(value)~='table'then return value end
  local result={};for k,v in pairs(value)do result[k]=copy(v)end;return result
 end
 local result=copy(s.ids.baseline)
 local base=s.ids.control:gsub('%-capacity%-lost$','');local lost=s.ids.control~=base
 local cancelled=not native and(base=='header-cancel'or base=='reader-child-cancel')
 for _,name in ipairs({'front','tail'})do
  local pages=name=='front'and cancelled and boundary.before.books.front.pages or name=='tail'and native and lost and s.ids.tail.initial or s.ids[name].total
  result.books[name].pages=pages;result.books[name].characterPages=pages
 end
 if lost or not native and s.ids.control=='return-child-cancel'then
  result.books.front.container='root'
  for _,entry in ipairs(result.items)do if entry.id==s.ids.front.id then entry.container='root'end end
 end
 result.volume=native and lost and s.ids.initialVolume or s.ids.targetVolume
 result.hands.primary=native and lost and false or s.ids.pen.id
 if native and lost then result.hands.primary=false end
 return result
end
function F.capacityLost(s,requestedAt,acceptedAt)
 assert(not isClient()and s.ids.source~='root','capacity change requires borrowed source authority')
 assert(F.refresh(s)and s.front:getContainer()==s.player:getInventory(),'capacity changed after the book already returned')
 assert(not s.capacityBefore,'duplicate capacity intervention')
 s.capacityBefore=s.source:getCapacity();assert(s.capacityBefore>0,'source capacity was not initially available')
 s.source:setCapacity(0)
 local result={case=s.ids.case,actor=s.player:getOnlineID(),source=s.ids.source,itemId=s.ids.front.id,itemType=s.ids.front.type,
  before=s.capacityBefore,after=s.source:getCapacity(),roomAfter=s.source:hasRoomFor(s.player,s.front),bookRoot=true,
  requestedAt=requestedAt,acceptedAt=acceptedAt,at=getTimestampMs(),authority=true}
 assert(result.after==0 and not result.roomAfter,'authority capacity intervention did not deny the book')
 return result
end
function F.restoreCapacity(s)
 if s.capacityBefore then assert(not isClient(),'capacity restoration requires authority');s.source:setCapacity(s.capacityBefore);s.capacityBefore=nil end
end
return F
