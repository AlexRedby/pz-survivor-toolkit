require 'Entity/TimedActions/ISHandcraftAction'
local states, race = {}, nil
local function reply(player, command, args) sendServerCommand(player, 'CraftChainTest', command, args or {}) end
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
 if race then
  local items=race.crate:getItems()
  for i=0,items:size()-1 do local item=items:get(i)
   if item:getID()==id and not seen[id] then count=count+1;seen[id]=true end
  end
 end
 return count
end
local function totalPlanks()
 local count,seen=0,{}
 for _,state in pairs(states) do eachItem(state,function(item) if item:getFullType()=='Base.Plank' then count=count+1 end end,seen) end
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
 return object,crate,{x=square:getX(),y=square:getY(),sprite=object:getSprite():getName()}
end
local nativePerform=ISHandcraftAction.performRecipe
ISHandcraftAction.performRecipe=function(action,...)
 local result=nativePerform(action,...)
 local player=action.character;local state=player and states[player:getUsername()]
 local created=action.logic and action.logic:getRecipeData():getAllCreatedItems()
 if state and created and created:size()>0 then
  local name=action.craftRecipe:getName()
  state.completed[name]=(state.completed[name] or 0)+1
  if race and race.started and name=='SawLogs' then race.completed=race.completed+1 end
  print('[CRAFT_TEST] SERVER_NATIVE_COMPLETE '..player:getUsername()..' recipe='..name..' outputs='..created:size())
 end
 return result
