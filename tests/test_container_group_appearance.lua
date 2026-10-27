local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local module = root .. 'client/PZSurvivorToolkit/ContainerGroupAppearance.lua'
local bcRoot = os.getenv('PZST_TEST_BC_LUA_ROOT')
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

if NativeActionRoot then
    local file = assert(io.open(NativeActionRoot .. '/client/ISUI/ISInventoryPage.lua', 'r'))
    local source = file:read('*a'):gsub('\r', ''); file:close()
    local refresh = assert(source:match('function ISInventoryPage:refreshBackpacks%(%)%s*(.-)\nend'))
    local selected = assert(refresh:find('self.selectedButton = containerButton', 1, true))
    local complete = assert(refresh:find('triggerEvent("OnRefreshInventoryWindowContainers", self, "end")', 1, true))
    assert(selected < complete, 'native end event moved before selectedButton assignment')
end

local function setup(active)
    PZSurvivorToolkit = {}
    local w = {active = active, ready = true, records = {}, listeners = {}, calls = 0, refreshes = 0}
    Events = {}
    for _, name in ipairs({'OnGameStart', 'OnRefreshInventoryWindowContainers'}) do
        local handlers = {}
        Events[name] = {handlers = handlers, Add = function(fn) handlers[#handlers + 1] = fn end}
    end
    function w.fire(event, ...)
        for _, fn in ipairs(Events[event].handlers) do fn(...) end
    end
    getTextOrNull = function(key)
        return ({IGUI_ContainerTitle_crate = 'Wooden crate', IGUI_ContainerTitle_shelf = 'Shelves',
            IGUI_ContainerTitle_display = 'Display title'})[key]
    end
    getTexture = function(path) return path end
    getSpecificPlayer = function() return {getUsername = function() return 'survivor' end} end
    instanceof = function(obj, kind) return obj and obj.kind == kind end
    local helpers = {
        getModDataRoot = function(md, create)
            if create then md.BetterContainers = md.BetterContainers or {} end
            return md.BetterContainers
        end,
        getIconTexture = function(icon) return icon and icon.value end,
        dlog = function() end,
    }
    local backend, customizer
    local groups = {
        resolve = function(obj, ci)
            local id = obj and obj.md and obj.md.links and obj.md.links[tostring(ci)]
            return copy(w.records[id])
        end,
        onChanged = function(fn) w.listeners[fn] = true end,
    }
    function w.change() for fn in pairs(w.listeners) do fn() end end
    require = function(name)
        if name == 'PZSurvivorToolkit/ContainerGroups' then return groups end
        if name == 'PZSurvivorToolkit/ContainerAppearance' then return {available = function() return w.active end} end
        if name == 'BetterContainers/Helpers' then return helpers end
        if name == 'BetterContainers/Customize/Network' then return {} end
        if name == 'BetterContainers/Customize/ModData' then
            if not w.ready then error('backend not loaded') end
            return backend
        end
        error('unexpected require ' .. name)
    end
    if bcRoot then
        backend = dofile(bcRoot .. '/shared/BetterContainers/Customize/ModData.lua')
        customizer = dofile(bcRoot .. '/client/BetterContainers/Customize/Customizer.lua')
    else
        -- Contract double for normal offline runs; the optional source run below
        -- executes the installed BC getter, index resolver and button customizer.
        backend = {getEffective = function(obj, username, ci)
            local index = math.max(0, math.floor(tonumber(ci) or 0))
            local customize = obj.md.BetterContainers and obj.md.BetterContainers.customize or {}
            local user = customize[username] or customize._global
            return copy(user and (index == 0 and user or user.containers and user.containers[index]))
        end}
        customizer = {captureBaseVisuals = function(button)
            button.base = {name = button.name, tooltip = button.tooltip, image = button.image}
        end, applyToButton = function(button, page, obj, selected)
            local payload = backend.getEffective(obj, 'survivor', button.ci)
            if not payload then return end
            button.name, button.tooltip = payload.name or button.base.name, payload.name or button.base.tooltip
            button.image = payload.icon and payload.icon.value or button.base.image
            if not selected and payload.color then button.backgroundColor = copy(payload.color) end
        end}
    end
    local original = backend.getEffective
    backend.getEffective = function(obj, username, ci, ...)
        w.calls, w.arguments = w.calls + 1, {obj, username, ci, ...}
        return original(obj, username, ci), nil, 'native-third'
    end
    w.original, w.backend = backend.getEffective, backend
    function w.object(types, links)
        local obj = {kind = 'IsoObject', md = {links = links, BetterContainers = {customize = {
            survivor = {name = 'Saved local', icon = {kind = 'item', value = 'Base.Axe'}, color = {r = 0.9, g = 0.1, b = 0.1, a = 1}}}}}}
        local containers = {}
        for index, kind in ipairs(types) do
            local ci = index - 1
            containers[index] = {kind = 'ItemContainer', getParent = function() return obj end,
                getType = function() return kind end, getDisplayType = function() return 'display' end,
                getCustomName = function() return obj.md['customName' .. ci] or 'Stale native name' end}
        end
        obj.getModData = function(self) return self.md end
        obj.getContainerCount = function() return #containers end
        obj.getContainerByIndex = function(_, ci) return containers[ci + 1] end
        return obj, containers
    end
    function w.page(rows, selected)
        local page = {rows = rows, inventory = selected, player = 0}
        function page:refreshBackpacks()
            w.refreshes = w.refreshes + 1
            self.backpacks = {}
            w.fire('OnRefreshInventoryWindowContainers', self, 'begin')
            for _, row in ipairs(self.rows) do
                local container, ci = row[1], row[2]
                local name = container:getCustomName() or getTextOrNull('IGUI_ContainerTitle_' .. container:getType())
                local button = {inventory = container, ci = ci, name = name, tooltip = name,
                    image = 'native:' .. container:getType(), backgroundColor = {r = 0, g = 0, b = 0, a = 0}}
                function button:setImage(value) self.image = value end
                function button:setBackgroundRGBA(r, g, b, a) self.backgroundColor = {r = r, g = g, b = b, a = a} end
                function button:setBackgroundColorMouseOverRGBA(r, g, b, a) self.backgroundColorMouseOver = {r = r, g = g, b = b, a = a} end
                self.backpacks[#self.backpacks + 1] = button
                if container == self.inventory then
                    self.selectedButton, self.title = button, name
                    button:setBackgroundRGBA(0.7, 0.7, 0.7, 1)
                end
            end
            -- Native assigns selectedButton/title before its end event. BC's
            -- wrapper captures vanilla base visuals and customizes after return.
            w.fire('OnRefreshInventoryWindowContainers', self, 'end')
            for _, button in ipairs(self.backpacks) do
                customizer.captureBaseVisuals(button, true)
                customizer.applyToButton(button, self, button.inventory:getParent(), self.selectedButton == button)
            end
        end
        return page
    end
    w.view = dofile(module)
    return w
end

local w = setup(true)
w.records.a = {configuration = {appearance = {name = 'Shared', icon = {kind = 'item', value = 'Base.Beans'},
    color = {r = 0.2, g = 0.3, b = 0.4, a = 1}}}}
w.records.b = {configuration = {appearance = {name = 'Second'}}}
local obj, containers = w.object({'crate', 'shelf'}, {['0'] = 'a', ['1'] = 'b'})
local other, otherContainers = w.object({'crate'}, {['0'] = 'a'})
local localObj, localContainers = w.object({'shelf'}, {})
local inventory = w.page({{containers[1], 0}, {containers[2], 1}}, containers[1])
local loot = w.page({{otherContainers[1], 0}, {localContainers[1], 0}}, localContainers[1])
getNumActivePlayers = function() return 1 end
getPlayerInventory = function() return inventory end
getPlayerLoot = function() return loot end
local before, otherBefore, localBefore = copy(obj.md), copy(other.md), copy(localObj.md)
w.change()
assert(inventory.backpacks[1].name == 'Shared' and inventory.backpacks[1].tooltip == 'Shared' and inventory.title == 'Shared')
assert(inventory.backpacks[2].name == 'Second' and loot.backpacks[1].name == 'Shared')
assert(loot.backpacks[1].image == 'Base.Beans' and loot.backpacks[1].backgroundColor.b == 0.4)
assert(same(before, obj.md) and same(otherBefore, other.md) and same(localBefore, localObj.md), 'rendering changed persisted appearance')
local calls = w.calls
local effective = w.backend.getEffective(obj, 'another-user', '1.9')
assert(effective.name == 'Second' and w.calls == calls, 'group accessor disagreed with BC index normalization or user-independent authority')
effective.name = 'mutated'
assert(w.backend.getEffective(obj, 'survivor', 1).name == 'Second', 'presentation leaked a shared draft')
local first, second, third = w.backend.getEffective(localObj, 'survivor', 0, 'extra')
assert(first.name == 'Saved local' and second == nil and third == 'native-third' and w.arguments[4] == 'extra',
    'detached/native getter arguments or multiple results changed')
w.records.a.configuration.appearance = {name = 'Shared update', icon = {kind = 'item', value = 'Base.Hammer'},
    color = {r = 0.1, g = 0.8, b = 0.2, a = 1}}
w.change()
assert(inventory.title == 'Shared update' and inventory.backpacks[1].image == 'Base.Hammer'
    and loot.backpacks[1].name == 'Shared update' and loot.backpacks[1].backgroundColor.g == 0.8,
    'shared change did not refresh open pages with live name/icon/color')
assert(same(before, obj.md) and same(otherBefore, other.md), 'shared refresh materialized data onto members')
-- Clearing group appearance suppresses stale local customization and stale native names.
w.records.a.configuration.appearance = {}
w.change()
assert(inventory.title == 'Wooden crate' and inventory.backpacks[1].name == 'Wooden crate'
    and inventory.backpacks[1].image == 'native:crate' and loot.backpacks[1].backgroundColor.a == 0,
    'empty shared appearance retained a stale native/local override')
w.records.b.configuration.appearance = {}
w.change()
assert(inventory.backpacks[2].name == 'Shelves', 'empty secondary compartment lost its own native name')
-- A detached container resumes the BC user/global policy without changing its peers.
obj.md.links['0'] = nil; obj.md.customName0 = 'Saved local'
before = copy(obj.md)
w.change()
assert(inventory.backpacks[1].name == 'Saved local' and inventory.backpacks[1].image == 'Base.Axe'
    and loot.backpacks[1].name == 'Wooden crate' and same(before, obj.md), 'detached member retained shared presentation or changed persistence')
local wrapper = w.backend.getEffective
assert(w.view.install() and dofile(module) == w.view and w.backend.getEffective == wrapper
    and #Events.OnGameStart.handlers == 1 and #Events.OnRefreshInventoryWindowContainers.handlers == 1,
    'repeat load/install duplicated the wrapper or event registration')
local refreshes = w.refreshes
w.change(); assert(w.refreshes == refreshes + 2, 'repeat load duplicated the group-change listener')
local later = function(...) return wrapper(...) end
w.backend.getEffective = later; w.view.install()
assert(w.backend.getEffective == later, 'repeat install removed a later integration wrapper')
w = setup(false)
assert(w.backend.getEffective == w.original, 'inactive BC getter was patched')
w.active = true; w.fire('OnGameStart')
assert(w.backend.getEffective ~= w.original, 'game start did not retry delayed activation')
print('Container group appearance passed: live BC name/icon/color, native names/selection, empty/default and detached fallback, pure reads and idempotent installation.'
    .. (bcRoot and ' Installed BC source exercised.' or ' BC contract doubles exercised.'))
