require = function() return PZSurvivorToolkit and PZSurvivorToolkit.ItemRetention end
next = nil -- Native Kahlua does not provide next.

local function list(values)
    return {size=function() return #values end, get=function(_, index) return values[index + 1] end}
end
local body = [[
craftRecipe RefillBlowTorch
    {
        timedAction = Welding,
        time = 50,
        OnCreate = RecipeCodeOnCreate.refillBlowTorch,
        Tags = InHandCraft;Welding,
        category = Metalworking,
        inputs
        {
            item 1 [Base.BlowTorch] mode:destroy flags[NotFull;ItemCount],
            item 1 [Base.PropaneTank] flags[NotEmpty;ItemCount] mode:keep,
        }
        outputs
        {
            item 1 Base.BlowTorch,
        }
    }
]]
if NativeActionRoot then
    local file = assert(io.open(NativeActionRoot .. "/../scripts/generated/recipes/recipes_metalWelding.txt"))
    local source = file:read("*a"); file:close()
    local nativeBody = source:match("craftRecipe%s+RefillBlowTorch%s*(%b{})")
    assert(nativeBody, "native RefillBlowTorch recipe must exist")
    local actual = "craftRecipe RefillBlowTorch" .. nativeBody
    assert(actual:gsub("%s+", "") == body:gsub("%s+", ""), "fixture matches exact native recipe body")
    body = actual
end

local client, server = false, false
getTimestampMs = function() return 0 end
local callbacks, serverCallbacks, originalCalls = {}, {}, 0
local function event(storage)
    storage = storage or {}
    return {Add=function(callback) storage[#storage + 1] = callback end}
end
Events = {OnGameStart=event(), OnServerCommand=event(serverCallbacks), OnTick=event(callbacks)}
isClient, isServer = function() return client end, function() return server end
instanceof = function(value, kind)
    return value and (value.class == kind or (kind == "InventoryItem" and value.class == "DrainableComboItem"))
end
local sent = {}
sendServerCommand = function(character, module, command, args)
    if type(character) == "string" then
        sent[#sent + 1] = {character=nil, module=character, command=module, args=command}
    else
        sent[#sent + 1] = {character=character, module=module, command=command, args=args}
    end
end
local character = {class="IsoPlayer", getOnlineID=function() return 27 end}
local function item(id, kind, marked)
    local data = {}
    if marked == "legacy" then data.ocStuck = true elseif marked then data.pzstRetained = true end
    local value = {class="DrainableComboItem", data=data, transmitted=0, container=nil}
    function value:getID() return id end
    function value:getFullType() return kind end
    function value:hasModData() return next and next(data) ~= nil or data.pzstRetained ~= nil or data.ocStuck ~= nil end
    function value:getModData() return data end
    function value:getContainer() return self.container end
    return value
end
local source, output, tank = item(11, "Base.BlowTorch", true), item(22, "Base.BlowTorch"), item(33, "Base.PropaneTank")
local recipe = {bodies={"pz-vanilla", body}}
function recipe:getScriptObjectFullType() return "Base.RefillBlowTorch" end
function recipe:getLoadedScriptBodies() return list(self.bodies) end
local data = {recipe=recipe, consumed={source}, created={output}, kept={tank}}
function data:getRecipe() return self.recipe end
function data:getAllConsumedItems() return list(self.consumed) end
function data:getAllCreatedItems() return list(self.created) end
function data:getAllKeepInputItems() return list(self.kept) end
local original = function(actual, actor)
    assert(actual == data and actor == character)
    originalCalls = originalCalls + 1
    return "native", nil, 9
end
RecipeCodeOnCreate = {refillBlowTorch=original}
getClassSimpleName = function(callback) return callback == original and "LuaJavaInvoker" or "LuaClosure" end
local playerContainer = {items={}, getItemById=function(self, id) return self.items[id] end}
function playerContainer:add(value) self.items[value:getID()] = value; value.container = self end
function playerContainer:remove(value) self.items[value:getID()] = nil; value.container = nil end
function playerContainer:getItems() return list({}) end
local vehicleContainer = {items={}}
function vehicleContainer:getItems() return list({}) end
local player = {class="IsoPlayer", container=playerContainer, traits={}, isDead=function() return false end,
    getInventory=function(self) return self.container end, hasTrait=function(self, trait) return self.traits[trait] == true end}
getSpecificPlayer = function(playerNum) assert(playerNum == 0); return player end
local queue = {queue={}}
function queue:indexOf(action) for i, value in ipairs(self.queue) do if value == action then return i end end; return -1 end
local function latestWait()
    for index = #queue.queue, 1, -1 do
        local action = queue.queue[index]
        if action.Type == "ISQueueActionsAction" then return action end
    end
end
ISTimedActionQueue = {queues={[player]=queue}}
function ISTimedActionQueue.getTimedActionQueue(actor) return ISTimedActionQueue.queues[actor] end
function ISTimedActionQueue.add(action) queue.queue[#queue.queue + 1] = action; return action end
local heldAction
ISInventoryPaneContextMenu = {OnNewCraft=function(selected, selectedRecipe, playerNum)
    local action = heldAction or {Type="ISHandcraftAction", character=player, craftRecipe=selectedRecipe,
        manualInputs={[1]=list({selected})}}
    heldAction = nil
    ISTimedActionQueue.add(action)
    return "queued"
end}
CharacterTrait = {DISORGANIZED="DISORGANIZED"}
ISInventoryTransferUtil = {newInventoryTransferAction=function(actor, value, from, to)
    local transfer = {item=value, srcContainer=from, destContainer=to, setAllowMissingItems=function(self, allow) self.allowMissingItems=allow end}
    return transfer
end}
local transfers = {}
ISTimedActionQueue.add = function(action)
    if action.srcContainer then transfers[#transfers + 1] = action end
    queue.queue[#queue.queue + 1] = action
    return action
end
require = function(module)
    if module == "PZSurvivorToolkit/ItemRetention" then return PZSurvivorToolkit.ItemRetention end
    if module == "PZSurvivorToolkit/ActionQueueOperations" then return PZSurvivorToolkit.ActionQueueOperations end
    return true
end
PZSurvivorToolkit = {ItemRetention={FIELD="pzstRetained", MODULE="PZSurvivorToolkitRetention",
    locate=function(value) return {id=value:getID(), inv=true} end,
    isRetained=function(value) return value:getModData().pzstRetained == true or value:getModData().ocStuck == true end,
    apply=function(value, retainedValue)
        value:getModData().pzstRetained = retainedValue and true or nil
        value:getModData().ocStuck = nil
    end}, ActionQueueOperations={
        run=function(callback, ...) return callback(...) end,
        adopt=function(action, token) action.toolkitQueueOperation = token; action.adopted = true end,
        invalidateTitle=function() end,
        command=function(actor, callback, snapshot, options)
            local command = {Type="ISQueueActionsAction", character=actor, callback=callback, snapshot=snapshot,
                options=options, ready=options.ready}
            function command:perform() return self.callback(self.character, self.snapshot) end
            return command
        end,
    }}

local sharedPath = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/TorchRefill.lua"
local retentionApi = PZSurvivorToolkit.ItemRetention
local api = assert(loadfile(sharedPath))()
local wrapped = RecipeCodeOnCreate.refillBlowTorch
assert(api.supports(recipe), "only exact native refill recipe is supported")
local a, b, c = wrapped(data, character)
assert(a == "native" and b == nil and c == 9 and originalCalls == 1, "observer preserves native return tuple")
assert(output.data.pzstRetained == true and output.data.ocStuck == nil, "legacy/retained mark is copied and migrated")

source = item(41, "Base.BlowTorch", "legacy")
output = item(42, "Base.BlowTorch")
output.container = playerContainer
data.consumed, data.created = {source}, {output}
server = true
syncItemModData = function(actor, value)
    assert(actor == character and value == output)
    value.transmitted = value.transmitted + 1
end
wrapped(data, character)
assert(output.data.pzstRetained == true and output.data.ocStuck == nil and output.transmitted == 1,
    "server copies retained state and syncs the new output")
assert(#sent == 2 and sent[1].module == retentionApi.MODULE and sent[1].command == "State"
    and sent[1].args.owner == 27 and sent[1].args.retained == true and sent[1].args.items[1].id == 42
    and sent[2].module == api.MODULE and sent[2].command == "Refilled"
    and sent[2].character == character and sent[2].args.onlineID == 27
    and sent[2].args.sourceID == 41 and sent[2].args.outputID == 42,
    "server sends correlated receipt only after authoritative retention sync")
source, output = item(51, "Base.BlowTorch"), item(52, "Base.BlowTorch")
data.consumed, data.created = {source}, {output}
wrapped(data, character)
assert(output.data.pzstRetained == nil and output.data.ocStuck == nil and output.transmitted == 0,
    "unmarked source leaves output unmarked")
local before = #sent
local function reject(change, restore)
    change(); wrapped(data, character); restore()
    assert(#sent == before, "invalid recipe transaction emits no receipt")
end
reject(function() data.recipe = {getScriptObjectFullType=function() return "Base.Other" end} end,
    function() data.recipe = recipe end)
reject(function() data.consumed = {source, source} end, function() data.consumed = {source} end)
reject(function() data.created = {source} end, function() data.created = {output} end)
reject(function() data.kept = {} end, function() data.kept = {tank} end)
reject(function() data.kept = {item(60, "Base.OtherTank")} end, function() data.kept = {tank} end)
reject(function() data.created = {item(61, "Base.PropaneTank")} end, function() data.created = {output} end)
reject(function() recipe.bodies[2] = body:gsub("time = 50", "time = 51") end,
    function() recipe.bodies[2] = body end)
reject(function() recipe.bodies[1] = "other-mod" end, function() recipe.bodies[1] = "pz-vanilla" end)
reject(function() character.class = "IsoGameCharacter" end, function() character.class = "IsoPlayer" end)
local ownedObserver = RecipeCodeOnCreate.refillBlowTorch
RecipeCodeOnCreate.refillBlowTorch = function(...) return ownedObserver(...) end
assert(not api.supports(recipe), "replacement of the native callback disables recipe ownership")
RecipeCodeOnCreate.refillBlowTorch = ownedObserver
local sentBeforeWrongClass = #sent
data.created = {output}; source = item(71, "Base.BlowTorch", true); data.consumed = {source}
character.class = "IsoGameCharacter"; wrapped(data, character); character.class = "IsoPlayer"
assert(#sent == sentBeforeWrongClass, "non-player callback owner is rejected")
server = false
client = true

local originalRequire = require
local operations = PZSurvivorToolkit.ActionQueueOperations
local shared = PZSurvivorToolkit.ItemRetention
assert(NativeActionRoot, "pass --game to load the native return helper")
assert(loadfile(NativeActionRoot .. "/client/ISUI/ISCraftingUI.lua"))()
require = function(module)
    if module == "PZSurvivorToolkit/TorchRefill" then return api end
    if module == "PZSurvivorToolkit/ActionQueueOperations" then return operations end
    return true
end
local root = "client/PZSurvivorToolkit/TorchRefillReturn.lua"
local nativeCraftCalls = 0
PZSurvivorToolkit.ActionQueue = {updateOperationState=function(actual)
    assert(actual == queue)
    queue.stateInitialized = true
end}
ISInventoryPaneContextMenu.OnNewCraft = function(selected, selectedRecipe)
    if selected:getContainer() == vehicleContainer then
        assert(queue.stateInitialized, "operation bookkeeping is initialized before native pickups begin")
    end
    nativeCraftCalls = nativeCraftCalls + 1
    local action = heldAction or {Type="ISHandcraftAction", character=player, craftRecipe=selectedRecipe,
        manualInputs={[1]=list({selected})}}
    heldAction = nil
    ISTimedActionQueue.add(action)
    return "queued"
end
-- Install against a native producer, then validate actual input identity before a wait is created.
local returnApi = assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/" .. root))()
assert(returnApi.install())
local wrongInput = item(72, "Base.BlowTorch")
heldAction = {Type="ISHandcraftAction", character=player, craftRecipe=recipe,
    manualInputs={[1]=list({wrongInput})}}
local initial = #queue.queue
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
assert(#queue.queue == initial + 1, "a different consumed torch does not get a return wait")

source = item(81, "Base.BlowTorch", true); source.container = vehicleContainer
queue.stateInitialized = nil
initial = #queue.queue
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
local wait = latestWait()
assert(wait and wait.options.ready, "supported selected vehicle torch gets a receipt wait")
local waitEntry = wait.snapshot
api.onRefilled(player, {sourceID=999, outputID=900})
assert(not waitEntry.outputID, "unrelated source receipt cannot select an output")
output = item(82, "Base.BlowTorch"); playerContainer:add(output)
player.getPlayerNum = function() return 0 end
getPlayerByOnlineID = function(id) if id == 27 then return player end end
assert(#serverCallbacks == 1, "one owned receipt handler is installed")
serverCallbacks[1](api.MODULE, "Refilled", {onlineID=28, sourceID=81, outputID=82})
assert(not waitEntry.outputID, "another actor cannot bind the local result")
serverCallbacks[1](api.MODULE, "Refilled", {sourceID=81, outputID=82})
assert(not waitEntry.outputID, "missing actor is rejected")
serverCallbacks[1](api.MODULE, "Refilled", {onlineID=27, sourceID=81, outputID=82})
assert(waitEntry.outputID == 82, "matching source receipt binds exact output ID")
assert(wait.options.ready(player, waitEntry), "wait becomes ready after exact output replicates")
wait:perform()
assert(#transfers == 1 and transfers[1].item == output and transfers[1].srcContainer == playerContainer
    and transfers[1].destContainer == vehicleContainer and transfers[1].allowMissingItems,
    "return uses native helper for the exact output and original source container")

-- A receipt arriving before the output replica waits; the timeout then safely skips return.
source = item(91, "Base.BlowTorch"); source.container = vehicleContainer
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
local lateWait = latestWait()
assert(lateWait)
api.onRefilled(player, {sourceID=91, outputID=92})
local lateEntry = lateWait.snapshot
getTimestampMs = function() return 100 end
assert(not lateWait.options.ready(player, lateEntry), "missing replica stays pending before deadline")
getTimestampMs = function() return 30101 end
assert(lateWait.options.ready(player, lateEntry), "late replication releases wait after bounded timeout")
lateWait:perform()
assert(#transfers == 1, "timed out replica is never returned by a stale ID")

-- Queue reset/cancel and wrong receipts do not return unrelated items.
source = item(101, "Base.BlowTorch"); source.container = vehicleContainer
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
local cancelled = latestWait()
assert(cancelled)
cancelled.toolkitQueueOperation = {toolkitCancelled=true}
api.onRefilled(player, {sourceID=101, outputID=102})
output = item(102, "Base.BlowTorch"); playerContainer:add(output)
assert(cancelled.options.ready(player, cancelled.snapshot), "cancelled pending wait releases")
cancelled:perform()
assert(#transfers == 1, "cancelled operation does not return its output")

source = item(106, "Base.BlowTorch"); source.container = vehicleContainer
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
local resetWait = latestWait()
local resetIndex = queue:indexOf(resetWait)
assert(resetIndex ~= -1)
table.remove(queue.queue, resetIndex)
for _, callback in ipairs(callbacks) do callback() end
api.onRefilled(player, {sourceID=106, outputID=107})
output = item(107, "Base.BlowTorch"); playerContainer:add(output)
resetWait:perform()
assert(#transfers == 1, "queue reset retires pending receipt and cannot return a stale output")

source = item(111, "Base.BlowTorch"); source.container = vehicleContainer
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
local wrongReceiptWait = latestWait()
api.onRefilled(player, {sourceID=222, outputID=223})
getTimestampMs = function() return 100000 end
assert(not wrongReceiptWait.options.ready(player, wrongReceiptWait.snapshot), "wrong receipt cannot release a wait early")
getTimestampMs = function() return 130000 end
assert(wrongReceiptWait.options.ready(player, wrongReceiptWait.snapshot))
wrongReceiptWait:perform()
assert(#transfers == 1, "wrong receipt never returns an unrelated torch")

-- Root-held sources and Disorganized players remain on the stock path.
playerContainer:add(source)
local beforeQueue, beforeTransfers = #queue.queue, #transfers
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
assert(#queue.queue == beforeQueue + 1, "root-held selected torch remains native without return command")
player.traits[CharacterTrait.DISORGANIZED] = true
source.container = vehicleContainer
beforeQueue = #queue.queue
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
assert(#queue.queue == beforeQueue + 1, "Disorganized player keeps native craft flow")
player.traits[CharacterTrait.DISORGANIZED] = nil
assert(nativeCraftCalls >= 6, "native OnNewCraft remains the crafting entry point")

-- Replacing the old consumed-item return keeps Host from invalidating the
-- operation before it can return either the output or the surviving tank.
local wrappedProducer = ISInventoryPaneContextMenu.OnNewCraft
local nativeProducer = function(selected, selectedRecipe)
    local action = {Type="ISHandcraftAction", character=player, craftRecipe=selectedRecipe,
        manualInputs={[1]=list({selected})}, toolkitQueueOperation={}}
    ISTimedActionQueue.add(action)
    local stale = {Type="ISInventoryTransferAction", character=player, item=selected,
        srcContainer=playerContainer, destContainer=vehicleContainer, allowMissingItems=true,
        queueList={{items={selected}}}, toolkitQueueOperation=action.toolkitQueueOperation}
    ISTimedActionQueue.add(stale)
    local tankReturn = {Type="ISInventoryTransferAction", character=player, item=tank,
        srcContainer=playerContainer, destContainer=vehicleContainer, allowMissingItems=true,
        queueList={{items={tank}}}, toolkitQueueOperation=action.toolkitQueueOperation}
    ISTimedActionQueue.add(tankReturn)
    return stale, tankReturn
end
ISInventoryPaneContextMenu.OnNewCraft = nativeProducer
local replacing = assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/" .. root))()
assert(replacing.install())
source = item(119, "Base.BlowTorch", true); source.container = vehicleContainer
local priorCount = #queue.queue
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
assert(#queue.queue == priorCount + 3, "the obsolete return is replaced one-for-one, without a duplicate tail")
local replacement, tankReturn = queue.queue[priorCount + 2], queue.queue[priorCount + 3]
assert(replacement.Type == "ISQueueActionsAction" and replacement.adopted and tankReturn.item == tank,
    "the replacement occupies the old torch return slot and preserves the tank return")
assert(replacement.toolkitQueueOperation == tankReturn.toolkitQueueOperation,
    "native cleanup retains one operation")
output = item(120, "Base.BlowTorch"); playerContainer:add(output)
api.onRefilled(player, {sourceID=119, outputID=120})
replacement:perform()
assert(transfers[#transfers].item == output and transfers[#transfers].destContainer == vehicleContainer,
    "the destroyed input is never transferred; only the authoritative replacement returns")
ISInventoryPaneContextMenu.OnNewCraft = wrappedProducer

-- A queued recipe that actually consumed a different matching torch fails closed.
source = item(121, "Base.BlowTorch"); source.container = vehicleContainer
heldAction = {Type="ISHandcraftAction", character=player, craftRecipe=recipe,
    manualInputs={[1]=list({wrongInput})}}
local countBeforeMismatch = #queue.queue
ISInventoryPaneContextMenu.OnNewCraft(source, recipe, 0, false)
assert(#queue.queue == countBeforeMismatch + 1, "actual selected-input mismatch gets no receipt wait")

require = originalRequire
PZSurvivorToolkit.ItemRetention = shared
print("Torch refill checks passed: native callback, exact recipe and identities, authority, receipt wait and safe return.")
