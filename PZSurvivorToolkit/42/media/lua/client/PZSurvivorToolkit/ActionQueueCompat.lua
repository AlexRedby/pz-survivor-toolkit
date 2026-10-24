require "PZSurvivorToolkit/ActionQueueOperations"
require "PZSurvivorToolkit/ActionQueueLifecycle"
require "PZSurvivorToolkit/ActionQueueDefinitions"
require "ISUI/ISXuiSkin"

local Toolkit = PZSurvivorToolkit
local Operations = Toolkit.ActionQueueOperations
local Settlement = require "PZSurvivorToolkit/ActionQueueSettlement"
local TidyIntent = require "PZSurvivorToolkit/ActionQueueTidyIntent"
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

local function sourceClassUnchanged(id, class, methods)
    return classUnchanged(class, methods) or id == "P4TidyUpMeister" and (class == ISInventoryTransferAction or class == ISUnequipAction)
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
local function ordinaryClothingItem(item, character, allowHeadwear)
    if not instanceof(item, "Clothing") or not ItemTag or not ItemTag.REPLACE_PRIMARY or not ItemTag.WEARABLE
        or not ItemBodyLocation or not ItemBodyLocation.HAT or not ItemBodyLocation.FULL_HAT
        or item:getContainer() ~= character:getInventory()
        or (item:getCategory() ~= "Clothing" and not (item:getCategory() == "AlarmClock" and instanceof(item, "AlarmClockClothing")))
        or item:canBeEquipped() ~= nil or item:hasTag(ItemTag.WEARABLE)
        or item:hasTag(ItemTag.REPLACE_PRIMARY) or item:isBroken()
        or item:getAttachedSlot() ~= -1 or isForceDropHeavyItem(item) then return end
    local location = item:getBodyLocation()
    if not location or tostring(location) == "" then return end
    -- AlarmClockClothing is a final Clothing subtype; inventory alarm clocks
    -- share its category but not Wear's bounded single-wrist effects.
    if item:getCategory() == "AlarmClock" and (not ItemBodyLocation.LEFT_WRIST or not ItemBodyLocation.RIGHT_WRIST
        or (location ~= ItemBodyLocation.LEFT_WRIST and location ~= ItemBodyLocation.RIGHT_WRIST)) then return end
    -- Ordinary Wear retains matching hand references; Unequip releases them.
    -- Existing character-hand ownership covers preceding P4 hand restoration.
    -- Native clothing actions retain alarm state on the same watch;
    -- naturally starting/stopping its alarm does not change item ownership.
    if location == ItemBodyLocation.HAT or location == ItemBodyLocation.FULL_HAT then
        if not allowHeadwear then return end
        -- Java setWornItem also flattens Mohawk when newItem is nil. Its
        -- native appearance effect is owned separately from item/hand state.
        local visual = character:getHumanVisual()
        local hair = visual and visual:getHairModel()
        if not hair or type(hair.contains) ~= "function" then return end
    end
    return location
end
local function ordinaryClothing(action, allowHeadwear)
    local item, character = action.item, action.character
    local location = ordinaryClothingItem(item, character, allowHeadwear)
    if not location then return end
    -- Native MP start rebinds from the root by ID. A stale queued proxy must
    -- not prove a missing, replaced or differently configured live garment.
    local liveItem = character:getInventory():getItemById(item:getID())
    if not liveItem or liveItem:getFullType() ~= item:getFullType()
        or ordinaryClothingItem(liveItem, character, allowHeadwear) ~= location then return end
    return location, liveItem
