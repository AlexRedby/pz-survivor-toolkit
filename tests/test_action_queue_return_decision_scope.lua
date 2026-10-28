if not NativeActionRoot then print('Return decision scope SKIP (pass --native-action-root).');return end
-- Test-only instrumentation counts the real Policy/native-source resource path.
-- Java actors and the two Execution/Settlement observer calls remain explicit
-- doubles; their earned-loan/episode contracts have separate dedicated suites.
local ordinaryLoadfile = loadfile
local function text(path)
    if NativeReadText then return NativeReadText(path) end
    local file=assert(io.open(path));local result=file:read('*a');file:close();return result
end
local function instrument(source, anchor, counter)
    local first=assert(source:find(anchor,1,true),'instrumentation anchor missing')
    assert(not source:find(anchor,first+1,true),'ambiguous instrumentation anchor')
    local inserted=anchor..'\n Counters.'..counter..'=(Counters.'..counter..' or 0)+1'
    return source:sub(1,first-1)..inserted..source:sub(first+#anchor)
end
Counters={};DecisionScopeNoTiming=true;DecisionScopeCandidate=true
loadfile=function(path)
    if path:sub(-21)=='ActionQueuePolicy.lua' then
        local source=text(path)
        source=instrument(source,'local function nativeMatches(action, snapshot, observingCleanup)','nativeMatches')
        source=instrument(source,'    local result = {Definitions.inspect(action, context)}','contracts')
        source=instrument(source,'    for i = index + 1, #queue.queue do','tailMembers')
        source=instrument(source,'    if not targetCheckersUnchanged() then return false, "unsupported_target_checker" end','tailSweeps')
        return loadstring(source,'@'..path)
    end
    return ordinaryLoadfile(path)
end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/RadioCom/ISRadioAction.lua');f.native('shared/TimedActions/ISEquipWeaponAction.lua')
isClient=function()return false end
isServer=function()return false end
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
getGameFilesInput=function(path)
 local text
 if NativeReadText then text=NativeReadText(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
 else local file=assert(io.open(NativeActionRoot..'/'..path:gsub('^media/lua/','')));text=file:read('*a');file:close()end
 local position=1
 return {close=function()end,readLine=function()
  if position>#text then return end
  local boundary=text:find('\n',position,true)or #text+1
  local line=text:sub(position,boundary-1):gsub('\r$','');position=boundary+1;return line
 end}
end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local adapters=f.project('ActionQueueEditAdapters');local originalRequire=require
require=function(name)if name=='PZSurvivorToolkit/ActionQueueEditAdapters'then return adapters end;return originalRequire(name)end
local transferAdapter=require('PZSurvivorToolkit/ActionQueueItemEditAdapters')
local transferDomain='item';local transferDevice
transferAdapter.transfer=function(action)return {version=1,complete=true,resources={{domain=transferDomain,key=transferDevice or action.item:getID()}}}end
local policy=f.project('ActionQueuePolicy')
loadfile=ordinaryLoadfile
local player=f.player;player.class='IsoPlayer'
local root={class='ItemContainer',getType=function()return'none'end,getParent=function()return player end,
 getContainingItem=function()end,getAcceptItemFunction=function()end}
player.inventory=root
local bagOwner=f.item('Base.Bag_Schoolbag');bagOwner.class='InventoryContainer'
local bag={class='ItemContainer',getType=function()return'bag'end,getParent=function()end,
 getContainingItem=function()return bagOwner end,getAcceptItemFunction=function()end}
local book=f.item('Base.BookCarpentry1');local pen=f.item('Base.Pen')
local reader=f.action(ISReadABook,{item=book,action={isStarted=function()return true end,
 finished=function()return false end,isForceComplete=function()return false end}})
local returning=f.action(ISInventoryTransferAction,{item=book,srcContainer=root,destContainer=bag,allowMissingItems=true})
returning.toolkitQueueOperation=reader.toolkitQueueOperation
local equip=f.action(ISEquipWeaponAction,{item=pen,primary=true,twoHands=false})
local queue=f.queue(reader,returning,equip)
-- Reproduce the actual native TV producer, including owned lazy approach.
player.isLocalPlayer=function()return true end
player.isDraggingCorpse=function()return false end
local function read(path)
 if NativeReadText then return NativeReadText(NativeActionRoot..'/'..path):gsub('\r','')end
 local file=assert(io.open(NativeActionRoot..'/'..path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
luautils={}
local utilities=read('shared/luautils.lua')
assert(loadstring(assert(utilities:match('(function luautils.walkAdj%(.-\nend)'))..'\n'..
 assert(utilities:match('(luautils.getCorrectSquareForWall = function.-\nend)')),
 '@'..NativeActionRoot..'/shared/luautils.lua'))()
local approach=f.project('ActionQueueApproach');assert(approach.install())
RWMPanel,RWMVolume={},{}
assert(loadstring(assert(read('client/RadioCom/RadioWindowModules/RWMPanel.lua'):match('(function RWMPanel:doWalkTo%(.-\nend)')),
 '@'..NativeActionRoot..'/client/RadioCom/RadioWindowModules/RWMPanel.lua'))()
assert(loadstring(assert(read('client/RadioCom/RadioWindowModules/RWMVolume.lua'):match('(function RWMVolume:onVolumeChange%(.-\nend)')),
 '@'..NativeActionRoot..'/client/RadioCom/RadioWindowModules/RWMVolume.lua'))()
local data={canPlayerRemoteInteract=function()return false end}
local tv={class='IsoTelevision',getDeviceData=function()return data end,getSquare=function()return{}end}
local widget={player=player,device=tv,deviceData=data,deviceType='IsoObject',
 volumeBar={getVolumeSteps=function()return 4 end},doWalkTo=RWMPanel.doWalkTo}
PZSurvivorToolkit.ActionQueueOperations.run(function()RWMVolume.onVolumeChange(widget,1)end)
assert(approach.isAction(queue.queue[4]))
queue.queue[6]=f.action(ISReadABook,{item=f.item('Base.BookCooking1')})
-- Deliberately model only the repeated observer fan-out. Both actual observers
-- call the real Policy proof; private-loan/native Execution guards are tested
-- separately and are not represented by this CPU microbenchmark.
PZSurvivorToolkit.ActionQueueExecution={
 inspect=function(action)
  Counters.support=(Counters.support or 0)+1
  if policy.returnFailureIndependent(queue,action)then return {supported=true}end
 end,
 capacityDeferred=function(action,descriptor)
  Counters.support=(Counters.support or 0)+1
  return descriptor.supported and policy.returnFailureIndependent(queue,action)
 end}
local function sized(count)
 for i=#queue.queue,7,-1 do queue.queue[i]=nil end
 for i=7,count do
  local device={class='IsoTelevision',getObjectIndex=function()return 0 end,getSquare=function()return{}end}
  local data={class='DeviceData',getParent=function()return device end,isIsoDevice=function()return true end,
   isVehicleDevice=function()return false end,getIsTurnedOn=function()return true end,getPower=function()return 1 end,
   getDeviceVolume=function()return .5 end,getChannel=function()return 100 end,getMicIsMuted=function()return false end}
  device.getDeviceData=function()return data end
  queue.queue[i]=ISRadioAction:new('SetVolume',player,device,.25);queue.queue[i].toolkitQueueOperation={}
 end
end
local function measure(count)
 sized(count);Counters={}
 local decision=policy.evaluateMove(queue,equip,reader)
 assert(decision.allowed and decision.mode=='audited-resume',decision.reason)
 return {members=count,counters=Counters}
end
local ProfileResults={}
for _,size in ipairs({6,8,16,32})do ProfileResults[#ProfileResults+1]=measure(size)end
-- Fresh next decision must see changed binding and changed sharing facts.
sized(32);Counters={};assert(policy.evaluateMove(queue,equip,reader).allowed)
local last=queue.queue[32];last.onCompleteFunc=function()error('foreign callback must not execute')end
assert(not policy.evaluateMove(queue,equip,reader).allowed,'cached suffix escaped its decision')
last.onCompleteFunc=nil;assert(policy.evaluateMove(queue,equip,reader).allowed)
last.item=book;setmetatable(last,ISReadABook);last.Type='ISReadABook'
assert(not policy.evaluateMove(queue,equip,reader).allowed,'next decision hid new shared book')
-- Raw inspection remains fresh and cannot borrow the just-finished decision.
sized(32);Counters={};local first,second=policy.inspect(returning),policy.inspect(returning)
if DecisionScopeCandidate then
 assert(not first.execution and not second.execution and not Counters.support and not Counters.tailSweeps,
  'generic contract inspection eagerly resolved isolated-return capacity')
else assert(first.execution and second.execution and Counters.tailSweeps==2)end
Counters={};assert(PZSurvivorToolkit.ActionQueueExecution.inspect(returning));assert(PZSurvivorToolkit.ActionQueueExecution.inspect(returning))
assert(Counters.tailSweeps==2,'public Execution inspector inherited a completed decision cache')
Counters={};assert(policy.evaluateMove(queue,queue.queue[5],reader).allowed)
if DecisionScopeCandidate then assert(not Counters.support and not Counters.tailSweeps,'volume-only edit eagerly inspected isolated-return suffix')end
Counters={};assert(policy.evaluateCancel(queue,reader,false).allowed)
if DecisionScopeCandidate then assert(not Counters.support and not Counters.tailSweeps,'isolated reader body stop eagerly inspected return suffix')end
-- A partial tail-only view must never displace the planner's full device edit.
sized(32);local context={contracts={},items={}}
assert(policy.evaluateMove(queue,equip,reader,false,context).allowed)
local full=policy.inspect(queue.queue[32],context)
assert(full.edit and full.edit.resources[1].domain=='device','tail-only footprint escaped into outer edit planner')
-- An unowned/changed adapter cannot borrow the projection specialization.
local originalRadio=adapters.radio
adapters.radio=function()return {resources={{domain='item',key=book:getID()}}}end
assert(not policy.evaluateMove(queue,equip,reader).allowed,'changed adapter bypassed shared item edit')
adapters.radio=originalRadio
-- A matching device-domain transfer edit forces the full shared-resource gate.
transferDomain='device';transferDevice=queue.queue[32].device;Counters={}
assert(not policy.evaluateMove(queue,equip,reader).allowed,'interacting device edit borrowed the elision')
assert(Counters.contracts>=32,'unknown projection domain borrowed tail-only device elision')
transferDomain='item';transferDevice=nil
-- These are existing generic-footprint semantics: invalid optional projected
-- device facts do not erase the same known native items/target footprint.
local ProjectionParityResults={}
for _,kind in ipairs({'valid','nan','missingScalar','missingDevice','foreignDevice','missingData','foreignData','foreignCallback','foreignMethod'})do
 sized(32);local last=queue.queue[32]
 if kind=='nan'then last.secondaryItem=0/0
 elseif kind=='missingScalar'then last.secondaryItem=nil
 elseif kind=='missingDevice'then last.device=nil
 elseif kind=='foreignDevice'then last.device={class='ForeignDevice'}
 elseif kind=='missingData'then last.deviceData=nil
 elseif kind=='foreignData'then last.deviceData={class='ForeignDeviceData'}
 elseif kind=='foreignCallback'then last.onCompleteFunc=function()error('foreign callback executed')end
 elseif kind=='foreignMethod'then last.complete=function()error('foreign lifecycle executed')end end
 Counters={};local independent=policy.returnFailureIndependent(queue,returning)
 local expected=kind~='foreignCallback'and kind~='foreignMethod'
 assert(independent==expected,'changed existing scalar/device generic footprint: '..kind)
 ProjectionParityResults[#ProjectionParityResults+1]={kind=kind,independent=independent}
end
sized(32)
local prepared=queue.queue[4];local previous=prepared.addActionsFunction
prepared.addActionsFunction=function()error('foreign deferred callback executed')end
assert(not policy.evaluateMove(queue,equip,reader).allowed,'next decision hid changed approach callback')
prepared.addActionsFunction=previous
local checker=approach.isAction;local foreignCalls=0
approach.isAction=function()foreignCalls=foreignCalls+1;error('foreign approach helper executed')end
assert(not policy.evaluateMove(queue,equip,reader).allowed and foreignCalls==0,'changed source helper executed')
approach.isAction=checker

for _,size in ipairs({33,200})do
 sized(size);Counters={};assert(not policy.evaluateMove(queue,equip,reader).allowed)
 assert(not Counters.tailSweeps and not Counters.tailMembers,'unsupported size inspected the suffix')
end
sized(32)
-- A throwing decision must release its private scope before later raw checks.
local originalMove=policy.moveReason
policy.moveReason=function()error('deliberate decision failure')end
assert(not pcall(policy.evaluateMove,queue,equip,reader))
policy.moveReason=originalMove;Counters={};assert(PZSurvivorToolkit.ActionQueueExecution.inspect(returning));assert(PZSurvivorToolkit.ActionQueueExecution.inspect(returning))
assert(Counters.tailSweeps==2,'exception leaked the private decision lifetime')
-- Nested source-owned inspection has its own lifetime and restores the caller.
local nested=false
policy.moveReason=function(...)
 if not nested then nested=true;assert(policy.evaluateMove(queue,equip,reader).allowed)end
 return originalMove(...)
end
Counters={};assert(policy.evaluateMove(queue,equip,reader).allowed)
assert(Counters.tailSweeps>=2,'nested decision borrowed another decision proof')
policy.moveReason=originalMove
-- Public context reuse is an output convenience, never authority from a
-- previous decision. The same native reader can acquire a shared book later.
sized(32)
local laterBook=f.item('Base.BookCooking2')
local laterReader=f.action(ISReadABook,{item=laterBook})
queue.queue[32]=laterReader
local reused={contracts={},items={}}
assert(policy.evaluateMove(queue,equip,reader,false,reused).allowed)
local oldContracts,oldItems=reused.contracts,reused.items
laterReader.item=book
assert(policy.previewMove(queue,equip,reader,false,reused).reason=='container_capacity',
    'public preview reused stale suffix item facts')
assert(not policy.evaluateMove(queue,equip,reader,false,reused).allowed,
    'public evaluation reused stale suffix item facts')
assert(reused.contracts~=oldContracts and reused.items~=oldItems and reused.contracts[laterReader],
    'supplied context did not receive fresh result caches')
-- Clear private tail views and diagnostics even if a caller returns a table
-- previously used by another query. A hidden shared book must still deny.
reused.failureOverrides={[laterReader]={{items={},itemTypes={},targets={}}}}
reused.failurePositionPrerequisite=laterReader;reused.executionProbe=true
reused.denialGate='stale';reused.denialReason='stale';reused.denialBlocker=laterReader
reused.editFallback={reason='stale'}
assert(not policy.evaluateMove(queue,equip,reader,false,reused).allowed,
    'stale tail override hid the shared book at a new public boundary')
assert(reused.failureOverrides==nil and reused.failurePositionPrerequisite==nil and reused.executionProbe==nil
    and reused.denialGate~='stale' and reused.denialReason~='stale' and not reused.editFallback,
    'public context retained prior diagnostics/private tail state')
laterReader.item=laterBook
assert(policy.evaluateMove(queue,equip,reader,false,reused).allowed,
    'fresh public context did not recover after the shared-item condition ended')
-- Nested calls with the identical caller-owned output still have distinct
-- private contexts; inner maps/diagnostics and output mutations cannot reach
-- the outer analysis. Outer publication wins only after its scope is restored.
local sameOutput={}
local outerContext,innerContext,innerContracts
local entered=false
local marker={}
policy.moveReason=function(q,a,target,after,context)
    if entered then
        innerContext=context
        assert(context~=outerContext and context.contracts~=outerContext.contracts
            and context.items~=outerContext.items and context.denialReason==nil,
            'nested same-output call inherited outer facts/diagnostics')
        local result={originalMove(q,a,target,after,context)}
        context.denialReason='inner-owned'
        return unpack(result,1,9)
    end
    entered=true;outerContext=context
    context.contracts[marker]={};context.denialReason='outer-owned'
    local decision=policy.evaluateMove(q,a,target,after,sameOutput)
    assert(decision.allowed and context.contracts[marker] and context.denialReason=='outer-owned',
        'nested same-output call replaced outer maps/diagnostics')
    innerContracts=sameOutput.contracts
    assert(innerContracts==innerContext.contracts and innerContracts~=context.contracts
        and sameOutput.denialReason=='inner-owned','inner output was not bounded independent publication')
    sameOutput.contracts[marker]={inFlight=true};sameOutput.denialReason='caller-mutated'
    assert(context.denialReason=='outer-owned' and context.contracts[marker].inFlight==nil,
        'mutating nested public output changed outer private facts')
    assert(policy.evaluateMove(q,a,target,after,context).allowed)
    assert(context.contracts[marker] and context.contracts[marker].inFlight==nil
        and context.denialReason=='outer-owned','private outer context was accepted as nested output carrier')
    return originalMove(q,a,target,after,context)
end
assert(policy.evaluateMove(queue,equip,reader,false,sameOutput).allowed)
assert(sameOutput.contracts==outerContext.contracts and sameOutput.contracts~=innerContracts
    and sameOutput.denialReason==nil,'outer did not publish its own final context')
-- The same isolation holds when the inner call throws and is caught by caller.
entered=false
policy.moveReason=function(q,a,target,after,context)
    if entered then error('deliberate nested same-output failure')end
    entered=true;outerContext=context
    context.contracts[marker]={};context.denialReason='outer-owned'
    assert(not pcall(policy.evaluateMove,q,a,target,after,sameOutput))
    assert(context.contracts[marker] and context.denialReason=='outer-owned',
        'nested same-output error corrupted outer analysis lifetime')
    return originalMove(q,a,target,after,context)
end
assert(policy.evaluateMove(queue,equip,reader,false,sameOutput).allowed)
policy.moveReason=originalMove
laterReader.item=book
assert(not policy.evaluateMove(queue,equip,reader,false,sameOutput).allowed,
    'later same-output decision reused nested proof state')
laterReader.item=laterBook
local foreignOutput=setmetatable({},{__index=function()error('foreign output getter')end,
    __newindex=function()error('foreign output setter')end})
assert(policy.evaluateMove(queue,equip,reader,false,foreignOutput).allowed,
    'foreign output table affected private authoritative analysis')
local largest=ProfileResults[#ProfileResults].counters
assert(largest.support==2 and largest.tailSweeps==1 and largest.tailMembers==30,
    'one decision repeated its isolated-return suffix proof')
assert(largest.contracts==5 and largest.nativeMatches==32,
    'tail-only setters rebuilt full planner contracts/native proofs')

-- Group-cancel and pending-return cancellation use comparison-only radio views.
-- These are positive decisions through the actual public cancel entry points;
-- settlement authority here remains an explicit double, as in the move fixture.
sized(32)
local originalSettlement=PZSurvivorToolkit.ActionQueueSettlement
PZSurvivorToolkit.ActionQueueSettlement={requiredStep=function()return false end,
 canWaivePendingReturn=function()return true end,pendingReturnWaiver=function()return {}end}
local function cancelAllowed()
 local group=policy.evaluateCancel(queue,reader,true)
 assert(group.allowed,group.reason)
 assert(not policy.previewCancel(queue,reader,true).reason,'group preview denied')
 local pending=policy.evaluateCancel(queue,returning,false)
 assert(pending.allowed and pending.mode=='pending-return',pending.reason)
 assert(not policy.previewCancel(queue,returning,false).reason,'pending return preview denied')
end
Counters={};cancelAllowed()
assert(Counters.contracts==20,'cancel comparisons rebuilt device-only projections')
-- A later member of the own group must disable elision for the entire group.
transferDomain='device';transferDevice={};Counters={};cancelAllowed()
assert(Counters.contracts>=128,'device edit on a later group member borrowed the elision')
transferDomain='item';transferDevice=nil
-- Shared native item resources remain visible with device projection omitted.
queue.queue[32].item=book
assert(not policy.evaluateCancel(queue,reader,true).allowed,'group hid shared item')
assert(not policy.evaluateCancel(queue,returning,false).allowed,'pending return hid shared item')
queue.queue[32].item=nil
local savedRadio=adapters.radio
adapters.radio=function()return {resources={{domain='item',key=book:getID()}}}end
assert(not policy.evaluateCancel(queue,reader,true).allowed,'changed helper hid group edit dependency')
assert(not policy.evaluateCancel(queue,returning,false).allowed,'changed helper hid return edit dependency')
adapters.radio=savedRadio
for _,field in ipairs({'complete','onCompleteFunc'})do
 local saved=queue.queue[32][field]
 queue.queue[32][field]=function()error('foreign lifecycle/callback executed')end
 assert(not policy.evaluateCancel(queue,reader,true).allowed,'group accepted foreign binding: '..field)
 assert(not policy.evaluateCancel(queue,returning,false).allowed,'return accepted foreign binding: '..field)
 queue.queue[32][field]=saved
end
-- The comparison overlay must never be returned as a full planner contract.
local rawContext={contracts={},items={}}
assert(not policy.cancelOperationReason(queue,reader,rawContext))
assert(not rawContext.contracts[queue.queue[32]],'comparison published partial radio contract')
assert(policy.inspect(queue.queue[32],rawContext).edit.resources[1].domain=='device',
 'full planner inherited partial radio contract')
local pendingContext={contracts={},items={}}
assert(not policy.cancelReason(queue,returning,pendingContext))
assert(not pendingContext.contracts[queue.queue[32]],'pending comparison published partial radio contract')
assert(policy.inspect(queue.queue[32],pendingContext).edit.resources[1].domain=='device')
-- Nested positive cancel calls start their own native/projection lifetime.
local originalCancel=policy.cancelOperationReason
local inCancel=false
policy.cancelOperationReason=function(q,a,context)
 if not inCancel then
  inCancel=true;assert(policy.evaluateCancel(q,a,true).allowed);inCancel=false
 end
 return originalCancel(q,a,context)
end
Counters={};assert(policy.evaluateCancel(queue,reader,true).allowed)
assert(Counters.tailSweeps==2,'nested cancel inherited outer independent-return proof')
policy.cancelOperationReason=originalCancel
-- Fresh next invocation must observe both binding and resource mutations.
queue.queue[32].item=book
assert(policy.previewCancel(queue,reader,true).reason,'fresh group preview hid shared item')
assert(policy.previewCancel(queue,returning,false).reason,'fresh return preview hid shared item')
queue.queue[32].item=nil;cancelAllowed()
PZSurvivorToolkit.ActionQueueSettlement=originalSettlement

DecisionScopeNoTiming=nil
print('Return decision scope: one bounded suffix, fresh nested/error/public boundaries, exact native/helper/callback gates, scalar/device parity and full-planner isolation passed.')
