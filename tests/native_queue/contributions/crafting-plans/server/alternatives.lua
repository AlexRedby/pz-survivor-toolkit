local Session=QueueCraftSession
local Events=Session and Session.events or Events
require 'Entity/TimedActions/ISHandcraftAction'
local states = {}
local function reply(player,command,args)
 if Session then Session.reply(player,command,args) else sendServerCommand(player,'CraftChainTest',command,args or {}) end
end
local function eachItem(state, visit, seen)
 seen = seen or {}
 local function item(value)
  if value and not seen[value:getID()] then seen[value:getID()]=true;visit(value) end
 end
 for _,container in ipairs({state.player:getInventory(),state.crate}) do
  local items=container:getItems();for i=0,items:size()-1 do item(items:get(i)) end
 end
 local square=state.player:getSquare()
 for dx=-2,2 do for dy=-2,2 do
  local ground=getCell():getGridSquare(square:getX()+dx,square:getY()+dy,0)
  if ground then
   local objects=ground:getWorldObjects()
   for i=0,objects:size()-1 do item(objects:get(i):getItem()) end
  end
 end end
end
local function counts(state)
 local result={}
 eachItem(state,function(item) local name=item:getFullType();result[name]=(result[name] or 0)+1 end)
 return result
end
local function rawIdCount(id)
 local count,seen=0,{}
 for _,state in pairs(states) do eachItem(state,function(item) if item:getID()==id then count=count+1 end end,seen) end
 return count
end
local function surfaceCrate(player, owner)
 local origin=player:getSquare();local square
 for _,offset in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
  local candidate=getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],0)
  if candidate and candidate:canStand() and origin:canReachTo(candidate) then square=candidate;break end
 end
 assert(square,'no loaded reachable surface fixture square')
 local object
 for _,sprite in ipairs({'furniture_tables_low_01_0','furniture_tables_high_01_0','furniture_tables_low_01_1','furniture_tables_high_01_1'}) do
  local candidate=IsoThumpable.new(getCell(),square,sprite,false,{})
  if candidate:isGenericCraftingSurface() then object=candidate;break end
 end
 assert(object,'stock table sprites are not native generic crafting surfaces')
 object:setCanPassThrough(true);object:setIsContainer(true)
 object:getModData().CraftChainTestOwner=owner
 local crate=object:getContainer();crate:setType('crate');crate:setCapacity(100);crate:setExplored(true)
 square:AddSpecialObject(object);square:RecalcProperties();square:RecalcAllWithNeighbours(true)
 if Session then Session.ownObject(object) end
 return object,crate,{x=square:getX(),y=square:getY(),sprite=object:getSprite():getName()}
end
local function performed(action)
 local player=action.character;local state=player and states[player:getUsername()]
 local created=action.logic and action.logic:getRecipeData():getAllCreatedItems()
 if state and created and created:size()>0 then
  local name=action.craftRecipe:getName()
  state.completed[name]=(state.completed[name] or 0)+1
  if Session then for i=0,created:size()-1 do Session.ownItem(created:get(i)) end end
  print('[CRAFT_TEST] SERVER_NATIVE_COMPLETE '..player:getUsername()..' recipe='..name..' outputs='..created:size())
 end
end
if Session then Session.performed=performed else
 local nativePerform=ISHandcraftAction.performRecipe
 ISHandcraftAction.performRecipe=function(action,...)
  local result=nativePerform(action,...);performed(action);return result
 end
