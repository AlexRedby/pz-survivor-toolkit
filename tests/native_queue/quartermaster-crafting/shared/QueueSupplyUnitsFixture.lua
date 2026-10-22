local F={cases={'full','carried','partial'}}
local function pool(container)
 local result={}
 for i=0,container:getItems():size()-1 do local item=container:getItems():get(i);result[item:getID()]=item end
 return result
end
function F.cleanup(state,removeBox)
 assert(state.verified,'unverified supplies cleanup')
 local root,source=state.player:getInventory(),state.object:getContainer()
 for _,container in ipairs({root,source})do
  for id,item in pairs(pool(container))do
   if state.owned[id]then
    assert(not state.player:isEquipped(item),'owned supply remains equipped')
    container:Remove(item);if isServer()then sendRemoveItemFromContainer(container,item)end
   end
  end
 end
 if removeBox then
  assert(state.object:getModData().PZSTSupplyFixture and source:getItems():size()==0,'foreign source cleanup')
  state.object:getSquare():transmitRemoveItemFromSquare(state.object)
 end
end
function F.prepare(player,index,point,previous)
 assert(F.cases[index],'invalid supply case')
 local object
 if previous then
  assert(previous.index==index-1 and previous.player==player,'supply preparation order')
  F.cleanup(previous,false);object=previous.object
 else
  local square=assert(getCell():getGridSquare(point.x+4,point.y,point.z))
  assert(square:isFree(false)and square:getObjects():size()<=1,'supply source occupied')
  object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
  object:setCanPassThrough(true);object:setIsContainer(true)
  object:getContainer():setType('crate');object:getContainer():setCapacity(100);object:getContainer():setExplored(true)
  object:getModData().PZSTSupplyFixture=true;square:AddSpecialObject(object)
  if isServer()then object:transmitCompleteItemToClients();object:transmitModData()end
 end
 local root,source=player:getInventory(),object:getContainer()
 local state={player=player,index=index,object=object,ids={},owned={},baseline=pool(root)}
 local specs=index==1 and {{2,4},{2,4}}or index==2 and {{1,4},{2,4}}or {{1,1},{2,1},{2,4}}
 for i,spec in ipairs(specs)do
  local container=spec[1]==1 and root or source
  local item=assert(container:AddItem('Base.DuctTape'));item:setUsedDelta(spec[2]*.25)
  assert(item:getCurrentUses()==spec[2],'native DuctTape use setup differs')
  state.ids[i]=item:getID();state.owned[item:getID()]=true
  if isServer()then sendAddItemToContainer(container,item)end
 end
 return state
end
function F.descriptor(state)
 local sq=state.object:getSquare()
 return {index=state.index,case=F.cases[state.index],ids=state.ids,
  source={x=sq:getX(),y=sq:getY(),z=sq:getZ(),index=state.object:getObjectIndex()}}
end
function F.resolve(player,packet)
 local point=packet.source;local sq=getCell():getGridSquare(point.x,point.y,point.z)
 local object=sq and sq:getObjects():size()>point.index and sq:getObjects():get(point.index)
 if not object or not object:getModData().PZSTSupplyFixture then return end
 local root,source=pool(player:getInventory()),pool(object:getContainer())
 for _,id in ipairs(packet.ids)do if not(root[id]or source[id])then return end end
 return object
end
function F.receipt(player,object,packet,baseline)
 local root,source=pool(player:getInventory()),pool(object:getContainer())
 local expected=packet.index==1 and {{2,2},{2,4}}or packet.index==2 and {{1,2},{2,4}}or {{0,0},{0,0},{2,4}}
 local items={}
 for i,id in ipairs(packet.ids)do
  assert(not(root[id]and source[id]),'duplicate supply identity')
  local item=root[id]or source[id];local location=root[id]and 1 or source[id]and 2 or 0
  local uses=item and item:getCurrentUses()or 0
  if location~=expected[i][1]or uses~=expected[i][2]then return end
  items[i]={id=id,container=location,uses=uses}
 end
 local outputs={}
 for id,item in pairs(root)do
  if not baseline[id]and item:getFullType()=='Base.WoodenStick2'then outputs[#outputs+1]=id end
 end
 if #outputs~=1 then return end
 for id in pairs(baseline)do assert(root[id],'pre-existing inventory item lost')end
 return {index=packet.index,case=packet.case,items=items,outputIds=outputs,outputs=1,consumedUses=2}
end
function F.verify(state)
 local value=F.receipt(state.player,state.object,F.descriptor(state),state.baseline)
 if value then
  state.verified=true
  for _,id in ipairs(value.outputIds)do state.owned[id]=true end
 end
 return value
end
return F
