local Controls = {}
local registered, ordered, hooked = {}, {}, {}
local function pack(...) return {n = select("#", ...), ...} end

function Controls.register(id, spec)
    registered[id] = spec
    ordered = {}
    for key, value in pairs(registered) do ordered[#ordered + 1] = {id = key, spec = value} end
    table.sort(ordered, function(a, b)
        if a.spec.order ~= b.spec.order then return a.spec.order < b.spec.order end
        return a.id < b.id
    end)
end

local function refresh(panel, update)
    local changed = false
    for _, entry in ipairs(ordered) do
        local spec = entry.spec
        local state = panel.pzstCraftingControls and panel.pzstCraftingControls[entry.id]
        if state then
            local enabled = spec.enabled()
            if update and spec.update then spec.update(panel, state.button, enabled) end
            local visible = enabled and (not spec.visible or spec.visible(panel, enabled)) or false
            if state.visible ~= visible then changed = true end
            state.visible = visible
            state.button:setVisible(visible)
            if state.row then state.row:setVisible(visible, true) end
        end
    end
    return changed
end

local function create(panel, native)
    if native then
        panel.pzstCraftingControls = {}
        for _, entry in ipairs(ordered) do panel[entry.spec.field] = nil end
        if not panel.logic or not panel.logic:getRecipe() then return end
    else
        panel.pzstCraftingControls = panel.pzstCraftingControls or {}
    end
    local added = false
    for _, entry in ipairs(ordered) do
        local spec = entry.spec
        if not panel.pzstCraftingControls[entry.id] then
            local button = spec.create(panel)
            if button then
                panel[spec.field] = button
                local state = {button = button}
                panel.pzstCraftingControls[entry.id] = state
                if native then
                    state.row = panel.rootTable:addRow()
                    button[spec.rowField] = state.row
                    panel.rootTable:setElement(0, state.row:index(), button)
                else
                    panel:addChild(button)
                end
                added = true
            end
        end
    end
    refresh(panel, true)
    if native and added then panel:xuiRecalculateLayout() end
end

local function layout(panel, original, width, height, ...)
    refresh(panel, false)
    local reserve = 0
    for _, entry in ipairs(ordered) do
        local state = panel.pzstCraftingControls and panel.pzstCraftingControls[entry.id]
        if state and state.visible then reserve = reserve + state.button.height + 4 end
    end
    local contentHeight = height - reserve
    local result = pack(original(panel, width, contentHeight, ...))
    local y = contentHeight + 4
    for _, entry in ipairs(ordered) do
        local state = panel.pzstCraftingControls and panel.pzstCraftingControls[entry.id]
        if state and state.visible then
            local button = state.button
            button:setX(0); button:setY(y); button:setWidth(width)
            y = y + button.height + 4
        end
        if entry.spec.layout then entry.spec.layout(panel, width, contentHeight) end
    end
    return unpack(result, 1, result.n)
end

local function wrap(class, method, callback)
    if not class or type(class[method]) ~= "function" then return end
    hooked[class] = hooked[class] or {}
    if hooked[class][method] then return end
    hooked[class][method] = true
    local original = class[method]
    class[method] = function(panel, ...)
        return callback(panel, original, ...)
    end
end

local function after(class, method, callback)
    wrap(class, method, function(panel, original, ...)
        local result = pack(original(panel, ...))
        callback(panel)
        return unpack(result, 1, result.n)
    end)
end

function Controls.install()
    after(ISCraftRecipePanel, "createDynamicChildren", function(panel) create(panel, true) end)
    after(ISCraftRecipePanel, "prerender", function(panel)
        if refresh(panel, true) then panel:xuiRecalculateLayout() end
    end)
    after(NC_CellBaseCraft, "createChildren", function(panel) create(panel, false) end)
    wrap(NC_CellBaseCraft, "layoutChildren", layout)
    after(NC_CellBaseCraft, "prerender", function(panel)
        if refresh(panel, true) then panel:calculateLayout(panel.width, panel.height) end
    end)
end

return Controls
