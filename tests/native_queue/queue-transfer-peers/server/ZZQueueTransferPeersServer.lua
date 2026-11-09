if not isServer()then return end
local config=require 'QueueTestSelection';if config.suite~='queue-transfer-peers'then return end
local F=require 'QueueTransferPeers'
local players,ready,body,results,closed={},{},{},{},false
local state,index,since,pending,applied,released,partial=nil,1,0,nil,nil,nil,nil
local function now()return getTimestampMs()end
local function both(t)return t.client1 and t.client2 end
local function broadcast(command,row)for _,role in ipairs(F.roles)do if players[role]then sendServerCommand(players[role],F.module,command,row)end end end
local function fail(problem)
 if closed then return end;closed=true;F.emit('FAIL',{case=config.cases[index],error=tostring(problem)})
 broadcast('Failed',{error=tostring(problem)});print('[QUEUE_TEST] FAIL queue-transfer-peers '..tostring(problem))
end
local function seed()
 ready,body,results,pending,applied,released,partial={},{},{},nil,nil,nil,nil;since=now()
 local ids=F.seed(state,config.cases[index],index);F.emit('SEED',ids);broadcast('Seeded',ids)
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module or closed then return end
 local ok,problem=pcall(function()
  local role=player:getUsername();assert(role=='client1'or role=='client2','foreign actor')
  if command=='Hello'then
   assert(not players[role]and not state,'duplicate hello');players[role]=player
   if both(players)then state=F.prepare(players);seed()end;return
  end
  local current=assert(state.seed or released)
  assert(players[role]==player and args.token==current.token and args.case==current.case and args.index==index,'foreign phase/actor')
  if command=='Ready'then
   assert(not ready[role],'duplicate ready');ready[role]=true
   if both(ready)then if current.case=='partial-accepted'then F.partialArm(state)end;F.emit('RELEASE',{case=current.case,token=current.token,index=index});broadcast('Go',{case=current.case,token=current.token,index=index})end
  elseif command=='BodyReady'then
   assert(both(ready)and not body[role],'duplicate/unreleased body boundary');body[role]=true
   if both(body)and current.case=='shared-capacity'then local receipt=F.capacity(state);F.emit('CAPACITY',receipt);broadcast('Capacity',receipt)end
  elseif command=='LostDone'then
   assert(current.case=='lost-done'and role=='client1'and not pending and not applied,'unexpected loss observation')
   pending=now()
  elseif command=='Result'then
   assert(not results[role]and both(ready),'duplicate/unreleased result');results[role]=args.result
  elseif command=='Released'then
   assert(pending=='release'and not ready[role],'duplicate release ack');ready[role]=true
   if both(ready)then
    if index==#config.cases then F.cleanup(state);local row={cases=config.cases,performed=#config.cases,failed=0,restored=true};F.emit('COMPLETE',row);broadcast('Done',row);closed=true
    else index=index+1;seed()end
   end
  else error('unknown command '..tostring(command))end
 end)
 if not ok then fail(problem)end
end)
Events.OnTick.Add(function()
 if closed or not state then return end
 local ok,problem=pcall(function()
  assert(now()-since<180000,'peer phase timeout')
  if type(pending)=='number'then
   local snapshot=F.snapshot(state);local target=state.seed.actors[1].front.id;local moved=false
   for _,item in ipairs(snapshot.items)do if item.id==target then moved=item.endpoint=='source1'end end
   if moved then applied=snapshot;F.emit('APPLIED',snapshot);pending=nil;sendServerCommand(players.client1,F.module,'AbortUnknown',{case=snapshot.case,token=snapshot.token,index=index})
   else assert(now()-pending<20000,'lost Done lacked actual server transfer')end
  end
  if state.seed and state.seed.case=='partial-accepted'and both(ready)and not partial then
   local probe=queuePeersPartialState()
   assert(probe.failure==''and probe.closed=='','partial native probe failed: '..tostring(probe.failure)..':'..tostring(probe.closed))
   if probe.managerRemoved then
    partial=F.snapshot(state);partial.probe=probe
    F.emit('PARTIAL',partial);broadcast('Partial',partial)
   end
  end
  if both(results)and pending~='release'then
   for _,role in ipairs(F.roles)do if state.players[role]:hasTimedActions()or not state.players[role]:getCharacterActions():isEmpty()then return end end
   local snapshot=F.snapshot(state);snapshot.clients=results
   F.emit('RESULT',snapshot);released=snapshot;F.release(state);pending='release';ready={}
   broadcast('Released',{case=snapshot.case,token=snapshot.token,index=index})
  end
 end)
 if not ok then fail(problem)end
end)
