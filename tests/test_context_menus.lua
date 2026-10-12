local client = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
local loaded, files, writes, enabled = {}, {}, 0, true
PZSurvivorToolkit = { Settings = { contextMenus = function() return enabled end } }
local gameStart, worldFill
Events = { OnGameExit = { Add = function() end },
    OnGameStart = {Add=function(fn) gameStart=fn end},
    OnPreFillWorldObjectContextMenu = {Add=function(fn) worldFill=fn end} }
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

-- Remove only exact duplicate actions, including nested native selectors; retain every distinct target.
menu,actions=build()
local duplicate=menu:addOption(actions[1].name,actions[1].target,actions[1].onSelect,actions[1].param1)
menu.mouseOver=#menu.options
for i=1,5 do
 menu:prerender()
 local food=group(menu,'consume');assert(#food.options==2,'exact repeated button must appear once')
 Organizer.restore(menu);same(menu,{actions[1],actions[2],actions[3],actions[4],actions[5],actions[6],duplicate})
end
menu:clear()
local seen={};for _,option in ipairs(menu.optionPool) do assert(not seen[option],'option pooled twice');seen[option]=true end
for _,option in ipairs(actions) do assert(seen[option]) end;assert(seen[duplicate])

menu=ISContextMenu:new(nil);root=menu
local callback=ISInventoryPaneContextMenu.onDropItems
local item,target={},{}
local variants={
 menu:addOption('Drop',target,callback,item),
 menu:addOption('Drop',{},callback,item),
 menu:addOption('Drop',target,function() end,item),
 menu:addOption('Drop',target,callback,{}),
 menu:addOption('Drop',target,callback,item),
 menu:addOption('Drop',target,callback,item),
}
variants[5].toolTip={description='different tooltip'};variants[6].notAvailable=true
menu:prerender();local transfers=group(menu,'transfer')
assert(transfers and #transfers.options==5 and menu.options[2]==variants[3],
 'same labels with different target/callback/arguments/metadata must retain distinct actions')
Organizer.restore(menu);same(menu,variants)

menu=ISContextMenu:new(nil);root=menu
local parent=menu:addOption('Rip',target,nil);parent.toolkitOriginalOnSelect=ISInventoryPaneContextMenu.OnNewCraft
-- Explicitly mark a recognized native selector, whose contents must not receive category groups.
parent.pzstCategory,parent.pzstKey='craft','ripSelector'
local child=menu:getNew(menu);menu:addSubMenu(parent,child)
local one=child:addOption('One item',target,callback,item)
child:addOption('One item',target,callback,item)
local different=child:addOption('One item',target,callback,{})
menu:prerender();assert(#child.options==2 and child.options[1]==one and child.options[2]==different)
Organizer.restore(menu);assert(#child.options==3 and child.parent==menu)
print('PASS exact duplicate cleanup, mixed-target safety, nested selectors and repeated pool/restore cycles')

menu=ISContextMenu:new(nil);root=menu
local first=menu:addOption('Custom action',target,nil,item)
local second=menu:addOption('Custom action',target,nil,item)
setmetatable(first,{__index={onSelect=callback}})
setmetatable(second,{__index={onSelect=function() end}})
menu:prerender();assert(#menu.options==2 and menu.options[1]==first and menu.options[2]==second,
 'mod-provided metatable options must remain intact even with identical raw fields')
print('PASS metatable-based mod actions stay untouched')

-- Context-dependent purpose ordering is stable and preserves exact selections/unknown commands.
ISInventoryPaneContextMenu.onGrabItems=function() end
ISInventoryPaneContextMenu.onMoveItemsTo=function() end
ISInventoryPaneContextMenu.onRenameBag=function() end
ISWorldObjectContextMenu={onOpenCloseDoor=function() end,onWalkTo=function() end,onBurnCorpse=function() end}
ISVehicleMenu={onEnter=function() end,onWash=function() end,onMechanic=function() end}
local function ordered(kind, specs)
 local m=ISContextMenu:new(nil);root=m;m.toolkitContextKind=kind
 local rows={}
 for _,spec in ipairs(specs) do rows[#rows+1]=m:addOption(spec[1],spec[3],spec[2],spec[4]) end
 return m,rows
end
local eat,grab,rename=ISInventoryPaneContextMenu.onEatItems,ISInventoryPaneContextMenu.onGrabItems,ISInventoryPaneContextMenu.onRenameBag
menu,actions=ordered('inventory',{{'Rename',rename},{'Grab',grab},{'Eat',eat}})
menu.mouseOver=1;menu:prerender()
assert(menu.options[1]==actions[3] and menu.options[2]==actions[2] and menu.options[3]==actions[1])
assert(menu.mouseOver==3,'selection must follow the original action after sorting')
Organizer.restore(menu);same(menu,actions)
menu,actions=ordered('loot',{{'Eat',eat},{'Rename',rename},{'Grab',grab}})
menu:prerender();assert(menu.options[1]==actions[3] and menu.options[2]==actions[1] and menu.options[3]==actions[2])
Organizer.restore(menu);same(menu,actions)
menu,actions=ordered('world',{{'Burn',ISWorldObjectContextMenu.onBurnCorpse},{'Walk',ISWorldObjectContextMenu.onWalkTo},{'Open',ISWorldObjectContextMenu.onOpenCloseDoor}})
menu:prerender();assert(menu.options[1]==actions[3] and menu.options[2]==actions[2] and menu.options[3]==actions[1])
menu,actions=ordered('world',{{'Wash',ISVehicleMenu.onWash},{'Mechanics',ISVehicleMenu.onMechanic},{'Enter',ISVehicleMenu.onEnter}})
menu:prerender();assert(menu.options[1]==actions[3] and menu.options[2]==actions[2] and menu.options[3]==actions[1])

menu,actions=ordered('inventory',{{'Rename',rename},{'Unknown',function()end},{'Eat',eat,nil,1},{'Header',nil},{'Grab',grab},{'Eat',eat,nil,2}})
actions[4].isTitle=true
menu:prerender();assert(menu.options[1]==actions[3] and menu.options[2]==actions[2] and menu.options[3]==actions[1])
assert(menu.options[4]==actions[4] and menu.options[5]==actions[6] and menu.options[6]==actions[5],
 'titles are section barriers and unknown commands retain their exact slot')
menu,actions=ordered('loot',{{'Same rank A',grab,nil,1},{'Same rank B',grab,nil,2},{'Same rank C',grab,nil,3}})
menu:prerender();same(menu,actions)

Organizer.setOverride('callback:ISInventoryPaneContextMenu.onRenameBag','root')
menu,actions=ordered('inventory',{{'Rename',rename},{'Grab',grab},{'Eat',eat}})
menu:prerender();assert(menu.options[1]==actions[1] and menu.options[2]==actions[3] and menu.options[3]==actions[2],
 'manual root placements stay anchored while automatic actions sort')
Organizer.reset()

menu=ISContextMenu:new(nil);root=menu;menu.toolkitContextKind='inventory'
local parent=menu:addOption('Eat',nil,nil);parent.pzstCategory,parent.pzstKey='consume','portions'
local portions=menu:getNew(menu);menu:addSubMenu(parent,portions)
local all=portions:addOption('All',nil,eat,1);local half=portions:addOption('Half',nil,eat,.5);local quarter=portions:addOption('Quarter',nil,eat,.25)
menu:prerender();same(portions,{all,half,quarter})

ISInventoryPaneContextMenu.createMenu=function(_,carried)
 local m=ISContextMenu:new(nil);m.wasCarried=carried;return m
end
local emptyPanel=false
ISInventoryPaneContextMenu.createMenuNoItems=function(_,isLoot)
 if emptyPanel then return nil end
 return ISContextMenu:new(nil)
end
gameStart();local wrapper=ISInventoryPaneContextMenu.createMenu;gameStart();assert(wrapper==ISInventoryPaneContextMenu.createMenu)
local owned=wrapper(0,true);local loot=wrapper(0,false)
assert(owned.toolkitContextKind=='inventory' and loot.toolkitContextKind=='loot')
owned:clear();assert(owned.toolkitContextKind==nil,'pooled roots must not inherit old menu context')
assert(ISInventoryPaneContextMenu.createMenuNoItems(0,true).toolkitContextKind=='loot')
assert(ISInventoryPaneContextMenu.createMenuNoItems(0,false).toolkitContextKind=='inventory')
emptyPanel=true
assert(ISInventoryPaneContextMenu.createMenuNoItems(0,true)==nil,'native empty panel stays absent')
worldFill(0,owned);assert(owned.toolkitContextKind=='world')
print('PASS contextual priorities, stable ties, title barriers, selection identity, native selectors, manual placement and pooled context markers')