end
-- Java WornItems removes exclusive slots even when setting a slot to nil.
-- Removal keeps the single-item proof. Wear may supply a bounded displaced
-- item collector; unknown/multi-item locations retain their native fallback.
local function clothingWornState(action, location, displaced)
    local character, item = action.character, action.item
    local group = character.getBodyLocationGroup and character:getBodyLocationGroup()
    if not group or not group.getLocation or not group.isMultiItem or not group.isExclusive
        or not group:getLocation(location) or group:isMultiItem(location) ~= false then return end
    local worn, exact, seen = character:getWornItems(), false, {}
    if not worn or not worn.size or not worn.get then return end
    for i = 0, worn:size() - 1 do
        local entry = worn:get(i)
        local otherLocation, other = entry:getLocation(), entry:getItem()
        if not other then return end
        if otherLocation ~= location and other:getID() == item:getID() then return end
        if otherLocation == location then
            if seen[otherLocation] then return end
            seen[otherLocation] = true
            if other:getID() == item:getID() then
                if other:getFullType() ~= item:getFullType() then return end
                exact = other
            elseif not displaced or not displaced(other, otherLocation, true, group) then return end
        else
            local exclusive = group:isExclusive(location, otherLocation)
            if exclusive ~= false then
                if exclusive ~= true or seen[otherLocation] or not displaced
                    or not displaced(other, otherLocation, false, group) then return end
                seen[otherLocation] = true
            end
        end
    end
    return true, exact
end
local function nonnegativeFinite(value)
    return type(value) == "number" and value >= 0 and value < math.huge
end
local function displacedClothing(item, character, location, group)
    return item:getCategory() == "Clothing" and not instanceof(item, "AlarmClockClothing")
        and not item:canBeActivated() and ordinaryClothingItem(item, character, true) == location
        and group:getLocation(location) and group:isMultiItem(location) == false
end
local function ordinaryClothingWear(action, saved)
    local location, liveItem = ordinaryClothing(action, true)
    if not location then return end
    local character, inventory = action.character, action.character:getInventory()
    local group = character.getBodyLocationGroup and character:getBodyLocationGroup()
    if not group or not group.getLocation or not group.isMultiItem then return end
    local proof, current, old, hasDisplaced = saved or {}, {}, nil, false
    -- Keep the original resource set through earlier cleanup and early Host
    -- completion. A newly occupying item cannot borrow an older action's proof.
    for id, entry in pairs(proof) do
        local item = inventory:getItemById(id)
        if not item or item:getFullType() ~= entry.fullType
            or not displacedClothing(item, character, entry.location, group) then return end
    end
    local function collect(item, otherLocation, sameSlot, wornGroup)
        local id = item:getID()
        if id == action.item:getID() or current[id] or inventory:getItemById(id) ~= item
            or not displacedClothing(item, character, otherLocation, wornGroup) then return false end
        local previous = proof[id]
        if saved and (not previous or previous.fullType ~= item:getFullType() or previous.location ~= otherLocation) then return false end
        proof[id] = previous or {fullType = item:getFullType(), location = otherLocation}
        current[id] = item
        hasDisplaced = true
        if sameSlot then old = item end
        return true
    end
    local safe, worn = clothingWornState(action, location, collect)
    if not safe then return end
    -- Native's same-object early return must not conceal a different worn proxy
    -- or an already inconsistent exclusive-slot combination.
    if worn and (worn ~= action.item or worn ~= liveItem or hasDisplaced) then return end
    if old then
        if not inventory.getCapacityWeight or not inventory.getEffectiveCapacity or not inventory.isItemAllowed then return end
        local weight, capacity = inventory:getCapacityWeight(), inventory:getEffectiveCapacity(character)
        if not nonnegativeFinite(weight) or not nonnegativeFinite(capacity) or inventory:isItemAllowed(old) ~= true then return end
        -- Java removes every exclusive entry but only capacity-checks the old
        -- same-slot item. Never credit the incoming item's worn-weight release.
        -- A changed native worn multiplier must not make that incoming item heavier.
        for _, item in ipairs({action.item, liveItem}) do
            local full, equipped = item:getUnequippedWeight(), item:getEquippedWeight()
            if not nonnegativeFinite(full) or not nonnegativeFinite(equipped) or equipped > full then return end
        end
        for _, item in pairs(current) do
            local full, equipped = item:getUnequippedWeight(), item:getEquippedWeight()
            if not nonnegativeFinite(full) or not nonnegativeFinite(equipped) or equipped > full then return end
            weight = weight + full
        end
        if weight + old:getUnequippedWeight() + 0.01 > capacity then return end
    end
    -- Exclusive-only changes have no native drop branch and need no reserve.
    return location, proof