end
Events.OnServerStarted.Add(function() print('[QUEUE_TEST] SERVER_READY') end)
local function onCommand(module,command,player,args)
 if module~='CraftChainTest' then return end
 local user,inv=player:getUsername(),player:getInventory();local state=states[user]
 if command=='Ready' then
  if state then reply(player,'Setup',state.ids);return end
  if Session then Session.player(player) end
  local object,crate,ids=surfaceCrate(player,user)
  state={player=player,object=object,crate=crate,ids=ids,completed={}};states[user]=state
  -- Native server XP packet synchronizes the client; SyncXp only sends client -> server.
  addXpNoMultiplier(player,Perks.Carving,Perks.Carving:getTotalXpForLevel(1)+1)
  assert(player:getPerkLevel(Perks.Carving)>=1,'server skill grant failed')
  player:setMaxWeightBase(50);player:setMaxWeight(50)
  for _,spec in ipairs({{'saw','Base.Saw'},{'knife','Base.HuntingKnife'}}) do
   local source=spec[1]=='saw' and crate or inv
   local item=assert(source:AddItem(spec[2]),spec[2]);if Session then Session.ownItem(item) end;item:setCondition(item:getConditionMax());item:applyMaxSharpness()
   ids[spec[1]]=item:getID();if source==inv then sendAddItemToContainer(inv,item) end
  end
  for _,spec in ipairs({{'cancelCurrent','Base.BookCarpentry1'},{'cancelTail','Base.BookCooking1'}}) do
   local book=assert(inv:AddItem(spec[2]),spec[2]);if Session then Session.ownItem(book) end;ids[spec[1]]=book:getID();sendAddItemToContainer(inv,book)
  end
  local log=assert(crate:AddItem('Base.Log'));if Session then Session.ownItem(log) end;ids.log=log:getID()
  for _,spec in ipairs({{'log2','Base.Log'},{'branch1','Base.TreeBranch2'},{'branch2','Base.TreeBranch2'},
   {'stick','Base.WoodenStick2'},{'longstick','Base.LongStick'},{'sapling','Base.Sapling'},
   {'handle','Base.SmallHandle'},{'firewood','Base.Firewood'},{'cleaver','Base.MeatCleaver'},{'unusable','Base.UnusableWood'}}) do
   local item=assert(inv:AddItem(spec[2]),spec[2]);if Session then Session.ownItem(item) end;item:setCondition(item:getConditionMax())
   if instanceof(item,'HandWeapon') then item:applyMaxSharpness() end
   ids[spec[1]]=item:getID();sendAddItemToContainer(inv,item)
  end

  state.baseline=counts(state)
  assert((state.baseline['Base.Plank'] or 0)==0 and (state.baseline['Base.SmallHandle'] or 0)==1 and (state.baseline['Base.WoodenSpoon'] or 0)==0,'fresh fixture already has chain outputs')
  object:transmitCompleteItemToClients();object:transmitModData()
  print('[CRAFT_TEST] SERVER_SETUP '..user..' log='..ids.log..' surface='..ids.sprite..' carving='..player:getPerkLevel(Perks.Carving))
  reply(player,'Setup',ids)
 elseif command=='VerifyAlternatives' and state then
  local ok,error=pcall(function()
   local totals=counts(state)
   assert((totals['Base.WoodenSpoon'] or 0)==2,'expected exactly two spoons')
   assert(state.completed.CarveWoodenSpoon==2 and state.completed.Carve2SmallHandles==1,'prerequisite native recipe counts differ')
   assert(rawIdCount(state.ids.unusable)==0 and rawIdCount(state.ids.handle)==0,'chosen intermediate/raw IDs survived')
   for _,name in ipairs({'firewood','stick','longstick','sapling','knife','cleaver','saw'}) do
    assert(rawIdCount(state.ids[name])==1,'unchosen resource or kept tool lost/duplicated '..name)
   end
   assert(state.crate:getItemById(state.ids.saw),'native floor keep saw did not remain on shelf')
   local repeated=args.phase~='chain'
   assert((totals['Base.SmallHandle'] or 0)==(repeated and 9 or 1),'leftover handles differ')
   assert((state.completed.Carve4SmallHandles or 0)==(repeated and 2 or 0),'repeated native counts differ')
   for _,name in ipairs({'branch1','branch2'}) do assert(rawIdCount(state.ids[name])==(repeated and 0 or 1),'branch count differs '..name) end
   local logs=args.phase=='logs'
   assert((totals['Base.Plank'] or 0)==(logs and 6 or 0),'plank count differs')
   assert((state.completed.SawLogs or 0)==(logs and 2 or 0),'saw native counts differ')
   for _,name in ipairs({'log','log2'}) do assert(rawIdCount(state.ids[name])==(logs and 0 or 1),'log count differs '..name) end
  end)
  print('[CRAFT_TEST] SERVER_ALTERNATIVES_VERIFY '..user..' phase='..args.phase..' ok='..tostring(ok)..' error='..tostring(error))
  reply(player,'AlternativesVerified',{ok=ok,error=tostring(error),phase=args.phase})
 end
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='CraftChainTest' then return end
 local ok,error=pcall(onCommand,module,command,player,args)
 if not ok then print('[CRAFT_TEST] FAIL server '..tostring(command)..' '..tostring(error)) end
end)

if Session then Session.cleanup=function() Session.cleanOwned();states={};return true end end
