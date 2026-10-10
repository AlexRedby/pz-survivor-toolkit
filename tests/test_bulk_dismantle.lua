-- Selection and queue checks. Native crafting/MP execution is tested separately.
require = function() end
local enabled, fill, player = true
PZSurvivorToolkit = {Settings = {bulkDismantle = function() return enabled end}}
Events = {OnFillInventoryObjectContextMenu = {Add = function(fn) fill = fn end}}
ResourceType = {Item = 1}
instanceof = function(item) return item and item.id ~= nil end
getText = function(key, count) if key=='UI_PZSurvivorToolkit_dismantle_one' then return 'One item' end;return 'Dismantle selected (' .. count .. ')' end
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
local client, rejected, done, stopped, removed = true, false, false, {}, {}
luautils = {haveToBeTransfered = function() return true end}
isClient = function() return client end
isItemTransactionRejected = function(id) assert(id == 17); return rejected end
isItemTransactionDone = function(id) assert(id == 17); return done end
removeItemTransaction = function(id, cancel) removed[#removed + 1] = {id, cancel} end
ISInventoryTransferUtil = {newInventoryTransferAction = function(p, value, source, destination)
    assert(p == player and source == value:getContainer() and destination == root)
    return {transfer = value, transactionId = 17, setOnComplete = function(self, fn) self.onCompleteFunc = fn end, stop = function(self)
        stopped[#stopped + 1] = self.transactionId
        removeItemTransaction(self.transactionId, true)
    end}
end}
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

local function newMenu()
    local menu = {options = {}}
    function menu:addOption(name, target, onSelect, ...)
        local option = {name = name, target = target, onSelect = onSelect}
        for i = 1, select('#', ...) do option['param' .. i] = select(i, ...) end
        self.options[#self.options + 1] = option
        return option
    end
    function menu:getNew() return newMenu() end
    function menu:getSubMenu(subOption) return subOption end
    function menu:addSubMenu(option, submenu) option.subOption = submenu end
    return menu
end
local nativeCalls, fallbackCalls = {}, 0
ISInventoryPaneContextMenu.OnNewCraft = function(...) nativeCalls = {...} end
local scrapIcon, nativeTooltip, nativeColor = {}, {}, {}
ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu = function(selected, context, recipes, index)
    fallbackCalls = fallbackCalls + 1
    local option = context:addOption('Native dismantle', selected, ISInventoryPaneContextMenu.OnNewCraft,
        recipes:get(0), index, false, 0.25)
    option.iconTexture, option.toolTip, option.color = scrapIcon, nativeTooltip, nativeColor
    return option
end
-- An already rejected transaction must not cancel another client's same-numbered transfer.
queued, removed, stopped = {}, {}, {}
bulk.queue(player, bulk.entries(player, {c}))
local transfer = queued[1];assert(transfer.transfer and transfer.stop and transfer.onCompleteFunc, 'guarded pickup must block native merging with an ordinary preceding transfer')
rejected = true;transfer:stop()
assert(#removed == 2 and removed[1][1] == 17 and removed[1][2] == false
    and removed[2][1] == 0 and stopped[1] == 0, 'rejected pickup needs local cleanup without network cancellation')
rejected, queued, removed, stopped = false, {}, {}, {}
bulk.queue(player, bulk.entries(player, {c}));queued[1]:stop()
assert(#removed == 1 and removed[1][1] == 17 and removed[1][2] == true
    and stopped[1] == 17, 'manual cancellation must keep the native stop path')
client, rejected, queued, removed = false, true, {}, {}
bulk.queue(player, bulk.entries(player, {c}));queued[1]:stop()
assert(#removed == 1 and removed[1][1] == 17, 'single-player stop must stay native')
client, rejected, done, queued, removed = true, true, true, {}, {}
bulk.queue(player, bulk.entries(player, {c}));queued[1]:stop()
assert(#removed == 1 and removed[1][1] == 17 and removed[1][2] == true,
    'missing local transaction must not be mistaken for an acknowledged rejection')
done, rejected = false, false

local menu = newMenu()
local original = ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu(a, menu, list({simple}), 1)
fill(1, menu, {a})
assert(#menu.options == 1 and not original.subOption, 'single selection must keep native action unchanged')
fill(1, menu, {a, c})
assert(#menu.options == 1 and not original.onSelect and original.subOption, 'reuse native row without top-level duplicate')
local single, batch = original.subOption.options[1], original.subOption.options[2]
assert(single.name == 'One item' and batch.name == 'Dismantle selected (2)')
assert(original.iconTexture == scrapIcon and single.iconTexture == scrapIcon and batch.iconTexture == scrapIcon,
    'all variants must use native recipe-result icon')
assert(single.toolTip == nativeTooltip and single.color == nativeColor)
single.onSelect(single.target, single.param1, single.param2, single.param3, single.param4)
assert(nativeCalls[1] == a and nativeCalls[2] == simple and nativeCalls[3] == 1
    and nativeCalls[4] == false and nativeCalls[5] == 0.25, 'native callback and arguments must survive')
local calls = fallbackCalls
fill(1, menu, {a, c})
assert(#menu.options == 1 and #original.subOption.options == 2 and fallbackCalls == calls,
    'repeated fill must not add another anchor or another submenu')

local mixed = newMenu()
fill(1, mixed, {a, b})
assert(#mixed.options == 1 and fallbackCalls == calls + 1, 'mixed types need a native one-item anchor')
local mixedBatch = mixed.options[1].subOption.options[2]
assert(mixedBatch.param1[1].item == a and mixedBatch.param1[2].item == b,
    'mixed native anchor retains full exact selection')

local flash1, flash2 = item(11, root), item(12, root)
root.items[11], root.items[12] = flash1, flash2
local flashlight = newMenu()
local group = flashlight:addOption('Flashlight')
local deviceMenu = newMenu();flashlight:addSubMenu(group, deviceMenu)
local battery = deviceMenu:addOption('Remove battery', flash1, ISInventoryPaneContextMenu.OnNewCraft,
    recipe('RemoveBattery'), 1, false)
local dismantle = ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu(flash1, deviceMenu, list({simple}), 1)
fill(1, flashlight, {flash1, flash2})
assert(#flashlight.options == 1 and #deviceMenu.options == 2 and battery.onSelect
    and not battery.subOption, 'battery action and native device group must stay intact')
assert(#dismantle.subOption.options == 2 and dismantle.subOption.options[2].onSelect == bulk.queue,
    'flashlight dismantle variants must work at third menu level')

local existing = newMenu()
local parent = ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu(a, existing, list({simple}), 1)
local quantity = newMenu();existing:addSubMenu(parent, quantity)
quantity:addOption('Existing choice', a, function() end)
fill(1, existing, {a, c})
assert(parent.subOption == quantity and #quantity.options == 2 and quantity.options[1].name == 'Existing choice',
    'existing crafting submenu must not be replaced')

a.favorite, queued = true, {}
assert(mixedBatch.onSelect(player, mixedBatch.param1) == 1, 'menu click must recheck selection changes')
a.favorite, enabled, queued = nil, false, {}
local disabled = newMenu()
local disabledNative = ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu(a, disabled, list({simple}), 1)
fill(1, disabled, {a, c})
assert(#disabled.options == 1 and not disabledNative.subOption and disabledNative.onSelect
    and bulk.queue(player, entries) == nil and #queued == 0, 'off keeps original native action and blocks stale bulk callback')
enabled, dead = true, true
local deadMenu = newMenu();fill(1, deadMenu, {a, b});assert(#deadMenu.options == 0)
print('Bulk dismantle checks passed: exact selection, native icons/callbacks, nested flashlight menus, transfers, safety and toggle.')
