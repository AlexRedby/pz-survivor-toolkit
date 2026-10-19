local client = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
PZSurvivorToolkit = {}
local starts, toggle = {}, nil
Events = {}
for _, name in ipairs({'OnGameStart', 'OnFillWorldObjectContextMenu', 'OnFillInventoryObjectContextMenu'}) do
    Events[name] = {Add=function(fn) starts[name] = fn end}
end
CleanUI_RegisterInventoryUiToggleCallback = function(fn) toggle = fn end
local activeBC, allowInteract, allowLoot = false, true, true
getActivatedMods = function() return {contains=function(_, id) return activeBC and id == 'EURY_CONTAINERS' end} end
getSpecificPlayer = function(number) assert(number == 1); return 'player1' end
getText = function(key) return key end
getMouseX, getMouseY = function() return 12 end, function() return 24 end
instanceof = function(value, class) return value and (value.class == class or class == 'IsoObject' and value.world) or false end
SafeHouse = {isSafehouseAllowInteract=function() return allowInteract end}
ISLootZed, JoypadState = {cheat=false}, {players={}}
isAdmin = function() return false end
local context
local function menu()
    local m = {options={}, numOptions=1, optionPool={}}
    function m:addOption(name, target, callback, p1, p2)
        local option = {name=name,target=target,onSelect=callback,param1=p1,param2=p2,id=self.numOptions}
        self.options[#self.options+1] = option; self.numOptions = self.numOptions+1
        return option
    end
    function m:calcHeight() end
    function m:isReallyVisible() return true end
    function m:closeAll() self.closed=true end
    return m
end
ISContextMenu = {get=function() context=menu(); return context end}
getPlayerContextMenu = function(number) assert(number == 1); return context end
local itemMenuCalls = 0
ISInventoryPaneContextMenu = {createMenu=function() itemMenuCalls=itemMenuCalls+1; return context end}
local wrongRename = function() end
local function fixtureHandler(class)
    return function(button)
        local m = ISContextMenu.get()
        local inventory = button.inventory
        if inventory:getContainingItem() then return ISInventoryPaneContextMenu.createMenu() end
        if allowInteract then m:addOption('rename',inventory,class.onRenameContainer,1) end
        m:addOption('rename',inventory,wrongRename,1)
        return 'original'
    end
end
local nativeSources = {NativeInventoryPageSource, CleanUIInventoryPageSource, CleanUIVanillaInventoryPageSource}
local function pageClass(source, name)
    local class = {onRenameContainer=function() end,onBackpackClick=function() end}
    _G[name] = class
    if source then
        source = source:gsub('\r', '')
        local method = assert(source:match('(function '..name..':onBackpackRightMouseDown%(.-)\nfunction '..name..':'), name..' handler missing')
        assert(loadstring(method))()
    else
        class.onBackpackRightMouseDown = fixtureHandler(class)
    end
    return class
end
local enhanced = pageClass(nativeSources[2], 'ISInventoryPage')
local vanilla = pageClass(nativeSources[3] or nativeSources[1], nativeSources[3] and 'CleanUI_Vanilla_ISInventoryPage' or 'ISInventoryPage')
CleanUI_Clean_ISInventoryPage, CleanUI_Vanilla_ISInventoryPage, ISInventoryPage = enhanced, vanilla, enhanced
local fallbackCalls = 0
local bc = {handleCustomiserOptions=function() fallbackCalls=fallbackCalls+1 end}
local bcOptions = {enableCustomizer=true}
local loaded = {}
require = function(name)
    if name == 'PZSurvivorToolkit/ContainerAppearance' then
        if not loaded[name] then
            loaded[name] = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/' .. name .. '.lua')
        end
        return loaded[name]
    end
    if name == 'ISUI/ISWorldObjectContextMenu' then return end
    if name == 'ISUI/ISInventoryPage' then return end
    if name == 'BetterContainers/Helpers' then return {getParent=function(inventory) return inventory:getParent() end} end
    if name == 'BetterContainers/_Options' then return bcOptions end
    if name == 'BetterContainers/Customize/Customizer' then return {} end
    if name == 'BetterContainers/Customize/ContextMenu' then return bc end
    if not loaded[name] then loaded[name] = dofile(client .. name .. '.lua') end
    return loaded[name]
end
LootSorter = {DBG=function() end,canLootSquare=function() return allowLoot end,
    hasClipboardContent=function() return true end,copyDesignation=function() end,
    containerIndex=function(obj, inventory)
        for ci, value in pairs(obj.containers or {}) do if value == inventory then return ci end end
    end}
local opened
LootSorter.openPicker = function(...) opened = {...} end
dofile(client .. 'LootSorter_ContextMenu.lua')
local Menus = loaded['PZSurvivorToolkit/ContainerConfigurationMenus']
starts.OnGameStart()
local wrapped = enhanced.onBackpackRightMouseDown
starts.OnGameStart(); toggle()
assert(enhanced.onBackpackRightMouseDown == wrapped, 'installed twice')
local square = {}
local obj = {world=true,containers={},getSquare=function() return square end,getObjectIndex=function() return 2 end}
local inventory = {getContainingItem=function(self) return self.item end,getParent=function(self) return self.parent end,
    getType=function(self) return self.kind or 'crate' end,parent=obj}
obj.containers[2] = inventory
local page = {player=1,backpacks={},onBackpackClick=function() end}
local button = {inventory=inventory,parent={parent=page},mouseOver=true}
page.backpacks[1] = button
local function unifiedCount()
    local n=0
    for _, option in ipairs(context.options) do
        if option.onSelect == LootSorter.onConfigureContainer then n=n+1 end
    end
    return n
end
local function checkSupported(class)
    class.onBackpackRightMouseDown(button,0,0)
    assert(unifiedCount() == 1, 'unified action missing')
    local copies,renames=0,0
    for _, option in ipairs(context.options) do
        if option.target == inventory and (option.onSelect == enhanced.onRenameContainer
                or option.onSelect == vanilla.onRenameContainer) then renames=renames+1 end
        if option.name == 'Copy sorting' then copies=copies+1 end
        if option.onSelect == LootSorter.onConfigureContainer then
            assert(option.target == obj and option.param1 == 2 and option.param2 == 1, 'wrong target/compartment/player')
            option.onSelect(option.target,option.param1,option.param2)
        end
    end
    assert(renames == (activeBC and 0 or 1), activeBC and 'native rename editor retained'
        or 'native rename missing without appearance controls')
    assert(copies == 1 and opened[1] == obj and opened[2] == 2 and opened[3] == 1)
end
checkSupported(enhanced); ISInventoryPage=vanilla; toggle(); checkSupported(vanilla)
activeBC=true
if NativeBCPageCustomizerSource then
    -- This installer closes over the module table; replacing its method must reach existing wrappers.
    vanilla.refreshBackpacks=function() end
    local customizer = assert(loadstring(NativeBCPageCustomizerSource))()
    customizer.install()
end
Menus.install()
checkSupported(enhanced); checkSupported(vanilla)
bcOptions.enableCustomizer=false
checkSupported(vanilla)
bcOptions.enableCustomizer=true
bc.handleCustomiserOptions(page,button,{world=true})
assert(unifiedCount()==1 and fallbackCalls==0, 'BC duplicated editor or trusted its supplied parent')
LootSorter.addBoxOptions(context,obj,2,'',1)
assert(unifiedCount()==1, 'contents/world route duplicated the same target')
local wrongFound=false
for _, option in ipairs(context.options) do if option.onSelect==wrongRename then wrongFound=true end end
if not nativeSources[1] and not nativeSources[2] then assert(wrongFound, 'unrelated same-label action removed') end
for _, state in ipairs({'bag','vehicle','corpse','virtual','floor','unindexed','character','detached'}) do
    inventory.item=nil; inventory.kind=nil; inventory.parent=obj; obj.containers[2]=inventory; page.onCharacter=false
    obj.getObjectIndex=function() return 2 end
    if state=='bag' then inventory.item={}
    elseif state=='vehicle' then inventory.parent={class='BaseVehicle',world=true}
    elseif state=='corpse' then inventory.parent={class='IsoDeadBody',world=true}
    elseif state=='virtual' then inventory.parent={}
    elseif state=='floor' then inventory.kind='floor'
    elseif state=='unindexed' then obj.containers[2]=nil
    elseif state=='character' then page.onCharacter=true
    elseif state=='detached' then obj.getObjectIndex=function() return -1 end end
    local before=fallbackCalls
    bc.handleCustomiserOptions(page,button,obj)
    assert(fallbackCalls==before+1, state..' lost original BC customizer')
end
inventory.item=nil; inventory.kind=nil; inventory.parent=obj; obj.containers[2]=inventory; page.onCharacter=false
obj.getObjectIndex=function() return 2 end
inventory.item={}
local beforeItems=itemMenuCalls
vanilla.onBackpackRightMouseDown(button,0,0)
assert(itemMenuCalls==beforeItems+1 and unifiedCount()==0, 'carried bag native item menu changed')
inventory.item=nil
-- Same callback on another target is independent of this container's editor.
context=menu()
local other={}
context:addOption('rename',other,vanilla.onRenameContainer,1)
Menus.decorate(page,button)
assert(context.options[1].target==other and context.options[1].onSelect==vanilla.onRenameContainer,
    'rename for another target removed')
for _, gate in ipairs({'interact','loot'}) do
    allowInteract=gate~='interact'; allowLoot=gate~='loot'
    local before=fallbackCalls
    context=menu()
    bc.handleCustomiserOptions(page,button,obj)
    assert(unifiedCount()==0 and fallbackCalls==before, gate..' permission bypass')
end
print('PASS unified container menus, exact targets, class toggles, duplicate suppression and BC fallback')
