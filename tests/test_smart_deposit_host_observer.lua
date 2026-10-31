-- Exercise the fixture's observers, including a transaction faster than one UI tick.
local path=ProjectRoot..'/tests/native_queue/contributions/smart-deposit/ZZSmartDepositHost.lua'
local file=assert(io.open(path,'r'));local source=file:read('*a');file:close()
local first=assert(source:find('local function endpoint(container)',1,true),'deposit endpoint observer missing')
local last=assert(source:find('local function configureMode()',first,true),'deposit observer boundary missing')
local luaRawget=rawget
local function kahluaRawget(owner,key)
 local value=luaRawget(owner,key);if value~=nil then return value end
 local meta=getmetatable(owner);return meta and kahluaRawget(meta,key)or nil
end
local environment=setmetatable({rawget=kahluaRawget},{__index=function(_,key)if key~='next'then return _G[key]end end})
assert(environment.next==nil,'observer regression must model Kahlua without next')
local observerChunk=assert(loadstring([[
return function(context)
 local state,expected=context.state,context.expected
 local actions,actionSet,observers,addObserver,observerFailure={},{},{},nil,nil
 local function pack(...)return {n=select('#',...),...}end
]]..source:sub(first,last-1)..[[
 return {begin=observeAdds,restore=restoreObservers,
  records=function()return actions end,failure=function()return observerFailure end}
end
]],'Smart Deposit native observers'))
setfenv(observerChunk,environment);local factory=observerChunk()
local function pack(...)return {n=select('#',...),...}end
local function tuple(actual,label,...)
 local expected=pack(...);assert(actual.n==expected.n,label..': return/argument arity changed')
 for i=1,expected.n do assert(actual[i]==expected[i],label..': value '..i..' changed')end
end
local function setup(nativeStop)
 local root={getType=function()return 'inventorymale'end};local crate={getType=function()return 'crate'end}
 local player={getInventory=function()return root end};local item={getID=function()return 42 end}
 local observed={calls={},duration=-1,durationReads=0};local native={}
 function native:isStarted()return self.running end
 function native:getJobDelta()return 0 end
 function native:start(...)
  observed.calls.start=pack(...);self.action={};self.running=true;self.transactionId=73;observed.duration=50
  return 'started',nil,3,nil
 end
 function native:update(...)
  observed.calls.update=pack(...)
  -- Native update sees Done before its duration-initialization branch.
  self.maxTime=0;return 'updated',nil,5,nil
 end
 function native:perform(...)
  observed.calls.perform=pack(...);observed.duration=-1
  return 'performed',nil,7,nil
 end
 function native:stop(...)
  observed.calls.stop=pack(...);if nativeStop then return nativeStop(...)end
  return 'stopped',nil,11,nil
 end
 native.__index=native
 local action=setmetatable({Type='ISInventoryTransferAction',item=item,srcContainer=root,destContainer=crate,maxTime=-1,queueList={{time=-1}}},native)
 getPlayer=function()return player end
 getItemTransactionDuration=function(id)
  assert(id==73,'observer queried foreign transaction');observed.durationReads=observed.durationReads+1;return observed.duration
 end
 local nativeAdd=function(value,...)
  assert(value==action,'observer replaced native action');observed.calls.add=pack(...)
  tuple(pack(value:start('begin',nil,13)),'native start return','started',nil,3,nil)
  return 'queued',nil,17,nil
 end
 ISTimedActionQueue={add=nativeAdd}
 local api=factory({state={stores={crate}},expected={[item]=crate}})
 return api,action,native,observed,nativeAdd
