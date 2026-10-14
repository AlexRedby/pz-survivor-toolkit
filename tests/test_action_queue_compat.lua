if not NativeActionRoot or not NativeWishlistWorkshopRoot then
    print('Selected chain source checks skipped (pass native action and Workshop roots).')
    return
end
local function read(path)
    if NativeReadText then local source = NativeReadText(path):gsub('\r', ''); return source end
    local file = assert(io.open(path)); local source = file:read('*a'); file:close()
    source = source:gsub('\r', ''); return source
end
local function list(values)
    return {class = 'List', size = function() return #values end, get = function(_, i) return values[i + 1] end,
        contains=function(_, value) for _, candidate in ipairs(values) do if candidate==value then return true end end return false end}
end
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
require = function() end
ISBaseObject = {derive = derive}
ISPanel = {derive = derive}
ISTableLayout = {derive = derive}
UIFont = {Small = 'small', Medium = 'medium'}
getTextManager = function() return {getFontHeight = function() return 12 end} end
local events = {}
Events = setmetatable({}, {__index = function(self, name)
    local event = {Add = function(callback) events[name] = events[name] or {}; table.insert(events[name], callback) end,
        Remove = function() end}
    rawset(self, name, event); return event
end})
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do _G[name] = {instance = function() return {} end} end
instanceof = function(value, kind)
    return type(value) == 'table' and (value.class == kind or (kind == 'InventoryItem' and value.item == true))
end
table.wipe = function(value) for key in pairs(value) do value[key] = nil end end
getText = function(value) return value end
getTextOrNull = getText
getTexture=function() return {} end
isClient = function() return false end
isServer = function() return false end
isMultiplayer = function() return false end
getTimestampMs = function() return 100 end
getGameVersion = function() return '42.21' end
SandboxVars = {}
ArrayList = {new = function() return list({}) end}
Perks = {Cooking = 'cooking'}
ISLogSystem = {logAction = function() end}
DebugType = {Action = {warn = function() end}}
luautils = {getCorrectSquareForWall=function(_, square) return square end,
    haveToBeTransfered = function(character, item) return item:getContainer() ~= character:getInventory() end}
assert(loadstring(read(NativeActionRoot .. '/shared/TimedActions/ISBaseTimedAction.lua')))()
assert(loadstring(read(NativeActionRoot .. '/client/TimedActions/ISTimedActionQueue.lua')))()
assert(loadstring(read(NativeActionRoot .. '/client/TimedActions/ISQueueActionsAction.lua')))()
local walkSource=read(NativeActionRoot .. '/shared/luautils.lua')
assert(loadstring(assert(walkSource:match('(function luautils.walkAdj%(playerObj, square, keepActions, excludeList%).-\nend)'))))()
local nativeWalk=luautils.walkAdj
local nativeClears=0
ISTimedActionQueue.clear=function(character)
    nativeClears=nativeClears+1
    local queue=ISTimedActionQueue.getTimedActionQueue(character); queue.queue,queue.current={},nil
end
ISBaseTimedAction.begin = function(self)
    self.action = {forceComplete = function() end, isStarted = function() return true end,
        finished = function() return false end, isForceComplete = function() return false end}
end
local function nativeClass(name)
    local class = ISBaseTimedAction:derive(name)
    class.isValid = function() return true end
    class.new = function(self, character, item)
        local action = ISBaseTimedAction.new(self, character); action.item = item; return action
    end
    class.complete = function() return true end
    _G[name] = class; return class
end
for _, name in ipairs({'ISInventoryTransferAction','ISWashClothing','ISEquipWeaponAction','ISUnequipAction',
    'ISWearClothing','ISClothingExtraAction','ISAttachItemHotbar','ISDetachItemHotbar','ISAddItemInRecipe','ISHandcraftAction','ISDumpContentsAction'}) do nativeClass(name) end
nativeClass('ISReadABook')
local nativeReadAnimEvent=function(self) self.fixtureReadEvents=(self.fixtureReadEvents or 0)+1 end
ISReadABook.animEvent=nativeReadAnimEvent
ISInventoryTransferAction.new = function(self, character, item, source, destination)
    local action = ISBaseTimedAction.new(self, character)
    action.item, action.srcContainer, action.destContainer = item, source, destination; return action
