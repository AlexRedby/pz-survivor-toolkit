if not isServer()then return end
local F=require 'QueueBulkReadingFixture'
local JSON=require 'QueueHealthEvents'
local state,pending
Events.OnClientCommand.Add(function(module,command,player)
 if module~='BulkReadingTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1','unexpected reading actor')
  if command=='Prepare'then
   assert(not state,'duplicate preparation');state=F.prepare(player)
   local packet=F.descriptor(state)
   print('[BULK_READING] PREPARED '..JSON.encode(packet));sendServerCommand(player,module,'Prepared',packet)
  else assert(command=='Verify'and state and not pending,'unexpected reading command');pending=getTimestampMs()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL bulk reading '..tostring(problem))end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value,reason=pcall(F.receipt,state)
 if ok and value then
  print('[BULK_READING] AUTHORITY '..JSON.encode(value));sendServerCommand(state.player,'BulkReadingTest','Verified',value);pending=nil
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QUEUE_TEST] FAIL bulk reading receipt '..tostring(ok and reason or value));pending=nil
 end
end)
