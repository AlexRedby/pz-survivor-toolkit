require "ISUI/ISContextMenu"
require "PZSurvivorToolkit/Settings"
local Rules = require "PZSurvivorToolkit/ContextMenuRules"
local Duplicates = require "PZSurvivorToolkit/ContextMenuDuplicates"

if PZSurvivorToolkit.ContextMenus then return PZSurvivorToolkit.ContextMenus end
local Profile = require "PZSurvivorToolkit/ContextMenuProfile"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Organizer = Profile.new(Rules, Tags)
PZSurvivorToolkit.ContextMenus = Organizer
local busy = false
local examples, previews = {}, {}

-- Preview runs the same organizer on copied options, without allocating native UI or invoking callbacks.
local function copyMenu(source)
    local nodes, menus = {}, {}
    local methods = {}
    function methods:getNew(parent)
        local node = setmetatable({options = {}, optionPool = {}, parent = parent, player = source.player}, {__index = methods})
        nodes[#nodes + 1] = node; node.subOptionNums = #nodes
        return node
    end
    function methods:getSubMenu(index) return nodes[index] end
    function methods:addSubMenu(option, child) option.subOption = child.subOptionNums end
    function methods:addOption(name, target, callback)
        local option = {name = name, target = target, onSelect = callback}
        self.options[#self.options + 1] = option
        return option
    end
    function methods:calcHeight() end
    function methods:calcWidth() return 0 end
    function methods:setWidth() end
    function methods:hideAndChildren() end
    local function clone(menu, parent)
        if menus[menu] then return menus[menu] end
        local node = methods:getNew(parent)
        menus[menu] = node
        node.toolkitContextKind = menu.toolkitContextKind
        node.toolkitContextTagSets = menu.toolkitContextTagSets
        for _, option in ipairs(menu.options) do
            if not option.isDefaultOption then
                local copied = {}; for key, value in pairs(option) do copied[key] = value end
                if getmetatable(option) ~= nil then
                    -- Snapshot inherited fields without running a foreign __newindex on preview writes.
                    for key in ([[isDefaultOption isTitle name text notAvailable onSelect target subOption
                        pzstCategory pzstKey toolkitBulkAttachments toolkitBulkRecipe toolkitBulkUnload
                        toolkitContextGroup toolkitContextGroupId toolkitOriginalOnSelect]]):gmatch("%S+") do copied[key] = option[key] end
                    for index = 1, 10 do local key = "param" .. index; copied[key] = option[key] end
                    setmetatable(copied, {})
                end
                node.options[#node.options + 1] = copied
                if option.subOption then
                    local child = menu:getSubMenu(option.subOption)
                    copied.subOption = child and clone(child, node).subOptionNums or nil
                end
            end
        end
        return node
    end
    return clone(source)
end

local function action(option, pass, defaults, discover)
    if option.isDefaultOption or option.isTitle or option.toolkitContextGroup then return nil end
    local category, key = pass.classify(option)
    category = defaults and defaults[option] or pass.semanticDefaults[option] or category
    local label = tostring(option.name or option.text or "")
    if label == "" then return nil end
    key = key or "label:" .. label:gsub("%s*%(%d+%)$", "")
    if discover and pass.automatic then Organizer.record(pass.scope, key, label, category) end
    local override = not pass.automatic and Organizer.getOverride(key, pass.scope, pass.tagScopes) or nil
    return override or category, override ~= nil, key
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

local function menuDefaults(root, pass)
    local defaults, roots, visited = {}, {}, {}
    for _, option in ipairs(root.options) do
        if Rules.cartCorpseRole(option) == "root" then
            defaults[option] = "root"
            local _, key = pass.classify(option)
            if not option.notAvailable and (pass.automatic or Organizer.getOverride(key, pass.scope, pass.tagScopes) ~= "hidden") then
                roots[#roots + 1] = option
            end
        end
    end
    if #roots == 0 then return defaults end
    local function children(menu)
        if visited[menu] then return end; visited[menu] = true
        for _, option in ipairs(menu.options) do
            if Rules.cartCorpseRole(option) == "nested" then
                for _, alternative in ipairs(roots) do
                    if option.target == alternative.target and option.param1 == alternative.param1 then defaults[option] = "hidden"; break end
                end
            end
            if option.subOption then
                local child = menu:getSubMenu(option.subOption)
                if child then children(child) end
            end
        end
    end
    children(root)
    return defaults
end

local function organizeNode(menu, pass, visited, selectorsOnly, context, parentKey)
    local state = pass.state
    if visited[menu] or not menu.options then return end
    visited[menu] = true
    local original, categories, explicit, counts, keys, priorities = {}, {}, {}, {}, {}, {}
    local changed, hasTitle, groupable, visibleCount = false, false, {}, 0
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
        local _, manual = action(option, pass)
        if not menu.parent and not selectorsOnly and not manual and (not context or context == "inventory" or context == "loot")
            and Rules.isMore(menu, option, pass.classify) then
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
        return not option.notAvailable and action(option, pass) ~= "hidden"
    end, pass.classify)
    local unique, aliases = Duplicates.collect(candidates)
    for option, duplicate in pairs(aliases) do
        changed = true
        if selected == option then selected = duplicate end
    end
    for _, option in ipairs(unique) do
        local category, manual, key = action(option, pass, defaults, not menu.parent)
        keys[option] = key
        categories[option] = category
        explicit[option] = manual
        if category ~= "hidden" then visibleCount = visibleCount + 1 end
        groupable[option] = not menu.parent and Rules.canGroupAutomatically(menu, option, category, key, context)
        if category and category ~= "root" and category ~= "hidden" and (manual or groupable[option]) then
            counts[category] = (counts[category] or 0) + 1
        end
        -- Portion/recipe selectors already form coherent native submenus.
        if option.subOption then
            local child = menu:getSubMenu(option.subOption)
            if child then organizeNode(child, pass, visited,
                selectorsOnly or (category ~= nil and not Rules.isRecipeSearch(menu, option)) or Rules.isRecipeSelector(menu, option), context, "submenu:" .. key) end
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
        if (not selectorsOnly or explicit[option] or pass.semanticDefaults[option] == "hidden") and category == "hidden" then
            changed = true
        elseif (not selectorsOnly or explicit[option]) and category and category ~= "root"
            and (explicit[option] or (groupable[option] and not hasTitle and visibleCount >= 5 and (counts[category] or 0) >= 2 and counts[category] < visibleCount)) then
            local group = groups[category]
            if not group then
                group = menu:getNew(menu)
                group.toolkitContextGroupMenu = true
                state.groups[#state.groups + 1] = group
                local label = category == "world" and not hasMore and (context == "inventory" or context == "loot")
                    and getText("ContextMenu_More") or Organizer.defaultGroupName(category)
                if not pass.automatic and Organizer.hasGroupName(category, pass.scope, pass.tagScopes) then label = Organizer.groupName(category, pass.scope, pass.tagScopes) end
                if not pass.automatic and Organizer.isCustomGroup(category) then label = Organizer.groupName(category, pass.scope, pass.tagScopes) end
                local anchor = menu:addOption(label, nil, nil)
                anchor.toolkitContextGroup = true
                anchor.toolkitContextGroupId = category
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
    if groups.equipment then
        local handsOnly = true
        for _, option in ipairs(groups.equipment.options) do
            local method = keys[option] and keys[option]:match("^callback:ISInventoryPaneContextMenu%.(.*)$")
            if method ~= "OnPrimaryWeapon" and method ~= "OnSecondWeapon" and method ~= "OnTwoHandsEquip" then handsOnly = false; break end
        end
        if handsOnly and (pass.automatic or not Organizer.hasGroupName("equipment", pass.scope, pass.tagScopes)) then groups.equipment.toolkitContextAnchor.name = getText("UI_PZSurvivorToolkit_context_take_in_hand") end
    end
    if not selectorsOnly then
        changed = sortActions(result, priorities) or changed
        for _, group in pairs(groups) do sortActions(group.options, priorities) end
    end
    if not pass.automatic then
        local function applyOrder(options, parent)
            local ranks = {}; for index, key in ipairs(Organizer.getOrder(pass.scope, parent, pass.tagScopes)) do ranks[key] = index end
            local any = false; for _ in pairs(ranks) do any = true; break end
            if not any then return false end
            local order = {}
            for index, option in ipairs(options) do
                local key = option.toolkitContextGroupId and "group:" .. option.toolkitContextGroupId or keys[option]
                order[option] = ranks[key] or (10000 + index)
            end
            return sortActions(options, order)
        end
        changed = applyOrder(result, parentKey or "root") or changed
        for id, group in pairs(groups) do applyOrder(group.options, id) end
    end
    if changed then
        removeAncestors(menu)
        menu.options = result
        for _, group in pairs(groups) do finish(group) end
        local category = selected and categories[selected]
        finish(menu, groups[category] and groups[category].toolkitContextAnchor or selected)
    end
end

local function snapshot(root, pass)
    local layout = {root = {}}
    local function rows(menu, parent)
        for _, option in ipairs(menu.options) do
            if not option.isDefaultOption then
                local id = option.toolkitContextGroupId
                local _, _, key = action(option, pass)
                if option.isTitle then
                    layout[parent][#layout[parent] + 1] = {key = "title:" .. tostring(option.name), label = option.name, kind = "title", category = parent}
                elseif id then
                    layout[parent][#layout[parent] + 1] = {key = "group:" .. id, label = option.name, kind = "group", category = id}
                    layout[id] = {}; rows(menu:getSubMenu(option.subOption), id)
                elseif key then
                    layout[parent][#layout[parent] + 1] = {key = key, label = option.name, kind = "action", category = parent}
                end
            end
        end
    end
    rows(root, "root")
    return layout
end

-- Both native menus and copied previews own all organization data for one pass.
local function runPass(root, automatic, scope, tagScopes)
    local pass = {
        automatic = automatic, scope = scope, tagScopes = tagScopes, semanticDefaults = {},
        classify = Rules.newClassifier(),
        state = {nodes = {}, parents = {}, groups = {}, borrowed = {}, anchors = {}, anchorOptions = {}},
    }
    -- Attach before any traversal or native mutation so a failed pass can restore partial work.
    root.toolkitContextState = pass.state
    pass.semanticDefaults = menuDefaults(root, pass)
    organizeNode(root, pass, {}, false, root.toolkitContextKind, "root")
    return pass
end

function Organizer.organize(root)
    if busy or not root or (root.parent and root.parent.options) or root.toolkitContextSkip then return end
    if not PZSurvivorToolkit.Settings.contextMenus() then restore(root); return end
    if root.toolkitContextState then return end
    Organizer.ensureLoaded()
    local scope = root.toolkitContextItemType or "*"
    busy = true
    local tagScopes = Tags.enabled() and Organizer.matchingTagProfiles(root.toolkitContextTagSets or {}) or {}
    root.toolkitContextTagScopes = tagScopes
    local ok, error = pcall(function()
        if scope ~= "*" then examples[scope] = copyMenu(root); previews[scope] = nil end
        local pass = runPass(root, true, scope, tagScopes)
        local layout = snapshot(root, pass)
        Organizer.captureLayout(scope, layout)
        if scope ~= "*" then Organizer.captureLayout("*", layout) end
        if Organizer.hasChanges(scope, tagScopes) then
            restore(root)
            pass = runPass(root, false, scope, tagScopes)
        end
        Organizer.captureActualLayout(scope, snapshot(root, pass))
    end)
    busy = false
    if not ok then
        restore(root)
        print("[PZSurvivorToolkit] Context menu organization failed: " .. tostring(error))
    end
end

function Organizer.renderPreview(editScope, itemType)
    local source = examples[itemType]
    if not source then return nil end
    local cached = previews[itemType]
    local tagsEnabled = Tags.enabled()
    if cached and cached.scope == editScope and cached.revision == Organizer.revision and cached.tagsEnabled == tagsEnabled then return cached.layout end
    local matches = tagsEnabled and Organizer.matchingTagProfiles(source.toolkitContextTagSets or {Organizer.typeTags[itemType] or {}}) or {}
    if Organizer.getTagProfile(editScope) then
        local found = false; for _, id in ipairs(matches) do if id == editScope then found = true; break end end
        if not found then return {} end
    end
    local wasBusy = busy
    busy = true
    local ok, layout = pcall(function()
        local menu = copyMenu(source)
        local pass = runPass(menu, false, editScope, editScope ~= "*" and matches or {})
        return snapshot(menu, pass)
    end)
    busy = wasBusy
    if not ok then error(layout) end
    previews[itemType] = {scope = editScope, revision = Organizer.revision, tagsEnabled = tagsEnabled, layout = layout}
    return layout
end

function Organizer.settingsChanged()
    for player = 0, getNumActivePlayers() - 1 do
        local menu = getPlayerContextMenu(player)
        if menu then
            local organized = menu.toolkitContextState ~= nil
            restore(menu); menu:hideAndChildren()
            if organized then Organizer.organize(menu) end
        end
    end
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
    self.toolkitContextState, self.toolkitContextGroupMenu, self.toolkitContextSkip, self.toolkitContextKind, self.toolkitContextItemType, self.toolkitContextTagScopes, self.toolkitContextTagSets = nil, nil, nil, nil, nil, nil, nil
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

local function markContext(menu, kind, items)
    if type(menu) == "table" and menu.options then
        restore(menu)
        menu.toolkitContextKind, menu.toolkitContextItemType, menu.toolkitContextTagScopes, menu.toolkitContextTagSets = kind, nil, {}, {}
        local itemType, mixed, tagSets = nil, false, {}
        for _, selection in ipairs(items or {}) do
            local selected = type(selection) == "table" and selection.items or {selection}
            for _, item in ipairs(selected) do
                if item and item.getFullType then
                    local fullType = item:getFullType()
                    if itemType and itemType ~= fullType then mixed = true end
                    itemType = fullType
                    local script = item.getScriptItem and item:getScriptItem()
                    local tags = Tags.forItem(item)
                    Organizer.rememberItem(fullType, script and script:getDisplayName() or fullType, tags)
                    tagSets[#tagSets + 1] = tags
                end
            end
        end
        menu.toolkitContextTagSets = tagSets
        if Tags.enabled() then menu.toolkitContextTagScopes = Organizer.matchingTagProfiles(tagSets) end
        if itemType and not mixed then
            menu.toolkitContextItemType, Organizer.lastItemType = itemType, itemType
        end
    end
    return menu
end

Events.OnGameStart.Add(function()
    if ISInventoryPaneContextMenu.toolkitContextOrder then return end
    ISInventoryPaneContextMenu.toolkitContextOrder = true
    local createMenu, noItems = ISInventoryPaneContextMenu.createMenu, ISInventoryPaneContextMenu.createMenuNoItems
    ISInventoryPaneContextMenu.createMenu = function(player, inInventory, items, ...)
        return markContext(createMenu(player, inInventory, items, ...), inInventory and "inventory" or "loot", items)
    end
    -- B42 triggers the no-items event without registering an Events object for subscribers.
    ISInventoryPaneContextMenu.createMenuNoItems = function(player, isLoot, ...)
        return markContext(noItems(player, isLoot, ...), isLoot and "loot" or "inventory")
    end
end)
Events.OnPreFillWorldObjectContextMenu.Add(function(_, menu)
    menu.toolkitContextKind, menu.toolkitContextItemType, menu.toolkitContextTagScopes, menu.toolkitContextTagSets = "world", nil, {}, {}
end)

return Organizer
