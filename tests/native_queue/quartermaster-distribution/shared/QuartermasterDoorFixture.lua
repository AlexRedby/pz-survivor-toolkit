local config=require 'QueueTestSelection'
if config.cases[1]~='barricaded-door' then return end
local F={module='QuartermasterDoorTest'}
local marker='PZSTQuartermasterDoorFixture'
local function counts(container,result)
 result=result or {}
 for index=0,container:getItems():size()-1 do
  local item=container:getItems():get(index);local id=item:getID()
  result[id]=(result[id]or 0)+1
  if instanceof(item,'InventoryContainer')then counts(item:getInventory(),result)end
 end
 return result
end
local function validPoint(point)
 assert(type(point)=='table','missing door fixture point')
 for _,key in ipairs({'x','y','z'})do
  local value=point[key]
  assert(type(value)=='number'and value==value and value~=math.huge and value~=-math.huge
   and value==math.floor(value),'invalid door fixture coordinate '..key)
 end
end
local function clearPad(point,player)
 for x=-2,7 do for y=-7,7 do
  local square=getCell():getGridSquare(point.x+x,point.y+y,point.z)
  if not square or not square:canStand()or square:getRoom()or square:getObjects():size()>1
   or(square~=player:getCurrentSquare()and not square:isFree(false))then return false end
 end end
 return true
end
function F.place(player)
 local origin=assert(player:getCurrentSquare())
 for radius=2,25 do for dx=-radius,radius do for dy=-radius,radius do
  if math.abs(dx)==radius or math.abs(dy)==radius then
   local point={x=origin:getX()+dx,y=origin:getY()+dy,z=origin:getZ()}
   if clearPad(point,player)then
    player:teleportTo(point.x,point.y,point.z);player:setX(point.x+0.5);player:setY(point.y+0.5)
    player:setLastX(point.x+0.5);player:setLastY(point.y+0.5);player:setCurrentSquareFromPosition()
    return point
   end
  end
 end end end
 error('No clear loaded pad for barricaded-door fixture')
end
local function own(state,object)
 local index=#state.owned+1
 object:getModData()[marker]=state.token..':'..index
 state.owned[index]=object
 return object
end
local function broadcast(object)
 if isServer()then object:transmitCompleteItemToClients();object:transmitModData()end
end
local function coord(object)
 local square=object:getSquare()
 return math.floor(square:getX())..','..math.floor(square:getY())..','..math.floor(square:getZ())
end
local function owned(state,object,index)
 assert(object and object:hasModData()and object:getModData()[marker]==state.token..':'..index,
  'foreign door fixture object '..index)
 local square=assert(object:getSquare(),'door fixture object lost square')
 local position=object:getObjectIndex()
 assert(position>=0 and square:getObjects():get(position)==object,'door fixture object removed/replaced')
