-- UI primitives only: window construction, rows, modes and save callbacks come from the owned picker.
return function(control, rules, options)
    options = options or {}
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
    function base:onJoypadDown() end
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
        function lb:getScrollHeight() return self.scrollHeight or self.count * self.itemheight end
        function lb:setScrollHeight(height) self.scrollHeight = height end
        function lb:clear() self.items, self.count, self.scrollHeight = {}, 0, nil end
        function lb:addItem(text, item)
            self.count = self.count + 1
            self.items[self.count] = {text = text, item = item, index = self.count, height = self.itemheight}
        end
        lb:clear()
        return lb
    end}
    local contextMenu
    ISContextMenu = {get = function()
        contextMenu = {options = {}, addOption = function(self, title, target, callback, key)
            self.options[#self.options + 1] = {title = title, target = target, callback = callback, key = key}
        end}
        return contextMenu
    end}
    getMouseX, getMouseY = function() return 0 end, function() return 0 end
    local originalRequire = require
    require = function(name)
        if name:sub(1, 5) == 'ISUI/' or name:sub(1, 13) == 'TimedActions/' then return end
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

    local pendingRule, pendingPreset, presetPayload, failures = nil, nil, nil, {}
    local publications, coordinates = {}, 0
    local preset = {cats = {OC_Food = true}, items = {Beans = true}, rev = 7, gen = 'generation'}
    LootSorter = {PRIORITY_MAX_DIGITS = 5, DBG = function() end,
        getCategories = options.categories or function() return {'OC_Food', 'OC_FoodPerishable', 'OC_Electrical'} end,
        getItemNames = function() return {'Beans', 'Hammer'} end,
        getPresetStore = function() return {Pantry = preset} end,
        presetNames = function() return {'Pantry'} end,
        putPreset = function(args, callback) presetPayload, pendingPreset = args, callback end,
        notify = function(_, message) failures[#failures + 1] = message end,
        addCoord = function() coordinates = coordinates + 1 end,
        removeCoords = function() coordinates = coordinates + 1 end}
    local function event() return {Add = function() end, Remove = function() end} end
    Events.OnReceiveGlobalModData, Events.OnTick, Events.OnObjectAdded = event(), event(), event()
    isClient, isServer = function() return false end, function() return false end
    dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/LootSorter_Util.lua')
    dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/LootSorter_Core.lua')
    LootSorter.notify = function(_, message) failures[#failures + 1] = message end
    local obj = {md = {LSBox = {['0'] = (options.cats or {OC_Food = true, MissingModCategory = true})},
        LSBoxItems = {['0'] = (options.items or {Beans = true})}, LSBoxPresets = {['0'] = {Pantry = 'generation'}},
        LSBoxPriority = {['0'] = 4}}}
    local square = {getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end,
        getObjects = function() return {size = function() return 1 end, get = function() return obj end} end}
    obj.getModData, obj.hasModData = function(self) return self.md end, function() return true end
    obj.getSquare = function() return square end
    local contents = options.contents or {'OC_FoodPerishable'}
    obj.getContainerByIndex = function()
        local items = {}
        for _, category in ipairs(contents) do
            items[#items + 1] = {getDisplayCategory = function() return category end}
        end
        return {getItems = function() return {size = function() return #items end,
            get = function(_, index) return items[index + 1] end} end}
    end
    function obj:transmitModData()
        publications[#publications + 1] = LootSorter.snapshotDesignation({cats = self.md.LSBox['0'],
            items = self.md.LSBoxItems['0'], presets = self.md.LSBoxPresets['0'], priority = self.md.LSBoxPriority['0'],
            pzstTagRule = self.md.PZSTQuartermasterTagRules and self.md.PZSTQuartermasterTagRules['0']})
    end
    rules.saveBox = function(obj, ci, rule, _, callback, revision)
        assert(revision == 0 and obj and ci == 0, 'upstream picker changed rule save target/revision')
        assert(not pendingRule, 'duplicate upstream in-flight save')
        pendingRule = {callback = callback, rule = rule}
    end
    rules.presetsSynced = function() return true end
    rules.getBox = function(target, ci)
        local value = target and target.md and target.md.PZSTQuartermasterTagRules
        return value and value[tostring(ci)] and require('PZSurvivorToolkit/ItemTags').normalizeRule(value[tostring(ci)])
    end
    dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/LootSorter_Picker.lua')
    -- Record the native failure callback outcome without constructing an unrelated modal UI.
    LootSorter.notifyPresetFailure = function(_, outcome) failures[#failures + 1] = outcome end
    assert(LootSorter.toolkitTagPicker, 'owned picker did not declare tag UI setup')
    local function open()
        LootSorter.openPicker(obj, 0, 0)
        local p = assert(LootSorter._picker)
        p:configJoypad()
        p:prerender()
        return p
    end
    local function save(p) p.btnSave.onclick(p.btnSave.target, p.btnSave) end
    local function reply(verdict)
        local request = assert(pendingRule)
        pendingRule = nil
        if verdict == 'ok' then obj.md.PZSTQuartermasterTagRules = {['0'] = request.rule} end
        request.callback(verdict, 1)
    end
    return {open = open, object = obj, joypad = joypad, failures = failures, publications = publications,
        save = save, reply = reply, coordinates = function() return coordinates end,
        pendingRule = function() return pendingRule end, presetPayload = function() return presetPayload end,
        presetReply = function(...) return assert(pendingPreset)(...) end,
        contextMenu = function() return contextMenu end,
        setContents = function(value) contents = value end,
        edit = function(parent)
            LootSorter.openPresetEditor('Pantry', 0, parent)
            local editor = assert(LootSorter._presetEditor)
            editor:prerender()
            return editor
        end}
end
