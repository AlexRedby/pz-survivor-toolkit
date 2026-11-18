-- Observe the owned pinned-recipe producer's real fetches. Native crafting
-- still schedules each original return, with its ordinary order and duration.
local Toolkit = PZSurvivorToolkit
local Proof = require "PZSurvivorToolkit/SourceProof"
local Loans = {}
Toolkit.ActionQueueCraftLoans = Loans
local capture, origin, source = Proof.captureBindings, Proof.closure, Proof.matches
local firstLine = getFirstLineOfClosure
local pins

local function captureLoans(player, body, selected, kept)
    local settlement, policy, craft, definitions, settings, bulk = Toolkit.ActionQueueSettlement,
        Toolkit.ActionQueuePolicy, Toolkit.ActionQueueCraft, Toolkit.ActionQueueDefinitions, Toolkit.Settings, Toolkit.BulkActions
    local menu, util = ISCraftingUI, ISInventoryTransferUtil
    if P4TidyUpMeister ~= nil or type(getActivatedMods) ~= "function"
        or type(settlement) ~= "table" or type(policy) ~= "table" or type(craft) ~= "table"
        or type(definitions) ~= "table" or type(settings) ~= "table" or type(bulk) ~= "table"
        or type(menu) ~= "table" or type(util) ~= "table" or type(selected) ~= "table"
        or settings.actionQueue() ~= true or not instanceof(player, "IsoPlayer")
        or getSpecificPlayer(player:getPlayerNum()) ~= player or player:isDead() or player:isAsleep()
        or player:hasTrait(CharacterTrait.DISORGANIZED) or not craft.supports(body)
        or body.character ~= player or body.action or body.started
        or body.craftRecipe:isCanBeDoneFromFloor() or kept:size() == 0 then return end
    -- Ordinary root-only crafts pay no source lease or binding scan. Retain
    -- only non-consuming kept tools; recipe books and other implicit inputs
    -- have no selected native input and cannot acquire a loan here.
    local inputs, ids, root, inputCount = {}, {}, player:getInventory(), 0
    for _, selection in ipairs(selected) do
        local input = selection.input.native
        if input:isKeep() and not input:hasConsumeFromItem() and not input:hasCreateToItem()
            and not input:isReplace() and not input:isApplyOnTick() then
            for index = 0, selection.items:size() - 1 do
                local item = selection.items:get(index)
                local location = item:getContainer()
                if kept:contains(item) and location ~= root and location:getContainingItem()
                    and not player:isEquipped(item) then
                    local script = item:getScriptItem()
                    if script and not script:isItemType(ItemType.DRAINABLE) and not script:isItemType(ItemType.FOOD)
                        and not script:isItemType(ItemType.CONTAINER) and not script:getReplaceOnUse()
                        and not script:getReplaceOnDeplete() and not script:getOnBreak() then
                        local id = item:getID()
                        if ids[id] then return end
                        ids[id], inputs[item] = true, {id=id, fullType=item:getFullType(), source=location}
                        inputCount = inputCount + 1
                    end
                end
            end
        end
    end
    if inputCount == 0 then return end
    local prepare, remember, inspect = settlement.observePreparation, settlement.rememberPreparation, definitions.inspect
    local matches, ordinary, carried = policy.matchesNative, policy.isOrdinaryTransfer, policy.isCarriedContainer
    local activated, enabled = getActivatedMods, settings.actionQueue
    local bindings = {
        {owner=_G, keys={"PZSurvivorToolkit","P4TidyUpMeister","getActivatedMods","getSpecificPlayer","getFirstLineOfClosure",
            "ISCraftingUI","ISInventoryTransferUtil","CharacterTrait","ItemType"}},
        {owner=Toolkit, keys={"ActionQueueCraftLoans","ActionQueueSettlement","ActionQueuePolicy","ActionQueueCraft",
            "ActionQueueDefinitions","Settings","BulkActions"}},
        {owner=Proof, keys={"captureBindings","closure","matches"}}, {owner=Loans, keys={"capture"}},
        {owner=settlement, keys={"observePreparation","rememberPreparation"}},
        {owner=policy, keys={"matchesNative","isOrdinaryTransfer","isCarriedContainer"}},
        {owner=craft, keys={"supports"}}, {owner=definitions, keys={"inspect"}},
        {owner=settings, keys={"actionQueue"}}, {owner=bulk, keys={"transfer"}},
        {owner=menu, keys={"ReturnItemsToOriginalContainer","ReturnItemToContainer"}},
        {owner=util, keys={"newInventoryTransferAction"}},
    }
    local watch = capture(bindings)
    if not watch or getFirstLineOfClosure ~= firstLine or type(firstLine) ~= "function" then return end
    for _, entry in ipairs({{prepare,"ActionQueueSettlement.lua"},{remember,"ActionQueueSettlement.lua"},
        {inspect,"ActionQueueDefinitions.lua"},{matches,"ActionQueuePolicy.lua"},{ordinary,"ActionQueuePolicy.lua"},
        {carried,"ActionQueuePolicy.lua"},{craft.supports,"ActionQueueCraft.lua"},{bulk.transfer,"BulkActions.lua"},
        {menu.ReturnItemsToOriginalContainer,"ISCraftingUI.lua"},{menu.ReturnItemToContainer,"ISCraftingUI.lua"},
        {util.newInventoryTransferAction,"ISInventoryTransferUtil.lua"}}) do
        if not origin(entry[1],entry[2]) or not watch() then return end
    end
    for _, entry in ipairs({{menu.ReturnItemsToOriginalContainer,4},{menu.ReturnItemToContainer,15},
        {util.newInventoryTransferAction,15},{bulk.transfer,233}}) do
        if firstLine(entry[1]) ~= entry[2] or not watch() then return end
    end
    if not pins then
        if not source("media/lua/client/ISUI/ISCraftingUI.lua",2192655063,nil,true)
            or not source("media/lua/shared/TimedActions/ISInventoryTransferUtil.lua",4121924183,nil,true)
            or not source("media/lua/client/PZSurvivorToolkit/BulkActions.lua",3109997898,"PZSurvivorToolkit",true)
            or not watch() then return end
        pins = true
    end
    local function live()
        if not watch() or enabled() ~= true or P4TidyUpMeister ~= nil then return false end
        local mods = activated()
        return mods and mods:contains("P4TidyUpMeister") == false and watch()
    end
    if not live() then return end
    local carriedCount = 0
    for _, expected in pairs(inputs) do
        if carried(expected.source,player) then carriedCount = carriedCount + 1 end
    end
    if carriedCount == 0 or not live() then return end
    local observed = false
    return {
        pickup = function(action)
            local item = action.item
            local expected = inputs[item]
            if not expected or not live() or action.character ~= player or action.destContainer ~= root
                or action.srcContainer ~= expected.source or item:getContainer() ~= expected.source
                or item:getID() ~= expected.id or item:getFullType() ~= expected.fullType
                or not matches(action) or not ordinary(action) or not carried(expected.source,player) then return end
            local function guard(value)
                return value == action and live() and value.character == player and value.srcContainer == expected.source
                    and value.destContainer == root and matches(value) and ordinary(value) and live()
            end
            local handle = prepare(action,{guard=guard,capture=function() return {source=expected.source} end,
                observed=function() return false end})
            observed = observed or handle ~= nil
        end,
        body = function(action)
            if observed and action == body and live() then remember(action,inspect) end
        end,
    }
end

-- Optional observation must never interrupt the original crafting path when
-- an unavailable/changed source or foreign provider cannot be inspected.
function Loans.capture(...)
    local ok, result = pcall(captureLoans, ...)
    if ok then return result end
end

return Loans