end
ISInventoryTransferAction.setAllowMissingItems = function(self, value) self.allowMissingItems = value end
ISInventoryTransferAction.setOnComplete = function(self, callback, ...)
    self.onCompleteFunc, self.onCompleteArgs = callback, {...}
end
ISInventoryTransferAction.canMergeAction = function() return false end
ISInventoryTransferAction.getNotFullFloorSquare = function() end
local nativeFloorHelper=ISInventoryTransferAction.getNotFullFloorSquare
local transferHelperAdopted=false
ISInventoryTransferAction.perform = function(self)
    if self.fixtureRebound then self.item=self.fixtureRebound end
    if not self.fixtureDelay then self.item.container = self.destContainer end
    if self.onCompleteFunc then self.onCompleteFunc(unpack(self.onCompleteArgs)) end
    ISBaseTimedAction.perform(self)
end
local consumed = 0
ISAddItemInRecipe.new = function(self, character, recipe, base, ingredient)
    local action = ISBaseTimedAction.new(self, character)
    action.recipe, action.baseItem, action.usedItem = recipe, base, ingredient; return action
end
ISAddItemInRecipe.complete = function(self) consumed = consumed + 1; return true end
local evolvedSource=read(NativeActionRoot .. '/shared/TimedActions/ISAddItemInRecipe.lua')
assert(loadstring(assert(evolvedSource:match('(function ISAddItemInRecipe:isValidStart%(%).-\nend)'))))()
ISWashClothing.new = function(self, character, sink, item, blood, dirt, noSoap)
    local action = ISBaseTimedAction.new(self, character)
    action.sink, action.item, action.noSoap, action.soaps = sink, item, noSoap, character:getInventory():getSoapList(); return action
end
ISWashClothing.complete = function() consumed = consumed + 1; return true end
ISWashClothing.GetRequiredWater = function() return 1 end
ISWashClothing.GetRequiredSoap = function() return 0 end
ISTransferAction = {GetDropItemOffset = function() end, transferItem = function() end}
ISInventoryTransferUtil = {newInventoryTransferAction = function(character, item, src, dst) return ISInventoryTransferAction:new(character, item, src, dst) end}
ISInventoryPaneContextMenu = {getContainers = function() return list({}) end,
    transferIfNeeded = function(character, item)
        if item:getContainer() ~= character:getInventory() then ISTimedActionQueue.add(ISInventoryTransferAction:new(character,item,item:getContainer(),character:getInventory())) end
    end}
