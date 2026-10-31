local selection=require 'QueueTestSelection'
if selection.kind~='mp'or selection.cases[1]~='peer-edits'or not isServer()then return end
local F=require 'WarehouseWorkloadFixture'
local players,ready,seen={},{},{}
local state,step,pending,since,closed,aborting
local function now()return getTimestampMs()end
local function both(t)return t.client1 and t.client2 end
local function broadcast(command,row)for _,role in ipairs({'client1','client2'})do sendServerCommand(players[role],F.module,command,row)end end
local function context(extra)
 local p=state and state.phase;local row=extra or {}
 row.token=state and state.token or'unprepared';row.index=p and p.index or state and state.nextIndex or 0
 row.phaseToken=p and p.phaseToken;row.paneMode=p and p.mode;return row
end
local function readiness(role,request)
 local player=players[role];local square=player:getSquare();local origin=state.ids.actorOrigin;local confirmedAt=now()
 local row={requestedAt=request.requestedAt,confirmedAt=confirmedAt,waitMs=confirmedAt-request.requestedAt,deadlineMs=15000,
  onlineId=player:getOnlineID(),x=player:getX(),y=player:getY(),z=player:getZ(),
  squareX=square and square:getX(),squareY=square and square:getY(),squareZ=square and square:getZ()}
 local matches=square and square:getZ()==origin.z and math.abs(row.x-origin.x-.5)<=1 and math.abs(row.y-origin.y-.5)<=1
 return row,matches
end
local function fail(problem,command,reply)
 if closed then return end;closed=true
 local row=context({error=tostring(problem),command=command,step=step})
 if state and not state.phase then
  row.readiness={};for role,request in pairs(ready)do row.readiness[role]=readiness(role,request)end
 end
 local restored,cleanup=false,'native abort readiness incomplete; refusing cleanup while peer actions may run'
 if not aborting or both(aborting.ready)then restored,cleanup=pcall(F.abort,state or F.preparing)end
 row.restored=restored;if restored then row.cleanup=cleanup else row.cleanupError=tostring(cleanup)end
 F.emit('FAIL',row)
 for _,player in pairs(players)do sendServerCommand(player,F.module,reply or'Failed',row)end
 print('[QUEUE_TEST] FAIL warehouse-workload server '..tostring(problem))
end
local function go(index)
 step=F.steps[index];seen={};pending=nil;since=now()
 if step=='initial'then return end
 local actor=step=='hidden-loot'and'client1'or'client2'
 broadcast('Go',context({step=step,actor=actor,phase=state.phase}))
 F.emit('GO',context({step=step,actor=actor}))
end
local function seedWhenReady()
 if not state or state.phase then return end
 local proof,matched={},true
 for _,role in ipairs({'client1','client2'})do
  local request=ready[role]
  if request then
   local row,matches=readiness(role,request);proof[role]=row
   assert(row.waitMs<row.deadlineMs,'workload server position convergence timeout: '..role)
   if not matches then matched=false end
  else matched=false end
 end
 if not matched then return end
 local phase=F.seed(state,state.nextIndex);ready={};step='initial';seen={};since=now()
 local receipt=assert(F.native(state,'initial'));F.emit('SEED',context({phase=phase,snapshot=receipt,readiness=proof}))
 broadcast('Seeded',context({phase=phase,readiness=proof}))
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module then return end
 local ok,problem=pcall(function()
  assert(not closed,'closed workload session')
  assert(type(args)=='table'and args.case=='peer-edits','invalid workload case')
  local role=player:getUsername();assert(role=='client1'or role=='client2','unexpected workload actor')
  if command=='Prepare'then
   assert(not players[role]and not state,'duplicate workload preparation');players[role]=player;since=since or now()
   if both(players)then
    state=F.prepare(players);F.emit('SETUP',context({ids=state.ids,onlineIds={client1=players.client1:getOnlineID(),client2=players.client2:getOnlineID()}}))
    for _,name in ipairs({'client1','client2'})do sendServerCommand(players[name],F.module,'Prepared',{ids=state.ids,role=name,token=state.token})end
   end;return
  end
  assert(state and players[role]==player and args.token==state.token,'wrong workload session/actor')
  if command=='Abort'then
   if aborting then
    assert(not aborting.requests[role],'duplicate workload abort request')
    aborting.requests[role]=true;return
   end
   aborting={since=now(),ready={},requests={[role]=true},error=args.error or'client workload aborted'}
   pending=nil;broadcast('AbortRequested',{token=state.token,error=aborting.error});return
  elseif command=='AbortReady'then
   assert(aborting and not aborting.ready[role],'duplicate/unrequested workload abort readiness')
   aborting.ready[role]=true
   if both(aborting.ready)then fail(aborting.error,'Abort','Abortd')end;return
  end
  if aborting then
   -- An action/observation sent before AbortRequested can still be in flight.
   -- Drain these notifications without dispatching or validating new effects.
   assert(command=='Acted'or command=='Seen'or command=='Ready','unknown workload command during abort drain');return
  end
  if command=='Ready'then
   assert(not state.phase and args.index==state.nextIndex and F.modes[args.index]and not ready[role],'out-of-order workload readiness')
   ready[role]={requestedAt=now()};seedWhenReady();return
  end
  local p=assert(state.phase,'workload phase absent')
  assert(args.index==p.index and args.phaseToken==p.phaseToken and args.step==step,'wrong workload phase/step')
  if command=='Acted'then
   assert(step~='initial'and not pending and not p.authorityStep,'duplicate/out-of-order workload action receipt')
   assert(role==(step=='hidden-loot'and'client1'or'client2'),'wrong workload action role')
   pending=now()
  elseif command=='Seen'then
   assert(not seen[role]and not pending and(step=='initial'or p.authorityStep==step),'duplicate/premature workload observer receipt')
   seen[role]=true;F.emit('SEEN',context({step=step,observer=role}))
   if both(seen)then
    assert(F.native(state,step),'authoritative workload changed after observation')
    if step=='hidden-loot'then
     local receipt=F.release(state,p.index);F.emit('RELEASE',receipt);broadcast('Released',receipt);step=nil;since=now()
     if state.nextIndex==3 then
      local cleanup=F.cleanup(state);F.emit('RESTORED',cleanup);F.emit('COMPLETE',{token=state.token,index=2,phases=2,restored=true})
      broadcast('Done',cleanup);closed=true
     end
    else
     local index;for i,name in ipairs(F.steps)do if name==step then index=i end end
     p.authorityStep=nil;go(assert(index)+1)
    end
   end
  else error('unknown workload command '..tostring(command))end
 end)
 if not ok then fail(problem,command)end
end)
Events.OnTick.Add(function()
 if closed or not since then return end
 local ok,problem=pcall(function()
  assert(now()-since<90000,'warehouse workload protocol timeout')
  if aborting then assert(now()-aborting.since<45000,'warehouse workload abort drain timeout');return end
  seedWhenReady()
  if pending then
   assert(now()-pending<30000,'warehouse native action never converged')
   local receipt=F.native(state,step)
   if receipt then
    local p=state.phase;p.state=step;p.authorityStep=step;pending=nil;since=now()
    F.emit('AUTHORITY',context({step=step,snapshot=receipt,phase=p}))
    broadcast('Observed',context({step=step,receipt=receipt,phase=p}))
   end
  end
 end)
 if not ok then fail(problem,'tick')end
end)
