-- Receipts contain exact fixture identities; foreign animals, inventory and vehicles are retained.
local M={}
local function position(square)
 assert(square,'owned fixture square unloaded')
 return {x=square:getX(),y=square:getY(),z=square:getZ()}
end
function M.verify(receipt,player)
 assert(type(receipt)=='table' and type(receipt.animals)=='table' and #receipt.animals==3
  and type(receipt.items)=='table' and #receipt.items==4 and type(receipt.squares)=='table','invalid animal ownership receipt')
 if getVehicleById(receipt.vehicle) then return false,'owned trailer still replicated' end
 local owned={};for _,id in ipairs(receipt.items) do owned[id]=true end
 local function hasOwned(items)
  for i=0,items:size()-1 do if owned[items:get(i):getID()] then return true end end
  return false
 end
 if hasOwned(player:getInventory():getItems()) then return false,'owned item still in inventory' end
 for _,animal in ipairs(receipt.animals) do
  local current=getAnimal(animal.online)
  if current and (current:isExistInTheWorld() or current:getSquare() or current:getVehicle() or current:getHutch()) then
   return false,'owned animal still active'
  end
 end
 for _,entry in ipairs(receipt.squares) do
  for dx=-2,2 do for dy=-2,2 do
   local square=getSquare(entry.x+dx,entry.y+dy,entry.z)
   if not square then return false,'owned cleanup square unloaded' end
   local animals=square:getAnimals()
   for i=0,animals:size()-1 do
    for _,animal in ipairs(receipt.animals) do if animals:get(i):getAnimalID()==animal.id then return false,'owned ground animal retained' end end
   end
   local objects=square:getWorldObjects()
   for i=0,objects:size()-1 do
    local item=objects:get(i):getItem()
    if item and owned[item:getID()] then return false,'owned ground item retained' end
   end
  end end
 end
 return true
end
function M.remove(state)
 local vehicle,player=state.vehicle,state.player
 assert(vehicle:getAnimals():size()==0,'owned trailer not empty after native drops')
 assert(not player:getPrimaryHandItem() and not player:getSecondaryHandItem(),'owned items still held')
 assert(#state.animals==3,'fixture animal ownership incomplete')
 for i=0,vehicle:getMaxPassengers()-1 do assert(not vehicle:getCharacter(i),'foreign passenger in owned trailer') end
 for i=0,vehicle:getPartCount()-1 do
  local container=vehicle:getPartByIndex(i):getItemContainer()
  assert(not container or container:getItems():size()==0,'foreign contents in owned trailer')
 end
 local receipt={vehicle=vehicle:getId(),animals={},items={},squares={position(vehicle:getSquare())}}
 local animals={}
 for _,identity in ipairs(state.animals) do
  local animal=getAnimal(identity.online)
  assert(animal and animal:getAnimalID()==identity.id,'owned dropped animal identity unresolved')
  animals[#animals+1]=animal
  receipt.animals[#receipt.animals+1]={id=identity.id,online=identity.online}
  receipt.squares[#receipt.squares+1]=position(animal:getSquare())
 end
 for id,item in pairs(state.items) do
  assert(item:getID()==id,'owned item identity changed')
  receipt.items[#receipt.items+1]=id
  local world,container=item:getWorldItem(),item:getContainer()
  if world and world:getSquare() then
   receipt.squares[#receipt.squares+1]=position(world:getSquare())
   world:getSquare():transmitRemoveItemFromSquare(world)
  elseif container and container:contains(item) then
   player:removeFromHands(item);container:Remove(item);sendRemoveItemFromContainer(container,item)
   assert(not container:contains(item),'owned item removal failed')
  end
 end
 assert(#receipt.items==4,'expected three exact animal inventory IDs and one owned bat')
 for index,animal in ipairs(animals) do
  assert(animalFixtureDelete(animal)=='removed='..receipt.animals[index].online,'native owned animal removal failed')
 end
 vehicle:permanentlyRemove()
 assert(not getVehicleById(receipt.vehicle),'owned trailer native removal failed')
 print('[ANIMAL_TRAILER] SERVER OWNED_RESET animals=3 items=4 trailer=1')
 return receipt
end
return M