end
local function clothingRemovalCapacity(action, liveItem, stillWorn)
    local inventory = action.character:getInventory()
    if not inventory.getCapacityWeight or not inventory.getEffectiveCapacity or not inventory.isItemAllowed then return false end
    local current, capacity = inventory:getCapacityWeight(), inventory:getEffectiveCapacity(action.character)
    if not nonnegativeFinite(current) or not nonnegativeFinite(capacity) then return false end
    local weight = 0
    for _, item in ipairs({action.item, liveItem, stillWorn or liveItem}) do
        if inventory:isItemAllowed(item) ~= true then return false end
        local value = item.getUnequippedWeight and item:getUnequippedWeight()
        if not nonnegativeFinite(value) then return false end
        local equipped = item.getEquippedWeight and item:getEquippedWeight()
        -- Removal may release worn/held weight before the native drop check.
        -- Negative equipped weight invalidates the full-weight upper bound.
        if not nonnegativeFinite(equipped) then return false end
        weight = math.max(weight, value)
    end
    -- setWornItem checks capacity after releasing worn weight, then adds the
    -- same item's full unequipped weight again. Never credit a pending release.
    -- Once authority removed the slot, one remaining reserve preserves this bound.
    return current + (stillWorn and 2 or 1) * weight + 0.01 <= capacity
end
local function nativeClothingMethods()
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
local function ordinaryClothingRemoval(action)
    local location, item = ordinaryClothing(action, true)
    if not location or item:canBeActivated() or action.item:canBeActivated() then return end
    local safe, stillWorn = clothingWornState(action, location)
    if not safe or not clothingRemovalCapacity(action, item, stillWorn) then return end
    -- Native ordinary-clothing cleanup removes both worn and matching hand
    -- references. The shared contract owns the character's hands as well as
    -- this exact root item; earlier P4 hand restoration may already clear them.
    return location
end
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
        or not sourceClassUnchanged(record.id, record.class, record.baseline) or not ownerUnchanged(record.id)
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
    for _, name in ipairs(lifecycle) do if action[name] ~= record.methods[name] then return false end end
    for name, method in pairs(record.methods) do if action[name] ~= method then return false end end
    for name, method in pairs(action) do
        if type(method) == "function" and method ~= record.methods[name] then return false end
    end
    for _, name in ipairs({"onStartFunc", "onCancelFunc", "onCompleteFunc", "onCompleteTarget", "onCompleteArgs"}) do
        if action[name] ~= record[name] then return false end
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

local scoped, rememberTidy
local function adopt(action)
    local context = sourceScope
    if not context then return end
    -- Verified Toolkit dispatchers already own their scope and lifecycle. A
    -- foreign producer may enqueue them, but must not replace their executor.
    if Operations.isCommand and Operations.isCommand(action) then return end
    local class = getmetatable(action)
    local baseline = classes[context.id] and classes[context.id][class]
    if not baseline or not sourceClassUnchanged(context.id, class, baseline) or action.onStartFunc or action.onCancelFunc
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
                self:beginAddingActions()
                Operations.runWith(record.token, scoped, record, callback, self.character, unpack(self.args))
                self:endAddingActions()
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
    if record.id == "P4TidyUpMeister" and record.class == ISInventoryTransferAction then
        local stop = action.stop
        action.stop = function(self, ...)
            if returnTransfer(self) and (matches(self, record) or Settlement.returnMatches(self, record.obligation)) then
                -- Capture before the native delegate removes its item transaction.
                -- Observation failure must not prevent the original stop call.
                pcall(Settlement.stopReturn, self, record.obligation, returnGuard)
            end
            return stop(self, ...)
        end
    end
    action.toolkitQueueSafeOnComplete = action.onCompleteFunc
    record.methods = snapshot(action)
    for name in pairs(baseline) do if record.methods[name] == nil then record.methods[name] = action[name] end end
    for _, name in ipairs({"onStartFunc", "onCancelFunc", "onCompleteFunc", "onCompleteTarget", "onCompleteArgs"}) do
        record[name] = action[name]
    end
