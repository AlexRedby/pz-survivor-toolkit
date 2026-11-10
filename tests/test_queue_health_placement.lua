-- Behavioral tests of the shipped health authority/coordinator and shared placement state machine.
local health=ProjectRoot and(ProjectRoot..'/tests/native_queue/health')or assert(arg[1])
local original=arg;arg={health,'placement-fixture'}
local fixture=assert(loadfile(health..'/check.lua'))();arg=original
local P=fixture.placement
local function copy(value)
 if type(value)~='table'then return value end
 local result={};for key,item in pairs(value)do result[key]=copy(item)end;return result
end
local function rejects(fn,reason)assert(not pcall(fn),reason)end
local now=0
getTimestampMs=function()return now end
sendAddItemToContainer=function()end;sendRemoveItemFromContainer=function()end
sendServerCommand=function()end;syncBodyPart=function()end
local server=true
isServer=function()return server end
local function world(kind,ids)
 fixture.select(kind,'toolkit',ids or {'bandageApply'})
 local players={fixture.player('client1')}
 if kind=='mp'then players[2]=fixture.player('client2')end
 getOnlinePlayers=function()return fixture.values(players)end
 local raw=fixture.source('shared','QueueHealthAuthority')
 return raw,players
end
local function localProof(actor,target)
 local previous=server;server=false
 local pending=P.beginCentered(actor,target)
 local proof
 for i=1,8 do now=now+500;proof=P.poll(pending);if proof then break end end
 server=previous;return assert(proof,'real local placement never settled')
end
local function prove(authority,layout)
 local proofs={}
 for actor,target in pairs(layout.targets)do
  local player=authority.actor(actor);local proof=localProof(player,target)
  if server then
   local observation=P.observeCentered(player,target)
   for i=1,4 do now=now+500;proof=P.poll(observation);if proof then break end end
  end
  proofs[actor]=assert(proof)
 end
 return proofs
end
local function count(map)local result=0;for _ in pairs(map)do result=result+1 end;return result end
local function setup(authority,players)
 local layout=authority.setupLayout(players);local proofs=prove(authority,layout)
 for _,actor in ipairs(players)do authority.setup(actor,layout,proofs)end
 return layout,proofs
end

