if not isServer() then return end
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
   assert(not state,'radio already prepared')
   state=Fixture.prepare(player,args.case,config.mode,previous);previous=nil
   print('[RADIO_SETTINGS] PREPARED '..JSON.encode(state.ids))
   sendServerCommand(player,module,'Prepared',state.ids)
  else
   assert(command=='Verify' and state and state.player==player and not pending,'unexpected radio request')
   pending=getTimestampMs()
  end
 end)
 if not ok then fail(player,problem) end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,receipt,actual=pcall(Fixture.verify,state,true)
 if ok and receipt then
  print('[RADIO_SETTINGS] VERIFIED '..JSON.encode(receipt))
  sendServerCommand(state.player,'RadioSettingsTest','Verified',receipt)
  previous=state;state,pending=nil,nil;step=step+1
 elseif not ok or getTimestampMs()-pending>15000 then
  fail(state.player,ok and JSON.encode(actual) or receipt)
 end
end)
