if not isServer()then return end
local Fixture=require 'QueueCraftUIFixture'
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local state,pending;local step=1
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='CraftUITest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[step],'UI craft actor/order differs')
  if command=='Prepare'then
   assert(not state,'UI craft already prepared');player:setGhostMode(true);state=Fixture.prepare(player,args.case)
   local ids=Fixture.descriptor(state);print('[CRAFT_UI_TEST] PREPARED '..JSON.encode(ids))
   sendServerCommand(player,module,'Prepared',ids)
  else
   assert(command=='Verify'and state and state.player==player and not pending,'unexpected UI craft request')
   pending=getTimestampMs()
  end
 end)
 if not ok then print('[QUEUE_TEST] FAIL craft UI server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value,reason=pcall(Fixture.verify,state)
 if ok and value then
  print('[CRAFT_UI_TEST] VERIFIED '..JSON.encode(value));sendServerCommand(state.player,'CraftUITest','Verified',value)
  state,pending=nil,nil;step=step+1
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QUEUE_TEST] FAIL craft UI authority '..tostring(ok and reason or value));pending=nil
 end
end)
