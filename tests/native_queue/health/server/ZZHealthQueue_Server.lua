if not isServer() then return end
local Authority=require 'QueueHealthAuthority'
local function session()
 local players=getOnlinePlayers()
 for i=0,players:size()-1 do local player=players:get(i);local result=Authority.session(player)
  if result then sendServerCommand(player,'HealthQueueTest','Session',result) end
 end
end
Events.OnServerStarted.Add(function() print('[QUEUE_TEST] SERVER_READY') end)
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='HealthQueueTest' then return end
 local reply=command=='Ready' and 'Setup' or command=='Prepare' and 'Prepared' or command=='Mutate' and 'Mutated' or command=='Baseline' and 'Baselined' or command=='Skip' and 'Skipped' or 'Verified'
 local ok,result=pcall(function()
  if command=='Ready' then sendServerCommand(player,module,'Setup',Authority.setup(player));session();return
  elseif command=='Finish' then Authority.finish(player);session();return
  elseif command=='Skip' then return Authority.skip(player,args.phase,args.reason)
  elseif command=='Prepare' then return Authority.prepare(player,args.phase)
  elseif command=='Mutate' then return Authority.mutate(player,args.phase,args.mode)
  elseif command=='Verify' then return Authority.verify(player,args.phase)
  elseif command=='Baseline' then return Authority.baseline(player,args.phase)
  else error('unknown medical fixture command') end
 end)
 if not ok then result={phase=args.phase or 'setup',ok=false,error=tostring(result)};print('[QUEUE_TEST] FAIL HEALTH server '..tostring(result.error)) end
 if result then sendServerCommand(player,module,reply,result) end
end)
