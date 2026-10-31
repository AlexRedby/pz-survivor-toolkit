local selection=require 'QueueTestSelection'
if selection.cases[1]~='walk'or(selection.kind~='sp'and selection.kind~='mp')then return end
local F=require 'WarehouseWalkingFixture'
local U=require 'WarehouseWorkloadUI'
local A=require 'WarehouseWalkingActor'
local N=require 'WarehouseWalkingNative'
local R={stage='baseline',index=1,replies={},phases=0}
local started,done=false,false
local function now()return getTimestampMs()end
local function transition(stage)R.stage=stage;R.since=now()end
local function emit(event,row)
 row=F.context(R.state,row or {});row.role=R.role;row.index=R.index
 row.token=R.ids and R.ids.token;F.emit(event,row)
end
local function authority(event,row)F.emit(event,F.context(R.authority,row))end
local function localRequest(command,args)
 if command=='Prepare'then
  R.localToken=F.sessionToken(R.player)
  F.emit('READY',{token=R.localToken,index=1,onlineIds={client1=R.player:getOnlineID()}})
  R.replies.CaptureBaseline={token=R.localToken}
 elseif command=='Baseline'then
  F.emit('BASELINE_SEEN',{token=R.localToken,index=1,observer='client1'})
  R.authority=F.capture({client1=R.player},{client1=R.actor},{client1=args.baseline},R.localToken)
  authority('BASELINES',{originalRootIds=R.authority.ids.originalRootIds,originalEquipment=R.authority.ids.originalEquipment})
  R.replies.Normalize={ids=R.authority.ids,role='client1'}
 elseif command=='Normalized'then
  authority('NORMALIZED',{observer='client1',proof=args.proof})
  F.materialize(R.authority);authority('SETUP',{ids=R.authority.ids,onlineIds={client1=R.player:getOnlineID()}})
  R.replies.Prepared={ids=R.authority.ids,role='client1'}
 elseif command=='Ready'then
  local p=F.seed(R.authority,R.index);local snapshot=assert(F.snapshot(R.authority));R.authorityBefore=snapshot
  local pos=U.position(R.player);local confirmedAt=now();local readiness={client1={x=pos.x,y=pos.y,z=pos.z,squareX=pos.squareX,squareY=pos.squareY,squareZ=pos.squareZ,
   requestedAt=confirmedAt,confirmedAt=confirmedAt,waitMs=0,deadlineMs=15000,onlineId=R.player:getOnlineID()}}
  authority('SEED',{phase=p,snapshot=snapshot,readiness=readiness});authority('ADMIT',{stage='before',snapshot=snapshot,readiness=readiness})
  R.replies.Seeded={phase=p,authority=snapshot,readiness=readiness}
 elseif command=='Seen'then
  authority('SEEN',{observer='client1',stage=args.stage})
  assert(F.snapshot(R.authority),'SP authoritative walking identities changed')
  if args.stage=='before'then authority('GO');R.replies.Go={phaseToken=R.phase.phaseToken,index=R.index}
  else
   local receipt=F.release(R.authority,R.index);F.emit('RELEASE',receipt);R.replies.Released=receipt
   if R.index==16 then local cleanup=F.cleanup(R.authority);F.emit('RESTORED',cleanup);F.emit('COMPLETE',{role='server',token=cleanup.token,index=16,phases=16,restored=true});R.replies.Done=cleanup end
  end
 elseif command=='Ended'then
  local after=assert(F.snapshot(R.authority));authority('AUTHORITY',{before=R.authorityBefore,after=after});R.replies.Observed={authority=after}
 elseif command=='Abort'then R.replies.AbortRequested={error=R.failure}
 elseif command=='AbortReady'then
  local cleanup=F.abort(R.authority or F.preparing);authority('ABORT',{restored=true,cleanup=cleanup});R.replies.Abortd={restored=true,cleanup=cleanup,cleanupTransport=F.cleanupTransport}
 else error('unknown local walking protocol command')end
end
local function request(command,args)
 args=args or {};args.case='walk';args.token=R.ids and R.ids.token or R.replies.AbortRequested and R.replies.AbortRequested.token
 args.index=R.index;args.phaseToken=R.phase and R.phase.phaseToken
 if selection.kind=='sp'then localRequest(command,args)
 elseif command=='Prepare'or command=='Baseline'or command=='Normalized'then
  assert(type(warehouseWalkingOrderedClient)=='function','native ordered walking client sender missing')
  assert(warehouseWalkingOrderedClient(R.player,F.module,command,args)==true,'native ordered walking client dispatch failed: '..command)
 else sendClientCommand(F.module,command,args)end
 if command=='Prepare'then R.prepareSent=true end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=F.module or done then return end
 -- Each coordinator command has one pending slot; a duplicate is a protocol failure.
 if (command=='CaptureBaseline'and R.captureReceived)or(command=='Normalize'and R.normalizeReceived)or R.replies[command]then R.protocolError='duplicate walking server command: '..command else R.replies[command]=args end
 if command=='CaptureBaseline'then R.captureReceived=true elseif command=='Normalize'then R.normalizeReceived=true end
