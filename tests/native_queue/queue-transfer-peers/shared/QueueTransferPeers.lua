-- Disposable shared storage; only authority seeds/removes owned identities.
local JSON=require 'QueueHealthEvents'
local F={module='QueueTransferPeersTest',roles={'client1','client2'}}
local owner='PZSTQueueTransferPeersOwner'
function F.emit(event,row)print('[QUEUE_PEERS] '..event..' '..JSON.encode(row))end
function F.same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not F.same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function scan(container,callback,depth)
 depth=depth or 0
 local items=container:getItems()
 for i=0,items:size()-1 do local item=items:get(i);callback(item,depth)
  if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),callback,depth+1)end
 end
end
function F.find(s,id)
 local item,endpoint,count=nil,nil,0
 local function visit(container,where)scan(container,function(value,depth)if value:getID()==id then item,endpoint,count=value,depth==0 and where or(where..'-nested'),count+1 end end)end
 for key,store in pairs(s.stores)do visit(store,key)end
 if s.players then for _,role in ipairs(F.roles)do visit(s.players[role]:getInventory(),role..'-root')end
 else visit(s.player:getInventory(),s.role..'-root')end
 return item,endpoint,count
end
local function point(object,key)
 local square=object:getSquare();return{key=key,x=square:getX(),y=square:getY(),z=square:getZ(),index=object:getObjectIndex(),capacity=object:getContainer():getCapacity()}
end
function F.prepare(players)
 assert(isServer()and players.client1 and players.client2 and players.client1:getOnlineID()~=players.client2:getOnlineID(),'two distinct authority actors required')
 local origin=require('QueueEnergyPlacement')(players.client1)
 players.client2:teleportTo(origin:getX()+1.5,origin:getY()+.5,origin:getZ())
 local s={players=players,stores={},objects={},initial={},owned={}}
 s.origin={x=origin:getX(),y=origin:getY(),z=origin:getZ()}
 for i,key in ipairs({'source1','source2'})do
  local square=assert(getCell():getGridSquare(origin:getX()+i-1,origin:getY()-1,origin:getZ()))
  local obj=IsoThumpable.new(getCell(),square,'furniture_storage_01_8',false,{})
  obj:setCanPassThrough(true);obj:setIsContainer(true);obj:getModData()[owner]=key
  square:AddSpecialObject(obj);local store=assert(obj:getContainer());store:setType('shelf');store:setCapacity(100);store:setExplored(true)
  s.objects[key],s.stores[key]=obj,store;obj:transmitCompleteItemToClients();obj:transmitModData()
 end
 for _,role in ipairs(F.roles)do
  local player=players[role];player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
  s.initial[role]={};scan(player:getInventory(),function(item)s.initial[role][item:getID()]={ft=item:getFullType(),container=item:getContainer()}end)
 end
 getGameTime():setTimeOfDay(12);return s
