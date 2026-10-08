local starts, callbacks = {}, {}
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end}}
CleanUI_RegisterInventoryUiToggleCallback = function(fn) callbacks[#callbacks + 1] = fn end
getActivatedMods = function() return {contains = function(_, id) return id == 'ProximityInventory' end} end
local proximity = {isEnabled = true, isForceSelected = {}, manualContainerOverride = {}, inventoryButtonRef = {}}
require = function() return proximity end
local shift = false
Keyboard = {KEY_LSHIFT = 1, KEY_RSHIFT = 2}
isKeyDown = function(key) return shift and (key == 1 or key == 2) end
getSpecificPlayer = function() return {} end
getText = function(key) return key end
HaloTextHelper = {addText = function() end, getColorWhite = function() end}

-- Replay the installed mod's refresh policy, without loading its options/UI.
local refreshSource = ProximityInventorySource and ProximityInventorySource:gsub('\r', '')
if refreshSource then
    local begin = assert(refreshSource:find('function ProximityInventory.OnRefreshEnd(', 1, true))
    local finish = assert(refreshSource:find('\nfunction ProximityInventory.OnToggle(', begin, true))
    local env = setmetatable({ProximityInventory = proximity}, {__index = _G})
    local chunk = assert(loadstring(refreshSource:sub(begin, finish - 1)))
    setfenv(chunk, env); chunk()
    begin = assert(refreshSource:find('function ProximityInventory.OnToggleForceSelected(', 1, true))
    finish = assert(refreshSource:find('\nEvents.OnKeyPressed.Add(', begin, true))
    chunk = assert(loadstring(refreshSource:sub(begin, finish - 1)))
    setfenv(chunk, env); chunk()
else
    function proximity.OnRefreshEnd(page)
        if not proximity.isForceSelected[page.player] then return end
        local globe = proximity.inventoryButtonRef[page.player]
        if not globe then return end
        local override = proximity.manualContainerOverride[page.player]
        local target
        for _, button in ipairs(page.backpacks) do
            if button.inventory == override then target = override end
        end
        if not target then proximity.manualContainerOverride[page.player] = nil end
        target = target or globe.inventory
        page.inventory, page.inventoryPane.inventory, page.inventoryPane.lastinventory = target, target, target
        for _, button in ipairs(page.backpacks) do
            if button.inventory == target then page.selectedButton = button end
        end
        page.inventoryPane:refreshContainer()
    end
end
if not proximity.OnToggleForceSelected then
    function proximity.OnToggleForceSelected()
        proximity.isForceSelected[0] = not proximity.isForceSelected[0]
        proximity.manualContainerOverride[0] = nil
    end
end

local function container(kind, locked)
    return {getType = function() return kind end, locked = locked,
        getParent = function(self) return self.locked and self or nil end}
end
local globe, bag, other, carried = container('proxInv'), container('bag'), container('satchel'), container('schoolbag')
local function button(inventory)
    return {inventory = inventory, name = inventory:getType(), setBackgroundRGBA = function() end}
end
local function class()
    local c = {onBackpackRightMouseDown = function() end, update = function() end, dirtyUI = function() end}
    function c:onBackpackMouseDown() end
    function c:selectContainer(target)
        if target.inventory.locked then return 'rejected' end
        self.inventoryPane.inventory = target.inventory
        self.inventoryPane.lastinventory = target.inventory
        self:refreshBackpacks()
        return 'selected'
    end
    function c:selectButtonForContainer(target)
        if self.inventoryPane.inventory == target then return end
        for _, entry in ipairs(self.backpacks) do
            if entry.inventory == target then return self:selectContainer(entry) end
        end
    end
    return c
end
local native, enhanced, switched = class(), class(), class()

-- The original mod hooks whichever global class existed when it loaded.
ISInventoryPage = enhanced
local pageSource = ProximityInventoryPageSource or [[
local ProximityInventory = require('ProximityInventory/ProximityInventory')
local original = ISInventoryPage.onBackpackMouseDown
function ISInventoryPage:onBackpackMouseDown(button, x, y)
    local target = button and button.inventory
    if target and target:getType() == 'proxInv' and isKeyDown(Keyboard.KEY_LSHIFT) then
        ProximityInventory.isForceSelected[self.player] = not ProximityInventory.isForceSelected[self.player]
        ProximityInventory.manualContainerOverride[self.player] = nil
        ISInventoryPage.dirtyUI()
        return
    end
    if target and target:getType() ~= 'proxInv' and ProximityInventory.isForceSelected[self.player] then
        ProximityInventory.manualContainerOverride[self.player] = target
    end
    return original(self, button, x, y)
end
]]
assert(loadstring(pageSource))()
ISInventoryPage, CleanUI_Clean_ISInventoryPage, CleanUI_Vanilla_ISInventoryPage = native, enhanced, switched

local function page(c, character)
    local pane = {inventory = globe, lastinventory = globe, refreshContainer = function() end}
    local p = setmetatable({player = 0, onCharacter = character, inventory = globe, inventoryPane = pane,
        backpacks = {button(globe), button(bag), button(other)}}, {__index = c})
    function p:refreshBackpacks()
        local found
        for _, entry in ipairs(self.backpacks) do
            if entry.inventory == self.inventoryPane.inventory then found = entry end
        end
        local target = found or self.backpacks[1]
        self.inventory, self.inventoryPane.inventory = target.inventory, target.inventory
        self.selectedButton = target
        if proximity.isEnabled and not self.onCharacter then proximity.OnRefreshEnd(self) end
    end
    proximity.inventoryButtonRef[0] = p.backpacks[1]
    return p
end
local function reset()
    proximity.isEnabled, proximity.isForceSelected[0], proximity.manualContainerOverride[0], shift = true, true, nil, false
end

-- Assert that the regression fixture actually reproduces the installed bug.
reset()
local originalCharacter = page(enhanced, true)
proximity.manualContainerOverride[0] = bag
originalCharacter:onBackpackMouseDown(button(carried))
assert(proximity.manualContainerOverride[0] == carried, 'original Proximity mouse-down did not contaminate loot choice')
page(enhanced):refreshBackpacks()
assert(proximity.manualContainerOverride[0] == nil, 'original refresh did not reject carried bag')

if not ProximitySelectionBaseline then
    dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ProximitySelection.lua')
    for _, start in ipairs(starts) do start() end
    local installed = enhanced.selectContainer
    for _, start in ipairs(starts) do start() end
    assert(enhanced.selectContainer == installed, 'installed hooks twice')
end

local failures, checks = {}, 0
local function check(name, fn)
    reset(); checks = checks + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ': ' .. tostring(err) end
end
for _, spec in ipairs({{name = 'native', class = native}, {name = 'CleanUI', class = enhanced}, {name = 'CleanUI vanilla', class = switched}}) do
    check(spec.name .. ' real choice survives refresh', function()
        local p = page(spec.class)
        assert(p:selectContainer(p.backpacks[2]) == 'selected')
        p:refreshBackpacks()
        assert(p.inventory == bag and proximity.manualContainerOverride[0] == bag, 'globe replaced real bag')
    end)
    check(spec.name .. ' wheel/joypad globe choice', function()
        local p = page(spec.class)
        proximity.manualContainerOverride[0] = bag
        p:selectContainer(p.backpacks[1])
        assert(p.inventory == globe and proximity.manualContainerOverride[0] == nil, 'globe choice retained old bag')
    end)
    check(spec.name .. ' automatic focus preserves manual/globe', function()
        local p = page(spec.class)
        proximity.manualContainerOverride[0] = bag
        p:refreshBackpacks()
        p:selectButtonForContainer(other)
        assert(p.inventory == bag and proximity.manualContainerOverride[0] == bag, 'transfer replaced manual bag')
        proximity.manualContainerOverride[0] = nil
        p:refreshBackpacks()
        p:selectButtonForContainer(other)
        assert(p.inventory == globe and proximity.manualContainerOverride[0] == nil, 'transfer installed sticky bag')
        assert(p.toolkitAutomaticSelection == nil, 'automatic-selection guard leaked')
    end)
    check(spec.name .. ' disabled/force-off native selection', function()
        local p = page(spec.class)
        proximity.isEnabled = false
        p:selectContainer(p.backpacks[2])
        assert(p.inventory == bag and proximity.manualContainerOverride[0] == nil)
        proximity.isEnabled, proximity.isForceSelected[0] = true, false
        p:selectContainer(p.backpacks[3])
        assert(p.inventory == other and proximity.manualContainerOverride[0] == nil)
    end)
    check(spec.name .. ' unreachable fallback', function()
        local p = page(spec.class)
        p:selectContainer(p.backpacks[2])
        table.remove(p.backpacks, 2)
        p:refreshBackpacks()
        assert(p.inventory == globe and proximity.manualContainerOverride[0] == nil, 'unreachable bag stayed selected')
    end)
end
check('left bag mouse-down preserves loot target', function()
    local p = page(enhanced)
    proximity.manualContainerOverride[0] = bag
    page(enhanced, true):onBackpackMouseDown(button(carried))
    p:refreshBackpacks()
    assert(p.inventory == bag and proximity.manualContainerOverride[0] == bag, 'carried bag erased loot target')
end)
check('rejected locked mouse-down cannot install manual target', function()
    local p, locked = page(enhanced), container('crate', true)
    proximity.manualContainerOverride[0] = bag
    p:refreshBackpacks()
    local target = button(locked)
    p.backpacks[#p.backpacks + 1] = target
    p:onBackpackMouseDown(target)
    assert(proximity.manualContainerOverride[0] == bag, 'mouse-down installed locked target before validation')
    assert(p:selectContainer(target) == 'rejected')
    p:refreshBackpacks()
    assert(p.inventory == bag and proximity.manualContainerOverride[0] == bag, 'locked container became sticky')
end)
check('Shift globe force toggle clears manual choice', function()
    local p = page(enhanced)
    proximity.manualContainerOverride[0], shift = bag, true
    p:onBackpackMouseDown(p.backpacks[1])
    assert(not proximity.isForceSelected[0] and proximity.manualContainerOverride[0] == nil, 'explicit force toggle was restored')
    proximity.manualContainerOverride[0] = bag
    p:onBackpackMouseDown(p.backpacks[1])
    assert(proximity.isForceSelected[0] and proximity.manualContainerOverride[0] == nil, 'enabling force retained manual bag')
end)
check('force hotkey clears manual choice', function()
    proximity.manualContainerOverride[0] = bag
    proximity.OnToggleForceSelected()
    assert(not proximity.isForceSelected[0] and proximity.manualContainerOverride[0] == nil)
    proximity.manualContainerOverride[0] = bag
    proximity.OnToggleForceSelected()
    assert(proximity.isForceSelected[0] and proximity.manualContainerOverride[0] == nil)
end)
if not ProximitySelectionBaseline then
    check('late CleanUI mode class is installed', function()
        local late = class()
        CleanUI_Vanilla_ISInventoryPage = late
        for _, callback in ipairs(callbacks) do callback() end
        local p = page(late)
        p:selectContainer(p.backpacks[2])
        assert(p.inventory == bag and proximity.manualContainerOverride[0] == bag)
    end)
end
assert(#failures == 0, table.concat(failures, '\n'))
print('Proximity selection checks passed: ' .. checks .. ' checks, real bags, globe, transfers and CleanUI modes.')
