local enabled, starts, creates = true, {}, {}
local openedRulePicker, adapter
local scriptCatalog = {}
local catalogReads, tagReads = 0, 0
local appearanceSelections={}
local ruleApi = {getBoxRevision = function(obj) return obj and obj.md.ruleRevision or 0 end,
    getBox = function() end, getPreset = function() end,
    presetsSynced = function() return true end}
getSpecificPlayer = function() return {} end
PZSurvivorToolkit = {}
local itemCategories = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemCategories.lua')
local categoryTags = {OC_Food = {'food'}, OC_FoodPerishable = {'food', 'perishable'},
    OC_Electrical = {'electrical'}, OC_FoodElectrical = {'food', 'electrical'}}
require = function(name)
    if name == 'LootSorter_Categories' then return end
    if name == 'PZSurvivorToolkit/ContainerAppearanceControls' then
        return {create=function() end, layout=function(_, top) return top end,
            close=function() end, value=function() end,
            select=function(picker,kind,key)
                if key then appearanceSelections[#appearanceSelections+1]={picker=picker,kind=kind,key=key} end
            end}
    end
    if name == 'PZSurvivorToolkit/ItemCategories' then return itemCategories end
    if name == 'PZSurvivorToolkit/TagVisuals' then
        return {get=function(id) return {r=0.3,g=0.7,b=0.3,texture=id and {id=id} or nil} end}
    end
    if name == 'PZSurvivorToolkit/QuartermasterTagRuleClient' or name == 'PZSurvivorToolkit/QuartermasterTagRules' then return ruleApi end
    if name == 'PZSurvivorToolkit/QuartermasterTags' then return assert(adapter) end
    if name == 'PZSurvivorToolkit/TagRulePicker' then return {open = function(args) openedRulePicker = args end} end
    assert(name == 'PZSurvivorToolkit/ItemTags')
    return {enabled = function() return enabled end,
        normalizeRule = function(value)
            local result = {mode = value and value.mode or 'all', include = {}, exclude = {}}
            for _, field in ipairs({'include', 'exclude'}) do
                for _, id in ipairs(value and value[field] or {}) do result[field][#result[field] + 1] = id end
            end
            return result
        end,
        ruleActive = function(value) return value and (#value.include > 0 or #value.exclude > 0) or false end,
        forCategory = function(category) return categoryTags[category] or {'category:' .. category} end,
        forScriptItem = function(script) tagReads = tagReads + 1; return script.tags end,
        label = function(id) return id end}
end
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end},
    OnCreatePlayer = {Add = function(fn) creates[#creates + 1] = fn end}}
getText, getTextOrNull = function(key) return key end, function() return nil end
UIFont = {Medium = 1}
Joypad = {AButton = 1, YButton = 2, BButton = 3, RBumper = 4, LBumper = 5}
getTexture = function() return {} end
getTextManager = function() return {getFontHeight = function() return 12 end} end
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
    scriptItems = function() catalogReads = catalogReads + 1; return scriptCatalog end,
    cats = storedCats, items = storedItems})
local open = fixture.open
local function edit() return fixture.edit(LootSorter._picker) end
local function find(p, tagOrCategory)
    for index, row in ipairs(p.listbox.items) do
        if row.item.tag == tagOrCategory or row.item.key == tagOrCategory then return row.item, index end
    end
end
local function click(p, id) local row = assert(find(p, id), 'missing ' .. id); p.listbox.onmousedown(p, row); p:prerender() end
assert(open())
local p = LootSorter._picker
assert(p.children[#p.children] == p.dimmer, 'tag switch bypasses preset dimmer')
assert(p.joypadButtonsY[4][1] == p.toolkitTagSwitch and p.joypadButtonsY[5][1] == p.toolkitTagRuleButton
    and p.listbox.y == 192)
p:setWidth(520); p:setHeight(700); p:prerender()
assert(p.toolkitTagSwitch.width == 500 and p.toolkitTagRuleButton.width == 500
    and p.listbox.width == 500 and p.listbox.y == 192 and p.listbox.height == 464
    and p.listbox.vscroll.x == 484 and p.listbox.vscroll.height == 464
    and p.dimmer.width == 520 and p.dimmer.height == 700, 'owned resize lost tag controls or list clipping')
p:layout(); p:layout()
assert(p.listbox.y == 192 and p.listbox.height == 464, 'repeated layout shifted the tag view')
p:setWidth(396); p:setHeight(580); p:prerender()
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
p.filter:setText(''); p.needRebuild = true; p:prerender()
assert(find(p, 'food') and find(p, 'electrical') and find(p, 'perishable'))
assert(find(p, 'MissingModCategory') and find(p, 'OtherMod'), 'unknown categories lost')
local food, fi = find(p, 'food')
p.listbox.selected, p.listbox.mouseoverselected = fi, fi
p.listbox.onJoypadDown(p.listbox, Joypad.YButton)
p.listbox.onRightMouseUp(p.listbox)
assert(fixture.contextMenu() == nil, 'tag row opened an exact-category context menu')
p.listbox.doDrawItem(p.listbox, 0, p.listbox.items[fi])
assert(p.listbox.semanticIcon and p.listbox.semanticIcon.id=='food','tag association icon missing')
assert(p.listbox.drawnText == 'food (1/3)' and not p.listbox.ticks, 'partial selection not displayed')
local dash = false
for _, size in ipairs(p.listbox.draws) do if size[1] == 10 and size[2] == 2 then dash = true end end
assert(dash, 'partial checkbox has no dash')
click(p, 'food')
assert(p.selectedCats.OC_Food and p.selectedCats.OC_FoodPerishable and p.selectedCats.OC_FoodElectrical)
assert(not p.selectedCats.food, 'tag ID escaped into serialized category set')
p.toolkitTagSwitch.onclick(p); p:prerender()
assert(not p.toolkitTagView and find(p, 'OC_FoodPerishable') and find(p, 'MissingModCategory'))
assert(p.listbox.vscroll.x == p.listbox.width - 16 and p.listbox.vscroll.height == p.listbox.height
    and stencilWidth(p.listbox) > 300, 'exact-category refinement retained clipped scrollbar geometry')
click(p, 'OC_FoodPerishable')
assert(not p.selectedCats.OC_FoodPerishable and p.selectedCats.OC_Food, 'exact refinement lost')
p.toolkitTagSwitch.onclick(p); p:prerender()
food, fi = find(p, 'food')
p.listbox.doDrawItem(p.listbox, 0, p.listbox.items[fi])
assert(p.listbox.drawnText == 'food (2/3)')
p.onlyChecked, p.needRebuild = true, true; p:prerender()
assert(find(p, 'food') and not find(p, 'perishable'), 'Only Checked omitted partial tags or kept unchecked tag')
p.onlyChecked, p.onlyContents, p.needRebuild = false, true, true; p:prerender()
assert(find(p, 'food') and find(p, 'perishable') and not find(p, 'electrical'), 'Only Contents did not map exact categories')
p.onlyContents = false; p.filter:setText('electr'); p.needRebuild = true; p:prerender()
assert(#p.listbox.items == 1 and find(p, 'electrical'))
p.btnAll.onclick(p); p:prerender()
assert(p.selectedCats.OC_Electrical and p.selectedCats.OC_FoodElectrical)
p.filter:setText(''); p.needRebuild = true; p:prerender()
local _, ei = find(p, 'electrical'); p.listbox.selected = ei
p.listbox.onJoypadDown(p.listbox, Joypad.AButton); p:prerender()
assert(not p.selectedCats.OC_Electrical and not p.selectedCats.OC_FoodElectrical, 'controller A did not toggle tag batch')
p.listbox.onJoypadDown(p.listbox, Joypad.BButton, fixture.joypad)
assert(fixture.joypad.focus == p, 'controller did not leave the tag list')
p:setMode('items'); p:prerender()
assert(not p.toolkitTagSwitch.visible and p.listbox.y == 136 and find(p, 'Beans'))
assert(p.listbox.vscroll.height == 400 and stencilWidth(p.listbox) > 300, 'native Items layout clipped rows')
click(p, 'Hammer'); assert(p.selectedItems.Hammer and p.selectedItems.Beans)
p:setMode('presets'); p:prerender(); click(p, 'Pantry')
assert(not p.selectedPresets.Pantry and find(p, 'Pantry'), 'preset mode intercepted')
p:setMode('cats'); p:prerender()
-- View changes preserve exact keys; actual owned Save is checked below.
storedCats, storedItems = p.selectedCats, p.selectedItems
fixture.object.md.LSBox['0'], fixture.object.md.LSBoxItems['0'] = storedCats, storedItems
assert(storedCats.OC_Food and storedCats.MissingModCategory and not storedCats.food and storedItems.Hammer)
categoryTags.OC_FoodNew = {'food'}; availableCats[#availableCats + 1] = 'OC_FoodNew'
open(); local reopened = LootSorter._picker
assert(reopened ~= p and reopened.selectedCats.OC_Food and reopened.selectedCats.MissingModCategory)
assert(not reopened.selectedCats.OC_FoodPerishable and reopened.toolkitTagView, 'reopen rebuilt broad tag selections')
assert(not reopened.selectedCats.OC_FoodNew, 'saved tags automatically selected a later-added category')
local _, unknownIndex = find(reopened, 'MissingModCategory')
reopened.listbox.mouseoverselected = unknownIndex
reopened.listbox.onRightMouseUp(reopened.listbox)
assert(fixture.contextMenu().options[1].key == 'MissingModCategory', 'unknown category inspector lost')
reopened.listbox.selected = unknownIndex
reopened.listbox.onJoypadDown(reopened.listbox, Joypad.YButton)
assert(fixture.contextMenu().options[1].key == 'MissingModCategory', 'controller lost the unknown-category inspector')
edit(); local editor = LootSorter._presetEditor
click(editor, 'perishable')
assert(editor.selectedCats.OC_FoodPerishable and not editor.selectedCats.perishable)
reopened.btnClear.onclick(reopened); reopened:prerender()
assert(next(reopened.selectedCats) == nil and reopened.selection == reopened.selectedCats, 'native Uncheck all did not clear category batches')
click(reopened, 'food')
assert(reopened.selectedCats.OC_Food and reopened.selectedCats.OC_FoodNew, 'batch used a stale selectedCats table after Uncheck all')
enabled = false
reopened:prerender()
assert(not reopened.toolkitTagSwitch.visible and reopened.listbox.y == 136 and find(reopened, 'OC_Food'))
open(); local openedDisabled = LootSorter._picker
assert(openedDisabled.toolkitTagSwitch and not openedDisabled.toolkitTagSwitch.visible
    and openedDisabled.listbox.y == 136 and find(openedDisabled, 'OC_Food'), 'disabled picker did not retain native view')
enabled = true; openedDisabled:prerender()
assert(openedDisabled.toolkitTagSwitch.visible and openedDisabled.listbox.y == 192
    and find(openedDisabled, 'food'), 'picker opened while disabled did not enable tags without reopening')
assert(openedDisabled.joypadButtonsY[4][1] == openedDisabled.toolkitTagSwitch
    and openedDisabled.joypadButtonsY[5][1] == openedDisabled.toolkitTagRuleButton, 'live enable did not add controller navigation')
reopened:prerender()
assert(reopened.toolkitTagSwitch.visible and find(reopened, 'food'), 'setting toggle left a stale list')
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
    return {tags=tags,uiCategory=category,getDisplayCategory=function() return 'Material' end,getDisplayName=function() return name end}
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
OrganizedCategories = {getScriptInventoryDisplayCategory = function(script) return script.uiCategory end}
for _,names in ipairs({{'Candy','Sunflower seeds','Full packet','Empty packet','Pure seed'},
    {'Конфеты','Семечки подсолнуха','Пакет семян','Пустой пакет семян','Семена'}}) do
    scriptCatalog={script(names[1],'OC_Snack',{'food','snack'}),
        script(names[2],'OC_Snack',{'food','snack','farming','seed'}),
        script(names[3],'OC_Seeds',{'farming','seed'}),script(names[4],'OC_Seeds',{'farming'}),
        script(names[5],'OC_SeedOnly',{'farming','seed'})}
    fixture.setContents({'OC_Snack'})
    local readsBefore = catalogReads
    open();local itemPicker=LootSorter._picker
    assert(catalogReads == readsBefore + 1, 'reopened picker did not read a fresh catalog')
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
    click(itemPicker,'seed')
    assert(openedRulePicker.owner==itemPicker and openedRulePicker.rule.mode=='all'
        and openedRulePicker.rule.include[1]=='seed' and openedRulePicker.scriptItems==scriptCatalog,
        'partial seed tag did not open a locale-independent real-item rule draft')
    unchanged(itemPicker.selectedCats,catsBefore,'partial tag click changed exact category picks')
    unchanged(itemPicker.selectedItems,itemsBefore,'partial tag click persisted localized names')
    assert(openedRulePicker.selectedTag=='seed','refined row lost the explicit initial tag')
    openedRulePicker.onApply({mode='all',include={'seed'},exclude={}},'seed')
    local suggestion=appearanceSelections[#appearanceSelections]
    assert(suggestion.picker==itemPicker and suggestion.kind=='tag' and suggestion.key=='seed',
        'accepted rule did not forward first explicit tag to appearance')
    assert(itemPicker.toolkitTagRuleTouched and itemPicker.toolkitTagRule.include[1]=='seed')
    unchanged(itemPicker.selectedCats,catsBefore,'rule Apply changed manual categories')
    unchanged(itemPicker.selectedItems,itemsBefore,'rule Apply changed manual items')
    assert(itemPicker.selectedPresets.Pantry=='generation','rule Apply changed a manual preset')
    itemPicker.listbox.selected=seedIndex
    itemPicker.listbox.onJoypadDown(itemPicker.listbox,Joypad.AButton)
    assert(openedRulePicker.owner==itemPicker and openedRulePicker.rule.include[1]=='seed',
        'controller bypassed the stable rule draft for a partial tag')
    itemPicker.onlyContents,itemPicker.needRebuild=true,true;itemPicker:prerender()
    assert(find(itemPicker,'seed'),'Only Contents hid a partial category planting input')
    itemPicker.onlyContents,itemPicker.needRebuild=false,true;itemPicker:prerender()
    click(itemPicker,'snack')
    assert(itemPicker.selectedCats.OC_Snack,'whole-category tag stopped selecting exact category IDs')
    unchanged(itemPicker.selectedItems,itemsBefore,'whole-category batch changed manual items')
    itemPicker.btnClear.onclick(itemPicker);itemPicker:prerender()
    assert(next(itemPicker.selectedCats)==nil,'native Uncheck all failed to clear exact category picks')
    unchanged(itemPicker.selectedItems,itemsBefore,'Uncheck all removed existing manual items')
    itemPicker.filter:setText('seed');itemPicker.needRebuild=true;itemPicker:prerender()
    itemPicker.btnAll.onclick(itemPicker)
    assert(openedRulePicker.rule.mode=='any' and openedRulePicker.rule.include[1]=='seed',
        'Select all omitted a partial filtered tag')
    openedRulePicker.onApply({mode='any',include={'seed'},exclude={}})
    unchanged(itemPicker.selectedItems,itemsBefore,'Select all rule Apply persisted localized names')
    assert(next(itemPicker.selectedCats)==nil,'Select all broadened a partial category')
    itemPicker.toolkitTagRuleButton.onclick(itemPicker)
    assert(openedRulePicker.scriptItems==scriptCatalog,'dynamic editor preview lacks the script catalog')
    assert(catalogReads == readsBefore + 1 and tagReads == projectionReads,
        'search, selection, saved-category changes or rule opening re-enumerated the item/tag catalog')
end
OrganizedCategories = nil
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
        local item = {category = 'Material', getDisplayCategory = function(self) return self.category end}
        local contents = {getItems = function()
            return {size = function() return 1 end, get = function() return item end}
        end}
        obj.getContainerByIndex = function() return contents end
        OrganizedCategories = {applyItemDisplayOverride = function(current)
            assert(current == item, 'picker replaced the real contents item')
            current.category = 'OC_FoodPerishable'
        end}
        local visible = p:contentsSet()
        assert(item.category == 'OC_FoodPerishable' and visible.OC_FoodPerishable and not visible.Material,
            'owned picker contents required an external category preparation wrapper')
        OrganizedCategories = nil
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
    assert(rows[4][1] == p.toolkitTagSwitch and rows[5][1] == p.toolkitTagRuleButton
        and rows[6][1] == p.listbox, 'native controller rows omitted tag controls')
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
    assert(p.listbox.drawnText == 'food (1/2)' and p.listbox.semanticIcon.id == 'food',
        'actual picker lost partial tag row rendering')
    click(p, 'food')
    assert(p.selectedCats.OC_FoodPerishable and not p.selectedCats.food)
    p.toolkitTagSwitch.onclick(p); p:prerender()
    click(p, 'OC_FoodPerishable')
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
    save(p); save(p)
    assert(fixture.pendingRule() and not p.removed and #publications == 0, 'native Save bypassed asynchronous rule verdict')
    p.selectedCats.Later, p.selectedItems.Later, p.priority = true, true, 99
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
        and saved.items.Hammer and not saved.items.Later and saved.priority == 4
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
        reply(verdict)
        assert(not p.removed and LootSorter._picker == p and #publications == 1 and fixture.coordinates() == 1,
            'rule ' .. verdict .. ' closed actual picker or wrote exact selections')
    end
    assert(#failures == 3)
    save(p); reply('ok')
    assert(p.removed and #publications == 2 and fixture.coordinates() == 2, 'rule refusal prevented retry')
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
    assert(p.dimmer.visible and not editor.btnModePreset.visible and find(editor, 'food'))
    click(editor, 'perishable')
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
