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
        contains=function(_, value) for _, candidate in ipairs(values) do if candidate==value then return true end end return false end,
        isEmpty=function()return #values==0 end}
end
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
local craftContainers
require = function(name)
    if name == 'PZSurvivorToolkit/SourceProof' then return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/' .. name .. '.lua') end
    if name == 'PZSurvivorToolkit/ActionQueueSettlement' then
        return PZSurvivorToolkit.ActionQueueSettlement or dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueSettlement.lua')
    end
    if name == "PZSurvivorToolkit/ActionQueueMembership" then
        return assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua"))()
    end
    if name == 'PZSurvivorToolkit/InventoryClasses' then
        return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. name .. '.lua')
    end
end
-- This fixture isolates other integrations; the owned Manifest handoff has its own suite.
LootSorter = {}
ISBaseObject = {derive = derive}
ISPanel = {derive = derive}
ISUIElement = {derive = derive}
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
    return type(value) == 'table' and (value.class == kind or (kind == 'IsoGameCharacter' and value.class == 'IsoPlayer') or (kind == 'Clothing' and value.class == 'AlarmClockClothing') or (kind == 'InventoryItem' and value.item == true))
end
getClassSimpleName=function(value)return value.class end
ComponentType={Attributes={},Script={}}
table.wipe = function(value) for key in pairs(value) do value[key] = nil end end
getText = function(value) return value end
getTextOrNull = getText
getTexture=function() return {} end
isDebugEnabled=function() return false end
LuaEventManager={AddEvent=function() end}
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
assert(loadstring(read(NativeActionRoot .. '/client/ISUI/ISXuiSkin.lua')))()
getFilenameOfClosure=function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
assert(loadstring(read(NativeActionRoot .. '/shared/TimedActions/ISBaseTimedAction.lua'),'@media/lua/shared/TimedActions/ISBaseTimedAction.lua'))()
assert(loadstring(read(NativeActionRoot .. '/client/TimedActions/ISTimedActionQueue.lua'),'@media/lua/client/TimedActions/ISTimedActionQueue.lua'))()
assert(loadstring(read(NativeActionRoot .. '/client/TimedActions/ISQueueActionsAction.lua'),'@media/lua/client/TimedActions/ISQueueActionsAction.lua'))()
local walkSource=read(NativeActionRoot .. '/shared/luautils.lua')
assert(loadstring(assert(walkSource:match('(function luautils.walkAdj%(playerObj, square, keepActions, excludeList%).-\nend)')),'@media/lua/shared/luautils.lua'))()
assert(loadstring(assert(walkSource:match('(luautils.getCorrectSquareForWall = function%(playerObj, square%).-\nend)')),'@media/lua/shared/luautils.lua'))()
local nativeWalk=luautils.walkAdj
local nativeClears=0
local nativeClear=ISTimedActionQueue.clear
ISTimedActionQueue.clear=function(character)
    nativeClears=nativeClears+1
    return nativeClear(character)
end
ISBaseTimedAction.begin = function(self)
    self.action = {forceComplete = function() end, isStarted = function() return true end,
        finished = function() return false end, isForceComplete = function() return false end, getJobDelta = function() return 0 end,
        stopTimedActionAnim=function()end,setLoopedAction=function()end}
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
local nativeTransferPath=NativeActionRoot..'/client/TimedActions/ISInventoryTransferAction.lua'
local nativeTransferSource=read(nativeTransferPath)
assert(loadstring(assert(nativeTransferSource:match('(function ISInventoryTransferAction:canMergeAction.-)\n%-%- This is to support returning')),
    '@'..nativeTransferPath))()
local groupedNativePerform=assert(loadstring(assert(nativeTransferSource:match('(function ISInventoryTransferAction:perform%(%).-\nend)'))
    :gsub('function ISInventoryTransferAction:perform%(%)','return function(self)',1),'@'..nativeTransferPath))()
ISInventoryTransferAction.transferItem=function(self,value) value.container=self.destContainer end
for _,name in ipairs({'playTransferCompleteSound','playSourceContainerCloseSound','playDestContainerCloseSound','stopLoopingSound'})do
    ISInventoryTransferAction[name]=function()end
end
ISInventoryTransferAction.stop = function(self) return ISBaseTimedAction.stop(self) end
ISInventoryTransferAction.getNotFullFloorSquare = function() end
local nativeFloorHelper=ISInventoryTransferAction.getNotFullFloorSquare
local transferHelperAdopted=false
ISInventoryTransferAction.perform = function(self)
    if self.fixtureNativeGroup then return groupedNativePerform(self) end
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
local nativeTransferItem=ISTransferAction.transferItem
local nativeDropItemOffset=ISTransferAction.GetDropItemOffset
local transferItemGuard,adoptedTransferItem
ISInventoryTransferUtil = {newInventoryTransferAction = function(character, item, src, dst) return ISInventoryTransferAction:new(character, item, src, dst) end}
ISInventoryPaneContextMenu = {getContainers = function() return list({}) end,
    transferIfNeeded = function(character, item)
        if item:getContainer() ~= character:getInventory() then ISTimedActionQueue.add(ISInventoryTransferAction:new(character,item,item:getContainer(),character:getInventory())) end
    end}
-- UI producers use native queue APIs; their engine effects are applied below.
ISInventoryPaneContextMenu.onGrabItems=function(items,playerNum)
    local player=getSpecificPlayer(playerNum)
    for _,item in ipairs(items) do ISInventoryPaneContextMenu.transferIfNeeded(player,item) end
end
ISEquipWeaponAction.new=function(self,player,item,time,primary,twoHands)
    local action=ISBaseTimedAction.new(self,player)
    action.item,action.primary,action.twoHands=item,primary,twoHands
    return action
end
ISEquipWeaponAction.complete=function(action)
    if action.twoHands then action.character.primary,action.character.secondary=action.item,action.item
    elseif action.primary then action.character.primary=action.item
    else action.character.secondary=action.item end
    return true
end
local unequipSource=read(NativeActionRoot..'/shared/TimedActions/ISUnequipAction.lua')
assert(loadstring(unequipSource,'@media/lua/shared/TimedActions/ISUnequipAction.lua'))()
ISWearClothing.isStopOnWalk=function()return false end
getPlayerHotbar=function()return nil end
ItemTag={WEARABLE='wearable',REPLACE_PRIMARY='replace-primary',FLASHLIGHT='flashlight'}
ItemBodyLocation=setmetatable({},{__index=function(owner,key)rawset(owner,key,key);return key end})
local wearSource=read(NativeActionRoot..'/shared/TimedActions/ISWearClothing.lua')
assert(loadstring(wearSource,'@media/lua/shared/TimedActions/ISWearClothing.lua'))()
getGameFilesInput=function(path)
    local source=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
    local cursor=1
    return {close=function()end,readLine=function()
        if cursor>#source then return end
        local boundary=source:find('\n',cursor,true)or #source+1
        local line=source:sub(cursor,boundary-1);cursor=boundary+1;return line
    end}
end
triggerEvent=function()end
sendEquip=function(character)character.equipSyncs=(character.equipSyncs or 0)+1 end
isForceDropHeavyItem=function(value)return value.fixtureHeavy or false end
ISInventoryPaneContextMenu.equipWeapon=function(item,primary,twoHands,playerNum)
    local player=getSpecificPlayer(playerNum)
    ISInventoryPaneContextMenu.transferIfNeeded(player,item)
    ISTimedActionQueue.add(ISEquipWeaponAction:new(player,item,50,primary,twoHands))
end
ISInventoryPaneContextMenu.OnPrimaryWeapon=function(items,playerNum)
    ISInventoryPaneContextMenu.equipWeapon(items[1],true,false,playerNum)
end
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
local enabled, dead, doNotReequip = true, false, true
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'))()
local operations, definitions = PZSurvivorToolkit.ActionQueueOperations, PZSurvivorToolkit.ActionQueueDefinitions
local sharedApproach=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueApproach.lua'))()
assert(sharedApproach.install()and sharedApproach.nativeHelper(luautils,'walkAdj',luautils.walkAdj)==nativeWalk)
nativeWalk=luautils.walkAdj
local adoptReturns, returnAdoptions = operations.adoptReturnMethods, 0
operations.adoptReturnMethods = function(...)
    assert(adoptReturns(...), 'actual Better Containers wrappers must remain recognized native returns')
    returnAdoptions = returnAdoptions + 1
    return true
end
local paths = {
    WashFix = '3460812542/mods/WashingMenusImproved/42.15',
    NeatUI_Equipment = '3790656296/mods/NeatUI_Equipment/42.20',
    P4TidyUpMeister = '2769706949/mods/P4TidyUpMeister/42.20',
    Project_Cook = '3490188370/mods/Project_Cook/common',
    Neat_Crafting = '3502080466/mods/Neat_Crafting/common',
    MPFastForward = '3738738086/mods/MPFastForward/42',
    EURY_CONTAINERS = '3586216562/mods/BetterContainers/42.21',
}
ISInventoryPage={onBackpackRightMouseDown=function() end}
local floorSource=read(NativeActionRoot..'/client/ISUI/ISInventoryPage.lua')
assert(loadstring(assert(floorSource:match('(function ISInventoryPage.GetFloorContainer%(playerNum%).-\nend)')),'@ISInventoryPage.lua'))()
local nativeFloorGetter,previousOrigin=ISInventoryPage.GetFloorContainer,getFilenameOfClosure
-- Model only vanilla refreshBackpacks' world-item -> cached-floor association; source ownership remains pinned.
local nativeFloorRefresh=function(self)
    self.refreshCount=(self.refreshCount or 0)+1
    local floor=ISInventoryPage.GetFloorContainer(self.player)
    floor.values=self.worldItems or {}
    for _,value in ipairs(floor.values)do value.container=floor end
end
ISInventoryPage.refreshBackpacks=nativeFloorRefresh
getFilenameOfClosure=function(callback)
    if callback==nativeFloorGetter then return 'ISInventoryPage.lua' end
    local source=debug and debug.getinfo(callback,'S').source
    if source and (source:match('/PJCK_Config%.lua$') or source:match('/ISWearClothing%.lua$') or source:match('/ISUnequipAction%.lua$') or source:match('/ISHotbar%.lua$') or source:match('/ISPlayerData%.lua$')) then return source end
    if previousOrigin then return previousOrigin(callback) end
end
ISInventoryPage.floorContainer={{class='ItemContainer',getType=function()return 'floor'end,
    getParent=function()end,getContainingItem=function()end}}
local containerGuards={}
PZSurvivorToolkit.ActionQueuePolicy={skipUnavailableHygiene=function() end,
    hygieneUnavailable=function() return false end, adoptReadAnimEvent=function(previous,replacement)
    return previous==nativeReadAnimEvent and ISReadABook.animEvent==replacement
end, adoptTransferFloorHelper=function(previous,replacement)
    transferHelperAdopted=previous==nativeFloorHelper and ISInventoryTransferAction.getNotFullFloorSquare==replacement
    return transferHelperAdopted
end, adoptTransferItemHelper=function(previous,replacement,guard,previousOffset,replacementOffset)
    assert(previous==nativeTransferItem and replacement==ISTransferAction.transferItem and replacement~=previous,
        'verified Tidy load must adopt its exact new native transfer wrapper')
    assert(type(guard)=='function' and guard(),'verified Tidy source identity must match before adoption')
    assert(previousOffset==nativeDropItemOffset and replacementOffset==ISTransferAction.GetDropItemOffset
        and replacementOffset~=previousOffset,'verified Tidy load adopts the companion floor-offset wrapper')
    transferItemGuard,adoptedTransferItem=guard,replacement
    return true
end, adoptTransferMethods=function(previous,replacement,guard)
    for _,name in ipairs({'isValid','start','perform','stop'}) do
        assert(type(previous[name])=='function' and ISInventoryTransferAction[name]==replacement[name])
    end
    assert(guard()); containerGuards[#containerGuards+1]=guard; return true
end, addContainerResources=function(result,container)
    if not instanceof(container,'ItemContainer') then return end
    local parent=container:getParent()
    if parent and not instanceof(parent,'IsoGameCharacter') then result.targets[parent]=true end
    local owner=container.getContainingItem and container:getContainingItem()
    if instanceof(owner,'InventoryContainer') then
        result.containerOwners=result.containerOwners or {}; result.containerOwners[owner:getID()]=true
        result.itemTypes[owner:getFullType()]=true
    end
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
local projectCookUiOriginal = {}
local loaded = {}
require = function(module)
    if module == 'PZSurvivorToolkit/ActionQueueSettlement' then
        return PZSurvivorToolkit.ActionQueueSettlement or dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueSettlement.lua')
    end
    if module == "PZSurvivorToolkit/ActionQueueMembership" then
        return assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. module .. ".lua"))()
    end
    if module == 'PZSurvivorToolkit/QuartermasterCraftContainers' then
        craftContainers = craftContainers or assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. module .. '.lua'))()
        return craftContainers
    end
    if module == 'PZSurvivorToolkit/SourceProof' then return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))() end
    if loaded[module] then return loaded[module] end
    if module == 'NeatEquipment/NEQ_Outfit' then return Outfit end
    if module == 'NeatEquipment/NEQ_Gather' then return Gather end
    if module == 'NeatEquipment/NEQ_Categories' then return {SLOTS = {}} end
    if module == 'NeatEquipment/NEQ_State' then return {wardrobeSwapContainers = false} end
    if module=='BetterContainers/_Options' then return {} end
    if module=='BetterContainers/_IO/IniWriter' then return {makeFeature=function() return {get=function() return {} end} end} end
    local id, branch
    if module:match('^NeatEquipment/') then id, branch = 'NeatUI_Equipment', 'client/'
    elseif module:match('^Neat_Crafting/NC_CraftActionPanel') then id, branch = 'Neat_Crafting', 'client/'
    elseif module == 'Project_Cook/PJCK_Config' or module:match('^Project_Cook/HandCraftPanel/PJCK_CraftActionPanel') or module:match('^Project_Cook/EvolvedRecipePanel/') then id, branch = 'Project_Cook', 'client/'
    elseif module == 'Project_Cook/PJCK_FrozenCooking' or module == 'Project_Cook/PJCK_EvolvedSpiceGuard' then id, branch = 'Project_Cook', 'shared/'
    elseif module:match('^ISUI/WMI_') and module ~= 'ISUI/WMI_Compat_TABAS' then id, branch = 'WashFix', 'client/'
    elseif module == 'TimedActions/WMI_PatchWashClothing' then id, branch = 'WashFix', 'shared/'
    elseif module == 'PZSurvivorToolkit/ActionQueueTidyIntent' then return assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueTidyIntent.lua'))()
    elseif module == 'PZSurvivorToolkit/ActionQueueLifecycle' then
        if PZSurvivorToolkit.ActionQueueLifecycle then return PZSurvivorToolkit.ActionQueueLifecycle end
        return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua'))()
    elseif module == 'P4TidyUpMeister' then id, branch = 'P4TidyUpMeister', 'client/'
    elseif module == 'MPFastForward_ReadFix' then id, branch = 'MPFastForward', 'server/'
    elseif module=='BetterContainers/Helpers' then id,branch='EURY_CONTAINERS','shared/'
    elseif module:match('^BetterContainers/') then id,branch='EURY_CONTAINERS','client/'
    elseif module:match('^TimedActions/P4Restore') then id, branch = 'P4TidyUpMeister', 'shared/' end
    if not id then return end
    local source = read(NativeWishlistWorkshopRoot .. '/' .. paths[id] .. '/media/lua/' .. branch .. module .. '.lua')
    -- Fixture exports expose private state only; the executed action/callback bodies remain upstream.
    if module == 'ISUI/WMI_WashingSubmenus' then
        source = source .. '\nWS.WMI_BuildWashMenu = function(menu, items, character, sink) return menu:addOption("Wash", character, onWashClothing3, sink, {}, items, nil, true, nil) end\nWS.WMI_TestOriginalWashCallback=onWashClothing3\nWS.WMI_TestAggregateWashCallback=WMI_OnWashAll\nWS.WMI_TestBodyWashCallback=_onWashYourselfAndClose\n'
    elseif module == 'P4TidyUpMeister' then source = source .. '\nTidyFixture = P4TidyUpMeister\n' end
    local result = assert(loadstring(source, (module == 'Project_Cook/PJCK_Config' or module:match('^Project_Cook/EvolvedRecipePanel/') or module == 'ISUI/WMI_WashingSubmenus') and '@'..module..'.lua' or module))()
    if module == 'Project_Cook/EvolvedRecipePanel/PJCK_InputPanel' then projectCookUiOriginal.canAddItem=PJCK_InputPanel.canAddItem end
    loaded[module] = result or true; return result
