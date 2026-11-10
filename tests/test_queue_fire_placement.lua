-- Exercise actual Fire setup/RPC entry points; placement and native work are doubles.
local root=assert(ProjectRoot)
local function point(x,y,z)return {x=x,y=y,z=z}end
local function same(a,b)return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
local validTarget=assert(loadfile(root..'/tests/native_queue/support/QueueEnergyPlacement.lua'))().target
local function fixture(role,kind,mode,case)
 local f={commands={},responses={},rows={},history={},begins=0,chooses=0,observes=0,seeds=0,prepares=0,
  pages=0,enqueues=0,teleports=0,tidyResets=0,localSettled=false,replicaSettled=false,centered=false,visible=true}
 case=case or 'bbq-fuel';mode=mode or 'toolkit'
 local fuelClient=role=='client'and(case=='fuel'or case=='missing-target-after-expansion')
 local config={kind=kind,mode=mode,cases={case},mods={}}
 local target=point(20,30,0)
 local book={getNumberOfPages=function()return 20 end,getFullType=function()return 'Base.BookCarpentry1'end,
  setAlreadyReadPages=function()f.pages=f.pages+1 end}
 local item={getFullType=function()return 'Base.Log'end}
 local source={getItemById=function(_,id)if id==10 then return item end end}
 function item:getContainer()return source end
 function item:getCondition()return 100 end
 local inventory={getItemById=function(_,id)if id==11 then return book end end}
 local player={}
 function player:isDead()return false end
 function player:getSquare()return {}end
 function player:getOnlineID()return 1 end
 function player:setGhostMode()end
 function player:getUsername()return f.username or 'client1'end
 function player:getInventory()return inventory end
 function player:getPlayerNum()return 0 end
 function player:isTimedActionInstant()return false end
 function player:setAlreadyReadPages()f.pages=f.pages+1 end
 function player:hasTimedActions()return false end
 function player:teleportTo()f.teleports=f.teleports+1;error('late fixture teleport')end
 local crate={getObjectIndex=function()return 1 end,getSprite=function()return {getName=function()return 'carpentry_01_16'end}end,
  getContainer=function()return source end}
 local barbecue={class='IsoBarbecue',getObjectIndex=function()return 2 end}
 local square={getObjects=function()return list({crate,barbecue})end,getSpecialObjects=function()return list({crate})end}
 local campfire={fuelAmt=0,isLit=false,getIsoObject=function()return barbecue end,updateFromIsoObject=function()end}
 local P={target=validTarget}
 function P.choose(actor)assert(actor==player);f.chooses=f.chooses+1;return validTarget(target)end
 function P.atCentered(actor,wanted)return actor==player and same(wanted,target)and f.centered end
 function P.beginCentered(actor,wanted)
  assert(role=='client'and actor==player and same(wanted,target));f.begins=f.begins+1
  return {mode='local',target=validTarget(wanted)}
 end
 function P.observeCentered(actor,wanted)
  assert(role=='server'and actor==player);f.observes=f.observes+1
  return {mode='replica',target=validTarget(wanted)}
 end
 function P.poll(pending)
  if not (pending.mode=='local'and f.localSettled or pending.mode=='replica'and f.replicaSettled)then return end
  local localActor=pending.mode=='local'
  return {mode=pending.mode,target=validTarget(pending.target),centered=true,
   teleports=localActor and 1 or 0,centers=localActor and 1 or 0}
 end
 local spec={mode='fuel',class='ISBBQAddFuel',duration=100,bbq=true}
 if case=='kindle-retry'then spec={mode='kindle',class='ISLightFromKindle',duration=1500,retry=true}end
 local test={cases={[case]=spec}}
 local function ids(trial)
  return {case=case,trial=trial or 1,actionType=spec.class,nativeDuration=spec.duration,targetKind=spec.bbq and 'bbq'or'campfire',
   placement=validTarget(target),x=21,y=30,z=0,crateX=21,crateY=30,crateZ=0,crateIndex=1,objectIndex=2,book=11,log=10,condition=100,fuelAmount=120,
   resources={{id=10,role='fuel',kind='Base.Log',source='crate'}}}
 end
 function test.prepare(actor,requested,wanted,proof,trial)
  assert(actor==player and requested==case and same(wanted,target)and P.atCentered(actor,wanted),'stale fixture placement')
  assert(proof.mode==(role=='server'and'replica'or'local')and same(proof.target,wanted)
   and proof.centered and proof.teleports==(role=='server'and 0 or 1)and proof.centers==(role=='server'and 0 or 1),'wrong authority proof')
  f.prepares=f.prepares+1;f.seeds=f.seeds+1;f.history[#f.history+1]='prepare';f.preparedProof=proof
  return ids(trial)
 end
 function test.verify(actor,requested,tidy)
  assert(actor==player and requested==case);f.verifiedTidy=tidy
  return {case=case,trial=f.receiptTrial or 1}
 end
 function test.invalidate()f.invalidations=(f.invalidations or 0)+1;return {case=case,ok=true}end
 local queue={queue={}}
 local eventNames={'OnClientCommand','OnTick','OnServerCommand','OnGameStart'};local events={}
 for _,name in ipairs(eventNames)do
  local handlers={};events[name]={Add=function(fn)handlers[#handlers+1]=fn end,
   fire=function(...)for _,fn in ipairs(handlers)do fn(...)end end}
 end
 local encoded
 local env=setmetatable({Events=events,isServer=function()return role=='server'end,isClient=function()return role=='client'and kind=='mp'end,
  getPlayer=function()return player end,getTimestampMs=function()return 100 end,
  instanceof=function(value,class)return value.class==class end,
  getCell=function()return {getGridSquare=function(_,x,y,z)assert(x==21 and y==30 and z==0);return square end}end,
  getPlayerInventory=function()return {refreshBackpacks=function()end}end,getPlayerLoot=function()return {refreshBackpacks=function()end}end,
  ISInventoryPaneContextMenu={getContainers=function()
   local value=list(f.visible and {source}or {});value.contains=function(_,entry)return entry==source and f.visible end;return value end},
  isIngameState=function()return true end,getCore=function()return {setOptionPauseOnFocusloss=function()end}end,
  CCampfireSystem={instance={getLuaObjectAt=function()return campfire end}},
  ISCampingMenu={onAddFuel=function()end,getFuelDurationForItem=function()return 120 end},ISBBQAddFuel={},ISAddFuelAction={},
  ISReadABook={new=function(_,actor,value)assert(actor==player and value==book);return {minutesPerPage=2,maxTime=10}end},
  PZSurvivorToolkit={Settings={actionQueue=function()return mode=='toolkit'end},ActionQueueLifecycle={begin=function()return mode=='toolkit'end,finish=function()end,flush=function()end}},
  ISTimedActionQueue={queues={[player]=queue},getTimedActionQueue=function()return queue end,
   queueActions=function()f.enqueues=f.enqueues+1;f.history[#f.history+1]='native' end,
   add=function()f.enqueues=f.enqueues+1 end},
  sendClientCommand=function(module,command,args)assert(module=='FireQueueTest');f.commands[#f.commands+1]={command=command,args=args}end,
  sendServerCommand=function(actor,module,command,args)assert(actor==player and module=='FireQueueTest');f.responses[#f.responses+1]={command=command,args=args}end,
  print=function(message)
   f.history[#f.history+1]=message
   if message:match('^%[FIRE_TEST%] ')then f.rows[#f.rows+1]={message=message,value=encoded}end
  end,
 },{__index=_G})
 env._G=env
 env.require=function(name)
  if name=='QueueTestSelection'then return config end
  if name=='QueueFireIgnition'then return fuelClient and {cases={}}or test end
  if name=='QueueFireAuthority'then return test end
  if name=='QueueFireIgnitionClient'then assert(fuelClient);return {response=function()end}end
  if name=='QueuePreflight'then return {onTick=function(_,fn)events.OnTick.Add(fn)end,onGameStart=function(_,fn)events.OnGameStart.Add(fn)end}end
  if name=='QueueEnergyPlacement'then return P end
  if name=='QueueHealthEvents'then return {encode=function(value)encoded=value;return '{}'end,emit=function(value)if value.event=='error'then f.error=value.message end end}end
  if name=='QueueFireTidy'then return {install=function()end,reset=function()f.tidyResets=f.tidyResets+1 end,idleUpdates=function()return 3 end}end
  assert(name=='PZSurvivorToolkit/ActionQueuePanel'or name:match('^Camping/')or name:match('^TimedActions/'),name);return true
 end
 if fuelClient then
  setfenv(assert(loadfile(root..'/tests/native_queue/fire/client/ZZFireQueue.lua')),env)()
  function f.tick()events.OnTick.fire()end
  function f.reply(command,args)events.OnServerCommand.fire('FireQueueTest',command,args)end
  events.OnGameStart.fire()
 elseif role=='client'then
  local file=assert(io.open(root..'/tests/native_queue/fire/client/QueueFireIgnitionClient.lua'));local source=file:read('*a');file:close()
  source=source:gsub('\nreturn Client','\nClient.fixtureState=function()return state end\nreturn Client')
  f.client=setfenv(assert(loadstring(source)),env)()
  function f.tick()return f.client.tick(player,case)end
  function f.reply(command,args)return f.client.response(command,args)end
  function f.state()return f.client.fixtureState()end
 else
  setfenv(assert(loadfile(root..'/tests/native_queue/fire/server/ZZFireServer.lua')),env)()
  function f.tick()events.OnTick.fire()end
  function f.request(command,args)events.OnClientCommand.fire('FireQueueTest',command,player,args)end
 end
 function f.args(trial)return {case=case,trial=trial or 1,target=validTarget(target),
  clientPlacement={mode='local',target=validTarget(target),centered=true,teleports=1,centers=1}}end
 function f.failed()return f.responses[#f.responses]and f.responses[#f.responses].command=='Failed'end
 f.ids,f.target,f.player,f.case,f.test=ids,target,player,case,test
 return f
end

for _,mode in ipairs({'toolkit','native'})do for _,kind in ipairs({'sp','mp'})do
 local f=fixture('client',kind,mode)
 f.tick();f.tick()
 assert(f.begins==1 and f.chooses==1 and f.prepares==0 and #f.commands==0 and f.tidyResets==0 and f.pages==0 and f.enqueues==0,
  'pending centered placement reached fixture preparation')
 f.localSettled=true;f.centered=true;f.tick()
 local row=f.rows[1]
 assert(row.message=='[FIRE_TEST] CLIENT_PLACEMENT {}'and row.value.case==f.case and row.value.trial==1
  and row.value.actor=='client1'and same(row.value.target,f.target)and row.value.proof.centered,'client placement log lost protocol identity')
 if kind=='mp'then
  local request=f.commands[1]
  assert(request.command=='Prepare'and request.args.trial==1 and same(request.args.target,f.target)
   and request.args.clientPlacement==row.value.proof and request.args.tidyReturnIds==nil and f.prepares==0)
  f.reply('Prepared',f.ids())
 else assert(f.prepares==1 and f.preparedProof==row.value.proof)end
 f.tick();f.visible=false;f.tick()
 assert(f.enqueues==0 and f.pages==0,'invisible borrowed source bypassed native container gate')
 f.visible=true;f.tick()
 assert(f.enqueues==2 and f.pages==2 and f.teleports==0 and f.tidyResets==1,'settled setup did not admit native work exactly once')
 local admitted=f.rows[#f.rows]
 assert(admitted.message=='[FIRE_TEST] ADMITTED {}'and admitted.value.trial==1 and admitted.value.case==f.case and admitted.value.actor=='client1')
 assert(f.history[#f.history-1]=='[FIRE_TEST] ADMITTED {}'and f.history[#f.history]=='native','admission was not immediately before native enqueue')
 f.state().phase='settling';f.tick()
 if kind=='mp'then
  local request=f.commands[#f.commands]
  assert(request.command=='Verify'and request.args.trial==1 and request.args.case==f.case and #request.args.tidyReturnIds==0
   and request.args.target==nil and request.args.clientPlacement==nil,'Verify did not bind the prepared trial')
 else assert(type(f.verifiedTidy)=='table')end
end end

for _,fault in ipairs({'stale-proof','wrong-case','wrong-trial','changed-target','drift-before-admission'})do
 local f=fixture('client','mp');f.localSettled=true;f.centered=fault~='stale-proof'
 local ok=pcall(function()
  f.tick()
  if fault=='stale-proof'then return end
  local ids=f.ids()
  if fault=='wrong-case'then ids.case='other'elseif fault=='wrong-trial'then ids.trial=2
  elseif fault=='changed-target'then ids.placement.x=ids.placement.x+1 end
  f.reply('Prepared',ids);f.tick()
  if fault=='drift-before-admission'then f.centered=false end
  f.tick()
 end)
 assert(not ok and f.pages==0 and f.enqueues==0 and f.teleports==0,'client accepted '..fault)
 if fault=='stale-proof'then assert(#f.commands==0 and f.tidyResets==0,'stale centered proof reached Prepare')end
end

for _,mode in ipairs({'toolkit','native'})do for _,kind in ipairs({'sp','mp'})do
 for _,case in ipairs({'fuel','missing-target-after-expansion'})do
  local f=fixture('client',kind,mode,case);f.tick();f.tick();f.tick()
  assert(f.begins==1 and f.chooses==1 and f.prepares==0 and #f.commands==0 and f.enqueues==0 and f.pages==0,
   'fuel client seeded before centered placement settled')
  f.localSettled=true;f.centered=true;f.tick()
  local placement=f.rows[1].value
  assert(placement.case==case and placement.trial==1 and placement.actor=='client1'and same(placement.target,f.target))
  if kind=='mp'then
   assert(f.commands[1].command=='Prepare'and f.commands[1].args.trial==1 and same(f.commands[1].args.target,f.target)
    and f.commands[1].args.clientPlacement==placement.proof,'fuel Prepare lost final client proof')
   f.reply('Prepared',f.ids())
  else assert(f.prepares==1 and f.preparedProof==placement.proof)end
  f.tick();f.visible=false;f.tick()
  assert(f.enqueues==0 and f.pages==0,'fuel client admitted invisible source')
  f.visible=true;f.tick()
  assert(not f.error and f.enqueues==2 and f.pages==2 and f.teleports==0,f.error or'fuel admission changed native enqueue')
  assert(f.rows[#f.rows].message=='[FIRE_TEST] ADMITTED {}'and f.rows[#f.rows].value.trial==1
   and f.history[#f.history-1]=='[FIRE_TEST] ADMITTED {}'and f.history[#f.history]=='native','fuel admission log did not precede native enqueue')
 end
end end
for _,fault in ipairs({'stale-proof','wrong-case','wrong-trial','changed-target','drift-before-admission'})do
 local f=fixture('client','mp','toolkit','fuel');f.tick();f.localSettled=true;f.centered=fault~='stale-proof';f.tick()
 if fault~='stale-proof'then
  local ids=f.ids()
  if fault=='wrong-case'then ids.case='other'elseif fault=='wrong-trial'then ids.trial=2
  elseif fault=='changed-target'then ids.placement.x=19 end
  local ok=pcall(function()f.reply('Prepared',ids)end)
  if ok then
   f.tick();if fault=='drift-before-admission'then f.centered=false end;f.tick()
  else f.error='response identity rejected'end
 end
 assert(f.error and f.enqueues==0 and f.pages==0 and f.teleports==0,'fuel client accepted '..fault)
 if fault=='stale-proof'then assert(#f.commands==0,'fuel stale centered proof reached Prepare')end
end

local retry=fixture('client','mp','toolkit','kindle-retry');retry.localSettled=true;retry.centered=true;retry.tick()
local prior=retry.state();prior.ids=retry.ids();prior.phase='receipt';prior.attempts=1
prior.receipt={case=retry.case,trial=1,bookId=11,targetKind='campfire',tailRead=true}
retry.tick();assert(retry.state().trial==2 and retry.state().phase=='prepare','natural Kindle trial did not reset placement identity')
retry.localSettled=false;retry.tick()
assert(retry.begins==2 and retry.chooses==2 and #retry.commands==1,'natural Kindle retry reused historical centered proof')
retry.localSettled=true;retry.tick();assert(retry.commands[2].args.trial==2,'natural retry Prepare reused trial one')
assert(not pcall(function()retry.reply('Prepared',retry.ids(1))end),'natural retry accepted preceding trial response')

local server=fixture('server','mp');server.request('Prepare',server.args())
server.tick();server.tick()
assert(server.observes==1 and server.prepares==0 and #server.responses==0 and server.teleports==0,'server seeded before replica proof settled')
server.replicaSettled=true;server.centered=true;server.tick();server.tick()
assert(server.prepares==1 and server.seeds==1 and #server.responses==1 and server.responses[1].command=='Prepared'
 and server.responses[1].args.trial==1 and server.preparedProof.mode=='replica','server did not prepare exact settled replica trial')
server.request('Verify',{case=server.case,trial=1,tidyReturnIds={}});server.tick()
assert(server.responses[#server.responses].command=='Verified'and #server.verifiedTidy==0,'server lost valid Verify binding')

for _,fault in ipairs({'missing-proof','foreign-proof','wrong-proof-target','uncentered-proof','bad-counter','fractional-target','missing-trial','foreign-actor','foreign-case','overlap','stale-replica'})do
 local f=fixture('server','mp');local args=f.args()
 if fault=='missing-proof'then args.clientPlacement=nil elseif fault=='foreign-proof'then args.clientPlacement.mode='replica'
 elseif fault=='wrong-proof-target'then args.clientPlacement.target.x=19 elseif fault=='uncentered-proof'then args.clientPlacement.centered=false
 elseif fault=='bad-counter'then args.clientPlacement.centers=0 elseif fault=='fractional-target'then args.target.x=20.5
 elseif fault=='missing-trial'then args.trial=nil elseif fault=='foreign-actor'then f.username='client2'
 elseif fault=='foreign-case'then args.case='other'end
 f.request('Prepare',args);if fault=='overlap'then f.request('Prepare',args)end
 f.replicaSettled=true;f.centered=fault~='stale-replica';f.tick()
 assert(f.failed()and f.prepares==0 and f.seeds==0 and f.teleports==0,'server accepted '..fault)
end
for _,command in ipairs({'Verify','Invalidate'})do
 local f=fixture('server','mp');f.replicaSettled=true;f.centered=true;f.request('Prepare',f.args());f.tick()
 f.request(command,{case=f.case,trial=2,tidyReturnIds={}});f.tick()
 assert(f.failed()and f.verifiedTidy==nil and not f.invalidations,'server accepted stale '..command..' trial')
end
print('Fire placement setup checks passed: centered arrival, trial-bound RPC, deferred seeding, fresh admission and natural retry identity.')
