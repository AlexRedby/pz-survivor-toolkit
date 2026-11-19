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
        getScriptItem=function() return script end,getContainer=function(self) return self.container end}

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
    player.moving=false;player.nativeActive=false;player.dead=false
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
    local episode=assert(restorationEpisodes[#restorationEpisodes])
    assert(episode.action==pickup and not Loans.ownsPickup(episode.episode,pickup),
        'producer ownership escaped its synchronous pickup boundary')
    local otherHandle
    if other then
        observation.pickup({Type='ISInventoryTransferAction',character=player,item=other,
            srcContainer=otherSource,destContainer=root,toolkitQueueOperation=token})
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
    observation.returns(keptItems)
    if other then
        other.container=root;inventoryItems[other:getID()]=other
        otherHandle.paid=options.otherPaid~=false
    end
    item.container=root;inventoryItems[item:getID()]=item
    handle.paid=options.paid~=false
    body.started=true;body.craftStarted=true;body.action={};body.delta=0.25
    player.moving=true;player.nativeActive=true
    return {item=item,source=sourceContainer,row=row,handle=handle,body=body,other=other,otherSource=otherSource}
end
local function finishNativeStop()
    -- Native reset wipes Lua first, then its caller wipes Java. Deferring only
    -- until the Lua queue is empty would still start work inside the old clear.
    for i=#queue.queue,1,-1 do queue.queue[i]=nil end;queue.current=nil
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
enabled=true
print('Craft loan producer checks passed: exact pickups, independent disabled-editor restoration, paid native movement stop, refusal and duplicate boundaries.')
