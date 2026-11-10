if not isServer() then return end
local Authority=require 'QueueFireAuthority'
local P=require 'QueueEnergyPlacement';local selection=require 'QueueTestSelection'
local waiting,pending,active
local function reply(player,command,value) sendServerCommand(player,'FireQueueTest',command,value) end
local function failed(player,problem)
 waiting,pending=nil,nil
 reply(player,'Failed',{ok=false,error=tostring(problem)});print('[QUEUE_TEST] FAIL fire server '..tostring(problem))
end
local function selected(case)
 for _,known in ipairs(selection.cases)do if case==known then return true end end
 return false
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='FireQueueTest' then return end
 local ok,problem=pcall(function()
  assert(type(args)=='table'and player:getUsername()=='client1'and selected(args.case),'unexpected fire actor/case')
  assert(type(args.trial)=='number'and args.trial%1==0 and args.trial>0,'fire request trial missing')
  if command=='Prepare' then
   assert(not waiting and not pending and not active,'duplicate fire request')
   local target=P.target(args.target);local proof=args.clientPlacement
   assert(type(proof)=='table'and proof.mode=='local'and proof.centered==true and proof.teleports==1 and proof.centers==1,'fire owning-client centered proof missing')
   local observed=P.target(proof.target)
   assert(observed.x==target.x and observed.y==target.y and observed.z==target.z,'fire client arrival target differs')
   waiting={player=player,case=args.case,trial=args.trial,target=target,arrival=P.observeCentered(player,target)}
  else
   assert(not waiting and not pending and active and active.player==player and active.case==args.case and active.trial==args.trial,'fire request lacks exact prepared trial')
   if command=='Invalidate'then reply(player,'Invalidated',Authority.invalidate(player,args.case))
   else assert(command=='Verify','unexpected fire request');pending={player=player,case=args.case,tidyReturnIds=args.tidyReturnIds,since=getTimestampMs()}end
  end
 end)
 if not ok then failed(player,problem) end
end)
Events.OnTick.Add(function()
 if waiting then
  local request=waiting
  local ok,problem=pcall(function()
   local proof=P.poll(request.arrival);if not proof then return end
   assert(P.atCentered(request.player,request.target),'fire authority left centered placement')
   local ids=Authority.prepare(request.player,request.case,request.target,proof,request.trial)
   assert(ids.case==request.case and ids.trial==request.trial,'fire prepared trial differs')
   active={player=request.player,case=request.case,trial=request.trial};waiting=nil;reply(request.player,'Prepared',ids)
  end)
  if not ok then failed(request.player,problem) end
  return
 end
 if not pending then return end
 local ok,result,problem=pcall(Authority.verify,pending.player,pending.case,pending.tidyReturnIds)
 if not ok then failed(pending.player,result);pending=nil
 elseif result then reply(pending.player,'Verified',result);pending,active=nil,nil
 elseif getTimestampMs()-pending.since>20000 then failed(pending.player,problem);pending=nil end
end)
