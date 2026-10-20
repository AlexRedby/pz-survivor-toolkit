if not isServer()then return end
local F=require 'QueueInventoryTransferFixture'
local JSON=require 'QueueHealthEvents'
local state,pending,verified
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='InventoryTransferTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case=='trunk-15','unexpected transfer actor/case')
  if command=='Prepare'then
   assert(not state,'fixture already prepared');state=F.prepare(player)
   print('[INVENTORY_TRANSFER_TEST] PREPARED '..JSON.encode(state.ids));sendServerCommand(player,module,'Prepared',state.ids)
  else assert(command=='Verify'and state and not pending and not verified,'unexpected transfer command');pending=getTimestampMs()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL inventory transfer server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value,reason=pcall(F.receipt,state)
 if ok and value then
  print('[INVENTORY_TRANSFER_TEST] VERIFIED '..JSON.encode(value));sendServerCommand(state.player,'InventoryTransferTest','Verified',value)
  pending=nil;verified=true
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QUEUE_TEST] FAIL inventory transfer authority '..tostring(ok and reason or value));pending=nil
 end
end)