-- Valid local proofs are produced by quiet/arrival sampling, never synthesized booleans.
do
 local authority,players=world('mp')
 local layout=authority.setupLayout(players)
 local untouched=players[1].inventory:AddItem('Base.Hammer')
 rejects(function()authority.setup(players[1],layout,{})end,'missing arrival allowed setup inventory')
 assert(#players[1].inventory.items==1 and players[1].inventory.items[1]==untouched,'unsettled setup changed inventory')
 local proofs=prove(authority,layout)
 rejects(function()authority.setup(players[1],copy(layout),proofs)end,'unreserved copied layout accepted')
 for _,fault in ipairs({'missing','mode','centered','stable','actor-target','wrong-phase','wrong-doctor','foreign-participant'})do
  local badLayout,badProofs=layout,copy(proofs)
  if fault=='missing'then badProofs.client2=nil
  elseif fault=='mode'then badProofs.client2.mode='local'
  elseif fault=='centered'then badProofs.client2.centered=false
  elseif fault=='stable'then badProofs.client2.stableMs=0
  elseif fault=='actor-target'then badProofs.client2.target=copy(layout.targets.client1)
  elseif fault=='wrong-phase'then badLayout.phase='bandageApply'
  elseif fault=='wrong-doctor'then badLayout.doctor='client1'
  elseif fault=='foreign-participant'then badLayout.targets.intruder=copy(layout.targets.client1)end
  rejects(function()authority.setup(players[1],badLayout,badProofs)end,'invalid '..fault..' proof allowed setup')
  assert(#players[1].inventory.items==1,'invalid proof changed setup inventory')
  layout.phase='setup';layout.doctor='setup';layout.targets.intruder=nil
 end
 players[2].x=players[2].x+.3
 rejects(function()authority.setup(players[1],layout,proofs)end,'historical proof accepted fresh setup drift')
 assert(#players[1].inventory.items==1,'drift changed setup inventory')
 players[2].x=layout.targets.client2.x+.5
 for _,actor in ipairs(players)do authority.setup(actor,layout,proofs)end
 assert(authority.setup(players[1],layout,proofs)==authority.ids(players[1]),'idempotent completed setup replaced inventory identity')
end
print('PASS actual centered local placement proofs gate setup and reject missing, malformed, mismatched and stale admission')

-- A remote clinical case must settle every actor before cleanup, health reset, or supply seeding.
do
 local authority,players=world('mp',{'bandageApply','inventoryBandage'})
 setup(authority,players)
 local doctor,patient=players[1],players[2]
 patient.body:setStitched(true)
 local sentinel=doctor.inventory:AddItem('Base.Hammer')
 local before=#doctor.inventory.items
 local layout=authority.prepareLayout(doctor,'bandageApply')
 assert(count(layout.targets)==2 and layout.targets.client2.x==layout.targets.client1.x+1,'remote case lost adjacent two-actor layout')
 rejects(function()authority.prepare(doctor,'bandageApply',layout,{})end,'unsettled remote case accepted')
 assert(#doctor.inventory.items==before and sentinel.owner==doctor.inventory and patient.body.stitch,'unsettled prepare cleaned or seeded clinical fixture')
 local proofs=prove(authority,layout)
 patient.x=patient.x+.3
 rejects(function()authority.prepare(doctor,'bandageApply',layout,proofs)end,'fresh remote drift seeded injury')
 assert(patient.body.stitch and #doctor.inventory.items==before,'fresh drift changed body or supply before admission')
 patient.x=layout.targets.client2.x+.5
 local prep=authority.prepare(doctor,'bandageApply',layout,proofs)
 assert(prep.patient=='client2' and patient.body.scratchFlag and not patient.body.stitch,'settled remote prepare lost real clinical seed')
 rejects(function()authority.prepare(doctor,'bandageApply',layout,proofs)end,'duplicate prepare accepted')
 rejects(function()authority.checkPlacement(layout,{client1=proofs.client1})end,'missing patient proof accepted admission')
 patient.x=patient.x+.3
 rejects(function()authority.checkPlacement(layout,proofs)end,'fresh drift accepted baseline admission')
end
print('PASS all remote participants settle before clinical reset, cleanup, supplies and fresh admission')

-- Prior case supplies must remain until the complete next layout is settled.
do
 local authority,players=world('mp',{'waitingCancel','bandageApply'})
 setup(authority,players)
 local doctor,patient=players[1],players[2]
 local previous=authority.prepareLayout(doctor,'waitingCancel')
 local prep=authority.prepare(doctor,'waitingCancel',previous,prove(authority,previous))
 authority.baseline(doctor,'waitingCancel')
 local retained
 for _,item in ipairs(doctor.inventory.items)do
  if item.id==prep.items.bandage then retained=item
  elseif item.id==prep.front or item.id==prep.tail then item.pages=100 end
 end
 assert(retained and authority.verify(doctor,'waitingCancel').ok,'cancelled fixture did not retain supply')
 patient.body.stitch=true
 local layout=authority.prepareLayout(doctor,'bandageApply')
 local proofs=prove(authority,layout);local missing=copy(proofs);missing.client2=nil
 rejects(function()authority.prepare(doctor,'bandageApply',layout,missing)end,'next case accepted incomplete arrival')
 assert(retained.owner==doctor.inventory and patient.body.stitch,'pending next case cleaned prior supply or reset patient')
 authority.prepare(doctor,'bandageApply',layout,proofs)
 assert(not retained.owner and not patient.body.stitch and patient.body.scratchFlag,'settled next case failed exact old fixture cleanup and clinical reset')
end
print('PASS pending next-case placement preserves previous fixture supply and clinical state until every proof arrives')

-- Inventory care uses the acting player's placement despite MP's alternating peer roles.
do
 local authority,players=world('mp',{'inventoryBandage'})
 setup(authority,players)
 for _,doctor in ipairs(players)do
  local peer=doctor==players[1]and players[2]or players[1]
  local layout=authority.prepareLayout(doctor,'inventoryBandage')
  assert(count(layout.targets)==1 and layout.targets[doctor.name] and not layout.targets[peer.name],'self inventory waited on peer placement')
  local prep=authority.prepare(doctor,'inventoryBandage',layout,prove(authority,layout))
  assert(prep.patient==doctor.name and doctor.body.scratchFlag and not peer.body.scratchFlag,'inventory role swap injured session peer')
  authority.baseline(doctor,'inventoryBandage')
  for i=#doctor.inventory.items,1,-1 do local item=doctor.inventory.items[i]
   if item.id==prep.items.bandage then doctor.inventory:Remove(item)
   elseif item.id==prep.front or item.id==prep.tail then item.pages=100 end
  end
  doctor.body.covered=true
  assert(authority.verify(doctor,'inventoryBandage').ok)
  -- The completed clinical state is independent from the next doctor's self patient.
  doctor.body.scratchFlag=false
  authority.finish(doctor)
 end
end
print('PASS self inventory uses one settled actor across both MP doctor roles')

-- The actual fixture accepts only its exact owned container approach, transfer and medicine chain.
local function inventoryBagScenario(mode,fault)
 server=false
 fixture.select('sp',mode,{'inventoryBag'})
 local actor=fixture.player('client1');actor:teleportTo(10.5,10.5,0)
 function actor:getPlayerNum()return 0 end
 function actor:pressedMovement()return false end;function actor:tooDarkToRead()return false end
 function actor:isTimedActionInstant()return false end
 function actor:getSecondaryHandItem()return self.secondary end
 local front=actor.inventory:AddItem('Base.BookCarpentry1');local tail=actor.inventory:AddItem('Base.BookFirstAid1')
 local bag=actor.inventory:AddItem('Base.Bag_Schoolbag');local selected=bag.inner:AddItem('Base.Bandage')
 local q={queue={}};function q:indexOf(action)for index,value in ipairs(self.queue)do if value==action then return index end end end
 local route,transfer,clinical,observer,visible,clock=nil,nil,nil,nil,false,0
 local token={}
 getPlayer=function()return actor end;getTimestampMs=function()return clock end
 ISReadABook={getDuration=function()end}
 ISInventoryPaneContextMenu={
  onLiteratureItems=function(items)q.queue[#q.queue+1]={Type='ISReadABook',item=items[1],getDuration=ISReadABook.getDuration,minutesPerPage=2.0}end,
  applyBandage=function(item,body,index)
   assert(item==selected and body==actor.body and index==0,'fixture changed native producer input identities')
   local source=item:getContainer()
   if fault=='wrong-fixture-bag'then
    local other=actor.inventory:AddItem('Base.Bag_Schoolbag');source:Remove(item);other.inner:AddItem(item);source=other.inner
   end
   route={Type='ISQueueActionsAction',character=actor,container=source,toolkitQueueOperation=token,trusted=true}
   transfer={Type='ISInventoryTransferAction',character=actor,item=item,srcContainer=source,destContainer=actor.inventory,toolkitQueueOperation=token}
   clinical={Type='ISApplyBandage',character=actor,otherPlayer=actor,item=item,bodyPart=body,doIt=true,toolkitQueueOperation=token}
   if fault=='wrong-route-source'then route.container=actor.inventory
   elseif fault=='wrong-token'then transfer.toolkitQueueOperation={}
   elseif fault=='wrong-actor'then transfer.character={}
   elseif fault=='wrong-body'then clinical.bodyPart={}
   elseif fault=='foreign-wrapper'then route.trusted=false end
   if mode=='toolkit'then q.queue[#q.queue+1]=route end
   q.queue[#q.queue+1]=transfer;q.queue[#q.queue+1]=clinical
   if fault=='extra-command'then q.queue[#q.queue+1]={Type='ISQueueActionsAction',character=actor,toolkitQueueOperation=token}end
  end}
 local authority={clinicalReady=function()return true end,setBagHand=function(character,actual,hand)
  assert(character==actor and actual==bag,'bag visibility changed unrelated fixture')
  actor.secondary=hand;visible=hand==bag
 end}
 PZSurvivorToolkit={Settings={actionQueue=function()return mode=='toolkit'end},
  ActionQueue={},ActionQueueOperations={run=function(fn,...)return fn(...)end},
  ActionQueueApproach={isContainer=function(action,container,character)
   return action==route and action.trusted and action.container==container and action.character==character
  end},
  ActionQueuePolicy={setDiagnostics=function()end,inspect=function(action)
   if action==route then return {positions={[actor]=true},deferred=true,preparation=true},'toolkit.approach' end
   if action==clinical then return {targets={[actor.body]=true}},'toolkit.health' end
   return {},'native.transfer'
  end},
  ActionQueueDefinitions={describe=function(action)assert(action==clinical,'fixture described preparation instead of exact medicine');return {title='bandage',target='body'}end}}
 Events={OnPlayerUpdate={Add=function(callback)observer=callback end,Remove=function(callback)assert(callback==observer);observer=nil end}}
 ISHealthPanel={new=function(_,patient)assert(patient==actor);return {character=actor,initialise=function()end}end}
 Translator={getLanguage=function()return {name=function()return 'EN'end}end}
 BodyPartType.FromIndex=function(value)return value end
 local fallback=fixture.require
 require=function(name)
  if name=='QueueHealthAuthority'then return authority end
  if name=='XpSystem/ISUI/ISHealthPanel'or name=='TimedActions/ISReadABook'or name=='QueueScenarioChecks'then return {} end
  return fallback(name)
 end
 local prep={ok=true,patient=actor.name,body=0,items={bandage=selected.id},front=front.id,frontPages=1,tail=tail.id,bag=bag.id,readiness={},
  placement={phase='inventoryBag',doctor=actor.name,targets={[actor.name]={x=10,y=10,z=0}}}}
 local prepared,baselines,stages={},{},{}
 fixture.source('client','QueueHealthScenarios')(function(_,fn)stages[#stages+1]=fn end,function()return q end,function()return #q.queue==0 end,
  {kind='sp',language='EN',ids=function()return {username=actor.name}end,preparations=prepared,baselines=baselines,
   send=function(command,args)
    if command=='Prepare'then prepared[args.phase]=prep
    elseif command=='Baseline'then baselines[args.phase]={ok=true}
    else error('unexpected inventory preparation command '..command)end
   end})
 stages[1]();local run=stages[2]
 local ok,problem=pcall(function()
  assert(run()==false and run()==false);clock=500;assert(run()==false);clock=501;assert(run()==false)
 end)
 if fault then assert(not ok,'fixture accepted malformed inventory approach chain '..fault)
 else
  assert(ok,problem)
  assert(visible and observer and q.queue[1].item==front and q.queue[#q.queue].item==tail,'exact medicine chain lost independent readers or visible carried bag')
  observer(actor);assert(visible,'unstarted transfer hid carried bag')
  transfer.action={isStarted=function()return true end,finished=function()return false end}
  observer(actor);assert(not visible and selected:getContainer()==bag.inner,'started native transfer failed to hide UI without moving selected item')
  assert(run()==false,'valid approach preparation observer rejected absence of body target')
  stages[3]();assert(not observer,'fixture teardown retained preparation observer')
 end
 require=fallback
 getTimestampMs=function()return now end
end
for _,mode in ipairs({'native','toolkit'})do inventoryBagScenario(mode)end
for _,fault in ipairs({'wrong-fixture-bag','wrong-route-source','wrong-token','wrong-actor','wrong-body','foreign-wrapper','extra-command'})do
 inventoryBagScenario('toolkit',fault)
end
print('PASS actual inventory-bag scenario admits exact container approach/transfer/clinical identities and observer; foreign wrappers, bags, tokens, actors, bodies and extra commands reject')

-- Coordinator/client asynchronous arrival, exact command ownership, replica delay and timeout.
local Coordinator
require=function(name)if name=='QueueEnergyPlacement'then return P end;return fixture.require(name)end
Coordinator=fixture.source('shared','QueueHealthPlacement')
local function harness(kind,username)
 server=kind=='mp'
 local authority,players=world(kind)
 if username~=nil then players[1].name=username end
 if kind=='sp'then getPlayer=function()return players[1]end end
 local messages,sent,clients={},{},{}
 local coordinator=Coordinator.newAuthority(authority,function(actor,command,args)
  messages[#messages+1]={actor=actor,command=command,args=args}
  if command=='Placement'then
   local previous=server;server=false;getPlayer=function()return actor end
   clients[actor.name]:receive(args);server=previous
  end
 end)
 for _,actor in ipairs(players)do
  clients[actor.name]=Coordinator.newClient(function(command,args)sent[#sent+1]={actor=actor,command=command,args=args}end)
 end
 local function tickClient(actor)
  server=false;getPlayer=function()return actor end;clients[actor.name]:tick();server=kind=='mp'
 end
 local function flush()
  local pending=sent;sent={}
  for _,message in ipairs(pending)do coordinator:handle(message.actor,message.command,message.args)end
  return pending
 end
 return authority,players,coordinator,messages,tickClient,flush,function()return sent end,clients
end
for _,kind in ipairs({'sp','mp'})do
 local authority,players,coordinator,messages,tickClient,flush,pending,clients=harness(kind)
 for _,actor in ipairs(players)do coordinator:handle(actor,'Ready',{})end
 coordinator:tick()
 local first=players[1]
 server=false;getPlayer=function()return first end
 rejects(function()clients[first.name]:receive(messages[1].args)end,'duplicate client layout accepted')
 server=kind=='mp'
 assert(#first.inventory.items==0,'Ready seeded setup before owning arrival')
 -- One owner stays moving, so the helper cannot teleport, center, or produce proof.
 local delayed=players[#players];local moving=true
 function delayed:isPlayerMoving()return moving end
 for i=1,4 do now=now+500;for _,actor in ipairs(players)do tickClient(actor)end;flush();coordinator:tick()end
 assert(#first.inventory.items==0 and #delayed.inventory.items==0,'missing owner arrival mutated setup inventory')
 moving=false
 local received
 for i=1,5 do
  now=now+500;for _,actor in ipairs(players)do tickClient(actor)end
  if #pending()>0 then received=pending()[1];break end
  flush();coordinator:tick()
 end
 assert(received,'owning client never sent real proof')
 for _,fault in ipairs({'phase','doctor','actor','target','proof'})do
  local args=copy(received.args)
  if fault=='phase'then args.phase='bandageApply'
  elseif fault=='doctor'then args.doctor='client1'
  elseif fault=='actor'then args.actor='intruder'
  elseif fault=='target'then args.target.x=args.target.x+1
  else args.proof.actual.queued=1 end
  rejects(function()coordinator:handle(received.actor,'Placed',args)end,'wrong '..fault..' owning receipt accepted')
 end
 rejects(function()coordinator:handle(fixture.player(received.actor.name),'Placed',received.args)end,'replaced actor identity accepted owning proof')
 local delivered=flush()
 assert(#delivered>0)
 rejects(function()coordinator:handle(received.actor,'Placed',received.args)end,'duplicate owning arrival accepted')
 if kind=='mp'then
  delayed.x=delayed.x+.3
  for i=1,3 do now=now+500;coordinator:tick()end
  assert(#first.inventory.items==0 and #delayed.inventory.items==0,'owning proof bypassed delayed authority replica')
  delayed.x=received.args.target.x+.5
 end
 for i=1,4 do now=now+500;coordinator:tick()end
 assert(#first.inventory.items==3 and #delayed.inventory.items==3,'settled setup never committed both inventories')
 rejects(function()coordinator:handle(received.actor,'Placed',received.args)end,'stale owning receipt accepted after round')
 coordinator:handle(first,'Prepare',{phase='bandageApply'})
 assert(not first.body.scratchFlag,'Prepare seeded injury before placement')
 for i=1,5 do
  now=now+500;for _,actor in ipairs(players)do tickClient(actor)end;flush();coordinator:tick()
 end
 if kind=='mp'then for i=1,3 do now=now+500;coordinator:tick()end end
 local patient=players[#players]
 assert(patient.body.scratchFlag,'settled coordinator failed real clinical preparation')
 local prepared
 for _,message in ipairs(messages)do if message.command=='Prepared'then prepared=message.args end end
 assert(prepared and prepared.patient==patient.name,'actual coordinator lost prepared patient')
 if kind=='mp'then
  authority.baseline(first,'bandageApply')
  for i=#first.inventory.items,1,-1 do local item=first.inventory.items[i]
   if item.id==prepared.items.bandage then first.inventory:Remove(item)
   elseif item.id==prepared.front or item.id==prepared.tail then item.pages=100 end
  end
  patient.body.covered=true
  assert(authority.verify(first,'bandageApply').ok)
  authority.finish(first)
  coordinator:handle(patient,'Prepare',{phase='bandageApply'})
  local layout=messages[#messages].args
  assert(layout.doctor==patient.name and layout.targets[patient.name].x+1==layout.targets[first.name].x,'next doctor did not swap centered roles')
  for i=1,8 do
   now=now+500;for _,actor in ipairs(players)do tickClient(actor)end;flush();coordinator:tick()
  end
  assert(first.body.scratchFlag and not first.body.covered and P.atCentered(first,layout.targets[first.name])
   and P.atCentered(patient,layout.targets[patient.name]),'remote role swap failed real owner/authority arrival and patient seed')
 end
end
print('PASS actual SP/MP coordinator/client waits for every owner and replica; rejects wrong, duplicate and stale receipts before real preparation')

-- SP native usernames are game identities, while emitted receipts use the runner role.
for _,username in ipairs({'','native-survivor'})do
 local priorPrint=print;local raw={}
 print=function(line)
  if type(line)=='string'and line:find('[HEALTH_PLACEMENT] ',1,true)==1 then raw[#raw+1]=line end
 end
 local authority,players,coordinator,messages,tickClient,flush=harness('sp',username)
 local actor=players[1]
 rejects(function()coordinator:handle(fixture.player(username),'Ready',{})end,'SP accepted another player with the native username')
 actor.isLocalPlayer=function()return false end
 rejects(function()coordinator:handle(actor,'Ready',{})end,'SP accepted a nonlocal Ready actor')
 actor.isLocalPlayer=function()return true end
 coordinator:handle(actor,'Ready',{});coordinator:tick()
 local setupLayout=messages[1].args
 assert(setupLayout.targets[username]and count(setupLayout.targets)==1,'SP setup replaced the native username with runner identity')
 for i=1,6 do now=now+500;tickClient(actor);flush();coordinator:tick()end
 assert(authority.ids(actor).username==username and actor:getUsername()==username,'SP setup renamed native actor identity')
 coordinator:handle(actor,'Prepare',{phase='bandageApply'})
 local caseLayout=messages[#messages].args
 assert(caseLayout.doctor==username and caseLayout.targets[username],'SP case reservation lost actual native doctor')
 for i=1,6 do now=now+500;tickClient(actor);flush();coordinator:tick()end
 local prepared=messages[#messages]
 assert(prepared.command=='Prepared'and prepared.args.patient==username and prepared.args.placement==caseLayout
  and actor.body.scratchFlag,'SP native identity did not complete actual settled clinical preparation')
 local events={}
 for _,line in ipairs(raw)do
  local event=line:match('^%[HEALTH_PLACEMENT%] ([A-Z_]+) ');events[event]=true
  assert(not line:find('"":',1,true)and not line:find('native-survivor',1,true),'raw receipt leaked noncanonical native actor')
  if line:find('"actor":',1,true)then assert(line:find('"actor":"client1"',1,true),'raw receipt actor is not runner role')end
  if line:find('"targets":',1,true)then assert(line:find('"targets":{"client1":',1,true),'raw layout keys are not runner roles')end
  assert(line:find('"doctor":"setup"',1,true)or line:find('"doctor":"client1"',1,true),'raw receipt doctor is not canonical')
 end
 for _,event in ipairs({'LAYOUT','CLIENT_PLACEMENT','AUTHORITY_PLACEMENT','PREPARED'})do assert(events[event],'actual SP path omitted raw '..event)end
 print=priorPrint
end
print('PASS empty and non-runner SP native usernames bind only the owning actor; actual placement keeps identities and raw receipts use client1')

do
 local _,players,coordinator,_,tickClient,flush=harness('mp')
 for _,actor in ipairs(players)do coordinator:handle(actor,'Ready',{})end
 coordinator:tick()
 -- A local motion stall cannot create an owning proof or mutate setup.
 players[2].isPlayerMoving=function()return true end
 now=now+P.timeoutMs
 rejects(function()tickClient(players[2])end,'owning placement never timed out')
 rejects(function()coordinator:tick()end,'missing owner round never timed out')
 assert(#players[1].inventory.items==0 and #players[2].inventory.items==0,'timeout changed setup inventory')
end
print('PASS local motion and coordinator arrival deadlines preserve untouched fixtures')

-- Exercise native empty-table decoding at the shipped server dispatch boundary.
local function serverDispatch()
 server=true
 local authority,players=world('mp',{'inventoryBandage'})
 local messages,clients={},{},{}
 local handlers={}
 Events={}
 for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'})do
  Events[name]={Add=function(callback)handlers[name]=callback end}
 end
 local function command(actor,name,args)
  local previous=server;server=true;handlers.OnClientCommand('HealthQueueTest',name,actor,args);server=previous
 end
 for _,actor in ipairs(players)do clients[actor.name]=Coordinator.newClient(function(name,args)command(actor,name,args)end)end
 sendServerCommand=function(actor,module,name,args)
  assert(module=='HealthQueueTest');messages[#messages+1]={actor=actor,command=name,args=args}
  if name=='Placement'then
   server=false;getPlayer=function()return actor end;clients[actor.name]:receive(args);server=true
  end
 end
 local fallback=fixture.require
 require=function(name)
  if name=='QueueHealthAuthority'then return authority elseif name=='QueueHealthPlacement'then return Coordinator end
  return fallback(name)
 end
 fixture.source('server','ZZHealthQueue_Server')
 local function failed()
  for _,message in ipairs(messages)do if message.command=='Failed'then return message.args.error end end
 end
 local function settleSetup()
  for _,actor in ipairs(players)do command(actor,'Ready',nil)end
  handlers.OnTick()
  for _,actor in ipairs(players)do assert(#actor.inventory.items==0,'nil Ready seeded inventory before owning placement')end
  for i=1,8 do
   now=now+500
   for _,actor in ipairs(players)do
    server=false;getPlayer=function()return actor end;clients[actor.name]:tick();server=true
   end
   handlers.OnTick()
  end
  assert(not failed(),'nil Ready failed native server dispatch')
  for _,actor in ipairs(players)do assert(authority.ids(actor),'nil Ready never completed actual settled setup')end
 end
 return authority,players,command,failed,settleSetup
end
for _,fault in ipairs({'Prepare','Placed','Verify','Ready'})do
 local _,players,command,failed=serverDispatch()
 local payload=nil;if fault=='Ready'then payload=false end
 command(players[1],fault,payload)
 assert(failed()and failed():find('health request arguments missing',1,true),'server accepted missing/false '..fault..' payload')
 assert(#players[1].inventory.items==0,'malformed server payload seeded fixture')
end
do
 local _,players,command,failed,settleSetup=serverDispatch()
 settleSetup();command(players[1],'Finish',nil)
 assert(failed()and failed():find('incomplete MP phases',1,true),'nil Finish bypassed authoritative terminal case guard')
end
do
 local authority,players,command,failed,settleSetup=serverDispatch()
 settleSetup()
 local actor=players[1];local layout=authority.prepareLayout(actor,'inventoryBandage')
 local prep=authority.prepare(actor,'inventoryBandage',layout,prove(authority,layout));authority.baseline(actor,'inventoryBandage')
 for i=#actor.inventory.items,1,-1 do local item=actor.inventory.items[i]
  if item.id==prep.items.bandage then actor.inventory:Remove(item)
  elseif item.id==prep.front or item.id==prep.tail then item.pages=100 end
 end
 actor.body.covered=true;assert(authority.verify(actor,'inventoryBandage').ok)
 command(actor,'Finish',nil)
 assert(not failed()and authority.session(players[2]).active,'nil Finish did not preserve actual terminal authority transition')
end
require=fixture.require
print('PASS actual native server dispatch normalizes only nil Ready/Finish; placement and terminal guards remain strict and malformed work payloads reject')
