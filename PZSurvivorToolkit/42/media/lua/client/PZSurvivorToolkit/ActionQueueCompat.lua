require "PZSurvivorToolkit/ActionQueueOperations"
require "PZSurvivorToolkit/ActionQueueLifecycle"
require "PZSurvivorToolkit/ActionQueueDefinitions"
require "ISUI/ISXuiSkin"

local Toolkit = PZSurvivorToolkit
local Operations = Toolkit.ActionQueueOperations
local expandCommand = Operations.expandCommand
local Settlement = require "PZSurvivorToolkit/ActionQueueSettlement"
local Transfers = require "PZSurvivorToolkit/ActionQueueTransfers"
local TidyIntent = require "PZSurvivorToolkit/ActionQueueTidyIntent"
local WashWaterRule = require "PZSurvivorToolkit/WashWaterRule"
local washWaterMatches = WashWaterRule and WashWaterRule.matchesComplete
local washWaterComplete
local Compat = {}
Toolkit.ActionQueueCompat = Compat
local records = {}
local classes, installed, sessions = {}, {}, {}
local owners = {}
local craftOwners = {}
local projectCookConfig
local nativeXuiMethods = ISXuiSkinFunctions and {
    xuiRecalculateLayout = ISXuiSkinFunctions.xuiRecalculateLayout,
    xuiRootElement = ISXuiSkinFunctions.xuiRootElement,
} or {}
local ready = {}
local sourceScope
local worldGeneration = 0
local installAttempted
local readFixAttempted
local transferSourceSafe = true
local reviewedTransferPerform, transferPerformGuard
local containerHelpersUnchanged
local washWalkHelper
local tidyClassUnchanged, tidyActionUnchanged, tidyUnequipVariant
local reviewedTransferClassUnchanged
local tidyFloorPage, tidyFloorGetter
local tidyFloorValid
-- Queued actions only; prune explicitly because Kahlua ignores weak-key modes.
local repairedFloors = {}
local Membership = require "PZSurvivorToolkit/ActionQueueMembership"
local lifecycle = {"new", "isValid", "isValidStart", "waitToStart", "start", "update", "stop", "perform",
    "complete", "getDuration", "serverStart", "serverStop", "animEvent", "forceStop", "forceCancel"}
local projectCookActionSources = {
    {"client/Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction.lua", 222676723},
    {"shared/Project_Cook/PJCK_FrozenCooking.lua", 3756381974},
}
-- UI transition proof is optional; an updated panel must not disable cooking/return producers.
local projectCookFirstAdditionSources = {
    {"client/Project_Cook/EvolvedRecipePanel/PJCK_InputPanel.lua", 3323057587},
    {"client/Project_Cook/EvolvedRecipePanel/PJCK_CookingInfo.lua", 726762453},
}
local sourceFiles = {
    SaucedCartsTransfers = {
        {"shared/SaucedCarts/TimedActions/ISCartTransferAction.lua", 3962234240},
        {"shared/SaucedCarts/CartTransferInterceptor.lua", 2772644904},
        {"shared/SaucedCarts/Core.lua", 2570266575},
        {"shared/SaucedCarts/Network.lua", 2897409368},
        {"client/SaucedCarts/Restrictions/TransferRestrictions.lua", 2976371209},
        {"client/SaucedCarts/CartState/VisualUpdateQueue.lua", 2627823607},
    },
    WashFix = {
        {"client/ISUI/WMI_WashingSubmenus.lua", 3809430929},
        {"client/ISUI/WMI_CleanBandagesContext.lua", 2564019136},
        {"shared/TimedActions/WMI_PatchWashClothing.lua", 2935848012},
    },
    NeatUI_Equipment = {
        {"client/NeatEquipment/NEQ_Dresser.lua", 859961585},
        {"client/NeatEquipment/NEQ_AttachAction.lua", 3212833623},
    },
    NicksTurnOffFridges = {
        {"shared/TurnOffFridges/TOF_Core.lua", 1091795413},
        {"shared/TurnOffFridges/TOF_TileProps.lua", 921744374},
        {"client/TurnOffFridges/TOF_Client.lua", 2838376957},
        {"client/TurnOffFridges/TOF_Light.lua", 76508066},
    },
    P4TidyUpMeister = {
        {"client/P4TidyUpMeister.lua", 389269229},
        {"shared/TimedActions/P4RestoreAction.lua", 1645293368},
        {"shared/TimedActions/P4RestoreFloorAction.lua", 1126532530},
    },
    Neat_Crafting = {{"client/Neat_Crafting/NC_CraftActionPanel.lua", 2203522815}},
    Project_Cook = {
        {"client/Project_Cook/HandCraftPanel/PJCK_CraftActionPanel.lua", 253384307},
        {"client/Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel.lua", 286152189},
        {"client/Project_Cook/PJCK_Config.lua", 2629049005},
        projectCookActionSources[1],
        projectCookActionSources[2],
        {"shared/Project_Cook/PJCK_EvolvedSpiceGuard.lua", 2430144672},
    },
    MPFastForward = {{"server/MPFastForward_ReadFix.lua", 598888215}},
    SaucedCarts = {
        {"client/SaucedCarts/ConsumeWithCart.lua", 2924576916},
        {"shared/SaucedCarts/Core.lua", 2570266575},
    },
    EURY_CONTAINERS = {
        {"client/BetterContainers/Proximity.lua", 3626949969},
        {"client/BetterContainers/Proximity/Proximity_ISInventoryTransferAction.lua", 909048245},
        {"client/BetterContainers/Nested.lua", 2806093898},
        {"shared/BetterContainers/Helpers.lua", 365367801},
    },
}

local function pack(...) return {n = select("#", ...), ...} end

function Compat.prune()
    -- Sessions outlive their source actions for delayed Tidy restores. Only
    -- their seen actions need queue membership, not the session/player keys.
    local registries = {records, repairedFloors}
    for _, session in pairs(sessions) do registries[#registries + 1] = session.seen end
    local queued = Membership.find(registries)
    for action in pairs(records) do if not queued[action] then records[action] = nil end end
    for action in pairs(repairedFloors) do if not queued[action] then repairedFloors[action] = nil end end
    for character, session in pairs(sessions) do
        if character:isDead() or ISTimedActionQueue.queues[character] ~= session.queue
            or (session.queue.toolkitOperationGeneration or 0) ~= session.generation then
            Settlement.close(session)
            sessions[character] = nil
        else
            Settlement.poll(session)
            -- Delayed Tidy restores still need task/pickup history after the source action leaves the queue.
            for action in pairs(session.seen) do if not queued[action] then session.seen[action] = nil end end
        end
    end
end
Events.OnTick.Add(Compat.prune)
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function()
    worldGeneration = worldGeneration + 1
    for action in pairs(records) do records[action] = nil end
    for action in pairs(repairedFloors) do repairedFloors[action] = nil end
    for character, session in pairs(sessions) do Settlement.close(session); sessions[character] = nil end
end) end

-- getModFileReader resolves the selected B42 version, then common; no Workshop path is assumed.
local Proof = require "PZSurvivorToolkit/SourceProof"
local bindingCapture = Proof and Proof.captureBindings
local bindingOrigin,bindingSourceOwn=Proof and Proof.closure,Proof and Proof.own
local bindingType,bindingMeta,bindingRaw,bindingPairs,bindingEach,bindingEqual=type,getmetatable,rawget,pairs,ipairs,rawequal
local bindingGlobals,bindingFilename=_G,getFilenameOfClosure
local transferBindingRecords, bindingState = {}, {revision=0}
local transferBindingFactory, transferListenerFactory, tidyBindingFactory
local transferListenerRecord, tidyBindingRecord
local function bindingOwn(owner,key)
    if bindingType(owner)~="table" then return nil end
    if bindingMeta(owner)==nil then local value=bindingRaw(owner,key);return value end
    local count=0
    for name,value in bindingPairs(owner) do
        count=count+1
        if count>128 then return nil end
        if bindingEqual(name,key) then return value end
    end
    return nil
end
local function bindingBase()
    if bindingType(bindingCapture)~="function" or bindingMeta(bindingGlobals)~=nil or bindingMeta(Toolkit)~=nil
        or bindingMeta(Compat)~=nil or bindingMeta(Proof)~=nil
        or not bindingEqual(bindingOwn(bindingGlobals,"getFilenameOfClosure"),bindingFilename)
        or not bindingEqual(bindingOwn(bindingGlobals,"PZSurvivorToolkit"),Toolkit)
        or not bindingEqual(bindingOwn(Toolkit,"ActionQueueCompat"),Compat)
        or not bindingEqual(bindingOwn(Toolkit,"ActionQueueSettlement"),Settlement)
        or not bindingEqual(bindingOwn(Toolkit,"ActionQueueTidyIntent"),TidyIntent)
        or not bindingEqual(bindingOwn(Toolkit,"ActionQueueTransfers"),Transfers)
        or not bindingEqual(bindingOwn(Toolkit,"ActionQueueOperations"),Operations)
        or not bindingEqual(bindingOwn(Proof,"captureBindings"),bindingCapture)
        or not bindingEqual(bindingOwn(Proof,"closure"),bindingOrigin) or not bindingEqual(bindingOwn(Proof,"own"),bindingSourceOwn)
        or not bindingEqual(bindingOwn(Compat,"transferBinding"),transferBindingFactory)
        or not bindingEqual(bindingOwn(Compat,"transferListenerBinding"),transferListenerFactory)
        or not bindingEqual(bindingOwn(Compat,"tidyBinding"),tidyBindingFactory) then return nil end
    return {{owner=bindingGlobals,keys={"PZSurvivorToolkit","getFilenameOfClosure","EURY_CONTAINERS","P4TidyUpMeister","TurnOffFridges"}},
        {owner=Toolkit,keys={"ActionQueueCompat","ActionQueueSettlement","ActionQueueTidyIntent","ActionQueueTransfers","ActionQueueOperations","ActionQueuePolicy","ActionQueueCarts","Settings"}},
        {owner=Compat,keys={"transferBinding","transferListenerBinding","tidyBinding"}},
        {owner=Proof,keys={"captureBindings","closure","own"}},{owner=bindingState,keys={"revision"}}}