local menu = {options = {}}
ISContextMenu = {addOption = function(self, name, target, callback, ...)
    local option = {name = name, target = target, callback = callback, args = {...}}
    self.options[#self.options + 1] = option; return option
end}
setmetatable(menu, {__index = ISContextMenu})
ISButton, ISInventoryPane = {}, {}
ISWorldObjectContextMenu = {}
PZAPI = {ModOptions = {create = function()
    return {addTickBox = function() return {value = false} end, addComboBox = function() return {addItem = function() end} end}
end}}
local enabled, dead = true, false
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'))()
local operations, definitions = PZSurvivorToolkit.ActionQueueOperations, PZSurvivorToolkit.ActionQueueDefinitions
local paths = {
    WashFix = '3460812542/mods/WashingMenusImproved/42.15',
    NeatUI_Equipment = '3790656296/mods/NeatUI_Equipment/42.20',
    P4TidyUpMeister = '2769706949/mods/P4TidyUpMeister/42.20',
    Project_Cook = '3490188370/mods/Project_Cook/common',
    Neat_Crafting = '3502080466/mods/Neat_Crafting/common',
    MPFastForward = '3738738086/mods/MPFastForward/42',
    EURY_CONTAINERS = '3586216562/mods/BetterContainers/42.20',
}
ISInventoryPage={onBackpackRightMouseDown=function() end}
local containerGuards={}
PZSurvivorToolkit.ActionQueuePolicy={adoptReadAnimEvent=function(previous,replacement)
    return previous==nativeReadAnimEvent and ISReadABook.animEvent==replacement
end, adoptTransferFloorHelper=function(previous,replacement)
    transferHelperAdopted=previous==nativeFloorHelper and ISInventoryTransferAction.getNotFullFloorSquare==replacement
    return transferHelperAdopted
end, adoptTransferMethods=function(previous,replacement,guard)
    for _,name in ipairs({'isValid','start','perform','stop'}) do
        assert(type(previous[name])=='function' and ISInventoryTransferAction[name]==replacement[name])
    end
    assert(guard()); containerGuards[#containerGuards+1]=guard; return true
end, isOrdinaryTransfer=function(action)
    for _,guard in ipairs(containerGuards) do if not guard() then return false end end
    for _,container in ipairs({action.srcContainer,action.destContainer}) do
        if not instanceof(container,'ItemContainer') then return false end
        local kind=container:getType()
        if kind=='floor' or kind=='proximityInv' or kind=='twistInv_corpses' then return false end
        local owner=container:getContainingItem()
        if owner and (not instanceof(owner,'InventoryContainer') or owner:getContainer()~=action.character:getInventory()) then return false end
    end
    return true
end}
MPFastForward={isConflictModActive=function() return false end}
getActivatedMods = function() return {contains = function(_, id) return paths[id] ~= nil end} end
getModFileReader = function(id, path)
    local source = read(NativeWishlistWorkshopRoot .. '/' .. paths[id] .. '/' .. path)
    local cursor = 1
    return {close = function() end, readLine = function()
        if cursor > #source then return end
        local boundary = source:find('\n', cursor, true) or #source + 1
        local line = source:sub(cursor, boundary - 1); cursor = boundary + 1; return line
    end}
end
local Outfit = {
    skipsHotbar = function() return true end, isOutfitLocation = function() return true end,
    isHotbarLocation = function() return false end, locationKey = function(value) return value end,
    itemLocationKey = function() return 'Torso' end, isBag = function() return false end,
    location = function(value) return value end,
    providesAttachments = function() return false end,
}
local Gather = {build = function() return {} end, find = function(_, descriptor) return descriptor.item, 'container', descriptor.item:getContainer() end}
local loaded = {}
require = function(module)
    if loaded[module] then return loaded[module] end
    if module == 'NeatEquipment/NEQ_Outfit' then return Outfit end
    if module == 'NeatEquipment/NEQ_Gather' then return Gather end
    if module == 'NeatEquipment/NEQ_Categories' then return {SLOTS = {}} end
    if module == 'NeatEquipment/NEQ_State' then return {wardrobeSwapContainers = false} end
    if module == 'Project_Cook/PJCK_Config' then PJCK_Config = {get = function() return {portionPolicy = 'full_first'} end}; return end
    if module=='BetterContainers/Helpers' then return {} end
    if module=='BetterContainers/_Options' then return {} end
    if module=='BetterContainers/_IO/IniWriter' then return {makeFeature=function() return {get=function() return {} end} end} end
    local id, branch
    if module:match('^NeatEquipment/') then id, branch = 'NeatUI_Equipment', 'client/'
    elseif module:match('^Neat_Crafting/NC_CraftActionPanel') then id, branch = 'Neat_Crafting', 'client/'
    elseif module:match('^Project_Cook/HandCraftPanel/PJCK_CraftActionPanel') or module:match('^Project_Cook/EvolvedRecipePanel/') then id, branch = 'Project_Cook', 'client/'
    elseif module == 'Project_Cook/PJCK_FrozenCooking' or module == 'Project_Cook/PJCK_EvolvedSpiceGuard' then id, branch = 'Project_Cook', 'shared/'
    elseif module:match('^ISUI/WMI_') and module ~= 'ISUI/WMI_Compat_TABAS' then id, branch = 'WashFix', 'client/'
    elseif module == 'TimedActions/WMI_PatchWashClothing' then id, branch = 'WashFix', 'shared/'
    elseif module == 'P4TidyUpMeister' then id, branch = 'P4TidyUpMeister', 'client/'
    elseif module == 'MPFastForward_ReadFix' then id, branch = 'MPFastForward', 'server/'
    elseif module:match('^BetterContainers/') then id,branch='EURY_CONTAINERS','client/'
    elseif module:match('^TimedActions/P4Restore') then id, branch = 'P4TidyUpMeister', 'shared/' end
    if not id then return end
    local source = read(NativeWishlistWorkshopRoot .. '/' .. paths[id] .. '/media/lua/' .. branch .. module .. '.lua')
    -- Fixture exports expose private state only; the executed action/callback bodies remain upstream.
    if module == 'ISUI/WMI_WashingSubmenus' then
        source = source .. '\nWS.WMI_BuildWashMenu = function(menu, items, character, sink) return menu:addOption("Wash", character, onWashClothing3, sink, {}, items, nil, true) end\n'
    elseif module == 'P4TidyUpMeister' then source = source .. '\nTidyFixture = P4TidyUpMeister\n' end
    local result = assert(loadstring(source, module))()
    loaded[module] = result or true; return result
end
local compat = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'))()
assert(not compat.isInstalled('MPFastForward'),'server wrapper waits for the server loading boundary')
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/server/000_PZSurvivorToolkitReadCompat.lua'))()
assert(WS and NEQ_Dresser and TidyFixture and PJCK_EvoPanel and NC_CraftActionPanel and PJCK_CraftActionPanel)
assert(transferHelperAdopted,'verified Tidy load hands the exact native wrapper pointers to Policy')
for id in pairs(paths) do assert(compat.isInstalled(id), 'source-pinned adapter installed: ' .. id) end
local readFixture={}; ISReadABook.animEvent(readFixture,'ReadAPage',nil)
assert(readFixture.fixtureReadEvents==1,'pinned MPFF animEvent delegates native SP reading once')
local inventory = {class = 'ItemContainer', values = {}}
inventory.getItems = function(self) return list(self.values) end
inventory.getSoapList = function() return list({}) end
inventory.contains = function(self, item) return item.container == self end
inventory.getItemById = function(self, id) for _, item in ipairs(self.values) do if item.id == id and item.container == self then return item end end end
inventory.getParent = function() end
inventory.getType = function() return 'inventory' end
inventory.getContainingItem=function() end
local square = {getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
    canReachTo=function() return true end}
local player = {class = 'IsoPlayer', getInventory = function() return inventory end, getPlayerNum = function() return 0 end,
    isDead = function() return dead end, isAsleep = function() return false end, isLocalPlayer = function() return true end,
    isDraggingCorpse = function() return false end, isFarming = function() return false end, getSquare = function() return square end,
    hasTimedActions = function() return false end, getModData = function() return {P4TidyUpMeister = {doNotReequip = true}} end,
    getWornItems = function() return list({}) end, getPrimaryHandItem = function(self) return self.primary end,
    getSecondaryHandItem = function() end, isEquipped = function() return false end, setIsFarming = function() end,
    isTimedActionInstant = function() return false end, hasTrait = function() return false end}
player.getPerkLevel=function() return 0 end
player.getX=function() return 0 end; player.getY=function() return 0 end
getSpecificPlayer = function() return player end
getGameVersion = function() return '42.21' end
local sink = {class = 'IsoObject', getSquare = function() return square end, getObjectIndex = function() return 1 end}
local queue = ISTimedActionQueue.getTimedActionQueue(player)
local completed = queue.onCompleted
queue.onCompleted = function(self, action) if not operations.deferCompletion(self, action) then return completed(self, action) end end
local function tickTidy() for _, callback in ipairs(events.OnPlayerUpdate or {}) do callback(player) end end
local function reset()
    queue.queue, queue.current = {}, nil
    tickTidy(); tickTidy()
    TidyFixture.sessions[player], TidyFixture.restoring[player] = nil, nil
    inventory.values = {}; enabled, dead = true, false
end
local function item(container, id)
    return {item = true, id = id, container = container, getContainer = function(self) return self.container end,
        getID = function(self) return self.id end, getFullType = function() return 'Base.Test' end,
        getType = function() return 'Test' end, getBloodLevel = function() return 1 end, getDirtiness = function() return 1 end,
        getItemAfterCleaning = function() end, canBeActivated = function() return false end, isActivated = function() return false end,
        getName = function() return 'test' end, isHidden = function() return false end}
end
local function tail()
    local action = ISBaseTimedAction:new(player); ISTimedActionQueue.add(action); return action
end
local function wash(value)
    menu.options = {}; WS.WMI_BuildWashMenu(menu, {value}, player, sink)
    local option = menu.options[1]; option.callback(option.target, unpack(option.args))
    return queue.queue[1]
end
reset()
local front=tail(); local frontClears=nativeClears
local frontBag={class='ItemContainer',getParent=function() end,getType=function() return 'none' end,getContainingItem=function() end}
wash(item(frontBag,21)); local waitingWash=queue.queue[2]; local back=tail()
assert(queue.queue[1]==front and waitingWash.Type=='ISInventoryTransferAction' and nativeClears==frontClears,
    'real native walkAdj preserves existing front work in the verified Wash source scope')
operations.invalidate(waitingWash.toolkitQueueOperation); table.remove(queue.queue,2)
assert(queue.queue[1]==front and queue.queue[2]==back,'waiting Wash cancellation preserves both unrelated ends')
assert(luautils.walkAdj==nativeWalk,'Wash entry restores native walking after success')
local oldReach=square.canReachTo; square.canReachTo=function() error('native walking failure') end
assert(not pcall(function() wash(item(frontBag,22)) end)); square.canReachTo=oldReach
assert(luautils.walkAdj==nativeWalk,'Wash entry restores native walking after a source exception')
reset(); local actorParent={class='IsoGameCharacter'}; local oldParent=inventory.getParent
inventory.getParent=function() return actorParent end
wash(item(frontBag,23)); local ownedTransfer=queue.queue[1]
assert(not definitions.inspect(ownedTransfer).targets[actorParent],'player inventory parent is not a shared world device')
inventory.getParent=oldParent
local foreignWalkCalls=0; luautils.walkAdj=function() foreignWalkCalls=foreignWalkCalls+1 end
assert(not definitions.inspect(ownedTransfer),'replaced walking helper closes existing source permissions')
reset(); wash(item(frontBag,24))
assert(not definitions.inspect(queue.queue[1]) and foreignWalkCalls==1,'replaced walking helper cannot grant new source permissions')
luautils.walkAdj=nativeWalk
reset(); enabled=false; front=tail(); frontClears=nativeClears; wash(item(frontBag,25))
assert(queue.queue[1]~=front and nativeClears==frontClears+1 and luautils.walkAdj==nativeWalk,
    'initially disabled Wash entry retains native walking and restores no temporary hooks')
reset()
local bag = {class = 'ItemContainer', getParent = function() end, getType=function() return 'none' end, getContainingItem=function() end}
local dirty = item(bag, 1)
local transfer = wash(dirty); local unrelated = tail()
assert(definitions.inspect(transfer), 'verified Wash callback owns its transfer')
transfer:perform()
assert(queue.queue[1].Type == 'ISWashClothing' and queue.queue[2].Type == 'ISInventoryTransferAction' and queue.queue[3] == unrelated)
local washed = queue.queue[1]
assert(washed.toolkitQueueOperation == transfer.toolkitQueueOperation and definitions.inspect(washed))
local soaps=washed.soaps; local unknownCalls=0
washed.soaps={size=function() unknownCalls=unknownCalls+1; return 0 end}
assert(not definitions.inspect(washed) and unknownCalls==0,'replaced non-native soap selector cannot execute during inspection')
washed.soaps=soaps
washed:perform(); washed:complete()
assert(consumed == 1 and queue.queue[2] == unrelated, 'perform does not replace or duplicate native completion')
queue.queue[1]:perform(); assert(dirty.container == bag and queue.queue[1] == unrelated)
transfer.onCompleteFunc(unpack(transfer.onCompleteArgs)); assert(#queue.queue == 1, 'late repeated transfer callback is one-shot')
reset(); dirty=item(bag,16); transfer=wash(dirty); unrelated=tail()
local rebound=item(bag,16); transfer.fixtureRebound=rebound; inventory.values={rebound}; transfer:perform()
assert(queue.queue[1].Type=='ISWashClothing' and queue.queue[1].item==rebound and queue.queue[3]==unrelated,
    'native transfer rebinding the same ID/type retains its audited callback and return chain')
reset(); dirty=item(bag,17); transfer=wash(dirty); unrelated=tail()
transfer.fixtureRebound=item(bag,18); transfer:perform()
assert(queue.queue[1]==unrelated and #queue.queue==1,'a changed item ID cannot borrow a source continuation')
reset(); dirty=item(bag,19); transfer=wash(dirty); unrelated=tail()
rebound=item(bag,19); rebound.getFullType=function() return 'Base.Foreign' end; transfer.fixtureRebound=rebound; transfer:perform()
assert(queue.queue[1]==unrelated,'a changed native item type cannot borrow a source continuation')
for _, state in ipairs({'cancel', 'clear', 'disabled', 'dead', 'lost-sink'}) do
    reset(); dirty = item(bag, 2); transfer = wash(dirty); unrelated = tail()
    if state == 'cancel' then operations.invalidate(transfer.toolkitQueueOperation)
    elseif state == 'clear' then operations.invalidateQueue(queue)
    elseif state == 'disabled' then enabled = false
    elseif state == 'dead' then dead = true
    else sink.getObjectIndex = function() return -1 end end
    transfer:perform()
    assert(queue.queue[1] == unrelated and #queue.queue == 1 and consumed == 1, state .. ' must suppress only the late chain')
    sink.getObjectIndex = function() return 1 end
end
reset(); dirty = item(bag, 3); transfer = wash(dirty); transfer.fixtureDelay = true; unrelated = tail()
transfer:perform()
local wait = queue.queue[1]
assert(wait.Type == 'WMI_WaitForInvUpdate' and definitions.inspect(wait) and queue.queue[2] == unrelated)
wait:perform(); assert(queue.queue[1].Type == 'WMI_WaitForInvUpdate', 'MP retry executes its real callback instead of stalling')
dirty.container = inventory; inventory.values = {dirty}
queue.queue[1]:perform(); assert(queue.queue[1].Type == 'ISWashClothing' and queue.queue[3] == unrelated)
reset(); enabled=false; dirty=item(bag,20); transfer=wash(dirty); transfer.fixtureDelay=true; unrelated=tail()
assert(not definitions.inspect(transfer),'initially disabled operations retain native callbacks')
transfer:perform(); assert(queue.queue[1].Type=='WMI_WaitForInvUpdate')
dirty.container=inventory; inventory.values={dirty}; queue.queue[1]:perform()
assert(queue.queue[1].Type=='ISWashClothing' and queue.queue[3]==unrelated,'native disabled washing still retries and queues its return before tail')
reset(); dirty = item(bag, 4); transfer = wash(dirty); transfer.fixtureDelay = true; unrelated = tail(); transfer:perform()
wait = queue.queue[1]; operations.invalidate(wait.toolkitQueueOperation); wait:perform()
assert(queue.queue[1] == unrelated, 'cancelled wait cannot schedule another retry')
reset(); dirty = item(bag, 5); transfer = wash(dirty)
transfer.onCompleteFunc = function() end; assert(not definitions.inspect(transfer), 'replaced callback fails closed')
reset(); dirty = item(bag, 6); transfer = wash(dirty)
transfer.getNotFullFloorSquare = function() end; assert(not definitions.inspect(transfer), 'replaced instance helper fails closed')
reset(); dirty=item(bag,15); transfer=wash(dirty)
transfer.queueList={{items={{getID=function() unknownCalls=unknownCalls+1; return 999 end}}}}
assert(not definitions.inspect(transfer) and unknownCalls==0,'malformed merged inventory entries cannot execute getters')
reset(); dirty = item(inventory, 7); inventory.values = {dirty}
NEQ_Dresser.restore(player, {{item = dirty, key = 'Torso'}})
assert(queue.queue[1].Type == 'ISWearClothing' and definitions.inspect(queue.queue[1]))
reset(); dirty = item(bag, 8)
assert(NEQ_Dresser.wear(player, 0, {worn = {Torso = {item = dirty}}}))
local dress = queue.queue[2]; unrelated = tail(); assert(definitions.inspect(dress).deferred)
queue.queue[1]:perform(); assert(queue.queue[1] == dress)
assert(dress:waitToStart() and not dress:waitToStart()); dress:start()
assert(queue.queue[2].Type == 'ISWearClothing' and queue.queue[3] == unrelated, 'real wardrobe expansion stays before unrelated tail')
reset(); dirty = item(bag, 9); NEQ_Dresser.wear(player,0,{worn={Torso={item=dirty}}}); dress=queue.queue[2]; unrelated=tail()
operations.invalidate(dress.toolkitQueueOperation); dress:begin(); dress:start(); assert(#queue.queue == 3 and queue.queue[3] == unrelated)
reset(); dirty = item(inventory, 10); inventory.values = {dirty}
local original = tail(); local token = original.toolkitQueueOperation
player.primary = dirty
local session = TidyFixture.captureSession(player); session.armed,session.restoreHands=true,true
TidyFixture.sessions[player] = session; player.primary = nil
original:perform(); tickTidy(); tickTidy()
assert(queue.queue[1].Type == 'ISEquipWeaponAction' and queue.queue[1].toolkitQueueOperation == token and definitions.inspect(queue.queue[1]), 'real late Tidy restores retain one task owner')
reset(); dirty=item(inventory,11); inventory.values={dirty}; original=tail(); token=original.toolkitQueueOperation
player.primary=dirty; session=TidyFixture.captureSession(player); session.armed,session.restoreHands=true,true
TidyFixture.sessions[player]=session; player.primary=nil; operations.invalidate(token); original:perform(); tickTidy(); tickTidy()
assert(#queue.queue==0 and TidyFixture.sessions[player]==nil, 'cancel suppresses future restores while native Tidy session cleanup runs')
local owner = setmetatable({}, PJCK_CraftActionPanel)
local callbackAction = {onStartFunc=owner.onHandcraftActionStart,onCompleteFunc=owner.onHandcraftActionComplete,onCancelFunc=owner.onHandcraftActionCancelled}
assert(compat.isCraftOwner('PJCK_CraftActionPanel',owner,callbackAction))
owner.startHandcraft=function() end; assert(not compat.isCraftOwner('PJCK_CraftActionPanel',owner,callbackAction),'unknown owner instance helpers fail closed')
reset()
local panel = setmetatable({player=player,baseItem=item(inventory,12),preCookItems={},inputGroupCache={Ingredient={}}},PJCK_EvoPanel)
local recipe = {getMaxItems=function() return 6 end}
panel.inputGroupCache.Ingredient.none={usableItems={}}
panel:addIngredients({{groupKey='none',panelType='Ingredient',recipeCompatible=true}},recipe,panel.baseItem)
local command=queue.queue[1]; unrelated=tail(); assert(definitions.inspect(command).deferred)
command:start(); assert(queue.queue[2].Type=='PJCK_SequenceWaitAction' and queue.queue[3]==unrelated and definitions.inspect(queue.queue[2]))
command:perform(); queue.queue[1]:perform(); assert(queue.queue[1]==unrelated, 'missing ingredient yields without clearing unrelated work')
reset(); panel:addIngredients({{groupKey='none',panelType='Ingredient',recipeCompatible=true}},recipe,panel.baseItem)
command=queue.queue[1]; unrelated=tail(); operations.invalidate(command.toolkitQueueOperation); command:start()
assert(#queue.queue==2 and queue.queue[2]==unrelated,'canceled Project Cook command cannot append a wait')
command:perform(); assert(queue.queue[1]==unrelated,'empty canceled source expansion completes without clearing its independent tail')
reset()
local food = item(bag, 13); food.class='Food'
for _, name in ipairs({'isRotten','isBurnt','isFrozen','isCooked','isSpice','IsDrainable','isNoRecipes'}) do food[name]=function() return false end end
food.isFresh=function() return true end
food.getHungerChange=function() return -0.4 end
food.getHungChange=food.getHungerChange
food.getActualWeight=function() return 1 end
food.getScriptItem=function() return {getHungerChange=function() return 40 end,getActualWeight=function() return 1 end} end
recipe.getItemRecipe=function() return {getUse=function() return 5 end} end
recipe.getResultItem=function() return 'Test' end
recipe.getItemsCanBeUse=function() return list({food}) end
local group=panel:getItemGroupKey(food)
panel.inputGroupCache.Ingredient[group]={usableItems={food}}
local function cook()
    panel:addIngredients({{groupKey=group,panelType='Ingredient',recipeCompatible=true,recipeUse=5}},recipe,panel.baseItem)
    local first=queue.queue[1]; local book=tail(); first:start()
    assert(queue.queue[2].Type=='ISInventoryTransferAction' and queue.queue[3].Type=='ISQueueActionsAction' and queue.queue[4]==book)
    first:perform(); return queue.queue[1],book,first
end
local pickup,book,first=cook()
pickup:perform(); command=queue.queue[1]; command:start()
local addRecipe=queue.queue[2]
assert(addRecipe.Type=='ISAddItemInRecipe' and definitions.inspect(addRecipe).items[food.id]
    and definitions.inspect(addRecipe).items[panel.baseItem.id], 'expanded native evolved action declares both inputs')
assert(addRecipe:isValidStart(),'source expansion satisfies the actual native evolved recipe start validation')
assert(definitions.inspect(addRecipe).cancelOperation==false and definitions.inspect(queue.queue[3]).cancelOperation==false,
    'apply plus its authoritative post-use cleanup is one protected phase')
local count=#queue.queue; command:start(); assert(#queue.queue==count,'a duplicate source command cannot consume again')
command:perform(); addRecipe:perform(); addRecipe:complete()
command=queue.queue[1]; assert(command.Type=='ISQueueActionsAction'); command:start(); command:perform()
assert(queue.queue[1].Type=='ISInventoryTransferAction' and queue.queue[2]==book)
queue.queue[1]:perform(); assert(food.container==bag and consumed==2 and queue.queue[1]==book,'successful real ingredient sequence returns leftovers and consumes once')
reset(); food.container=bag; pickup,book=cook(); pickup.fixtureDelay=true; pickup:perform()
command=queue.queue[1]; command:start(); command:perform()
assert(queue.queue[1].Type=='PJCK_SequenceWaitAction' and queue.queue[2].Type=='ISQueueActionsAction' and queue.queue[3]==book,'delayed ingredient transfer uses source wait/retry before tail')
wait=queue.queue[1]; operations.invalidate(wait.toolkitQueueOperation); wait:perform(); command=queue.queue[1]; command:start(); command:perform()
assert(queue.queue[1]==book and consumed==2,'cancelled delayed ingredient retry cannot consume or return future items')
reset(); food.container=inventory; inventory.values={food}; panel.baseItemOriginalContainer=bag; panel.baseItem=food
panel:returnBaseItemToOriginalContainer(); transfer=queue.queue[1]; unrelated=tail()
assert(definitions.inspect(transfer),'remembered base return callback has source ownership')
operations.invalidate(transfer.toolkitQueueOperation); transfer:perform()
assert(queue.queue[1]==unrelated and food.container==bag and consumed==2,'completed native return survives cancellation without late source effects')
local hooks={table.insert,ISTimedActionQueue.add,ISTimedActionQueue.addAfter,ISTimedActionQueue.queueActions,ISContextMenu.addOption}
local old=NEQ_Dresser.resolve; NEQ_Dresser.resolve=function() error('changed producer') end
assert(not pcall(function() NEQ_Dresser.wear(player,0,{}) end)); NEQ_Dresser.resolve=old
for i,value in ipairs({table.insert,ISTimedActionQueue.add,ISTimedActionQueue.addAfter,ISTimedActionQueue.queueActions,ISContextMenu.addOption}) do assert(value==hooks[i],'source hooks restore on error') end
reset(); dirty=item(inventory,14); inventory.values={dirty}; player.primary=dirty
session=TidyFixture.captureSession(player); session.armed,session.restoreHands=true,true; TidyFixture.sessions[player]=session
local firstTail,secondTail=tail(),tail(); player.primary=nil; firstTail:perform(); secondTail:perform(); tickTidy(); tickTidy()
assert(#queue.queue>0 and not definitions.inspect(queue.queue[1]),'a Tidy session with several task owners stays opaque')
-- A changed source and an unknown preloaded owner cannot obtain a private baseline.
local oldOperations,oldDefinitions,oldCompat=PZSurvivorToolkit.ActionQueueOperations,PZSurvivorToolkit.ActionQueueDefinitions,PZSurvivorToolkit.ActionQueueCompat
local oldAdd,oldMods,oldReader,oldClass=ISTimedActionQueue.add,getActivatedMods,getModFileReader,NC_CraftActionPanel
PZSurvivorToolkit.ActionQueueOperations={registerProducer=function() end}
PZSurvivorToolkit.ActionQueueDefinitions={registerBehavior=function() end}
getActivatedMods=function() return {contains=function(_,id) return id=='Neat_Crafting' end} end
getModFileReader=function(id,path,...)
    local reader=oldReader(id,path,...); local readLine=reader.readLine; local first=true
    reader.readLine=function(...) local line=readLine(...); if first then first=false; return line..' -- changed' end; return line end
    return reader
end
NC_CraftActionPanel=nil
local refused=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'))()
assert(not refused.isInstalled('Neat_Crafting') and NC_CraftActionPanel==nil,'unknown source version stays native')
getModFileReader=oldReader; NC_CraftActionPanel=oldClass
refused=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'))()
assert(not refused.isInstalled('Neat_Crafting'),'preloaded owner is never adopted by first capture')
PZSurvivorToolkit.ActionQueueOperations,PZSurvivorToolkit.ActionQueueDefinitions,PZSurvivorToolkit.ActionQueueCompat=oldOperations,oldDefinitions,oldCompat
ISTimedActionQueue.add,getActivatedMods,getModFileReader=oldAdd,oldMods,oldReader
print('Selected mod chain actual-source checks passed.')
