local P=require 'QueueEnergyPlacement'
local F={}
local function identity(o)local s=o:getSquare();return {x=s:getX(),y=s:getY(),z=s:getZ(),index=o:getObjectIndex()}end
local function resolve(id)
 local s=getCell():getGridSquare(id.x,id.y,id.z);if not s then return end
 for i=0,s:getObjects():size()-1 do local o=s:getObjects():get(i)
  if o:getObjectIndex()==id.index and instanceof(o,'IsoRadio')then return o end
 end
end
local function book(p,kind)
 local i=assert(p:getInventory():AddItem(kind));local n=i:getNumberOfPages();assert(n>2)
 i:setAlreadyReadPages(n-2);p:setAlreadyReadPages(kind,n-2)
 return i,{id=i:getID(),type=kind,pages=n,initial=n-2}
end
function F.prepare(player,case,mode,placement,proof,previous)
 assert((case=='root' or case=='worn-bag' or case=='world') and P.at(player,placement))
 if previous then F.dispose(previous)end
 getGameTime():setTimeOfDay(12)
 local x,y,z=placement.x,placement.y,placement.z
 local square=assert(getCell():getGridSquare(x-1,y,z))
 local function radio()
  local o=IsoRadio.new(getCell(),square,assert(getSprite('appliances_radio_01_0')));square:AddSpecialObject(o)
  local d=assert(o:getDeviceData());d:setIsBatteryPowered(true);d:setIsPortable(false);d:setIsTelevision(false)
  d:setTurnedOnRaw(false);d:setHasBattery(false);d:setPower(0);assert(not d:getHasBattery() and d:getPower()==0);return o,d
 end
 local a,da=radio();local b,db=radio();assert(a:getObjectIndex()<b:getObjectIndex())
 local root=player:getInventory();local source,bag,shelf=root,nil,nil
 if case=='worn-bag'then
  bag=assert(root:AddItem('Base.Bag_Military'));local slot=assert(bag:canBeEquipped())
  assert(not player:getWornItem(slot),'battery fixture needs an unoccupied bag slot')
  player:setWornItem(slot,bag);source=bag:getItemContainer();source:setExplored(true)
 elseif case=='world'then
  local sq=assert(getCell():getGridSquare(x,y-1,z))
  shelf=IsoThumpable.new(getCell(),sq,'furniture_storage_01_8',false,{})
  shelf:setCanPassThrough(true);shelf:setIsContainer(true);shelf:setName('Battery fixture')
  sq:AddSpecialObject(shelf);source=assert(shelf:getContainer());source:setType('shelf');source:setCapacity(100);source:setExplored(true)
 end
 local battery=assert(source:AddItem('Base.Battery'));assert(battery:getCurrentUses()>0)
 local front,frontID=book(player,'Base.BookCarpentry1');local tail,tailID=book(player,'Base.BookCooking1')
 local ids={case=case,mode=mode,origin=placement,placementProof=proof,wrong=identity(a),target=identity(b),
  battery={id=battery:getID(),uses=battery:getCurrentUses(),maxUses=battery:getMaxUses()},front=frontID,tail=tailID,
  source={kind=case,bag=bag and {id=bag:getID(),type=bag:getFullType(),location=tostring(bag:canBeEquipped())}or false,
   world=shelf and identity(shelf)or false}}
 if isServer()then a:transmitCompleteItemToClients();b:transmitCompleteItemToClients()
  if shelf then shelf:transmitCompleteItemToClients()end
  if bag then sendAddItemToContainer(root,bag);sendClothing(player,bag:canBeEquipped(),bag)end
  for _,item in ipairs({front,tail})do sendAddItemToContainer(root,item)end
  if case=='root'then sendAddItemToContainer(root,battery)end end
 local state={player=player,wrong=a,target=b,wrongData=da,data=db,battery=battery,front=front,tail=tail,ids=ids,source=source,bag=bag,shelf=shelf}
 state.input=F.snapshot(state);return state
end
local function sourceFor(player,ids)
 local root=player:getInventory();local spec=ids.source
 if spec.kind=='root'then return root end
 if spec.kind=='worn-bag'then
  local bag=root:getItemById(spec.bag.id)
  if not bag or bag:getContainer()~=root or bag:getFullType()~=spec.bag.type
   or tostring(bag:canBeEquipped())~=spec.bag.location or player:getWornItem(bag:canBeEquipped())~=bag then return end
  return bag:getItemContainer(),bag
 end
 if spec.kind=='world'then
  local id=spec.world;local sq=getCell():getGridSquare(id.x,id.y,id.z);if not sq then return end
  for i=0,sq:getObjects():size()-1 do local o=sq:getObjects():get(i)
   if o:getObjectIndex()==id.index and instanceof(o,'IsoThumpable')and o:getContainer()then return o:getContainer(),nil,o end
  end
 end
