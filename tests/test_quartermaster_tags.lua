local enabled, starts, creates = true, {}, {}
PZSurvivorToolkit = {}
local categoryTags = {OC_Food = {'food'}, OC_FoodPerishable = {'food', 'perishable'},
    OC_Electrical = {'electrical'}, OC_FoodElectrical = {'food', 'electrical'}}
require = function(name)
    assert(name == 'PZSurvivorToolkit/ItemTags')
    return {enabled = function() return enabled end,
        forCategory = function(category) return categoryTags[category] or {'category:' .. category} end,
        label = function(id) return id end}
end
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end},
    OnCreatePlayer = {Add = function(fn) creates[#creates + 1] = fn end}}
getText, getTextOrNull = function(key) return key end, function() return nil end
UIFont = {Medium = 1}
Joypad = {AButton = 1, YButton = 2, BButton = 3, RBumper = 4}
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
    function b:drawText(text) self.drawnText = text end
    function b:isMouseOver() return false end
    b.draws = {}
    return b
end
ISButton = {new = function(_, _, _, _, _, _, target, onclick)
    local b = control(); b.target, b.onclick = target, onclick; return b
end}
local storedCats, storedItems = {OC_Food = true, MissingModCategory = true}, {Beans = true}
local availableCats = {'OC_Food', 'OC_FoodPerishable', 'OC_Electrical', 'OC_FoodElectrical', 'OtherMod'}
local native = {}
function native:activeList()
    if self.mode == 'cats' then return availableCats end
    if self.mode == 'items' then return {'Beans', 'Hammer'} end
    return {'Pantry'}
end
function native:currentFilter() return self.filterText or '' end
function native:contentsSet() return {OC_FoodPerishable = true} end
function native:rebuild()
    self.listbox:clear()
    for _, key in ipairs(self:activeList()) do self.listbox:addItem(key, {key = key}) end
    self.needRebuild = false
end
function native:layout()
    self.listbox:setY(100); self.listbox:setHeight(300)
end
function native:setMode(mode)
    self.mode = mode
    self.selection = mode == 'items' and self.selectedItems or mode == 'presets' and self.selectedPresets or self.selectedCats
    self.needRebuild = true
    if self.joypadConfigured then self:configJoypad() end
end
function native:prerender()
    if self.needRebuild then self:rebuild() end
    return 'native'
end
function native:insertNewLineOfButtons(first) self.rows[#self.rows + 1] = first end
function native:configJoypad()
    self.rows = {}; self:insertNewLineOfButtons(self.listbox); self:insertNewLineOfButtons(self.btnAll)
end
function native:addChild(child) self.children[#self.children + 1] = child end
function native:removeChild(child)
    for i, c in ipairs(self.children) do if c == child then table.remove(self.children, i); return end end
end
function native:onSave()
    if self.targetKind == 'preset' and self.refuse then self.failureShown = true; return end
    storedCats, storedItems = self.selectedCats, self.selectedItems
    self.closed = true
end
local function picker(kind)
    local p = setmetatable({mode = 'cats', targetKind = kind or 'box', selectedCats = {}, selectedItems = {},
        selectedPresets = {Pantry = 'generation'}, children = {}, rows = {}}, {__index = native})
    for k, v in pairs(storedCats) do p.selectedCats[k] = v end
    for k, v in pairs(storedItems) do p.selectedItems[k] = v end
    p.selection = p.selectedCats
    p.listbox = control(); local lb = p.listbox; lb.target, lb.items = p, {}
    -- Quartermaster instantiates a 10x10 list before layout; native clipping uses the scrollbar.
    lb.vscroll = control(); lb.vscroll.x, lb.vscroll.height = -6, 10
    lb.scrollHeight = 0
    function lb:updateScrollbars() end
    function lb:getScrollHeight() return self.scrollHeight end
    function lb:setScrollHeight(height) self.scrollHeight = height end
    function lb:clear() self.items = {} end
    function lb:addItem(label, row)
        self.items[#self.items + 1] = {item = row, text = label, index = #self.items + 1, height = 22}
        self.scrollHeight = self.scrollHeight + 22
    end
    lb.onmousedown = function(target, row) target.selection[row.key] = not target.selection[row.key] or nil end
    lb.doDrawItem = function() return 'native draw' end
    lb.onJoypadDown = function(self, key) self.nativeJoypad = key end
    lb.onRightMouseUp = function(self) self.inspected = self.items[self.mouseoverselected].item.key end
    p.btnAll = control()
    p.btnAll.onclick = function(target)
        for _, row in ipairs(target.listbox.items) do target.selection[row.item.key] = true end
    end
    p.btnClear = control()
    p.btnClear.onclick = function(target)
        target.selectedCats = {}; target.selection = target.selectedCats; target.needRebuild = true
    end
    p.dimmer = control(); p:addChild(p.dimmer)
    p.joypadConfigured = true
    p:rebuild()
    return p
end
LootSorter = {
    openPicker = function() LootSorter._picker = picker(); return 'opened' end,
    openPresetEditor = function() LootSorter._presetEditor = picker('preset'); return 'edited' end}
local adapter = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/QuartermasterTags.lua')
starts[1](); local wrapped = LootSorter.openPicker
starts[1](); creates[1]()
assert(LootSorter.openPicker == wrapped, 'duplicate event wrappers')
local function find(p, tagOrCategory)
    for index, row in ipairs(p.listbox.items) do
        if row.item.tag == tagOrCategory or row.item.key == tagOrCategory then return row.item, index end
    end
end
local function click(p, id) local row = assert(find(p, id), 'missing ' .. id); p.listbox.onmousedown(p, row); p:prerender() end
assert(LootSorter.openPicker() == 'opened')
local p = LootSorter._picker
assert(p.children[#p.children] == p.dimmer, 'tag switch bypasses preset dimmer')
assert(p.rows[1] == p.toolkitTagSwitch and p.listbox.y == 128)
local function stencilWidth(list)
    -- ISScrollingListBox.prerender uses these exact native geometry fields.
    if list.vscroll:getHeight() < list:getScrollHeight() then return list.vscroll.x + 3 end
    return list.width - 1
end
assert(p.listbox.vscroll.x == p.listbox.width - 16 and p.listbox.vscroll.height == p.listbox.height,
    'native scrollbar kept the constructor geometry and clipped rows')
p.listbox:setScrollHeight(1000)
assert(stencilWidth(p.listbox) > 300, 'scrollable tag rows are clipped before their checkbox/label')
p.filterText, p.needRebuild = 'electr', true; p:prerender()
p.listbox:setScrollHeight(22)
assert(stencilWidth(p.listbox) > 300, 'single filtered tag row is clipped')
p.filterText, p.needRebuild = '', true; p:prerender()
assert(find(p, 'food') and find(p, 'electrical') and find(p, 'perishable'))
assert(find(p, 'MissingModCategory') and find(p, 'OtherMod'), 'unknown categories lost')
local food, fi = find(p, 'food')
p.listbox.doDrawItem(p.listbox, 0, p.listbox.items[fi])
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
p.onlyContents, p.filterText, p.needRebuild = false, 'electr', true; p:prerender()
assert(#p.listbox.items == 1 and find(p, 'electrical'))
p.btnAll.onclick(p); p:prerender()
assert(p.selectedCats.OC_Electrical and p.selectedCats.OC_FoodElectrical)
p.filterText, p.needRebuild = '', true; p:prerender()
local _, ei = find(p, 'electrical'); p.listbox.selected = ei
p.listbox.onJoypadDown(p.listbox, Joypad.AButton); p:prerender()
assert(not p.selectedCats.OC_Electrical and not p.selectedCats.OC_FoodElectrical, 'controller A did not toggle tag batch')
p.listbox.onJoypadDown(p.listbox, Joypad.BButton)
assert(p.listbox.nativeJoypad == Joypad.BButton, 'controller exit intercepted')
p:setMode('items'); p:prerender()
assert(not p.toolkitTagSwitch.visible and p.listbox.y == 100 and find(p, 'Beans'))
assert(p.listbox.vscroll.height == 300 and stencilWidth(p.listbox) > 300, 'native Items layout clipped rows')
click(p, 'Hammer'); assert(p.selectedItems.Hammer and p.selectedItems.Beans)
p:setMode('presets'); p:prerender(); click(p, 'Pantry')
assert(not p.selectedPresets.Pantry and find(p, 'Pantry'), 'preset mode intercepted')
p:setMode('cats'); p:prerender()
p:onSave()
assert(p.closed and storedCats.OC_Food and storedCats.MissingModCategory and not storedCats.food)
assert(storedItems.Hammer, 'item selection lost on category save')
categoryTags.OC_FoodNew = {'food'}; availableCats[#availableCats + 1] = 'OC_FoodNew'
LootSorter.openPicker(); local reopened = LootSorter._picker
assert(reopened ~= p and reopened.selectedCats.OC_Food and reopened.selectedCats.MissingModCategory)
assert(not reopened.selectedCats.OC_FoodPerishable and reopened.toolkitTagView, 'reopen rebuilt broad tag selections')
assert(not reopened.selectedCats.OC_FoodNew, 'saved tags automatically selected a later-added category')
local _, unknownIndex = find(reopened, 'MissingModCategory')
reopened.listbox.mouseoverselected = unknownIndex
reopened.listbox.onRightMouseUp(reopened.listbox)
assert(reopened.listbox.inspected == 'MissingModCategory', 'unknown category inspector lost')
LootSorter.openPresetEditor(); local editor = LootSorter._presetEditor
click(editor, 'perishable'); editor.refuse = true; editor:onSave()
assert(editor.failureShown and not editor.closed, 'preset conflict protection bypassed')
editor.refuse = false; editor:onSave()
assert(storedCats.OC_FoodPerishable and not storedCats.perishable and editor.closed)
reopened.btnClear.onclick(reopened); reopened:prerender()
assert(next(reopened.selectedCats) == nil and reopened.selection == reopened.selectedCats, 'native Uncheck all did not clear category batches')
click(reopened, 'food')
assert(reopened.selectedCats.OC_Food and reopened.selectedCats.OC_FoodNew, 'batch used a stale selectedCats table after Uncheck all')
enabled = false
reopened:prerender()
assert(not reopened.toolkitTagSwitch.visible and reopened.listbox.y == 100 and find(reopened, 'OC_Food'))
LootSorter.openPicker(); local openedDisabled = LootSorter._picker
assert(openedDisabled.toolkitTagSwitch and not openedDisabled.toolkitTagSwitch.visible
    and openedDisabled.listbox.y == 100 and find(openedDisabled, 'OC_Food'), 'disabled picker did not retain native view')
enabled = true; openedDisabled:prerender()
assert(openedDisabled.toolkitTagSwitch.visible and openedDisabled.listbox.y == 128
    and find(openedDisabled, 'food'), 'picker opened while disabled did not enable tags without reopening')
assert(openedDisabled.rows[1] == openedDisabled.toolkitTagSwitch, 'live enable did not add controller navigation')
reopened:prerender()
assert(reopened.toolkitTagSwitch.visible and find(reopened, 'food'), 'setting toggle left a stale list')
print('Quartermaster tag checks passed: exact saved keys, partial/refined batches, filters, controller, modes, conflicts, reopens and opt-out.')
