-- Cancellation settles already-earned obligations; it never undoes native effects.
local Toolkit = PZSurvivorToolkit
local Settlement = {}
Toolkit.ActionQueueSettlement = Settlement
local providers, byId = {}, {}
local cleanupMarker = {}

-- Families retain their own identity/effect proofs. Registration grants no edit rights.
function Settlement.register(id, provider)
    assert(type(id) == "string" and type(provider) == "table" and type(provider.retain) == "function")
    assert(provider.ownsPickup == nil or type(provider.ownsPickup) == "function")
    local entry = byId[id]
    if not entry then
        entry = {id = id}
        providers[#providers + 1], byId[id] = entry, entry
    end
    entry.retain, entry.ownsPickup = provider.retain, provider.ownsPickup
end

local function retained(action, current, queue)
    for _, provider in ipairs(providers) do
        if provider.retain(action, current, queue) then return provider.id end
    end
end

local function ownedPickup(current, id)
    for _, provider in ipairs(providers) do
        if provider.ownsPickup and provider.ownsPickup(current, id) then return true end
    end
    return false
end

function Settlement.isCleanup(action)
    return action and action.toolkitQueueReturn == cleanupMarker or false
end

local function insert(queue, action, index)
    -- Required work gets a fresh operation: cancelling its former owner cannot revoke it.
    action.toolkitQueueOperation, action.toolkitQueueReturn = {}, cleanupMarker
    table.insert(queue.queue, index, action)
end

-- Called only after the current native step/Host receipt has settled. Pickup
-- locations are intents: only the surviving exact direct-root item can activate
-- a return. Family adapters own any stronger effect/cleanup proof they require.
function Settlement.finish(queue, request, discard)
    local current, token = request.action, request.token
    if request.settlement or not queue or queue.current ~= current or queue.queue[1] ~= current
        or current.character ~= queue.character or current.toolkitQueueOperation ~= token then return false end
    local state = {phase = "body", obligations = {}, discarded = 0}
    request.settlement = state
    local operations = Toolkit.ActionQueueOperations
    local inventory = queue.character:getInventory()
    local last = 1
    while token and queue.queue[last + 1] and queue.queue[last + 1].toolkitQueueOperation == token do last = last + 1 end
    local returns, cleanup = {}, {}
    for i = last, 2, -1 do
        local member = table.remove(queue.queue, i)
        if operations.isTransfer(member) and member.allowMissingItems and member.item
            and member.srcContainer == inventory and member.destContainer ~= inventory then
            returns[member.item:getID()] = member.destContainer
        end
        local provider = retained(member, current, queue)
        if provider then
            table.insert(cleanup, 1, {kind = "cleanup", provider = provider, action = member})
        else
            discard(member, false)
            state.discarded = state.discarded + 1
        end
    end
    -- The current effect is already native/authoritative. Only release its owned
    -- bookkeeping; never force-cancel it again or synthesize a compensating effect.
    discard(current, true)
    for item, source in pairs(type(token) == "table" and token.toolkitPickups or {}) do returns[item:getID()] = source end
    local containers = ISInventoryPaneContextMenu.getContainers(queue.character)
    local index = 2
    state.phase = "cleanup"
    for _, obligation in ipairs(cleanup) do
        insert(queue, obligation.action, index)
        state.obligations[#state.obligations + 1] = obligation
        index = index + 1
    end
    for id, destination in pairs(returns) do
        -- Host replication may replace the object. Never return the stale object,
        -- recreate a consumed item or reclaim an item moved into another container.
        local item = inventory:getItemById(id)
        if not ownedPickup(current, id) and item and item:getContainer() == inventory and not item:getIsCraftingConsumed()
            and destination:isExistYet() and (containers:contains(destination)
                or Toolkit.ActionQueuePolicy.isCarriedContainer(destination, queue.character)) then
            local action = ISInventoryTransferUtil.newInventoryTransferAction(queue.character, item, inventory, destination)
            if action.Type == "ISInventoryTransferAction"
                or (not isClient() and Toolkit.ActionQueueCarts and Toolkit.ActionQueueCarts.isTransfer(action)) then
                if action.Type == "ISInventoryTransferAction" then Toolkit.BulkActions.guardTransfer(action) end
                action:setAllowMissingItems(true)
                insert(queue, action, index)
                state.obligations[#state.obligations + 1] = {kind = "return", itemId = id, destination = destination, action = action}
                index = index + 1
            end
        end
    end
    state.phase = "scheduled"
    return true
end

return Settlement
