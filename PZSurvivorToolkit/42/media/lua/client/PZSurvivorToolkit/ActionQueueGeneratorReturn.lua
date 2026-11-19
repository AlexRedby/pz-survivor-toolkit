-- Client side of an owned, one-shot generator recovery. The world object never
-- crosses this boundary: only the authority knows which generator was placed.
local Return = {}
PZSurvivorToolkit.ActionQueueGeneratorReturn = Return
local active, issued = {}, {}
local sequence = 0
local recovery
local protocol = 'PZSurvivorToolkitGenerator'
local function received(actor, message)
    local record = actor and active[actor:getPlayerNum()]
    if not record or record.actor ~= actor or record.receipt or not record.action
        or record.episode ~= message.episode or record.sourceID ~= message.sourceID
        or record.toolID ~= message.toolID then return end
    if message.skipped == true or message.unknown == true or (message.outputType == record.item:getFullType()
        and type(message.outputID) == 'number' and message.outputID ~= record.sourceID) then
        record.receipt = message
        active[actor:getPlayerNum()] = nil
    end
end

local function install()
    if recovery then return true end
    local impl = require 'PZSurvivorToolkit/ActionQueueGeneratorRecovery'
    if not impl or type(impl.beforeEquip) ~= 'function' then return false end
    if not isClient() then
        local observer = {
            begin = function(action, phase)
                if phase ~= 'complete' then return false end
                local actor = action.character
                local record = actor and active[actor:getPlayerNum()]
                if record and record.equip == action then
                    record.ticket = impl.beforeEquip(action)
                    if Return.trace then pcall(Return.trace, action, 'drop-begin', record.ticket ~= nil) end
                    return record.ticket ~= nil
                end
            end,
            finish = function(action, phase, succeeded)
                if phase ~= 'complete' then return end
                local actor = action.character
                local record = actor and active[actor:getPlayerNum()]
                if record and record.equip == action and record.ticket then
                    local ticket = record.ticket
                    record.ticket = nil
                    impl.afterEquip(ticket, action, succeeded)
                end
            end,
        }
        if not PZSurvivorToolkit.ActionQueueLifecycle.registerObserver('generator-drop', observer) then return false end
        impl.onRecovered = received
    else
        Events.OnServerCommand.Add(function(module, command, args)
            if module ~= protocol or command ~= 'Recovered' or type(args) ~= 'table' then return end
            for _, record in pairs(active) do
                if record.actor:getOnlineID() == args.onlineID then received(record.actor, args); return end
            end
        end)
    end
    -- Settlement requires a behavior contract for each owned cleanup child.
    -- Its world target and newly allocated output are known only on the authority.
    PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('toolkit.generator-recovery', {
        types = {'PZSurvivorToolkitGeneratorRecovery'},
        matches = function(action)
            local record = action.character and issued[action.character:getPlayerNum()]
            return record ~= nil and Return.bound(record, action)
        end,
        inspect = function(action)
            return {items={[action.toolID]=true}, itemTypes={}, targets={}, hands=action.character,
                knownInputs=false, unknownOutputs=true, cancelWaiting=false, cancelOperation=false}
        end,
    })
    recovery = impl
    return true
end

function Return.holding(actor)
    local item = actor:getPrimaryHandItem()
    return item and item == actor:getSecondaryHandItem() and item:getFullType() == 'Base.Generator'
end

function Return.arm(actor, tool, equip)
    if not Return.holding(actor) or not install() then return nil, 'observer-unavailable' end
    local root, item = actor:getInventory(), actor:getPrimaryHandItem()
    if item:getContainer() ~= root or root:getItemWithID(item:getID()) ~= item
        or not tool or tool:getContainer() ~= root or root:getItemWithID(tool:getID()) ~= tool then return nil, 'inventory-changed' end
    sequence = sequence + 1
    local message = {episode=sequence, sourceID=item:getID(), toolID=tool:getID()}
    if isClient() then
        sendClientCommand(actor, protocol, 'Arm', message)
    else
        local armed, reason = recovery.arm(actor, message)
        if not armed then return nil, reason or 'authority-declined' end
    end
    local record = {actor=actor, item=item, equip=equip, episode=sequence, sourceID=message.sourceID, toolID=message.toolID}
    active[actor:getPlayerNum()] = record
    return record
end

function Return.cancel(record)
    if not record then return end
    local actor = record.actor
    if active[actor:getPlayerNum()] ~= record or record.revoked then return end
    record.revoked = true
    -- An already-issued action still needs its final authority receipt.
    if not record.action or not record.action.action then active[actor:getPlayerNum()] = nil end
    if isClient() then
        sendClientCommand(actor, protocol, 'Cancel', {episode=record.episode})
    else
        recovery.cancel(actor, record.episode)
    end
end

function Return.handRequested(actor)
    local record = active[actor:getPlayerNum()]
    if record and record.actor == actor then Return.cancel(record) end
end

function Return.pickup(record)
    if active[record.actor:getPlayerNum()] ~= record or record.action then return end
    local action = PZSurvivorToolkitGeneratorRecovery:new(record.actor, record.sourceID, record.toolID, record.episode)
    record.action = action
    issued[record.actor:getPlayerNum()] = record
    return action
end

function Return.bound(record, action)
    return record.action == action and getmetatable(action) == PZSurvivorToolkitGeneratorRecovery
        and action.character == record.actor and action.sourceID == record.sourceID
        and action.toolID == record.toolID and action.episode == record.episode
end

function Return.observed(record)
    local receipt, actor = record.receipt, record.actor
    if not receipt or receipt.skipped or receipt.unknown then return false end
    local root = actor:getInventory()
    local item = root:getItemWithID(receipt.outputID)
    return item ~= nil and item:getContainer() == root and item:getFullType() == receipt.outputType
        and actor:getPrimaryHandItem() == item and actor:getSecondaryHandItem() == item
end

if Events and Events.OnGameStart then Events.OnGameStart.Add(function() active, issued = {}, {} end) end
return Return
