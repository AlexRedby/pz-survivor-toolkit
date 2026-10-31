-- Fresh menu-Host plus joining client, both exercising the installed live UI.
local selection=require 'QueueTestSelection'
if selection.kind~='mp'or selection.cases[1]~='peer-edits'then return end
local F=require 'WarehouseWorkloadFixture'
local U=require 'WarehouseWorkloadUI'
local N=require 'WarehouseWorkloadNative'
local JSON=require 'QueueHealthEvents'
local started,done=false,false
local R={stage='baseline',index=1,replies={},phases=0}
local function now()return getTimestampMs()end
local function transition(stage)R.stage=stage;R.since=now()end
local function emit(event,row)
 row=row or {};row.role=R.role;row.index=R.index;row.paneMode=F.modes[R.index];row.step=row.step or R.step
 row.token=R.ids and R.ids.token;row.phaseToken=R.phase and R.phase.phaseToken
 F.emit(event,row)
end
local function request(command,args)
 args=args or {};args.case='peer-edits';args.token=R.ids and R.ids.token;args.index=R.index
 args.phaseToken=R.phase and R.phase.phaseToken;args.step=R.step
 sendClientCommand(F.module,command,args)
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=F.module or done then return end
 R.replies[command]=args
end)
local function placeTarget(point)
 return {x=point.x+.5,y=point.y+.5,z=point.z,squareX=point.x,squareY=point.y,squareZ=point.z}
end
local function place(point)
 R.placement={began=now(),target=placeTarget(point)};transition('position')
end
local function stableUI()
 if R.baseline and now()-R.baseline.last<120 then return end
 local pages=U.pages(R.player);for _,page in ipairs(pages)do if not page or not page.inventoryPane then return end end
 U.normalize(R.player);local values={}
 for i,page in ipairs(pages)do if not page or not page.inventoryPane or not page.inventoryPane.inventory then return end
  local pane=page.inventoryPane
  values[i]={page=page,pane=pane,inventory=pane.inventory,x=page:getX(),y=page:getY(),w=page:getWidth(),h=page:getHeight(),px=pane:getX(),py=pane:getY(),pw=pane:getWidth(),ph=pane:getHeight()}
  if values[i].w<=0 or values[i].h<=0 or values[i].pw<=0 or values[i].ph<=0 then return end
 end
 local same=R.baseline~=nil
 if same then for i,value in ipairs(values)do for key,v in pairs(value)do if R.baseline.values[i][key]~=v then same=false end end end end
 if same then R.baseline.samples=R.baseline.samples+1 else R.baseline={samples=1,began=now()}end
 R.baseline.last=now();R.baseline.values=values
 return R.baseline.samples>=3
end
local function hide()
 R.hidden=N.hide(R.run);R.hiddenAt=now();R.hiddenSamples=0
end
local function sampleHidden()
 if not R.run or not R.hidden then return end
 local sample=N.hidden(R.run)
 assert(not sample.visible,'observer loot page became visible during native peer actions')
 if R.role=='client1'and R.step~='hidden-loot'then
  assert(sample.nativeBuilds==R.hidden.nativeBuilds,'hidden idle loot rebuilt native details rows')
  assert(sample.rowsPending,'hidden native details lost pending obligation')
 end
 R.hiddenSamples=R.hiddenSamples+1;R.lastHidden=sample
end
local function beginInitial()
 R.phase=assert(R.replies.Seeded.phase);R.replies.Seeded=nil;F.attachPhase(R.state,R.phase)
 R.run=N.startObservation(R.player,R.phase);R.run.state=R.state;R.run.step='initial';R.step='initial'
 R.waitEmitted=false;R.initialDiscovery=false;transition('initial')
