-- Native inventory recipe fixture, with its consumed Plank moved to a distant world source.
local Base=require 'QueueCraftUIFixture'
local Fixture={}
function Fixture.placement(player)
 local origin=player:getSquare()
 for radius=2,12 do
  for dx=-radius,radius do for dy=-radius,radius do
   if math.max(math.abs(dx),math.abs(dy))==radius then
    local x,y,z=origin:getX()+dx,origin:getY()+dy,origin:getZ();local clear=true
    for a=-1,5 do for b=-1,1 do
     local sq=getCell():getGridSquare(x+a,y+b,z)
     if not sq or not sq:getFloor()or not sq:isFree(false)or sq:getRoom()or sq:getObjects():size()>1 then clear=false end
    end end
    if clear then return {x=x,y=y,z=z}end
   end
  end end
 end
 error('No clear loaded seven by three Quartermaster craft strip')
end
function Fixture.prepare(player,case,position,previous)
 assert(case=='vanilla'or case=='neat','unknown Quartermaster craft case')
 assert(type(position)=='table'and type(position.x)=='number'and type(position.y)=='number'and type(position.z)=='number','invalid craft placement')
 assert(math.abs(position.x-player:getX())<30 and math.abs(position.y-player:getY())<30 and position.z==player:getSquare():getZ(),'craft placement too far from actor')
 local square=assert(getCell():getGridSquare(position.x+4,position.y,position.z))
 assert(square:isFree(false)and square:getObjects():size()<=1,'craft source footprint occupied')
 local state=Base.prepare(player,'context',previous);state.case=case
 local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
 object:setCanPassThrough(true);object:setIsContainer(true)
 local source=assert(object:getContainer());source:setType('crate');source:setCapacity(100);source:setExplored(true)
 object:getModData().QueueQuartermasterCraftOwner=player:getUsername()
 square:AddSpecialObject(object)
 local material=assert(state.root:getItemById(state.materials[1]));state.root:Remove(material);source:AddItem(material)
 if isServer()then sendRemoveItemFromContainer(state.root,material);object:transmitCompleteItemToClients()end
 state.source=source;state.object=object
 state.location={x=square:getX(),y=square:getY(),z=square:getZ(),index=object:getObjectIndex()}
 return state
end
function Fixture.descriptor(state)
 local ids=Base.descriptor(state);ids.source=state.location;return ids
end
function Fixture.resolve(player,ids)
 local sq=getCell():getGridSquare(ids.source.x,ids.source.y,ids.source.z)
 local object=sq and sq:getObjects():size()>ids.source.index and sq:getObjects():get(ids.source.index)
 if not object or not object:getContainer()or object:getModData().QueueQuartermasterCraftOwner~=player:getUsername()then return end
 local source=object:getContainer();if not source:getItemById(ids.materials[1])then return end
 local root=player:getInventory()
 for _,id in ipairs(ids.bags)do if not root:getItemById(id)then return end end
 for _,meta in ipairs(ids.toolMeta)do if not root:getItemById(meta.id)then return end end
 local book=root:getItemById(ids.book);if not book then return end
 return {root=root,source=source,object=object,book=book}
end
function Fixture.verify(state)
 if state.source:getItems():size()~=0 then return nil,'exact designated source input remains'end
 local value,reason=Base.verify(state);if not value then return nil,reason end
 if value.toolsReturned~=2 then return nil,'exact kept tools did not return to source bags'end
 value.sourceConsumed=true;value.source=state.location
 return value
end
function Fixture.cleanup(state)
 assert(state.verified and state.object:getContainer()==state.source and state.source:getItems():size()==0
  and state.object:getModData().QueueQuartermasterCraftOwner==state.player:getUsername(),'foreign or unverified craft crate cleanup refused')
 state.object:getSquare():transmitRemoveItemFromSquare(state.object)
end
return Fixture
