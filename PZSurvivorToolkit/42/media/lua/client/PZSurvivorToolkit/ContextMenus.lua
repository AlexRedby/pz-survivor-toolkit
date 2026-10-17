require "ISUI/ISContextMenu"
require "PZSurvivorToolkit/Settings"
local Rules = require "PZSurvivorToolkit/ContextMenuRules"

if PZSurvivorToolkit.ContextMenus then return PZSurvivorToolkit.ContextMenus end
local Organizer = { entries = {}, overrides = {}, revision = 0 }
PZSurvivorToolkit.ContextMenus = Organizer
local file = "PZSurvivorToolkit_ContextMenus.ini"
local allowed = { root = true, hidden = true }
for _, id in ipairs(Rules.groups) do allowed[id] = true end
local busy = false

local function encode(value)
    return tostring(value):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
end
local function decode(value)
    return value:gsub("%%0A", "\n"):gsub("%%0D", "\r"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function load()
    local reader = getFileReader(file, false)
    if not reader then return end
    while true do
        local line = reader:readLine()
        if not line then break end
        local kind, key, value = line:match("^([ER])|([^|]+)|(.*)$")
        if key then
            key, value = decode(key), decode(value)
            if kind == "E" then Organizer.entries[key] = { key = key, label = value }
            elseif allowed[value] then Organizer.overrides[key] = value end
        end
    end
    reader:close()
end

function Organizer.save()
    local writer = getFileWriter(file, true, false)
    if not writer then return false end
    for key, entry in pairs(Organizer.entries) do
        writer:write("E|" .. encode(key) .. "|" .. encode(entry.label) .. "\n")
    end
    for key, id in pairs(Organizer.overrides) do
        writer:write("R|" .. encode(key) .. "|" .. encode(id) .. "\n")
    end
    writer:close()
    return true
end

function Organizer.groupName(id)
    return getText("UI_PZSurvivorToolkit_context_group_" .. id)
end

local function action(option, defaults)
    if option.isDefaultOption or option.isTitle or option.toolkitContextGroup then return nil end
    local category, key = Rules.classify(option)
    category = defaults and defaults[option] or category
    local label = tostring(option.name or option.text or "")
    if label == "" then return nil end
    key = key or "label:" .. label:gsub("%s*%(%d+%)$", "")
    local entry = Organizer.entries[key]
    if not entry or entry.label ~= label or entry.category ~= category then
        Organizer.entries[key] = { key = key, label = label, category = category }
        Organizer.revision = Organizer.revision + 1
    end
    return Organizer.overrides[key] or category, Organizer.overrides[key] ~= nil, key
end

local function finish(menu, selected)
    local index = tonumber(menu.mouseOver)
    for index, option in ipairs(menu.options) do option.id = index end
    menu.numOptions = #menu.options + 1
    menu.mouseOver = index and index > 0 and math.min(index, #menu.options) or -1
    if selected then
        for index, option in ipairs(menu.options) do if option == selected then menu.mouseOver = index; break end end
    end
    menu:calcHeight()
    menu:setWidth(menu:calcWidth())
end

local function removeAncestors(menu)
    local options = {}
    for _, option in ipairs(menu.options) do
        if option.isDefaultOption then
            if menu.optionPool then menu.optionPool[#menu.optionPool + 1] = option end
        else options[#options + 1] = option end
    end
    menu.options = options
    menu.addedDefaultOptions = false
end

local function refreshAncestors(menu, visited)
    if visited[menu] then return end
    visited[menu] = true
    local selected = menu.options[menu.mouseOver]
    removeAncestors(menu)
    finish(menu, selected)
    for _, option in ipairs(menu.options) do
        if option.subOption then
            local child = menu:getSubMenu(option.subOption)
            if child then refreshAncestors(child, visited) end
        end
    end
end

local function restore(root)
    local state = root.toolkitContextState
    if not state then return end
    for _, group in ipairs(state.groups) do group:hideAndChildren() end
    for child, parent in pairs(state.parents) do child.parent = parent end
    local visited = {}
    for child in pairs(state.parents) do refreshAncestors(child, visited) end
    for node, original in pairs(state.nodes) do
        local selected = node.options[node.mouseOver]
        selected = state.anchorOptions[selected] or selected
        removeAncestors(node)
        node.options = original
        removeAncestors(node)
        finish(node, selected)
    end
    -- Native clear pools every option: borrowed action objects must only return to their original menu.
    for _, group in ipairs(state.groups) do
        for _, option in ipairs(group.options) do
            if not state.borrowed[option] and group.optionPool then group.optionPool[#group.optionPool + 1] = option end
        end
        group.options = {}
        group.numOptions = 1
        group.addedDefaultOptions = false
    end
    for anchor, owner in pairs(state.anchors) do
        if owner.optionPool then owner.optionPool[#owner.optionPool + 1] = anchor end
    end
    root.toolkitContextState = nil
end
Organizer.restore = restore

local function sameAction(left, right)
    if getmetatable(left) or getmetatable(right)
        or not left.onSelect or left.isTitle or right.isTitle then return false end
    -- Labels alone cannot distinguish actions on different items or mod-specific metadata.
    for key, value in pairs(left) do
        if key ~= "id" and right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if key ~= "id" and left[key] ~= value then return false end
    end
    return true
end

local function sortActions(options, priorities)
    local changed, start = false, 1
    for boundary = 1, #options + 1 do
        if boundary > #options or options[boundary].isTitle then
            local slots, ordered = {}, {}
            for index = start, boundary - 1 do
                local option = options[index]
                if priorities[option] then
                    slots[#slots + 1] = index
                    ordered[#ordered + 1] = {option = option, index = index}
                end
            end
            table.sort(ordered, function(left, right)
                local a, b = priorities[left.option], priorities[right.option]
                return a < b or (a == b and left.index < right.index)
            end)
            for index, row in ipairs(ordered) do
                local slot = slots[index]
                changed = changed or options[slot] ~= row.option
                options[slot] = row.option
            end
            start = boundary + 1
        end
    end
    return changed
end

local function organizeNode(menu, state, visited, selectorsOnly, context)
    if visited[menu] or not menu.options then return end
    visited[menu] = true
    local original, unique, categories, explicit, counts, keys, priorities = {}, {}, {}, {}, {}, {}, {}
    local changed, hasTitle = false, false
    local selected = menu.options[menu.mouseOver]
    for index, option in ipairs(menu.options) do
        if not option.isDefaultOption then
            original[#original + 1] = option
            state.borrowed[option] = true
            hasTitle = hasTitle or option.isTitle
        end
    end
    state.nodes[menu] = original
    local candidates = {}
    for _, option in ipairs(original) do
        local _, manual = action(option)
        if not menu.parent and not selectorsOnly and not manual and (not context or context == "inventory" or context == "loot")
            and Rules.isMore(menu, option) then
            local child = menu:getSubMenu(option.subOption)
            local rows = {}
            for _, row in ipairs(child.options) do
                if not row.isDefaultOption then
                    rows[#rows + 1] = row
                    candidates[#candidates + 1] = row
                    state.borrowed[row] = true
                    state.anchorOptions[row] = option
                    if selected == option then selected = row end
                end
            end
            state.nodes[child] = rows
            changed = true
        else candidates[#candidates + 1] = option end
    end
    local defaults = Rules.defaults(menu, candidates, context, function(option)
        return not option.notAvailable and action(option) ~= "hidden"
    end)
    local named = {}
    for _, option in ipairs(candidates) do
        local name = option.name or false
        local matches = named[name] or {}
        named[name] = matches
        local duplicate
        for _, kept in ipairs(matches) do
            if sameAction(option, kept) then duplicate = kept; break end
        end
        if duplicate then
            changed = true
            if selected == option then selected = duplicate end
        else
            unique[#unique + 1] = option
            matches[#matches + 1] = option
        end
    end
    for _, option in ipairs(unique) do
        local category, manual, key = action(option, defaults)
        keys[option] = key
        categories[option] = category
        explicit[option] = manual
        if category and category ~= "root" and category ~= "hidden" then
            counts[category] = (counts[category] or 0) + 1
        end
        -- Portion/recipe selectors already form coherent native submenus.
        if option.subOption then
            local child = menu:getSubMenu(option.subOption)
            if child then organizeNode(child, state, visited, selectorsOnly or category ~= nil or Rules.isRecipeSelector(menu, option), context) end
        end
    end
    if context ~= "inventory" and context ~= "loot" then
        for _, option in ipairs(unique) do
            if categories[option] == "vehicle" then context = "vehicle"; break end
        end
    end
    context = context or "inventory"
    for _, option in ipairs(unique) do
        if not explicit[option] then priorities[option] = Rules.priority(categories[option], keys[option], context) end
    end
    local groups, result = {}, {}
    local hasMore = false
    for _, option in ipairs(unique) do
        hasMore = hasMore or (option.name == getText("ContextMenu_More") and categories[option] ~= "hidden")
    end
    for _, option in ipairs(unique) do
        local category = categories[option]
        if not selectorsOnly and category == "hidden" then
            changed = true
        elseif not selectorsOnly and category and category ~= "root"
            and (explicit[option] or (not hasTitle and #unique >= 5 and counts[category] >= 2)) then
            local group = groups[category]
            if not group then
                group = menu:getNew(menu)
                group.toolkitContextGroupMenu = true
                state.groups[#state.groups + 1] = group
                local label = category == "world" and not hasMore and (context == "inventory" or context == "loot")
                    and getText("ContextMenu_More") or Organizer.groupName(category)
                local anchor = menu:addOption(label, nil, nil)
                anchor.toolkitContextGroup = true
                state.anchors[anchor] = menu
                state.anchorOptions[anchor] = state.anchorOptions[option] or option
                menu:addSubMenu(anchor, group)
                group.toolkitContextAnchor = anchor
                groups[category] = group
                result[#result + 1] = anchor
            end
            group.options[#group.options + 1] = option
            if explicit[option] then
                group.toolkitContextManual = true
                priorities[group.toolkitContextAnchor] = nil
            elseif not group.toolkitContextManual and priorities[option] then
                priorities[group.toolkitContextAnchor] = math.min(priorities[group.toolkitContextAnchor] or math.huge, priorities[option])
            end
            if option.subOption then
                local child = menu:getSubMenu(option.subOption)
                if child then
                    state.parents[child] = child.parent
                    child.parent = group
                    refreshAncestors(child, {})
                end
            end
            changed = true
        else
            result[#result + 1] = option
        end
    end
    if not selectorsOnly then
        changed = sortActions(result, priorities) or changed
        for _, group in pairs(groups) do sortActions(group.options, priorities) end
    end
    if changed then
        removeAncestors(menu)
        menu.options = result
        for _, group in pairs(groups) do finish(group) end
        local category = selected and categories[selected]
        finish(menu, groups[category] and groups[category].toolkitContextAnchor or selected)
    end
end

function Organizer.organize(root)
    if busy or not root or (root.parent and root.parent.options) or root.toolkitContextSkip then return end
    if not PZSurvivorToolkit.Settings.contextMenus() then restore(root); return end
    if root.toolkitContextState then return end
    busy = true
    local state = { nodes = {}, parents = {}, groups = {}, borrowed = {}, anchors = {}, anchorOptions = {} }
    root.toolkitContextState = state
    local ok, error = pcall(organizeNode, root, state, {}, false, root.toolkitContextKind)
    busy = false
    if not ok then
        restore(root)
        print("[PZSurvivorToolkit] Context menu organization failed: " .. tostring(error))
    end
end

function Organizer.settingsChanged()
    for player = 0, getNumActivePlayers() - 1 do
        local menu = getPlayerContextMenu(player)
        if menu then restore(menu); menu:hideAndChildren() end
    end
end

function Organizer.setOverride(key, category)
    if category ~= nil and not allowed[category] then return false end
    Organizer.overrides[key] = category
    Organizer.revision = Organizer.revision + 1
    Organizer.save()
    Organizer.settingsChanged()
    return true
end

function Organizer.reset()
    Organizer.overrides = {}
    Organizer.revision = Organizer.revision + 1
    Organizer.save()
    Organizer.settingsChanged()
end

function Organizer.openEditor()
    local Editor = require "PZSurvivorToolkit/ContextMenuEditor"
    return Editor.show()
end

local prerender, clear = ISContextMenu.prerender, ISContextMenu.clear
ISContextMenu.prerender = function(self, ...)
    Organizer.organize(self)
    return prerender(self, ...)
end
ISContextMenu.clear = function(self, ...)
    if not busy then
        local root = self
        while root.parent and root.parent.options do root = root.parent end
        restore(root)
    end
    self.toolkitContextState, self.toolkitContextGroupMenu, self.toolkitContextSkip, self.toolkitContextKind = nil, nil, nil, nil
    return clear(self, ...)
end
local function beforeMutation(menu)
    if busy then return end
    local root = menu
    while root.parent and root.parent.options do root = root.parent end
    restore(root)
end
for _, name in ipairs({"addOption", "addOptionOnTop", "insertOptionBefore", "insertOptionAfter", "removeLastOption", "removeOptionByName"}) do
    local native = ISContextMenu[name]
    if native then
        ISContextMenu[name] = function(self, ...)
            local ancestor = name == "addOptionOnTop" and ISContextMenu.displayAncestor
                and select(3, ...) == ISContextMenu.displayAncestor
            if not ancestor then beforeMutation(self) end
            return native(self, ...)
        end
    end
end

local function markContext(menu, kind)
    if type(menu) == "table" and menu.options then
        restore(menu)
        menu.toolkitContextKind = kind
    end
    return menu
end

Events.OnGameStart.Add(function()
    if ISInventoryPaneContextMenu.toolkitContextOrder then return end
    ISInventoryPaneContextMenu.toolkitContextOrder = true
    local createMenu, noItems = ISInventoryPaneContextMenu.createMenu, ISInventoryPaneContextMenu.createMenuNoItems
    ISInventoryPaneContextMenu.createMenu = function(player, inInventory, ...)
        return markContext(createMenu(player, inInventory, ...), inInventory and "inventory" or "loot")
    end
    -- B42 triggers the no-items event without registering an Events object for subscribers.
    ISInventoryPaneContextMenu.createMenuNoItems = function(player, isLoot, ...)
        return markContext(noItems(player, isLoot, ...), isLoot and "loot" or "inventory")
    end
end)
Events.OnPreFillWorldObjectContextMenu.Add(function(_, menu)
    menu.toolkitContextKind = "world"
end)

load()
return Organizer
