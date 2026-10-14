if not NativeActionRoot then print('Policy native contracts SKIP (pass --native-action-root).');return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/Fluids/ISFluidContainer.lua')
f.native('shared/Fluids/ISFluidTransferAction.lua')
f.native('shared/Fluids/ISFluidEmptyAction.lua')
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local originalItem=f.item
f.item=function(kind)
    local item=originalItem(kind)
    item.getUnequippedWeight=function(self)return self.weight or 0.1 end
    item.getType=function(self)return self:getFullType():match('%.(.+)$') end
    return item
end
local function capacity(container)
    container.getCapacityWeight=function(self)return self.load or 0 end
    container.getEffectiveCapacity=function(self)return self.capacity or 50 end
    container.getAcceptItemFunction=function(self)return self.acceptItem end
    return container
end
local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
local function vessel()
    local owner=f.item('Base.Bucket')
    local fluid={class="FluidContainer",amount=5,getOwner=function() return owner end,getAmount=function(self)return self.amount end,
        isEmpty=function(self)return self.amount==0 end,canPlayerEmpty=function()return true end,
        Empty=function(self)self.amount=0 end}
    local wrapper=setmetatable({fluidContainer=fluid,isFluidResource=false},ISFluidContainer)
    return wrapper,owner
end
local source,owner=vessel();local target=vessel()
local transfer=f.action(ISFluidTransferAction,{source=source,target=target,amount=3,sourceStartAmount=5})
local empty=f.action(ISFluidEmptyAction,{container=source,amount=5})
local q=f.queue(head,transfer,empty)
assert(policy.moveReason(q,empty,transfer)=='move_shared_item')
assert(policy.moveReason(q,transfer,empty,true)=='move_shared_item')
assert(policy.cancelOperationReason(q,empty)=='operation_shared_item')
local moveDecision=policy.evaluateMove(q,empty,transfer)
assert(not moveDecision.allowed and moveDecision.blocker==transfer and moveDecision.resource==owner:getID())
local cancelDecision=policy.evaluateCancel(q,empty,true)
assert(not cancelDecision.allowed and cancelDecision.blocker==transfer and cancelDecision.resource==owner:getID())
local independent=vessel();local other=f.action(ISFluidEmptyAction,{container=independent})
q=f.queue(head,transfer,other)
assert(not policy.moveReason(q,other,transfer) and not policy.moveReason(q,transfer,other,true))
assert(not policy.cancelOperationReason(q,other),'independent waiting fluid action can be removed')
-- Distinct wrapper and replicated item objects still name the same inventory resource.
local replacement=f.item('Base.Bucket');replacement.id=owner.id
local replacementWrapper=setmetatable({fluidContainer={class="FluidContainer",getOwner=function() return replacement end}},ISFluidContainer)
other.container=replacementWrapper
assert(policy.moveReason(q,other,transfer)=='move_shared_item')
other.container=independent
other.updateEmpty=function() error('policy must not execute callbacks') end
assert(policy.moveReason(q,other,transfer)=='move_dependent','changed helper cannot keep native permission')
other.updateEmpty=nil
local unknown=f.action(ISBaseTimedAction:derive('Unknown'))
q=f.queue(head,transfer,unknown,other)
assert(policy.moveReason(q,other,transfer)=='move_dependent','unknown crossed effects are a barrier')
local token=other.toolkitQueueOperation
local continuation=PZSurvivorToolkit.ActionQueueOperations.attachContinuation(token,f.player)
assert(policy.moveReason(q,other)=='move_dependent','future continuations are not empty operations')
PZSurvivorToolkit.ActionQueueOperations.finishContinuation(continuation)
-- Native validity may mutate state; policy never calls it.
local before=ISFluidTransferAction.isValid
ISFluidTransferAction.isValid=function() error('must not invoke native validation') end
assert(policy.moveReason(f.queue(head,transfer,other),transfer,other,true)=='move_dependent')
ISFluidTransferAction.isValid=before
print('Policy native fluid resources, IDs, symmetric move/cancel, unknown lifecycle and async barriers passed.')

