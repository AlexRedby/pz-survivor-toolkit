local client = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
local loaded, files, writes, enabled = {}, {}, 0, true
PZSurvivorToolkit = { Settings = { contextMenus = function() return enabled end } }
Events = { OnGameExit = { Add = function() end } }
function getText(key) return key end
function getFileReader(name)
    if not files[name] then return nil end
    local lines = {}; for line in files[name]:gmatch('[^\n]+') do lines[#lines + 1] = line end
    local index = 0
    return { readLine = function() index = index + 1; return lines[index] end, close = function() end }
end
function getFileWriter(name)
    writes = writes + 1; files[name] = ''
    return { write = function(_, value) files[name] = files[name] .. value end, close = function() end }
end
local root
function getNumActivePlayers() return 1 end
function getPlayerContextMenu() return root end
local nextSub, map = 0, {}
ISContextMenu = {}
ISContextMenu.__index = ISContextMenu
function ISContextMenu:new(parent)
    return setmetatable({options = {}, numOptions = 1, parent = parent, player = 0, optionPool = {}}, self)
end
function ISContextMenu:getNew(parent)
    nextSub = nextSub + 1
    local menu = ISContextMenu:new(parent)
    menu.subOptionNums = nextSub; map[nextSub] = menu
    return menu
end
function ISContextMenu:getSubMenu(index) return map[index] end
function ISContextMenu:addSubMenu(option, menu) option.subOption = menu.subOptionNums end
function ISContextMenu:addOption(name, target, callback, ...)
    local option = table.remove(self.optionPool) or {}
    for key in pairs(option) do option[key] = nil end
    option.name, option.target, option.onSelect, option.id = name, target, callback, self.numOptions
    for index, param in ipairs({...}) do option['param' .. index] = param end
    self.options[#self.options + 1] = option; self.numOptions = #self.options + 1
    return option
end
function ISContextMenu:clear()
    for _, option in ipairs(self.options) do self.optionPool[#self.optionPool + 1] = option end
    self.options = {}; self.numOptions = 1
end
function ISContextMenu.displayAncestor() end
local rawAddOption = ISContextMenu.addOption
function ISContextMenu:addOptionOnTop(name, target, callback, ...)
    local option = rawAddOption(self, name, target, callback, ...)
    table.remove(self.options)
    table.insert(self.options,1,option)
    return option
end
function ISContextMenu:prerender(value) self.nativeRendered = true; return value end
function ISContextMenu:hideAndChildren() self.hidden = true end
function ISContextMenu:calcHeight() self.height = #self.options * 20 end
function ISContextMenu:calcWidth() return 100 end
function ISContextMenu:setWidth(width) self.width = width end
function ISContextMenu.onGetUpAndThen() end
ISInventoryPaneContextMenu = {}
for _, name in ipairs({'onEatItems','onDrinkFluid','onWearItems','OnPrimaryWeapon','onDropItems','onResearchRecipe'}) do
    ISInventoryPaneContextMenu[name] = function(target, item) return target, item end
end
require = function(name)
    if name == 'ISUI/ISContextMenu' or name == 'PZSurvivorToolkit/Settings' then return end
    if loaded[name] then return loaded[name] end
    loaded[name] = assert(loadfile(client .. name .. '.lua'))()
    return loaded[name]
end
local nativeMethods = {prerender=ISContextMenu.prerender, clear=ISContextMenu.clear, addOption=ISContextMenu.addOption, addOptionOnTop=ISContextMenu.addOptionOnTop}
local Organizer = require 'PZSurvivorToolkit/ContextMenus'
local function build()
    root = ISContextMenu:new(nil)
    local actions = {}
    for index, name in ipairs({'onEatItems','onDrinkFluid','onWearItems','OnPrimaryWeapon','onDropItems'}) do
        actions[index] = root:addOption(name, 'owner', ISInventoryPaneContextMenu[name], 'item-' .. index)
    end
    actions[6] = root:addOption('Read', 'foreign-target', function() return 'foreign' end)
    return root, actions
end
local function anchor(menu, category)
    for _, option in ipairs(menu.options) do
        if option.name == Organizer.groupName(category) and option.toolkitContextGroup then return option end
    end
end
local function group(menu, category)
    local option = anchor(menu, category)
    return option and menu:getSubMenu(option.subOption)
end
local function same(menu, original)
    assert(#menu.options == #original)
    for index, option in ipairs(original) do assert(menu.options[index] == option); assert(option.id == index) end
end
local menu, actions = build()
assert(menu:prerender('native-result') == 'native-result')
assert(menu.nativeRendered and #menu.options == 4)
local food, gear = group(menu, 'consume'), group(menu, 'equipment')
assert(food.options[1] == actions[1] and food.options[2] == actions[2])
assert(gear.options[1] == actions[3] and gear.options[2] == actions[4])
assert(menu.options[4] == actions[6], 'unknown mod callback with native-looking label remains visible at root')
assert(food.options[1].onSelect(food.options[1].target, food.options[1].param1) == 'owner')
local counts = nextSub
menu:prerender(); menu:prerender(); assert(nextSub == counts, 'no per-frame group allocations')
assert(writes == 0, 'discovery never writes config per frame/menu')
enabled = false; menu:prerender(); same(menu, actions)
enabled = true; menu:prerender(); assert(group(menu,'consume'))
menu:addOption('Late mod action', nil, function() end)
assert(#menu.options == 7 and menu.options[1] == actions[1], 'late native additions restore the original tree first')
menu:prerender(); assert(menu.options[#menu.options].name == 'Late mod action')
menu:clear(); assert(menu.toolkitContextState == nil and #menu.options == 0)
print('PASS automatic known categories, unknown mod actions, original callbacks, live rollback, late additions and pooled clear')

menu = ISContextMenu:new(nil); root = menu
local short = menu:addOption('Wear', nil, ISInventoryPaneContextMenu.onWearItems)
menu:addOption('Drop', nil, ISInventoryPaneContextMenu.onDropItems)
menu:prerender(); assert(#menu.options == 2 and menu.options[1] == short)
assert(Organizer.setOverride('callback:ISInventoryPaneContextMenu.onWearItems', 'equipment'))
menu:prerender(); assert(group(menu,'equipment').options[1] == short, 'explicit rules apply to short menus too')
assert(not Organizer.setOverride('key', 'unknown-category'))
Organizer.reset()
menu, actions = build()
Organizer.setOverride('callback:ISInventoryPaneContextMenu.onDropItems', 'hidden')
menu:prerender(); assert(#menu.options == 3)
Organizer.setOverride('callback:ISInventoryPaneContextMenu.onEatItems', 'root')
menu:prerender(); assert(menu.options[1] == actions[1])
Organizer.setOverride('label:Read', 'research')
menu:prerender(); assert(group(menu,'research').options[1] == actions[6])
Organizer.setOverride('label:with|pipe\nand%text', 'medical')
assert(files['PZSurvivorToolkit_ContextMenus.ini']:find('%%7C'))
loaded['PZSurvivorToolkit/ContextMenus'] = nil
assert(require('PZSurvivorToolkit/ContextMenus') == Organizer, 'duplicate load reuses service/hooks')
loaded['PZSurvivorToolkit/ContextMenus'] = nil
PZSurvivorToolkit.ContextMenus = nil
for name, callback in pairs(nativeMethods) do ISContextMenu[name] = callback end
Organizer = require 'PZSurvivorToolkit/ContextMenus'
assert(Organizer.overrides['label:with|pipe\nand%text'] == 'medical')
assert(Organizer.overrides['callback:ISInventoryPaneContextMenu.onDropItems'] == 'hidden')
Organizer.reset(); assert(next(Organizer.overrides) == nil)
print('PASS overrides, root/hidden/group, reset and reload of escaped persistent rules')

menu, actions = build()
local native = menu:getNew(menu)
local one = native:addOption('One item', 'body', function() return 'one' end, 'exact-one')
local batch = native:addOption('Selected', 'batch', function() return 'batch' end, 'exact-many')
one.toolTip = {description='original'}; one.iconTexture = 'native-icon'; one.customField='preserved'; one.index='foreign-index'
local deep = menu:getNew(native)
local battery = deep:addOption('Remove Battery', nil, function() end)
native:addSubMenu(batch,deep)
local dismantle = menu:addOption('Dismantle',nil,nil)
dismantle.toolkitBulkRecipe = 'DismantleElectronics'
menu:addSubMenu(dismantle,native)
local second = menu:addOption('Radio',nil,nil); second.pzstCategory='electronics';second.pzstKey='radio'
menu:prerender()
local devices = group(menu,'electronics')
assert(devices and devices.options[1] == dismantle)
assert(menu:getSubMenu(dismantle.subOption) == native and native.parent == devices)
assert(native.options[1] == one and native.options[2] == batch)
assert(one.toolTip.description == 'original' and one.iconTexture == 'native-icon' and one.customField == 'preserved')
assert(menu:getSubMenu(batch.subOption) == deep and deep.options[1] == battery and deep.parent == native)
local back = native:addOptionOnTop('Devices', native, ISContextMenu.displayAncestor, devices)
back.isDefaultOption = true; native.addedDefaultOptions = true
local deepBack = deep:addOptionOnTop('Devices', deep, ISContextMenu.displayAncestor, devices)
deepBack.isDefaultOption = true; deep.addedDefaultOptions = true
assert(menu.toolkitContextState, 'native ancestor rows do not restore the organized tree')
Organizer.restore(menu); assert(native.parent == menu and native.addedDefaultOptions == false)
assert(deep.addedDefaultOptions == false and #deep.options == 1 and deep.options[1] == battery,
    'restoring a recognized branch must remove stale ancestor rows from its third-level descendants')
assert(deep.parent == native and battery.onSelect,
    'refreshing descendant ancestors must retain original submenu links and action callbacks')
assert(one.index == 'foreign-index')
for _, groupMenu in ipairs({devices}) do
    assert(#groupMenu.options == 0)
    groupMenu:clear()
    local created = groupMenu:addOption('Next pooled use', nil, function() end)
    assert(created ~= dismantle and created ~= second and one.param1 == 'exact-one')
end
assert(native.options[1] == one and one.onSelect('body') == 'one')
print('PASS original nested selectors, third-level actions, parent links and arbitrary option metadata')

menu, actions = build()
local originalGetNew = menu.getNew
local calls = 0
menu.getNew = function(self,parent)
    calls = calls + 1
    if calls == 2 then error('allocation failure') end
    return originalGetNew(self,parent)
end
menu:prerender(); same(menu,actions)
assert(menu.toolkitContextState == nil and menu.nativeRendered, 'failed grouping leaves native rendering usable')
print('PASS partial grouping failure restores every native action')
print('Context menu organization checks passed (actual classifier, menu/file boundaries are doubles).')

menu, actions = build();menu.mouseOver=2;menu:prerender()
assert(menu.mouseOver==1 and menu.options[1].toolkitContextGroup,'joypad selection follows its action into the group')
Organizer.restore(menu);assert(menu.mouseOver==1 and menu.options[1]==actions[1])
local parent=ISContextMenu:new(nil);root=parent
local header=parent:addOption('Unknown item header',nil,nil)
local child=parent:getNew(parent);parent:addSubMenu(header,child)
for _, name in ipairs({'onEatItems','onDrinkFluid','onWearItems','OnPrimaryWeapon','onDropItems'})do child:addOption(name,nil,ISInventoryPaneContextMenu[name])end
parent:prerender();assert(group(child,'consume'))
child:clear();assert(parent.toolkitContextState==nil and #child.options==0)
child:addOption('Replacement',nil,function()end);parent:prerender()
assert(#child.options==1 and child.options[1].name=='Replacement','late submenu rebuild never resurrects pooled actions')
print('PASS joypad selection and dynamic native submenu clear/rebuild')
