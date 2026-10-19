local Floor={}
function Floor.resolve(spec)
 local square=getCell():getGridSquare(spec.x,spec.y,spec.z)
 if not square then return end
 local result,objects=nil,square:getWorldObjects()
 for i=0,objects:size()-1 do local item=objects:get(i):getItem()
  if item and item:getID()==spec.id then assert(not result,'duplicate floor fixture ID');result=item end
 end
 return result
end
local function status(state,stage)
 local item,world=state.pickup,state.pickup:getWorldItem()
 local container=item:getContainer()
 local present=world and world:getSquare() and world:getSquare():getWorldObjects():contains(world) or false
 local action=state.pickupAction
 print('[EQUIPMENT_TEST] FLOOR_STATE stage='..stage..' id='..item:getID()
  ..' root='..tostring(container==state.root)..' container='..tostring(container and container:getType())
  ..' world='..tostring(world~=nil)..' worldPresent='..tostring(present)
  ..' sourceContains='..tostring(state.pickupSource and state.pickupSource:contains(item))
  ..' dontAdd='..tostring(action and action.dontAdd))
 return world,present
end
function Floor.prepare(state,seed,kind)
 local player=state.player
 if isClient() then
  state.floor=assert(state.ids.floor,'authoritative floor fixture metadata missing')
  state.pickup=assert(Floor.resolve(state.floor),'authoritative floor fixture has not replicated')
 else
  local square=assert(player:getCurrentSquare(),'floor fixture square missing')
  if state.id=='tidy-floor' then
   state.pickup=assert(instanceItem(kind),'native borrowed floor fixture creation failed')
   state.pickup:setWorldZRotation(37)
   square:AddWorldInventoryItem(state.pickup,0.5,0.5,0,true)
  else state.pickup=assert(square:AddWorldInventoryItem(kind or 'Base.Plank',0.5,0.5,0),'native floor fixture creation failed') end
  state.floor={id=state.pickup:getID(),x=square:getX(),y=square:getY(),z=square:getZ()}
 end
 if state.id=='tidy-floor' and not isClient() then
  local world=assert(state.pickup:getWorldItem())
  state.floor.pose={world:getOffX(),world:getOffY(),world:getOffZ(),state.pickup:getWorldXRotation(),state.pickup:getWorldYRotation(),state.pickup:getWorldZRotation()}
 end
 state.items.pickup=state.pickup;state.owned[#state.owned+1]=state.pickup
 state.pickupWorld=assert(state.pickup:getWorldItem(),'fixture must start as an actual world item')
 assert(state.pickupWorld:getItem()==state.pickup and state.pickup:getID()==state.floor.id,'floor fixture identity differs')
 if not isServer() then
  assert(getPlayerLoot(player:getPlayerNum()),'native loot UI missing'):refreshBackpacks()
  state.pickupSource=assert(state.pickup:getContainer(),'floor fixture lacks native source')
  assert(state.pickupSource==ISInventoryPage.GetFloorContainer(player:getPlayerNum())
   and state.pickupSource:contains(state.pickup),'native floor UI did not associate exact world item')
 end
 assert(state.root:hasRoomFor(player,state.pickup),'floor fixture must fit without equipment or capacity changes')
 status(state,'prepared')
end
function Floor.enqueue(state,helpers)
 local queue=helpers.queue();local before=#queue.queue
 status(state,'enqueue')
 assert(state.pickup:getWorldItem()==state.pickupWorld and state.pickupSource:contains(state.pickup),'floor fixture changed before native grab')
 helpers.run(ISInventoryPaneContextMenu.onGrabItems,{state.pickup},state.player:getPlayerNum())
 for i=before+1,#queue.queue do local action=queue.queue[i]
  if action.Type=='ISInventoryTransferAction' and action.item==state.pickup then
   assert(not state.pickupAction,'duplicate native floor pickup');state.pickupAction=action
  end
 end
 assert(state.pickupAction and state.pickupAction.srcContainer==state.pickupSource
  and state.pickupAction.destContainer==state.root,'native floor grab callback did not enqueue exact transfer')
 return state.pickupAction
end
function Floor.controls(state,helpers)
 if helpers.native then return end
 helpers.denied(state.pickupAction,state.tailAction,true,'move_dependent')
 helpers.denied(state.tailAction,state.pickupAction,false,'move_dependent')
 local queue=helpers.queue();local before={}
 for i,action in ipairs(queue.queue) do before[i]=action end
 local toolkit=PZSurvivorToolkit
 local decision=toolkit.ActionQueuePolicy.evaluateCancel(queue,state.pickupAction,true)
 assert(not decision.allowed and decision.reason=='operation_dependent','floor cancellation must remain protected')
 local ok,reason=toolkit.ActionQueue.cancelOperation(queue,state.pickupAction)
 assert(not ok and reason=='operation_dependent','floor cancellation API bypassed policy')
 assert(#before==#queue.queue,'denied floor cancellation changed queue size')
 for i,action in ipairs(before) do assert(queue.queue[i]==action,'denied floor cancellation changed queue order') end
 state.floorProtected=true
end
function Floor.verify(state,mode)
 local world,present=status(state,'verify')
 assert(state.pickup:getID()==state.floor.id,'floor pickup ID changed')
 assert(state.pickup:getContainer()==state.root and state.root:getItemById(state.floor.id)==state.pickup,
  'exact floor pickup did not reach root; see FLOOR_STATE evidence')
 assert(not world and not present,'picked-up fixture still has a world object')
 local square=getCell():getGridSquare(state.floor.x,state.floor.y,state.floor.z)
 assert(square and not square:getWorldObjects():contains(state.pickupWorld),'original floor object remains after pickup')
 assert(not Floor.resolve(state.floor),'floor fixture ID remains on original square')
 assert(isServer() or mode=='native' or state.floorProtected,'floor policy protection evidence missing')
 return {floorPickup=true,pickupID=state.floor.id,pickupWorldRemoved=true,floorProtected=mode=='toolkit'}
end
function Floor.cleanup(state)
 local world=state.pickup and state.pickup:getWorldItem()
 if world then
  assert(world:getItem()==state.pickup and state.pickup:getID()==state.floor.id,'refusing cleanup of unrelated world item')
  local square=world:getSquare()
  assert(square and square:getX()==state.floor.x and square:getY()==state.floor.y and square:getZ()==state.floor.z,
   'refusing cleanup of fixture outside its original square')
  if square:getWorldObjects():contains(world) then square:transmitRemoveItemFromSquare(world);square:removeWorldObject(world) end
  state.pickup:setWorldItem(nil)
 end
end
return Floor
