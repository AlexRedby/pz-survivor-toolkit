local Spawn = require 'PinnedItemsFixture'
local Retention = require 'PZSurvivorToolkit/ItemRetention'
local Categories = require 'PZSurvivorToolkit/ItemCategories'
local F = {module='ItemRetentionTest', types={'Base.Screwdriver','Base.Screwdriver','Base.PetrolCan','Base.Hammer'}}
F.persistence='PZSTRetentionFixturePersistence'

function F.prepare(player)
 assert(not getActivatedMods():contains('organizedCategories_core'),'External OC is still active')
 Spawn.types=F.types
 local vehicle,container=Spawn.spawn(player,true,6)
 vehicle:getModData().PZSTRetentionFixture=true
 local area=assert(vehicle:getAreaCenter(vehicle:getPartById('TruckBed'):getArea()))
 local square
 local access=assert(getCell():getGridSquare(math.floor(area:getX()),math.floor(area:getY()),0))
 -- Cargo access can sit inside the truck's occupied footprint. Search a
 -- bounded connected route out to a free tile, checking each native edge;
 -- choosing only its four immediate neighbors fails for some valid spawns.
 local queue,visited={{square=access,depth=0}},{}
 local cursor=1
 visited[access]=true
 while not square and cursor<=#queue do
  local point=queue[cursor];cursor=cursor+1
  if point.depth<4 then
   for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}})do
    local candidate=getCell():getGridSquare(point.square:getX()+offset[1],point.square:getY()+offset[2],0)
    if candidate and not visited[candidate]and candidate:canStand()and not candidate:isVehicleIntersecting()
     and not point.square:isBlockedTo(candidate)then
     visited[candidate]=true
     queue[#queue+1]={square=candidate,depth=point.depth+1}
     if not square and candidate:isFree(true)and candidate:getObjects():size()<=1 then square=candidate end
    end
   end
  end
 end
 assert(square,'No free crate tile next to truck')
 local crate=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
 crate:setIsContainer(true);crate:setBlockAllTheSquare(true);square:AddSpecialObject(crate)
 local target=assert(crate:getContainer());target:setType('crate');target:setCapacity(100);target:setExplored(true)
 local ids,cats={},{}
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i);Categories.prepareItem(item)
  ids[#ids+1]=item:getID();cats[item:getDisplayCategory()]=true
  if i==2 then item:getModData().ocStuck=true end
 end
 crate:getModData().PZSTRetentionFixture=true;crate:getModData().LSBox={['0']=cats}
 local key=square:getX()..','..square:getY()..','..square:getZ()
 assert(LootSorter.serverFns.addCoord(player,{key=key})=='ok','Cannot register destination')
 crate:transmitCompleteItemToClients();crate:transmitModData()
 local packet={truckId=vehicle:getId(),x=area:getX(),y=area:getY(),ids=ids,
  crate={x=square:getX(),y=square:getY(),z=0,index=crate:getObjectIndex()}}
 return {vehicle=vehicle,container=container,crate=crate,packet=packet,player=player}
end

function F.resolve(packet)
 local vehicle=getVehicleById(packet.truckId);local point=packet.crate
 local function matches(candidate)
  if not candidate or not instanceof(candidate,'BaseVehicle')then return false end
  local part=candidate:getPartById('TruckBed');local container=part and part:getItemContainer()
  return container and container:getItemById(packet.ids[3])~=nil
 end
 if not matches(vehicle)then
  vehicle=nil
  -- Native network vehicle IDs can change after restarting the saved world.
  -- Locate the owned truck by its persisted item identity in loaded squares.
  for dx=-8,8 do for dy=-8,8 do
   local square=getCell():getGridSquare(math.floor(packet.x)+dx,math.floor(packet.y)+dy,0)
   if square and not vehicle then
    local moving=square:getMovingObjects()
    for i=0,moving:size()-1 do
     local candidate=moving:get(i)
     if matches(candidate)then vehicle=candidate;break end
    end
   end
  end end
 end
 local sq=getCell():getGridSquare(point.x,point.y,point.z)
 if not vehicle or not sq or sq:getObjects():size()<=point.index then return end
 local crate=sq:getObjects():get(point.index)
 if not crate:hasModData() or not crate:getModData().PZSTRetentionFixture then return end
 packet.truckId=vehicle:getId()
 return vehicle,vehicle:getPartById('TruckBed'):getItemContainer(),crate
end

function F.item(state,index)
 local id=state.packet.ids[index]
 return state.container:getItemById(id) or state.crate:getContainer():getItemById(id)
  or state.player:getInventory():getItemWithIDRecursiv(id)
end

function F.check(state,phase)
 local trunk,target,inventory=state.container,state.crate:getContainer(),state.player:getInventory()
 local ids=state.packet.ids;local items={}
 for i,id in ipairs(ids)do
  local found,count=nil,0
  for _,pool in ipairs({trunk,target,inventory})do
   local item=pool:getItemWithIDRecursiv(id)
   if item then found,count=item,count+1 end
  end
  assert(count<=1,'Duplicated retained-item ID '..id)
  if count~=1 then return false end
  assert(found:getFullType()==F.types[i],'Retained item type changed')
  items[i]=found
 end
 if not Retention.isRetained(items[3]) then return false end
 if phase=='multiple'then
  return inventory:getItemById(ids[1])~=nil and inventory:getItemById(ids[4])~=nil
   and trunk:getItemById(ids[2])~=nil and trunk:getItemById(ids[3])~=nil
   and Retention.isRetained(items[1])and Retention.isRetained(items[4])
 end
 if phase=='marked'then
  return Retention.isRetained(items[1]) and Retention.isRetained(items[4]) and trunk:getItems():size()==4
 end
 if not target:getItemById(ids[2]) or target:getItems():size()~=1 then return false end
 if not trunk:getItemById(ids[3]) or not trunk:getItemById(ids[4]) then return false end
 if phase=='distributed'then return trunk:getItemById(ids[1])~=nil and Retention.isRetained(items[1])end
 if not inventory:getItemById(ids[1]) then return false end
 if phase=='manual'then return Retention.isRetained(items[1])end
 return not Retention.isRetained(items[1])
end

function F.receipt(role, state)
 return {role=role,retained=true,legacy=true,observer=true,distributed=true,manual=true,
  released=true,conserved=true,noOC=not getActivatedMods():contains('organizedCategories_core'),
  truckId=state.packet.truckId,ids=state.packet.ids}
end

function F.diagnostic(state)
 local result={}
 for index,id in ipairs(state.packet.ids)do
  local item=F.item(state,index)
  result[#result+1]={id=id,trunk=state.container:getItemById(id)~=nil,
   crate=state.crate:getContainer():getItemById(id)~=nil,
   carried=state.player:getInventory():getItemWithIDRecursiv(id)~=nil,
   retained=Retention.isRetained(item)}
 end
 return result
end
function F.persisted(role,state)
 return {role=role,ids=state.packet.ids,truckId=state.packet.truckId,retained=true,
  legacy=true,released=true,noOC=not getActivatedMods():contains('organizedCategories_core')}
end
return F
