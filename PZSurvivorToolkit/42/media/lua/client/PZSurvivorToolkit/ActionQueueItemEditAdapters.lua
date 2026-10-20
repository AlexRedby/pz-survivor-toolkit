require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISTransferAction"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISEatFoodAction"
local Proof = require "PZSurvivorToolkit/SourceProof"
local Toolkit = PZSurvivorToolkit
local Adapters = {}
Toolkit.ActionQueueItemEditAdapters = Adapters
local base = ISBaseTimedAction
local transfer, lowlevel, drink = ISInventoryTransferAction, ISTransferAction, ISDrinkFluidAction
local eat = ISEatFoodAction
local operations=Toolkit.ActionQueueOperations
local mergeDelegate=operations and operations.transferMergeDelegate
local lifecycle = {"new", "begin", "create", "adjustMaxTime", "isValid", "isValidStart", "waitToStart", "start", "update", "stop",
    "perform", "complete", "getDuration", "serverStart", "serverStop", "animEvent", "forceComplete", "forceStop", "forceCancel", "invoke"}
local snapshots, approved, guards, baseHooks, pins = {}, {}, {}, {}, {}
local baseMethods={}
local ownMethods,ownerSafe,baselineSafe={},{},true
-- These are the own methods in the pinned native files, including helpers called
-- by other methods. Enumerating only surviving callbacks would trust a class
-- whose effect/helper was deleted before this module loaded, or inherited instead.
local requiredOwn={
    [base]={"isValidStart","isValid","isUsingTimeout","update","forceComplete","forceStop","forceCancel",
        "getJobDelta","setJobDelta","resetJobDelta","waitToStart","interruptWaitToStart","start","isStarted","stop",
        "perform","getDuration","create","begin","setCurrentTime","setTime","adjustMaxTime","setActionAnim",
        "setOverrideHandModels","setOverrideHandModelsString","overrideWeaponType","restoreWeaponType","setAnimVariable",
        "addAfter","beginAddingActions","endAddingActions","getDeltaModifiers","new"},
    [transfer]={"isValid","update","doActionAnim","startActionAnim","waitToStart","start","playSourceContainerOpenSound",
        "playSourceContainerCloseSound","playDestContainerOpenSound","playDestContainerCloseSound","getTransferStartSoundName",
        "getTransferCompleteSoundName","playTransferCompleteSound","stopLoopingSound","stop","forceComplete","perform",
        "isAlreadyTransferred","floorHasRoomFor","canDropOnFloor","getNotFullFloorSquare","transferItem","setOnComplete",
        "getTimeDelta","canMergeAction","checkQueueList","setAllowMissingItems","getExtraLogData","new"},
    [lowlevel]={"floorHasRoomFor","canDropOnFloor","getNotFullFloorSquare","GetDropItemOffset","removeItemOnCharacter","transferItem"},
    [drink]={"isValidStart","waitToStart","isValid","update","serverStart","animEvent","start","stop","perform",
        "complete","updateEat","getDuration","new"},
    [eat]={"isValidStart","waitToStart","isValid","update","start","stop","serverStop","perform","complete",
        "getRequiredItem","eat","getDuration","getSecondItem","isEatingRemaining","new"},
}
local function ownsRequired(owner,methods)
    for _,name in ipairs(requiredOwn[owner]) do
        local callback=rawget(owner,name)
        if type(callback)~="function" or methods and callback~=methods[name] then return false end
    end
    return true
end
local function unique(methods)
    local seen={}
    for name,callback in pairs(methods) do
        if name~="derive" and type(callback)=="function" then
            if seen[callback] then return false end
            seen[callback]=name
        end
    end
    return true
end
for name,callback in pairs(base) do if type(callback)=="function" then baseMethods[name]=callback end end
baselineSafe=ownsRequired(base) and unique(baseMethods)
local files = {[transfer] = "ISInventoryTransferAction.lua", [lowlevel] = "ISTransferAction.lua", [drink] = "ISDrinkFluidAction.lua", [eat] = "ISEatFoodAction.lua"}
local allowed = {[transfer] = {new=true,isValid=true,start=true,perform=true,stop=true,transferItem=true,checkQueueList=true,getNotFullFloorSquare=true},
    [lowlevel] = {transferItem=true,GetDropItemOffset=true}, [drink] = {start=true}, [eat] = {start=true}}
for owner in pairs(files) do
    local methods,own = {},{}
    for name, callback in pairs(owner) do if type(callback) == "function" then methods[name],own[name] = callback,true end end
    ownerSafe[owner]=ownsRequired(owner) and unique(methods)
    ownMethods[owner]=own
    if owner ~= lowlevel then for _, name in ipairs(lifecycle) do methods[name] = owner[name] or false end end
    snapshots[owner], approved[owner], guards[owner] = methods, {}, {}
