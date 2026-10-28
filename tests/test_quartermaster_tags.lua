package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;' .. package.path
local enabled, starts, creates = true, {}, {}
local openedRulePicker, adapter
local scriptCatalog = {}
local catalogReads, tagReads = 0, 0
local projectionContexts = 0
local tagRevision, customIds = 0, {}
local normalizations = 0
local appearanceSelections={}
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local groupRecords, groupsSynced, groupEditable, groupControls = {}, true, true, nil
local groupApi = {FIELD = 'PZSTContainerGroups', synced = function() return groupsSynced end,
    link = function(obj, ci) return obj and obj.md.PZSTContainerGroups and obj.md.PZSTContainerGroups[tostring(ci)] end,
    canEdit = function() return groupEditable end}
groupApi.resolve = function(obj, ci) return groupsSynced and copy(groupRecords[groupApi.link(obj, ci)]) or nil end
groupApi.list = function()
    local records = {}; for _, record in pairs(groupRecords) do records[#records + 1] = copy(record) end; return records
end
local ruleApi = {getBoxRevision = function(obj) return obj and obj.md.ruleRevision or 0 end,
    getBox = function() end, getPreset = function() end,
    presetsSynced = function() return true end}
getSpecificPlayer = function() return {} end
PZSurvivorToolkit = {}
local itemCategories = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemCategories.lua')
local categoryTags = {OC_Food = {'food'}, OC_FoodPerishable = {'food', 'perishable'},
    OC_Electrical = {'electrical'}, OC_FoodElectrical = {'food', 'electrical'}}
require = function(name)
    if name == 'LootSorter_Categories' then
        return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/LootSorter_Categories.lua')
    end
    if name == 'PZSurvivorToolkit/ContainerAppearanceControls' then
        return {create=function() end, layout=function(_, top) return top end,
            close=function() end, value=function() end,
            snapshot=function(picker) return copy(picker.toolkitAppearance or {}) end,
            setValue=function(picker, value) picker.toolkitAppearance = copy(value) end,
            select=function(picker,kind,key)
                if key then appearanceSelections[#appearanceSelections+1]={picker=picker,kind=kind,key=key} end
            end}
    end
    if name == 'PZSurvivorToolkit/ContainerGroups' then return groupApi end
    if name == 'PZSurvivorToolkit/ContainerGroupControls' then
        groupControls = groupControls or dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. name .. '.lua')
        return groupControls
    end
    if name == 'PZSurvivorToolkit/UIStyle' then return {fit = function(value) return value end} end
    if name == 'PZSurvivorToolkit/ItemCategories' then return itemCategories end
    if name == 'PZSurvivorToolkit/ItemRetention' or name == 'PZSurvivorToolkit/ItemAccess' then
        return dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..name..'.lua')
    end
    if name == 'PZSurvivorToolkit/InventoryTransferProtection' or name == 'PZSurvivorToolkit/QuartermasterDuplicates' then
        return dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..name..'.lua')
    end
    if name == 'PZSurvivorToolkit/TagVisuals' then
        return {get=function(id) return {r=0.3,g=0.7,b=0.3,texture=id and {id=id} or nil} end}
    end
    if name == 'PZSurvivorToolkit/QuartermasterTagRuleClient' or name == 'PZSurvivorToolkit/QuartermasterTagRules' then return ruleApi end
    if name == 'PZSurvivorToolkit/QuartermasterTags' then return assert(adapter) end
    if name == 'PZSurvivorToolkit/TagRulePicker' then return {open = function(args) openedRulePicker = args end,
        summary=function() return 'rule summary' end} end
    if name == 'PZSurvivorToolkit/UIStyle' then return {fit=function(value) return value end} end
    assert(name == 'PZSurvivorToolkit/ItemTags')
    return {enabled = function() return enabled end,
        revision = function() return tagRevision end, customIds = function() return customIds end,
        allIds = function() error('selection view scanned the automatic script tag catalog') end,
        newScriptProjectionContext = function()
            projectionContexts = projectionContexts + 1
            return {id = projectionContexts}
        end,
        requiresItemRule = function(id) return id=='readable' or id=='literature' or id=='writeable'
            or id=='fresh' or id=='stale' or id=='rotten' end,
        choices = function(tags) return tags.menuChoices or tags end,
        normalizeRule = function(value)
            normalizations = normalizations + 1
            local result = {mode = value and value.mode or 'all', include = {}, exclude = {}}
            for _, field in ipairs({'include', 'exclude'}) do
                for _, id in ipairs(value and value[field] or {}) do result[field][#result[field] + 1] = id end
            end
            if value and value.groups then result.groups = copy(value.groups) end
            return result
        end,
        ruleActive = function(value) return value and (value.groups and #value.groups > 0 or #value.include > 0 or #value.exclude > 0) or false end,
        ruleIncludes = function(rule,id)
            -- The production public predicate normalizes before querying membership.
            rule = require('PZSurvivorToolkit/ItemTags').normalizeRule(rule)
            for _, group in ipairs(rule and rule.groups or {}) do
                for _, tag in ipairs(group.include) do if tag == id then return true end end
            end
            for _,tag in ipairs(rule and rule.include or {}) do if tag==id then return true end end
            return false
        end,
        forCategory = function(category) return categoryTags[category] or {'category:' .. category} end,
        forScriptItem = function() error('choice catalog copied owned script metadata') end,
        choicesForScriptItem = function(script, context)
            assert(context and context.id == projectionContexts, 'script projection did not receive its catalog context')
            tagReads = tagReads + 1
            local tags = {legacyCategory = itemCategories.forScript(script), menuChoices = script.tags.menuChoices}
            for index, id in ipairs(script.tags) do tags[index] = id end
            local choices = {legacyCategory = tags.legacyCategory}
            for index, id in ipairs(tags.menuChoices or tags) do choices[index] = id end
            return choices
        end,
        label = function(id) return id end}
end
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end},
    OnCreatePlayer = {Add = function(fn) creates[#creates + 1] = fn end}}
local uiText = {UI_PZST_ContainerSorting='What belongs here',
    UI_PZST_ContainerSortingHint='Select what this box accepts.',
    UI_PZST_ContainerSearch='Search the list', UI_PZST_ContainerSearchHint='Search visible entries',
    UI_PZST_ContainerOnlyChecked='Only checked', UI_PZST_ContainerOnlyContents='Only in contents',
    UI_PZST_ContainerPriority='Priority', UI_PZST_ContainerNoDuplicates='No duplicates',
    UI_PZST_ContainerNoDuplicatesHint='One item of each full type per container.', UI_PZST_ContainerCategories='Categories',
    UI_PZST_ContainerTags='Tags', UI_PZST_ContainerItems='Items', UI_PZST_ContainerPresets='Presets',
    UI_PZST_ContainerAddRule='Add rule', UI_PZST_ContainerEditRule='Edit rule',
    UI_PZST_ContainerSave='Save'}
getText, getTextOrNull = function(key) return uiText[key] or key end, function() return nil end
UIFont = {Small = 0, Medium = 1}
Joypad = {AButton = 1, YButton = 2, BButton = 3, RBumper = 4, LBumper = 5}
getTexture = function() return {} end
getTextManager = function() return {getFontHeight = function(_, font) return font == UIFont.Medium and 22 or 14 end} end
getCore = function() return {getGoodHighlitedColor = function()
    return {getR = function() return 1 end, getG = function() return 1 end, getB = function() return 1 end}
end} end
local function control()
    local b = {x = 10, y = 100, width = 360, height = 300, visible = true}
    for _, name in ipairs({'X', 'Y', 'Width', 'Height'}) do
        local key = name:lower()
        b['get' .. name] = function(self) return self[key] end
        b['set' .. name] = function(self, value) self[key] = value end
    end
    function b:getAbsoluteX() return self.x end
    function b:getAbsoluteY() return self.y end
    function b:setVisible(value) self.visible = value end
    function b:setTitle(value) self.title = value end
    function b:setTooltip(value) self.tooltip = value end
    function b:initialise() end
    function b:instantiate() end
    function b:setYScroll(value) self.scroll = value end
    function b:getYScroll() return self.scroll or 0 end
    function b:drawRect(_, _, width, height) self.draws[#self.draws + 1] = {width, height} end
    function b:drawRectBorder() end
    function b:drawTextureScaled() self.ticks = (self.ticks or 0) + 1 end
    function b:drawTextureScaledAspect(texture) self.semanticIcon=texture end
    function b:drawText(text) self.drawnText = text end
    function b:isMouseOver() return false end
    b.draws = {}
    return b
end
local storedCats, storedItems = {OC_Food = true, MissingModCategory = true}, {Beans = true}
local availableCats = {'OC_Food', 'OC_FoodPerishable', 'OC_Electrical', 'OC_FoodElectrical', 'OtherMod'}
adapter = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/QuartermasterTags.lua')
assert(#starts == 0 and #creates == 0 and adapter.attach == nil,
    'tag helpers installed lifecycle hooks or retained per-instance attachment')
local createSourceFixture = dofile(ProjectRoot .. '/tests/support/quartermaster_picker_source.lua')
local function createFixture(...)
    local fixture = createSourceFixture(...)
    dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/LootSorter_Presets.lua')
    LootSorter.arePresetsSynced = function() return true end
    return fixture
end
local fixture = createFixture(control, ruleApi, {categories = function() return availableCats end,
    scriptItems = function()
        catalogReads = catalogReads + 1
        local scripts, seen = {}, {}
        for _, item in ipairs(scriptCatalog) do scripts[#scripts + 1], seen[item.uiCategory] = item, true end
        for _, category in ipairs(availableCats) do
            if not seen[category] then
                scripts[#scripts + 1] = {uiCategory = category, tags = categoryTags[category] or {'category:' .. category},
                    getDisplayCategory = function() return category end, getFullName = function() return 'Fixture.Category.' .. category end}
            end
        end
        return scripts
    end,
    cats = storedCats, items = storedItems})
local open = fixture.open
local function edit() return fixture.edit(LootSorter._picker) end
local function find(p, tagOrCategory)
    for index, row in ipairs(p.listbox.items) do
        if row.item.tag == tagOrCategory or row.item.key == tagOrCategory then return row.item, index end
    end
end
local function click(p, id) local row = assert(find(p, id), 'missing ' .. id); p.listbox.onmousedown(p, row); p:prerender() end
LootSorter.openPicker(fixture.object, 0, 0)
local p = LootSorter._picker
repeat p:prerender() until not p.toolkitTagCatalogPending
local initialRows, initialLayout, firstLayouts = p.listbox.items, p.layout, 0
p.layout = function(self) firstLayouts = firstLayouts + 1; initialLayout(self) end
p:configJoypad(); p:prerender()
p.layout = initialLayout
assert(p.listbox.items == initialRows and firstLayouts == 0, 'first frame repeated the prepared rows/layout')
assert(p.children[#p.children] == p.dimmer, 'tag switch bypasses preset dimmer')
assert(p.filter.nativeFont == UIFont.Medium, 'filter font was assigned only on the Lua wrapper after native creation')
local originalFontHeight = getTextManager().getFontHeight
getTextManager().getFontHeight = function(_, font) return font == UIFont.Medium and 40 or 32 end
p:setHeight(380);p:layout()
assert(p.minimumHeight > 380 and p.height >= p.minimumHeight
    and p.listbox.y + p.listbox.height < p.btnSave.y, 'large-font minimum window overlaps its list/footer')
getTextManager().getFontHeight = originalFontHeight
p:setHeight(580);p:layout()

assert(p.joypadButtonsY[1][1] == p.groupSelect and p.joypadButtonsY[5][1] == p.chkNoDuplicates
    and p.joypadButtonsY[6][1] == p.toolkitTagSwitch
    and p.joypadButtonsY[7][1] == p.toolkitTagRuleButton, 'container policy has no controller row')
local function assertLayout(picker)
    assert(picker.sortingHeading.y + picker.sortingHeading.height <= picker.sortingHint.y
        and picker.sortingHint.y + picker.sortingHint.height < picker.filterLabel.y
        and picker.filterLabel.y == picker.filter.y and picker.filterLabel.x < picker.filter.x
        and picker.filter.x + picker.filter.width <= picker:getWidth() - 10
        and picker.filter.y + picker.filter.height < picker.btnModeCat.y
        and picker.btnModeCat.y + picker.btnModeCat.height <= picker.chkChecked.y
        and picker.chkChecked.y < picker.chkContents.y
        and picker.chkContents.y + picker.chkContents.height <= picker.chkNoDuplicates.y
        and picker.chkNoDuplicates.y + picker.chkNoDuplicates.height <= picker.listbox.y
        and picker.chkNoDuplicates.x + picker.chkNoDuplicates.width <= picker:getWidth() - 10
        and picker.listbox.y + picker.listbox.height <= picker.btnSave.y,
        'window layout overlaps headings, search, filters, list, or Save')
end
assert(p.chkNoDuplicates.visible and not p.noDuplicates
    and p.chkNoDuplicates.qmLabel == uiText.UI_PZST_ContainerNoDuplicates
    and p.chkNoDuplicates.tooltip == uiText.UI_PZST_ContainerNoDuplicatesHint)
assertLayout(p)
assert(p.btnSave.title == uiText.UI_PZST_ContainerSave, 'Save button is not using the localized Toolkit label')
p:setWidth(520); p:setHeight(700); p:prerender()
assert(p.toolkitTagSwitch.width == 500 and p.toolkitTagRuleButton.width == 500
    and p.listbox.width == 500
    and p.dimmer.width == 520 and p.dimmer.height == 700, 'owned resize lost tag controls or list clipping')
assertLayout(p)
p:layout(); p:layout()
assertLayout(p)
p:setWidth(420); p:setHeight(600); p:prerender()
assert(p.minimumWidth == 420 and p.minimumHeight == 600, 'minimum picker bounds changed')
assertLayout(p)
p:setMode('items'); p:prerender(); assertLayout(p)
p:setMode('cats'); p:prerender(); assertLayout(p)
local function stencilWidth(list)
    -- ISScrollingListBox.prerender uses these exact native geometry fields.
    if list.vscroll:getHeight() < list:getScrollHeight() then return list.vscroll.x + 3 end
    return list.width - 1
end
assert(p.listbox.vscroll.x == p.listbox.width - 16 and p.listbox.vscroll.height == p.listbox.height,
    'native scrollbar kept the constructor geometry and clipped rows')
p.listbox:setScrollHeight(1000)
assert(stencilWidth(p.listbox) > 300, 'scrollable tag rows are clipped before their checkbox/label')
p.filter:setText('electr'); p.needRebuild = true; p:prerender()
p.listbox:setScrollHeight(22)
assert(stencilWidth(p.listbox) > 300, 'single filtered tag row is clipped')
p.filter:setText('no-matching-fixture-tag'); p:prerender()
assert(p.listbox.count == 0 and p.emptyListKey == 'NoMatches', 'empty search has no recovery guidance')
assert(p.listbox.doRepaintStencil, 'list did not restore the window stencil for empty-state text')
p.listbox:prerender()
assert(p.listbox.drawnText == 'UI_PZST_ContainerNoMatchesHint', 'list did not draw empty-search guidance')
p.filter:setText(''); p.needRebuild = true; p:prerender()
assert(not p.emptyListKey, 'empty-list guidance covers restored rows')
assert(find(p, 'food') and find(p, 'electrical') and find(p, 'perishable'))
assert(find(p, 'MissingModCategory') and find(p, 'OtherMod'), 'unknown categories lost')
local food, fi = find(p, 'food')
p.listbox.selected, p.listbox.mouseoverselected = fi, fi
p.listbox.onJoypadDown(p.listbox, Joypad.YButton)
p.listbox.onRightMouseUp(p.listbox)
assert(fixture.contextMenu() == nil, 'tag row opened an exact-category context menu')
p.listbox.doDrawItem(p.listbox, 0, p.listbox.items[fi])
assert(p.listbox.semanticIcon and p.listbox.semanticIcon.id=='food','tag association icon missing')
assert(p.listbox.drawnText == 'food (UI_PZST_QMTagRule)' and not p.listbox.ticks,
 'semantic checkbox incorrectly represents saved exact-category assignments')
local state, offscreenChecks = adapter.state, 0
adapter.state = function(...) offscreenChecks = offscreenChecks + 1; return state(...) end
p.listbox.doDrawItem(p.listbox, 10000, p.listbox.items[fi])
adapter.state = state
assert(offscreenChecks == 0, 'offscreen tag rows still counted category selections')
local dash = false
for _, size in ipairs(p.listbox.draws) do if size[1] == 10 and size[2] == 2 then dash = true end end
assert(not dash, 'semantic rule checkbox inherited partial exact-category state')
local beforeCats=p.selectedCats
click(p,'food')
assert(not openedRulePicker and p.toolkitTagRule.include[1]=='food' and p.selectedCats==beforeCats
 and not p.selectedCats.OC_FoodPerishable,'semantic tag click opened an editor or expanded static categories')
assert(p.toolkitTagRule.include[1]=='food' and not p.selectedCats.food)
click(p,'food')
local checked,total=adapter.state(p.selectedCats,assert(find(p,'food')),p.toolkitTagRule)
assert(checked==0 and total==1 and #p.toolkitTagRule.include==0
    and p.selectedCats==beforeCats and p.selectedCats.OC_Food,
    'unchecking a live tag stayed checked or removed saved exact assignments')
click(p,'food')
-- Exact-category refinement and existing saved keys keep their literal meaning.
p.toolkitTagSwitch.onclick(p);p:prerender()
assert(not p.toolkitTagView and find(p,'OC_FoodPerishable'))
assert(p.listbox.vscroll.x == p.listbox.width - 16 and p.listbox.vscroll.height == p.listbox.height
    and stencilWidth(p.listbox) > 300, 'exact-category refinement retained clipped scrollbar geometry')
click(p,'OC_FoodPerishable');assert(p.selectedCats.OC_FoodPerishable)
click(p,'OC_FoodPerishable');assert(not p.selectedCats.OC_FoodPerishable and p.selectedCats.OC_Food)
p.toolkitTagSwitch.onclick(p);p:prerender()
p.onlyChecked,p.needRebuild=true,true;p:prerender()
assert(find(p,'food') and not find(p,'perishable'), 'Only Checked omitted partial tags or kept unchecked tag')
p.onlyChecked,p.onlyContents,p.needRebuild=false,true,true;p:prerender()
assert(find(p,'food') and find(p,'perishable') and not find(p,'electrical'), 'Only Contents did not map exact categories')
p.onlyContents=false;p.filter:setText('electr');p.needRebuild=true;p:prerender()
assert(#p.listbox.items==1 and find(p,'electrical'))
local _,ei=find(p,'electrical');p.listbox.selected=ei
p.listbox.onJoypadDown(p.listbox,Joypad.AButton);p:prerender()
assert(p.toolkitTagRule.include[2]=='electrical' and not p.selectedCats.OC_Electrical
    and not p.selectedCats.OC_FoodElectrical and not openedRulePicker, 'controller did not select a live tag directly')
p.listbox.onJoypadDown(p.listbox,Joypad.BButton,fixture.joypad)
assert(fixture.joypad.focus==p, 'controller did not leave the tag list')
p.filter:setText('');p.needRebuild=true;p:prerender()
p:setMode('items');p:prerender();click(p,'Hammer')
assert(p.selectedItems.Hammer and p.selectedItems.Beans)
assert(not p.toolkitTagSwitch.visible and stencilWidth(p.listbox)>300, 'native Items layout clipped rows')
p:setMode('presets');p:prerender();click(p,'Pantry')
assert(not p.selectedPresets.Pantry and find(p,'Pantry'), 'preset mode intercepted')
p:setMode('cats');p:prerender()
storedCats,storedItems=p.selectedCats,p.selectedItems
fixture.object.md.LSBox['0'],fixture.object.md.LSBoxItems['0']=storedCats,storedItems
categoryTags.OC_FoodNew={'food'};availableCats[#availableCats+1]='OC_FoodNew'
open();local reopened=LootSorter._picker
assert(reopened.selectedCats.OC_Food and reopened.selectedCats.MissingModCategory
 and not reopened.selectedCats.OC_FoodNew,'reopen widened saved exact category selections')
local _,unknownIndex=find(reopened,'MissingModCategory')
reopened.listbox.mouseoverselected=unknownIndex;reopened.listbox.onRightMouseUp(reopened.listbox)
assert(fixture.contextMenu().options[1].key=='MissingModCategory')
reopened.listbox.selected=unknownIndex
reopened.listbox.onJoypadDown(reopened.listbox,Joypad.YButton)
assert(fixture.contextMenu().options[1].key=='MissingModCategory', 'controller lost the unknown-category inspector')
edit();local editor=LootSorter._presetEditor
click(editor,'perishable');assert(editor.toolkitTagRule.include[1]=='perishable' and not openedRulePicker)
assert(not editor.selectedCats.perishable)
reopened.btnClear.onclick(reopened);reopened:prerender()
assert(next(reopened.selectedCats)==nil and reopened.selection==reopened.selectedCats)
click(reopened,'food');assert(reopened.toolkitTagRule.include[1]=='food' and next(reopened.selectedCats)==nil,
 'tag selection after clear was expanded into static categories')
enabled = false
reopened:prerender()
assert(not reopened.toolkitTagSwitch.visible and find(reopened, 'OC_Food'))
open(); local openedDisabled = LootSorter._picker
assert(openedDisabled.toolkitTagSwitch and not openedDisabled.toolkitTagSwitch.visible
    and find(openedDisabled, 'OC_Food'), 'disabled picker did not retain native view')
enabled = true; openedDisabled:prerender()
assert(openedDisabled.toolkitTagSwitch.visible and find(openedDisabled, 'food'),
    'picker opened while disabled did not enable tags without reopening')
assert(openedDisabled.joypadButtonsY[5][1] == openedDisabled.chkNoDuplicates
    and openedDisabled.joypadButtonsY[6][1] == openedDisabled.toolkitTagSwitch
    and openedDisabled.joypadButtonsY[7][1] == openedDisabled.toolkitTagRuleButton, 'live enable did not add controller navigation')
local closedReads = tagReads
reopened:prerender()
assert(reopened.toolkitTagClosed and tagReads == closedReads, 'closed picker restarted tag discovery')
openedDisabled.toolkitTagRuleButton.onclick(openedDisabled)
assert(openedRulePicker and openedRulePicker.owner == openedDisabled and #openedRulePicker.categories == #availableCats + 1)
local exactCats = openedDisabled.selectedCats
local dynamicRule = {mode='all',include={'food'},exclude={'perishable'}}
openedRulePicker.onApply(dynamicRule)
assert(openedDisabled.selectedCats == exactCats, 'dynamic rule stripped precise picks')
ruleApi.presetsSynced = function() return false end
editor.toolkitTagRule, editor.toolkitTagRuleTouched = nil, nil
local payload = adapter.presetArgs(editor,{cats=editor.selectedCats})
assert(payload.pzstTagRule == nil, 'unsynced preset metadata was cleared by native exact-selection save')
editor.toolkitTagRule, editor.toolkitTagRuleTouched = dynamicRule, true
payload = adapter.presetArgs(editor,{cats=editor.selectedCats})
assert(payload.pzstTagRule.include[1] == 'food' and payload.pzstTagRule.exclude[1] == 'perishable'
    and payload.pzstTagRule ~= dynamicRule, 'explicit rule edit was not detached for native preset conflict request')
local function script(name, category, tags)
    return {tags=tags,uiCategory=category,getFullName=function() return 'Fixture.'..name end,
        getDisplayCategory=function(self) return self.uiCategory end,getDisplayName=function() return name end}
end
for category, ids in pairs({OC_Snack={'food','snack'},OC_Seeds={'farming','seed'},
    OC_SeedOnly={'farming','seed'}}) do
    categoryTags[category]=ids;availableCats[#availableCats+1]=category
end
local function snapshot(set)
    local result={};for key,value in pairs(set) do result[key]=value end;return result
end
local function unchanged(set,before,message)
    for key,value in pairs(before) do assert(set[key]==value,message) end
    for key,value in pairs(set) do assert(before[key]==value,message) end
end
for _,names in ipairs({{'Candy','Sunflower seeds','Full packet','Empty packet','Pure seed'},
    {'Конфеты','Семечки подсолнуха','Пакет семян','Пустой пакет семян','Семена'}}) do
    scriptCatalog={script(names[1],'OC_Snack',{'food','snack'}),
        script(names[2],'OC_Snack',{'food','snack','farming','seed'}),
        script(names[3],'OC_Seeds',{'farming','seed'}),script(names[4],'OC_Seeds',{'farming'}),
        script(names[5],'OC_SeedOnly',{'farming','seed'})}
    fixture.setContents({'OC_Snack'})
    local readsBefore, contextsBefore = catalogReads, projectionContexts
    open();local itemPicker=LootSorter._picker
    assert(catalogReads == readsBefore + 1, 'reopened picker did not read a fresh catalog')
    assert(projectionContexts == contextsBefore + 1, 'reopened picker did not use one fresh projection context')
    local projectionReads = tagReads
    itemPicker.selectedItems['Sunflower seeds']=true
    local seed,seedIndex=assert(find(itemPicker,'seed'))
    assert(seed.requiresRule and seed.items==nil and #seed.categories==1 and seed.categories[1]=='OC_SeedOnly',
        'partial categories did not require a stable tag rule')
    local catsBefore,itemsBefore=snapshot(itemPicker.selectedCats),snapshot(itemPicker.selectedItems)
    for _, query in ipairs({'s', 'se', 'seed', ''}) do
        itemPicker.filter:setText(query); itemPicker:prerender()
        assert(find(itemPicker, 'seed') == seed, 'typing rebuilt the prepared tag rows')
    end
    itemPicker.selectedCats.NewMissingCategory = true; itemPicker.needRebuild = true; itemPicker:prerender()
    assert(find(itemPicker, 'NewMissingCategory'), 'new saved category was omitted from prepared rows')
    itemPicker.selectedCats.NewMissingCategory = nil; itemPicker.needRebuild = true; itemPicker:prerender()
    assert(not find(itemPicker, 'NewMissingCategory'), 'removed saved category left a stale row')
    seed, seedIndex = assert(find(itemPicker, 'seed'))
    local previousEditor = openedRulePicker
    click(itemPicker,'seed')
    assert(openedRulePicker == previousEditor, 'one-click tag selection unexpectedly opened advanced rules')
    assert(itemPicker.toolkitTagRuleTouched and itemPicker.toolkitTagRule.mode=='any'
        and itemPicker.toolkitTagRule.include[1]=='seed', 'partial tag was not selected as a stable union rule')
    unchanged(itemPicker.selectedCats,catsBefore,'partial tag click changed exact category picks')
    unchanged(itemPicker.selectedItems,itemsBefore,'partial tag click persisted localized names')
    local suggestion=appearanceSelections[#appearanceSelections]
    assert(suggestion.picker==itemPicker and suggestion.kind=='tag' and suggestion.key=='seed',
        'direct tag selection did not forward first explicit tag to appearance')
    assert(itemPicker.selectedPresets.Pantry=='generation','direct tag click changed a manual preset')
    local checked,total=adapter.state(itemPicker.selectedCats,seed,itemPicker.toolkitTagRule)
    assert(checked==1 and total==1,'selected partial tag is not checked')
    itemPicker.onlyChecked,itemPicker.needRebuild=true,true;itemPicker:prerender()
    assert(find(itemPicker,'seed'),'Only Checked hid the applied tag rule')
    itemPicker.onlyChecked,itemPicker.needRebuild=false,true;itemPicker:prerender()
    seed,seedIndex=find(itemPicker,'seed')
    itemPicker.listbox.selected=seedIndex
    itemPicker.listbox.onJoypadDown(itemPicker.listbox,Joypad.AButton)
    assert(#itemPicker.toolkitTagRule.include==0 and openedRulePicker==previousEditor,
        'controller failed to uncheck a direct rule tag')
    itemPicker.toolkitTagRule={mode='all',include={'farming'},exclude={'seed','food'}}
    click(itemPicker,'seed')
    assert(itemPicker.toolkitTagRule.mode=='all' and #itemPicker.toolkitTagRule.include==2
        and #itemPicker.toolkitTagRule.exclude==1 and itemPicker.toolkitTagRule.exclude[1]=='food',
        'direct selection replaced advanced conditions or retained a contradictory exclusion')
    itemPicker.selectedCats={};itemPicker.selection=itemPicker.selectedCats
    local foodRow=assert(find(itemPicker,'food'))
    assert(foodRow.requiresRule, 'semantic whole-category tag lost its live rule')
    adapter.select(itemPicker,foodRow,true)
    assert(#itemPicker.toolkitTagRule.exclude==0 and #itemPicker.toolkitTagRule.include==3
        and itemPicker.toolkitTagRule.mode=='all' and next(itemPicker.selectedCats)==nil,
        'excluded whole-category tag bypassed the advanced rule via exact picks')
    local suggestionsBefore=#appearanceSelections
    adapter.select(itemPicker,foodRow,true)
    assert(#appearanceSelections==suggestionsBefore, 'reselecting an existing rule tag supplied appearance again')
    local limitRule={mode='all',include={},exclude={'food'}}
    for i=1,64 do limitRule.include[i]='limit'..i end
    itemPicker.toolkitTagRule=limitRule
    adapter.select(itemPicker,foodRow,true)
    assert(itemPicker.toolkitTagRule==limitRule and #limitRule.include==64 and limitRule.exclude[1]=='food'
        and next(itemPicker.selectedCats)==nil and #appearanceSelections==suggestionsBefore,
        'selection beyond the rule limit partially changed selections, exclusions or appearance')
    itemPicker.toolkitTagRule={mode='any',include={'seed'},exclude={}}

    itemPicker.onlyContents,itemPicker.needRebuild=true,true;itemPicker:prerender()
    assert(find(itemPicker,'seed'),'Only Contents hid a partial category planting input')
    itemPicker.onlyContents,itemPicker.needRebuild=false,true;itemPicker:prerender()
    click(itemPicker,'snack')
    assert(openedRulePicker==previousEditor and itemPicker.toolkitTagRule.include[2]=='snack',
        'whole-category semantic tag did not select a live rule directly')
    assert(next(itemPicker.selectedCats)==nil,'semantic tag expanded into static categories')
    unchanged(itemPicker.selectedItems,itemsBefore,'whole-category batch changed manual items')
    itemPicker.btnClear.onclick(itemPicker);itemPicker:prerender()
    assert(next(itemPicker.selectedCats)==nil and #itemPicker.toolkitTagRule.include==0
        and #itemPicker.toolkitTagRule.exclude==0,'Uncheck all failed to clear category/tag picks')
    unchanged(itemPicker.selectedItems,itemsBefore,'Uncheck all removed existing manual items')
    itemPicker.filter:setText('seed');itemPicker.needRebuild=true;itemPicker:prerender()
    itemPicker.btnAll.onclick(itemPicker)
    assert(itemPicker.toolkitTagRule.mode=='any' and itemPicker.toolkitTagRule.include[1]=='seed'
        and openedRulePicker==previousEditor, 'Select all did not directly select the partial filtered tag')
    unchanged(itemPicker.selectedItems,itemsBefore,'Select all rule Apply persisted localized names')
    assert(next(itemPicker.selectedCats)==nil,'Select all broadened a partial category')
    itemPicker.toolkitTagRuleButton.onclick(itemPicker)
    assert(openedRulePicker.tagSources()==itemPicker.toolkitTagCatalog.tagSources,'dynamic editor chooser lacks the cached projections')
    itemPicker.onlyChecked=true
    openedRulePicker.onApply({mode='all',include={},exclude={'seed'}})
    itemPicker:prerender()
    assert(not find(itemPicker,'seed'), 'advanced Apply failed to refresh checked rows')
    assert(catalogReads == readsBefore + 1 and tagReads == projectionReads,
        'search, selection, saved-category changes or rule opening re-enumerated the item/tag catalog')
end
do
    local items, reads = {}, 0
    for index = 1, 150 do items[index] = script('Async '..index, 'AsyncCategory', {'snack'}) end
    local test = createFixture(control, ruleApi, {
        categories = function() error('loading tags forced a synchronous category scan') end,
        scriptItems = function() reads = reads + 1; return items end})
    local clock, now = getTimestampMs, 0
    getTimestampMs = function() now = now + 1; return now end
    local projections, contexts = tagReads, projectionContexts
    local picker = test.openRaw()
    assert(picker.toolkitTagCatalogPending and not picker.toolkitTagCatalog and reads == 1 and tagReads == projections,
        'opening projected scripts synchronously or exposed a partial catalog')
    assert(picker.emptyListKey == 'LoadingTags' and picker.listbox.count == 0)
    items[1] = script('Changed after snapshot', 'LaterCategory', {'electrical'})
    local editorBefore = openedRulePicker
    picker.toolkitTagRuleButton.onclick(picker)
    picker.btnAll.onclick(picker)
    picker.listbox.onmousedown(picker, {tag='snack',categories={},toolkitTagRow=true,requiresRule=true})
    assert(openedRulePicker == editorBefore and not picker.toolkitTagRuleTouched,
        'partial catalog authorized a chooser or selection')
    picker:prerender()
    assert(tagReads == projections + 5 and projectionContexts == contexts + 1
        and picker.toolkitTagCatalogPending and not picker.toolkitTagCatalog,
        'one frame did not respect its time budget and fresh recipe context')
    assert(picker.toolkitTagRuleButton.enable == false and picker.btnAll.enable == false)
    picker:setPriority(7)
    assert(picker.priorityEntry:getInternalText() == '7', 'loading blocked an independent draft control')
    local frames = 1
    while picker.toolkitTagCatalogPending do
        local before = tagReads
        picker:prerender(); frames = frames + 1
        assert(tagReads - before <= 5, 'later frame exceeded the projection budget')
        assert(frames < 100, 'bounded catalog did not finish')
    end
    assert(adapter.catalogReady(picker) and projectionContexts == contexts + frames and reads == 1
        and picker.toolkitTagCatalog.groups.AsyncCategory.count == 150
        and not picker.toolkitTagCatalog.groups.LaterCategory,
        'completion did not atomically publish the captured raw script snapshot')
    assert(picker.toolkitTagRuleButton.enable and picker.btnAll.enable and find(picker,'snack'))

    picker = test.openRaw()
    local pending = picker.toolkitTagCatalogScan
    picker:prerender()
    local before = tagReads
    picker:closePicker(); picker:prerender()
    assert(pending.cancelled and not picker.toolkitTagCatalogPending and tagReads == before
        and not adapter.stepCatalog(picker), 'close did not cancel owned work')
    picker = test.openRaw()
    pending = picker.toolkitTagCatalogScan
    items = {script('Fresh revision', 'FreshCategory', {'electrical'})}
    tagRevision = tagRevision + 1
    picker:prerender()
    assert(pending.cancelled and adapter.catalogReady(picker)
        and picker.toolkitTagCatalog.visibleCategories[1] == 'FreshCategory'
        and not picker.toolkitTagCatalog.groups.AsyncCategory,
        'revision change published old partial work instead of restarting')
    items = {script('Fresh reopen', 'ReopenedCategory', {'readable'})}
    picker = test.open()
    assert(picker.toolkitTagCatalog.visibleCategories[1] == 'ReopenedCategory',
        'reopen reused a previous window catalog')
    getTimestampMs = clock
end
do
    local visible = script('Visible', 'OC_Snack', {'food', 'snack'})
    local duplicate = script('Duplicate', 'OC_Snack', {'food', 'snack'})
    local hidden = script('Hidden', 'OC_Snack', {'food'})
    local hiddenOnly = script('Hidden only', 'HiddenCategory', {'hidden'})
    local obsolete = script('Obsolete', 'ObsoleteCategory', {'obsolete'})
    local incomplete = script('Incomplete', 'IncompleteCategory', {'incomplete'})
    for _, item in ipairs({visible, duplicate, hidden, hiddenOnly, obsolete}) do
        item.isHidden = function() return item == hidden or item == hiddenOnly end
        item.getObsolete = function() return item == obsolete end
    end
    incomplete.getObsolete = function() return true end
    local scripts, reads, categoryReads = {visible, duplicate, hidden, hiddenOnly, obsolete, incomplete}, 0, 0
    local forScript = itemCategories.forScript
    itemCategories.forScript = function(item)
        categoryReads = categoryReads + 1; return forScript(item)
    end
    local test = createFixture(control, ruleApi, {
        categories = function() error('enabled window performed a separate category scan') end,
        scriptItems = function() reads = reads + 1; return scripts end,
        cats = {MissingModCategory = true}})
    local projections = tagReads
    local picker = test.open()
    local catalog = picker.toolkitTagCatalog
    assert(reads == 1 and tagReads == projections + 4 and categoryReads == 5,
        'window did not classify the current script universe exactly once')
    assert(#catalog.visibleCategories == 2 and catalog.visibleCategories[1] == 'IncompleteCategory'
        and catalog.visibleCategories[2] == 'OC_Snack', 'visible/hidden/obsolete inclusion policies changed')
    assert(catalog.groups.OC_Snack.count == 3 and catalog.groups.OC_Snack.tags.snack == 2
        and catalog.groups.HiddenCategory and not catalog.groups.ObsoleteCategory
        and not catalog.groups.IncompleteCategory, 'hidden or obsolete scripts changed routing coverage')
    assert(#catalog.tagSources == 3, 'chooser retained duplicate script tag sources')
    local snack = assert(find(picker, 'snack'))
    assert(snack.requiresRule and #snack.categories == 0, 'hidden shared-category script broadened a partial tag')
    assert(find(picker, 'MissingModCategory'), 'saved missing category was lost')
    picker.filter:setText('food'); picker:prerender()
    picker.toolkitTagRuleButton.onclick(picker); openedRulePicker.tagSources()
    assert(reads == 1 and categoryReads == 5, 'filtering or rule opening reclassified scripts')
    visible.uiCategory = 'ChangedCategory'
    scripts = {visible}
    local reopened = test.open()
    assert(reads == 2 and categoryReads == 6 and #reopened.toolkitTagCatalog.visibleCategories == 1
        and reopened.toolkitTagCatalog.visibleCategories[1] == 'ChangedCategory',
        'reopening reused stale categories or script projections')
    itemCategories.forScript = forScript
end
OrganizedCategories = nil
do
    categoryTags.OC_ToyWeapons={'weapon','ranged'}
    availableCats[#availableCats+1]='OC_ToyWeapons'
    scriptCatalog={script('Cap gun','OC_ToyWeapons',{'toy'})}
    OrganizedCategories={getScriptInventoryDisplayCategory=function(value) return value.uiCategory end}
    open();local toyPicker=LootSorter._picker
    local toy=assert(find(toyPicker,'toy'))
    assert(toy.requiresRule and #toy.categories==0,
        'all currently known items were refined, but their legacy category was selected wholesale')
    click(toyPicker,'toy')
    assert(toyPicker.toolkitTagRule.include[1]=='toy' and not toyPicker.selectedCats.OC_ToyWeapons,
        'toy checkbox stored a ranged-weapon category instead of the toy rule')
    scriptCatalog[#scriptCatalog+1]=script('Crossbow','OC_ToyWeapons',{'weapon','ranged'})
    open();toyPicker=LootSorter._picker
    toy=assert(find(toyPicker,'toy'))
    assert(toy.requiresRule and #toy.categories==0,'new real weapon broadened the toy row')
    OrganizedCategories=nil
end
do
    categoryTags.OC_Reading={'readable'}
    availableCats[#availableCats+1]='OC_Reading'
    scriptCatalog={script('Book','OC_Reading',{'readable'})}
    OrganizedCategories={getScriptInventoryDisplayCategory=function(value) return value.uiCategory end}
    open();local readingPicker=LootSorter._picker
    local readable=assert(find(readingPicker,'readable'))
    assert(readable.requiresRule and #readable.categories==0,'content capability collapsed into a category')
    click(readingPicker,'readable')
    assert(readingPicker.toolkitTagRule.include[1]=='readable' and not readingPicker.selectedCats.OC_Reading,
        'Readable checkbox will accept unreadable instances from the same category')
    OrganizedCategories=nil
end
do
    categoryTags.OC_Fruit={'food','perishable'}
    availableCats[#availableCats+1]='OC_Fruit'
    local actual={'food','perishable'}
    actual.menuChoices={'food','perishable','fresh','stale','rotten'}
    scriptCatalog={script('Apple','OC_Fruit',actual)}
    OrganizedCategories={getScriptInventoryDisplayCategory=function(value) return value.uiCategory end}
    open();local foodPicker=LootSorter._picker
    local rotten=assert(find(foodPicker,'rotten'),'future food states missing from script choices')
    assert(rotten.requiresRule and #rotten.categories==0,'freshness choice collapsed into food category')
    click(foodPicker,'rotten')
    assert(foodPicker.toolkitTagRule.include[1]=='rotten' and not foodPicker.selectedCats.OC_Fruit,
        'rotten-only choice will collect every apple')
    assert(not find(foodPicker,'compost'),'removed Compost tag remains in the container picker')
    assert(#actual==2,'picker injected possible states into actual script tags')
    OrganizedCategories=nil
end
do
    local first = script('First state', 'OC_Fruit', {'food'})
    local second = script('Second state', 'OC_Fruit', {'food'})
    first.tags.menuChoices, second.tags.menuChoices = {'food', 'fresh'}, {'food', 'stale'}
    scriptCatalog = {first, second}
    open(); local p = LootSorter._picker
    assert(find(p, 'fresh') and find(p, 'stale'), 'state metadata was lost before catalogue choices')
    local sources = p.toolkitTagCatalog.tagSources
    local fresh, stale = false, false
    for _, source in ipairs(sources) do
        for _, id in ipairs(source) do fresh = fresh or id == 'fresh'; stale = stale or id == 'stale' end
    end
    assert(fresh and stale, 'deduplication collapsed distinct state choices with identical actual tags')
    local readsBefore = catalogReads
    customIds, tagRevision = {'custom:unassigned'}, tagRevision + 1
    p:prerender()
    assert(find(p, 'custom:unassigned') and catalogReads == readsBefore + 1,
        'tag revision did not rebuild the open window catalogue/custom choices')
    p:prerender()
    assert(catalogReads == readsBefore + 1, 'stable revision rescanned the catalogue')
    customIds = {}
end
do
    local grouped = {groups = {{include = {'readable', 'seed'}, exclude = {'rotten'}},
        {include = {'electrical'}, exclude = {'fresh'}}}}
    local groupedPicker = {selectedCats = {}, toolkitTagRule = grouped,
        activeList = function() return availableCats end}
    local selectionsBefore = #appearanceSelections
    adapter.select(groupedPicker, {tag = 'readable', categories = {}, requiresRule = true}, false)
    assert(groupedPicker.toolkitTagRule == grouped and not groupedPicker.toolkitTagRuleTouched
        and openedRulePicker.selectedTag == 'readable' and #appearanceSelections == selectionsBefore,
        'grouped checkbox mutated an AND branch or appearance before Apply')
    assert(openedRulePicker.rule.groups[1].include[2] == 'seed'
        and openedRulePicker.rule.groups[2].exclude[1] == 'fresh', 'grouped checkbox lost branches/exclusions')
    local checked, total = adapter.state({}, {tag = 'readable', requiresRule = true}, grouped)
    assert(checked == 1 and total == 1, 'grouped positive tag is unchecked')
    local beforeNormalizations = normalizations
    local row = {tag = 'readable', requiresRule = true, categories = {}}
    local previousTarget = p.listbox.target
    p.listbox.target = groupedPicker
    for _ = 1, 10 do
        assert(adapter.state({}, row, grouped) == 1)
        adapter.drawRow(p.listbox, 0, {item = row, height = 28, index = 1})
    end
    p.listbox.target = previousTarget
    assert(normalizations == beforeNormalizations, 'grouped checkbox state/draw normalized the full rule per frame')
    adapter.select(groupedPicker, {key = 'Exact', categories = {'Exact'}}, true)
    assert(groupedPicker.selectedCats.Exact and groupedPicker.toolkitTagRule == grouped,
        'grouped rule prevented independent exact category picks')
end
print('Quartermaster tag view checks passed: owned controls, exact/refined selections, filters, controller, modes, reopens and opt-out.')
scriptCatalog = {}
enabled = true
ruleApi.presetsSynced = function() return true end
local function checkSaveContract()
    local rules = ruleApi
    local fixture = createFixture(control, rules)
    local open, save, reply = fixture.open, fixture.save, fixture.reply
    local obj, failures, publications = fixture.object, fixture.failures, fixture.publications
    local function rulePicker() return openedRulePicker end
    local initialRule = {mode = 'all', include = {'food'}, exclude = {'perishable'}}
    obj.md.PZSTQuartermasterTagRules, obj.md.ruleRevision = {['0'] = initialRule}, 9
    local initialized = open()
    assert(initialized.toolkitTagRuleRevision == 9 and initialized.toolkitTagRule.include[1] == 'food'
        and initialized.toolkitTagRule.exclude[1] == 'perishable' and initialized.toolkitTagRule ~= initialRule,
        'owned construction did not load detached box rule state and revision')
    obj.md.PZSTQuartermasterTagRules, obj.md.ruleRevision = nil, nil
    local p = open()
    do
        local item = {category = 'Material', getDisplayCategory = function(self) return self.category end,
            setDisplayCategory=function(self,category) self.category=category end,
            getModData=function() return {OC_DisplayCategory='OC_FoodPerishable'} end}
        local contents = {getItems = function()
            return {size = function() return 1 end, get = function() return item end}
        end}
        obj.getContainerByIndex = function() return contents end
        local visible = p:contentsSet()
        assert(item.category == 'OC_FoodPerishable' and visible.OC_FoodPerishable and not visible.Material,
            'owned picker must prepare preserved instance overrides without an external wrapper')
    end
    assert(p.btnSave.cachedOnclick == p.btnSave.onclick and p.btnSave.onclick == p.onSave,
        'owned Save callback was replaced')
    assert(p.onSave == getmetatable(p).onSave and p.closePicker == getmetatable(p).closePicker
        and p.close == p.closePicker, 'owned Save or close method was replaced')
    for _, name in ipairs({'activeList', 'rebuild', 'layout', 'setMode', 'prerender',
        'insertNewLineOfButtons', 'onSave', 'closePicker'}) do
        assert(rawget(p, name) == nil, 'picker still replaces inherited method: ' .. name)
    end
    assert(p.listbox.onmousedown == p.onRowClick and p.listbox.doDrawItem == p.doDrawItem
        and p.btnAll.cachedOnclick == p.onSelectFiltered and p.toolkitTagSwitch.cachedOnclick == p.onTagView
        and p.toolkitTagRuleButton.cachedOnclick == p.onTagRule, 'owned tag dispatch was replaced')
    assert(p.children[#p.children] == p.dimmer and not p.dimmer.visible)
    local rows = p.joypadButtonsY
    assert(rows[1][1] == p.groupSelect and rows[5][1] == p.chkNoDuplicates
        and rows[6][1] == p.toolkitTagSwitch and rows[7][1] == p.toolkitTagRuleButton
        and rows[8][1] == p.listbox, 'native controller rows omitted container/tag controls')
    assert(p.listbox.vscroll.x == p.listbox.width - 16 and p.listbox.vscroll.height == p.listbox.height)
    assert(find(p, 'food') and find(p, 'MissingModCategory'), 'actual picker did not build tag/saved-category rows')
    local createRule = {mode = 'all', include = {'food'}, exclude = {'perishable'}}
    p.toolkitTagRule = createRule
    p.onPresetNamed(p, {internal = 'OK', parent = {entry = {getText = function() return 'New pantry' end}}})
    assert(fixture.presetPayload().name == 'New pantry' and fixture.presetPayload().expectExisting == false
        and fixture.presetPayload().cats == p.selectedCats and fixture.presetPayload().items == p.selectedItems
        and fixture.presetPayload().pzstTagRule.include[1] == 'food' and fixture.presetPayload().pzstTagRule.exclude[1] == 'perishable'
        and fixture.presetPayload().pzstTagRule ~= createRule, 'new preset entry lost its owning picker rule or selections')
    fixture.presetReply('ok')
    p.toolkitTagRule = nil
    local _, foodIndex = find(p, 'food')
    p.listbox.doDrawItem(p.listbox, 0, p.listbox.items[foodIndex])
    assert(p.listbox.drawnText == 'food (UI_PZST_QMTagRule)' and p.listbox.semanticIcon.id == 'food',
        'actual picker lost semantic rule row rendering')
    click(p, 'food')
    assert(p.toolkitTagRule.include[1]=='food' and not p.selectedCats.OC_FoodPerishable and not p.selectedCats.food)
    p.toolkitTagSwitch.onclick(p); p:prerender()
    click(p, 'OC_FoodPerishable');click(p, 'OC_FoodPerishable')
    assert(p.selectedCats.OC_Food and not p.selectedCats.OC_FoodPerishable)
    p.btnModeItem.onclick(p); p:prerender()
    assert(p.mode == 'items' and not p.toolkitTagSwitch.visible and find(p, 'Hammer'))
    click(p, 'Hammer')
    p.btnModePreset.onclick(p); p:prerender()
    click(p, 'Pantry'); click(p, 'Pantry')
    assert(p.selectedPresets.Pantry == 'generation', 'native preset generation lost')
    p.btnModeCat.onclick(p); p:prerender()
    p.toolkitTagRuleButton.onclick(p)
    local draft = rulePicker()
    assert(draft.owner == p and draft.player and #draft.categories == 4)
    draft.onApply({mode = 'all', include = {'food'}, exclude = {}})
    p.chkNoDuplicates.onclick(p)
    assert(p.noDuplicates and p.priority == 4, 'duplicate policy changed fill priority')
    save(p); save(p)
    assert(fixture.pendingRule() and not p.removed and #publications == 0, 'native Save bypassed asynchronous rule verdict')
    p.selectedCats.Later, p.selectedItems.Later, p.priority, p.noDuplicates = true, true, 99, false
    p.selectedPresets.Later = 42
    p.toolkitTagRule.include[1] = 'electrical'
    p.toolkitTagRule, p.toolkitTagRuleTouched = nil, nil
    save(p)
    assert(#publications == 0 and fixture.pendingRule().rule.include[1] == 'food',
        'pending Save used a cleared rule to bypass its in-flight guard or aliased its rule draft')
    reply('ok')
    assert(p.removed and LootSorter._picker == nil and #publications == 1 and fixture.coordinates() == 1,
        'designation Save did not publish exactly once')
    local saved = publications[1]
    assert(saved.cats.OC_Food and saved.cats.MissingModCategory and not saved.cats.Later and not saved.cats.food
        and saved.items.Hammer and not saved.items.Later and saved.priority == 4 and saved.noDuplicates == true
        and saved.presets.Pantry == 'generation' and not saved.presets.Later
        and saved.pzstTagRule.include[1] == 'food', 'actual native save mixed snapshot and later edits')

    local function startPending()
        local owner = open()
        owner.toolkitTagRule, owner.toolkitTagRuleTouched = {mode = 'all', include = {'food'}, exclude = {}}, true
        save(owner)
        return owner
    end
    for _, verdict in ipairs({'stale', 'denied', 'timeout'}) do
        p = startPending()
        assert(p.noDuplicates, 'reopened picker lost saved duplicate policy')
        p.chkNoDuplicates.onclick(p)
        reply(verdict)
        assert(not p.removed and LootSorter._picker == p and #publications == 1 and fixture.coordinates() == 1,
            'rule ' .. verdict .. ' closed actual picker or wrote exact selections')
        assert(p.noDuplicates == false and obj.md.LSBoxNoDuplicates['0'] == true,
            'refused save lost duplicate policy draft or changed live policy')
    end
    assert(#failures == 3)
    save(p); reply('ok')
    assert(p.removed and #publications == 2 and fixture.coordinates() == 2, 'rule refusal prevented retry')
    assert(obj.md.LSBoxNoDuplicates['0'] == nil and publications[2].noDuplicates == false,
        'disabling duplicate policy did not clear persisted field')
    for _, closeVia in ipairs({'close', 'replace', 'retarget'}) do
        p = startPending()
        local writes = #publications
        if closeVia == 'close' then p:close() end
        local replacement
        if closeVia == 'retarget' then p.targetCI = 1 else replacement = open() end
        reply('ok')
        assert(#publications == writes + 1 and fixture.coordinates() == writes + 1,
            'accepted save was not published once by authority after ' .. closeVia)
        if replacement then
            assert(LootSorter._picker == replacement and not replacement.removed,
                'late native save closed new owner after ' .. closeVia)
        end
    end
    obj.md.PZSTQuartermasterTagRules = nil
    p = open()
    local writes = #publications
    save(p)
    assert(not p.removed and fixture.pendingRule() and #publications == writes,
        'plain designation bypassed the full configuration authority')
    reply('ok')
    assert(p.removed and not fixture.pendingRule() and #publications == writes + 1 and fixture.coordinates() == writes + 1,
        'plain designation did not publish once after acceptance')
    p = open()
    LootSorter.openPresetEditor('Pantry', 0, p)
    local editor = assert(LootSorter._presetEditor)
    editor:prerender()
    assert(p.dimmer.visible and not editor.btnModePreset.visible and not editor.chkNoDuplicates.visible and find(editor, 'food'))
    editor:configJoypad()
    for _, row in ipairs(editor.joypadButtonsY) do
        for _, button in ipairs(row) do assert(button ~= editor.chkNoDuplicates, 'preset navigation exposes container policy') end
    end
    editor.toolkitTagRuleButton.onclick(editor)
    rules.presetsSynced = function() return false end
    save(editor)
    assert(fixture.presetPayload().pzstTagRule == nil and fixture.presetPayload().baseRev == 7
        and fixture.presetPayload().baseGen == 'generation', 'untouched unsynced preset save cleared rule metadata')
    fixture.presetReply('stale', {action = 'save'})
    editor.toolkitTagRule, editor.toolkitTagRuleTouched = {mode = 'all', include = {'food'}, exclude = {}}, true
    save(editor)
    assert(not editor.removed and fixture.presetPayload().expectExisting and fixture.presetPayload().baseRev == 7
        and fixture.presetPayload().baseGen == 'generation' and fixture.presetPayload().pzstTagRule.include[1] == 'food',
        'native preset save lost rule metadata or conflict tokens')
    rules.presetsSynced = function() return true end
    fixture.presetReply('stale', {action = 'save'})
    assert(not editor.removed and p.dimmer.visible and failures[#failures] == 'stale')
    save(editor); fixture.presetReply('ok')
    assert(editor.removed and LootSorter._presetEditor == nil and not p.dimmer.visible)
    print('Owned Quartermaster picker Save contract passed: complete publication, asynchronous verdicts and owner guards.')
end
checkSaveContract()


-- The picker projects dead links privately; scans and merely opening/rendering the editor do not
-- publish a stale client object. Copy remains a lossless snapshot of the stored designation.
do
    local fixture = createFixture(control, ruleApi)
    local obj, store, synced = fixture.object, {}, true
    local originalIsClient = isClient
    obj.md.LSBoxPresets = {['0'] = {Pantry = 10, Missing = 30, Valid = 20, Legacy = true}}
    LootSorter.getPresetStore = function() return store end
    LootSorter.arePresetsSynced = function() return synced end
    local p = fixture.open()
    fixture.save(p)
    assert(p.selectedPresets.Pantry == 10 and p.selectedPresets.Missing == 30
        and fixture.pendingRule().configuration.presets.Pantry == 10,
        'SP picker removed world links absent from the per-machine library')
    fixture.reply('stale')
    isClient = function() return true end
    synced = false
    p = fixture.open()
    assert(p.selectedPresets.Pantry == 10 and p.selectedPresets.Missing == 30
        and p.btnModePreset.title == 'Presets (4)', 'unsynced picker discarded stored preset links')
    store = {Pantry = {gen = 11}, Valid = {gen = 20}, Legacy = {gen = 40}}
    synced = true
    p.btnModePreset.onclick(p); p:prerender()
    assert(not p.selectedPresets.Pantry and not p.selectedPresets.Missing
        and p.selectedPresets.Valid == 20 and p.selectedPresets.Legacy == true
        and p.btnModePreset.title == 'Presets (2)', 'picker did not resolve links after synchronization')
    assert(find(p, 'Pantry') and find(p, 'Valid'), 'link projection hid an available preset row')
    p.onlyChecked, p.needRebuild = true, true
    p:prerender()
    assert(not find(p, 'Pantry') and find(p, 'Valid') and find(p, 'Legacy'),
        'Only Checked retained a different preset generation')
    assert(#fixture.publications == 0 and fixture.coordinates() == 0
        and obj.md.LSBoxPresets['0'].Pantry == 10 and obj.md.LSBoxPresets['0'].Missing == 30,
        'picker read published or mutated the stored designation')
    local copied = LootSorter.copyDesignation(obj, 0)
    assert(copied.presets.Pantry == 10 and copied.presets.Missing == 30,
        'read-side projection changed lossless Copy sorting')
    -- Save can run before another prerender after a new snapshot arrives.
    p.selectedPresets.Pantry = 10
    fixture.save(p)
    local pending = assert(fixture.pendingRule()).configuration
    assert(not pending.presets.Pantry and not pending.presets.Missing and pending.presets.Valid == 20,
        'Save submitted links excluded by checked/count projection')
    assert(obj.md.LSBoxPresets['0'].Pantry == 10 and #fixture.publications == 0,
        'Save cleaned object links before authority acceptance')
    fixture.reply('ok')
    assert(not obj.md.LSBoxPresets['0'].Pantry and obj.md.LSBoxPresets['0'].Valid == 20
        and #fixture.publications == 1, 'ordinary accepted Save did not own link cleanup')
    isClient = originalIsClient
end
print('Quartermaster preset-link view passed: delayed sync, generations, checked/count/save consistency, read-only projection and lossless Copy.')

-- Group selection owns a complete detached draft; Save scope never follows checkbox state.
do
    groupRecords = {books = {id = 'books', rev = 7, createdBy = 'survivor',
        configuration = {cats = {OC_Electrical = true}, items = {Hammer = true}, presets = {}, priority = 12,
            noDuplicates = false, appearance = {name = 'Books', icon = {kind = 'item', value = 'Base.Book'},
                color = {r = .2, g = .3, b = .4, a = 1}}},
        rule = {mode = 'all', include = {'electrical'}, exclude = {'perishable'}}}}
    local Controls = require 'PZSurvivorToolkit/ContainerGroupControls'
    local fixture = createFixture(control, ruleApi)
    local p = fixture.open()
    assert(p.groupSelect and not p.groupScope.visible and not p.containerGroupRecord,
        'fresh container did not start with own settings')
    p.groupSelect.onclick(p)
    local menu = fixture.contextMenu()
    assert(menu.origin == p and menu.options[1].callback == Controls.select
        and menu.options[2].callback == Controls.createGroup and menu.options[3].title == 'Books',
        'group selector lacks own/new/existing choices or controller return focus')
    menu.options[3].callback(menu.options[3].target, menu.options[3].key)
    assert(p.selectedCats.OC_Electrical and not p.selectedCats.OC_Food and p.selectedItems.Hammer
        and p.priority == 12 and not p.noDuplicates and p.toolkitTagRule.include[1] == 'electrical'
        and p.toolkitAppearance.name == 'Books' and p.toolkitAppearance.icon.value == 'Base.Book'
        and p.toolkitAppearance.color.g == .3, 'joining group did not load every sorting/appearance field')
    assert(p.groupScope.visible and p.containerGroupScope == 'local' and p.joypadButtonsY[2][1] == p.groupScope
        and p.groupHint.y + p.groupHint.height <= p.sortingHeading.y,
        'group scope default, layout or controller row is missing')
    p:setWidth(420);p:setHeight(600);p:layout()
    assert(p.groupSelect.x + p.groupSelect.width <= 410 and p.groupScope.x + p.groupScope.width <= 410
        and p.listbox.y + p.listbox.height < p.btnSave.y, 'group controls overlap minimum-width layout')
    fixture.save(p)
    local pending = assert(fixture.pendingRule()).configuration
    assert(pending.groupOperation.mode == 'join' and pending.groupOperation.id == 'books',
        'unchanged selection detached instead of joining group')
    Controls.select(p, nil)
    assert(p.containerGroupRecord.id == 'books', 'pending save allowed group retargeting')
    fixture.reply('denied')
    p.selectedCats.Local = true
    fixture.save(p)
    pending = fixture.pendingRule().configuration
    assert(pending.groupOperation.mode == 'detach' and pending.cats.Local and pending.appearance.name == 'Books',
        'local edit failed to detach with a complete copy')
    assert(not groupRecords.books.configuration.cats.Local, 'local draft edited the shared group')
    fixture.reply('denied')
    Controls.setScope(p, 'group')
    fixture.save(p)
    pending = fixture.pendingRule().configuration
    assert(pending.groupOperation.mode == 'update' and pending.groupOperation.id == 'books'
        and pending.groupOperation.baseRevision == 7 and pending.cats.Local and not pending.noDuplicates,
        'explicit whole-group save lost revision or depended on noDuplicates')
    p.toolkitAppearance.color.g, p.selectedCats.Local = .9, nil
    assert(pending.appearance.color.g == .3 and pending.cats.Local, 'in-flight group save aliased later UI edits')
    fixture.reply('staleGroup')
    assert(not p.removed and p.containerGroupScope == 'group' and p.toolkitAppearance.color.g == .9,
        'stale group response discarded retry draft')
    groupEditable = false
    p.groupScope.onclick(p)
    assert(fixture.contextMenu().options[2].notAvailable, 'non-owner can choose whole-group edits')
    fixture.save(p)
    assert(not fixture.pendingRule(), 'non-owner submitted whole-group update')
    groupEditable = true
    Controls.createGroup(p)
    p.toolkitAppearance.name = ''
    fixture.save(p)
    assert(not fixture.pendingRule(), 'unnamed group was submitted')
    p.toolkitAppearance.name = 'New books'
    fixture.save(p)
    pending = fixture.pendingRule().configuration
    assert(pending.groupOperation.mode == 'create' and pending.appearance.name == 'New books'
        and pending.appearance.icon.value == 'Base.Book' and pending.priority == 12 and not pending.noDuplicates,
        'create group lost appearance or required duplicate mode')
    fixture.reply('denied')

    fixture.object.md.PZSTContainerGroups = {['0'] = 'books'}
    p = fixture.open()
    assert(p.containerGroupRecord.id == 'books' and p.containerGroupScope == 'local'
        and p.toolkitAppearance.name == 'Books', 'reopened member did not resolve group')
    Controls.select(p, nil); fixture.save(p)
    assert(fixture.pendingRule().configuration.groupOperation.mode == 'detach', 'own settings kept group membership')
    fixture.reply('denied')
    groupsSynced = false
    p = fixture.open(); fixture.save(p)
    assert(not fixture.pendingRule(), 'unsynchronized member draft was saved as local settings')
    groupsSynced = true; p:prerender()
    assert(p.containerGroupRecord.id == 'books' and p.toolkitAppearance.name == 'Books',
        'late group synchronization did not hydrate an untouched draft')
    local editor = fixture.edit(p)
    assert(not editor.groupSelect and not editor.groupScope, 'legacy preset acquired container-group controls')
    editor:closePicker(); p:closePicker()
    groupRecords = {}
end
print('Quartermaster group draft checks passed: complete inheritance, join/create, local detach, scoped CAS, pending snapshots, permissions and late sync.')
