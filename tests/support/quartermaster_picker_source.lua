-- UI primitives only: window construction, rows, modes and save callbacks come from the owned picker.
return function(adapter, control, rules, find, click, rulePicker)
    local function rect(x, y, w, h)
        local c = control()
        c.x, c.y, c.width, c.height = x, y, w, h
        return c
    end
    local base = {}
    base.__index = base
    function base:derive()
        local class = setmetatable({}, {__index = self})
        class.__index = class
        return class
    end
    function base:new(x, y, w, h)
        local c = setmetatable(rect(x, y, w, h), self)
        c.children, c.joypadButtonsY = {}, {}
        function c:initialise() self:createChildren() end
        return c
    end
    function base:createChildren() end
    function base:prerender() end
    function base:titleBarHeight() return 20 end
    function base:addChild(child) self.children[#self.children + 1] = child end
    function base:removeChild(child)
        for i, c in ipairs(self.children) do if c == child then table.remove(self.children, i); return end end
    end
    function base:addToUIManager() self.removed = false end
    function base:removeFromUIManager() self.removed = true end
    function base:close() self.visible = false end
    function base:clearISButtons() end
    function base:clearJoypadFocus() end
    function base:restoreJoypadFocus() end
    function base:getMinVisibleRow() return 1 end
    function base:insertNewLineOfButtons(...)
        self.joypadButtonsY[#self.joypadButtonsY + 1] = {...}
    end
    ISCollapsableWindow, ISCollapsableWindowJoypad = base, base
    ISPanel = {new = function(_, ...) return rect(...) end}
    ISButton = {new = function(_, x, y, w, h, title, target, onclick)
        local b = rect(x, y, w, h)
        b.title, b.target, b.onclick, b.cachedOnclick = title, target, onclick, onclick
        return b
    end}
    ISTextEntryBox = {new = function(_, text, x, y, w, h)
        local c = rect(x, y, w, h)
        c.text = text
        function c:getInternalText() return self.text end
        function c:setText(value) self.text = value end
        function c:setMaxTextLength(value) self.maxLength = value end
        return c
    end}
    ISLabel = {new = function(_, x, y, h) return rect(x, y, 0, h) end}
    ISScrollingListBox = {new = function(_, x, y, w, h)
        local lb = rect(x, y, w, h)
        lb.vscroll = rect(w - 16, 0, 16, h)
        function lb:updateScrollbars() end
        function lb:getScrollHeight() return self.count * self.itemheight end
        function lb:clear() self.items, self.count = {}, 0 end
        function lb:addItem(text, item)
            self.count = self.count + 1
            self.items[self.count] = {text = text, item = item, index = self.count, height = self.itemheight}
        end
        lb:clear()
        return lb
    end}
    local originalRequire = require
    require = function(name)
        if name:sub(1, 5) == 'ISUI/' then return end
        return originalRequire(name)
    end
    local core = getCore()
    core.getScreenWidth, core.getScreenHeight = function() return 1280 end, function() return 800 end
    getCore = function() return core end
    local textManager = getTextManager()
    textManager.MeasureStringX = function(_, _, value) return #value * 6 end
    getTextManager = function() return textManager end
    UIFont.Small = 0
    local joypad = {focus = {}}
    getJoypadData = function() return joypad end
    setJoypadFocus = function(_, focus) joypad.focus = focus end
    updateJoypadFocus = function() end
    getSpecificPlayer = function() return {getJoypadBind = function() return 0 end} end

    local saved, pendingRule, pendingPreset, presetPayload, failures = {}, nil, nil, nil, {}
    local preset = {cats = {OC_Food = true}, items = {Beans = true}, rev = 7, gen = 'generation'}
    LootSorter = {PRIORITY_MAX_DIGITS = 5,
        getCategories = function() return {'OC_Food', 'OC_FoodPerishable', 'OC_Electrical'} end,
        getItemNames = function() return {'Beans', 'Hammer'} end,
        getPresetStore = function() return {Pantry = preset} end,
        presetNames = function() return {'Pantry'} end,
        getBoxCats = function() return {OC_Food = true, MissingModCategory = true} end,
        getBoxItems = function() return {Beans = true} end,
        getBoxPresets = function() return {Pantry = 'generation'} end,
        getBoxPriority = function() return 4 end,
        putPreset = function(args, callback) presetPayload, pendingPreset = args, callback end,
        notify = function(_, message) failures[#failures + 1] = message end}
    for field, setter in pairs({cats = 'setBoxCats', items = 'setBoxItems', presets = 'setBoxPresets', priority = 'setBoxPriority'}) do
        LootSorter[setter] = function(obj, ci, value)
            saved[field], saved.obj, saved.ci = value, obj, ci
            saved.writes = (saved.writes or 0) + 1
        end
    end
    rules.saveBox = function(obj, ci, rule, _, callback, revision)
        assert(revision == 0 and obj and ci == 0, 'upstream picker changed rule save target/revision')
        assert(not pendingRule, 'duplicate upstream in-flight save')
        pendingRule = callback
    end
    rules.presetsSynced = function() return true end
    dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/LootSorter_Picker.lua')
    -- Record the native failure callback outcome without constructing an unrelated modal UI.
    LootSorter.notifyPresetFailure = function(_, outcome) failures[#failures + 1] = outcome end
    assert(LootSorter.toolkitTagPicker, 'owned picker did not declare tag UI setup')
    local obj = {}
    local function open()
        LootSorter.openPicker(obj, 0, 0)
        local p = assert(LootSorter._picker)
        p:configJoypad()
        p:prerender()
        return p
    end
    local function save(p) p.btnSave.onclick(p.btnSave.target, p.btnSave) end
    local function reply(verdict)
        local callback = assert(pendingRule)
        pendingRule = nil
        callback(verdict, 1)
    end
    local p = open()
    assert(p.btnSave.cachedOnclick ~= p.btnSave.onclick and p.btnSave.onclick == p.onSave,
        'adapter did not replace actual upstream cached Save callback')
    assert(p.children[#p.children] == p.dimmer and not p.dimmer.visible)
    local rows = p.joypadButtonsY
    assert(rows[4][1] == p.toolkitTagSwitch and rows[5][1] == p.toolkitTagRuleButton
        and rows[6][1] == p.listbox, 'native controller rows omitted tag controls')
    assert(p.listbox.vscroll.x == p.listbox.width - 16 and p.listbox.vscroll.height == p.listbox.height)
    assert(find(p, 'food') and find(p, 'MissingModCategory'), 'actual picker did not build tag/saved-category rows')
    local createRule = {mode = 'all', include = {'food'}, exclude = {'perishable'}}
    p.toolkitTagRule = createRule
    p.onPresetNamed(p, {internal = 'OK', parent = {entry = {getText = function() return 'New pantry' end}}})
    assert(presetPayload.name == 'New pantry' and presetPayload.expectExisting == false
        and presetPayload.cats == p.selectedCats and presetPayload.items == p.selectedItems
        and presetPayload.pzstTagRule == createRule, 'new preset entry lost its owning picker rule or selections')
    pendingPreset('ok')
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
    assert(pendingRule and not p.removed and not saved.writes, 'native Save bypassed asynchronous rule verdict')
    p.selectedCats.Later, p.selectedItems.Later, p.priority = true, true, 99
    reply('ok')
    assert(p.removed and LootSorter._picker == nil and saved.writes == 4)
    assert(saved.cats.OC_Food and saved.cats.MissingModCategory and not saved.cats.Later and not saved.cats.food
        and saved.items.Hammer and not saved.items.Later and saved.priority == 4
        and saved.presets.Pantry == 'generation', 'actual native save mixed snapshot and later edits')

    local function startPending()
        local owner = open()
        owner.toolkitTagRule, owner.toolkitTagRuleTouched = {mode = 'all', include = {'food'}, exclude = {}}, true
        save(owner)
        return owner
    end
    p = startPending()
    reply('stale')
    assert(not p.removed and LootSorter._picker == p and saved.writes == 4 and #failures == 1,
        'rule refusal closed actual picker or wrote exact selections')
    save(p); reply('ok')
    assert(p.removed and saved.writes == 8, 'rule refusal prevented retry')
    for _, closeVia in ipairs({'close', 'replace', 'retarget'}) do
        p = startPending()
        local writes = saved.writes
        if closeVia == 'close' then p:close() end
        local replacement
        if closeVia == 'retarget' then p.targetCI = 1 else replacement = open() end
        reply('ok')
        assert(saved.writes == writes, 'late native save wrote after ' .. closeVia)
        if replacement then
            assert(LootSorter._picker == replacement and not replacement.removed,
                'late native save closed new owner after ' .. closeVia)
        end
    end
    p = open()
    LootSorter.openPresetEditor('Pantry', 0, p)
    local editor = assert(LootSorter._presetEditor)
    editor:prerender()
    assert(p.dimmer.visible and not editor.btnModePreset.visible and find(editor, 'food'))
    click(editor, 'perishable')
    rules.presetsSynced = function() return false end
    save(editor)
    assert(presetPayload.pzstTagRule == nil and presetPayload.baseRev == 7
        and presetPayload.baseGen == 'generation', 'untouched unsynced preset save cleared rule metadata')
    pendingPreset('stale', {action = 'save'})
    editor.toolkitTagRule, editor.toolkitTagRuleTouched = {mode = 'all', include = {'food'}, exclude = {}}, true
    save(editor)
    assert(not editor.removed and presetPayload.expectExisting and presetPayload.baseRev == 7
        and presetPayload.baseGen == 'generation' and presetPayload.pzstTagRule == editor.toolkitTagRule,
        'native preset save lost rule metadata or conflict tokens')
    rules.presetsSynced = function() return true end
    pendingPreset('stale', {action = 'save'})
    assert(not editor.removed and p.dimmer.visible and failures[#failures] == 'stale')
    save(editor); pendingPreset('ok')
    assert(editor.removed and LootSorter._presetEditor == nil and not p.dimmer.visible)
    print('Owned Quartermaster picker contract passed: actual construction, rows, modes, cached Save, asynchronous verdicts and owner guards.')
end
