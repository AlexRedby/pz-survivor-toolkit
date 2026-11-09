if not isServer()then return end
local F=require 'QueueGroomingCancel';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local P=require 'QueueEnergyPlacement'
local state,previous,index=nil,nil,1
local baseline,checkpoint,pending
local arrival
local function raw(marker,row)print('[GROOMING_TEST] '..marker..' '..JSON.encode(row))end
local function fail(player,problem)
 arrival=nil
 print('[QUEUE_TEST] FAIL grooming-cancel server '..tostring(problem))
 sendServerCommand(player,'GroomingCancelTest','Failed',{error=tostring(problem)})
end
Events.OnServerStarted.Add(function()raw('SERVER_READY',{})end)
Events.OnClientCommand.Add(function(module,name,player,args)
 if module~='GroomingCancelTest'then return end
 local ok,problem=pcall(function()
  assert(type(args)=='table'and player:getUsername()=='client1'and args.case==config.cases[index]and not arrival,'grooming actor/case/order or pending arrival differs')
  if name=='Prepare'then
   assert(not state and not pending,'previous grooming case not settled')
   local target=P.target(args.target);local proof=args.clientPlacement
   assert(type(proof)=='table'and proof.mode=='local'and proof.teleports==1,'grooming owning-client arrival proof missing')
   local observed=P.target(proof.target)
   assert(observed.x==target.x and observed.y==target.y and observed.z==target.z,'grooming client arrival target differs')
   arrival={player=player,case=args.case,target=target,state=P.observe(player,target)}
  elseif name=='Baseline'then
   assert(state and not pending and not baseline,'unexpected grooming baseline request')
   pending={since=getTimestampMs()}
  elseif name=='Checkpoint'then
   assert(state and baseline and not pending and not checkpoint,'unexpected grooming checkpoint')
   assert(F.handsReady(state),'authority held styling input changed before move checkpoint')
   checkpoint=F.snapshot(state);raw('CHECKPOINT',checkpoint);sendServerCommand(player,module,'Checkpointd',checkpoint)
  elseif name=='Verify'then
   assert(state and baseline and checkpoint and not pending,'unexpected grooming verify')
   assert(not player:hasTimedActions()and player:getCharacterActions():isEmpty(),'authority native action queue not idle')
   local final=F.snapshot(state)
   assert(F.restored(state,final)and final.tailPages==state.ids.tailTotal,'authority grooming items/equipment/reader not restored')
   local completed=config.mode=='native'or F.moving(state.ids.case)
   local effectsMatch=F.effectsMatch(state,final,baseline,completed)
   if not effectsMatch then
    local expected={appearance=F.expectedAppearance(state,baseline,completed),gel=false,dye=false}
    if state.gel then expected.gel={id=baseline.gel.id,uses=baseline.gel.uses-(completed and F.stylingCost(state.ids.case).uses or 0)}end
    if state.dye then
     expected.dye={id=baseline.dye.id,amount=completed and math.max(0,baseline.dye.amount-.5)or baseline.dye.amount,color=baseline.dye.color}
    end
    raw('EFFECT_MISMATCH',{case=state.ids.case,mode=config.mode,actionKind=state.ids.actionKind,nativeEffects=completed,
     baseline=baseline,checkpoint=checkpoint,actual=final,expected=expected,
     matches={appearance=F.same(final.appearance,expected.appearance),gel=F.same(final.gel,expected.gel),dye=F.same(final.dye,expected.dye)}})
   end
   assert(effectsMatch,'authority grooming appearance/fluid/gel differs')
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
 if arrival then
  local request=arrival
  local ok,problem=pcall(function()
   local proof=P.poll(request.state);if not proof then return end
   assert(P.at(request.player,request.target),'grooming authority left final placement')
   state=F.prepare(request.player,request.case,previous,request.target,proof);previous=nil;arrival=nil
   raw('PREPARED',state.ids);sendServerCommand(request.player,'GroomingCancelTest','Prepared',state.ids)
  end)
  if not ok then fail(request.player,problem)end
  return
 end
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