end)
local function place(point)
 R.placement={began=now(),target={x=point.x+.5,y=point.y+.5,z=point.z,squareX=point.x,squareY=point.y,squareZ=point.z}};transition('position')
end
local function stableUI()
 if R.baseline and now()-R.baseline.last<120 then return end
 for _,page in ipairs(U.pages(R.player))do if not page or not page.inventoryPane then return end end
 U.normalize(R.player);local values={}
 for i,page in ipairs(U.pages(R.player))do local pane=page.inventoryPane
  if not pane.inventory then return end
  values[i]={page=page,pane=pane,inventory=pane.inventory,x=page:getX(),y=page:getY(),w=page:getWidth(),h=page:getHeight(),px=pane:getX(),py=pane:getY(),pw=pane:getWidth(),ph=pane:getHeight()}
  if values[i].w<=0 or values[i].h<=0 or values[i].pw<=0 or values[i].ph<=0 then return end
 end
 local same=R.baseline~=nil
 if same then for i,value in ipairs(values)do for key,v in pairs(value)do if R.baseline.values[i][key]~=v then same=false end end end end
 if same then R.baseline.samples=R.baseline.samples+1 else R.baseline={samples=1}end
 R.baseline.last=now();R.baseline.values=values;return R.baseline.samples>=3
end
local function admit(stage,authoritySnapshot)
 local snapshot=F.snapshot(R.state);if not snapshot then return end
 F.project(snapshot,authoritySnapshot,R.role);A.originalProof(R.actor)
 assert(N.idle(R.player)and N.matches(R.player,R.phase.paneState),'walking admission state differs')
 emit('ADMIT',{stage=stage,snapshot=snapshot,authority=authoritySnapshot})
 if stage=='before'then R.before=snapshot else R.after=snapshot end
 request('Seen',{stage=stage});return true
