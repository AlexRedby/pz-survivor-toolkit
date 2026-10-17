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
    for index = 1, select('#', ...) do option['param' .. index] = select(index, ...) end
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

-- Prefer the richer cooking/search routes only while their actual replacements are in this menu.
local translations={ContextMenu_Fluid='Fluid',ContextMenu_More='More'}
getText=function(key) return translations[key] or key end
local sources={}
getFilenameOfClosure=function(callback) return sources[callback] or 'foreign.lua' end
local tagsEnabled=true
PZSurvivorToolkit.Settings.itemTags=function() return tagsEnabled end
instanceof=function(item,kind) return type(item)=='table' and item.kind==kind end
PJCK_CookingUI={OnOpenPanel=function() end}
NC_InventorySearch={searchAsInput=function() end,searchAsOutput=function() end}
ISEntityUI={OpenHandcraftWindow=function() end}
for _,name in ipairs({'onAddItemInEvoRecipe','OnNewCraft','onPlaceItemOnGround','onFavorite','onUnwanted','onNoRecipes','OnSecondWeapon','OnTwoHandsEquip'}) do
 ISInventoryPaneContextMenu[name]=function() end
end
local controller,buttonVisible=false,true
local container={}
ISInventoryWindowControlHandler_LootSorterDistribute={}
local controls={getIsVisible=function() return true end,handlers={}}
controls.handlers[ISInventoryWindowControlHandler_LootSorterDistribute]={container=container,control={getIsVisible=function() return buttonVisible end}}
local page={controlsUI=controls,inventoryPane={inventory=container},getIsVisible=function() return true end}
getSpecificPlayer=function() return {getJoypadBind=function() return controller and 0 or -1 end} end
getPlayerInventory=function() return page end
local pot={getFullType=function() return 'Base.Pot' end}
local function potMenu(withCook,withInput,ingredient)
 local m=ISContextMenu:new(nil);root=m;m.toolkitContextKind='inventory'
 local o={}
 if withCook then o.cook=m:addOption('Cooking',{},PJCK_CookingUI.OnOpenPanel,pot) end
 m:addOption('Primary',nil,ISInventoryPaneContextMenu.OnPrimaryWeapon)
 m:addOption('Secondary',nil,ISInventoryPaneContextMenu.OnSecondWeapon)
 o.fluid=m:addOption('Fluid',nil,nil);local fluids=m:getNew(m);m:addSubMenu(o.fluid,fluids)
 fluids:addOption('Info',nil,function() end);fluids:addOption('Transfer',nil,function() end)
 o.native=m:addOption('Recipes',{},ISEntityUI.OpenHandcraftWindow,nil,'*',false,nil,'!Base.Pot')
 o.recipe=m:addOption('Soup',nil,nil);o.ingredients=m:getNew(m);m:addSubMenu(o.recipe,o.ingredients)
 for i=1,6 do o.ingredients:addOption('Ingredient '..i,{},ISInventoryPaneContextMenu.onAddItemInEvoRecipe,pot,ingredient or {kind='Food'},0) end
 o.place=m:addOption('Place',nil,ISInventoryPaneContextMenu.onPlaceItemOnGround)
 o.more=m:addOption('More',nil,nil);o.misc=m:getNew(m);m:addSubMenu(o.more,o.misc)
 for _,name in ipairs({'onFavorite','onUnwanted','onNoRecipes'}) do o.misc:addOption(name,pot,ISInventoryPaneContextMenu[name]) end
 o.category=m:addOption('Change category',nil,function() end);sources[o.category.onSelect]='/mods/BetterContainers/Categorize.lua'
 o.pin=m:addOption('Pin type',nil,function() end);sources[o.pin.onSelect]='C:\\mods\\BetterContainers\\Upgrades\\PinnedItems.lua'
 o.search=m:addOption('Recipe search',pot,nil);local search=m:getNew(m);m:addSubMenu(o.search,search)
 if withInput then search:addOption('Uses',pot,NC_InventorySearch.searchAsInput,0) end
 search:addOption('Makes',pot,NC_InventorySearch.searchAsOutput,0)
 o.wishlist=m:addOption('Wishlist',nil,function() end)
 sources[o.wishlist.onSelect]='/mods/PZSurvivorWishlist/Inventory.lua'
 o.distribute=m:addOption('Distribute Loot',nil,function() end);sources[o.distribute.onSelect]='/mods/LootSorter_ContextMenu.lua'
 o.drop=m:addOption('Drop',nil,ISInventoryPaneContextMenu.onDropItems)
 o.original={unpack(m.options)};o.originalMisc={unpack(o.misc.options)}
 return m,o
