local P=require 'QueueEnergyPlacement'
local F={}
local cases={['tv-remove']='remove',['tv-move']='move',['radio-remove']='remove',['radio-move']='move',
 ['radio-walk-remove']='remove',['tv-walk-move']='move'}
local walkCases={['radio-walk-remove']=true,['tv-walk-move']=true}
function F.walkCase(case)return walkCases[case]==true end
local function clearCorridor(origin)
 for dx=-10,1 do for dy=-1,1 do
  local s=getCell():getGridSquare(origin.x+dx,origin.y+dy,origin.z)
  if not s or not s:getFloor()or not s:TreatAsSolidFloor()or s:getRoom()or not s:isFree(false)
   or s:getObjects():size()>1 or s:isVehicleIntersecting()then return false end
 end end
 return true
end
function F.choosePlacement(player,case)
 if not F.walkCase(case)then return P.choose(player)end
 local origin=P.choose(player)
 local map=assert(getCell():getChunkMap(player:getPlayerNum()),'native device walking chunk map unavailable')
 for _,name in ipairs({'getWorldXMinTiles','getWorldYMinTiles','getWorldXMaxTiles','getWorldYMaxTiles','getWidthInTiles'})do
  assert(type(map[name])=='function','native device walking chunk-map method unavailable '..name)
 end
 local minX,minY,maxX,maxY=map:getWorldXMinTiles(),map:getWorldYMinTiles(),map:getWorldXMaxTiles(),map:getWorldYMaxTiles()
 local width=map:getWidthInTiles()
 local function integer(value)return type(value)=='number'and value==value and value%1==0 end
 assert(integer(minX)and integer(minY)and integer(maxX)and integer(maxY)and integer(width),
  'invalid native device walking chunk-map bounds')
 -- B42.21 CalcChunkWidth caps the grid at 19 chunks of eight tiles.
 -- MaxTiles is exclusive: leave the full unchanged [-10,1] x [-1,1]
 -- corridor inside this actual map, then still reject every unloaded square.
 assert(width>=12 and width<=19*8 and width%8==0 and maxX-minX==width and maxY-minY==width,
  'inconsistent native device walking chunk-map extent')
 assert(origin.x>=minX and origin.x<maxX and origin.y>=minY and origin.y<maxY,
  'native device walking placement anchor is outside its chunk map')
 local firstX,lastX,firstY,lastY=minX+10,maxX-2,minY+1,maxY-2
 local radius=math.max(math.abs(firstX-origin.x),math.abs(lastX-origin.x),
  math.abs(firstY-origin.y),math.abs(lastY-origin.y))
 local tested=0
 local function try(x,y)
  if x<firstX or x>lastX or y<firstY or y>lastY then return end
  tested=tested+1
  local candidate={x=x,y=y,z=origin.z}
  if clearCorridor(candidate)then return P.target(candidate)end
 end
 local function finish(candidate)
  local detail='candidates='..tostring(tested)..' map='..minX..','..minY..':'..maxX..','..maxY..' width='..width..' z='..origin.z
  print('[DEVICE_TARGET_LOSS] WALK_PLACEMENT status='..(candidate and'selected'or'failed')..' '..detail)
  assert(candidate,'No clear loaded native device walking corridor before placement '..detail)
  return candidate
 end
 local candidate=try(origin.x,origin.y);if candidate then return finish(candidate)end
 for distance=1,radius do
  for x=origin.x-distance,origin.x+distance do
   candidate=try(x,origin.y-distance);if candidate then return finish(candidate)end
   candidate=try(x,origin.y+distance);if candidate then return finish(candidate)end
  end
  for y=origin.y-distance+1,origin.y+distance-1 do
   candidate=try(origin.x-distance,y);if candidate then return finish(candidate)end
   candidate=try(origin.x+distance,y);if candidate then return finish(candidate)end
  end
 end
 return finish(nil)
end
local function tile(square)return square and{x=square:getX(),y=square:getY(),z=square:getZ()}or false end
local function square(id)
 local value=getCell():getGridSquare(id.x,id.y,id.z)
 assert(value,'device fixture square unloaded')
 return value
end
local function member(object,where)
 local objects=square(where):getObjects()
 for i=0,objects:size()-1 do if objects:get(i)==object then return true end end
 return false
end
function F.find(ids,where)
 local found;local objects=square(where):getObjects()
 for i=0,objects:size()-1 do local object=objects:get(i)
  if object:getModData().queueDeviceLoss==ids.key then
   assert(not found and instanceof(object,ids.class),'ambiguous/foreign device fixture identity');found=object
  end
 end
 return found
