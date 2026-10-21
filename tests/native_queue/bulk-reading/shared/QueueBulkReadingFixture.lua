local F={count=15,kind='Base.Magazine'}
function F.prepare(player)
 local origin=player:getCurrentSquare();local square
 for _,offset in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
  local candidate=getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ())
  if not square and candidate and candidate:canStand()and candidate:isFree(false)
   and not origin:isBlockedTo(candidate)then square=candidate end
 end
 assert(square,'no adjacent free dresser tile')
 local box=IsoThumpable.new(getCell(),square,'furniture_storage_01_8',false,{})
 box:setBlockAllTheSquare(true);box:setIsContainer(true)
 local container=assert(box:getContainer());container:setType('wardrobe');container:setCapacity(100);container:setExplored(true)
 box:getModData().PZSTBulkReadingFixture=true;square:AddSpecialObject(box)
 local state={player=player,box=box,items={},ids={}}
 for index=1,F.count do
  local item=assert(container:AddItem(F.kind));state.items[index]=item;state.ids[index]=item:getID()
  item:getModData().literatureTitle='ToolkitReadingFixture'..tostring(item:getID())
 end
 if isServer()then box:transmitCompleteItemToClients();box:transmitModData()end
 return state
end
function F.descriptor(state)
 local square=state.box:getSquare()
 return {ids=state.ids,x=square:getX(),y=square:getY(),z=square:getZ(),index=state.box:getObjectIndex()}
end
function F.resolve(packet)
 local square=getCell():getGridSquare(packet.x,packet.y,packet.z)
 local objects=square and square:getObjects()
 local box=objects and packet.index>=0 and packet.index<objects:size()and objects:get(packet.index)
 if not box or not box:getModData().PZSTBulkReadingFixture then return end
 local items={};local container=box:getContainer()
 for _,id in ipairs(packet.ids)do
  local item=container:getItemById(id);if not item then return end
  items[#items+1]=item
 end
 return box,items
end
local function occurrences(container,id)
 local count=0
 for index=0,container:getItems():size()-1 do
  local item=container:getItems():get(index)
  if item:getID()==id then count=count+1 end
  if instanceof(item,'InventoryContainer')then count=count+occurrences(item:getInventory(),id)end
 end
 return count
end
function F.receipt(state)
 local container=state.box:getContainer();local rows={}
 for index,id in ipairs(state.ids)do
  local item=container:getItemById(id)
  if not item or item:getFullType()~=F.kind or item:getContainer()~=container then return nil,'magazine not returned '..id end
  if occurrences(container,id)~=1 or occurrences(state.player:getInventory(),id)~=0 then return nil,'magazine identity mismatch '..id end
  if not state.player:isLiteratureRead(item:getModData().literatureTitle)then return nil,'magazine not read '..id end
  rows[index]={id=id,read=true,returned=true}
 end
 return {items=rows,count=#rows}
end
return F
