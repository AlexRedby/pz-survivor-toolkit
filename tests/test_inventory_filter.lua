local pickerOptions, presetMenuOptions
require = function(name)
    if name == "PZSurvivorToolkit/InventoryClasses" or name == "PZSurvivorToolkit/InventoryRows"
        or name == "PZSurvivorToolkit/InventorySearch" then
        return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua")
    end
    if name == "PZSurvivorToolkit/TagFilterPresetsMenu" then return {add=function(_,options) presetMenuOptions=options end} end
    if name == "PZSurvivorToolkit/TagRulePicker" then return {open=function(options) pickerOptions=options end} end
    if name == "PZSurvivorToolkit/TagVisuals" then
        return {get=function() return {r=0.4,g=0.8,b=0.3,texture={}} end}
    end
    if name == "PZSurvivorToolkit/ItemTagSchema" or name == "PZSurvivorToolkit/ItemTags"
        or name == "PZSurvivorToolkit/PlantingTags" then
        return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/" .. name .. ".lua")
    end
    if name == "PZSurvivorToolkit/UIStyle" then
        return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/UIStyle.lua")
    end
end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
local enabled, tagsEnabled = true, false
PZSurvivorToolkit = {Settings = {inventoryFilters = function() return enabled end, itemTags = function() return tagsEnabled end}}
local starts, toggles = {}, {}
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end}}
CleanUI_RegisterInventoryUiToggleCallback = function(fn) toggles[#toggles + 1] = fn; fn() end
getText = function(key) return key == 'IGUI_ItemCat_Tool' and 'Tools' or key end
getTextOrNull = function(key) if key == 'IGUI_ItemCat_Tool' then return 'Tools' end end
getSpecificPlayer = function() return {} end
JoypadState = {players = {}}
local function button()
    return setmetatable({}, {__index = function(_, name)
        if name == 'getHeight' then return function() return 20 end end
        if name == 'getAbsoluteX' or name == 'getAbsoluteY' then return function() return 0 end end
        return function() end
    end})
end
ISButton = {new = function(_, _, _, _, _, _, target, callback)
    local b = button(); b.target, b.callback = target, callback; return b
end}
local menu
ISContextMenu = {get = function()
    menu = {options = {}, setOptionChecked = function(_, option, checked) option.checked = checked end}
    function menu:addSubMenu(option, submenu) option.submenu=submenu end
    function menu:addOption(name, target, callback, arg)
        local option = {name = name, target = target, callback = callback, arg = arg}
        self.options[#self.options + 1] = option; return option
    end
    return menu
end}
ISContextMenu.getNew = ISContextMenu.get
local hammer, beans, screwdriver, modItem = {}, {}, {}, {}
local source, incomingSource = {}, {}
for _, item in ipairs({hammer, beans, screwdriver, modItem}) do
    item.getContainer = function() return source end
end
local function transferList(values)
    return {size=function() return #values end, get=function(_, index) return values[index+1] end,
        contains=function(_, item)
            for _, value in ipairs(values) do if value==item then return true end end
            return false
        end}
end
local sourceItems=transferList({hammer,beans,screwdriver,modItem})
source.getItems = function() return sourceItems end
local groups = {
    {cat = 'Food', name = 'beans', items = {beans, beans}, matchesSearch = false},
    {cat = 'Tool', name = 'hammer', items = {hammer, hammer}, matchesSearch = true},
    {cat = 'Tool', name = 'screwdriver', items = {screwdriver, screwdriver}, matchesSearch = false},
    {cat = 'ModCategory', name = 'mod item', items = {modItem, modItem}, matchesSearch = false}
}
for _, group in ipairs(groups) do
    for _, item in ipairs(group.items) do
        item.getDisplayCategory = function() return group.cat end
        item.getCategory = item.getDisplayCategory
        item.getName = function() return group.name end
        item.getDisplayName = item.getName
        item.getType = item.getName
        item.getUnequippedWeight = function() return 1 end
    end
end
local class = {}
ISInventoryPageTransferHandler = {
    canTransferItem = function(item) return item ~= nil end,
    transferSameType = function(page) return 'type' end,
    transferSameCategory = function(page) return 'category' end,
    moveToFloor = function(page) return 'floor' end
}
function class:restoreSelection(saved)
    for row, group in ipairs(self.itemslist) do
        if saved[group.items[1]] then self.selected[row] = group end
    end
end
function class:refreshContainer()
    local saved = self.saved or {}
    self.itemslist, self.selected = {}, {}
    for _, group in ipairs(groups) do self.itemslist[#self.itemslist + 1] = group end
    self:restoreSelection(saved)
end
function class:prerender() return 'native' end
function class:transferItemsByWeight(items, container, token) self.transferred = items; return token end
ISInventoryPane, CleanUI_Clean_ISInventoryPane, CleanUI_Vanilla_ISInventoryPane = class, class, {}
for name, fn in pairs(class) do CleanUI_Vanilla_ISInventoryPane[name] = fn end
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryFilter.lua')
starts[1]()
local wrapped = class.restoreSelection
starts[1](); toggles[1]()
assert(class.restoreSelection == wrapped, 'duplicate wrapper')
local pane = setmetatable({items = {}, saved = {[hammer] = 'group', [beans] = 'group'}, player = 0,
    collapsed = {beans=true,hammer=true,screwdriver=true,['mod item']=true,mixed=true,full=true,empty=true},
    inventory = source,
    setYScroll = function() end, mode = 'details', headerHgt = 20, addChild = function() end,
    typeHeader = {getIsVisible = function() return true end, getWidth = function() return 140 end,
        getX = function() return 200 end, getY = function() return 0 end}}, {__index = class})
pane:refreshContainer()
assert(#pane.itemslist == 4 and #pane.toolkitCategories == 3)
pane.toolkitCategory = 'Tool'
pane:refreshContainer()
assert(#pane.itemslist == 2 and pane.itemslist[1].items[1] == hammer)
assert(pane.selected[1] == groups[2] and not pane.selected[2], 'selection moved onto another item')
assert(#pane.toolkitCategories == 3, 'category choices reduced by active filter')
pane.searchMode, pane.searchText = 'name', 'hammer'
pane:refreshContainer()
assert(#pane.itemslist == 1)
assert(pane:transferItemsByWeight({beans, hammer, screwdriver}, {}, 'native result') == 'native result')
assert(#pane.transferred == 1 and pane.transferred[1] == hammer, 'bulk transfer included hidden items')
local incoming = {getContainer = function() return incomingSource end}
pane:transferItemsByWeight({incoming}, source)
assert(#pane.transferred == 1 and pane.transferred[1] == incoming, 'destination filter blocked incoming drag')
local page = {inventoryPane = pane}
getPlayerInventory = function() return page end
getPlayerLoot = function() return {inventoryPane = {inventory = incomingSource}} end
local player = {getPlayerNum = function() return 0 end}
assert(ISInventoryPageTransferHandler.transferSameType(page) == 'type')
assert(ISInventoryPageTransferHandler.transferSameCategory(page) == 'category')
assert(ISInventoryPageTransferHandler.moveToFloor(page) == 'floor')
assert(ISInventoryPageTransferHandler.canTransferItem(hammer, {}, player))
assert(not ISInventoryPageTransferHandler.canTransferItem(beans, {}, player), 'nearby/floor path included hidden item')
assert(not ISInventoryPageTransferHandler.canTransferItem(nil, {}, player))
assert(ISInventoryPageTransferHandler.canTransferItem(hammer, {}, nil), "CleanUI hover passes no player")
assert(ISInventoryPageTransferHandler.takeSameType == ISInventoryPageTransferHandler.transferSameType)
assert(ISInventoryPageTransferHandler.takeSameCategory == ISInventoryPageTransferHandler.transferSameCategory)
pane.searchText = 'missing'
pane:refreshContainer()
assert(#pane.itemslist == 0 and next(pane.selected) == nil, 'zero matches must be empty')
pane.searchMode, pane.searchText, pane.searchCategoryText = 'category', nil, 'missing'
pane:refreshContainer(); assert(#pane.itemslist == 0)
pane.searchMode, pane.searchText = 'both', 'hammer'
pane:refreshContainer(); assert(#pane.itemslist == 0)
pane.searchText, pane.searchCategoryText = nil, nil
pane.toolkitCategory = 'Tool'
pane:refreshContainer(); assert(#pane.itemslist == 2)
assert(pane:prerender() == 'native')
local b = pane.toolkitCategoryButton
b.callback(b.target, b)
assert(#menu.options == 4 and menu.options[1].name == 'UI_PZSurvivorToolkit_all_categories')
assert(menu.options[4].name == 'Tools' and menu.options[4].checked)
pane.firstSelect = 3
menu.options[1].callback(menu.options[1].target, menu.options[1].arg)
assert(pane.firstSelect == nil, "category changes left a stale Shift-selection row")
assert(pane.toolkitCategory == nil and #pane.itemslist == 4, 'clear did not restore all rows')
local aggregateItems=transferList({hammer,beans})
pane.inventory = {getItems = function() return aggregateItems end}
pane.toolkitCategory = 'Tool'
pane:refreshContainer()
pane:transferItemsByWeight({beans, hammer}, source)
assert(#pane.transferred == 1 and pane.transferred[1] == hammer, 'Proximity source ownership bypassed filtering')
pane.inventory = source
pane.toolkitCategory, enabled = 'Tool', false
pane:refreshContainer(); assert(#pane.itemslist == 4 and not pane.toolkitVisibleItems)
assert(#groups[1].items == 2 and groups[1].items[1] == beans, 'real inventory/group contents changed')
enabled, tagsEnabled = true, true
pane.toolkitCategory, pane.toolkitTag = nil, 'food'
pane:refreshContainer()
assert(#pane.itemslist == 1 and pane.itemslist[1] == groups[1], 'food tag filter failed')
pane:transferItemsByWeight({beans, hammer}, source)
assert(#pane.transferred == 1 and pane.transferred[1] == beans, 'tag filter transferred hidden items')
local originalCategory = groups[4].cat
groups[4].cat = 'Food'
pane:transferItemsByWeight({groups[4].items[1]}, source)
assert(#pane.transferred == 1, 'tag-only transfer ignored a newly matching category')
groups[1].cat = 'Tool'
pane:transferItemsByWeight({beans}, source)
assert(#pane.transferred == 0, 'tag-only transfer used stale visible items')
groups[1].cat, groups[4].cat = 'Food', originalCategory
pane.toolkitTag = 'electrical';pane:refreshContainer();assert(#pane.itemslist == 0)
tagsEnabled = false
pane:transferItemsByWeight({beans, hammer}, source)
assert(#pane.transferred == 2, 'disabled tags left a stale bulk transfer filter')
assert(#pane.itemslist == 4, 'tag toggle failed to restore rows')
tagsEnabled = true;pane:prerender()
assert(#pane.itemslist == 0, 'live enable ignored the selected tag')
tagsEnabled = false;pane:prerender()
assert(#pane.itemslist == 4, 'live disable kept tag-filtered rows')
assert(groups[1].cat == 'Food', 'legacy category changed')
tagsEnabled=true
pane:prerender()
local trigger=pane.toolkitCategoryButton
trigger.callback(trigger.target,trigger)
local tagMenu=assert(menu)
assert(#tagMenu.options>0 and tagMenu.options[1].iconTexture,'tag picker missing icons')
assert(tagMenu.options[1].color.g>tagMenu.options[1].color.r,'tag picker missing family color')
local foodOption
for _,option in ipairs(tagMenu.options) do if option.arg=='food' then foodOption=option end end
assert(foodOption,'food tag missing from picker')
foodOption.callback(foodOption.target,foodOption.arg)
assert(pane.toolkitTag=='food' and #pane.itemslist==1,'decorated picker changed tag filtering')
print('Inventory filter checks passed: exact categories, search, empty results, selections, bulk actions and clear.')

pane.toolkitTag, pane.toolkitTagRule = nil, {mode='all', include={'tool'}, exclude={'weapon'}}
pane:refreshContainer()
assert(#pane.itemslist == 2, 'combined all rule did not match tools')
pane.toolkitTagRule = {mode='any', include={'food', 'tool'}, exclude={'category:ModCategory'}}
pane:refreshContainer()
assert(#pane.itemslist == 3, 'combined any rule did not union tags')
pane.toolkitTagRule = {mode='all', include={}, exclude={'tool'}}
pane:refreshContainer()
assert(#pane.itemslist == 2 and pane.itemslist[1] == groups[1], 'exclude-only rule failed')
pane:transferItemsByWeight({beans, hammer}, source)
assert(#pane.transferred == 1 and pane.transferred[1] == beans, 'combined rule ignored during transfer')
local function rootMenu()
    local root
    ISContextMenu.get = function()
        root = {options={}, setOptionChecked=function(_, option, checked) option.checked=checked end}
        function root:addSubMenu(option, submenu) option.submenu=submenu end
        function root:addOption(name,target,callback,arg)
            local option={name=name,target=target,callback=callback,arg=arg};self.options[#self.options+1]=option;return option
        end
        return root
    end
    pane.toolkitCategoryButton.callback(pane, pane.toolkitCategoryButton)
    return root
end
local root=rootMenu()
local combined
for _,option in ipairs(root.options) do if option.name=='UI_PZST_TagRule' then combined=option end end
assert(combined and combined.checked, 'combined picker entry missing')
combined.callback(combined.target)
assert(pickerOptions and #pickerOptions.categories==3 and #pickerOptions.items==4, 'preview lost hidden source items')
assert(pickerOptions.rule.exclude[1]=='tool', 'existing combined rule not passed to picker')
pickerOptions.onApply({mode='all',include={'food'},exclude={}})
assert(pane.toolkitCategory==nil and pane.toolkitTag==nil and #pane.itemslist==1, 'applying combined rule failed')
enabled=false;pane:prerender()
assert(#pane.itemslist==4 and not pane.toolkitVisibleItems, 'live filter disable left filtered rows')
enabled=true;pane:prerender()
assert(#pane.itemslist==1, 'live filter enable lost combined rule')
tagsEnabled=false;pane:prerender()
assert(#pane.itemslist==4, 'live tags disable left combined filter active')
tagsEnabled=true;pane:prerender()
assert(#pane.itemslist==1, 'live tags enable did not restore combined rule')
print('Combined inventory rule checks passed.')
-- Item Details sorts stacks after native/CleanUI refresh and restores selection again.
local refreshWithNativeRestore = class.refreshContainer
class.refreshContainer = function(self, ...)
    local result = refreshWithNativeRestore(self, ...)
    self:restoreSelection(self.saved or {})
    return result
end
groups[4].cat = 'Electronics'
pane.toolkitTagRule = {mode='all',include={'food'},exclude={}}
pane:refreshContainer()
assert(#pane.itemslist==1, 'second selection restoration changed the active filter')
assert(#pane.toolkitCategories==3 and #pane.toolkitUnfilteredRows==4,
    'Item Details second selection restoration discarded hidden categories/source rows')
root=rootMenu()
for _,option in ipairs(root.options) do if option.name=='UI_PZST_TagRule' then combined=option end end
combined.callback(combined.target)
local available={}
for _,category in ipairs(pickerOptions.categories) do available[category]=true end
assert(available.Electronics and #pickerOptions.items==4,
    'reopened combined picker lost electrical category or hidden preview items')
pickerOptions.onApply({mode='any',include={'food','electrical'},exclude={}})
assert(#pane.itemslist==2 and pane.itemslist[2]==groups[4], 'reopened any rule could not include formerly hidden category')
pickerOptions.onApply({mode='all',include={'food','electrical'},exclude={}})
assert(#pane.itemslist==0 and #pane.toolkitCategories==3 and #pane.toolkitUnfilteredRows==4,
    'empty results discarded the source universe on repeated selection restoration')
pickerOptions.onApply({mode='all',include={},exclude={}})
assert(#pane.itemslist==4, 'clear after repeated selection restoration lost inventory rows')
-- A true refresh creates a new row table, so current container changes must still be imported.
groups[4].cat='ModCategory';pane:refreshContainer()
for _,category in ipairs(pane.toolkitCategories) do assert(category.id~='Electronics','fresh refresh kept stale category choices') end
print('Repeated native/Item Details selection restoration preserves the full picker universe.')
-- A selection restore may reuse rows while filter state changes, without a rebuild.
pane.toolkitTagRule={mode='all',include={'food'},exclude={}};pane:refreshContainer()
pane.toolkitTagRule.include[1]='tool';pane:restoreSelection({})
assert(#pane.itemslist==2 and pane.itemslist[1].cat=='Tool', 'reused rows ignored changed combined rule')
pane.toolkitTagRule=nil;pane.toolkitCategory='ModCategory';pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1]==groups[4], 'reused rows ignored exact category')
pane.toolkitCategory=nil;pane.toolkitTag='food';pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1]==groups[1], 'reused rows ignored single tag')
pane.toolkitTag=nil;pane.searchMode,pane.searchText='name','missing';pane:restoreSelection({})
assert(#pane.itemslist==0, 'reused rows ignored name search')
pane.searchText='hammer';pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1]==groups[2], 'reused rows ignored changed search query')
pane.searchMode,pane.searchCategoryText='category','tools';pane:restoreSelection({})
assert(#pane.itemslist==2, 'reused rows ignored category search')
pane.searchMode='both';pane:restoreSelection({})
assert(#pane.itemslist==1, 'reused rows ignored combined search mode')
enabled=false;pane:restoreSelection({})
assert(#pane.itemslist==4 and not pane.toolkitVisibleItems, 'reused rows ignored disabled filters')
enabled=true;pane.searchText,pane.searchCategoryText=nil,nil
pane.toolkitTagRule={mode='all',include={'tool'},exclude={}};pane:restoreSelection({})
assert(#pane.itemslist==2, 'reused unfiltered rows ignored re-enabled rule')
tagsEnabled=false;pane:restoreSelection({})
assert(#pane.itemslist==4, 'reused rows ignored disabled tags')
tagsEnabled=true;pane:restoreSelection({})
assert(#pane.itemslist==2 and #pane.toolkitUnfilteredRows==4 and #pane.toolkitCategories==3,
    'reused rows lost source universe after settings/search/rule changes')
groups[3].cat='Food';pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1]==groups[2], 'second restoration ignored updated stack category')
groups[3].cat='Tool';pane:restoreSelection({})
assert(#pane.itemslist==2, 'second restoration could not recover a newly matching hidden stack')
print('Reused row tables recompute rule, exact/single category, search, stack categories and option changes.')
local function plantingItem(fullType, category, recipe)
    local item = {category=category,testItem=true}
    local script = {getFullName=function() return fullType end,
        getDisplayCategory=function() return category end,getDoubleClickRecipe=function() return recipe end}
    item.getFullType = function() return fullType end
    item.getScriptItem = function() return script end
    item.getDisplayCategory = function(self) return self.category end
    item.getCategory = item.getDisplayCategory
    item.getName = function() return 'Shared planting display name' end
    item.getDisplayName = item.getName
    item.getType = function() return fullType:match('%.(.+)$') end
    item.getUnequippedWeight = function() return 1 end
    item.getEquippedWeight = function() return 0.5 end
    item.getContainer = function() return source end
    item.isHidden = function() return false end
    item.IsFood = function() return false end
    return item
end
farming_vegetableconf={props={Sunflower={seedName='Base.SunflowerSeeds'}}}
local sunflower=plantingItem('Base.SunflowerSeeds','foodNonPerishable_candySnack')
local candy=plantingItem('Base.Candy','foodNonPerishable_candySnack')
local fullPacket=plantingItem('Base.CarrotBagSeed2','farmingSeed','OpenPacketOfSeeds')
local emptyPacket=plantingItem('Base.CarrotBagSeed2_Empty','farmingSeed')
local function javaList(values)
    return {size=function() return #values end,get=function(_,index) return values[index+1] end}
end
ScriptManager={instance={getCraftRecipe=function()
    return {getInputs=function() return javaList({{getPossibleInputItems=function() return javaList({fullPacket:getScriptItem()}) end}}) end,
        getOutputs=function() return javaList({{getPossibleResultItems=function() return javaList({emptyPacket:getScriptItem()}) end}}) end}
end}}
-- Optional source-backed integration: real native/CleanUI refresh plus our real
-- owned presentation/sort boundary, which performs the second restoreSelection call.
for _,sourceCode in ipairs({NativeInventoryPaneSource or false, CleanUIInventoryPaneSource or false}) do
    if sourceCode then
        sourceCode=sourceCode:gsub('\r','')
        local real={MAX_ITEMS_IN_STACK_TO_RENDER=50,prerender=function() end,
            transferItemsByWeight=function() end,drawItemDetails=function() end}
        local detailOptions={enableSort={getValue=function() return true end},maxSort={getValue=function() return 50 end}}
        local env=setmetatable({ISInventoryPane=real,CleanUI_Clean_ISInventoryPane=false,CleanUI_Vanilla_ISInventoryPane=false,
            CleanUI_RegisterInventoryUiToggleCallback=false,ISInventoryPageTransferHandler=false,
            ISInventoryCommonHandler_SortMenu=false,ISMouseDrag={},
            getSpecificPlayer=function() return {} end,getPlayerHotbar=function() return {} end,
            instanceof=function(value) return value and value.testItem end,
            getActivatedMods=function() return {contains=function() return false end} end,
            ISInventoryItem={renderItemIcon=function() end},ISInventoryPage=false,
            CleanUI_Clean_ISInventoryPage=false,CleanUI_Vanilla_ISInventoryPage=false}, {__index=_G})
        env._G=env
        env.CleanUI_isValidInventoryContainerReference=function(inv) return inv~=nil end
        env.CleanUI_captureSelectionAnchor=function() end
        env.CleanUI_restoreSelectionAnchor=function() end
        env.CleanUI_isWeightDataNeeded=function() return false end
        env.CleanUI_isLargeStackOptimizationEnabled=function() return false end
        env.CleanUI_shouldUseLargeStackVirtualHeader=function() return false end
        env.CleanUI_getStackDisplayItem=function(group) return group.items[1] end
        env.CleanUI_getStackActualStartIndex=function(group) return group.cleanUIFirstActualIndex or 2 end
        local starts={}
        env.Events={OnGameStart={Add=function(fn) starts[#starts+1]=fn end}}
        env.require=function(name)
            if name=='PZSurvivorToolkit/InventoryClasses' or name=='PZSurvivorToolkit/InventoryRows'
                or name=='PZSurvivorToolkit/InventoryDetailSort' or name=='PZSurvivorToolkit/InventorySearch' then
                local chunk=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua'))
                setfenv(chunk,env);return chunk()
            end
            if name=='PZSurvivorToolkit/InventoryDetailOptions' then return detailOptions end
            if name=='PZSurvivorToolkit/InventoryCapacity' then return {} end
            if name=='PZSurvivorToolkit/InventoryDetails' then return {isConditionItem=function() return false end} end
            if name=='PZSurvivorToolkit/InventoryPlantingTooltip' or name=='PZSurvivorToolkit/InventoryMediaTooltip'
                or name=='PZSurvivorToolkit/InventoryClothingTooltip' then return {install=function() end} end
            if name=='ISUI/ISInventoryPane' or name=='ISUI/ISInventoryPage' then return end
            return require(name)
        end
        for _,name in ipairs({'saveSelection','restoreSelection','refreshContainer'}) do
            local begin=assert(sourceCode:find('function ISInventoryPane:'..name..'(',1,true))
            local finish=sourceCode:find('\nfunction ISInventoryPane:',begin+1,true) or #sourceCode+1
            if name=='restoreSelection' then
                finish=sourceCode:find('\nlocal function CleanUI_captureSelectionAnchor',begin,true) or finish
            end
            local chunk=assert(loadstring(sourceCode:sub(begin,finish-1)));setfenv(chunk,env);chunk()
        end
        local function loadProduct(path)
            local chunk=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..path))
            setfenv(chunk,env);return chunk()
        end
        loadProduct('PZSurvivorToolkit/InventoryPresentation.lua')
        loadProduct('PZSurvivorToolkit/InventoryFilter.lua')
        starts[1]()
        local objects={}
        for index,spec in ipairs({{'Apple','foodPerishable_fruit'},{'Steak','foodPerishable_meat'},
            {'Battery','craftingElectrical_material'},{'Beans','foodNonPerishable_cannedJarred'}}) do
            local item={testItem=true}
            item.getName=function() return spec[1] end
            item.getDisplayName=item.getName
            item.getType=item.getName
            item.getDisplayCategory=function() return spec[2] end
            item.getCategory=item.getDisplayCategory
            item.isHidden=function() return false end
            item.IsFood=function() return false end
            item.getUnequippedWeight=function() return 1 end
            objects[index]=item
        end
        local inv={getItems=function() return {size=function() return #objects end,get=function(_,index) return objects[index+1] end} end,
            setDrawDirty=function() end}
        local noOp=function() end
        local p=setmetatable({inventory=inv,player=0,parent={onCharacter=false},items={},selected={},collapsed={},mode='details',
            itemSortFunc=function(a,b) return a.name<b.name end,
            collapseAll={setVisible=noOp},expandAll={setVisible=noOp},updateScrollbars=noOp,
            updateWorldObjectHighlight=noOp,isMouseOver=function() return false end}, {__index=real})
        p:refreshContainer()
        assert(#p.itemslist==4 and #p.toolkitCategories==4,'real refresh did not retain source categories')
        p.toolkitTagRule={mode='all',include={'food','perishable'},exclude={}};p:refreshContainer()
        assert(#p.itemslist==2 and #p.toolkitUnfilteredRows==4 and #p.toolkitCategories==4,
            'real native/Item Details refresh lost all rule or source universe')
        p.toolkitTagRule={mode='any',include={'perishable','electrical'},exclude={}};p:restoreSelection({})
        assert(#p.itemslist==3,'real rows ignored changed any rule on second restoration')
        p.toolkitTagRule={mode='all',include={'food','perishable'},exclude={'meat'}};p:refreshContainer()
        assert(#p.itemslist==1 and p.itemslist[1].items[1]==objects[1], 'real rows did not apply exclusions')
        p.toolkitTagRule={mode='all',include={'electrical'},exclude={}}
        p:restoreSelection({})
        assert(#p.itemslist==1 and p.itemslist[1].items[1]==objects[3], 'real rows lost hidden electrical item')
        p.toolkitTagRule=nil;p:refreshContainer()
        assert(#p.itemslist==4,'real refresh did not clear rule')
        objects[#objects+1],objects[#objects+2]=candy,sunflower
        p.toolkitTagRule={mode='all',include={'seed'},exclude={}};p:refreshContainer()
        assert(#p.itemslist==1 and p.itemslist[1].items[1]==sunflower and #p.itemslist[1].items==2,
            'actual native mixed stack kept candy or lost seed header/child')
        local sourceGroup=p.itemindex[sunflower:getName()]
        assert(sourceGroup~=p.itemslist[1] and #sourceGroup.items==3 and sourceGroup.items[1]==candy,
            'actual native itemindex was mutated by partial stack filtering')
        assert(p.toolkitVisibleItems[sunflower] and not p.toolkitVisibleItems[candy],
            'actual native mixed stack transfer visibility is wrong')
        p.toolkitTagRule=nil;p:restoreSelection({})
        assert(#p.itemslist==5 and #sourceGroup.items==3,'actual native rule clear lost mixed stack contents')
        p.selected={};p.toolkitTagRule={mode='all',include={'seed'},exclude={}}
        local savedGroupSelection={[candy]='group'}
        p:restoreSelection(savedGroupSelection)
        local selection=p.selected[1]
        assert(selection==sunflower or selection and selection.items and selection.items[1]==sunflower,
            'actual mixed stack lost group selection when its filtered header changed')
        assert(not savedGroupSelection[sunflower],'partial stack changed caller saved selection')
        p.selected={[1]=candy};p:refreshContainer()
        assert(next(p.selected)==nil,'actual hidden item selection moved onto a visible item')
        p.collapsed[sunflower:getName()]=false;p.selected={[2]=sunflower};p:refreshContainer()
        assert(p.selected[2]==sunflower and not p.selected[1] and not p.selected[3],
            'actual explicit child selection was lost or duplicated')
        print('Actual inventory refresh + Item Details integration passed.')
    end
end

-- Saved filters share the combined-rule path and keep current text search.
pane.toolkitCategory='Tool';pane.toolkitTagRule=nil;pane.searchMode,pane.searchText='name','hammer'
rootMenu()
assert(presetMenuOptions and presetMenuOptions.owner==pane,'saved filter menu not connected')
local savedRule={mode='all',include={'tool'},exclude={}}
presetMenuOptions.onApply(savedRule)
assert(pane.toolkitCategory==nil and pane.searchText=='hammer' and #pane.itemslist==1
    and pane.itemslist[1]==groups[2], 'saved rule did not combine with current search')
savedRule.include[1]='food'
assert(pane.toolkitTagRule.include[1]=='tool','applied saved rule aliases storage entry')
pane.searchText=nil;pane:refreshContainer()
assert(#pane.itemslist==2,'saved rule was frozen to prior search results')
print('Saved inventory filters share combined-rule application and detached rules.')

local originalGroups=groups
local mixed={name='mixed',cat='foodNonPerishable_candySnack',items={candy,candy,sunflower},
    count=3,weight=2,matchesSearch=true,equipped=true,cleanUIWeightKnown=true,cleanUIWeightText='2',
    firstItem=candy,cleanUIDisplayItem=candy,cleanUITooltipWeightKnown=true}
groups={mixed,{name='full',cat='farmingSeed',items={fullPacket,fullPacket},matchesSearch=true},
    {name='empty',cat='farmingSeed',items={emptyPacket,emptyPacket},matchesSearch=true}}
pane.itemindex={mixed=mixed}
pane.toolkitTagRule={mode='all',include={'seed'},exclude={}}
pane.saved={[sunflower]='group',[candy]='group'}
pane:refreshContainer()
local shown=pane.itemslist[1]
assert(#pane.itemslist==2 and shown~=mixed and shown.items[1]==sunflower and shown.items[2]==sunflower,
    'item seed filter contaminated same-category candy or lost a mixed-stack seed')
assert(shown.count==2 and shown.realCount==1 and shown.weight==1 and shown.equippedWeight==0.5,
    'partial stack retained unfiltered count/weight')
assert(shown.firstItem==sunflower and shown.cleanUIDisplayItem==sunflower and not shown.cleanUIWeightText
    and not shown.cleanUITooltipWeightKnown,'partial stack retained cached hidden header or weight')
assert(pane.selected[1]==shown and not pane.toolkitVisibleItems[candy] and not pane.toolkitVisibleItems[emptyPacket],
    'mixed-stack selection or item visibility included rejected items')
pane:transferItemsByWeight({candy,sunflower,fullPacket,emptyPacket},source)
assert(#pane.transferred==2 and pane.transferred[1]==sunflower and pane.transferred[2]==fullPacket,
    'seed bulk transfer included candy or empty packet')
assert(pane.itemindex.mixed==mixed and #mixed.items==3 and mixed.items[1]==candy and mixed.count==3,
    'filter modified native source stack/itemindex')
pane.toolkitTagRule={mode='all',include={'food','seed'},exclude={}};pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1].items[1]==sunflower,'item all rule lost dual food/seed role')
pane.toolkitTagRule={mode='any',include={'food','seed'},exclude={'food'}};pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1].items[1]==fullPacket,'item any/exclude rule included same-category candy')
pane.toolkitTagRule={mode='all',include={'seed'},exclude={'food'}};pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1].items[1]==fullPacket,'item exclusion kept sunflower food role')
pane.toolkitTagRule={mode='all',include={'food','seed'},exclude={'food'}};pane:restoreSelection({})
assert(#pane.itemslist==0,'contradictory item rule was not empty')
pane.toolkitTagRule=nil;pane.toolkitCategory='foodNonPerishable_candySnack';pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1]==mixed,'exact category lost baseline mixed stack')
pane.toolkitCategory=nil;pane.toolkitTag='seed';sunflower.category='medicalTreatment';pane:restoreSelection({})
assert(#pane.itemslist==2 and pane.itemslist[1].items[1]==sunflower,'live item category lost planting role')
pane.toolkitTagRule={mode='all',include={'food','seed'},exclude={}};pane.toolkitTag=nil;pane:restoreSelection({})
assert(#pane.itemslist==0,'item filter reused stale food category')
sunflower.category='foodNonPerishable_candySnack'
mixed.cleanUILargeStackOptimized,mixed.cleanUIFirstActualIndex,mixed.items=true,1,{candy,sunflower}
pane.toolkitTagRule={mode='all',include={'seed'},exclude={}};pane:restoreSelection({})
assert(#pane.itemslist[1].items==1 and pane.itemslist[1].items[1]==sunflower and pane.itemslist[1].count==2,
    'CleanUI virtual header gained a duplicate or lost matching item')
pane.toolkitTagRule=nil;pane:restoreSelection({})
assert(pane.itemslist[1]==mixed and #mixed.items==2,'clear did not restore original virtual stack')
groups={{name='sunflower',cat='foodNonPerishable_candySnack',items={sunflower,sunflower}}}
root=rootMenu()
local choices
for _,option in ipairs(root.options) do if option.name=='UI_PZST_Tags' then choices=option.submenu end end
local seedOption
for _,option in ipairs(choices.options) do if option.arg=='seed' then seedOption=option end end
assert(seedOption,'item-only seed tag missing from dropdown')
seedOption.callback(seedOption.target,seedOption.arg)
assert(#pane.itemslist==1,'item-only tag choice could not filter inventory')
groups={{name='candy',cat='foodNonPerishable_candySnack',items={candy,candy}}}
root=rootMenu()
for _,option in ipairs(root.options) do
    if option.name=='UI_PZST_Tags' then
        for _,tag in ipairs(option.submenu.options) do assert(tag.arg~='seed','candy category contaminated dropdown') end
    end
end
groups=originalGroups
print('Item-aware inventory checks passed: mixed native/virtual stacks, packet state, exact categories, dynamic rules and dropdowns.')

-- CleanUI groups equal display names before OC splits per-instance categories.
-- The cached group match may describe a different physical child than the
-- category/tag rule, so visibility must test all conditions on the same item.
local function renamedItem(typeName, category)
    local item={category=category}
    item.getName=function() return 'Shared display name' end
    item.getDisplayName=item.getName
    item.getType=function() return typeName end
    item.getDisplayCategory=function(self) return self.category end
    item.getCategory=item.getDisplayCategory
    item.getUnequippedWeight=function() return 1 end
    item.getContainer=function() return source end
    return item
end
local red=renamedItem('RedNail','Tool')
local blue=renamedItem('BlueNail','Food')
local mixedCategories={name='Shared display name',cat='Tool',items={red,red,blue},count=3,
    realCount=2,weight=2,matchesSearch=true,firstItem=red,cleanUIDisplayItem=red}
groups={mixedCategories}
pane.collapsed[mixedCategories.name]=true
pane.toolkitTag,pane.toolkitTagRule=nil,nil
pane.searchText,pane.searchCategoryText=nil,nil
pane.toolkitCategory='Food'
pane.saved={[red]='group'}
pane:refreshContainer()
local foodRow=pane.itemslist[1]
assert(#pane.itemslist==1 and foodRow.items[1]==blue and foodRow.items[2]==blue and foodRow.cat=='Food',
    'exact category used the original mixed-stack header instead of each item')
assert(pane.selected[1]==foodRow and not pane.toolkitVisibleItems[red] and pane.toolkitVisibleItems[blue],
    'exact-category projection lost group selection or retained a hidden item')
local categorySet={}
for _,entry in ipairs(pane.toolkitCategories) do categorySet[entry.id]=true end
assert(categorySet.Tool and categorySet.Food and #pane.toolkitCategories==2,
    'category choices omitted a physical child category from the source stack')
pane.toolkitCategory=nil
pane.searchMode,pane.searchCategoryText='category','food'
pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1].items[1]==blue and not pane.toolkitVisibleItems[red],
    'category search kept a nonmatching child through the shared group match')
pane.searchMode,pane.searchText='both','RedNail'
pane:restoreSelection({})
assert(#pane.itemslist==0 and next(pane.selected)==nil,
    'combined search matched name and category on different children')
pane.searchMode,pane.searchCategoryText='name',nil
pane.toolkitTag='food'
pane:restoreSelection({})
assert(#pane.itemslist==0,'search and tag rule matched different children')
pane.toolkitTag=nil
mixedCategories.matchesSearch=false
pane:restoreSelection({})
assert(#pane.itemslist==1 and pane.itemslist[1].items[1]==red and not pane.toolkitVisibleItems[blue],
    'name search trusted a stale group match or kept a different script type')
pane:transferItemsByWeight({red,blue},source)
assert(#pane.transferred==1 and pane.transferred[1]==red,'mixed-stack search transferred a rejected child')
pane.searchText=nil;pane.toolkitCategory='Food';pane:restoreSelection({})
assert(pane.itemslist[1].items[1]==blue,'repeated restore lost a previously hidden category')
pane.toolkitCategory='Tool';pane:restoreSelection({})
assert(pane.itemslist[1].items[1]==red and #pane.toolkitUnfilteredRows==1 and #mixedCategories.items==3
    and mixedCategories.items[1]==red and mixedCategories.cat=='Tool',
    'repeated item predicates mutated the source universe or lost the original header')

-- OC can split a CleanUI virtual stack into a headerless row while resetting
-- the optimization flag. Its explicit physical start remains authoritative.
mixedCategories.cleanUILargeStackOptimized=false
mixedCategories.cleanUIFirstActualIndex=1
mixedCategories.items={red,blue}
pane.toolkitCategory=nil;pane.searchMode,pane.searchText='name','RedNail'
pane:refreshContainer()
assert(#pane.itemslist==1 and #pane.itemslist[1].items==1 and pane.itemslist[1].items[1]==red
    and pane.itemslist[1].cleanUIFirstActualIndex==1,
    'headerless OC row skipped its first physical item or gained a dummy header')
pane.searchText=nil;pane.toolkitCategory='Food';pane:restoreSelection(pane.saved)
assert(#pane.itemslist[1].items==1 and pane.itemslist[1].items[1]==blue and pane.selected[1]==pane.itemslist[1],
    'headerless category projection lost the changed group header selection')
pane.toolkitCategory=nil;pane:restoreSelection({})
assert(pane.itemslist[1]==mixedCategories and #mixedCategories.items==2,
    'clearing headerless projection did not restore the unfiltered stack')
groups=originalGroups
print('Mixed-category search checks passed: one physical predicate, source choices, selection and OC headerless rows.')

-- Exercise the real late category split: it replaces the filtered row array
-- after the native restore, so display identity cannot own the full universe.
if OCDisplayOverrideSource then
    local first=assert(OCDisplayOverrideSource:find('local function itemDisplayCategory(item)',1,true))
    local last=assert(OCDisplayOverrideSource:find('-- refreshContainer also fires',first,true))
    local environment=setmetatable({OrganizedCategories={},
        instanceof=function(item) return type(item)=='table' and item.getDisplayCategory~=nil end}, {__index=_G})
    local chunk=assert(loadstring('local luaStr=tostring; local persistEnabled=function() return true end\n'..
        'local function tableHasEntries(t) return t and next(t)~=nil end; local sessionInstanceOverrides={}\n'..
        OCDisplayOverrideSource:sub(first,last-1)..'\nreturn OrganizedCategories.splitStacksByDisplayCategory'))
    setfenv(chunk,environment)
    local split=chunk()
    local excluded=renamedItem('ExcludedType','medicalTreatment')
    excluded.getName=function() return 'Excluded display name' end
    excluded.getDisplayName=excluded.getName
    local shared={name='Shared display name',cat='Tool',items={red,red,blue},count=3,realCount=2,
        firstItem=red,cleanUIDisplayItem=red,cleanUIFirstActualIndex=2}
    groups={shared,{name='Excluded display name',cat='medicalTreatment',items={excluded,excluded},count=2}}
    pane.toolkitTag,pane.toolkitTagRule,pane.toolkitCategory=nil,nil,nil
    pane.searchMode,pane.searchText,pane.searchCategoryText='name','Shared display name',nil
    pane.saved={}
    local originalRefresh=class.refreshContainer
    class.refreshContainer=function(self,...)
        local result=originalRefresh(self,...)
        split(self)
        return result
    end
    pane:refreshContainer()
    assert(#pane.toolkitCategories==3 and #pane.itemslist==2 and pane.itemslist~=pane.toolkitFilteredRows,
        'Actual OC fixture did not replace the filtered mixed-category row array')
    local firstSplit,secondSplit=pane.itemslist[1],pane.itemslist[2]
    for pass=1,2 do
        pane:restoreSelection({})
        local choices={}
        for _,entry in ipairs(pane.toolkitCategories) do choices[entry.id]=true end
        assert(choices.Tool and choices.Food and choices.medicalTreatment and #pane.toolkitCategories==3,
            'Late OC split caused a repeated restore to discard the excluded category universe')
        assert(#pane.itemslist==2 and pane.itemslist[1]==firstSplit and pane.itemslist[2]==secondSplit,
            'Full-universe recovery discarded OC split group identity or order')
        assert(not pane.toolkitVisibleItems[excluded],'Full-universe recovery made a rejected item visible')
    end
    root=rootMenu()
    for _,option in ipairs(root.options) do if option.name=='UI_PZST_TagRule' then combined=option end end
    combined.callback(combined.target)
    local preview={}
    for _,item in ipairs(pickerOptions.items) do preview[item]=true end
    assert(#pickerOptions.items==3 and preview[red] and preview[blue] and preview[excluded],
        'Combined picker lost excluded source items after a late OC category split')
    class.refreshContainer=originalRefresh
    groups=originalGroups
    print('Actual OC category split retains full choices/picker universe and current split projection.')
end

-- Transfer eligibility may visit every physical item in an aggregate. Its
-- membership index belongs to this synchronous command, never the next click.
do
    local function fixture(nativeHandler)
        local callbacks, pages, rawLists = {}, {}, {}
        local physical = {}
        local function item(category, hidden)
            return {category=category or 'Tool', hidden=hidden,
                getContainer=function() return physical end,
                getDisplayCategory=function(self) return self.category end,
                getCategory=function(self) return self.category end,
                getFullType=function() return 'Base.Nails' end,
                getUnequippedWeight=function() return 1 end,
                isFavorite=function() return false end, isEquipped=function() return false end}
        end
        local function raw(values)
            local list={values=values, gets=0, scans=0}
            function list:size() return #self.values end
            function list:get(index) self.gets=self.gets+1; return self.values[index+1] end
            function list:contains(wanted)
                self.scans=self.scans+1
                for _,value in ipairs(self.values) do if value==wanted then return true end end
                return false
            end
            rawLists[#rawLists+1]=list
            return list
        end
        local paneClass={prerender=function() end,restoreSelection=function() end}
        function paneClass:refreshContainer()
            self.refreshes=(self.refreshes or 0)+1
            self.itemslist={}
            for _,value in ipairs(self.inventory.list.values) do
                if not value.hidden then
                    self.itemslist[#self.itemslist+1]={name=tostring(value),items={value,value}}
                end
            end
            self:restoreSelection({})
        end
        function paneClass:transferItemsByWeight(values, target, ...)
            self.transferred=values
            return 'native-transfer',nil,select('#',...),...
        end
        local handler={canTransferItem=function(value) return value and not value.forbidden end}
        for _,name in ipairs({'transferSameType','transferSameCategory','moveToFloor',
            'getQuickTransferItems','showTransferMenu'}) do
            handler[name]=function(page,...) return page.callback(page,...) end
        end
        local player={getPlayerNum=function() return 0 end}
        local env=setmetatable({PZSurvivorToolkit={Settings={inventoryFilters=function() return true end}},
            ISInventoryPane=paneClass,CleanUI_Clean_ISInventoryPane=false,CleanUI_Vanilla_ISInventoryPane=false,
            CleanUI_RegisterInventoryUiToggleCallback=false,ISInventoryPageTransferHandler=handler,
            ISInventoryCommonHandler_SortMenu=false,
            Events={OnGameStart={Add=function(fn) callbacks[#callbacks+1]=fn end}},
            getPlayerInventory=function() return pages[1] end,getPlayerLoot=function() return pages[2] end,
            getSpecificPlayer=function() return player end,getPlayerHotbar=function() end,
            isGamePaused=function() return false end,CleanUI_getTransferMethod=function() return '1' end}, {__index=_G})
        env.require=function(name)
            if name=='PZSurvivorToolkit/InventoryClasses' then
                return {panes=function(install) install(paneClass) end,onToggle=function() end}
            end
            if name=='PZSurvivorToolkit/InventoryRows' then return {restoreSelection=function() end} end
            if name=='PZSurvivorToolkit/InventorySearch' then return {forPane=function() end,matches=function() return true end} end
            if name=='PZSurvivorToolkit/ItemTags' then return {enabled=function() return false end,ruleActive=function() return false end} end
            return {}
        end
        for index=1,2 do
            local inventory={list=raw({}),getItems=function(self) return self.list end,
                getType=function() return 'proximityInv' end,isItemAllowed=function() return true end,
                isInCharacterInventory=function() return false end,isEmpty=function(self) return self.list:size()==0 end}
            local p=setmetatable({inventory=inventory,mode='details',items={},selected={},
                toolkitCategory='Tool',player=0}, {__index=paneClass})
            pages[index]={inventoryPane=p,player=0,onCharacter=index==1}
        end
        if nativeHandler then
            local chunk=assert(loadstring(nativeHandler));setfenv(chunk,env);chunk()
            handler=env.ISInventoryPageTransferHandler
            env.ISInventoryPaneContextMenu={onMoveItemsTo=function(values) pages[1].inventoryPane.transferred=values end}
            env.ISInventoryPage={floorContainer={[1]=pages[2].inventoryPane.inventory}}
        end
        local chunk=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryFilter.lua'))
        setfenv(chunk,env);chunk();callbacks[1]()
        local function resetCounts() for _,list in ipairs(rawLists) do list.gets,list.scans=0,0 end end
        local function fill(page,values)
            page.inventoryPane.inventory.list=raw(values)
            page.inventoryPane:refreshContainer()
            return page.inventoryPane.inventory.list
        end
        return {env=env,handler=handler,pages=pages,player=player,item=item,raw=raw,fill=fill,reset=resetCounts}
    end
    -- With no predicate, restored rows need no projection. Choices must still
    -- read live metadata from the full refresh's physical-item references.
    local inactive=fixture()
    local live=inactive.item('Tool')
    inactive.fill(inactive.pages[1],{live})
    local inactivePane=inactive.pages[1].inventoryPane
    inactivePane.toolkitCategory=nil
    inactivePane:refreshContainer()
    local noProjection={{items=false}}
    inactivePane.itemslist=noProjection
    live.category='Changed category'
    inactivePane:restoreSelection({})
    assert(inactivePane.itemslist==noProjection and inactivePane.toolkitVisibleItems==nil
        and #inactivePane.toolkitCategories==1 and inactivePane.toolkitCategories[1].id=='Changed category',
        'inactive restoration inspected unused projection rows or cached stale category choices')
    local f=fixture()
    local left,right=f.pages[1],f.pages[2]
    local h=f.handler
    local function allowed(value) return h.canTransferItem(value,right.inventoryPane.inventory,f.player) end
    for _,size in ipairs({100,400,1600}) do
        local values={}
        for index=1,size do values[index]=f.item(index%2==0 and 'Tool' or 'Food',index==size) end
        values[2].forbidden=true -- Native protection still runs after the filter.
        local sourceList=f.fill(left,values)
        local destinationItem=f.item('Food')
        local destinationList=f.fill(right,{destinationItem})
        left.callback=function()
            f.reset()
            local count=0
            for _,value in ipairs(values) do
                local expected=value.category=='Tool' and not value.hidden and not value.forbidden
                assert(allowed(value)==expected,'aggregate filter or native admission changed')
                if expected then count=count+1 end
            end
            assert(sourceList.gets==size and destinationList.gets==1,
                'bulk eligibility did not build one raw membership index per pane')
            assert(sourceList.scans==0 and destinationList.scans==0,'bulk eligibility retained linear contains calls')
            return count,nil,'tail',nil
        end
        for _,name in ipairs({'transferSameType','transferSameCategory','moveToFloor',
            'getQuickTransferItems','showTransferMenu'}) do
            local function verify(...) assert(select('#',...)==4 and select(2,...)==nil
                and select(3,...)=='tail' and select(4,...)==nil,'command wrapper changed return arity') end
            verify(h[name](left))
        end
        f.reset()
        local a,b,c,d=left.inventoryPane:transferItemsByWeight(values,right.inventoryPane.inventory,'argument')
        assert(a=='native-transfer' and b==nil and c==1 and d=='argument','direct transfer return values changed')
        -- Direct native transfer retains its own admission policy; this wrapper owns visibility only.
        assert(#left.inventoryPane.transferred==size/2-1 and sourceList.gets==size and sourceList.scans==0,
            'direct aggregate transfer did not filter once with indexed raw membership')
    end
    local old,replacement,incoming=f.item('Food'),f.item('Food',true),f.item('Tool')
    local sourceList=f.fill(left,{old,incoming})
    f.fill(right,{f.item('Food')})
    left.callback=function() assert(not allowed(old) and allowed(incoming)) end
    h.transferSameType(left)
    sourceList.values[1]=replacement -- Same size, same list: a new command must rebuild it.
    left.callback=function() assert(not allowed(replacement),'next command reused old aggregate membership') end
    h.getQuickTransferItems(left)
    assert(not allowed(replacement),'standalone eligibility reused command membership')
    sourceList.values[1]=old
    assert(allowed(replacement),'standalone eligibility ignored live same-count removal')
    sourceList.values[1]=replacement
    -- A destination filter accepts unrelated incoming items, but rejects its own hidden members.
    assert(allowed(incoming) and not allowed(replacement),'both-pane source ownership changed')
    f.fill(right,{incoming})
    right.inventoryPane.toolkitCategory='Food';right.inventoryPane:refreshContainer()
    assert(not allowed(incoming),'overlapping filtered destination lost its own source exclusion')
    f.fill(right,{f.item('Food')});right.inventoryPane.toolkitCategory='Tool';right.inventoryPane:refreshContainer()
    -- Nested scopes must restore their caller's index. Refresh in a child must
    -- invalidate that caller too, even after a same-count replacement.
    sourceList.values[1]=old
    left.callback=function()
        assert(not allowed(old))
        right.callback=function() assert(not allowed(old));error('expected nested failure') end
        local nestedOk,nestedError=pcall(h.getQuickTransferItems,right)
        assert(not nestedOk and tostring(nestedError):find('expected nested failure',1,true))
        local readsAfterFailure=sourceList.gets
        assert(not allowed(old) and sourceList.gets==readsAfterFailure,
            'nested failure did not restore its caller membership scope')
        right.callback=function()
            sourceList.values[1]=replacement
            left.inventoryPane:refreshContainer()
            assert(not allowed(replacement))
            return 'nested',nil,'tail'
        end
        local a,b,c=h.showTransferMenu(right)
        assert(a=='nested' and b==nil and c=='tail')
        assert(not allowed(replacement),'nested refresh left the ancestor membership index stale')
        -- Raw list replacement and size changes invalidate an index even within a command.
        left.inventoryPane.inventory.list=f.raw({old,incoming})
        assert(allowed(replacement),'same-size raw list replacement reused an index')
        left.inventoryPane.inventory.list.values[3]=replacement
        assert(not allowed(replacement),'raw list growth reused an index')
    end
    h.transferSameType(left)
    left.callback=function() assert(not allowed(replacement));error('expected transfer enumeration failure') end
    local ok,err=pcall(h.transferSameCategory,left)
    assert(not ok and tostring(err):find('expected transfer enumeration failure',1,true),'command swallowed its error')
    left.inventoryPane.inventory.list.values[3]=nil
    assert(allowed(replacement),'failed command leaked its membership scope')
    print('Transfer membership checks passed: linear 100/400/1600 reads, visibility, freshness, nested scopes and errors.')
    if CleanUIInventoryTransferHandlerSource then
        local native=fixture(CleanUIInventoryTransferHandlerSource)
        local sourcePage,targetPage=native.pages[1],native.pages[2]
        local selected,hidden,rejected=native.item('Tool'),native.item('Tool',true),native.item('Food')
        local source=native.fill(sourcePage,{selected,hidden,rejected})
        native.fill(targetPage,{native.item('Food')})
        -- Same-type preview and dispatch use the real upstream admission/iteration paths.
        native.reset()
        local preview=native.handler.getQuickTransferItems(sourcePage,'type')
        assert(#preview==1 and preview[1]==selected and source.scans==0,
            'real CleanUI quick preview bypassed the scoped physical filter')
        native.handler.transferSameType(sourcePage)
        assert(#sourcePage.inventoryPane.transferred==1 and sourcePage.inventoryPane.transferred[1]==selected,
            'real CleanUI same-type dispatch changed selected physical items')
        native.handler.moveToFloor(sourcePage)
        assert(#sourcePage.inventoryPane.transferred==1 and sourcePage.inventoryPane.transferred[1]==selected,
            'real CleanUI floor dispatch included hidden or rejected items')
        native.handler.showTransferMenu(sourcePage,0,0)
        assert(source.scans==0,'real CleanUI transfer menu retained per-item membership scans')
        print('Actual CleanUI transfer handler preview, command, floor and menu integration passed.')
    end
end
