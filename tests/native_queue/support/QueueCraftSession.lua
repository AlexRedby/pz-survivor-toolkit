-- Exact fixture ownership; no container, world, player-inventory or queue-wide wipes.
return function(S,server)
 local function snapshot(player)
  local result={player=player,weight=player:getMaxWeight(),baseWeight=player:getMaxWeightBase(),xp={},total=player:getXp():getTotalXp(),
   primary=player:getPrimaryHandItem(),secondary=player:getSecondaryHandItem()}
  for _,perk in ipairs({Perks.Carving,Perks.Woodwork}) do
   result.xp[#result.xp+1]={perk,player:getXp():getXP(perk),player:getPerkLevel(perk)}
  end
  return result
 end
 local function restore(state)
  local player=state.player;local xp=player:getXp()
  for _,spec in ipairs(state.xp) do
   if xp:getXP(spec[1])~=spec[2] or player:getPerkLevel(spec[1])~=spec[3] then
    -- The two-argument AddXP wrapper ignores server-side remote players.
    xp:setXPToLevel(spec[1],0);xp:AddXP(spec[1],spec[2],false,false,false,false);player:setPerkLevelDebug(spec[1],spec[3])
   end
   local actualXP,actualLevel=xp:getXP(spec[1]),player:getPerkLevel(spec[1])
   assert(math.abs(actualXP-spec[2])<.001 and actualLevel==spec[3],
    'skill reset failed actor='..player:getUsername()..' perk='..tostring(spec[1])..' expectedXP='..spec[2]..' actualXP='..actualXP..' expectedLevel='..spec[3]..' actualLevel='..actualLevel)
  end
  xp:setTotalXP(state.total);assert(math.abs(xp:getTotalXp()-state.total)<.001,'total XP reset failed')
  player:setMaxWeightBase(state.baseWeight);player:setMaxWeight(state.weight)
  assert(player:getMaxWeightBase()==state.baseWeight and player:getMaxWeight()==state.weight,'weight reset failed')
  player:setPrimaryHandItem(state.primary);player:setSecondaryHandItem(state.secondary)
 end
 S.configure=function(context)
  local items,objects,players={},{},{}
  context.receipt={items={},squares={}}
  context.ownItem=function(item)
   if not items[item:getID()] then context.receipt.items[#context.receipt.items+1]=item:getID() end
   items[item:getID()]=item
  end
  context.ownObject=function(object)
   local square=object:getSquare();objects[#objects+1]={object=object,square=square}
   context.receipt.squares[#context.receipt.squares+1]={x=square:getX(),y=square:getY(),z=square:getZ()}
  end
  context.player=function(player) if not players[player:getUsername()] then players[player:getUsername()]=snapshot(player) end end
  context.cleanOwned=function()
   for _,item in pairs(items) do
    local world=item:getWorldItem();local container=item:getContainer()
    if world and world:getSquare() then world:getSquare():transmitRemoveItemFromSquare(world)
    elseif container and container:contains(item) then
     for _,state in pairs(players) do state.player:removeFromHands(item) end
     container:Remove(item);sendRemoveItemFromContainer(container,item)
     assert(not container:contains(item),'owned item removal failed')
    end
   end
   for _,entry in ipairs(objects) do
    local object,square=entry.object,entry.square
    local container=object:getContainer()
    assert(not container or container:getItems():size()==0,'foreign item in owned surface; retain it for diagnosis')
    -- Stock table sprites have multi-square partners which this fixture never owns or creates.
    if square:getObjects():contains(object) then square:transmitRemoveItemFromSquare(object,false) end
    assert(not square:getObjects():contains(object),'owned surface removal failed')
   end
   for _,state in pairs(players) do restore(state) end
   for _,item in pairs(items) do
    assert((not item:getWorldItem() or not item:getWorldItem():getSquare()) and (not item:getContainer() or not item:getContainer():contains(item)),'owned item survived reset')
   end
  end
  context.verifyOwned=function(receipt)
   assert(type(receipt)=='table' and type(receipt.items)=='table' and type(receipt.squares)=='table','missing ownership receipt')
   local owned={};for _,id in ipairs(receipt.items) do owned[id]=true end
   local function container(value)
    local contents=value:getItems()
    for i=0,contents:size()-1 do if owned[contents:get(i):getID()] then return false end end
    return true
   end
   if not container(getPlayer():getInventory()) then return false,'owned inventory item still replicated' end
   for _,position in ipairs(receipt.squares) do
    for dx=-2,2 do for dy=-2,2 do
     local square=getCell():getGridSquare(position.x+dx,position.y+dy,position.z)
     if not square then return false,'cleanup square unloaded' end
     local objects=square:getObjects()
     for i=0,objects:size()-1 do local object=objects:get(i)
      if object:getModData()[context.ownerKey or 'CraftChainTestOwner'] then return false,'owned surface still replicated' end
      if object:getContainer() and not container(object:getContainer()) then return false,'owned container item still replicated' end
     end
     local ground=square:getWorldObjects()
     for i=0,ground:size()-1 do if owned[ground:get(i):getItem():getID()] then return false,'owned ground output still replicated' end end
    end end
   end
   return true
  end
  if not server then
   local state=snapshot(getPlayer());local player=state.player
   local x,y,z=player:getX(),player:getY(),player:getZ()
   local autoDrink,coreAuto=getPlayer():getAutoDrink(),getCore():getOptionAutoDrink()
   context.restoreClient=function()
    restore(state);player:teleportTo(x,y,z);player:setForceX(x);player:setForceY(y)
    player:setAutoDrink(autoDrink);getCore():setOptionAutoDrink(coreAuto)
   end
  end
 end
end
