local selection=require 'QueueTestSelection'
if selection.kind~='mp'or selection.cases[1]~='walk'or not isServer()then return end
local F=require 'WarehouseWalkingFixture'
local players,ready,seen,ended={},{},{},{}
local state,since,closed,aborting,before,barrier
local roles={'client1','client2'}
local function now()return getTimestampMs()end
local function both(t)return t.client1 and t.client2 end
local function broadcast(command,row)for _,player in pairs(players)do sendServerCommand(player,F.module,command,row)end end
local function drained(t)for role in pairs(players)do if not t[role]then return false end end;return true end
local function emit(event,row)
 row=F.context(state,row);if aborting then row.token=aborting.token end;F.emit(event,row)
end
local function beginAbort(problem)
 if aborting then return end
 aborting={since=now(),ready={},requests={},results={},stage='drain',error=tostring(problem),
  token=state and state.token or F.preparing and F.preparing.token or 'warehouse-walking-abort:'..now()};barrier='abort'
 local row=F.context(state,{error=aborting.error});row.token=aborting.token;broadcast('AbortRequested',row)
end
local function failClosed(problem)
 closed=true;local row=F.context(state,{error=tostring(problem),restored=false})
 emit('FAIL',row);broadcast('Failed',row);print('[QUEUE_TEST] FAIL warehouse-walking server '..tostring(problem))
end
local function finishAbort()
 assert(aborting and aborting.stage=='drain'and drained(aborting.ready),'abort cleanup before native drains')
 local ok,result=pcall(F.abort,state or F.preparing)
 local row=F.context(state,{error=aborting.error,restored=ok,cleanup=ok and result or nil,cleanupError=not ok and tostring(result)or nil})
 emit('ABORT',row)
 if not ok then failClosed('owned cleanup failed: '..tostring(result));return end
 aborting.cleanup=result;aborting.stage='restore';aborting.since=now();broadcast('Abortd',row)
end
local function finishClientRestoration()
 assert(aborting.stage=='restore'and drained(aborting.results),'terminal failure before all client restoration results')
 local restored=true;local clients={}
 for role,result in pairs(aborting.results)do clients[role]=result.restored;if not result.restored then restored=false end end
 local row=F.context(state,{error=aborting.error,restored=restored,cleanup=aborting.cleanup,clientsRestored=clients})
 closed=true;emit('FAIL',row);broadcast('Failed',row);print('[QUEUE_TEST] FAIL warehouse-walking server '..aborting.error)
end
local function readiness()
 local proof={};local matched=true
 for _,role in ipairs(roles)do local request=ready[role];local player=players[role]
  if not request then matched=false else
   local square=player:getSquare();local point=state.ids.actorOrigins[role]
   local confirmedAt=now()
   local row={requestedAt=request,confirmedAt=confirmedAt,waitMs=confirmedAt-request,deadlineMs=15000,onlineId=player:getOnlineID(),
    x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square and square:getX(),squareY=square and square:getY(),squareZ=square and square:getZ()}
   proof[role]=row;assert(row.waitMs<15000,'walking server position convergence timeout: '..role)
   if not square or square:getX()~=point.x or square:getY()~=point.y or square:getZ()~=point.z
    or math.abs(row.x-point.x-.5)>.1 or math.abs(row.y-point.y-.5)>.1 then matched=false end
  end
 end;return matched,proof
