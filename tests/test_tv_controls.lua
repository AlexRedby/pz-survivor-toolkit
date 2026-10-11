-- UI/world doubles exercise the adapter; optional source inputs also run native drag/transfer code.
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "VHS values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function setup(active)
    local w = {enabled = true, active = active ~= false, refreshes = 0, reachable = {}, queue = {},
        transfers = {}, walks = {}, steps = {}, nativeCalls = {}, menus = {}, children = {}}
    require = function(name)
        if name == "PZSurvivorToolkit/TVDeviceResolver" then
            return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TVDeviceResolver.lua")
        end
    end
    PZSurvivorToolkit = {Settings = {improveVHSControls = function() return w.enabled end,
        keepMediaWindowOpen = function() return false end}}
    Events = {OnGameStart = {Add = function(fn) w.install = fn end}}
    getActivatedMods = function() return {contains = function(_, id) return w.active and id == "TVRadio_ReInvented" end} end
    getText, getTexture = function(key) return key end, function(path) return path end
    UIFont = {Small = 1, Large = 2}
    getTextManager = function() return {getFontHeight = function() return 14 end} end
    JoypadState = {players = {}}
    setJoypadFocus = function(playerNum, menu) w.focus = {playerNum, menu} end
    ArrayList = {new = function() return {} end}
    ISMouseDrag = {}
    instanceof = function(item, class) return class == "InventoryItem" and item.inventoryItem == true end
    ISPanel = {derive = function(self) return setmetatable({}, {__index = self}) end}
    ISPanel.drawTexture = function(self, ...) w.textureCall = {...}; return "native texture" end
    ISPanel.prerender = function() w.panelPrerender = true end
    RWMPanel = ISPanel
    ISButton = {new = function(_, x, y, width, height, title, target, callback)
        return {backgroundColor = {}, borderColor = {}, target = target, callback = callback,
            initialise = function() end, setVisible = function() end, getIsVisible = function() return true end,
            getAbsoluteX = function() return x end, getAbsoluteY = function() return y end,
            onMouseUp = function(button, a, b) w.nativeMouse = {button, a, b}; return "native mouse" end,
            prerender = function(button) w.renderedColor = button.backgroundColorMouseOver; return "native render" end}
    end}
    ISVolumeBar = {new = function() return {initialise = function() end, setVisible = function() end,
        elBorderColor = {}, elBorderHighlightColor = {}, elHighlightColor = {}, elHoverColor = {}} end}
    RWMVolume = {}
    ISContextMenu = {get = function(playerNum, x, y)
        local menu = {options = {}, numOptions = 0, playerNum = playerNum, x = x, y = y}
        function menu:addOption(name, target, callback, item)
            local option = {name = name, target = target, callback = callback, item = item}
            self.options[#self.options + 1], self.numOptions = option, self.numOptions + 1
            return option
        end
        w.menus[#w.menus + 1] = menu
        return menu
    end}
    function w:container(outer)
        local c = {items = {}, outer = outer}
        function c:getOutermostContainer() return self.outer or self end
        function c:isLockedToCharacter(player) equal(player, w.player); return self.locked == true end
        function c:getAllEvalRecurse(predicate)
            local result = {}
            local function scan(container)
                for _, item in ipairs(container.items) do
                    if predicate(item) then result[#result + 1] = item end
                    if item.bag then scan(item.bag) end
                end
            end
            scan(self)
            return list(result)
        end
        function c:FindAll(fullType)
            local result = {}
            for _, item in ipairs(self.items) do
                if item.fullType == fullType then result[#result + 1] = item end
            end
            return list(result)
        end
        return c
    end
    w.inventory = w:container()
    w.player = {getPlayerNum = function() return 1 end, getInventory = function() return w.inventory end}
    function w:item(container, name, watched, mediaType, fullType)
        local item = {inventoryItem = true, container = container, name = name, watched = watched == true,
            mediaType = mediaType or 1, fullType = fullType or "Base.VHS_Retail"}
        function item:isRecordedMedia() return not self.notMedia end
        function item:getMediaType() return self.mediaType end
        function item:getContainer() return self.container end
        function item:getDisplayName() return self.name end
        function item:hasBeenSeen(player) equal(player, w.player); return self.watched end
        function item:getWorldItem() return self.worldItem end
        container.items[#container.items + 1] = item
        return item
    end
    local visible = {}
    getPlayerLoot = function(playerNum)
        equal(playerNum, 1)
        return {refreshBackpacks = function()
            w.refreshes = w.refreshes + 1
            visible = {w.inventory}
            for _, container in ipairs(w.reachable) do
                if not container.inaccessible then visible[#visible + 1] = container end
            end
        end}
    end
    ISInventoryPaneContextMenu = {getContainers = function(player) equal(player, w.player); return list(visible) end,
        transferIfNeeded = function(player, item)
            equal(player, w.player); w.transfers[#w.transfers + 1] = item; w.steps[#w.steps + 1] = "transfer"
        end}
    luautils = {walkAdj = function(player, square, adjacent)
        equal(player, w.player); equal(adjacent, true); w.walks[#w.walks + 1] = square
        w.steps[#w.steps + 1] = "floor walk"
        return w.worldWalk ~= false
    end}
    ISDeviceBatteryAction = {getDeviceDataParameter = function(_, player, device, deviceType)
        equal(player, w.player); equal(device, w.panel.device); equal(deviceType, "IsoObject")
        return "device parameter"
    end}
    ISDeviceMediaAction = {new = function(_, player, remove, item, parameter)
        equal(player, w.player); equal(parameter, "device parameter")
        return {remove = remove, item = item}
    end}
    ISTimedActionQueue = {add = function(action) w.queue[#w.queue + 1] = action; w.steps[#w.steps + 1] = "queue" end}
    ISItemDropBox = {hasValidItemInDrag = function(button)
        for _, item in ipairs(ISMouseDrag.dragging or {}) do
            if button.onVerifyItem(button.functionTarget, item) then return true end
        end
        return false
    end, onMouseUp = function(button, x, y)
        w.dropCall = {button, x, y}
        if not button.boxOccupied then
            for _, item in ipairs(ISMouseDrag.dragging or {}) do
                if button.onVerifyItem(button.functionTarget, item) then
                    button.onItemDropped(button.functionTarget, {item}); return
                end
            end
        end
    end}
    if NativeDropBoxSource then assert(loadstring(NativeDropBoxSource))() end
    RWMMedia = {addMediaAux = function(panel, item) w.nativeMedia = {panel, item}; return "native insert" end}
    if NativeMediaSource then assert(loadstring(NativeMediaSource))() end
    RWMMergedTV = {drawTexture = ISPanel.drawTexture}
    for _, name in ipairs({"addMedia", "addMediaAux", "onBumperContext", "clear"}) do
        RWMMergedTV[name] = function(self, ...) w.nativeCalls[name] = {self, ...}; return "native " .. name end
    end
    RWMMergedTV.removeMedia = function() w.queue[#w.queue + 1] = {remove = true} end
    RWMMergedTV.createChildren = function(panel)
        panel.slotVHS = ISButton:new(25, 173, 134, 24, "", panel, RWMMergedTV.addMedia)
        panel.slotVHS.backgroundColorMouseOver = {r = 0.15, g = 0.15, b = 0.15, a = 0.5}
        panel.slotVHS.tooltip = "native tooltip"
        return "native children"
    end
    if TVSource then assert(loadstring(TVSource))() end
    -- Video initialisation is registered by upstream before the adapter, but not needed here.
    ISRadioWindow = {instances = {}, instancesIso = {}, activate = function() end,
        prerender = function() end, onMouseDownOutside = function() end}
    dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TVRadio.lua")
    local nativeAdd, nativeClear = RWMMergedTV.addMedia, RWMMergedTV.clear
    w.install()
    w.nativeAdd, w.nativeClear = nativeAdd, nativeClear
    w.panel = setmetatable({player = w.player, device = {}, deviceType = "IsoObject", parent = {},
        deviceData = {hasMedia = function() return w.occupied == true end},
        doWalkTo = function()
            w.deviceWalks = (w.deviceWalks or 0) + 1; w.steps[#w.steps + 1] = "device walk"
            return w.deviceWalk ~= false
        end,
        addChild = function(_, child) w.children[#w.children + 1] = child end}, {__index = RWMMergedTV})
    w.panel:createChildren()
    w.slot = w.panel.slotVHS
    return w
end

local count = 0
local function test(name, body) body(); count = count + 1; print("PASS VHS " .. name) end

test("inventory, nested bags and refreshed reachable loot; access checks and identity dedup", function()
    local w = setup()
    local bag, loot, locked, far = w:container(w.inventory), w:container(), w:container(), w:container()
    w:item(w.inventory, "Bag").notMedia = true
    w.inventory.items[#w.inventory.items].bag = bag
    local own = w:item(w.inventory, "Inventory")
    local nested = w:item(bag, "Bag tape", false, 1, "AnotherMod.VHS")
    local nearby = w:item(loot, "Loot")
    w:item(w.inventory, "CD", false, 0)
    w:item(w.inventory, "Not media").notMedia = true
    w:item(locked, "Locked"); locked.locked = true
    w:item(far, "Out of reach"); far.inaccessible = true
    w.reachable = {loot, loot, bag, locked, far}
    w.panel:addMedia()
    local options = w.menus[1].options
    equal(#options, 3); equal(options[1].item, nested); equal(options[2].item, own); equal(options[3].item, nearby)
    equal(w.refreshes, 1)
    loot.inaccessible = true
    w.panel:addMedia()
    equal(#w.menus[2].options, 2, "cached reachable container must disappear after refresh")
    bag.outer.locked = true
    w.panel:addMedia()
    equal(#w.menus, 2, "no tapes means no empty menu")
end)

test("unwatched first, alphabetical within each group, same watched predicate for ticks", function()
    local w = setup()
    w:item(w.inventory, "A watched", true); w:item(w.inventory, "Z unseen")
    w:item(w.inventory, "Z watched", true); w:item(w.inventory, "A unseen")
    local origin = {}
    JoypadState.players[2] = {focus = origin}
    w.panel:onBumperContext()
    local menu = w.menus[1]
    for i, name in ipairs({"A unseen", "Z unseen", "A watched", "Z watched"}) do
        equal(menu.options[i].name, name)
        equal(menu.options[i].iconTexture, i > 2 and "media/ui/Tick_Mark-10.png" or nil)
        equal(menu.options[i].target, w.panel); equal(menu.options[i].callback, w.panel.addMediaAux)
    end
    equal(menu.playerNum, 1); equal(menu.x, 25); equal(menu.y, 173); equal(menu.mouseOver, 1)
    equal(menu.origin, origin); equal(w.focus[2], menu)
end)

test("occupied slot directly ejects; bumper retains upstream removal menu", function()
    local w = setup()
    w.occupied = true
    w.panel:addMedia()
    equal(#w.queue, 1); equal(w.queue[1].remove, true); equal(#w.menus, 0); equal(w.refreshes, 0)
    w.panel:onBumperContext()
    if TVSource then
        equal(w.menus[1].options[1].name, "IGUI_media_removeMedia")
    else
        equal(w.nativeCalls.onBumperContext[1], w.panel)
    end
end)

test("off delegates original list, auxiliary callback and mouse; live toggle restores visuals", function()
    local w = setup()
    local item = w:item(w.inventory, "Retail")
    w:item(w.inventory, "Modded", false, 1, "AnotherMod.VHS")
    w.enabled = false
    local result = w.panel:addMedia()
    if TVSource then
        equal(#w.menus[1].options, 1); equal(w.menus[1].options[1].item, item)
    else
        equal(result, "native addMedia"); equal(w.nativeCalls.addMedia[1], w.panel)
    end
    w.panel:addMediaAux(item)
    if TVSource then equal(w.queue[1].item, item); equal(#w.transfers, 0)
    else equal(w.nativeCalls.addMediaAux[2], item) end
    ISMouseDrag.dragging = {item}
    equal(w.slot:onMouseUp(3, 4), "native mouse"); equal(w.nativeMouse[2], 3); equal(w.nativeMouse[3], 4)
    local hover, tooltip = w.slot.backgroundColorMouseOver, w.slot.tooltip
    w.enabled = true
    w.slot:prerender()
    equal(w.slot.tooltip, "UI_PZSurvivorToolkit_vhs_slot_tooltip"); equal(w.renderedColor.g, 0.45)
    w.enabled = false
    w.slot:prerender()
    equal(w.slot.backgroundColorMouseOver, hover); equal(w.slot.tooltip, tooltip)
    equal(RWMMergedTV.clear, w.nativeClear, "device cleanup must remain upstream")
    w.enabled = true; ISMouseDrag.dragging = nil
    w.slot:prerender(); equal(w.slot.backgroundColorMouseOver, hover)
end)

test("drag routes through native drop box; invalid, stale and occupied tapes never insert", function()
    local w = setup()
    local valid = w:item(w.inventory, "Tape")
    local invalid = w:item(w.inventory, "CD", false, 0)
    local function inserts() return NativeMediaSource and #w.queue or (w.nativeMedia and 1 or 0) end
    ISMouseDrag.dragging = {invalid}
    w.slot.pressed = true
    w.slot:prerender(); equal(w.renderedColor.r, 0.5)
    w.slot:onMouseUp(2, 7); equal(inserts(), 0); equal(w.slot.pressed, false)
    ISMouseDrag.dragging = {valid}
    w.occupied = true
    w.slot:prerender(); equal(w.renderedColor.r, 0.5)
    w.slot:onMouseUp(2, 7); equal(inserts(), 0)
    w.occupied = false
    valid.container = nil
    w.slot:onMouseUp(2, 7); equal(inserts(), 0, "stale drag is revalidated")
    valid.container = w.inventory
    w.slot:onMouseUp(2, 7); equal(inserts(), 1)
    if not NativeDropBoxSource then equal(w.dropCall[2], 2); equal(w.dropCall[3], 7) end
    -- In-game parser owns stack flattening: test its real code when supplied, not a copied implementation.
    if NativeDropBoxSource then
        for _, drag in ipairs({{{items = {"stack header", valid, invalid}}}, {invalid, valid}}) do
            local before = #w.queue
            ISMouseDrag.dragging = drag
            w.slot:onMouseUp(0, 0)
            if NativeMediaSource then equal(#w.queue, before + 1) end
        end
        ISMouseDrag.draggingFocus = w.slot
        local before = #w.queue
        w.slot:onMouseUp(0, 0); equal(#w.queue, before, "dragging out of the same slot must not insert")
    end
end)

test("menu callback revalidates access and occupancy before the native insertion path", function()
    local w = setup()
    local loot = w:container()
    local item = w:item(loot, "Loot tape")
    w.reachable = {loot}
    w.panel:addMedia()
    local option = w.menus[1].options[1]
    loot.inaccessible = true
    option.callback(option.target, option.item)
    equal(#w.queue, 0); equal(w.nativeMedia, nil)
    loot.inaccessible = false; w.occupied = true
    option.callback(option.target, option.item)
    equal(#w.queue, 0); equal(w.nativeMedia, nil)
    w.occupied = false
    option.callback(option.target, option.item)
    if NativeMediaSource then equal(w.queue[1].item, item); equal(w.transfers[1], item)
    else equal(w.nativeMedia[1], w.panel); equal(w.nativeMedia[2], item) end
end)

if NativeMediaSource then
    test("native media walks to floor item, transfers before queueing and retains walk failures", function()
        local w = setup()
        local floor = w:container()
        local item = w:item(floor, "Floor tape")
        local square = {}
        item.worldItem = {getSquare = function() return square end}
        w.reachable = {floor}
        w.worldWalk = false
        w.panel:addMediaAux(item)
        equal(w.walks[1], square); equal(#w.transfers, 0); equal(#w.queue, 0)
        w.worldWalk, w.deviceWalk = true, false
        w.panel:addMediaAux(item)
        equal(w.transfers[1], item); equal(#w.queue, 0)
        w.deviceWalk = true; w.steps = {}
        w.panel:addMediaAux(item)
        equal(w.queue[1].item, item); equal(w.queue[1].remove, false)
        equal(table.concat(w.steps, ","), "floor walk,transfer,device walk,queue")
    end)
end

test("inactive TV mod stays untouched and repeated installs do not stack wrappers", function()
    local w = setup(false)
    equal(RWMMergedTV.addMedia, w.nativeAdd)
    w.active = true; w.install()
    local hooked = RWMMergedTV.addMedia
    w.install(); equal(RWMMergedTV.addMedia, hooked)
end)

test("missing TV video uses scaled fallback; other texture calls remain upstream", function()
    local w = setup()
    local panel = w.panel
    panel.noSignal = {}
    panel.drawTextureScaled = function(self, ...)
        w.scaledCall = {...}; return "scaled texture"
    end
    equal(panel:drawTexture(panel.noSignal, 7, 6, 160, 120, 1, 1, 1, 1), "scaled texture")
    equal(#w.scaledCall, 9)
    for i, value in ipairs({panel.noSignal, 7, 6, 160, 120, 1, 1, 1, 1}) do equal(w.scaledCall[i], value) end
    local texture = {}
    equal(panel:drawTexture(texture, 2, 3, 0.5, 1, 1, 1), "native texture")
    equal(w.textureCall[1], texture); equal(w.textureCall[4], 0.5)
    equal(panel:drawTexture(panel.noSignal, 7, 6, 1, 1, 1, 1), "native texture")
    if TVSource then
        panel.deviceData = {getIsTurnedOn = function() return true end}
        panel.video = nil
        panel:prerender()
        equal(w.scaledCall[4], 160); equal(w.scaledCall[6], 1)
        equal(w.panelPrerender, true)
    end
end)

if NativeTVWindowSource then
    test("base TV window resolves EN/RU identities and retains controller, range and close lifecycle", function()
        local active, keepOpen, language = false, true, "EN"
        require = function(name)
            if name == "PZSurvivorToolkit/TVDeviceResolver" then
                return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TVDeviceResolver.lua")
            end
        end
        PZSurvivorToolkit = {Settings = {improveVHSControls = function() return false end,
            keepMediaWindowOpen = function() return keepOpen end}}
        local start, equipPrimary, equipSecondary
        Events = {OnGameStart = {Add = function(fn) start = fn end},
            OnEquipPrimary = {Add = function(fn) equipPrimary = fn end},
            OnEquipSecondary = {Add = function(fn) equipSecondary = fn end}}
        getActivatedMods = function() return {contains = function() return active end} end
        instanceof = function(object, class) return object and object.classes and object.classes[class] == true end
        getTextManager = function() return {getFontHeight = function() return 14 end, MeasureStringX = function() return 50 end} end
        getText = function(key) return key end
        UIFont = {Small = 1, Large = 2}
        getItemNameFromFullType = function(itemType) return language .. ":" .. itemType end
        local translatedName = getItemNameFromFullType
        local closed, parentRenders, focus, draw
        ISCollapsableWindow = {derive = function(self) return setmetatable({}, {__index = self}) end,
            close = function() closed = true end, update = function() end,
            prerender = function() parentRenders = (parentRenders or 0) + 1 end}
        ISUIElement = {stayOnSplitScreen = function() end}
        assert(loadstring(NativeTVWindowSource))()
        local nativeRead, nativeRender = ISRadioWindow.readFromObject, ISRadioWindow.prerender
        local nativeClose, nativeUpdate, nativeInput = ISRadioWindow.close, ISRadioWindow.update, ISRadioWindow.onJoypadDown
        RWMMergedTV = nil
        dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TVRadio.lua")
        start()
        equal(ISRadioWindow.readFromObject, nativeRead, "disabled TV mod must not patch resolution")
        active = true; start()
        assert(ISRadioWindow.readFromObject ~= nativeRead and ISRadioWindow.prerender ~= nativeRender)
        equal(ISRadioWindow.close, nativeClose); equal(ISRadioWindow.update, nativeUpdate)
        equal(ISRadioWindow.onJoypadDown, nativeInput)
        equal(equipPrimary, ISRadioWindow.onEquip); equal(equipSecondary, ISRadioWindow.onEquip)
        local window = {playerNum = 0, width = 283, modules = {}, title = "window",
            valutechTV = "tv", premiumTV = "wide", antiqueTV = "antique", carRadio = "car",
            premiumRadio = "red", valutechRadio = "black", playerCD = "cd", walkieTalkie = "walkie", RadioHAM = "ham"}
        setmetatable(window, {__index = ISRadioWindow})
        local controls = {onJoypadDown = function(self, button) self.lastButton = button end,
            onJoypadDirUp = function(self) self.up = true end}
        for i = 1, 6 do
            window.modules[i] = {enabled = false, element = {subpanel = controls,
                setVisible = function(self, visible) self.visible = visible end,
                clear = function(self) self.cleared = true end,
                readFromObject = function(self, player, device, data, kind) self.read = {player, device, data, kind} end}}
        end
        window.closeButton = {setVisible = function(self, visible) self.visible = visible end,
            setX = function() end, setY = function() end, bringToTop = function() end, getWidth = function() return 18 end}
        window.collapseButton = {setVisible = function() end}
        for _, name in ipairs({"addToUIManager", "removeFromUIManager", "initialise", "instantiate"}) do window[name] = function() end end
        function window:setVisible(value) self.visible = value end
        function window:getIsVisible() return self.visible end
        function window:setWidth(value) self.width = value end
        function window:setHeight(value) self.height = value end
        function window:getWidth() return self.width end
        function window:titleBarHeight() return 18 end
        function window:drawTexture(texture) draw = texture end
        Joypad = {AButton = 1, BButton = 2, RBumper = 3}
        JoypadState = {players = {}}
        local origin = {setVisible = function(self, value) self.visible = value end}
        getFocusForPlayer = function() return focus end
        setJoypadFocus = function(_, value) focus = value end
        getCore = function() return {getOptionFontSizeReal = function() return 1 end} end
        local player = {getPlayerNum = function() return 0 end, setVariable = function() end,
            getX = function() return 0 end, getY = function() return 0 end,
            getPrimaryHandItem = function(self) return self.held end,
            getSecondaryHandItem = function() end, getClothingItem_Back = function() end}
        getPlayer = function() return player end
        local screen = {close = function(self) self.closed = true end}
        getPlayerInventory, getPlayerLoot = function() return screen end, function() return screen end
        local function device(itemType, kind, name)
            local data = {getDeviceName = function() return name or "untranslated device" end,
                setIsTurnedOn = function(self, value) self.on = value end}
            local object = {classes = {[kind] = true}, getFullType = function() return itemType end,
                getDeviceData = function() return data end, getID = function() return 7 end,
                getModData = function() return {} end, getProperties = function() return {get = function() end} end,
                getSquare = function() return {} end, getX = function() return 0 end, getY = function() return 0 end}
            if kind == "InventoryItem" then object.classes.Radio = true end
            if kind == "IsoRadio" or kind == "IsoTelevision" then object.classes.IsoObject = true; object.classes.IsoWaveSignal = true end
            return object, data
        end
        local function check(object, module, texture)
            draw = nil
            window:readFromObject(player, object)
            for i = 1, 6 do equal(window.modules[i].enabled, i == module) end
            window:prerender(); equal(draw, texture)
            equal(window.title, object:getDeviceData():getDeviceName(), "display title must remain native")
            equal(getItemNameFromFullType, translatedName, "translation getter must be restored")
        end
        for _, lang in ipairs({"EN", "RU"}) do
            language = lang
            for _, case in ipairs({{"Base.TvBlack", 1, "tv"}, {"Base.TvWideScreen", 1, "wide"},
                {"Base.TvAntique", 1, "antique"}, {"Base.RadioRed", 3, "red"}, {"Base.RadioBlack", 3, "black"},
                {"Base.CDplayer", 4, "cd"}, {"Base.ManPackRadio", 5, "walkie"},
                {"Base.WalkieTalkieMakeShift", 5, "walkie"}, {"Base.HamRadio5", 6, "ham"}}) do
                check(device(case[1], "InventoryItem"), case[2], case[3])
            end
            local furniture = device(nil, "IsoTelevision")
            furniture.getProperties = function() return {get = function() return "TvWideScreen" end} end
            check(furniture, 1, "wide")
            furniture.getProperties = function() return {get = function() return "Base.TvAntique" end} end
            check(furniture, 1, "antique")
            local radio = device("Base.RadioRed", "InventoryItem")
            local floor = device(nil, "IsoRadio")
            floor.getModData = function() return {RadioItemID = 7} end
            local world = {classes = {IsoWorldInventoryObject = true}, getItem = function() return radio end}
            floor.getSquare = function() return {getWorldObjects = function() return list({world}) end,
                getObjects = function() return list({}) end} end
            check(floor, 3, "red")
            floor.getSquare = function() return {getWorldObjects = function() end, getObjects = function() return list({world}) end} end
            check(floor, 3, "red")
            check(device(nil, "IsoTelevision"), 1, "tv")
            check(device(nil, "IsoRadio"), 3, "black")
            local car = device(nil, "VehiclePart")
            car.getInventoryItem = function() return radio end
            check(car, 2, "car")
            check(device("Unknown.TV", "InventoryItem", translatedName("Base.TvBlack")), nil, nil)
        end
        JoypadState.players[1] = {}; focus = origin
        local held, data = device("Base.RadioRed", "InventoryItem")
        player.held = held
        ISRadioWindow.instances[0] = window
        equal(ISRadioWindow.activate(player, held), window)
        equal(focus, window); equal(screen.closed, true); equal(window.closeButton.visible, true)
        equipPrimary(player, held); equal(window.device, held)
        equipSecondary(player, held); equal(window.device, held)
        window:setVisible(true)
        window:onJoypadDirUp(); equal(controls.up, true)
        window:onJoypadDown(Joypad.RBumper); equal(controls.lastButton, Joypad.RBumper); equal(controls.parent, window)
        window:onMouseDownOutside(-1, 0); equal(window.visible, true)
        window:update(); equal(window.visible, true, "held device must remain open")
        player.held = nil; window:update()
        equal(closed, true); equal(window.device, nil); equal(focus, nil); equal(data.on, false)
        assert(parentRenders > 0)
        local resolver = PZSurvivorToolkit.TVDeviceResolver
        assert(not pcall(resolver.call, held, function() error("fixture error") end))
        equal(getItemNameFromFullType, translatedName, "translation getter must restore on failure")
        if TVSource then
            RWMPanel.readFromObject = function(panel, p, object, d, kind)
                panel.player, panel.device, panel.deviceData, panel.deviceType = p, object, d, kind
                return true
            end
            assert(loadstring(TVSource))()
            for _, itemType in ipairs({"Base.TvAntique", "Base.TvBlack"}) do
                local object, d = device(itemType, "InventoryItem")
                d.getDeviceVolume = function() return 0.5 end
                d.getChannel = function() return 200 end
                d.getDevicePresets = function() return {getPresets = function() return list({{getFrequency = function() return 200 end}}) end} end
                local slot = {setVisible = function(self, value) self.visible = value end}
                local panel = {slotVHS = slot, playMediaButton = slot,
                    volumeBar = {setVolume = function() end, getVolumeSteps = function() return 10 end}}
                resolver.call(object, RWMMergedTV.readFromObject, panel, player, object, d, "InventoryItem")
                equal(panel.canMedia, itemType ~= "Base.TvAntique")
                equal(slot.visible, panel.canMedia)
                equal(getItemNameFromFullType, translatedName)
            end
        end
        print("PASS TV identity: EN/RU, held/floor/furniture/fallback/vehicle, unknown type and controller/range lifecycle")
    end)
end

print("Passed " .. count .. " VHS controls tests" .. (NativeDropBoxSource and " (native drag parser)" or " (drag dispatch double)") .. ".")
