if not isServer()then return end
local Fixture=require 'QuartermasterDistributionFixture'
local JSON=require 'QueueHealthEvents'
local state,pending,preparing
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='QuartermasterDistributionTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1','unexpected distribution actor')
  if command=='Prepare'then
   assert(not state and not preparing,'duplicate distribution preparation')
   preparing={player=player,point=args,since=getTimestampMs()}
  elseif command=='Verify'then assert(state and not pending,'invalid distribution verification');pending=getTimestampMs()
  else
   assert(command=='Cleanup'and state.verified,'cleanup before verified effects')
   Fixture.cleanup(state);sendServerCommand(player,module,'Cleaned',{})
  end
 end)
 if not ok then print('[QUEUE_TEST] FAIL distribution server '..tostring(problem))end
end)
Events.OnTick.Add(function()
 if preparing then
  local request=preparing;local player,point=request.player,request.point
  if player:getCurrentSquare() and math.abs(player:getX()-point.x)<2 and math.abs(player:getY()-point.y)<2 then
   preparing=nil
   local ok,problem=pcall(function()
    state=Fixture.prepare(player,point)
    sendServerCommand(player,'QuartermasterDistributionTest','Prepared',Fixture.descriptor(state))
   end)
   if not ok then print('[QUEUE_TEST] FAIL distribution preparation '..tostring(problem))end
  elseif getTimestampMs()-request.since>20000 then
   print('[QUEUE_TEST] FAIL distribution positioning timeout');preparing=nil
  end
 end
 if not pending then return end
 local ok,result,problem=pcall(Fixture.receipt,state.player,state.boxes,state.ids,state.original)
 if ok and result then
  print('[QM_DISTRIBUTION] AUTHORITY '..JSON.encode(result))
  state.verified=true;sendServerCommand(state.player,'QuartermasterDistributionTest','Verified',result);pending=nil
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QUEUE_TEST] FAIL distribution authority '..tostring(ok and problem or result));pending=nil
 end
end)
