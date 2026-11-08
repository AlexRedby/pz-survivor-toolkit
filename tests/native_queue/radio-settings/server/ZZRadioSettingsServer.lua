if not isServer() then return end
local P=require 'QueueEnergyPlacement'
local Fixture=require 'QueueRadioSettings'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local state,pending,previous;local step=1
local function fail(player,reason)
 pending=nil
 print('[QUEUE_TEST] FAIL radio-settings server '..tostring(reason))
 sendServerCommand(player,'RadioSettingsTest','Failed',{error=tostring(reason)})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='RadioSettingsTest' then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1' and args.case==config.cases[step],'radio actor/case order differs')
  if command=='Prepare' then
   assert(not state and not pending,'radio already prepared')
   local target=P.target(args.placement)
   assert(type(args.clientPlacement)=='table'and args.clientPlacement.mode=='local','radio owning-client placement proof missing')
   pending={command='Prepare',player=player,case=args.case,since=getTimestampMs(),target=target,arrival=P.observe(player,target)}
  else
   assert(command=='Verify' and state and state.player==player and not pending,'unexpected radio request')
   pending={command='Verify',since=getTimestampMs()}
  end
 end)
 if not ok then fail(player,problem) end
end)
Events.OnTick.Add(function()
 if not pending then return end
 if pending.command=='Prepare'then
  local player=pending.player
  local ok,problem=pcall(function()
   local proof=P.poll(pending.arrival);if not proof then return end
   assert(P.at(player,pending.target),'radio replica left settled placement before preparation')
   state=Fixture.prepare(player,pending.case,config.mode,previous,pending.target,proof);previous=nil
   print('[RADIO_SETTINGS] PREPARED '..JSON.encode(state.ids))
   sendServerCommand(player,'RadioSettingsTest','Prepared',state.ids);pending=nil
  end)
  if not ok then fail(player,problem)end
  return
 end
 local ok,receipt,actual=pcall(Fixture.verify,state,true)
 if ok and receipt then
  print('[RADIO_SETTINGS] VERIFIED '..JSON.encode(receipt))
  sendServerCommand(state.player,'RadioSettingsTest','Verified',receipt)
  previous=state;state,pending=nil,nil;step=step+1
 elseif not ok or getTimestampMs()-pending.since>15000 then
  fail(state.player,ok and JSON.encode(actual) or receipt)
 end
end)