end
local function values(data)
 -- B42 canBePoweredHere dereferences getSquare before its later nil guard.
 -- Detached data remains observable without invoking this unsafe native query.
 local parent=data:getParent();local attached=parent and parent:getSquare()~=nil
 return {volume=data:getDeviceVolume(),channel=data:getChannel(),on=data:getIsTurnedOn(),
  battery=data:getIsBatteryPowered(),media=data:hasMedia(),power=data:getPower(),powered=attached and data:canBePoweredHere()or false}
end
local function generatorPresent(ids)
 local objects=square(ids.generator):getObjects();local found=false
 for i=0,objects:size()-1 do
  if objects:get(i):getModData().queueDeviceLoss==ids.key..':generator'then
   assert(not found and instanceof(objects:get(i),'IsoGenerator'),'ambiguous fixture generator');found=true
  end
 end
 return found
end
local function book(player,kind,remaining)
 local item=assert(player:getInventory():AddItem(kind));local pages=item:getNumberOfPages()
 assert(pages>remaining);item:setAlreadyReadPages(pages-remaining);player:setAlreadyReadPages(kind,pages-remaining)
 return item,{id=item:getID(),type=kind,pages=pages,initial=pages-remaining}
end
function F.prepare(player,case,mode,placement,proof)
 assert(cases[case]and(mode=='native'or mode=='toolkit'),'unknown device loss case')
 local origin=P.target(placement);assert(P.at(player,origin),'device loss actor left settled placement')
 assert(proof.mode==(isServer()and'replica'or'local'),'device loss placement role differs')
 local walk=F.walkCase(case)
 if walk then assert(clearCorridor(origin),'device walking corridor changed before preparation')end
 local old={x=origin.x-(walk and 8 or 1),y=origin.y,z=origin.z}
 local destination={x=origin.x+(walk and -9 or 1),y=origin.y,z=origin.z}
 local generatorAt={x=origin.x-(walk and 5 or 0),y=origin.y+1,z=origin.z}
 for _,where in ipairs({old,destination})do local s=square(where)
  assert(s:isFree(false)and s:getObjects():size()<=1,'device loss destination is not clear')
 end
 local generator=IsoGenerator.new(assert(instanceItem('Base.Generator')),getCell(),square(generatorAt))
 generator:setCondition(100);generator:setFuel(10);generator:setActivated(true)
 local tv=case:sub(1,2)=='tv';local object
 if tv then object=IsoTelevision.new(getCell(),square(old),assert(getSprite('appliances_television_01_4')))
 else object=IsoRadio.new(getCell(),square(old),assert(getSprite('appliances_radio_01_0')))end
 square(old):AddSpecialObject(object)
 local data=assert(object:getDeviceData());data:setIsBatteryPowered(false);data:setIsPortable(false)
 data:setIsTelevision(tv);data:setPower(1);data:setTurnedOnRaw(true);data:setDeviceVolumeRaw(.5)
 data:setMinChannelRange(88000);data:setMaxChannelRange(108000);data:setChannelRaw(90000)
 assert(not data:hasMedia()and data:canBePoweredHere()and square(destination):haveElectricity(),'invalid powered bare world device')
 local key='device-target-loss:'..case..':'..tostring(getTimestampMs())
 object:getModData().queueDeviceLoss=key
 generator:getModData().queueDeviceLoss=key..':generator'
 if isServer()then generator:transmitModData()end
 local hold,holdId=book(player,'Base.BookForaging1',4);local tail,tailId=book(player,'Base.BookTrapping1',2)
 local ids={case=case,mode=mode,key=key,class=tv and'IsoTelevision'or'IsoRadio',old=old,destination=destination,
  index=object:getObjectIndex(),origin=origin,generator=generatorAt,
  placementProof=proof,hold=holdId,tail=tailId}
 if walk then ids.walkLayout={distance=8,minX=-10,maxX=1,minY=-1,maxY=1,chosenBeforePlacement=true}end
 if isServer()then object:transmitCompleteItemToClients()
  sendAddItemToContainer(player:getInventory(),hold);sendAddItemToContainer(player:getInventory(),tail)
 end
 return {player=player,ids=ids,object=object,data=data,hold=hold,tail=tail,generator=generator,authority=true}
end
function F.resolve(player,ids)
 local object=F.find(ids,ids.old);local root=player:getInventory()
 if not object or not P.at(player,ids.origin)or not generatorPresent(ids)then return end
 local state={player=player,ids=ids,object=object,data=object:getDeviceData()}
 for _,name in ipairs({'hold','tail'})do
  local spec=ids[name];local item=root:getItemById(spec.id)
  if not item or item:getContainer()~=root then return end
  assert(item:getFullType()==spec.type and item:getNumberOfPages()==spec.pages,'book binding differs')
  item:setAlreadyReadPages(spec.initial);player:setAlreadyReadPages(spec.type,spec.initial);state[name]=item
 end
 if math.abs(state.data:getDeviceVolume()-.5)>.0001 or not state.data:canBePoweredHere()then return end
 return state
