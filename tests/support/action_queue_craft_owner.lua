-- Exercise the real source-pinned owner installer with the supplied native Neat source.
return function(source)
    local Toolkit = PZSurvivorToolkit
    local previousRequire, reader, mods, events = require, getModFileReader, getActivatedMods, Events
    local definitions, operations, queue = Toolkit.ActionQueueDefinitions, Toolkit.ActionQueueOperations, ISTimedActionQueue
    local add = queue and queue.add
    local producer = operations and operations.registerProducer
    Toolkit.ActionQueueDefinitions = definitions or {registerBehavior = function() end}
    Toolkit.ActionQueueOperations = operations or {}
    Toolkit.ActionQueueOperations.registerProducer = producer or function() end
    ISTimedActionQueue = queue or {}
    Events = events or {}
    getActivatedMods = function() return {contains = function(_, id) return id == 'Neat_Crafting' end} end
    getModFileReader = function(id, path)
        if id ~= 'Neat_Crafting' or not path:find('NC_CraftActionPanel.lua', 1, true) then return end
        local cursor = 1
        return {close = function() end, readLine = function()
            if cursor > #source then return end
            local boundary = source:find('\n', cursor, true) or #source + 1
            local line = source:sub(cursor, boundary - 1):gsub('\r', '')
            cursor = boundary + 1; return line
        end}
    end
    require = function(module)
        if module == 'Neat_Crafting/NC_CraftActionPanel' then return assert(loadstring(source))() end
        return previousRequire(module)
    end
    local compat = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'))()
    require, getModFileReader, getActivatedMods, Events = previousRequire, reader, mods, events
    Toolkit.ActionQueueDefinitions, Toolkit.ActionQueueOperations = definitions, operations
    if operations then operations.registerProducer = producer end
    ISTimedActionQueue = queue
    if queue then queue.add = add end
    assert(NC_CraftActionPanel, 'verified installer must load the actual Neat panel source')
    return compat
end