end
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function guarded(callback) local ok, result = pcall(callback); return ok and result == true end
local function pinned(path, checksum, mod)
    if not Proof or type(getFilenameOfClosure)~="function" or type(getGameFilesInput)~="function"
        or (mod and type(getModFileReader)~="function") then return false end
    if pins[path]==nil then pins[path]=Proof.matches(path,checksum,mod,true) end
    return pins[path]
end
local function origin(owner,name,callback)
    if type(callback)~="function" then return callback==false end
    if approved[owner][name]==callback then return true end
    if owner==drink and name=="isValidStart" and Proof.closure(callback,"DrinkFluidAction.lua") then
        return pinned("media/lua/shared/PZSurvivorToolkit/DrinkFluidAction.lua",3238429308,"PZSurvivorToolkit")
    end
    if owner==transfer and name=="canMergeAction" and Proof.closure(callback,"ActionQueueOperations.lua") then
        if Toolkit.ActionQueueOperations~=operations or type(mergeDelegate)~="function"
            or operations.transferMergeDelegate~=mergeDelegate or not Proof.closure(mergeDelegate,"ActionQueueOperations.lua") then return false end
        local ok,delegate=pcall(mergeDelegate,callback)
        return ok and Proof.closure(delegate,"ISInventoryTransferAction.lua")
    end
    if ownMethods[owner][name] then return Proof.closure(callback,files[owner]) end
    return callback==base[name] and (Proof.closure(callback,"ISBaseTimedAction.lua")
        or baseHooks[name]==callback and Proof.closure(callback,"ActionQueue.lua"))
end

