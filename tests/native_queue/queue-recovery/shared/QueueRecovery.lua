-- Authority owns all scene mutations; snapshots after preparation are read-only.
local F={}
local function ids(root,nested)
 local result={};local items=root:getItems()
 for i=0,items:size()-1 do local item=items:get(i);result[#result+1]=item:getID()
  if nested and instanceof(item,'InventoryContainer')then for _,id in ipairs(ids(item:getItemContainer(),true))do result[#result+1]=id end end
 end
 table.sort(result);return result
end
local function count(root,id)
 local n=0;local items=root:getItems()
 for i=0,items:size()-1 do local item=items:get(i);if item:getID()==id then n=n+1 end
  if instanceof(item,'InventoryContainer')then n=n+count(item:getItemContainer(),id)end
 end
 return n
end
local function identity(tv)local s=tv:getSquare();return{x=s:getX(),y=s:getY(),z=s:getZ(),index=tv:getObjectIndex()}end
local function book(player,kind,left)
 local item=assert(player:getInventory():AddItem(kind));local pages=item:getNumberOfPages();assert(pages>left)
 item:setAlreadyReadPages(pages-left);player:setAlreadyReadPages(kind,pages-left)
 return item,{id=item:getID(),type=kind,pages=pages,initial=pages-left}
end
function F.prepare(player,case,mode)
 assert(case=='movement-cancel'or case=='clear-queue')
 local origin=require('QueueEnergyPlacement')(player);local x,y,z=origin:getX(),origin:getY(),origin:getZ()
 local generator=IsoGenerator.new(assert(instanceItem('Base.Generator')),getCell(),getCell():getGridSquare(x,y+1,z))
 generator:setCondition(100);generator:setFuel(10);generator:setActivated(true)
 local square=assert(getCell():getGridSquare(x-1,y,z))
 local tv=IsoTelevision.new(getCell(),square,assert(getSprite('appliances_television_01_4')));square:AddSpecialObject(tv)
 local data=assert(tv:getDeviceData());data:setMediaType(1);data:setIsBatteryPowered(false);data:setIsPortable(false)
 data:setPower(1);data:setMinChannelRange(88000);data:setMaxChannelRange(108000);data:setChannelRaw(90000)
 data:setDeviceVolumeRaw(.5);data:setMicIsMuted(false);data:setTurnedOnRaw(true);getGameTime():setTimeOfDay(12)
 local front,frontId=book(player,'Base.BookCarpentry1',3);local tail,tailId=book(player,'Base.BookCooking1',2)
 local spec={case=case,mode=mode,tv=identity(tv),front=frontId,tail=tailId,origin={x=x,y=y,z=z}}
 if isServer()then tv:transmitCompleteItemToClients();for _,item in ipairs({front,tail})do sendAddItemToContainer(player:getInventory(),item)end end
 return{player=player,tv=tv,data=data,front=front,tail=tail,ids=spec,generator=generator}
end
local function television(id)
 local square=getCell():getGridSquare(id.x,id.y,id.z);if not square then return end
 for i=0,square:getObjects():size()-1 do local o=square:getObjects():get(i)
  if o:getObjectIndex()==id.index and instanceof(o,'IsoTelevision')then return o end
 end
end
function F.resolve(player,spec)
 local root=player:getInventory();local tv=television(spec.tv)
 local front,tail=root:getItemById(spec.front.id),root:getItemById(spec.tail.id)
 if not tv or not front or not tail or front:getContainer()~=root or tail:getContainer()~=root then return end
 local p=spec.origin
 if math.floor(player:getX())~=p.x or math.floor(player:getY())~=p.y or math.floor(player:getZ())~=p.z then player:teleportTo(p.x+.5,p.y+.5,p.z);return end
 -- Actor-local seed is established before the first paid prefix/native action.
 for _,name in ipairs({'front','tail'})do local item=name=='front'and front or tail;local s=spec[name]
  assert(item:getFullType()==s.type and item:getNumberOfPages()==s.pages)
  item:setAlreadyReadPages(s.initial);player:setAlreadyReadPages(s.type,s.initial)
 end
 return{player=player,tv=tv,data=tv:getDeviceData(),front=front,tail=tail,ids=spec}
end
function F.approach(state)
 local player=state.player;local target=luautils.getCorrectSquareForWall(player,state.tv:getSquare())
 return target and math.abs(target:getX()+.5-player:getX())<=1.6 and math.abs(target:getY()+.5-player:getY())<=1.6 and player:getSquare():canReachTo(target)
end
function F.snapshot(state)
 local root=state.player:getInventory();local data=state.tv:getDeviceData();assert(television(state.ids.tv)==state.tv and data==state.data and data:getParent()==state.tv)
 local result={case=state.ids.case,tv=identity(state.tv),rootIds=ids(root),carriedIds=ids(root,true),books={},
  device={on=data:getIsTurnedOn(),power=data:getPower(),powerable=data:canBePoweredHere(),volume=data:getDeviceVolume(),channel=data:getChannel(),hasMedia=data:hasMedia()}}
 for _,name in ipairs({'front','tail'})do local spec=state.ids[name];local item=root:getItemById(spec.id)
  result.books[name]={id=spec.id,type=item and item:getFullType()or'',root=item and item:getContainer()==root or false,count=count(root,spec.id),
   pages=item and item:getAlreadyReadPages()or -1,total=item and item:getNumberOfPages()or -1,characterPages=state.player:getAlreadyReadPages(spec.type)}
 end
 return result
end
local function valid(value,state)
 local d=value.device;if not d.on or not d.powerable or d.power<=0 or d.hasMedia or d.channel~=90000 then return false end
 for _,name in ipairs({'front','tail'})do local row=value.books[name];local spec=state.ids[name]
  if not row.root or row.count~=1 or row.id~=spec.id or row.type~=spec.type or row.total~=spec.pages or row.pages~=row.characterPages then return false end
 end
 return true
end
function F.baseline(state)
 local v=F.snapshot(state);local f,t=v.books.front,v.books.tail
 if not valid(v,state)or math.abs(v.device.volume-.4)>.0001 or f.pages<=state.ids.front.initial or f.pages>=state.ids.front.pages or t.pages~=state.ids.tail.initial then return end
 state.baseline=v;return v
end
function F.verify(state)
 if not state.baseline then return end
 local v=F.snapshot(state);if not valid(v,state)then return nil,v end
 if state.ids.mode=='toolkit'then
  if math.abs(v.device.volume-.25)>.0001 or v.books.front.pages~=state.ids.front.pages or v.books.tail.pages~=state.ids.tail.pages then return nil,v end
 else
  if math.abs(v.device.volume-.4)>.0001 or v.books.front.pages~=state.baseline.books.front.pages or v.books.tail.pages~=state.ids.tail.initial then return nil,v end
 end
 local function same(a,b)if #a~=#b then return false end;for i,id in ipairs(a)do if b[i]~=id then return false end end;return true end
 if not same(v.rootIds,state.baseline.rootIds)or not same(v.carriedIds,state.baseline.carriedIds)then return nil,v end
 return v
end
return F