end
local function seedWhenReady()
 if not state or state.phase or aborting then return end
 local matched,proof=readiness();if not matched then return end
 local phase=F.seed(state,state.nextIndex);before=assert(F.snapshot(state));ready={};seen={};ended={};barrier='before';since=now()
 emit('SEED',{phase=phase,snapshot=before,readiness=proof});emit('ADMIT',{stage='before',snapshot=before,readiness=proof})
 broadcast('Seeded',F.context(state,{phase=phase,authority=before,readiness=proof}))
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module or closed then return end
 local ok,problem=pcall(function()
  assert(type(args)=='table'and args.case=='walk','invalid walking case')
  local role=player:getUsername();assert(role=='client1'or role=='client2','unexpected walking role')
  if command=='Prepare'then
   assert(not state and not players[role],'duplicate walking preparation');players[role]=player;since=since or now()
   if both(players)then
    F.preparing=nil;state=F.prepare(players);emit('SETUP',{ids=state.ids,onlineIds={client1=players.client1:getOnlineID(),client2=players.client2:getOnlineID()}})
    for _,name in ipairs(roles)do sendServerCommand(players[name],F.module,'Prepared',{ids=state.ids,role=name,token=state.token})end
   end;return
  end
  assert(players[role]==player and args.token==(aborting and aborting.token or state and state.token or nil),'wrong walking actor/token')
  if command=='Abort'then
   beginAbort(args.error or'client aborted');assert(not aborting.requests[role],'duplicate walking abort request');aborting.requests[role]=true;return
  elseif command=='AbortReady'then
   assert(aborting and aborting.stage=='drain'and not aborting.ready[role],'duplicate/unrequested walking abort drain');aborting.ready[role]=true
   if drained(aborting.ready)then finishAbort()end;return
  elseif command=='AbortRestored'then
   assert(aborting and aborting.stage=='restore'and not aborting.results[role]and type(args.restored)=='boolean','duplicate/unrequested client restoration acknowledgement')
   aborting.results[role]={restored=args.restored,error=args.error};emit('ABORT_SEEN',{observer=role,restored=args.restored})
   if drained(aborting.results)then finishClientRestoration()end;return
  end
  assert(state,'walking session absent')
  if aborting then assert(command=='Ready'or command=='Seen'or command=='Ended','unexpected abort-drain command');return end
  if command=='Ready'then
   assert(not state.phase and args.index==state.nextIndex and F.phases[args.index]and not ready[role],'out-of-order walking readiness')
   ready[role]=now();seedWhenReady();return
  end
  local p=assert(state.phase);assert(args.index==p.index and args.phaseToken==p.phaseToken,'wrong walking phase')
  if command=='Seen'then
   assert(args.stage==barrier and(barrier=='before'or barrier=='after')and not seen[role],'stale/replayed walking Seen')
   seen[role]=true;emit('SEEN',{observer=role,stage=barrier})
   if both(seen)then
    assert(F.snapshot(state),'authoritative walking identities changed')
    if barrier=='before'then barrier='measure';seen={};since=now();emit('GO');broadcast('Go',F.context(state,{}))
    else
     local receipt=F.release(state,p.index);F.emit('RELEASE',receipt);broadcast('Released',receipt);barrier=nil;since=now()
     if state.nextIndex==17 then
      local cleanup=F.cleanup(state);F.emit('RESTORED',cleanup);F.emit('COMPLETE',{role='server',token=state.token,index=16,phases=16,restored=true});broadcast('Done',cleanup);closed=true
     end
    end
   end
  elseif command=='Ended'then
   assert(barrier=='measure'and not ended[role],'stale/replayed walking Ended');ended[role]=true
   if both(ended)then
    local after=assert(F.snapshot(state),'authoritative walking cohort changed');emit('AUTHORITY',{before=before,after=after})
    seen={};barrier='after';since=now();broadcast('Observed',F.context(state,{authority=after}))
   end
  else error('unknown walking command '..tostring(command))end
 end)
 if not ok then
  if aborting then failClosed(problem)else emit('ERROR',{error=tostring(problem),command=command});beginAbort(problem)end
 end
end)
Events.OnTick.Add(function()
 if closed or not since then return end
 local ok,problem=pcall(function()
  if aborting then assert(now()-aborting.since<45000,'walking abort '..aborting.stage..' timeout');return end
  assert(now()-since<90000,'walking server protocol timeout');seedWhenReady()
 end)
 if not ok then if aborting then failClosed(problem)else emit('ERROR',{error=tostring(problem)});beginAbort(problem)end end
end)