end
local function contains(m,option)
 for _,row in ipairs(m.options) do if row==option then return true end end
 return false
end
local function moreGroup(m)
 for _,row in ipairs(m.options) do if row.toolkitContextGroup and row.name=='More' then return m:getSubMenu(row.subOption) end end
end
menu,actions=potMenu(true,true)
for i=1,5 do
 menu:prerender()
 assert(not contains(menu,actions.recipe) and not contains(menu,actions.native), 'covered cooking and input-search paths must disappear, not move into another group')
 assert(not contains(menu,actions.distribute),'mouse distribution uses the visible toolbar button')
 assert(contains(menu,actions.cook) and contains(menu,actions.fluid))
 assert(contains(menu,actions.drop) and contains(menu,actions.place) and not group(menu,'transfer'),'fluid, drop and placement must not gain an extra transfer group')
 local misc=assert(moreGroup(menu));assert(#misc.options==6 and not contains(misc,actions.category) and contains(misc,actions.pin))
 assert(contains(misc,actions.search) and contains(misc,actions.wishlist),'rare search and wishlist commands belong in More')
 assert(not contains(menu,actions.search) and not contains(menu,actions.wishlist))
 assert(#menu.options==6,'rare commands must not clutter the root')
 Organizer.restore(menu);same(menu,actions.original);same(actions.misc,actions.originalMisc)
end
menu:prerender();enabled=false;menu:prerender();same(menu,actions.original);enabled=true
menu:clear();actions.misc:clear()
local pooled={}
for _,pool in ipairs({menu.optionPool,actions.misc.optionPool}) do
 for _,row in ipairs(pool) do assert(not pooled[row],'flattened native children must only be pooled once');pooled[row]=true end
end
print('PASS preferred cooking/search routes, fluid depth, shared More group, live rollback and native option pools')

menu,actions=potMenu(false,false);menu:prerender()
assert(contains(menu,actions.recipe) and contains(menu,actions.native),'missing replacements must retain native actions')
assert(#actions.ingredients.options==6 and not group(actions.ingredients,'craft'),'native recipe selectors never get a redundant craft group')
menu,actions=potMenu(true,true,{kind='InventoryItem'});menu:prerender()
assert(contains(menu,actions.recipe),'Project Cook cannot replace non-Food scripted ingredients')
menu,actions=potMenu(true,true);actions.ingredients.options[1].param1={};menu:prerender()
assert(contains(menu,actions.recipe),'cooking another base item is not a replacement')
menu,actions=potMenu(true,true);actions.cook.notAvailable=true;menu:prerender()
assert(contains(menu,actions.recipe),'disabled preferred entry cannot replace a native action')
menu,actions=potMenu(true,true);actions.native.param5='!Base.Other';menu:prerender()
assert(contains(menu,actions.native),'search for another full type is not redundant')
for _,fallback in ipairs({'controller','hidden','absent'}) do
 controller=fallback=='controller';buttonVisible=fallback~='hidden';page.controlsUI=fallback~='absent' and controls or nil
 menu,actions=potMenu(true,true);menu:prerender();assert(contains(menu,actions.distribute),'distribution context fallback missing: '..fallback)
end
controller=false;buttonVisible=true;page.controlsUI=controls
Organizer.setOverride('label:Soup','root')
menu,actions=potMenu(true,true);menu:prerender();assert(contains(menu,actions.recipe),'manual placements override preferred routes')
Organizer.reset()
Organizer.setOverride('mod:BetterContainers.pin','root')
menu,actions=potMenu(true,true);menu:prerender();assert(contains(menu,actions.pin),'manual placement of a secondary mod control stays at root')
Organizer.reset()
menu,actions=potMenu(true,true);sources[actions.distribute.onSelect]='foreign.lua';menu:prerender()
assert(contains(menu,actions.distribute),'a foreign callback with the same label must remain available')
print('PASS missing/disabled replacements, modded ingredients, exact item identity, controller/toolbar fallbacks and manual overrides')

for _,hidden in ipairs({'Cooking','Recipe search','Uses'}) do
 Organizer.setOverride('label:'..hidden,'hidden')
 menu,actions=potMenu(true,true);menu:prerender()
 if hidden=='Cooking' then assert(contains(menu,actions.recipe),'hiding Project Cook must restore native cooking')
 else assert(contains(menu,actions.native),'hiding a replacement search must restore native lookup') end
 if hidden=='Uses' then
  for _,row in ipairs(menu:getSubMenu(actions.search.subOption).options) do assert(row.name~='Uses','hidden input search must remain hidden inside More') end
 end
 Organizer.reset()
end
Organizer.setOverride('label:Makes','hidden')
menu,actions=potMenu(true,true);menu:prerender()
for _,row in ipairs(menu:getSubMenu(actions.search.subOption).options) do assert(row.name~='Makes','hidden output search must remain hidden inside More') end
Organizer.reset()
menu,actions=potMenu(true,true)
local buildAction=actions.misc:addOption('Build',nil,ISEntityUI.OpenBuildWindow or function() end)
menu:prerender()
local moreCount=0
for _,row in ipairs(menu.options) do if row.name=='More' then moreCount=moreCount+1 end end
assert(moreCount==1 and contains(menu,actions.more) and contains(actions.misc,buildAction),
 'a native More branch with additional actions must stay intact without creating a second More group')
Organizer.restore(menu);assert(contains(actions.misc,buildAction))
print('PASS hidden replacement fallbacks and distinct labels for mixed native More branches')
tagsEnabled=false
menu,actions=potMenu(true,true);menu:prerender()
assert(contains(assert(moreGroup(menu)),actions.category),'BC category editing remains available without Toolkit tags')
tagsEnabled=true
Organizer.setOverride('mod:BetterContainers.category','root')
Organizer.setOverride('mod:PZSurvivorWishlist.addWanted','root')
Organizer.setOverride('label:Recipe search','root')
menu,actions=potMenu(true,true);menu:prerender()
assert(contains(menu,actions.category) and contains(menu,actions.wishlist) and contains(menu,actions.search),'manual placements still win')
Organizer.reset()
menu,actions=potMenu(true,true);sources[actions.wishlist.onSelect]='foreign.lua';menu:prerender()
assert(contains(menu,actions.wishlist),'a foreign wishlist command must not move by label')
menu,actions=potMenu(true,true)
menu:getSubMenu(actions.search.subOption):addOption('Custom search',pot,function() end)
menu:prerender();assert(contains(menu,actions.search),'mixed recipe search headers keep their original placement')
print('PASS Toolkit tag/category ownership, rare actions, exact mod callbacks and manual placement')
menu,actions=potMenu(true,true)
for _,row in ipairs(actions.ingredients.options) do row.onSelect=ISInventoryPaneContextMenu.OnNewCraft end
menu:prerender()
assert(contains(menu,actions.recipe) and #actions.ingredients.options==6 and not group(actions.ingredients,'craft'),
 'Project Cook must not replace custom crafting recipes, and native crafting selectors stay flat')
print('PASS custom crafting recipe fallback stays available without an extra category level')
menu,actions=potMenu(true,true);menu:prerender()
local handGroup
for _,row in ipairs(menu.options) do
 if row.name=='UI_PZSurvivorToolkit_context_take_in_hand' then handGroup=menu:getSubMenu(row.subOption) end
end
assert(handGroup and #handGroup.options==2,'hand-only actions need a specific label')
assert(handGroup.options[1].onSelect==ISInventoryPaneContextMenu.OnPrimaryWeapon and handGroup.options[2].onSelect==ISInventoryPaneContextMenu.OnSecondWeapon)
menu:addOption('Wear',nil,ISInventoryPaneContextMenu.onWearItems);menu:prerender()
assert(group(menu,'equipment') and #group(menu,'equipment').options==3,'mixed equipment actions keep their broader label')
print('PASS hand-only group label and unchanged mixed equipment group')

Organizer.reset()
local dropKey='callback:ISInventoryPaneContextMenu.onDropItems'
local placeKey='callback:ISInventoryPaneContextMenu.onPlaceItemOnGround'
menu,actions=potMenu(true,true);menu.toolkitContextItemType='Base.Pot';menu:prerender()
assert(#Organizer.getLayout('Base.Pot','root')==6,'editor must show the actual compact default layout')
local foundRoot=false
for _,entry in ipairs(Organizer.getEntries('Base.Pot')) do if entry.key==dropKey then foundRoot=entry.category=='root' end end
assert(foundRoot,'editor must report rendered placement, not semantic classifier category')
local custom=assert(Organizer.createGroup('Kitchen | Кухня','Base.Pot'))
assert(not Organizer.createGroup('in\nvalid'))
assert(Organizer.renameGroup('equipment','My hands','Base.Pot'))
assert(Organizer.setOverride(dropKey,custom,'Base.Pot'))
assert(Organizer.setOverride(placeKey,'hidden'))
assert(Organizer.setOrder('Base.Pot','root',{'group:'..custom,'label:Cooking'}))
menu,actions=potMenu(true,true);menu.toolkitContextItemType='Base.Pot';menu:prerender()
assert(menu.options[1].toolkitContextGroupId==custom and not contains(menu,actions.place))
local customMenu=menu:getSubMenu(menu.options[1].subOption)
assert(customMenu.options[1]==actions.drop and actions.drop.onSelect==ISInventoryPaneContextMenu.onDropItems)
local renamed=false
for _,row in ipairs(menu.options) do if row.name=='My hands' then renamed=true end end
assert(renamed,'item group rename missing')
Organizer.restore(menu);same(menu,actions.original)
menu,actions=potMenu(true,true);menu.toolkitContextItemType='Base.Hammer';menu:prerender()
assert(contains(menu,actions.drop) and not contains(menu,actions.place),'item placement leaked or global placement not inherited')
for _,row in ipairs(menu.options) do assert(row.name~='My hands','item name leaked') end
local persisted=dofile(client..'PZSurvivorToolkit/ContextMenuProfile.lua').new(require('PZSurvivorToolkit/ContextMenuRules'))
assert(persisted.getOverride(dropKey,'Base.Pot')==custom and persisted.getOverride(dropKey,'Base.Hammer')==nil)
assert(persisted.getOverride(placeKey,'Base.Pot')=='hidden' and persisted.groupName('equipment','Base.Pot')=='My hands')
assert(persisted.getOrder('Base.Pot','root')[1]=='group:'..custom and persisted.isCustomGroup(custom))
Organizer.reset('Base.Pot')
assert(Organizer.getOverride(dropKey,'Base.Pot')==nil and Organizer.getOverride(placeKey,'Base.Pot')=='hidden')
assert(Organizer.setOverride(dropKey,custom,'Base.Pot'))
assert(Organizer.deleteGroup(custom) and Organizer.getOverride(dropKey,'Base.Pot')==nil)
Organizer.reset()
menu,actions=potMenu(true,true);menu.toolkitContextItemType='Base.Pot';menu:prerender()
assert(#menu.options==6 and contains(menu,actions.drop) and contains(menu,actions.place),'full reset must restore current defaults')
for _,row in ipairs(menu.options) do assert(row.name~='My hands') end
print('PASS item rules, custom groups, renaming, order, persistence, deletion and exact defaults reset')

local anotherPot={getFullType=function() return 'Base.Pot' end}
local mixed=wrapper(0,true,{{items={pot,anotherPot}}})
assert(mixed.toolkitContextItemType=='Base.Pot','a same-type stack must use type rules')
local hammer={getFullType=function() return 'Base.Hammer' end}
mixed=wrapper(0,true,{pot,hammer})
assert(mixed.toolkitContextItemType==nil,'mixed selections must not pick an arbitrary item rule')
mixed:clear();assert(mixed.toolkitContextItemType==nil,'pooled menus must clear item scope')

menu=ISContextMenu:new(nil);root=menu;menu.toolkitContextKind='inventory'
local a=menu:addOption('A',nil,function() end)
local title=menu:addOption('Section',nil,nil);title.isTitle=true
local b=menu:addOption('B',nil,function() end)
menu:prerender()
assert(not Organizer.moveEntry('*','root','label:B',-1),'editor must not cross a native title barrier')
print('PASS item scope capture, mixed stacks and title barriers in editor ordering')
Organizer.reset()
Organizer.setOverride('label:Recipe search','hidden','Base.Pot')
menu,actions=potMenu(true,true);menu.toolkitContextItemType='Base.Pot';menu:prerender()
assert(contains(menu,actions.native),'native lookup fallback missing')
local fallbackVisible=false
for _,row in ipairs(Organizer.getLayout('Base.Pot','root')) do if row.key=='callback:ISEntityUI.OpenHandcraftWindow' then fallbackVisible=true end end
assert(fallbackVisible,'editor must show restored native fallback, not only the baseline tree')
Organizer.reset()
print('PASS editor reflects conditional fallback actions in the actual menu')
