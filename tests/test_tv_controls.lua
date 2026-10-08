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
    require = function() end
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
    RWMMergedTV = {}
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

print("Passed " .. count .. " VHS controls tests" .. (NativeDropBoxSource and " (native drag parser)" or " (drag dispatch double)") .. ".")
