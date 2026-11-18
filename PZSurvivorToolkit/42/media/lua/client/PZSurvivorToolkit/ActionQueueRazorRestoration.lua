-- P4-free native tool producer. Installation is explicit until editor-off
-- restoration and live provider cutover are qualified. No per-tick queue scan.
local Toolkit = PZSurvivorToolkit
local Hand = require 'PZSurvivorToolkit/ActionQueueHandRestoration'
local Razor = {}
Toolkit.ActionQueueRazorRestoration = Razor
local installed = false
local commandMarker = {}

function Razor.enabled()
    return installed
end

local function command(actor, callback)
    local action = Toolkit.ActionQueueOperations.command(actor, callback, {})
    action[commandMarker] = function(candidate)
        return candidate == action and action.addActionsFunction == callback
    end
    return action
end

function Razor.install()
    if installed then return true end
    local definitions, ops = Toolkit.ActionQueueDefinitions, Toolkit.ActionQueueOperations
    if not definitions or not ops or not Toolkit.ActionQueueTidyIntent
        or not Toolkit.ActionQueueRestoration.prepareOwnHandIntent()
        or not ops.installRazorProducer() then return false end
    definitions.registerBehavior('toolkit.razor-restoration', {
        types = {'ISQueueActionsAction'},
        matches = function(action)
            local seal = rawget(action, commandMarker)
            return type(seal) == 'function' and seal(action) and ops.isCommand(action)
        end,
        inspect = function(action)
            return {knownInputs=false, items={}, targets={[action.character]=true}, hands=action.character,
                equipment=action.character, deferred=true, cancelWaiting=true}
        end,
    })
    installed = true
    return true
end

local function isPrimaryEquip(action, actor, item)
    return action.character == actor and action.item == item and action.primary == true
        and not action.twoHands and not action.fromHotbar and not action.alwaysTurnOn
        and Toolkit.ActionQueuePolicy.matchesNative(action)
end

local function currentTool(episode)
    local root = episode.actor:getInventory()
    local item = root:getItemById(episode.itemId)
    if item and item:getFullType() == episode.itemType and item:getContainer() == root
        and (item == episode.tool or isClient()) then return item end
end

function Razor.observe(episode, action)
    if not Toolkit.ActionQueueRazorProducer.owns(episode) then return end
    local settlement, policy = Toolkit.ActionQueueSettlement, Toolkit.ActionQueuePolicy
    local actor, tool = episode.actor, episode.tool
    if action == episode.pickup then
        local itemType = tool:getFullType()
        if (itemType ~= 'Base.Razor' and itemType ~= 'Base.Scissors') or not policy.matchesNative(action)
            or not policy.isOrdinaryTransfer(action) or not policy.isCarriedContainer(action.srcContainer, actor)
            or actor:isEquipped(tool) then return end
        if not Toolkit.Settings.actionQueue() and not settlement.beginIndependentRestoration(episode, action) then return end
        local source, root = action.srcContainer, actor:getInventory()
        episode.itemId, episode.itemType = tool:getID(), itemType
        episode.loan = settlement.observePreparation(action, {
            guard = function(value)
                return value == action and value.character == actor and value.srcContainer == source
                    and value.destContainer == root and episode.source() and policy.matchesNative(value)
                    and policy.isOrdinaryTransfer(value)
            end,
            capture = function() return {source=source} end,
            observed = function() return false end, -- Settlement verifies the native transfer itself.
        })
    elseif episode.loan and action == episode.equip then
        settlement.rememberPreparation(action, Toolkit.ActionQueueDefinitions.inspect)
        local function guard(value)
            -- Native Host isValid resolves the inventory ID after begin. The
            -- original menu reference may still be present at capture time.
            local canonical = currentTool(episode)
            return canonical ~= nil and value == action and episode.source()
                and (value.item == canonical or isClient() and value.item == tool)
                and isPrimaryEquip(value, actor, value.item)
        end
        episode.equipHandle = settlement.observePreparation(action, {
            guard = guard,
            capture = function()
                local revision = Toolkit.ActionQueueTidyIntent.primaryRequestRevision(actor)
                local before = Toolkit.ActionQueueEquip.restorationHands(actor)
                if before and before.primary and revision ~= nil then
                    episode.revision = revision
                    return before
                end
            end,
            observed = function(_, before)
                local after = Toolkit.ActionQueueEquip.restorationHands(actor)
                if not after or not after.primary or after.primary.item ~= currentTool(episode) then return false end
                if not episode.hand then episode.hand = Hand.capture(before, after, after.primary) end
                return episode.hand ~= nil
            end,
        })
    elseif episode.loan and action == episode.body then
        settlement.rememberPreparation(action, Toolkit.ActionQueueDefinitions.inspect)
    end
