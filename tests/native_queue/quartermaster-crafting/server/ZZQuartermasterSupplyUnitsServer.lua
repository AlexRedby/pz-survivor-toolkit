if not isServer()then return end
local config=require 'QueueTestSelection'
if config.cases[1]~='uses'then return end
local F=require 'QueueSupplyUnitsFixture'
local JSON=require 'QueueHealthEvents'
local state,previous,pending
local index=1
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='QuartermasterSupplyTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.index==index,'supply actor/order differs')
  if command=='Prepare'then
   assert(not state and index<=3,'supply already prepared');player:setGhostMode(true)
   state=F.prepare(player,index,args.position,previous);previous=nil
   local value=F.descriptor(state);print('[QM_USES] PREPARED '..JSON.encode(value));sendServerCommand(player,module,'Prepared',value)
  elseif command=='Verify'then assert(state and not pending,'unexpected supply verification');pending=getTimestampMs()
  else
   assert(command=='Cleanup'and previous and index==4,'unexpected supply cleanup')
   F.cleanup(previous,true);previous=nil
   print('[QM_USES] CLEANUP');sendServerCommand(player,module,'Cleaned',{})
  end
 end)
 if not ok then print('[QM_USES] FAIL server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value=pcall(F.verify,state)
 if ok and value then
  print('[QM_USES] VERIFIED '..JSON.encode(value));sendServerCommand(state.player,'QuartermasterSupplyTest','Verified',value)
  previous=state;state,pending=nil,nil;index=index+1
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QM_USES] FAIL authority '..tostring(value));pending=nil
 end
end)