end
function F.snapshot(state)
 local ids=state.ids;local old,destination=F.find(ids,ids.old),F.find(ids,ids.destination)
 local live=old or destination;assert(not(old and destination),'device duplicated across squares')
 local result={case=ids.case,key=ids.key,generatorPresent=generatorPresent(ids),oldPresent=old~=nil,destinationPresent=destination~=nil,
  heldMemberOld=member(state.object,ids.old),heldMemberDestination=member(state.object,ids.destination),
  heldSquare=tile(state.object:getSquare()),heldIndex=state.object:getObjectIndex(),
  heldDataSame=state.object:getDeviceData()==state.data,heldDataParentSame=state.data:getParent()==state.object,
  liveSameObject=live~=nil and live==state.object,liveSameData=live~=nil and live:getDeviceData()==state.data,
  held=values(state.data),live=live and values(live:getDeviceData())or false,books={}}
 for _,name in ipairs({'hold','tail'})do local spec=ids[name];local root=state.player:getInventory()
  local item=root:getItemById(spec.id);local count=0;local list=root:getItems()
  for i=0,list:size()-1 do if list:get(i):getID()==spec.id then count=count+1 end end
  result.books[name]={id=spec.id,type=item and item:getFullType()or'',root=item~=nil and item:getContainer()==root,
   count=count,pages=item and item:getAlreadyReadPages()or -1,characterPages=state.player:getAlreadyReadPages(spec.type)}
 end
 return result
end
function F.mutate(state)
 assert(state.authority and not state.mutation,'device mutation authority/replay differs')
 local ids=state.ids;local object,data=state.object,state.data
 assert(F.find(ids,ids.old)==object and object:getDeviceData()==data and data:getParent()==object,
  'device mutation requires exact original authority binding')
 local before=F.snapshot(state);assert(math.abs(before.held.volume-.5)<.0001,'pending setter already affected device')
 assert(not F.find(ids,ids.destination),'destination already contains fixture object')
 square(ids.old):transmitRemoveItemFromSquare(object)
 assert(not member(object,ids.old),'native removal retained original object')
 if cases[ids.case]=='move'then
  object:setSquare(square(ids.destination));square(ids.destination):AddSpecialObject(object)
  if isServer()then object:transmitCompleteItemToClients()end
 end
 assert(object:getDeviceData()==data and data:getParent()==object,'mutation replaced original DeviceData')
 state.mutation={case=ids.case,key=ids.key,operation=assert(cases[ids.case]),
  sameAuthorityObject=true,sameAuthorityData=true,before=before,after=F.snapshot(state),at=getTimestampMs()}
 return state.mutation
end
function F.observed(state)
 local value=F.snapshot(state);local moved=cases[state.ids.case]=='move'
 if value.oldPresent or value.destinationPresent~=moved then return end
 return value
end
function F.cleanup(state)
 assert(state.authority and state.mutation and not state.cleaned,'cleanup authority/order differs')
 local ids=state.ids
 for _,where in ipairs({ids.old,ids.destination})do local object=F.find(ids,where)
  if object then assert(object==state.object,'cleanup encountered replacement authority object');square(where):transmitRemoveItemFromSquare(object)end
 end
 local generator=assert(state.generator);generator:setActivated(false)
 assert(generator:getSquare());generator:getSquare():transmitRemoveItemFromSquare(generator)
 assert(not member(generator,ids.generator),'generator cleanup retained original object')
 for _,name in ipairs({'hold','tail'})do local item=state[name];local root=state.player:getInventory()
  assert(root:getItemById(ids[name].id)==item and item:getContainer()==root,'cleanup book binding differs')
  root:Remove(item);if isServer()then sendRemoveItemFromContainer(root,item)end
 end
 state.cleaned=true
 return {case=ids.case,key=ids.key,objectsRemoved=true,generatorRemoved=true,booksRemoved=true}
end
function F.cleaned(state)
 local ids=state.ids
 if F.find(ids,ids.old)or F.find(ids,ids.destination)then return false end
 local objects=square(ids.generator):getObjects()
 for i=0,objects:size()-1 do if objects:get(i):getModData().queueDeviceLoss==ids.key..':generator'then return false end end
 for _,name in ipairs({'hold','tail'})do if state.player:getInventory():getItemById(ids[name].id)then return false end end
 return true
end
return F
