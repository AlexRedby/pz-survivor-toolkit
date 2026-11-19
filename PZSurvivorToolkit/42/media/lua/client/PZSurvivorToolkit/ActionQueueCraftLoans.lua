-- Observe the owned pinned-recipe producer's real fetches. Native crafting
-- still schedules each original return, with its ordinary order and duration.
local Toolkit = PZSurvivorToolkit
local Proof = require "PZSurvivorToolkit/SourceProof"
local Loans = {}
Toolkit.ActionQueueCraftLoans = Loans
local capture, origin, source = Proof.captureBindings, Proof.closure, Proof.matches
local firstLine = getFirstLineOfClosure
local pins

local movementMarker = {}
local observingEpisode, observingAction
function Loans.ownsPickup(episode, action)
    return episode ~= nil and episode == observingEpisode and action == observingAction
end

local cleanupMarker = {}
local cleanupDefinitions

-- Native put-back rows stay visible and independently editable. Only a group
-- cancellation can materialize this command in place of the discarded rows.
local function registerCleanup(definitions, operations)
    if cleanupDefinitions == definitions then return end
    definitions.registerBehavior("toolkit.cancel-craft-returns", {
        types={"ISQueueActionsAction"},
        matches=function(action)
            local owns = rawget(action, cleanupMarker)
            return type(owns) == "function" and owns(action) and operations.isCommand(action)
        end,
        inspect=function(action)
            return {items={}, targets={[action.character]=true}, knownInputs=false, unknownOutputs=true}
        end,
    })
    cleanupDefinitions = definitions
end

local function nativeReturnRow(row, body, member, root, afterPickup)
    return row and row.Type == "ISInventoryTransferAction" and row.character == body.character
        and row.toolkitQueueOperation == body.toolkitQueueOperation and not row.action and not row.started
        and row.allowMissingItems == true and row.srcContainer == root and row.destContainer == member.source
        -- Host replaces the item reference in an already queued return after
        -- its native pickup. Accept only the current replica in this inventory.
        and (row.item == member.item or afterPickup and isClient() and row.item
            and row.item == root:getItemById(member.id) and row.item:getContainer() == root
            and row.item:getID() == member.id and row.item:getFullType() == member.fullType)
end

local function bindCancelledReturns(player, body, returns, members)
    if #members < 2 or #members ~= #returns then return end
    local queue = ISTimedActionQueue.queues[player]
    local index = queue and queue:indexOf(body)
    local token = body.toolkitQueueOperation
    if not index or index < 1 or not token then return end
    local handles = {}
    for i, member in ipairs(members) do
        local row = queue.queue[index + i]
        if returns[i] ~= member.item or not nativeReturnRow(row, body, member, player:getInventory()) then return end
        handles[i] = member.handle
    end
    local settlement, operations, definitions = Toolkit.ActionQueueSettlement, Toolkit.ActionQueueOperations, Toolkit.ActionQueueDefinitions
    local issue = settlement.enqueueClaimedReturns
    if not origin(issue, "ActionQueueSettlement.lua") then return end
    registerCleanup(definitions, operations)
    local expansion
    local function restore()
        if settlement.enqueueClaimedReturns == issue then issue(expansion, handles) end
    end
    expansion = operations.command(player, restore, {})
    expansion[cleanupMarker] = function(action) return action == expansion and action.addActionsFunction == restore end
    operations.adopt(expansion, token)
    if settlement.cleanupAfter(expansion, handles) and settlement.claimBorrowedReturns(expansion, handles) then
        settlement.onCancelBorrowedReturns(expansion, handles)
    end
end