end
Events.OnServerStarted.Add(function() print('[QUEUE_TEST] SERVER_READY') end)
local function onCommand(module,command,player,args)
 if module~='CraftChainTest' then return end
 local user,inv=player:getUsername(),player:getInventory();local state=states[user]
 if command=='Ready' then
  if state then reply(player,'Setup',state.ids);return end
  local object,crate,ids=surfaceCrate(player,user)
  state={player=player,object=object,crate=crate,ids=ids,completed={}};states[user]=state
  -- Native server XP packet synchronizes the client; SyncXp only sends client -> server.
  addXpNoMultiplier(player,Perks.Carving,Perks.Carving:getTotalXpForLevel(1)+1)
  assert(player:getPerkLevel(Perks.Carving)>=1,'server skill grant failed')
  player:setMaxWeightBase(50);player:setMaxWeight(50)
  for _,spec in ipairs({{'saw','Base.Saw'},{'knife','Base.HuntingKnife'}}) do
   local source=spec[1]=='saw' and crate or inv
   local item=assert(source:AddItem(spec[2]),spec[2]);item:setCondition(item:getConditionMax());item:applyMaxSharpness()
   ids[spec[1]]=item:getID();if source==inv then sendAddItemToContainer(inv,item) end
  end
  for _,spec in ipairs({{'cancelCurrent','Base.BookCarpentry1'},{'cancelTail','Base.BookCooking1'}}) do
   local book=assert(inv:AddItem(spec[2]),spec[2]);ids[spec[1]]=book:getID();sendAddItemToContainer(inv,book)
  end
  local log=assert(crate:AddItem('Base.Log'));ids.log=log:getID()
  state.baseline=counts(state)
  assert((state.baseline['Base.Plank'] or 0)==0 and (state.baseline['Base.SmallHandle'] or 0)==0 and (state.baseline['Base.WoodenSpoon'] or 0)==0,'fresh fixture already has chain outputs')
  object:transmitCompleteItemToClients();object:transmitModData()
  print('[CRAFT_TEST] SERVER_SETUP '..user..' log='..ids.log..' surface='..ids.sprite..' carving='..player:getPerkLevel(Perks.Carving))
  reply(player,'Setup',ids)
 elseif command=='VerifyCancel' and state then
  local ok,error=pcall(function()
   assert(state.crate:getItemById(state.ids.log),'waiting plan moved or consumed raw log')
   assert(state.crate:getItemById(state.ids.saw),'waiting plan moved shelf saw')
   assert(rawIdCount(state.ids.log)==1 and rawIdCount(state.ids.saw)==1 and rawIdCount(state.ids.knife)==1,'waiting cancel lost or duplicated raw/tool ID')
   local totals=counts(state)
   assert((totals['Base.Plank'] or 0)==0 and (totals['Base.SmallHandle'] or 0)==0 and (totals['Base.WoodenSpoon'] or 0)==0,'waiting canceled plan produced outputs')
   for _,name in ipairs({'SawLogs','CarveSmallHandlesFromPlank','CarveWoodenSpoon'}) do assert(not state.completed[name],'waiting recipe unexpectedly executed '..name) end
   assert(inv:getItemById(state.ids.cancelCurrent) and inv:getItemById(state.ids.cancelTail),'unrelated book lost')
  end)
  print('[CRAFT_TEST] SERVER_CANCEL_VERIFY '..user..' ok='..tostring(ok)..' error='..tostring(error))
  reply(player,'CancelVerified',{ok=ok,error=tostring(error)})
 elseif command=='VerifyChain' and state then
  local ok,error=pcall(function()
   local totals=counts(state)
   assert((totals['Base.Plank'] or 0)==2,'chain did not leave exactly two planks')
   assert((totals['Base.SmallHandle'] or 0)==11,'chain did not leave exactly eleven small handles')
   assert((totals['Base.WoodenSpoon'] or 0)==1,'chain did not create exactly one spoon')
   assert(rawIdCount(state.ids.log)==0,'original log survived or duplicated')
   for _,name in ipairs({'SawLogs','CarveSmallHandlesFromPlank','CarveWoodenSpoon'}) do assert(state.completed[name]==1,'native recipe count differs '..name) end
   for _,name in ipairs({'saw','knife'}) do assert(rawIdCount(state.ids[name])==1,'tool ID lost or duplicated '..name) end
   assert(state.crate:getItemById(state.ids.saw),'native floor keep tool did not remain on shelf')
   state.verified=true
  end)
  print('[CRAFT_TEST] SERVER_CHAIN_VERIFY '..user..' ok='..tostring(ok)..' error='..tostring(error))
  reply(player,'ChainVerified',{ok=ok,error=tostring(error)})
 elseif command=='PrepareRace' and state then
  assert(state.verified,'race requested before authoritative chain completion')
  if not state.ids.raceSaw then
   local saw=assert(inv:AddItem('Base.Saw'));saw:setCondition(saw:getConditionMax())
   state.ids.raceSaw=saw:getID();sendAddItemToContainer(inv,saw)
  end
  if not race then
   local object,crate,ids=surfaceCrate(player,'shared')
   local log=assert(crate:AddItem('Base.Log'));ids.log=log:getID()
   race={object=object,crate=crate,ids=ids,ready={},done={},completed=0}
   object:transmitCompleteItemToClients();object:transmitModData()
  end
  reply(player,'RaceSetup',race.ids)
 elseif command=='RaceReady' and race and state then
  assert(args.log==race.ids.log,'clients did not plan against the same shared raw ID')
  race.ready[user]=true
  local number=0;for _ in pairs(race.ready) do number=number+1 end
  if number==2 and not race.started then
   race.started=true;race.planksBefore=totalPlanks()
   for _,owner in pairs(states) do reply(owner.player,'RaceStart',{log=race.ids.log}) end
  end
 elseif command=='RaceDone' and race and state then
  race.done[user]=true
  local number=0;for _ in pairs(race.done) do number=number+1 end
  if number==2 and not race.verified then
   race.verified=true
   local ok,error=pcall(function()
    assert(race.completed==1,'shared raw item produced '..race.completed..' native crafts')
    assert(rawIdCount(race.ids.log)==0,'shared original log survived or duplicated')
    assert(totalPlanks()==race.planksBefore+3,'shared log did not produce exactly three planks globally')
   end)
   print('[CRAFT_TEST] SERVER_RACE_VERIFY ok='..tostring(ok)..' completed='..race.completed..' error='..tostring(error))
   for _,owner in pairs(states) do reply(owner.player,'RaceVerified',{ok=ok,error=tostring(error),completed=race.completed}) end
  end
 end
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='CraftChainTest' then return end
 local ok,error=pcall(onCommand,module,command,player,args)
 if not ok then print('[CRAFT_TEST] FAIL server '..tostring(command)..' '..tostring(error)) end
end)
