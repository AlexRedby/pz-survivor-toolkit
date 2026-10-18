if not NativeActionRoot then print('Fire native-contract checks skipped.'); return end
require = function(module)
    if module == 'PZSurvivorToolkit/SourceProof' then return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))() end
end
local enabled, client = true, false
PZSurvivorToolkit = {BulkActions = {}, Settings = {actionQueue = function() return enabled end}}
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
local mainMenuCleanup
Events = {OnGameStart = {Add = function() end}, OnTick = {Add = function() end},
    OnMainMenuEnter = {Add = function(callback) mainMenuCleanup=callback end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do _G[name] = {instance = function() return {} end} end
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
local function list(items)
    return {items = items or {}, size = function(self) return #self.items end,
        get = function(self, i) return self.items[i + 1] end, add = function(self, item) self.items[#self.items + 1] = item end,
        clear = function(self) self.items = {} end, remove=function(self,value) for i=#self.items,1,-1 do if self.items[i]==value then table.remove(self.items,i) end end end, isEmpty = function(self) return #self.items == 0 end}
end
ArrayList = {new = function() return list() end}
instanceof = function(value, name) return value and (value.class == name or (name == 'IsoObject' and value.class == 'IsoBarbecue')) end
local function read(path, raw)
    if raw and NativeReadRawText then return NativeReadRawText(path):gsub('\r', '') end
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local text = file:read('*a'); file:close(); return text:gsub('\r', '')
end
local function native(path) assert(loadstring(read(NativeActionRoot .. '/' .. path), '@' .. NativeActionRoot .. '/' .. path))() end
local function extract(path, pattern) assert(loadstring(assert(read(path):match(pattern), pattern), '@' .. path))() end
local resolvedSources = {}
getGameFilesInput = function(path)
    local text, index = read(resolvedSources[path] or NativeActionRoot .. '/' .. path:gsub('^media/lua/', ''), true), 1
    return {readLine = function()
        if index > #text then return end
        local stop = text:find('\n', index) or #text + 1
        local value = text:sub(index, stop - 1); index = stop + 1; return value
    end, close = function() end}
end
local fixtureOrigins = {}
getFilenameOfClosure = function(callback) return fixtureOrigins[callback] or (NativeFilenameOfClosure and NativeFilenameOfClosure(callback)) or debug.getinfo(callback, 'S').source end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
ISInventoryPage = {}
native('client/TimedActions/ISInventoryTransferAction.lua')
native('client/Map/CGlobalObject.lua'); native('client/Camping/CCampfireGlobalObject.lua')
native('shared/Camping/ISCampingMenu.lua')
for _, name in ipairs({'ISAddFuelAction','ISLightFromLiterature','ISLightFromPetrol','ISLightFromKindle'}) do native('shared/Camping/TimedActions/' .. name .. '.lua') end
for _, name in ipairs({'ISBBQAddFuel','ISBBQLightFromLiterature','ISBBQLightFromPetrol','ISBBQLightFromKindle'}) do native('shared/TimedActions/' .. name .. '.lua') end
native('shared/TimedActions/ISInventoryTransferUtil.lua')
ISContextMenu, ISButton, ISInventoryPane, ISInventoryPaneContextMenu = {}, {}, {}, {}
ISCraftingUI = {}
local containers, id = list(), 0
local function container()
    local result = {class = 'ItemContainer', items = {}, getParent = function() return nil end, getContainingItem = function() return nil end,isInside=function() return false end,
        isInCharacterInventory=function() return false end,isVehicleSeat=function() return false end,getType=function() return 'crate' end}
    function result:getItems() local out=list(); for _, value in pairs(self.items) do out:add(value) end; return out end
    function result:contains(item) return self.items[item:getID()] == item end
    function result:getItemById(key) return self.items[key] end
    function result:getFirstTypeEvalRecurse(kind, predicate)
        local keys = {}; for key in pairs(self.items) do keys[#keys + 1] = key end; table.sort(keys)
        for _, key in ipairs(keys) do local item = self.items[key]; if item:getFullType() == kind and predicate(item) then return item end end
        for _, child in ipairs(self.nested or {}) do local item=child:getFirstTypeEvalRecurse(kind,predicate);if item then return item end end
    end
    function result:getAllEval(predicate, out)
        local keys = {}; for key in pairs(self.items) do keys[#keys + 1] = key end; table.sort(keys)
        for _, key in ipairs(keys) do local item = self.items[key]; if predicate(item) then out:add(item) end end
    end
    function result:getAllTypeEval(kind, predicate, out) self:getAllEval(function(item) return item:getFullType() == kind and predicate(item) end, out) end
    function result:Remove(item) self.items[item:getID()], item.source = nil, nil end
    function result:FindAndReturn(kind) for _, item in pairs(self.items) do if item:getType() == kind then return item end end end
    function result:containsID(key) return self.items[key] ~= nil end
    result.setDrawDirty, result.setDrawDirty = function() end, function() end
    return result
end
local inventory = container()
local stopped = 0
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end, getInventory = function() return inventory end,
    isDead = function() return false end, isAsleep = function() return false end, isLocalPlayer = function() return true end,
    isDraggingCorpse = function() return false end, isFarming = function() return false end,
    isTimedActionInstant = function() return false end, isWearingAwkwardGloves=function() return false end, hasTrait = function() return false end,
    isEquipped = function(_, item) return item.equipped end, removeFromHands = function() end,
    StopAllActionQueue = function() stopped = stopped + 1 end, stopOrTriggerSound = function() end,
    getEmitter = function() return {stopOrTriggerSoundByName = function() end} end}
getSpecificPlayer = function() return player end
isClient, isServer = function() return client end, function() return false end
campingText = {lightCampfire = 'light', addFuel = 'fuel'}
campingFuelCategory, campingFuelType = {}, {Log = 10, Charcoal = 10}
campingLightFireCategory, campingLightFireType = {}, {Paper = 1}
ItemTag = {IS_FIRE_FUEL='fuel',IS_FIRE_TINDER='tinder',IS_FIRE_FUEL_SINGLE_USE='single'}
CharacterTrait, CharacterStat = {OUTDOORSMAN='outdoors'}, {ENDURANCE='endurance'}
getCampingFuelMax = function() return 1000 end
round = function(number) return number end
table.isempty = table.isempty or function(t) for _ in pairs(t) do return false end return true end
string.sort = function(a,b) return a < b end
getText = function(key) return key end
getTimestampMs = function() return 0 end
getCore = function() return {getGameMode=function() return 'Sandbox' end} end
sendRemoveItemFromContainer = function() end
IsoObjectChange = {STATE='state'}
ZomboidGlobals = {LightFromPetrolAmount = 0.1}
ISReadABook, ISRadioAction = ISBaseTimedAction:derive('ISReadABook'), ISBaseTimedAction:derive('ISRadioAction')
ISWalkToTimedAction = ISBaseTimedAction:derive('ISWalkToTimedAction')
local function synthetic(class, character) local a = ISBaseTimedAction.new(class, character); a.begin = function() end; return a end
native('shared/TimedActions/ISUnequipAction.lua')
ISWearClothing={isStopOnWalk=function() return false end}
getPlayerHotbar=function() end
ISInventoryPaneContextMenu.getContainers = function() return containers end
luautils = {}
extract(NativeActionRoot .. '/shared/luautils.lua', '(function luautils.walkToContainer.-\nend)')
extract(NativeActionRoot .. '/shared/luautils.lua', '(function luautils.haveToBeTransfered.-\nend)')
extract(NativeActionRoot .. '/client/ISUI/ISInventoryPaneContextMenu.lua', '(function ISInventoryPaneContextMenu.transferIfNeeded.-\nend)')
extract(NativeActionRoot .. '/client/ISUI/ISCraftingUI.lua', '(function ISCraftingUI.ReturnItemToContainer.-\nend)')
fixtureOrigins[ISInventoryPaneContextMenu.getContainers] = 'ISInventoryPaneContextMenu.lua'
-- Use the native movement function, with a narrow native path action fixture.
IsoDirections = {NW=1,NE=2,SE=3,SW=4}
AdjacentFreeTileFinder = {FindClosest = function(square) return square end}
ISPathFindAction = ISBaseTimedAction:derive('ISPathFindAction')
function ISPathFindAction:pathToLocationF(character) return synthetic(self, character) end
player.getCurrentSquare = function() return {getZ = function() return 0 end} end
player.DistToSquared = function() return 10 end
local function square()
    return {getObjects=function() return list() end,getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
        getAdjacentSquare=function() return nil end}
end
local function target(kind)
    local object = {class = kind or 'IsoBarbecue', fuel=20, lit=false, square=square(), changes=0,
        getObjectIndex=function(self) return self.removed and -1 or 0 end,getSquare=function(self) return self.square end,
        getFuelAmount=function(self) return self.fuel end,isLit=function(self) return self.lit end,hasFuel=function(self) return self.fuel > 0 end,
        addFuel=function(self, amount) self.fuel = self.fuel + amount end, turnOn=function(self) self.lit=true end,
        sendObjectChange=function(self) self.changes=self.changes+1 end}
    return object
end
local campfireObject, campfire
getCell = function() return {getGridSquare=function() return campfireObject.square end} end
local function fire()
    campfireObject = target('IsoObject')
    campfire = setmetatable({x=1,y=1,z=0,fuelAmt=20,isLit=false,
        luaSystem={getIsoObjectAt=function() return not campfireObject.removed and campfireObject or nil end}}, CCampfireGlobalObject)
    campfireObject.getModData=function() return {fuelAmt=campfire.fuelAmt,isLit=campfire.isLit} end
    return campfire
end
CCampfireSystem = {instance={getLuaObjectAt=function() return campfire end,
    getLuaObjectOnSquare=function() return campfireObject and not campfireObject.removed and campfire or nil end}}
SCampfireSystem = {instance={getLuaObjectAt=function() return {addFuel=function(_, amount) campfire.fuelAmt=campfire.fuelAmt+amount end,
    lightFire=function() campfire.isLit=true end} end}}
local function item(kind, source, drainable, uses)
    id=id+1
    local value = {class='InventoryItem',id=id,kind=kind,source=source or inventory,uses=uses or 1,used=0,drainable=drainable,
        getID=function(self) return self.id end,getFullType=function(self) return 'Base.'..self.kind end,getType=function(self) return self.kind end,
        getCategory=function() return 'Item' end,getFireFuelRatio=function() return 0 end,getActualWeight=function() return 2 end,getWeight=function() return 2 end,getIsCraftingConsumed=function() return false end,getName=function(self) return self.kind end,getDisplayName=function(self) return self.kind end,
        getContainer=function(self) return self.source end,isFavorite=function() return false end,isEquipped=function() return false end,
        isHumanCorpse=function() return false end,IsClothing=function() return false end,IsInventoryContainer=function() return false end,IsLiterature=function() return false end,IsMap=function() return false end,getFluidContainer=function(self) return self.fluid end,
        hasTag=function() return false end,IsDrainable=function(self) return self.drainable end,
        getCurrentUses=function(self) return self.uses end,getCurrentUsesFloat=function(self) return self.uses end,
        setJobDelta=function() end,UseAndSync=function(self) self.used=self.used+1;self.uses=self.uses-1 end}
    value.Use = value.UseAndSync
    value.source.items[value.id]=value
    return value
end
local function project(name)
    local path=ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/'..name..'.lua'
    if name~='ActionQueueFire' then return assert(loadfile(path))() end
    return assert(loadstring((read(path):gsub('\nreturn Fire','\nFire.fixtureRegistries = {records, snapshots, expanded, returns}\nreturn Fire'))))()
end
project('ActionQueueOperations'); project('ActionQueueDefinitions')
-- A mod replacement present before capture must not acquire permission.
local originalBBQPetrol = ISBBQLightFromPetrol.new
if not FireTestTrustBBQPetrol then ISBBQLightFromPetrol.new = function(...) return originalBBQPetrol(...) end end
local cleanUIPath
if NativeWishlistWorkshopRoot then
    cleanUIPath=NativeWishlistWorkshopRoot .. '/3437629766/mods/CleanUI/42.19/media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'
    resolvedSources['media/lua/client/ISUI/ISInventoryPaneContextMenu.lua']=cleanUIPath
    local source=read(cleanUIPath)
    local chunks={'local CleanUI_reportedUnsafeContextTimedActions = {}'}
    for _, pattern in ipairs({'(local function CleanUI_reportUnsafeContextTimedAction.-\nend)',
        '(local function CleanUI_isContextInventoryItem.-\nend)', '(local function CleanUI_addContextInventoryTransferAction.-\nend)',
        '(function ISInventoryPaneContextMenu.transferIfNeeded.-\nend)', '(ISInventoryPaneContextMenu.getContainers = function.-\nend)',
        '(ISInventoryPaneContextMenu.cleanUILogTimedActionFix = function.-\nend)',
        '(ISInventoryPaneContextMenu.cleanUIResetStaleTimedActionRetrigger = function.-\nend)'}) do
        chunks[#chunks+1]=assert(source:match(pattern),pattern)
    end
    assert(loadstring(table.concat(chunks,'\n'),'@' .. cleanUIPath))()
    getPlayerInventory=function()
        local backpacks={};for _, value in ipairs(containers.items) do backpacks[#backpacks+1]={inventory=value} end
        return {inventoryPane={inventoryPage={backpacks=backpacks}}}
    end
    getPlayerLoot=function() return {inventoryPane={inventoryPage={backpacks={}}}} end
    player.getTimedActionToRetrigger=function(self) return self.retrigger end
    player.setTimedActionToRetrigger=function(self, value) self.retrigger=value end
end
local bcControls,bcProximity
if NativeWishlistWorkshopRoot then
    local bcRoot=NativeWishlistWorkshopRoot .. '/3586216562/mods/BetterContainers/42.20/'
    bcProximity={itemContainer={},corpseContainer={}}
    local earlierRequire,earlierReader=require,getModFileReader
    local helpers={isCleanUIActive=function() return true end,dlog=function() end}
    require=function(name)
        if name=='BetterContainers/Proximity' then return bcProximity end
        if name=='BetterContainers/Helpers' then return helpers end
        if name=='BetterContainers/Proximity/BlacklistCompat' then return {} end
        if name=='BetterContainers/Proximity/Proximity_ISLootWindowContainerControls' then return bcControls end
        return earlierRequire(name)
    end
    getModFileReader=function(mod,path)
        if mod~='EURY_CONTAINERS' then return earlierReader(mod,path) end
        local content,index=read(bcRoot .. path),1
        return {readLine=function()
            if index>#content then return end
            local stop=content:find('\n',index) or #content+1
            local line=content:sub(index,stop-1);index=stop+1;return line
        end,close=function() end}
    end
    local controlsPath=bcRoot .. 'media/lua/client/BetterContainers/Proximity/Proximity_ISLootWindowContainerControls.lua'
    bcControls=assert(loadstring(read(controlsPath),'@' .. controlsPath))()
    Events.OnRefreshInventoryWindowContainers={Add=function() end}
    getActivatedMods=function() return {contains=function(_,id) return id=='EURY_CONTAINERS' end} end
    if FireTestBCPreinstalled then bcControls.install() end
end
local quartermasterStart, quartermasterOwner
if NativeQuartermasterLuaRoot then
    local root=NativeQuartermasterLuaRoot
    local startCallbacks,loaded={},false
    local earlierRequire,earlierReader,earlierMods=require,getModFileReader,getActivatedMods
    Events.OnGameStart={Add=function(callback)startCallbacks[#startCallbacks+1]=callback end}
    getActivatedMods=function()return {contains=function(_,id)
        return id=='Quartermaster' or earlierMods and earlierMods():contains(id) or false
    end}end
    getModFileReader=function(mod,path)
        if mod~='Quartermaster' then return earlierReader and earlierReader(mod,path) end
        local content,index=read(root..'/'..path:gsub('^media/lua/','')),1
        if FireTestQMChangedSource and path:find('LootSorter_CraftMenu.lua',1,true)then content=content..'\n-- changed\n'end
        return {readLine=function()
            if index>#content then return end
            local stop=content:find('\n',index)or #content+1
            local line=content:sub(index,stop-1);index=stop+1;return line
        end,close=function()end}
    end
    LootSorter={};isDebugEnabled=function()return false end
    player.getCharacterActions=function()return list()end
    player.getCurrentState=function()end
    assert(loadstring(read(root..'/shared/LootSorter_Debug.lua'),'@'..root..'/shared/LootSorter_Debug.lua'))()
    LootSorter.gatherBoxes=function()error('forwarding proof must not call storage helpers')end
    require=function(name)
        if name~='LootSorter_CraftMenu'then return earlierRequire(name)end
        if loaded then return end
        loaded=true
        assert(loadstring(read(root..'/client/LootSorter_CraftMenu.lua'),'@'..root..'/client/LootSorter_CraftMenu.lua'))()
    end
    if FireTestQMPreloaded then require('LootSorter_CraftMenu')end
    local source=read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua')
    local first=assert(source:find('local sourceFiles = {',1,true))
    local last=assert(source:find('function Compat.prune()',first,true))
    local functions=assert(source:find('-- getModFileReader resolves',last,true))
    local stop=assert(source:find('local function snapshot(class)',functions,true))
    -- Execute the production observer and checksum code without unrelated mod adapter fixtures.
    local compat=assert(loadstring('local Compat,craftOwners={},{}\n'..source:sub(first,last-1)..source:sub(functions,stop-1)
        ..'\nprepareQuartermasterContainers()\nreturn Compat'))()
    PZSurvivorToolkit.ActionQueueCompat=compat
    -- The normal client loader still runs the file when early observation was refused.
    if not loaded then require('LootSorter_CraftMenu')end
    quartermasterOwner=LootSorter
    quartermasterStart=function()
        if FireTestQMForeignGather then LootSorter.gatherBoxes=function()error('foreign storage helper must not run')end end
        if FireTestQMForeignPredecessor then
            local original=ISInventoryPaneContextMenu.getContainers
            ISInventoryPaneContextMenu.getContainers=function(...)return original(...)end
        end
        for _,callback in ipairs(startCallbacks)do callback()end
    end
end
local originalContainerGetter=ISInventoryPaneContextMenu.getContainers
project('ActionQueueFire')
ISBBQLightFromPetrol.new = originalBBQPetrol
project('ActionQueuePolicy')
local api, policy, operations = PZSurvivorToolkit.ActionQueueFire, PZSurvivorToolkit.ActionQueuePolicy, PZSurvivorToolkit.ActionQueueOperations
assert(not api.matchesContainerGetter(function()end),'an unrelated getter cannot borrow the observed predecessor proof')
if quartermasterStart and FireTestQMBeforeBC then quartermasterStart()end
if bcControls then
    if FireTestBCPreinstalled then
        inventory.items={};local fuel=item('Log');containers=list({inventory})
        local first=synthetic(ISReadABook,player);ISTimedActionQueue.add(first)
        ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20)
        local queue=ISTimedActionQueue.queues[player]
        assert(queue.queue[2].Type~='ISQueueActionsAction' and not api.isDeferredAction(queue.queue[2]))
        print('Fire early preinstalled BC remains opaque without a verified predecessor.');return
    end
    local originalGetter=ISInventoryPaneContextMenu.getContainers
    if FireTestBCForeignPredecessor then ISInventoryPaneContextMenu.getContainers=function(...) return originalGetter(...) end end
    bcControls.install()
    assert(api.matchesContainerGetter(originalGetter)==not FireTestBCForeignPredecessor,'only the observed BC predecessor can be shared')
    assert(api.matchesContainerGetter(ISInventoryPaneContextMenu.getContainers)==not FireTestBCForeignPredecessor,'current getter needs the same intact owner proof')
    if FireTestBCForeignPredecessor then
        inventory.items={};item('Log');containers=list({inventory})
        local first=synthetic(ISReadABook,player);ISTimedActionQueue.add(first)
        ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20)
        local queue=ISTimedActionQueue.queues[player]
        assert(queue.queue[2].Type~='ISQueueActionsAction' and not api.isDeferredAction(queue.queue[2]))
        print('Fire unknown predecessor remains opaque after native BC install.');return
    end
end
if quartermasterStart then
    if not FireTestQMBeforeBC then quartermasterStart()end
    local valid=not (FireTestQMPreloaded or FireTestQMForeignPredecessor or FireTestQMChangedSource)
    assert(api.matchesContainerGetter(originalContainerGetter)==valid,'Quartermaster accepts only the observed trusted predecessor')
    assert(api.matchesContainerGetter(ISInventoryPaneContextMenu.getContainers)==valid,'Quartermaster current getter keeps the exact observed chain')
    if not valid then print('Fire unknown/preloaded/changed Quartermaster chains remain opaque.');return end
    local getter=ISInventoryPaneContextMenu.getContainers
    ISInventoryPaneContextMenu.getContainers=function(...)return getter(...)end
    assert(not api.matchesContainerGetter(originalContainerGetter),'an arbitrary late getter replacement revokes the chain')
    ISInventoryPaneContextMenu.getContainers=getter
    for _,name in ipairs({'DBG'})do
        local callback=quartermasterOwner[name];quartermasterOwner[name]=function()end
        assert(not api.matchesContainerGetter(originalContainerGetter),'a changed Quartermaster '..name..' revokes the shared proof')
        quartermasterOwner[name]=callback
    end
    LootSorter={};assert(not api.matchesContainerGetter(originalContainerGetter),'Quartermaster owner replacement revokes the proof');LootSorter=quartermasterOwner
    local clock=getTimestampMs;getTimestampMs=function()return 0 end
    assert(not api.matchesContainerGetter(originalContainerGetter),'changed Quartermaster clock revokes the shared proof');getTimestampMs=clock
    local busy=ISTimedActionQueue.isPlayerDoingAction;ISTimedActionQueue.isPlayerDoingAction=function()return false end
    assert(not api.matchesContainerGetter(originalContainerGetter),'changed Quartermaster busy predicate revokes the shared proof');ISTimedActionQueue.isPlayerDoingAction=busy
    local matcher=PZSurvivorToolkit.ActionQueueCompat.matchesQuartermasterContainerGetter
    PZSurvivorToolkit.ActionQueueCompat.matchesQuartermasterContainerGetter=function()return true end
    assert(not api.matchesContainerGetter(originalContainerGetter),'a changed observer cannot forge container proof')
    PZSurvivorToolkit.ActionQueueCompat.matchesQuartermasterContainerGetter=matcher
    local gather=quartermasterOwner.gatherBoxes
    quartermasterOwner.gatherBoxes=function()error('a late storage helper must not be called while forwarding')end
    assert(api.matchesContainerGetter(originalContainerGetter),'unused Quartermaster storage helpers do not affect forwarding proof')
    assert(getter(player),'the real Quartermaster wrapper forwards without calling the untrusted storage helper')
    quartermasterOwner.craftFromBoxes=true;quartermasterOwner._craftContextUntil=10
    assert(not api.matchesContainerGetter(originalContainerGetter),'active Quartermaster availability injection stays opaque')
    quartermasterOwner._craftContextUntil=-1
    assert(api.matchesContainerGetter(originalContainerGetter),'expired Quartermaster context is a proven forwarding wrapper')
    quartermasterOwner._craftContextUntil=10;quartermasterOwner._activelyCrafting=true
    assert(api.matchesContainerGetter(originalContainerGetter),'Quartermaster disables availability injection while hauling/crafting')
    quartermasterOwner.craftFromBoxes=false;quartermasterOwner._craftContextUntil=nil;quartermasterOwner._activelyCrafting=nil
    quartermasterOwner.gatherBoxes=gather
    assert(api.matchesContainerGetter(originalContainerGetter),'the original medical getter remains valid through the intact chain')
    print('Fire Quartermaster cold install: old/current getters, BC order and changed owner/helper protection passed.')
end
local q=ISTimedActionQueue.getTimedActionQueue(player)
local function reset()
    q.queue,q.current={},nil; q.toolkitGroupCancel,q.toolkitCancel=nil,nil
    inventory.items,inventory.nested,containers,stopped={},{},list({inventory}),0
    local first=synthetic(ISReadABook,player);first.item=item('Book');ISTimedActionQueue.add(first)
    return first
end
local function expand(command)
    q:removeFromQueue(q.queue[1]);q.current=command
    command.action={forceComplete=function() end,isStarted=function() return true end}
    command:start()
end
do
    local function count(registry) local n=0; for _ in pairs(registry) do n=n+1 end; return n end
    local records,snapshots,expanded,returns=unpack(api.fixtureRegistries)
    for i=1,500 do
        reset(); item('Log'); ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20)
        local command=q.queue[2]; api.prune()
        assert(count(records)==1 and count(snapshots)==1 and records[command], 'old fire request snapshots must not accumulate during a busy queue')
        expand(command); q:removeFromQueue(command); q.current=q.queue[1]; api.prune()
        assert(count(records)==1 and count(snapshots)==1 and count(expanded)==1,
            'expanded fire command must release its record while the native child retains its request')
    end
    for _,state in ipairs({'cancel','dead','replacement','world'}) do
        reset(); item('Log'); ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20)
        local command=q.queue[2]
        if state=='cancel' then operations.invalidate(command.toolkitQueueOperation); q.queue={}
        elseif state=='dead' then player.isDead=function() return true end
        elseif state=='replacement' then ISTimedActionQueue.queues[player]={queue={}}
        else ISTimedActionQueue.queues={} end
        api.prune(); assert(count(records)==0 and count(snapshots)==0 and count(expanded)==0 and count(returns)==0,state..' must release all fire registries')
        player.isDead=function() return false end; ISTimedActionQueue.queues[player]=q
    end
    reset(); item('Log'); ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20)
    mainMenuCleanup(); assert(count(records)==0 and count(snapshots)==0 and count(expanded)==0 and count(returns)==0, 'main menu must release fire world references immediately')
end
local function pickups()
    for _, action in ipairs(q.queue) do
        if action.Type=='ISInventoryTransferAction' and action.destContainer==inventory then
            action.srcContainer.items[action.item.id]=nil;inventory.items[action.item.id]=action.item;action.item.source=inventory
        end
    end
end
if cleanUIPath then
    reset();local source=container();containers=list({inventory,source});local log=item('Log',source)
    player.retrigger={stale=true};ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20);local request=q.queue[2]
    assert(api.isDeferredAction(request));expand(request)
    assert(player.retrigger==nil and q.queue[2].Type=='ISInventoryTransferAction' and q.queue[2].srcContainer==source)
    for _, name in ipairs({'cleanUIResetStaleTimedActionRetrigger','cleanUILogTimedActionFix'}) do
        local callback=ISInventoryPaneContextMenu[name];ISInventoryPaneContextMenu[name]=function() end
        assert(not api.supports(q.queue[#q.queue]));ISInventoryPaneContextMenu[name]=callback
    end
end
-- Repeated views of the same physical source never duplicate selected IDs.
reset();local sharedSource=container();local sharedFuel=item('Log',sharedSource)
containers=list({inventory,sharedSource,sharedSource});ISCampingMenu.onAddAllFuel(player,target(),ISBBQAddFuel,20)
local deduplicated=q.queue[2];assert(api.isDeferredAction(deduplicated) and #deduplicated.args[1].items==1 and deduplicated.args[1].items[1].id==sharedFuel.id)
if bcControls then
    reset();local source,aggregate,corpses=container(),container(),container();local log=item('Log',source)
    aggregate.items[log.id],corpses.items[log.id]=log,log
    bcProximity.itemContainer[0],bcProximity.corpseContainer[0]=aggregate,corpses
    containers=list({inventory,source,aggregate,corpses})
    ISCampingMenu.onAddAllFuel(player,target(),ISBBQAddFuel,20);local request=q.queue[2]
    assert(api.isDeferredAction(request) and #request.args[1].items==1 and request.args[1].items[1].source==source)
    local install=bcControls.install;bcControls.install=function() end;assert(not api.isDeferredAction(request));bcControls.install=install
    local map=bcProximity.itemContainer;bcProximity.itemContainer={};assert(not api.isDeferredAction(request));bcProximity.itemContainer=map
    map=bcProximity.corpseContainer;bcProximity.corpseContainer={};assert(not api.isDeferredAction(request));bcProximity.corpseContainer=map
    local getter=ISInventoryPaneContextMenu.getContainers;ISInventoryPaneContextMenu.getContainers=function(...) return getter(...) end
    assert(not api.isDeferredAction(request));ISInventoryPaneContextMenu.getContainers=getter
end
-- Native queueActions routes cached callbacks at the click, before previous work changes item selection.
for _, mp in ipairs({false,true}) do
    client=mp;local first=reset();local object=target();local fuel=item('Log')
    ISTimedActionQueue.queueActions(player,ISCampingMenu.onAddFuel,object,'Base.Log',ISBBQAddFuel,20)
    local command=q.queue[2];assert(api.isDeferredAction(command) and q.queue[1]==first and stopped==0)
    local other=item('Log');inventory.items[fuel.id]=nil;inventory.items[other.id]=other
    expand(command);assert(#q.queue==1,'missing selected fuel must not substitute a different copy')
    reset();object=target();fuel=item('Log')
    ISTimedActionQueue.queueActions(player,ISCampingMenu.onAddFuel,object,'Base.Log',ISBBQAddFuel,20)
    command=q.queue[2];expand(command)
    local action=q.queue[#q.queue];assert(action.Type=='ISBBQAddFuel' and action.item==fuel and api.supports(action))
    assert(action.toolkitQueueOperation==command.toolkitQueueOperation and not api.canSkip(action))
    action:complete();assert(object.fuel==100 and object.changes==1 and not inventory:contains(fuel))
end
client=false
-- Multi-use count is frozen; later drainable growth cannot silently expand user intent.
reset();local object=target();local fuel=item('Charcoal',nil,true,2)
ISCampingMenu.onAddMultipleFuel(player,object,'Base.Charcoal',ISBBQAddFuel,20)
local command=q.queue[2];fuel.uses=8;expand(command)
local count=0;for _, action in ipairs(q.queue) do if action.Type=='ISBBQAddFuel' then count=count+1 end end
assert(count==2)
-- Distinct one-use copies are reserved at the click; a third request safely finds no fuel.
reset();local log1,log2=item('Log'),item('Log');local target1,target2=target(),target()
ISCampingMenu.onAddFuel(player,target1,'Base.Log',ISBBQAddFuel,20);local request1=q.queue[2]
ISCampingMenu.onAddFuel(player,target2,'Base.Log',ISBBQAddFuel,20);local request2=q.queue[3]
assert(request1.args[1].items[1].id==log1.id and request2.args[1].items[1].id==log2.id)
ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20);assert(#q.queue==3)
assert(not policy.moveReason(q,request1,request2,true) and not policy.moveReason(q,request2,request1,false))
-- Repeated single additions can reserve the remaining uses of one drainable bag.
reset();local bagFuel=item('Charcoal',nil,true,2)
ISCampingMenu.onAddFuel(player,target(),'Base.Charcoal',ISBBQAddFuel,20);local bagFirst=q.queue[2]
ISCampingMenu.onAddFuel(player,target(),'Base.Charcoal',ISBBQAddFuel,20);local bagSecond=q.queue[3]
assert(bagFirst.args[1].items[1].id==bagFuel.id and bagSecond.args[1].items[1].id==bagFuel.id)
ISCampingMenu.onAddFuel(player,target(),'Base.Charcoal',ISBBQAddFuel,20);assert(#q.queue==3)
assert(policy.moveReason(q,bagFirst,bagSecond,true)=='move_shared_item')
-- Expanded native fuel steps reserve one use each, without counting their copied whole snapshot.
reset();bagFuel=item('Charcoal',nil,true,3)
ISCampingMenu.onAddFuel(player,target(),'Base.Charcoal',ISBBQAddFuel,20);command=q.queue[2];expand(command)
ISCampingMenu.onAddMultipleFuel(player,target(),'Base.Charcoal',ISBBQAddFuel,20)
local remainingCommand=q.queue[#q.queue];assert(remainingCommand.args[1].items[1].uses==2)
ISCampingMenu.onAddFuel(player,target(),'Base.Charcoal',ISBBQAddFuel,20);assert(q.queue[#q.queue]==remainingCommand)
-- Capacity is projected across distinct items, rather than reset for each item.
reset();local duplicateFuel=item('Log');containers=list({inventory,inventory})
ISCampingMenu.onAddAllFuel(player,target(),ISBBQAddFuel,20);command=q.queue[2]
assert(#command.args[1].items==1 and command.args[1].items[1].id==duplicateFuel.id,'overlapping container views must not double-select fuel')
expand(command);count=0;for _, queued in ipairs(q.queue) do if queued.Type=='ISBBQAddFuel' then count=count+1 end end;assert(count==1)
reset();object=target();object.fuel=900;item('Log');item('Log')
ISCampingMenu.onAddAllFuel(player,object,ISBBQAddFuel,900);command=q.queue[2];expand(command)
count=0;for _, queued in ipairs(q.queue) do if queued.Type=='ISBBQAddFuel' then count=count+1 end end;assert(count==1)
-- Stable ID reacquisition handles a replicated replacement object without substituting a new ID.
reset();object=target();fuel=item('Log');ISCampingMenu.onAddFuel(player,object,'Base.Log',ISBBQAddFuel,20);command=q.queue[2]
local replacement=item('Log');inventory.items[replacement.id]=nil;replacement.id=fuel.id;inventory.items[fuel.id]=replacement
expand(command);assert(q.queue[#q.queue].item==replacement)
-- Nested sources use the same recursive reachability as native item selection.
reset();object=target();local nested=container();inventory.nested={nested};fuel=item('Log',nested)
ISCampingMenu.onAddFuel(player,object,'Base.Log',ISBBQAddFuel,20);command=q.queue[2];expand(command)
assert(q.queue[#q.queue].item==fuel and q.queue[2].srcContainer==nested)
-- Independent pending requests can cross in both directions and cancel; shared targets/items cannot.
reset();local a,b=target(),target();local log,paper=item('Log'),item('Paper')
ISCampingMenu.onAddFuel(player,a,'Base.Log',ISBBQAddFuel,20);local left=q.queue[2]
ISCampingMenu.onLightFromLiterature(player,'Base.Paper',item('Matches'),b,ISBBQLightFromLiterature);local right=q.queue[3]
assert(not policy.moveReason(q,left,right,true) and not policy.moveReason(q,right,left,false))
assert(not policy.cancelOperationReason(q,left))
right.args[1].object=a
assert(not api.isDeferredAction(right),'mutating queued snapshot must remove permissions')
right.args[1].object=b
local original = ISCampingMenu.getFuelItemUses
ISCampingMenu.getFuelItemUses=function() return 99 end
assert(not api.isDeferredAction(left));ISCampingMenu.getFuelItemUses=original
reset();a=target();local firstPaper,sharedMatches=item('Paper'),item('Matches')
ISCampingMenu.onLightFromLiterature(player,'Base.Paper',sharedMatches,a,ISBBQLightFromLiterature);left=q.queue[2]
item('Paper');ISCampingMenu.onLightFromLiterature(player,'Base.Paper',sharedMatches,target(),ISBBQLightFromLiterature);right=q.queue[3]
assert(policy.moveReason(q,left,right,true)=='move_shared_item' and policy.cancelOperationReason(q,left)=='operation_shared_item')
reset();a=target();item('Log');item('Paper');ISCampingMenu.onAddFuel(player,a,'Base.Log',ISBBQAddFuel,20);left=q.queue[2]
ISCampingMenu.onLightFromLiterature(player,'Base.Paper',item('Matches'),a,ISBBQLightFromLiterature);right=q.queue[3]
assert(policy.moveReason(q,left,right,true)=='move_dependent' and policy.cancelOperationReason(q,left)=='operation_dependent')
-- Kindling retries can consume a pending fuel action's type; cancel only after that dependency is absent.
reset();local branchDuration=campingFuelType.TreeBranch2;campingFuelType.TreeBranch2=10
local branch=item('TreeBranch2');local borrowed=container();containers=list({inventory,borrowed})
local borrowedPlank,borrowedStick=item('PercedWood',borrowed),item('TreeBranch2',borrowed)
ISCampingMenu.onAddFuel(player,target(),'Base.TreeBranch2',ISBBQAddFuel,20);local pendingFuel=q.queue[2]
ISCampingMenu.onLightFromKindle(player,borrowedPlank,borrowedStick,fire(),ISLightFromKindle);local pendingKindle=q.queue[3]
local why,_,_,conflict,kind=policy.cancelOperationReason(q,pendingKindle)
assert(why=='operation_dependent' and conflict==pendingFuel and kind=='TreeBranch2','pending native retry fuel type must protect cancellation')
table.remove(q.queue,2)
assert(not policy.cancelOperationReason(q,pendingKindle),'independent borrowed kindling cancellation must remain available')
assert(borrowed:contains(borrowedPlank) and borrowed:contains(borrowedStick) and inventory:contains(branch),'waiting validation must not transfer or consume inputs')
campingFuelType.TreeBranch2=branchDuration
-- Native literature completion consumes the selected tinder/starter once and sends the actual fuel/light effects.
reset();a=target('IsoFireplace');paper=item('Paper');local matches=item('Matches')
ISCampingMenu.onLightFromLiterature(player,'Base.Paper',matches,a,ISBBQLightFromLiterature);command=q.queue[2];expand(command)
local light=q.queue[#q.queue];assert(light.Type=='ISBBQLightFromLiterature');light:complete()
assert(matches.used==1 and not inventory:contains(paper) and a.lit and a.changes==1)
-- MP native start rebinds replicated inputs to their live same-ID inventory proxies.
client=true;reset();local mpTarget=target();local originalPaper,originalStarter=item('Paper'),item('Matches')
ISCampingMenu.onLightFromLiterature(player,'Base.Paper',originalStarter,mpTarget,ISBBQLightFromLiterature)
local mpCommand=q.queue[2];expand(mpCommand);local mpLight=q.queue[#q.queue]
assert(api.supports(mpLight))
local livePaper,liveStarter=item('Paper'),item('Matches')
inventory.items[livePaper.id],inventory.items[liveStarter.id]=nil,nil
livePaper.id,liveStarter.id=originalPaper.id,originalStarter.id
inventory.items[livePaper.id],inventory.items[liveStarter.id]=livePaper,liveStarter
livePaper.setJobType=function() end;mpTarget.getComponent=function() end
local setVariable,playSound,componentType=player.SetVariable,player.playSound,ComponentType
player.SetVariable=function() end;player.playSound=function() return 1 end;ComponentType={CraftBenchSounds='sounds'}
mpLight.action={setActionAnim=function() end,finished=function(self) return self.done==true end,isForceComplete=function() return false end}
assert(api.supports(mpLight) and not api.canSkip(mpLight),'MP stale original refs must use native ID membership before native start')
mpLight.item=livePaper;assert(api.supports(mpLight));inventory:Remove(livePaper)
assert(not api.supports(mpLight),'inspection alone must not adopt an MP proxy before its trusted native start')
livePaper.source=inventory;inventory.items[livePaper.id]=livePaper;mpLight.item=originalPaper
mpLight:start()
player.SetVariable,player.playSound,ComponentType=setVariable,playSound,componentType
assert(mpLight.item==livePaper and mpLight.lighter==liveStarter,'actual native MP start did not reacquire live IDs')
assert(api.supports(mpLight),'native MP same-ID input rebinding must retain its sealed fire contract')
client=false;mpLight.item=originalPaper
assert(not api.supports(mpLight),'SP changed input references must remain strict');client=true;mpLight.item=livePaper
local spoof=item('Paper');inventory.items[spoof.id]=nil;spoof.id=originalPaper.id
mpLight.item=spoof;assert(not api.supports(mpLight),'a same-ID object outside the live inventory must remain opaque')
mpLight.item=item('Paper');assert(not api.supports(mpLight),'swapped MP input IDs must remain opaque')
local wrongType=item('Log');inventory.items[wrongType.id]=nil;wrongType.id=originalPaper.id
inventory.items[wrongType.id],mpLight.item=wrongType,wrongType
assert(not api.supports(mpLight),'same-ID live MP input with a different full type must remain opaque')
inventory.items[livePaper.id]=livePaper
mpLight.item=livePaper;local fuelAmount=mpLight.fuelAmt;mpLight.fuelAmt=fuelAmount+1
assert(not api.supports(mpLight),'numeric fire inputs must remain sealed');mpLight.fuelAmt=fuelAmount
inventory:Remove(livePaper);mpTarget.lit=true
assert(api.supports(mpLight) and api.canSkip(mpLight),'native-start-approved MP proxies must retain the contract after authoritative consumption')
mpLight.action.done=true
assert(api.supports(mpLight) and not api.canSkip(mpLight),'native completed MP ignition must retain its audited completion boundary')
client=false
-- Native MP transfer can replace petrol inputs before start, including a last-use starter.
local petrolClasses={ISLightFromPetrol}
if FireTestTrustBBQPetrol then petrolClasses[#petrolClasses+1]=ISBBQLightFromPetrol end
for _, petrolClass in ipairs(petrolClasses) do for _, foreignCallback in ipairs({false,true}) do
    client=true;reset();local petrolTarget=petrolClass==ISLightFromPetrol and fire() or target('IsoFireplace')
    local originalMatch,originalCan=item('Matches'),item('Petrol')
    ISCampingMenu.onLightFromPetrol(player,originalMatch,originalCan,petrolTarget,petrolClass)
    local petrolCommand=q.queue[2];expand(petrolCommand);local petrolAction=q.queue[#q.queue]
    local liveMatch,liveCan=item('Matches'),item('Petrol')
    inventory.items[liveMatch.id],inventory.items[liveCan.id]=nil,nil
    liveMatch.id,liveCan.id=originalMatch.id,originalCan.id
    inventory.items[liveMatch.id],inventory.items[liveCan.id]=liveMatch,liveCan
    liveCan.fluid={amount=1,getAmount=function(self) return self.amount end,adjustAmount=function(self,value) self.amount=value end}
    liveCan.setJobType=function() end;liveCan.getStaticModel=function() return 'PetrolCan' end
    liveMatch.UseAndSync=function(self) self.used=self.used+1;self.uses=self.uses-1;if self.uses==0 then inventory:Remove(self) end end
    petrolAction.lighter,petrolAction.petrol=liveMatch,liveCan
    local starts=0;petrolAction.action={setActionAnim=function() starts=starts+1 end,setOverrideHandModelsObject=function() end,
        finished=function() return false end,isForceComplete=function() return false end}
    local animations,sound=CharacterActionAnims,player.playSound
    CharacterActionAnims={Pour='Pour'};player.playSound=function() return 1 end
    if foreignCallback then petrolAction.onStartFunc=function() end end
    petrolAction:start();assert(starts==1,'native petrol start must run exactly once')
    CharacterActionAnims,player.playSound=animations,sound
    petrolAction.onStartFunc=nil;petrolAction:complete()
    assert(liveMatch.used==1 and not inventory:containsID(liveMatch.id) and math.abs(liveCan.fluid.amount-0.9)<0.00001)
    if foreignCallback then assert(not api.supports(petrolAction),'foreign callback start must not capture replacement proxies')
    else assert(api.supports(petrolAction) and api.canSkip(petrolAction),'trusted petrol start must seal pre-start live replacements through last-use consumption') end
end end
client=false
-- Native petrol completion owns the exact fuel amount and starter consumption in SP and MP.
for _, mp in ipairs({false,true}) do
    client=mp;reset();local camp=fire();local starter,petrol=item('Matches'),item('Petrol')
    petrol.fluid={amount=1,getAmount=function(self) return self.amount end,adjustAmount=function(self,value) self.amount=value end}
    ISCampingMenu.onLightFromPetrol(player,starter,petrol,camp,ISLightFromPetrol);command=q.queue[2];expand(command)
    local action=q.queue[#q.queue];assert(action.Type=='ISLightFromPetrol');action:complete()
    assert(math.abs(petrol.fluid.amount-0.9)<0.00001 and starter.used==1 and camp.isLit)
end
client=false
-- Campfire native completion and missing native target/input skip predicates.
reset();local camp=fire();log=item('Log');ISCampingMenu.onAddFuel(player,camp,'Base.Log',ISAddFuelAction,20);command=q.queue[2];expand(command)
local action=q.queue[#q.queue];assert(api.supports(action) and not api.canSkip(action));action:complete();assert(camp.fuelAmt==100)
reset();camp=fire();log=item('Log');ISCampingMenu.onAddFuel(player,camp,'Base.Log',ISAddFuelAction,20);command=q.queue[2];expand(command);action=q.queue[#q.queue]
campfireObject.removed=true;assert(api.canSkip(action));campfireObject.removed=false
inventory:Remove(log);assert(api.canSkip(action));action.action={finished=function() return true end,isForceComplete=function() return true end}
assert(not api.canSkip(action),'finished native actions must retain completion effects');action.action=nil
local originalGetter=camp.getIsoObject;camp.getIsoObject=function() return campfireObject end
assert(not api.supports(action));camp.getIsoObject=originalGetter
action.item=item('Log');assert(not api.supports(action))
-- Removing an expanded target is unsafe even though the native prestart method still returns true.
do
    reset();local camp=fire();local source=container();containers=list({inventory,source})
    local fuel=item('Log',source)
    ISCampingMenu.onAddFuel(player,camp,'Base.Log',ISAddFuelAction,20)
    local command=q.queue[2];expand(command);pickups()
    local pending=q.queue[#q.queue]
    local tail=synthetic(ISReadABook,player);tail.item=item('Book');ISTimedActionQueue.add(tail)
    local token=pending.toolkitQueueOperation
    assert(pending.Type=='ISAddFuelAction' and api.supports(pending) and not pending.action and pending:isValid()
        and token.toolkitPickups[fuel]==source and inventory:contains(fuel) and not source:contains(fuel),
        'expanded native fuel must retain the exact borrowed item/source for queue cleanup')
    campfireObject.removed=true
    assert(CCampfireSystem.instance:getLuaObjectOnSquare(camp:getSquare())==nil
        and pending:isValidStart() and api.canSkip(pending),
        'the audited unavailable predicate must cover an expanded target before native validity runs')
    local ok,reason=pcall(pending.isValid,pending)
    assert(not ok and tostring(reason):find("local 'campfire'",1,true),
        'native campfire validity must expose the missing-object lookup that the queue transition avoids')
    assert(camp.fuelAmt==20 and fuel.used==0 and inventory:contains(fuel)
        and token.toolkitPickups[fuel]==source and q.queue[#q.queue]==tail
        and tail.toolkitQueueOperation~=token and not tail.action,
        'unavailable-target inspection must preserve borrowed cleanup identity and the independent tail')
    pending.onCompleteFunc=function() error('unknown callback must not run') end
    assert(not api.supports(pending) and not api.canSkip(pending),'unknown callbacks cannot gain unavailable-step permission')
    pending.onCompleteFunc=nil
    assert(api.canSkip(pending),'restoring the audited callback identity must restore unavailable-step permission')
end
-- Cancellation remains protected once fuel/ignition has started; native completion owns all effects.
reset();a=target();item('Log');ISCampingMenu.onAddFuel(player,a,'Base.Log',ISBBQAddFuel,20);command=q.queue[2];expand(command)
action=q.queue[#q.queue];q.queue={action};q.current=action;action.action={finished=function() return false end,isForceComplete=function() return false end,isStarted=function() return true end}
assert(policy.cancelOperationReason(q,action)=='operation_active')
-- Native campfire retries stay before returns and unrelated later work, under the original token.
reset();camp=fire();local bag=container();containers=list({inventory,bag});local plank=item('PercedWood',bag);local stick=item('WoodenStick',bag)
ISCampingMenu.onLightFromKindle(player,plank,stick,camp,ISLightFromKindle);command=q.queue[2];expand(command);pickups()
local parent;for _, queued in ipairs(q.queue) do if queued.Type=='ISLightFromKindle' then parent=queued end end
local tail=synthetic(ISReadABook,player);tail.item=item('Book');ISTimedActionQueue.add(tail)
while q.queue[1]~=parent do table.remove(q.queue,1) end;q.current=parent
local nativePerform=ISBaseTimedAction.perform
ISBaseTimedAction.perform=function(action) api.skipUnavailableReturns(q,action);table.remove(q.queue,1);q.current=q.queue[1] end
parent:perform();ISBaseTimedAction.perform=nativePerform
api.prune(); assert(not api.fixtureRegistries[1][parent] and api.fixtureRegistries[2][command.args[1]], 'retry retains the sealed request after parent and command release')
local retry=q.queue[1];assert(retry.Type=='ISLightFromKindle' and retry.toolkitQueueOperation==parent.toolkitQueueOperation and api.supports(retry))
assert(q.queue[#q.queue]==tail and q.queue[2].Type=='ISInventoryTransferAction')
local contract=policy.inspect(retry);assert(contract.items[stick.id] and contract.dynamicInputs['Base.WoodenStick'])
-- A native broken-stick retry may select another ID; it still owns the original return chain.
local spare=item('WoodenStick2');inventory:Remove(stick)
ISBaseTimedAction.perform=function(action) api.skipUnavailableReturns(q,action);table.remove(q.queue,1);q.current=q.queue[1] end
retry:perform();ISBaseTimedAction.perform=nativePerform
local replacementRetry=q.queue[1]
assert(replacementRetry.Type=='ISLightFromKindle' and replacementRetry.item==spare and replacementRetry.plank==plank)
assert(replacementRetry.toolkitQueueOperation==parent.toolkitQueueOperation and api.supports(replacementRetry))
assert(q.queue[2].Type=='ISInventoryTransferAction' and q.queue[#q.queue]==tail)
contract=policy.inspect(replacementRetry)
assert(contract.items[stick.id] and contract.items[spare.id] and contract.items[plank.id] and contract.targets[campfireObject])
local childItem=replacementRetry.item;replacementRetry.item=item('WoodenStick2')
assert(not api.supports(replacementRetry),'mutating a native retry input must revoke adapter permissions')
replacementRetry.item=childItem;retry=replacementRetry
-- Changing an entry callback after the click revokes both native-child and deferred rights.
local fuelBinding=ISCampingMenu.onAddFuel
ISCampingMenu.onAddFuel=function() end
assert(not api.supports(retry));ISCampingMenu.onAddFuel=fuelBinding
reset();item('Log');ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20);local bindingCommand=q.queue[2]
ISCampingMenu.onAddFuel=function() end;assert(not api.isDeferredAction(bindingCommand));expand(bindingCommand);assert(#q.queue==1)
ISCampingMenu.onAddFuel=fuelBinding
-- A replaced return callback revokes permissions; retry producers must not trust it.
local originalReturn = ISCraftingUI.ReturnItemToContainer
ISCraftingUI.ReturnItemToContainer=function() end
assert(not api.supports(retry));ISCraftingUI.ReturnItemToContainer=originalReturn
-- Only sealed original leading returns may be skipped after their Fire step completes.
do
    local function scenario()
        reset();local camp=fire();local source=container();containers=list({inventory,source})
        local plank,stick=item('PercedWood',source),item('WoodenStick',source)
        ISCampingMenu.onLightFromKindle(player,plank,stick,camp,ISLightFromKindle)
        expand(q.queue[2]);pickups()
        local owner;for _, member in ipairs(q.queue) do if member.Type=='ISLightFromKindle' then owner=member end end
        local tail=synthetic(ISReadABook,player);tail.item=item('Book');ISTimedActionQueue.add(tail)
        while q.queue[1]~=owner do table.remove(q.queue,1) end;q.current=owner
        assert(q.queue[2].item==stick and q.queue[3].item==plank)
        return owner,q.queue[2],q.queue[3],tail,plank,stick,source
    end
    for _, mp in ipairs({false,true}) do
        client=mp
        local owner,missing,restore,tail,plank,stick=scenario();inventory:Remove(stick)
        api.skipUnavailableReturns(q,owner)
        assert(#q.queue==3 and q.queue[2]==restore and q.queue[3]==tail and inventory:contains(plank),
            'missing original return must not interfere with the live return or unrelated tail')
        owner,missing,restore,tail,plank,stick=scenario();inventory:Remove(plank)
        api.skipUnavailableReturns(q,owner)
        assert(#q.queue==4 and q.queue[2]==missing and q.queue[3]==restore,'a live leading return must stop cleanup')
        inventory:Remove(stick);api.skipUnavailableReturns(q,owner)
        assert(#q.queue==2 and q.queue[2]==tail,'consecutive missing original returns must be discarded')
    end
    client=true
    for _, change in ipairs({'callback','source','destination','token','ownerToken','item','perform','helper','transferHelper','pending','started','java','batch','replacement','disabled','cancelled'}) do
        local owner,missing,restore,tail,plank,stick,source=scenario();inventory:Remove(stick)
        local helper=ISCraftingUI.ReturnItemToContainer
        if change=='callback' then missing.onCompleteFunc=function() end
        elseif change=='source' then missing.srcContainer=source
        elseif change=='destination' then missing.destContainer=container()
        elseif change=='token' then missing.toolkitQueueOperation={}
        elseif change=='ownerToken' then owner.toolkitQueueOperation={}
        elseif change=='item' then missing.item=item('WoodenStick')
        elseif change=='perform' then missing.perform=function() end
        elseif change=='helper' then ISCraftingUI.ReturnItemToContainer=function() end
        elseif change=='transferHelper' then missing.startActionAnim=function() end
        elseif change=='pending' then missing.transactionId=3
        elseif change=='started' then missing.started=true
        elseif change=='java' then missing.action={}
        elseif change=='batch' then missing.queueList[1].items[2]=plank
        elseif change=='replacement' then
            local replacement=ISInventoryTransferAction:new(player,stick,inventory,source,50)
            replacement:setAllowMissingItems(true);replacement.toolkitQueueOperation=owner.toolkitQueueOperation
            q.queue[2]=replacement;missing=replacement
        elseif change=='disabled' then enabled=false
        elseif change=='cancelled' then owner.toolkitQueueOperation.toolkitCancelled=true end
        api.skipUnavailableReturns(q,owner)
        assert(#q.queue==4 and q.queue[2]==missing and q.queue[3]==restore and q.queue[4]==tail,change..' must revoke missing-return cleanup')
        ISCraftingUI.ReturnItemToContainer=helper;enabled=true
    end
    for i=1,100 do
        local owner,missing,restore=scenario();api.prune()
        local count=0;for _ in pairs(api.fixtureRegistries[4]) do count=count+1 end
        assert(count==2,'private original return records must prune completed/removed operations')
    end
    mainMenuCleanup();assert(table.isempty(api.fixtureRegistries[4]),'main menu must release private original returns')
    scenario();reset();api.prune();assert(table.isempty(api.fixtureRegistries[4]),'removed returns must release their private records')
    local function nativeRebind(original)
        local live=item(original.kind);inventory.items[live.id]=nil;live.id=original.id;inventory.items[live.id]=live
        -- ActionManager.replaceObjectInQueuedActions only replaces direct fields, never nested queueList tables.
        for _, member in ipairs(q.queue) do
            for key,value in pairs(member) do if value==original then member[key]=live end end
        end
        return live
    end
    local function startOwner(owner,plank,stick)
        stick.setJobType=function() end;plank.setJobType=function() end
        owner.action={setActionAnim=function() end,setOverrideHandModelsObject=function() end}
        owner:start()
    end
    for _, trusted in ipairs({false,true}) do for _, changedBatch in ipairs({false,true}) do
        local owner,missing,restore,tail,plank,stick=scenario()
        local live=nativeRebind(stick);local livePlank=nativeRebind(plank)
        assert(missing.item==live and missing.queueList[1].items[1]==stick and restore.item==livePlank
            and restore.queueList[1].items[1]==plank,'Java queued-object replacement must leave nested native batch references unchanged')
        if changedBatch then missing.queueList[1].items[1]=live end
        if trusted then startOwner(owner,livePlank,live) end
        inventory:Remove(live);api.skipUnavailableReturns(q,owner)
        if trusted and not changedBatch then
            assert(q.queue[2]==restore and q.queue[3]==tail,'trusted native MP start must seal shallow-rebound return proxies before consumption')
        else assert(q.queue[2]==missing,'absent same-ID proxies or replaced nested batch refs must not be adopted') end
    end end
    -- Exercise the actual native start/isValid/perform reuse that lost the MP tail.
    -- Java TransactionManager rejects even its own pending transaction before Lua.started is true.
    local pending=false
    local priorTrading,priorOptions,priorConsistency,priorCreate,priorRemove,priorLog=ISTradingUI,getServerOptions,isItemTransactionConsistent,createItemTransaction,removeItemTransaction,ISLogSystem
    local priorMoving,priorEmitter,priorFarming=player.isPlayerMoving,player.getEmitter,player.setIsFarming
    ISTradingUI={GetUIForPlayer=function() end};getServerOptions=function() return {getInteger=function() return 0 end} end
    isItemTransactionConsistent=function() return not pending end
    createItemTransaction=function() pending=true;return 3 end
    removeItemTransaction=function() pending=false end
    ISLogSystem={logAction=function() end};player.isPlayerMoving=function() return false end;player.setIsFarming=function() end
    player.getEmitter=function() return {playSound=function() return 1 end,isPlaying=function() return false end} end
    local function engine(action)
        for _,name in ipairs({'playSourceContainerOpenSound','playDestContainerOpenSound','playSourceContainerCloseSound',
            'playDestContainerCloseSound','playTransferCompleteSound','stopLoopingSound','startActionAnim','resetJobDelta'}) do action[name]=function() end end
        action.getTransferStartSoundName=function() end
        action.action={setTime=function(self,value) self.time=value end,reset=function() end,setLoopedAction=function() end,
            setWaitForFinished=function() end,stopTimedActionAnim=function() end,isStarted=function() return true end}
        action.item.getWeight=function() return 2 end
    end
    for _, cleanup in ipairs({false,true}) do
        pending=false
        local owner,missing,restore,tail,plank,stick,source=scenario()
        if cleanup then
            local live=nativeRebind(stick);plank=nativeRebind(plank);startOwner(owner,plank,live)
            inventory:Remove(live);api.skipUnavailableReturns(q,owner)
        else inventory:Remove(stick) end
        table.remove(q.queue,1);q.current=q.queue[1]
        local action=q.current;engine(action)
        assert(action:isValid());action:start()
        if not cleanup then
            assert(action==missing and action.dontAdd and not action.started)
            plank.getWeight=function() return 2 end;action:perform()
            assert(action.item==plank and pending and action.transactionId==3 and not action.started)
            assert(not action:isValid(),'native missing-return reuse must expose its own pending-transaction failure')
            action:stop();assert(#q.queue==0,'baseline native failure must reproduce unrelated tail loss')
        else
            assert(action==restore and action.started and pending and action:isValid(),'live return must start its own native transaction normally')
            inventory:Remove(plank);plank.source=source;source.items[plank.id]=plank
            local began=false;tail.begin=function() began=true end
            action:perform()
            assert(source:contains(plank) and q.current==tail and #q.queue==1 and began and not pending,
                'native accepted plank return must complete and start the unrelated book')
        end
    end
    ISTradingUI,getServerOptions,isItemTransactionConsistent,createItemTransaction,removeItemTransaction,ISLogSystem=priorTrading,priorOptions,priorConsistency,priorCreate,priorRemove,priorLog
    player.isPlayerMoving,player.getEmitter,player.setIsFarming=priorMoving,priorEmitter,priorFarming
    client=false
end

-- The actual Project Cook FUEL/LIGHT closures forward native callbacks for each supported cooker.
if NativeWishlistWorkshopRoot then
    PJCK_CookerAdjustmentPanel, PJCK_CookerPicker = {}, {}
    local cookRoot=NativeWishlistWorkshopRoot .. '/3490188370/mods/Project_Cook/common/media/lua/client/Project_Cook/Cooker/'
    extract(cookRoot .. 'PJCK_CookerAdjustmentPanel.lua', '(function PJCK_CookerAdjustmentPanel:onAddFuelButtonClick.-\nend)')
    extract(cookRoot .. 'PJCK_CookerAdjustmentPanel.lua', '(function PJCK_CookerAdjustmentPanel:getCurrentFuelAmount.-\nend)')
    extract(cookRoot .. 'PJCK_CookerPicker.lua', '(function PJCK_CookerPicker:showLightFireContextMenu.-\nend)')
    UIManager={getSpeedControls=function() return {getCurrentGameSpeed=function() return 1 end} end}
    ISWorldObjectContextMenu={addToolTip=function() return {} end}
    local menuOptions
    local function menu()
        return {options={},setAlwaysOnTop=function() end,getNew=function() return menu() end,
            addOption=function(self) local option={};self.options[#self.options+1]=option;return option end,
            addSubMenu=function() end,addActionsOption=function(self,text,callback,...)
                local option={callback=callback,args={...}};menuOptions[#menuOptions+1]=option;self.options[#self.options+1]=option;return option
            end}
    end
    ISContextMenu.get=function() return menu() end
    ISContextMenu.getNew=function() return menu() end
    for _, kind in ipairs({'FIREPLACE','CAMPFIRE','CHARCOAL_BBQ'}) do
        reset();local object=kind=='CAMPFIRE' and fire() or target(kind=='FIREPLACE' and 'IsoFireplace' or 'IsoBarbecue')
        item('Log');item('Paper');item('Matches')
        local selected={getParent=function() return kind=='CAMPFIRE' and campfireObject or object end}
        local panel={player=player,CookerPanel={selectedCooker=selected,CookerType=kind,getCampfireLuaObject=function() return object end},
            getCurrentFuelAmount=PJCK_CookerAdjustmentPanel.getCurrentFuelAmount,getAbsoluteX=function() return 0 end,getAbsoluteY=function() return 0 end,
            adjustmentInfo={{getX=function() return 0 end,getY=function() return 0 end,getWidth=function() return 10 end}}}
        panel.controlButton=panel.adjustmentInfo[1]
        menuOptions={};PJCK_CookerAdjustmentPanel.onAddFuelButtonClick(panel)
        local option=menuOptions[1];assert(option and option.callback==ISCampingMenu.onAddFuel)
        ISTimedActionQueue.queueActions(player,option.callback,unpack(option.args));command=q.queue[2]
        assert(api.isDeferredAction(command) and command.toolkitWorldTarget==selected:getParent())
        menuOptions={};PJCK_CookerPicker.showLightFireContextMenu(panel)
        option=menuOptions[1];assert(option and option.callback==ISCampingMenu.onLightFromLiterature)
        ISTimedActionQueue.queueActions(player,option.callback,unpack(option.args));assert(api.isDeferredAction(q.queue[3]))
        -- Mutating selection afterwards cannot retarget either queued request.
        panel.CookerPanel.selectedCooker={getParent=function() return target() end}
        assert(command.toolkitWorldTarget==selected:getParent())
    end
end
-- Missing target/snapshot tampering never expands; disabling the feature still delegates to native callbacks.
reset();a=target();item('Log');ISCampingMenu.onAddFuel(player,a,'Base.Log',ISBBQAddFuel,20);command=q.queue[2];a.removed=true;expand(command);assert(#q.queue==1)
reset();a=target();item('Log');ISCampingMenu.onAddFuel(player,a,'Base.Log',ISBBQAddFuel,20);command=q.queue[2];command.args[1].items[1].uses=99;expand(command);assert(#q.queue==1)
reset();a=target();item('Log');enabled=false;ISCampingMenu.onAddFuel(player,a,'Base.Log',ISBBQAddFuel,20);assert(q.queue[#q.queue].Type=='ISBBQAddFuel');enabled=true
if not FireTestTrustBBQPetrol then
    assert(not api.supports(ISBBQLightFromPetrol:new(player,target(),item('Matches'),item('Petrol'))),'pre-capture replacement must remain protected')
end
-- Unsupported action classes still execute the actual native shared callback, without adapter rights.
local modFuel=ISBBQAddFuel:derive('ModFuel')
reset();a=target();local customLog=item('Log')
ISCampingMenu.onAddFuel(player,a,'Base.Log',modFuel,20)
local custom=q.queue[#q.queue];assert(custom.Type=='ModFuel' and custom.item==customLog and not api.supports(custom))
custom:complete();assert(a.fuel==100 and not inventory:contains(customLog))
reset();a=target();customLog=item('Log')
ISTimedActionQueue.queueActions(player,ISCampingMenu.onAddFuel,a,'Base.Log',modFuel,20)
local opaqueRequest=q.queue[2];assert(opaqueRequest.Type=='ISQueueActionsAction' and not api.isDeferredAction(opaqueRequest) and not policy.inspect(opaqueRequest))
expand(opaqueRequest);assert(q.queue[#q.queue].Type=='ModFuel' and q.queue[#q.queue].item==customLog)
-- A lifecycle replacement made after adapter capture also stays on the native opaque route.
local valid=ISBBQAddFuel.isValid
ISBBQAddFuel.isValid=function() return true end
reset();a=target();item('Log');ISCampingMenu.onAddFuel(player,a,'Base.Log',ISBBQAddFuel,20)
assert(q.queue[#q.queue].Type=='ISBBQAddFuel' and not api.supports(q.queue[#q.queue]))
reset();a=target();customLog=item('Log')
ISTimedActionQueue.queueActions(player,ISCampingMenu.onAddFuel,a,'Base.Log',ISBBQAddFuel,20)
opaqueRequest=q.queue[2];assert(not api.isDeferredAction(opaqueRequest) and opaqueRequest.addActionsFunction~=ISCampingMenu.onAddFuel)
ISBBQAddFuel.isValid=valid
expand(opaqueRequest);custom=q.queue[#q.queue]
assert(custom.Type=='ISBBQAddFuel' and custom.item==customLog and not api.supports(custom),'restored lifecycle must not convert opaque work into adapter-owned work')
-- Compatible mod world targets also retain native execution while remaining opaque.
reset();a=target('ModBBQ');customLog=item('Log')
ISCampingMenu.onAddFuel(player,a,'Base.Log',ISBBQAddFuel,20);custom=q.queue[#q.queue]
assert(custom.Type=='ISBBQAddFuel' and custom.fireplace==a and not api.supports(custom));custom:complete();assert(a.fuel==100)
-- Changing an unused unequip hook cannot revoke single-fuel or lighting requests.
reset();item('Log');ISCampingMenu.onAddFuel(player,target(),'Base.Log',ISBBQAddFuel,20)
local singleEquipment=q.queue[2]
local ordinaryUnequip=ISUnequipAction.new
ISUnequipAction.new=function(self,...) return ordinaryUnequip(self,...) end
assert(api.isDeferredAction(singleEquipment),'single fuel depended on unused equipment')
reset();local ordinaryPaper,ordinaryLighter=item('Paper'),item('Matches')
ISCampingMenu.onLightFromLiterature(player,'Base.Paper',ordinaryLighter,target(),ISBBQLightFromLiterature)
assert(api.isDeferredAction(q.queue[2]),'lighting depended on unused equipment')
reset();local equippedFuel=item('Log');equippedFuel.equipped=true
ISCampingMenu.onAddAllFuel(player,target(),ISBBQAddFuel,20)
assert(not api.isDeferredAction(q.queue[2]),'multiple fuel accepted an unknown used equipment constructor')
ISUnequipAction.new=ordinaryUnequip
if SaucedCartsSource then
    -- Real SaucedCarts wrappers delegate the ordinary selected fuel; operation ownership stays exact.
    native('shared/Camping/ISCampingMenu.lua')
    for _,name in ipairs({'ISAddFuelAction','ISLightFromLiterature','ISLightFromPetrol','ISLightFromKindle'}) do native('shared/Camping/TimedActions/'..name..'.lua') end
    for _,name in ipairs({'ISBBQAddFuel','ISBBQLightFromLiterature','ISBBQLightFromPetrol','ISBBQLightFromKindle','ISUnequipAction'}) do native('shared/TimedActions/'..name..'.lua') end
    -- This independent capture needs the same observed native BC installation as the first fixture.
    ISInventoryPaneContextMenu.getContainers=originalContainerGetter
    if bcControls then
        local controlsPath=NativeWishlistWorkshopRoot .. '/3586216562/mods/BetterContainers/42.20/media/lua/client/BetterContainers/Proximity/Proximity_ISLootWindowContainerControls.lua'
        bcControls=assert(loadstring(read(controlsPath),'@'..controlsPath))()
    end
    project('ActionQueueDefinitions');policy=project('ActionQueuePolicy')
    local previous={new=ISUnequipAction.new,complete=ISUnequipAction.complete}
    local path=SaucedCartsSource..'/ContainerRestrictions.lua';local text=read(path)
    SaucedCarts={debug=function() end,safeIsCart=function(value) return value and value.cart==true end}
    local code='local unequipHookInitialized=false\n'
        ..assert(text:match('(local function flushDistanceOnCreate%(character, item, label%).-\nend)'))..'\n'
        ..assert(text:match('(local function wrapUnequipNew%(%).-\nend)'))..'\n'
        ..assert(text:match('(local function initUnequipHook%(%).-\nend)'))..'\ninitUnequipHook()'
    assert(loadstring(code,'@'..path))()
    local replacement={new=ISUnequipAction.new,complete=ISUnequipAction.complete}
    local equipmentActive=true
    local matcher=assert(policy.nativeUnequipVariant(previous,replacement,function() return equipmentActive end))
    local firstConstructor=ISInventoryTransferAction.new
    local laterConstructor=function(self,...) return firstConstructor(self,...) end
    local verifiedConstructors={[firstConstructor]=true,[laterConstructor]=true}
    local carts={isTransfer=function() return false end,isReturn=function() return false end,isTransferConstructor=function(callback) return verifiedConstructors[callback]==true end,
        isUnequipConstructor=function(callback) return equipmentActive and callback==replacement.new and ISUnequipAction.complete==replacement.complete end,
        isNonCartItem=function(value) return equipmentActive and not value.cart end,
        isNonCartUnequip=function(value) return equipmentActive and matcher(value) and not value.item.cart end}
    PZSurvivorToolkit.ActionQueueCarts=carts
    local producerRegister=operations.registerProducer;operations.registerProducer=function() end
    api=project('ActionQueueFire');operations.registerProducer=producerRegister
    if bcControls then bcControls.install() end
    reset();local selectedFuel=item('Log');selectedFuel.equipped=true
    ISCampingMenu.onAddAllFuel(player,target(),ISBBQAddFuel,20)
    command=q.queue[2];assert(api.isDeferredAction(command),'verified cart equipment did not admit selected ordinary fuel')
    local approvedConstructor=carts.isTransferConstructor;carts.isTransferConstructor=function() return true end
    assert(not api.isDeferredAction(command),'replaced cart transfer proof retained fire request');carts.isTransferConstructor=approvedConstructor
    ISInventoryTransferAction.new=laterConstructor
    assert(api.isDeferredAction(command),'verified later cart constructor revoked fire request')
    expand(command)
    local preparation
    for _,member in ipairs(q.queue) do if member.Type=='ISUnequipAction' then preparation=member end end
    assert(preparation and policy.inspect(preparation),'owned actual cart-wrapper unequip lacked preparation permission')
    assert(not policy.inspect(ISUnequipAction:new(player,selectedFuel,50)),'unowned unequip borrowed fire ownership')
    equipmentActive=false
    assert(not policy.inspect(preparation),'revoked cart equipment proof retained preparation rights')
    equipmentActive=true;selectedFuel.cart=true
    assert(not policy.inspect(preparation),'selected cart borrowed ordinary-fuel equipment rights')
    selectedFuel.cart=nil
    local acceptedItem=carts.isNonCartItem;carts.isNonCartItem=function() return true end
    assert(not policy.inspect(preparation),'replaced cart classification proof retained fire rights');carts.isNonCartItem=acceptedItem
    ISInventoryTransferAction.new=firstConstructor
end
-- A different resolved source must not acquire permissions even if helper closures kept the same names.
local sourceReader=getGameFilesInput
getGameFilesInput=function() return {readLine=function() return nil end,close=function() end} end
local originalRegister,originalBehavior=operations.registerProducer,PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior
operations.registerProducer=function() end;PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior=function() end
project('ActionQueueFire')
operations.registerProducer=originalRegister;PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior=originalBehavior
reset();local opaque=target();item('Log');ISCampingMenu.onAddFuel(player,opaque,'Base.Log',ISBBQAddFuel,20)
assert(q.queue[#q.queue].Type=='ISBBQAddFuel' and not PZSurvivorToolkit.ActionQueueFire.supports(q.queue[#q.queue]))
getGameFilesInput=sourceReader
print('Fire native contracts: fixed resource IDs, SP/MP completion, multi-use limits, independent/shared work, active boundary, retry-before-returns, sealed missing returns, native MP transfer reuse and source/helper guards passed.')