-- Capture only the native return rows the walk is about to discard. The Java
-- movement handler also clears characterActions *after* the Lua stop returns.
-- Issue fresh timed transfers on a later stationary tick, one tool at a time.
local function bindMovementReturns(player, body, items, members, live)
    local queue = ISTimedActionQueue.queues[player]
    local index = queue and queue:indexOf(body)
    if not index or index < 1 or #items ~= #members then return end
    local list, root = queue.queue, player:getInventory()
    for i, member in ipairs(members) do
        local row = list[index+i]
        if items[i] ~= member.item or not nativeReturnRow(row, body, member, root) then return end
        member.row = row
    end
    body[movementMarker] = function(stoppedQueue)
        if stoppedQueue ~= queue or queue.queue ~= list or queue.current ~= body or list[1] ~= body
            or not live() or not body.stopOnWalk or not body:isStarted()
            or not (player:isPlayerMoving() or player:pressedMovement(false)) then return end
        local progress = body:getJobDelta()
        if progress <= 0 or progress >= 1 then return end
        local pending = {}
        for i, member in ipairs(members) do
            if list[1+i] == member.row and nativeReturnRow(member.row, body, member, root, true)
                and Toolkit.ActionQueueSettlement.earned(member.handle) then
                pending[#pending+1] = member
            end
        end
        if #pending == 0 then return end
        local generation = (queue.toolkitOperationGeneration or 0) + 1
        local cursor, issued = 1, nil
        local function advance()
            if ISTimedActionQueue.queues[player] ~= queue or queue.queue ~= list
                or queue.toolkitOperationGeneration ~= generation
                or player:isDead() or player:isAsleep() or getSpecificPlayer(player:getPlayerNum()) ~= player then return false end
            if list[1] or queue.current then
                return issued ~= nil and list[1] == issued and queue.current == issued and #list == 1
            end
            if player:hasTimedActions() or player:isPlayerMoving() or player:pressedMovement(false) then return true end
            if not live() then return false end
            while cursor <= #pending do
                local member = pending[cursor]
                cursor = cursor + 1
                local item = root:getItemById(member.id)
                if item and item:getFullType() == member.fullType and item:getContainer() == root
                    and not player:isEquipped(item)
                    and Toolkit.ActionQueuePolicy.isCarriedContainer(member.source, player)
                    and member.source:hasRoomFor(player, item) then
                    ISCraftingUI.ReturnItemToContainer(player, item, member.source)
                    issued = list[1]
                    return cursor <= #pending and issued ~= nil and issued.Type == "ISInventoryTransferAction"
                        and issued.character == player and issued.srcContainer == root and issued.destContainer == member.source
                        and issued.item == item and issued.allowMissingItems == true
                end
            end
            return false
        end
        local function tick()
            local ok, waiting = pcall(advance)
            if not ok or not waiting then Events.OnTick.Remove(tick) end
        end
        Events.OnTick.Add(tick)
    end
end

function Loans.movementStopped(body, queue)
    local stopped = rawget(body, movementMarker)
    if stopped then
        body[movementMarker] = nil
        stopped(queue)
    end
end

local function captureLoans(player, body, selected, kept)
    local settlement, policy, craft, definitions, settings, bulk = Toolkit.ActionQueueSettlement,
        Toolkit.ActionQueuePolicy, Toolkit.ActionQueueCraft, Toolkit.ActionQueueDefinitions, Toolkit.Settings, Toolkit.BulkActions
    local menu, util = ISCraftingUI, ISInventoryTransferUtil
    if P4TidyUpMeister ~= nil or type(getActivatedMods) ~= "function"
        or type(settlement) ~= "table" or type(policy) ~= "table" or type(craft) ~= "table"
        or type(definitions) ~= "table" or type(settings) ~= "table" or type(bulk) ~= "table"
        or type(menu) ~= "table" or type(util) ~= "table" or type(selected) ~= "table"
        or not instanceof(player, "IsoPlayer")
        or getSpecificPlayer(player:getPlayerNum()) ~= player or player:isDead() or player:isAsleep()
        or player:hasTrait(CharacterTrait.DISORGANIZED) or not craft.supports(body)
        or body.character ~= player or body.action or body.started
        or body.craftRecipe:isCanBeDoneFromFloor() or kept:size() == 0 then return end
    local editor = settings.actionQueue()
    if not editor and type(settlement.beginIndependentRestoration) ~= "function" then return end
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
        if not watch() or enabled() ~= editor or P4TidyUpMeister ~= nil then return false end
        local mods = activated()
        return mods and mods:contains("P4TidyUpMeister") == false and watch()
    end
    if not live() then return end
    local carriedCount = 0
    for _, expected in pairs(inputs) do
        if carried(expected.source,player) then carriedCount = carriedCount + 1 end
    end
    if carriedCount == 0 or not live() then return end
    local members, episode = {}, {actor=player}
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
            if not editor then
                observingEpisode, observingAction = episode, action
                local ok, admitted = pcall(settlement.beginIndependentRestoration, episode, action)
                observingEpisode, observingAction = nil, nil
                if not ok or not admitted then return end
            end
            local handle = prepare(action,{guard=guard,capture=function() return {source=expected.source} end,
                observed=function() return false end})
            if handle then members[#members+1] = {handle=handle, item=item, source=expected.source, id=expected.id, fullType=expected.fullType} end
        end,
        returns = function(items)
            if #members == 0 or not live() then return end
            if editor then
                bindCancelledReturns(player, body, items, members)
            else
                bindMovementReturns(player, body, items, members, live)
            end
        end,
        body = function(action)
            if #members > 0 and action == body and live() then remember(action,inspect) end
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