end
local function tick()
 assert(not R.protocolError,R.protocolError)
 assert(not R.replies.Failed,R.replies.Failed and R.replies.Failed.error)
 assert(now()-R.since<90000,'walking client stage timeout: '..R.stage)
 if R.stage=='baseline'then
  if not N.idle(R.player)or not stableUI()then return end
  R.ui=U.save(R.player);R.lock=N.saveLock(R.player);R.readyPosition=U.position(R.player)
  U.protect(R.player,R.ui);request('Prepare');transition('capture-baseline')
 elseif R.stage=='capture-baseline'then
  local packet=R.replies.CaptureBaseline;if not packet then return end
  assert(type(packet.token)=='string'and not R.ids,'duplicate/wrong walking capture token');R.ids={token=packet.token}
  assert(N.idle(R.player),'native walking actor busy at original capture')
  R.original=U.original(R.player);R.position=U.position(R.player);R.actor=A.save(R.player)
  emit('BASELINE',{original=U.originalProof(R.player,R.original),originalEquipment=A.equipmentProof(R.actor),position=R.position,stableSamples=R.baseline.samples})
  R.replies.CaptureBaseline=nil;request('Baseline',{baseline=A.baseline(R.actor)});transition('normalize')
 elseif R.stage=='normalize'then
  local packet=R.replies.Normalize;if not packet then return end
  assert(packet.role==R.role and packet.ids.token==R.ids.token,'wrong walking normalization role/token')
  A.matchBaseline(R.actor,{rootIds=packet.ids.originalRootIds[R.role],equipment=packet.ids.originalEquipment[R.role]})
  assert(N.idle(R.player),'native walking actor busy at normalization')
  U.originalProof(R.player,R.original);A.equipmentProof(R.actor);A.detach(R.actor)
  local proof=A.normalizedProof(R.actor);emit('NORMALIZED',{proof=proof})
  R.replies.Normalize=nil;request('Normalized',{baseline=A.baseline(R.actor),proof=proof});transition('prepared')
 elseif R.stage=='prepared'then
  local packet=R.replies.Prepared;if not packet then return end
  assert(packet.role==R.role and packet.ids.token==R.ids.token,'walking prepared role/token differs');R.ids=packet.ids
  R.state=F.resolve(R.player,R.ids,R.role,R.actor);if not R.state then return end
  R.replies.Prepared=nil;emit('SETUP',{ids=R.ids});place(R.ids.actorOrigins[R.role])
 elseif R.stage=='position'then
  local proof=U.place(R.player,R.placement,N.idle(R.player));if not proof then return end
  U.configure(R.player,F.phases[R.index].paneMode);R.placementProof=proof
  request('Ready');transition('seeded')
 elseif R.stage=='seeded'then
  local packet=R.replies.Seeded;if not packet then return end
  R.phase=packet.phase;F.attach(R.state,R.phase)
  if R.lastScan and now()-R.lastScan<120 then return end;R.lastScan=now()
  local snapshot=F.snapshot(R.state);if not snapshot then return end
  F.project(snapshot,packet.authority,R.role)
  N.configure(R.player,R.phase);emit('MODE',{placement=R.placementProof,paneStateProof=N.state(R.player)})
  R.seedAuthority=packet.authority;R.replies.Seeded=nil;transition('warmup')
 elseif R.stage=='warmup'then
  if now()-R.since<2000 then return end
  if admit('before',R.seedAuthority)then transition('await-go')end
 elseif R.stage=='await-go'then
  local packet=R.replies.Go;if not packet then return end
  assert(packet.phaseToken==R.phase.phaseToken and packet.index==R.index,'walking Go phase differs');R.replies.Go=nil
  R.run=N.begin(R.player,R.phase,R.ids.routeOrigins[R.role]);transition('measure')
 elseif R.stage=='measure'then
  -- The only measured loop is N.sample, with scalar movement/state reads.
  if not N.sample(R.run)then return end
  local receipt=N.finish(R.run);R.run=nil
  local after=assert(F.snapshot(R.state),'walking replica changed during interval');F.project(after,R.before,R.role)
  receipt.before=R.before;receipt.after=after;emit('INTERVAL',receipt)
  request('Ended');transition('observed')
 elseif R.stage=='observed'then
  local packet=R.replies.Observed;if not packet then return end
  if admit('after',packet.authority)then R.replies.Observed=nil;transition('released')end
 elseif R.stage=='released'then
  local receipt=R.replies.Released;if not receipt then return end
  assert(receipt.token==R.ids.token and receipt.index==R.index and receipt.phaseToken==R.phase.phaseToken and receipt.ownedRemaining==0,'walking release phase differs')
  for _,container in ipairs(R.state.stores)do if container:getItems():size()~=0 then return end end
  assert(N.idle(R.player),'native actions survived walking release')
  emit('RELEASE',{receipt=receipt,absent=true,originalStash=A.originalProof(R.actor),actorLoad=assert(R.after.actorLoads[R.role])});R.replies.Released=nil;R.phases=R.phases+1
  if R.index<16 then R.index=R.index+1;R.phase=nil;R.state.phase=nil;place(R.ids.actorOrigins[R.role])else transition('await-done')end
 elseif R.stage=='await-done'then
  if not R.replies.Done then return end
  assert(R.replies.Done.cleanupTransport==F.cleanupTransport,'walking final cleanup transport differs')
  if not F.absent(R.ids)then return end
  if selection.kind=='mp'and R.player:getInventory():getItems():size()~=0 then return end
  R.placement={began=now(),target=R.position};transition('return')
 elseif R.stage=='return'then
  local position=U.place(R.player,R.placement,N.idle(R.player));if not position then return end
  if R.actor then A.restore(R.actor,false)end;local original=R.original and U.originalProof(R.player,R.original);N.restoreLock(R.player,R.lock);local ui=U.restore(R.player,R.ui)
  local lockProof=N.finishLockRestoration(R.player,R.lock)
  A.matchBaseline(R.actor,{rootIds=R.replies.Done.originalRootIds[R.role],equipment=R.replies.Done.originalEquipment[R.role]})
  emit('RESTORED',{original=original,originalEquipment=A.equipmentProof(R.actor),uiProof=ui,positionProof=position,lockProof=lockProof,ownedAbsent=true,authority=R.replies.Done})
  emit('COMPLETE',{phases=R.phases,restored=true});done=true
 end
end
local function reportAbortResult(restored,problem)
 if selection.kind=='mp'and R.prepareSent and not R.replies.Done then
  request('AbortRestored',{restored=restored,error=problem})
 else
  emit('FAIL',{stage='abort',restored=restored,error=problem or R.failure})
  print('[QUEUE_TEST] FAIL warehouse-walking client '..tostring(problem or R.failure))
 end