end
function F.prepare(player,point)
 assert(not isClient(),'door fixture world creation requires authority')
 validPoint(point)
 assert(player:getCurrentSquare()and player:getCurrentSquare():getZ()==point.z
  and math.abs(player:getX()-point.x)<2 and math.abs(player:getY()-point.y)<2,'door actor has not reached fixture origin')
 assert(clearPad(point,player),'door fixture pad occupied on authority')
 local state={player=player,point={x=point.x,y=point.y,z=point.z},boxes={},doors={},ids={},items={},owned={},
  originalinventory=counts(player:getInventory()),token=point.x..','..point.y..','..point.z..':'..getTimestampMs()}
 local function square(x,y)return assert(getCell():getGridSquare(point.x+x,point.y+y,point.z))end
 for _,dx in ipairs({-1,3,5})do
  local sq=square(dx,0)
  assert(sq:canStand()and sq:isFree(true),'door fixture crate tile occupied')
  local box=IsoThumpable.new(getCell(),sq,'carpentry_01_16',false,{})
  box:setBlockAllTheSquare(true);box:setIsContainer(true)
  local container=assert(box:getContainer());container:setType('crate');container:setCapacity(100);container:setExplored(true)
  own(state,box);sq:AddSpecialObject(box);state.boxes[#state.boxes+1]=box
  -- Send an empty crate before the separate native item-add packets.
  broadcast(box)
 end
 for index,kind in ipairs({'Base.Nails','Base.Apple'})do
  local source=state.boxes[1]:getContainer();local item=assert(source:AddItem(kind))
  state.items[index]=item;state.ids[index]=item:getID()
  assert(not state.originalinventory[item:getID()],'fixture item reused an existing player identity')
  if isServer()then sendAddItemToContainer(source,item)end
  local box=state.boxes[index+1]
  box:getModData().LSBoxItems={['0']={[item:getDisplayName()]=true}}
  assert(LootSorter.serverFns.addCoord(player,{key=coord(box)})=='ok','door target registration refused')
  if isServer()then box:transmitModData()end
 end
 assert(state.ids[1]~=state.ids[2],'duplicate door fixture identities')
 for y=-5,5 do
  local sq=square(1,y);local isDoor=y==0 or y==3
  local object=isDoor and IsoDoor.new(getCell(),sq,assert(getSprite('fixtures_doors_01_0')),false)
   or IsoObject.new(getCell(),sq,assert(getSprite('walls_exterior_wooden_01_0')))
  own(state,object)
  if isDoor then
   object:setLocked(false);object:setLockedByKey(false);sq:AddSpecialObject(object);state.doors[y]=object
  else sq:AddTileObject(object)end
 end
 state.barricade=own(state,assert(IsoBarricade.AddBarricadeToObject(state.doors[0],false)))
 state.barricade:addPlank(player)
 state.originalHealth=state.barricade:getHealth();state.planks=state.barricade:getNumPlanks()
 assert(state.doors[0]:isBarricaded()and not state.doors[0]:IsOpen()and not state.doors[3]:IsOpen()
  and state.planks==1 and state.originalHealth>0,'native door/barricade preparation failed')
 -- Barricade insertion can change a door's object index. Broadcast these objects after all inserts,
 -- in native square/object order, with the completed plank health serialized in the barricade.
 local world={};for index=4,#state.owned do world[#world+1]=state.owned[index]end
 table.sort(world,function(a,b)
  local as,bs=a:getSquare(),b:getSquare()
  if as:getZ()~=bs:getZ()then return as:getZ()<bs:getZ()end
  if as:getX()~=bs:getX()then return as:getX()<bs:getX()end
  if as:getY()~=bs:getY()then return as:getY()<bs:getY()end
  return a:getObjectIndex()<b:getObjectIndex()
 end)
 for _,object in ipairs(world)do broadcast(object)end
 assert(#state.owned==15,'door fixture ownership count differs')
 state.createdAt=getTimestampMs()
 return state
end
function F.descriptor(state)
 local packet={point=state.point,ids=state.ids,token=state.token,objects={},boxes={},doors={},
  originalHealth=state.originalHealth,planks=state.planks,createdAt=state.createdAt}
 local indices={}
 for index,object in ipairs(state.owned)do
  owned(state,object,index);indices[object]=index
  local sq=object:getSquare()
  packet.objects[index]={x=sq:getX(),y=sq:getY(),z=sq:getZ(),index=object:getObjectIndex()}
 end
 for index,box in ipairs(state.boxes)do packet.boxes[index]=indices[box]end
 packet.doors.blocked=indices[state.doors[0]];packet.doors.normal=indices[state.doors[3]]
 packet.barricade=indices[state.barricade]
 return packet
end
function F.resolve(packet)
 local objects={}
 for index,point in ipairs(packet.objects)do
  local square=getCell():getGridSquare(point.x,point.y,point.z)
  if not square or point.index<0 or point.index>=square:getObjects():size()then return end
  local object=square:getObjects():get(point.index)
  if not object or not object:hasModData()or object:getModData()[marker]~=packet.token..':'..index then return end
  objects[index]=object
 end
 local state={point=packet.point,ids=packet.ids,token=packet.token,owned=objects,boxes={},doors={},items={},
  originalHealth=packet.originalHealth,planks=packet.planks,createdAt=packet.createdAt}
 for index,value in ipairs(packet.boxes)do state.boxes[index]=objects[value]end
 state.doors[0]=objects[packet.doors.blocked];state.doors[3]=objects[packet.doors.normal]
 state.barricade=objects[packet.barricade]
 if not state.doors[0]:isBarricaded()or state.doors[0]:IsOpen()or state.doors[3]:IsOpen()
  or state.doors[0]:getBarricadeOnSameSquare()~=state.barricade
  or state.barricade:getNumPlanks()~=state.planks or state.barricade:getHealth()~=state.originalHealth then return end
 for index,id in ipairs(packet.ids)do
  local item=state.boxes[1]:getContainer():getItemById(id)
  if not item then return end
  local selections=state.boxes[index+1]:getModData().LSBoxItems
  if not selections or not selections['0']or not selections['0'][item:getDisplayName()]then return end
  state.items[index]=item
 end
 local player=assert(getPlayer(),'door fixture resolution requires local player')
 state.player=player;state.originalinventory=counts(player:getInventory())
 return state
end
function F.receipt(player,state)
 for index,object in ipairs(state.owned)do owned(state,object,index)end
 local door,barricade=state.doors[0],state.barricade
 assert(not door:IsOpen()and door:isBarricaded()and door:getBarricadeOnSameSquare()==barricade
  and barricade:getBarricadedObject()==door and barricade:getNumPlanks()==state.planks
  and state.planks==1 and barricade:getHealth()==state.originalHealth,
  'original barricaded door opened/damaged/replaced')
 local pools={counts(state.boxes[1]:getContainer()),counts(state.boxes[2]:getContainer()),
  counts(state.boxes[3]:getContainer()),counts(player:getInventory())}
 local expected={[state.ids[1]]=true,[state.ids[2]]=true}
 for index=1,3 do for id in pairs(pools[index])do assert(expected[id],'unknown item in owned door crate')end end
 for index,id in ipairs(state.ids)do
  local total=0;for _,pool in ipairs(pools)do total=total+(pool[id]or 0)end
  assert(total<=1,'duplicate door distribution item '..id)
  if total~=1 or pools[index+1][id]~=1 then return nil,'awaiting door distribution item '..id end
  local container=state.boxes[index+1]:getContainer();local item=container:getItemById(id)
  assert(item and item:getContainer()==container,'door distribution item/container link differs')
 end
 assert(type(state.originalinventory)=='table','original door fixture inventory missing')
 for id,count in pairs(state.originalinventory)do assert(pools[4][id]==count,'pre-existing player inventory changed')end
 for id,count in pairs(pools[4])do assert(state.originalinventory[id]==count,'door distribution left carried items')end
 if not state.doors[3]:IsOpen()then return nil,'awaiting ordinary door state' end
 return {ids=state.ids,moved=2,normalDoorOpened=true,barricadedDoorClosed=true,barricadeIntact=true,conserved=true}
end
function F.cleanup(state)
 assert(not isClient(),'door fixture cleanup requires authority')
 assert(not state.cleaned,'duplicate door fixture cleanup')
 if getTimestampMs()-state.createdAt<LootSorter.ADD_GRACE_MS+1000 then return nil,'awaiting designation grace' end
 for index,object in ipairs(state.owned)do owned(state,object,index)end
 local keys={}
 for index=2,3 do
  local box=state.boxes[index];keys[#keys+1]=coord(box)
  if not state.designationsCleared then
   box:getModData().LSBoxItems=nil
   if isServer()then box:transmitModData()end
  end
 end
 state.designationsCleared=true
 assert(LootSorter.serverFns.removeCoords(state.player,{keys=keys})=='ok','door registry cleanup refused')
 local registry=ModData.getOrCreate('LootSorter_Registry').boxes or {}
 for _,key in ipairs(keys)do if registry[key]then return nil,'awaiting designation removal' end end
 for index=#state.owned,1,-1 do
  local object=state.owned[index];local square=object:getSquare()
  square:transmitRemoveItemFromSquare(object)
  assert(object:getObjectIndex()<0,'owned door fixture object was not removed')
 end
 state.cleaned=true
 return {objects=#state.owned}
end
return F