end
function F.resolve(player,ids)
 local a,b=resolve(ids.wrong),resolve(ids.target);local root=player:getInventory()
 local source,bag,shelf=sourceFor(player,ids);if not source then return end
 local battery,front,tail=source:getItemById(ids.battery.id),root:getItemById(ids.front.id),root:getItemById(ids.tail.id)
 if not a or not b or a==b or not battery or not front or not tail or not P.at(player,ids.origin)then return end
 if battery:getContainer()~=source or front:getContainer()~=root or tail:getContainer()~=root then return end
 local da,db=a:getDeviceData(),b:getDeviceData();if da:getHasBattery()or db:getHasBattery()then return end
 for name,item in pairs({front=front,tail=tail})do local spec=ids[name];item:setAlreadyReadPages(spec.initial);player:setAlreadyReadPages(spec.type,spec.initial)end
 return {player=player,wrong=a,target=b,wrongData=da,data=db,battery=battery,front=front,tail=tail,ids=ids,source=source,bag=bag,shelf=shelf}
end
function F.snapshot(s)
 local root=s.player:getInventory();local ids=s.ids
 assert(resolve(ids.wrong)==s.wrong and resolve(ids.target)==s.target and s.data:getParent()==s.target and s.wrongData:getParent()==s.wrong)
 local source,bag,shelf=sourceFor(s.player,ids)
 assert(source==s.source and bag==s.bag and shelf==s.shelf,'battery source identity changed')
 local sourceItem=source:getItemWithID(ids.battery.id);local rootItem=root:getItemWithID(ids.battery.id)
 local out={case=ids.case,source=ids.source,sourceCount=sourceItem and 1 or 0,rootCount=rootItem and 1 or 0,actorCount=0,wrong={identity=identity(s.wrong),battery=s.wrongData:getHasBattery(),power=s.wrongData:getPower()},
  target={identity=identity(s.target),battery=s.data:getHasBattery(),power=s.data:getPower()},inputPresent=sourceItem~=nil or rootItem~=nil,
  batteries={},books={}}
 local function scan(container)
  local items=container:getItems();for i=0,items:size()-1 do local item=items:get(i)
   if item:getID()==ids.battery.id then out.actorCount=out.actorCount+1 end
   if item:getFullType()=='Base.Battery'then out.batteries[#out.batteries+1]={id=item:getID(),uses=item:getCurrentUses(),maxUses=item:getMaxUses()}end
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer())end
  end
 end
 scan(root);out.inputPresent=out.actorCount>0 or sourceItem~=nil
 table.sort(out.batteries,function(a,b)return a.id<b.id end)
 for _,name in ipairs({'front','tail'})do local spec=ids[name];local item=root:getItemById(spec.id)
  out.books[name]={id=spec.id,root=item~=nil and item:getContainer()==root,pages=item and item:getAlreadyReadPages()or -1,
   characterPages=s.player:getAlreadyReadPages(spec.type)}end
 return out
end
function F.baseline(s)
 local v=F.snapshot(s);if v.wrong.battery or not v.target.battery or v.inputPresent
  or math.abs(v.target.power-s.ids.battery.uses/s.ids.battery.maxUses)>.011 then return end
 s.baseline=v;return v
end
function F.verify(s)
 local v=F.snapshot(s);if not s.baseline or not s.input or v.wrong.battery or v.target.battery or v.inputPresent then return end
 local before={};for _,item in ipairs(s.input.batteries)do if item.id~=s.ids.battery.id then before[item.id]=item end end
 local outputs=0
 for _,item in ipairs(v.batteries)do local prior=before[item.id]
  if prior then if item.uses~=prior.uses or item.maxUses~=prior.maxUses then return end;before[item.id]=nil
  else if item.id==s.ids.battery.id or item.maxUses~=s.ids.battery.maxUses or math.abs(item.uses-s.ids.battery.uses)>1 then return end;outputs=outputs+1 end
 end
 if outputs~=1 then return end
 for _ in pairs(before)do return end
 for _,name in ipairs({'front','tail'})do if not v.books[name].root or v.books[name].pages~=s.ids[name].pages or v.books[name].characterPages~=s.ids[name].pages then return end end
 return v
end
function F.dispose(s)
 assert(F.verify(s),'battery fixture must be verified before cleanup')
 local root=s.player:getInventory();local initial={}
 for _,entry in ipairs(s.input.batteries)do initial[entry.id]=true end
 local final=F.snapshot(s);local output
 for _,entry in ipairs(final.batteries)do if not initial[entry.id]then assert(not output);output=entry.id end end
 assert(output,'missing exact verified output before cleanup')
 if s.bag then local slot=s.bag:canBeEquipped();assert(s.player:getWornItem(slot)==s.bag)
  s.player:removeWornItem(s.bag,false);if isServer()then sendClothing(s.player,slot,nil)end end
 for _,id in ipairs({s.ids.front.id,s.ids.tail.id,output,s.bag and s.bag:getID()or -1})do
  local item=root:getItemById(id);if id~=-1 then assert(item and item:getContainer()==root,'fixture cleanup item missing')
   root:Remove(item);if isServer()then sendRemoveItemFromContainer(root,item)end end
 end
 for _,object in ipairs({s.wrong,s.target})do object:getSquare():transmitRemoveItemFromSquare(object)end
 if s.shelf then s.shelf:getSquare():transmitRemoveItemFromSquare(s.shelf)end
end
return F
