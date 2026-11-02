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
  local itemTypes,lease,journal,World={},nil,nil,nil
  context.receipt={items={},squares={}}
  local function cleanupCurrent()
   return (not S.current or S.current()==context) and (S.epoch==nil or S.epoch==context.epoch)
  end
  context.cleanupCurrent=cleanupCurrent
  context.ownItem=function(item)
   assert(not lease,'fixture ownership is frozen for cleanup')
   assert(not items[item:getID()] or items[item:getID()]==item,'owned item identity rebound')
   assert(not itemTypes[item:getID()] or itemTypes[item:getID()]==item:getFullType(),'owned item type changed')
   itemTypes[item:getID()]=item:getFullType()
   if not items[item:getID()] then context.receipt.items[#context.receipt.items+1]=item:getID() end
   items[item:getID()]=item
  end
  context.ownObject=function(object)
   assert(not lease,'fixture ownership is frozen for cleanup')
   local square=assert(object:getSquare(),'owned surface has no square')
   local key=context.ownerKey or 'CraftChainTestOwner'
   local owner=assert(object:getModData()[key],'owned surface has no fixture mark')
   objects[#objects+1]={object=object,square=square,key=key,owner=owner}
   context.receipt.squares[#context.receipt.squares+1]={x=square:getX(),y=square:getY(),z=square:getZ()}
  end
  context.player=function(player)
   assert(not lease,'fixture ownership is frozen for cleanup')
   local previous=players[player:getUsername()]
   assert(not previous or previous.player==player,'fixture player identity rebound')
   if not previous then players[player:getUsername()]=snapshot(player) end
  end
  local function guard()
   assert(context.case==lease.case and context.epoch==lease.epoch,'cleanup generation changed')
   assert(cleanupCurrent(),'cleanup context is no longer current')
   for _,entry in ipairs(lease.items) do
    local item=entry.item
    assert(items[entry.id]==item and item:getID()==entry.id and item:getFullType()==entry.kind,'owned item identity changed')
    local container=item:getContainer()
    assert(container==entry.container or container==nil,'owned item moved during cleanup')
    local world=item:getWorldItem()
    assert(world==entry.world or world==nil and entry.world and journal and World.removed(journal,entry.world),
     'owned item world binding changed during cleanup')
   end
   for index,entry in ipairs(objects) do
    local square=entry.object:getSquare()
    assert(lease.objects[index]==entry and (square==entry.square or square==nil and journal and World.removed(journal,entry.object)),
     'owned surface moved or rebound')
    assert(entry.object:getModData()[entry.key]==entry.owner,'owned surface fixture mark changed')
    local container=entry.object:getContainer()
    local contents=container and container:getItems()
    for i=0,(contents and contents:size() or 0)-1 do
     local item=contents:get(i)
     assert(items[item:getID()]==item,'foreign item in owned surface; retain it for diagnosis')
    end
   end
   assert(#objects==#lease.objects,'fixture world ownership changed during cleanup')
   return true
  end
  context.cleanOwned=function()
   World=World or require 'QueueFixtureWorldCleanup'
   if not lease then
    lease={case=context.case,epoch=context.epoch,items={},objects={}}
    for id,item in pairs(items) do
     assert(item:getFullType()==itemTypes[id],'owned item type changed')
     local world=item:getWorldItem()
     lease.items[#lease.items+1]={id=id,kind=itemTypes[id],item=item,container=item:getContainer(),world=world,square=world and world:getSquare()}
     if world then
      local square=assert(world:getSquare(),'owned ground square missing')
      context.receipt.squares[#context.receipt.squares+1]={x=square:getX(),y=square:getY(),z=square:getZ()}
     end
    end
    for i,entry in ipairs(objects) do lease.objects[i]=entry end
   end
   guard()
   if not journal then
    local entries={}
    for _,entry in ipairs(lease.items) do
     if entry.world then entries[#entries+1]={object=entry.world,square=entry.square,item=entry.item} end
    end
    for _,entry in ipairs(objects) do entries[#entries+1]={object=entry.object,square=entry.square} end
    -- Freeze neighbors before any inventory mutation can invoke another callback.
    journal=World.new(entries,{server=server,guard=guard})
   end
   for _,entry in ipairs(lease.items) do
    local item,container=entry.item,entry.container
    if not entry.world and container and container:contains(item) then
     for _,state in pairs(players) do state.player:removeFromHands(item) end
     container:Remove(item);sendRemoveItemFromContainer(container,item)
     assert(not container:contains(item),'owned item removal failed')
    end
   end
   for _,entry in ipairs(objects) do
    local container=entry.object:getContainer()
    assert(not container or container:getItems():size()==0,'nonempty owned surface; retain it for diagnosis')
   end
   World.run(journal);context.receipt.worldCleanup=World.receipt(journal)
   for _,state in pairs(players) do restore(state) end
   for _,entry in ipairs(lease.items) do
    local item=entry.item
    if entry.world then
     assert(World.absent(entry.square,entry.world,item),'owned ground item survived reset')
    else
     assert(not item:getContainer() or not item:getContainer():contains(item),'owned item survived reset')
    end
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