-- Policy calls this only after its source-owned adoption path succeeds. Keep every
-- predecessor guard live, including when another approved wrapper delegates to it.
function Adapters.adoptMethods(owner,previous,replacement,guard)
    if not allowed[owner] or type(previous)~="table" or type(replacement)~="table" or getmetatable(previous) or getmetatable(replacement)
        or type(guard)~="function" or not guarded(guard) then return false end
    local count=0
    for name, callback in pairs(replacement) do
        if not allowed[owner][name] or type(callback)~="function" or snapshots[owner][name]~=previous[name]
            or rawget(owner,name)~=callback or not origin(owner,name,previous[name]) then return false end
        count=count+1
    end
    for name in pairs(previous) do if replacement[name]==nil then return false end end
    if count==0 then return false end
    for name,callback in pairs(replacement) do snapshots[owner][name],approved[owner][name]=callback,callback end
    guards[owner][#guards[owner]+1]=guard
    return true
end
function Adapters.adoptBase(name,previous,replacement)
    if (name~="begin" and name~="stop") or ISBaseTimedAction~=base or rawget(base,name)~=replacement
        or baseMethods[name]~=previous
        or not Proof.closure(previous,"ISBaseTimedAction.lua") or not Proof.closure(replacement,"ActionQueue.lua") then return false end
    for _,owner in ipairs({transfer,drink,eat}) do
        if snapshots[owner][name]==previous and owner[name]==replacement then snapshots[owner][name]=replacement end
    end
    baseHooks[name],baseMethods[name]=replacement,replacement
    return true
end
local function unchanged(owner,action)
    if not baselineSafe or ISBaseTimedAction~=base or ISInventoryTransferAction~=transfer or ISTransferAction~=lowlevel
        or ISDrinkFluidAction~=drink or ISEatFoodAction~=eat then return false end
    if not ownsRequired(base,baseMethods) then return false end
    local policy=Toolkit.ActionQueuePolicy
    if not policy or type(policy.matchesNative)~="function" or not policy.matchesNative(action) then return false end
    for name,callback in pairs(baseMethods) do
        if base[name]~=callback or name~="derive" and not Proof.closure(callback,"ISBaseTimedAction.lua")
            and not (baseHooks[name]==callback and Proof.closure(callback,"ActionQueue.lua")) then return false end
    end
    for _, candidate in ipairs(owner==transfer and {transfer,lowlevel} or {owner}) do
        if not ownerSafe[candidate] or not ownsRequired(candidate,snapshots[candidate]) then return false end
        for _,guard in ipairs(guards[candidate]) do if not guarded(guard) then return false end end
        for name,callback in pairs(snapshots[candidate]) do
            if (candidate[name] or false)~=callback or name~="derive" and not origin(candidate,name,callback) then return false end
            if candidate==owner and (action[name] or false)~=callback then
                local bulk=Toolkit.BulkActions
                if name~="stop" or not bulk or not bulk.isGuardedTransfer or not bulk.isGuardedTransfer(action,callback) then return false end
            end
        end
        for name,callback in pairs(candidate) do if type(callback)=="function" and snapshots[candidate][name]~=callback then return false end end
    end
    for name,callback in pairs(action) do
        if type(callback)=="function" and snapshots[owner][name]~=callback then
            local bulk=Toolkit.BulkActions
            local guardedTransfer=owner==transfer and bulk and bulk.isGuardedTransfer
                and bulk.isGuardedTransfer(action,snapshots[owner].stop)
            if not guardedTransfer or (name~="stop" and name~="onCompleteFunc") then return false end
        end
    end
    return true
end
local function pending(action,owner)
    if type(action)~="table" or getmetatable(action)~=owner or action.Type~=owner.Type or action.action or action.started
        or action._isAddingActions or action.transactionId and action.transactionId~=0
        or type(action.toolkitQueueOperation)=="table" and (action.toolkitQueueOperation.toolkitStarted or action.toolkitQueueOperation.toolkitCancelled)
        or not instanceof(action.character,"IsoPlayer") then return false end
    if not pinned("media/lua/shared/TimedActions/ISBaseTimedAction.lua",3104185167) then return false end
    if owner==transfer then
        if not pinned("media/lua/client/TimedActions/ISInventoryTransferAction.lua",3739549534)
            or not pinned("media/lua/shared/TimedActions/ISTransferAction.lua",798240932) then return false end
    elseif owner==eat then
        if not pinned("media/lua/shared/TimedActions/ISEatFoodAction.lua",178315973) then return false end
    elseif not pinned("media/lua/shared/TimedActions/ISDrinkFluidAction.lua",3564665289) then return false end
    return unchanged(owner,action)
end
local function leaf(item,player)
    if not instanceof(item,"InventoryItem") or instanceof(item,"InventoryContainer") or instanceof(item,"AnimalInventoryItem")
        or instanceof(item,"Radio") or item:getWorldItem() or item:getIsCraftingConsumed() or player:isEquipped(item)
        or item:getEquipParent() or item:getAttachedSlot()>=0 then return false end
    local kind=item:getType()
    return kind~="CandleLit" and kind~="Lantern_HurricaneLit"
end
local function ancestry(container,player)
    local root,seen=player:getInventory(),{}
    while instanceof(container,"ItemContainer") and not seen[container] do
        seen[container]=true
        local kind=container:getType()
        if kind=="floor" or kind=="proximityInv" or kind=="twistInv_corpses" or kind=="TradeUI"
            or not container:isExistYet() or container:getAcceptItemFunction()~=nil or container:getOnlyAcceptCategory()~=nil then return false end
        if container==root then return true end
        local owner=container:getContainingItem()
        if not instanceof(owner,"InventoryContainer") or owner:getInventory()~=container then return false end
        container=owner:getContainer()
    end
    return false
end
local function itemFacts(item)
    local id=item:getID()
    if not finite(id) or id%1~=0 then return end
    local facts={item=item,location=item:getContainer()}
    if not instanceof(facts.location,"ItemContainer") or not facts.location:contains(item)
        or facts.location:getItemById(id)~=item then return end
    local fluid=item:getFluidContainer()
    if fluid then
        if not instanceof(fluid,"FluidContainer") or fluid:getOwner()~=item then return end
        facts.fluid=fluid
    end
    if instanceof(item,"Food") then
        local amount=-item:getHungChange()
        if finite(amount) and amount>0 then facts.foodLower,facts.foodUpper=amount,amount end
    end
    return facts
end
local function singleton(value)
    if type(value)~="table" or getmetatable(value) or value[1]==nil then return false end
    for key in pairs(value) do if key~=1 then return false end end
    return true
end
function Adapters.transfer(action)
    if not pending(action,transfer) or not leaf(action.item,action.character) or action.srcContainer==action.destContainer
        or not ancestry(action.srcContainer,action.character) or not ancestry(action.destContainer,action.character) then return end
    local bag=action.destContainer:getContainingItem()
    if bag then
        local maximum,weight=bag:getMaxItemSize(),action.item:getUnequippedWeight()
        if not finite(maximum) or maximum<0 or not finite(weight) or weight<0 or maximum>0 and weight>maximum then return end
    end
    local groups=action.queueList
    if not singleton(groups) or type(groups[1])~="table" or getmetatable(groups[1])
        or not singleton(groups[1].items) or groups[1].items[1]~=action.item
        or groups[1].type~=action.item:getFullType() or not finite(groups[1].time) or groups[1].time~=action.maxTime
        or action.allowMissingItems~=nil and type(action.allowMissingItems)~="boolean" then return end
    for key in pairs(groups[1]) do if key~="items" and key~="time" and key~="type" then return end end
    local facts=itemFacts(action.item)
    if not facts or facts.location~=action.srcContainer and facts.location~=action.destContainer then return end
    -- Ancestry owner mutations remain linked by Policy.transferResources.containerOwners.
    local requires={{field="location",oneOf={action.srcContainer,action.destContainer}}}
    if facts.foodLower then requires[#requires+1]={field="foodLower",above=0} end
    return {version=1,complete=true,capacity="external",resources={{domain="item",key=action.item:getID(),facts=facts,
        requires=requires,effects={{field="location",set=action.destContainer}}}}}
end
local function fullness(player)
    local damage=player:getBodyDamage()
    local timer,standard=damage:getHealthFromFoodTimer(),damage:getStandardHealthFromFoodTime()
    if not finite(timer) or timer>11000 or not finite(standard) or standard<=0 then return end
    -- Native decay can overshoot zero and leave a small negative timer.
    return {domain="actor",key=player,facts={foodTimerUpper=math.max(0,timer)},
        requires={{field="foodTimerUpper",max=2*standard}},effects={}}
end
local zeroProperties={"getFatigueChange","getHungerChange","getStressChange","getUnhappyChange","getCalories","getCarbohydrates",
    "getLipids","getProteins","getAlcohol","getPoison","getFluReduction","getPainReduction","getEnduranceChange","getFoodSicknessChange"}
local function cleanWater(fluid)
    if not instanceof(fluid,"FluidContainer") or not Fluid or not Fluid.Water or not fluid:isPureFluid(Fluid.Water)
        or fluid:isTainted() or fluid:isPoisonous() then return false end
    local properties=fluid:getProperties()
    for _,name in ipairs(zeroProperties) do if properties[name](properties)~=0 then return false end end
    local thirst=properties:getThirstChange()
    return finite(thirst) and thirst<=0
end
function Adapters.fullnessNeutralDrink(action)
    -- An already-running clean-water action changes no fullness. Other fluid
    -- consumption must join the actor dependency component even without a
    -- supported edit contract of its own.
    return type(action)=="table" and getmetatable(action)==drink and action.useUtensil==false
        and pinned("media/lua/shared/TimedActions/ISDrinkFluidAction.lua",3564665289)
        and pinned("media/lua/shared/TimedActions/ISBaseTimedAction.lua",3104185167)
        and unchanged(drink,action) and cleanWater(action.fluidContainer)
end
function Adapters.drink(action)
    if not pending(action,drink) or action.useUtensil~=false or not leaf(action.item,action.character)
        or not ancestry(action.item:getContainer(),action.character) or not Fluid or not Fluid.Water then return end
    local facts=itemFacts(action.item)
    local fluid=action.fluidContainer
    if not facts or facts.fluid~=fluid or not cleanWater(fluid) then return end
    local amount,capacity,ratio=fluid:getAmount(),fluid:getCapacity(),fluid:getFilledRatio()
    if not finite(amount) or not finite(capacity) or not finite(ratio) or capacity<=0 or amount<=0 or amount>capacity
        or ratio<=0 or ratio>1 or math.abs(amount/capacity-ratio)>0.000001 then return end
    for _,field in ipairs({"percentage","startRatio","endRatio","targetConsumedRatio","consumedRatio"}) do
        if not finite(action[field]) or action[field]<0 or action[field]>1 then return end
    end
    if action.percentage<=0 or action.startRatio<=0 or action.consumedRatio~=0 or action.endRatio>ratio or ratio>action.startRatio
        or action.endRatio~=action.startRatio*(1-action.percentage)
        or action.targetConsumedRatio~=action.startRatio-action.endRatio then return end
    local resources={{domain="item",key=action.item:getID(),facts=facts,
        requires={{field="location",equal=action.character:getInventory()},{field="fluid",equal=fluid}},effects={}}}
    local effects
    if isClient() then effects={{field="amountLower",set=0},{field="amountUpper",scale=1-action.percentage}}
    else
        local endpoint=capacity*action.endRatio
        -- Native FluidContainer removes a fluid instance below 1e-4. Do not
        -- promise nonempty near that boundary, including the ratio/float
        -- uncertainty already accepted by the amount/filled-ratio shape check.
        local pruningBoundary=0.0001+capacity*0.000001
        local lower=(endpoint<=pruningBoundary or amount<=pruningBoundary)
            and {field="amountLower",set=0} or {field="amountLower",cap=endpoint}
        effects={lower,{field="amountUpper",cap=endpoint}}
    end
    resources[#resources+1]={domain="fluid",key=fluid,facts={amountLower=amount,amountUpper=amount},
        requires={{field="amountLower",above=0}},effects=effects,bounds={amountLower={min=0,max=capacity},amountUpper={min=0,max=capacity}}}
    if Proof.closure(drink.isValidStart,"ISDrinkFluidAction.lua") then
        local actor=fullness(action.character)
        if not actor then return end
        resources[#resources+1]=actor
    end
    return {version=1,complete=true,capacity="external",resources=resources}
end

function Adapters.food(action)
    if not pending(action,eat) or not instanceof(action.container,"ItemContainer")
        or action.carLighter or action.openFlame or action.fromRelaunch or not leaf(action.item,action.character)
        or not instanceof(action.item,"Food") or not ancestry(action.item:getContainer(),action.character) then return end
    local item=action.item
    -- Use the constructor's captured reference, never a fresh inventory search.
    -- Native getSecondItem/start select only one of the two remembered utensils.
    local kind=item:getEatType()
    local utensil
    if kind=="2handbowl" then utensil=action.spoon
    elseif kind=="Can" or kind=="Candrink" or kind=="2hand" or kind=="Plate" then utensil=action.fork or action.spoon end
    if action.useUtensil~=(utensil~=nil) then return end
    local utensilFacts
    if utensil~=nil then
        if not instanceof(utensil,"HandWeapon") or not leaf(utensil,action.character) or utensil:isBroken()
            or not ancestry(utensil:getContainer(),action.character) then return end
        utensilFacts=itemFacts(utensil)
        if not utensilFacts then return end
    end
    local script=item:getScriptItem()
    local cookedOutputs=item:getReplaceOnCooked()
    if not script or script:isCantEat() or script:getOpeningRecipe() or script:getOnBreak()
        or script:getReplaceOnUse() or script:getReplaceOnDeplete() or item:getReplaceOnUse()
        or item:getOnEat() or item:getOnCooked() or item:getReplaceOnRotten()
        or cookedOutputs and not cookedOutputs:isEmpty() or item:isCookable()
        or item:getRequireInHandOrInventory() or item:getCustomMenuOption()
        or item:hasTag(ItemTag.SMOKABLE) or not item:isDisappearOnUse() or item:isKeepOnDeplete()
        or item:getUses()~=1 or item:getFluidContainer() or item:isTainted() or item:getPoisonPower()~=0
        or item:isAlcoholic() or item:getReduceInfectionPower()~=0 or item:isBurnt() or item:isRotten()
        or item:isbDangerousUncooked() and not item:isCooked() then return end
    local facts=itemFacts(item)
    local base=-item:getBaseHunger()
    local portion=action.percentage
    if not facts or not facts.foodLower or not finite(base) or base<=0 or facts.foodUpper>base+0.000001
        or not finite(portion) or portion<=0 or portion>1 then return end
    local actor=fullness(action.character)
    if not actor then return end
    local debit=base*portion
    -- Java float division/multiplication and the strict native .01 tail test
    -- are enclosed, not rounded into a promise that an item survives.
    local margin=0.00001*math.max(1,base)
    local effects={{field="foodLower",deplete={amount=debit+margin,minimum=0.01+margin}},
        {field="foodUpper",deplete={amount=math.max(0,debit-margin),minimum=0.01-margin}}}
    -- Food timers only grow at minimum hunger. Ignoring that condition and
    -- decay is conservative; cooked food has a 1.3 multiplier and doubles
    -- the timer bonus. The extra .01 covers the native final-tail rounding.
    local multiplier=item:isCooked() and 33800 or 13000
    actor.effects={{field="foodTimerUpper",delta=multiplier*(debit+0.01+margin)+1},{field="foodTimerUpper",cap=11000}}
    local resources={
        {domain="item",key=item:getID(),facts=facts,
            requires={{field="location",equal=action.character:getInventory()},{field="foodLower",above=0}},effects=effects,
            bounds={foodLower={min=0},foodUpper={min=0}}},actor}
    if utensil then
        -- Native Eat receives a boolean: it neither consumes nor equips cutlery.
        -- Keep the exact selected tool reachable; a bag/root transfer can commute
        -- without changing the captured duration or mood benefit.
        resources[#resources+1]={domain="item",key=utensil:getID(),facts=utensilFacts,
            requires={{field="location",oneOf={utensilFacts.location,action.character:getInventory()}}},effects={}}
    end
    return {version=1,complete=true,capacity="external",resources=resources}
end
return Adapters