end
local function bindingDependencies()
    local result={}
    for _,specification in bindingEach({
        {slot="ActionQueueSettlement",owner=Settlement,keys={"admittedPickupScope","refreshPickup","departure","pickupMatches","beforePickupMerge",
            "beginPickup","finishPickup","refreshReturn","returnMatches","beginReturn","finishReturn","stopReturn"}},
        {slot="ActionQueueOperations",owner=Operations,keys={"perform"}},
        {slot="ActionQueuePolicy",owner=bindingOwn(Toolkit,"ActionQueuePolicy"),keys={"matchesNative","isOrdinaryTransfer"}},
        {slot="Settings",owner=bindingOwn(Toolkit,"Settings"),keys={"actionQueue"}},
    }) do
        if bindingType(specification.owner)~="table" then return nil end
        specification.values={}
        for _,key in bindingEach(specification.keys) do specification.values[key]=bindingOwn(specification.owner,key) end
        result[#result+1]=specification
    end
    local carts=bindingOwn(Toolkit,"ActionQueueCarts")
    if bindingType(carts)=="table" then
        local keys={"isTransferConstructor","isUnequipConstructor","isNonCartUnequip","isNonCartItem"}
        local values={}
        for _,key in bindingEach(keys) do values[key]=bindingOwn(carts,key) end
        result[#result+1]={slot="ActionQueueCarts",owner=carts,keys=keys,values=values}
    end
    return result
end
local function addBindingDependencies(specifications,dependencies)
    if not dependencies then return false end
    for _,dependency in bindingEach(dependencies) do
        if not bindingEqual(bindingOwn(Toolkit,dependency.slot),dependency.owner) then return false end
        for _,key in bindingEach(dependency.keys) do
            if not bindingEqual(bindingOwn(dependency.owner,key),dependency.values[key]) then return false end
        end
        specifications[#specifications+1]={owner=dependency.owner,keys=dependency.keys}
    end
    return true
end
local function bindingFields(specifications,owner,expected)
    if bindingType(owner)~="table" or bindingMeta(owner)~=nil then return false end
    local keys={}
    for key,value in bindingPairs(expected) do
        if not bindingEqual(bindingOwn(owner,key),value) then return false end
        keys[#keys+1]=key
    end
    if #keys>0 then specifications[#specifications+1]={owner=owner,keys=keys} end
    return true
end
local function noFridgeParent(types,on,off)
    if types==false then return true end
    if bindingType(types)~="table" or bindingMeta(types)~=nil then return false end
    local count,size=0,#types
    if size==0 or size>64 then return false end -- native bounded parent-container DTO
    for key,value in bindingPairs(types) do
        if bindingType(key)~="number" or key%1~=0 or key<1 or key>size or bindingType(value)~="string"
            or bindingOwn(on,value)~=nil or bindingOwn(off,value)~=nil then return false end
        count=count+1
    end
    return count==size
end
-- Source provenance only. Each record is created next to the reviewed wrapper
-- installation; callers cannot turn an arbitrary successful guard into a lease.
transferBindingFactory=function(guard,action)
    local specifications=bindingBase()
    if not specifications or bindingType(action)~="table" then return nil end
    if guard==false then
        local record=records[action]
        local delegates=record and record.transferBinding
        if not delegates or record.id~="P4TidyUpMeister" or record.class~=ISInventoryTransferAction or record.opaque
            or delegates.completion~=nil or not bindingEqual(bindingOwn(action,"perform"),delegates.performWrapper) then return nil end
        specifications[#specifications+1]={owner=records,keys={action}}
        specifications[#specifications+1]={owner=record,keys={"id","class","opaque","character","token","queue","generation",
            "worldGeneration","fields","methods","obligation","transferBinding"}}
        specifications[#specifications+1]={owner=delegates,exact=true}
        specifications[#specifications+1]={owner=action,keys={"perform","stop","onCompleteFunc"}}
        specifications[#specifications+1]={owner=record.fields,exact=true}
        if not addBindingDependencies(specifications,delegates.dependencies) then return nil end
        return bindingCapture(specifications),{wrappedPerform=delegates.performWrapper,perform=delegates.performDelegate,
            wrappedStop=delegates.stopWrapper,stop=delegates.stopDelegate,completeWasAbsent=true}
    end
    local record=transferBindingRecords[guard]
    if not record then return nil end
    specifications[#specifications+1]={owner=transferBindingRecords,keys={guard}}
    specifications[#specifications+1]={owner=record,exact=true}
    specifications[#specifications+1]={owner=ready,keys={record.id}}
    if ready[record.id]~=true then return nil end
    if record.kind=="bc" then
        if not bindingEqual(bindingOwn(bindingGlobals,"EURY_CONTAINERS"),record.helpers)
            or not bindingFields(specifications,record.helpers,record.helperMethods)
            or not bindingFields(specifications,record.proximity,record.proximityMethods) then return nil end
        if bindingType(record.running)~="table" or bindingType(record.browsing)~="table" then return nil end
        for _,state in bindingEach({record.running,record.browsing}) do
            if bindingType(state)~="table" or bindingMeta(state)~=nil then return nil end
            specifications[#specifications+1]={owner=state,exact=true}
        end
    elseif record.kind=="p4" then
        if not bindingEqual(bindingOwn(bindingGlobals,"P4TidyUpMeister"),record.owner)
            or not bindingFields(specifications,record.owner,record.ownerMethods) then return nil end
    elseif record.kind=="tof" then
        if not bindingEqual(bindingOwn(bindingGlobals,"TurnOffFridges"),record.owner)
            or not bindingFields(specifications,record.owner,record.ownerMethods) then return nil end
        for _,constant in bindingEach({record.on,record.off}) do
            if not bindingFields(specifications,constant.map,constant.values) then return nil end
            local count=0
            for key,value in bindingPairs(constant.map) do
                count=count+1
                if not bindingEqual(bindingOwn(constant.values,key),value) then return nil end
            end
            if count~=2 then return nil end
        end
        local prior=record.priorGuard and transferBindingFactory(record.priorGuard,action)
        if record.priorGuard and not prior then return nil end
        local watch=bindingCapture(specifications)
        if not watch then return nil end
        return function(facts)
            return watch() and (not prior or prior(facts)) and bindingType(facts)=="table" and bindingMeta(facts)==nil
                and bindingOwn(facts,"schema")==2
                and noFridgeParent(bindingOwn(facts,"sourceParentTypes"),record.on.map,record.off.map)
                and noFridgeParent(bindingOwn(facts,"destinationParentTypes"),record.on.map,record.off.map)
        end
    else return nil end
    return bindingCapture(specifications)
end
Compat.transferBinding=transferBindingFactory
local function privateTransferBinding(action,specifications)
    local record=records[action]
    if record and (record.id~="P4TidyUpMeister" or record.opaque or record.mergeCandidates) then return nil end
    specifications[#specifications+1]={owner=records,keys={action}}
    if record then
        specifications[#specifications+1]={owner=record,keys={"id","class","opaque","mergeCandidates","fields","methods","obligation","transferBinding"}}
    end
    local actor=bindingOwn(action,"character")
    local session=sessions[actor]
    specifications[#specifications+1]={owner=sessions,keys={actor}}
    if session then
        if bindingType(session)~="table" or bindingMeta(session)~=nil then return nil end
        specifications[#specifications+1]={owner=session,keys={"character","queue","generation","phase","restored","seen"}}
    end
    return bindingCapture(specifications)
end
transferListenerFactory=function(action,callback,canObserve,events)
    local record=transferListenerRecord
    local specifications=bindingBase()
    if not specifications or not record or not bindingEqual(callback,record.callback)
        or not bindingEqual(canObserve,record.canObserve) or not bindingEqual(events,record.events) then return nil end
    specifications[#specifications+1]={owner=record,exact=true}
    specifications[#specifications+1]={owner=events,exact=true}
    if not addBindingDependencies(specifications,record.dependencies) then return nil end
    return privateTransferBinding(action,specifications)
end
Compat.transferListenerBinding=transferListenerFactory
tidyBindingFactory=function(action,valid,wrapper)
    local record=tidyBindingRecord
    local specifications=bindingBase()
    if not specifications or not record or not bindingEqual(valid,record.valid) or not bindingEqual(wrapper,record.wrapper) then return nil end
    specifications[#specifications+1]={owner=record,exact=true}
    if not bindingEqual(bindingOwn(bindingGlobals,"P4TidyUpMeister"),record.owner)
        or not bindingFields(specifications,record.owner,record.ownerMethods) then return nil end
    if not addBindingDependencies(specifications,record.dependencies) then return nil end
    return privateTransferBinding(action,specifications)
end
Compat.tidyBinding=tidyBindingFactory
local function verified(id, files)
    for _, file in ipairs(files or sourceFiles[id]) do
        if not Proof.matches("media/lua/" .. file[1], file[2], id, true) then return false end
    end
    return true
end
Compat.verifySources = verified

local quartermasterContainers
local CraftContainers = require "PZSurvivorToolkit/QuartermasterCraftContainers"
local activeCraftContext = CraftContainers.active
function Compat.matchesQuartermasterContainerGetter(previous, replacement)
    local saved = quartermasterContainers
    if not saved or saved.previous ~= previous or saved.replacement ~= replacement or LootSorter ~= saved.owner
        or not saved.owner._craftHooksAdded or not saved.owner._getContainersWrapped
        or ISTimedActionQueue ~= saved.queue or saved.queue.isPlayerDoingAction ~= saved.busy
        or CraftContainers.active ~= saved.active or saved.owner.DBG ~= saved.debug then return false end
    -- Only forwarding is audited; an active availability scan may call arbitrary storage helpers.
    if saved.owner.craftFromBoxes and not saved.owner._activelyCrafting and saved.active() then return false end
    return true
end
function Compat.installQuartermasterCraft(install)
    local owner = LootSorter
    if owner._craftHooksAdded then return end
    local previous = ISInventoryPaneContextMenu.getContainers
    local queue, busy = ISTimedActionQueue, ISTimedActionQueue.isPlayerDoingAction
    local active = activeCraftContext
    local debug = owner.DBG
    local neat = craftOwners.NC_CraftActionPanel
    local neatUnchanged = neat and NC_CraftActionPanel == neat.class
    if neatUnchanged then
        for method, expected in pairs(neat.methods) do
            if neat.class[method] ~= expected then neatUnchanged = false; break end
        end
    end
    install()
    local replacement = ISInventoryPaneContextMenu.getContainers
    if LootSorter ~= owner or not owner._craftHooksAdded or not owner._getContainersWrapped
        or CraftContainers.active ~= active then return end
    quartermasterContainers = {previous = previous, replacement = replacement, owner = owner, debug = debug,
        queue = queue, busy = busy, active = active}
    if neatUnchanged and NC_CraftActionPanel == neat.class then
        for method, expected in pairs(neat.methods) do
            if method ~= "prerender" and method ~= "onCraftButtonClick" and neat.class[method] ~= expected then
                neatUnchanged = false; break
            end
        end
        if neatUnchanged then
            neat.methods.prerender = neat.class.prerender
            neat.methods.onCraftButtonClick = neat.class.onCraftButtonClick
        end
    end
end

local function snapshot(class)
    local methods = {Type = class.Type}
    for _, name in ipairs(lifecycle) do methods[name] = class[name] end
    for name, method in pairs(class) do if type(method) == "function" then methods[name] = method end end
    return methods
end

local function classUnchanged(class, methods)
    for name, method in pairs(methods) do if class[name] ~= method then return false end end
    for _, name in ipairs(lifecycle) do if class[name] ~= methods[name] then return false end end
    return true
end

-- BulkActions owns the stop delegate and optionally an empty completion that
-- prevents merging. Validate those exact differences before admitting them
-- into Tidy's source proof; never call Policy.inspect from this binding check.
local bulkTransferBinding
local function ownedBulkStop(action, original)
    if getmetatable(action)~=ISInventoryTransferAction or action.Type~='ISInventoryTransferAction'then return false end
    local guard=action.toolkitTransferGuard
    if type(guard)~='table'or action.stop~=guard.stop or guard.original~=original then return false end
    local bulk,policy=Toolkit.BulkActions,Toolkit.ActionQueuePolicy
    if not bulk or not policy or not Proof.closure(bulk.guardTransfer,'BulkActions.lua')
        or not Proof.closure(bulk.isGuardedTransfer,'BulkActions.lua')
        or not Proof.closure(policy.matchesNative,'ActionQueuePolicy.lua')
        or not Proof.closure(policy.isOrdinaryTransfer,'ActionQueuePolicy.lua')then return false end
    if not bulkTransferBinding then
        bulkTransferBinding={bulk=bulk,policy=policy,guard=bulk.guardTransfer,guarded=bulk.isGuardedTransfer,
            native=policy.matchesNative,ordinary=policy.isOrdinaryTransfer}
    end
    local saved=bulkTransferBinding
    return bulk==saved.bulk and policy==saved.policy and bulk.guardTransfer==saved.guard
        and bulk.isGuardedTransfer==saved.guarded and policy.matchesNative==saved.native
        and policy.isOrdinaryTransfer==saved.ordinary and saved.guarded(action,original)==true
        and Proof.closure(action.stop,'BulkActions.lua')and saved.ordinary(action)==true
end
local function ownedBulkCompletion(action)
    if not action.onCompleteFunc or action.onCompleteFunc~=action.toolkitQueueSafeOnComplete
        or not Proof.closure(action.onCompleteFunc,'BulkActions.lua')
        or type(action.onCompleteArgs)~='table'or getmetatable(action.onCompleteArgs)then return false end
    for _ in pairs(action.onCompleteArgs)do return false end
    return true
end
local function ownedNativeBulkTransfer(action)
    if not ownedBulkStop(action,ISInventoryTransferAction.stop)then return false end
    local stopOnly=action.onCompleteFunc==nil
    local args=action.onCompleteArgs
    if stopOnly and args~=nil then
        if type(args)~='table'or getmetatable(args)then stopOnly=false
        else for _ in pairs(args)do stopOnly=false;break end end
    end
    return (stopOnly or ownedBulkCompletion(action))and bulkTransferBinding.native(action)==true
end

local function sourceClassUnchanged(id, class, methods, clothingTransfer)
    if id == "WashFix" and class == ISWashClothing and washWaterComplete and methods.complete == washWaterComplete
        and (WashWaterRule.matchesComplete ~= washWaterMatches or not washWaterMatches(methods.complete)) then return false end
    return classUnchanged(class, methods) or id == "WashFix" and clothingTransfer == true and class == ISInventoryTransferAction
        and reviewedTransferClassUnchanged and reviewedTransferClassUnchanged(class, class, methods)
        or id == "P4TidyUpMeister" and (class == ISInventoryTransferAction or class == ISUnequipAction)
        and tidyClassUnchanged and tidyClassUnchanged(class, class, methods)
end

local function live(record)
    if record.settlement and not Settlement.isLive(record) then return false end
    local character, queue, token = record.character, record.queue, record.token
    if not token or token.toolkitCancelled or not Toolkit.Settings.actionQueue()
        or (record.worldGeneration and record.worldGeneration ~= worldGeneration)
        or character:isDead() or ISTimedActionQueue.queues[character] ~= queue
        or (queue.toolkitOperationGeneration or 0) ~= record.generation then return false end
    local target = record.target
    if target and ((target.getObjectIndex and target:getObjectIndex() == -1)
        or (target.getSquare and not target:getSquare())) then return false end
    if record.id == "WashFix" and target and character.getSquare and target.getSquare then
        local here, there = character:getSquare(), target:getSquare()
        if not here or not there or here:getZ() ~= there:getZ()
            or math.abs(here:getX() - there:getX()) > 1 or math.abs(here:getY() - there:getY()) > 1 then return false end
    end
    return true
end

local function captureProjectCookConfig()
    if not pcall(require, "Project_Cook/PJCK_Config") or type(PJCK_Config) ~= "table" then return false end
    local methods = {}
    for _, name in ipairs({"get", "getBaseItemHandling", "shouldReturnBaseItemToSource", "load", "validate"}) do
        local callback = PJCK_Config[name]
        if not Proof.closure(callback, "PJCK_Config.lua") then return false end
        methods[name] = callback
    end
    projectCookConfig = {owner = PJCK_Config, methods = methods}
    return true
end

local function ownerUnchanged(id)
    if id == "Project_Cook" then
        if not projectCookConfig or PJCK_Config ~= projectCookConfig.owner then return false end
        for name, callback in pairs(projectCookConfig.methods) do
            if PJCK_Config[name] ~= callback then return false end
        end
    end
    if id == "WashFix" and washWalkHelper then
        if luautils ~= washWalkHelper.owner or luautils.walkAdj ~= washWalkHelper.callback then return false end
    end
    for _, owner in ipairs(owners[id] or {}) do
        for name, method in pairs(owner.methods) do if owner.target[name] ~= method then return false end end
    end
    return true
end

local function instanceUnchanged(target, class)
    if not target or getmetatable(target) ~= class then return false end
    for name, callback in pairs(class) do
        if type(callback) == "function" and target[name] ~= callback then return false end
    end
    for name, callback in pairs(target) do
        if type(callback) == "function" and callback ~= class[name] then return false end
    end
    return true
end

local clothingSourceSafe
local clothingMethods = {"isValid", "update", "start", "stop", "perform", "complete", "isAlreadyEquipped",
    "getDuration", "stopSound", "isStopOnWalk"}
local Clothing=require 'PZSurvivorToolkit/ActionQueueClothing'
local clothingMeta=toolkitLuaMetatableMatches
local clothingBindings=Clothing and Clothing.bindingsTrusted
local ordinaryClothingItem=Clothing and Clothing.ordinaryClothingItem
local ordinaryClothing=Clothing and Clothing.ordinaryClothing
local clothingWornState=Clothing and Clothing.clothingWornState
local nonnegativeFinite=Clothing and Clothing.nonnegativeFinite
local displacedClothing=Clothing and Clothing.displacedClothing
local ordinaryClothingWear=Clothing and Clothing.ordinaryClothingWear
local clothingRemovalCapacity=Clothing and Clothing.clothingRemovalCapacity
local clothingHelperSource
local function nativeClothingMethods()
    if type(clothingMeta)~="function" or type(Clothing)~="table" or not clothingMeta(Toolkit,nil)
        or not clothingMeta(Clothing,nil) or Toolkit.ActionQueueClothing~=Clothing or Clothing.bindingsTrusted~=clothingBindings
        or type(clothingBindings)~="function" or not clothingBindings() then return false end
    if clothingHelperSource==nil then
        clothingHelperSource=Proof.closure(clothingBindings,"ActionQueueClothing.lua")
            and Proof.matches("media/lua/client/PZSurvivorToolkit/ActionQueueClothing.lua",2600563667,"PZSurvivorToolkit",true)
    end
    if not clothingHelperSource then return false end
    if clothingSourceSafe == nil then
        clothingSourceSafe = Proof.matches("media/lua/shared/TimedActions/ISWearClothing.lua", 1104211581, nil, true)
    end
    if not clothingSourceSafe then return false end
    for _, name in ipairs(clothingMethods) do
        if not Proof.closure(ISWearClothing[name], "ISWearClothing.lua") then return false end
    end
    return true
end
local function clothingRestore(action, class)
    if class ~= ISWearClothing or not nativeClothingMethods() then return end
    for _, name in ipairs(clothingMethods) do if action[name] ~= class[name] then return end end
    return ordinaryClothingWear(action)
end

local unequipSourceSafe
local unequipMethods = {"new", "isValid", "update", "start", "stop", "animEvent", "perform", "complete"}
local function nativeUnequipMethods(action)
    if unequipSourceSafe == nil then
        unequipSourceSafe = Proof.matches("media/lua/shared/TimedActions/ISUnequipAction.lua", 2851923231, nil, true)
    end
    if not unequipSourceSafe or not nativeClothingMethods() then return false end
    local variant
    for _, name in ipairs(unequipMethods) do
        if not Proof.closure(ISUnequipAction[name], "ISUnequipAction.lua") then
            if name ~= "new" and name ~= "complete" then return false end
            if variant == nil then variant = tidyUnequipVariant and tidyUnequipVariant(action) or false end
            if not variant then return false end
        end
    end
    return true
end
local ordinaryClothingRemoval=Clothing and Clothing.ordinaryClothingRemoval
local function clothingRemoval(action, class)
    if class ~= ISUnequipAction or action.fromHotbar or action.reason ~= nil or not nativeUnequipMethods(action) then return end
    for _, name in ipairs(unequipMethods) do if action[name] ~= class[name] then return end end
    local location = ordinaryClothingRemoval(action)
    local worn = location and action.character:getWornItem(location)
    if not worn or worn:getID() ~= action.item:getID() or worn:getFullType() ~= action.item:getFullType() then return end
    return location
end

local hotbarSourcesSafe, hotbarHelpers
local function nativeHotbarHelpers(hotbar)
    if hotbarSourcesSafe == nil then
        hotbarSourcesSafe = Proof.matches("media/lua/client/Hotbar/ISHotbar.lua", 3215104203, nil, true)
            and Proof.matches("media/lua/client/ISUI/PlayerData/ISPlayerData.lua", 2353448738, nil, true)
    end
    if not hotbarSourcesSafe or not ISHotbar then return false end
    if not hotbarHelpers then
        if not Proof.closure(getPlayerHotbar, "ISPlayerData.lua") or not Proof.closure(getPlayerData, "ISPlayerData.lua")
            or not Proof.closure(ISHotbar.isItemAttached, "ISHotbar.lua") or not Proof.closure(ISHotbar.setAttachAnim, "ISHotbar.lua") then return false end
        hotbarHelpers = {owner = ISHotbar, getter = getPlayerHotbar, data = getPlayerData,
            attached = ISHotbar.isItemAttached, animate = ISHotbar.setAttachAnim}
    end
    return ISHotbar == hotbarHelpers.owner and getPlayerHotbar == hotbarHelpers.getter and getPlayerData == hotbarHelpers.data
        and ISHotbar.isItemAttached == hotbarHelpers.attached and ISHotbar.setAttachAnim == hotbarHelpers.animate
        and hotbar and hotbar.isItemAttached == hotbarHelpers.attached and hotbar.setAttachAnim == hotbarHelpers.animate
end
local hotbarClassName = getClassSimpleName
local function passiveHotbarComponents(item, script)
    if not script:hasComponents() then return not item:hasComponents() end
    if not ComponentType or not ComponentType.Attributes or not ComponentType.Script then return false end
    for _, name in ipairs({"componentSize", "getComponentForIndex", "getAttributes", "getComponent", "getEntityScript"}) do
        if type(item[name]) ~= "function" then return false end
    end
    if type(script.getComponentScripts) ~= "function" or type(script.getComponentScriptFor) ~= "function" then return false end
    local scripts = script:getComponentScripts()
    if not scripts or type(scripts.size) ~= "function" or type(scripts.get) ~= "function"
        or scripts:size() ~= 1 or not item:hasComponents() or item:componentSize() ~= 2 then return false end
    local definition, attributes = scripts:get(0), item:getAttributes()
    if not definition or hotbarClassName(definition) ~= "AttributesScript"
        or script:getComponentScriptFor(ComponentType.Attributes) ~= definition
        or not attributes or hotbarClassName(attributes) ~= "AttributeContainer"
        or type(attributes.getComponentType) ~= "function" or type(attributes.getOwner) ~= "function"
        or attributes:getComponentType() ~= ComponentType.Attributes or attributes:getOwner() ~= item then return false end
    -- The factory adds passive Script metadata to an entity with Attributes.
    -- This is EntityScriptInfo, not an executable Lua callback/component.
    local metadata = item:getComponent(ComponentType.Script)
    if not metadata or hotbarClassName(metadata) ~= "EntityScriptInfo" then return false end
    for _, name in ipairs({"getComponentType", "getOwner", "getScript", "getOriginalScript", "isOriginalIsItem"}) do
        if type(metadata[name]) ~= "function" then return false end
    end
    if metadata:getComponentType() ~= ComponentType.Script or metadata:getOwner() ~= item
        or metadata:getScript() ~= script or item:getEntityScript() ~= script
        or metadata:getOriginalScript() ~= item:getFullType() or metadata:isOriginalIsItem() ~= true then return false end
    local first, second = item:getComponentForIndex(0), item:getComponentForIndex(1)
    return first == attributes and second == metadata or first == metadata and second == attributes
end
local function hotbarScript(item, class, kind)
    if not instanceof(item, "InventoryItem") or type(hotbarClassName) ~= "function" or getClassSimpleName ~= hotbarClassName
        or hotbarClassName(item) ~= class then return end
    for _, name in ipairs({"getScriptItem", "hasComponents", "getFluidContainer", "isWet", "getItemWhenDry"}) do
        if type(item[name]) ~= "function" then return end
    end
    local script = item:getScriptItem()
    if not script then return end
    for _, name in ipairs({"getFullName", "getItemType", "getLuaCreate", "getItemConfig", "getItemConfigKey", "hasComponents"}) do
        if type(script[name]) ~= "function" then return end
    end
    if script:getFullName() ~= item:getFullType() or tostring(script:getItemType()) ~= kind
        or script:getLuaCreate() or script:getItemConfig() or script:getItemConfigKey()
        or item:getFluidContainer() or item:isWet() or item:getItemWhenDry() then return end
    return passiveHotbarComponents(item, script) and script or nil
end
local function normalHotbarItem(item)
    -- Native base:normal creates final ComboItem. Ordinary Attributes (including
    -- sharpness) and factory Script metadata have no update/equipment hooks.
    return hotbarScript(item, "ComboItem", "base:normal") ~= nil
end
local function radioHotbarItem(item)
    if not instanceof(item, "Radio") or not hotbarScript(item, "Radio", "base:radio")
        or type(item.getDeviceData) ~= "function" then return false end
    local data = item:getDeviceData()
    if not data or hotbarClassName(data) ~= "DeviceData" then return false end
    for _, name in ipairs({"getParent", "getIsPortable", "getIsBatteryPowered", "getIsTelevision", "hasMedia", "isPlayingMedia"}) do
        if type(data[name]) ~= "function" then return false end
    end
    -- DeviceData power is separate from InventoryItem activation. Native hand
    -- removal changes the equipped-radio pointer and its update/audio path;
    -- do not turn off, reset the battery clock or replace device synchronization.
    return data:getParent() == item and data:getIsPortable() == true and data:getIsBatteryPowered() == true
        and data:getIsTelevision() == false and data:hasMedia() == false and data:isPlayingMedia() == false
end
local function flashlightHotbarItem(item)
    local script = instanceof(item, "DrainableComboItem") and hotbarScript(item, "DrainableComboItem", "base:drainable")
    if not script or not ItemTag or not ItemTag.FLASHLIGHT then return false end
    for _, name in ipairs({"hasTag", "isKeepOnDeplete", "isUseWhileEquiped", "isUseWhileUnequiped", "getUseDelta",
        "getReplaceOnDeplete", "getReplaceOnDepleteFullType", "getReplaceOnCooked", "getOnCooked", "getOnEat",
        "isCookable", "getLightStrength", "getLightDistance", "isTorchCone"}) do
        if type(item[name]) ~= "function" then return false end
    end
    for _, name in ipairs({"getReplaceOnUse", "getOnBreak"}) do
        if type(script[name]) ~= "function" or script[name](script) then return false end
    end
    local cooked = item:getReplaceOnCooked()
    if cooked and (not instanceof(cooked, "List") or not cooked:isEmpty()) then return false end
    local strength, distance, delta = item:getLightStrength(), item:getLightDistance(), item:getUseDelta()
    -- Native depletion keeps this exact item but stops light emission. Unequip
    -- start owns deactivation/sync; never pin charge, emission or activation in
    -- the cleanup proof, refill the battery or manufacture replacement effects.
    return item:hasTag(ItemTag.FLASHLIGHT) == true and item:canBeActivated() == true and item:isTorchCone() == true
        and item:isKeepOnDeplete() == true and item:isUseWhileEquiped() == true and item:isUseWhileUnequiped() == false
        and not item:getReplaceOnDeplete() and not item:getReplaceOnDepleteFullType()
        and not item:getOnCooked() and not item:getOnEat() and item:isCookable() == false
        and nonnegativeFinite(strength) and strength > 0 and nonnegativeFinite(distance) and distance > 0
        and nonnegativeFinite(delta) and delta > 0 and delta <= 1
end
local function hotbarItem(item, character)
    local flashlight = flashlightHotbarItem(item)
    return (flashlight or instanceof(item, "HandWeapon") or normalHotbarItem(item) or radioHotbarItem(item)) and item:getContainer() == character:getInventory()
        and (flashlight or not item:canBeActivated()) and not item:isBroken() and not isForceDropHeavyItem(item)
        and not character:getWornItems():contains(item)
end
local function hotbarState(action, saved)
    local item, character, hotbar = action.item, action.character, action.hotbar
    if not hotbarItem(item, character) or not nativeHotbarHelpers(hotbar)
        or hotbar.chr ~= character or getPlayerHotbar(character:getPlayerNum()) ~= hotbar then return end
    local liveItem = character:getInventory():getItemById(item:getID())
    if not liveItem or liveItem:getFullType() ~= item:getFullType() or not hotbarItem(liveItem, character) then return end
    local index, kind, model, attachment = item:getAttachedSlot(), item:getAttachedSlotType(), item:getAttachedToModel(), item:getAttachmentType()
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(kind) ~= "string" or kind == ""
        or type(model) ~= "string" or model == "" or model == "null" or type(attachment) ~= "string" or attachment == ""
        or liveItem:getAttachedSlot() ~= index or liveItem:getAttachedSlotType() ~= kind
        or liveItem:getAttachedToModel() ~= model or liveItem:getAttachmentType() ~= attachment then return end
    local slots = hotbar.availableSlot
    if type(slots) ~= "table" or getmetatable(slots) then return end
    local slot = slots[index]
    local definition = type(slot) == "table" and not getmetatable(slot) and slot.def
    if type(definition) ~= "table" or getmetatable(definition) or slot.slotType ~= kind or definition.type ~= kind
        or type(definition.attachments) ~= "table" or getmetatable(definition.attachments)
        or type(definition.animset) ~= "string" or definition.animset == "" then return end
    local count = 0
    for _, candidate in pairs(slots) do
        if type(candidate) ~= "table" or getmetatable(candidate) or type(candidate.def) ~= "table" or getmetatable(candidate.def) then return end
        if candidate.def.type == kind then count = count + 1 end
    end
    if count ~= 1 then return end
    local expected = definition.attachments[attachment]
    if definition.name == "Back" and hotbar.replacements then
        if type(hotbar.replacements) ~= "table" or getmetatable(hotbar.replacements) then return end
        expected = hotbar.replacements[attachment] or expected
    end
    if expected ~= model or type(hotbar.attachedItems) ~= "table" or getmetatable(hotbar.attachedItems)
        or hotbar.attachedItems[index] ~= liveItem or not hotbar:isItemAttached(liveItem) then return end
    local attached = character:getAttachedItem(model)
    if attached and (attached:getID() ~= item:getID() or attached:getFullType() ~= item:getFullType()) then return end
    if saved then
        return saved.index == index and saved.kind == kind and saved.model == model and saved.attachment == attachment
            and saved.definition == definition and saved.name == definition.name and saved.animset == definition.animset or nil
    end
    return {index = index, kind = kind, model = model, attachment = attachment, definition = definition,
        name = definition.name, animset = definition.animset}
end
local function hotbarRestore(action, class)
    if class ~= ISUnequipAction or action.fromHotbar ~= true or action.reason ~= nil or not nativeUnequipMethods(action) then return end
    for _, name in ipairs(unequipMethods) do if action[name] ~= class[name] then return end end
    local item, character = action.item, action.character
    if item ~= character:getPrimaryHandItem() and item ~= character:getSecondaryHandItem() then return end
    return hotbarState(action)
end

local function sourceMatches(action, record, observedItem)
    record = record or records[action]
    if not record or getmetatable(action) ~= record.class or action.Type ~= record.class.Type
        or action.character ~= record.character or action.toolkitQueueOperation ~= record.token
        or not sourceClassUnchanged(record.id, record.class, record.baseline, record.washOrigin ~= nil) or not ownerUnchanged(record.id)
        or (record.owner and not instanceUnchanged(record.owner, PJCK_EvoPanel))
        or (record.class == ISInventoryTransferAction and containerHelpersUnchanged and not containerHelpersUnchanged()) then return false end
    local policy = Toolkit.ActionQueuePolicy
    if record.class == ISInventoryTransferAction and policy and policy.isOrdinaryTransfer and not policy.isOrdinaryTransfer(action) then return false end
    if record.class == ISEquipWeaponAction and (action.primary ~= record.primary or action.twoHands ~= record.twoHands
        or action.alwaysTurnOn ~= record.alwaysTurnOn) then return false end
    if record.class == ISUnequipAction and (action.reason ~= record.reason or action.fromHotbar ~= record.fromHotbar
        or action.hotbar ~= record.hotbar) then return false end
    if record.clothingVisual and action.character:getHumanVisual() ~= record.clothingVisual then return false end
    if record.tidyClothingUnequip and ordinaryClothingRemoval(action) ~= record.clothingLocation then return false end
    if record.tidyHotbarUnequip and not hotbarState(action, record.hotbarProof) then return false end
    if (record.tidyClothingUnequip or record.tidyHotbarUnequip) and (not nativeUnequipMethods(action)
        or action.clothingAction ~= record.clothingAction or action.stopOnWalk ~= record.stopOnWalk
        or action.stopOnRun ~= record.stopOnRun or action.animSpeed ~= record.animSpeed) then return false end
    if record.tidyClothingWear and (not nativeClothingMethods() or ordinaryClothingWear(action, record.clothingDisplaced) ~= record.clothingLocation
        or action.fromHotbar ~= record.fromHotbar or action.clothingAction ~= record.clothingAction
        or action.stopOnWalk ~= record.stopOnWalk or action.stopOnRun ~= record.stopOnRun) then return false end
    local bulkStop=record.class==ISInventoryTransferAction and ownedBulkStop(action,record.methods.stop)
    local bulkComplete=bulkStop and record.onCompleteFunc==nil and record.onCompleteArgs==nil
        and ownedBulkCompletion(action)
    local function bulkMethod(name)
        return name=='stop'and bulkStop or (name=='onCompleteFunc'or name=='toolkitQueueSafeOnComplete')and bulkComplete
    end
    for _, name in ipairs(lifecycle) do if action[name] ~= record.methods[name]and not bulkMethod(name)then return false end end
    for name, method in pairs(record.methods) do if action[name] ~= method and not bulkMethod(name)then return false end end
    for name, method in pairs(action) do
        if type(method) == "function" and method ~= record.methods[name]and not bulkMethod(name)then return false end
    end
    for _, name in ipairs({"onStartFunc", "onCancelFunc", "onCompleteFunc", "onCompleteTarget", "onCompleteArgs"}) do
        if action[name] ~= record[name]and not ((name=='onCompleteFunc'or name=='onCompleteArgs')and bulkComplete)then return false end
    end
    for name, value in pairs(record.fields) do
        local identity = name == "item" and observedItem or record.itemIdentities[name]
        if identity then
            local item = action[name]
            if not instanceof(item, "InventoryItem") or item:getID() ~= identity.id
                or item:getFullType() ~= identity.fullType then return false end
        elseif action[name] ~= value then return false end
    end
    if record.args then
        if getmetatable(action.onCompleteArgs) then return false end
        for i = 1, 8 do if action.onCompleteArgs[i] ~= record.args[i] then return false end end
    end
    if record.commandArgs then
        if getmetatable(action.args) then return false end
        for i, value in ipairs(record.commandArgs) do if action.args[i] ~= value then return false end end
    end
    return not action.retriggerLastAction and not action.onFailFunc and not action.additionalTest
end

local function matches(action, record)
    record = record or records[action]
    if not record or record.opaque then return false end
    return sourceMatches(action, record)
end

local function tidyRestoreContext(context, action)
    local session = context.tidySession
    local policy = Toolkit.ActionQueuePolicy
    if not session or not session.mixed or getmetatable(action) ~= ISInventoryTransferAction
        or not policy or not policy.isOrdinaryTransfer or not policy.isOrdinaryTransfer(action)
        or action.srcContainer ~= action.character:getInventory() or not instanceof(action.item, "InventoryItem") then return context end
    local owner = Settlement.owner(session, action.item:getID(), action.item:getFullType(), action.destContainer)
    if not owner then return context end
    local result = Settlement.context(session, owner)
    result.id = context.id
    return result
end

-- Source-sealed compound preparation is independent of completion/edit capabilities.
-- Only ordinary clothing commands migrate completion; other All branches stay legacy.
local washClothingCapability, washBatchCapability = {}, {}
local function clothingMenuSelection(args)
    if args.n == 6 and args[4] == nil and type(args[5]) == "boolean" then
        return args[3]
    end
    local data = args[3]
    if args.n ~= 5 or type(args[4]) ~= "boolean" or type(data) ~= "table" or getmetatable(data)
        or type(data.washYourself) ~= "boolean" or type(data.cleanBandages) ~= "boolean" then return end
    for key in pairs(data) do
        if key ~= "washYourself" and key ~= "regularItems" and key ~= "cleanBandages" then return end
    end
    if type(data.regularItems) ~= "table" or not data.cleanBandages and #data.regularItems + (data.washYourself and 1 or 0) < 2 then return end
    return data.regularItems, data
end
local function clothingMenuOrigin(callback, character, sink, args)
    if not Proof.closure(callback, "WMI_WashingSubmenus.lua") or not instanceof(character, "IsoGameCharacter")
        or not instanceof(sink, "IsoObject") or args[1] ~= sink then return end
    local selected, aggregate = clothingMenuSelection(args)
    if type(selected) ~= "table" or getmetatable(selected) then return end
    local count, inputs, ordinary = 0, {}, not aggregate or not aggregate.cleanBandages
    for key, item in pairs(selected) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #selected
            or not instanceof(item, "InventoryItem") or not item.getItemAfterCleaning then return end
        local after = item:getItemAfterCleaning()
        local clothing = instanceof(item, "Clothing") and (after == nil or after == "")
        if not aggregate and not clothing then return end
        if not clothing then ordinary = false end
        local id, fullType, container = item:getID(), item:getFullType(), item:getContainer()
        if inputs[id] or not container then return end
        inputs[id] = {item = item, fullType = fullType, source = container, position = key, afterType = after}
        count = count + 1
    end
    if count == 0 or count ~= #selected then return end
    -- No regular items means every native approach keeps prior work; do not declare replacement.
    return {capability = ordinary and washClothingCapability or washBatchCapability, character = character, sink = sink,
        root = character:getInventory(), inputs = inputs, arguments = args, selected = selected,
        aggregate = aggregate, washYourself = aggregate and aggregate.washYourself,
        cleanBandages = aggregate and aggregate.cleanBandages, transfers = {}}
end
local function clothingMenuMatches(origin, args, preparationOnly)
    if not origin or args.n < origin.arguments.n + 1 or args.n > 11 or args[1] ~= origin.character
        or origin.character:getInventory() ~= origin.root then return false end
    for i = 1, origin.arguments.n do if args[i + 1] ~= origin.arguments[i] then return false end end
    -- Native ISContextMenu invokes all ten parameter slots, including trailing nils.
    for i = origin.arguments.n + 2, args.n do if args[i] ~= nil then return false end end
    local selected, aggregate = clothingMenuSelection(origin.arguments)
    if selected ~= origin.selected or aggregate ~= origin.aggregate or getmetatable(selected)
        or aggregate and (aggregate.washYourself ~= origin.washYourself or aggregate.cleanBandages ~= origin.cleanBandages) then return false end
    local count = 0
    for key, item in pairs(selected) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #selected
            or not instanceof(item, "InventoryItem") or not item.getItemAfterCleaning then return false end
        local expected, after = origin.inputs[item:getID()], item:getItemAfterCleaning()
        if not expected or expected.item ~= item or expected.position ~= key or expected.fullType ~= item:getFullType()
            or not preparationOnly and (expected.source ~= item:getContainer() or after ~= expected.afterType) then return false end
        count = count + 1
    end
    local expected = 0; for _ in pairs(origin.inputs) do expected = expected + 1 end
    return count == expected
end
local function clothingSourceAction(origin, action, class)
    if not origin or origin.capability ~= washClothingCapability or action.character ~= origin.character
        or action.character:getInventory() ~= origin.root then return false end
    if class.Type == "WMI_WaitForInvUpdate" then return origin.transfers[action.wmiTransferAction] == true end
    if class ~= ISInventoryTransferAction and class ~= ISWashClothing then return false end
    local item = action.item
    if not instanceof(item, "Clothing") or not item.getItemAfterCleaning then return false end
    local expected, after = origin.inputs[item:getID()], item:getItemAfterCleaning()
    if not expected or item:getFullType() ~= expected.fullType or after ~= nil and after ~= "" then return false end
    if class == ISWashClothing then
        return action.sink == origin.sink and action.wmiReturnContainer == nil and action.wmiWaterOverride == nil
    end
    local pickup = action.srcContainer == expected.source and action.destContainer == origin.root
    local returning = action.srcContainer == origin.root and action.destContainer == expected.source
    if not pickup and not returning then return false end
    return true
end

local scoped, rememberTidy
local function adopt(action)
    local context = sourceScope
    if not context then return end
    -- Verified Toolkit dispatchers already own their scope and lifecycle. A
    -- foreign producer may enqueue them, but must not replace their executor.
    if Operations.isCommand and Operations.isCommand(action) then return end
    local class = getmetatable(action)
    local baseline = classes[context.id] and classes[context.id][class]
    local clothing = baseline and context.id == "WashFix" and clothingSourceAction(context.washOrigin, action, class)
    if not baseline or not sourceClassUnchanged(context.id, class, baseline, clothing) or action.onStartFunc or action.onCancelFunc
        or action.retriggerLastAction or action.onFailFunc or action.additionalTest then return end
    local clothingLocation, clothingDisplaced
    if context.id == "P4TidyUpMeister" then clothingLocation, clothingDisplaced = clothingRestore(action, class) end
    local removalLocation = context.id == "P4TidyUpMeister" and clothingRemoval(action, class)
    local hotbarProof = context.id == "P4TidyUpMeister" and hotbarRestore(action, class)
    local wornLocation = clothingLocation or removalLocation
    local clothingVisual = wornLocation and (wornLocation == ItemBodyLocation.HAT or wornLocation == ItemBodyLocation.FULL_HAT)
        and action.character:getHumanVisual() or nil
    local tidyHandUnequip = context.id == "P4TidyUpMeister" and class == ISUnequipAction and not action.fromHotbar
            and (action.item == action.character:getPrimaryHandItem() or action.item == action.character:getSecondaryHandItem())
            and not action.character:getWornItems():contains(action.item) and not isForceDropHeavyItem(action.item)
    if context.id == "P4TidyUpMeister" and class == ISUnequipAction and not classUnchanged(class, baseline)
        and (not (tidyHandUnequip or removalLocation or hotbarProof) or not tidyClassUnchanged(action, class, baseline)) then return end
    context = tidyRestoreContext(context, action)
    if context.id == "P4TidyUpMeister" and not live(context) then return false end
    Operations.adopt(action, context.token)
    if records[action] then return end
    local queue = ISTimedActionQueue.getTimedActionQueue(action.character)
    local record = {class = class, baseline = baseline, character = action.character,
        token = action.toolkitQueueOperation, queue = queue, generation = queue.toolkitOperationGeneration or 0, worldGeneration = worldGeneration,
        id = context.id, target = context.target, fields = {}, itemIdentities = {}, owner = context.owner,
        primary = action.primary, twoHands = action.twoHands, alwaysTurnOn = action.alwaysTurnOn,
        reason = action.reason, fromHotbar = action.fromHotbar, hotbar = action.hotbar,
        tidyHandUnequip = tidyHandUnequip, tidyClothingWear = clothingLocation ~= nil and clothingLocation ~= false,
        tidyClothingUnequip = removalLocation ~= nil and removalLocation ~= false,
        tidyHotbarUnequip = type(hotbarProof) == "table", hotbarProof = hotbarProof,
        clothingLocation = wornLocation, clothingDisplaced = clothingDisplaced, clothingVisual = clothingVisual,
        clothingAction = action.clothingAction, animSpeed = action.animSpeed,
        stopOnWalk = action.stopOnWalk, stopOnRun = action.stopOnRun,
        opaque = context.opaque or (context.sharedCleanup and class == P4RestoreFloorAction),
        settlement = context.settlement, obligation = Settlement.obligation(context)}
    if clothing then
        record.washOrigin = context.washOrigin
        if class == ISInventoryTransferAction and action.destContainer == context.washOrigin.root then
            context.washOrigin.transfers[action] = true
        end
    end
    records[action] = record
    if context.id == "Project_Cook" and class == ISAddItemInRecipe then context.lastApply = action end
    if class == ISQueueActionsAction then
        record.cleanupFor, context.lastApply = context.lastApply, nil
        local callback = action.addActionsFunction
        record.commandArgs = {}
        for i, value in ipairs(action.args) do record.commandArgs[i] = value end
        action.start = function(self)
            if record.expanded then return end
            record.expanded = true
            if live(record) and matches(self) then
                return expandCommand(self, Operations.runWith, record.token,
                    scoped, record, callback, self.character, unpack(self.args))
            end
            -- The source may have lost its target; native's empty-command path clears unrelated work.
            self:forceComplete()
        end
        action.waitToStart = function(self)
            if not self.toolkitCompletionWaited then self.toolkitCompletionWaited = true; return true end
            return false
        end
    end
    for _, name in ipairs({"item", "sink", "srcContainer", "destContainer", "slotType", "activated", "x", "y", "z",
        "offX", "offY", "offZ", "rotationX", "rotationY", "rotationZ",
        "addActionsFunction", "args", "toolkitQueueCommand", "wmiTransferAction", "wmiReturnContainer", "wmiOriginalContainer",
        "baseItem", "usedItem", "recipe", "soaps"}) do
        if action[name] ~= nil then
            record.fields[name] = action[name]
            if instanceof(action[name], "InventoryItem") then
                -- Native transferItem can rebind a Java item proxy; its inventory identity must stay the same.
                record.itemIdentities[name] = {id = action[name]:getID(), fullType = action[name]:getFullType()}
            end
        end
    end
    local sourceCompletion=action.onCompleteFunc
    if action.onCompleteFunc then
        local callback, args = action.onCompleteFunc, action.onCompleteArgs
        if type(args) ~= "table" or args[1] ~= action then records[action] = nil; return end
        record.args = {}
        for i = 1, 8 do record.args[i] = args[i] end
        action.onCompleteFunc = function(...)
            if record.continued or not matches(action, record) or not live(record) then return end
            record.continued = true
            local handle = Operations.attachContinuation(record.token, record.character)
            return Operations.runContinuation(handle, function(...)
                return scoped(record, callback, ...)
            end, ...)
        end
    end
    local function returnGuard(candidate, member)
        -- This override is for native observation only. Policy matches still
        -- requires the original item and keeps its existing edit permissions.
        return candidate == action and not record.opaque and sourceMatches(action, record, member)
    end
    local function returnTransfer(self)
        return self == action and record.id == "P4TidyUpMeister" and record.class == ISInventoryTransferAction and record.obligation
            and self.srcContainer == self.character:getInventory() and self.destContainer and self.destContainer:getType() ~= "floor"
    end
    local perform = action.perform
    action.perform = function(self, ...)
        local returning = returnTransfer(self) and Settlement.returnMatches(self, record.obligation)
        if matches(self, record) or returning then
            return Operations.perform(self, function(...)
                local observed = returnTransfer(self) and Settlement.beginReturn(self, record.obligation, returnGuard)
                if not observed then return scoped(record, perform, ...) end
                local results = pack(pcall(scoped, record, perform, ...))
                Settlement.finishReturn(record.obligation, results[1])
                if not results[1] then error(results[2], 0) end
                return unpack(results, 2, results.n)
            end, ...)
        end
        return perform(self, ...)
    end
    local sourceStop
    if record.id == "P4TidyUpMeister" and record.class == ISInventoryTransferAction then
        local stop = action.stop
        sourceStop=stop
        action.stop = function(self, ...)
            if returnTransfer(self) and (matches(self, record) or Settlement.returnMatches(self, record.obligation)) then
                -- Capture before the native delegate removes its item transaction.
                -- Observation failure must not prevent the original stop call.
                pcall(Settlement.stopReturn, self, record.obligation, returnGuard)
            end
            return stop(self, ...)
        end
    end
    if sourceStop then
        record.transferBinding={performDelegate=perform,performWrapper=action.perform,
            stopDelegate=sourceStop,stopWrapper=action.stop,completion=sourceCompletion,dependencies=bindingDependencies()}
    end
    action.toolkitQueueSafeOnComplete = action.onCompleteFunc
    record.methods = snapshot(action)
    for name in pairs(baseline) do if record.methods[name] == nil then record.methods[name] = action[name] end end
    for _, name in ipairs({"onStartFunc", "onCancelFunc", "onCompleteFunc", "onCompleteTarget", "onCompleteArgs"}) do
        record[name] = action[name]
    end
end

scoped = function(context, callback, ...)
    if not context.token and not ownerUnchanged(context.id) then return callback(...) end
    local nativeMenu = not context.token and not Toolkit.Settings.actionQueue()
    if nativeMenu and context.id ~= "WashFix" then return callback(...) end
    local previous = sourceScope
    if not nativeMenu then sourceScope = context end
    local insert, add, addAfter, queueActions = table.insert, ISTimedActionQueue.add,
        ISTimedActionQueue.addAfter, ISTimedActionQueue.queueActions
    local addOption = ISContextMenu and ISContextMenu.addOption
    local function valid() return ownerUnchanged(context.id) and (not context.token or live(context)) end
    if not nativeMenu then
        ISTimedActionQueue.add = function(action)
            if context.id == "P4TidyUpMeister" and sessions[action.character] then sessions[action.character].restored = true end
            if not valid() then return end
            if adopt(action) == false then return end
            return add(action)
        end
        ISTimedActionQueue.addAfter = function(previousAction, action)
            if not valid() then return end
            if previousAction then action.toolkitQueueOperation = previousAction.toolkitQueueOperation end
            if adopt(action) == false then return end
            return addAfter(previousAction, action)
        end
        table.insert = function(target, ...)
            local args = pack(...)
            local action = args[args.n]
            local queue = type(action) == "table" and action.character and ISTimedActionQueue.queues[action.character]
            if queue and target == queue.queue then
                if not valid() then return end
                if adopt(action) == false then return end
                local results = pack(insert(target, unpack(args, 1, args.n)))
                if rememberTidy then rememberTidy(action) end
                Operations.invalidateTitle(action)
                return unpack(results, 1, results.n)
            end
            return insert(target, unpack(args, 1, args.n))
        end
        ISTimedActionQueue.queueActions = function(character, callback, ...)
            if not valid() then return end
            return queueActions(character, callback, ...)
        end
    end
    if addOption and context.id == "WashFix" then
        ISContextMenu.addOption = function(menu, label, target, callback, ...)
            if callback then
                local original, sink = callback, select(1, ...)
                local origin = clothingMenuOrigin(original, target, sink, pack(...))
                callback = function(...)
                    return Operations.run(function(...)
                        local context = {id = "WashFix", target = instanceof(sink, "IsoObject") and sink or nil}
                        if ownerUnchanged("WashFix") and clothingMenuMatches(origin, pack(...), true) then
                            if origin.capability == washClothingCapability and clothingMenuMatches(origin, pack(...)) then context.washOrigin = origin end
                            local approach = Toolkit.ActionQueueApproach
                            if origin.aggregate and approach and approach.runNativeBatch then
                                return approach.runNativeBatch(origin.character, scoped, context, original, ...)
                            end
                        end
                        return scoped(context, original, ...)
                    end, ...)
                end
            end
            return addOption(menu, label, target, callback, ...)
        end
    end
    local results = pack(pcall(callback, ...))
    table.insert, ISTimedActionQueue.add, ISTimedActionQueue.addAfter, ISTimedActionQueue.queueActions = insert, add, addAfter, queueActions
    if addOption then ISContextMenu.addOption = addOption end
    sourceScope = previous
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
end

local function inspect(action)
    local record = records[action]
    -- Off-mode native merging may absorb a different operation. Its native
    -- completion remains valid, but the old exclusive edit contract does not.
    if record.mixedTransferOwners then return end
    local result = {items = {}, itemTypes = {}, targets = {}, callbacksSafe = true,
        cancelWaiting = true, interrupt = "audited-stop", preparationFinish = true}
    for _, field in ipairs({"item", "primary", "secondary", "baseItem", "usedItem"}) do
        local item = action[field]
        if instanceof(item, "InventoryItem") then result.items[item:getID()] = true; result.itemTypes[item:getFullType()] = true end
    end
    for _, batch in ipairs(action.queueList or {}) do
        for _, item in ipairs(batch.items or {}) do
            if not instanceof(item, "InventoryItem") then return end
            result.items[item:getID()] = true; result.itemTypes[item:getFullType()] = true
        end
    end
    for id, entry in pairs(record.clothingDisplaced or {}) do
        result.items[id] = true; result.itemTypes[entry.fullType] = true
    end
    if action.sink then result.targets[action.sink] = true end
    if record.class == ISWashClothing and action.soaps then
        if not instanceof(action.soaps, "List") then return end
        result.dynamicInputs = {}
        for i = 0, action.soaps:size() - 1 do
            local item = action.soaps:get(i)
            if not instanceof(item, "InventoryItem") then return end
            result.items[item:getID()] = true; result.itemTypes[item:getFullType()] = true
            result.dynamicInputs[item:getFullType()] = true
        end
        -- MP chooses soap again on the server, including newly reachable fluid containers.
        -- Native's generic-item branch uses soap even when noSoap is true.
        if not action.noSoap or (not instanceof(action.item, "Clothing") and not instanceof(action.item, "InventoryContainer")
            and not action.item:getItemAfterCleaning()) then result.knownInputs = false end
    end
    for _, container in pairs({action.srcContainer, action.destContainer, action.wmiReturnContainer}) do
        Toolkit.ActionQueuePolicy.addContainerResources(result, container)
    end
    if record.target then result.targets[record.target] = true end
    -- Claim every admitted headwear visual, including initially plain hair:
    -- native hair edits/sync mutate this stable object before cleanup runs.
    if record.clothingVisual then result.targets[record.clothingVisual] = true end
    if record.id ~= "WashFix" then result.hands = action.character end
    if record.class == ISQueueActionsAction then result.deferred, result.knownInputs = true, false end
    if record.class == ISWashClothing or record.class == ISAddItemInRecipe then result.unknownOutputs = true end
    -- The following source command repairs invalid consumed spice on the authoritative side.
    if record.class == ISAddItemInRecipe or record.cleanupFor or Settlement.required(record.obligation) then result.cancelOperation = false end
    if record.class == P4RestoreFloorAction then
        -- Floor placement is a server completion effect, never an interrupted client-side restore.
        result.interrupt, result.preparationFinish = "finish-step", true
        local target = getCell and getCell():getGridSquare(action.x, action.y, action.z)
        if not target then return end
        result.targets[target] = true
    end
    return result
end

local function repairTidyFloor(character, callback, ...)
    if not character or not character:isLocalPlayer() or not isClient() or not tidyActionUnchanged
        or not tidyFloorValid or P4RestoreFloorAction.isValid ~= tidyFloorValid
        or ISInventoryPage ~= tidyFloorPage or not tidyFloorGetter
        or tidyFloorPage.GetFloorContainer ~= tidyFloorGetter then return callback(...) end
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    local idle = #queue.queue == 0 and not character:hasTimedActions()
    local add, buffered = ISTimedActionQueue.add, {}
    ISTimedActionQueue.add = function(action) buffered[#buffered + 1] = action; return queue end
    local results = pack(pcall(callback, ...))
    ISTimedActionQueue.add = add
    if not results[1] then
        for _, action in ipairs(buffered) do add(action) end
        error(results[2], 0)
    end
    if #buffered == 0 then return unpack(results, 2, results.n) end
    if not tidyActionUnchanged() then
        for _, action in ipairs(buffered) do add(action) end
        return unpack(results, 2, results.n)
    end
    local controller = Toolkit.ActionQueue
    if controller then controller.updateOperationState(queue) end
    local inventory = character:getInventory()
    local floor = tidyFloorGetter(character:getPlayerNum())
    local planned, transfers, incoming = {}, {}, {}
    local precedingKnown = true
    local function validTransfer(action, item)
        return action and action.character == character and getmetatable(action) == ISInventoryTransferAction
            and instanceof(action.item, "InventoryItem") and action.item:getID() == item:getID()
            and action.item:getFullType() == item:getFullType() and action.item:getContainer() == inventory
            and action.srcContainer == inventory and action.destContainer == floor
            and tidyActionUnchanged(action)
    end
    for _, action in ipairs(buffered) do
        local class, keep = getmetatable(action), true
        local known = action.character == character and tidyActionUnchanged(action)
        if known and class == ISInventoryTransferAction and instanceof(action.item, "InventoryItem")
            and action.destContainer == inventory and action.srcContainer ~= inventory then
            incoming[action.item:getID()] = action.item:getFullType()
        end
        if idle and precedingKnown and known and class == ISWearClothing and nativeClothingMethods()
            and instanceof(action.item, "InventoryItem") then
            local old = action.item
            local item = inventory:getItemById(old:getID())
            -- P4 retains its original worn object after native Host placement.
            -- Native start replaces it by ID and dereferences nil when the bag
            -- stayed on the ground or another player took it. Leave fresh exact
            -- replicas to that native resolver, and unknown/incoming work alone.
            if incoming[old:getID()] ~= old:getFullType() and (not instanceof(item, "InventoryItem")
                or item:getID() ~= old:getID() or item:getFullType() ~= old:getFullType()) then keep = false end
        elseif action.character == character and class == P4RestoreFloorAction and tidyActionUnchanged(action) then
            local old = action.item
            local item = instanceof(old, "InventoryItem") and inventory:getItemById(old:getID())
            if item and old ~= item and item:getID() == old:getID() and item:getFullType() == old:getFullType()
                and old:getContainer() == floor and item:getContainer() == inventory then
                local here = character:getCurrentSquare()
                local target = getCell():getGridSquare(action.x, action.y, action.z)
                if here and target and here:getZ() == action.z and math.abs(here:getX() - action.x) <= 2
                    and math.abs(here:getY() - action.y) <= 2 then
                    local transfer = transfers[item:getID()]
                    if not transfer then
                        transfer = ISInventoryTransferAction:new(character, item, inventory, floor)
                        if validTransfer(transfer, item) then planned[#planned + 1] = transfer else transfer = nil end
                    end
                    if validTransfer(transfer, item) then
                        transfers[item:getID()], action.item = transfer, item
                        local repair = {character = character, queue = queue, generation = queue.toolkitOperationGeneration or 0,
                            worldGeneration = worldGeneration, id = item:getID(), fullType = item:getFullType(),
                            lootGetter = getPlayerLoot, fields = {}}
                        for _, name in ipairs({"x", "y", "z", "offX", "offY", "offZ", "rotationX", "rotationY", "rotationZ", "debugOutput"}) do
                            repair.fields[name] = action[name]
                        end
                        repairedFloors[action] = repair
                    end
                end
            end
        elseif action.character == character and getmetatable(action) == ISInventoryTransferAction
            and instanceof(action.item, "InventoryItem") and action.srcContainer == inventory and action.destContainer == floor then
            transfers[action.item:getID()] = action
        end
        if keep then planned[#planned + 1] = action end
        precedingKnown = precedingKnown and known
    end
    for _, action in ipairs(planned) do add(action) end
    return unpack(results, 2, results.n)
end

local function installTidyFloorValidation()
    local page, class = ISInventoryPage, P4RestoreFloorAction
    local getter = page and page.GetFloorContainer
    if not Proof.closure(getter, "ISInventoryPage.lua") then return end
    local valid = class.isValid
    class.isValid = function(action, ...)
        local repair = repairedFloors[action]
        if not repair then return valid(action, ...) end
        local character, queue = repair.character, repair.queue
        if not isClient() or not character:isLocalPlayer() or character:isDead()
            or repair.worldGeneration ~= worldGeneration or action.character ~= character
            or ISTimedActionQueue.queues[character] ~= queue or queue.current ~= action or queue:indexOf(action) == -1
            or (queue.toolkitOperationGeneration or 0) ~= repair.generation
            or ISInventoryPage ~= page or page.GetFloorContainer ~= getter
            or getPlayerLoot ~= repair.lootGetter or not tidyActionUnchanged or not tidyActionUnchanged(action, true)
            or not instanceof(action.item, "InventoryItem") or action.item:getID() ~= repair.id
            or action.item:getFullType() ~= repair.fullType then return false end
        local record = records[action]
        if record and record.token.toolkitCancelled and not Settlement.required(record.obligation) then return false end
        for _, name in ipairs({"x", "y", "z", "offX", "offY", "offZ", "rotationX", "rotationY", "rotationZ", "debugOutput"}) do
            if action[name] ~= repair.fields[name] then return false end
        end
        if not valid(action, ...) then return false end
        local floor = getter(character:getPlayerNum())
        local function resolved()
            local item = floor:getItemById(repair.id)
            if not instanceof(item, "InventoryItem") or item:getFullType() ~= repair.fullType
                or item:getID() ~= repair.id or item:getContainer() ~= floor then return end
            local world = item:getWorldItem()
            local square, here = world and world:getSquare(), character:getCurrentSquare()
            if not square or not here or world:getItem() ~= item or square:getZ() ~= here:getZ()
                or math.abs(square:getX() - here:getX()) > 2 or math.abs(square:getY() - here:getY()) > 2 then return end
            return item
        end
        local item = resolved()
        if not item then
            local loot = repair.lootGetter(character:getPlayerNum())
            local refresh = page.refreshBackpacks
            if not loot or loot.player ~= character:getPlayerNum() or loot.onCharacter ~= false
                or type(refresh) ~= "function" or loot.refreshBackpacks ~= refresh then return false end
            -- The normal UI refresh associates the received world replica with the native floor cache.
            refresh(loot)
            item = resolved()
        end
        if not item then return false end
        action.item = item
        return true
    end
    tidyFloorValid = class.isValid
end

local function loadSource(id, module, eventName)
    local event = eventName and Events[eventName]
    local deriveOwner = ISBaseTimedAction
    local eventAdd, derive = event and event.Add, deriveOwner.derive
    local ownDerive = Proof.own(deriveOwner, "derive")
    local privateWait, sequenceWait
    deriveOwner.derive = function(class, name)
        local result = derive(class, name)
        if id == "WashFix" and name == "WMI_WaitForInvUpdate" then privateWait = result end
        if id == "Project_Cook" and name == "PJCK_SequenceWaitAction" then sequenceWait = result end
        return result
    end
    if event then
        event.Add = function(callback)
            if id == "P4TidyUpMeister" then
                local native = callback
                callback = function(character, ...) return repairTidyFloor(character, native, character, ...) end
            end
            eventAdd(function(...)
                if id == "P4TidyUpMeister" then
                    local character = select(1, ...)
                    local record = sessions[character]
                    if record then
                        if not Toolkit.Settings.actionQueue() then
                            Settlement.close(record)
                            sessions[character] = nil
                            return TidyIntent.update(character, callback, ...)
                        end
                        Settlement.poll(record)
                        -- Shared cleanup keeps a separate owner; unique returns may resolve back to their source task.
                        local context = Settlement.context(record)
                        context.id, context.tidySession = id, record
                        local results = pack(scoped(context, function(...) return TidyIntent.update(character, callback, ...) end, ...))
                        if #record.queue.queue == 0 and not character:hasTimedActions() then
                            record.idleTicks = (record.idleTicks or 0) + 1
                        else record.idleTicks = 0 end
                        if record.restored or record.idleTicks >= 2 then sessions[character] = nil end
                        return unpack(results, 1, results.n)
                    end
                    return TidyIntent.update(character, callback, ...)
                end
                return scoped({id = id}, callback, ...)
            end)
        end
    end
    local results = pack(pcall(require, module))
    deriveOwner.derive = ownDerive
    if event then event.Add = eventAdd end
    if not results[1] then return false end
    if privateWait then
        -- B42.21 Base has neither a setter nor dispatch for this mod's private retry callback.
        privateWait.setOnComplete = ISInventoryTransferAction.setOnComplete
        local perform = privateWait.perform
        privateWait.perform = function(action)
            if action.onCompleteFunc then action.onCompleteFunc(unpack(action.onCompleteArgs)) end
            perform(action)
        end
        classes[id][privateWait] = snapshot(privateWait)
    end
    if sequenceWait then classes[id][sequenceWait] = snapshot(sequenceWait) end
    return true
end

local function normalizeCookBase(panel, invalidate)
    if not ownerUnchanged("Project_Cook") or not instanceUnchanged(panel, PJCK_EvoPanel)
        or not panel.player or panel.player:isDead() then return end
    local selected = panel.baseItem
    if not instanceof(selected, "InventoryItem") then panel._toolkitCookRootCache = nil; return end
    local root = panel.player:getInventory()
    local item = root:getItemById(selected:getID())
    -- Root arrival keeps the object in SP but can replace a floor proxy in Host.
    -- Resolve only the exact selected ID/type in the actor's actual root; keep the source's
    -- recipe, return target and replacement bookkeeping.
    if instanceof(item, "InventoryItem") and item:getID() == selected:getID()
        and item:getFullType() == selected:getFullType()
        and item:getContainer() == root and root:contains(item) then
        local previous = panel._toolkitCookRootCache
        if item ~= selected or type(previous) ~= "table" or getmetatable(previous) ~= nil
            or previous.item ~= item or previous.root ~= root then
            panel.baseItem = item
            panel._toolkitCookRootCache = {item = item, root = root}
            invalidate(panel)
        end
    else
        panel._toolkitCookRootCache = nil
    end
end

local function installCookFirstAddition()
    if not ready.Project_Cook or not verified("Project_Cook", projectCookFirstAdditionSources)
        or not pcall(require, "Project_Cook/EvolvedRecipePanel/PJCK_InputPanel")
        or not pcall(require, "Project_Cook/EvolvedRecipePanel/PJCK_CookingInfo") then return end
    local input, info, evo = PJCK_InputPanel, PJCK_CookingInfo, PJCK_EvoPanel
    if type(input) ~= "table" or type(info) ~= "table" or type(evo) ~= "table" then return end
    -- Fingerprints prove the selected files; loaded closures must still belong to those files.
    for _, source in ipairs({{input, "PJCK_InputPanel.lua"}, {info, "PJCK_CookingInfo.lua"}}) do
        for name, callback in pairs(source[1]) do
            if type(callback) == "function" and name ~= "derive" and not Proof.closure(callback, source[2]) then return end
        end
    end
    local original, transition = input.canAddItem, info.isAddOneFirst
    if not Proof.closure(original, "PJCK_InputPanel.lua") or not Proof.closure(transition, "PJCK_CookingInfo.lua")
        or not Proof.closure(info.updateContentType, "PJCK_CookingInfo.lua")
        or not Proof.closure(info.isNeedWater, "PJCK_CookingInfo.lua") then return end
    local inputMethods, infoMethods
    local function unchanged(class, methods)
        if not classUnchanged(class, methods) then return false end
        for name, callback in pairs(class) do
            if type(callback) == "function" and methods[name] ~= callback then return false end
        end
        return true
    end
    input.canAddItem = function(self, item, ...)
        local panel = self and self.EvoPanel
        local cookingInfo = panel and panel.cookingInfoPanel
        if PJCK_InputPanel ~= input or PJCK_CookingInfo ~= info or PJCK_EvoPanel ~= evo
            or not ownerUnchanged("Project_Cook") or not unchanged(input, inputMethods) or not unchanged(info, infoMethods)
            or not instanceUnchanged(self, input) or not instanceUnchanged(panel, evo)
            or not instanceUnchanged(cookingInfo, info) or cookingInfo.EvoPanel ~= panel
            or not panel.player or panel.player:isDead()
            or not ((self.panelType == "Ingredient" and panel.ingredientsPanel == self)
                or (self.panelType == "Seasoning" and panel.seasoningsPanel == self)) then return original(self, item, ...) end
        local recipe, baseItem = panel:getRecipe(), panel:getBaseItem()
        if not recipe or not baseItem or cookingInfo:isNeedWater(baseItem, recipe)
            or not transition(cookingInfo, baseItem, recipe) then return original(self, item, ...) end
        -- Keep the reviewed source's native availability and portion/group checks.
        if not panel:isUsableForRecipe(item, recipe, self.panelType)
            or panel:getGroupUseCapacity(item, self.panelType) <= panel:getSelectedGroupCount(item) then return false end
        -- A new recipe can inherit contained labels from its base (for example, sliced bread).
        -- Only NEW pending additions occupy the single request allowed before the native result exists.
        return #panel:getPreCookItems("Ingredient") + #panel:getPreCookItems("Seasoning") < 1
    end
    inputMethods, infoMethods = snapshot(input), snapshot(info)
    ready.Project_Cook_FirstAddition = true
end

local names = {"ISInventoryTransferAction", "ISWalkToTimedAction", "ISWalkToTimedActionF", "ISPathFindAction",
    "ISWashClothing", "ISEquipWeaponAction", "ISUnequipAction", "ISWearClothing", "ISClothingExtraAction",
    "ISAttachItemHotbar", "ISDetachItemHotbar", "ISQueueActionsAction", "NEQ_AttachAction", "P4RestoreAction", "P4RestoreFloorAction", "ISAddItemInRecipe"}

local function transferMethods()
    local result = {}
    for _, name in ipairs({"new", "isValid", "start", "perform", "stop", "transferItem"}) do result[name] = ISInventoryTransferAction[name] end
    return result
end

local function installContainerTransfers()
    if not getActivatedMods or not getActivatedMods():contains("EURY_CONTAINERS") then return end
    transferSourceSafe = false
    if not verified("EURY_CONTAINERS") then return end
    local ok, proximity = pcall(require, "BetterContainers/Proximity")
    if not ok or type(proximity) ~= "table" then return end
    local loaded, helpers = pcall(require, "BetterContainers/Helpers")
    if not loaded or type(helpers) ~= "table" or helpers ~= EURY_CONTAINERS
        or type(helpers.isStaleVehicleContainer) ~= "function" then return end
    local staleVehicle = helpers.isStaleVehicleContainer
    local proximityMethods = {invName = proximity.invName, invName_corpses = proximity.invName_corpses}
    for _, name in ipairs({"isLockedForPlayer", "setTransferRunning", "hasQueuedTransferAction", "isProximityType"}) do
        if type(proximity[name]) ~= "function" then return end
        proximityMethods[name] = proximity[name]
    end
    containerHelpersUnchanged = function()
        if EURY_CONTAINERS ~= helpers or helpers.isStaleVehicleContainer ~= staleVehicle then return false end
        for name, expected in pairs(proximityMethods) do if proximity[name] ~= expected then return false end end
        return true
    end
    local policy = Toolkit.ActionQueuePolicy
    if not policy or not policy.adoptTransferMethods then return end
    local delegates={}
    for _, module in ipairs({"BetterContainers/Proximity/Proximity_ISInventoryTransferAction", "BetterContainers/Nested"}) do
        local loaded, patch = pcall(require, module)
        if not loaded or type(patch) ~= "table" or patch._installed ~= false or type(patch.install) ~= "function" then return end
        local previous = transferMethods()
        if not pcall(patch.install) then return end
        local replacement = transferMethods()
        if not policy.adoptTransferMethods(previous, replacement, containerHelpersUnchanged) then return end
        delegates[#delegates+1]={previous=previous,replacement=replacement}
        if Operations.adoptReturnMethods then Operations.adoptReturnMethods(previous, replacement, containerHelpersUnchanged) end
    end
    reviewedTransferPerform, transferPerformGuard = ISInventoryTransferAction.perform, containerHelpersUnchanged
    local leaseMethods={}
    for name,value in pairs(proximityMethods) do leaseMethods[name]=value end
    leaseMethods._TransferRunning,leaseMethods._BrowseElapsedMs=proximity._TransferRunning,proximity._BrowseElapsedMs
    transferBindingRecords[containerHelpersUnchanged]={kind="bc",id="EURY_CONTAINERS",helpers=helpers,proximity=proximity,
        helperMethods={isStaleVehicleContainer=staleVehicle},proximityMethods=leaseMethods,delegates=delegates,
        running=proximity._TransferRunning,browsing=proximity._BrowseElapsedMs}
    bindingState.revision=bindingState.revision+1
    transferSourceSafe, ready.EURY_CONTAINERS = true, true
end

-- Preserve the selected mod's native delegate order: BC, then the fridge
-- observer, then delayed cart hooks. Loading it after snapshots loses provenance.
local function installFridgeTransfers()
    if not getActivatedMods or not getActivatedMods():contains("NicksTurnOffFridges")
        or not verified("NicksTurnOffFridges") then return end
    local policy = Toolkit.ActionQueuePolicy
    if not policy or type(policy.adoptTransferHooks) ~= "function" then return end
    local previous, priorGuard = transferMethods(), transferPerformGuard
    if not Proof.closure(previous.perform, "ISInventoryTransferAction.lua")
        and not Compat.isTransferPerform(previous.perform) then return end
    if not pcall(require, "TurnOffFridges/TOF_Client") or not pcall(require, "TurnOffFridges/TOF_Light") then return end
    local owner, functions = TurnOffFridges, {}
    if type(owner) ~= "table" or getmetatable(owner) ~= nil then return end
    for name, callback in pairs(owner) do
        if type(callback) == "function" then
            local origin = name == "clearFridgeProperty" and "TOF_TileProps.lua"
                or name == "autoTick" and "TOF_Client.lua"
                or (name == "applyLight" or name == "lightReport") and "TOF_Light.lua" or "TOF_Core.lua"
            if not Proof.closure(callback, origin) then return end
            functions[name] = callback
        end
    end
    for _, name in ipairs({"clearFridgeProperty", "autoTick", "isFridgeObject", "isAuto", "isUnitEmpty", "isUnplugged", "requestAutoEval", "applyLight"}) do
        if type(functions[name]) ~= "function" then return end
    end
    local module, autoKey, constants = owner.MODULE, owner.AUTO_KEY, {}
    if module ~= "TurnOffFridges" or autoKey ~= "TOF_auto" then return end
    local expected = {ON = {fridgeoff = "fridge", freezeroff = "freezer"}, OFF = {fridge = "fridgeoff", freezer = "freezeroff"}}
    for _, name in ipairs({"ON", "OFF"}) do
        local map = owner[name]
        if type(map) ~= "table" or getmetatable(map) ~= nil then return end
        local values = expected[name]
        for key, value in pairs(values) do if map[key] ~= value then return end end
        for key, value in pairs(map) do if values[key] ~= value then return end end
        constants[name] = {map = map, values = values}
    end
    local function helpersUnchanged()
        if TurnOffFridges ~= owner or getmetatable(owner) ~= nil or owner.MODULE ~= module or owner.AUTO_KEY ~= autoKey
            or priorGuard and not priorGuard() then return false end
        for name, callback in pairs(functions) do if owner[name] ~= callback then return false end end
        for name, captured in pairs(constants) do
            local map = captured.map
            if owner[name] ~= map or getmetatable(map) ~= nil then return false end
            for key, value in pairs(captured.values) do if map[key] ~= value then return false end end
            for key, value in pairs(map) do if captured.values[key] ~= value then return false end end
        end
        return true
    end
    local replacement = transferMethods()
    if not Proof.closure(replacement.perform, "TOF_Client.lua")
        or replacement.new ~= previous.new or replacement.transferItem ~= previous.transferItem
        or not policy.adoptTransferHooks(previous, replacement, helpersUnchanged)
        or not Operations.adoptReturnHooks(previous, replacement, helpersUnchanged) then return end
    reviewedTransferPerform, transferPerformGuard = replacement.perform, helpersUnchanged
    transferBindingRecords[helpersUnchanged]={kind="tof",id="NicksTurnOffFridges",owner=owner,priorGuard=priorGuard,
        ownerMethods={isFridgeObject=functions.isFridgeObject,ON=constants.ON.map,OFF=constants.OFF.map},
        on=constants.ON,off=constants.OFF,previous=previous,replacement=replacement}
    bindingState.revision=bindingState.revision+1
    ready.NicksTurnOffFridges = true
end

local function installCartEating()
    if not getActivatedMods or not getActivatedMods():contains("SaucedCarts") or not verified("SaucedCarts")
        or not ISEatFoodAction or not ISDrinkFluidAction
        or ISEatFoodAction._saucedCartsConsumeWrapped or ISDrinkFluidAction._saucedCartsConsumeWrapped then return end
    if SaucedCarts and SaucedCarts.ConsumeWithCart then return end
    -- The early Quartermaster entry point can arrive before queue policy.
    -- Capture native starts and install their proof owner before cart wrapping.
    require "PZSurvivorToolkit/ActionQueuePolicy"
    local policy = Toolkit.ActionQueuePolicy
    if not policy or type(policy.adoptConsumeStarts) ~= "function" then return end
    local previous = {[ISEatFoodAction] = ISEatFoodAction.start, [ISDrinkFluidAction] = ISDrinkFluidAction.start}
    local ok, consume = pcall(require, "SaucedCarts/ConsumeWithCart")
    local owner = SaucedCarts
    if not ok or not owner or type(consume) ~= "table" or owner.ConsumeWithCart ~= consume
        or type(consume.install) ~= "function" or type(consume._wrapStart) ~= "function"
        or type(owner.safeIsCart) ~= "function" or type(owner.isCart) ~= "function" or type(owner.debug) ~= "function" then return end
    local install, wrapStart, safeIsCart, isCart, debug = consume.install, consume._wrapStart, owner.safeIsCart, owner.isCart, owner.debug
    local function helpersUnchanged()
        return SaucedCarts == owner and owner.ConsumeWithCart == consume
            and consume.install == install and consume._wrapStart == wrapStart
            and owner.safeIsCart == safeIsCart and owner.isCart == isCart and owner.debug == debug
    end
    if not pcall(install) then return end
    ready.SaucedCarts = policy and policy.adoptConsumeStarts
        and policy.adoptConsumeStarts(previous, helpersUnchanged) == true
end

function Compat.install()
    if installAttempted then return end
    installAttempted = true
    installCartEating()
    installContainerTransfers()
    installFridgeTransfers()
    if getActivatedMods and getActivatedMods():contains("SaucedCarts") and verified("SaucedCarts", sourceFiles.SaucedCartsTransfers) then
        ready.SaucedCartsTransfers = require("PZSurvivorToolkit/ActionQueueCarts").install()
    end
    -- Snapshot reviewed native modifiers even when an updated cooking UI disables its own adapter.
    if getActivatedMods and getActivatedMods():contains("Project_Cook") and verified("Project_Cook", projectCookActionSources) then
        pcall(require, "Project_Cook/PJCK_FrozenCooking")
        pcall(require, "Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction")
    end
    for _, owner in ipairs({
        {"Neat_Crafting", "NC_CraftActionPanel", "Neat_Crafting/NC_CraftActionPanel"},
        {"Project_Cook", "PJCK_CraftActionPanel", "Project_Cook/HandCraftPanel/PJCK_CraftActionPanel"},
    }) do
        if not installed[owner[1]] and getActivatedMods and getActivatedMods():contains(owner[1]) then
            installed[owner[1]] = true
            if not _G[owner[2]] and verified(owner[1])
                and (owner[1] ~= "Project_Cook" or captureProjectCookConfig()) and pcall(require, owner[3]) then
                local class = _G[owner[2]]
                if class and owner[1] == "Project_Cook" then
                    local complete, methods = class.onHandcraftActionComplete
                    class.onHandcraftActionComplete = function(self, ...)
                        local quantity = self.craftTimes
                        local balance = Toolkit.Settings.actionQueue() and type(quantity) == "number" and quantity > 1
                            and classUnchanged(class, methods) and instanceUnchanged(self, class)
                        local result = complete(self, ...)
                        -- Project Cook starts every craft but only stops the last one in a batch.
                        if balance then self.logic:stopCraftAction() end
                        return result
                    end
                    methods = snapshot(class)
                end
                if class then craftOwners[owner[2]] = {class = class, methods = snapshot(class)}; ready[owner[1]] = true end
                if owner[1] == "Project_Cook" and not PJCK_EvoPanel then
                    ready.Project_Cook = false
                    classes.Project_Cook = {}
                    if pcall(require, "Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction")
                        and loadSource("Project_Cook", "Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel") then
                        ready.Project_Cook = true
                        for _, name in ipairs({"addIngredients", "returnBaseItemToOriginalContainer", "queueBaseItemReturn", "setBaseItem"}) do
                            local callback = PJCK_EvoPanel[name]
                            PJCK_EvoPanel[name] = function(self, ...)
                                if not instanceUnchanged(self, PJCK_EvoPanel) then return callback(self, ...) end
                                return Operations.run(function(...) return scoped({id = "Project_Cook", owner = self}, callback, self, ...) end, ...)
                            end
                        end
                        local refresh, resolve = PJCK_EvoPanel.setContainers, PJCK_EvoPanel.resolveCurrentBaseItem
                        local getter, inputs, invalidate = PJCK_EvoPanel.getBaseItem, PJCK_EvoPanel.getInputList, PJCK_EvoPanel.invalidateInputCaches
                        if Proof.closure(refresh, "PJCK_EvoPanel.lua") and Proof.closure(resolve, "PJCK_EvoPanel.lua")
                            and Proof.closure(getter, "PJCK_EvoPanel.lua") and Proof.closure(inputs, "PJCK_EvoPanel.lua")
                            and Proof.closure(invalidate, "PJCK_EvoPanel.lua") then
                            PJCK_EvoPanel.setContainers = function(self, ...)
                                normalizeCookBase(self, invalidate)
                                return refresh(self, ...)
                            end
                            PJCK_EvoPanel.resolveCurrentBaseItem = function(self, preferPlayerInventory, ...)
                                if preferPlayerInventory == true then normalizeCookBase(self, invalidate) end
                                return resolve(self, preferPlayerInventory, ...)
                            end
                            PJCK_EvoPanel.getBaseItem = function(self, ...)
                                normalizeCookBase(self, invalidate)
                                return getter(self, ...)
                            end
                            PJCK_EvoPanel.getInputList = function(self, ...)
                                normalizeCookBase(self, invalidate)
                                return inputs(self, ...)
                            end
                        end
                    end
                end
            end
        end
    end
    for _, id in ipairs({"WashFix", "NeatUI_Equipment", "P4TidyUpMeister"}) do
        local active = getActivatedMods and getActivatedMods():contains(id)
        if not installed[id] and active and verified(id) then
            installed[id], classes[id] = true, {}
            local ok
            if id == "WashFix" and not WS then
                ok = pcall(require, "ISUI/WMI_Compat_TABAS") and pcall(require, "TimedActions/WMI_PatchWashClothing")
                    and loadSource(id, "ISUI/WMI_CleanBandagesContext", "OnFillWorldObjectContextMenu")
                    and loadSource(id, "ISUI/WMI_WashingSubmenus", "OnFillWorldObjectContextMenu")
                if ok then washWalkHelper = {owner = luautils, callback = luautils.walkAdj} end
                if ok and WS.WMI_BuildWashMenu then
                    local callback = WS.WMI_BuildWashMenu
                    WS.WMI_BuildWashMenu = function(...) return scoped({id = id}, callback, ...) end
                end
                if ok and WMI_Clean.queueAllDirtyItems then
                    local callback = WMI_Clean.queueAllDirtyItems
                    WMI_Clean.queueAllDirtyItems = function(character, sink, ...)
                        return Operations.run(function(...)
                            return scoped({id = id, target = sink}, callback, character, sink, ...)
                        end, ...)
                    end
                end
            elseif id == "NeatUI_Equipment" and not NEQ_Dresser then
                ok = loadSource(id, "NeatEquipment/NEQ_Dresser")
                if ok then
                    for _, name in ipairs({"wear", "stripAll", "restore"}) do
                        local callback = NEQ_Dresser[name]
                        if callback then NEQ_Dresser[name] = function(...) return Operations.run(function(...) return scoped({id = id}, callback, ...) end, ...) end end
                    end
                    for _, name in ipairs({"newAttach", "newDetach"}) do
                        local callback = NEQ_AttachAction[name]
                        NEQ_AttachAction[name] = function(...)
                            return Operations.run(function(...)
                                local action = scoped({id = id}, callback, ...)
                                scoped({id = id}, adopt, action)
                                return action
                            end, ...)
                        end
                    end
                end
            elseif id == "P4TidyUpMeister" then
                local previous = ISInventoryTransferAction.getNotFullFloorSquare
                local transferItem = ISTransferAction and ISTransferAction.transferItem
                local dropItemOffset = ISTransferAction and ISTransferAction.GetDropItemOffset
                ok = loadSource(id, "P4TidyUpMeister", "OnPlayerUpdate")
                local policy = Toolkit.ActionQueuePolicy
                if ok and policy and policy.adoptTransferFloorHelper then
                    policy.adoptTransferFloorHelper(previous, ISInventoryTransferAction.getNotFullFloorSquare)
                end
                if ok and policy and policy.adoptTransferItemHelper and type(P4TidyUpMeister) == "table" then
                    local owner = P4TidyUpMeister
                    local registerAction, registerWorn = owner.registerActionPolicy, owner.registerWornItemReplacement
                    local replacementTransfer, replacementOffset = ISTransferAction.transferItem, ISTransferAction.GetDropItemOffset
                    -- The pinned source captures both delegates in its private local table.
                    local sourceGuard=function()
                        return P4TidyUpMeister == owner and type(registerAction) == "function" and type(registerWorn) == "function"
                            and owner.registerActionPolicy == registerAction and owner.registerWornItemReplacement == registerWorn
                            and ISTransferAction.transferItem == replacementTransfer
                            and ISTransferAction.GetDropItemOffset == replacementOffset
                    end
                    if policy.adoptTransferItemHelper(transferItem, replacementTransfer, sourceGuard, dropItemOffset, replacementOffset) then
                        transferBindingRecords[sourceGuard]={kind="p4",id="P4TidyUpMeister",owner=owner,
                            ownerMethods={registerActionPolicy=registerAction,registerWornItemReplacement=registerWorn},
                            transferDelegate=transferItem,offsetDelegate=dropItemOffset,
                            transferWrapper=replacementTransfer,offsetWrapper=replacementOffset}
                        bindingState.revision=bindingState.revision+1
                    end
                end
            end
            ready[id] = ok == true
            if not ok then classes[id] = {} end
        end
    end
    if transferSourceSafe then
        local previous=ISInventoryTransferAction.checkQueueList
        local function pickupScope(action)
            return action and (Settlement.admittedPickupScope(action) or sessions[action.character])
        end
        local function pickupGuard(action)
            return getmetatable(action) == ISInventoryTransferAction and tidyActionUnchanged and tidyActionUnchanged(action)
                and Toolkit.ActionQueuePolicy.isOrdinaryTransfer(action)
        end
        local onMerged=function(action)
            local session = pickupScope(action)
            if session then
                Settlement.refreshPickup(session, action)
                if pickupGuard(action) then Settlement.departure(session, action) end
            end
            local record = records[action]
            if record and record.mergeCandidates then
                local queue = ISTimedActionQueue.queues[action.character]
                for _,candidate in ipairs(record.mergeCandidates) do
                    local wiped = true
                    for _ in pairs(candidate.action) do wiped = false; break end
                    if wiped and queue and queue:indexOf(candidate.action) == -1 then
                        for _,group in ipairs(action.queueList or {}) do
                            for _,item in ipairs(group.items or {}) do
                                if instanceof(item, "InventoryItem") and item:getID() == candidate.id
                                    and item:getFullType() == candidate.fullType then
                                    record.mixedTransferOwners = true
                                end
                            end
                        end
                    end
                end
                record.mergeCandidates = nil
            end
            if record and record.id == "P4TidyUpMeister" and record.obligation then
                Settlement.refreshReturn(action, record.obligation)
            end
        end
        local canObserve=function(action)
            local record = records[action]
            local session = pickupScope(action)
            return record and record.class == ISInventoryTransferAction and matches(action, record)
                or session and Settlement.pickupMatches(session, action)
        end
        local events={
            merging = function(action)
                local record = records[action]
                local queue = ISTimedActionQueue.queues[action.character]
                if record and record.class == ISInventoryTransferAction and not Toolkit.Settings.actionQueue()
                    and matches(action, record) and queue then
                    local candidates = {}
                    -- Capture identity and token before native checkQueueList wipes
                    -- accepted children. Rejected or merely removed rows grant no proof.
                    local first = queue:indexOf(action)
                    for index = first > 0 and first + 1 or 1, first > 0 and #queue.queue or 0 do
                        local child = queue.queue[index]
                        if child.Type ~= action.Type or child.srcContainer ~= action.srcContainer
                            or child.destContainer ~= action.destContainer or child.onCompleteFunc or action.onCompleteFunc
                            or child.allowMissingItems ~= action.allowMissingItems then break end
                        if child.toolkitQueueOperation ~= record.token and instanceof(child.item, "InventoryItem") then
                            candidates[#candidates + 1] = {action = child, id = child.item:getID(),
                                fullType = child.item:getFullType()}
                        end
                    end
                    record.mergeCandidates = candidates
                end
                local session = pickupScope(action)
                return session and pickupGuard(action) and Settlement.beforePickupMerge(session, action, pickupGuard)
            end,
            begin = function(action)
                local session = pickupScope(action)
                if session and pickupGuard(action) then
                    Settlement.departure(session, action)
                    return Settlement.beginPickup(session, action, pickupGuard)
                end
                return false
            end,
            finish = function(action, succeeded)
                local session = pickupScope(action)
                return session and Settlement.finishPickup(session, action, succeeded) or false
            end,
        }
        transferListenerRecord={callback=onMerged,canObserve=canObserve,events=events,dependencies=bindingDependencies()}
        bindingState.revision=bindingState.revision+1
        Transfers.observeTransfers(onMerged,canObserve,events,transferListenerFactory)
        local policy=Toolkit.ActionQueuePolicy
        if policy and policy.adoptTransferQueueObserver then policy.adoptTransferQueueObserver(previous,ISInventoryTransferAction.checkQueueList) end
        Settlement.observePlannedReturns()
    end
    if ready.P4TidyUpMeister then installTidyFloorValidation() end
    if ready.WashFix and WashWaterRule and WashWaterRule.install() and washWaterMatches
        and washWaterMatches(ISWashClothing.complete) then washWaterComplete = ISWashClothing.complete end
    for id, sourceClasses in pairs(classes) do
        if ready[id] then
            for _, name in ipairs(names) do
                local class = _G[name]
                if class and (class ~= ISInventoryTransferAction or transferSourceSafe) then sourceClasses[class] = snapshot(class) end
            end
        end
        owners[id] = {}
        for _, target in ipairs(id == "WashFix" and {WS, WMI_Clean} or id == "NeatUI_Equipment" and {NEQ_Dresser, NEQ_AttachAction}
            or id == "Project_Cook" and {PJCK_EvoPanel, PJCK_FrozenCooking, PJCK_EvolvedSpiceGuard} or {}) do
            if target then owners[id][#owners[id] + 1] = {target = target, methods = snapshot(target)} end
        end
    end
    installCookFirstAddition()
    local carts=ready.SaucedCartsTransfers and Toolkit.ActionQueueCarts
    local transfer=carts and carts.isTransferConstructor
    -- These late bindings are already verified by the Carts adapter. Share only
    -- that exact native-transfer proof; every other class/helper/callback stays pinned.
    reviewedTransferClassUnchanged = function(target, class, methods)
        if class~=ISInventoryTransferAction or not carts or Toolkit.ActionQueueCarts~=carts
            or carts.isTransferConstructor~=transfer or not transfer(methods.new) or not transfer(class.new) then return false end
        local allowed={new=true,perform=true,transferItem=true}
        for name in pairs(allowed)do if target[name]~=class[name]then return false end end
        for name,method in pairs(methods)do if not allowed[name]and target[name]~=method then return false end end
        for _,name in ipairs(lifecycle)do if not allowed[name]and target[name]~=methods[name]then return false end end
        return true
    end
    if ready.P4TidyUpMeister then
        local owner=P4TidyUpMeister
        local actionPolicy,wornPolicy=owner.registerActionPolicy,owner.registerWornItemReplacement
        local unequip=carts and carts.isUnequipConstructor
        local nonCart=carts and carts.isNonCartUnequip
        local nonCartItem=carts and carts.isNonCartItem
        tidyUnequipVariant = function(action)
            if not carts or Toolkit.ActionQueueCarts ~= carts or carts.isUnequipConstructor ~= unequip
                or carts.isNonCartUnequip ~= nonCart or carts.isNonCartItem ~= nonCartItem
                or type(nonCartItem) ~= "function" or not unequip(ISUnequipAction.new) then return false end
            local record = records[action]
            -- Before adoption use the full native instance matcher. Afterwards
            -- Compat owns perform/stop wrappers; sourceMatches validates those
            -- exact saved methods while the Carts guard still proves the class.
            return record and (record.tidyClothingUnequip or record.tidyHotbarUnequip) and nonCartItem(action.item) or nonCart(action)
        end
        tidyClassUnchanged = function(target,class,methods)
            if classUnchanged(target,methods) then return true end
            if not carts or Toolkit.ActionQueueCarts~=carts or carts.isTransferConstructor~=transfer
                or carts.isUnequipConstructor~=unequip or carts.isNonCartUnequip~=nonCart then return false end
            local allowed
            if class==ISInventoryTransferAction then
                return reviewedTransferClassUnchanged(target,class,methods)
            elseif class==ISUnequipAction and unequip(methods.new) and unequip(class.new) then
                if target~=class and not nonCart(target) then return false end
                allowed={new=true,complete=true}
            else return false end
            for name in pairs(allowed) do if target[name]~=class[name] then return false end end
            -- Reuse the existing source-pinned late Cart hooks without accepting other method changes.
            for name,method in pairs(methods) do if not allowed[name] and target[name]~=method then return false end end
            for _,name in ipairs(lifecycle) do if not allowed[name] and target[name]~=methods[name] then return false end end
            return true
        end
        local retention=Toolkit.ItemRetention
        local retentionWrapper
        local floorPage = ISInventoryPage
        local floorGetter = floorPage and floorPage.GetFloorContainer
        if Proof.closure(floorGetter, "ISInventoryPage.lua") then tidyFloorPage, tidyFloorGetter = floorPage, floorGetter end
        tidyActionUnchanged = function(action, sourceOnly)
            if P4TidyUpMeister~=owner or owner.registerActionPolicy~=actionPolicy or owner.registerWornItemReplacement~=wornPolicy then return false,'owner_changed' end
            for class,methods in pairs(classes.P4TidyUpMeister) do
                if not tidyClassUnchanged(class,class,methods) then
                    for name,method in pairs(methods) do
                        if class[name]~=method then return false,'class_changed',tostring(class.Type)..'.'..tostring(name) end
                    end
                    return false,'class_changed',class.Type
                end
            end
            if not action then return true end
            local baseline=classes.P4TidyUpMeister[getmetatable(action)]
            if not baseline then return false end
            local record=records[action]
            if not record and ownedNativeBulkTransfer(action)then return true end
            if not record and (action.onStartFunc or action.onCompleteFunc or action.onCancelFunc
                or action.retriggerLastAction or action.onFailFunc or action.additionalTest) then return false end
            return record and (sourceOnly and sourceMatches(action,record) or not sourceOnly and matches(action,record))
                or not record and tidyClassUnchanged(action,getmetatable(action),baseline)
        end
        local wrapper=function(menu,name)
            local live=Toolkit.ItemRetention
            if retention and live~=retention then return false end
            local checker=live and live.isContextWrapper
            -- Compat can install before the inventory UI publishes its hooks.
            -- Seal only the owned checker, then reject owner/predicate changes.
            if not retentionWrapper then
                if type(checker)~='function' or not Proof.closure(checker,'ItemRetentionUI.lua') then return false end
                retention,retentionWrapper=live,checker
            end
            return live==retention and checker==retentionWrapper and retentionWrapper(menu,name)
        end
        tidyBindingRecord={valid=tidyActionUnchanged,wrapper=wrapper,dependencies=bindingDependencies(),owner=owner,
            ownerMethods={registerActionPolicy=actionPolicy,registerWornItemReplacement=wornPolicy}}
        bindingState.revision=bindingState.revision+1
        TidyIntent.install(tidyActionUnchanged,wrapper,tidyBindingFactory)
    end
end

-- Early compatibility entrypoints can precede ActionQueue's shared native stop wrapper.
function Compat.adoptStop(previous,replacement)
    if ISBaseTimedAction.stop~=replacement then return false end
    for _,registry in pairs(classes) do
        for _,methods in pairs(registry) do if methods.stop==previous then methods.stop=replacement end end
    end
    return true
end

-- Server Lua is not resolvable during the client load pass; the early SP server bridge calls this.
function Compat.installReadFix()
    if readFixAttempted then return end
    readFixAttempted = true
    if getActivatedMods and getActivatedMods():contains("MPFastForward") and verified("MPFastForward") then
        local previous = ISReadABook and ISReadABook.animEvent
        if previous and pcall(require, "MPFastForward_ReadFix") and ISReadABook.animEvent ~= previous then
            local policy = Toolkit.ActionQueuePolicy
            ready.MPFastForward = policy and policy.adoptReadAnimEvent and policy.adoptReadAnimEvent(previous, ISReadABook.animEvent) == true
        end
    end
end

function Compat.isInstalled(id) return ready[id] == true end

function Compat.isCartMaskSource()
    return verified("SaucedCarts", {{"shared/SaucedCarts/ContainerRestrictions.lua", 2765771727},
        {"shared/SaucedCarts/Core.lua", 2570266575}})
end

function Compat.isCartCapacitySource()
    return verified("SaucedCarts", {{"shared/SaucedCarts/CapacityOverride.lua", 1655578365},
        {"shared/SaucedCarts/CartData.lua", 3388888445}, {"shared/SaucedCarts/Core.lua", 2570266575}})
end

function Compat.isTransferPerform(callback)
    return type(callback) == "function" and callback == reviewedTransferPerform
        and type(transferPerformGuard) == "function" and transferPerformGuard()
end

function Compat.isCraftOwner(name, target, action)
    local owner = craftOwners[name]
    if not owner or not target then return false end
    for method, callback in pairs(owner.methods) do if target[method] ~= callback then return false end end
    for method, callback in pairs(target) do
        if type(callback) == "function" and callback ~= owner.methods[method]
            and callback ~= nativeXuiMethods[method] then return false end
    end
    return owner and getmetatable(target) == owner.class and classUnchanged(owner.class, owner.methods)
        and action.onStartFunc == owner.methods.onHandcraftActionStart
        and action.onCompleteFunc == owner.methods.onHandcraftActionComplete
        and action.onCancelFunc == owner.methods.onHandcraftActionCancelled
        and target.onHandcraftActionStart == owner.methods.onHandcraftActionStart
        and target.onHandcraftActionComplete == owner.methods.onHandcraftActionComplete
        and target.onHandcraftActionCancelled == owner.methods.onHandcraftActionCancelled
end

rememberTidy = function(action)
    if installed.P4TidyUpMeister and action.character and action.toolkitQueueOperation then
        local character, token = action.character, action.toolkitQueueOperation
        if not Toolkit.Settings.actionQueue() then
            -- A new native operation while disabled has no single owner with an older tracked Tidy session.
            if sessions[character] and sessions[character].token ~= token then
                Settlement.close(sessions[character]); sessions[character] = nil
            end
            return
        end
        if sourceScope and sourceScope.id == "P4TidyUpMeister" then
            if sessions[character] then sessions[character].restored = true end
        else
            local record = sessions[character]
            if not record then
                record = Settlement.deferred(character, token)
                sessions[character] = record
            end
            if record.seen[action] then return end
            local contract = Toolkit.ActionQueueDefinitions.inspect(action)
            Settlement.remember(record, action, contract)
            local policy = Toolkit.ActionQueuePolicy
            if getmetatable(action) == ISInventoryTransferAction and tidyActionUnchanged and tidyActionUnchanged(action)
                and policy and policy.isOrdinaryTransfer and policy.isOrdinaryTransfer(action) then
                Settlement.preparePickup(record, action)
            end
        end
    end
end

local add = ISTimedActionQueue.add
ISTimedActionQueue.add = function(action)
    local results = pack(add(action))
    if results[1] then rememberTidy(action) end
    return unpack(results, 1, results.n)
end
local addAfter = ISTimedActionQueue.addAfter
ISTimedActionQueue.addAfter = function(previous, action)
    local results = pack(addAfter(previous, action))
    if results[2] then rememberTidy(results[2]) end
    return unpack(results, 1, results.n)
end
local addToQueue = ISTimedActionQueue.addToQueue
ISTimedActionQueue.addToQueue = function(queue, action)
    local results = pack(addToQueue(queue, action))
    if queue:indexOf(action) ~= -1 then rememberTidy(action) end
    return unpack(results, 1, results.n)
end

local behaviorTypes = {"WMI_WaitForInvUpdate", "PJCK_SequenceWaitAction"}
for _, name in ipairs(names) do behaviorTypes[#behaviorTypes + 1] = name end
local function tidyTransfer(action)
    local record = records[action]
    return record and record.id == "P4TidyUpMeister" and record.class == ISInventoryTransferAction
end
local function matchesTidyTransfer(action) return tidyTransfer(action) and matches(action) end
local function tidyEquipment(action)
    local record = records[action]
    return record and record.id == "P4TidyUpMeister"
        and (record.class == ISEquipWeaponAction or record.class == P4RestoreAction or record.tidyHandUnequip or record.tidyClothingWear or record.tidyClothingUnequip or record.tidyHotbarUnequip)
end
local function matchesTidyEquipment(action) return tidyEquipment(action) and matches(action) end
local function washClothing(action)
    local record = records[action]
    return record and record.id == "WashFix" and record.washOrigin
        and record.washOrigin.capability == washClothingCapability
end
local function matchesWashClothing(action) return washClothing(action) and matches(action) end
local function matchesSelectedChain(action)
    return not tidyTransfer(action) and not tidyEquipment(action) and not washClothing(action) and matches(action)
end
local function acceptsChild(parent, child)
    return matches(child) and child.toolkitQueueOperation == parent.toolkitQueueOperation
end
Toolkit.ActionQueueDefinitions.registerBehavior("compat.selected-chains",
    {types = behaviorTypes, matches = matchesSelectedChain, inspect = inspect})
Operations.registerProducer("compat.selected-chains", matchesSelectedChain, acceptsChild)
Toolkit.ActionQueueDefinitions.registerBehavior("compat.wash-clothing",
    {types = {"ISInventoryTransferAction", "ISWashClothing", "WMI_WaitForInvUpdate"}, matches = matchesWashClothing, inspect = inspect})
Operations.registerProducer("compat.wash-clothing", matchesWashClothing, function(parent, child)
    return matchesWashClothing(parent) and matchesWashClothing(child)
        and records[parent].washOrigin == records[child].washOrigin and acceptsChild(parent, child)
end, true)
Toolkit.ActionQueueDefinitions.registerBehavior("compat.tidy-transfers",
    {types = {"ISInventoryTransferAction"}, matches = matchesTidyTransfer, inspect = inspect})
Operations.registerProducer("compat.tidy-transfers", matchesTidyTransfer, acceptsChild, true)
Toolkit.ActionQueueDefinitions.registerBehavior("compat.tidy-equipment",
    {types = {"ISEquipWeaponAction", "P4RestoreAction", "ISUnequipAction", "ISWearClothing"}, matches = matchesTidyEquipment, inspect = inspect})
Operations.registerProducer("compat.tidy-equipment", matchesTidyEquipment, acceptsChild, true)
require "LootSorter_CraftMenu"
local sourceAdapters=Toolkit.ActionQueueItemEditAdapters
if sourceAdapters and type(sourceAdapters.registerSourceFactory)=="function" then
    sourceAdapters.registerSourceFactory(Compat,"transferBinding",transferBindingFactory)
    sourceAdapters.registerSourceFactory(Compat,"transferListenerBinding",transferListenerFactory)
    sourceAdapters.registerSourceFactory(Compat,"tidyBinding",tidyBindingFactory)
end
Compat.install()
return Compat