end
local function abortTick()
 -- Stop dispatching walks immediately, let the current native action finish,
 -- then close the observer before requesting authoritative owned-only cleanup.
 if not N.idle(R.player)then assert(now()-R.since<45000,'walking abort native drain timeout');return end
 R.profileCleanup=N.abortProfile(R.run)or R.profileCleanup;R.run=nil
 local requested=R.replies.AbortRequested;local reply=R.replies.Abortd or R.replies.Failed
 if not reply and R.replies.Done then reply={restored=true,cleanup=R.replies.Done,cleanupTransport=R.replies.Done.cleanupTransport}end
 if requested and not R.abortReady then R.abortReady=true;request('AbortReady');reply=R.replies.Abortd or R.replies.Failed end
 if R.prepareSent and not requested and not reply and not R.abortSent then R.abortSent=true;request('Abort',{error=R.failure});return end
 if R.prepareSent then
  if not reply then assert(now()-R.since<45000,'walking abort receipt timed out');return end
  assert(reply.restored and reply.cleanup,'walking authority refused safe cleanup: '..tostring(reply.cleanupError))
  assert(reply.cleanupTransport==F.cleanupTransport and reply.cleanup.cleanupTransport==F.cleanupTransport,'walking abort cleanup transport differs')
  local packet=R.ids
  if not packet or not packet.crates or #packet.crates==0 then packet=reply.cleanup end
  if packet.crates and not F.absent(packet)then return end
  if selection.kind=='mp'and R.actor and R.actor.detached and not R.actor.restored and R.player:getInventory():getItems():size()~=0 then return end
 end
 if not R.ui then emit('ABORT',{restored=true,authority=reply});reportAbortResult(true);done=true;return end
 if not R.abortPosition then R.abortPosition={began=now(),target=R.position or R.readyPosition}end
 local position=U.place(R.player,R.abortPosition,true);if not position then return end
 if R.actor then A.restore(R.actor,false)end;local original=R.original and U.originalProof(R.player,R.original);N.restoreLock(R.player,R.lock);local ui=U.restore(R.player,R.ui)
  local lockProof=N.finishLockRestoration(R.player,R.lock)
 if R.actor and reply and reply.cleanup and reply.cleanup.originalEquipment and reply.cleanup.originalEquipment[R.role]then
  A.matchBaseline(R.actor,{rootIds=reply.cleanup.originalRootIds[R.role],equipment=reply.cleanup.originalEquipment[R.role]})
 end
 emit('ABORT',{restored=true,authority=reply,original=original,originalEquipment=R.actor and A.equipmentProof(R.actor),uiProof=ui,positionProof=position,lockProof=lockProof,profileCleanup=R.profileCleanup});reportAbortResult(true);done=true
end
Events.OnTick.Add(function()
 if done or(selection.kind=='mp'and not isClient())or not isIngameState()then return end
 if not started then
  local player=getPlayer();if not player or not player:getSquare()or not getPlayerInventory(player:getPlayerNum())or not getPlayerLoot(player:getPlayerNum())then return end
  R.player=player;R.role=selection.kind=='sp'and'client1'or player:getUsername();assert(R.role=='client1'or R.role=='client2','unknown walking client role')
  started=true;R.since=now()
 end
 if R.replies.AbortRequested and R.stage~='abort'then R.failure=R.replies.AbortRequested.error;transition('abort')end
 local aborting=R.stage=='abort';local ok,problem=pcall(aborting and abortTick or tick)
 if not ok then
  if aborting then
   if R.lock then pcall(N.restoreLockGlobals,R.player,R.lock)end
   if R.ui then pcall(U.flags,R.player,R.ui)end
   emit('ABORT',{restored=false,error=tostring(problem),originalFailure=R.failure});reportAbortResult(false,tostring(problem));done=true
  else R.failure=tostring(problem);emit('ERROR',{stage=R.stage,error=R.failure});transition('abort')end
 end
end)
-- Fresh SP launch follows the same disposable creation route as storage-profile.
if selection.kind=='sp'then
 local entered,starting,worldEntered=false,false,false
 Events.OnGameStart.Add(function()worldEntered=true end)
 Events.OnMainMenuEnter.Add(function()entered=true end)
 Events.OnPreUIDraw.Add(function()
  if worldEntered and isIngameState()and isGamePaused()then setGameSpeed(1)end
  if not entered or starting or isIngameState()then return end;starting=true
  getWorld():setGameMode('Sandbox');getWorld():setWorld('WarehouseWalkingNative');getWorld():setMap('Muldraugh, KY')
  MainScreen.instance:setDefaultSandboxVars()
  for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2})do getSandboxOptions():getOptionByName(name):setValue(value)end
  getSandboxOptions():toLua()
  local current,active=ActiveMods.getById('currentGame'),getActivatedMods();current:getMods():clear()
  for i=0,active:size()-1 do current:getMods():add(active:get(i))end
  MainScreen.instance.createWorld=true
  MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'});MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 end)
end
