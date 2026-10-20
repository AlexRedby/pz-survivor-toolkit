require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISTransferAction"
require "TimedActions/ISDrinkFluidAction"
local Proof = require "PZSurvivorToolkit/SourceProof"
local Toolkit = PZSurvivorToolkit
local Adapters = {}
Toolkit.ActionQueueItemEditAdapters = Adapters
local base = ISBaseTimedAction
local transfer, lowlevel, drink = ISInventoryTransferAction, ISTransferAction, ISDrinkFluidAction
local operations=Toolkit.ActionQueueOperations
local mergeDelegate=operations and operations.transferMergeDelegate
local lifecycle = {"new", "begin", "create", "adjustMaxTime", "isValid", "isValidStart", "waitToStart", "start", "update", "stop",
    "perform", "complete", "getDuration", "serverStart", "serverStop", "animEvent", "forceComplete", "forceStop", "forceCancel", "invoke"}
local snapshots, approved, guards, baseHooks, pins = {}, {}, {}, {}, {}
local baseMethods={}
for name,callback in pairs(base) do if type(callback)=="function" then baseMethods[name]=callback end end
local files = {[transfer] = "ISInventoryTransferAction.lua", [lowlevel] = "ISTransferAction.lua", [drink] = "ISDrinkFluidAction.lua"}
local allowed = {[transfer] = {new=true,isValid=true,start=true,perform=true,stop=true,transferItem=true,checkQueueList=true,getNotFullFloorSquare=true},
    [lowlevel] = {transferItem=true}, [drink] = {start=true}}
for owner in pairs(files) do
    local methods = {}
    for name, callback in pairs(owner) do if type(callback) == "function" then methods[name] = callback end end
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
    return Proof.closure(callback,files[owner]) or Proof.closure(callback,"ISBaseTimedAction.lua")
        or baseHooks[name]==callback and Proof.closure(callback,"ActionQueue.lua")
end

