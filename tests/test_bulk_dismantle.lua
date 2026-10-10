-- Selection and queue checks. Native crafting/MP execution is tested separately.
require = function() end
local enabled, fill, player = true
PZSurvivorToolkit = {Settings = {bulkDismantle = function() return enabled end}}
Events = {OnFillInventoryObjectContextMenu = {Add = function(fn) fill = fn end}}
ResourceType = {Item = 1}
instanceof = function(item) return item and item.id ~= nil end
getText = function(_, count) return 'Dismantle selected (' .. count .. ')' end
getTexture = function(name) return name end
getSpecificPlayer = function(index) assert(index == 1); return player end

local function list(values)
    local result = {values = values or {}}
    function result:size() return #self.values end
    function result:get(index) return self.values[index + 1] end
    function result:add(value) self.values[#self.values + 1] = value end
    function result:contains(value)
        for _, item in ipairs(self.values) do if item == value then return true end end
        return false
    end
    return result
end
ArrayList = {new = function() return list() end}

local destroy = {getResourceType = function() return 1 end,
    isKeep = function() return false end, isDestroy = function() return true end,
    getIntAmount = function() return 1 end, containsItem = function(_, script) return script.electronic end}
local keep = {getResourceType = function() return 1 end, isKeep = function() return true end}
local function recipe(name, inputs)
    return {getName = function() return name end, getInputs = function() return list(inputs or {keep, destroy}) end}
end
local simple, radio = recipe('DismantleElectronics'), recipe('DismantleElectronicsDevice')
local function item(id, container, electronic)
    local value = {id = id, container = container, script = {electronic = electronic ~= false}}
    function value:getID() return self.id end
    function value:getContainer() return self.container end
    function value:getScriptItem() return self.script end
    function value:isFavorite() return self.favorite == true end
    return value
end

local queued, returned, tool, unselected, missingTool, rejectPin, dead = {}, {}, nil
local root = {items = {}}
function root:getItemById(id) return self.items[id] end
local bag = {}
player = {getInventory = function() return root end,
    getPrimaryHandItem = function(self) return self.primary end,
    getSecondaryHandItem = function(self) return self.secondary end,
    isEquippedClothing = function(_, value) return value.worn == true end,
    isDead = function() return dead == true end}
ISInventoryPaneContextMenu = {getContainers = function(p) assert(p == player); return list({root, bag}) end,
    transferIfNeeded = function(p, value) assert(p == player); queued[#queued + 1] = {transfer = value} end}
ISCraftingUI = {ReturnItemsToOriginalContainer = function(_, values) returned = values end}
CraftRecipeManager = {getUniqueRecipeItems = function(value)
    if value.noRecipes then return nil end
    return list({false, value.radio and radio or simple, recipe('CraftMakeshiftRadio')})
end}

HandcraftLogic = {new = function()
    local logic = {}
    function logic:setContainers(containers) self.containers = containers end
    -- Deliberately choose the wrong input: the caller must override automatic selection.
    function logic:setRecipeFromContextClick(rec) self.recipe, self.target = rec, unselected end
    function logic:setManualInputsFor(input, values)
        assert(input == destroy and values:size() == 1)
        self.target = values:get(0)
        return not rejectPin
    end
    function logic:getManualInputsFor() return list({self.target}) end
    function logic:canPerformCurrentRecipe() return not missingTool and self.target.container ~= nil end
    function logic:getRecipeData()
        return {getAllInputItems = function() return list({self.target, tool}) end,
            getAllPutBackInputItems = function() return list({tool}) end}
    end
    return logic
end}
ISHandcraftAction = {FromLogic = function(logic)
    return {character = player, target = logic.target, recipe = logic.recipe, isValid = function() return true end}
end}
ISTimedActionQueue = {add = function(action) queued[#queued + 1] = action end}
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/BulkDismantle.lua')
local bulk = PZSurvivorToolkit.BulkDismantle
local a, b, c = item(1, root), item(2, bag), item(3, root)
b.radio = true
tool, unselected = item(99, bag), item(100, root)
root.items = {[1] = a, [3] = c, [100] = unselected}

local entries = bulk.entries(player, {{items = {a, a, b}}, a, {items = {c}}})
assert(#entries == 3 and entries[1].item == a and entries[2].item == b and entries[3].item == c,
    'native duplicate headers, explicit rows and CleanUI virtual rows must yield exact unique items')
assert(entries[2].recipe == radio, 'mixed electronics must use their own native recipes')
assert(bulk.queue(player, entries) == 3)
local crafts, toolTransfers, targetTransfers = {}, 0, 0
for _, action in ipairs(queued) do
    if action.transfer == tool then toolTransfers = toolTransfers + 1
    elseif action.transfer == b then targetTransfers = targetTransfers + 1
    elseif not action.transfer then crafts[#crafts + 1] = action end
end
assert(#crafts == 3 and crafts[1].target == a and crafts[2].target == b and crafts[3].target == c,
    'crafts must bind selected instances, never the automatic substitute')
assert(toolTransfers == 1 and targetTransfers == 1 and returned[1] == tool and #returned == 1,
    'bag target and shared tool must transfer once; only kept tool returns')
assert(not crafts[2]:isValidStart(), 'pre-start check rejects a selected target absent from character inventory')
b.container, root.items[2] = root, b
assert(crafts[2]:isValidStart())
for _, flag in ipairs({'favorite', 'worn'}) do
    b[flag] = true
    assert(not crafts[2]:isValidStart(), flag .. ' queued target must be protected')
    assert(#bulk.entries(player, {b}) == 0)
    b[flag] = nil
end
for _, hand in ipairs({'primary', 'secondary'}) do
    player[hand] = b
    assert(not crafts[2]:isValidStart() and #bulk.entries(player, {b}) == 0, 'held target must be protected')
    player[hand] = nil
end
root.items[2] = nil
assert(not crafts[2]:isValidStart(), 'missing exact target must not substitute another electronic')
assert(crafts[2]:isValid(), 'normal server consumption must not invalidate an executing native craft')
root.items[2] = b
missingTool = true
assert(#bulk.entries(player, {a, b}) == 0, 'missing tool must suppress the bulk menu')
missingTool, rejectPin = false, true
assert(#bulk.entries(player, {a, b}) == 0, 'rejected explicit binding must fail closed')
rejectPin = false
assert(#bulk.entries(player, {item(8, root, false)}) == 0, 'keep-only or unrelated input must not qualify')
a.noRecipes = true
assert(#bulk.entries(player, {a}) == 0, 'nil recipe list must be harmless')
a.noRecipes = nil

local menu = {options = {}}
function menu:addOption(label, target, callback, values)
    local option = {label = label, target = target, callback = callback, values = values}
    self.options[#self.options + 1] = option
    return option
end
fill(1, menu, {a})
assert(#menu.options == 0, 'single-item selection must retain only native menu')
fill(1, menu, {a, b})
assert(#menu.options == 1 and menu.options[1].label == 'Dismantle selected (2)')
a.favorite, queued = true, {}
assert(menu.options[1].callback(player, menu.options[1].values) == 1,
    'menu click must recheck changes since opening')
a.favorite, enabled, queued = nil, false, {}
fill(1, menu, {a, b})
assert(#menu.options == 1 and bulk.queue(player, entries) == nil and #queued == 0,
    'disabled feature must add no menu and refuse stale menu callbacks')
enabled, dead = true, true
fill(1, menu, {a, b})
assert(#menu.options == 1, 'dead player must have no new actions')
print('Bulk dismantle checks passed: exact/mixed selection, protected items, transfers, stale inputs and toggle.')
