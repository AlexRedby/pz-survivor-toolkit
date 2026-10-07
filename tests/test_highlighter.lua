-- Behavioural tests: the world and UI are doubles, not an in-game render test.
local client = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/"
local count = 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function setup(savedFile)
    local world = { now = 0, squares = {}, objects = {}, saves = 0, file = savedFile or "",
        itemReads = 0, inspections = 0, maxItemReads = 0, maxInspections = 0 }
    local function event()
        local handlers = {}
        return { Add = function(handler) handlers[#handlers + 1] = handler end,
            fire = function(...) for _, handler in ipairs(handlers) do handler(...) end end }
    end
    Events = { OnTick = event(), OnTickEvenPaused = event(), OnGameStart = event(), OnPlayerDeath = event(),
        OnMainMenuEnter = event(), OnKeyPressed = event() }
    Keyboard = { KEY_F8 = 66 }
    PZSurvivorToolkit = {}
    getText = function(key) return key end
    getTimestampMs = function() return world.now end
    world.player = { x = 0.5, y = 0.5, z = 0, num = 0, dead = false }
    function world.player:getX() return self.x end
    function world.player:getY() return self.y end
    function world.player:getZ() return self.z end
    function world.player:getPlayerNum() return self.num end
    function world.player:isDead() return self.dead end
    getPlayer = function() return world.player end
    local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
    world.cell = { getGridSquare = function(_, x, y, z) return world.squares[key(x, y, z)] end }
    getCell = function() return world.cell end
    local core = { isDoingTextEntry = function(self)
        assert(self ~= nil, "Core.isDoingTextEntry is an instance method")
        return world.typing == true
    end }
    getCore = function() return core end
    Core, UIManager = nil, nil
    MainOptions = { instance = { isVisible = function() return world.optionsVisible == true end } }
    getFileWriter = function()
        world.saves = world.saves + 1
        world.file = ""
        return { write = function(_, text) world.file = world.file .. text end,
            close = function() end }
    end
    getFileReader = function()
        local lines = {}
        for line in world.file:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
        local index = 0
        return { readLine = function() index = index + 1; return lines[index] end,
            close = function() end }
    end
    luautils = { split = function(text, separator)
        local parts = {}
        for part in text:gmatch("[^" .. separator .. "]+") do parts[#parts + 1] = part end
        return parts
    end }

    local loaded = {}
    require = function(name)
        if loaded[name] then return end
        loaded[name] = true
        if name == "PZSurvivorToolkit" then return end
        if name == "ISUI/ISButton" then assert(ISButton); return end
        if name == "PZAPI/ModOptions" then
            if NativeModOptionsSource then
                assert(loadstring(NativeModOptionsSource))()
            else
                -- Small option API double. Persistence integration uses extracted vanilla code.
                PZAPI = { ModOptions = { Dict = {} } }
                function PZAPI.ModOptions:create(id)
                    local options = { dict = {}, addTitle = function() end }
                    local function add(optionID, value)
                        local option = { value = value }
                        function option:getValue() return self.value end
                        function option:setValue(newValue) self.value = newValue end
                        options.dict[optionID] = option
                        return option
                    end
                    function options:addTickBox(optionID, _, value) return add(optionID, value) end
                    function options:addKeyBind(optionID, _, value) return add(optionID, value) end
                    function options:addColorPicker(optionID, _, r, g, b, a)
                        return add(optionID, { r = r, g = g, b = b, a = a })
                    end
                    function options:addComboBox(optionID)
                        local option = add(optionID, 1)
                        option.items = 0
                        function option:addItem(_, selected)
                            self.items = self.items + 1
                            if selected then self.value = self.items end
                        end
                        return option
                    end
                    self.Dict[id] = options
                    return options
                end
                function PZAPI.ModOptions:save() world.saves = world.saves + 1 end
            end
            return
        end
        dofile(client .. name .. ".lua")
    end
    require("PZSurvivorToolkit/Highlighter")
    require("PZSurvivorToolkit/Input")
    if NativeModOptionsSource then PZAPI.ModOptions:load() end
    world.options = PZAPI.ModOptions.Dict.PZSurvivorToolkit
    world.highlighter = PZSurvivorToolkit.Highlighter
    world.settings = PZSurvivorToolkit.Settings

    function world:add(x, y, z, name, zoff)
        local squareKey = key(math.floor(x), math.floor(y), z)
        local square = self.squares[squareKey]
        if not square then
            square = { x = math.floor(x), y = math.floor(y), z = z, items = {} }
            function square:getX() return self.x end
            function square:getY() return self.y end
            function square:getZ() return self.z end
            square.visible = {}
            function square:isCanSee(player) return self.visible[player] ~= false end
            function square:isSeen() return true end -- explored is deliberately not enough
            function square:isCouldSee() return true end -- LOS/FOV is the engine decision
            function square:getWorldObjects()
                return { size = function() return #self.items end,
                    get = function(_, index)
                        world.itemReads = world.itemReads + 1
                        return self.items[index + 1]
                    end }
            end
            function square:getObjects() error("must not scan containers") end
            function square:getStaticMovingObjects() error("must not scan corpses") end
            self.squares[squareKey] = square
        end
        local object = { square = square, x = x, y = y, name = name,
            flags = {}, colours = {}, attached = {}, zoff = zoff or 0 }
        object.item = { object = object }
        function object.item:getWorldItem()
            world.inspections = world.inspections + 1
            return self.object
        end
        function object.item:getFullType() error("must not filter by item type") end
        function object.item:getInventory() error("must not scan nested inventory") end
        function object:getSquare() return self.square end
        function object:getItem() return self.item end
        function object:getWorldPosX() return self.x end
        function object:getWorldPosY() return self.y end
        function object:getOffZ() return self.zoff end
        function object:getDoRender() return self.doRender ~= false end
        function object:getTargetAlpha(player) return self.targetAlpha == nil and 1 or self.targetAlpha end
        function object.item:getScriptItem()
            return { isWorldRender = function() return object.worldRender ~= false end }
        end
        object.modelFlags, object.modelColours = {}, {}
        function object:isHighlighted(player) return self.modelFlags[player] == true end
        function object:setHighlighted(player, enabled, once)
            self.modelFlags[player] = enabled
            self:setOutlineHighlight(player, enabled)
            self:setHighlightColor(player, 0.2, 0.3, 0.4, 1)
            self:setOutlineHighlightCol(player, 0.2, 0.3, 0.4, 1)
        end
        function object:getHighlightColor(player)
            local value = self.modelColours[player]
            -- Java ColorInfo exposes getters to Lua, not its public fields.
            return { getR = function() return value.r end, getG = function() return value.g end,
                getB = function() return value.b end, getA = function() return value.a end }
        end
        function object:setHighlightColor(player, r, g, b, a)
            self.modelColours[player] = { r=r, g=g, b=b, a=a }
        end
        function object:isOutlineHighlight(player) return self.flags[player] == true end
        function object:setOutlineHighlight(player, enabled) self.flags[player] = enabled end
        function object:isOutlineHlAttached(player) return self.attached[player] == true end
        function object:setOutlineHlAttached(player, attached) self.attached[player] = attached end
        function object:getOutlineHighlightCol(player) return self.colours[player] end
        function object:setOutlineHighlightCol(player, r, g, b, a)
            -- Opaque key: tests intentionally do not assume native colour bit packing.
            self.colours[player] = r .. ":" .. g .. ":" .. b .. ":" .. a
        end
        square.items[#square.items + 1] = object
        self.objects[#self.objects + 1] = object
        return object
    end
    function world:advance(ticks)
        for _ = 1, ticks do
            self.now = self.now + 17
            self.itemReads, self.inspections = 0, 0
            Events.OnTickEvenPaused.fire()
            Events.OnTick.fire()
            self.maxItemReads = math.max(self.maxItemReads, self.itemReads)
            self.maxInspections = math.max(self.maxInspections, self.inspections)
            equal(self.highlighter.getStatus().lastError, nil, "unexpected engine API error")
        end
    end
    function world:apply(id, value)
        local option = self.options.dict[id]
        -- MainOptions invokes onChangeApply BEFORE storing the new value.
        if option.onChangeApply then option:onChangeApply(value) end
        option:setValue(value)
        self.options:apply()
    end
    function world:pickup(object)
        local items = object.square.items
        for i, candidate in ipairs(items) do
            if candidate == object then table.remove(items, i); break end
        end
        object.item.object = nil
        -- Leave square non-nil to exercise stale references, not just the easy case.
    end
    return world
end

local function test(name, body)
    body()
    count = count + 1
    print("PASS " .. name)
end

test("all world items including mod items and floor stacks, no type or container traversal", function()
    local w = setup()
    local objects = { w:add(0.3, 0.4, 0, "Base.Hammer"), w:add(1.2, 0.6, 0, "AnotherMod.StrangeItem"),
        w:add(0.5, 1.5, 0, "Base.Plank", 0.06) }
    local far = w:add(20.5, 0.5, 0, "Base.Axe")
    local upstairs = w:add(0.5, 0.5, 1, "Base.Nails")
    w:advance(70)
    for _, object in ipairs(objects) do equal(object.flags[0], true) end
    equal(far:isOutlineHighlight(0), false)
    equal(upstairs:isOutlineHighlight(0), false)
end)

test("new drop appears and pickup clears even with a stale square", function()
    local w = setup()
    w:advance(50)
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    w:advance(70)
    equal(object.flags[0], true)
    w:pickup(object)
    w:advance(1)
    equal(object.flags[0], false)
    equal(w.highlighter.getStatus().highlightedObjects, 0)
end)

test("movement changes range, floor changes clear old contours", function()
    local w = setup()
    local behind = w:add(-14, 0.5, 0, "Base.Hammer")
    local ahead = w:add(17, 0.5, 0, "Base.Hammer")
    local above = w:add(2.5, 0.5, 1, "Base.Hammer")
    w:advance(70)
    equal(behind.flags[0], true)
    w.player.x = 3.5
    w:advance(70)
    equal(behind.flags[0], false)
    equal(ahead.flags[0], true)
    w.player.z = 1
    w:advance(1)
    equal(ahead.flags[0], false)
    w:advance(70)
    equal(above.flags[0], true)
end)

test("chunk unload clears, reload finds items again", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    w:advance(70)
    local square = object.square
    w.squares["0:0:0"] = nil
    w:advance(1)
    equal(object.flags[0], false)
    w.squares["0:0:0"] = square
    w:advance(70)
    equal(object.flags[0], true)
end)

test("menu disabled immediately clears; reenable applies new colour and radius", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    local edge = w:add(12, 0.5, 0, "Base.Axe")
    w:advance(70)
    w:apply("Enabled", false)
    equal(object.flags[0], false)
    w:advance(70)
    equal(object.flags[0], false)
    w:apply("Color", { r = 0, g = 1, b = 0, a = 1 })
    w:apply("Radius", 1)
    w:apply("Enabled", true)
    w:advance(70)
    equal(object.colours[0], "0:1:0:1")
    equal(object.flags[0], true)
    equal(edge.flags[0], false)
end)

test("unseen or explored-only tiles never acquire highlights; visible tiles do", function()
    local w = setup()
    local hidden = w:add(1.5, 0.5, 0, "Base.Hammer")
    hidden.square.visible[0] = false
    local visible = w:add(0.5, 0.5, 0, "Base.Plank")
    w:advance(70)
    equal(hidden.modelFlags[0], nil)
    equal(hidden.flags[0], nil)
    equal(visible.flags[0], true)
    hidden.square.visible[0] = true -- the engine resolves a window/open door
    w:advance(70)
    equal(hidden.flags[0], true)
    hidden.square.visible[0] = false -- wall or turning away
    w:advance(1)
    equal(hidden.modelFlags[0], false)
    equal(hidden.flags[0], false)
end)

test("render-disabled and fully transparent world items remain unhighlighted", function()
    local w = setup()
    local disabled = w:add(0.5, 0.5, 0, "Base.Hammer")
    local transparent = w:add(0.6, 0.5, 0, "Base.Plank")
    local scriptHidden = w:add(0.7, 0.5, 0, "Mod.InvisibleItem")
    disabled.doRender, transparent.targetAlpha, scriptHidden.worldRender = false, 0, false
    w:advance(70)
    equal(disabled.flags[0], nil)
    equal(transparent.flags[0], nil)
    equal(scriptHidden.flags[0], nil)
    disabled.doRender, transparent.targetAlpha, scriptHidden.worldRender = true, 0.5, true
    w:advance(70)
    equal(disabled.flags[0], true)
    equal(transparent.flags[0], true)
    equal(scriptHidden.flags[0], true)
    disabled.doRender, transparent.targetAlpha, scriptHidden.worldRender = false, 0, false
    w:advance(1)
    equal(disabled.flags[0], false)
    equal(transparent.flags[0], false)
    equal(scriptHidden.flags[0], false)
end)

test("visibility uses the local player slot and preserves foreign highlights", function()
    local w = setup()
    w.player.num = 1
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    object.square.visible[0], object.square.visible[1] = true, false
    w:advance(70)
    equal(object.flags[1], nil)
    object.square.visible[1] = true
    w:advance(70)
    equal(object.flags[1], true)
    object.modelColours[1] = { r=0, g=0, b=1, a=1 }
    object.square.visible[1] = false
    w:advance(1)
    equal(object.flags[1], true)
end)

test("scanner owns both model and outline highlights with the configured colour", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    w:advance(70)
    equal(object.modelFlags[0], true)
    equal(object.flags[0], true)
    equal(object.modelColours[0].r, 1.0)
    equal(object.modelColours[0].g, 0.55)
    equal(object.modelColours[0].b, 0.05)
    equal(object.modelColours[0].a, 1.0)
end)

test("native cleanup clears both model and outline highlights", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    w:advance(70)
    w.settings.toggle()
    equal(object.modelFlags[0], false)
    equal(object.flags[0], false)
end)

test("foreign model colour takeover survives cleanup", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    w:advance(70)
    object.modelColours[0] = { r = 0.8, g = 0.1, b = 0.2, a = 1.0 }
    w.settings.toggle()
    equal(object.modelFlags[0], true)
    equal(object.flags[0], true)
    equal(object.modelColours[0].r, 0.8)
    equal(object.modelColours[0].g, 0.1)
    equal(object.modelColours[0].b, 0.2)
end)

test("existing model highlight is respected and not claimed", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    object.modelFlags[0] = true
    object.modelColours[0] = { r = 0.3, g = 0.4, b = 0.5, a = 1.0 }
    object.flags[0] = true
    object.colours[0] = "foreign-outline"
    w:advance(70)
    w.settings.toggle()
    equal(object.modelFlags[0], true)
    equal(object.flags[0], true)
    equal(object.modelColours[0].r, 0.3)
    equal(object.modelColours[0].g, 0.4)
    equal(object.modelColours[0].b, 0.5)
    equal(object.colours[0], "foreign-outline")
end)

test("existing foreign contour, different colour takeover and attached takeover survive cleanup", function()
    local w = setup()
    local existing = w:add(0.5, 0.5, 0, "Base.Hammer")
    existing.flags[0], existing.colours[0] = true, "foreign"
    local takeover = w:add(1.5, 0.5, 0, "Base.Hammer")
    local attached = w:add(2.5, 0.5, 0, "Base.Hammer")
    w:advance(70)
    takeover.colours[0] = "another mod"
    attached.attached[0] = true
    w.settings.toggle()
    equal(existing.flags[0], true)
    equal(existing.colours[0], "foreign")
    equal(takeover.flags[0], true)
    equal(attached.flags[0], true)
end)

test("vanilla clearing a contour allows it to be reapplied", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    w:advance(70)
    object:setHighlighted(0, false, false)
    w:advance(1)
    equal(object.flags[0], true)
end)

test("hotkey toggles, wrong key and text/key capture do not", function()
    local w = setup()
    equal(w.settings.getToggleKey(), Keyboard.KEY_F8)
    Events.OnKeyPressed.fire(1)
    equal(w.settings.isEnabled(), true)
    w.typing = true
    Events.OnKeyPressed.fire(Keyboard.KEY_F8)
    equal(w.settings.isEnabled(), true)
    w.typing = false
    w.optionsVisible = true
    Events.OnKeyPressed.fire(Keyboard.KEY_F8)
    equal(w.settings.isEnabled(), true)
    w.optionsVisible = false
    Events.OnKeyPressed.fire(Keyboard.KEY_F8)
    equal(w.settings.isEnabled(), false)
    equal(w.saves, 1)
    w:apply("ToggleKey", 12)
    Events.OnKeyPressed.fire(Keyboard.KEY_F8)
    equal(w.settings.isEnabled(), false)
    Events.OnKeyPressed.fire(12)
    equal(w.settings.isEnabled(), true)
end)

test("sidebar button shares settings with menu and rebound key, survives sidebar replacement", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    ISButton = {}
    function ISButton:derive() return setmetatable({}, { __index = self }) end
    function ISButton:new(x, y, width, height, title, target, onclick)
        self.__index = self
        return setmetatable({ y = y, height = height, target = target, onclick = onclick }, self)
    end
    function ISButton:initialise() end
    function ISButton:setEnable(value) self.enable = value end
    function ISButton:setTitle(value) self.title = value end
    function ISButton:setTooltip(value) self.tooltip = value end
    function ISButton:getBottom() return self.y + self.height end
    function ISButton:forceClick() if self.enable then self.onclick(self.target, self) end end
    UIFont = { Small = 1 }
    getKeyName = function(key) return "KEY_" .. key end
    getText = function(key, value) return value and key .. ":" .. value or key end
    getTextManager = function() return {
        MeasureStringX = function(_, font, text) return #text * 6 end,
        getFontHeight = function() return 14 end,
    } end
    local function sidebar()
        return { width = 48, height = 500, children = {},
            getWidth = function(self) return self.width end,
            getHeight = function(self) return self.height end,
            setWidth = function(self, value) self.width = value end,
            setHeight = function(self, value) self.height = value end,
            addChild = function(self, child) self.children[#self.children + 1] = child end }
    end
    local data = { equipped = sidebar() }
    getPlayerData = function() return data end
    require("PZSurvivorToolkit/ToggleButton")
    w:advance(70)
    local button = data.equipped.toolkitHighlightButton
    equal(#data.equipped.children, 1)
    equal(button.title, "UI_PZSurvivorToolkit_button_on")
    button:forceClick()
    equal(w.settings.isEnabled(), false)
    equal(object.flags[0], false)
    equal(button.title, "UI_PZSurvivorToolkit_button_off")
    equal(w.saves, 1)
    Events.OnKeyPressed.fire(Keyboard.KEY_F8)
    button:update()
    equal(button.title, "UI_PZSurvivorToolkit_button_on")
    w:apply("ToggleKey", 12)
    button:update()
    equal(button.tooltip, "UI_PZSurvivorToolkit_button_tooltip:KEY_12")
    Events.OnKeyPressed.fire(Keyboard.KEY_F8)
    equal(w.settings.isEnabled(), true)
    Events.OnKeyPressed.fire(12)
    button:update()
    equal(button.title, "UI_PZSurvivorToolkit_button_off")
    w:apply("ToggleKey", 0)
    button:update()
    equal(button.tooltip, "UI_PZSurvivorToolkit_button_tooltip:UI_PZSurvivorToolkit_no_shortcut")
    Events.OnKeyPressed.fire(0)
    equal(w.settings.isEnabled(), false)
    button:forceClick()
    equal(w.settings.isEnabled(), true)
    w:apply("Enabled", false)
    button:update()
    equal(button.title, "UI_PZSurvivorToolkit_button_off")
    data.equipped = sidebar()
    w:advance(2)
    local replacement = data.equipped.toolkitHighlightButton
    assert(replacement ~= button)
    equal(#data.equipped.children, 1)
    equal(replacement.title, "UI_PZSurvivorToolkit_button_off")
    w.player.dead = true
    replacement:update()
    replacement:forceClick()
    equal(w.settings.isEnabled(), false)
    equal(replacement.enable, false)
end)

test("death, player replacement and main menu release the correct player index", function()
    local w = setup()
    local object = w:add(0.5, 0.5, 0, "Base.Hammer")
    w.player.num = 2
    w:advance(70)
    equal(object.flags[2], true)
    w.player.num = 0
    w:advance(1)
    equal(object.flags[2], false)
    w:advance(70)
    equal(object.flags[0], true)
    w.player.dead = true
    w:advance(1)
    equal(object.flags[0], false)
    Events.OnKeyPressed.fire(Keyboard.KEY_F8)
    equal(w.settings.isEnabled(), true)
    w.player.dead = false
    w:advance(70)
    Events.OnMainMenuEnter.fire()
    equal(object.flags[0], false)
end)

test("dense pile has bounded per-tick work, all items eventually covered", function()
    local w = setup()
    local pile = {}
    for i = 1, 3000 do pile[i] = w:add(0.5, 0.5, 0, "Mod.Item" .. i) end
    w:advance(150)
    for _, object in ipairs(pile) do equal(object.flags[0], true) end
    assert(w.maxItemReads <= 128, "unbounded discovery work")
    assert(w.maxInspections <= 256, "unbounded maintenance work")
    w:pickup(pile[2500])
    w:advance(30)
    equal(pile[2500].flags[0], false)
    w.settings.toggle()
    w:advance(30)
    for _, object in ipairs(pile) do equal(object.flags[0], false) end
end)

test("movement beside a dense pile discovers the new nearest tile immediately", function()
    local w = setup()
    for i = 1, 3000 do w:add(0.5, 0.5, 0, "Mod.Item" .. i) end
    w:advance(1)
    w.player.x = 1.5
    local nearby = w:add(1.5, 0.5, 0, "Mod.NewDrop")
    w:advance(1)
    equal(nearby.flags[0], true)
end)

test("cleanup makes progress while the game is paused", function()
    local w = setup()
    local pile = {}
    for i = 1, 1000 do pile[i] = w:add(0.5, 0.5, 0, "Mod.Item" .. i) end
    w:advance(100)
    w.settings.toggle()
    for _ = 1, 10 do Events.OnTickEvenPaused.fire() end
    for _, object in ipairs(pile) do equal(object.flags[0], false) end
    equal(w.highlighter.getStatus().clearing, false)
end)

if NativeModOptionsSource then
    test("native ModOptions saves and reloads enabled, colour, radius and hotkey", function()
        local w = setup()
        w:apply("Color", { r = 0.2, g = 0.4, b = 0.6, a = 0.8 })
        w:apply("Radius", 4)
        w:apply("ToggleKey", 12)
        w.settings.toggle()
        local reloaded = setup(w.file)
        equal(reloaded.settings.isEnabled(), false)
        equal(reloaded.settings.getRadius(), 20)
        equal(reloaded.settings.getToggleKey(), 12)
        equal(reloaded.settings.getColor().g, 0.4)
    end)
end

test("wear comparisons keep zero neutral and preserve gains, losses and replacement items", function()
    local previousRequire = require
    require = function() end
    local replaced = { "Base.Tshirt_DefaultTEXTURE_TINT" }
    local description
    ISInventoryPaneContextMenu = { doWearClothingTooltip = function(player, item, current, option)
        equal(player, 1); equal(item, 2); equal(current, 3)
        option.toolTip = description and { description = description } or nil
        return replaced
    end }
    dofile(client .. "PZSurvivorToolkit/WearComparison.lua")
    require = previousRequire
    for _, delta in ipairs({ "+0", "-0", "0", "+10", "-5" }) do
        local color = delta == "-5" and "<RGB:1.00,0.00,0.00>" or "<RGB:0.00,1.00,0.00>"
        local row = " Bite defense: <SETX:110> 10 (" .. delta .. ") <LINE> "
        description = "Replace: Shirt <LINE> " .. color .. row
        local option = {}
        equal(ISInventoryPaneContextMenu.doWearClothingTooltip(1, 2, 3, option), replaced)
        local expectedColor = delta:match("^[+-]?0$") and "<RGB:0.8,0.8,0.8>" or color
        equal(option.toolTip.description, "Replace: Shirt <LINE> " .. expectedColor .. row)
    end
    description = nil
    equal(ISInventoryPaneContextMenu.doWearClothingTooltip(1, 2, 3, {}), replaced)
end)

print("Passed " .. count .. " behavioural tests (Lua 5.1; game rendering remains untested).")
