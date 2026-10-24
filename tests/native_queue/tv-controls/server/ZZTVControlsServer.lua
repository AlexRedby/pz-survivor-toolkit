if not isServer()then return end
local F=require 'QueueTVControls'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local state,pending;local index=1
local function raw(event,value)print('[TV_CONTROLS] '..event..' '..JSON.encode(value))end
local function fail(player,error)
 pending=nil;print('[QUEUE_TEST] FAIL tv-controls server '..tostring(error))
 sendServerCommand(player,'TVControlsTest','Failed',{error=tostring(error)})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='TVControlsTest'then return end
 local ok,error=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'unexpected TV actor/case order')
  if command=='Prepare'then
   assert(not state and not pending,'duplicate TV prepare')
   state=F.prepare(player,args.case,config.mode);raw('PREPARED',state.ids)
   sendServerCommand(player,module,'Prepared',state.ids)
  else
   assert((command=='Baseline'or command=='Verify')and state and not pending,'unexpected TV authority request')
   pending={command=command,since=getTimestampMs()}
  end
 end)
 if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,receipt,actual=pcall(pending.command=='Baseline'and F.baseline or F.verify,state)
 if ok and receipt then
  local command=pending.command;raw(command=='Baseline'and 'BASELINE'or 'VERIFIED',receipt)
  sendServerCommand(state.player,'TVControlsTest',command=='Baseline'and 'Baselined'or 'Verified',receipt)
  pending=nil
  if command=='Verify'then state=nil;index=index+1 end
 elseif not ok or getTimestampMs()-pending.since>20000 then
  fail(state.player,ok and JSON.encode(actual or F.snapshot(state))or receipt)
 elseif not pending.diagnosed and getTimestampMs()-pending.since>2000 then
  pending.diagnosed=true;raw('AUTHORITY_WAIT',{command=pending.command,actual=actual or F.snapshot(state)})
 end
end)
