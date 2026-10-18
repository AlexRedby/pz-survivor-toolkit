local root = ProjectRoot or "."
local failures, checked = {}, 0
local function test(name, callback)
    checked = checked + 1
    local ok, err = pcall(callback)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local function fixture(client)
    local h = {valid = true, nextID = 0, callbacks = {}, emitted = {}}
    require = function() end
    isClient = function() return client == true end
    instanceof = function(value, kind) return kind == "InventoryItem" and type(value) == "table" and value.inventoryItem end
    Events = {OnMainMenuEnter = {Add = function(callback) h.callbacks[#h.callbacks + 1] = callback end}}
    PZSurvivorToolkit = {Settings = {actionQueue = function() return false end}}
    local function class(name)
        local value = {Type = name}
        value.__index = value
        function value:new(player, item) return setmetatable({character = player, item = item}, self) end
        return value
    end
    ISInventoryTransferAction = class("ISInventoryTransferAction")
    function ISInventoryTransferAction:new(player, item, source, destination)
        return setmetatable({character = player, item = item, srcContainer = source, destContainer = destination, queueList = {{items={item},time=1,type=item:getFullType()}}}, self)
    end
    ISEquipWeaponAction = class("ISEquipWeaponAction")
    function ISEquipWeaponAction:new(player, item, time, primary, twoHands)
        return setmetatable({character = player, item = item, primary = primary, twoHands = twoHands}, self)
    end
    ISUnequipAction = class("ISUnequipAction")
    ISWearClothing = class("ISWearClothing")
    ISAttachItemHotbar = class("ISAttachItemHotbar")
    function ISAttachItemHotbar:new(player, item, slot)
        return setmetatable({character = player, item = item, slot = slot}, self)
    end
    P4RestoreAction = class("P4RestoreAction")
    function P4RestoreAction:new(player, item, activated)
        return setmetatable({character = player, item = item, activated = activated}, self)
    end
    P4RestoreFloorAction = class("P4RestoreFloorAction")
    ISQueueActionsAction = {start = function() end}
    local acceptedClasses = {[ISInventoryTransferAction] = true, [ISEquipWeaponAction] = true,
        [ISUnequipAction] = true, [ISWearClothing] = true, [ISAttachItemHotbar] = true,
        [P4RestoreAction] = true, [P4RestoreFloorAction] = true}
    h.inventory = {items = {}}
    function h.inventory:getItemById(id) return self.items[id] end
    h.source = {items = {}}
    h.player = {primary = nil, secondary = nil, worn = {}, attached = {}}
    function h.player:getInventory() return h.inventory end
    function h.player:getPrimaryHandItem() return self.primary end
    function h.player:getSecondaryHandItem() return self.secondary end
    function h.player:getWornItem(location) return self.worn[location] end
    function h.player:getAttachedItems() return {getItem = function(_, slot) return h.player.attached[slot] end} end
    function h.player:hasTimedActions() return self.nativeBusy == true end
    function h.player:isDead() return self.dead == true end
    function getSpecificPlayer(number) if number == 0 then return h.player end end
    h.queue = {queue = {}, character = h.player}
    function h.queue:indexOf(action)
        for index, value in ipairs(self.queue) do if value == action then return index end end
        return -1
    end
    ISTimedActionQueue = {queues = {[h.player] = h.queue}}
    function ISTimedActionQueue.getTimedActionQueue(player) return ISTimedActionQueue.queues[player] end
    function ISTimedActionQueue.addToQueue(queue, action)
        if action.rejected then return end
        queue.queue[#queue.queue + 1] = action
        if h.instant then h.complete(action) end
        return queue
    end
    function ISTimedActionQueue.add(action)
        return ISTimedActionQueue.addToQueue(ISTimedActionQueue.getTimedActionQueue(action.character), action)
    end
    function ISTimedActionQueue.addAfter(previous, action)
        local queue = ISTimedActionQueue.getTimedActionQueue(action.character)
        if action.rejected then return queue end
        local actual = action.replacement or action
        table.insert(queue.queue, queue:indexOf(previous) + 1, actual)
        return queue, actual
    end
    local function ui(kind, items)
        if h.onUI then return h.onUI(kind, items) end
        for _, item in ipairs(items) do
            local action
            if kind == "grab" then action = h.transfer(item, h.inventory)
            elseif kind == "equip" then action = h.equip(item, true, false)
            elseif kind == "secondary" then action = h.equip(item, false, false)
            elseif kind == "twoHands" then action = h.equip(item, true, true)
            elseif kind == "unequip" then action = ISUnequipAction:new(h.player, item)
            elseif kind == "wear" then action = ISWearClothing:new(h.player, item) end
            ISTimedActionQueue.add(action)
        end
        return "native result", nil, 23
    end
    ISInventoryPaneContextMenu = {
        equipWeapon = function() end,
        transferIfNeeded = function() end,
        OnPrimaryWeapon = function(items) return ui("equip", items) end,
        OnSecondWeapon = function(items) return ui("secondary", items) end,
        OnTwoHandsEquip = function(items) return ui("twoHands", items) end,
        onGrabItems = function(items) return ui("grab", items) end,
        onGrabOneItems = function(items) return ui("grab", items) end,
        onGrabHalfItems = function(items) return ui("grab", items) end,
        onWearItems = function(items) return ui("wear", items) end,
        onUnEquip = function(items) return ui("unequip", items) end,
    }
    ISInventoryPane = {getActualItems = function(items) return items end}
    ISInventoryTransferUtil = {newInventoryTransferAction = function(...) return ISInventoryTransferAction:new(...) end}
    ISHotbar = {attachItem = function(bar, item, slot, _, _, animated)
        if animated then return ISTimedActionQueue.add(ISAttachItemHotbar:new(bar.chr, item, slot)) end
        bar.chr.attached[slot] = item
    end}
    h.intent = assert(loadfile(root .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueTidyIntent.lua"))()
    h.lifecycle = assert(loadfile(root .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua"))()
    h.intent.install(function(action)
        return h.valid and (not action or acceptedClasses[getmetatable(action)] and not action.changed
            and not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc
            and not action.retriggerLastAction and not action.onFailFunc and not action.additionalTest)
    end, function(menu,name)
        return h.approvedWrapper and menu==ISInventoryPaneContextMenu and menu['_ocStick_'..name]==menu[name]
    end)
    function h.item(container, id, kind)
        h.nextID = h.nextID + 1
        local value = {inventoryItem = true, id = id or h.nextID, kind = kind or "Base.Hammer", container = container or h.inventory}
        function value:getWeight() return self.weight or 0.1 end
        function value:setJobDelta() end
        function value:getID() return self.id end
        function value:getFullType() return self.kind end
        function value:getContainer() return self.container end
        function value:IsClothing() return self.location ~= nil end
        function value:getBodyLocation() return self.location end
        function value:canBeEquipped() return self.location end
        function value:canBeActivated() return self.activatable == true end
        function value:isActivated() return self.activated == true end
        value.container.items[value.id] = value
        return value
    end
    function h.move(item, destination)
        item.container.items[item.id] = nil
        item.container = destination
        destination.items[item.id] = item
    end
    function h.transfer(item, destination) return ISInventoryTransferAction:new(h.player, item, item:getContainer(), destination) end
    function h.equip(item, primary, twoHands) return ISEquipWeaponAction:new(h.player, item, 1, primary, twoHands) end
    function h.complete(action, noEffect, succeeded)
        local phase = (client or getmetatable(action) == ISInventoryTransferAction) and "perform" or "complete"
        h.lifecycle.begin(action, phase)
        if not noEffect then
            if getmetatable(action) == ISInventoryTransferAction then
                h.move(action.item, action.destContainer)
                if action.destContainer ~= h.inventory then
                    if h.player.primary == action.item then h.player.primary = nil end
                    if h.player.secondary == action.item then h.player.secondary = nil end
                    for slot, item in pairs(h.player.attached) do if item == action.item then h.player.attached[slot] = nil end end
                    for location, item in pairs(h.player.worn) do if item == action.item then h.player.worn[location] = nil end end
                end
            elseif getmetatable(action) == ISEquipWeaponAction then
                local before = h.player.primary and h.player.primary == h.player.secondary
                if action.twoHands then h.player.primary, h.player.secondary = action.item, action.item
                elseif action.primary then
                    if before or h.player.secondary == action.item then h.player.secondary = nil end
                    h.player.primary = action.item
                else
                    if before or h.player.primary == action.item then h.player.primary = nil end
                    h.player.secondary = action.item
                end
                if action.item.activatable then action.item.activated = true end
            elseif getmetatable(action) == ISUnequipAction then
                if h.player.primary == action.item then h.player.primary = nil end
                if h.player.secondary == action.item then h.player.secondary = nil end
            elseif getmetatable(action) == ISWearClothing then h.player.worn[action.item.location] = action.item
            elseif getmetatable(action) == ISAttachItemHotbar then h.player.attached[action.slot] = action.item
            elseif getmetatable(action) == P4RestoreAction then action.item.activated = action.activated end
        end
        h.lifecycle.finish(action, phase, succeeded ~= false)
        local index = h.queue:indexOf(action)
        if index ~= -1 then table.remove(h.queue.queue, index) end
    end
    function h.drain()
        while #h.queue.queue > 0 do h.complete(h.queue.queue[1]) end
    end
    function h.tick(callback) return h.intent.update(h.player, callback or function() end) end
    function h.restore(callback) h.tick(); return h.tick(callback) end
    function h.manualGrab(item)
        ISInventoryPaneContextMenu.onGrabItems({item}, 0)
        h.drain()
    end
    function h.nativeMerge()
        assert(NativeActionRoot, 'native source root required')
        local path=NativeActionRoot..'/client/TimedActions/ISInventoryTransferAction.lua'
        local source
        if NativeReadText then source=NativeReadText(path) else
            local file=assert(io.open(path));source=file:read('*a');file:close()
        end
        source=source:gsub('\r','')
        for _,name in ipairs({'canMergeAction','checkQueueList','perform'}) do
            local body=assert(source:match('(function ISInventoryTransferAction:'..name..'%b().-\nend)'))
            assert(loadstring(body))()
        end
        table.wipe=function(value) for key in pairs(value) do value[key]=nil end end
        round=function(value) return value end
        ISInventoryPage={}
        ISBaseTimedAction={perform=function(action)
            local index=h.queue:indexOf(action)
            if index~=-1 then table.remove(h.queue.queue,index) end
        end}
        createItemTransaction=function() return 1 end
        removeItemTransaction=function() end
        local noop=function() end
        for _,name in ipairs({'playTransferCompleteSound','resetJobDelta','startActionAnim','playSourceContainerCloseSound',
            'playDestContainerCloseSound','stopLoopingSound'}) do ISInventoryTransferAction[name]=noop end
        ISInventoryTransferAction.isAlreadyTransferred=function(_,item) return item:getContainer()==h.inventory end
        ISInventoryTransferAction.isValid=function(action) return not action.blocked or not action.blocked[action.item:getID()] end
        ISInventoryTransferAction.transferItem=function(action,item) h.move(item,action.destContainer) end
        h.intent.observeTransfers()
        function h.prepareNative(action)
            action.action={reset=noop,setTime=noop,stopTimedActionAnim=noop,setLoopedAction=noop,setWaitForFinished=noop}
        end
        function h.performNative(action,failed)
            h.prepareNative(action)
            if client then
                for _,item in ipairs(action.queueList[1].items) do
                    if not action.blocked or not action.blocked[item:getID()] then h.move(item,action.destContainer) end
                end
            end
            h.lifecycle.begin(action,'perform')
            action:perform()
            h.lifecycle.finish(action,'perform',not failed)
        end
    end
    return h
end

test("confirmed explicit pickup keeps item and borrowed tool returns", function()
    local h = fixture()
    local kept, borrowed = h.item(h.source), h.item(h.inventory)
    h.manualGrab(kept)
    h.restore(function()
        ISTimedActionQueue.add(h.transfer(kept, h.source))
        ISTimedActionQueue.add(h.transfer(borrowed, h.source))
    end)
    assert(#h.queue.queue == 1 and h.queue.queue[1].item == borrowed)
    h.drain()
    assert(kept:getContainer() == h.inventory and borrowed:getContainer() == h.source)
end)

test("instant explicit equip confirms through lifecycle before UI callback returns", function()
    local h = fixture()
    local kept = h.item()
    h.instant = true
    local a, b, c = ISInventoryPaneContextMenu.OnPrimaryWeapon({kept}, 0)
    assert(a == "native result" and b == nil and c == 23)
    h.instant = false
    h.player.primary = nil
    h.restore(function() ISTimedActionQueue.add(h.transfer(kept, h.source)) end)
    h.drain()
    assert(kept:getContainer() == h.inventory and h.player.primary == kept)
end)

test("manual primary overlay preserves native restore of borrowed secondary", function()
    local h = fixture()
    local manual, borrowed, original = h.item(), h.item(), h.item()
    h.player.secondary = borrowed
    ISInventoryPaneContextMenu.OnPrimaryWeapon({manual}, 0); h.drain()
    h.restore(function()
        ISTimedActionQueue.add(ISUnequipAction:new(h.player, manual))
        ISTimedActionQueue.add(h.equip(original, false, false))
        ISTimedActionQueue.add(h.transfer(borrowed, h.source))
    end)
    h.drain()
    assert(h.player.primary == manual and h.player.secondary == original)
    assert(borrowed:getContainer() == h.source)
end)

test("manual two-handed equip owns both slots", function()
    local h = fixture()
    local manual, oldPrimary, oldSecondary = h.item(), h.item(), h.item()
    ISInventoryPaneContextMenu.OnTwoHandsEquip({manual}, 0); h.drain()
    h.player.primary, h.player.secondary = oldPrimary, oldSecondary
    h.restore(function()
        ISTimedActionQueue.add(h.equip(oldPrimary, true, false))
        ISTimedActionQueue.add(h.equip(oldSecondary, false, false))
        ISTimedActionQueue.add(h.transfer(manual, h.source))
    end)
    h.drain()
    assert(h.player.primary == manual and h.player.secondary == manual)
end)

test("manual equip leaving a two-handed item frees the other slot", function()
    for _, client in ipairs({false, true}) do
        local h = fixture(client)
        local manual, old = h.item(), h.item()
        h.player.primary, h.player.secondary = old, old
        ISInventoryPaneContextMenu.OnPrimaryWeapon({manual}, 0); h.drain()
        h.restore(function() ISTimedActionQueue.add(h.equip(old, true, true)) end)
        h.drain()
        assert(h.player.primary == manual and h.player.secondary == nil,
            "two-hand transition was not retained in " .. (client and "MP" or "SP"))
    end
end)

test("moving a manual item between hands preserves the freed slot", function()
    for _, primary in ipairs({true, false}) do
        local h = fixture()
        local manual, old = h.item(), h.item()
        h.player.primary, h.player.secondary = primary and old or manual, primary and manual or old
        local callback = primary and ISInventoryPaneContextMenu.OnPrimaryWeapon or ISInventoryPaneContextMenu.OnSecondWeapon
        callback({manual}, 0); h.drain()
        local function otherHand() if primary then return h.player.secondary end return h.player.primary end
        assert(otherHand() == nil)
        h.restore(function()
            ISTimedActionQueue.add(h.equip(old, primary, false))
            ISTimedActionQueue.add(h.equip(manual, not primary, false))
        end)
        h.drain()
        assert((primary and h.player.primary or h.player.secondary) == manual,
            "manual target slot lost after " .. (primary and "primary" or "secondary") .. " hand move")
        assert(otherHand() == nil, "manual hand move restored the item into both hands")
    end
end)

test("manual equip activation survives P4's older hand snapshot", function()
    local h = fixture()
    local torch, old = h.item(nil, nil, "Base.HandTorch"), h.item()
    torch.activatable, torch.activated = true, false
    h.player.primary, h.player.secondary = old, torch
    ISInventoryPaneContextMenu.OnPrimaryWeapon({torch}, 0); h.drain()
    assert(torch:isActivated())
    h.restore(function()
        ISTimedActionQueue.add(h.equip(old, true, false))
        ISTimedActionQueue.add(h.equip(torch, false, false))
        ISTimedActionQueue.add(P4RestoreAction:new(h.player, torch, false))
    end)
    h.drain()
    assert(h.player.primary == torch and h.player.secondary == nil)
    assert(torch:isActivated(), "stale P4 activation undid the manual equip effect")
end)

test("later explicit unequip supersedes earlier manual equip", function()
    local h = fixture()
    local manual, original = h.item(), h.item()
    h.player.primary = original
    ISInventoryPaneContextMenu.OnPrimaryWeapon({manual}, 0); h.drain()
    ISInventoryPaneContextMenu.onUnEquip({manual}, 0); h.drain()
    assert(h.player.primary == nil)
    h.restore(function() ISTimedActionQueue.add(h.equip(original, true, false)) end)
    h.drain()
    assert(h.player.primary == nil, "earlier manual equip overrode the later explicit unequip")
end)

test("MP keeps pre-start hand intent when server changes hands before perform", function()
    local h=fixture(true)
    local old,manual=h.item(),h.item()
    ISInventoryPaneContextMenu.OnTwoHandsEquip({old},0);h.drain()
    ISInventoryPaneContextMenu.OnPrimaryWeapon({manual},0)
    local action=h.queue.queue[1];h.intent.start(action)
    -- EquipPacket has already applied the server's result when client perform runs.
    h.player.primary,h.player.secondary=manual,nil
    h.complete(action,true)
    h.restore(function() ISTimedActionQueue.add(h.equip(old,true,true)) end);h.drain()
    assert(h.player.primary==manual and h.player.secondary==nil)
end)

test("MP explicit unequip uses pre-start slots after the server clears them", function()
    local h=fixture(true)
    local manual=h.item()
    ISInventoryPaneContextMenu.OnTwoHandsEquip({manual},0);h.drain()
    ISInventoryPaneContextMenu.onUnEquip({manual},0)
    local action=h.queue.queue[1];h.intent.start(action)
    h.player.primary,h.player.secondary=nil,nil
    h.complete(action,true)
    h.restore(function() ISTimedActionQueue.add(h.equip(manual,true,true)) end);h.drain()
    assert(h.player.primary==nil and h.player.secondary==nil)
end)

test("MP perform confirms an instant intent without SP complete", function()
    local h = fixture(true)
    local kept = h.item(h.source)
    h.instant = true
    ISInventoryPaneContextMenu.onGrabOneItems({kept}, 0)
    h.instant = false
    h.restore(function() ISTimedActionQueue.add(h.transfer(kept, h.source)) end)
    assert(#h.queue.queue == 0)
end)

test("unaccepted action does not create pickup intent", function()
    local h = fixture()
    local item = h.item(h.source)
    h.onUI = function()
        local action = h.transfer(item, h.inventory); action.rejected = true
        ISTimedActionQueue.add(action)
    end
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    h.move(item, h.inventory)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, "rejected pickup protected an unrelated later pickup")
end)

test("cancelled queued intent does not protect an unrelated later pickup", function()
    local h = fixture()
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    h.queue.queue = {}
    h.move(item, h.inventory)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, "cancelled pickup inferred success from later inventory state")
end)

test("direct addToQueue captures a real explicit pickup once", function()
    local h = fixture()
    local item = h.item(h.source)
    h.onUI = function() return ISTimedActionQueue.addToQueue(h.queue, h.transfer(item, h.inventory)) end
    ISInventoryPaneContextMenu.onGrabItems({item}, 0); h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 0)
end)

test("addAfter captures the actual accepted explicit pickup", function()
    local h = fixture()
    local item = h.item(h.source)
    local preceding = h.equip(h.item(), true, false)
    ISTimedActionQueue.add(preceding)
    h.onUI = function()
        local requested = h.transfer(item, h.inventory)
        requested.replacement = h.transfer(item, h.inventory)
        return ISTimedActionQueue.addAfter(preceding, requested)
    end
    ISInventoryPaneContextMenu.onGrabItems({item}, 0); h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 0, "intent was attached to discarded requested action instead of accepted action")
end)

test("native completion without requested effect does not confirm", function()
    local h = fixture()
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    h.complete(h.queue.queue[1], true)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("no-effect completion cannot confirm from a later unrelated transfer", function()
    local h = fixture()
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    h.complete(h.queue.queue[1], true)
    h.move(item, h.inventory)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, "no-effect action gained success from a subsequent inventory change")
end)

test("failed native completion does not confirm even if item later appears", function()
    local h = fixture()
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    h.complete(h.queue.queue[1], true, false)
    h.move(item, h.inventory)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("confirmed pickup survives cancellation of later unrelated action", function()
    local h = fixture()
    local kept = h.item(h.source)
    h.manualGrab(kept)
    local unrelated = h.equip(h.item(), true, false)
    ISTimedActionQueue.add(unrelated); h.queue.queue = {}
    h.restore(function() ISTimedActionQueue.add(h.transfer(kept, h.source)) end)
    assert(#h.queue.queue == 0)
end)

test("item wrapper rebind keeps the same inventory identity", function()
    local h = fixture()
    local old = h.item(h.source, 77, "Base.Hammer")
    h.manualGrab(old)
    local rebound = h.item(h.inventory, 77, "Base.Hammer")
    h.restore(function() ISTimedActionQueue.add(h.transfer(rebound, h.source)) end)
    assert(#h.queue.queue == 0)
end)

test("same ID with changed full type is not protected", function()
    local h = fixture()
    local old = h.item(h.source, 77, "Base.Hammer")
    h.manualGrab(old)
    local changed = h.item(h.inventory, 77, "Base.Screwdriver")
    h.restore(function() ISTimedActionQueue.add(h.transfer(changed, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("changed guard leaves native P4 returns untouched", function()
    local h = fixture()
    local item = h.item(h.source)
    h.manualGrab(item); h.valid = false
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("changed native helper disables previously captured intent", function()
    local h = fixture()
    local item = h.item(h.source)
    h.manualGrab(item)
    ISInventoryPaneContextMenu.transferIfNeeded = function() end
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("changed item normalizer prevents new explicit capture", function()
    local h = fixture()
    local item = h.item(h.source)
    ISInventoryPane.getActualItems = function(items) return items end
    ISInventoryPaneContextMenu.onGrabItems({item}, 0); h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("changed restore action is not suppressed", function()
    local h = fixture()
    local item = h.item(h.source)
    h.manualGrab(item)
    h.restore(function()
        local action = h.transfer(item, h.source); action.changed = true
        ISTimedActionQueue.add(action)
    end)
    assert(#h.queue.queue == 1)
end)

test("missing manual hand reference leaves native restore group intact", function()
    local h = fixture()
    local manual, borrowed, original = h.item(), h.item(), h.item()
    ISInventoryPaneContextMenu.OnPrimaryWeapon({manual}, 0); h.drain()
    h.move(manual, h.source); h.player.primary = borrowed
    h.restore(function()
        ISTimedActionQueue.add(h.equip(original, true, false))
        ISTimedActionQueue.add(h.transfer(borrowed, h.source))
    end)
    assert(#h.queue.queue == 2)
    h.drain()
    assert(h.player.primary == original and borrowed:getContainer() == h.source)
end)

test("unresolvable baseline does not discard a native hand restore group", function()
    local h = fixture()
    local manual, borrowed, missing = h.item(), h.item(), h.item(h.source)
    ISInventoryPaneContextMenu.OnPrimaryWeapon({manual}, 0); h.drain()
    h.player.primary, h.player.secondary = manual, borrowed
    local nativeSecondary = h.equip(missing, false, false)
    h.restore(function() ISTimedActionQueue.add(nativeSecondary) end)
    assert(h.queue:indexOf(nativeSecondary) ~= -1, "partially rebuilt hands silently discarded unresolved native restore")
end)

test("paired floor relocation is suppressed with explicit pickup return", function()
    local h = fixture(true)
    local item = h.item(h.source)
    h.manualGrab(item)
    h.restore(function()
        ISTimedActionQueue.add(h.transfer(item, h.source))
        ISTimedActionQueue.add(P4RestoreFloorAction:new(h.player, item))
    end)
    assert(#h.queue.queue == 0)
end)

test("direct helper equipment is not explicit intent", function()
    local h = fixture()
    local item = h.item()
    ISTimedActionQueue.add(h.equip(item, true, false)); h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("animated hotbar attach retains item while passive refresh does not", function()
    for _, animated in ipairs({true, false}) do
        local h = fixture()
        local item = h.item()
        ISHotbar.attachItem({chr = h.player}, item, "Back", 1, {}, animated)
        h.drain()
        h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
        assert(#h.queue.queue == (animated and 0 or 1))
    end
end)

test("explicit worn item stays while borrowed clothing returns", function()
    local h = fixture()
    local manual, borrowed = h.item(), h.item()
    manual.location, borrowed.location = "Jacket", "Gloves"
    ISInventoryPaneContextMenu.onWearItems({manual}, 0); h.drain()
    h.restore(function()
        ISTimedActionQueue.add(h.transfer(manual, h.source))
        ISTimedActionQueue.add(h.transfer(borrowed, h.source))
    end)
    assert(#h.queue.queue == 1 and h.queue.queue[1].item == borrowed)
end)

test("B42 body location object is retained without string concatenation", function()
    local h = fixture()
    local item = h.item()
    item.location = setmetatable({}, {__tostring = function() return "Base.Jacket" end})
    ISInventoryPaneContextMenu.onWearItems({item}, 0); h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 0)
end)

test("nested explicit callbacks restore outer capture kind", function()
    local h = fixture()
    local manual, grabbed = h.item(), h.item(h.source)
    h.onUI = function(kind)
        if kind == "equip" then
            ISInventoryPaneContextMenu.onGrabItems({grabbed}, 0)
            ISTimedActionQueue.add(h.equip(manual, true, false))
        else ISTimedActionQueue.add(h.transfer(grabbed, h.inventory)) end
    end
    ISInventoryPaneContextMenu.OnPrimaryWeapon({manual}, 0); h.drain()
    h.restore(function()
        ISTimedActionQueue.add(h.transfer(manual, h.source))
        ISTimedActionQueue.add(h.transfer(grabbed, h.source))
    end)
    h.drain()
    assert(manual:getContainer() == h.inventory and grabbed:getContainer() == h.inventory)
end)

test("UI callback error releases capture scope", function()
    local h = fixture()
    local item = h.item(h.source)
    h.onUI = function() error("intent callback failure") end
    assert(not pcall(ISInventoryPaneContextMenu.onGrabItems, {item}, 0))
    ISTimedActionQueue.add(h.transfer(item, h.inventory)); h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("nested successful intent survives an outer callback error", function()
    local h = fixture()
    local grabbed, manual = h.item(h.source), h.item()
    h.instant = true
    h.onUI = function(kind)
        if kind == "equip" then
            ISInventoryPaneContextMenu.onGrabItems({grabbed}, 0)
            error("outer callback failure")
        end
        return ISTimedActionQueue.add(h.transfer(grabbed, h.inventory))
    end
    assert(not pcall(ISInventoryPaneContextMenu.OnPrimaryWeapon, {manual}, 0))
    h.instant = false
    h.restore(function() ISTimedActionQueue.add(h.transfer(grabbed, h.source)) end)
    assert(#h.queue.queue == 0)
end)

test("callback queued actions before error are not treated as explicit success", function()
    local h = fixture()
    local item = h.item(h.source)
    h.onUI = function()
        ISTimedActionQueue.add(h.transfer(item, h.inventory))
        error("callback failed after enqueue")
    end
    assert(not pcall(ISInventoryPaneContextMenu.onGrabItems, {item}, 0))
    h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("P4 callback error restores queue add wrapper", function()
    local h = fixture()
    local item = h.item(h.source)
    h.manualGrab(item); h.tick()
    local add = ISTimedActionQueue.add
    assert(not pcall(h.tick, function() error("P4 callback failure") end))
    assert(ISTimedActionQueue.add == add)
    ISTimedActionQueue.add(h.transfer(item, h.source))
    assert(#h.queue.queue == 1)
end)

test("cached explicit wrapper stops capture when owner callback changes", function()
    local h = fixture()
    local item = h.item(h.source)
    local cached = ISInventoryPaneContextMenu.onGrabItems
    ISInventoryPaneContextMenu.onGrabItems = function() end
    cached({item}, 0); h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1)
end)

test("approved late selection wrapper preserves explicit pickup after filtering", function()
    local h=fixture()
    local selected,filtered=h.item(h.source),h.item(h.source)
    local original=ISInventoryPaneContextMenu.onGrabItems
    ISInventoryPaneContextMenu.onGrabItems=function(items,player) return original({items[1]},player) end
    ISInventoryPaneContextMenu._ocStick_onGrabItems=ISInventoryPaneContextMenu.onGrabItems
    h.approvedWrapper=true
    ISInventoryPaneContextMenu.onGrabItems({selected,filtered},0);h.drain()
    h.move(filtered,h.inventory)
    h.restore(function()
        ISTimedActionQueue.add(h.transfer(selected,h.source))
        ISTimedActionQueue.add(h.transfer(filtered,h.source))
    end)
    assert(#h.queue.queue==1 and h.queue.queue[1].item==filtered)
end)

test("approved wrapper marker mismatch fails closed", function()
    local h=fixture()
    local item=h.item(h.source)
    local original=ISInventoryPaneContextMenu.onGrabItems
    ISInventoryPaneContextMenu.onGrabItems=function(...) return original(...) end
    ISInventoryPaneContextMenu._ocStick_onGrabItems=function() end
    h.approvedWrapper=true
    h.manualGrab(item)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item,h.source)) end)
    assert(#h.queue.queue==1)
end)

test("restore episode clears after two empty ticks", function()
    local h = fixture()
    local item = h.item(h.source)
    h.manualGrab(item)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 0)
    h.tick(); h.tick()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, "old intent suppressed a later borrowing episode")
end)

test("completed outgoing transfer ends pickup protection before a later borrow", function()
    local h = fixture()
    local item = h.item(h.source)
    h.manualGrab(item)
    ISTimedActionQueue.add(h.transfer(item, h.source)); h.drain()
    ISTimedActionQueue.add(h.transfer(item, h.inventory)); h.drain()
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, "old manual grab protected a subsequent borrowed pickup")
end)

test("new queue and main menu invalidate old intent", function()
    for _, menu in ipairs({true, false}) do
        local h = fixture()
        local item = h.item(h.source)
        h.manualGrab(item)
        if menu then for _, callback in ipairs(h.callbacks) do callback() end
        else
            local replacement = {queue = {}, character = h.player, indexOf = h.queue.indexOf}
            h.queue = replacement; ISTimedActionQueue.queues[h.player] = replacement
        end
        h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
        assert(#h.queue.queue == 1)
    end
end)

if NativeActionRoot then
    test('native small-item merge retains every explicit ID and returns borrowed neighbor',function()
        for _,client in ipairs({false,true}) do
            local h=fixture(client);h.nativeMerge()
            local borrowed,one,two=h.item(h.source),h.item(h.source),h.item(h.source)
            ISTimedActionQueue.add(h.transfer(borrowed,h.inventory))
            ISInventoryPaneContextMenu.onGrabItems({one,two},0)
            local executor,child=h.queue.queue[1],h.queue.queue[2]
            if client then executor:checkQueueList();h.tick() end
            h.performNative(executor)
            assert(child.character==nil and #h.queue.queue==0,'native merge did not wipe child')
            h.restore(function()
                for _,item in ipairs({borrowed,one,two}) do ISTimedActionQueue.add(h.transfer(item,h.source)) end
            end)
            assert(#h.queue.queue==1 and h.queue.queue[1].item==borrowed,'explicit merged IDs were not distinguished from borrow')
        end
    end)
    test('native heavy groups confirm only completed group across canceled executor',function()
        for _,client in ipairs({false,true}) do
            local h=fixture(client);h.nativeMerge()
            local one,two=h.item(h.source),h.item(h.source);one.weight,two.weight=1,1
            ISInventoryPaneContextMenu.onGrabItems({one,two},0)
            local executor=h.queue.queue[1]
            if client then executor:checkQueueList() end
            h.performNative(executor)
            assert(executor.item==two and two:getContainer()==h.source,'native next-group mutation absent')
            h.queue.queue={};h.player.nativeBusy=true;h.tick();h.player.nativeBusy=false;h.move(two,h.inventory)
            h.restore(function()
                ISTimedActionQueue.add(h.transfer(one,h.source));ISTimedActionQueue.add(h.transfer(two,h.source))
            end)
            assert(#h.queue.queue==1 and h.queue.queue[1].item==two,'future group gained success after cancellation')
        end
    end)
    test('native partial group protects only successful IDs',function()
        for _,client in ipairs({false,true}) do
            local h=fixture(client);h.nativeMerge()
            local one,two,three=h.item(h.source),h.item(h.source),h.item(h.source)
            ISInventoryPaneContextMenu.onGrabItems({one,two,three},0)
            local executor=h.queue.queue[1];executor.blocked={[two:getID()]=true}
            if client then executor:checkQueueList() end
            h.performNative(executor)
            -- MP transaction may reject individual items; neither rejection nor subsequent inventory state is a receipt.
            h.move(two,h.inventory)
            h.restore(function()
                for _,item in ipairs({one,two,three}) do if item:getContainer()==h.inventory then ISTimedActionQueue.add(h.transfer(item,h.source)) end end
            end)
            assert(#h.queue.queue==1 and h.queue.queue[1].item==two,'rejected item was protected')
        end
    end)
    test('MP end-of-perform merge cannot confirm the next group early',function()
        local h=fixture(true);h.nativeMerge()
        local one,two=h.item(h.source),h.item(h.source);one.weight,two.weight=1,1
        ISInventoryPaneContextMenu.onGrabItems({one},0)
        local executor=h.queue.queue[1];executor:checkQueueList()
        ISInventoryPaneContextMenu.onGrabItems({two},0)
        h.performNative(executor)
        assert(two:getContainer()==h.source and executor.item==two)
        h.queue.queue={};h.player.nativeBusy=true;h.tick();h.player.nativeBusy=false;h.move(two,h.inventory)
        h.restore(function()
            ISTimedActionQueue.add(h.transfer(one,h.source));ISTimedActionQueue.add(h.transfer(two,h.source))
        end)
        assert(#h.queue.queue==1 and h.queue.queue[1].item==two)
    end)
    test('canceled native child cannot attach to later transfer of same ID',function()
        local h=fixture(true);h.nativeMerge()
        local one,two=h.item(h.source),h.item(h.source)
        ISInventoryPaneContextMenu.onGrabItems({one,two},0)
        table.remove(h.queue.queue,2);h.tick()
        ISTimedActionQueue.add(h.transfer(two,h.inventory))
        local executor=h.queue.queue[1];executor:checkQueueList();h.performNative(executor)
        h.restore(function()
            ISTimedActionQueue.add(h.transfer(one,h.source));ISTimedActionQueue.add(h.transfer(two,h.source))
        end)
        assert(#h.queue.queue==1 and h.queue.queue[1].item==two)
    end)
    test('unknown automatic executor callbacks keep native P4 fallback',function()
        for _,client in ipairs({false,true}) do
            local h=fixture(client);h.nativeMerge()
            local borrowed,manual=h.item(h.source),h.item(h.source)
            local executor=h.transfer(borrowed,h.inventory);executor.onCancelFunc=function() end
            ISTimedActionQueue.add(executor);ISInventoryPaneContextMenu.onGrabItems({manual},0)
            if client then executor:checkQueueList() end
            h.performNative(executor)
            h.restore(function()
                ISTimedActionQueue.add(h.transfer(manual,h.source));ISTimedActionQueue.add(h.transfer(borrowed,h.source))
            end)
            assert(#h.queue.queue==2,'unknown executor acquired explicit restore privileges')
        end
    end)
    test('late callback mutation after MP merge invalidates every bound record',function()
        local h=fixture(true);h.nativeMerge()
        local one,two=h.item(h.source),h.item(h.source)
        ISInventoryPaneContextMenu.onGrabItems({one,two},0)
        local executor=h.queue.queue[1];executor:checkQueueList();executor.onCompleteFunc=function() end;executor.onCompleteArgs={}
        h.performNative(executor)
        h.restore(function()
            ISTimedActionQueue.add(h.transfer(one,h.source));ISTimedActionQueue.add(h.transfer(two,h.source))
        end)
        assert(#h.queue.queue==2,'late callback mutation retained stale merge rights')
    end)
    test('merged outgoing groups end protection for every transferred ID',function()
        local h=fixture();h.nativeMerge()
        local one,two=h.item(h.source),h.item(h.source)
        ISInventoryPaneContextMenu.onGrabItems({one,two},0);h.performNative(h.queue.queue[1])
        ISTimedActionQueue.add(h.transfer(one,h.source));ISTimedActionQueue.add(h.transfer(two,h.source))
        h.performNative(h.queue.queue[1])
        ISTimedActionQueue.add(h.transfer(one,h.inventory));ISTimedActionQueue.add(h.transfer(two,h.inventory))
        h.performNative(h.queue.queue[1])
        h.restore(function()
            ISTimedActionQueue.add(h.transfer(one,h.source));ISTimedActionQueue.add(h.transfer(two,h.source))
        end)
        assert(#h.queue.queue==2,'earlier explicit IDs protected later automatic borrow')
    end)
end

for _, failure in ipairs(failures) do print("FAIL tidy intent: " .. failure) end
assert(#failures == 0, tostring(#failures) .. " of " .. checked .. " tidy intent checks failed")
print("Tidy explicit intent checks passed (" .. checked .. ").")