-- Transfers may alter the containing device even when moving an unrelated item.
f.native('shared/TimedActions/ISToggleStoveAction.lua')
policy.installContracts()
local microwave={class='IsoStove'}
local container={class='ItemContainer',getParent=function()return microwave end}
local pickup=f.action(ISInventoryTransferAction,{item=f.item('Base.Apple'),srcContainer=container,destContainer=f.player.inventory})
local toggle=f.action(ISToggleStoveAction,{object=microwave})
q=f.queue(head,pickup,toggle)
local decision=policy.evaluateMove(q,toggle,pickup)
assert(not decision.allowed and decision.blocker==pickup and decision.resource==microwave)
assert(policy.moveReason(q,pickup,toggle,true)=='move_dependent')
policy.record('move',toggle,decision);assert(#policy.getDiagnostics()==0)
policy.setDiagnostics(true)
for i=1,70 do policy.record('move',toggle,decision) end
local records=policy.getDiagnostics()
assert(#records==64 and records[1].blocker=='ISInventoryTransferAction' and records[1].adapter=='native.ISToggleStoveAction')
records[1].reason='changed';assert(policy.getDiagnostics()[1].reason=='move_dependent')
policy.setDiagnostics(false);assert(#policy.getDiagnostics()==0)

-- Battery insertion consumes the selected battery, including replicated replacements.
f.native('shared/TimedActions/ISConnectCarBatteryToChargerAction.lua')
policy.installContracts()
local battery=f.item('Base.CarBattery1')
local insertion=f.action(ISConnectCarBatteryToChargerAction,{charger={},battery=battery})
local movedBattery=f.item('Base.CarBattery1');movedBattery.id=battery.id
local moveBattery=f.action(ISInventoryTransferAction,{item=movedBattery})
q=f.queue(head,insertion,moveBattery)
assert(policy.moveReason(q,moveBattery,insertion)=='move_shared_item')
assert(policy.moveReason(q,insertion,moveBattery,true)=='move_shared_item')
assert(policy.cancelOperationReason(q,insertion)=='operation_shared_item')

local missingSource=f.action(ISFluidTransferAction,{target=target})
local missingTarget=f.action(ISFluidTransferAction,{source=source})
assert(not policy.inspect(missingSource) and not policy.inspect(missingTarget),'a hole in the wrapper list is unknown, not an empty resource set')

-- Native movement invokes optional data callbacks outside its lifecycle methods.
f.native('client/Vehicles/TimedActions/ISPathFindAction.lua')
f.native('client/TimedActions/WalkToTimedAction.lua')
f.native('client/TimedActions/WalkToTimedActionF.lua')
policy.installContracts()
for _, entry in ipairs({{ISPathFindAction, 'onFailFunc'}, {ISWalkToTimedAction, 'additionalTest'}, {ISWalkToTimedActionF, 'additionalTest'}}) do
    local movement = f.action(entry[1])
    assert(policy.inspect(movement), 'unmodified native movement retains its preparation contract')
    movement[entry[2]] = function() error('policy must not invoke optional movement callbacks') end
    assert(not policy.inspect(movement), 'optional movement callback makes its effects unknown')
end

-- Late selection is a recipe type dependency, never a promise that MP reserved selected IDs.
f.native('shared/TimedActions/ISFixAction.lua')
f.native('shared/TimedActions/ISCraftAction.lua')
f.native('shared/Entity/TimedActions/ISHandcraftAction.lua')
local Craft=f.project('ActionQueueCraft')
ResourceType={Item='Item',Fluid='Fluid'}
ItemType={CONTAINER='Container'}
local function list(...)
    local entries={...}
    return {class='List',size=function()return #entries end,get=function(_,i)return entries[i+1] end}
end
local scripts={}
local function script(kind)
    local value={class='Item',getFullName=function()return kind end,
        isItemType=function()return false end,getReplaceOnUse=function()end,getReplaceOnDeplete=function()end,getOnBreak=function()end}
    scripts[kind]=value;return value
end
getScriptManager=function()return {FindItem=function(_,kind)return scripts[kind] end} end
local function recipe(inputType,outputType)
    local input={class='InputScript',getResourceType=function()return ResourceType.Item end,
        isAcceptsAnyItem=function()return false end,getConsumeFromItemScript=function()end,
        getPossibleInputItems=function()return list(script(inputType)) end,getCreateToItemScript=function()end,
        isReplace=function()return false end}
    local output={class='OutputScript',getResourceType=function()return ResourceType.Item end,
        getCreateToItemScript=function()end,getPossibleResultItems=function()return list(script(outputType)) end}
    return {class='CraftRecipe',getScriptLines=function()return list('craftRecipe Example {', 'inputs { item 1 Base.Material, }') end,
        getInputs=function()return list(input) end,getOutputs=function()return list(output) end},input,output
end
local function late(inputType,outputType)
    return f.action(ISHandcraftAction,{craftRecipe=recipe(inputType,outputType),manualInputs=false})
end
local first,second=late('Base.Material','Base.Product'),late('Base.Thread','Base.Cloth')
q=f.queue(head,first,second)
assert(not policy.moveReason(q,first,second,true) and not policy.moveReason(q,second,first),
    'two item-only late recipes with disjoint inputs and outputs can move in either direction')
assert(not policy.cancelOperationReason(q,first) and not policy.cancelOperationReason(q,second),
    'removing either independent waiting recipe does not change the other late selector')
assert(policy.inspect(first).dynamicInputs['Base.Material'] and policy.inspect(first).outputTypes['Base.Product'])
local function blocked(other,reason)
    q=f.queue(head,first,other)
    assert(policy.moveReason(q,other,first)==reason and policy.moveReason(q,first,other,true)==reason)
    local cancel = reason == 'move_shared_item' and 'operation_shared_item' or 'operation_dependent'
    assert(policy.cancelOperationReason(q,first)==cancel and policy.cancelOperationReason(q,other)==cancel)
end
blocked(late('Base.Material','Base.Other'),'move_craft_inputs')
blocked(late('Base.Product','Base.Other'),'move_craft_inputs')
blocked(late('Base.Other','Base.Material'),'move_craft_inputs')
blocked(late('Base.Other','Base.Product'),'move_craft_inputs')
blocked(f.action(ISInventoryTransferAction,{item=f.item('Base.Material')}),'move_craft_inputs')
blocked(f.action(ISInventoryTransferAction,{item=f.item('Base.Product')}),'move_craft_inputs')
local selected=f.item('Base.Material')
first.items=list(selected)
blocked(f.action(ISInventoryTransferAction,{item=selected}),'move_shared_item')
first.items=nil
local unknown=late('Base.Other','Base.Unrelated')
unknown.craftRecipe.getScriptLines=function()return list('OnCreate = Mod.unknown,') end
blocked(unknown,'move_craft_inputs')
unknown=late('Base.Other','Base.Unrelated')
local replacement=script('Base.Other');replacement.getReplaceOnUse=function()return 'Base.Bottle' end
unknown.craftRecipe.getInputs=function()return list({class='InputScript',getResourceType=function()return ResourceType.Item end,
    isAcceptsAnyItem=function()return false end,getConsumeFromItemScript=function()end,
    getPossibleInputItems=function()return list(replacement) end}) end
assert(not Craft.futureResources(unknown),'undeclared use/depletion replacements remain protected')
unknown=late('Base.Other','Base.Unrelated')
unknown.fixMovedItems=function() error('changed helper must never execute') end
assert(not Craft.supports(unknown),'helper overrides do not retain native source permission')
local listReads = 0
unknown=late('Base.Other','Base.Unrelated')
unknown.items={size=function()listReads=listReads+1;error('unknown items getter')end,get=function()listReads=listReads+1 end}
assert(not Craft.futureResources(unknown) and listReads==0,'plain table list callbacks remain uninvoked and protected')
f.native('shared/TimedActions/ISEquipWeaponAction.lua');policy.installContracts()
blocked(f.action(ISEquipWeaponAction,{item=f.item('Base.Hammer')}),'move_dependent')
local pending=PZSurvivorToolkit.ActionQueueOperations.attachContinuation(first.toolkitQueueOperation,f.player)
assert(policy.moveReason(f.queue(head,first,second),first,second,true)=='move_craft_inputs',
    'MP late results keep the entire operation protected until the continuation finishes')
PZSurvivorToolkit.ActionQueueOperations.finishContinuation(pending)

local legacyRecipe={class='Recipe',getScriptLines=function()return list('recipe Example { Base.Material, Result:Product, }') end,
    getSource=function()return list({getItems=function()return list('Base.Material') end}) end,
    getResults=function()return list({getFullType=function()return 'Base.Product' end}) end,
    isRequiresWorkstation=function()return false end,getNearItem=function()end,getHeat=function()return 0 end}
script('Base.Material')
local legacy=f.action(ISCraftAction,{item=f.item('Base.Material'),recipe=legacyRecipe})
assert(Craft.futureResources(legacy).dynamicInputs['Base.Material'])
q=f.queue(head,legacy,second)
assert(not policy.moveReason(q,legacy,second,true) and not policy.moveReason(q,second,legacy))
legacyRecipe.getScriptLines=function()return list('OnGiveXP: Mod.callback,') end
assert(not Craft.futureResources(legacy),'unknown legacy callbacks stay protected without being invoked')
local recipeReads=0
legacy.recipe={getScriptLines=function()recipeReads=recipeReads+1;error('unknown legacy recipe getter')end}
assert(not Craft.futureResources(legacy) and recipeReads==0,'foreign legacy recipe getters must not execute before provenance checks')
print('Late native craft inputs, outputs, selected IDs, equipment, recipe callbacks and MP continuations passed.')

-- A verified wrapper adopts one exact method; other unknown lifecycle changes stay protected.
local originalAnim=ISReadABook.animEvent
local readWrapper=function(self,...)return originalAnim(self,...)end
assert(not policy.adoptReadAnimEvent(originalAnim,readWrapper),'replacement must already be installed on the native class')
ISReadABook.animEvent=readWrapper
assert(not policy.inspect(head) and policy.adoptReadAnimEvent(originalAnim,readWrapper) and policy.inspect(head))
local readStop=ISReadABook.stop
ISReadABook.stop=function()end
assert(not policy.inspect(head),'adopting the reading wrapper cannot resnapshot unrelated methods')
ISReadABook.stop=readStop
ISReadABook.animEvent=originalAnim
assert(policy.adoptReadAnimEvent(readWrapper,originalAnim))

local cleanupClass=ISBaseTimedAction:derive('GuardedCleanup')
PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('fixture.cleanup-phase',{
    matches=function(action)return getmetatable(action)==cleanupClass end,
    inspect=function()return {items={},targets={},interrupt='audited-stop',cancelWaiting=true,cancelOperation=false}end,
})
local cleanup=f.action(cleanupClass)
cleanup.cancelOperation=true
q=f.queue(head,cleanup)
assert(policy.cancelReason(q,cleanup)=='dependent' and policy.cancelOperationReason(q,cleanup)=='operation_dependent',
    'verified unfinished cleanup protects direct and whole-operation cancellation without trusting action flags')

local originalFloor=ISInventoryTransferAction.getNotFullFloorSquare
local floorWrapper=function(self,...)return originalFloor(self,...)end
local chest={class='ItemContainer',getType=function()return 'crate' end,getParent=function()end}
local nativeTransfer=f.action(ISInventoryTransferAction,{item=f.item('Base.Nails'),destContainer=chest})
assert(not policy.adoptTransferFloorHelper(originalFloor,floorWrapper),'floor helper must already be installed')
ISInventoryTransferAction.getNotFullFloorSquare=floorWrapper
assert(not policy.inspect(nativeTransfer) and policy.adoptTransferFloorHelper(originalFloor,floorWrapper)
    and policy.inspect(nativeTransfer),'audited floor-only wrapper retains a native non-floor transfer contract')
q=f.queue(head,nativeTransfer,late('Base.Sheet','Base.SheetRope'))
assert(not policy.moveReason(q,q.queue[3],nativeTransfer) and not policy.moveReason(q,nativeTransfer,q.queue[3],true),
    'native independent container pickups remain movable beside late recipes')
nativeTransfer.destContainer={class='ItemContainer',getType=function()return 'floor' end,getParent=function()end}
assert(not policy.inspect(nativeTransfer),'floor destination stays protected until Tidy restore-square effects are described')
local containerReads=0
nativeTransfer.destContainer={getType=function()containerReads=containerReads+1;error('unknown container getter')end}
assert(not policy.inspect(nativeTransfer) and containerReads==0,'unknown destination callbacks must not execute')
nativeTransfer.destContainer=chest
nativeTransfer.getNotFullFloorSquare=function()error('unknown instance wrapper')end
assert(not policy.inspect(nativeTransfer),'the verified helper cannot grant a different instance wrapper')
ISInventoryTransferAction.getNotFullFloorSquare=originalFloor

local beforeMethods,afterMethods={},{}
local sourceHelpers=true
local function helpersUnchanged()return sourceHelpers end
for _,name in ipairs({'isValid','start','perform','stop'}) do
    local method=ISInventoryTransferAction[name]
    beforeMethods[name]=method
    afterMethods[name]=function(self,...)return method(self,...)end
end
assert(not policy.adoptTransferMethods(beforeMethods,afterMethods,helpersUnchanged),'new methods must already be installed')
for name,method in pairs(afterMethods) do ISInventoryTransferAction[name]=method end
local wrongBefore={isValid=function()end,start=beforeMethods.start,perform=beforeMethods.perform,stop=beforeMethods.stop}
assert(not policy.adoptTransferMethods(wrongBefore,afterMethods,helpersUnchanged),'one unknown previous method cannot adopt the rest')
assert(policy.adoptTransferMethods(beforeMethods,afterMethods,helpersUnchanged))
local carriedBag=f.item('Base.Bag_Schoolbag')
carriedBag.class='InventoryContainer'
f.player.class='IsoPlayer'
f.player.inventory.class='ItemContainer'
f.player.inventory.getType=function()return 'none' end
f.player.inventory.getContainingItem=function()end
f.player.inventory.getParent=function()end
local bagInventory={class='ItemContainer',getType=function()return 'bag' end,
    getContainingItem=function()return carriedBag end,getParent=function()end}
nativeTransfer.getNotFullFloorSquare=nil
nativeTransfer.srcContainer,nativeTransfer.destContainer=bagInventory,f.player.inventory
assert(policy.inspect(nativeTransfer) and policy.inspect(nativeTransfer).containerOwners[carriedBag:getID()],
    'verified carried bag to native root transfer retains its contract and owner ID')
nativeTransfer.srcContainer,nativeTransfer.destContainer=f.player.inventory,bagInventory
assert(policy.inspect(nativeTransfer),'native return into the same carried bag remains supported')
sourceHelpers=false
assert(not policy.inspect(nativeTransfer) and not policy.preparationCanFinish(nativeTransfer),
    'changed delegated source helpers close native and alternate preparation permission')
sourceHelpers=true
carriedBag.getContainer=function()return bagInventory end
assert(not policy.inspect(nativeTransfer) and not policy.preparationCanFinish(nativeTransfer),'deep nested destination remains protected')
carriedBag.getContainer=function()return f.player.inventory end
nativeTransfer.destContainer={class='ItemContainer',getType=function()return 'floor' end,getContainingItem=function()end}
assert(not policy.inspect(nativeTransfer) and not policy.preparationCanFinish(nativeTransfer),'floor destination is outside ordinary BetterContainers adoption')
for _,kind in ipairs({'proximityInv','twistInv_corpses'}) do
    nativeTransfer.destContainer={class='ItemContainer',getType=function()return kind end,getContainingItem=function()end}
    assert(not policy.inspect(nativeTransfer) and not policy.preparationCanFinish(nativeTransfer),
        'native Java proximity aggregation containers stay protected too')
end
local proxyReads=0
nativeTransfer.destContainer={getType=function()proxyReads=proxyReads+1;error('unknown proxy callback')end}
assert(not policy.inspect(nativeTransfer) and proxyReads==0,'foreign proximity proxy callbacks remain uninvoked')
nativeTransfer.destContainer=bagInventory
nativeTransfer.start=function()error('unknown late start')end
assert(not policy.inspect(nativeTransfer),'verified wrapper adoption cannot trust an unrelated late instance override')

local baseInstanceof=instanceof
instanceof=function(value,name)
    return baseInstanceof(value,name) or (type(value)=='table' and ((name=='IsoGameCharacter' and value.class=='IsoPlayer')
        or (name=='InventoryItem' and value.class=='InventoryContainer')))
end
f.player.inventory.getParent=function()return f.player end
capacity(f.player.inventory);capacity(bagInventory)
local bag2=f.item('Base.Bag_Schoolbag');bag2.class='InventoryContainer'
local secondBagInventory={class='ItemContainer',getType=function()return 'bag' end,
    getContainingItem=function()return bag2 end,getParent=function()return f.player end}
capacity(secondBagInventory)
local separate1=f.action(ISInventoryTransferAction,{item=f.item('Base.Nails'),srcContainer=bagInventory,destContainer=f.player.inventory})
local separate2=f.action(ISInventoryTransferAction,{item=f.item('Base.Thread'),srcContainer=secondBagInventory,destContainer=f.player.inventory})
q=f.queue(head,separate1,separate2)
assert(not policy.inspect(separate1).targets[f.player] and not policy.inspect(separate2).targets[f.player])
assert(not policy.moveReason(q,separate1,separate2,true) and not policy.moveReason(q,separate2,separate1),
    'real-shaped character inventory parent is not a shared world device for separate bag transfers')
local rootOut1=f.action(ISInventoryTransferAction,{item=f.item('Base.Nails'),srcContainer=f.player.inventory,destContainer=bagInventory})
local rootOut2=f.action(ISInventoryTransferAction,{item=f.item('Base.Thread'),srcContainer=f.player.inventory,destContainer=secondBagInventory})
q=f.queue(head,rootOut1,rootOut2)
assert(not policy.moveReason(q,rootOut1,rootOut2,true) and not policy.moveReason(q,rootOut2,rootOut1),
    'different loose root items can return into distinct carried bags in either order')
q=f.queue(head,separate1,late('Base.Sheet','Base.SheetRope'))
assert(not policy.moveReason(q,q.queue[3],separate1) and not policy.moveReason(q,separate1,q.queue[3],true),
    'unrelated late recipe can cross a player-parented native transfer')
separate2.item=separate1.item
q=f.queue(head,separate1,separate2)
assert(policy.moveReason(q,separate1,separate2,true)=='move_shared_item' and policy.moveReason(q,separate2,separate1)=='move_shared_item')
local stoveDestination={class='ItemContainer',getType=function()return 'microwave' end,
    getContainingItem=function()end,getParent=function()return microwave end}
separate1.destContainer=stoveDestination
q=f.queue(head,separate1,toggle)
assert(policy.moveReason(q,toggle,separate1)=='move_dependent' and policy.moveReason(q,separate1,toggle,true)=='move_dependent',
    'character exclusion keeps genuine microwave world-owner dependency')

-- The bag is a shared container reference, while the moved contents remain distinct native IDs.
local itemA,itemB=f.item('Base.Nails'),f.item('Base.Thread')
itemA.weight,itemB.weight=2,1
local outgoingA=f.action(ISInventoryTransferAction,{item=itemA,srcContainer=bagInventory,destContainer=f.player.inventory})
local outgoingB=f.action(ISInventoryTransferAction,{item=itemB,srcContainer=bagInventory,destContainer=f.player.inventory})
local incomingA=f.action(ISInventoryTransferAction,{item=itemA,srcContainer=f.player.inventory,destContainer=bagInventory})
local incomingB=f.action(ISInventoryTransferAction,{item=itemB,srcContainer=f.player.inventory,destContainer=bagInventory})
local function both(a,b,reason)
    local queue=f.queue(head,a,b)
    assert(policy.moveReason(queue,a,b,true)==reason and policy.moveReason(queue,b,a)==reason,'symmetric transfer move: '..tostring(reason))
    assert(policy.cancelOperationReason(queue,a)==reason and policy.cancelOperationReason(queue,b)==reason,'symmetric transfer cancellation: '..tostring(reason))
end
both(outgoingA,outgoingB);both(incomingA,incomingB);both(outgoingA,incomingB)
local replicated=f.item('Base.Bag_Schoolbag');replicated.class='InventoryContainer';replicated.id=carriedBag.id
local bagUse=f.action(ISEquipWeaponAction,{item=replicated})
q=f.queue(head,outgoingA,bagUse)
assert(policy.moveReason(q,bagUse,outgoingA)=='move_shared_item' and policy.moveReason(q,outgoingA,bagUse,true)=='move_shared_item')
assert(policy.cancelOperationReason(q,outgoingA)=='operation_shared_item','owner references still protect changes to the bag itself')
q=f.queue(head,outgoingA,late('Base.Bag_Schoolbag','Base.Rags'))
assert(policy.moveReason(q,q.queue[3],outgoingA)=='move_craft_inputs','future bag consumption still intersects the owner type')
f.player.inventory.load=48
both(outgoingA,outgoingB,'container_capacity')
local blockedCapacity=policy.evaluateMove(f.queue(head,outgoingA,outgoingB),outgoingB,outgoingA)
assert(blockedCapacity.blocker==outgoingA and blockedCapacity.resource==f.player.inventory)
f.player.inventory.load=nil
bagInventory.load,bagInventory.capacity=8,10
both(incomingA,incomingB,'container_capacity')
bagInventory.load=9.5
both(outgoingA,incomingB,'container_capacity') -- No credit for the first transfer freeing bag space.
bagInventory.load,bagInventory.capacity=nil,nil
local prefix=f.action(ISInventoryTransferAction,{item=f.item('Base.Hammer'),srcContainer=f.player.inventory,destContainer=bagInventory})
prefix.item.weight=48
q=f.queue(head,prefix,incomingA,incomingB)
assert(policy.moveReason(q,incomingB,incomingA)=='container_capacity','earlier incoming transfers count too')
prefix.item.weight=1
prefix.queueList={{items={prefix.item,f.item('Base.Anvil')}}}
prefix.queueList[1].items[2].weight=48
assert(policy.moveReason(q,incomingB,incomingA)=='container_capacity','all native batched items count, not just the visible item')
prefix.queueList={{items={prefix.item}}}
f.player.inventory.capacity=4.02;bagInventory.capacity=4.02
assert(not policy.moveReason(q,incomingB,incomingA),'current item is counted once within its own native batch')
f.player.inventory.capacity,bagInventory.capacity=nil,nil
prefix.queueList=nil
q=f.queue(head,late('Base.Sheet','Base.SheetRope'),incomingA,incomingB)
assert(policy.moveReason(q,incomingB,incomingA)=='container_capacity','unbounded weight effects in the prefix remain a barrier')
bagInventory.acceptItem='Mod.contentsDependentAccept'
both(incomingA,incomingB,'container_capacity')
bagInventory.acceptItem=nil
for _,weight in ipairs({-1,math.huge,0/0}) do itemA.weight=weight;both(incomingA,incomingB,'container_capacity') end
itemA.weight=2
for _,kind in ipairs({'Base.CandleLit','Base.Lantern_HurricaneLit','Mod.CandleLit','Mod.Lantern_HurricaneLit'}) do
    local lit=f.action(ISInventoryTransferAction,{item=f.item(kind),srcContainer=f.player.inventory,destContainer=bagInventory})
    both(lit,incomingB,'container_capacity')
end
bagInventory.load,bagInventory.capacity=6.999,10
both(incomingA,incomingB,'container_capacity') -- Native rounds the existing load at each step.
bagInventory.load,bagInventory.capacity=nil,nil
q=f.queue(head,outgoingA,outgoingB)
outgoingA.isValid=function()error('capacity proof must never call action validity')end
assert(policy.moveReason(q,outgoingA,outgoingB,true)=='move_dependent')
outgoingA.isValid=nil
both(outgoingA,outgoingB)
local sequence, weightReads = {head}, 0
for i=1,12 do
    local item=f.item('Base.Nails')
    item.getUnequippedWeight=function()weightReads=weightReads+1;return 0.1 end
    sequence[#sequence+1]=f.action(ISInventoryTransferAction,{item=item,srcContainer=bagInventory,destContainer=f.player.inventory})
end
local many=f.queue(unpack(sequence))
assert(not policy.cancelOperationReason(many,sequence[2]) and weightReads==12,
    'one cancellation decision computes capacity once for the whole sequence')
weightReads=0
assert(not policy.moveReason(many,sequence[#sequence],sequence[2]) and weightReads==12,
    'one move decision computes capacity once across multiple crossed transfers')
print('Shared bag references: stable owners, aggregate native capacity, batches, prefix effects and cancellation passed.')
instanceof=baseInstanceof
