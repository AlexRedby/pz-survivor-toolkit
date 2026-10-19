if not isServer()then return end
local Fixture=require 'QueueInventoryGrabFixture'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local step,state,previous,pending,target=1
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='InventoryGrabTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[step],'inventory grab actor/order differs')
  if command=='Prepare'then
   assert(not state,'inventory grab already prepared');state=Fixture.prepare(player,args.case,previous);previous=nil
   print('[INVENTORY_GRAB_TEST] PREPARED '..JSON.encode(state.ids));sendServerCommand(player,module,'Prepared',state.ids)
  else
   assert(command=='Verify'and state and not pending,'unexpected inventory grab command')
   assert(args.targetId==state.ids.bottles[1].id or args.targetId==state.ids.bottles[2].id,'unknown transfer target')
   target=args.targetId;pending=getTimestampMs()
  end
 end)
 if not ok then print('[QUEUE_TEST] FAIL inventory grab server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value,reason=pcall(Fixture.receipt,state,target)
 if ok and value then
  print('[INVENTORY_GRAB_TEST] VERIFIED '..JSON.encode(value));sendServerCommand(state.player,'InventoryGrabTest','Verified',value)
  previous=state;state,pending=nil,nil;step=step+1
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QUEUE_TEST] FAIL inventory grab authority '..tostring(ok and reason or value));pending=nil
 end
end)