end
-- Load the real controller before source adapters, matching the game's lifecycle/load order.
local fixturePolicy=PZSurvivorToolkit.ActionQueuePolicy
fixturePolicy.isCraftAction=function() return false end
fixturePolicy.live=function(queue) return not queue.character:isDead() end
fixturePolicy.stoppable=function() return false end
fixturePolicy.resumableWorld=function() return false end
fixturePolicy.replaceStop=function() end
fixturePolicy.adoptBegin=function() end
fixturePolicy.inspect=definitions.inspect
fixturePolicy.matchesNative=function()return false end -- real Policy is used by the planned-return observer regression below
PZSurvivorToolkit.ActionQueueLabels={label=function() end}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua'))()
local compatSource = read(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua')
-- Stub only the separately tested Carts hook proof; P4 adoption/matching and its source callbacks stay real.
local priorCarts=PZSurvivorToolkit.ActionQueueCarts
local lateCartProof={enabled=true,constructors={},unequipConstructors={}}
function lateCartProof.isTransferConstructor(callback)
    local latest=lateCartProof.latest
    return lateCartProof.enabled and lateCartProof.constructors[callback]==true and latest
        and ISInventoryTransferAction.new==latest.new and ISInventoryTransferAction.perform==latest.perform
        and ISInventoryTransferAction.transferItem==latest.transferItem
end
function lateCartProof.isUnequipConstructor(callback)
    local latest=lateCartProof.unequipLatest
    return lateCartProof.enabled and lateCartProof.unequipConstructors[callback]==true and latest
        and ISUnequipAction.new==latest.new and ISUnequipAction.complete==latest.complete
end
lateCartProof.isNonCartItem=function(value)return not value.fixtureCart end
lateCartProof.isNonCartUnequip=function(action)
    return lateCartProof.isNonCartItem(action.item) and action.perform==ISUnequipAction.perform
        and action.complete==ISUnequipAction.complete and action.stop==ISUnequipAction.stop
end
lateCartProof.isReturn=function()return false end
lateCartProof.isTransfer=function()return false end
PZSurvivorToolkit.ActionQueueCarts=lateCartProof
local proofSeams
compatSource,proofSeams=compatSource:gsub('local carts=ready%.SaucedCartsTransfers and Toolkit%.ActionQueueCarts',
    'local carts=Toolkit.ActionQueueCarts')
assert(proofSeams==1,'late-hook fixture must replace only the Carts proof capture')
local compat = assert(loadstring((compatSource:gsub('\nreturn Compat',
    '\nCompat.fixtureRegistries = {records, sessions}\nCompat.fixtureRepairTidyFloor = repairTidyFloor\nCompat.fixtureFloorRepairs = repairedFloors\nCompat.fixtureScoped = scoped\nCompat.fixtureLoadSource = loadSource\nreturn Compat'))))()
assert(not compat.isInstalled('MPFastForward'),'server wrapper waits for the server loading boundary')
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/server/000_PZSurvivorToolkitReadCompat.lua'))()
for name, available in pairs({WS=WS~=nil, NEQ_Dresser=NEQ_Dresser~=nil, TidyFixture=TidyFixture~=nil,
    PJCK_EvoPanel=PJCK_EvoPanel~=nil, NC_CraftActionPanel=NC_CraftActionPanel~=nil, PJCK_CraftActionPanel=PJCK_CraftActionPanel~=nil}) do
    assert(available, 'selected source not installed: '..name)
end
assert(transferHelperAdopted,'verified Tidy load hands the exact native wrapper pointers to Policy')
assert(transferItemGuard and transferItemGuard() and adoptedTransferItem==ISTransferAction.transferItem,
    'actual pinned Tidy source adopts its once-captured native delegate wrapper')
assert(TidyFixture.ISTransferAction_transferItem==nativeTransferItem,'actual source saves the captured helper as its private delegate')
assert(TidyFixture.ISTransferAction_GetDropItemOffset==nativeDropItemOffset,'actual source saves the companion offset delegate')
assert(PZSurvivorToolkit.ActionQueueLifecycle,'early Compat load must install Lifecycle before P4 method snapshots')
local tidyPublic=P4TidyUpMeister
P4TidyUpMeister={registerActionPolicy=tidyPublic.registerActionPolicy,registerWornItemReplacement=tidyPublic.registerWornItemReplacement}
assert(not transferItemGuard(),'late public owner replacement invalidates adopted helper identity')
P4TidyUpMeister=tidyPublic
for _,name in ipairs({'registerActionPolicy','registerWornItemReplacement'}) do
    local callback=tidyPublic[name];tidyPublic[name]=function() end
    assert(not transferItemGuard(),'late public source callback replacement invalidates adopted helper identity')
    tidyPublic[name]=callback
end
local changedTransferItem=ISTransferAction.transferItem
ISTransferAction.transferItem=function() end
assert(ISTransferAction.transferItem~=adoptedTransferItem,'late global helper replacement cannot match the adopted wrapper')
assert(not transferItemGuard(),'late global transfer replacement invalidates adopted helper identity')
ISTransferAction.transferItem=changedTransferItem
local changedOffset=ISTransferAction.GetDropItemOffset
ISTransferAction.GetDropItemOffset=function() end
assert(not transferItemGuard(),'late companion offset replacement invalidates adopted helper identity')
ISTransferAction.GetDropItemOffset=changedOffset
assert(transferItemGuard(),'restoring exact source identity restores the helper guard')
for id in pairs(paths) do assert(compat.isInstalled(id), 'source-pinned adapter installed: ' .. id) end
assert(returnAdoptions == 2, 'both verified transfer patches must update native return recognition')
operations.adoptReturnMethods = adoptReturns
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
inventory.setDrawDirty=function()end
IsoFlagType={collideW='collideW',collideN='collideN'}
local square = {getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
    canReachTo=function() return true end,has=function()return false end}
getCell=function()return{getGridSquare=function()return square end}end
local player = {class = 'IsoPlayer', getInventory = function() return inventory end, getPlayerNum = function() return 0 end,
    isDead = function() return dead end, isAsleep = function() return false end, isLocalPlayer = function() return true end,
    isDraggingCorpse = function() return false end, isFarming = function() return false end, getSquare = function() return square end,
    isPlayerMoving=function() return false end, pressedMovement=function() return false end,
    hasTimedActions = function() return false end, getModData = function() return {P4TidyUpMeister = {doNotReequip = doNotReequip}} end,
    getWornItems = function() return list({}) end, getPrimaryHandItem = function(self) return self.primary end,
    getSecondaryHandItem = function(self) return self.secondary end, isEquipped = function() return false end, setIsFarming = function() end,
    isTimedActionInstant = function() return false end, hasTrait = function() return false end,StopAllActionQueue=function()end}
player.setPrimaryHandItem=function(self,value)self.primary=value end
player.setSecondaryHandItem=function(self,value)self.secondary=value end
player.removeWornItem=function()end
MoodleType={UNHAPPY='unhappy',DRUNK='drunk'}
player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
player.getTimedActionTimeModifier=function()return 1 end
player.getCurrentSquare=player.getSquare
player.getPerkLevel=function() return 0 end
player.getX=function() return 0 end; player.getY=function() return 0 end
getSpecificPlayer = function() return player end
getGameVersion = function() return '42.21' end
local sink = {class = 'IsoObject', getSquare = function() return square end, getObjectIndex = function() return 1 end}
local queue = ISTimedActionQueue.getTimedActionQueue(player)
local completed = queue.onCompleted
queue.onCompleted = function(self, action) if not operations.deferCompletion(self, action) then return completed(self, action) end end
local function tickTidy()
    compat.prune()
    -- Native OnTick housekeeping interleaves with delayed OnPlayerUpdate restore events.
    if #queue.queue==0 then queue:tick() end
    for _, callback in ipairs(events.OnPlayerUpdate or {}) do callback(player) end
end
local function reset()
    queue.queue, queue.current = {}, nil
    tickTidy(); tickTidy()
    TidyFixture.sessions[player], TidyFixture.restoring[player], TidyFixture.restoreFloor[player] = nil, nil, nil
    inventory.values = {}; enabled, dead, doNotReequip = true, false, true
end
local function item(container, id)
    return {item = true, id = id, container = container, getContainer = function(self) return self.container end,
        getID = function(self) return self.id end, getFullType = function() return 'Base.Test' end,
        getType = function() return 'Test' end, getBloodLevel = function() return 1 end, getDirtiness = function() return 1 end,
        getItemAfterCleaning = function() end, canBeActivated = function(self) return self.activatable or false end, isActivated = function(self) return self.activated or false end,
        setActivated=function(self,value) self.activated=value; self.activationChanges=(self.activationChanges or 0)+1 end,
        getName = function() return 'test' end, isHidden = function() return false end,
        setJobDelta=function()end, IsInventoryContainer=function()return false end, hasTag=function()return false end,
        getCategory=function(self)return self.class=='Clothing' and 'Clothing' or self.class=='AlarmClockClothing' and 'AlarmClock' or 'Item'end,
        getBodyLocation=function(self)return self.location or ItemBodyLocation.SOCKS end,
        canBeEquipped=function(self)return self.equippedAt end,getClothingItem=function()end,
        isBroken=function(self)return self.broken==true end,getAttachedSlot=function(self)return self.attachedSlot or -1 end,
        getUnequippedWeight=function(self)return self.weight or 0.2 end,
        getEquippedWeight=function(self)return self.equippedWeight or self:getUnequippedWeight()*0.3 end,
        isTwoHandWeapon=function()return false end, isRequiresEquippedBothHands=function()return false end}
end
local function tail()
    local action = ISBaseTimedAction:new(player); ISTimedActionQueue.add(action); return action
end
-- The actual audited source-scope table.insert hook must upgrade a previously
-- saved transfer heading even though it bypasses native enqueue callbacks.
do
    reset()
    local transfer = ISInventoryTransferAction:new(player, item(inventory, 19001), inventory, inventory)
    ISTimedActionQueue.add(transfer)
    local token = transfer.toolkitQueueOperation
    assert(definitions.taskTitle(queue, 1, 1) == 'UI_PZSurvivorToolkit_queue_action_transfer')
    local readAction = ISReadABook:new(player, item(inventory, 19002))
    readAction.toolkitQueueOperation = token
    compat.fixtureScoped({id = 'WashFix', token = token, character = player, queue = queue,
        generation = queue.toolkitOperationGeneration or 0}, function()
        table.insert(queue.queue, readAction)
    end)
    assert(queue.queue[2] == readAction and definitions.taskTitle(queue, 1, 2) == 'ContextMenu_Read',
        'direct audited primary insertion failed to upgrade a saved transfer heading')
    reset()
    transfer = ISInventoryTransferAction:new(player, item(inventory, 19003), inventory, inventory)
    ISTimedActionQueue.add(transfer)
    token = transfer.toolkitQueueOperation
    local custom = ISInventoryTransferAction:new(player, item(inventory, 19004), inventory, inventory)
    custom.toolkitQueueOperation = token
    custom.craftRecipe = {class = 'CraftRecipe', getName = function() return 'direct' end,
        getTranslationName = function() return 'Direct custom transfer' end}
    compat.fixtureScoped({id = 'WashFix', token = token, character = player, queue = queue,
        generation = queue.toolkitOperationGeneration or 0}, function()
        table.insert(queue.queue, 2, custom)
    end)
    assert(definitions.taskTitle(queue, 1, 2) == 'UI_PZSurvivorToolkit_queue_mixed',
        'direct audited custom insertion failed to refresh a saved transfer heading')
    reset()
    transfer = ISInventoryTransferAction:new(player, item(inventory, 19005), inventory, inventory)
    ISTimedActionQueue.add(transfer)
    token = transfer.toolkitQueueOperation
    local preparation = ISBaseTimedAction:new(player)
    preparation.Type, preparation.toolkitQueueOperation = 'ISWalkToTimedAction', token
    compat.fixtureScoped({id = 'WashFix', token = token, character = player, queue = queue,
        generation = queue.toolkitOperationGeneration or 0}, function() table.insert(queue.queue, preparation) end)
    assert(token.presentation.dirty)
    queue:removeFromQueue(transfer)
    assert(definitions.taskTitle(queue, 1, 1) == 'UI_PZSurvivorToolkit_queue_action_transfer'
        and not token.presentation.dirty, 'retaining a higher saved title must still clear lazy invalidation')
    reset()
    local describe, bounds = definitions.describe, operations.bounds
    local descriptions, searches = 0, 0
    definitions.describe = function(...) descriptions = descriptions + 1; return describe(...) end
    operations.bounds = function(...) searches = searches + 1; return bounds(...) end
    for _, count in ipairs({10, 30, 60, 120}) do
        reset(); tail()
        descriptions, searches = 0, 0
        local group = {}
        operations.runWith(group, function()
            compat.fixtureScoped({id = 'WashFix', token = group, character = player, queue = queue,
                generation = queue.toolkitOperationGeneration or 0}, function()
                for i = 1, count do
                    ISTimedActionQueue.add(ISInventoryTransferAction:new(player,
                        item(inventory, 19100 + i), inventory, inventory))
                end
            end)
        end)
        assert(#queue.queue == count + 1 and descriptions == 2 * count - 1 and searches == 0,
            'nested ordinary source adds must not rebuild their growing title range')
        descriptions = 0
        compat.fixtureScoped({id = 'WashFix', token = group, character = player, queue = queue,
            generation = queue.toolkitOperationGeneration or 0}, function()
            for i = 1, count do
                local direct = ISInventoryTransferAction:new(player, item(inventory, 19300 + i), inventory, inventory)
                direct.toolkitQueueOperation = group
                table.insert(queue.queue, direct)
            end
        end)
        assert(descriptions == count and searches == 0, 'raw fixed transfers must inspect only their new member')
        descriptions = 0
        for frame = 1, 100 do definitions.taskTitle(queue, 2, #queue.queue) end
        assert(descriptions == 0, 'raw fixed transfer additions must retain their fixed heading')
        compat.fixtureScoped({id = 'WashFix', token = group, character = player, queue = queue,
            generation = queue.toolkitOperationGeneration or 0}, function()
            for i = 1, count do
                local direct = ISReadABook:new(player, item(inventory, 19500 + i))
                direct.toolkitQueueOperation = group
                table.insert(queue.queue, direct)
            end
        end)
        assert(descriptions == 0 and group.presentation.dirty, 'raw primary additions must invalidate lazily')
        assert(definitions.taskTitle(queue, 2, #queue.queue) == 'ContextMenu_Read')
        assert(descriptions == 3 * count and not group.presentation.dirty and searches == 0,
            'raw primary additions must rebuild their heading once')
        descriptions = 0
        for frame = 1, 100 do definitions.taskTitle(queue, 2, #queue.queue) end
        assert(descriptions == 0, 'a refreshed direct-primary heading must not rebuild each frame')
    end
    definitions.describe, operations.bounds = describe, bounds
    reset()
end
print('Audited direct queue insertion: primary/custom title upgrades and linear raw/native additions passed.')
do
    local ordinary=ISInventoryTransferAction:new(player,item(inventory,22),inventory,inventory)
    assert(fixturePolicy.isOrdinaryTransfer(ordinary),'reviewed Better Containers allows ordinary transfers')
    local helpers=EURY_CONTAINERS
    local staleVehicle=helpers.isStaleVehicleContainer
    helpers.isStaleVehicleContainer=function() return false end
    assert(not fixturePolicy.isOrdinaryTransfer(ordinary),'changed stale-vehicle helper loses transfer permissions')
    helpers.isStaleVehicleContainer=staleVehicle
    EURY_CONTAINERS={isStaleVehicleContainer=staleVehicle}
    assert(not fixturePolicy.isOrdinaryTransfer(ordinary),'changed Helpers owner loses transfer permissions')
    EURY_CONTAINERS=helpers
    assert(fixturePolicy.isOrdinaryTransfer(ordinary),'restored exact Helpers identity remains valid')

    local vehicle={}
    local ancestor={getVehiclePart=function() return {getVehicle=function() return vehicle end} end,
        getContainingItem=function() end,getCapacityWeight=function() return 0 end,getEffectiveCapacity=function() return 10 end}
    local owner={getContainer=function() return ancestor end}
    local destination={getType=function() return 'inventory' end,getContainingItem=function() return owner end}
    ordinary.destContainer=destination
    ordinary.item.getUnequippedWeight=function() return 1 end
    assert(ordinary:isValid(),'live vehicle ancestor accepts the native nested transfer')
    vehicle=nil
    assert(not ordinary:isValid(),'stale vehicle ancestor retains the upstream transfer rejection')

    local reader=getModFileReader
    for _,path in ipairs({'media/lua/client/BetterContainers/Nested.lua','media/lua/shared/BetterContainers/Helpers.lua'}) do
        getModFileReader=function(id,file,...)
            local input=reader(id,file,...)
            if id=='EURY_CONTAINERS' and file==path then
                local readLine=input.readLine;local first=true
                input.readLine=function(...)
                    local line=readLine(...)
                    if first then first=false;return line..' -- changed' end
                    return line
                end
            end
            return input
        end
        assert(not compat.verifySources('EURY_CONTAINERS'),'changed Better Containers source must remain unapproved: '..path)
    end
    getModFileReader=reader
    assert(compat.verifySources('EURY_CONTAINERS'),'exact current Better Containers sources remain approved')
end
-- Temporary source interception must preserve ownership under Kahlua's rawget.
do
 local base,savedRequire,savedRawget=ISBaseTimedAction,require,rawget
 local function own(owner,key)for name,value in pairs(owner)do if name==key then return value end end end
 local owned,meta=own(base,'derive'),getmetatable(base);local inherited=base.derive
 local parent={derive=inherited};parent.__index=parent
 base.derive=nil;setmetatable(base,parent)
 rawget=function(owner,key)
  local value=own(owner,key);if value~=nil then return value end
  local ancestor=getmetatable(owner);if ancestor then return rawget(ancestor,key)end
 end
 assert(rawget(base,'derive')==inherited and own(base,'derive')==nil,'fixture missing native inherited rawget behavior')
 for _,fails in ipairs({false,true})do
  require=function(module)
   assert(module=='fixture/source-loader')
   ISBaseTimedAction:derive('FixtureChild')
   if fails then error('fixture source failure')end
   return{}
  end
  assert(compat.fixtureLoadSource('FixtureSource','fixture/source-loader')==not fails)
  assert(own(base,'derive')==nil and base.derive==inherited,'source load changed ownership of inherited derive')
 end
 require,rawget=savedRequire,savedRawget;setmetatable(base,meta);base.derive=owned
end
local function wash(value)
    menu.options = {}; WS.WMI_BuildWashMenu(menu, {value}, player, sink)
    local option = menu.options[1]; option.callback(option.target, unpack(option.args,1,10))
    -- Deep source cases begin at the transfer boundary. Execute a genuine head
    -- approach when it is ready; keep deferred preparation behind other work.
    local approach=queue.queue[1]
    if sharedApproach.isAction(approach)then approach:begin();approach:start();approach:perform()end
    return queue.queue[1]
end
reset()
local front=tail(); local frontClears=nativeClears
local frontBag={class='ItemContainer',getParent=function() end,getType=function() return 'none' end,getContainingItem=function() end}
wash(item(frontBag,21)); local approachCommand,waitingWash=queue.queue[2],queue.queue[3];local back=tail()
assert(queue.queue[1]==front and sharedApproach.isAction(approachCommand)and waitingWash.Type=='ISInventoryTransferAction'
    and approachCommand.toolkitQueueOperation==waitingWash.toolkitQueueOperation and nativeClears==frontClears,
    'real shared walkAdj defers intact native clearing behind unrelated work in the Wash source scope; got '
        ..tostring(approachCommand and approachCommand.Type)..' command='..tostring(operations.isCommand(approachCommand))
        ..' approach='..tostring(sharedApproach.isAction(approachCommand))..' tracked='..tostring(compat.fixtureRegistries[1][approachCommand]~=nil))
assert(luautils.walkAdj==nativeWalk,'Wash callback must leave the shared dispatcher installed')
operations.invalidate(waitingWash.toolkitQueueOperation);table.remove(queue.queue,3);table.remove(queue.queue,2)
assert(queue.queue[1]==front and queue.queue[2]==back,'waiting Wash cancellation preserves both unrelated ends')
-- Run the actual queued native helper at its turn; no temporary keepActions wrapper exists.
reset();front=tail();wash(item(frontBag,22));approachCommand,waitingWash=queue.queue[2],queue.queue[3];back=tail()
queue:removeFromQueue(front);queue.current=approachCommand;frontClears=nativeClears
approachCommand:begin();approachCommand:start();approachCommand:perform()
assert(queue.current==waitingWash and queue.queue[#queue.queue]==back and nativeClears==frontClears+1 and luautils.walkAdj==nativeWalk,
    'native walkAdj clear at the shared command head must preserve its dependent transfer and independent tail')
reset();front=tail();wash(item(frontBag,26));approachCommand=queue.queue[2]
queue:removeFromQueue(front);queue.current=approachCommand
local oldReach=square.canReachTo;square.canReachTo=function()error('native walking failure')end
approachCommand:begin();assert(not pcall(function()approachCommand:start()end));square.canReachTo=oldReach
assert(luautils.walkAdj==nativeWalk,'native routing exception must not replace the shared dispatcher')
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
-- Only an exact reviewed laundering menu selection owns the migrated producer.
do
 local beforeConsumed=consumed
 local function garment(id,container)
  local value=item(container or bag,id);value.class='Clothing';return value
 end
 local function producer(action)return select(2,definitions.inspect(action))end
 local function choose(callback,args,mutate)
  menu.options={}
  compat.fixtureScoped({id='WashFix'},function()
   menu:addOption('Wash fixture',player,callback,unpack(args,1,args.n))
  end)
  local option=menu.options[1]
  if mutate then mutate(option)end
  option.callback(option.target,unpack(option.args,1,10))
  local approach=queue.queue[1]
  if sharedApproach.isAction(approach)then approach:begin();approach:start();approach:perform()end
  return queue.queue[1]
 end
 reset()
 local value=garment(28001);local pickup=wash(value);local later=tail()
 assert(producer(pickup)=='compat.wash-clothing','reviewed clothing pickup must select shared completion producer')
 local origin=assert(compat.fixtureRegistries[1][pickup].washOrigin)
 pickup:perform()
 local laundering,returning=queue.queue[1],queue.queue[2]
 assert(producer(laundering)=='compat.wash-clothing'and producer(returning)=='compat.wash-clothing'
  and compat.fixtureRegistries[1][laundering].washOrigin==origin and compat.fixtureRegistries[1][returning].washOrigin==origin,
  'clothing source continuation lost its sealed origin or same-task return')
 assert(queue.queue[3]==later,'fallback completion reordered independent tail')
 laundering:perform();laundering:complete();returning:perform()
 assert(value.container==bag and queue.queue[1]==later,'shared producer fallback without a Java lifecycle lost native return')
 reset();value=garment(28002);pickup=wash(value);pickup.fixtureDelay=true;later=tail();pickup:perform()
 local retry=queue.queue[1]
 assert(producer(retry)=='compat.wash-clothing','private inventory wait lost laundering origin')
 retry:perform();local nextRetry=queue.queue[1]
 assert(producer(nextRetry)=='compat.wash-clothing'and nextRetry~=retry,'recursive raw wait insertion lost laundering origin')
 value.container=inventory;inventory.values={value};nextRetry:perform()
 assert(producer(queue.queue[1])=='compat.wash-clothing'and producer(queue.queue[2])=='compat.wash-clothing'
  and queue.queue[3]==later,'retry did not preserve its native wash/return/tail ordering')
 local size=#queue.queue;retry.onCompleteFunc(unpack(retry.onCompleteArgs));nextRetry.onCompleteFunc(unpack(nextRetry.onCompleteArgs))
 assert(#queue.queue==size,'late duplicate inventory waits replayed the source')
 reset();value=garment(28003);pickup=wash(value);later=tail()
 queue.queue,queue.current={later},later;value.container=inventory;compat.prune()
 assert(not compat.fixtureRegistries[1][pickup],'fixture did not prune completed parent')
 pickup.onCompleteFunc(unpack(pickup.onCompleteArgs))
 assert(producer(queue.queue[1])=='compat.wash-clothing'and queue.queue[3]==later,'pruned asynchronous parent lost its sealed origin')
 pickup.onCompleteFunc(unpack(pickup.onCompleteArgs));assert(#queue.queue==3,'late asynchronous callback applied twice')
 for _,state in ipairs({'cancel','generation','dead','disabled','lost-sink'})do
  reset();value=garment(28004);pickup=wash(value);later=tail()
  if state=='cancel'then operations.invalidate(pickup.toolkitQueueOperation)
  elseif state=='generation'then operations.invalidateQueue(queue)
  elseif state=='dead'then dead=true
  elseif state=='disabled'then enabled=false
  else sink.getObjectIndex=function()return -1 end end
  pickup:perform()
  assert(queue.queue[1]==later and #queue.queue==1,'invalidated laundering callback revived source children: '..state)
  sink.getObjectIndex=function()return 1 end
 end
 -- Ordinary aggregate commands seal the same native clothing effects, not the body action.
 do
  reset();local first=garment(28101);local second=garment(28102)
  local selected={first,second};local data={washYourself=false,regularItems=selected,cleanBandages=false}
  local pickup=choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{},data,false,nil});local later=tail()
  assert(producer(pickup)=='compat.wash-clothing','ordinary All clothing pickup retained legacy completion')
  local sealed=assert(compat.fixtureRegistries[1][pickup].washOrigin)
  assert(sealed.aggregate==data and sealed.selected==selected and sealed.washYourself==false)
  pickup:perform()
  assert(producer(queue.queue[1])=='compat.wash-clothing'and producer(queue.queue[2])=='compat.wash-clothing'
   and compat.fixtureRegistries[1][queue.queue[1]].washOrigin==sealed and queue.queue[#queue.queue]==later,
   'aggregate continuation lost exact origin, return or independent tail')
  operations.invalidate(pickup.toolkitQueueOperation)
  local size=#queue.queue;pickup.onCompleteFunc(unpack(pickup.onCompleteArgs));assert(#queue.queue==size,'aggregate late callback replayed after cancellation')
 end
 for _,change in ipairs({'bandages','extra-data','no-soap','changed-list','named-list','metatable','duplicate','transform'})do
  reset();local first,second=garment(28103),garment(28104)
  local data={washYourself=false,regularItems={first,second},cleanBandages=false}
  local mutate
  if change=='bandages'then data.cleanBandages=true
  elseif change=='extra-data'then data.extra=true
  elseif change=='no-soap'then mutate=function(option)option.args[4]=true end
  elseif change=='changed-list'then mutate=function()data.regularItems={first,second}end
  elseif change=='named-list'then data.regularItems.extra=true
  elseif change=='metatable'then mutate=function()setmetatable(data,{})end
  elseif change=='duplicate'then data.regularItems[2]=first
  else second.getItemAfterCleaning=function()return 'Base.Bandage'end end
  local action=choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{},data,false,nil},mutate)
  assert(action and producer(action)=='compat.selected-chains','unknown aggregate shape migrated: '..change)
 end
 -- Each rejected provenance shape still executes its original native/legacy source callback.
 for _,state in ipairs({'foreign-callback','changed-args','named-list','late-metatable','reordered-list','duplicate','mixed','transform','aggregate'})do
  reset();value=garment(28005)
  local callback=WS.WMI_TestOriginalWashCallback
  local args={n=6,sink,{}, {value},nil,true,nil}
  local mutate
  if state=='foreign-callback'then local native=callback;callback=function(...)return native(...)end
  elseif state=='changed-args'then mutate=function(option)option.args[5]=false end
  elseif state=='named-list'then args[3].extra='foreign metadata'
  elseif state=='late-metatable'then mutate=function(option)setmetatable(option.args[3],{})end
  elseif state=='reordered-list'then
   args[3][2]=garment(28009);mutate=function(option)local v=option.args[3];v[1],v[2]=v[2],v[1]end
  elseif state=='duplicate'then args[3][2]=value
  elseif state=='mixed'then args[3][2]=item(bag,28006)
  elseif state=='transform'then value.getItemAfterCleaning=function()return 'Base.Bandage'end
  elseif state=='aggregate'then callback=WS.WMI_TestAggregateWashCallback;args={n=5,sink,{}, {regularItems={value}},true,nil}end
  local action=choose(callback,args,mutate)
  assert(action and producer(action)=='compat.selected-chains','unsupported laundering provenance migrated: '..state)
 end
 reset()
 local bodyClass,bodyCallback,walkObject=ISWashYourself,ISWorldObjectContextMenu.onWashYourself,luautils.walkAdjObject
 nativeClass('ISWashYourself')
 local worldSource=read(NativeActionRoot..'/client/ISUI/ISWorldObjectContextMenu.lua')
 assert(loadstring(assert(worldSource:match('(ISWorldObjectContextMenu.onWashYourself = function.-\nend)')),'@ISWorldObjectContextMenu.lua'))()
 assert(loadstring(assert(walkSource:match('(function luautils.walkAdjObject.-\nend)')),'@luautils.lua'))()
 local body=choose(WS.WMI_TestBodyWashCallback,{n=3,sink,{},nil})
 assert(body.Type=='ISWashYourself'and producer(body)==nil,'body washing must retain the default native lifecycle, without any legacy or clothing producer')
 reset();value=garment(28105)
 local mixed={washYourself=true,regularItems={value},cleanBandages=false}
 choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{},mixed,false,nil})
 local bodySeen,pickupSeen=false,false
 for _,action in ipairs(queue.queue)do
  if action.Type=='ISWashYourself'then bodySeen=true;assert(producer(action)==nil,'All command replaced native body lifecycle')
  elseif action.Type=='ISInventoryTransferAction'then pickupSeen=true;assert(producer(action)=='compat.wash-clothing','mixed body/clothing All did not migrate its ordinary clothing branch')end
 end
 assert(bodySeen and pickupSeen,'mixed All source did not enqueue both native branches')
 reset();value=garment(28106);local other=garment(28107)
 mixed={washYourself=false,regularItems={value,other},cleanBandages=false}
 choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{},mixed,false,nil},function()mixed.washYourself=true end)
 local rejectedPickups=0
 for _,action in ipairs(queue.queue)do
  if action.Type=='ISInventoryTransferAction'then
   rejectedPickups=rejectedPickups+1
   assert(producer(action)=='compat.selected-chains','mutated aggregate body flag kept original seal')
  end
 end
 assert(rejectedPickups==2,'mutated All did not exercise both original clothing pickups')
 -- Preparation admission does not grant transformation lifecycle rights.
 for _,queueEnabled in ipairs({false,true})do
  reset();enabled=queueEnabled;local first=garment(28201)
  local bandage=item(bag,28202);bandage.getFullType=function()return 'Base.BandageDirty'end
  bandage.getItemAfterCleaning=function()return 'Base.Bandage'end
  local recurse=inventory.getAllTypeRecurse
  inventory.getAllTypeRecurse=function(_,kind)return list(kind=='Base.BandageDirty'and{bandage}or{})end
  local data={washYourself=true,regularItems={first},cleanBandages=true};local clears=nativeClears
  choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{},data,false,nil})
  inventory.getAllTypeRecurse=recurse
  local bodies,pickups=0,0
  for _,action in ipairs(queue.queue)do
   if action.Type=='ISWashYourself'then bodies=bodies+1
   elseif action.Type=='ISInventoryTransferAction'then
    pickups=pickups+1;assert(producer(action)~='compat.wash-clothing','bandage aggregate borrowed ordinary-clothing lifecycle rights')
   end
  end
  assert(bodies==1 and pickups==2,'bandage All preparation discarded body/clothing/bandage siblings')
  if not queueEnabled then assert(nativeClears==clears+1,'native bandage All replaced prior work more than once')end
 end
 reset();enabled=false;local kept=tail();local clears=nativeClears
 local dirtyCloth=item(bag,28204);dirtyCloth.getFullType=function()return 'Base.BandageDirty'end
 dirtyCloth.getItemAfterCleaning=function()return 'Base.Bandage'end
 local recurse=inventory.getAllTypeRecurse
 inventory.getAllTypeRecurse=function(_,kind)return list(kind=='Base.BandageDirty'and{dirtyCloth}or{})end
 choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{}, {washYourself=true,regularItems={},cleanBandages=true},false,nil})
 inventory.getAllTypeRecurse=recurse
 assert(queue.queue[1]==kept and nativeClears==clears,'body/bandage-only All invented replacement despite native keep-actions routes')
 reset();enabled=false;local containerItem=item(inventory,28205);containerItem.class='InventoryContainer'
 choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{}, {washYourself=true,regularItems={containerItem},cleanBandages=false},false,nil})
 local bodyCount,containerCount=0,0
 for _,action in ipairs(queue.queue)do
  if action.Type=='ISWashYourself'then bodyCount=bodyCount+1
  elseif action.Type=='ISWashClothing'then containerCount=containerCount+1;assert(producer(action)~='compat.wash-clothing','generic All borrowed clothing rights')end
 end
 assert(bodyCount==1 and containerCount==1,'generic washable All discarded its native body sibling')
 reset();enabled=false;value=garment(28203)
 mixed={washYourself=true,regularItems={value},cleanBandages=false}
 choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{},mixed,false,nil},function()value.container=inventory end)
 local bodies,washes=0,0
 for _,action in ipairs(queue.queue)do
  if action.Type=='ISWashYourself'then bodies=bodies+1
  elseif action.Type=='ISWashClothing'then washes=washes+1;assert(producer(action)~='compat.wash-clothing','changed container kept an old completion claim')end
 end
 assert(bodies==1 and washes==1,'a changed native input container incorrectly disabled safe batch preparation')
 -- Queue-disabled native All replaces prior work once, but must not erase its own body sibling.
 reset();enabled=false;local prior=tail();local clears=nativeClears
 value=garment(28108);mixed={washYourself=true,regularItems={value},cleanBandages=false}
 choose(WS.WMI_TestAggregateWashCallback,{n=5,sink,{},mixed,false,nil})
 local nativeBody,route,pickup
 for _,action in ipairs(queue.queue)do
  if action.Type=='ISWashYourself'then nativeBody=action
  elseif sharedApproach.isAction(action)then route=action
  elseif action.Type=='ISInventoryTransferAction'then pickup=action end
 end
 assert(queue:indexOf(prior)==-1 and nativeClears==clears+1 and queue.queue[1]==nativeBody and route and pickup,
  'native All must replace old work once and retain body, later approach and clothing')
 assert(producer(nativeBody)==nil and producer(pickup)==nil,'queue-off All borrowed enabled source contracts')
 local independent=tail()
 -- Model the completed body boundary; the second real native route must not clear its existing siblings.
 queue:removeFromQueue(nativeBody);queue.current=route
 route:begin();route:start();route:perform()
 assert(queue.queue[1]==pickup and queue.queue[#queue.queue]==independent and nativeClears==clears+2,
  'later native clear escaped its preparation boundary and erased clothing or the independent tail')
 reset();enabled=false
 operations.run(function()
  local ok,message=pcall(sharedApproach.runNativeBatch,player,function()error('batch callback failure')end)
  assert(not ok and tostring(message):find('batch callback failure',1,true),'native batch swallowed callback failure')
  local before=nativeClears;luautils.walkAdj(player,square)
  assert(nativeClears==before+1 and #queue.queue==0,'failed native batch leaked deferred preparation to a later callback')
  sharedApproach.runNativeBatch(player,function()
   luautils.walkAdj(player,square);local owned=queue.queue[1];local before=nativeClears
   sharedApproach.runNativeBatch(player,function()luautils.walkAdj(player,square)end)
   assert(queue.queue[1]==owned and #queue.queue==2 and nativeClears==before,'nested native batch erased an earlier sibling')
   local remote=setmetatable({isLocalPlayer=function()return false end},{__index=player})
   local called=false;sharedApproach.runNativeBatch(remote,function()called=true end)
   assert(called and nativeClears==before and queue.queue[1]==owned,'remote batch replaced local work')
   local foreign=setmetatable({},{__index=player});local foreignQueue=ISTimedActionQueue.getTimedActionQueue(foreign)
   luautils.walkAdj(foreign,square)
   assert(nativeClears==before+1 and #foreignQueue.queue==0 and queue.queue[1]==owned,
    'foreign actor inherited deferred preparation from the local batch')
   ISTimedActionQueue.queues[foreign]=nil
  end)
  local function packed(...)return{n=select('#',...),...}end
  local result=packed(sharedApproach.runNativeBatch(player,function()return nil,'native result',nil,4 end))
  assert(result.n==4 and result[1]==nil and result[2]=='native result'and result[3]==nil and result[4]==4,
   'native batch changed the original callback return tuple')
 end)
 reset()
 ISWashYourself,ISWorldObjectContextMenu.onWashYourself,luautils.walkAdjObject=bodyClass,bodyCallback,walkObject
 reset();value=garment(28007)
 WS.WMI_TestOriginalWashCallback(player,sink,{}, {value},nil,true,nil)
 local approach=queue.queue[1]
 if sharedApproach.isAction(approach)then approach:begin();approach:start();approach:perform()end
 assert(producer(queue.queue[1])~='compat.wash-clothing','direct source invocation forged a menu capability')
 reset()
 local dirtyBandage=item(bag,28008);dirtyBandage.getFullType=function()return 'Base.BandageDirty'end
 dirtyBandage.getItemAfterCleaning=function()return 'Base.Bandage'end
 local allTypes=inventory.getAllTypeRecurse
 inventory.getAllTypeRecurse=function(_,kind)return list(kind=='Base.BandageDirty'and{dirtyBandage}or{})end
 assert(WMI_Clean.queueAllDirtyItems(player,sink,true,nil),'actual legacy bandage aggregate did not queue')
 inventory.getAllTypeRecurse=allTypes
 approach=queue.queue[1]
 if sharedApproach.isAction(approach)then approach:begin();approach:start();approach:perform()end
 assert(producer(queue.queue[1])=='compat.selected-chains','transformed/direct-server bandage path migrated with clothing')
 reset();consumed=beforeConsumed
 print('PASS sealed Wash clothing menu origin, raw retries, late/pruned continuation, duplicate/invalidation and legacy subset boundaries')
end

do
    local function count(registry) local n=0; for _ in pairs(registry) do n=n+1 end; return n end
    local records, sessions = unpack(compat.fixtureRegistries)
    for i=1,500 do
        reset(); wash(item(bag,10000+i)); compat.prune()
        assert(count(records)==1 and count(sessions[player].seen)==1, 'completed source actions must not accumulate in registries')
    end
    reset()
    local visits = assert(loadfile(ProjectRoot .. '/tests/support/queue_registry_visits.lua'))()
    local queuedSource = wash(item(bag, 19050))
    -- Release the completed real approach before measuring steady queued-source pruning.
    compat.prune()
    queue.queue, queue.current = {queuedSource}, queuedSource
    for i = 2, 4097 do queue.queue[i] = {} end
    assert(visits(queue.queue, compat.prune) == 1 and records[queuedSource],
        'queued compatibility source must not scan an unrelated long tail')
    table.remove(queue.queue, 1)
    compat.prune()
    assert(not records[queuedSource] and sessions[player] and count(sessions[player].seen) == 0)
    assert(visits(queue.queue, compat.prune) == 0 and sessions[player],
        'delayed Tidy history with no seen actions must retain its session without scanning the queue')
    reset(); dirty=item(bag,1)
    -- Native completion may dispatch this callback after the queue has already released its parent.
    local delayed=wash(dirty); local later=tail()
    queue.queue,queue.current={later},later; dirty.container=inventory
    compat.prune(); assert(not records[delayed])
    delayed.onCompleteFunc(unpack(delayed.onCompleteArgs))
    assert(queue.queue[1].Type=='ISWashClothing' and queue.queue[3]==later,
        'registry cleanup must preserve an outstanding audited source callback')
    delayed.onCompleteFunc(unpack(delayed.onCompleteArgs)); assert(#queue.queue==3, 'late completion remains one-shot')
    for _, state in ipairs({'cancel','dead','replacement','world'}) do
        reset(); local stale=wash(item(bag,11000)); later=tail()
        if state=='cancel' then operations.invalidate(stale.toolkitQueueOperation); queue.queue,queue.current={later},later
        elseif state=='dead' then dead=true
        elseif state=='replacement' then ISTimedActionQueue.queues[player]={queue={later},character=player}
        else ISTimedActionQueue.queues={} end
        compat.prune(); assert(count(records)==0, state..' must release source records')
        if state~='cancel' then assert(count(sessions)==0, state..' must release Tidy session ownership') end
        stale.onCompleteFunc(unpack(stale.onCompleteArgs))
        assert(queue.queue[#queue.queue]==later, state..' must not append a stale source chain')
        ISTimedActionQueue.queues[player]=queue; dead=false
    end
    reset(); local stale=wash(item(bag,12000)); local later=tail()
    queue.queue,queue.current={later},later; compat.prune()
    for _,callback in ipairs(events.OnMainMenuEnter or {}) do callback() end
    assert(count(records)==0 and count(sessions)==0, 'main menu must release the departed world immediately')
    -- Even reusing the same player/queue with its original generation must not revive an old callback.
    stale.onCompleteFunc(unpack(stale.onCompleteArgs))
    assert(#queue.queue==1 and queue.queue[1]==later, 'a new world cannot revive an already pruned source callback')
    -- Floor repair receipts can outlive all other compatibility registries.
    -- Inspect entries directly, without relying on Lua's weak-key GC behavior.
    local floorRepairs=compat.fixtureFloorRepairs
    for _, lifecycle in ipairs({'completed','dead','replacement','world','menu'}) do
        reset()
        for _,callback in ipairs(events.OnMainMenuEnter or {}) do callback() end
        local repaired={character=player}
        queue.queue,queue.current={repaired},repaired
        floorRepairs[repaired]={queue=queue,character=player}
        assert(count(records)==0 and count(sessions)==0,
            'floor-only cleanup must exercise prune without another registry keeping it active')
        compat.prune()
        assert(floorRepairs[repaired], 'queued floor placement must retain its repair receipt')
        if lifecycle=='completed' then queue.queue,queue.current={},nil
        elseif lifecycle=='dead' then dead=true
        elseif lifecycle=='replacement' then ISTimedActionQueue.queues[player]={queue={},character=player}
        elseif lifecycle=='world' then ISTimedActionQueue.queues={}
        else for _,callback in ipairs(events.OnMainMenuEnter or {}) do callback() end end
        if lifecycle~='menu' then compat.prune() end
        assert(not floorRepairs[repaired], lifecycle..' must release departed floor placement receipts')
        ISTimedActionQueue.queues[player]=queue; dead=false
    end
    reset(); dirty=item(bag,1)
end
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
local successfulWait=queue.queue[1]
successfulWait:perform(); assert(queue.queue[1].Type == 'ISWashClothing' and queue.queue[3] == unrelated)
successfulWait.onCompleteFunc(unpack(successfulWait.onCompleteArgs))
assert(#queue.queue==3 and queue.queue[3]==unrelated,'a repeated private wait result cannot duplicate washing or return')
reset(); enabled=false; dirty=item(bag,20); transfer=wash(dirty); transfer.fixtureDelay=true; unrelated=tail()
assert(not definitions.inspect(transfer),'initially disabled operations retain native callbacks')
transfer:perform(); assert(queue.queue[1].Type=='WMI_WaitForInvUpdate')
dirty.container=inventory; inventory.values={dirty}; queue.queue[1]:perform()
assert(queue.queue[1].Type=='ISWashClothing' and queue.queue[3]==unrelated,'native disabled washing still retries and queues its return before tail')
reset(); dirty = item(bag, 4); transfer = wash(dirty); transfer.fixtureDelay = true; unrelated = tail(); transfer:perform()
wait = queue.queue[1]; operations.invalidate(wait.toolkitQueueOperation); wait:perform()
assert(queue.queue[1] == unrelated, 'cancelled wait cannot schedule another retry')
wait.onCompleteFunc(unpack(wait.onCompleteArgs))
assert(queue.queue[1]==unrelated and #queue.queue==1,'late canceled private wait callback preserves native completion and unrelated tail')
reset();dirty=item(bag,140);transfer=wash(dirty);transfer.fixtureDelay=true;unrelated=tail();transfer:perform()
wait=queue.queue[1]
local waitStart=wait.start
wait.start=function() end
assert(not definitions.inspect(wait),'modified private wait lifecycle remains protected')
wait.start=waitStart
local waitCallback=wait.onCompleteFunc
wait.onCompleteFunc=function() end
assert(not definitions.inspect(wait),'modified private wait callback remains protected')
wait.onCompleteFunc=waitCallback
assert(definitions.inspect(wait),'exact private wait callback and lifecycle restore the verified contract')
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
do
    local control=setmetatable({},NC_CraftActionPanel)
    ISXuiSkin.RegisterXuiSkinFunctions(control,false)
    local callbacks={onStartFunc=control.onHandcraftActionStart,onCompleteFunc=control.onHandcraftActionComplete,
        onCancelFunc=control.onHandcraftActionCancelled}
    assert(compat.isCraftOwner('NC_CraftActionPanel',control,callbacks),
        'actual native Xui instance functions do not replace verified Neat callbacks')
    for _,name in ipairs({'xuiRecalculateLayout','xuiRootElement'})do
        local original=rawget(control,name)
        assert(type(original)=='function'and original==ISXuiSkinFunctions[name],
            'native RegisterXuiSkinFunctions must attach each exact instance method')
        local foreign=function()error('foreign Xui helper must not run')end
        control[name]=foreign
        assert(not compat.isCraftOwner('NC_CraftActionPanel',control,callbacks),'unknown Xui instance pointer remains protected: '..name)
        ISXuiSkinFunctions[name]=foreign
        assert(not compat.isCraftOwner('NC_CraftActionPanel',control,callbacks),'late Xui registry changes cannot establish a baseline: '..name)
        ISXuiSkinFunctions[name],control[name]=original,original
    end
    control.unknownNativeUIHelper=function()error('unknown instance function must not run')end
    assert(not compat.isCraftOwner('NC_CraftActionPanel',control,callbacks),'extra arbitrary instance functions remain protected')
    control.unknownNativeUIHelper=nil
    assert(compat.isCraftOwner('NC_CraftActionPanel',control,callbacks),'restoring native instance pointers restores the verified owner')
end
-- Java HandcraftLogic counts each start and decrements one reference per ordinary stop.
local function projectCookOwner(craftTimes)
    local logic={references=0,starts=0,stops=0,refills=0,sorts=0}
    function logic:startCraftAction()
        self.starts=self.starts+1;self.references=self.references+1
    end
    function logic:stopCraftAction(all)
        self.stops=self.stops+1;self.references=math.max(0,self.references-1)
        if all then self.references=0 end
    end
    function logic:autoPopulateInputs()self.refills=self.refills+1 end
    function logic:sortRecipeList()self.sorts=self.sorts+1 end
    local control=setmetatable({player=player,logic=logic,craftTimes=craftTimes,returnToContainer={},refreshes=0,
        quantityInput={setText=function(self,value)self.text=value end}},PJCK_CraftActionPanel)
    control.HandCraftPanel={updateContainers=function()control.refreshes=control.refreshes+1 end}
    local callbacks={onStartFunc=control.onHandcraftActionStart,onCompleteFunc=control.onHandcraftActionComplete,
        onCancelFunc=control.onHandcraftActionCancelled}
    assert(compat.isCraftOwner('PJCK_CraftActionPanel',control,callbacks),'actual verified Project Cook callbacks own the fixture')
    return control,logic
end
local previousEnabled=enabled
for _,queueEnabled in ipairs({false,true}) do
    enabled=queueEnabled
    for _,quantity in ipairs({1,2}) do
        local control,logic=projectCookOwner(quantity)
        for i=1,quantity do
            control:onHandcraftActionStart({})
            control:onHandcraftActionComplete()
        end
        local expectedReferences=quantity==2 and not queueEnabled and 1 or 0
        local expectedStops=quantity==2 and queueEnabled and 2 or 1
        assert(logic.references==expectedReferences and logic.stops==expectedStops,
            'Project Cook refcount queue='..tostring(queueEnabled)..' quantity='..quantity
            ..' references='..logic.references..' stops='..logic.stops..' expected='..expectedReferences..'/'..expectedStops)
        assert(logic.starts==quantity and logic.refills==quantity and logic.sorts==quantity and control.refreshes==quantity,
            'actual Project Cook completion and FrozenCooking helpers still run once per craft')
        assert(control.craftTimes==nil and control.quantityInput.text=='1' and control.currentCraftQuantity==1,
            'actual Project Cook completion restores single-craft UI state')
    end
    local control,logic=projectCookOwner(2)
    control:onHandcraftActionStart({});control:onHandcraftActionCancelled()
    assert(logic.references==0 and logic.stops==1 and control.craftTimes==nil,'Project Cook cancellation retains its native stop')
    control:onHandcraftActionComplete()
    assert(logic.references==0 and logic.stops==2,'native stop completion after cancellation gets no extra batch balance')
end
enabled=true
local changedCook,changedLogic=projectCookOwner(2)
changedCook.startHandcraft=function() end
changedCook:onHandcraftActionStart({});changedCook:onHandcraftActionComplete()
assert(changedLogic.references==1 and changedLogic.stops==0,
    'a modified Project Cook instance helper keeps native completion without extra balancing')
enabled=previousEnabled
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
-- An actual Project Cook producer can fail after native insertion. Its source
-- callback remains unchanged; inject the failure at the child enqueue boundary.
do
    reset()
    panel:addIngredients({{groupKey='none',panelType='Ingredient',recipeCompatible=true}},recipe,panel.baseItem)
    local failed = queue.queue[1]
    local independent = tail()
    assert(definitions.inspect(failed).deferred)
    local errorValue, attempts, completions = {}, 0, 0
    failed.action.forceComplete = function() completions = completions + 1 end
    local add = ISTimedActionQueue.add
    local injectedAdd = function(action)
        local result = add(action)
        if action.Type == 'PJCK_SequenceWaitAction' then
            attempts = attempts + 1
            error(errorValue)
        end
        return result
    end
    ISTimedActionQueue.add = injectedAdd
    local insert, addAfter, queueActions = table.insert, ISTimedActionQueue.addAfter, ISTimedActionQueue.queueActions
    local ok, failure = pcall(failed.start, failed)
    assert(not ok and failure == errorValue and attempts == 1 and completions == 0,
        'reviewed mod failure was hidden, skipped or completed')
    assert(not queue:isCurrentActionAddingOtherActions() and failed._numAddedActions == nil,
        'reviewed mod failure retained the native insertion boundary')
    assert(ISTimedActionQueue.add == injectedAdd and table.insert == insert
        and ISTimedActionQueue.addAfter == addAfter and ISTimedActionQueue.queueActions == queueActions,
        'reviewed mod failure retained scoped queue hooks')
    failed:start()
    assert(attempts == 1 and completions == 0, 'reviewed mod failure replayed its producer')
    ISTimedActionQueue.add = add
    local following = tail()
    assert(queue.queue[2].Type == 'PJCK_SequenceWaitAction' and queue.queue[3] == independent
        and queue.queue[4] == following and following.toolkitQueueOperation ~= failed.toolkitQueueOperation,
        'reviewed mod failure rolled back a child or captured the independent tail')
end
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
-- A native-eligible new recipe may inherit labels without having any NEW additions yet.
do
 require('Project_Cook/EvolvedRecipePanel/PJCK_InputPanel');require('Project_Cook/EvolvedRecipePanel/PJCK_CookingInfo')
 local savedEnabled,savedManager,savedContainers,savedPolicy=enabled,RecipeManager,ISInventoryPaneContextMenu.getContainers,PJCK_Config.get().portionPolicy
 local original=assert(projectCookUiOriginal.canAddItem,'actual original InputPanel callback missing')
 local function sourceFood(id,kind,spice)
  local value=item(bag,id);value.class='Food';value.fixtureSpice=spice
  for _,name in ipairs({'isRotten','isBurnt','isFrozen','isCooked','IsDrainable','isNoRecipes'})do
   value[name]=function(self)return self.blocked==name end
  end
  value.isFresh=function()return true end
  value.isSpice=function(self)return self.fixtureSpice end
  value.getFullType=function()return 'Base.'..kind end;value.getType=function()return kind end
  value.getHungerChange=function()return -.4 end;value.getHungChange=value.getHungerChange
  value.getActualWeight=function()return 1 end
  value.getScriptItem=function()return{getHungerChange=function()return 40 end,getActualWeight=function()return 1 end}end
  return value
 end
 local function setup(contained,seasonings)
  reset()
  local topping,spice=sourceFood(31002,'Tomato',false),sourceFood(31003,'Pepper',true)
  local base=sourceFood(31001,'BreadSlices',false);base.container=inventory;base.kind='BreadSlices';base.contained=contained;base.seasonings=seasonings
  base.getType=function(self)return self.kind end;base.getFullType=function(self)return 'Base.'..self.kind end
  base.getFluidContainer=function(self)return self.fixtureFluid end
  base.getExtraItems=function(self)local values={};for i=1,self.contained do values[i]='Base.Cheese'end;return list(values)end
  base.haveExtraItems=function(self)return self.contained>0 end
  base.getSpices=function(self)local values={};for i=1,self.seasonings do values[i]='Base.Salt'end;return list(values)end
  local uiRecipe={getResultItem=function()return 'Sandwich'end,getMaxItems=function()return 4 end,
   getMinimumWater=function(self)return self.minimumWater or 0 end,isAllowFrozenItem=function()return false end,
   getItemRecipe=function()return{getUse=function()return 5 end}end}
  -- Native/Java availability is a boundary input; real source builds the cached usable IDs/profiles.
  uiRecipe.getItemsCanBeUse=function(_,actor,selected,containers)
   assert(actor==player and selected==base and containers,'native availability arguments changed')
   local available={};for _,value in ipairs({topping,spice})do if not value.blocked then available[#available+1]=value end end
   return list(available)
  end
  inventory.values={base}
  RecipeManager={getEvolvedRecipe=function()return list({uiRecipe})end}
  ISInventoryPaneContextMenu.getContainers=function()return list({inventory,bag})end
  local ui=setmetatable({player=player,baseItem=base,recipe=uiRecipe,preCookItems={},switchItems={},
   showPossible={Ingredient=false,Seasoning=false},inputGroupCache={Ingredient={},Seasoning={}},
   inputGroupCacheValid={Ingredient=false,Seasoning=false},Window={getAllItems=function()return list({topping,spice})end}},PJCK_EvoPanel)
  local info=setmetatable({EvoPanel=ui,contentType='',content={},switchRecipeButton={setVisible=function()end}},PJCK_CookingInfo)
  ui.cookingInfoPanel=info
  local input=setmetatable({EvoPanel=ui,panelType='Ingredient'},PJCK_InputPanel)
  local seasoning=setmetatable({EvoPanel=ui,panelType='Seasoning'},PJCK_InputPanel)
  ui.ingredientsPanel,ui.seasoningsPanel=input,seasoning
  info:updateContentType()
  assert(info.contentType=='addOneFirst','real rendering state did not detect BreadSlices -> Sandwich')
  ui:getInputList('Ingredient');ui:getInputList('Seasoning')
  return ui,input,seasoning,info,base,topping,spice,uiRecipe
 end
 for _,queueMode in ipairs({true,false})do
  for _,counts in ipairs({{0,0},{1,0},{2,0},{0,1},{2,1}})do
   local ui,input,seasoning,info,base,topping,spice=setup(counts[1],counts[2]);enabled=queueMode
   assert(ui:isUsableForRecipe(topping,ui.recipe,'Ingredient') and ui:getGroupUseCapacity(topping,'Ingredient')>0,
    'real source native-usability/profile premise missing')
   assert(original(input,topping)==(counts[1]+counts[2]==0),'original actual source did not reproduce inherited-label refusal')
   local inputs,groups,selected=ui.cachedAvailableItems,ui.inputGroupCache,ui.preCookItems
   for _,status in ipairs({'','showNutrition','addOneFirst'})do
    info.contentType=status
    assert(input:canAddItem(topping) and seasoning:canAddItem(spice),'first NEW addition must ignore inherited labels: '..status)
    for _,pendingType in ipairs({'Ingredient','Seasoning'})do
     ui.preCookItems={{panelType=pendingType,groupKey='some-other-selected-group'}}
     assert(not input:canAddItem(topping)and not seasoning:canAddItem(spice),'second NEW pending addition escaped first-result limit: '..status)
    end
    ui.preCookItems=selected
   end
   info.contentType='addOneFirst'
   assert(ui.cachedAvailableItems==inputs and ui.inputGroupCache==groups and base.contained==counts[1]and base.seasonings==counts[2],
    'UI permission changed input caches, contained metadata or selection')
   for _,blocked in ipairs({'isFrozen','isBurnt','isRotten','unusable'})do
    topping.blocked=blocked;ui:invalidateInputCaches();ui:getInputList('Ingredient')
    assert(not input:canAddItem(topping),'native-unavailable ingredient was admitted: '..blocked)
   end
   topping.blocked=nil;ui:invalidateInputCaches();ui:getInputList('Ingredient')
   local data=assert(ui:getCachedGroupData(topping,'Ingredient'))
   local full,total=data.fullUses,data.totalUses;data.fullUses,data.totalUses=0,0
   assert(not input:canAddItem(topping),'empty portion group was admitted')
   data.fullUses,data.totalUses=full,total
   PJCK_Config.get().portionPolicy='full_only';data.fullUses=0
   assert(not input:canAddItem(topping),'full-only portion rule was bypassed')
   data.fullUses=full;PJCK_Config.get().portionPolicy=savedPolicy
   if counts[1]+counts[2]>0 then
    ui.recipe.minimumWater=.5;base.fixtureFluid={getAmount=function()return 0 end,getCapacity=function()return 1 end}
    assert(info:isNeedWater(base,ui.recipe)and input:canAddItem(topping)==original(input,topping),
     'unmet native water prerequisite escaped original UI permission')
    ui.recipe.minimumWater=nil;base.fixtureFluid=nil
   end
   info.contentType='showNutrition';base.kind='Sandwich';base.contained=4
   assert(not input:canAddItem(topping)and input:canAddItem(topping)==original(input,topping),'normal recipe MaxItems behavior changed')
   base.contained=3;assert(input:canAddItem(topping)==original(input,topping),'normal non-transition behavior changed')
  end
 end
 -- Unknown instance/class/config owners must keep the original refusal rather than gain permission.
 for _,changed in ipairs({'input-instance','info-instance','evo-instance','foreign-child','foreign-info','global-input',
  'global-info','global-evo','input-class','info-class','evo-class','config'})do
  local ui,input,seasoning,info,base,topping=setup(2,0)
  local restore
  if changed=='input-instance'then input.getSelectedCount=function()return 0 end
  elseif changed=='info-instance'then info.isAddOneFirst=function()return true end
  elseif changed=='evo-instance'then ui.getCookStatus=function()return 'addOneFirst'end
  elseif changed=='foreign-child'then ui.ingredientsPanel=seasoning
  elseif changed=='foreign-info'then info.EvoPanel={}
  elseif changed=='global-input'then local old=PJCK_InputPanel;PJCK_InputPanel={};restore=function()PJCK_InputPanel=old end
  elseif changed=='global-info'then local old=PJCK_CookingInfo;PJCK_CookingInfo={};restore=function()PJCK_CookingInfo=old end
  elseif changed=='global-evo'then local old=PJCK_EvoPanel;PJCK_EvoPanel={};restore=function()PJCK_EvoPanel=old end
  elseif changed=='input-class'then local old=PJCK_InputPanel.getMaxAvailableCount;PJCK_InputPanel.getMaxAvailableCount=function()return 1 end;restore=function()PJCK_InputPanel.getMaxAvailableCount=old end
  elseif changed=='info-class'then local old=PJCK_CookingInfo.isAddOneFirst;PJCK_CookingInfo.isAddOneFirst=function()return true end;restore=function()PJCK_CookingInfo.isAddOneFirst=old end
  elseif changed=='evo-class'then local old=PJCK_EvoPanel.getCookStatus;PJCK_EvoPanel.getCookStatus=function()return 'addOneFirst'end;restore=function()PJCK_EvoPanel.getCookStatus=old end
  else local old=PJCK_Config.get;PJCK_Config.get=function()return old()end;restore=function()PJCK_Config.get=old end end
  assert(input:canAddItem(topping)==original(input,topping)and not original(input,topping),'unknown '..changed..' gained first-addition permission')
  if restore then restore()end
 end
 reset();enabled,RecipeManager,ISInventoryPaneContextMenu.getContainers=savedEnabled,savedManager,savedContainers
 PJCK_Config.get().portionPolicy=savedPolicy
 print('PASS actual-source Cook rendered first-result permission, inherited metadata, native availability, capacity and unknown-owner guards in both settings')
end

local function cook()
    panel:addIngredients({{groupKey=group,panelType='Ingredient',recipeCompatible=true,recipeUse=5}},recipe,panel.baseItem)
    local first=queue.queue[1]; local book=tail(); first:start()
    assert(queue.queue[2].Type=='ISInventoryTransferAction' and queue.queue[3].Type=='ISQueueActionsAction' and queue.queue[4]==book)
    first:perform(); return queue.queue[1],book,first
end
-- Build unavailable rows through the actual UI source before root arrival.
-- Availability and physical item objects are native/Java boundary inputs only.
do
 local savedEnabled=enabled
 for _,queueMode in ipairs({true,false})do
  for _,cacheKind in ipairs({'available','group'})do
   for _,replica in ipairs({'same','clone'})do
   reset();enabled=queueMode;food.container=bag
   local floor={class='ItemContainer',getType=function()return 'floor'end,getParent=function()end,getContainingItem=function()end}
   local stale=item(floor,1200)
   local live=replica=='same'and stale or item(inventory,1200)
   for _,value in ipairs({stale,live})do value.getFullType=function()return 'Base.Pot'end;value.getType=function()return 'Pot'end end
   local scans=0
   local uiRecipe={getItemRecipe=recipe.getItemRecipe,getMaxItems=recipe.getMaxItems}
   function uiRecipe:getItemsCanBeUse(actor,base,containers)
    assert(actor==player and containers,'native availability lost its actor/container arguments')
    scans=scans+1
    return list(base==live and base:getContainer()==inventory and inventory:getItemById(base:getID())==base and {food}or {})
   end
   local requests={{groupKey='another-queued-group',panelType='Ingredient'}}
   local switches={[group]=food}
   local ui=setmetatable({player=player,baseItem=stale,recipe=uiRecipe,baseItemOriginalContainer=floor,
    pendingBaseItemTransferId=1200,pendingBaseItemTransferUntil=6000,
    preCookItems=requests,switchItems=switches,showPossible={Ingredient=false,Seasoning=false},
    inputGroupCache={Ingredient={},Seasoning={}},inputGroupCacheValid={Ingredient=false,Seasoning=false},
    Window={getAllItems=function()return list({food})end}},PJCK_EvoPanel)
   local before=ui:getInputList('Ingredient')
   assert(#before==0 and scans==1 and ui.cachedAvailableItems:size()==0 and ui.inputGroupCacheValid.Ingredient,
    'source did not prime its unavailable floor cache')
   if cacheKind=='available'then ui:invalidateGroupCache('Ingredient')end
   live.container=inventory;inventory.values={live}
   local rows=ui:getInputList('Ingredient')
   assert(#rows==1 and rows[1].usableItems[1]==food and rows[1].usableIds[food:getID()]
    and rows[1].item==food and rows[1].recipeCompatible and rows[1].totalUses>0,
    'same-ID root arrival left the source ingredient UI unavailable: '..cacheKind..' replica='..replica..' queue='..tostring(queueMode))
   assert(scans==2 and ui.baseItem==live and ui.cachedAvailableBaseId==1200 and ui.cachedAvailableRecipe==uiRecipe,
    'source UI did not recompute native availability once against canonical root')
   assert(ui.preCookItems==requests and requests[1].groupKey=='another-queued-group'and ui.switchItems==switches
    and switches[group]==food and ui.baseItemOriginalContainer==floor and ui.recipe==uiRecipe
    and ui.pendingBaseItemTransferUntil==6000,'UI recovery discarded logical requests, selection or return state')
   local available,groups=ui.cachedAvailableItems,ui.inputGroupCache
   assert(ui:getBaseItem()==live and ui:resolveCurrentBaseItem(true)==live,'source getter/resolver lost canonical root')
   ui:getInputList('Ingredient')
   assert(ui.cachedAvailableItems==available and ui.inputGroupCache==groups and scans==2,
    'stable canonical reference repeatedly invalidated input caches')
   assert(ui._toolkitCookRootCache.item==live and ui._toolkitCookRootCache.root==inventory,
    'canonical root proof did not record exact item/container')
   live.container=floor;inventory.values={}
   assert(ui:getBaseItem()==live and ui._toolkitCookRootCache==nil and scans==2,
    'leaving root failed to clear proof or changed original getter/availability behavior')
   live.container=inventory;inventory.values={live}
   local again=ui:getInputList('Ingredient')
   assert(#again==1 and again[1].usableItems[1]==food and scans==3,
    'same exact object returning to root did not create one new cache generation')
   ui:getBaseItem();ui:getInputList('Ingredient')
   assert(scans==3 and ui.preCookItems==requests and ui.switchItems==switches,
    'repeated proof reads rescanned or discarded logical requests')
   end
  end
 end
 reset();enabled=savedEnabled
 print('PASS actual-source same-object/clone root generations recover cached unavailable/valid-empty-group UI exact food after root arrival in both settings')
end

-- Floor packets can leave the selected proxy's container nonnil while the
-- authoritative same-ID replica has already arrived in root. Execute the real
-- producer and native Lua start validator, without refreshing the panel first.
do
 local saved={enabled=enabled,base=panel.baseItem,source=panel.baseItemOriginalContainer,
  pendingId=panel.pendingBaseItemTransferId,deadline=panel.pendingBaseItemTransferUntil,
  contains=inventory.contains,consumed=consumed,result=recipe.getResultItem,groups=panel.inputGroupCache,groupValid=panel.inputGroupCacheValid}
 inventory.contains=function(self,target)for _,value in ipairs(self.values)do if value==target then return true end end;return false end
 recipe.getResultItem=function()return 'Pot'end
 local floor={class='ItemContainer',getType=function()return 'floor'end,getParent=function()end,getContainingItem=function()end,
  contains=function()return false end,getItems=function()return list({})end,getItemById=function()end}
 for _,queueMode in ipairs({true,false})do
  reset();enabled=queueMode;food.container=bag;panel.inputGroupCache=saved.groups
  local stale,live=item(floor,12),item(inventory,12)
  for _,value in ipairs({stale,live})do value.getFullType=function()return 'Base.Pot'end;value.getType=function()return 'Pot'end end
  inventory.values={live};panel.baseItem=stale;panel.baseItemOriginalContainer=floor
  panel.pendingBaseItemTransferId=12;panel.pendingBaseItemTransferUntil=6000
  local pickup,book=cook()
  assert(pickup.Type=='ISInventoryTransferAction'and pickup.item==food,'source did not queue ingredient pickup')
  pickup:perform();inventory.values={live,food}
  assert(food:getContainer()==inventory and stale:getContainer()==floor,'fixture did not reach post-pickup stale-floor state')
  local command=queue.queue[1];command:start()
  local add=queue.queue[2]
  if not add or add.Type~='ISAddItemInRecipe'then
   -- Diagnostic RED path: let the unchanged source exhaust its own retry window.
   -- No recipe effect is supplied by the fixture; only wall-clock/UI boundaries
   -- are observed, as in the existing source transfer-timeout regressions.
   assert(ISAddItemInRecipe:new(player,recipe,live,food):isValidStart(),'canonical root recipe was already unusable')
   local priorClock,priorHalo=getTimestampMs,HaloTextHelper
   local now,notices,retries=100,0,0
   getTimestampMs=function()return now end
   HaloTextHelper={addBadText=function()notices=notices+1 end}
   command:perform()
   while queue.queue[1]and queue.queue[1]~=book and retries<80 do
    local action=queue.queue[1];now=now+500;retries=retries+1
    action:start();action:perform()
   end
   getTimestampMs,HaloTextHelper=priorClock,priorHalo
   assert(notices==1 and consumed==saved.consumed and queue.queue[1]==book,
    'source retry failure did not stay bounded without applying recipe effects')
   error('stale-nonnull floor cache: ingredient reached root, native root recipe valid, source retried '..retries..' actions then NotAvailable='..notices..'; queue='..tostring(queueMode))
  end
  assert(add.baseItem==live and add.usedItem==food,'native evolved producer selected a substitute base or ingredient')
  assert(add:isValidStart(),'actual native Lua recipe start rejected canonical root base')
  assert(panel.baseItem==live and panel.recipe==nil and panel.baseItemOriginalContainer==floor
   and panel.pendingBaseItemTransferUntil==6000,'canonicalization changed source selection bookkeeping')
  command:perform();add:perform();add:complete()
  local post=queue.queue[1];assert(post.Type=='ISQueueActionsAction','source post-use command disappeared')
  post:start();post:perform()
  local back=queue.queue[1]
  assert(back.Type=='ISInventoryTransferAction'and back.item==food and back.destContainer==bag,'source leftover return changed')
  back:perform()
  assert(food:getContainer()==bag and queue.queue[1]==book,'source sequence lost its independent tail')
  assert(consumed==saved.consumed+1,'source apply did not execute exactly once')
  consumed=saved.consumed
  reset();enabled=queueMode;panel.baseItem=live;panel.baseItemOriginalContainer=floor
  assert(panel:queueBaseItemReturn(floor),'source return producer rejected canonical root pot')
  local returning=queue.queue[1]
  assert(returning.item==live and returning.destContainer==floor and returning.onCompleteFunc
   and returning.onCompleteArgs[1]==returning and returning.onCompleteArgs[2]==panel,
   'source remembered floor return or completion arguments changed')
 end
 reset();enabled=saved.enabled;food.container=bag;panel.baseItem=saved.base;panel.baseItemOriginalContainer=saved.source
 panel.pendingBaseItemTransferId,panel.pendingBaseItemTransferUntil=saved.pendingId,saved.deadline
 panel.inputGroupCache,panel.inputGroupCacheValid=saved.groups,saved.groupValid
 inventory.contains,recipe.getResultItem,consumed=saved.contains,saved.result,saved.consumed
 print('PASS actual-source stale-nonnull floor pot -> ingredient pickup -> same-ID root native apply/leftover/return producer in both settings')
end

-- The actual source refresh must keep a selected exact replica, not a wall-clock
-- grace period. Input containers/native bindings are fixture boundary state only.
do
 local savedClock,savedManager,savedContainers,savedActions=getTimestampMs,RecipeManager,ISInventoryPaneContextMenu.getContainers,player.getCharacterActions
 local savedGet,savedRootLookup,savedDead,savedContains=PJCK_Config.get,inventory.getItemById,player.isDead,inventory.contains
 inventory.contains=function(self,target)for _,value in ipairs(self.values)do if value==target then return true end end;return false end
 local now=6001;getTimestampMs=function()return now end
 local parent={class='IsoObject',getSquare=function()return square end,getObjectIndex=function()return 1 end}
 local source={class='ItemContainer',values={}}
 function source:getType()return 'stove'end
 function source:getContainingItem()end
 function source:getParent()return parent end
 function source:getSourceGrid()return square end
 function source:getItems()return list(self.values)end
 function source:contains(target)for _,value in ipairs(self.values)do if value==target then return true end end;return false end
 function source:getItemById(id)for _,value in ipairs(self.values)do if value:getID()==id then return value end end end
 parent.getContainerIndex=function(_,value)return value==source and 0 or -1 end
 parent.getContainerByIndex=function(_,index)return index==0 and source or nil end
 local containers=list({inventory,source})
 ISInventoryPaneContextMenu.getContainers=function()return containers end
 local recipe={};RecipeManager={getEvolvedRecipe=function()return list({recipe})end}
 local function setup(queueMode)
  reset();enabled=queueMode;now=6001;source.values={}
  local old,live=item(nil,600),item(inventory,600)
  local notifications={containers=0,base=0,recipe=0}
  local widget={onUpdateContainers=function()notifications.containers=notifications.containers+1 end,
   onUpdateBaseItem=function()notifications.base=notifications.base+1 end,onUpdateRecipe=function()notifications.recipe=notifications.recipe+1 end}
  local panel=setmetatable({player=player,baseItem=old,recipe=recipe,baseItemOriginalContainer=source,
   pendingBaseItemTransferId=600,pendingBaseItemTransferUntil=6000,pendingBaseItemReplacement=nil,
   ingredientsPanel=widget,seasoningsPanel=widget,preCookItems={},switchItems={},cachedAvailableItems={}},PJCK_EvoPanel)
  return panel,old,live,notifications
 end
 for _,queueMode in ipairs({true,false})do
  for _,preference in ipairs({'false','nil'})do
   local panel,old,live=setup(queueMode);old.container=source;inventory.values={live}
   local result
   if preference=='false'then result=panel:resolveCurrentBaseItem(false)else result=panel:resolveCurrentBaseItem()end
   assert(result==old and panel.baseItem==old,'nonpreferred resolver changed its original nonnil-cache semantics')
  end
  do
   local panel,old,live=setup(queueMode);old.container=source;inventory.values={live}
   assert(panel:resolveCurrentBaseItem(true)==live and panel.baseItemOriginalContainer==source
    and panel.recipe==recipe and panel.pendingBaseItemTransferUntil==6000,'preferred resolver lost exact root identity or source bookkeeping')
  end
  do
   local panel,old=setup(queueMode);old.container=nil;source.values={old}
   assert(panel:resolveCurrentBaseItem(true)==old,'original accessible-source resolver fallback disappeared')
  end
  do
   local panel,old=setup(queueMode)
   local dish=item(inventory,800);dish.getFullType=function()return 'Base.Result'end;inventory.values={dish}
   panel.pendingBaseItemReplacement={expectedId=800,expectedFullType='Base.Result',beforeIds={[600]=true},['until']=12000}
   assert(panel:resolveCurrentBaseItem(true)==dish and panel.baseItemOriginalContainer==source
    and panel.pendingBaseItemReplacement==nil,'original pending native replacement resolver changed')
  end
  do
   local panel,old,live=setup(queueMode);old.container=source;inventory.values={live}
   local callback=PJCK_EvoPanel.resolveCurrentBaseItem
   local calls=0;PJCK_EvoPanel.resolveCurrentBaseItem=function(self,...)calls=calls+1;return callback(self,...)end
   local result=panel:resolveCurrentBaseItem(true)
   PJCK_EvoPanel.resolveCurrentBaseItem=callback
   assert(calls==1 and result==old and panel.baseItem==old,'unreviewed late resolver wrapper obtained canonicalization')
  end
  for _,changed in ipairs({'getBaseItem','getInputList','invalidateInputCaches'})do
   local panel,old,live=setup(queueMode);old.container=source;inventory.values={live}
   panel.inputGroupCacheValid={Ingredient=true,Seasoning=true}
   panel._pjckFoodSafetySignature=panel:getFoodSafetyKnowledgeSignature()
   panel._pjckCompatRevision=PJCK_Compat and PJCK_Compat.getRevision and PJCK_Compat.getRevision()or 0
   local groups=panel.inputGroupCache
   local callback=PJCK_EvoPanel[changed]
   PJCK_EvoPanel[changed]=function(self,...)return callback(self,...)end
   assert(panel:getBaseItem()==old and #panel:getInputList('Ingredient')==0 and panel.baseItem==old
    and panel.inputGroupCache==groups,'unreviewed late UI callback obtained canonicalization: '..changed)
   PJCK_EvoPanel[changed]=callback
  end
  do
   local panel,old,live=setup(queueMode);panel.baseItem=live;inventory.values={live}
   panel:getBaseItem()
   local groups=panel.inputGroupCache
   local getInventory=player.getInventory
   local other={class='ItemContainer',values={live},getItemById=inventory.getItemById,contains=inventory.contains}
   player.getInventory=function()return other end;live.container=other
   local result=panel:getBaseItem()
   player.getInventory=getInventory;live.container=inventory
   assert(result==live and panel._toolkitCookRootCache.root==other and panel.inputGroupCache~=groups,
    'changing actual actor root failed to create a new canonical cache generation')
  end
  for _,timestamp in ipairs({6001,6000})do
   for _,staleRoot in ipairs({false,true})do
    local panel,old,live,notifications=setup(queueMode);now=timestamp
    old.container=staleRoot and inventory or nil;inventory.values={live}
    panel:setContainers(containers)
    assert(panel.baseItem==live and panel.recipe==recipe and panel.baseItemOriginalContainer==source,
     'same-ID/type direct-root replica was cleared at '..timestamp..' queue='..tostring(queueMode))
    assert(panel.pendingBaseItemTransferUntil==6000 and panel.cachedAvailableItems==nil and notifications.containers==2,
     'exact-root normalization changed deadline or skipped source refresh side effects')
    panel:setBaseItem(nil)
    assert(panel.baseItem==nil and panel.recipe==nil and panel.baseItemOriginalContainer==nil,'explicit user clear was suppressed')
   end
  end
  do
   local panel,old,live=setup(queueMode);inventory.values={live}
   local callback=PJCK_EvoPanel.setContainers
   local calls=0
   PJCK_EvoPanel.setContainers=function(self,...)calls=calls+1;return callback(self,...)end
   panel:setContainers(containers)
   PJCK_EvoPanel.setContainers=callback
   assert(calls==1 and panel.baseItem==nil,'unreviewed late class wrapper obtained exact-root normalization')
  end
  -- Original grace-period and visible-source behavior stays authoritative when
  -- no exact root replica is available; this is not a new retry scheduler.
  for _,timestamp in ipairs({6000,6001})do
   local panel,old=setup(queueMode);now=timestamp
   panel:setContainers(containers)
   assert((timestamp==6000 and panel.baseItem==old)or(timestamp==6001 and panel.baseItem==nil),
    'missing-root deadline behavior changed')
  end
  do
   local panel,old=setup(queueMode);old.container=source;source.values={old}
   panel:setContainers(containers)
   assert(panel.baseItem==old and panel.recipe==recipe,'visible source item was cleared at expiry')
  end
  for _,case in ipairs({'missing','wrong-id','wrong-type','wrong-container','nonmember','dead','unknown-panel','unknown-config','new-selection'})do
   local panel,old,live=setup(queueMode)
   if case=='wrong-id'then live.id=601;inventory.values={live}
   elseif case=='wrong-type'then live.getFullType=function()return 'Base.Foreign'end;inventory.values={live}
   elseif case=='wrong-container'then live.container=source;inventory.values={live}
   elseif case=='nonmember'then inventory.getItemById=function()return live end;inventory.values={}
   elseif case=='dead'then inventory.values={live};player.isDead=function()return true end
   elseif case=='unknown-panel'then inventory.values={live};panel.getRecipe=function()return recipe end
   elseif case=='unknown-config'then inventory.values={live};PJCK_Config.get=function()error('unreviewed config getter')end
   elseif case=='new-selection'then
    local replacement=item(inventory,700);inventory.values={live,replacement};panel.baseItem=replacement
   end
   local marker={item=old,root=source};panel._toolkitCookRootCache=marker
   if case~='new-selection'then
    old.container=source
    assert(panel:getBaseItem()==old and panel.baseItem==old,'unproven getter repaired cached proxy: '..case)
    if case=='dead'or case=='unknown-panel'or case=='unknown-config'then
     assert(panel._toolkitCookRootCache==marker,'untrusted/dead owner mutated root proof')
    else assert(panel._toolkitCookRootCache==nil,'missing/foreign exact root retained canonical proof: '..case)end
    assert(panel:resolveCurrentBaseItem(true)==old and panel.baseItem==old,'unproven resolver repaired cached proxy: '..case)
    old.container=nil
   else
    assert(panel:resolveCurrentBaseItem(true):getID()==700,'resolver resurrected previous selection')
   end
   panel:setContainers(containers)
   if case=='new-selection'then assert(panel.baseItem:getID()==700,'old pending replica replaced new user selection')
   else assert(panel.baseItem==nil,'missing/foreign/unreviewed base was resurrected: '..case)end
   PJCK_Config.get,inventory.getItemById,player.isDead=savedGet,savedRootLookup,savedDead
  end
  -- Pending native evolved-recipe replacement retains its original source resolver
  -- and takes precedence even if an old-type replica still exists in root.
  for _,oldStillPresent in ipairs({false,true})do
   local panel,old,live=setup(queueMode)
   local dish=item(inventory,800);dish.getFullType=function()return 'Base.Result'end
   inventory.values=oldStillPresent and {live,dish}or {dish}
   panel.pendingBaseItemReplacement={expectedId=800,expectedFullType='Base.Result',beforeIds={[600]=true},['until']=12000}
   panel:setContainers(containers)
   assert(panel.baseItem==dish and panel.recipe==recipe and panel.baseItemOriginalContainer==source
    and panel.pendingBaseItemReplacement==nil,'native recipe replacement/return bookkeeping changed')
  end
 end
 reset();getTimestampMs,RecipeManager,ISInventoryPaneContextMenu.getContainers,player.getCharacterActions=savedClock,savedManager,savedContainers,savedActions
 inventory.contains=savedContains
 print('PASS actual-source Cook exact root cache, expiry, explicit clear, replacement and unknown callback guards in both settings')
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
do
    -- Use the selected source's real settings helpers and deferred finalizer, including
    -- replacement/return failures; these checks must not substitute callback bodies.
    local previousClock,previousHalo=getTimestampMs,HaloTextHelper
    local now,notices=100,0
    getTimestampMs=function() return now end
    HaloTextHelper={addBadText=function() notices=notices+1 end}
    assert(PJCK_Config.getBaseItemHandling()=='keep_inventory' and not PJCK_Config.shouldReturnBaseItemToSource(),
        'actual Project Cook config defaults to retaining the base in inventory')
    local foreign={class='ItemContainer',getParent=function() end,getType=function() return 'none' end,getContainingItem=function() end}
    local function settings(value)
        PJCK_Config.get().baseItemHandling=value
        assert(PJCK_Config.shouldReturnBaseItemToSource()==(value=='return_source'))
    end
    local function expand(action)
        assert(queue.queue[1]==action and action.Type=='ISQueueActionsAction')
        action:start()
        local size=#queue.queue
        action:start()
        assert(#queue.queue==size,'repeated source command start cannot duplicate a return or retry')
        action:perform()
    end
    local function finalizer(value,container)
        reset(); now,notices=100,0; settings('return_source')
        panel.baseItem=value or item(inventory,21000)
        panel.baseItemOriginalContainer=container or bag
        panel.pendingBaseItemReplacement=nil
        panel.inputGroupCache={Ingredient={none={usableItems={}}}}
        panel:addIngredients({{groupKey='none',panelType='Ingredient',recipeCompatible=true}},recipe,panel.baseItem)
        assert(#queue.queue==2,'return-source setting appends one finalizer after the requested ingredient')
        local first=queue.queue[1]
        local later=tail()
        expand(first)
        assert(queue.queue[1].Type=='PJCK_SequenceWaitAction')
        queue.queue[1]:perform()
        assert(queue.queue[1].Type=='ISQueueActionsAction' and queue.queue[2]==later)
        return queue.queue[1],later
    end
    local function waitRetry(later)
        assert(queue.queue[1].Type=='PJCK_SequenceWaitAction' and queue.queue[3]==later,
            'a bounded return retry stays ahead of independent work')
        queue.queue[1]:perform()
        return queue.queue[1]
    end
    reset(); settings('return_source')
    panel.baseItem=item(inventory,21001); panel.baseItemOriginalContainer=bag
    assert(panel:queueBaseItemReturn(bag),'new public Project Cook return producer queues its transfer')
    local direct=queue.queue[1]
    assert(definitions.inspect(direct) and direct.destContainer==bag,'public return retains source ownership and exact destination')
    local config=PJCK_Config
    for _,name in ipairs({'get','getBaseItemHandling','shouldReturnBaseItemToSource','load','validate'}) do
        local callback=config[name]
        config[name]=function() error('unreviewed Project Cook setting helper') end
        assert(not definitions.inspect(direct),'changed Project Cook '..name..' helper rejects an existing source contract')
        config[name]=callback
        assert(definitions.inspect(direct),'restoring the exact setting helper restores the source contract')
    end
    PJCK_Config={}
    assert(not definitions.inspect(direct),'replaced Project Cook config table cannot inherit a source contract')
    PJCK_Config=config
    settings('keep_inventory')
    assert(definitions.inspect(direct),'ordinary settings data changes preserve source method identity')
    direct:perform()
    assert(panel.baseItem==direct.item and direct.item.container==bag,'native return completion keeps the returned base selected')

    local finish,later=finalizer()
    local base=panel.baseItem
    panel.baseItemOriginalContainer=foreign
    expand(finish)
    local returned=queue.queue[1]
    assert(returned.Type=='ISInventoryTransferAction' and returned.item==base and returned.destContainer==bag
        and definitions.inspect(returned),'automatic return uses the sequence-captured source and audited transfer')
    returned:perform()
    assert(base.container==bag and panel.baseItem==base and panel.baseItemOriginalContainer==bag and queue.queue[1]==later,
        'automatic return settles once, preserves selection and leaves independent work queued')
    for _,destination in ipairs({bag,foreign}) do
        finish,later=finalizer()
        panel.baseItem.container=destination
        expand(finish)
        assert(queue.queue[1].Type=='PJCK_SequenceWaitAction' and queue.queue[2]==later,
            'already returned and unexpected third-container bases produce no extra transfer')
        queue.queue[1]:perform()
        assert(queue.queue[1]==later and notices==0)
    end

    finish,later=finalizer()
    local stale=panel.baseItem
    stale.container=nil
    expand(finish); finish=waitRetry(later)
    local replacement=item(inventory,stale.id)
    inventory.values={replacement}
    expand(finish)
    returned=queue.queue[1]
    assert(returned.Type=='ISInventoryTransferAction' and returned.item==replacement and returned.destContainer==bag,
        'base return retry resolves the live inventory replacement instead of returning its stale proxy')
    returned:perform()
    assert(panel.baseItem==replacement and replacement.container==bag and stale.container==nil and queue.queue[1]==later,
        'replacement return preserves the authoritative inventory identity and source endpoint')

    finish,later=finalizer()
    panel.baseItem=nil
    for attempt=1,21 do
        expand(finish)
        if attempt<=20 then
            finish=waitRetry(later)
        else
            assert(queue.queue[1].Type=='PJCK_SequenceWaitAction' and queue.queue[2]==later and notices==1,
                'missing base stops after twenty retries with one sequence notice')
            queue.queue[1]:perform()
        end
    end
    assert(queue.queue[1]==later,'exhausted base return does not clear independent work')
    finish,later=finalizer(); panel.baseItem=nil
    expand(finish); finish=waitRetry(later); now=8101
    expand(finish)
    assert(queue.queue[1].Type=='PJCK_SequenceWaitAction' and queue.queue[2]==later and notices==1,
        'base return also expires at its eight-second deadline before the retry count')
    queue.queue[1]:perform()

    finish,later=finalizer(); panel.baseItem=nil
    expand(finish); finish=waitRetry(later)
    operations.invalidate(finish.toolkitQueueOperation)
    expand(finish)
    assert(queue.queue[1]==later and notices==0,'cancelled base-return retry cannot append another wait, return or notification')

    reset(); settings('keep_inventory'); panel.baseItem=item(inventory,21003); panel.baseItemOriginalContainer=bag
    panel.inputGroupCache={Ingredient={none={usableItems={}}}}
    panel:addIngredients({{groupKey='none',panelType='Ingredient',recipeCompatible=true}},recipe,panel.baseItem)
    assert(#queue.queue==1,'default keep-inventory setting does not append automatic return work')

    -- Exercise the actual ingredient retry deadline independently of the return path.
    reset(); now,notices=100,0; food.container=bag; panel.baseItem=item(inventory,21004)
    panel.inputGroupCache={Ingredient={[group]={usableItems={food}}}}
    local delayed,reader=cook(); delayed.fixtureDelay=true; delayed:perform()
    local retry=queue.queue[1]
    expand(retry); retry=waitRetry(reader); now=5101
    expand(retry)
    assert(queue.queue[1].Type=='PJCK_SequenceWaitAction' and queue.queue[2]==reader and notices==1,
        'ingredient retry expires at five seconds without consuming or clearing independent work')
    queue.queue[1]:perform()
    assert(food.container==bag and consumed==2)
    reset(); now,notices=100,0; food.container=bag; panel.baseItem=item(inventory,21005)
    panel.inputGroupCache={Ingredient={[group]={usableItems={food}}}}
    delayed,reader=cook(); delayed.fixtureDelay=true; delayed:perform(); retry=queue.queue[1]
    for attempt=1,21 do
        expand(retry)
        if attempt<=20 then retry=waitRetry(reader)
        else
            assert(queue.queue[1].Type=='PJCK_SequenceWaitAction' and queue.queue[2]==reader and notices==1,
                'ingredient retries also stop after twenty attempts with one notice')
            queue.queue[1]:perform()
        end
    end
    assert(queue.queue[1]==reader and food.container==bag and consumed==2)
    settings('keep_inventory'); getTimestampMs,HaloTextHelper=previousClock,previousHalo
    reset()
end
local hooks={table.insert,ISTimedActionQueue.add,ISTimedActionQueue.addAfter,ISTimedActionQueue.queueActions,ISContextMenu.addOption}
local old=NEQ_Dresser.resolve; NEQ_Dresser.resolve=function() error('changed producer') end
assert(not pcall(function() NEQ_Dresser.wear(player,0,{}) end)); NEQ_Dresser.resolve=old
for i,value in ipairs({table.insert,ISTimedActionQueue.add,ISTimedActionQueue.addAfter,ISTimedActionQueue.queueActions,ISContextMenu.addOption}) do assert(value==hooks[i],'source hooks restore on error') end
reset(); dirty=item(inventory,14); inventory.values={dirty}; player.primary=dirty; dirty.activatable,dirty.activated=true,true
session=TidyFixture.captureSession(player); session.armed,session.restoreHands=true,true; TidyFixture.sessions[player]=session
local firstTail,secondTail=tail(),tail(); player.primary=nil; dirty.activated=false; firstTail:perform(); secondTail:perform(); tickTidy(); tickTidy()
local sharedEquip,sharedActivate=queue.queue[1],queue.queue[2]
assert(sharedEquip.Type=='ISEquipWeaponAction' and definitions.inspect(sharedEquip).cancelOperation==false
    and sharedEquip.toolkitQueueOperation~=firstTail.toolkitQueueOperation
    and sharedEquip.toolkitQueueOperation~=secondTail.toolkitQueueOperation,
    'mixed equipment restore has a protected shared cleanup contract')
operations.invalidate(firstTail.toolkitQueueOperation)
sharedEquip:perform(); sharedActivate:perform(); sharedActivate:complete()
assert(dirty.activated and dirty.activationChanges==1 and TidyFixture.sessions[player]==nil and TidyFixture.restoring[player],
    'actual native activation completion still runs after a mixed owner cancellation')
tickTidy(); tickTidy()
assert(TidyFixture.restoring[player]==nil and TidyFixture.restoreFloor[player]==nil,
    'partial task cancellation preserves native completion and native Tidy cleanup')

-- P4 hand/activation cleanup uses the native completion boundary even after its original owner is cancelled.
do
    local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    local client,actions,completed=isClient,player.getCharacterActions,queue.onCompleted
    local callbacks=0
    local function restoreEquipment(mixed)
        reset();player.secondary=nil
        local torch=item(inventory,143);torch.activatable,torch.activated=true,true
        inventory.values={torch};player.primary=torch
        local captured=TidyFixture.captureSession(player)
        captured.armed,captured.restoreHands=true,true;TidyFixture.sessions[player]=captured
        local owner=tail();local other=mixed and tail()or nil
        player.primary=nil;torch.activated=false
        owner:perform();if other then other:perform()end;tickTidy();tickTidy()
        local equip,activate=queue.queue[1],queue.queue[2]
        assert(equip.Type=='ISEquipWeaponAction'and activate.Type=='P4RestoreAction')
        for _,action in ipairs({equip,activate})do
            local contract,id=definitions.inspect(action)
            assert(contract and id=='compat.tidy-equipment','P4 equipment did not select its shared producer')
            assert((contract.cancelOperation==false)==mixed,'P4 shared cleanup cancellation contract changed')
        end
        assert(equip.toolkitQueueOperation==activate.toolkitQueueOperation)
        assert((equip.toolkitQueueOperation==owner.toolkitQueueOperation)==not mixed)
        return torch,owner,equip,activate
    end
    queue.onCompleted=function(self,action)
        if lifecycle.current(player)==action then
            assert(not operations.deferCompletion(self,action),'P4 equipment acquired legacy completion scope')
            callbacks=callbacks+1
        end
        return completed(self,action)
    end
    for _,mp in ipairs({false,true})do
        for _,mixed in ipairs({false,true})do
            for _,cancelled in ipairs({false,true})do
                local torch,owner,equip,activate=restoreEquipment(mixed)
                local unrelated=tail()
                assert(unrelated.toolkitQueueOperation~=equip.toolkitQueueOperation)
                if cancelled then operations.invalidate(owner.toolkitQueueOperation)end
                isClient=function()return mp end
                for index,action in ipairs({equip,activate})do
                    local following=index==1 and activate or unrelated
                    local token=action.toolkitQueueOperation
                    local removed=false;action.action={};queue.current=action
                    player.getCharacterActions=function()return list(removed and {}or{action.action})end
                    -- Model the authoritative Host effect separately from its client perform boundary.
                    if mp then action:complete()end
                    assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
                    assert(queue.current==action and queue.queue[1]==action and queue.queue[2]==following
                        and action.toolkitQueueOperation==token,'P4 cleanup lost native ownership or its independent tail')
                    if not mp then
                        assert(lifecycle.flush(queue)=='waiting','SP equipment advanced before its effect')
                        assert(lifecycle.begin(action,'complete'));action:complete();lifecycle.finish(action,'complete',true)
                    end
                    assert(lifecycle.flush(queue)=='waiting','P4 equipment advanced before native removal')
                    removed=true
                    assert(lifecycle.flush(queue)=='completed'and queue.current==following and lifecycle.flush(queue)==nil,
                        'P4 cleanup advanced twice or lost the following action')
                end
                assert(player.primary==torch and torch.activated and torch.activationChanges==1,
                    'P4 hand/activation effects did not complete exactly once')
                isClient=client;player.getCharacterActions=actions;unrelated:perform();tickTidy();tickTidy()
                assert(TidyFixture.restoring[player]==nil and TidyFixture.restoreFloor[player]==nil)
            end
        end
    end
    assert(callbacks==16,'P4 equipment lifecycle gates missed a native return')
    queue.onCompleted=completed
    for _,field in ipairs({'primary','twoHands','alwaysTurnOn','onCompleteFunc','start'})do
        local _,_,equip=restoreEquipment(true)
        local original=equip[field]
        equip[field]=(field=='onCompleteFunc'or field=='start')and function()end or not original
        assert(not definitions.inspect(equip),'P4 equip accepted changed '..field)
        equip[field]=original;assert(definitions.inspect(equip))
        while queue.queue[1]do local action=queue.queue[1];action:complete();action:perform()end
        tickTidy();tickTidy()
    end
    local _,_,_,activate=restoreEquipment(true)
    activate.activated=false
    assert(not definitions.inspect(activate),'P4 activation accepted a changed effect')
    activate.activated=true
    while queue.queue[1]do local action=queue.queue[1];action:complete();action:perform()end
    tickTidy();tickTidy()
end

-- Empty-hand Tidy cleanup shares the native boundary; held/worn overlaps and attachments retain fallback.
do
    local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    local client,actions,completed=isClient,player.getCharacterActions,queue.onCompleted
    local callbacks=0
    local function restoreEmptyHands(mixed,slot,worn,attached,kind)
        reset();player.primary,player.secondary=nil,nil
        local tool=item(inventory,148);inventory.values={tool}
        tool.fixtureCart,tool.fixtureHeavy=kind=='cart',kind=='heavy'
        local captured=TidyFixture.captureSession(player)
        captured.armed,captured.restoreHands=true,true;TidyFixture.sessions[player]=captured
        local owner=tail();local other=mixed and tail()or nil
        if slot~='secondary'then player.primary=tool end
        if slot=='secondary'or slot=='both'then player.secondary=tool end
        local getWorn,hotbar=player.getWornItems,getPlayerHotbar
        if worn then player.getWornItems=function()return {size=function()return 0 end,contains=function(_,value)return value==tool end}end end
        if attached then getPlayerHotbar=function()return {isItemAttached=function()return true end}end end
        owner:perform();if other then other:perform()end;tickTidy();tickTidy()
        player.getWornItems,getPlayerHotbar=getWorn,hotbar
        local action=queue.queue[1]
        assert(action and action.Type=='ISUnequipAction','actual P4 source did not queue an empty-hand restore')
        return tool,owner,action
    end
    local function drain()
        while queue.queue[1]do local action=queue.queue[1];action:complete();action:perform()end
        tickTidy();tickTidy()
    end
    queue.onCompleted=function(self,action)
        if lifecycle.current(player)==action then
            assert(not operations.deferCompletion(self,action),'P4 unequip acquired legacy completion scope')
            callbacks=callbacks+1
        end
        return completed(self,action)
    end
    for _,mp in ipairs({false,true})do
        for _,mixed in ipairs({false,true})do
            for _,cancelled in ipairs({false,true})do
                for _,slot in ipairs({'primary','secondary','both'})do
                    local tool,owner,action=restoreEmptyHands(mixed,slot)
                    local contract,id=definitions.inspect(action)
                    assert(contract and id=='compat.tidy-equipment'and (contract.cancelOperation==false)==mixed,
                        'P4 hand unequip did not select the existing shared cleanup contract')
                    local following=tail();local syncs=player.equipSyncs or 0
                    assert((action.toolkitQueueOperation==owner.toolkitQueueOperation)==not mixed)
                    assert(action.toolkitQueueOperation~=following.toolkitQueueOperation)
                    if cancelled then operations.invalidate(owner.toolkitQueueOperation)end
                    local removed=false;action.action={};queue.current=action
                    player.getCharacterActions=function()return list(removed and {}or{action.action})end
                    isClient=function()return mp end
                    if mp then action:complete()end
                    assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
                    assert(queue.current==action and queue.queue[1]==action and queue.queue[2]==following,
                        'hand unequip advanced before its native effect/removal')
                    assert(lifecycle.flush(queue)=='waiting')
                    if not mp then
                        assert(player.primary==tool or player.secondary==tool,'SP unequip applied its effect during perform')
                        assert(lifecycle.begin(action,'complete'));action:complete();lifecycle.finish(action,'complete',true)
                    end
                    assert(player.primary==nil and player.secondary==nil and player.equipSyncs==syncs+1,
                        'native unequip must clear held items and sync exactly once')
                    assert(lifecycle.flush(queue)=='waiting','hand unequip ignored native removal')
                    removed=true
                    assert(lifecycle.flush(queue)=='completed'and queue.current==following and lifecycle.flush(queue)==nil,
                        'hand unequip completed twice or lost its independent tail')
                    isClient,player.getCharacterActions=client,actions
                    following:perform();tickTidy();tickTidy()
                    assert(TidyFixture.restoring[player]==nil and TidyFixture.restoreFloor[player]==nil)
                end
            end
        end
    end
    assert(callbacks==24,'hand unequip lifecycle missed a native return')
    queue.onCompleted=completed
    for _,field in ipairs({'reason','fromHotbar','hotbar','onCompleteFunc','start','item'})do
        local _,_,action=restoreEmptyHands(true,'primary')
        local original=action[field]
        action[field]=(field=='onCompleteFunc'or field=='start')and function()end
            or field=='item'and item(inventory,149)or field=='reason'and 'drop'or true
        assert(not definitions.inspect(action),'P4 hand unequip accepted changed '..field)
        action[field]=original;assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
        drain()
    end
    local _,_,action=restoreEmptyHands(true,'primary')
    local start=ISUnequipAction.start;ISUnequipAction.start=function()end
    assert(not definitions.inspect(action),'changed unequip class retained source permissions')
    ISUnequipAction.start=start;drain()
    local _,_,worn=restoreEmptyHands(true,'primary',true)
    assert(select(2,definitions.inspect(worn))=='compat.selected-chains','held/worn cleanup migrated without clothing verification')
    drain()
    local _,_,attached=restoreEmptyHands(true,'primary',false,true)
    assert(select(2,definitions.inspect(attached))=='compat.selected-chains','hotbar cleanup migrated without attachment verification')
    reset();tickTidy();tickTidy()
    local _,_,heavy=restoreEmptyHands(true,'primary',false,false,'heavy')
    assert(select(2,definitions.inspect(heavy))=='compat.selected-chains','heavy world-drop cleanup migrated without verification')
    reset();tickTidy();tickTidy()
    local methods={new=ISUnequipAction.new,complete=ISUnequipAction.complete}
    local wrapped={new=function(...)return methods.new(...)end,complete=function(...)return methods.complete(...)end}
    lateCartProof.unequipConstructors[methods.new],lateCartProof.unequipConstructors[wrapped.new]=true,true
    lateCartProof.unequipLatest=wrapped
    ISUnequipAction.new,ISUnequipAction.complete=wrapped.new,wrapped.complete
    for _,mp in ipairs({false,true})do
        local _,_,ordinary=restoreEmptyHands(true,'primary')
        assert(select(2,definitions.inspect(ordinary))=='compat.tidy-equipment','audited non-cart unequip wrapper lost P4 cleanup ownership')
        local following=tail();local removed=false;ordinary.action={};queue.current=ordinary
        player.getCharacterActions=function()return list(removed and {}or{ordinary.action})end
        isClient=function()return mp end
        if mp then ordinary:complete()end
        assert(lifecycle.begin(ordinary,'perform'));ordinary:perform();lifecycle.finish(ordinary,'perform',true)
        assert(queue.queue[1]==ordinary and queue.queue[2]==following and lifecycle.flush(queue)=='waiting')
        if not mp then
            assert(lifecycle.begin(ordinary,'complete'));ordinary:complete();lifecycle.finish(ordinary,'complete',true)
        end
        removed=true
        assert(player.primary==nil and lifecycle.flush(queue)=='completed'and queue.current==following and lifecycle.flush(queue)==nil)
        isClient,player.getCharacterActions=client,actions;following:perform();tickTidy();tickTidy()
    end
    for _,case in ipairs({'worn','attached','heavy'})do
        local _,_,unsupported=restoreEmptyHands(true,'primary',case=='worn',case=='attached',case)
        assert(not definitions.inspect(unsupported) and not compat.fixtureRegistries[1][unsupported],
            'late unequip wrapper expanded the previous fallback for '..case)
        reset();tickTidy();tickTidy()
    end
    local _,_,cart=restoreEmptyHands(true,'primary',false,false,'cart')
    assert(not definitions.inspect(cart),'cart unequip obtained the audited non-cart source contract')
    reset();tickTidy();tickTidy()
    lateCartProof.enabled=false
    local _,_,unknown=restoreEmptyHands(true,'primary')
    assert(not definitions.inspect(unknown),'changed Carts proof granted P4 unequip permissions')
    lateCartProof.enabled=true
    reset();ISUnequipAction.new,ISUnequipAction.complete=methods.new,methods.complete
    lateCartProof.unequipLatest=nil
end

-- Ordinary P4 clothing restores use real native WearClothing effects and the
-- shared removal boundary. Java worn/visual state and MP transport remain doubles.
do
    local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    local client,actions,completed=isClient,player.getCharacterActions,queue.onCompleted
    local getWorn,getWornItem,setWorn,visual,removeWorn=player.getWornItems,player.getWornItem,player.setWornItem,player.getHumanVisual,player.removeWornItem
    local oldGroup=player.getBodyLocationGroup
    local oldLoad,oldCapacity,oldAllowed=inventory.getCapacityWeight,inventory.getEffectiveCapacity,inventory.isItemAllowed
    local worn,writes,load,capacity,allowed,hair,exclusive,multi={},0,0,10,true,'CrewCut',false,false
    local resetModel=player.resetModel
    local visualState={getHairModel=function()return hair and {contains=function(_,needle)return hair:find(needle,1,true)~=nil end}end,
        setHairModel=function(_,value)hair=value end}
    local function flattenHeadwear(location)
        -- Java visual mutation remains a double; actual Lua Wear runs below.
        -- Normal Host authority never initializes render-only cached isoPlayer.
        -- MP completion here simulates that server; Lua Wear still flattens.
        if not isClient()and (location==ItemBodyLocation.HAT or location==ItemBodyLocation.FULL_HAT)
            and hair and hair:find('Mohawk',1,true)then hair='MohawkFlat'end
    end
    local group={getLocation=function(_,location)return location end,isMultiItem=function()return multi end,
        isExclusive=function()return exclusive end}
    player.getBodyLocationGroup=function()return group end
    inventory.getCapacityWeight=function()return load end
    inventory.getEffectiveCapacity=function()return capacity end
    inventory.isItemAllowed=function()return allowed end
    player.getWornItems=function()
        local entries={}
        for location,value in pairs(worn)do
            local loc,clothing=location,value
            entries[#entries+1]={getLocation=function()return loc end,getItem=function()return clothing end}
        end
        local values=list(entries)
        values.contains=function(_,wanted)for _,value in pairs(worn)do if value==wanted then return true end end;return false end
        return values
    end
    player.getWornItem=function(_,location)return worn[location]end
    player.setWornItem=function(_,location,value)worn[location]=value;writes=writes+1;flattenHeadwear(location)end
    player.removeWornItem=function(_,item)
        for location,value in pairs(worn)do if value==item then
            worn[location]=nil;writes=writes+1;flattenHeadwear(location)
            -- Java storage/effects are doubles: use the worst allowed increase
            -- from worn to unequipped weight, then native's second weight debit.
            load=load+item:getUnequippedWeight()
            if math.floor(load*100+0.5)/100+item:getUnequippedWeight()>capacity then
                for i,value in ipairs(inventory.values)do if value==item then table.remove(inventory.values,i);break end end
                item.container=nil
            end
        end end
    end
    player.getHumanVisual=function()return visualState end
    player.resetModel=function()end
    local function restoreClothing(mixed,kind,removal,setup)
        local ringing=kind and kind:match('^ringing%-')~=nil
        if ringing then kind=kind:sub(9)end
        local watchOverlap=kind and (kind:match('^watch%-held%-')or kind:match('^watch%-desired%-'))
        if watchOverlap then kind=kind:sub(7)end
        reset();worn={};writes=0;load,capacity,allowed,hair,exclusive,multi=0,10,true,'CrewCut',false,false
        player.primary,player.secondary=nil,nil
        local sock=item(inventory,14801);sock.class='Clothing';sock.getUnequippedWeight=function(self)return self.weight or 0.2 end;inventory.values={sock}
        if kind=='bag'then sock.class='InventoryContainer';sock.equippedAt='Back'
        elseif kind=='hat'then sock.location=ItemBodyLocation.HAT
        elseif kind=='full-hat'then sock.location=ItemBodyLocation.FULL_HAT
        elseif kind=='watch-left'or kind=='watch-right'then
            sock.class='AlarmClockClothing';sock.location=kind=='watch-left'and ItemBodyLocation.LEFT_WRIST or ItemBodyLocation.RIGHT_WRIST
            sock.alarmHour,sock.alarmMinute,sock.alarmSet=23,40,kind=='watch-left'
            sock.getHour=function(self)return self.alarmHour end;sock.getMinute=function(self)return self.alarmMinute end
            sock.isAlarmSet=function(self)return self.alarmSet end;sock.isRinging=function()return false end
        elseif kind=='primary'then sock.hasTag=function(_,tag)return tag==ItemTag.REPLACE_PRIMARY end
        elseif kind=='wearable'then sock.equippedAt='Back'
        elseif kind=='wearable-tag'then sock.hasTag=function(_,tag)return tag==ItemTag.WEARABLE end
        elseif kind=='attached'then sock.attachedSlot=1
        elseif kind=='heavy'then sock.fixtureHeavy=true
        elseif kind=='broken'then sock.broken=true
        elseif kind=='activated'then sock.activatable=true;sock.activated=true end
        if watchOverlap then
            sock.class='AlarmClockClothing';sock.location=ItemBodyLocation.LEFT_WRIST
            sock.alarmHour,sock.alarmMinute,sock.alarmSet=23,40,true
            sock.getHour=function(self)return self.alarmHour end;sock.getMinute=function(self)return self.alarmMinute end
            sock.isAlarmSet=function(self)return self.alarmSet end;sock.isRinging=function()return false end
        end
        local desired=kind and kind:match('^desired%-')
        if desired then
            if kind~='desired-both'then
                local other=item(inventory,14807);inventory.values[#inventory.values+1]=other
                if kind=='desired-primary'then player.secondary=other else player.primary=other end
            end
            assert(ISEquipWeaponAction:new(player,sock,50,kind~='desired-secondary',kind=='desired-both'):complete())
            assert(ISWearClothing:new(player,sock):complete())
            writes=0
        elseif not removal then worn[sock:getBodyLocation()]=sock end
        local captured=TidyFixture.captureSession(player)
        captured.armed,captured.restoreWorn=true,true;captured.restoreHands=desired and true or captured.restoreHands
        TidyFixture.sessions[player]=captured
        local owner=tail();local other=mixed and tail()or nil
        if desired then
            assert(ISUnequipAction:new(player,sock,50):complete())
            assert((kind=='desired-secondary'or not player.primary)and (kind=='desired-primary'or not player.secondary)
                and not worn[sock:getBodyLocation()])
            writes=0
        end
        worn=removal and {[sock:getBodyLocation()]=sock}or {}
        if kind and kind:match('^held') then
            -- Reach the overlap through native Wear, rather than directly seeding
            -- a dual worn/held state. Java hands/worn storage remains a double.
            worn={}
            if kind=='held-primary' or kind=='held-both' then player.primary=sock end
            if kind=='held-secondary' or kind=='held-both' or kind=='held-prefix' then player.secondary=sock end
            assert(ISWearClothing:new(player,sock,50):complete())
            assert(worn[sock:getBodyLocation()]==sock and (player.primary==sock or player.secondary==sock),
                'native ordinary Wear did not retain the held clothing overlap')
            writes=0
            local other=item(inventory,14803);inventory.values[#inventory.values+1]=other
            if not player.primary then player.primary=other end
            if not player.secondary then player.secondary=other end
        end
        if kind=='capacity-edge'then sock.weight=0.25;load,capacity=1,1.51 end
        if ringing then sock.isRinging=function()return true end end
        if setup then setup(sock)end
        owner:perform();if other then other:perform()end;tickTidy();tickTidy()
        local action
        for _,candidate in ipairs(queue.queue)do
            if candidate.Type==(removal and 'ISUnequipAction'or 'ISWearClothing')and candidate.item==sock then action=candidate end
        end
        assert(action,'actual P4 did not generate its exact clothing restore')
        return sock,owner,action
    end
    local callbacks=0
    queue.onCompleted=function(self,action)
        if lifecycle.current(player)==action then
            assert(not operations.deferCompletion(self,action),'ordinary clothing restore retained a legacy completion scope')
            callbacks=callbacks+1
        end
        return completed(self,action)
    end
    for _,removal in ipairs({false,true})do
    for _,kind in ipairs(removal and {'plain','hat','full-hat','watch-left','watch-right','capacity-edge','held-primary','held-secondary','held-both','held-prefix','watch-held-primary','watch-held-secondary','watch-held-both','ringing-watch-left','ringing-watch-held-both'} or {'plain','hat','full-hat','watch-left','watch-right','ringing-watch-left'})do
    for _,mode in ipairs({'sp','mp-early','mp-late'})do
        for _,mixed in ipairs({false,true})do for _,cancelled in ipairs({false,true})do
            local sock,owner,action=restoreClothing(mixed,kind,removal)
            local contract,id=definitions.inspect(action)
            assert(contract and id=='compat.tidy-equipment'and contract.items[sock:getID()]
                and contract.hands==player and (contract.cancelOperation==false)==mixed,'ordinary clothing restore lacks shared-boundary ownership')
            local following=tail();local removed=false;action.action={};queue.current=action
            local syncs=player.equipSyncs or 0
            if kind=='held-prefix' then
                -- The native fixture verifies P4's earlier hand-restoration
                -- producer. Its hand storage effect must not revoke adoption.
                player.secondary=item(inventory,14804)
                inventory.values[#inventory.values+1]=player.secondary
                assert(select(2,definitions.inspect(action))=='compat.tidy-equipment',
                    'earlier hand restoration revoked ordinary worn cleanup')
            end
            local expectedPrimary=player.primary~=sock and player.primary or nil
            local expectedSecondary=player.secondary~=sock and player.secondary or nil
            player.getCharacterActions=function()return list(removed and {}or{action.action})end
            isClient=function()return mode~='sp'end
            if cancelled then operations.invalidate(owner.toolkitQueueOperation)end
            if mode=='mp-early'then assert(action:complete())end
            assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
            assert(queue.current==action and queue.queue[1]==action and queue.queue[2]==following,
                'clothing perform advanced before native removal or lost its independent tail')
            assert(lifecycle.flush(queue)=='waiting')
            if mode=='sp'then
                assert(writes==0 and (worn[sock:getBodyLocation()]==sock)==removal,'SP clothing effect ran before native complete')
                assert(lifecycle.begin(action,'complete'));assert(action:complete());lifecycle.finish(action,'complete',true)
            elseif mode=='mp-late'then assert(action:complete())end
            assert(writes==1 and (worn[sock:getBodyLocation()]==sock)==not removal and sock:getContainer()==inventory and inventory:getItemById(sock:getID())==sock,
                'native clothing effect lost its exact slot/item or ran twice')
            assert(hair=='CrewCut','plain headwear cleanup changed hair')
            if kind:match('^watch%-')or kind:match('^ringing%-')then
                assert(sock:getHour()==23 and sock:getMinute()==40 and sock:isAlarmSet()==(kind~='watch-right')
                    and sock:isRinging()==(kind:match('^ringing%-')~=nil),
                    'native wristwatch cleanup altered its alarm configuration')
            end
            if removal then
                assert(player.primary==expectedPrimary and player.secondary==expectedSecondary and player.equipSyncs==syncs+1,
                    'ordinary worn/held removal suppressed or repeated native hand synchronization')
            end
            assert(lifecycle.flush(queue)=='waiting','clothing restore ignored native removal')
            removed=true
            assert(lifecycle.flush(queue)=='completed'and queue.current==following and lifecycle.flush(queue)==nil,
                'clothing restore advanced twice or lost the unrelated continuation')
            isClient,player.getCharacterActions=client,actions;following:perform();tickTidy();tickTidy()
            assert(not TidyFixture.restoring[player]and not TidyFixture.sessions[player])
        end end
    end
    end
    end
    assert(callbacks==252,'ordinary clothing/headwear/watch wear/removal boundary missed a hand/worn/single/mixed/cancel/MP-order combination')
    queue.onCompleted=completed
    -- A desired held/worn baseline is restored in the opposite direction to
    -- temporary clothing: native hands first, then Wear retains those hands.
    -- Inspect the same adopted Wear before and after every native hand effect.
    local desiredBoundaries=0
    for _,variant in ipairs({'desired-primary','desired-secondary','desired-both','watch-desired-primary','watch-desired-secondary','watch-desired-both','ringing-watch-desired-both'})do
    local kind=variant:gsub('^ringing%-',''):gsub('^watch%-','')
    for _,mode in ipairs({'sp','mp-early','mp-late'})do
    for _,mixed in ipairs({false,true})do for _,cancelled in ipairs({false,true})do
        local sock,owner,wear=restoreClothing(mixed,variant,false)
        local equip,activate=queue.queue[1],queue.queue[2]
        local expectedPrimary=kind~='desired-secondary'and sock or player.primary
        local expectedSecondary=(kind=='desired-secondary'or kind=='desired-both')and sock or player.secondary
        assert(equip.Type=='ISEquipWeaponAction'and equip.item==sock
            and equip.primary==(kind~='desired-secondary')and equip.twoHands==(kind=='desired-both')
            and activate.Type=='P4RestoreAction'and activate.item==sock and not activate.activated
            and queue.queue[3]==wear,'actual P4 desired baseline cleanup changed native order/flags')
        local following=tail()
        if cancelled then operations.invalidate(owner.toolkitQueueOperation)end
        isClient=function()return mode~='sp'end
        for i,action in ipairs({equip,activate,wear})do
            assert(select(2,definitions.inspect(wear))=='compat.tidy-equipment',
                'desired Wear lost its source proof across native hand prefix')
            assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
            local after=({activate,wear,following})[i]
            local removed=false;action.action={};queue.current=action
            player.getCharacterActions=function()return list(removed and {}or{action.action})end
            if mode=='mp-early'then assert(action:complete())end
            assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
            assert(queue.current==action and queue.queue[1]==action and queue.queue[2]==after)
            assert(lifecycle.flush(queue)=='waiting','desired clothing advanced before native removal')
            if mode=='sp'then
                assert(lifecycle.begin(action,'complete'));assert(action:complete());lifecycle.finish(action,'complete',true)
            elseif mode=='mp-late'then assert(action:complete())end
            assert(lifecycle.flush(queue)=='waiting')
            removed=true
            assert(lifecycle.flush(queue)=='completed'and queue.current==after and lifecycle.flush(queue)==nil)
            desiredBoundaries=desiredBoundaries+1
        end
        assert(writes==1 and worn[sock:getBodyLocation()]==sock and inventory:getItemById(sock:getID())==sock
            and player.primary==expectedPrimary and player.secondary==expectedSecondary,
            'native desired Wear failed to retain exact held/worn/root state')
        if variant:match('^watch%-')or variant:match('^ringing%-')then
            assert(sock:getHour()==23 and sock:getMinute()==40 and sock:isAlarmSet()
                and sock:isRinging()==(variant:match('^ringing%-')~=nil),
                'desired native watch hand/worn restoration changed alarm configuration')
        end
        isClient,player.getCharacterActions=client,actions;following:perform();tickTidy();tickTidy()
        assert(not TidyFixture.restoring[player]and not TidyFixture.sessions[player])
    end end
    end end
    assert(desiredBoundaries==252,'desired held/worn ownership and MP-order coverage incomplete')
    for _,kind in ipairs({'watch-held-primary','watch-held-secondary','watch-held-both','watch-desired-primary','watch-desired-secondary','watch-desired-both'})do
        for _,change in ipairs({'exclusive','missing'})do
            local sock,_,action=restoreClothing(true,kind,kind:match('^watch%-held%-')~=nil)
            assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
            if change=='exclusive'then
                local other=item(inventory,14808);other.class='Clothing';worn[ItemBodyLocation.FORE_ARM_LEFT]=other;exclusive=true
            else inventory.values={}end
            assert(not definitions.inspect(action),'held watch retained shared permissions after '..change)
        end
    end
    for _,kind in ipairs({'watch-left','watch-held-both','watch-desired-both'})do
        local sock,_,action=restoreClothing(true,kind,kind=='watch-held-both')
        sock.isRinging=function()return true end
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment',
            'native alarm start revoked exact watch cleanup ownership')
        sock.isRinging=function()return false end
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment',
            'native alarm stop revoked exact watch cleanup ownership')
    end
    for _,field in ipairs({'fromHotbar','clothingAction','stopOnWalk','stopOnRun','item','onCompleteFunc','start'})do
        local sock,_,action=restoreClothing(true)
        local previous=action[field]
        action[field]=(field=='start'or field=='onCompleteFunc')and function()end
            or field=='item'and item(inventory,14802)or not previous
        assert(not definitions.inspect(action),'clothing restore accepted a changed '..field)
        action[field]=previous;assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
    end
    for _,field in ipairs({'location','container','broken','equippedAt','attachedSlot','hasTag'})do
        local sock,_,action=restoreClothing(true)
        if field=='location'then sock.location=ItemBodyLocation.HANDS
        elseif field=='container'then sock.container={}
        elseif field=='broken'then sock.broken=true
        elseif field=='equippedAt'then sock.equippedAt='Back'
        elseif field=='attachedSlot'then sock.attachedSlot=1
        else sock.hasTag=function(_,tag)return tag==ItemTag.REPLACE_PRIMARY end end
        assert(not definitions.inspect(action),'clothing restore accepted changed item state '..field)
    end
    do
        local sock,_,action=restoreClothing(true)
        inventory.values={}
        assert(not definitions.inspect(action),'a stale container reference cannot prove a missing root clothing ID')
        local replica=item(inventory,sock:getID());replica.class='Clothing';inventory.values={replica}
        assert(definitions.inspect(action),'same-ID/type/body-location native replica preserves the clothing proof')
        replica.location=ItemBodyLocation.HANDS
        assert(not definitions.inspect(action),'a different live body location cannot borrow the queued proxy proof')
        replica.location=nil;replica.getFullType=function()return 'Base.OtherClothing'end
        assert(not definitions.inspect(action),'a different live full type cannot borrow the queued proxy proof')
    end
    for _,name in ipairs({'isAlreadyEquipped','stopSound','isStopOnWalk','complete','perform','start'})do
        local _,_,action=restoreClothing(true);local previous=ISWearClothing[name]
        ISWearClothing[name]=function()error('foreign clothing helper must not run')end
        assert(not definitions.inspect(action),'clothing restore accepted changed native helper '..name)
        ISWearClothing[name]=previous
    end
    for _,kind in ipairs({'bag','primary','wearable','wearable-tag','attached','heavy','broken'})do
        local _,_,action=restoreClothing(true,kind)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','clothing migration expanded into '..kind)
    end
    for _,field in ipairs({'reason','fromHotbar','hotbar','clothingAction','stopOnWalk','stopOnRun','animSpeed','onCompleteFunc','animEvent'})do
        local _,_,action=restoreClothing(true,nil,true)
        local original=action[field]
        action[field]=(field=='onCompleteFunc'or field=='animEvent')and function()end or field=='reason'and 'drop'or not original
        assert(not definitions.inspect(action),'worn removal accepted changed '..field)
        action[field]=original;assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
    end
    for _,kind in ipairs({'bag','primary','wearable','wearable-tag','attached','heavy','broken','activated'})do
        local _,_,action=restoreClothing(true,kind,true)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','worn removal migration expanded into '..kind)
    end
    for _,field in ipairs({'location','container','activatable','attachedSlot','broken'})do
        local sock,_,action=restoreClothing(true,nil,true)
        if field=='location'then sock.location=ItemBodyLocation.HANDS
        elseif field=='container'then sock.container={}
        elseif field=='activatable'then sock.activatable=true
        elseif field=='attachedSlot'then sock.attachedSlot=1
        else sock.broken=true end
        assert(not definitions.inspect(action),'worn removal accepted changed item '..field)
    end
    do
        local sock,_,action=restoreClothing(true,nil,true)
        inventory.values={}
        assert(not definitions.inspect(action),'missing live worn ID retained removal proof')
        local replica=item(inventory,sock:getID());replica.class='Clothing';inventory.values={replica}
        assert(definitions.inspect(action),'same-ID/type/slot root replica should preserve removal proof')
        replica.location=ItemBodyLocation.HANDS
        assert(not definitions.inspect(action),'live worn slot mismatch retained queued proxy proof')
        replica.location=nil;replica.getFullType=function()return 'Base.OtherClothing'end
        assert(not definitions.inspect(action),'live worn type mismatch retained queued proxy proof')
        replica.getFullType=sock.getFullType;sock.activatable=true
        assert(not definitions.inspect(action),'activatable queued proxy retained a plain removal proof')
    end
    for _,name in ipairs({'animEvent','complete','perform','start','update'})do
        local _,_,action=restoreClothing(true,nil,true);local original=ISUnequipAction[name]
        ISUnequipAction[name]=function()error('foreign unequip helper must not run')end
        assert(not definitions.inspect(action),'worn removal accepted changed native helper '..name)
        ISUnequipAction[name]=original
    end
    -- AlarmClockClothing is a real Clothing subtype. Category alone must not
    -- admit a table alarm clock, another special category or a non-wrist slot.
    for _,removal in ipairs({false,true})do
    for _,kind in ipairs({'watch-left','watch-right'})do
        for _,change in ipairs({'category','subtype','location','exclusive','multi','replacement','callback'})do
            local sock,_,action=restoreClothing(true,kind,removal)
            assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
            if change=='category'then sock.getCategory=function()return 'UnknownClock'end
            elseif change=='subtype'then sock.class='Clothing';sock.getCategory=function()return 'AlarmClock'end
            elseif change=='location'then sock.location=ItemBodyLocation.SOCKS
            elseif change=='exclusive'then
                local other=item(inventory,14808);other.class='Clothing';worn[ItemBodyLocation.FORE_ARM_LEFT]=other;exclusive=true
            elseif change=='multi'then multi=true
            elseif change=='replacement'then
                local other=item(inventory,sock:getID());other.class='AlarmClock';other.getCategory=function()return 'AlarmClock'end
                inventory.values={other}
            else action.onCompleteFunc=function()error('foreign watch callback must not run')end end
            assert(not definitions.inspect(action),'watch shared proof retained changed '..change)
        end
        local _,_,action=restoreClothing(true,kind,removal,function(sock)
            sock.class='AlarmClock';sock.getCategory=function()return 'AlarmClock'end
        end)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','inventory alarm clock borrowed worn watch proof')
    end
    end
    -- Headwear owns the stable native HumanVisual, including before a hair
    -- change. Hair content is mutable native state, not an identity/version.
    local appearanceBoundaries=0
    for _,removal in ipairs({false,true})do
    for _,kind in ipairs({'hat','full-hat'})do
    for _,style in ipairs({'MohawkFan','MohawkFlat','CustomMohawk','CrewCut'})do
    for _,mode in ipairs({'sp','mp-early','mp-late'})do
        local sock,owner,action=restoreClothing(true,kind,removal,function()hair=style end)
        local contract,id=definitions.inspect(action)
        assert(id=='compat.tidy-equipment'and contract.targets[visualState]and not contract.targets[player],
            'headwear must own exact appearance without actor-wide food conflicts')
        local following=tail();local removed=false;action.action={};queue.current=action
        player.getCharacterActions=function()return list(removed and {}or{action.action})end
        isClient=function()return mode~='sp'end
        operations.invalidate(owner.toolkitQueueOperation)
        if mode=='mp-early'then action:complete()end
        assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
        assert(lifecycle.flush(queue)=='waiting'and queue.queue[2]==following)
        if mode=='sp'then
            assert(lifecycle.begin(action,'complete'));action:complete();lifecycle.finish(action,'complete',true)
        elseif mode=='mp-late'then action:complete()end
        local expectedHair=style:find('Mohawk',1,true)and (not removal or mode=='sp')and 'MohawkFlat'or style
        assert(hair==expectedHair
            and (worn[sock:getBodyLocation()]==sock)==not removal and sock:getContainer()==inventory,
            'headwear cleanup changed native appearance or item effects')
        assert(definitions.inspect(action),'native flatten or early Host effect revoked required cleanup')
        hair='MohawkFan'
        if removal then assert(action:complete())else assert(not action:complete())end
        assert(hair=='MohawkFan','already completed clothing must not repeat native appearance effects')
        removed=true;assert(lifecycle.flush(queue)=='completed'and queue.current==following)
        isClient,player.getCharacterActions=client,actions;following:perform();tickTidy();tickTidy()
        appearanceBoundaries=appearanceBoundaries+1
    end end end end
    assert(appearanceBoundaries==48,'headwear appearance missed a slot/direction/hair/native-order boundary')
    for _,removal in ipairs({false,true})do
    for _,kind in ipairs({'hat','full-hat'})do
        local _,_,unknown=restoreClothing(true,kind,removal,function()hair=false end)
        assert(select(2,definitions.inspect(unknown))=='compat.selected-chains','headwear adopted a missing hair API')
        local _,_,action=restoreClothing(true,kind,removal)
        hair='MohawkFan'
        assert(definitions.inspect(action),'live native hair changes must keep the same visual resource')
        local saved=visualState;visualState={getHairModel=saved.getHairModel,setHairModel=saved.setHairModel}
        assert(not definitions.inspect(action),'replacement HumanVisual borrowed previous appearance ownership')
        visualState=saved;assert(definitions.inspect(action),'original exact visual must recover its contract')
    end end
    -- Headwear Wear adds no unrelated output when the real single slot is
    -- empty; a replaced item, occupied slot or exclusive location must never
    -- borrow that proof, even after the original action was already adopted.
    for _,kind in ipairs({'hat','full-hat'})do
        for _,change in ipairs({'missing','type','location','same-id-occupied','exclusive','other-slot','multi','hair-api'})do
            local sock,_,action=restoreClothing(true,kind,false)
            assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
            if change=='missing'then inventory.values={}
            elseif change=='type'then
                local replica=item(inventory,sock:getID());replica.class='Clothing';replica.location=sock.location
                replica.getFullType=function()return 'Base.OtherHeadwear'end;inventory.values={replica}
            elseif change=='location'then sock.location=ItemBodyLocation.HANDS
            elseif change=='same-id-occupied'then
                local proxy=item(inventory,sock:getID());proxy.class='Clothing';proxy.location=sock.location
                worn[sock:getBodyLocation()]=proxy
            elseif change=='exclusive'then
                local other=item(inventory,14805);other.class='Clothing'
                inventory.values[#inventory.values+1]=other;worn[ItemBodyLocation.HANDS]=other;exclusive=true
            elseif change=='other-slot'then worn[ItemBodyLocation.HANDS]=sock
            elseif change=='multi'then multi=true
            else hair=false end
            assert(not definitions.inspect(action),'headwear Wear retained shared ownership after '..change)
        end
        local sock,_,action=restoreClothing(true,kind,false)
        load,capacity=100,0
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment',
            'empty-slot native Wear must not invent a removal capacity debit')
        assert(action:complete()and worn[sock:getBodyLocation()]==sock and inventory:getItemById(sock:getID())==sock,
            'empty-slot headwear Wear lost its exact item on a full inventory')
    end
    -- The capacity proof covers Java's post-removal check, which adds the
    -- existing garment's full weight again. This state really drops on native
    -- authority in our Java storage double; the shared root-only proof declines.
    do
        local sock,_,action=restoreClothing(true,'hat',true,function()load,capacity=1,1.35 end)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','single-weight reserve incorrectly accepted native world-drop effects')
        assert(action:complete()and sock:getContainer()==nil and not inventory:getItemById(sock:getID()),
            'native capacity rejection was suppressed or failed to exercise its world-drop boundary')
    end
    for _,field in ipairs({'load','capacity','weight'})do
        for _,bad in ipairs({{value=-1},{value=math.huge},{value=0/0},{value='1'}, {}})do
            local _,_,action=restoreClothing(true,nil,true,function(sock)
                if field=='load'then load=bad.value
                elseif field=='capacity'then capacity=bad.value
                else sock.getUnequippedWeight=function()return bad.value end end
            end)
            assert(select(2,definitions.inspect(action))=='compat.selected-chains','unknown '..field..' borrowed a root-only removal proof')
        end
    end
    for _,bad in ipairs({{value=-1},{value=math.huge},{value=0/0},{value='1'},{}})do
        local _,_,action=restoreClothing(true,nil,true,function(sock)
            sock.getEquippedWeight=function()return bad.value end
        end)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','unknown/negative worn weight obtained a root-only removal proof')
    end
    for _,candidate in ipairs({'queued','root','worn'})do
    for _,bad in ipairs({-1,math.huge,0/0})do
        local queued,_,action=restoreClothing(true,nil,true)
        local live=item(inventory,queued:getID());live.class='Clothing'
        local wornProxy=item(inventory,queued:getID());wornProxy.class='Clothing'
        inventory.values={live};worn[queued:getBodyLocation()]=wornProxy
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','valid replicated removal baseline was rejected')
        local selected=candidate=='queued'and queued or candidate=='root'and live or wornProxy
        selected.getEquippedWeight=function()return bad end
        assert(not definitions.inspect(action),'negative/unknown '..candidate..' worn weight retained adopted removal ownership')
    end end
    do
        local sock,_,action=restoreClothing(true,nil,true,function(value)
            value.equippedWeight=-1;load,capacity=1,2
        end)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','negative worn multiplier bypassed native drop protection')
        local previous=player.removeWornItem
        player.removeWornItem=function(_,value)
            assert(value==sock and worn[value:getBodyLocation()]==value)
            worn[value:getBodyLocation()]=nil
            load=load+value:getUnequippedWeight()-value:getEquippedWeight()
            if math.floor(load*100+0.5)/100+value:getUnequippedWeight()>capacity then
                inventory.values={};value.container=nil
            end
        end
        assert(action:complete()and sock:getContainer()==nil,'negative multiplier must reproduce native capacity-driven world output')
        player.removeWornItem=previous
        local _,_,safe=restoreClothing(true,nil,true,function(value)value.equippedWeight=10 end)
        assert(select(2,definitions.inspect(safe))=='compat.tidy-equipment','larger positive worn weight must not invent a removal risk')
    end
    do
        local _,_,action=restoreClothing(true,nil,true,function()allowed=false end)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','native item rejection retained shared removal')
        local sock,_,live=restoreClothing(true,nil,true)
        load=capacity
        assert(not definitions.inspect(live),'late capacity loss retained shared removal')
        load=0
        local replica=item(inventory,sock:getID());replica.class='Clothing';replica.weight=100;inventory.values={replica}
        assert(not definitions.inspect(live),'queued light proxy concealed a heavy live root replica')
    end
    for _,removal in ipairs({false,true})do
        local _,_,multiAction=restoreClothing(true,nil,removal,function()multi=true end)
        assert(select(2,definitions.inspect(multiAction))=='compat.selected-chains','multi-item worn slot obtained an exact single-garment proof')
        local function extra(sock,sameSlot)
            local other=item(inventory,14805);other.class='Clothing';other.location=sameSlot and sock:getBodyLocation()or ItemBodyLocation.HANDS
            inventory.values[#inventory.values+1]=other;worn[other:getBodyLocation()]=other;exclusive=not sameSlot
        end
        local _,_,exclusiveAction=restoreClothing(true,nil,removal,function(sock)extra(sock,false)end)
        assert(select(2,definitions.inspect(exclusiveAction))==(removal and 'compat.selected-chains'or 'compat.tidy-equipment'),
            'exclusive Wear resource proof or strict removal boundary differs')
        if not removal then
            local _,_,replacement=restoreClothing(true,nil,false,function(sock)extra(sock,true)end)
            local proof,id=definitions.inspect(replacement)
            assert(id=='compat.tidy-equipment'and proof.items[14805],'same-slot Wear omitted its displaced root item')
        end
        local sock,_,action=restoreClothing(true,nil,removal)
        extra(sock,false)
        assert(not definitions.inspect(action),'late exclusive worn change retained shared ownership')
        exclusive=false;worn={[sock:getBodyLocation()]=item(inventory,14806)}
        assert(not definitions.inspect(action),'late same-slot replacement retained shared ownership')
    end
    do
        local function proxyInSlot(sock)
            local proxy=item(inventory,sock:getID());proxy.class='Clothing'
            worn[sock:getBodyLocation()]=proxy;load,capacity=1,1.1
        end
        local _,_,action=restoreClothing(true,nil,false,proxyInSlot)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','same-ID occupied Wear proxy concealed native replacement/drop effects')
        local sock,_,live=restoreClothing(true)
        proxyInSlot(sock)
        assert(not definitions.inspect(live),'late same-ID occupied Wear proxy retained exact-object ownership')
    end
    for _,removal in ipairs({false,true})do
        local function otherSlot(sock)worn={[ItemBodyLocation.HANDS]=sock}end
        local _,_,action=restoreClothing(true,nil,removal,otherSlot)
        assert(select(2,definitions.inspect(action))=='compat.selected-chains','same garment in a different nonexclusive slot obtained a single-slot proof')
        local sock,_,live=restoreClothing(true,nil,removal)
        otherSlot(sock)
        assert(not definitions.inspect(live),'late same-item different-slot mutation retained shared ownership')
    end
    -- The real P4 observer records all displaced root items. Java storage,
    -- equipped weight and its post-mutation drop decision remain doubles here.
    do
        local oldSetter,oldExclusive=player.setWornItem,group.isExclusive
        group.isExclusive=function(_,left,right)
            return left~=right and (left==ItemBodyLocation.SOCKS or right==ItemBodyLocation.SOCKS)
        end
        player.setWornItem=function(_,location,value)
            local previous=worn[location]
            if previous==value then return end
            local removed={}
            for loc,garment in pairs(worn)do
                if loc==location or group:isExclusive(location,loc)then removed[#removed+1]={loc,garment}end
            end
            for _,entry in ipairs(removed)do
                worn[entry[1]]=nil;load=load+entry[2]:getUnequippedWeight()-entry[2]:getEquippedWeight()
            end
            worn[location]=value;writes=writes+1
            if value then load=load+value:getEquippedWeight()-value:getUnequippedWeight()end
            if previous and (not allowed or math.floor(load*100+0.5)/100+previous:getUnequippedWeight()>capacity)then
                for i,candidate in ipairs(inventory.values)do if candidate==previous then table.remove(inventory.values,i);break end end
                previous.container=nil
            end
        end
        local displaced={}
        local function occupy(sock,pattern)
            displaced={}
            for index,location in ipairs(pattern=='same'and {sock:getBodyLocation()}
                or pattern=='exclusive-two'and {ItemBodyLocation.HAT,ItemBodyLocation.HANDS}or {ItemBodyLocation.HAT})do
                local garment=item(inventory,14900+index);garment.class='Clothing';garment.location=location
                garment.getFullType=function()return 'Base.Displaced'..index end
                inventory.values[#inventory.values+1]=garment;worn[location]=garment;displaced[#displaced+1]=garment
            end
            load,capacity=1,20
        end
        local displacedBoundaries=0
        for _,pattern in ipairs({'same','exclusive','exclusive-two'})do
        for _,mode in ipairs({'sp','mp-early','mp-late'})do
        for _,mixed in ipairs({false,true})do for _,cancelled in ipairs({false,true})do
            local sock,owner,wear=restoreClothing(mixed,nil,false,function(value)occupy(value,pattern)end)
            local contract,id=definitions.inspect(wear)
            assert(id=='compat.tidy-equipment'and contract.items[sock:getID()]and contract.hands==player)
            for _,garment in ipairs(displaced)do
                assert(contract.items[garment:getID()]and contract.itemTypes[garment:getFullType()],
                    'displaced clothing resource missing from the retained contract')
            end
            local cleanup={}
            for _,action in ipairs(queue.queue)do
                cleanup[#cleanup+1]=action
                if action==wear then break end
                assert(action.Type=='ISUnequipAction','unexpected P4 exclusive prefix')
            end
            assert(#cleanup==(pattern=='same'and 1 or #displaced+1),'P4 displaced cleanup changed native order/count')
            local following=tail()
            if cancelled then operations.invalidate(owner.toolkitQueueOperation)end
            isClient=function()return mode~='sp'end
            for index,action in ipairs(cleanup)do
                assert(select(2,definitions.inspect(wear))=='compat.tidy-equipment',
                    'displaced Wear lost its recorded resources through a native prefix')
                local nextAction=cleanup[index+1]or following
                local removed=false;action.action={};queue.current=action
                player.getCharacterActions=function()return list(removed and {}or{action.action})end
                if mode=='mp-early'then assert(action:complete())end
                assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
                assert(queue.current==action and queue.queue[2]==nextAction and lifecycle.flush(queue)=='waiting')
                if mode=='sp'then
                    assert(lifecycle.begin(action,'complete'));assert(action:complete());lifecycle.finish(action,'complete',true)
                elseif mode=='mp-late'then assert(action:complete())end
                assert(lifecycle.flush(queue)=='waiting','displaced cleanup ignored native action removal')
                removed=true
                assert(lifecycle.flush(queue)=='completed'and queue.current==nextAction and lifecycle.flush(queue)==nil)
                displacedBoundaries=displacedBoundaries+1
            end
            assert(worn[sock:getBodyLocation()]==sock and inventory:getItemById(sock:getID())==sock)
            local after=definitions.inspect(wear)
            assert(after,'early native completion revoked the displaced resource proof')
            for _,garment in ipairs(displaced)do
                assert(garment:getContainer()==inventory and inventory:getItemById(garment:getID())==garment
                    and not player:getWornItems():contains(garment)and after.items[garment:getID()],
                    'native replacement lost a displaced garment or released its resource too early')
            end
            isClient,player.getCharacterActions=client,actions;following:perform();tickTidy();tickTidy()
        end end end end
        assert(displacedBoundaries==72,'displaced clothing shared lifecycle coverage incomplete')
        -- Kahlua has pairs but no global next. Early Host completion can
        -- already have worn the exact target before its client perform starts.
        for _,pattern in ipairs({'none','same','exclusive'})do
            local _,_,wear=restoreClothing(true,nil,false,function(sock)
                if pattern~='none'then occupy(sock,pattern)else load=1 end
            end)
            assert(wear:complete())
            local standardNext=next;next=nil
            local contract,id=definitions.inspect(wear)
            next=standardNext
            assert(contract and id=='compat.tidy-equipment','early Host clothing proof requires unavailable Kahlua next')
        end
        for _,change in ipairs({'missing','type','body','container','activation','new-occupant','multi','capacity','equipped-weight'})do
            local sock,_,wear=restoreClothing(true,nil,false,function(value)occupy(value,'same')end)
            assert(select(2,definitions.inspect(wear))=='compat.tidy-equipment')
            local garment=displaced[1]
            if change=='missing'then inventory.values={sock}
            elseif change=='type'then garment.getFullType=function()return 'Base.OtherGarment'end
            elseif change=='body'then garment.location=ItemBodyLocation.HANDS
            elseif change=='container'then garment.container={}
            elseif change=='activation'then garment.activatable=true
            elseif change=='new-occupant'then
                local other=item(inventory,14905);other.class='Clothing';inventory.values[#inventory.values+1]=other
                worn[sock:getBodyLocation()]=other
            elseif change=='multi'then multi=true
            elseif change=='capacity'then capacity=1.1
            else garment.equippedWeight=100 end
            assert(not definitions.inspect(wear),'displaced Wear retained a stale '..change..' proof')
        end
        for _,change in ipairs({'alarm','container-item','broken','heavy','wrong-body','root-proxy','multi'})do
            local _,_,wear=restoreClothing(true,nil,false,function(sock)
                occupy(sock,'same');local garment=displaced[1]
                if change=='alarm'then garment.class='AlarmClockClothing'
                elseif change=='container-item'then garment.class='InventoryContainer';garment.equippedAt='Back'
                elseif change=='broken'then garment.broken=true
                elseif change=='heavy'then garment.fixtureHeavy=true
                elseif change=='wrong-body'then garment.location=ItemBodyLocation.HANDS
                elseif change=='root-proxy'then inventory.values={sock,item(inventory,garment:getID())}
                else multi=true end
            end)
            assert(select(2,definitions.inspect(wear))=='compat.selected-chains','displaced Wear accepted unsupported '..change)
        end
        for _,target in ipairs({'incoming','displaced'})do
        for _,bad in ipairs({-1,math.huge,0/0,100})do
            local _,_,wear=restoreClothing(true,nil,false,function(sock)
                occupy(sock,'same');local garment=target=='incoming'and sock or displaced[1]
                garment.getEquippedWeight=function()return bad end
            end)
            assert(select(2,definitions.inspect(wear))=='compat.selected-chains','unknown native worn multiplier obtained a no-drop proof')
        end end
        do
            local sock,_,wear=restoreClothing(true,nil,false,function(value)occupy(value,'same');capacity=1.1 end)
            local garment=displaced[1]
            assert(select(2,definitions.inspect(wear))=='compat.selected-chains','native same-slot world output was admitted')
            assert(wear:complete()and garment:getContainer()==nil and not inventory:getItemById(garment:getID())
                and worn[sock:getBodyLocation()]==sock,'fallback suppressed the real native capacity/drop branch')
        end
        do
            -- A mod can change exclusion data after clothes were worn. The
            -- same-slot drop check must include every newly displaced weight.
            local sock,_,wear=restoreClothing(true,nil,false,function(value)
                occupy(value,'same');displaced[1].equippedWeight=0
                local other=item(inventory,14907);other.class='Clothing';other.location=ItemBodyLocation.HAT
                other.weight,other.equippedWeight=3,0
                inventory.values[#inventory.values+1]=other;worn[other.location]=other;displaced[#displaced+1]=other
                value.equippedWeight=value:getUnequippedWeight();capacity=1.5
            end)
            assert(select(2,definitions.inspect(wear))=='compat.selected-chains',
                'same-slot reserve ignored an additional displaced exclusive garment')
            assert(wear:complete()and displaced[1]:getContainer()==nil and displaced[2]:getContainer()==inventory
                and worn[sock:getBodyLocation()]==sock,'Java drop branch must affect only its same-slot old item')
        end
        do
            local sock,_,wear=restoreClothing(true,nil,false,function(value)occupy(value,'exclusive-two');load,capacity=100,0 end)
            assert(select(2,definitions.inspect(wear))=='compat.tidy-equipment',
                'exclusive-only native Wear invented a same-slot capacity/drop check')
            assert(wear:complete()and worn[sock:getBodyLocation()]==sock)
            for _,garment in ipairs(displaced)do assert(garment:getContainer()==inventory)end
        end
        player.setWornItem,group.isExclusive=oldSetter,oldExclusive
    end
    do
        reset()
        local methods={new=ISUnequipAction.new,complete=ISUnequipAction.complete}
        local wrapped={new=function(...)return methods.new(...)end,complete=function(...)return methods.complete(...)end}
        lateCartProof.unequipConstructors[methods.new],lateCartProof.unequipConstructors[wrapped.new]=true,true
        lateCartProof.unequipLatest=wrapped
        ISUnequipAction.new,ISUnequipAction.complete=wrapped.new,wrapped.complete
        for _,kind in ipairs({'plain','hat','full-hat','held-secondary'})do
        for _,mode in ipairs({'sp','mp-early','mp-late'})do
            local sock,_,action=restoreClothing(true,kind,true)
            assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','audited non-cart late wrapper lost worn cleanup ownership')
            local following=tail();local removed=false;action.action={};queue.current=action
            local primary,syncs=player.primary,player.equipSyncs or 0
            player.getCharacterActions=function()return list(removed and {}or{action.action})end
            isClient=function()return mode~='sp'end
            if mode=='mp-early'then action:complete()end
            assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
            assert(lifecycle.flush(queue)=='waiting'and queue.queue[2]==following)
            if mode=='sp'then
                assert(lifecycle.begin(action,'complete'));action:complete();lifecycle.finish(action,'complete',true)
            elseif mode=='mp-late'then action:complete()end
            assert(writes==1 and not worn[sock:getBodyLocation()]and sock:getContainer()==inventory
                and player.primary==primary and player.secondary==nil and player.equipSyncs==syncs+1)
            removed=true;assert(lifecycle.flush(queue)=='completed'and queue.current==following)
            isClient,player.getCharacterActions=client,actions;following:perform();tickTidy();tickTidy()
        end
        end
        local _,_,action=restoreClothing(true,nil,true)
        lateCartProof.enabled=false;assert(not definitions.inspect(action),'changed late source proof retained worn removal permissions')
        lateCartProof.enabled=true
        local originalItemProof=lateCartProof.isNonCartItem
        lateCartProof.isNonCartItem=function()return true end
        assert(not definitions.inspect(action),'foreign item proof retained adopted clothing wrapper permissions')
        lateCartProof.isNonCartItem=originalItemProof
        local ownedPerform=action.perform;action.perform=function()end
        assert(not definitions.inspect(action),'foreign instance perform borrowed the adopted wrapper exception')
        action.perform=ownedPerform;assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
        reset();ISUnequipAction.new,ISUnequipAction.complete=methods.new,methods.complete
        lateCartProof.unequipLatest=nil
    end
    reset();player.getWornItems,player.getWornItem,player.setWornItem,player.getHumanVisual,player.removeWornItem=getWorn,getWornItem,setWorn,visual,removeWorn
    player.resetModel=resetModel
    player.getBodyLocationGroup=oldGroup
    inventory.getCapacityWeight,inventory.getEffectiveCapacity,inventory.isItemAllowed=oldLoad,oldCapacity,oldAllowed
end

-- P4 fromHotbar cleanup retains both native animation/perform attachment and
-- authoritative hand removal. Java visuals and network delivery are doubles.
do
    local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    local client,actions,completed=isClient,player.getCharacterActions,queue.onCompleted
    local oldGetter,oldDataGetter,oldData,oldBar=getPlayerHotbar,getPlayerData,ISPlayerData,ISHotbar
    local oldAttached,oldSetAttached,oldSetVariable,oldVariable,oldReport=player.getAttachedItem,player.setAttachedItem,player.SetVariable,player.setVariable,player.reportEvent
    ISHotbar={};ISHotbar.__index=ISHotbar
    local hotbarSource=read(NativeActionRoot..'/client/Hotbar/ISHotbar.lua')
    for _,name in ipairs({'isItemAttached','setAttachAnim'})do
        assert(loadstring(assert(hotbarSource:match('(function ISHotbar:'..name..'%([^\n]*\n.-\nend)')),'@media/lua/client/Hotbar/ISHotbar.lua'))()
    end
    local dataSource=read(NativeActionRoot..'/client/ISUI/PlayerData/ISPlayerData.lua')
    for _,name in ipairs({'getPlayerData','getPlayerHotbar'})do
        assert(loadstring(assert(dataSource:match('(function '..name..'%([^\n]*\n.-\nend)')),'@media/lua/client/ISUI/PlayerData/ISPlayerData.lua'))()
    end
    local slotEnvironment={ISHotbarAttachDefinition={},table=table}
    local slotDefinitions=assert(loadstring(read(NativeActionRoot..'/client/Hotbar/ISHotbarAttachDefinition.lua'),
        '@media/lua/client/Hotbar/ISHotbarAttachDefinition.lua'))
    setfenv(slotDefinitions,slotEnvironment);slotDefinitions()
    local function nativeSlot(kind)
        for _,definition in ipairs(slotEnvironment.ISHotbarAttachDefinition)do
            if definition.type==kind then
                local copy={type=definition.type,name=definition.name,animset=definition.animset,attachments={}}
                for attachment,model in pairs(definition.attachments)do copy.attachments[attachment]=model end
                return {slotType=kind,def=copy}
            end
        end
        error('native hotbar slot missing: '..kind)
    end
    local attached,writes,bar={},0
    player.getAttachedItem=function(_,location)return attached[location]end
    player.setAttachedItem=function(_,location,value)attached[location]=value;writes=writes+1 end
    player.SetVariable=function(self,name,value)self[name]=value end
    player.setVariable=player.SetVariable;player.reportEvent=function()end
    local function restoreHotbar(mixed,slot,kind,variant)
        reset();attached={};writes=0;player.primary,player.secondary=nil,nil
        local weapon=item(inventory,14810);weapon.class='HandWeapon';inventory.values={weapon}
        weapon.attachedSlot,weapon.attachedKind,weapon.attachedModel=1,'Back','Rifle Back with Bag'
        weapon.getAttachedSlotType=function(self)return self.attachedKind end
        weapon.getAttachedToModel=function(self)return self.attachedModel end
        weapon.getAttachmentType=function(self)return self.attachment or 'Rifle'end
        weapon.getUnequipSound=function()end;weapon.setJobType=function()end
        local definition={type='Back',name='Back',animset='back',attachments={Rifle='Rifle Back'}}
        bar=setmetatable({chr=player,availableSlot={{slotType='Back',def=definition}},
            attachedItems={weapon},replacements={Rifle='Rifle Back with Bag'}},ISHotbar)
        if variant=='HolsterLeft'or variant=='HolsterRight'then
            -- Both native slots share the display name Holster but have distinct
            -- types/models/animations. The item must retain the exact slot.
            bar.availableSlot={nativeSlot('Back'),nativeSlot('HolsterLeft'),nativeSlot('HolsterRight')}
            local index=variant=='HolsterLeft'and 2 or 3
            local expected=bar.availableSlot[index].def
            weapon.attachment='Holster'
            weapon.attachedSlot,weapon.attachedKind,weapon.attachedModel=index,variant,expected.attachments.Holster
            bar.attachedItems={[index]=weapon}
            assert(expected.name=='Holster'and weapon.attachedModel=='Holster '..(index==2 and 'Left'or 'Right'))
        end
        local radio=type(variant)=='string'and variant:match('^RadioBelt')~=nil
        local flashlight=type(variant)=='string'and variant:match('^Flashlight')~=nil
        if variant=='SmallBeltLeft'or variant=='SmallBeltRight'or radio or flashlight then
            bar.availableSlot=flashlight and {nativeSlot('WebbingLeft'),nativeSlot('WebbingRight')}or {nativeSlot('SmallBeltLeft'),nativeSlot('SmallBeltRight')}
            local index=(variant=='SmallBeltLeft'or radio and variant:find('Left',1,true)or flashlight)and 1 or 2
            local expected=bar.availableSlot[index].def
            weapon.class='ComboItem';weapon.attachment='Screwdriver'
            weapon.attachedSlot,weapon.attachedKind,weapon.attachedModel=index,bar.availableSlot[index].slotType,expected.attachments.Screwdriver
            weapon.script={getFullName=function()return weapon:getFullType()end,getItemType=function()return 'base:normal'end,
                getLuaCreate=function()end,getItemConfig=function()end,getItemConfigKey=function()end,hasComponents=function()return false end}
            weapon.getScriptItem=function(self)return self.script end
            weapon.hasComponents=function(self)return self.components or false end
            weapon.getFluidContainer=function(self)return self.fluid end
            weapon.isWet=function(self)return self.wet or false end
            weapon.getItemWhenDry=function(self)return self.dryReplacement end
            if variant=='SmallBeltRight'then
                weapon.attributeScript={class='AttributesScript'}
                weapon.attributes={class='AttributeContainer',getComponentType=function()return ComponentType.Attributes end,
                    getOwner=function()return weapon end}
                weapon.components=true;weapon.script.hasComponents=function()return true end
                weapon.script.getComponentScripts=function()return list({weapon.attributeScript})end
                weapon.script.getComponentScriptFor=function(_,kind)if kind==ComponentType.Attributes then return weapon.attributeScript end end
                weapon.metadata={class='EntityScriptInfo',getComponentType=function()return ComponentType.Script end,
                    getOwner=function()return weapon end,getScript=function()return weapon.script end,
                    getOriginalScript=function()return weapon:getFullType()end,isOriginalIsItem=function()return true end}
                weapon.componentSize=function()return 2 end
                weapon.getComponentForIndex=function(_,index)if index==0 then return weapon.attributes elseif index==1 then return weapon.metadata end end
                weapon.getAttributes=function()return weapon.attributes end
                weapon.getComponent=function(_,kind)if kind==ComponentType.Script then return weapon.metadata end end
                weapon.getEntityScript=function()return weapon.script end
            end
            if radio then
                weapon.class='Radio';weapon.attachment='Walkie';weapon.attachedModel=expected.attachments.Walkie
                weapon.script.getItemType=function()return 'base:radio'end
                weapon.device={class='DeviceData',portable=true,batteryPowered=true,television=false,media=false,playing=false,
                    on=variant:find('On',1,true)~=nil,power=0.65,channel=88000,volume=0.25}
                weapon.getDeviceData=function(self)return self.device end
                local data=weapon.device
                data.getParent=function()return weapon end
                data.getIsPortable=function(self)return self.portable end
                data.getIsBatteryPowered=function(self)return self.batteryPowered end
                data.getIsTelevision=function(self)return self.television end
                data.hasMedia=function(self)return self.media end
                data.isPlayingMedia=function(self)return self.playing end
            end
            if flashlight then
                weapon.class='DrainableComboItem';weapon.attachment='Webbing';weapon.attachedModel=expected.attachments.Webbing
                weapon.script.getItemType=function()return 'base:drainable'end
                weapon.script.getReplaceOnUse=function()end;weapon.script.getOnBreak=function()end
                weapon.activatable=true;weapon.activated=variant~='FlashlightEmpty'
                weapon.uses=variant=='FlashlightCharged'and 80 or 0
                weapon.keep=true;weapon.useWhileEquipped=true;weapon.useWhileUnequipped=false
                weapon.strength,weapon.distance,weapon.delta=1.5,15,0.006
                weapon.hasTag=function(self,tag)return tag==ItemTag.FLASHLIGHT and not self.wrongTag end
                weapon.isKeepOnDeplete=function(self)return self.keep end
                weapon.isUseWhileEquiped=function(self)return self.useWhileEquipped end
                weapon.isUseWhileUnequiped=function(self)return self.useWhileUnequipped end
                weapon.getUseDelta=function(self)return self.delta end
                weapon.getReplaceOnDeplete=function(self)return self.replaceDeplete end
                weapon.getReplaceOnDepleteFullType=function(self)return self.replaceFullType end
                weapon.getReplaceOnCooked=function(self)return self.replaceCooked end
                weapon.getOnCooked=function(self)return self.onCooked end
                weapon.getOnEat=function(self)return self.onEat end
                weapon.isCookable=function(self)return self.cookable or false end
                weapon.getLightStrength=function(self)return self.strength end
                weapon.getLightDistance=function(self)return self.distance end
                weapon.isTorchCone=function(self)return not self.noCone end
                weapon.playDeactivateSound=function(self)self.deactivateSounds=(self.deactivateSounds or 0)+1 end
            end
            bar.attachedItems={[index]=weapon}
        end
        ISPlayerData={{playerHotbar=bar}}
        if kind=='heavy'then weapon.fixtureHeavy=true
        elseif kind=='activated'then weapon.activatable=true
        elseif kind=='broken'then weapon.broken=true
        elseif kind=='slot'then bar.availableSlot={}
        elseif kind=='duplicate'then bar.availableSlot[#bar.availableSlot+1]=bar.availableSlot[weapon.attachedSlot]end
        local captured=TidyFixture.captureSession(player)
        captured.armed,captured.restoreHands=true,true;TidyFixture.sessions[player]=captured
        local owner=tail();local other=mixed and tail()or nil
        if slot~='secondary'then player.primary=weapon end
        if slot=='secondary'or slot=='both'then player.secondary=weapon end
        local getWorn=player.getWornItems
        if kind=='worn'then player.getWornItems=function()return {size=function()return 0 end,contains=function(_,value)return value==weapon end}end end
        owner:perform();if other then other:perform()end;tickTidy();tickTidy()
        player.getWornItems=getWorn
        local action=queue.queue[1]
        assert(action and action.Type=='ISUnequipAction'and action.item==weapon and action.fromHotbar==true,
            'actual P4 did not create the exact hand-to-hotbar restore')
        assert(#queue.queue==1,'P4 created duplicate hotbar cleanup for two held hands')
        return weapon,owner,action
    end
    local callbacks=0
    local previousActivatedSync=syncItemActivated
    syncItemActivated=function(character,value)
        assert(character==player and value.class=='DrainableComboItem'and not value:isActivated(),'native deactivation must sync the exact kept flashlight')
        value.activationSyncs=(value.activationSyncs or 0)+1
    end
    queue.onCompleted=function(self,action)
        if lifecycle.current(player)==action then
            assert(not operations.deferCompletion(self,action),'hotbar cleanup acquired a legacy completion scope')
            callbacks=callbacks+1
        end
        return completed(self,action)
    end
    local function completeCase(mode,mixed,cancelled,slot,variant)
        local weapon,owner,action=restoreHotbar(mixed,slot,nil,variant)
        local index,slotType=weapon:getAttachedSlot(),weapon:getAttachedSlotType()
        local device=weapon.device;local powered=device and device.on
        local flashlight=weapon.class=='DrainableComboItem'
        local wasActive,charge=weapon:isActivated(),weapon.uses
        local animation=bar.availableSlot[index].def.animset
        local contract,kind=definitions.inspect(action)
        assert(contract and kind=='compat.tidy-equipment'and contract.items[weapon:getID()]
            and (contract.cancelOperation==false)==mixed,'hotbar cleanup lacks shared native ownership')
        local following=tail();local removed=false;local syncs=player.equipSyncs or 0
        action.action={setOverrideHandModelsObject=function()end,setActionAnim=function()end}
        queue.current=action;player.getCharacterActions=function()return list(removed and {}or{action.action})end
        isClient=function()return mode~='sp'end
        if cancelled then operations.invalidate(owner.toolkitQueueOperation)end
        -- Native start uses the real hotbar animation helper. attachConnect is
        -- a visual effect; complete separately applies authoritative hand state.
        action:start();assert(player.AttachAnim==animation)
        if flashlight then
            assert(not weapon:isActivated()and weapon.uses==charge and weapon:getContainer()==inventory
                and (weapon.activationChanges or 0)==(wasActive and 1 or 0)
                and (weapon.activationSyncs or 0)==(wasActive and 1 or 0)
                and (weapon.deactivateSounds or 0)==(wasActive and 1 or 0),'native flashlight start lost or duplicated deactivation/sync/sound')
            assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','native deactivation revoked required flashlight cleanup')
        end
        action:animEvent('attachConnect',nil)
        assert(writes==1 and attached[weapon:getAttachedToModel()]==weapon)
        if mode=='mp-early'then action:complete()end
        assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
        assert(queue.queue[1]==action and queue.queue[2]==following and lifecycle.flush(queue)=='waiting')
        if mode=='sp'then
            assert(player.primary==weapon or player.secondary==weapon,'SP hand effect ran before native complete')
            assert(lifecycle.begin(action,'complete'));action:complete();lifecycle.finish(action,'complete',true)
        elseif mode=='mp-late'then action:complete()end
        assert(player.primary==nil and player.secondary==nil and player.equipSyncs==syncs+1,
            'hotbar native hand effect was lost or duplicated')
        assert(writes==2 and attached[weapon:getAttachedToModel()]==weapon and weapon:getContainer()==inventory
            and weapon:getAttachedSlot()==index and weapon:getAttachedSlotType()==slotType
            and bar.attachedItems[index]==weapon,'hotbar animation/perform metadata or exact root item changed')
        if device then
            assert(weapon:getDeviceData()==device and device:getParent()==weapon and device.on==powered
                and device.power==0.65 and device.channel==88000 and device.volume==0.25,
                'native hotbar return changed independent DeviceData settings or battery')
        end
        assert(lifecycle.flush(queue)=='waiting');removed=true
        assert(lifecycle.flush(queue)=='completed'and queue.current==following and lifecycle.flush(queue)==nil)
        isClient,player.getCharacterActions=client,actions;following:perform();tickTidy();tickTidy()
        assert(not TidyFixture.restoring[player]and not TidyFixture.sessions[player])
    end
    for _,variant in ipairs({'Back','HolsterLeft','HolsterRight','SmallBeltLeft','SmallBeltRight','RadioBeltLeftOff','RadioBeltLeftOn','RadioBeltRightOff','RadioBeltRightOn','FlashlightCharged','FlashlightEmpty','FlashlightDeplete'})do
        for _,mode in ipairs({'sp','mp-early','mp-late'})do
            for _,mixed in ipairs({false,true})do for _,cancelled in ipairs({false,true})do
                for _,slot in ipairs({'primary','secondary','both'})do completeCase(mode,mixed,cancelled,slot,variant)end
            end end
        end
    end
    assert(callbacks==432,'hotbar cleanup missed item-family/slot/hand/owner/cancel/effect-order combinations')
    queue.onCompleted=completed
    syncItemActivated=previousActivatedSync
    for _,variant in ipairs({'HolsterLeft','HolsterRight'})do
        for _,change in ipairs({'other-slot','other-definition','duplicate-type','icon-other-slot','removed-slot'})do
            local weapon,_,action=restoreHotbar(true,'primary',nil,variant)
            local index=weapon:getAttachedSlot();local other=index==2 and 3 or 2
            if change=='other-slot'then
                local definition=bar.availableSlot[other].def
                weapon.attachedSlot,weapon.attachedKind,weapon.attachedModel=other,definition.type,definition.attachments.Holster
                bar.attachedItems={[other]=weapon}
            elseif change=='other-definition'then bar.availableSlot[index]=bar.availableSlot[other]
            elseif change=='duplicate-type'then bar.availableSlot[other]=bar.availableSlot[index]
            elseif change=='icon-other-slot'then bar.attachedItems={[other]=weapon}
            elseif change=='removed-slot'then table.remove(bar.availableSlot,index)end
            assert(not definitions.inspect(action),'holster restore accepted changed '..variant..' '..change)
        end
    end
    for _,variant in ipairs({'Back','SmallBeltLeft'})do
        for _,kind in ipairs({'heavy','activated','broken','slot','duplicate','worn'})do
            local _,_,action=restoreHotbar(true,'primary',kind,variant)
            assert(select(2,definitions.inspect(action))=='compat.selected-chains','hotbar cleanup migration expanded into '..variant..' '..kind)
        end
    end
    for _,change in ipairs({'class','type','script-id','create','config','config-key','script-components',
        'components','fluid','wet','dry-replacement','missing-api','missing-script','class-helper','live-components','missing-item','occupied','base-class'})do
        local weapon,_,action=restoreHotbar(true,'secondary',nil,'SmallBeltLeft')
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','normal belt item did not migrate')
        local classHelper=getClassSimpleName
        if change=='class'then weapon.class='Radio'
        elseif change=='type'then weapon.script.getItemType=function()return 'base:drainable'end
        elseif change=='script-id'then weapon.script.getFullName=function()return 'Base.Other'end
        elseif change=='create'then weapon.script.getLuaCreate=function()return 'customCreate'end
        elseif change=='config'then weapon.script.getItemConfig=function()return {}end
        elseif change=='config-key'then weapon.script.getItemConfigKey=function()return 'customConfig'end
        elseif change=='script-components'then weapon.script.hasComponents=function()return true end
        elseif change=='components'then weapon.components=true
        elseif change=='fluid'then weapon.fluid={}
        elseif change=='wet'then weapon.wet=true
        elseif change=='dry-replacement'then weapon.dryReplacement='Base.Other'
        elseif change=='missing-api'then weapon.hasComponents=nil
        elseif change=='missing-script'then weapon.script=nil
        elseif change=='class-helper'then getClassSimpleName=function()return 'ComboItem'end
        elseif change=='live-components'then
            local live=setmetatable({components=true},{__index=weapon});inventory.values={live}
        elseif change=='missing-item'then action.item=nil
        elseif change=='occupied'then attached[weapon.attachedModel]=item(inventory,14811)
        elseif change=='base-class'then weapon.class='InventoryItem'end
        assert(not definitions.inspect(action),'normal belt cleanup accepted changed '..change)
        getClassSimpleName=classHelper
    end
    for _,change in ipairs({'script-class','script-extra','script-mapping','script-api','item-extra','item-api',
        'component-class','component-type','component-owner','component-index','missing-attributes','fluid',
        'metadata-class','metadata-type','metadata-owner','metadata-key','metadata-kind','metadata-script','entity-script','metadata-index'})do
        local weapon,_,action=restoreHotbar(true,'primary',nil,'SmallBeltRight')
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','ordinary native attributes did not migrate')
        if change=='script-class'then weapon.attributeScript.class='FluidContainerScript'
        elseif change=='script-extra'then weapon.script.getComponentScripts=function()return list({weapon.attributeScript,{}})end
        elseif change=='script-mapping'then weapon.script.getComponentScriptFor=function()return {}end
        elseif change=='script-api'then weapon.script.getComponentScripts=nil
        elseif change=='item-extra'then weapon.componentSize=function()return 3 end
        elseif change=='item-api'then weapon.componentSize=nil
        elseif change=='component-class'then weapon.attributes.class='FluidContainer'
        elseif change=='component-type'then weapon.attributes.getComponentType=function()return {}end
        elseif change=='component-owner'then weapon.attributes.getOwner=function()return item(inventory,14812)end
        elseif change=='component-index'then weapon.getComponentForIndex=function()return {}end
        elseif change=='missing-attributes'then weapon.attributes=nil
        elseif change=='fluid'then weapon.fluid={}
        elseif change=='metadata-class'then weapon.metadata.class='Unknown'
        elseif change=='metadata-type'then weapon.metadata.getComponentType=function()return {}end
        elseif change=='metadata-owner'then weapon.metadata.getOwner=function()return {}end
        elseif change=='metadata-key'then weapon.metadata.getOriginalScript=function()return 'Base.Other'end
        elseif change=='metadata-kind'then weapon.metadata.isOriginalIsItem=function()return false end
        elseif change=='metadata-script'then weapon.metadata.getScript=function()return {}end
        elseif change=='entity-script'then weapon.getEntityScript=function()return {}end
        elseif change=='metadata-index'then weapon.getComponentForIndex=function(_,index)if index==0 then return weapon.attributes end end end
        assert(not definitions.inspect(action),'normal belt cleanup accepted changed attributes '..change)
    end
    for _,change in ipairs({'class','script-type','script-id','create','config','config-key','components','fluid','wet','dry-replacement',
        'missing-getter','missing-device','device-class','parent','portable','battery','tv','media','playing','device-api','live-device','activation'})do
        local weapon,_,action=restoreHotbar(true,'secondary',nil,'RadioBeltLeftOn')
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','powered radio did not migrate')
        local data=weapon.device
        if change=='class'then weapon.class='ComboItem'
        elseif change=='script-type'then weapon.script.getItemType=function()return 'base:normal'end
        elseif change=='script-id'then weapon.script.getFullName=function()return 'Base.Other'end
        elseif change=='create'then weapon.script.getLuaCreate=function()return 'customCreate'end
        elseif change=='config'then weapon.script.getItemConfig=function()return {}end
        elseif change=='config-key'then weapon.script.getItemConfigKey=function()return 'customConfig'end
        elseif change=='components'then weapon.components=true
        elseif change=='fluid'then weapon.fluid={}
        elseif change=='wet'then weapon.wet=true
        elseif change=='dry-replacement'then weapon.dryReplacement='Base.Other'
        elseif change=='missing-getter'then weapon.getDeviceData=nil
        elseif change=='missing-device'then weapon.device=nil
        elseif change=='device-class'then data.class='UnknownDeviceData'
        elseif change=='parent'then data.getParent=function()return {}end
        elseif change=='portable'then data.portable=false
        elseif change=='battery'then data.batteryPowered=false
        elseif change=='tv'then data.television=true
        elseif change=='media'then data.media=true
        elseif change=='playing'then data.playing=true
        elseif change=='device-api'then data.hasMedia=nil
        elseif change=='live-device'then
            local live=setmetatable({device={class='DeviceData'}},{__index=weapon});inventory.values={live}
        elseif change=='activation'then weapon.activatable=true end
        assert(not definitions.inspect(action),'radio hotbar cleanup accepted changed '..change)
    end
    do
        local weapon,_,action=restoreHotbar(true,'secondary',nil,'RadioBeltRightOn')
        -- Autonomous native power changes do not revoke required cleanup. A
        -- canonical MP item proxy may change without changing inventory identity.
        weapon.device.power=0;weapon.device.on=false
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','depleted radio lost required cleanup')
        local live=setmetatable({},{__index=weapon})
        live.device=setmetatable({getParent=function()return live end},{__index=weapon.device});inventory.values={live}
        bar.attachedItems[weapon:getAttachedSlot()]=live
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','canonical radio proxy replacement lost cleanup')
    end
    for _,change in ipairs({'class','tag','script-type','script-id','create','config','components','fluid','wet','dry','missing-api',
        'not-activatable','keep','equipped-use','unequipped-use','deplete-output','full-output','cooked-output','cooked-callback','eat-callback','cookable',
        'use-output','break-callback','no-cone','strength','distance','delta','nan','live-output','missing-root'})do
        local weapon,_,action=restoreHotbar(true,'secondary',nil,'FlashlightCharged')
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','native flashlight did not migrate')
        if change=='class'then weapon.class='InventoryItem'
        elseif change=='tag'then weapon.wrongTag=true
        elseif change=='script-type'then weapon.script.getItemType=function()return 'base:normal'end
        elseif change=='script-id'then weapon.script.getFullName=function()return 'Base.Other'end
        elseif change=='create'then weapon.script.getLuaCreate=function()return 'customCreate'end
        elseif change=='config'then weapon.script.getItemConfig=function()return {}end
        elseif change=='components'then weapon.components=true
        elseif change=='fluid'then weapon.fluid={}
        elseif change=='wet'then weapon.wet=true
        elseif change=='dry'then weapon.dryReplacement='Base.Other'
        elseif change=='missing-api'then weapon.getUseDelta=nil
        elseif change=='not-activatable'then weapon.activatable=false
        elseif change=='keep'then weapon.keep=false
        elseif change=='equipped-use'then weapon.useWhileEquipped=false
        elseif change=='unequipped-use'then weapon.useWhileUnequipped=true
        elseif change=='deplete-output'then weapon.replaceDeplete='Base.Other'
        elseif change=='full-output'then weapon.replaceFullType='Base.Other'
        elseif change=='cooked-output'then weapon.replaceCooked=list({'Base.Other'})
        elseif change=='cooked-callback'then weapon.onCooked='callback'
        elseif change=='eat-callback'then weapon.onEat='callback'
        elseif change=='cookable'then weapon.cookable=true
        elseif change=='use-output'then weapon.script.getReplaceOnUse=function()return 'Base.Other'end
        elseif change=='break-callback'then weapon.script.getOnBreak=function()return 'callback'end
        elseif change=='no-cone'then weapon.noCone=true
        elseif change=='strength'then weapon.strength=0
        elseif change=='distance'then weapon.distance=math.huge
        elseif change=='delta'then weapon.delta=0
        elseif change=='nan'then weapon.delta=0/0
        elseif change=='live-output'then local live=setmetatable({replaceDeplete='Base.Other'},{__index=weapon});inventory.values={live}
        elseif change=='missing-root'then inventory.values={}end
        assert(not definitions.inspect(action),'flashlight hotbar cleanup accepted changed '..change)
    end
    do
        local weapon,_,action=restoreHotbar(true,'secondary',nil,'FlashlightCharged')
        local id=weapon:getID()
        weapon.uses=0;weapon.activated=false;weapon.replaceCooked=list({})
        local contract,kind=definitions.inspect(action)
        assert(kind=='compat.tidy-equipment'and contract.items[id]and contract.hands==player,'depleted flashlight lost exact item/hands resource or cleanup')
        local live=setmetatable({uses=0,activated=false},{__index=weapon});inventory.values={live};bar.attachedItems[weapon:getAttachedSlot()]=live
        assert(select(2,definitions.inspect(action))=='compat.tidy-equipment','canonical depleted flashlight proxy lost cleanup')
    end
    for _,field in ipairs({'reason','fromHotbar','hotbar','clothingAction','stopOnWalk','stopOnRun','animSpeed','onCompleteFunc','animEvent'})do
        local _,_,action=restoreHotbar(true,'primary');local original=action[field]
        action[field]=(field=='onCompleteFunc'or field=='animEvent')and function()end or field=='reason'and 'drop'or not original
        assert(not definitions.inspect(action),'hotbar restore accepted changed '..field)
        action[field]=original;assert(select(2,definitions.inspect(action))=='compat.tidy-equipment')
    end
    for _,change in ipairs({'index','kind','model','attachment','root','missing','occupied','slot-def','animset','mapping','duplicate','activated','icon-index'})do
        local weapon,_,action=restoreHotbar(true,'primary')
        if change=='index'then weapon.attachedSlot=2
        elseif change=='kind'then weapon.attachedKind='SmallBeltLeft'
        elseif change=='model'then weapon.attachedModel='other'
        elseif change=='attachment'then weapon.attachment='Knife'
        elseif change=='root'then weapon.container={}
        elseif change=='missing'then inventory.values={}
        elseif change=='occupied'then attached[weapon.attachedModel]=item(inventory,14811)
        elseif change=='slot-def'then bar.availableSlot[1].def={type='Back',name='Back',animset='back',attachments={Rifle='Rifle Back'}}
        elseif change=='animset'then bar.availableSlot[1].def.animset='belt left'
        elseif change=='mapping'then bar.replacements.Rifle='other'
        elseif change=='duplicate'then bar.availableSlot[2]=bar.availableSlot[1]
        elseif change=='activated'then weapon.activatable=true
        elseif change=='icon-index'then bar.attachedItems={[1]=item(inventory,14811),[2]=weapon}end
        assert(not definitions.inspect(action),'hotbar restore accepted changed '..change)
    end
    for _,change in ipairs({'getter','data','animate','attached','instance'})do
        local _,_,action=restoreHotbar(true,'primary')
        local getter,data,animate,check=getPlayerHotbar,getPlayerData,ISHotbar.setAttachAnim,ISHotbar.isItemAttached
        if change=='getter'then getPlayerHotbar=function()return bar end
        elseif change=='data'then getPlayerData=function()return ISPlayerData[1]end
        elseif change=='animate'then ISHotbar.setAttachAnim=function()end
        elseif change=='attached'then ISHotbar.isItemAttached=function()return true end
        else bar.setAttachAnim=function()end end
        assert(not definitions.inspect(action),'hotbar cleanup accepted changed helper '..change)
        getPlayerHotbar,getPlayerData,ISHotbar.setAttachAnim,ISHotbar.isItemAttached=getter,data,animate,check
    end
    do
        reset();local methods={new=ISUnequipAction.new,complete=ISUnequipAction.complete}
        local wrapped={new=function(...)return methods.new(...)end,complete=function(...)return methods.complete(...)end}
        lateCartProof.unequipConstructors[methods.new],lateCartProof.unequipConstructors[wrapped.new]=true,true
        lateCartProof.unequipLatest=wrapped;ISUnequipAction.new,ISUnequipAction.complete=wrapped.new,wrapped.complete
        for _,variant in ipairs({'Back','HolsterLeft','HolsterRight'})do
            for _,mode in ipairs({'sp','mp-early','mp-late'})do completeCase(mode,true,false,'both',variant)end
        end
        local _,_,action=restoreHotbar(true,'primary')
        local proof=lateCartProof.isNonCartItem;lateCartProof.isNonCartItem=function()return true end
        assert(not definitions.inspect(action),'hotbar restore accepted a foreign late item helper');lateCartProof.isNonCartItem=proof
        reset();ISUnequipAction.new,ISUnequipAction.complete=methods.new,methods.complete;lateCartProof.unequipLatest=nil
    end
    reset();getPlayerHotbar,getPlayerData,ISPlayerData,ISHotbar=oldGetter,oldDataGetter,oldData,oldBar
    player.getAttachedItem,player.setAttachedItem,player.SetVariable,player.setVariable,player.reportEvent=oldAttached,oldSetAttached,oldSetVariable,oldVariable,oldReport
end

-- Exact fixture native actions supply the same known-input contracts the native Policy installs.
local nativeTransferPerform=ISInventoryTransferAction.perform
local pinnedFloorHelper=ISInventoryTransferAction.getNotFullFloorSquare
local unknownInput,dynamicInput
local fixtureContractMethods={}
for _,class in ipairs({ISInventoryTransferAction,ISReadABook}) do
    fixtureContractMethods[class]={}
    for _,name in ipairs({'new','isValid','start','perform','stop','complete','getNotFullFloorSquare'}) do
        fixtureContractMethods[class][name]=class[name]
    end
end
definitions.registerBehavior('fixture.native-tidy-inputs',{types={'ISInventoryTransferAction','ISReadABook'},matches=function(action)
    local class=getmetatable(action); local methods=fixtureContractMethods[class]
    if not methods or action.perform~=methods.perform then return false end
    for name,callback in pairs(methods) do if class[name]~=callback then return false end end
    return true
end,inspect=function(action)
    local value=action.item
    local result={items=value and {[value:getID()]=true} or {},itemTypes=value and {[value:getFullType()]=true} or {},targets={},
        knownInputs=not unknownInput,dynamicInputs=dynamicInput and {['Base.Test']=true} or nil}
    PZSurvivorToolkit.ActionQueuePolicy.addContainerResources(result,action.srcContainer)
    PZSurvivorToolkit.ActionQueuePolicy.addContainerResources(result,action.destContainer)
    return result
end})
local tidyBagOwner=item(inventory,40); tidyBagOwner.class='InventoryContainer'
local tidyBag={class='ItemContainer',getParent=function() end,getType=function() return 'bag' end,
    getContainingItem=function() return tidyBagOwner end}
getPlayerLoot=function() return {backpacks={{inventory=tidyBag}}} end
local function tidyTasks(shared, insertion, queueEnabled, sameOwner)
    reset(); doNotReequip=false; player.primary=nil
    if queueEnabled~=nil then enabled=queueEnabled end
    local first,second=item(tidyBag,41),item(tidyBag,42)
    local firstPickup,firstRead,secondPickup,secondRead
    operations.run(function()
        firstPickup=ISInventoryTransferAction:new(player,first,tidyBag,inventory); ISTimedActionQueue.add(firstPickup)
        firstRead=ISReadABook:new(player,first); ISTimedActionQueue.add(firstRead)
    end)
    local secondOperation=sameOwner and function(callback) return operations.runWith(firstRead.toolkitQueueOperation,callback) end or operations.run
    secondOperation(function()
        if not shared then secondPickup=ISInventoryTransferAction:new(player,second,tidyBag,inventory); ISTimedActionQueue.add(secondPickup) end
        secondRead=ISReadABook:new(player,shared and first or second); ISTimedActionQueue.add(secondRead)
    end)
    local extra
    if insertion then
        extra=ISReadABook:new(player,first)
        if insertion=='after' then
            local result,added=ISTimedActionQueue.addAfter(secondRead,extra)
            assert(result==queue and added==extra and extra.toolkitQueueOperation==secondRead.toolkitQueueOperation,
                'native addAfter keeps both result values and child ownership')
        else
            operations.runWith(secondRead.toolkitQueueOperation,function() queue:addToQueue(extra) end)
        end
    end
    local nativeSession=TidyFixture.sessions[player]
    assert(nativeSession.armed and nativeSession.transferredItems[first].hasFollowingOperation,
        'actual installed Tidy observes pickup plus following operation')
    firstPickup:perform(); firstRead:perform()
    if secondPickup then secondPickup:perform() end
    secondRead:perform(); if extra then extra:perform() end
    inventory.values=shared and {first} or {first,second}
    return first,second,firstRead.toolkitQueueOperation,secondRead.toolkitQueueOperation,nativeSession
end
local function findReturn(value)
    for _,action in ipairs(queue.queue) do if action.Type=='ISInventoryTransferAction' and action.item==value then return action end end
end
-- Disabling native merge boundaries cannot lend an older source record to another task.
do
    local previousRound,previousOnline,previousVehiclePart=round,player.getOnlineID,inventory.getVehiclePart
    local previousExists,previousLookup=tidyBag.isExistYet,tidyBag.getItemById
    local actualPolicy
    round=function(value)return value end
    player.getOnlineID=function()return 101 end
    inventory.getVehiclePart=function()end
    tidyBag.isExistYet=function()return true end
    for _,mode in ipairs({'same-owner','foreign','foreign-retired','endpoint','callback','removed-not-wiped','wash-foreign'})do
        local first,second
        if mode=='wash-foreign'then
            reset();first=item(bag,27001)
            local pickup=wash(first);pickup:perform()
            local washing=queue.queue[1];washing:perform();washing:complete()
            local returning=queue.queue[1]
            assert(returning.Type=='ISInventoryTransferAction'and not returning.onCompleteFunc
                and compat.fixtureRegistries[1][returning].id=='WashFix',
                'actual Wash callback must enqueue its own merge-compatible native return')
            second=item(inventory,27002)
            local native=ISInventoryTransferAction:new(player,second,inventory,bag)
            native:setAllowMissingItems(true);ISTimedActionQueue.add(native)
        else first,second=tidyTasks(false,nil,true,mode=='same-owner');tickTidy();tickTidy() end
        tidyBag.getItemById=function(_,id)
            for _,value in ipairs({first,second})do if value:getID()==id and value.container==tidyBag then return value end end
        end
        local action,child=queue.queue[1],queue.queue[2]
        assert(action and child and findReturn(first) and findReturn(second),'fixture must queue both native returns')
        local childItem=child.item
        local token,childToken=action.toolkitQueueOperation,child.toolkitQueueOperation
        assert((token==childToken)==(mode=='same-owner'),'fixture must preserve the requested native operation owners: '..mode)
        for _,value in ipairs({first,second})do
            value.getWeight=function()return 0.05 end
            value.getUnequippedWeight=value.getWeight
            value.setJobDelta=function()end
            value.getIsCraftingConsumed=function()return false end
        end
        for _,value in ipairs({action,child})do
            value.queueList={{items={value.item},time=10,type=value.item:getFullType()}}
            value.maxTime,value.fixtureNativeGroup=10,true
        end
        local destination,callback=child.destContainer,child.onCompleteFunc
        if mode=='endpoint'then child.destContainer=inventory
        elseif mode=='callback'then child.onCompleteFunc=function()end end
        enabled=false
        if mode=='same-owner'then
            -- Native checkQueueList is a no-op for an action outside its queue.
            -- The observer must stay installed for the following real merges.
            local rows=queue.queue;queue.queue={};action:checkQueueList();queue.queue=rows
        end
        if mode=='foreign-retired'or mode=='wash-foreign'then
            PZSurvivorToolkit.ActionQueue.updateOperationState(queue);compat.prune()
            assert(token.toolkitCancelled and not compat.fixtureRegistries[2][player],
                'disabled queue retirement must precede the mixed native merge')
        end
        local wipe=table.wipe
        if mode=='removed-not-wiped'then table.wipe=function()end end
        action:checkQueueList()
        table.wipe=wipe
        local merged=mode~='endpoint'and mode~='callback'
        assert((queue:indexOf(child)==-1)==merged,'native merge must respect the '..mode..' barrier')
        if merged then
            assert(action.queueList[1].items[2]==childItem and action.toolkitQueueOperation==token,
                'native merge must retain the exact foreign member and original executor token')
            assert((next(child)==nil)==(mode~='removed-not-wiped'),'native child wipe proof changed')
        else child.destContainer,child.onCompleteFunc=destination,callback end
        enabled=true
        local contract,id=definitions.inspect(action)
        local mixed=mode=='foreign'or mode=='foreign-retired'or mode=='wash-foreign'
        assert((contract==nil)==mixed,'source mixed-owner edit rights survived '..mode..' native merge')
        if not mixed then assert(id=='compat.tidy-transfers'and contract.interrupt=='audited-stop',
            'unmerged/same-owner P4 return must retain its audited contract') end
        local oldPolicy=PZSurvivorToolkit.ActionQueuePolicy
        local oldBulk=PZSurvivorToolkit.BulkActions
        PZSurvivorToolkit.BulkActions={isGuardedTransfer=function()return false end}
        if not actualPolicy then
            local entries,types={},{}
            for key,value in pairs(definitions.entries)do entries[key]=value end
            for key,values in pairs(definitions.behaviorTypes)do
                types[key]={};for i,value in ipairs(values)do types[key][i]=value end
            end
            actualPolicy=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePolicy.lua'))()
            -- Keep this fixture's deliberate native input contracts; exercise
            -- the real policy decisions without registering a second owner.
            for key in pairs(definitions.entries)do definitions.entries[key]=entries[key] end
            for key in pairs(definitions.behaviorTypes)do definitions.behaviorTypes[key]=types[key] end
        else PZSurvivorToolkit.ActionQueuePolicy=actualPolicy end
        action:begin();queue.current=action
        if mixed then
            assert(actualPolicy.cancelReason(queue,action) and actualPolicy.cancelOperationReason(queue,action),
                'actual Policy must deny cancellation through an old owner of a merged source return')
        elseif mode=='same-owner'then
            assert(not actualPolicy.cancelReason(queue,action) and not actualPolicy.cancelOperationReason(queue,action),
                'actual Policy must retain same-owner P4 cancellation rights')
        end
        PZSurvivorToolkit.ActionQueuePolicy=oldPolicy;PZSurvivorToolkit.BulkActions=oldBulk
        for _,value in ipairs(queue.queue)do value:begin()end
        while queue.queue[1]do queue.queue[1]:perform()end
        tickTidy();tickTidy()
        assert(first.container==destination and second.container==destination and not TidyFixture.restoring[player]
            and not TidyFixture.sessions[player],
            'native grouped P4 effects and cleanup must finish after '..mode..' ownership validation')
    end
    -- Actual Compat transfer observation must admit Settlement's native guarded
    -- return without weakening P4's original source/instance matcher. Only the
    -- private ledger's exact owned-action binding is stubbed here; native Policy,
    -- BulkActions guard bodies and TidyIntent's observer dispatcher stay real.
    do
        reset()
        local previousPolicy,previousBulk=PZSurvivorToolkit.ActionQueuePolicy,PZSurvivorToolkit.BulkActions
        local source=read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/BulkActions.lua')
        local first=assert(source:find('function Actions.guardTransfer(',1,true))
        local last=assert(source:find('function Actions.transfer(',first,true))
        local bulk=assert(loadstring('local Actions={};local transferGuard={}\n'..source:sub(first,last-1)..'\nreturn Actions',
            '@PZSurvivorToolkit/BulkActions.lua'))()
        PZSurvivorToolkit.ActionQueuePolicy,PZSurvivorToolkit.BulkActions=actualPolicy,bulk
        local settlement=PZSurvivorToolkit.ActionQueueSettlement
        local intent=PZSurvivorToolkit.ActionQueueTidyIntent
        local beforeBegin,beforeFinish=settlement.beginPlannedReturn,settlement.finishPlannedReturn
        local owned,begun;local captures,finishes=0,0
        settlement.beginPlannedReturn=function(action,guard)
            if action~=owned then return false end
            assert(guard(action)and actualPolicy.matchesNative(action),'planned return lost full native binding proof')
            begun=action;captures=captures+1;return true
        end
        settlement.finishPlannedReturn=function(action,succeeded)
            if action~=begun then return false end
            assert(succeeded,'native planned return failed');finishes=finishes+1;begun=nil;return true
        end
        local function returning(id)
            return bulk.guardTransfer(ISInventoryTransferAction:new(player,item(inventory,id),inventory,tidyBag))
        end
        owned=returning(19401)
        assert(actualPolicy.matchesNative(owned)and actualPolicy.isOrdinaryTransfer(owned),'actual guarded return must match native Policy')
        assert(not intent.status(owned),'owned stop/no-op callback must not widen P4 source-instance permissions')
        assert(intent.begin(owned,'perform'),'actual Compat listener must capture an owned guarded planned return')
        intent.finish(owned,'perform',true)
        assert(captures==1 and finishes==1,'owned guarded return did not pair its real observer begin/finish')
        local outside=returning(19402)
        assert(not intent.begin(outside,'perform'),'valid but unowned guard cannot mint a planned return')
        for _,change in ipairs({'guard','callback','helper'})do
            local beforeCaptures,beforeFinishes=captures,finishes
            owned=returning(19403)
            local restore
            if change=='guard'then
                local original=owned.toolkitTransferGuard
                owned.toolkitTransferGuard={stop=original.stop,original=original.original}
                restore=function()owned.toolkitTransferGuard=original end
            elseif change=='callback'then
                local original=owned.onCompleteFunc;owned.onCompleteFunc=function()error('foreign completion must not run')end
                restore=function()owned.onCompleteFunc=original end
            else
                local original=ISInventoryTransferAction.getNotFullFloorSquare
                ISInventoryTransferAction.getNotFullFloorSquare=function()error('foreign helper must not run')end
                restore=function()ISInventoryTransferAction.getNotFullFloorSquare=original end
            end
            assert(not actualPolicy.matchesNative(owned)and not intent.begin(owned,'perform'),
                'forged '..change..' obtained planned native return observation')
            assert(captures==beforeCaptures and finishes==beforeFinishes,'rejected '..change..' reached the private ledger begin')
            restore()
            assert(intent.begin(owned,'perform'),'restored exact '..change..' did not regain its native observation')
            intent.finish(owned,'perform',true)
            assert(captures==beforeCaptures+1 and finishes==beforeFinishes+1,'restored '..change..' did not pair its native observer finish')
        end
        local ordinary=ISInventoryTransferAction:new(player,item(inventory,19404),inventory,tidyBag)
        assert(intent.status(ordinary),'unchanged P4 source instance lost its own ordinary pickup guard')
        local sourcePolicy=P4TidyUpMeister.registerActionPolicy
        P4TidyUpMeister.registerActionPolicy=function()end
        assert(not intent.status(ordinary),'planned return migration widened a changed P4 owner proof')
        P4TidyUpMeister.registerActionPolicy=sourcePolicy
        assert(intent.status(ordinary),'restored exact P4 owner did not regain source permissions')
        settlement.beginPlannedReturn,settlement.finishPlannedReturn=beforeBegin,beforeFinish
        PZSurvivorToolkit.ActionQueuePolicy,PZSurvivorToolkit.BulkActions=previousPolicy,previousBulk
        reset()
    end
    round,player.getOnlineID,inventory.getVehiclePart=previousRound,previousOnline,previousVehiclePart
    tidyBag.isExistYet,tidyBag.getItemById=previousExists,previousLookup
end
-- The native boundary owns only audited Tidy transfers, including completion after cancellation.
do
    local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    local client,actions,completed=isClient,player.getCharacterActions,queue.onCompleted
    local settlement=PZSurvivorToolkit.ActionQueueSettlement
    local beginReturn,online=settlement.beginReturn,player.getOnlineID
    local returnAttempts,returnCaptures=0,0
    local expectedReturn
    player.getOnlineID=function() return 101 end
    settlement.beginReturn=function(action,obligation,guard)
        if action~=expectedReturn then return beginReturn(action,obligation,guard) end
        local record=compat.fixtureRegistries[1][action]
        assert(record and record.obligation==obligation and record.settlement,
            'actual P4 cleanup must retain its minted deferred obligation')
        assert(action.item:getContainer()==inventory and guard(action),
            'cleanup observation must run before the native transfer effect')
        returnAttempts=returnAttempts+1
        local captured=beginReturn(action,obligation,guard)
        if captured then returnCaptures=returnCaptures+1 end
        return captured
    end
    local callbacks=0
    queue.onCompleted=function(self,action)
        if lifecycle.current(player)==action then
            assert(not operations.deferCompletion(self,action),'Tidy return acquired the legacy completion scope')
            callbacks=callbacks+1
        end
        return completed(self,action)
    end
    for _,mp in ipairs({false,true}) do
        for _,cancelled in ipairs({false,true}) do
            local first,second,token=tidyTasks()
            tickTidy();tickTidy()
            local action,following=findReturn(first),findReturn(second)
            local contract,id=definitions.inspect(action)
            assert(contract and id=='compat.tidy-transfers' and action.srcContainer==inventory
                and action.destContainer==tidyBag and action.toolkitQueueOperation==token,
                'exact mixed-session return did not select its own completion producer')
            local removed=false;action.action={};queue.current=action
            -- The transfer double otherwise omits native new()'s singleton list.
            action.queueList={{items={first}}}
            expectedReturn=action
            player.getCharacterActions=function()return list(removed and {} or {action.action})end
            isClient=function()return mp end
            assert(lifecycle.begin(action,'perform'))
            if cancelled then operations.invalidate(token) end
            action:perform();lifecycle.finish(action,'perform',true)
            assert(first.container==tidyBag and second.container==inventory and queue.current==action
                and queue.queue[2]==following,'native return effect or independent return order changed')
            assert(lifecycle.flush(queue)=='waiting','Tidy return advanced before native removal')
            if not mp then
                assert(lifecycle.begin(action,'complete'));action:complete();lifecycle.finish(action,'complete',true)
                assert(lifecycle.flush(queue)=='waiting','Tidy SP return ignored native removal')
            end
            removed=true
            assert(lifecycle.flush(queue)=='completed' and queue.current==following
                and lifecycle.flush(queue)==nil,'Tidy return advanced twice or lost the next operation')
            following:perform();tickTidy();tickTidy()
            assert(second.container==tidyBag and TidyFixture.restoring[player]==nil,
                'fallback return or native mixed-session cleanup failed')
            isClient=client
        end
    end
    assert(callbacks==4,'Tidy completion scope checks missed a native path')
    assert(returnAttempts==4 and returnCaptures==4,
        'actual adopted P4 cleanup must capture its singleton outcome before every native perform')
    settlement.beginReturn,player.getOnlineID=beginReturn,online
    queue.onCompleted=completed;player.getCharacterActions=actions;isClient=client
    reset();local transfer=wash(item(bag,141))
    assert(select(2,definitions.inspect(transfer))=='compat.selected-chains',
        'unmigrated Wash transfer escaped its existing completion producer')
end
-- Shared native completion owns reviewed laundering effects and child order; fallback stays available.
do
 local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
 local client,actions,completed=isClient,player.getCharacterActions,queue.onCompleted
 local callbacks=0
 queue.onCompleted=function(self,action)
  if lifecycle.current(player)==action then
   assert(not operations.deferCompletion(self,action),'Wash clothing acquired the legacy completion scope inside shared lifecycle')
   callbacks=callbacks+1
  end
  return completed(self,action)
 end
 local function boundary(action,mp)
  local removed=false;action.action={};queue.current=action
  player.getCharacterActions=function()return list(removed and{}or{action.action})end
  assert(lifecycle.begin(action,'perform'))
  action:perform();lifecycle.finish(action,'perform',true)
  assert(queue.current==action and lifecycle.flush(queue)=='waiting','Wash advanced before its native removal/complete')
  if not mp then
   assert(lifecycle.begin(action,'complete'));action:complete();lifecycle.finish(action,'complete',true)
   assert(lifecycle.flush(queue)=='waiting','SP Wash ignored native removal')
  end
  removed=true
  assert(lifecycle.flush(queue)=='completed'and lifecycle.flush(queue)==nil,'Wash completion did not advance exactly once')
 end
 for _,mp in ipairs({false,true})do
  reset();isClient=function()return mp end
  local value=item(bag,28100);value.class='Clothing'
  local pickup=wash(value);local later=tail();local before=consumed
  assert(select(2,definitions.inspect(pickup))=='compat.wash-clothing','real garment selected the legacy producer')
  boundary(pickup,mp)
  local laundering,returning=queue.queue[1],queue.queue[2]
  assert(laundering.Type=='ISWashClothing'and returning.Type=='ISInventoryTransferAction'and queue.queue[3]==later,
   'native pickup continuation lost wash/return/independent tail order')
  boundary(laundering,mp)
  if mp then laundering:complete()end -- authoritative completion is separately delivered in MP
  assert(consumed==before+1,'laundering did not call its original native completion once')
  boundary(returning,mp)
  assert(value.container==bag and queue.queue[1]==later,'native same-ID return or independent tail was lost')
  pickup.onCompleteFunc(unpack(pickup.onCompleteArgs))
  assert(#queue.queue==1 and consumed==before+1,'late native pickup completion replayed washing')
 end
 assert(callbacks==6,'shared laundering fixture missed a native pickup/wash/return path')
 queue.onCompleted,player.getCharacterActions,isClient=completed,actions,client
 reset()
 print('PASS Wash clothing shared native SP/MP boundary, original once-only effect and same-ID return before independent tail')
end

-- Observe native stop before the original delegate clears the queue. An
-- observer failure cannot suppress/repeat that delegate or its native reset.
do
    local settlement=PZSurvivorToolkit.ActionQueueSettlement
    local originalStop,online=settlement.stopReturn,player.getOnlineID
    local resetQueue=queue.resetQueue
    local captures,resets=0,0
    player.getOnlineID=function()return 101 end
    queue.resetQueue=function(self,...)
        resets=resets+1
        return resetQueue(self,...)
    end
    for _,failObserver in ipairs({false,true})do
        local first=tidyTasks()
        tickTidy();tickTidy()
        local action=assert(findReturn(first))
        local record=assert(compat.fixtureRegistries[1][action])
        action.action={isStarted=function()return true end};action.queueList={{items={first}}};queue.current=action
        local beforeResets=resets
        settlement.stopReturn=function(candidate,obligation,guard)
            assert(candidate==action and queue.current==action and queue.queue[1]==action and guard(candidate),
                'P4 stop receipt must be captured before native queue reset')
            captures=captures+1
            if failObserver then error('fixture observer failure')end
            return originalStop(candidate,obligation,guard)
        end
        action:stop()
        assert(resets==beforeResets+1 and #queue.queue==0,'native stop delegate must execute exactly once')
        if not failObserver then
            local history=settlement.returnAttempts(record.obligation)
            assert(#history==1 and history[1].phase=='stop' and history[1].state=='unavailable',
                'unconfirmed native stop cannot mint a completed transfer')
        end
    end
    assert(captures==2)
    settlement.stopReturn,player.getOnlineID=originalStop,online
    queue.resetQueue=resetQueue
    reset()
end
-- A real reviewed late constructor install must not silently turn laundering back into untracked native work.
do
 local saved={owner=SaucedCarts,client=isClient,events=Events,carts=PZSurvivorToolkit.ActionQueueCarts,
  new=ISInventoryTransferAction.new,perform=ISInventoryTransferAction.perform,transferItem=ISInventoryTransferAction.transferItem,
  start=ISInventoryTransferAction.start,latest=lateCartProof.latest,enabled=lateCartProof.enabled,
  checker=lateCartProof.isTransferConstructor,consumed=consumed}
 local hooks={}
 Events=setmetatable({},{__index=function(owner,name)local event={Add=function(callback)hooks[#hooks+1]=callback end};rawset(owner,name,event);return event end})
 SaucedCarts={safeIsCart=function()return false end,log=function()end,debug=function()end,error=function(message)error(message)end}
 isClient=function()return false end
 local source=read(NativeWishlistWorkshopRoot..'/3651954650/mods/SaucedCarts/42/media/lua/shared/SaucedCarts/CartTransferInterceptor.lua')
 assert(loadstring(source,'@SaucedCarts/CartTransferInterceptor.lua'))()
 local installed=ISInventoryTransferAction.new
 assert(installed~=saved.new and SaucedCarts.CartTransferInterceptor.isInstalled()
  and getFilenameOfClosure(installed):match('CartTransferInterceptor%.lua$'),'actual upstream late transfer constructor did not install')
 Events=saved.events
 local approved={new=installed,perform=saved.perform,transferItem=saved.transferItem}
 lateCartProof.constructors[saved.new],lateCartProof.constructors[installed]=true,true
 local function install()
  PZSurvivorToolkit.ActionQueueCarts=lateCartProof;lateCartProof.enabled=true;lateCartProof.isTransferConstructor=saved.checker
  lateCartProof.latest=approved
  ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem=installed,saved.perform,saved.transferItem
  ISInventoryTransferAction.start=saved.start
 end
 for _,mode in ipairs({'enabled','disabled','revoked','foreign-new','foreign-perform','foreign-start','foreign-api','foreign-owner'})do
  install();reset()
  if mode=='disabled'then enabled=false
  elseif mode=='revoked'then lateCartProof.enabled=false
  elseif mode=='foreign-new'then ISInventoryTransferAction.new=function(...)return installed(...)end
  elseif mode=='foreign-perform'then ISInventoryTransferAction.perform=function(...)return saved.perform(...)end
  elseif mode=='foreign-start'then ISInventoryTransferAction.start=function()end
  elseif mode=='foreign-api'then lateCartProof.isTransferConstructor=function()return true end
  elseif mode=='foreign-owner'then PZSurvivorToolkit.ActionQueueCarts={isTransfer=saved.carts.isTransfer,isReturn=saved.carts.isReturn}end
  local value=item(bag,28201);value.class='Clothing'
  local pickup=wash(value);local later=tail()
  if mode=='enabled'then
   assert(select(2,definitions.inspect(pickup))=='compat.wash-clothing','real approved late constructor lost Wash pickup adoption')
   pickup:perform()
   local laundering,returning=queue.queue[1],queue.queue[2]
   assert(select(2,definitions.inspect(laundering))=='compat.wash-clothing'
    and select(2,definitions.inspect(returning))=='compat.wash-clothing'and queue.queue[3]==later,
    'real late constructor lost audited wash/return callback propagation')
   laundering:perform();laundering:complete();returning:perform()
   assert(value.container==bag and queue.queue[1]==later,'approved late install changed original native return or tail')
  else
   assert(select(2,definitions.inspect(pickup))~='compat.wash-clothing','unknown late binding gained laundering permission: '..mode)
   if mode=='disabled'then
    pickup:perform();local laundering,returning=queue.queue[1],queue.queue[2]
    laundering:perform();laundering:complete();returning:perform()
    assert(value.container==bag and queue.queue[1]==later,'disabled late-install fallback lost native effects/return')
   end
  end
 end
 install();reset()
 local value=item(bag,28202);value.class='Clothing';local pickup=wash(value);local later=tail()
 assert(definitions.inspect(pickup),'positive late-install proof missing before helper mutation')
 ISInventoryTransferAction.start=function()end
 assert(not definitions.inspect(pickup),'late foreign helper retained existing Wash proof')
 pickup:perform();assert(queue.queue[1]==later,'invalidated late binding revived an audited continuation')
 ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem,ISInventoryTransferAction.start=saved.new,saved.perform,saved.transferItem,saved.start
 lateCartProof.latest,lateCartProof.enabled,lateCartProof.isTransferConstructor=saved.latest,saved.enabled,saved.checker
 PZSurvivorToolkit.ActionQueueCarts,SaucedCarts,isClient,Events=saved.carts,saved.owner,saved.client,saved.events
 consumed=saved.consumed;reset()
 print('PASS actual reviewed late transfer installer retains Wash adoption/native fallback and rejects unknown bindings')
end

-- The actual P4 source may restore ordinary items after approved hooks changed the shared transfer class.
do
    local methods={new=ISInventoryTransferAction.new,perform=ISInventoryTransferAction.perform,
        transferItem=ISInventoryTransferAction.transferItem,start=ISInventoryTransferAction.start}
    local proof=lateCartProof.isTransferConstructor
    local wrapped={new=function(...)return methods.new(...)end,perform=function(...)return methods.perform(...)end,
        transferItem=function(...)return methods.transferItem(...)end}
    lateCartProof.constructors[methods.new],lateCartProof.constructors[wrapped.new]=true,true
    lateCartProof.latest=wrapped
    local function install()
        PZSurvivorToolkit.ActionQueueCarts=lateCartProof;lateCartProof.enabled=true;lateCartProof.isTransferConstructor=proof
        for name,method in pairs(wrapped)do ISInventoryTransferAction[name]=method end
        ISInventoryTransferAction.start=methods.start
    end
    local function restores()
        local first,second,token=tidyTasks();tickTidy();tickTidy()
        local action=findReturn(first)
        assert(action and action.srcContainer==inventory and action.destContainer==tidyBag,
            'late-hook fixture must use an actual ordinary P4 source return')
        return first,second,token,action,findReturn(second)
    end
    local function drain()
        while queue.queue[1]do queue.queue[1]:perform()end
        tickTidy();tickTidy()
    end
    local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    local client,actions,completed=isClient,player.getCharacterActions,queue.onCompleted
    for _,mp in ipairs({false,true})do
        install()
        local first,second,token,action,following=restores()
        assert(select(2,definitions.inspect(action))=='compat.tidy-transfers',
            'approved late hooks must retain the real P4 transfer contract')
        token=action.toolkitQueueOperation
        local removed,callbacks=false,0
        action.action={};queue.current=action
        player.getCharacterActions=function()return list(removed and {}or{action.action})end
        isClient=function()return mp end
        queue.onCompleted=function(self,current)
            if current==action and lifecycle.current(player)==action then
                assert(not operations.deferCompletion(self,current),'approved late P4 return acquired legacy scope')
                callbacks=callbacks+1
            end
            return completed(self,current)
        end
        assert(lifecycle.begin(action,'perform'));action:perform();lifecycle.finish(action,'perform',true)
        assert(callbacks==1,'approved late return missed the shared onCompleted scope')
        assert(first.container==tidyBag and second.container==inventory,'approved late return changed exact effects')
        assert(queue.current==action and action.toolkitQueueOperation==token and queue.queue[2]==following,
            'approved late return lost ownership or order')
        if not mp then
            assert(lifecycle.begin(action,'complete'));action:complete();lifecycle.finish(action,'complete',true)
        end
        assert(lifecycle.flush(queue)=='waiting');removed=true
        assert(lifecycle.flush(queue)=='completed'and queue.current==following and lifecycle.flush(queue)==nil)
        queue.onCompleted=completed;player.getCharacterActions=actions;isClient=client;drain()
        assert(second.container==tidyBag and TidyFixture.restoring[player]==nil)
    end
    for _,change in ipairs({'revoked','new','perform','api','owner','class','instance','endpoint'})do
        install()
        local _,_,_,action=restores()
        assert(definitions.inspect(action),'late-hook positive control missing before '..change)
        if change=='revoked'then lateCartProof.enabled=false
        elseif change=='new'then ISInventoryTransferAction.new=function(...)return wrapped.new(...)end
        elseif change=='perform'then ISInventoryTransferAction.perform=function(...)return wrapped.perform(...)end
        elseif change=='api'then lateCartProof.isTransferConstructor=function()return true end
        elseif change=='owner'then PZSurvivorToolkit.ActionQueueCarts={}
        elseif change=='class'then ISInventoryTransferAction.start=function()end
        elseif change=='instance'then action.start=function()end
        elseif change=='endpoint'then action.destContainer=inventory end
        assert(not definitions.inspect(action),'late-hook proof accepted changed '..change)
        if change=='instance'then action.start=nil end
        if change=='endpoint'then action.destContainer=tidyBag end
        install();drain()
    end
    for _,change in ipairs({'revoked','new','perform','api','class'})do
        install();local first=tidyTasks()
        if change=='revoked'then lateCartProof.enabled=false
        elseif change=='new'then ISInventoryTransferAction.new=function(...)return wrapped.new(...)end
        elseif change=='perform'then ISInventoryTransferAction.perform=function(...)return wrapped.perform(...)end
        elseif change=='api'then lateCartProof.isTransferConstructor=function()return true end
        elseif change=='class'then ISInventoryTransferAction.start=function()end end
        tickTidy();tickTidy()
        local action=assert(findReturn(first),'unapproved hooks must preserve native P4 restore')
        assert(not definitions.inspect(action)and action.perform==ISInventoryTransferAction.perform,
            'unapproved late hooks gained adoption: '..change)
        install();drain()
    end
    install();reset()
    local transfer=wash(item(bag,142))
    assert(not definitions.inspect(transfer),'P4 late-hook exception must not grant Wash transfer rights')
    drain()
    for name,method in pairs(methods)do ISInventoryTransferAction[name]=method end
    PZSurvivorToolkit.ActionQueueCarts=priorCarts
end
local firstItem,secondItem,firstToken,secondToken,nativeSession=tidyTasks()
tickTidy(); tickTidy()
local firstReturn,secondReturn=findReturn(firstItem),findReturn(secondItem)
assert(firstReturn and secondReturn and firstReturn.toolkitQueueOperation==firstToken
    and secondReturn.toolkitQueueOperation==secondToken and definitions.inspect(firstReturn).cancelOperation~=false
    and definitions.inspect(secondReturn).cancelOperation~=false,
    'unique exact returns from a real mixed native session retain their respective task owners')
local returnContract=definitions.inspect(firstReturn)
assert(returnContract.containerOwners[tidyBagOwner:getID()] and not returnContract.items[tidyBagOwner:getID()],
    'compat restore references the carried bag without treating its owner as a consumed item')
-- Native completion of an already running step is never suppressed by a late token invalidation.
operations.invalidate(firstToken); firstReturn:perform(); secondReturn:perform()
assert(firstItem.container==tidyBag and secondItem.container==tidyBag)
tickTidy(); tickTidy()
assert(TidyFixture.sessions[player]==nil and TidyFixture.restoring[player]==nil,'late native completion cleans the mixed session')
firstItem,secondItem,firstToken,secondToken=tidyTasks()
operations.invalidate(firstToken); tickTidy(); tickTidy()
assert(not findReturn(firstItem) and findReturn(secondItem).toolkitQueueOperation==secondToken,
    'partial cancellation suppresses only the cancelled unique late return')
secondReturn=findReturn(secondItem); secondReturn:perform(); tickTidy(); tickTidy()
assert(firstItem.container==inventory and secondItem.container==tidyBag and TidyFixture.restoring[player]==nil)
firstItem,secondItem,firstToken,secondToken=tidyTasks(true)
operations.invalidate(firstToken); tickTidy(); tickTidy()
firstReturn=findReturn(firstItem)
assert(firstReturn and definitions.inspect(firstReturn).cancelOperation==false
    and firstReturn.toolkitQueueOperation~=firstToken and firstReturn.toolkitQueueOperation~=secondToken,
    'another task using the same item without pickup makes its return shared protected cleanup')
firstReturn:perform(); assert(firstItem.container==tidyBag); tickTidy(); tickTidy()
firstItem,secondItem,firstToken,secondToken=tidyTasks()
enabled=false; tickTidy(); tickTidy()
firstReturn,secondReturn=findReturn(firstItem),findReturn(secondItem)
assert(firstReturn and secondReturn and select(2,definitions.inspect(firstReturn))=='fixture.native-tidy-inputs'
    and firstReturn.perform==nativeTransferPerform and secondReturn.perform==nativeTransferPerform,
    'disabling the setting before the native restore event preserves native returns without adapter rights')
firstReturn:perform(); secondReturn:perform(); tickTidy(); tickTidy()
assert(firstItem.container==tidyBag and secondItem.container==tidyBag and TidyFixture.restoring[player]==nil)
firstItem,secondItem=tidyTasks()
ISInventoryTransferAction.getNotFullFloorSquare=function() end; tickTidy(); tickTidy()
firstReturn,secondReturn=findReturn(firstItem),findReturn(secondItem)
assert(firstReturn and secondReturn and not definitions.inspect(firstReturn) and not definitions.inspect(secondReturn),
    'a changed native floor helper does not gain restore contracts from the pinned Tidy source')
ISInventoryTransferAction.getNotFullFloorSquare=pinnedFloorHelper
firstReturn:perform(); secondReturn:perform(); tickTidy(); tickTidy()
assert(TidyFixture.restoring[player]==nil)
for _,inputMode in ipairs({'unknown','dynamic'}) do
    unknownInput,dynamicInput=inputMode=='unknown',inputMode=='dynamic'
    firstItem,secondItem,firstToken,secondToken=tidyTasks()
    unknownInput,dynamicInput=nil,nil; tickTidy(); tickTidy()
    assert(definitions.inspect(findReturn(firstItem)).cancelOperation==false
        and definitions.inspect(findReturn(secondItem)).cancelOperation==false,
        inputMode..' inputs in another task prevent claiming an exclusive restore owner')
    findReturn(firstItem):perform(); findReturn(secondItem):perform(); tickTidy(); tickTidy()
end
for _,insertion in ipairs({'after','direct'}) do
    firstItem,secondItem,firstToken,secondToken=tidyTasks(false,insertion)
    operations.invalidate(firstToken); tickTidy(); tickTidy()
    firstReturn=findReturn(firstItem)
    assert(firstReturn and definitions.inspect(firstReturn).cancelOperation==false
        and firstReturn.toolkitQueueOperation~=firstToken,
        'shared input introduced by '..insertion..' queue API retains protected shared cleanup')
    firstReturn:perform(); findReturn(secondItem):perform(); tickTidy(); tickTidy()
end
-- Retiring adapter history must not disable stock P4's delayed callback. Its
-- fallback may still return the items, but cannot reuse a departed task owner.
do
    local settlement=PZSurvivorToolkit.ActionQueueSettlement
    local records,sessions=unpack(compat.fixtureRegistries)
    local function hasEntries(values) for _ in pairs(values) do return true end return false end
    for _,boundary in ipairs({'dead','reset','menu'}) do
        local first,second,firstOwner,secondOwner=tidyTasks()
        compat.prune()
        local departed=assert(sessions[player])
        assert(not hasEntries(departed.seen) and hasEntries(departed.tasks),
            boundary..': delayed P4 regression must outlive all seen source actions')
        local oldContext=settlement.context(departed)
        local cleanupOwner=oldContext.token
        if boundary=='dead' then dead=true
        elseif boundary=='reset' then queue.toolkitOperationGeneration=(queue.toolkitOperationGeneration or 0)+1
        else for _,callback in ipairs(events.OnMainMenuEnter or {})do callback()end end
        compat.prune()
        assert(not sessions[player] and not settlement.isLive(oldContext),
            boundary..': departed P4 history must release its shared settlement')
        tickTidy();tickTidy()
        local nativeFirst,nativeSecond=findReturn(first),findReturn(second)
        assert(nativeFirst and nativeSecond,'stock P4 delayed fallback must remain available after '..boundary)
        for _,action in ipairs({nativeFirst,nativeSecond})do
            assert(not records[action] and action.perform==nativeTransferPerform
                and action.toolkitQueueOperation~=firstOwner and action.toolkitQueueOperation~=secondOwner
                and action.toolkitQueueOperation~=cleanupOwner,
                boundary..': native fallback inherited old adopted P4 ownership')
        end
        nativeFirst:perform();nativeSecond:perform();tickTidy();tickTidy()
        assert(first.container==tidyBag and second.container==tidyBag and not TidyFixture.restoring[player],
            boundary..': retiring adapter ownership changed native fallback effects or cleanup')
        dead=false
        local freshFirst,freshSecond,freshOwner,otherOwner=tidyTasks()
        tickTidy();tickTidy()
        local freshReturn,otherReturn=findReturn(freshFirst),findReturn(freshSecond)
        assert(freshReturn and otherReturn and freshReturn.toolkitQueueOperation==freshOwner
            and otherReturn.toolkitQueueOperation==otherOwner
            and freshOwner~=firstOwner and freshOwner~=secondOwner and freshOwner~=cleanupOwner
            and select(2,definitions.inspect(freshReturn))=='compat.tidy-transfers',
            boundary..': a later same-ID P4 session must retain only its new task owners')
        freshReturn:perform();otherReturn:perform();tickTidy();tickTidy()
    end
end
firstItem,secondItem,firstToken,secondToken,nativeSession=tidyTasks()
local nativeClient=isClient
isClient=function() return true end
TidyFixture.options.DebugOutput.selected=1
nativeSession.floorItems[firstItem:getFullType()]={square=square,offX=0,offY=0,offZ=0,rotationX=0,rotationY=0,rotationZ=0}
local tidyFloor={class='ItemContainer',getParent=function() return square end,getType=function() return 'floor' end,
    getContainingItem=function() end}
nativeSession.transferredItems[firstItem].container=tidyFloor
getPlayerLoot=function() return {backpacks={{inventory=tidyBag},{inventory=tidyFloor}}} end
tickTidy(); tickTidy()
assert(findReturn(firstItem).destContainer==tidyFloor and not definitions.inspect(findReturn(firstItem)),
    'mixed native floor return keeps its native transfer without adapter rights')
local floorRestores=0
for _,action in ipairs(queue.queue) do
    if action.Type=='P4RestoreFloorAction' then
        floorRestores=floorRestores+1
        assert(not definitions.inspect(action),'mixed native MP floor cleanup remains opaque')
    end
end
assert(floorRestores==2,'actual installed Tidy builds MP floor cleanup without toolkit rights')
while queue.queue[1] do queue.queue[1]:perform() end
isClient=nativeClient; tickTidy(); tickTidy()
assert(TidyFixture.restoring[player]==nil and TidyFixture.restoreFloor[player]==nil)
-- Nonmixed MP floor placement remains legacy, with its exact server placement fields pinned.
do
    reset();doNotReequip=false;player.primary,player.secondary=nil,nil
    local value=item(tidyBag,144)
    local pickup,readAction
    operations.run(function()
        pickup=ISInventoryTransferAction:new(player,value,tidyBag,inventory);ISTimedActionQueue.add(pickup)
        readAction=ISReadABook:new(player,value);ISTimedActionQueue.add(readAction)
    end)
    local captured=TidyFixture.sessions[player]
    captured.transferredItems[value].container=tidyFloor
    captured.floorItems[value:getFullType()]={square=square,offX=0.1,offY=0.2,offZ=0.3,
        rotationX=10,rotationY=20,rotationZ=30}
    pickup:perform();readAction:perform();inventory.values={value}
    local cell=getCell
    getCell=function()return {getGridSquare=function()return square end}end
    isClient=function()return true end
    tickTidy();tickTidy()
    local floorAction
    for _,action in ipairs(queue.queue)do if action.Type=='P4RestoreFloorAction'then floorAction=action end end
    local contract,id=definitions.inspect(floorAction)
    assert(contract and id=='compat.selected-chains'and contract.interrupt=='finish-step',
        'nonmixed floor placement must keep its existing protected completion contract')
    for _,field in ipairs({'offX','offY','offZ','rotationX','rotationY','rotationZ'})do
        local previous=floorAction[field];floorAction[field]=previous+1
        assert(not definitions.inspect(floorAction),'floor placement accepted changed '..field)
        floorAction[field]=previous;assert(definitions.inspect(floorAction))
    end
    while queue.queue[1]do queue.queue[1]:perform()end
    isClient=nativeClient;getCell=cell;tickTidy();tickTidy()
end
-- Host can retain the old floor proxy after the authoritative transfer recreates its exact ID in root.
do
    local client,multi,cell,loot=isClient,isMultiplayer,getCell,getPlayerLoot
    local cached=ISInventoryPage.floorContainer[1]
    local floor={class='ItemContainer',getParent=function()return square end,getType=function()return 'floor'end,
        getContainingItem=function()end,values={},getItemById=function(self,id)
            for _,value in ipairs(self.values)do if value:getID()==id then return value end end
        end}
    ISInventoryPage.floorContainer[1]=floor
    getCell=function()return {getGridSquare=function()return square end}end
    local floorLoot={player=0,onCharacter=false,refreshBackpacks=nativeFloorRefresh,
        backpacks={{inventory=tidyBag},{inventory=floor}}}
    getPlayerLoot=function()return floorLoot end
    local function worldItem(id)
        local value=item(floor,id)
        local world={getSquare=function()return square end,getItem=function()return value end}
        value.getWorldItem=function()return world end
        return value
    end
    local function clearIntent()
        for _,callback in ipairs(events.OnMainMenuEnter or {})do callback()end
    end
    local function placement(value)
        return P4RestoreFloorAction:new(player,value,0,0,0,0.1,0.2,0.3,10,20,30,false)
    end
    local function drain()
        while queue.queue[1]do queue.queue[1]:perform()end
        tickTidy();tickTidy()
    end
    for _,queueEnabled in ipairs({true,false})do
        for _,staleFloor in ipairs({true,false})do
            clearIntent()
            local old,second,firstToken,_,captured=tidyTasks(false,nil,queueEnabled)
            captured.transferredItems[old].container=floor
            captured.floorItems[old:getFullType()]={square=square,offX=0.1,offY=0.2,offZ=0.3,rotationX=10,rotationY=20,rotationZ=30}
            local live=item(inventory,old:getID());inventory.values={live,second};old.container=staleFloor and floor or nil
            isClient=function()return true end;isMultiplayer=function()return true end
            tickTidy();tickTidy()
            local transfers,relocations,returned,placementAction=0,0
            for index,action in ipairs(queue.queue)do
                if action.Type=='ISInventoryTransferAction'and action.item==live and action.destContainer==floor then
                    transfers=transfers+1
                    local following=queue.queue[index+1]
                    assert(following.Type=='P4RestoreFloorAction'and following.item==live,
                        'exact rebound transfer must precede its native relocation')
                    returned,placementAction=action,following
                    assert((not queueEnabled or not definitions.inspect(action))and not definitions.inspect(following),
                        'mixed floor repair must not gain queue edit rights')
                end
                if action.Type=='P4RestoreFloorAction'and action.item:getID()==old:getID()then
                    relocations=relocations+1;assert(action.item==live,'Host floor relocation retained its stale proxy')
                end
            end
            assert(transfers==1 and relocations==1,'Host floor rebound lost or duplicated its actual P4 return pair')
            assert(old:getContainer()==(staleFloor and floor or nil),'repair mutated the stale source proxy')
            local replica
            if staleFloor then
                assert(compat.fixtureFloorRepairs[placementAction], 'actual Host floor repair must own its queued receipt')
                -- Native MP removes the held proxy and receives a new world replica before relocation starts.
                returned:perform();live.container=nil
                replica=worldItem(live:getID());floor.values={};floorLoot.worldItems={replica}
                firstToken.toolkitCancelled=true
                local refreshed=floorLoot.refreshCount or 0
                assert(placementAction:isValid()and placementAction.item==replica,
                    'actual P4 repaired relocation did not resolve its post-transfer world replica')
                assert(floorLoot.refreshCount==refreshed+1 and placementAction:isValid()
                    and floorLoot.refreshCount==refreshed+1,'cached exact replica must not repeatedly refresh native UI')
                assert(not definitions.inspect(placementAction),'mixed floor validation widened opaque queue rights')
            end
            drain();assert((replica or live):getContainer()==floor and TidyFixture.restoring[player]==nil)
            compat.prune()
            assert(not compat.fixtureFloorRepairs[placementAction], 'completed Host placement must release its repair receipt')
            isClient,isMultiplayer=client,multi
        end
    end
    -- Source callback emission exercises the same owned hook without adding a queue permission contract.
    for _,queueEnabled in ipairs({true,false})do
        for _,change in ipairs({'none','wrapped-refresh','missing','id','type','root','world','world-item','far','target','pose','debug','item',
            'callback','instance','class','owner','getter','refresh','missing-refresh','loot-api','loot-method','loot-player','loot-character',
            'generation','removed','cancelled'})do
            clearIntent();reset();enabled=queueEnabled;doNotReequip=false
            -- No prior tick has initialized this mode, as on the first return
            -- after entering the world or disabling the queue in settings.
            queue.toolkitOperationsInvalid=nil
            if change=='none'then queue.toolkitOperationGeneration=nil end
            local generation=queue.toolkitOperationGeneration or 0
            isClient=function()return true end
            local old,held=item(floor,148),item(inventory,148);inventory.values={held}
            local action=placement(old)
            local getter,refresh,lootAPI,owner=ISInventoryPage.GetFloorContainer,ISInventoryPage.refreshBackpacks,getPlayerLoot,P4TidyUpMeister
            local nativeValid=P4RestoreFloorAction.isValid
            compat.fixtureRepairTidyFloor(player,function()ISTimedActionQueue.add(action)end)
            assert(compat.fixtureFloorRepairs[action].generation == (queue.toolkitOperationGeneration or 0),
                'native enqueue invalidated a fresh floor receipt queue='..tostring(queueEnabled))
            assert((queue.toolkitOperationGeneration or 0) == generation + (queueEnabled and 0 or 1),
                'first enqueue must initialize disabled bookkeeping exactly once')
            assert(#queue.queue==2 and action.item==held,'owned relocation fixture failed to create exact return pair')
            queue.queue[1]:perform();held.container=nil
            assert(compat.fixtureFloorRepairs[action].generation == (queue.toolkitOperationGeneration or 0),
                'beginning the placement invalidated its transfer receipt')
            local replica=worldItem(148);floor.values={};floorLoot.worldItems={replica}
            floorLoot.player,floorLoot.onCharacter,floorLoot.refreshBackpacks=0,false,nativeFloorRefresh
            if change=='missing'then floorLoot.worldItems={}
            elseif change=='id'then replica.id=149
            elseif change=='type'then replica.getFullType=function()return 'Base.Other'end
            elseif change=='root'then floorLoot.worldItems={};held.container=inventory;inventory.values={held}
            elseif change=='world'then replica.getWorldItem=function()end
            elseif change=='world-item'then replica.getWorldItem=function()return {getSquare=function()return square end,getItem=function()return held end}end
            elseif change=='far'then replica.getWorldItem=function()return {getSquare=function()return {getX=function()return 3 end,getY=function()return 0 end,getZ=function()return 0 end}end,getItem=function()return replica end}end
            elseif change=='target'then getCell=function()return {getGridSquare=function()end}end
            elseif change=='pose'then action.offX=0.9
            elseif change=='debug'then action.debugOutput=nil
            elseif change=='item'then action.item=item(inventory,149)
            elseif change=='callback'then action.onCompleteFunc=function()end
            elseif change=='instance'then action.start=function()end
            elseif change=='class'then P4RestoreFloorAction.isValid=function()return true end
            elseif change=='owner'then P4TidyUpMeister={}
            elseif change=='getter'then ISInventoryPage.GetFloorContainer=function()return floor end
            elseif change=='wrapped-refresh'then
                ISInventoryPage.refreshBackpacks=function(self)return nativeFloorRefresh(self)end
                floorLoot.refreshBackpacks=ISInventoryPage.refreshBackpacks
            elseif change=='refresh'then
                ISInventoryPage.refreshBackpacks=function()end
                floorLoot.refreshBackpacks=ISInventoryPage.refreshBackpacks
            elseif change=='missing-refresh'then ISInventoryPage.refreshBackpacks=nil
            elseif change=='loot-api'then getPlayerLoot=function()return floorLoot end
            elseif change=='loot-method'then floorLoot.refreshBackpacks=function()end
            elseif change=='loot-player'then floorLoot.player=1
            elseif change=='loot-character'then floorLoot.onCharacter=true
            elseif change=='generation'then operations.invalidateQueue(queue)
            elseif change=='removed'then queue.queue,queue.current={},nil
            elseif change=='cancelled'then dead=true end
            local ok=nativeValid(action)
            local resolved=change=='none'or change=='wrapped-refresh'
            assert(ok==resolved,'owned floor validation accepted unsafe '..change..' queue='..tostring(queueEnabled))
            assert(action.item==(resolved and replica or change=='item'and action.item or held),
                'failed floor validation changed the retained proxy: '..change)
            assert(not definitions.inspect(action),'unadopted floor repair gained queue rights')
            assert(held.container==(change=='root'and inventory or nil),'floor validation mutated stale item container')
            ISInventoryPage.GetFloorContainer,ISInventoryPage.refreshBackpacks,getPlayerLoot,P4TidyUpMeister=getter,refresh,lootAPI,owner
            P4RestoreFloorAction.isValid=nativeValid
            floorLoot.player,floorLoot.onCharacter,floorLoot.refreshBackpacks=0,false,nativeFloorRefresh
            getCell=function()return {getGridSquare=function()return square end}end
            dead=false;queue.queue,queue.current={},nil
        end
    end
    isClient=client
    -- Direct helper checks keep the real matcher while varying the emitted source action and native refs.
    for _,change in ipairs({'none','existing','invalid-existing','missing','id','type','world','far','unloaded','callback','instance','class','owner','getter','refresh','valid-hook','error'})do
        clearIntent();reset();doNotReequip=false
        local old,live=item(floor,145),item(inventory,145);inventory.values={live}
        local action=placement(old)
        local originalStart,owner,floorGetter=ISInventoryTransferAction.start,P4TidyUpMeister,ISInventoryPage.GetFloorContainer
        local floorRefresh,floorValid=ISInventoryPage.refreshBackpacks,P4RestoreFloorAction.isValid
        if change=='missing'then inventory.values={}
        elseif change=='id'then live.id=146
        elseif change=='type'then live.getFullType=function()return 'Base.Other'end
        elseif change=='world'then live.container=floor
        elseif change=='far'then action.x=3
        elseif change=='unloaded'then getCell=function()return {getGridSquare=function()end}end
        elseif change=='callback'then action.onCompleteFunc=function()end
        elseif change=='instance'then action.start=function()end
        elseif change=='class'then ISInventoryTransferAction.start=function()end
        elseif change=='owner'then P4TidyUpMeister={}
        elseif change=='getter'then ISInventoryPage.GetFloorContainer=function()return floor end
        elseif change=='refresh'then ISInventoryPage.refreshBackpacks=function()end
        elseif change=='valid-hook'then P4RestoreFloorAction.isValid=function()return true end end
        isClient=function()return true end
        local add=ISTimedActionQueue.add
        local ok,result=pcall(function()
            return compat.fixtureRepairTidyFloor(player,function()
                if change=='existing'or change=='invalid-existing'then
                    local transfer=ISInventoryTransferAction:new(player,live,inventory,floor)
                    if change=='invalid-existing'then transfer.onCompleteFunc=function()end;transfer.onCompleteArgs={}end
                    ISTimedActionQueue.add(transfer)
                end
                ISTimedActionQueue.add(action)
                if change=='error'then error('native floor callback failed')end
                return 'native-result'
            end)
        end)
        assert(ISTimedActionQueue.add==add,'floor callback leaked its temporary add hook')
        assert(ok==(change~='error')and (not ok or result=='native-result'),'floor wrapper changed native return/error')
        local repaired=change=='none'or change=='existing'or change=='refresh'
        assert(action.item==(repaired and live or old),'floor repair accepted unsafe '..change)
        assert(#queue.queue==((repaired or change=='invalid-existing')and 2 or 1),'floor repair duplicated/removed source actions: '..change)
        if change=='refresh'then
            queue.queue[1]:perform()
            assert(not action:isValid(),'unknown no-op UI refresh must refuse late resolution, not suppress the native return pair')
        end
        ISInventoryTransferAction.start=originalStart;P4TidyUpMeister=owner;ISInventoryPage.GetFloorContainer=floorGetter
        ISInventoryPage.refreshBackpacks,P4RestoreFloorAction.isValid=floorRefresh,floorValid
        getCell=function()return {getGridSquare=function()return square end}end
        drain();isClient=client
    end
    clearIntent();reset();doNotReequip=false;player.primary,player.secondary=nil,nil
    local old,live=item(tidyBag,147),item(inventory,147)
    ISInventoryPaneContextMenu.onGrabItems({old},0)
    local pickup=queue.queue[1];pickup.fixtureRebound=live
    ISTimedActionQueue.add(ISReadABook:new(player,old))
    local captured=TidyFixture.sessions[player]
    captured.transferredItems[old].container=floor
    captured.floorItems[old:getFullType()]={square=square,offX=0,offY=0,offZ=0,rotationX=0,rotationY=0,rotationZ=0}
    inventory.values={live}
    local intent=PZSurvivorToolkit.ActionQueueTidyIntent
    intent.begin(pickup,'perform');pickup:perform();intent.finish(pickup,'perform',true)
    queue.queue[1]:perform();old.container=floor
    isClient=function()return true end;isMultiplayer=function()return true end
    tickTidy();tickTidy()
    assert(#queue.queue==0 and live:getContainer()==inventory,'explicit pickup must suppress repaired floor return and relocation together')
    local called=0
    compat.fixtureRepairTidyFloor(nil,function()called=called+1 end)
    compat.fixtureRepairTidyFloor({isLocalPlayer=function()return false end},function()called=called+1 end)
    assert(called==2,'floor wrapper changed native nil/remote early guards')
    isClient,isMultiplayer,getCell,getPlayerLoot=client,multi,cell,loot
    ISInventoryPage.floorContainer[1]=cached
end
-- P4's idle worn snapshot may still point at a bag left on the ground or taken
-- by a peer. Native Host wear start rebinds that ID to nil before dereferencing it.
do
    local client, getWorn = isClient, player.getWornItem
    isClient = function() return true end
    local worn = {}
    player.getWornItem = function(_, location) return worn[location] end
    local floor = {class = 'ItemContainer', getType = function() return 'floor' end,
        getContainingItem = function() end, getParent = function() return square end}
    local peerInventory = {class = 'ItemContainer', getType = function() return 'inventory' end,
        getContainingItem = function() end, getParent = function() end}
    local function bag(container, id)
        local value = item(container, id)
        value.class, value.equippedAt = 'InventoryContainer', 'base:back'
        value.getFullType = function() return 'Base.Bag_Schoolbag' end
        value.IsInventoryContainer = function() return true end
        value.getWorldItem = function() end
        return value
    end
    local function clearIntent()
        for _, callback in ipairs(events.OnMainMenuEnter or {}) do callback() end
    end
    for _, queueEnabled in ipairs({false, true}) do
        for _, endpoint in ipairs({'ground-four-tiles', 'peer', 'wrong-type', 'fresh-replica'}) do
            clearIntent(); reset(); enabled = queueEnabled; doNotReequip = false
            worn = {}; player.primary, player.secondary = nil, nil
            local source = endpoint == 'peer' and peerInventory or floor
            local missing = bag(source, 17501)
            local lookalike = bag(inventory, 17502)
            local valid = bag(inventory, 17503); valid.equippedAt = 'base:fannypackfront'
            local hand = item(inventory, 17504)
            inventory.values = {lookalike, valid, hand}
            local live
            if endpoint == 'fresh-replica' or endpoint == 'wrong-type' then
                live = bag(inventory, missing:getID()); inventory.values[#inventory.values + 1] = live
                if endpoint == 'wrong-type' then live.getFullType = function() return 'Base.Other' end end
            end
            if endpoint == 'ground-four-tiles' then
                local away = {getX = function() return 4 end, getY = function() return 0 end, getZ = function() return 0 end}
                local world = {getItem = function() return missing end, getSquare = function() return away end}
                missing.getWorldItem = function() return world end
            end
            if not live then
                local probe = ISWearClothing:new(player, missing)
                local ok, problem = pcall(probe.start, probe)
                assert(not ok and probe.item == nil and tostring(problem):find('nil'),
                    'regression must execute native Host start nil-rebinding before the repair')
            end
            local session = TidyFixture.captureSession(player)
            session.restoreWorn, session.restoreHands = true, true
            session.wornItems = {['base:back'] = missing, ['base:fannypackfront'] = valid}
            session.primaryItem = hand
            compat.fixtureRepairTidyFloor(player, function() TidyFixture.queueRestore(session) end)
            local missingWear, validWear, handEquip
            for _, action in ipairs(queue.queue) do
                if action.Type == 'ISWearClothing' and action.item == missing then missingWear = action end
                if action.Type == 'ISWearClothing' and action.item == valid then validWear = action end
                if action.Type == 'ISEquipWeaponAction' and action.item == hand then handEquip = action end
            end
            assert(handEquip and validWear and queue:indexOf(handEquip) < queue:indexOf(validWear),
                'missing worn storage must preserve P4 hand/clothing actions and order')
            assert((missingWear ~= nil) == (endpoint == 'fresh-replica'),
                'P4 emitted unavailable exact worn item into native Host start: ' .. endpoint)
            if missingWear then
                assert(missingWear.item == missing, 'filter must leave private original-item metadata unchanged')
                worn['base:back'] = live
                missingWear:begin()
                missingWear:start()
                assert(missingWear.item == live, 'native Host start must retain its fresh exact-ID/type resolver')
            end
            assert(missing:getContainer() == source and lookalike:getContainer() == inventory,
                'wear filter moved unavailable storage or selected a same-type substitute')
        end
    end
    for _, mutation in ipairs({'callback', 'instance', 'foreign', 'incoming', 'unknown-before', 'busy'}) do
        clearIntent(); reset(); doNotReequip = false; player.primary, player.secondary = nil, nil
        local missing = bag(floor, 17511)
        local wear = ISWearClothing:new(player, missing)
        local before
        if mutation == 'callback' then wear.onCompleteFunc = function() end
        elseif mutation == 'instance' then wear.start = function() end
        elseif mutation == 'foreign' then wear.character = setmetatable({}, {__index = player})
        elseif mutation == 'incoming' then before = ISInventoryTransferAction:new(player, missing, floor, inventory)
        elseif mutation == 'unknown-before' then before = ISBaseTimedAction:new(player)
        elseif mutation == 'busy' then ISTimedActionQueue.add(ISBaseTimedAction:new(player)) end
        compat.fixtureRepairTidyFloor(player, function()
            if before then ISTimedActionQueue.add(before) end
            ISTimedActionQueue.add(wear)
        end)
        local actualQueue = ISTimedActionQueue.getTimedActionQueue(wear.character)
        assert(actualQueue:indexOf(wear) ~= -1 and (not before or queue:indexOf(before) < queue:indexOf(wear)),
            'unknown callback, pending supplier or nonidle work must remain unchanged: ' .. mutation)
    end
    clearIntent(); reset(); player.getWornItem = getWorn; isClient = client
    print('PASS real P4 missing world/peer worn storage, native nil-rebind and exact Host replica preservation')
end
-- Match the early-Compat / later-ActionQueue startup order, including inherited P4 stop methods.
local previousStop=ISBaseTimedAction.stop
ISBaseTimedAction.stop=function(...) return previousStop(...) end
assert(compat.adoptStop(previousStop,ISBaseTimedAction.stop))
-- Exercise the installed, unmodified P4 session builder, including its stale hand baseline.
local intent=PZSurvivorToolkit.ActionQueueTidyIntent
for _,queueEnabled in ipairs({false,true}) do
    reset();enabled=queueEnabled;doNotReequip=false;player.primary,player.secondary=nil,nil
    local kept,borrowed=item(tidyBag,71),item(tidyBag,72)
    ISInventoryPaneContextMenu.onGrabItems({kept},0)
    local manualPickup=queue.queue[1]
    local borrowedPickup=ISInventoryTransferAction:new(player,borrowed,tidyBag,inventory)
    ISTimedActionQueue.add(borrowedPickup);ISTimedActionQueue.add(ISReadABook:new(player,borrowed))
    inventory.values={kept,borrowed}
    while queue.queue[1] do
        local action=queue.queue[1]
        if action==manualPickup then intent.begin(action,'perform') end
        action:perform()
        if action==manualPickup then intent.finish(action,'perform',true) end
    end
    tickTidy();tickTidy()
    assert(not findReturn(kept) and findReturn(borrowed),
        'real P4 keeps confirmed manual pickup and returns only the borrowed item with queue '..tostring(queueEnabled))
    while queue.queue[1] do queue.queue[1]:perform() end
    tickTidy();tickTidy()
    reset();enabled=queueEnabled;doNotReequip=false
    local original,manual,tool=item(inventory,81),item(inventory,82),item(inventory,83)
    inventory.values={original,manual,tool};player.primary,player.secondary=original,nil
    ISInventoryPaneContextMenu.OnPrimaryWeapon({manual},0)
    local manualEquip=queue.queue[1]
    ISTimedActionQueue.add(ISEquipWeaponAction:new(player,tool,50,true,false))
    P4TidyUpMeister.registerActionPolicy('ISReadABook',{restoreHands=true})
    ISTimedActionQueue.add(ISReadABook:new(player,tool))
    while queue.queue[1] do
        local action=queue.queue[1]
        if action==manualEquip then intent.begin(action,'complete') end
        if action.complete then action:complete() end
        if action==manualEquip then intent.finish(action,'complete',true) end
        action:perform()
    end
    assert(player.primary==tool and TidyFixture.sessions[player].primaryItem==original,
        'automatic tool prep changes hands after P4 captured the older baseline')
    tickTidy();tickTidy()
    while queue.queue[1] do
        local action=queue.queue[1];if action.complete then action:complete() end;action:perform()
    end
    assert(player.primary==manual,'real P4 restores the explicit primary instead of its older baseline')
    tickTidy();tickTidy()
end
player.getTimedActionToRetrigger=function() end
player.setTimedActionToRetrigger=function() end
for index,field in ipairs({'onStartFunc','onCompleteFunc','onCancelFunc','retriggerLastAction','onFailFunc','additionalTest'}) do
    reset();enabled=false;doNotReequip=false;player.primary,player.secondary=nil,nil
    local kept=item(tidyBag,90+index)
    ISInventoryPaneContextMenu.onGrabItems({kept},0)
    local action=queue.queue[1]
    action[field]=field=='retriggerLastAction' and true or function() end
    action.onCompleteArgs={}
    ISTimedActionQueue.add(ISReadABook:new(player,kept));inventory.values={kept}
    intent.begin(action,'perform');action:perform();intent.finish(action,'perform',true)
    while queue.queue[1] do queue.queue[1]:perform() end
    tickTidy();tickTidy()
    assert(findReturn(kept),'unknown late '..field..' must leave real P4 return unchanged')
    while queue.queue[1] do queue.queue[1]:perform() end
    tickTidy();tickTidy()
end
reset()
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
if NativeQuartermasterLuaRoot then
    local menuSource=read(NativeQuartermasterLuaRoot..'/client/LootSorter_CraftMenu.lua')
    local debugSource=read(NativeQuartermasterLuaRoot..'/shared/LootSorter_Debug.lua')
    local neatSource=read(NativeWishlistWorkshopRoot..'/'..paths.Neat_Crafting..'/media/lua/client/Neat_Crafting/NC_CraftActionPanel.lua')
    local previousRequire,previousEvents,previousOrigin=require,Events,getFilenameOfClosure
    local previousGetter=ISInventoryPaneContextMenu.getContainers
    local previousDebug,previousLootSorter=isDebugEnabled,LootSorter
    local previousNeat=NC_CraftActionPanel
    local function quartermasterNeat(change)
        local starts={}
        Events={OnTick={Add=function() end},OnGameStart={Add=function(callback)starts[#starts+1]=callback end}}
        getActivatedMods=function()return {contains=function(_,id)return id=='Neat_Crafting'or id=='Quartermaster'end}end
        getModFileReader=oldReader
        getFilenameOfClosure=previousOrigin
        require=function(module)
            if module=='Neat_Crafting/NC_CraftActionPanel'then return assert(loadstring(neatSource,'@NC_CraftActionPanel.lua'))()end
            if module=='LootSorter_CraftMenu'then return assert(loadstring(menuSource,'@LootSorter_CraftMenu.lua'))()end
            return previousRequire(module)
        end
        isDebugEnabled=function()return false end
        LootSorter=nil;assert(loadstring(debugSource,'@LootSorter_Debug.lua'))()
        ISInventoryPaneContextMenu.getContainers=previousGetter
        NC_CraftActionPanel=nil
        if change=='preloaded'then require('Neat_Crafting/NC_CraftActionPanel')end
        PZSurvivorToolkit.ActionQueueOperations={registerProducer=function()end}
        PZSurvivorToolkit.ActionQueueDefinitions={registerBehavior=function()end}
        local selected=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'))()
        local class=assert(NC_CraftActionPanel)
        if #starts==0 then require('LootSorter_CraftMenu')end -- An unverified auto-loaded module still installs its native hooks.
        if change=='early-callback'then class.onHandcraftActionComplete=function()end
        elseif change=='early-helper'then class.refreshAfterCraftBatch=function()end end
        local before={}
        for name,callback in pairs(class)do before[name]=callback end
        for _,callback in ipairs(starts)do callback()end
        assert(class.prerender~=before.prerender and class.onCraftButtonClick~=before.onCraftButtonClick,
            'actual Quartermaster installer must replace both Neat UI methods')
        if not change then
            for name,callback in pairs(before)do
                assert(name=='prerender'or name=='onCraftButtonClick'or class[name]==callback,
                    'actual Quartermaster installer changed a Neat callback/helper: '..name)
            end
        end
        if change=='late-callback'then class.onHandcraftActionComplete=function()end
        elseif change=='late-helper'then class.refreshAfterCraftBatch=function()end end
        local target=setmetatable({},class)
        ISXuiSkin.RegisterXuiSkinFunctions(target,false)
        local action={onStartFunc=target.onHandcraftActionStart,onCompleteFunc=target.onHandcraftActionComplete,
            onCancelFunc=target.onHandcraftActionCancelled}
        assert(selected.isCraftOwner('NC_CraftActionPanel',target,action)==(change==nil),
            'Quartermaster Neat hook adoption must retain early source/callback/helper/provenance guards: '..tostring(change))
        if not change then
            target.onCraftButtonClick=function()end
            assert(not selected.isCraftOwner('NC_CraftActionPanel',target,action),'unknown Neat instance UI wrapper remains protected')
        end
    end
    quartermasterNeat()
    for _,change in ipairs({'early-callback','early-helper','late-callback','late-helper','preloaded'})do
        quartermasterNeat(change)
    end
    require,Events,getFilenameOfClosure=previousRequire,previousEvents,previousOrigin
    isDebugEnabled,LootSorter,NC_CraftActionPanel=previousDebug,previousLootSorter,previousNeat
    ISInventoryPaneContextMenu.getContainers=previousGetter
    PZSurvivorToolkit.ActionQueueOperations,PZSurvivorToolkit.ActionQueueDefinitions,PZSurvivorToolkit.ActionQueueCompat=oldOperations,oldDefinitions,oldCompat
    ISTimedActionQueue.add,getActivatedMods,getModFileReader=oldAdd,oldMods,oldReader
end
do
    -- A changed cooking panel must not delay reviewed recipe hooks past P4's class snapshot.
    local previousRequire,previousReader,previousMods=require,getModFileReader,getActivatedMods
    local previousPolicy=PZSurvivorToolkit.ActionQueuePolicy
    local previousOperations,previousDefinitions,previousCompat=PZSurvivorToolkit.ActionQueueOperations,PZSurvivorToolkit.ActionQueueDefinitions,PZSurvivorToolkit.ActionQueueCompat
    local previousAdd,previousAfter,previousToQueue=ISTimedActionQueue.add,ISTimedActionQueue.addAfter,ISTimedActionQueue.addToQueue
    local previousRecipe,previousHandcraft,previousFrozen=ISAddItemInRecipe,ISHandcraftAction,PJCK_FrozenCooking
    local previousPanel=PJCK_CraftActionPanel
    local modulePaths={
        ['Project_Cook/PJCK_FrozenCooking']='shared/Project_Cook/PJCK_FrozenCooking.lua',
        ['Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction']='client/Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction.lua',
    }
    local panelPath='media/lua/client/Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel.lua'
    local function clone(class)
        local result={};for name,value in pairs(class)do result[name]=value end
        return setmetatable(result,getmetatable(class))
    end
    local function cookingHooks(changed)
        ISAddItemInRecipe,ISHandcraftAction=clone(previousRecipe),clone(previousHandcraft)
        PJCK_FrozenCooking,PJCK_CraftActionPanel=nil,nil
        local loadedHooks,guard={}
        local isolatedIntent={observeTransfers=function()end,install=function(valid)guard=valid end}
        getActivatedMods=function()return {contains=function(_,id)return id=='Project_Cook'or id=='P4TidyUpMeister'end}end
        getModFileReader=function(id,path,...)
            local reader=previousReader(id,path,...)
            if id=='Project_Cook'and(path==panelPath or path=='media/lua/'..tostring(changed))then
                local readLine=reader.readLine;local first=true
                reader.readLine=function(...)
                    local line=readLine(...)
                    if first then first=false;return line..' -- changed source'end
                    return line
                end
            end
            return reader
        end
        require=function(module)
            if module=='PZSurvivorToolkit/ActionQueueTidyIntent'then return isolatedIntent end
            local path=modulePaths[module]
            if not path then return previousRequire(module)end
            if loadedHooks[module]then return loadedHooks[module]end
            local source=read(NativeWishlistWorkshopRoot..'/'..paths.Project_Cook..'/media/lua/'..path)
            if path==changed then source=source..'\n-- changed source'end
            local result=assert(loadstring(source,'@'..path))()
            loadedHooks[module]=result or true;return result
        end
        PZSurvivorToolkit.ActionQueuePolicy={}
        PZSurvivorToolkit.ActionQueueOperations={registerProducer=function()end}
        PZSurvivorToolkit.ActionQueueDefinitions={registerBehavior=function()end}
        local selected=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'))()
        assert(not selected.isInstalled('Project_Cook')and PJCK_CraftActionPanel==nil,
            'changed EvoPanel must not enable the cooking adapter')
        assert(selected.isInstalled('P4TidyUpMeister'),'P4 source must remain installed')
        assert(guard,'P4 class guard must be captured')
        assert(guard(),'unrelated P4 class guard must start valid')
        if changed then
            assert(not selected.verifySources('Project_Cook',{{changed,changed:find('FrozenCooking',1,true)and 3756381974 or 222676723}}),
                'changed recipe modifier source must remain unapproved')
            for module,path in pairs(modulePaths)do if path==changed then assert(not loadedHooks[module],'unapproved modifier was eagerly loaded')end end
        end
        for module in pairs(modulePaths)do require(module)end
        local equip=ISEquipWeaponAction:new(player,item(inventory,190),50,true,false)
        if not changed then
            assert(guard()and guard(equip),'reviewed recipe hooks must preserve unrelated P4 equipment intent')
        else
            assert(not guard(),'late unapproved recipe hook must still invalidate P4 class proof')
        end
    end
    cookingHooks()
    for _,path in pairs(modulePaths)do cookingHooks(path)end
    require,getModFileReader,getActivatedMods=previousRequire,previousReader,previousMods
    ISAddItemInRecipe,ISHandcraftAction,PJCK_FrozenCooking,PJCK_CraftActionPanel=previousRecipe,previousHandcraft,previousFrozen,previousPanel
    PZSurvivorToolkit.ActionQueuePolicy=previousPolicy
    PZSurvivorToolkit.ActionQueueOperations,PZSurvivorToolkit.ActionQueueDefinitions,PZSurvivorToolkit.ActionQueueCompat=previousOperations,previousDefinitions,previousCompat
    ISTimedActionQueue.add,ISTimedActionQueue.addAfter,ISTimedActionQueue.addToQueue=previousAdd,previousAfter,previousToQueue
end
-- An unknown refresh introduced during fresh source loading must remain native;
-- file checksum approval does not bless a callback installed by another loader.
do
 local saved={require=require,mods=getActivatedMods,operations=PZSurvivorToolkit.ActionQueueOperations,
  definitions=PZSurvivorToolkit.ActionQueueDefinitions,compat=PZSurvivorToolkit.ActionQueueCompat,
  panel=PJCK_EvoPanel,craft=PJCK_CraftActionPanel,add=ISTimedActionQueue.add,
  after=ISTimedActionQueue.addAfter,toQueue=ISTimedActionQueue.addToQueue,checkQueue=ISInventoryTransferAction.checkQueueList,
  post=PJCK_postIngredientUse,process=PJCK_processIngredientEntry}
 local injected,expected
 for _,changed in ipairs({'setContainers','resolveCurrentBaseItem','getBaseItem','getInputList','invalidateInputCaches'})do
 getActivatedMods=function()return {contains=function(_,id)return id=='Project_Cook'end}end
 require=function(module)
  if module=='Project_Cook/HandCraftPanel/PJCK_CraftActionPanel'or module=='Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel'then
   local path=NativeWishlistWorkshopRoot..'/'..paths.Project_Cook..'/media/lua/client/'..module..'.lua'
   local result=assert(loadstring(read(path),'@'..module..'.lua'))()
   if module=='Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel'then
    local callback=PJCK_EvoPanel[changed]
    injected=function(self,...)return callback(self,...)end
    PJCK_EvoPanel[changed]=injected
    expected={}
    for _,name in ipairs({'setContainers','resolveCurrentBaseItem','getBaseItem','getInputList'})do expected[name]=PJCK_EvoPanel[name]end
   end
   return result
  end
  return saved.require(module)
 end
 PJCK_EvoPanel,PJCK_CraftActionPanel=nil,nil
 PZSurvivorToolkit.ActionQueueOperations={registerProducer=function()end}
 PZSurvivorToolkit.ActionQueueDefinitions={registerBehavior=function()end}
 local selected=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'))()
 assert(selected.isInstalled('Project_Cook')and injected,'early source integration unexpectedly unavailable')
 for name,callback in pairs(expected)do assert(PJCK_EvoPanel[name]==callback,
  'unknown early '..changed..' obtained canonicalizer at '..name)end
 require,getActivatedMods=saved.require,saved.mods
 PZSurvivorToolkit.ActionQueueOperations,PZSurvivorToolkit.ActionQueueDefinitions,PZSurvivorToolkit.ActionQueueCompat=saved.operations,saved.definitions,saved.compat
 PJCK_EvoPanel,PJCK_CraftActionPanel=saved.panel,saved.craft
 ISTimedActionQueue.add,ISTimedActionQueue.addAfter,ISTimedActionQueue.addToQueue=saved.add,saved.after,saved.toQueue
 ISInventoryTransferAction.checkQueueList=saved.checkQueue
 PJCK_postIngredientUse,PJCK_processIngredientEntry=saved.post,saved.process
 end
 print('PASS unknown early Cook refresh/resolver/getter/input/invalidator callbacks remain outside shared canonicalizer')
end

-- Optional UI proof must never weaken the existing evolved/handcraft/return source proof.
do
 local saved={require=require,reader=getModFileReader,mods=getActivatedMods,events=Events,
  operations=PZSurvivorToolkit.ActionQueueOperations,definitions=PZSurvivorToolkit.ActionQueueDefinitions,
  compat=PZSurvivorToolkit.ActionQueueCompat,panel=PJCK_EvoPanel,craft=PJCK_CraftActionPanel,
  input=PJCK_InputPanel,info=PJCK_CookingInfo,add=ISTimedActionQueue.add,after=ISTimedActionQueue.addAfter,
  toQueue=ISTimedActionQueue.addToQueue,checkQueue=ISInventoryTransferAction.checkQueueList,
  post=PJCK_postIngredientUse,process=PJCK_processIngredientEntry}
 local modules={
  ['Project_Cook/HandCraftPanel/PJCK_CraftActionPanel']='client/Project_Cook/HandCraftPanel/PJCK_CraftActionPanel.lua',
  ['Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel']='client/Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel.lua',
  ['Project_Cook/EvolvedRecipePanel/PJCK_InputPanel']='client/Project_Cook/EvolvedRecipePanel/PJCK_InputPanel.lua',
  ['Project_Cook/EvolvedRecipePanel/PJCK_CookingInfo']='client/Project_Cook/EvolvedRecipePanel/PJCK_CookingInfo.lua',
 }
 for _,scenario in ipairs({'known','input-source','info-source','input-early','info-early','info-missing-water','input-extra'})do
  local loadedUi,original,expected={}
  local changed=scenario=='input-source'and 'media/lua/'..modules['Project_Cook/EvolvedRecipePanel/PJCK_InputPanel']
   or scenario=='info-source'and 'media/lua/'..modules['Project_Cook/EvolvedRecipePanel/PJCK_CookingInfo']
  getActivatedMods=function()return{contains=function(_,id)return id=='Project_Cook'end}end
  getModFileReader=function(id,path,...)
   local reader=saved.reader(id,path,...)
   if id=='Project_Cook'and path==changed then
    local readLine,first=reader.readLine,true
    reader.readLine=function(...)
     local line=readLine(...);if first then first=false;return line..' -- changed UI source'end;return line
    end
   end
   return reader
  end
  require=function(module)
   local path=modules[module]
   if not path then return saved.require(module)end
   if loadedUi[module]then return loadedUi[module]end
   local result=assert(loadstring(read(NativeWishlistWorkshopRoot..'/'..paths.Project_Cook..'/media/lua/'..path),'@'..module..'.lua'))()
   if module=='Project_Cook/EvolvedRecipePanel/PJCK_InputPanel'then
    original=PJCK_InputPanel.canAddItem
    if scenario=='input-early'then PJCK_InputPanel.canAddItem=function(self,...)return original(self,...)end
    elseif scenario=='input-extra'then PJCK_InputPanel.unreviewedHelper=function()end end
    expected=PJCK_InputPanel.canAddItem
   elseif module=='Project_Cook/EvolvedRecipePanel/PJCK_CookingInfo'then
    if scenario=='info-early'then
     local callback=PJCK_CookingInfo.isAddOneFirst
     PJCK_CookingInfo.isAddOneFirst=function(self,...)return callback(self,...)end
    elseif scenario=='info-missing-water'then PJCK_CookingInfo.isNeedWater=nil end
   end
   loadedUi[module]=result or true;return result
  end
  Events={OnTick={Add=function()end},OnGameStart={Add=function()end}}
  PJCK_EvoPanel,PJCK_CraftActionPanel,PJCK_InputPanel,PJCK_CookingInfo=nil,nil,nil,nil
  PZSurvivorToolkit.ActionQueueOperations={registerProducer=function()end}
  PZSurvivorToolkit.ActionQueueDefinitions={registerBehavior=function()end}
  local selected=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'))()
  assert(selected.isInstalled('Project_Cook'),'optional UI source disabled reviewed cooking core: '..scenario)
  assert(selected.isInstalled('Project_Cook_FirstAddition')==(scenario=='known'),'optional first-addition proof admitted unknown source: '..scenario)
  require('Project_Cook/EvolvedRecipePanel/PJCK_InputPanel')
  if scenario=='known'then assert(PJCK_InputPanel.canAddItem~=original,'known UI source was not adapted')
  else assert(PJCK_InputPanel.canAddItem==expected,'unknown UI callback was replaced: '..scenario)end
 end
 require,getModFileReader,getActivatedMods,Events=saved.require,saved.reader,saved.mods,saved.events
 PZSurvivorToolkit.ActionQueueOperations,PZSurvivorToolkit.ActionQueueDefinitions,PZSurvivorToolkit.ActionQueueCompat=saved.operations,saved.definitions,saved.compat
 PJCK_EvoPanel,PJCK_CraftActionPanel,PJCK_InputPanel,PJCK_CookingInfo=saved.panel,saved.craft,saved.input,saved.info
 ISTimedActionQueue.add,ISTimedActionQueue.addAfter,ISTimedActionQueue.addToQueue=saved.add,saved.after,saved.toQueue
 ISInventoryTransferAction.checkQueueList=saved.checkQueue
 PJCK_postIngredientUse,PJCK_processIngredientEntry=saved.post,saved.process
 print('PASS optional Cook first-addition source/early-closure guards retain original UI and reviewed cooking core')
end

print('Selected mod chain actual-source checks passed.')
-- The numbered Quartermaster entry loads Compat before Policy in the game.
-- Exercise both require-loaded and already-loaded shared repair startup orders.
for _,sharedPreload in ipairs({false,true})do
    local fixture=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    for _,path in ipairs({'shared/TimedActions/ISTransferAction.lua','shared/TimedActions/ISEatFoodAction.lua',
        'shared/TimedActions/ISDrinkFluidAction.lua','shared/Fluids/ISFluidContainer.lua','shared/Fluids/ISFluidUtil.lua',
        'shared/Fluids/ISFluidEmptyAction.lua','shared/RadioCom/ISRadioAction.lua','client/TimedActions/WalkToTimedAction.lua',
        'shared/TimedActions/ISToggleStoveAction.lua'})do
        fixture.native(path)
    end
    local cartRoot=NativeWishlistWorkshopRoot..'/3651954650/mods/SaucedCarts/42'
    local modules={}
    local function input(source)
        local cursor=1
        return {close=function()end,readLine=function()
            if cursor>#source then return end
            local boundary=source:find('\n',cursor,true)or #source+1
            local line=source:sub(cursor,boundary-1);cursor=boundary+1;return line
        end}
    end
    getGameFilesInput=function(path)return input(read(NativeActionRoot..'/'..path:gsub('^media/lua/','')))end
    getModFileReader=function(id,path)
        if id=='PZSurvivorToolkit'then return input(read(ProjectRoot..'/PZSurvivorToolkit/42/'..path))end
        assert(id=='SaucedCarts')
        -- Keep unrelated cart transfer installation outside this startup boundary.
        if path~='media/lua/client/SaucedCarts/ConsumeWithCart.lua'and path~='media/lua/shared/SaucedCarts/Core.lua'then return end
        return input(read(cartRoot..'/'..path))
    end
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getDebug=function()return false end
    isClient,isServer=function()return false end,function()return false end
    getActivatedMods=function()return {contains=function(_,id)return id=='SaucedCarts'end}end
    SaucedCarts,LootSorter=nil,{}
    Fluid={Water={}};MoodleType={FOOD_EATEN=1};ItemTag={}
    local nativeEatStart,nativeDrinkStart=ISEatFoodAction.start,ISDrinkFluidAction.start
    local policyLoads,consumeLoads=0,0
    local function shared(name)
        return assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..name..'.lua'))()
    end
    local sharedModules={SourceProof=true,DrinkFluidAction=true,DrinkFluidCompletion=true,EmptyFluidAction=true,SetStoveStateAction=true}
    require=function(name)
        if modules[name]~=nil then return modules[name]end
        local suffix=name:match('^PZSurvivorToolkit/(.+)$')
        local result
        if suffix=='ActionQueuePolicy'then
            policyLoads=policyLoads+1
            assert(PZSurvivorToolkit.ActionQueuePolicy==nil and ISEatFoodAction.start==nativeEatStart
                and ISDrinkFluidAction.start==nativeDrinkStart,'early Compat must load Policy before either cart start changes')
            result=fixture.project(suffix)
            assert(result==PZSurvivorToolkit.ActionQueuePolicy and type(result.adoptConsumeStarts)=='function')
        elseif suffix=='Settings'then return PZSurvivorToolkit.Settings
        elseif suffix then
            if sharedModules[suffix]then result=shared(name)else result=fixture.project(suffix)end
        elseif name=='SaucedCarts/Core'then
            result=assert(loadfile(cartRoot..'/media/lua/shared/SaucedCarts/Core.lua'))()
        elseif name=='SaucedCarts/ConsumeWithCart'then
            consumeLoads=consumeLoads+1
            assert(policyLoads==1 and type(PZSurvivorToolkit.ActionQueuePolicy.adoptConsumeStarts)=='function',
                'actual cart producer must not load until real Policy and completion adapters are ready')
            local repair=assert(PZSurvivorToolkit.DrinkFluidCompletion)
            assert(repair.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid),
                'completion repair must still own native starts when the producer is required')
            result=assert(loadfile(cartRoot..'/media/lua/client/SaucedCarts/ConsumeWithCart.lua'))()
        else return end
        modules[name]=result or true
        return result
    end
    if sharedPreload then
        local preloaded=require('PZSurvivorToolkit/DrinkFluidCompletion')
        assert(preloaded==PZSurvivorToolkit.DrinkFluidCompletion and PZSurvivorToolkit.ActionQueuePolicy==nil
            and preloaded.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid),
            'shared completion must already be installed before any client Policy or compatibility code')
    end
    -- Operations and definitions are Compat's existing prerequisites, not Policy.
    require('PZSurvivorToolkit/ActionQueueOperations')
    require('PZSurvivorToolkit/ActionQueueDefinitions')
    assert(PZSurvivorToolkit.ActionQueuePolicy==nil,'regression must enter before Policy exists')
    local selected=require('PZSurvivorToolkit/ActionQueueCompat')
    assert(policyLoads==1 and consumeLoads==1 and selected.isInstalled('SaucedCarts'),
        'early Compat must install and adopt actual cart starts through lazy Policy loading')
    local repair=PZSurvivorToolkit.DrinkFluidCompletion
    assert(ISDrinkFluidAction.start~=nativeDrinkStart and ISEatFoodAction.start~=nativeEatStart
        and repair.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid)
        and repair.authorizes(ISDrinkFluidAction,'updateEat',ISDrinkFluidAction.updateEat),
        'actual cart start adoption must leave both completion wrappers authorized')
    local player=fixture.player;player.class='IsoPlayer';player.isEquipped=function()return false end
    getClassSimpleName=function(value)return value.class end
    local priorInstanceof=instanceof
    instanceof=function(value,kind)return priorInstanceof(value,kind)or type(value)=='table'
        and kind=='InventoryItem'and value.class=='ComboItem'end
    local root={class='ItemContainer'};player.inventory=root
    root.getType=function()return 'none'end;root.isExistYet=function()return true end
    root.getAcceptItemFunction=function()end;root.getOnlyAcceptCategory=function()end
    root.getContainingItem=function()end;root.getParent=function()return player end
    local bottle={class='ComboItem',getID=function()return 917 end,getContainer=function()return root end,
        getWorldItem=function()end,getIsCraftingConsumed=function()return false end,getEquipParent=function()end,
        getAttachedSlot=function()return -1 end,getType=function()return 'WaterBottle'end,getFullType=function()return 'Base.WaterBottle'end,
        getEatType=function()return 'bottle'end}
    root.contains=function(_,item)return item==bottle end
    root.getItemById=function(_,id)return id==917 and bottle or nil end
    local properties={getThirstChange=function()return -.5 end}
    for _,name in ipairs({'getFatigueChange','getHungerChange','getStressChange','getUnhappyChange','getCalories','getCarbohydrates',
        'getLipids','getProteins','getAlcohol','getPoison','getFluReduction','getPainReduction','getEnduranceChange','getFoodSicknessChange'})do
        properties[name]=function()return 0 end
    end
    local fluid={class='FluidContainer',getOwner=function()return bottle end,getAmount=function()return 1 end,
        getCapacity=function()return 1 end,getFilledRatio=function()return 1 end,getCustomDrinkSound=function()return ''end,
        isPureFluid=function(_,kind)return kind==Fluid.Water end,isTainted=function()return false end,isPoisonous=function()return false end,
        getProperties=function()return properties end,isEmpty=function()return false end}
    bottle.getFluidContainer=function()return fluid end
    -- Load the actual controller after early compatibility, including its native
    -- begin/stop wrappers; unrelated target/UI integrations have separate suites.
    require('PZSurvivorToolkit/ActionQueueLabels')
    local selectedRequire=require
    require=function(name)
        if modules[name]~=nil then return modules[name]end
        if name=='PZSurvivorToolkit/ActionQueueLifecycle'or name=='PZSurvivorToolkit/ActionQueueAcknowledgements'then
            return selectedRequire(name)
        end
    end
    fixture.project('ActionQueue')
    require=selectedRequire
    local action=ISDrinkFluidAction:new(player,bottle,1)
    local adapters=PZSurvivorToolkit.ActionQueueItemEditAdapters
    local contract=assert(adapters.drink(action),'pending full drink must retain a complete edit contract after early actual cart adoption')
    assert(contract.complete and contract.resources[2].effects[1].set==0)
    local inspected=PZSurvivorToolkit.ActionQueuePolicy.inspect(action)
    assert(inspected and inspected.edit and inspected.edit.complete,
        'real Policy.inspect must retain the pending full-drink edit after later Queue begin/stop hooks')
    local owner=SaucedCarts;local original=owner.safeIsCart;owner.safeIsCart=function()return false end
    assert(not repair.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid)and not adapters.drink(action),
        'actual early-entry helper guard must remain live for completion and pending edits')
    owner.safeIsCart=original
    assert(adapters.drink(action),'restoring the captured helper identity restores the pending native drink contract')
    print('Early Quartermaster Compat: sharedPreload='..tostring(sharedPreload)..', lazy real Policy, actual cart starts, live repair and pending drink inspection passed.')
end
