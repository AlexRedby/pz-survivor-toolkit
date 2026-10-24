local F={}
local cases={['eject-idle']=true,['eject-playing']=true}
local function rootIds(root,nested)
 local ids={}
 local items=root:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i);ids[#ids+1]=item:getID()
  if nested and instanceof(item,'InventoryContainer')then
   for _,id in ipairs(rootIds(item:getItemContainer(),true))do ids[#ids+1]=id end
  end
 end
 table.sort(ids);return ids
end
local function identity(tv)
 local s=tv:getSquare();return {x=s:getX(),y=s:getY(),z=s:getZ(),index=tv:getObjectIndex()}
end
local function count(root,id)
 local n=0;local items=root:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  if item:getID()==id then n=n+1 end
  if instanceof(item,'InventoryContainer')then n=n+count(item:getItemContainer(),id)end
 end
 return n
end
local function book(player,kind)
 local item=assert(player:getInventory():AddItem(kind));local pages=item:getNumberOfPages()
 assert(pages>2,'native book has insufficient pages')
 item:setAlreadyReadPages(pages-2);player:setAlreadyReadPages(kind,pages-2)
 return item,{id=item:getID(),type=kind,pages=pages,initial=pages-2}
end
function F.prepare(player,case,mode)
 assert(cases[case] and (mode=='native'or mode=='toolkit'),'unknown TV controls selection')
 local origin=require('QueueEnergyPlacement')(player);local x,y,z=origin:getX(),origin:getY(),origin:getZ()
 local generator=IsoGenerator.new(assert(instanceItem('Base.Generator')),getCell(),getCell():getGridSquare(x,y+1,z))
 generator:setCondition(100);generator:setFuel(10);generator:setActivated(true)
 -- The TV sprite gains collideW when its square flags refresh. Stand east
 -- of it so native getCorrectSquareForWall never redirects us two tiles away.
 local square=assert(getCell():getGridSquare(x-1,y,z))
 local tv=IsoTelevision.new(getCell(),square,assert(getSprite('appliances_television_01_4')))
 square:AddSpecialObject(tv)
 local data=assert(tv:getDeviceData())
 -- Authoritative scene setup only. No device, playback, clock or duration setter
 -- is used after this point; insertion/playback are native UI-produced actions.
 data:setMediaType(1);data:setIsBatteryPowered(false);data:setIsPortable(false)
 data:setPower(1);data:setMinChannelRange(88000);data:setMaxChannelRange(108000)
 data:setChannelRaw(90000);data:setDeviceVolumeRaw(.5);data:setMicIsMuted(false)
 data:setTurnedOnRaw(true);getGameTime():setTimeOfDay(12)
 local presets=data:getDevicePresets();presets:clearPresets()
 presets:addPreset('Initial',90000);presets:addPreset('Final',95000)
 assert(not data:hasMedia()and data:canBePoweredHere()and square:haveElectricity(),'invalid powered empty TV scene')
 local front,frontId=book(player,'Base.BookCarpentry1')
 local tail,tailId=book(player,'Base.BookCooking1')
 local tape=assert(player:getInventory():AddItem('Base.VHS_Retail'))
 tape:setRecordedMediaData(assert(getZomboidRadio():getRecordedMedia():getMediaData('07b0cd73-7563-4699-9fb4-99316a0fc0bd')))
 local ids={case=case,mode=mode,tv=identity(tv),front=frontId,tail=tailId,
  tape={id=tape:getID(),type=tape:getFullType(),index=tape:getRecordedMediaIndex(),mediaType=tape:getMediaType()},
  origin={x=x,y=y,z=z}}
 assert(ids.tape.index>=0 and ids.tape.mediaType==1 and count(player:getInventory(),ids.tape.id)==1)
 if isServer()then
  tv:transmitCompleteItemToClients()
  for _,item in ipairs({front,tail,tape})do sendAddItemToContainer(player:getInventory(),item)end
 end
 return {player=player,tv=tv,data=data,front=front,tail=tail,tape=tape,ids=ids,generator=generator}
end
local function television(id)
 local square=getCell():getGridSquare(id.x,id.y,id.z)
 if not square then return end
 for i=0,square:getObjects():size()-1 do
  local o=square:getObjects():get(i)
  if o:getObjectIndex()==id.index and instanceof(o,'IsoTelevision')then return o end
 end
end
function F.resolve(player,ids)
 local root=player:getInventory();local tv=television(ids.tv)
 local front,tail,tape=root:getItemById(ids.front.id),root:getItemById(ids.tail.id),root:getItemById(ids.tape.id)
 if not tv or not front or not tail or not tape then return end
 for _,item in ipairs({front,tail,tape})do if item:getContainer()~=root then return end end
 local p=ids.origin
 if math.floor(player:getX())~=p.x or math.floor(player:getY())~=p.y or math.floor(player:getZ())~=p.z then
  player:teleportTo(p.x+.5,p.y+.5,p.z);return
 end
 local data=tv:getDeviceData()
 if data:hasMedia()or not data:getIsTurnedOn()or not data:canBePoweredHere()
  or data:getChannel()~=90000 or math.abs(data:getDeviceVolume()-.5)>.00001 then return end
 -- Character reading progress is local to the actor; match the authoritative
 -- seed before any native read begins, as in the existing shelf-TV fixture.
 for _,name in ipairs({'front','tail'})do
  local item=name=='front'and front or tail;local spec=ids[name]
  assert(item:getFullType()==spec.type and item:getNumberOfPages()==spec.pages)
  item:setAlreadyReadPages(spec.initial);player:setAlreadyReadPages(spec.type,spec.initial)
 end
 return {player=player,tv=tv,data=data,front=front,tail=tail,tape=tape,ids=ids}
end
-- Read the exact native walkAdj near-target predicates before the baseline.
-- This does not enqueue, teleport, alter square flags or replace doWalkTo.
function F.approach(state)
 local player=state.player
 local target=luautils.getCorrectSquareForWall(player,state.tv:getSquare())
 if not target then return {reachable=false}end
 local dx=math.abs(target:getX()+.5-player:getX())
 local dy=math.abs(target:getY()+.5-player:getY())
 local canReach=player:getSquare():canReachTo(target)
 return {x=player:getX(),y=player:getY(),z=player:getZ(),
  targetX=target:getX(),targetY=target:getY(),targetZ=target:getZ(),
  dx=dx,dy=dy,canReach=canReach,reachable=dx<=1.6 and dy<=1.6 and canReach}
end
function F.snapshot(state)
 local root=state.player:getInventory();local data=state.tv:getDeviceData();local ids=state.ids
 assert(television(ids.tv)==state.tv and data==state.data and data:getParent()==state.tv,'TV canonical binding changed')
 local result={case=ids.case,tv=identity(state.tv),rootIds=rootIds(root),carriedIds=rootIds(root,true),books={},
  originalCount=count(root,ids.tape.id),outputs={},
  device={on=data:getIsTurnedOn(),power=data:getPower(),powerable=data:canBePoweredHere(),
   volume=data:getDeviceVolume(),channel=data:getChannel(),micMuted=data:getMicIsMuted(),
   hasMedia=data:hasMedia(),mediaIndex=data:getMediaIndex(),mediaType=data:getMediaType(),playing=data:isPlayingMedia()}}
 for _,name in ipairs({'front','tail'})do
  local spec=ids[name];local item=root:getItemById(spec.id)
  result.books[name]={id=spec.id,type=item and item:getFullType()or '',root=item and item:getContainer()==root or false,
   count=count(root,spec.id),pages=item and item:getAlreadyReadPages()or -1,total=item and item:getNumberOfPages()or -1,
   characterPages=state.player:getAlreadyReadPages(spec.type)}
 end
 if state.baseline then
  local retained={};for _,id in ipairs(state.baseline.carriedIds)do retained[id]=true end
  local items=root:getItems()
  for i=0,items:size()-1 do
   local item=items:get(i)
   if not retained[item:getID()]then
    result.outputs[#result.outputs+1]={id=item:getID(),type=item:getFullType(),index=item:getRecordedMediaIndex(),
     mediaType=item:getMediaType(),recorded=item:isRecordedMedia(),root=item:getContainer()==root,count=count(root,item:getID())}
   end
  end
 end
 return result
end
function F.baseline(state)
 local value=F.snapshot(state);local d=value.device
 if value.originalCount~=0 or not d.on or not d.powerable or d.power<=0 or not d.hasMedia
  or d.mediaIndex~=state.ids.tape.index or d.mediaType~=1 or d.playing~=(state.ids.case=='eject-playing')
  or math.abs(d.volume-.5)>.00001 or d.channel~=90000 or d.micMuted then return end
 for _,name in ipairs({'front','tail'})do
  local row=value.books[name];if not row.root or row.count~=1 or row.pages~=state.ids[name].initial then return end
 end
 state.baseline=value;return value
end
function F.verify(state)
 if not state.baseline then return end
 local value=F.snapshot(state);local d=value.device
 if not d.on or not d.powerable or d.power<=0 or d.hasMedia or d.mediaIndex~=-1 or d.mediaType~=1 or d.playing
  or math.abs(d.volume-.25)>.00001 or d.channel~=95000 or d.micMuted or value.originalCount~=0 or #value.outputs~=1 then return nil,value end
 local o=value.outputs[1];local tape=state.ids.tape
 if o.id==tape.id or o.type~=tape.type or o.index~=tape.index or o.mediaType~=tape.mediaType
  or not o.recorded or not o.root or o.count~=1 then return nil,value end
 local retained={};for _,id in ipairs(value.carriedIds)do retained[id]=true end
 for _,id in ipairs(state.baseline.carriedIds)do if not retained[id]then return nil,value end end
 if #value.carriedIds~=#state.baseline.carriedIds+1 or #value.rootIds~=#state.baseline.rootIds+1 then return nil,value end
 for _,name in ipairs({'front','tail'})do
  local row=value.books[name];local spec=state.ids[name]
  if not row.root or row.count~=1 or row.type~=spec.type or row.total~=spec.pages
   or row.pages~=spec.pages or row.characterPages~=spec.pages then return nil,value end
 end
 return value
end
return F