end

local function restore(episode, parent)
    local settlement, ops = Toolkit.ActionQueueSettlement, Toolkit.ActionQueueOperations
    local actor, loan = episode.actor, episode.loan
    if not settlement.reserveClaimedReturn(parent, loan) then return end
    if not episode.source() or not episode.hand or not settlement.earned(episode.equipHandle) then return end
    local hands = Toolkit.ActionQueueEquip.restorationHands
    local revision = Toolkit.ActionQueueTidyIntent.primaryRequestRevision
    local function eligible()
        return episode.source() and revision(actor) == episode.revision
    end
    if not eligible() then return end
    local proposal, plan = Hand.propose(episode.hand, hands(actor))
    if not proposal then return end
    local previous = plan.incoming.item
    if not hands(actor, previous) then return end
    local action = ISEquipWeaponAction:new(actor, previous, 50, true, false)
    local token = parent.toolkitQueueOperation
    ops.adopt(action, token)
    if not settlement.inheritCleanup(action, parent) then return end
    local function bound(value)
        return value == action and isPrimaryEquip(value, actor, previous)
    end
    local effect = settlement.observeCleanupEffect(action, {
        guard = bound, sourceGuard = bound,
        admit = function(value)
            return bound(value) and eligible() and Hand.consume(episode.hand, proposal, hands(actor, previous)) ~= nil
        end,
        capture = function() return hands(actor) end,
        observed = function(_, before)
            local after = hands(actor)
            return after and after.primary and after.primary.item == previous and before.primary
                and before.primary.item == currentTool(episode)
                and (after.secondary and after.secondary.item) == (before.secondary and before.secondary.item)
        end,
    })
    if not effect then return end
    local continuation = command(actor, function()
        if settlement.earned(effect) then settlement.enqueueBorrowedReturn(loan) end
    end)
    ops.adopt(continuation, token)
    if settlement.inheritCleanup(continuation, parent)
        and settlement.requireBorrowedReturnSuccess(loan, {effect}, continuation) then
        ISTimedActionQueue.add(action)
        ISTimedActionQueue.add(continuation)
    end
end

function Razor.finish(episode)
    if not Toolkit.ActionQueueRazorProducer.owns(episode) or not episode.loan or not episode.equipHandle then return end
    local body, actor = episode.body, episode.actor
    local token = body.toolkitQueueOperation
    local queue = ISTimedActionQueue.queues[actor]
    if not token or episode.pickup.toolkitQueueOperation ~= token or episode.equip.toolkitQueueOperation ~= token
        or not queue or queue.queue[#queue.queue] ~= body or queue.queue[#queue.queue - 1] ~= episode.equip
        or not Toolkit.ActionQueueDefinitions.inspect(body) or not episode.source() then return end
    local parent
    parent = command(actor, function() restore(episode, parent) end)
    local ops, settlement = Toolkit.ActionQueueOperations, Toolkit.ActionQueueSettlement
    ops.adopt(parent, token)
    if settlement.cleanup(parent, episode.loan) and settlement.claimBorrowedReturn(parent, episode.loan) then
        ops.runWith(token, ISTimedActionQueue.add, parent)
    end
end

return Razor