end

scoped = function(context, callback, ...)
    if not context.token and (not ownerUnchanged(context.id) or not Toolkit.Settings.actionQueue()) then
        return callback(...)
    end
    local previous = sourceScope
    sourceScope = context
    local insert, add, addAfter, queueActions = table.insert, ISTimedActionQueue.add,
        ISTimedActionQueue.addAfter, ISTimedActionQueue.queueActions
    local addOption = ISContextMenu and ISContextMenu.addOption
    local function valid() return ownerUnchanged(context.id) and (not context.token or live(context)) end
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
    if addOption and context.id == "WashFix" then
        ISContextMenu.addOption = function(menu, label, target, callback, ...)
            if callback then
                local original, sink = callback, select(1, ...)
                callback = function(...)
                    return Operations.run(function(...)
                        local context = {id = "WashFix", target = instanceof(sink, "IsoObject") and sink or nil}
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
    local planned, transfers = {}, {}
    local function validTransfer(action, item)
        return action and action.character == character and getmetatable(action) == ISInventoryTransferAction
            and instanceof(action.item, "InventoryItem") and action.item:getID() == item:getID()
            and action.item:getFullType() == item:getFullType() and action.item:getContainer() == inventory
            and action.srcContainer == inventory and action.destContainer == floor
            and tidyActionUnchanged(action)
    end
    for _, action in ipairs(buffered) do
        if action.character == character and getmetatable(action) == P4RestoreFloorAction and tidyActionUnchanged(action) then
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
        planned[#planned + 1] = action
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
    local eventAdd, derive = event and event.Add, ISBaseTimedAction.derive
    local privateWait, sequenceWait
    ISBaseTimedAction.derive = function(class, name)
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
    ISBaseTimedAction.derive = derive
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
    for _, module in ipairs({"BetterContainers/Proximity/Proximity_ISInventoryTransferAction", "BetterContainers/Nested"}) do
        local loaded, patch = pcall(require, module)
        if not loaded or type(patch) ~= "table" or patch._installed ~= false or type(patch.install) ~= "function" then return end
        local previous = transferMethods()
        if not pcall(patch.install) then return end
        local replacement = transferMethods()
        if not policy.adoptTransferMethods(previous, replacement, containerHelpersUnchanged) then return end
        if Operations.adoptReturnMethods then Operations.adoptReturnMethods(previous, replacement, containerHelpersUnchanged) end
    end
    reviewedTransferPerform, transferPerformGuard = ISInventoryTransferAction.perform, containerHelpersUnchanged
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
                    policy.adoptTransferItemHelper(transferItem, replacementTransfer, function()
                        return P4TidyUpMeister == owner and type(registerAction) == "function" and type(registerWorn) == "function"
                            and owner.registerActionPolicy == registerAction and owner.registerWornItemReplacement == registerWorn
                            and ISTransferAction.transferItem == replacementTransfer
                            and ISTransferAction.GetDropItemOffset == replacementOffset
                    end, dropItemOffset, replacementOffset)
                end
            end
            ready[id] = ok == true
            if not ok then classes[id] = {} end
        end
    end
    if transferSourceSafe then
        local previous=ISInventoryTransferAction.checkQueueList
        local function pickupScope(action)
            return action and sessions[action.character]
        end
        local function pickupGuard(action)
            return getmetatable(action) == ISInventoryTransferAction and tidyActionUnchanged and tidyActionUnchanged(action)
                and Toolkit.ActionQueuePolicy.isOrdinaryTransfer(action)
        end
        local function plannedReturnGuard(action)
            -- Settlement owns this freshly constructed native return. Its
            -- reviewed rejection-stop and no-op merge guard are intentionally
            -- absent from P4's original instance snapshot. Reuse Policy's full
            -- native/approved-helper matcher; a copied safe-callback flag alone
            -- cannot grant observation or cleanup ownership.
            local policy = Toolkit.ActionQueuePolicy
            return getmetatable(action) == ISInventoryTransferAction and policy.matchesNative(action)
                and policy.isOrdinaryTransfer(action)
        end
        TidyIntent.observeTransfers(function(action)
            Settlement.refreshPlannedReturn(action)
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
        end, function(action)
            local record = records[action]
            local session = pickupScope(action)
            return record and record.class == ISInventoryTransferAction and matches(action, record)
                or session and Settlement.pickupMatches(session, action)
                or Settlement.plannedReturnMatches(action)
        end, {
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
                local returning = plannedReturnGuard(action) and Settlement.beginPlannedReturn(action, plannedReturnGuard)
                local session = pickupScope(action)
                if session and pickupGuard(action) then
                    Settlement.departure(session, action)
                    return Settlement.beginPickup(session, action, pickupGuard) or returning
                end
                return returning
            end,
            finish = function(action, succeeded)
                local returning = Settlement.finishPlannedReturn(action, succeeded)
                local session = pickupScope(action)
                return session and Settlement.finishPickup(session, action, succeeded) or returning
            end,
        })
        local policy=Toolkit.ActionQueuePolicy
        if policy and policy.adoptTransferQueueObserver then policy.adoptTransferQueueObserver(previous,ISInventoryTransferAction.checkQueueList) end
    end
    if ready.P4TidyUpMeister then installTidyFloorValidation() end
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
    if ready.P4TidyUpMeister then
        local owner=P4TidyUpMeister
        local actionPolicy,wornPolicy=owner.registerActionPolicy,owner.registerWornItemReplacement
        local carts=ready.SaucedCartsTransfers and Toolkit.ActionQueueCarts
        local transfer=carts and carts.isTransferConstructor
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
            if class==ISInventoryTransferAction and transfer(methods.new) and transfer(class.new) then
                allowed={new=true,perform=true,transferItem=true}
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
            if not record and (action.onStartFunc or action.onCompleteFunc or action.onCancelFunc
                or action.retriggerLastAction or action.onFailFunc or action.additionalTest) then return false end
            return record and (sourceOnly and sourceMatches(action,record) or not sourceOnly and matches(action,record))
                or not record and tidyClassUnchanged(action,getmetatable(action),baseline)
        end
        TidyIntent.install(tidyActionUnchanged,function(menu,name)
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
        end)
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
local function matchesSelectedChain(action) return not tidyTransfer(action) and not tidyEquipment(action) and matches(action) end
local function acceptsChild(parent, child)
    return matches(child) and child.toolkitQueueOperation == parent.toolkitQueueOperation
end
Toolkit.ActionQueueDefinitions.registerBehavior("compat.selected-chains",
    {types = behaviorTypes, matches = matchesSelectedChain, inspect = inspect})
Operations.registerProducer("compat.selected-chains", matchesSelectedChain, acceptsChild)
Toolkit.ActionQueueDefinitions.registerBehavior("compat.tidy-transfers",
    {types = {"ISInventoryTransferAction"}, matches = matchesTidyTransfer, inspect = inspect})
Operations.registerProducer("compat.tidy-transfers", matchesTidyTransfer, acceptsChild, true)
Toolkit.ActionQueueDefinitions.registerBehavior("compat.tidy-equipment",
    {types = {"ISEquipWeaponAction", "P4RestoreAction", "ISUnequipAction", "ISWearClothing"}, matches = matchesTidyEquipment, inspect = inspect})
Operations.registerProducer("compat.tidy-equipment", matchesTidyEquipment, acceptsChild, true)
require "LootSorter_CraftMenu"
Compat.install()
return Compat
