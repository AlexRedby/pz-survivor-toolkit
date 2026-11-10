if not isServer()then return end
local config=require 'QueueTestSelection';if config.suite~='queue-transfer-peers'then return end
local F=require 'QueueTransferPeers';local P=require 'QueueEnergyPlacement'
local players,ready,body,results,closed={},{},{},{},false
local state,index,since,pending,applied,released,partial=nil,1,0,nil,nil,nil,nil
local layout,placing,arrivals,proofs=nil,false,{},{}
local function now()return getTimestampMs()end
local function both(t)return t.client1 and t.client2 end
local function broadcast(command,row)for _,role in ipairs(F.roles)do if players[role]then sendServerCommand(players[role],F.module,command,row)end end end
local function fail(problem)
 if closed then return end;closed=true;F.emit('FAIL',{case=config.cases[index],error=tostring(problem)})
 broadcast('Failed',{error=tostring(problem)});print('[QUEUE_TEST] FAIL queue-transfer-peers '..tostring(problem))
end
local function plan()
 ready,body,results,pending,applied,released,partial={},{},{},nil,nil,nil,nil;since=now()
 layout=F.plan(players,config.cases[index],index,state);placing=true;arrivals,proofs={},{}
 F.emit('LAYOUT',layout);broadcast('Layout',layout)
end
local function seed()
 F.checkPlacement(players,layout,proofs)
 if not state then state=F.prepare(players,layout,proofs)end
 local ids=F.seed(state,config.cases[index],index,layout,proofs)
 placing=false;since=now();F.emit('SEED',ids);broadcast('Seeded',ids)
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module or closed then return end
 local ok,problem=pcall(function()
  local role=player:getUsername();assert(role=='client1'or role=='client2','foreign actor')
  assert(type(args)=='table','peer request arguments missing')
  if command=='Hello'then
   assert(not players[role]and not state and not layout,'duplicate hello');players[role]=player
   if since==0 then since=now()end
   return
  end
  assert(players[role]==player,'foreign phase actor')
  if command=='Placed'then
   assert(placing and layout and args.role==role and args.token==layout.token and args.case==layout.case and args.index==index,'foreign placement phase/actor')
   assert(not arrivals[role],'duplicate client placement')
   local target=P.target(args.target);assert(F.same(target,layout.targets[role]),'peer client target differs')
   F.proof(args.proof,target,'local')
   arrivals[role]={clientProof=args.proof,observation=P.observeCentered(player,target)};return
  end
  assert(state and not placing,'peer work before settled preparation')
  local current=assert(state.seed or released)
  assert(args.token==current.token and args.case==current.case and args.index==index,'foreign phase/actor')
  if command=='Ready'then
   assert(not ready[role],'duplicate ready')
   F.checkPlacement(players,layout,proofs);ready[role]=true
   if both(ready)then
    F.checkPlacement(players,layout,proofs)
    if current.case=='partial-accepted'then F.partialArm(state)end
    F.emit('RELEASE',{case=current.case,token=current.token,index=index});broadcast('Go',{case=current.case,token=current.token,index=index})
   end
  elseif command=='BodyReady'then
   assert(both(ready)and not body[role],'duplicate/unreleased body boundary');body[role]=true
   if both(body)and current.case=='shared-capacity'then local receipt=F.capacity(state);F.emit('CAPACITY',receipt);broadcast('Capacity',receipt)end
  elseif command=='LostDone'then
   assert(current.case=='lost-done'and role=='client1'and not pending and not applied,'unexpected loss observation');pending=now()
  elseif command=='Result'then
   assert(not results[role]and both(ready),'duplicate/unreleased result');results[role]=args.result
  elseif command=='Released'then
   assert(pending=='release'and not ready[role],'duplicate release ack')
   assert(not player:hasTimedActions()and player:getCharacterActions():isEmpty()and F.absent(state,released),'peer release lacked native idle or global absence')
   ready[role]=true;F.emit('AUTHORITY_CLEARED',{case=current.case,token=current.token,index=index,role=role})
   if both(ready)then
    if index==#config.cases then F.cleanup(state);local row={cases=config.cases,performed=#config.cases,failed=0,restored=true};F.emit('COMPLETE',row);broadcast('Done',row);closed=true
    else index=index+1;plan()end
   end
  else error('unknown command '..tostring(command))end
 end)
 if not ok then fail(problem)end
end)
Events.OnTick.Add(function()
 if closed then return end
 local ok,problem=pcall(function()
  if not both(players)then return end
  if not state and not layout then
   if not players.client1:getCurrentSquare()or not players.client2:getCurrentSquare()then assert(now()-since<P.timeoutMs,'peer layout load timeout');return end
   plan()
  end
  if placing then
   assert(now()-since<P.timeoutMs,'peer placement round timeout')
   for _,role in ipairs(F.roles)do
    local request=arrivals[role]
    if request and not proofs[role]then local proof=P.poll(request.observation);if proof then proofs[role]=proof end end
   end
   if both(proofs)then
    F.checkPlacement(players,layout,proofs)
    for _,role in ipairs(F.roles)do F.emit('AUTHORITY_PLACEMENT',{case=layout.case,index=index,token=layout.token,role=role,
     target=layout.targets[role],proof=proofs[role],clientProof=arrivals[role].clientProof})end
    seed()
   end
   return
  end
  if not state then return end
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
   if probe.managerRemoved then partial=F.snapshot(state);partial.probe=probe;F.emit('PARTIAL',partial);broadcast('Partial',partial)end
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
