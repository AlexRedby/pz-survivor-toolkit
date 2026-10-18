if not isServer()then return end
local Fixture=require 'QueueFluidFixture'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local state,pending,previous;local step=1
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='FluidTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[step],'fluid actor/order differs')
  if command=='Prepare'then
   assert(not state,'fluid already prepared');state=Fixture.prepare(player,args.case,previous);previous=nil
   print('[FLUID_TEST] PREPARED '..JSON.encode(state.ids));sendServerCommand(player,module,'Prepared',state.ids)
  else assert(command=='Verify'and state and state.player==player and not pending,'unexpected fluid request');pending=getTimestampMs()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL fluid server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)
Events.OnTick.Add(function()
 if state then
  state.debited=state.debited or {}
  for index,ids in ipairs(state.ids.bottles)do
   local bottle=state.player:getInventory():getItemById(ids.id)
   if bottle and not state.debited[index]and bottle:getFluidContainer():getAmount()<ids.amount-.0001 then
    state.debited[index]=true
    print('[FLUID_TEST] TRACE '..JSON.encode({event='server-debit',case=state.case,id=ids.id,amount=bottle:getFluidContainer():getAmount()}))
   end
  end
 end
 if not pending then return end
 local ok,value,reason=pcall(Fixture.verify,state)
 if ok and value then
  print('[FLUID_TEST] VERIFIED '..JSON.encode(value));sendServerCommand(state.player,'FluidTest','Verified',value)
  previous=state;state,pending=nil,nil;step=step+1
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QUEUE_TEST] FAIL fluid authority '..tostring(ok and reason or value));pending=nil
 end
end)
