local root = ProjectRoot or "."
local failures, checked = {}, 0
local function test(name, callback)
    checked = checked + 1
    local ok, err = pcall(callback)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local function fixture(client)
    local h = {valid = true, nextID = 0, callbacks = {}, emitted = {}, now = 100}
    require = function() end
    isClient = function() return client == true end
    instanceof = function(value, kind) return kind == "InventoryItem" and type(value) == "table" and value.inventoryItem end
    getTimestampMs = function() return h.now end
    isItemTransactionDone = function() return true end
    isItemTransactionRejected = function() return false end
    Events = {OnMainMenuEnter = {Add = function(callback) h.callbacks[#h.callbacks + 1] = callback end},
        OnServerCommand = {Add = function(callback) h.receive = callback end}}
    PZSurvivorToolkit = {Settings = {actionQueue = function() return h.queueEnabled == true end}}
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
    function h.player:getPlayerNum() return 0 end
    function h.player:getOnlineID() return 101 end
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
    -- Load the real shared proof and ACK observer; only the native transport is modeled.
    local loaded = {}
    require = function(name)
        if name == 'PZSurvivorToolkit/ActionQueueAcknowledgements' or name == 'PZSurvivorToolkit/ActionQueueSettlement'
            or name == 'PZSurvivorToolkit/ActionQueueTidyIntent' or name == 'PZSurvivorToolkit/ActionQueueLifecycle' then
            if not loaded[name] then
                loaded[name] = assert(loadfile(root .. '/PZSurvivorToolkit/42/media/lua/client/' .. name .. '.lua'))()
            end
            return loaded[name]
        end
    end
    h.acks = require('PZSurvivorToolkit/ActionQueueAcknowledgements')
    h.settlement = require('PZSurvivorToolkit/ActionQueueSettlement')
    h.intent = require('PZSurvivorToolkit/ActionQueueTidyIntent')
    h.lifecycle = require('PZSurvivorToolkit/ActionQueueLifecycle')
    function h.receipt(action, state, token)
        h.receive('PZSurvivorToolkitActions', 'State', {protocol = 1, player = 101,
            transaction = action.toolkitNativeTransaction, kind = action.toolkitNativeKind,
            token = token or action.receiptToken, state = state})
    end
    function h.startReceipt(action, transaction, token)
        action.action = action.action or {}
        h.queue.current = action
        action.toolkitNativeTransaction, action.toolkitNativeKind = transaction or 7, 'fixture'
        action.receiptToken = token or '11111111-1111-4111-8111-111111111111'
        h.receipt(action, 'started')
    end
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
        function value:getIsCraftingConsumed() return false end
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
    function h.applyEffect(action)
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
    function h.complete(action, noEffect, succeeded)
        action.action = action.action or {}
        h.queue.current = action
        local phase = (client or getmetatable(action) == ISInventoryTransferAction) and "perform" or "complete"
        h.lifecycle.begin(action, phase)
        if not noEffect then h.applyEffect(action) end
        h.lifecycle.finish(action, phase, succeeded ~= false)
        local index = h.queue:indexOf(action)
        if index ~= -1 then table.remove(h.queue.queue, index) end
        if h.queue.current == action then h.queue.current = nil end
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
    function h.nativeMerge(onMerged)
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
        h.intent.observeTransfers(onMerged)
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
    test('native SP merge and Host group retain exact P4 return members through child wipe',function()
        for _,client in ipairs({false,true}) do
            for _,partial in ipairs({false,true}) do
                local h=fixture(client)
                h.queueEnabled=true
                h.source.isExistYet=function()return true end
                h.source.getItemById=function(self,id)return self.items[id]end
                local obligation
                h.nativeMerge(function(action) h.settlement.refreshReturn(action,obligation) end)
                local one,two=h.item(),h.item()
                local executor,child=h.transfer(one,h.source),h.transfer(two,h.source)
                ISTimedActionQueue.add(executor);ISTimedActionQueue.add(child)
                if partial then executor.blocked={[two:getID()]=true} end
                h.prepareNative(executor);h.queue.current=executor
                executor.transactionId=17
                if client then executor:checkQueueList() end
                local scope=h.settlement.deferred(h.player,{})
                obligation=h.settlement.obligation(h.settlement.context(scope))
                assert(h.settlement.beginReturn(executor,obligation,function()return h.valid end))
                if client then
                    h.move(one,h.source)
                    if not partial then h.move(two,h.source)end
                end
                h.lifecycle.begin(executor,'perform')
                executor:perform()
                h.lifecycle.finish(executor,'perform',true)
                assert(h.settlement.finishReturn(obligation,true))
                assert(child.character==nil and #h.queue.queue==0,'native merge must wipe the actual child')
                local items=h.settlement.returnItems(obligation)
                assert(#items==2 and items[1].id==one:getID() and items[2].id==two:getID(),
                    'SP must capture after native merge; Host must retain its pre-transaction group')
                assert(items[1].state=='completed' and items[2].state==(partial and 'waiting' or 'completed'))
                assert(h.settlement.returnState(obligation)==(partial and 'waiting' or 'completed'))
                if partial then
                    h.now=h.now+30001
                    items=h.settlement.returnItems(obligation)
                    assert(items[1].state=='completed' and items[2].state=='unavailable',
                        'failed sibling cannot erase or inherit the successful exact native transfer')
                end
            end
        end
    end)
    test('native merge observation can attach after installation without replacing its helper',function()
        local h=fixture();h.nativeMerge()
        local helper=ISInventoryTransferAction.checkQueueList
        local calls=0
        local observer=function(action)
            calls=calls+1
            assert(#action.queueList==1 and #action.queueList[1].items==2)
        end
        h.intent.observeTransfers(observer);h.intent.observeTransfers(observer)
        assert(ISInventoryTransferAction.checkQueueList==helper,'late observation must not replace pinned native helper')
        local one,two=h.item(),h.item()
        local executor=h.transfer(one,h.source)
        ISTimedActionQueue.add(executor);ISTimedActionQueue.add(h.transfer(two,h.source))
        h.performNative(executor)
        assert(calls==1,'duplicate subscription cannot duplicate observed outcomes')
    end)
    test('failed read-only merge observer cannot abort or replay native effects',function()
        local h=fixture();h.nativeMerge()
        local failed,healthy=0,0
        h.intent.observeTransfers(function()failed=failed+1;error('observer failure')end)
        h.intent.observeTransfers(function()healthy=healthy+1 end)
        for _=1,2 do
            local one,two=h.item(),h.item()
            local executor=h.transfer(one,h.source)
            ISTimedActionQueue.add(executor);ISTimedActionQueue.add(h.transfer(two,h.source))
            h.performNative(executor)
            assert(one:getContainer()==h.source and two:getContainer()==h.source and #h.queue.queue==0,
                'observer failure must preserve exact native transfers and advancement')
        end
        assert(failed==1 and healthy==2,'failed observer must stay quarantined without suppressing independent listeners')
    end)
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

for _, order in ipairs({'effect-first', 'receipt-first'}) do
    test('MP correlated explicit pickup waits both completion gates: ' .. order, function()
        local h = fixture(true)
        local item = h.item(h.source)
        ISInventoryPaneContextMenu.onGrabItems({item}, 0)
        local action = h.queue.queue[1]
        h.startReceipt(action)
        h.complete(action, order == 'receipt-first')
        if order == 'receipt-first' then h.receipt(action, 'completed') end
        local callbacks = 0
        h.restore(function() callbacks = callbacks + 1; ISTimedActionQueue.add(h.transfer(item, h.source)) end)
        assert(callbacks == 0 and #h.queue.queue == 0,
            'idle native restoration must wait while a correlated terminal or replication effect is pending')
        if order == 'receipt-first' then h.move(item, h.inventory) else h.receipt(action, 'completed') end
        h.restore(function() callbacks = callbacks + 1; ISTimedActionQueue.add(h.transfer(item, h.source)) end)
        assert(callbacks == 1 and #h.queue.queue == 0 and item:getContainer() == h.inventory,
            'finished pending intent must confirm after both authoritative gates, without replaying a transfer')
    end)
end

for _, terminal in ipairs({'canceled', 'rejected'}) do
    test('MP ' .. terminal .. ' pickup cannot become explicit intent from inventory state', function()
        local h = fixture(true)
        local item = h.item(h.source)
        ISInventoryPaneContextMenu.onGrabItems({item}, 0)
        local action = h.queue.queue[1]
        h.startReceipt(action); h.complete(action)
        h.receipt(action, terminal)
        h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
        assert(#h.queue.queue == 1 and h.queue.queue[1].item == item,
            'terminal failure must release native restoration even when an effect is visible')
        h.drain()
        assert(item:getContainer() == h.source, 'failed intent must not replay its earlier pickup')
    end)
end

test('MP duplicate completion cannot resurrect retired explicit pickup intent', function()
    local h = fixture(true)
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    local action = h.queue.queue[1]
    h.startReceipt(action); h.complete(action); h.receipt(action, 'completed'); h.tick()
    -- A genuine later native outgoing action retires the previous explicit pickup.
    ISTimedActionQueue.add(h.transfer(item, h.source)); h.drain()
    h.receipt(action, 'completed')
    h.move(item, h.inventory)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, 'duplicate completion restored an already retired pickup privilege')
end)

for _, mutation in ipairs({'guard', 'native', 'transaction', 'kind', 'generation', 'receipt-reset', 'ack-module'}) do
    test('MP pending explicit pickup fails closed after ' .. mutation .. ' change', function()
        local h = fixture(true)
        local item = h.item(h.source)
        ISInventoryPaneContextMenu.onGrabItems({item}, 0)
        local action = h.queue.queue[1]
        h.startReceipt(action); h.complete(action)
        if mutation == 'guard' then h.valid = false
        elseif mutation == 'native' then action.action = {}
        elseif mutation == 'transaction' then action.toolkitNativeTransaction = 8
        elseif mutation == 'kind' then action.toolkitNativeKind = 'other'
        elseif mutation == 'generation' then h.queue.toolkitOperationGeneration = 1
        elseif mutation == 'receipt-reset' then h.acks.reset(h.queue)
        else PZSurvivorToolkit.ActionQueueAcknowledgements = {capture = h.acks.capture, observe = h.acks.observe} end
        h.receipt(action, 'completed')
        h.now = h.now + 30001
        h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
        assert(#h.queue.queue == 1, 'changed ancestry acquired an explicit return exemption')
    end)
end

test('MP signed-byte receipt ID reuse cannot attach stale completion to a later intent', function()
    local h = fixture(true)
    local first, second = h.item(h.source), h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({first}, 0)
    local oldAction = h.queue.queue[1]
    h.startReceipt(oldAction, -7); h.complete(oldAction)
    h.acks.reset(h.queue)
    ISInventoryPaneContextMenu.onGrabItems({second}, 0)
    local newAction = h.queue.queue[1]
    h.startReceipt(newAction, -7, '22222222-2222-4222-8222-222222222222')
    h.complete(newAction)
    h.receipt(oldAction, 'completed')
    local callbacks = 0
    h.restore(function() callbacks = callbacks + 1 end)
    assert(callbacks == 0, 'old token completed the later pending intent with the same signed-byte ID')
    h.receipt(newAction, 'completed'); h.now = h.now + 30001
    h.restore(function()
        callbacks = callbacks + 1
        ISTimedActionQueue.add(h.transfer(first, h.source)); ISTimedActionQueue.add(h.transfer(second, h.source))
    end)
    assert(callbacks == 1 and #h.queue.queue == 1 and h.queue.queue[1].item == first,
        'queue reset must retire the old proof while the new exact receipt protects only its own item')
end)

test('MP explicit confirmed intent remains active with queue management disabled', function()
    local h = fixture(true)
    assert(not PZSurvivorToolkit.Settings.actionQueue())
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    local action = h.queue.queue[1]
    h.startReceipt(action); h.complete(action); h.receipt(action, 'completed')
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 0 and item:getContainer() == h.inventory,
        'the explicit P4 intent observer incorrectly depends on queue-edit settings')
end)

test('MP missing terminal receipt releases native restoration after bounded timeout', function()
    local h = fixture(true)
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    local action = h.queue.queue[1]
    h.startReceipt(action); h.complete(action)
    local callbacks = 0
    h.now = h.now + 29999
    h.restore(function() callbacks = callbacks + 1 end)
    assert(callbacks == 0, 'a still-correlated pending effect lost its bounded terminal wait')
    h.now = h.now + 2
    h.restore(function() callbacks = callbacks + 1; ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(callbacks == 1 and #h.queue.queue == 1,
        'missing terminal receipt held native restoration indefinitely or inferred completion')
    h.receipt(action, 'completed'); h.drain(); h.move(item, h.inventory)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, 'late timeout completion resurrected explicit intent')
end)

test('MP pending intent holds restoration only at an idle native boundary', function()
    local h = fixture(true)
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    local action = h.queue.queue[1]
    h.startReceipt(action); h.complete(action)
    h.player.nativeBusy = true
    local callbacks = 0
    h.tick(function() callbacks = callbacks + 1 end)
    assert(callbacks == 1, 'pending observation stalled the ordinary native update while actions were busy')
    h.player.nativeBusy = false
    h.restore(function() callbacks = callbacks + 1 end)
    assert(callbacks == 1, 'the native idle restoration boundary escaped the pending receipt hold')
end)

test('MP completed receipt without replicated effect times out without replay', function()
    local h = fixture(true)
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    local action = h.queue.queue[1]
    h.startReceipt(action); h.complete(action, true); h.receipt(action, 'completed')
    local callbacks = 0
    h.restore(function() callbacks = callbacks + 1 end)
    assert(callbacks == 0 and item:getContainer() == h.source,
        'receipt-only completion ran native restoration or replayed the missing pickup')
    h.now = h.now + 30001
    h.restore(function() callbacks = callbacks + 1 end)
    assert(callbacks == 1 and item:getContainer() == h.source,
        'missing replication must release after the bounded wait without executing an effect')
    h.move(item, h.inventory)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, 'a later unrelated transfer revived timed-out receipt-only intent')
end)

test('MP unmarked native callback cannot gain proof from an unrelated late pickup', function()
    local h = fixture(true)
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    h.complete(h.queue.queue[1], true)
    h.move(item, h.inventory)
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1, 'unmarked native no-effect callback acquired a correlated replication wait')
end)

test('MP pending explicit pickup expires when native outgoing transfer ends its borrowing episode', function()
    local h = fixture(true)
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    local original = h.queue.queue[1]
    h.startReceipt(original); h.complete(original)
    ISTimedActionQueue.add(h.transfer(item, h.source)); h.drain()
    ISTimedActionQueue.add(h.transfer(item, h.inventory)); h.drain()
    h.receipt(original, 'completed')
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1 and h.queue.queue[1].item == item,
        'late old receipt protected a later unrelated borrowing episode')
end)

test('MP observed pickup intent cannot revive after the item leaves root inventory', function()
    local h = fixture(true)
    local item = h.item(h.source)
    ISInventoryPaneContextMenu.onGrabItems({item}, 0)
    local original = h.queue.queue[1]
    h.startReceipt(original); h.complete(original)
    h.move(item, h.source); h.tick()
    h.move(item, h.inventory); h.receipt(original, 'completed')
    h.restore(function() ISTimedActionQueue.add(h.transfer(item, h.source)) end)
    assert(#h.queue.queue == 1 and h.queue.queue[1].item == item,
        'late completion revived an old intent after its observed item left root inventory')
end)

for _, failure in ipairs(failures) do print("FAIL tidy intent: " .. failure) end
assert(#failures == 0, tostring(#failures) .. " of " .. checked .. " tidy intent checks failed")
print("Tidy explicit intent checks passed (" .. checked .. ").")
