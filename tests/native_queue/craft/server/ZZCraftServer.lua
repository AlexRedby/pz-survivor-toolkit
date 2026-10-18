if not isServer() then return end
local Fixture=require 'QueueCraftFixture'
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local session,waiting,pending
local step=1
local function reply(player,command,value)sendServerCommand(player,'CraftQueueTest',command,value)end
local function fail(player,problem)
 reply(player,'Failed',{ok=false,error=tostring(problem)});print('[QUEUE_TEST] FAIL craft server '..tostring(problem))
end
local function prepare(player,case)
 assert(not session and config.cases[step]==case,'out-of-order craft preparation')
 player:setGhostMode(true);session=Fixture.prepare(player,case)
 local ids=Fixture.descriptor(session)
 reply(player,'Prepared',ids);print('[CRAFT_QUEUE_TEST] PREPARED '..JSON.encode(ids))
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='CraftQueueTest' then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1' and args.case==config.cases[step],'unexpected craft actor/case')
  if command=='Prepare' then
   if not player:getSquare() then assert(not waiting,'duplicate craft wait');waiting={player=player,case=args.case}
   else prepare(player,args.case) end
  else
   assert(session and session.player==player and not pending,'unexpected craft request')
   if command=='RemoveInput' then
    local receipt=Fixture.removeInput(session)
    print('[CRAFT_QUEUE_TEST] REMOVED '..JSON.encode(receipt));reply(player,'Removed',receipt)
   else assert(command=='Verify','unexpected craft verification');pending={player=player,since=getTimestampMs()} end
  end
 end)
 if not ok then fail(player,problem) end
end)
Events.OnTick.Add(function()
 if waiting and waiting.player:getSquare() then
  local request=waiting;waiting=nil
  local ok,problem=pcall(prepare,request.player,request.case)
  if not ok then fail(request.player,problem) end
 end
 if not pending then return end
 local ok,result,problem=pcall(Fixture.verify,session,config.mode=='toolkit')
 if not ok then fail(pending.player,result);pending=nil
 elseif result then
  if session.case=='borrowed-tools' then print('[CRAFT_QUEUE_TEST] AUTHORITY consumed=1 outputs=1 toolsReturned=2 tailRead=true')
  elseif session.case=='cancel-craft'or session.case=='late-input'then print('[CRAFT_QUEUE_TEST] ACTIVE_AUTHORITY '..JSON.encode(result))
  else print('[CRAFT_QUEUE_TEST] ABORT_AUTHORITY '..JSON.encode(result)) end
  reply(pending.player,'Verified',result);pending=nil;session=nil;step=step+1
 elseif getTimestampMs()-pending.since>20000 then fail(pending.player,problem);pending=nil end
end)