end
local api,action,native,observed,nativeAdd=setup()
api.begin(false)
tuple(pack(ISTimedActionQueue.add(action,'dispatch',nil,19)),'native add return','queued',nil,17,nil)
tuple(observed.calls.add,'native add arguments','dispatch',nil,19)
tuple(observed.calls.start,'native start arguments','begin',nil,13)
assert(action.maxTime==-1 and action.queueList[1].time==-1,'observer changed initial native timing')
tuple(pack(action:update('tick',nil,23)),'native update return','updated',nil,5,nil)
tuple(observed.calls.update,'native update arguments','tick',nil,23)
tuple(pack(action:perform('finish',nil,29)),'native perform return','performed',nil,7,nil)
tuple(observed.calls.perform,'native perform arguments','finish',nil,29)
assert(not api.failure(),'valid native lifecycle failed its observer')
local records=api.records();assert(#records==1,'native action was omitted or duplicated');local row=records[1]
assert(row.action==action and row.id==42 and row.source=='root'and row.destination=='crate1','observer changed native identity/endpoints')
assert(row.initialDuration==-1 and row.queueTime==-1 and row.lastDuration==0 and action.maxTime==0,'observer rewrote native timing')
assert(row.transactionId==73 and row.transactionDuration==50 and row.duration==50 and row.lastTransactionDuration==-1,'Done transaction duration was lost before native removal')
assert(row.durationSource=='native-transaction-duration'and observed.durationReads>0,'positive duration did not come from native transaction API')
assert(row.observedMaxTime==nil and row.progressSamples==0,'fast-Done test accidentally observed positive maxTime/progress')
assert(row.started and row.completed and row.startCalls==1 and row.updateCalls==1 and row.performCalls==1 and row.stopCalls==0,'native callback witnesses differ')
api.restore();assert(ISTimedActionQueue.add==nativeAdd,'native add observer survived restoration')
for _,key in ipairs({'start','update','perform','stop'})do assert(rawget(action,key)==nil and action[key]==native[key],'inherited native method was not restored: '..key)end
assert(environment.rawget(action,'update')==native.update,'regression did not model Kahlua inherited rawget')
local laterUpdate=function()return 'later native update'end;native.update=laterUpdate
assert(action.update==laterUpdate,'restoration materialized an inherited callback and hid later class updates')
print('PASS Smart Deposit Host observer retains fast-Done duration without changing native timing or return arity')

-- A cancelled action delegates stop unchanged; a native error retains its identity.
api,action,native,observed,nativeAdd=setup()
api.begin(false);ISTimedActionQueue.add(action)
tuple(pack(action:stop('cancel',nil,31)),'native stop return','stopped',nil,11,nil)
tuple(observed.calls.stop,'native stop arguments','cancel',nil,31)
assert(api.records()[1].stopCalls==1 and not api.records()[1].completed,'stop was misreported as successful completion')
api.restore()
local nativeError={message='native stop failure'}
api,action,native,observed,nativeAdd=setup(function()error(nativeError,0)end)
api.begin(false);ISTimedActionQueue.add(action)
local ok,problem=pcall(action.stop,action)
assert(not ok and problem==nativeError,'observer changed native error identity')
api.restore()
print('PASS Smart Deposit Host stop observer preserves cancellation and native errors')

-- Failed full admission must remain observable without suppressing native add.
api,action,native,observed,nativeAdd=setup()
api.begin(true)
tuple(pack(ISTimedActionQueue.add(action,'rejected',nil,37)),'rejected native add return','queued',nil,17,nil)
tuple(observed.calls.add,'rejected native add arguments','rejected',nil,37)
assert(api.failure()=='fully rejected native drop queued an action','fully rejected batch queued work without failing its observer')
assert(#api.records()==0,'rejected batch was counted as a valid transfer')
ok=pcall(function()assert(not api.failure(),api.failure())end)
assert(not ok,'native full-drop failure gate accepted unexpected queued work')
api.restore();assert(ISTimedActionQueue.add==nativeAdd,'rejected add observer survived restoration')
for _,key in ipairs({'start','update','perform','stop'})do assert(rawget(action,key)==nil,'rejected action was unexpectedly instrumented')end
print('PASS Smart Deposit Host full rejection fails on queued work while preserving native delegation')

-- Native B42 worn slots are ItemBodyLocation userdata, not JSON values.
first=assert(source:find('local function arrayIds(values)',1,true),'original inventory proof missing')
last=assert(source:find('local function nativeRows(q)',first,true),'original inventory proof boundary missing')
local originalFactory=assert(loadstring([[
return function(context)
 local F=context.F
 local initial,initialEquipment=context.initial,context.equipment
]]..source:sub(first,last-1)..[[
 return originalProof
end
]],'Smart Deposit original identity proof'))()
local location=newproxy(true);getmetatable(location).__tostring=function()return 'base:Shirt'end
local originalItem={getID=function()return 101 end};local originalItems={[101]=originalItem}
local wornEntry={getLocation=function()return location end,getItem=function()return originalItem end}
local wornList={size=function()return 1 end,get=function(_,i)assert(i==0);return wornEntry end}
local player={getPrimaryHandItem=function()return originalItem end,getSecondaryHandItem=function()return nil end,getWornItems=function()return wornList end}
getPlayer=function()return player end
local proof=originalFactory({F={originalItems=function()return originalItems end},initial=originalItems,
 equipment={primary=originalItem,worn={{location=location,item=originalItem}}}})
local identity=proof()
assert(identity.worn[1].location=='base:Shirt'and type(identity.worn[1].location)=='string','native body location leaked into identity receipt')
local JSON=dofile(ProjectRoot..'/tests/native_queue/health/shared/QueueHealthEvents.lua')
local encoded=JSON.encode(identity)
assert(encoded:find('"location":"base:Shirt"',1,true),'native body location proof is not serializable')
local differentLocation=newproxy(true);getmetatable(differentLocation).__tostring=getmetatable(location).__tostring
wornEntry.getLocation=function()return differentLocation end
ok=pcall(proof)
assert(not ok,'serializing a slot name weakened native worn-location identity verification')
print('PASS Smart Deposit Host identity receipt serializes native body locations while retaining exact identity checks')

-- Native AddInventoryItemToContainer packets deserialize owned replicas by ID.
local sharedFile=assert(io.open(ProjectRoot..'/tests/native_queue/contributions/smart-deposit/QueueSmartDepositHostFixture.lua','r'))
local sharedSource=sharedFile:read('*a');sharedFile:close()
local function between(text,from,to)
 local at=assert(text:find(from,1,true),'fixture source boundary missing: '..from)
 local finish=assert(text:find(to,at+#from,true),'fixture source boundary missing: '..to)
 return text:sub(at,finish-1)
end
local find=assert(loadstring('local F={}\n'
 ..between(sharedSource,'local function array(list)','local function finite(value)')
 ..between(sharedSource,'function F.find(s,id)','function F.phaseIds(phase)')..'\nreturn F.find','Smart Deposit native identity scan'))()
local effectChunk=assert(loadstring([[
return function(context)
 local state,samples,expected,initial=context.state,context.samples,context.expected,context.initial
 local phaseProperties,phaseInitialEndpoints=context.properties,context.endpoints
 local F={find=context.find}
]]..between(source,'local function shallow(value)','local function queue()')
 ..between(source,'local function endpoint(container)','local function restoreAdd()')
 ..between(source,'local function localEffectReady()','local function transferDiagnostic()')..[[
 return localEffectReady
end
]],'Smart Deposit replicated effects'))
setfenv(effectChunk,environment);local effectFactory=effectChunk()
local function nativeList(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
local function ownedItem(id,kind,name,weight)
 return {id=id,kind=kind,name=name,weight=weight,getID=function(self)return self.id end,getFullType=function(self)return self.kind end,
  getName=function(self)return self.name end,getUnequippedWeight=function(self)return self.weight end}
end
local function replicatedEffect()
 local samples,properties,endpoints={},{},{}
 for i=1,9 do
  local kind=i<=4 and 'Base.Nails'or i==5 and 'Base.Screws'or i==6 and 'Base.Nails'or 'Base.Apple'
  local name=i<=4 and 'Deposit '..i or kind;local weight=i<=6 and .05 or 9.8
  properties[i]={id=i,type=kind,name=name,weight=weight};endpoints[i]=i<=4 and 'root'or i==5 and 'crate2'or i==6 and 'crate3'or 'crate'..(i-6)
  if i<=4 then samples[i]=ownedItem(i,kind,name,weight)end
 end
 local function replica(id)local p=properties[id];return ownedItem(id,p.type,p.name,p.weight)end
 local original=ownedItem(900,'Base.Tshirt','Original',.2)
 local contents={{original,replica(4)},{replica(3),replica(7)},{replica(2),replica(5),replica(8)},{replica(1),replica(6),replica(9)}}
 local stores={};local root
 for slot,values in ipairs(contents)do local container={getItems=function()return nativeList(values)end,getType=function()return 'crate'end}
  if slot==1 then root=container else stores[slot-1]=container end
 end
 local player={getInventory=function()return root end};getPlayer=function()return player end
 local expected={[samples[1]]=stores[3],[samples[2]]=stores[2],[samples[3]]=stores[1]}
 local ready=effectFactory({state={player=player,stores=stores},samples=samples,expected=expected,initial={[900]=original},properties=properties,endpoints=endpoints,find=find})
 return ready,contents,samples
end
local ready,contents,oldSamples=replicatedEffect()
assert(contents[4][1]~=oldSamples[1]and ready(),'same-ID deserialized replicas did not satisfy exact native effect proof')
contents[1][2]=oldSamples[4]
assert(ready(),'unchanged owned root object did not satisfy native effect proof')
ready,contents=replicatedEffect();contents[1][#contents[1]+1]=contents[4][1]
assert(not ready(),'duplicate sample identity passed native effect proof')
ready,contents=replicatedEffect();contents[2][#contents[2]+1]=ownedItem(999,'Base.Nails','Foreign',.05)
assert(not ready(),'foreign crate content passed native effect proof')
ready,contents=replicatedEffect();contents[2][1],contents[4][1]=contents[4][1],contents[2][1]
assert(not ready(),'sample at wrong crate endpoint passed native effect proof')
for _,field in ipairs({'id','kind','name','weight'})do
 ready,contents=replicatedEffect();local replica=contents[4][1]
 replica[field]=field=='id'and 998 or field=='weight'and .06 or 'Changed'
 assert(not ready(),'changed replica '..field..' passed native effect proof')
end
ready,contents=replicatedEffect();contents[1][1]=ownedItem(900,'Base.Tshirt','Original',.2)
assert(not ready(),'replacement of untouched original root object passed native effect proof')
print('PASS Smart Deposit Host effects accept exact replicated owned identities and reject duplicates, foreign cohorts, wrong endpoints/properties and replaced originals')

-- The final table-constructor expression expands every return value in Lua.
-- F.find returns item, endpoint and count; only its item belongs in a drag list.
local batchBuilder=assert(loadstring('return function(F,state,samples,current)\n'
 ..between(source,'local overflow=assert(F.find(state,samples[4]:getID()))','fullBefore=F.snapshot(state)')
 ..'\nreturn batch\nend','Smart Deposit full rejection batch'))()
local function nativeItem(id)
 local item=newproxy(true);getmetatable(item).__index={getID=function()return id end};return item
end
local replicas={[4]=nativeItem(4),[11]=nativeItem(11),[12]=nativeItem(12),[13]=nativeItem(13)}
local requested={};local fixtureState={token='owned-phase'}
local batch=batchBuilder({find=function(s,id)
 assert(s==fixtureState,'full batch resolved another fixture');requested[#requested+1]=id
 return assert(replicas[id]),'root',1
end},fixtureState,{[4]=nativeItem(4)},{extraIds={11,12,13}})
assert(#batch==4 and #requested==4,'full rejection batch expanded endpoint/count metadata into dragged items')
for i,id in ipairs({4,11,12,13})do
 assert(requested[i]==id and batch[i]==replicas[id]and type(batch[i])=='userdata'and batch[i]:getID()==id,
  'full rejection batch omitted, reordered or contaminated an actual owned item')
end
print('PASS Smart Deposit Host full rejection batch contains exactly four native items from three-value identity lookups')

-- UI mode entry mutates once; discovery polls the newly active native owners.
local modeFactory=assert(loadstring([[
return function(context)
 local index,state=context.index,context.state
 local modeLifecycle,sourcePane,loot,pane,target,button,order=context.lifecycle
 local Proximity=context.Proximity
 local clearDrag,idle,geometry,now=context.clearDrag,context.idle,context.geometry,context.now
]]..between(source,'local function configureMode()','local function modeDiagnostic()')..[[
 return {configure=configureMode,discover=discoverMode,result=function()return order,sourcePane,loot,button end}
end
]],'Smart Deposit mode lifecycle'))()
local cleanClass,vanillaClass={},{}
CleanUI_Clean_ISInventoryPane,CleanUI_Vanilla_ISInventoryPane=cleanClass,vanillaClass
local function modeSetup()
 local ctx={index=2,clock=0,toggles=0,clears=0,geometryCalls=0,refreshes=0,clicked=0,lifecycle={}}
 local function container(kind)return {getType=function()return kind end}end
 local root,target,floor=container('inventorymale'),container('proximityInv'),container('floor')
 ctx.state={stores={container('crate'),container('crate'),container('crate')}}
 local function page(class)
  local q=setmetatable({setMode=function()end,setVisible=function()end,clearMaxDrawHeight=function()end,setYScroll=function()end},class)
  local p={inventoryPane=q,backpacks={},setPinned=function()end,setVisible=function()end,clearMaxDrawHeight=function()end,
   setNewContainer=function(self,value)self.inventory=value;self.inventoryPane.inventory=value end,
   refreshBackpacks=function(self)ctx.refreshes=ctx.refreshes+1;self.backpacks={{inventory=floor}}end,
   onBackpackClick=function(self,value)ctx.clicked=ctx.clicked+1;self.inventory=value.inventory;self.inventoryPane.inventory=value.inventory end}
  return p
 end
 ctx.oldInventory,ctx.oldLoot=page(cleanClass),page(cleanClass)
 ctx.inventory,ctx.loot=ctx.oldInventory,ctx.oldLoot
 CleanUI_setCleanInventoryUIEnabled=function(enabled)
  assert(enabled==false,'wrong native mode requested');ctx.toggles=ctx.toggles+1
  ISInventoryPane=vanillaClass;ctx.inventory,ctx.loot=page(vanillaClass),page(vanillaClass)
 end
 getPlayerInventory=function()return ctx.inventory end;getPlayerLoot=function()return ctx.loot end
 getPlayer=function()return {getInventory=function()return root end}end
 getCore=function()return {getScreenWidth=function()return 1280 end,getScreenHeight=function()return 900 end}end
 ctx.now=function()return ctx.clock end;ctx.clearDrag=function()ctx.clears=ctx.clears+1 end;ctx.idle=function()return true end
 ctx.geometry=function()ctx.geometryCalls=ctx.geometryCalls+1 end;ctx.Proximity={GetItemContainer=function()return target end}
 ctx.publish=function()
  ctx.loot.backpacks={{inventory=target},{inventory=ctx.state.stores[3]},{inventory=ctx.state.stores[1]},{inventory=ctx.state.stores[2]},{inventory=floor}}
 end
 return ctx,modeFactory(ctx),target
end
local ctx,mode,target=modeSetup();mode.configure()
assert(ctx.toggles==1 and ctx.geometryCalls==2 and ctx.clears==1,'UI mode configuration was omitted or repeated')
assert(ctx.inventory~=ctx.oldInventory and ctx.loot~=ctx.oldLoot,'test did not recreate native owners')
assert(not mode.discover()and ctx.refreshes==0,'discovery refreshed before native UI had one update')
ctx.clock=200;assert(not mode.discover()and ctx.refreshes==2,'discovery must refresh each active native owner exactly once')
for i=1,5 do ctx.clock=200+i;assert(not mode.discover(),'missing owned buttons passed discovery')end
assert(ctx.refreshes==2 and ctx.toggles==1,'discovery polling rebuilt or refreshed native owners repeatedly')
ctx.publish();assert(mode.discover(),'three real owned crates and target were not discovered')
local order,activePane,activeLoot,selectedButton=mode.result()
assert(order[1]==3 and order[2]==1 and order[3]==2 and #order==3,'discovery replaced native container order')
assert(activePane==ctx.inventory.inventoryPane and activeLoot==ctx.loot and selectedButton.inventory==target and ctx.clicked==1,'discovery used retired owners or skipped native selection')
ctx.loot.backpacks[4]=nil;assert(not mode.discover(),'missing third owned crate passed discovery')
ctx.publish();ctx.loot.backpacks[#ctx.loot.backpacks+1]={inventory={getType=function()return 'foreign storage'end}}
ok=pcall(mode.discover);assert(not ok,'foreign nearby storage passed native discovery')
print('PASS Smart Deposit Host mode configuration runs once; delayed discovery uses active owners without rebuild loops and retains exact native crate order')

-- A float teleport can floor the centre; exact coordinates and both squares
-- must settle before the next mode can reach the authority/UI stages.
local positionFactory=assert(loadstring([[
return function(context)
 local ids,replies,index,modeLifecycle,lastModeDiagnostic=context.ids,{},2,nil,nil
 local motionProbe,positionTransition,position,returnAt=nil,nil,context.position,nil
 local now,idle,clearDrag,transition=context.now,context.idle,context.clearDrag,context.transition
]]..between(source,'local function shallow(value)','local function queue()')
 ..between(source,'local function readPosition()','local function setupTick()')..[[
 return {begin=beginModePosition,ready=modePositionReady,lifecycle=function()return modeLifecycle end,
  returnBegin=returnPosition,returnReady=positionReturnReady,setOriginal=function(value)position=value end}
end
]],'Smart Deposit mode origin barrier'))()
local clock,teleports,actor=0,0,{x=19.2,y=30.1,z=0,squareX=19,squareY=30,squareZ=0,moving=false,deferredX=.012,deferredY=.009}
Vector2={new=function()return {getX=function(self)return self.x end,getY=function(self)return self.y end}end}
local square={getX=function()return actor.squareX end,getY=function()return actor.squareY end,getZ=function()return actor.squareZ end}
local nativePlayer={getX=function()return actor.x end,getY=function()return actor.y end,getZ=function()return actor.z end,
 getSquare=function()return square end,getCurrentSquare=function()return square end,isPlayerMoving=function()return actor.moving end,getPath2=function()return nil end,
 getDeferredMovement=function(_,value)value.x=actor.deferredX;value.y=actor.deferredY;return value end,getAnimationStateName=function()return 'actions'end,
 teleportTo=function(_,x,y,z)teleports=teleports+1;actor.x=math.floor(x);actor.y=math.floor(y);actor.z=z end,
 setForceX=function(_,x)actor.x=x end,setForceY=function(_,y)actor.y=y end,setZ=function(_,z)actor.z=z end}
getPlayer=function()return nativePlayer end
local transitioned
local placement=positionFactory({ids={origin={x=20,y=30,z=0}},now=function()return clock end,idle=function()return true end,
 clearDrag=function()end,transition=function(stage)transitioned=stage end})
placement.begin();assert(transitioned=='mode-position'and teleports==0,'mode origin teleported before deferred native animation settled')
assert(not placement.ready(),'mode origin accepted deferred native movement')
clock=100;actor.x=actor.x+.01171875;actor.y=actor.y+.0087890625
assert(not placement.ready()and teleports==0,'mode placement raced residual root movement despite idle queue/no path')
clock=400;actor.deferredX=0;actor.deferredY=0;assert(not placement.ready(),'native quiescence lacked a stable interval')
clock=899;assert(not placement.ready()and teleports==0,'mode placement bypassed the 500ms animation quiescence interval')
clock=900;assert(not placement.ready()and teleports==1 and actor.x==20.5 and actor.y==30.5,'mode origin did not restore exact fractional centre after quiescence')
clock=2399;assert(not placement.ready(),'mode origin bypassed minimum post-placement native settle time')
clock=2400;assert(not placement.ready(),'mode origin bypassed stale native square')
actor.squareX=20;actor.squareY=30;actor.moving=true;assert(not placement.ready(),'mode origin accepted moving actor')
actor.moving=false;assert(placement.ready(),'exact idle origin did not pass native mode barrier')
local lifecycle=placement.lifecycle();assert(lifecycle.positionProof.before.x==19.2 and lifecycle.positionProof.actual.x==20.5,'origin barrier did not preserve raw before/after evidence')
assert(lifecycle.positionProof.quiescence.stableMs==500 and lifecycle.positionProof.quiescence.samples==3 and lifecycle.positionProof.quiescence.last.deferredX==0,'mode placement lacks native quiescence evidence')
actor.x=20.51171875;assert(not placement.ready()and teleports==1,'mode placement weakened .01 precision or repeatedly teleported a drifting actor')
actor.x=20.5;assert(placement.ready(),'exact native centre was rejected after drift resolved')
clock=10000;ok=pcall(placement.ready);assert(not ok,'native mode placement lacks a bounded deadline')
print('PASS Smart Deposit Host mode origin waits for native animation quiescence and retains exact centre, square, motion and deadline gates')

clock=11000;local originalPosition={x=14.25,y=19.75,z=0,squareX=14,squareY=19,squareZ=0}
placement.setOriginal(originalPosition);placement.returnBegin();local beforeReturn=teleports
assert(transitioned=='return-position'and teleports==beforeReturn,'original-position return did not use shared asynchronous placement')
actor.deferredX=.01;assert(not placement.returnReady(),'original-position return bypassed residual native animation')
clock=11400;actor.deferredX=0;assert(not placement.returnReady(),'original return bypassed native quiescence sampling')
clock=11900;assert(not placement.returnReady()and teleports==beforeReturn+1 and actor.x==14.25 and actor.y==19.75,'original return did not restore exact fractional coordinates once')
actor.squareX=14;actor.squareY=19;clock=11999;assert(not placement.returnReady(),'original return bypassed its post-placement 100ms wait')
clock=12000;local returned=placement.returnReady()
assert(returned and returned.original.x==14.25 and returned.actual.x==14.25 and returned.elapsedMs==100 and returned.quiescence.stableMs==500,'original return lost exact original or native transition proof')
print('PASS Smart Deposit Host original return shares bounded native quiescence while retaining strict fractional restoration')
