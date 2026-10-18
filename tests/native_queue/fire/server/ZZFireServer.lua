if not isServer() then return end
local Authority=require 'QueueFireAuthority'
local waiting,pending
local function reply(player,command,value) sendServerCommand(player,'FireQueueTest',command,value) end
local function failed(player,problem)
 reply(player,'Failed',{ok=false,error=tostring(problem)});print('[QUEUE_TEST] FAIL fire server '..tostring(problem))
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='FireQueueTest' then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1','unexpected fire actor')
  if command=='Prepare' then
   assert(not waiting and not pending,'duplicate fire request')
   if not player:getSquare() then waiting={player=player,case=args.case}
   else player:setGhostMode(true);reply(player,'Prepared',Authority.prepare(player,args.case)) end
  elseif command=='Invalidate' then reply(player,'Invalidated',Authority.invalidate(player,args.case))
  else assert(command=='Verify' and not pending,'unexpected fire request');pending={player=player,case=args.case,since=getTimestampMs()} end
 end)
 if not ok then failed(player,problem) end
end)
Events.OnTick.Add(function()
 if waiting and waiting.player:getSquare() then
  local request=waiting;waiting=nil
  local ok,problem=pcall(function()request.player:setGhostMode(true);reply(request.player,'Prepared',Authority.prepare(request.player,request.case))end)
  if not ok then failed(request.player,problem) end
 end
 if not pending then return end
 local ok,result,problem=pcall(Authority.verify,pending.player,pending.case)
 if not ok then failed(pending.player,result);pending=nil
 elseif result then reply(pending.player,'Verified',result);pending=nil
 elseif getTimestampMs()-pending.since>20000 then failed(pending.player,problem);pending=nil end
end)
