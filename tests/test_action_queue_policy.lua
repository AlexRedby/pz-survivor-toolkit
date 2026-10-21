if not NativeActionRoot then print('Policy native contracts SKIP (pass --native-action-root).');return end
next = nil -- PZ Kahlua has no global next; capacity checks must work without it.
local function readNative(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local changedBaseSource=false
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
getGameFilesInput=function(path)
    local text=readNative(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
    if changedBaseSource and path:find('ISBaseTimedAction.lua',1,true) then text=text..'-- unreviewed base source\n' end
    local position=1
    return {close=function()end,readLine=function()
        if position>#text then return end
        local boundary=text:find('\n',position,true) or #text+1
        local line=text:sub(position,boundary-1);position=boundary+1;return line
    end}
end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/Fluids/ISFluidContainer.lua')
f.native('shared/Fluids/ISFluidTransferAction.lua')
f.native('shared/Fluids/ISFluidEmptyAction.lua')
f.native('shared/TimedActions/ISTransferAction.lua')
f.native('shared/TimedActions/ISDrinkFluidAction.lua')
isClient=function()return false end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local originalItem=f.item
f.item=function(kind)
    local item=originalItem(kind)
    item.getUnequippedWeight=function(self)return self.weight or 0.1 end
    item.getType=function(self)return self:getFullType():match('%.(.+)$') end
    item.getIsCraftingConsumed=function(self)return self.consumed or false end
    return item
end
local function capacity(container)
    container.class='ItemContainer'
    container.getItems=function()
        return {size=function()return 0 end,get=function()end}
    end
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
assert(not policy.cancelOperationReason(q,empty),'removing a pending tail cannot change the shared-resource prefix')
local moveDecision=policy.evaluateMove(q,empty,transfer)
assert(not moveDecision.allowed and moveDecision.blocker==transfer and moveDecision.resource==owner:getID())
local cancelDecision=policy.evaluateCancel(q,empty,true)
assert(cancelDecision.allowed and cancelDecision.first==3 and cancelDecision.last==3)
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
print('Policy native fluid resources, IDs, directional cancellation, unknown lifecycle and async barriers passed.')

-- Decision-local analysis is shared by every check, but never by later decisions or direct inspections.
do
    local definitions=PZSurvivorToolkit.ActionQueueDefinitions
    local originalInspect,originalCraft,originalGenerators=definitions.inspect,PZSurvivorToolkit.ActionQueueCraft,PZSurvivorToolkit.ActionQueueGenerators
    local inspections,collections={},{}
    definitions.inspect=function(action)
        inspections[action]=(inspections[action] or 0)+1
        return originalInspect(action)
    end
    PZSurvivorToolkit.ActionQueueCraft={supports=function()return false end,collectItems=function(action)
        collections[action]=(collections[action] or 0)+1
    end}
    PZSurvivorToolkit.ActionQueueGenerators={sharesTarget=function(a,b,context)
        -- The generator power-scope check must reuse the same inspected contracts.
        policy.inspect(a,context);policy.inspect(b,context)
    end}
    local independent=f.action(ISFluidEmptyAction,{container=vessel()})
    local queue=f.queue(head,transfer,independent)
    local result=policy.evaluateMove(queue,independent,transfer)
    assert(result.allowed and result.to==2 and result.first==3 and result.last==3)
    assert(inspections[independent]==1 and inspections[transfer]==1
        and collections[independent]==1 and collections[transfer]==1,'move analyzes each action once across resource and target checks')
    inspections,collections={},{}
    result=policy.evaluatePriority(queue,independent,true)
    assert(result.allowed and result.to==2 and result.after and result.target==head)
    assert(inspections[independent]==1 and inspections[head]==1 and inspections[transfer]==1,
        'priority fallback shares analysis with the failed preemption attempt')
    inspections,collections={},{}
    result=policy.evaluateCancel(queue,independent)
    assert(result.allowed and result.first==3 and result.last==3)
    assert(inspections[independent]==1 and collections[independent]==1,
        'delegated cancellation analyzes the removed operation once')
    assert(not inspections[head] and not inspections[transfer] and not collections[head] and not collections[transfer],
        'side-effect-free pending removal does not inspect the unchanged prefix')
    independent.container=source
    inspections,collections={},{}
    result=policy.evaluateMove(queue,independent,transfer)
    assert(result.reason=='move_shared_item' and result.blocker==transfer and result.resource==owner:getID(),
        'next decision observes changed resources and preserves blocker/resource')
    assert(inspections[independent]==1 and inspections[transfer]==1)
    independent.container=vessel()
    independent.updateEmpty=function()error('must never execute replaced helpers')end
    assert(policy.evaluateMove(queue,independent,transfer).reason=='move_dependent','next decision revalidates helpers')
    independent.updateEmpty=nil
    assert(policy.evaluateMove(queue,independent,transfer).allowed,'restored helper restores the next decision')
    local opaque=f.action(ISBaseTimedAction:derive('OpaqueAnalysis'))
    inspections={}
    assert(policy.cancelReason(f.queue(head,opaque),opaque)=='dependent' and inspections[opaque]==1,
        'a negative contract is analyzed once even across cancellation fallback checks')
    independent.container=vessel()
    ISTimedActionQueue.queues[f.player]=queue
    local getOwner=independent.container.fluidContainer.getOwner
    independent.container.fluidContainer.getOwner=function()error('removed fluid owner')end
    inspections={}
    assert(policy.cancelReason(queue,independent)=='dependent' and inspections[independent]==1,
        'failed resource inspection remains closed and is cached within the decision')
    independent.container.fluidContainer.getOwner=getOwner
    assert(policy.evaluateCancel(queue,independent).allowed,'inspection errors do not leak state to the next decision')
    assert(policy.inspect(independent))
    independent.updateEmpty=function()end
    assert(not policy.inspect(independent),'direct inspection is always fresh')
    independent.updateEmpty=nil
    assert(policy.inspect(independent),'direct inspection observes restored helpers')
    definitions.inspect=originalInspect
    PZSurvivorToolkit.ActionQueueCraft,PZSurvivorToolkit.ActionQueueGenerators=originalCraft,originalGenerators
end
print('Policy decision-local positive/negative contracts, item collection, fresh resources/helpers and direct inspection passed.')

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
local function blocked(other,reason,pendingTail)
    q=f.queue(head,first,other)
    assert(policy.moveReason(q,other,first)==reason and policy.moveReason(q,first,other,true)==reason)
    local cancel = reason == 'move_shared_item' and 'operation_shared_item' or 'operation_dependent'
    assert(policy.cancelOperationReason(q,first)==cancel,'earlier resource producer/consumer remains protected against its suffix')
    if pendingTail then
        assert(not policy.cancelOperationReason(q,other),'native pending tail removal does not depend on the earlier craft')
    else
        assert(policy.cancelOperationReason(q,other)==cancel,'contracts outside pure pending removal retain conservative cancellation')
    end
end
blocked(late('Base.Material','Base.Other'),'move_craft_inputs')
blocked(late('Base.Product','Base.Other'),'move_craft_inputs')
blocked(late('Base.Other','Base.Material'),'move_craft_inputs')
blocked(late('Base.Other','Base.Product'),'move_craft_inputs')
blocked(f.action(ISInventoryTransferAction,{item=f.item('Base.Material')}),'move_craft_inputs',true)
blocked(f.action(ISInventoryTransferAction,{item=f.item('Base.Product')}),'move_craft_inputs',true)
local selected=f.item('Base.Material')
first.items=list(selected)
blocked(f.action(ISInventoryTransferAction,{item=selected}),'move_shared_item',true)
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
-- Kahlua logs assert before pcall catches it; redraw rejection must use ordinary returns.
local function withoutAssertions(callback)
    local originalAssert, calls = assert, 0
    assert = function(...) calls = calls + 1; return originalAssert(...) end
    local ok, result = pcall(callback)
    assert = originalAssert
    assert(ok, result)
    assert(calls == 0, 'craft inspection must not invoke assert (Kahlua logs caught assertions): ' .. calls)
    return result
end
for _, actionType in ipairs({'handcraft', 'legacy'}) do
    for _, method in ipairs({'isItemType', 'getReplaceOnUse', 'getReplaceOnDeplete', 'getOnBreak'}) do
        local rejected = actionType == 'handcraft' and late('Base.Other', 'Base.Unrelated')
            or f.action(ISCraftAction, {item=f.item('Base.Material'), recipe=legacyRecipe})
        local inputScript = scripts[actionType == 'handcraft' and 'Base.Other' or 'Base.Material']
        if actionType == 'handcraft' then
            local inputs = rejected.craftRecipe:getInputs()
            local input = inputs:get(0)
            inputScript = input:getPossibleInputItems():get(0)
            input.getPossibleInputItems = function() return list(inputScript) end
            rejected.craftRecipe.getInputs = function() return inputs end
        end
        local previous = inputScript[method]
        inputScript[method] = function() return method == 'isItemType' and true or 'Base.Bottle' end
        local redrawQueue = f.queue(head, rejected, second)
        for redraw = 1, 3 do
            local checked = withoutAssertions(function()
                return {resources=Craft.futureResources(rejected), contract=policy.inspect(rejected),
                    rejectedCancel=policy.evaluateCancel(redrawQueue, rejected, true),
                    cancel=policy.evaluateCancel(redrawQueue, second, true),
                    move=policy.evaluateMove(redrawQueue, second, rejected)}
            end)
            assert(not checked.resources and not checked.contract.knownInputs and checked.contract.unknownOutputs,
                actionType .. ' ' .. method .. ' keeps unknown craft effects protected')
            assert(not checked.cancel.allowed and checked.cancel.reason == 'operation_dependent')
            assert(not checked.rejectedCancel.allowed and checked.rejectedCancel.reason == 'operation_dependent')
            assert(not checked.move.allowed and checked.move.reason == 'move_craft_inputs')
        end
        inputScript[method] = previous
    end
end
q = f.queue(head, legacy, second)
local accepted = withoutAssertions(function()
    return {resources=Craft.futureResources(legacy), contract=policy.inspect(first),
        cancel=policy.evaluateCancel(q, second, true), move=policy.evaluateMove(q, second, legacy)}
end)
assert(accepted.resources.dynamicInputs['Base.Material'] and accepted.resources.outputTypes['Base.Product'])
assert(accepted.contract.knownInputs and not accepted.contract.unknownOutputs and accepted.cancel.allowed and accepted.move.allowed,
    'valid native handcraft and legacy resource contracts still permit independent operations')
local partial = late('Base.Other', 'Base.Unrelated')
local partialOutputs = partial.craftRecipe:getOutputs()
partialOutputs:get(0).getPossibleResultItems = function() return list(script('Base.Unrelated'), script('Malformed')) end
partial.craftRecipe.getOutputs = function() return partialOutputs end
local rejectedPartial = withoutAssertions(function()
    return {resources=Craft.futureResources(partial), contract=policy.inspect(partial)}
end)
assert(not rejectedPartial.resources and not rejectedPartial.contract.knownInputs and rejectedPartial.contract.unknownOutputs,
    'a late invalid output cannot expose a partially populated craft resource contract')
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
PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('fixture.cleanup-phase',{types={'GuardedCleanup'},
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
assert(not policy.inspect(nativeTransfer) and not policy.preparationCanFinish(nativeTransfer),'cyclic bag ancestry remains protected')
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
    assert(policy.cancelOperationReason(queue,a)==reason,'transfer cancellation retains suffix capacity checks: '..tostring(reason))
    assert(not policy.cancelOperationReason(queue,b),'pending tail removal cannot invalidate earlier transfers')
end
both(outgoingA,outgoingB);both(incomingA,incomingB);both(outgoingA,incomingB)
-- Equipment weight can invalidate a transfer of a different item, even with only one transfer.
f.native('shared/TimedActions/ISUnequipAction.lua');f.native('shared/TimedActions/ISEquipHeavyItem.lua');policy.installContracts()
for _,class in ipairs({ISEquipWeaponAction,ISUnequipAction,ISEquipHeavyItem}) do
    local equipment=f.action(class,{item=f.item('Base.Bag_DuffelBag')})
    local q=f.queue(head,outgoingA,equipment)
    assert(policy.moveReason(q,outgoingA,equipment,true)=='container_capacity')
    assert(policy.moveReason(q,equipment,outgoingA)=='container_capacity')
    assert(policy.cancelOperationReason(q,outgoingA)=='container_capacity')
    local result=policy.evaluateMove(q,equipment,outgoingA)
    assert(result.blocker==outgoingA and result.resource==f.player.inventory)
    local book=f.action(ISReadABook,{item=f.item('Base.BookFirstAid1')})
    assert(not policy.moveReason(f.queue(head,equipment,book),book,equipment),'unrelated reading stays reorderable')
    local other=f.action(ISEquipWeaponAction,{item=f.item('Base.Screwdriver')})
    assert(policy.moveReason(f.queue(head,equipment,other),other,equipment)=='move_dependent','hand dependencies remain protected')
    equipment.complete=function()end
    assert(policy.moveReason(f.queue(head,outgoingA,equipment),equipment,outgoingA)=='move_dependent','foreign equipment remains closed')
end
print('Equipment/transfer capacity barrier and independent reading passed.')
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
q=f.queue(head,incomingA,incomingB)
assert(policy.moveReason(q,incomingA,incomingB,true)=='move_dependent'
    and policy.moveReason(q,incomingB,incomingA)=='move_dependent')
assert(policy.cancelOperationReason(q,incomingA)=='operation_dependent'
    and policy.cancelOperationReason(q,incomingB)=='operation_dependent',
    'unknown acceptance callback effects must protect the entire transfer contract')
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
-- All ancestors are resources, but their contents can still move independently.
bag2.getContainer=function()return bagInventory end
local deepOut=f.action(ISInventoryTransferAction,{item=f.item('Base.Nails'),srcContainer=secondBagInventory,destContainer=f.player.inventory})
local deepIn=f.action(ISInventoryTransferAction,{item=f.item('Base.Thread'),srcContainer=f.player.inventory,destContainer=secondBagInventory})
local deepContract=assert(policy.inspect(deepOut))
assert(deepContract.containerOwners[carriedBag.id] and deepContract.containerOwners[bag2.id])
both(deepOut,deepIn)
q=f.queue(head,deepOut,bagUse)
assert(policy.moveReason(q,bagUse,deepOut)=='move_shared_item' and policy.cancelOperationReason(q,deepOut)=='operation_shared_item')
bagInventory.load,bagInventory.capacity=49.95,50
both(deepOut,deepIn,'container_capacity')
bagInventory.load,bagInventory.capacity=nil,nil
bag2.getContainer=function()return secondBagInventory end
assert(not policy.inspect(deepOut),'cycle closes native deep transfer permission')
bag2.getContainer=function()return bagInventory end

-- Proposed order must retain the pickup that makes room. Never credit a skipped, cancelled or rejected pickup.
f.player.getVehicle=function()end
f.player.inventory.getOnlyAcceptCategory=function()end
local free=f.item('Base.Hammer');free.weight=2;free.getContainer=function()return bagInventory end
bagInventory.contains=function(_,item)return item==free end
local release=f.action(ISInventoryTransferAction,{item=free,srcContainer=bagInventory,destContainer=f.player.inventory})
local fill=f.action(ISInventoryTransferAction,{item=f.item('Base.Thread'),srcContainer=f.player.inventory,destContainer=bagInventory})
local extra=f.action(ISInventoryTransferAction,{item=f.item('Base.Nails'),srcContainer=f.player.inventory,destContainer=bagInventory})
bagInventory.load,bagInventory.capacity=10,10
q=f.queue(head,release,fill,extra)
assert(not policy.moveReason(q,extra,fill) and not policy.moveReason(q,fill,extra,true),'independent fills may swap after guaranteed release')
local unordered=f.queue(head,fill,release,extra)
assert(not policy.moveReason(unordered,release,fill),'moving the release first repairs an invalid original order')
assert(policy.moveReason(q,fill,release)=='container_capacity' and policy.moveReason(q,release,fill,true)=='container_capacity',
    'moving fill before its release is rejected in either drag direction')
assert(policy.cancelOperationReason(q,release)=='container_capacity','cancel cannot remove required released space')
assert(not policy.cancelOperationReason(q,extra),'unrelated cancellation retains the preceding release')
free.consumed=true
assert(policy.moveReason(q,extra,fill)=='container_capacity');free.consumed=false
bagInventory.contains=function()return false end
assert(policy.moveReason(q,extra,fill)=='container_capacity');bagInventory.contains=function(_,item)return item==free end
isClient=function()return true end
assert(policy.moveReason(q,extra,fill)=='container_capacity','MP rejection forbids speculative free space');isClient=function()return false end
local nativeTransfer=ISTransferAction.transferItem
ISTransferAction.transferItem=function()end
assert(policy.moveReason(q,extra,fill)=='container_capacity','changed global native transfer helper forbids free-space proof')
ISTransferAction.transferItem=nativeTransfer
local nativeTransferClass=ISTransferAction;ISTransferAction=nil
assert(policy.moveReason(q,extra,fill)=='container_capacity','missing global helper closes the proof without an exception')
ISTransferAction=nativeTransferClass
local nativeInstanceof=instanceof
instanceof=function(value,name)return (value==free and name=='AnimalInventoryItem') or nativeInstanceof(value,name) end
assert(policy.moveReason(q,extra,fill)=='container_capacity','animal rejection cannot release bag space')
instanceof=nativeInstanceof
f.player.getVehicle=function()return {} end
assert(policy.moveReason(q,extra,fill)=='container_capacity');f.player.getVehicle=function()end
f.player.inventory.getOnlyAcceptCategory=function()return 'Food' end
assert(policy.moveReason(q,extra,fill)=='container_capacity');f.player.inventory.getOnlyAcceptCategory=function()end
local prior=f.action(ISInventoryTransferAction,{item=free,srcContainer=bagInventory,destContainer=secondBagInventory})
-- Earlier relocation makes the later bag-to-root pickup a no-op, even though its current source still matches.
bag2.getContainer=function()return f.player.inventory end
q=f.queue(head,prior,release,fill,extra)
assert(policy.moveReason(q,extra,fill)=='container_capacity','earlier relocation must invalidate outgoing credit')
local repeated=f.action(ISInventoryTransferAction,{item=free,srcContainer=bagInventory,destContainer=f.player.inventory})
fill.item.weight,extra.item.weight=1.3,1.3
q=f.queue(head,release,repeated,fill,extra)
assert(policy.moveReason(q,extra,fill)=='container_capacity','a duplicate pickup cannot release the same space twice')
fill.item.weight,extra.item.weight=nil,nil
local reads,capacityWeight=0,bagInventory.getCapacityWeight
bagInventory.getCapacityWeight=function(self)reads=reads+1;return capacityWeight(self)end
q=f.queue(head,release,fill,extra)
assert(not policy.moveReason(q,extra,fill) and reads==1,'scan each container weight once per decision')
bagInventory.getCapacityWeight=capacityWeight
local previousTransfer,delegation=ISTransferAction.transferItem,true
local replacementTransfer=function(...)return previousTransfer(...)end
local function unchangedDelegate()return delegation end
assert(not policy.adoptTransferItemHelper(previousTransfer,replacementTransfer,unchangedDelegate),'replacement must already be installed')
ISTransferAction.transferItem=replacementTransfer
assert(not policy.adoptTransferItemHelper(nil,replacementTransfer,unchangedDelegate),'missing original cannot be adopted')
assert(not policy.adoptTransferItemHelper(function()end,replacementTransfer,unchangedDelegate),'unknown original cannot be adopted')
assert(policy.adoptTransferItemHelper(previousTransfer,replacementTransfer,unchangedDelegate))
assert(not policy.moveReason(q,extra,fill),'verified Tidy wrapper retains released-space proof')
delegation=false
assert(policy.moveReason(q,extra,fill)=='container_capacity','changed Tidy delegation cannot grant outgoing credit')
delegation=true
assert(not policy.moveReason(q,extra,fill))
bagInventory.load,bagInventory.capacity=nil,nil
print('Container policy: ancestor identities/cycles/capacity, proposed order, released-space cancellation and changed/missing/MP inputs passed.')
instanceof=baseInstanceof

do
    f.project('ActionQueueLabels')
    local api=f.project('ActionQueue')
    local source,target=vessel(),vessel()
    local prefix=f.action(ISFluidTransferAction,{source=source,target=target,amount=3,sourceStartAmount=5})
    local waiting=f.action(ISFluidEmptyAction,{container=source,amount=5})
    local queue=f.queue(head,prefix,waiting)
    local emptied=0
    source.fluidContainer.Empty=function(self)emptied=emptied+1;self.amount=0 end
    local token=waiting.toolkitQueueOperation
    assert(api.cancelOperation(queue,waiting) and #queue.queue==2 and queue.queue[1]==head and queue.queue[2]==prefix
        and queue.current==head,'cancel shared-resource tail through the real queue operation without changing its prefix')
    assert(token.toolkitCancelled and not prefix.toolkitQueueOperation.toolkitCancelled
        and not head.toolkitQueueOperation.toolkitCancelled,'only the removed operation is invalidated')
    assert(emptied==0 and source.fluidContainer.amount==5 and target.fluidContainer.amount==5
        and prefix.source==source and prefix.target==target and prefix.amount==3 and prefix.sourceStartAmount==5,
        'pending removal neither calls native completion nor spends fluid or rewrites preceding transfer data')
    local control=f.action(ISFluidEmptyAction,{container=source,amount=5})
    assert(control:complete() and emptied==1 and source.fluidContainer.amount==0,
        'the unchanged native completion performs the observed resource mutation only when explicitly executed')
    source.fluidContainer.amount=5
    waiting=f.action(ISFluidEmptyAction,{container=source,amount=5})
    queue=f.queue(head,prefix,waiting)
    token=waiting.toolkitQueueOperation
    token.toolkitStarted=true
    assert(not api.cancelOperation(queue,waiting) and policy.cancelOperationReason(queue,waiting)=='operation_active'
        and #queue.queue==3 and not token.toolkitCancelled,'a started token cannot claim pending removal')
    token.toolkitStarted=nil
    local continuation=PZSurvivorToolkit.ActionQueueOperations.attachContinuation(token,f.player)
    assert(not api.cancelOperation(queue,waiting) and policy.cancelOperationReason(queue,waiting)=='operation_dependent'
        and #queue.queue==3 and not token.toolkitCancelled,'a pending continuation keeps its operation intact')
    PZSurvivorToolkit.ActionQueueOperations.finishContinuation(continuation)
    local callbacks=0
    waiting.onCancelFunc=function()callbacks=callbacks+1 end
    assert(not api.cancelOperation(queue,waiting) and #queue.queue==3 and callbacks==0
        and not token.toolkitCancelled,'unverified cancellation callbacks remain protected and are never invoked')
    waiting.onCancelFunc=nil
    waiting.forceCancel=function()callbacks=callbacks+1 end
    assert(not api.cancelOperation(queue,waiting) and #queue.queue==3 and callbacks==0
        and not token.toolkitCancelled,'a substituted forceCancel cannot grant pending removal')
    waiting.forceCancel=nil
    local guardedClass=ISBaseTimedAction:derive('GuardedPendingCancellation')
    PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('fixture.pending-cancellation-callback',{
        types={'GuardedPendingCancellation'},matches=function(action)return getmetatable(action)==guardedClass end,
        inspect=function(action)return {items={},targets={},cancelWaiting=true,callbacksSafe=true,forceCancel=action.forceCancel}end,
    })
    for _,field in ipairs({'onCancelFunc','forceCancel'})do
        local guarded=f.action(guardedClass)
        guarded.toolkitQueueOperation=token
        guarded[field]=function()callbacks=callbacks+1 end
        local grouped=f.queue(head,prefix,waiting,guarded)
        assert(policy.cancelOperationReason(grouped,waiting)=='operation_shared_item' and not api.cancelOperation(grouped,waiting)
            and #grouped.queue==4 and callbacks==0 and not token.toolkitCancelled,
            'every operation member must prove native no-effect removal, including audited '..field)
    end
    assert(not policy.cancelOperationReason(queue,waiting),'restored native cancellation permits the pending tail again')
    queue=f.queue(head,waiting,prefix)
    assert(policy.cancelOperationReason(queue,waiting)=='operation_shared_item' and not api.cancelOperation(queue,waiting)
        and #queue.queue==3 and not token.toolkitCancelled,'removing an earlier shared-resource action still checks its downstream consumer')
    local consumer=f.action(ISFluidEmptyAction,{container=target,amount=5})
    queue=f.queue(head,prefix,consumer)
    assert(policy.cancelOperationReason(queue,prefix)=='operation_shared_item' and not api.cancelOperation(queue,prefix)
        and #queue.queue==3 and queue.queue[2]==prefix and queue.queue[3]==consumer
        and not prefix.toolkitQueueOperation.toolkitCancelled and source.fluidContainer.amount==5
        and target.fluidContainer.amount==5,'removing a pending producer still protects its downstream target consumer')
    print('Pending cancellation: native resource effects, exact prefix, tokens, continuations, callbacks and downstream dependencies passed.')
end

do
    f.project('ActionQueueLabels')
    local api=f.project('ActionQueue')
    local function drink()
        local item,fluid=f.item('Base.WaterBottle'),{class='FluidContainer'}
        item.getFluidContainer=function()return fluid end
        return f.action(ISDrinkFluidAction,{item=item,fluidContainer=fluid})
    end
    local first,waiting,tail=drink(),drink(),drink()
    local queue=f.queue(first,waiting,tail)
    local contract,source=policy.inspect(waiting)
    assert(source=='native.ISDrinkFluidAction' and contract.items[waiting.item:getID()]
        and contract.cancelWaiting and contract.interrupt=='finish-step' and not policy.stoppable(waiting),
        'native drinking supports waiting cancellation without stopping partial effects')
    assert(api.move(queue,waiting,tail,true) and queue.queue[2]==tail and queue.queue[3]==waiting,
        'independent waiting drink moves after the tail')
    assert(api.move(queue,waiting,tail,false) and queue.queue[2]==waiting and queue.queue[3]==tail,
        'independent waiting drink returns to its original position')
    assert(api.cancelOperation(queue,waiting) and #queue.queue==2 and queue.queue[1]==first and queue.queue[2]==tail,
        'cancel an independent waiting drink without removing either unrelated drink')
    assert(waiting.toolkitQueueOperation.toolkitCancelled and not first.toolkitQueueOperation.toolkitCancelled
        and not tail.toolkitQueueOperation.toolkitCancelled,'drink cancellation invalidates only its own operation')
    waiting=drink()
    queue=f.queue(first,waiting,tail)
    local independent=tail.item
    tail.item=drink().item;tail.item.id=waiting.item:getID()
    local independentFluid=tail.fluidContainer;tail.fluidContainer=tail.item:getFluidContainer()
    assert(policy.moveReason(queue,waiting,tail,true)=='move_shared_item' and not api.move(queue,waiting,tail,true)
        and queue.queue[2]==waiting and queue.queue[3]==tail,'shared-bottle move preserves order')
    assert(policy.cancelOperationReason(queue,waiting)=='operation_shared_item' and not api.cancelOperation(queue,waiting)
        and #queue.queue==3,'replicated references to the same bottle protect waiting cancellation')
    tail.item=independent
    tail.fluidContainer=independentFluid
    for _,fluid in ipairs({false,tail.fluidContainer}) do
        waiting.fluidContainer=fluid or nil
        assert(not policy.inspect(waiting) and policy.cancelOperationReason(queue,waiting)=='operation_dependent',
            'missing or unrelated fluid containers cannot claim the bottle resource contract')
    end
    waiting.fluidContainer=waiting.item:getFluidContainer()
    for _,method in ipairs({'updateEat','start','isValidStart','animEvent','onCompleteFunc'}) do
        waiting[method]=function()error('policy must never invoke drink callbacks')end
        assert(not policy.inspect(waiting) and policy.cancelOperationReason(queue,waiting)=='operation_dependent'
            and not api.cancelOperation(queue,waiting) and #queue.queue==3,'changed drink '..method..' must fail closed')
        waiting[method]=nil
    end
    queue=f.queue(waiting,tail)
    assert(policy.cancelOperationReason(queue,waiting)=='operation_active' and not api.cancelOperation(queue,waiting)
        and #queue.queue==2,'active drinking remains protected because its effects can be partial')
    print('Drink policy: independent waiting cancellation, stable bottle IDs, changed callbacks and active protection passed.')
end

do
    local api=PZSurvivorToolkit.ActionQueue
    local oldInstanceof,oldFluid=instanceof,Fluid
    instanceof=function(value,name)
        return oldInstanceof(value,name) or (name=='IsoGameCharacter' and value==f.player)
            or (name=='InventoryItem' and value==carriedBag)
    end
    Fluid={Water={}}
    local effects={'getFatigueChange','getHungerChange','getStressChange','getUnhappyChange','getCalories',
        'getCarbohydrates','getLipids','getProteins','getAlcohol','getPoison','getFluReduction','getPainReduction',
        'getEnduranceChange','getFoodSicknessChange'}
    local function operation()
        local item=f.item('Base.WaterBottle');item.weight=1
        item.getContainer=function()return bagInventory end
        local properties={getThirstChange=function()return -.5 end}
        for _,method in ipairs(effects)do properties[method]=function()return 0 end end
        local fluid={class='FluidContainer',amount=1,capacity=1,ratio=1,pure=true,tainted=false,poisonous=false,
            getAmount=function(self)return self.amount end,getFilledRatio=function(self)return self.ratio end,
            getCapacity=function(self)return self.capacity end,
            isPureFluid=function(self,value)return self.pure and value==Fluid.Water end,
            isTainted=function(self)return self.tainted end,isPoisonous=function(self)return self.poisonous end,
            getProperties=function()return properties end}
        item.getFluidContainer=function()return fluid end
        local token={}
        local pickup=f.action(ISInventoryTransferAction,{item=item,srcContainer=bagInventory,destContainer=f.player.inventory})
        local drink=f.action(ISDrinkFluidAction,{item=item,fluidContainer=fluid,useUtensil=false,percentage=.5,
            startRatio=1,endRatio=.5,targetConsumedRatio=.5,consumedRatio=0})
        local putback=f.action(ISInventoryTransferAction,{item=item,srcContainer=f.player.inventory,destContainer=bagInventory,
            allowMissingItems=true})
        for _,action in ipairs({pickup,drink,putback})do action.toolkitQueueOperation=token end
        return {pickup,drink,putback,fluid=fluid,properties=properties}
    end
    local a,b,c=operation(),operation(),operation()
    local queue=f.queue(a[1],a[2],a[3],b[1],b[2],b[3],c[1],c[2],c[3])
    local previousContains=bagInventory.contains
    bagInventory.contains=function()return true end
    bagInventory.load,bagInventory.capacity=3,50
    f.player.inventory.load,f.player.inventory.capacity=4,50
    assert(not policy.cancelOperationReason(queue,b[2]),'clean-water groups retain an ample capacity proof')
    a.fluid.amount,a.fluid.ratio,a[2].consumedRatio=.75,.75,.25
    assert(not policy.cancelOperationReason(queue,b[2]),'partly consumed native water retains its full current-weight bound')
    a.fluid.amount,a.fluid.ratio,a[2].consumedRatio=1,1,0
    isClient=function()return true end
    assert(not policy.cancelOperationReason(queue,b[2]),'clean-water upper bounds do not require speculative MP pickup credit')
    isClient=function()return false end
    bagInventory.capacity=3
    assert(policy.cancelOperationReason(queue,b[2])=='container_capacity','full bag cannot borrow cancelled pickup space')
    bagInventory.capacity=50;f.player.inventory.capacity=4.5
    assert(policy.cancelOperationReason(queue,b[2])=='container_capacity','drinking does not grant root capacity credit')
    f.player.inventory.capacity=50
    for _,field in ipairs({'pure','tainted','poisonous'})do
        local previous=a.fluid[field];a.fluid[field]=not previous
        assert(policy.cancelOperationReason(queue,b[2])=='container_capacity','unsafe prefix fluid remains a barrier: '..field)
        a.fluid[field]=previous
    end
    for _,method in ipairs(effects)do
        local previous=a.properties[method];a.properties[method]=function()return .1 end
        assert(policy.cancelOperationReason(queue,b[2])=='container_capacity','modified water effect remains a barrier: '..method)
        a.properties[method]=previous
    end
    local thirst=a.properties.getThirstChange
    for _,value in ipairs({.1,math.huge,-math.huge,0/0})do
        a.properties.getThirstChange=function()return value end
        assert(policy.cancelOperationReason(queue,b[2])=='container_capacity','invalid thirst effect remains a barrier')
    end
    a.properties.getThirstChange=thirst
    for _,field in ipairs({'percentage','startRatio','endRatio','targetConsumedRatio','consumedRatio'})do
        local previous=a[2][field]
        for _,value in ipairs({-1,math.huge,0/0,1.1})do
            a[2][field]=value
            assert(policy.cancelOperationReason(queue,b[2])=='container_capacity','invalid consumption bound remains a barrier: '..field)
        end
        a[2][field]=previous
    end
    for _,field in ipairs({'amount','capacity','ratio'})do
        local previous=a.fluid[field]
        for _,value in ipairs({-1,math.huge,0/0})do
            a.fluid[field]=value
            assert(policy.cancelOperationReason(queue,b[2])=='container_capacity','invalid fluid bound remains a barrier: '..field)
        end
        a.fluid[field]=previous
    end
    a.fluid.amount=1.1
    assert(policy.cancelOperationReason(queue,b[2])=='container_capacity','overfilled fluid is outside the bound')
    a.fluid.amount=1
    for _,method in ipairs({'start','updateEat','onCompleteFunc'})do
        a[2][method]=function()error('capacity proof must not execute drink callbacks')end
        assert(policy.cancelOperationReason(queue,b[2]),'changed prefix drink remains protected: '..method)
        a[2][method]=nil
    end
    assert(api.cancelOperation(queue,b[2]) and #queue.queue==6,'cancel removes the whole waiting water operation')
    for i,action in ipairs({a[1],a[2],a[3],c[1],c[2],c[3]})do
        assert(queue.queue[i]==action and not action.toolkitQueueOperation.toolkitCancelled,'first and tail operations retain exact actions')
    end
    assert(b[2].toolkitQueueOperation.toolkitCancelled,'only the cancelled water operation is invalidated')
    bagInventory.load,bagInventory.capacity,bagInventory.contains=nil,nil,previousContains
    f.player.inventory.load,f.player.inventory.capacity=nil,nil
    instanceof,Fluid=oldInstanceof,oldFluid
    print('Drink capacity: grouped native water pickups/returns, full-weight bounds, unsafe fluids and callback barriers passed.')
end

-- The negative broad phase skips only proven-disjoint plain item footprints.
-- Compare every result with the original pair path, forced by an unregistered
-- wrapper, and count the eliminated product for growing native book groups.
do
    local toolkit=PZSurvivorToolkit
    local oldWorld,oldGenerators,oldCraft=toolkit.ActionQueueWorld,toolkit.ActionQueueGenerators,toolkit.ActionQueueCraft
    local pairsChecked,repairsChecked=0,0
    local world={sharesTarget=function()pairsChecked=pairsChecked+1 end}
    local generators={sharesTarget=function()pairsChecked=pairsChecked+1 end}
    toolkit.ActionQueueWorld,toolkit.ActionQueueGenerators=world,generators
    toolkit.ActionQueueCraft={supports=function()return false end,collectItems=function()end,
        repairInputs=function(action)repairsChecked=repairsChecked+1;return action.fixtureRepair end}
    local originalWorld,originalGenerator=world.sharesTarget,generators.sharesTarget
    local function legacy(enabled)
        world.sharesTarget=enabled and function(...)return originalWorld(...)end or originalWorld
    end
    local function books(count)
        local values={head}
        local selected,crossed={},{}
        local firstToken,secondToken={},{}
        for _,group in ipairs({selected,crossed})do
            for i=1,count do
                local action=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
                action.toolkitQueueOperation=group==selected and firstToken or secondToken
                group[i]=action;values[#values+1]=action
            end
        end
        return f.queue(unpack(values)),selected,crossed
    end
    local queue,selected,crossed=books(3)
    assert(policy.previewMove(queue,crossed[1],selected[1]).reason==nil and pairsChecked>0,
        'helpers present before registration must retain the pair path')
    assert(policy.registerTargetChecker('world',world,originalWorld))
    assert(policy.registerTargetChecker('generators',generators,originalGenerator))
    for _,count in ipairs({4,16,48,120})do
        queue,selected,crossed=books(count)
        pairsChecked,repairsChecked=0,0
        local savedNext=next;next=nil
        local move=policy.previewMove(queue,crossed[1],selected[1])
        local cancel=policy.previewCancel(queue,selected[1],true)
        next=savedNext
        assert(not move.reason and not cancel.reason and pairsChecked==0 and repairsChecked<=4*count,
            'independent groups must use linear footprint work without any pair checks or next global')
        legacy(true);pairsChecked=0
        local oldMove=policy.previewMove(queue,crossed[1],selected[1])
        local oldCancel=policy.previewCancel(queue,selected[1],true)
        legacy(false)
        assert(not oldMove.reason and not oldCancel.reason and pairsChecked==4*count*count,
            'unregistered helper retains both original ordered group products')
    end
    local fixture=ISBaseTimedAction:derive('PlainFootprintFixture')
    toolkit.ActionQueueDefinitions.registerBehavior('fixture.plain-footprint',{
        types={'PlainFootprintFixture'},matches=function(action)return getmetatable(action)==fixture end,
        inspect=function(action)return action.fixtureContract end})
    local function plain()
        local action=f.action(fixture,{item=f.item('Base.Fixture')})
        action.fixtureContract={items={[action.item:getID()]=true},itemTypes={['Base.Fixture']=true},
            targets={},knownInputs=true,cancelWaiting=true}
        return action
    end
    local target={class='IsoObject'}
    local variants={
        function(a,b)b.item.id=a.item.id;b.fixtureContract.items={[a.item.id]=true}end,
        function(a,b)a.fixtureContract.containerOwners={[b.item.id]=true}end,
        function(a,b)a.fixtureContract.targets[target]=true;b.fixtureContract.targets[target]=true end,
        function(a,b)a.fixtureContract.dynamicInputs={['Base.Fixture']=true}end,
        function(a,b)a.fixtureContract.dynamicInputsByType={Fixture=true}end,
        function(a,b)a.fixtureContract.outputTypes={['Base.Fixture']=true}end,
        function(a,b)a.fixtureContract.unknownOutputs=true;b.fixtureContract.dynamicInputs={['Base.Fixture']=true}end,
        function(a,b)a.fixtureContract.hands=f.player;b.fixtureContract.equipment=f.player end,
        function(a,b)a.fixtureContract.edit={resources={{domain='fixture',key=target}}}
            b.fixtureContract.edit={resources={{domain='fixture',key=target}}}end,
        function(a,b)a.object=target;b.object=target end,
        function(a,b)a.fixtureRepair={}end,
        function(a,b)setmetatable(a.fixtureContract.items,{})end,
        function(a,b)setmetatable(a.fixtureContract.itemTypes,{})end,
        function(a,b)setmetatable(a.fixtureContract,{})end,
    }
    for index,change in ipairs(variants)do
        local a,b=plain(),plain();change(a,b)
        local owner=f.queue(head,a,b)
        local move=policy.previewMove(owner,a,b,true)
        local cancel=policy.previewCancel(owner,a,true)
        legacy(true)
        local oldMove=policy.previewMove(owner,a,b,true)
        local oldCancel=policy.previewCancel(owner,a,true)
        legacy(false)
        for _,field in ipairs({'reason','blocker','resource','to','first','last','preempt'})do
            assert(move[field]==oldMove[field] and cancel[field]==oldCancel[field],
                'broad phase must preserve exact legacy '..field..' for guarded variant '..index)
        end
    end
    queue,selected,crossed=books(2)
    local hidden={}
    world.sharesTarget=function()return hidden end
    assert(not policy.registerTargetChecker('world',world,world.sharesTarget),'late re-registration cannot authorize an override')
    local denied=policy.previewMove(queue,crossed[1],selected[1])
    assert(denied.reason=='move_dependent' and denied.blocker==selected[1] and denied.resource==true,
        'changed world helper must retain its exact denial and first blocker')
    world.sharesTarget=originalWorld
    generators.sharesTarget=function()return hidden end
    assert(not policy.registerTargetChecker('generators',generators,generators.sharesTarget))
    denied=policy.previewCancel(queue,selected[1],true)
    assert(denied.reason=='operation_dependent' and denied.blocker==crossed[1] and denied.resource==hidden,
        'changed generator helper must retain its exact denial and first blocker')
    generators.sharesTarget=originalGenerator
    toolkit.ActionQueueWorld={sharesTarget=originalWorld}
    pairsChecked=0;policy.previewMove(queue,crossed[1],selected[1])
    assert(pairsChecked>0,'replaced helper owner must retain the pair path even with the same callback')
    toolkit.ActionQueueWorld,toolkit.ActionQueueGenerators,toolkit.ActionQueueCraft=oldWorld,oldGenerators,oldCraft
end
print('Policy negative broad phase: linear independent groups, unchanged pair diagnostics, resource guards and helper provenance passed.')

-- Connectivity uses owner references separately from mutations: two leaf-item
-- transfers in the same bag are independent, but moving that bag connects them.
do
    local toolkit=PZSurvivorToolkit
    local previousPolicy,previousRequire,previousDefinitions=toolkit.ActionQueuePolicy,require,toolkit.ActionQueueDefinitions
    f.project('ActionQueueDefinitions')
    local model=f.project('ActionQueueEditModel')
    require=function(name)
        if name=='PZSurvivorToolkit/ActionQueueEditModel' then return model end
        return previousRequire(name)
    end
    local indexed=f.project('ActionQueuePolicy');require=previousRequire
    local previousWorld,previousGenerators,previousCraft=toolkit.ActionQueueWorld,toolkit.ActionQueueGenerators,toolkit.ActionQueueCraft
    local checks,footprints=0,0
    local world={sharesTarget=function()checks=checks+1 end}
    local generators={sharesTarget=function()checks=checks+1 end}
    toolkit.ActionQueueWorld,toolkit.ActionQueueGenerators=world,generators
    toolkit.ActionQueueCraft={supports=function()return false end,collectItems=function()end,
        repairInputs=function(action)footprints=footprints+1;return action.fixtureRepair end}
    indexed.registerTargetChecker('world',world,world.sharesTarget)
    indexed.registerTargetChecker('generators',generators,generators.sharesTarget)
    local originalWorld=world.sharesTarget
    local function legacy(enabled)world.sharesTarget=enabled and function(...)return originalWorld(...)end or originalWorld end
    local class=ISBaseTimedAction:derive('ConnectivityTransferFixture')
    toolkit.ActionQueueDefinitions.registerBehavior('fixture.connectivity-transfer',{
        types={'ConnectivityTransferFixture'},matches=function(action)return getmetatable(action)==class end,
        inspect=function(action)return action.fixtureContract end})
    local bagID=f.item('Base.Bag_Schoolbag'):getID()
    local function transfer()
        local action=f.action(class,{item=f.item('Base.Nails')})
        action.fixtureContract={items={[action.item:getID()]=true},itemTypes={['Base.Nails']=true},targets={},
            containerOwners={[bagID]=true},knownInputs=true,cancelWaiting=true,
            edit={version=1,complete=true,capacity='unchanged',resources={{domain='item',key=action.item:getID(),
                facts={ready=false},requires={},effects={{field='ready',set=true}}}}}}
        return action
    end
    local function sameResult(a,b)
        for _,key in ipairs({'reason','blocker','resource','to','first','last','preempt'})do
            assert(a[key]==b[key],'indexed connectivity must preserve exact legacy '..key)
        end
    end
    for _,count in ipairs({4,16,48,120})do
        local values,selected,crossed={head},{},{}
        for _,group in ipairs({selected,crossed})do
            local token={}
            for i=1,count do local action=transfer();action.toolkitQueueOperation=token
                group[i]=action;values[#values+1]=action end
        end
        local queue=f.queue(unpack(values))
        checks,footprints=0,0
        local move=indexed.previewMove(queue,crossed[1],selected[1])
        local cancel=indexed.previewCancel(queue,selected[1],true)
        assert(not move.reason and not cancel.reason and checks==0 and footprints<=4*count+2,
            'independent declared transfers sharing a bag require linear connectivity work')
        legacy(true);checks=0
        local oldMove=indexed.previewMove(queue,crossed[1],selected[1])
        local oldCancel=indexed.previewCancel(queue,selected[1],true)
        legacy(false)
        sameResult(move,oldMove);sameResult(cancel,oldCancel)
        assert(checks==4*count*(count+1),'changed helper must retain the original component product')
    end
    local marker={}
    local variants={
        function(a,b)b.fixtureContract.items[a.item.id]=true end,
        function(a,b)b.fixtureContract.containerOwners[a.item.id]=true end,
        function(a,b)a.fixtureContract.containerOwners[b.item.id]=true end,
        function(a,b)b.fixtureContract.edit.resources[1].key=a.fixtureContract.edit.resources[1].key
            b.fixtureContract.edit.resources[1].requires={{field='ready',equal=true}}end,
        function(a,b)a.fixtureContract.targets[marker]=true;b.fixtureContract.targets[marker]=true end,
        function(a,b)a.fixtureContract.dynamicInputs={['Base.Nails']=true}end,
        function(a,b)a.fixtureContract.dynamicInputsByType={Nails=true}end,
        function(a,b)a.fixtureContract.unknownOutputs=true end,
        function(a,b)a.fixtureRepair={}end,
        function(a,b)a.fixtureContract.edit.version=2 end,
        function(a,b)setmetatable(a.fixtureContract.edit.resources[1],{})end,
    }
    for _,change in ipairs(variants)do
        local a,b=transfer(),transfer();change(a,b)
        local queue=f.queue(head,a,b)
        local move=indexed.previewMove(queue,a,b,true)
        local cancel=indexed.previewCancel(queue,a,true)
        legacy(true)
        sameResult(move,indexed.previewMove(queue,a,b,true))
        sameResult(cancel,indexed.previewCancel(queue,a,true))
        legacy(false)
    end
    -- The index must grow when a simple member joins, then fall back entirely
    -- when a complex bridge joins. Check the actual projected member order.
    local evaluate=model.evaluate
    local projected
    model.evaluate=function(entries)projected=entries;return evaluate(entries)end
    for _,complex in ipairs({false,true})do
        local a,b,c=transfer(),transfer(),transfer()
        if complex then
            b.fixtureContract.items[a.item.id]=true
            b.fixtureContract.targets[marker]=true;c.fixtureContract.targets[marker]=true
        else
            b.fixtureContract.edit.resources[2]={domain='link',key=marker,facts={ready=false},requires={},effects={}}
            c.fixtureContract.edit.resources[2]={domain='link',key=marker,facts={ready=false},requires={},effects={}}
            b.fixtureContract.edit.resources[1].key=a.item.id
        end
        local queue=f.queue(head,c,b,a)
        local result=indexed.previewCancel(queue,a,true)
        assert(not result.reason and #projected==3 and projected[1].action==c
            and projected[2].action==b and projected[3].action==a,
            'connectivity must include backwards chains and complex bridges in original queue order')
        legacy(true);sameResult(result,indexed.previewCancel(queue,a,true));legacy(false)
    end
    model.evaluate=evaluate
    toolkit.ActionQueueWorld,toolkit.ActionQueueGenerators,toolkit.ActionQueueCraft=previousWorld,previousGenerators,previousCraft
    toolkit.ActionQueuePolicy=previousPolicy
    toolkit.ActionQueueDefinitions=previousDefinitions
end
print('Policy component index: linear owner references, exact legacy model results, transitive growth and complex bridge fallback passed.')

-- Provenance is checked on a fresh policy instance, including a hook installed before its snapshot.
for _,variant in ipairs({'foreign-force-cancel','changed-base-source','missing-source-reader'})do
    local fresh=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    fresh.native('shared/Fluids/ISFluidContainer.lua')
    fresh.native('shared/Fluids/ISFluidTransferAction.lua')
    fresh.native('shared/Fluids/ISFluidEmptyAction.lua')
    fresh.native('shared/TimedActions/ISTransferAction.lua')
    fresh.native('shared/TimedActions/ISDrinkFluidAction.lua')
    local invoked=0
    if variant=='foreign-force-cancel'then ISBaseTimedAction.forceCancel=function()invoked=invoked+1 end end
    changedBaseSource=variant=='changed-base-source'
    local reader=getGameFilesInput
    if variant=='missing-source-reader'then getGameFilesInput=nil end
    fresh.project('ActionQueueOperations');fresh.project('ActionQueueDefinitions')
    local guardedPolicy=fresh.project('ActionQueuePolicy')
    local owner=fresh.item('Base.Bucket')
    local fluid={class='FluidContainer',getOwner=function()return owner end}
    local wrapper=setmetatable({fluidContainer=fluid,isFluidResource=false},ISFluidContainer)
    local prefix=fresh.action(ISFluidEmptyAction,{container=wrapper})
    local tail=fresh.action(ISFluidEmptyAction,{container=wrapper})
    local current=fresh.action(ISReadABook,{item=fresh.item('Base.BookCarpentry1')})
    local queue=fresh.queue(current,prefix,tail)
    assert(guardedPolicy.cancelOperationReason(queue,tail)=='operation_shared_item' and invoked==0,
        'unproven no-effect cancellation retains prefix protection: '..variant)
    getGameFilesInput=reader
end
changedBaseSource=false
print('Pending cancellation provenance: preinstalled foreign forceCancel, changed base source and unavailable readers remain closed.')