end
function F.seed(s,case,index)
 assert(isServer(),'seed requires authority');assert(not s.seed,'previous phase not released')
 local ids={case=case,index=index,token='queue-peers:'..getTimestampMs()..':'..index,actors={},items={},stores={},originalRootIds={},origin=s.origin}
 s.owned={};s.seed=ids
 for _,key in ipairs({'source1','source2'})do s.stores[key]:setCapacity(100);ids.stores[#ids.stores+1]=point(s.objects[key],key)end
 local shared=case=='shared-capacity'or case=='contested-pickup'or case=='partial-accepted'
 local sharedFront
 local function add(container,ft,where)
  local item=assert(container:AddItem(ft));item:setFavorite(false);item:getModData()[owner]=ids.token
  local total=instanceof(item,'Literature')and item:getNumberOfPages()or 1
  local initial=instanceof(item,'Literature')and(total-(ft=='Base.BookCarpentry1'and 4 or 1))or 0
  if instanceof(item,'Literature')then assert(initial>0);item:setAlreadyReadPages(initial)end
  local spec={id=item:getID(),ft=ft,total=total,initial=initial};assert(not s.owned[spec.id],'duplicate owned item')
  s.owned[spec.id]=spec;ids.items[#ids.items+1]={id=spec.id,ft=ft,initialEndpoint=where}
  sendAddItemToContainer(container,item);return spec
 end
 for i,role in ipairs(F.roles)do
  local player=s.players[role];local key=shared and'source1'or('source'..i)
  local front
  if case=='contested-pickup'and sharedFront then front=sharedFront else front=add(s.stores[key],case=='partial-accepted'and'Base.Nails'or'Base.BookCarpentry1',key);sharedFront=front end
  local tail=add(player:getInventory(),'Base.BookCooking1',role..'-root')
  if case~='partial-accepted'then player:setAlreadyReadPages(front.ft,front.initial)end;player:setAlreadyReadPages(tail.ft,tail.initial)
  player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Cooking,0)
  ids.actors[#ids.actors+1]={role=role,onlineId=player:getOnlineID(),front=front,tail=tail}
  local original={};for id in pairs(s.initial[role])do original[#original+1]=id end;table.sort(original);ids.originalRootIds[role]=original
 end
 return ids
end
function F.resolve(player,seed,role)
 if not seed or not seed.actors then return end
 local s={player=player,role=role,seed=seed,stores={}}
 for _,actor in ipairs(seed.actors)do if actor.role==role then s.ids=actor end end
 if not s.ids or s.ids.onlineId~=player:getOnlineID()then return end
 for _,desc in ipairs(seed.stores)do
  local square=getCell():getGridSquare(desc.x,desc.y,desc.z)
  if not square or desc.index<0 or desc.index>=square:getObjects():size()then return end
  local object=square:getObjects():get(desc.index)
  if object:getModData()[owner]~=desc.key or not object:getContainer()then return end
  s.stores[desc.key]=object:getContainer()
 end
 local front,where,count=F.find(s,s.ids.front.id);local tail,tailWhere,tailCount=F.find(s,s.ids.tail.id)
 if count~=1 or tailCount~=1 or not front or not tail or tailWhere~=role..'-root'then return end
 s.front,s.tail=front,tail;return s
end
function F.snapshot(s)
 assert(isServer(),'physical global snapshot requires authority')
 local items={}
 for _,spec in ipairs(s.seed.items)do
  local item,endpoint,count=F.find(s,spec.id)
  assert(item and count==1 and item:getFullType()==spec.ft,'owned item absent/duplicated/replaced')
  items[#items+1]={id=spec.id,ft=spec.ft,endpoint=endpoint,count=count,pages=instanceof(item,'Literature')and item:getAlreadyReadPages()or 0}
 end
 for _,role in ipairs(F.roles)do for id,spec in pairs(s.initial[role])do
  local item,endpoint,count=F.find(s,id)
  assert(item and count==1 and(endpoint==role..'-root'or endpoint==role..'-root-nested')
   and item:getContainer()==spec.container and item:getFullType()==spec.ft,'original actor item changed')
 end end
 local capacity={};for _,key in ipairs({'source1','source2'})do
  local store=s.stores[key];capacity[key]={weight=store:getCapacityWeight(),capacity=store:getCapacity()}
  assert(capacity[key].weight<=capacity[key].capacity+.0001,'authority container overfilled')
 end
 return{case=s.seed.case,token=s.seed.token,index=s.seed.index,items=items,originalsPreserved=true,capacity=capacity}
end
function F.partialArm(s)
 assert(isServer()and s.seed.case=='partial-accepted','partial arm requires exact authority phase')
 local first,where,count=F.find(s,s.seed.actors[1].front.id)
 local second,other,n=F.find(s,s.seed.actors[2].front.id)
 assert(count==1 and n==1 and where=='source1'and other=='source1','partial items not in source')
 assert(first:getFullType()=='Base.Nails'and second:getFullType()=='Base.Nails'and first:getWeight()<=.1 and second:getWeight()<=.1,'native bulk grouping unsupported')
 assert(type(queuePeersArmPartial)=='function'and queuePeersArmPartial(s.players.client1,first,second,s.stores.source1,s.players.client1:getInventory(),s.stores.source2,s.seed.token),'partial native probe could not arm')
end
function F.replica(s)
 local items={}
 for _,spec in ipairs(s.seed.items)do
  local item,endpoint,count=F.find(s,spec.id)
  assert(count<=1,'replica duplicated owned identity')
  items[#items+1]={id=spec.id,ft=item and item:getFullType()or spec.ft,endpoint=endpoint or false,count=count,pages=item and instanceof(item,'Literature')and item:getAlreadyReadPages()or 0}
 end
 for _,id in ipairs(s.seed.originalRootIds[s.role])do
  local item,endpoint,count=F.find(s,id)
  assert(item and count==1 and(endpoint==s.role..'-root'or endpoint==s.role..'-root-nested'),'original replica item missing')
 end
 return{items=items,originalsPreserved=true}
end
function F.capacity(s)
 assert(s.seed.case=='shared-capacity','wrong intervention')
 local ids={}
 for _,actor in ipairs(s.seed.actors)do
  local item,where,count=F.find(s,actor.front.id);assert(count==1 and where==actor.role..'-root','both pickups must be earned before capacity change')
  assert(item:getActualWeight()==1 and s.stores.source1:hasRoomFor(s.players[actor.role],item),'unsupported native book/initial room')
  ids[#ids+1]=actor.front.id
 end
 assert(s.stores.source1:getCapacityWeight()==0,'shared source not empty after pickups')
 s.stores.source1:setCapacity(1)
 local receipt={case=s.seed.case,token=s.seed.token,index=s.seed.index,capacity=1,roomBefore=true,combinedFits=false,items=ids}
 return receipt
end
function F.release(s)
 assert(isServer(),'release requires authority');F.snapshot(s)
 for _,spec in ipairs(s.seed.items)do local item,_,count=F.find(s,spec.id);assert(item and count==1)
  local store=item:getContainer();store:Remove(item);sendRemoveItemFromContainer(store,item)
 end
 for _,store in pairs(s.stores)do store:setCapacity(100)end
 s.seed=nil;s.owned={}
end
function F.cleanup(s)
 assert(not s.seed,'phase still active')
 for _,object in pairs(s.objects)do object:getSquare():transmitRemoveItemFromSquare(object)end
end
return F
