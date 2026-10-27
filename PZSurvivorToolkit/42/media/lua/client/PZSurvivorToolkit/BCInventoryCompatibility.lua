-- BC installs one set of aggregate policies against the initially active UI.
-- Share those policies while each supported class retains its own native chain.
require 'ISUI/ISInventoryPane'
require 'ISUI/ISInventoryPage'
local Classes = require 'PZSurvivorToolkit/InventoryClasses'
PZSurvivorToolkit = PZSurvivorToolkit or {}
if PZSurvivorToolkit.BCInventoryCompatibility then return PZSurvivorToolkit.BCInventoryCompatibility end
local Compatibility = {}
local pane = require 'BetterContainers/Proximity/Proximity_ISInventoryPane'
local page = require 'BetterContainers/Proximity/Proximity_ISInventoryPage'
if pane._installed or page._installed then
    error('BC inventory compatibility must load before Better Containers proximity installers')
end

local function pack(...)return {n=select('#',...),...}end

-- Kahlua rawget follows metatables, so ownership must use own-field enumeration.
local function own(class, name)
    for key,value in pairs(class) do if key == name then return value end end
end

local function methodOwner(class, name)
    while type(class) == 'table' do
        local method = own(class, name)
        if method ~= nil then return class, method end
        class = getmetatable(class)
    end
end

local function bridge(upstream, activeClass, classes, names)
    local entries, dispatchers = {}, {}
    local original, sourceFallback, shared, failure = upstream.install
    local failed = false
    local function boundAncestor(class, name)
        class = getmetatable(class)
        while type(class) == 'table' do
            local entry = entries[class]
            if entry and entry.published[name] then return true end
            class = getmetatable(class)
        end
        return false
    end
    local function register(class)
        if not class or entries[class] then return end
        local entry = {native={}, published={}}
        for _,name in ipairs(names) do
            local owner, method = methodOwner(class, name)
            if type(method) ~= 'function' then error('BC inventory compatibility needs '..name) end
            -- A late derived override owns its policy. Its super call inherits BC;
            -- retaining that override as a predecessor would dispatch back into it.
            if not boundAncestor(class, name) then
                entry.native[name] = {owner=owner, callback=method}
            end
        end
        entries[class] = entry
    end
    local function predecessor(self, name, previous)
        local class = previous and getmetatable(previous) or getmetatable(self)
        while type(class) == 'table' do
            local entry = entries[class]
            local native = entry and entry.native[name]
            if native then return native end
            class = getmetatable(class)
        end
        if previous then error('BC inventory predecessor has no parent for '..name, 0) end
        return sourceFallback[name]
    end
    for _,name in ipairs(names) do
        local owners = setmetatable({}, {__mode='k'})
        local function finish(self, previous, ok, ...)
            owners[self] = previous
            if not ok then error((...), 0) end
            return ...
        end
        dispatchers[name] = function(self, ...)
            local previous = owners[self]
            local native = predecessor(self, name, previous)
            owners[self] = native.owner
            -- A derived native override may call parent.shared(self). Resolve
            -- that super after the current owner, restoring scope on any error.
            -- Vararg forwarding avoids allocating a result table on each UI tick.
            return finish(self, previous, pcall(native.callback, self, ...))
        end
    end
    local function publish(class)
        if not class then return end
        local entry = entries[class]
        if entry.processed then return end
        for _,name in ipairs(names) do
            local native = entry.native[name]
            if native and native.owner ~= class and entries[native.owner] then
                -- The owning ancestor is also being bridged. Keep actual
                -- inheritance so its later decorators remain visible to children.
                entry.native[name] = nil
                if own(class, name) == shared[name] then class[name] = nil end
            elseif native then
                class[name] = shared[name]
                entry.published[name] = true
            end
        end
        entry.processed = true
    end
    local function attach()
        if shared then
            classes(register)
            classes(publish)
        end
    end
    upstream.install = function(...)
        if failed then error(failure, 0) end
        if shared then return end
        local source = activeClass()
        classes(register)
        register(source)
        if not source then error('BC inventory compatibility needs an active UI class') end
        local sourceOwn = {}
        sourceFallback = {}
        for _,name in ipairs(names) do
            local owner, method = methodOwner(source, name)
            sourceOwn[name] = own(source, name)
            sourceFallback[name] = {owner=owner, callback=method}
            source[name] = dispatchers[name]
        end
        -- One public install captures the dispatchers without replacing globals
        -- or replaying BC's singleton guard.
        local values = pack(pcall(original, ...))
        local methods = {}
        if values[1] then
            for _,name in ipairs(names) do
                local method = source[name]
                if type(method) ~= 'function' or method == dispatchers[name] then
                    values = {false, 'BC inventory installer did not decorate '..name, n=2}
                    break
                end
                methods[name] = method
            end
        end
        if not values[1] then
            for _,name in ipairs(names) do source[name] = sourceOwn[name] end
            -- Preserve the upstream guard exactly as its failed installer left it;
            -- never publish a partial bridge or silently retry a singleton install.
            failed, failure = true, values[2]
            error(failure, 0)
        end
        shared = methods
        attach()
        return unpack(values, 2, values.n)
    end
    return attach
end

local attachPanes = bridge(pane, function()return ISInventoryPane end, Classes.panes,
    {'update','clearWorldObjectHighlights','doWorldObjectHighlight'})
local attachPages = bridge(page, function()return ISInventoryPage end, Classes.pages,
    {'addContainerButton','selectContainer','setNewContainer','selectButtonForContainer',
        'setForceSelectedContainer','onMouseOutButton','update'})
Classes.onToggle(function()
    attachPanes()
    attachPages()
end)
PZSurvivorToolkit.BCInventoryCompatibility = Compatibility
return Compatibility
