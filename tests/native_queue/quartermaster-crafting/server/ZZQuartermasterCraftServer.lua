if not isServer()then return end
local Fixture=require 'QueueQuartermasterCraftFixture'
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local step,state,previous,pending=1,nil,nil,nil
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='QuartermasterCraftTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[step],'Quartermaster craft actor/order differs')
  if command=='Prepare'then
   assert(not state,'Quartermaster craft already prepared');player:setGhostMode(true)
   state=Fixture.prepare(player,args.case,args.position,previous);previous=nil
   local ids=Fixture.descriptor(state);print('[QM_CRAFT] PREPARED '..JSON.encode(ids));sendServerCommand(player,module,'Prepared',ids)
  else
   assert(command=='Verify'and state and not pending,'unexpected Quartermaster craft request');pending=getTimestampMs()
  end
 end)
 if not ok then print('[QM_CRAFT] FAIL server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value,reason=pcall(Fixture.verify,state)
 if ok and value then
  print('[QM_CRAFT] VERIFIED '..JSON.encode(value));Fixture.cleanup(state)
  sendServerCommand(state.player,'QuartermasterCraftTest','Verified',value)
  previous=state;state,pending=nil,nil;step=step+1
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QM_CRAFT] FAIL authority '..tostring(ok and reason or value));pending=nil
 end
end)
