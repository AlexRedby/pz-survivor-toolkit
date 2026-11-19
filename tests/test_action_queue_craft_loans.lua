-- Focused producer observation checks. Native transfer outcomes/Keep commits
-- have separate Settlement coverage; these doubles grant no gameplay proof.
local function list(items)
    return {size=function() return #items end, get=function(_,i) return items[i+1] end,
        contains=function(_,item) for _,value in ipairs(items) do if value==item then return true end end return false end}
end
local sources, lines = {}, {}
local function callback(file,line,body)
    local fn=body or function() return true end
    sources[fn],lines[fn]=file,line
    return fn
end
local bindingCalls=0
local Proof={closure=function(fn,file) return sources[fn]==file end,matches=function() return true end}
Proof.captureBindings=function(bindings)
    bindingCalls=bindingCalls+1
    local refs={}
    for _,entry in ipairs(bindings) do
        for _,key in ipairs(entry.keys) do refs[#refs+1]={entry.owner,key,entry.owner[key]} end
    end
    return function() for _,ref in ipairs(refs) do if ref[1][ref[2]]~=ref[3] then return false end end return true end
end
getFirstLineOfClosure=function(fn) return lines[fn] end
CharacterTrait={DISORGANIZED='disorganized'}
ItemType={DRAINABLE='drainable',FOOD='food',CONTAINER='container'}
local inventoryItems={}
local root={getItemById=function(_,id) return inventoryItems[id] end}
local tickCallbacks={}
Events={OnTick={Add=function(fn) tickCallbacks[#tickCallbacks+1]=fn end,
    Remove=function(fn) for i=#tickCallbacks,1,-1 do if tickCallbacks[i]==fn then table.remove(tickCallbacks,i) end end end},
    OnMainMenuEnter={Add=function() end}}
local function tick()
    local callbacks={}
    for _,fn in ipairs(tickCallbacks) do callbacks[#callbacks+1]=fn end
    for _,fn in ipairs(callbacks) do fn() end
end
local player={getPlayerNum=function() return 0 end,getInventory=function() return root end,
    isDead=function(self) return self.dead==true end,isAsleep=function() return false end,
    isPlayerMoving=function(self) return self.moving==true end,
    isRunning=function(self) return self.running==true end,isSprinting=function(self) return self.sprinting==true end,
    pressedMovement=function(self) return self.moving==true end,
    hasTimedActions=function(self) return self.nativeActive==true end,
    isLocalPlayer=function() return true end,getOnlineID=function() return 7 end,
    hasTrait=function(self) return self.disorganized==true end,isEquipped=function() return false end}
instanceof=function(value,kind) return value==player and kind=='IsoPlayer' end
getSpecificPlayer=function() return player end
local p4,enabled=false,true
getActivatedMods=function() return {contains=function(_,id) return id=='P4TidyUpMeister' and p4 end} end
local recipe={isCanBeDoneFromFloor=function(self) return self.floor==true end}
local body={character=player,craftRecipe=recipe}
local handles,remembered={},0
local settlement={observePreparation=callback('ActionQueueSettlement.lua',nil,function(action,spec)
    local handle={action=action,spec=spec};handles[#handles+1]=handle;return handle
end),rememberPreparation=callback('ActionQueueSettlement.lua',nil,function(value)
    assert(value==body);remembered=remembered+1;return true
end)}
local policy={matchesNative=callback('ActionQueuePolicy.lua'),isOrdinaryTransfer=callback('ActionQueuePolicy.lua'),
    isCarriedContainer=callback('ActionQueuePolicy.lua',nil,function(container) return container.carried==true end)}
local craft={supports=callback('ActionQueueCraft.lua')}
local definitions={inspect=callback('ActionQueueDefinitions.lua')}
local bulk={transfer=callback('BulkActions.lua',233)}
ISCraftingUI={ReturnItemsToOriginalContainer=callback('ISCraftingUI.lua',4),ReturnItemToContainer=callback('ISCraftingUI.lua',15)}
ISInventoryTransferUtil={newInventoryTransferAction=callback('ISInventoryTransferUtil.lua',15)}
PZSurvivorToolkit={ActionQueueSettlement=settlement,ActionQueuePolicy=policy,ActionQueueCraft=craft,
    ActionQueueDefinitions=definitions,BulkActions=bulk,Settings={actionQueue=function() return enabled end}}
require=function(name) assert(name=='PZSurvivorToolkit/SourceProof');return Proof end
local path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCraftLoans.lua'
local source
if NativeReadText then source=NativeReadText(path)
else local file=assert(io.open(path));source=file:read('*a');file:close() end
local Loans=assert(loadstring(source,'@'..path))()
local function tool(id,opts)
    opts=opts or {}
    local source={carried=not opts.world,getContainingItem=function() return {} end,
        hasRoomFor=function() return true end}
    local script={isItemType=function(_,kind) return opts.kind==kind end,
        getReplaceOnUse=function() return opts.replace end,getReplaceOnDeplete=function() end,
        getOnBreak=function() return opts.onBreak end}
    local item={container=opts.root and root or source,getID=function() return id end,
        getFullType=function() return 'Base.Tool'..id end,
        getScriptItem=function() return script end,getContainer=function(self) return self.container end,
        getIsCraftingConsumed=function() return opts.craftingConsumed==true end}
    source.getItemById=function(_,wanted)
        if wanted==id and item:getContainer()==source then return item end
    end

    local input={isKeep=function() return not opts.consume end,hasConsumeFromItem=function() return false end,
        hasCreateToItem=function() return false end,isReplace=function() return false end,isApplyOnTick=function() return false end}
    return item,{input={native=input},items=list({item})},source
end
local first,firstSelection,firstSource=tool(1)
local second,secondSelection,secondSource=tool(2)
local consumed,consumeSelection=tool(3,{consume=true})
local selected={firstSelection,secondSelection,consumeSelection}
local kept=list({first,second})
local observation=assert(Loans.capture(player,body,selected,kept))
local firstPickup={character=player,item=first,srcContainer=firstSource,destContainer=root}
local secondPickup={character=player,item=second,srcContainer=secondSource,destContainer=root}
observation.pickup(firstPickup);observation.pickup(secondPickup);observation.body(body)
assert(#handles==2 and handles[1]~=handles[2] and handles[1].action==firstPickup and handles[2].action==secondPickup)
assert(remembered==1 and handles[1].spec.guard(firstPickup) and handles[2].spec.guard(secondPickup))
assert(not handles[1].spec.guard(secondPickup),'one tool acquired the other tool pickup')
assert(handles[1].spec.capture().source==firstSource and handles[2].spec.capture().source==secondSource)
assert(handles[1].spec.observed()==false,'producer guessed native transfer success')
local before=bindingCalls
local rootItem,rootSelection=tool(4,{root=true})
assert(Loans.capture(player,body,{rootSelection},list({rootItem}))==nil and bindingCalls==before)
assert(Loans.capture(player,body,selected,list({}))==nil and bindingCalls==before)
recipe.floor=true
assert(Loans.capture(player,body,selected,kept)==nil and bindingCalls==before)
recipe.floor=false
for _,opts in ipairs({{consume=true},{kind='food'},{kind='drainable'},{kind='container'},{replace=true},{onBreak=true}}) do
    local item,selection=tool(5,opts)
    before=bindingCalls
    assert(Loans.capture(player,body,{selection},list({item}))==nil and bindingCalls==before)
end
local worldItem,worldSelection=tool(6,{world=true})
assert(Loans.capture(player,body,{worldSelection},list({worldItem}))==nil)
p4=true;assert(Loans.capture(player,body,selected,kept)==nil);p4=false
enabled=false;assert(Loans.capture(player,body,selected,kept)==nil);enabled=true
player.disorganized=true;assert(Loans.capture(player,body,selected,kept)==nil);player.disorganized=false
local old=policy.matchesNative
policy.matchesNative=function() return true end
assert(not handles[1].spec.guard(firstPickup),'changed transfer policy retained its loan lease')
assert(Loans.capture(player,body,selected,kept)==nil)
policy.matchesNative=old
local saved=settlement.observePreparation
settlement.observePreparation=nil
assert(Loans.capture(player,body,selected,kept)==nil,'missing optional support escaped into gameplay')
settlement.observePreparation=saved
assert(Loans.capture(player,body,{},nil)==nil,'malformed optional capture escaped into gameplay')
-- Independent restoration is source-owned during the exact producer pickup,
-- including when the editor starts disabled. Nothing is owed until Settlement
-- confirms this particular transfer was earned.
local queue={character=player,queue={},toolkitOperationGeneration=0}
function queue:indexOf(action)
    for index,member in ipairs(self.queue) do if member==action then return index end end
    return -1
end
ISTimedActionQueue={queues={[player]=queue}}
local restorationEpisodes={}
settlement.beginIndependentRestoration=callback('ActionQueueSettlement.lua',nil,function(episode,action)
    assert(Loans.ownsPickup(episode,action),'producer did not own its active pickup')
    assert(not Loans.ownsPickup(episode,{}),'producer accepted a foreign pickup')
    restorationEpisodes[#restorationEpisodes+1]={episode=episode,action=action}
    return true
end)
settlement.earned=callback('ActionQueueSettlement.lua',nil,function(handle) return handle.paid==true end)
-- Group cancellation remains owned by the editor's existing cleanup command.
-- These source-tagged doubles only let an editor-enabled producer bind it.
local operations={
    command=function(actor,fn) return {character=actor,addActionsFunction=fn} end,
    adopt=function(action,token) action.toolkitQueueOperation=token end,
    isCommand=function() return true end,
}
PZSurvivorToolkit.ActionQueueOperations=operations
definitions.registerBehavior=function() end
settlement.enqueueClaimedReturns=callback('ActionQueueSettlement.lua')
settlement.cleanupAfter=callback('ActionQueueSettlement.lua')
settlement.claimBorrowedReturns=callback('ActionQueueSettlement.lua')
settlement.onCancelBorrowedReturns=callback('ActionQueueSettlement.lua')
local restored={}
ISCraftingUI.ReturnItemToContainer=callback('ISCraftingUI.lua',15,function(actor,item,destination)
    assert(actor==player and item:getContainer()==root)
    restored[#restored+1]={item=item,destination=destination}
    local row={Type='ISInventoryTransferAction',character=actor,item=item,srcContainer=root,
        destContainer=destination,allowMissingItems=true}
    queue.queue[#queue.queue+1]=row;queue.current=queue.queue[1]
    return row
end)
local function movementFixture(options)
    options=options or {}
    enabled=options.enabled==true
    queue.queue={};queue.current=nil;queue.toolkitOperationGeneration=0
    queue.toolkitCancel=nil;queue.toolkitGroupCancel=nil
    player.moving=false;player.nativeActive=false;player.dead=false;player.running=false;player.sprinting=false
    inventoryItems={}
    local item,selection,sourceContainer=tool(20)
    local other,otherSelection,otherSource
    if options.multiple then other,otherSelection,otherSource=tool(21) end
    local token={}

    body={Type='ISHandcraftAction',character=player,craftRecipe=recipe,toolkitQueueOperation=token,
        stopOnWalk=true,isStarted=function(self) return self.started==true end,
        getJobDelta=function(self) return self.delta end}
    local selections=other and {selection,otherSelection} or {selection}
    local keptItems=other and {item,other} or {item}
    local observation=assert(Loans.capture(player,body,selections,list(keptItems)),
        'disabled editor refused source-owned restoration')
    local pickup={Type='ISInventoryTransferAction',character=player,item=item,
        srcContainer=sourceContainer,destContainer=root,toolkitQueueOperation=token}
    local beforeHandle=#handles
    observation.pickup(pickup)
    local handle=assert(handles[beforeHandle+1],'independent pickup was not observed')
    if not enabled then
        local episode=assert(restorationEpisodes[#restorationEpisodes])
        assert(episode.action==pickup and not Loans.ownsPickup(episode.episode,pickup),
            'producer ownership escaped its synchronous pickup boundary')
    end
    local otherHandle,otherPickup
    if other then
        otherPickup={Type='ISInventoryTransferAction',character=player,item=other,
            srcContainer=otherSource,destContainer=root,toolkitQueueOperation=token}
        observation.pickup(otherPickup)
        otherHandle=assert(handles[beforeHandle+2])
    end
    observation.body(body)
    local row={Type='ISInventoryTransferAction',character=player,item=item,srcContainer=root,
        destContainer=sourceContainer,allowMissingItems=true,toolkitQueueOperation=token}
    queue.queue={body,row};queue.current=body
    if other then
        queue.queue[3]={Type='ISInventoryTransferAction',character=player,item=other,srcContainer=root,
            destContainer=otherSource,allowMissingItems=true,toolkitQueueOperation=token}
    end
    if options.pickup then
        assert(otherPickup,'pickup interruption requires distinct pinned tools')
        table.insert(queue.queue,1,otherPickup);queue.current=otherPickup
    end
    observation.returns(keptItems)
    if other then
        other.container=root;inventoryItems[other:getID()]=other
        otherHandle.paid=options.otherPaid~=false
    end
    item.container=root;inventoryItems[item:getID()]=item
    handle.paid=options.paid~=false
    body.started=true;body.craftStarted=true;body.action={};body.delta=0.25
    player.moving=true;player.nativeActive=true
    if options.pickup then
        other.container=otherSource;otherHandle.paid=false
        body.started=false;body.craftStarted=false;body.action=nil;body.delta=0
        otherPickup.action={};otherPickup.started=true;otherPickup.stopOnRun=true
        otherPickup.isStarted=function(self) return self.started==true end
        otherPickup.getJobDelta=function(self) return self.delta end;otherPickup.delta=.1
        player.running=true
    end
    return {item=item,source=sourceContainer,row=row,handle=handle,body=body,other=other,otherSource=otherSource,otherHandle=otherHandle,pickup=otherPickup}
end
local function finishNativeStop()
    -- Native reset wipes Lua first, then its caller wipes Java. Deferring only
    -- until the Lua queue is empty would still start work inside the old clear.
    for i=#queue.queue,1,-1 do
        local token=queue.queue[i].toolkitQueueOperation
        if token then token.toolkitCancelled=true end
        queue.queue[i]=nil
    end
    queue.current=nil
    queue.toolkitOperationGeneration=queue.toolkitOperationGeneration+1
    tick()
    player.nativeActive=false;player.moving=false
    tick()
end
local fixture=movementFixture()
local restoredBefore=#restored
Loans.movementStopped(fixture.body,queue)
Loans.movementStopped(fixture.body,queue)
assert(#restored==restoredBefore,'movement stop returned tools inside native clear')
for i=#queue.queue,1,-1 do queue.queue[i]=nil end;queue.current=nil
queue.toolkitOperationGeneration=queue.toolkitOperationGeneration+1
player.moving=false
tick()
assert(#restored==restoredBefore,'cleanup ran while old Java action was still active')
player.nativeActive=false
tick()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item
    and restored[#restored].destination==fixture.source,'paid kept tool did not return after native clear')
tick()
assert(#restored==restoredBefore+1,'same stopped craft returned its tool twice')
-- Host can rebind a pending return to a new replica after the paid pickup.
-- A matching ID on a stale object is insufficient.
local host=false
isClient=function() return host end
for _,variant in ipairs({'host-canonical','host-stale','sp-alias'}) do
    fixture=movementFixture()
    restoredBefore=#restored
    host=variant~='sp-alias'
    local original=fixture.item
    local replica={getID=original.getID,getFullType=original.getFullType,getContainer=function() return root end}
    fixture.row.item=replica
    if variant~='host-stale' then inventoryItems[original:getID()]=replica end
    Loans.movementStopped(fixture.body,queue);finishNativeStop()
    if variant=='host-canonical' then
        assert(#restored==restoredBefore+1 and restored[#restored].item==replica)
    else
        assert(#restored==restoredBefore,'unconfirmed alias acquired native movement return')
    end
end
host=false
fixture=movementFixture({paid=false})
restoredBefore=#restored
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore,'unearned pickup manufactured a restoration')
fixture=movementFixture()
restoredBefore=#restored
fixture.row.destContainer={}
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore,'changed native return origin manufactured a restoration')
fixture=movementFixture()
restoredBefore=#restored
Loans.movementStopped(fixture.body,queue)
for i=#queue.queue,1,-1 do queue.queue[i]=nil end;queue.current=nil
queue.toolkitOperationGeneration=queue.toolkitOperationGeneration+2
player.nativeActive=false;player.moving=false;tick()
assert(#restored==restoredBefore,'unrelated queue reset revived stale restoration')
fixture=movementFixture({multiple=true})
restoredBefore=#restored
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item,
    'movement cleanup did not start with its first paid tool')
tick()
assert(#restored==restoredBefore+1,'second return started before the first timed return ended')
queue.queue[1]=nil;queue.current=nil
tick()
assert(#restored==restoredBefore+2 and restored[#restored].item==fixture.other
    and restored[#restored].destination==fixture.otherSource,'second paid return did not follow first completion')
fixture=movementFixture({multiple=true,paid=false})
restoredBefore=#restored
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.other,
    'one unpaid sibling hid or acquired the other paid tool')
for _,progress in ipairs({0,1}) do
    fixture=movementFixture()
    restoredBefore=#restored
    fixture.body.delta=progress
    Loans.movementStopped(fixture.body,queue);finishNativeStop()
    assert(#restored==restoredBefore,'unstarted or completed craft acquired movement cleanup')
end
-- Editor reset invalidates operation tokens as well as incrementing the
-- generation. A native walk still owes the exact earned return after that reset.
fixture=movementFixture({enabled=true})
restoredBefore=#restored
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item,
    'editor token invalidation lost the paid native walk return')
-- Editor reordering retains exact native rows and their edited return order.
fixture=movementFixture({enabled=true,multiple=true})
restoredBefore=#restored
queue.queue[2],queue.queue[3]=queue.queue[3],queue.queue[2]
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.other
    and restored[#restored].destination==fixture.otherSource,'edited first return lost its queue order')
queue.queue[1]=nil;queue.current=nil;tick()
assert(#restored==restoredBefore+2 and restored[#restored].item==fixture.item
    and restored[#restored].destination==fixture.source,'edited second return lost its queue order')
queue.queue[1]=nil;queue.current=nil;tick();tick()
assert(#restored==restoredBefore+2,'reordered native returns repeated an original tool')
-- Individual Keep removes its original return row before a later walk. The
-- untouched sibling remains owed after shifting into the removed row's slot.
fixture=movementFixture({enabled=true,multiple=true})
restoredBefore=#restored
table.remove(queue.queue,2)
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.other
    and restored[#restored].destination==fixture.otherSource,
    'individual Keep lost the shifted sibling or revived the removed return')
queue.queue={};queue.current=nil;tick()
assert(#restored==restoredBefore+1,'individual Keep was undone by a later restoration tick')
-- An equivalent-looking replacement is not the captured native return. It
-- cannot acquire the absent row's loan or hide the surviving original sibling.
fixture=movementFixture({enabled=true,multiple=true})
restoredBefore=#restored
queue.queue[2]={Type=fixture.row.Type,character=player,item=fixture.item,srcContainer=root,
    destContainer=fixture.source,allowMissingItems=true,toolkitQueueOperation=fixture.body.toolkitQueueOperation}
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.other,
    'replacement row acquired the removed native return loan')
-- A stopped body from explicit editor cancellation is not a native walk, even
-- if the movement input happens to be held during the stop callback.
for _,intent in ipairs({'action','group'}) do
    fixture=movementFixture({enabled=true,multiple=true})
    restoredBefore=#restored
    fixture.body.toolkitQueueOperation.toolkitCancelled=true
    if intent=='group' then queue.toolkitGroupCancel={action=fixture.body}
    else queue.toolkitCancel=fixture.body end
    Loans.movementStopped(fixture.body,queue);finishNativeStop()
    assert(#restored==restoredBefore,'explicit editor cancellation acquired native walk restoration')
end
fixture=movementFixture({enabled=true})
restoredBefore=#restored
player.moving=false
Loans.movementStopped(fixture.body,queue);finishNativeStop()
assert(#restored==restoredBefore,'unrelated idle clear acquired native walk restoration')

-- An interrupted second pickup shares the producer's pending body and exact
-- put-back rows. Only already earned tools can use ordinary Settlement proof.
-- The Host receipt double models the native observer's opaque public contract.
local pickupWatches={}
pzWatchInterruptedPickup=function(action)
    local watch=assert(pickupWatches[action],'watched a foreign pickup')
    watch.calls=watch.calls+1
    return watch.receipt
end
local function pickupFixture(options)
    options=options or {}
    host=options.host==true
    local value=movementFixture({enabled=options.editor~=false,multiple=true,pickup=true})
    local state={confirmed=false,expired=false,releases=0,calls=0}
    state.receipt={isConfirmed=function()return state.confirmed end,
        isExpired=function()return state.expired end,release=function()state.releases=state.releases+1 end}
    pickupWatches[value.pickup]=state;value.watch=state
    return value
end
local function finishReturn()
    for i=#queue.queue,1,-1 do queue.queue[i]=nil end
    queue.current=nil;tick()
end
for _,runKind in ipairs({'running','sprinting'})do
    fixture=pickupFixture();restoredBefore=#restored
    player.running=runKind=='running';player.sprinting=runKind=='sprinting'
    Loans.movementStopped(fixture.pickup,queue)
    Loans.movementStopped(fixture.pickup,queue)
    assert(#restored==restoredBefore,'pickup restoration issued inside native stop')
    finishNativeStop()
    assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item
        and restored[#restored].destination==fixture.source,'run during second pickup lost the earned first saw')
    finishReturn();tick()
    assert(#restored==restoredBefore+1,'unearned source drill received a return')
end
-- Native pre-stop can arrive before the Lua started flag or at either UI
-- progress endpoint. The live native instance and owned run boundary matter.
for _,progress in ipairs({0,1})do
    fixture=pickupFixture();restoredBefore=#restored
    fixture.pickup.started=false;fixture.pickup.delta=progress
    Loans.movementStopped(fixture.pickup,queue);finishNativeStop()
    assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item,
        'native pickup pre-stop lost earned saw at UI progress endpoint')
    finishReturn();tick()
    assert(#restored==restoredBefore+1,'UI progress endpoint manufactured unearned drill return')
end
fixture=pickupFixture({editor=false});restoredBefore=#restored
Loans.movementStopped(fixture.pickup,queue);finishNativeStop();finishReturn()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item,
    'editor-off interruption lost the previously collected tool')
fixture=pickupFixture();restoredBefore=#restored
Loans.movementStopped(fixture.pickup,queue);finishNativeStop()
fixture.other.container=root;inventoryItems[fixture.other:getID()]=fixture.other
finishReturn();tick()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item,
    'root-only unearned SP drill manufactured an interrupted pickup return')
-- Root membership alone cannot promote the interrupted Host request to a
-- completed pickup. A late exact-root replica needs positive native proof.
fixture=pickupFixture({host=true});restoredBefore=#restored
Loans.movementStopped(fixture.pickup,queue);finishNativeStop()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item,
    'unconfirmed Host drill hid earned first-tool restoration')
fixture.other.container=root;inventoryItems[fixture.other:getID()]=fixture.other
finishReturn();tick();tick()
assert(#restored==restoredBefore+1,'root-only unconfirmed drill acquired cleanup authority')
fixture.watch.expired=true;tick()
assert(fixture.watch.releases==1,'expired interrupted request receipt was not released')
fixture.watch.confirmed=true;tick()
assert(#restored==restoredBefore+1,'expired request revived after late confirmation')
-- Accept/Done and physical inventory arrival are independent observations.
-- Confirmation while still in source must wait, then issue exactly one return.
fixture=pickupFixture({host=true});restoredBefore=#restored
Loans.movementStopped(fixture.pickup,queue);finishNativeStop();finishReturn()
fixture.watch.confirmed=true;tick();tick()
assert(#restored==restoredBefore+1,'confirmed receipt returned drill before physical root arrival')
fixture.other.container=root;inventoryItems[fixture.other:getID()]=fixture.other
tick()
assert(#restored==restoredBefore+2 and restored[#restored].item==fixture.other
    and restored[#restored].destination==fixture.otherSource,'late confirmed exact-root drill did not return')
finishReturn();tick()
assert(#restored==restoredBefore+2 and fixture.watch.releases==1,'confirmed drill returned repeatedly or retained its receipt')
-- Later user work and unrelated resets revoke a deferred pickup watch, even
-- when a native confirmation and physical root item subsequently appear.
for _,replacement in ipairs({'foreign-work','extra-clear'})do
    fixture=pickupFixture({host=true});restoredBefore=#restored
    Loans.movementStopped(fixture.pickup,queue);finishNativeStop()
    assert(#restored==restoredBefore+1,'earned first return did not start before deferred revocation')
    for i=#queue.queue,1,-1 do queue.queue[i]=nil end
    queue.current=nil
    if replacement=='foreign-work'then
        local foreign={Type='ISReadABook',character=player};queue.queue[1]=foreign;queue.current=foreign
    else queue.toolkitOperationGeneration=queue.toolkitOperationGeneration+1 end
    tick()
    assert(fixture.watch.releases==1,'foreign work/reset failed to release interrupted pickup watch')
    fixture.watch.confirmed=true;fixture.other.container=root;inventoryItems[fixture.other:getID()]=fixture.other
    for i=#queue.queue,1,-1 do queue.queue[i]=nil end
    queue.current=nil;tick();tick()
    assert(#restored==restoredBefore+1,'revoked pickup watch returned a late drill')
end
fixture=pickupFixture({host=true});restoredBefore=#restored
-- Keep removes only the drill's original pending put-back row.
table.remove(queue.queue,4)
Loans.movementStopped(fixture.pickup,queue);finishNativeStop();finishReturn()
fixture.watch.confirmed=true;fixture.other.container=root;inventoryItems[fixture.other:getID()]=fixture.other
tick();tick()
assert(#restored==restoredBefore+1 and restored[#restored].item==fixture.item,
    'Keep on pending drill revived its return or hid first saw')
assert(fixture.watch.calls==0 or fixture.watch.releases==1,'Keep leaked an interrupted pickup watch')
for _,invalid in ipairs({'walking','idle','no-stop-run','foreign-source','foreign-destination','unstarted'})do
    fixture=pickupFixture();restoredBefore=#restored
    if invalid=='walking'then player.running=false
    elseif invalid=='idle'then player.moving=false
    elseif invalid=='no-stop-run'then fixture.pickup.stopOnRun=false
    elseif invalid=='foreign-source'then fixture.pickup.srcContainer={carried=true}
    elseif invalid=='foreign-destination'then fixture.pickup.destContainer={}
    elseif invalid=='unstarted'then fixture.pickup.action=nil end
    Loans.movementStopped(fixture.pickup,queue);finishNativeStop()
    assert(#restored==restoredBefore,'invalid pickup movement boundary acquired restoration: '..invalid)
end
host=false

enabled=true
print('Craft loan producer checks passed: exact pickups, independent disabled-editor restoration, paid native movement stop, refusal and duplicate boundaries.')
