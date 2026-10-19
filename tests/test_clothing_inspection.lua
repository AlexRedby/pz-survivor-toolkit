if not NativeInventoryContextMenuSource or not NativeTransferSource then
    print('SKIP clothing inspection requires native sources (--game)')
    return
end
require = function() end
local client, now, queued, completed = false, 100, {}, 0
isClient = function() return client end
getTimestampMs = function() return now end
instanceof = function() return false end
removeItemTransaction = function() end
ISInventoryPage = {}
ISBaseTimedAction = {derive = function() return {} end,
    perform = function() completed = completed + 1 end}
assert(loadstring(NativeTransferSource))()
local storage, inventory = {}, {items = {}}
function inventory:getItemById(id) return self.items[id] end
local player = {getPlayerNum = function() return 0 end, getInventory = function() return inventory end,
    isDead = function(self) return self.dead end}
local currentPlayer = player
getSpecificPlayer = function(num) assert(num == 0); return currentPlayer end
local function garment(id, container, fullType)
    return {id = id, container = container, fullType = fullType or 'Base.Trousers_Denim',
        getID = function(self) return self.id end, getFullType = function(self) return self.fullType end,
        getContainer = function(self) return self.container end, setJobDelta = function() end,
        isInPlayerInventory = function(self) return self.container == inventory end}
end
local tick, reset
Events = {OnTick = {Add = function(fn) tick = fn end}, OnMainMenuEnter = {Add = function(fn) reset = fn end}}
local opened = 0
ISCollapsableWindow = {update = function() end}
ISGarmentUI = {windows = {}}
function ISGarmentUI:new(_, _, p, clothing)
    assert(p == player)
    opened = opened + 1
    return setmetatable({clothing = clothing, initialise = function() end,
        addToUIManager = function(self) self.visible = true end,
        close = function(self) self.visible = false end}, {__index = self})
end
assert(loadstring(assert(NativeGarmentSource:gsub('\r', ''):match('(function ISGarmentUI:update%(%).-\nend)'))))()
JoypadState = {players = {}}
luautils = {haveToBeTransfered = function(p, item) return item:getContainer() ~= p:getInventory() end}
ISTimedActionQueue = {add = function(action) queued[#queued + 1] = action end}
-- Preserve native callback registration and perform; replace only construction/engine services.
function ISInventoryTransferAction:new(p, item, src, dest)
    local action = setmetatable({character = p, item = item, srcContainer = src, destContainer = dest,
        queueList = {{items = {item}}}, action = {stopTimedActionAnim = function() end,
            setLoopedAction = function() end, setWaitForFinished = function() end},
        isValid = function(self) return not self.rejected end,
        transferItem = function(self, value) value.container = self.destContainer; inventory.items[value.id] = value end},
        {__index = self})
    for _, name in ipairs({'checkQueueList', 'playTransferCompleteSound', 'playSourceContainerCloseSound',
        'playDestContainerCloseSound', 'stopLoopingSound'}) do action[name] = function() end end
    return action
end
ISInventoryPaneContextMenu = {}
local contextSource = NativeInventoryContextMenuSource:gsub('\r', '')
local first = assert(contextSource:find('ISInventoryPaneContextMenu.onInspectClothing = function', 1, true))
local last = assert(contextSource:find('ISInventoryPaneContextMenu.doClothingPatchMenu = function', first, true))
assert(loadstring(contextSource:sub(first, last - 1)))()
local menu = ISInventoryPaneContextMenu
local function visible(item)
    local window = ISGarmentUI.windows[0]
    if window then window:update() end
    return window and window.visible and window.clothing == item
end
local function inspect(item)
    queued = {}; menu.onInspectClothing(player, item)
    return queued[1]
end
-- Reproduce the native Host failure before applying the fix: the arrived item has the same ID,
-- but the callback opens a window on the detached original, so native update closes it.
client = true
local original, received = garment(1, storage), garment(1, inventory)
inventory.items[1] = received
inspect(original):perform()
assert(not visible(received), 'native baseline must reproduce the stale-instance window closing')
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ClothingInspection.lua')
local count = opened
inspect(original):perform()
assert(opened == count + 1 and visible(received), 'Host inspection must use the delivered item')
-- Same-instance SP transfers and already-carried inspection retain the native window path.
client = false
local sp = garment(2, storage)
inspect(sp):perform(); assert(visible(sp))
assert(not inspect(sp) and visible(sp), 'carried items open immediately without transfer')
-- A failed SP transfer or a cancelled transfer cannot open a window.
local missing = garment(3, storage)
count = opened
local failed = inspect(missing); failed.rejected = true; failed:perform()
assert(opened == count)
client = true
local cancelled = inspect(missing)
tick(); assert(cancelled and opened == count, 'unperformed/cancelled actions never request a window')
-- Async cart/late network delivery: exact ID and type, once only, without a second transfer.
inspect(missing):perform(); tick(); assert(opened == count)
inventory.items[3] = garment(4, inventory); tick(); assert(opened == count)
inventory.items[3] = garment(3, inventory, 'Base.Shirt'); tick(); assert(opened == count)
received = garment(3, inventory); inventory.items[3] = received
tick(); tick(); assert(opened == count + 1 and visible(received) and #queued == 1)
-- A newer request wins, including direct inventory inspection.
local old = garment(5, storage)
inspect(old):perform(); inspect(sp)
count = opened; inventory.items[5] = garment(5, inventory); tick(); assert(opened == count and visible(sp))
local newer = garment(6, storage)
inventory.items[5] = nil; inspect(old):perform(); inspect(newer):perform()
count = opened; inventory.items[5] = garment(5, inventory); tick(); assert(opened == count)
inventory.items[6] = garment(6, inventory); tick(); assert(opened == count + 1 and visible(inventory.items[6]))
-- Pending requests release ownership on timeout, death, player replacement or leaving the game.
for _, reason in ipairs({'timeout', 'death', 'replacement', 'menu'}) do
    inventory.items[5] = nil; inspect(old):perform(); count = opened
    if reason == 'timeout' then now = now + 30000
    elseif reason == 'death' then player.dead = true
    elseif reason == 'replacement' then currentPlayer = {}
    else reset() end
    tick(); player.dead = nil; currentPlayer = player
    inventory.items[5] = garment(5, inventory); tick(); assert(opened == count, reason)
end
player.dead = true; inspect(sp); assert(opened == count, 'dead players cannot open inspection')
assert(completed > 0, 'native transfer completion must remain active')
print('PASS native storage inspection: Host stale instance, SP/carried, delayed receipt, identity, failure/cancel and request cleanup')
