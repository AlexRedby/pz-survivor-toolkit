if not isServer() then return end
local Authority=require 'QueueHealthAuthority'
local function session()
 local players=getOnlinePlayers()
 for i=0,players:size()-1 do local player=players:get(i);local result=Authority.session(player)
  if result then sendServerCommand(player,'HealthQueueTest','Session',result) end
 end
end
local Placement=require 'QueueHealthPlacement'
local failed=false
local coordinator=Placement.newAuthority(Authority,function(player,command,args)
 sendServerCommand(player,'HealthQueueTest',command,args)
 if command=='Setup'then session()end
end)
local function failure(problem)
 if failed then return end;failed=true;coordinator.failed=true
 local reason=tostring(problem);print('[QUEUE_TEST] FAIL HEALTH server '..reason)
 local players=getOnlinePlayers()
 for i=0,players:size()-1 do sendServerCommand(players:get(i),'HealthQueueTest','Failed',{error=reason})end
end
Events.OnServerStarted.Add(function()print('[QUEUE_TEST] SERVER_READY')end)
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='HealthQueueTest'or failed then return end
 local ok,problem=pcall(function()
  -- Native network decoding represents an empty Lua argument table as nil.
  if(command=='Ready'or command=='Finish')and args==nil then args={}end
  assert(type(args)=='table','health request arguments missing')
  if coordinator:handle(player,command,args)then return end
  local result,reply
  if command=='Finish'then Authority.finish(player);session();return
  elseif command=='Skip'then result=Authority.skip(player,args.phase,args.reason);reply='Skipped'
  elseif command=='Mutate'then result=Authority.mutate(player,args.phase,args.mode);reply='Mutated'
  elseif command=='Verify'then result=Authority.verify(player,args.phase);reply='Verified'
  elseif command=='Baseline'then result=Authority.baseline(player,args.phase);reply='Baselined'
  else error('unknown medical fixture command')end
  if result then sendServerCommand(player,module,reply,result)end
 end)
 if not ok then failure(problem)end
end)
Events.OnTick.Add(function()
 if failed then return end
 local ok,problem=pcall(function()coordinator:tick()end)
 if not ok then failure(problem)end
end)