end
local function readinessWait(native,aggregate)
 if R.waitEmitted or now()-R.since<5000 then return end
 R.waitEmitted=true
 local expected={};for id,endpoint in pairs(F.expected(R.phase,R.step))do expected[#expected+1]={id=id,endpoint=endpoint}end
 table.sort(expected,function(a,b)return a.id<b.id end)
 local row={role=R.role,token=R.ids.token,index=R.index,paneMode=R.phase.mode,phaseToken=R.phase.phaseToken,
  step=R.step,elapsedMs=now()-R.since,nativeReady=native~=nil,aggregateReady=aggregate~=nil,
  expected=expected,snapshot=F.snapshot(R.state),discovery=N.diagnostics(R.run)}
 -- Diagnostics deliberately use a distinct prefix: they are neither lifecycle
 -- receipts nor evidence that a readiness gate passed.
 print('[WAREHOUSE_WORKLOAD_WAIT] '..JSON.encode(row))
end
local function checkProjection(native,authority)
 if not authority then return end
 assert(native.token==authority.token and native.phaseToken==authority.phaseToken and #native.crates==#authority.crates,'authority/client workload identity differs')
 for i,crate in ipairs(native.crates)do local expected=authority.crates[i]
  assert(crate.id==expected.id and crate.capacity==expected.capacity and N.sameIds(crate.itemIds,expected.itemIds),'replicated crate IDs/endpoints differ from authority')
 end
 local expected=assert(authority.rootIds[R.role]);assert(N.sameIds(native.rootIds[R.role],expected),'replicated own root IDs differ from authority')
 local physical={};for _,item in ipairs(authority.items)do if item.endpoint==R.role or string.sub(item.endpoint,1,5)=='crate'then physical[item.id]=item end end
 local n=0;for _,item in ipairs(native.items)do local expectedItem=physical[item.id]
  assert(expectedItem and item.ft==expectedItem.ft and item.endpoint==expectedItem.endpoint and item.count==1 and item.key==expectedItem.key and item.cat==expectedItem.cat,'replicated item payload differs from authority');n=n+1
 end
 local expectedCount=0;for _ in pairs(physical)do expectedCount=expectedCount+1 end;assert(n==expectedCount,'replicated projected item count differs from authority')
end
local function observerReady(authority)
 local native=F.native(R.state,R.step);local aggregateBefore=N.aggregateObservation(R.run)
 readinessWait(native,aggregateBefore.fresh and aggregateBefore or nil);if not native then return end
 checkProjection(native,authority)
 if R.role=='client1'and R.step=='peer-transfer'then
  local target=R.ids.actorOrigin;local pos=U.position(R.player)
  if not N.idle(R.player)or math.floor(pos.x)~=target.x or math.floor(pos.y)~=target.y then return end
  assert(R.walked and R.walked.progress,'hidden observer never walked through the native aisle')
 end
 -- Native transfers briefly hold their destination tab. Keep the loot hidden
 -- and let that hold expire before asking the real button to select a view.
 if not N.reopenReady(R.run)then return end
 if R.hidden then sampleHidden();emit('HIDDEN',{before=R.hidden,after=R.lastHidden,samples=R.hiddenSamples,elapsedMs=now()-R.hiddenAt,walker=R.walked})end
 local reopened,aggregate=N.reopen(R.run,aggregateBefore)
 if R.step=='peer-replace'and R.role=='client1'then
  local ids={};for _,id in ipairs(reopened.rowIds)do ids[id]=true end
  assert(ids[R.phase.replacementId]and not ids[R.phase.replacementSourceId],'same-count peer replacement retained stale native rows')
 end
 if R.step=='peer-craft'and R.role=='client1'then
  local ids={};for _,id in ipairs(reopened.rowIds)do ids[id]=true end
  assert(not ids[R.phase.craftInputId],'consumed native crafting input survived reopened rows')
 end
 emit('SNAPSHOT',{native=native,authority=authority,reopen=reopened,aggregateBefore=aggregateBefore,aggregateProof=aggregate})
 if R.step=='peer-craft'then N.closeCraft(R.run)end
 if R.step=='peer-craft'then
  -- Bind the exact physical quick source while visible; its callback must later
  -- consume current physical stock while the loot owner remains fully hidden.
  local loot=getPlayerLoot(R.player:getPlayerNum());loot:setNewContainer(R.state.stores[5])
 end
 hide();request('Seen');transition('await-go');return true
end
local function dispatch(go)
 assert(go.phase.phaseToken==R.phase.phaseToken and go.actor==(go.step=='hidden-loot'and'client1'or'client2'),'wrong native workload dispatch')
 F.attachPhase(R.state,go.phase);R.phase=go.phase;R.run.phase=go.phase;R.step=go.step;R.run.step=go.step
 R.substage=0;R.acted=false;R.walked=nil;R.go=go;R.waitEmitted=false
 if R.role=='client1'and R.step=='peer-transfer'then
  R.walked={from=U.position(R.player),target=R.ids.walkTarget,progress=false,returned=false}
  R.walkAction=N.walk(R.run,R.ids.walkTarget.x,R.ids.walkTarget.y,R.ids.walkTarget.z)
 elseif R.role==go.actor and R.step=='hidden-loot'then R.quick=N.quick(R.run)
 end
 transition('working')
end
local function nativeActor()
 local run=R.run;local p=R.phase;local root=R.player:getInventory();local stores=R.state.stores
 if not N.idle(R.player)then return end
 if R.step=='peer-transfer'then
  if R.substage==0 then N.transfer(run,p.transferId,stores[1],root);R.substage=1
  elseif R.substage==1 then if not root:getItemById(p.transferId)then return end;N.transfer(run,p.transferId,root,stores[2]);R.substage=2
  elseif not stores[2]:getItemById(p.transferId)then return else return true end
 elseif R.step=='peer-replace'then
  if R.substage==0 then N.transfer(run,p.replacementSourceId,stores[3],root);R.substage=1
  elseif R.substage==1 then if not root:getItemById(p.replacementSourceId)then return end;N.transfer(run,p.replacementId,root,stores[3]);R.substage=2
  elseif not stores[3]:getItemById(p.replacementId)then return else return true end
 elseif R.step=='peer-craft'then
  if R.substage==0 then
   local point=R.ids.crates[4];N.walk(run,point.x,R.ids.origin.y,R.ids.origin.z);R.substage=1
  elseif R.substage==1 then N.craft(run);R.substage=2
  else
   if stores[4]:getItemById(p.craftInputId)or root:getItemById(p.craftInputId)then return end
   local count=0;for i=0,root:getItems():size()-1 do local item=root:getItems():get(i)
    if item:getFullType()==p.outputType and not R.original.items[item:getID()]then count=count+1 end
   end
   if count~=4 then return end;return true
  end
 elseif R.step=='hidden-loot'then return root:getItemById(p.quickId)~=nil and not stores[5]:getItemById(p.quickId)end
end
local function walkObserver()
 if not R.walked then return end
 local pos=U.position(R.player);local action=R.walkAction
 if action and action:isStarted()and action:getJobDelta()>0 then R.walked.progress=true end
 if math.abs(pos.x-R.walked.from.x)>.25 then R.walked.progress=true end
 if N.idle(R.player)and not R.walked.returned then
  R.walked.reached=pos;R.walked.returned=true;local target=R.ids.actorOrigin
  R.walkAction=N.walk(R.run,target.x,target.y,target.z)
 end
end
local function releaseReady(receipt)
 assert(receipt.token==R.ids.token and receipt.index==R.index and receipt.ownedRemaining==0,'wrong native workload release')
 for _,id in ipairs(receipt.removedIds)do local _,_,count=F.find(R.state,id);if count~=0 then return end end
 for _,container in ipairs(R.state.stores)do if container:getItems():size()~=0 then return end end
 assert(N.idle(R.player),'native actions survived workload release')
 N.closeCraft(R.run);R.run=nil;R.hidden=nil
 local original=U.originalProof(R.player,R.original)
 emit('RELEASE',{receipt=receipt,absent=true,original=original});R.phases=R.phases+1
 if R.index==1 then R.index=2;R.phase=nil;place(R.ids.actorOrigin)else transition('await-done')end
 return true
end
local function tick()
 assert(not R.replies.Failed,R.replies.Failed and R.replies.Failed.error)
 assert(now()-R.since<90000,'native warehouse client stage timeout: '..R.stage)
 if R.run then N.observe(R.run)end
 if R.stage=='baseline'then
  if not N.idle(R.player)or not stableUI()then return end
  R.ui=U.save(R.player);R.original=U.original(R.player);R.position=U.position(R.player)
  emit('BASELINE',{original=U.originalProof(R.player,R.original),position=R.position,stableSamples=R.baseline.samples})
  U.protect(R.player,R.ui)
  request('Prepare');transition('prepared')
 elseif R.stage=='prepared'then
  local packet=R.replies.Prepared;if not packet then return end
  assert(packet.role==R.role,'prepared native role differs');R.ids=packet.ids
  R.state=F.resolve(R.player,R.ids,R.role);if not R.state then return end
  emit('SETUP',{ids=R.ids});place(R.ids.actorOrigin)
 elseif R.stage=='position'then
  local proof=U.place(R.player,R.placement,N.idle(R.player));if not proof then return end
  U.configure(R.player,F.modes[R.index]);R.configuredAt=now();R.placementProof=proof;transition('configured')
 elseif R.stage=='configured'then
  if now()-R.configuredAt<300 then return end
  local pages=U.pages(R.player);pages[1]:setNewContainer(R.player:getInventory());pages[1]:refreshBackpacks();pages[2]:refreshBackpacks()
  if not N.selectAggregate(R.player)then return end
  emit('MODE',{placement=R.placementProof});request('Ready');transition('seeded')
 elseif R.stage=='seeded'then if R.replies.Seeded then beginInitial()end
 elseif R.stage=='initial'then
  local native=F.native(R.state,'initial')
  -- Seeded physical replicas must precede the single setup discovery. The
  -- aggregate was selected before the server seed and can still be empty.
  if native and not R.initialDiscovery then R.initialDiscovery=true;hide()end
  local aggregate=N.aggregateProof(R.run)
  readinessWait(native,aggregate);if not native or not aggregate then return end
  local contains={};for _,id in ipairs(aggregate.actualIds)do contains[id]=true end
  assert(contains[R.phase.replacementSourceId]and contains[R.phase.craftInputId],'observer setup missed native peer replacement/craft source')
  -- Peer effects must arrive through ordinary native movement/network updates
  -- until the actual reopen callback; setup discovery is never retried.
  observerReady(nil)
 elseif R.stage=='await-go'then
  if R.replies.Go then local go=R.replies.Go;R.replies.Go=nil;dispatch(go)
  elseif R.replies.Released then local receipt=R.replies.Released;if releaseReady(receipt)then R.replies.Released=nil end end
 elseif R.stage=='working'then
  sampleHidden();walkObserver()
  if R.role==R.go.actor and not R.acted and nativeActor()then
   R.acted=true;emit('ACTIONS',{records=N.actionProof(R.run),craftDispatch=R.step=='peer-craft'and R.run.craftDispatch or nil,quick=R.step=='hidden-loot'and R.quick or nil});request('Acted')
  end
  local observed=R.replies.Observed
  if observed then
   assert(observed.step==R.step and observed.phase.phaseToken==R.phase.phaseToken,'wrong native workload observation')
   R.phase=observed.phase;F.attachPhase(R.state,R.phase);R.run.phase=R.phase
   if observerReady(observed.receipt)then R.replies.Observed=nil end
  end
 elseif R.stage=='await-done'then
  if not R.replies.Done or not F.absent(R.ids)then return end
  R.placement={began=now(),target=R.position};transition('return')
 elseif R.stage=='return'then
  local position=U.place(R.player,R.placement,N.idle(R.player));if not position then return end
  local actual=U.originalProof(R.player,R.original);local ui=U.restore(R.player,R.ui)
  emit('RESTORED',{original=actual,actual=actual,uiProof=ui,positionProof=position,ownedAbsent=true,authority=R.replies.Done})
  emit('COMPLETE',{phases=R.phases,restored=true});done=true
 end
end
local function abortTick()
 local requested=R.replies.AbortRequested
 local reply=R.replies.Abortd or R.replies.Failed
 if not N.idle(R.player)then return end
 if R.run then N.closeCraft(R.run);R.run=nil end
 R.hidden=nil
 if requested and not R.abortReady then R.abortReady=true;request('AbortReady')end
 if R.ids and not requested and not reply and not R.abortSent then
  R.abortSent=true;request('Abort',{error=R.failure});return
 end
 if R.ids then
  if not reply then assert(now()-R.since<45000,'native abort receipt timed out');return end
  assert(reply.restored and reply.cleanup,'server refused owned-only workload abort: '..tostring(reply.cleanupError))
  if not F.absent(R.ids)then return end
 end
 if not R.ui then emit('ABORT',{restored=true,authority=reply});done=true;return end
 if not R.abortPosition then R.abortPosition={began=now(),target=R.position}end
 local position=U.place(R.player,R.abortPosition,true);if not position then return end
 local actual=U.originalProof(R.player,R.original);local ui=U.restore(R.player,R.ui)
 emit('ABORT',{restored=true,authority=reply,actual=actual,uiProof=ui,positionProof=position});done=true
end
Events.OnTick.Add(function()
 if done or not isClient()or not isIngameState()then return end
 if not started then
  local player=getPlayer();if not player or not player:getSquare()or not getPlayerInventory(player:getPlayerNum())or not getPlayerLoot(player:getPlayerNum())then return end
  R.player=player;R.role=player:getUsername();assert(R.role=='client1'or R.role=='client2','unknown native warehouse role')
  started=true;R.since=now()
 end
 if R.replies.AbortRequested and R.stage~='abort'then
  R.failure=R.replies.AbortRequested.error or 'peer requested native workload abort';transition('abort')
 end
 local aborting=R.stage=='abort';local ok,problem=pcall(aborting and abortTick or tick)
 if not ok then
  if aborting then
   if R.ui then pcall(U.flags,R.player,R.ui)end
   emit('ABORT',{restored=false,error=tostring(problem),originalFailure=R.failure});done=true
  else
   R.failure=tostring(problem);emit('FAIL',{stage=R.stage,error=R.failure})
   print('[QUEUE_TEST] FAIL warehouse-workload client '..R.failure);transition('abort')
  end
 end
end)
