if not isServer()then return end
local F=require 'QueueGroomingCancel';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local state,previous,index=nil,nil,1
local baseline,checkpoint,pending
local function raw(marker,row)print('[GROOMING_TEST] '..marker..' '..JSON.encode(row))end
local function fail(player,problem)
 print('[QUEUE_TEST] FAIL grooming-cancel server '..tostring(problem))
 sendServerCommand(player,'GroomingCancelTest','Failed',{error=tostring(problem)})
end
Events.OnServerStarted.Add(function()raw('SERVER_READY',{})end)
Events.OnClientCommand.Add(function(module,name,player,args)
 if module~='GroomingCancelTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'grooming actor/case/order differs')
  if name=='Prepare'then
   assert(not state and not pending,'previous grooming case not settled')
   state=F.prepare(player,args.case,previous);previous=nil;raw('PREPARED',state.ids)
   sendServerCommand(player,module,'Prepared',state.ids)
  elseif name=='Baseline'then
   assert(state and not pending and not baseline,'unexpected grooming baseline request')
   pending={since=getTimestampMs()}
  elseif name=='Checkpoint'then
   assert(state and baseline and not pending and not checkpoint,'unexpected grooming checkpoint')
   checkpoint=F.snapshot(state);raw('CHECKPOINT',checkpoint);sendServerCommand(player,module,'Checkpointd',checkpoint)
  elseif name=='Verify'then
   assert(state and baseline and checkpoint and not pending,'unexpected grooming verify')
   assert(not player:hasTimedActions()and player:getCharacterActions():isEmpty(),'authority native action queue not idle')
   local final=F.snapshot(state)
   assert(F.restored(state,final)and final.tailPages==state.ids.tailTotal,'authority grooming items/equipment/reader not restored')
   assert(F.effectsMatch(state,final,baseline,config.mode=='native'),'authority grooming appearance/fluid/gel differs')
   local receipt={baseline=baseline,checkpoint=checkpoint,final=final,bodyCompletes=false,bodyRecords={},
    completeCountProof='unavailable-remote-callback',
    completeCountLimit='NetTimedAction.perform directly invokes complete; server callback invocation count unavailable without replacement'}
   raw('VERIFIED',receipt);sendServerCommand(player,module,'Verified',receipt)
   previous=state.ids;state,baseline,checkpoint=nil,nil,nil;index=index+1
  else error('unknown grooming command')end
 end)
 if not ok then fail(player,problem)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-pending.since<30000,'grooming authority baseline timed out')
  if not F.refresh(state)then return end
  local actual=F.snapshot(state)
  if not F.sameSetup(actual,state.ids.baseline)then return end
  if not pending.snapshot or not F.same(actual,pending.snapshot)then pending.snapshot=actual;pending.quiet=getTimestampMs();return end
  if getTimestampMs()-pending.quiet<500 then return end
  baseline=actual;raw('BASELINED',baseline);sendServerCommand(state.player,'GroomingCancelTest','Baselined',baseline);pending=nil
 end)
 if not ok then pending=nil;fail(state.player,problem)end
end)