-- Policy calls this only after its source-owned adoption path succeeds. Keep every
-- predecessor guard live, including when another approved wrapper delegates to it.
function Adapters.adoptMethods(owner,previous,replacement,guard)
    if not allowed[owner] or type(previous)~="table" or type(replacement)~="table" or getmetatable(previous) or getmetatable(replacement)
        or type(guard)~="function" or not guarded(guard) then return false end
    local count=0
    for name, callback in pairs(replacement) do
        if not allowed[owner][name] or type(callback)~="function" or snapshots[owner][name]~=previous[name]
            or owner[name]~=callback or not origin(owner,name,previous[name]) then return false end
        count=count+1
    end
    for name in pairs(previous) do if replacement[name]==nil then return false end end
    if count==0 then return false end
    for name,callback in pairs(replacement) do snapshots[owner][name],approved[owner][name]=callback,callback end
    guards[owner][#guards[owner]+1]=guard
    return true
end
function Adapters.adoptBase(name,previous,replacement)
    if (name~="begin" and name~="stop") or ISBaseTimedAction~=base or base[name]~=replacement
        or baseMethods[name]~=previous
        or not Proof.closure(previous,"ISBaseTimedAction.lua") or not Proof.closure(replacement,"ActionQueue.lua") then return false end
    for _,owner in ipairs({transfer,drink}) do
        if snapshots[owner][name]==previous and owner[name]==replacement then snapshots[owner][name]=replacement end
    end
    baseHooks[name],baseMethods[name]=replacement,replacement
    return true
end
local function unchanged(owner,action)
    if ISBaseTimedAction~=base or ISInventoryTransferAction~=transfer or ISTransferAction~=lowlevel or ISDrinkFluidAction~=drink then return false end
    local policy=Toolkit.ActionQueuePolicy
    if not policy or type(policy.matchesNative)~="function" or not policy.matchesNative(action) then return false end
    for name,callback in pairs(baseMethods) do
        if base[name]~=callback or name~="derive" and not Proof.closure(callback,"ISBaseTimedAction.lua")
            and not (baseHooks[name]==callback and Proof.closure(callback,"ActionQueue.lua")) then return false end
    end
    for _, candidate in ipairs(owner==transfer and {transfer,lowlevel} or {drink}) do
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
    local groups=action.queueList
    if not singleton(groups) or type(groups[1])~="table" or getmetatable(groups[1])
        or not singleton(groups[1].items) or groups[1].items[1]~=action.item
        or groups[1].type~=action.item:getFullType() or not finite(groups[1].time) or groups[1].time~=action.maxTime
        or action.allowMissingItems~=nil and type(action.allowMissingItems)~="boolean" then return end
    for key in pairs(groups[1]) do if key~="items" and key~="time" and key~="type" then return end end
    local facts=itemFacts(action.item)
    if not facts or facts.location~=action.srcContainer and facts.location~=action.destContainer then return end
    -- Ancestry owner mutations remain linked by Policy.transferResources.containerOwners.
    return {version=1,complete=true,capacity="external",resources={{domain="item",key=action.item:getID(),facts=facts,
        requires={{field="location",oneOf={action.srcContainer,action.destContainer}}},effects={{field="location",set=action.destContainer}}}}}
end
local zeroProperties={"getFatigueChange","getHungerChange","getStressChange","getUnhappyChange","getCalories","getCarbohydrates",
    "getLipids","getProteins","getAlcohol","getPoison","getFluReduction","getPainReduction","getEnduranceChange","getFoodSicknessChange"}
function Adapters.drink(action)
    if not pending(action,drink) or action.useUtensil~=false or not leaf(action.item,action.character)
        or not ancestry(action.item:getContainer(),action.character) or not Fluid or not Fluid.Water then return end
    local facts=itemFacts(action.item)
    local fluid=action.fluidContainer
    if not facts or facts.fluid~=fluid or not instanceof(fluid,"FluidContainer") or not fluid:isPureFluid(Fluid.Water)
        or fluid:isTainted() or fluid:isPoisonous() then return end
    local amount,capacity,ratio=fluid:getAmount(),fluid:getCapacity(),fluid:getFilledRatio()
    if not finite(amount) or not finite(capacity) or not finite(ratio) or capacity<=0 or amount<=0 or amount>capacity
        or ratio<=0 or ratio>1 or math.abs(amount/capacity-ratio)>0.000001 then return end
    for _,field in ipairs({"percentage","startRatio","endRatio","targetConsumedRatio","consumedRatio"}) do
        if not finite(action[field]) or action[field]<0 or action[field]>1 then return end
    end
    if action.percentage<=0 or action.startRatio<=0 or action.consumedRatio~=0 or action.endRatio>ratio or ratio>action.startRatio
        or action.endRatio~=action.startRatio*(1-action.percentage)
        or action.targetConsumedRatio~=action.startRatio-action.endRatio then return end
    local properties=fluid:getProperties()
    for _,name in ipairs(zeroProperties) do if properties[name](properties)~=0 then return end end
    local thirst=properties:getThirstChange()
    if not finite(thirst) or thirst>0 then return end
    local resources={{domain="item",key=action.item:getID(),facts=facts,
        requires={{field="location",equal=action.character:getInventory()},{field="fluid",equal=fluid}},effects={}}}
    local effects
    if isClient() then effects={{field="amountLower",set=0},{field="amountUpper",scale=1-action.percentage}}
    else effects={{field="amountLower",cap=capacity*action.endRatio},{field="amountUpper",cap=capacity*action.endRatio}} end
    resources[#resources+1]={domain="fluid",key=fluid,facts={amountLower=amount,amountUpper=amount},
        requires={{field="amountLower",above=0}},effects=effects,bounds={amountLower={min=0,max=capacity},amountUpper={min=0,max=capacity}}}
    if Proof.closure(drink.isValidStart,"ISDrinkFluidAction.lua") then
        resources[#resources+1]={domain="actor",key=action.character,facts={canDrink=action.character:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)<3},
            requires={{field="canDrink",equal=true}},effects={}}
    end
    return {version=1,complete=true,capacity="external",resources=resources}
end
return Adapters
