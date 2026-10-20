if not isServer()then return end
local Fixture=require 'QueueFoodFixture'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local state,pending,previous;local step=1
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='FoodTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[step],'food actor/order differs')
  if command=='Prepare'then
   assert(not state,'food already prepared');state=Fixture.prepare(player,args.case,previous);previous=nil
   print('[FOOD_TEST] PREPARED '..JSON.encode(state.ids));sendServerCommand(player,module,'Prepared',state.ids)
  else assert(command=='Verify'and state and state.player==player and not pending,'unexpected food request');pending=getTimestampMs()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL food server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value,reason=pcall(Fixture.verify,state)
 if ok and value then
  print('[FOOD_TEST] VERIFIED '..JSON.encode(value));sendServerCommand(state.player,'FoodTest','Verified',value)
  previous=state;state,pending=nil,nil;step=step+1
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QUEUE_TEST] FAIL food authority '..tostring(ok and reason or value));pending=nil
 end
end)
