if not NativeActionRoot then print('Fitness queue native contracts SKIP.'); return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
local fixtureRequire=require
require=function(name)
    if name=='PZSurvivorToolkit/FitnessEquipment' then
        return PZSurvivorToolkit.FitnessEquipment
            or assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua'))()
    end
    if name=='PZSurvivorToolkit/ActionQueueSettlement' then
        return PZSurvivorToolkit.ActionQueueSettlement
            or assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua'))()
    end
    return fixtureRequire(name)
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function native(path)
    return assert(loadstring(read(NativeActionRoot..'/'..path),'@media/lua/'..path))()
end
local function extract(path,pattern,prefix)
    return assert(loadstring((prefix or '')..assert(read(NativeActionRoot..'/'..path):match(pattern),pattern),
        '@media/lua/'..path))()
end
getFilenameOfClosure=function(callback) return debug.getinfo(callback,'S').source:gsub('^@','') end
for _,path in ipairs({'shared/TimedActions/ISBaseTimedAction.lua','client/TimedActions/ISTimedActionQueue.lua',
    'client/TimedActions/ISQueueActionsAction.lua','shared/TimedActions/ISReadABook.lua','client/TimedActions/ISInventoryTransferAction.lua'})do native(path)end
local sourceOverride
getGameFilesInput=function(path)
    local text=sourceOverride and sourceOverride(path) or read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
    local offset=1
    return {readLine=function()
        if offset>#text then return end
        local stop=text:find('\n',offset) or #text+1
        local line=text:sub(offset,stop-1);offset=stop+1;return line
    end,close=function()end}
end
local enabled,client,now=true,false,1000000
local transactions,nextTransaction={},0
isItemTransactionDone=function(id)return transactions[id]=='completed' end
isItemTransactionRejected=function(id)return transactions[id]=='rejected' end
createItemTransaction=function()error('fixture never requests native transactions')end
removeItemTransaction=function()end
isClient=function()return client end;isServer=function()return false end
PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
getTimestampMs=function()return now end
getCore=function()return {getGameMode=function()return 'Sandbox' end}end
local quantizedCalendar=false
local calendarOffset=0
local frameClock={id=0,ms=0,now=now,manual=false,offset=0}
frameClock.world={getFrameNo=function()
 if not frameClock.manual and now~=frameClock.now then
  frameClock.ms=math.max(0,now-frameClock.now);frameClock.now=now;frameClock.id=frameClock.id+1
 end
 return frameClock.id
end}
getWorld=function()return frameClock.world end
getGameTime=function()return {
 getCalender=function()return {getTimeInMillis=function()
  local world=now+frameClock.offset
  return(quantizedCalendar and math.floor(world/60000)*60000 or world)+calendarOffset
 end}end,
 getNightsSurvived=function()return math.floor((now+frameClock.offset)/86400000)end,
 getTimeOfDay=function()return((now+frameClock.offset)/3600000+7)%24 end,
 getGameWorldSecondsSinceLastUpdate=function()return frameClock.ms/1000 end}end
local tickCallbacks,menuCallbacks={},{}
Events.OnTick.Add=function(callback)tickCallbacks[#tickCallbacks+1]=callback end
Events.OnMainMenuEnter={Add=function(callback)menuCallbacks[#menuCallbacks+1]=callback end}
MoodleType={ENDURANCE='endurance',HEAVY_LOAD='load',PAIN='pain'}
ItemTag={LIT_LANTERN='lit_lantern',WEARABLE='wearable',REPLACE_PRIMARY='replace_primary',LIGHTER='lighter'}
ItemType={RADIO='radio'};ItemBodyLocation=setmetatable({},{__index=function(_,key)return key end})
CharacterTrait={};Perks={};WearClothingAnimations={}
getPlayerHotbar=function()end
getPlayerInventory=function()return {refreshBackpacks=function()end}end
sendEquip=function()end;syncItemActivated=function()end;triggerEvent=function()end
sendRemoveItemFromContainer=function()end
setGameSpeed=function()end
round=function(value,places)local multiplier=10^places;return math.floor(value*multiplier+.5)/multiplier end
getTextManager=function()return {getFontHeight=function()return 14 end}end
UIFont={Small='small'}
ISPanelJoypad=ISBaseObject:derive('ISPanelJoypad')
native('shared/TimedActions/ISWearClothing.lua')
native('shared/TimedActions/ISUnequipAction.lua')
native('shared/TimedActions/ISEquipWeaponAction.lua')
native('shared/TimedActions/ISFitnessAction.lua')
native('shared/TimedActions/ISWaitWhileGettingUp.lua')
native('shared/TimedActions/ISDropWorldItemAction.lua')
native('client/ISUI/ISFitnessUI.lua')
native('shared/TimedActions/ISInventoryTransferUtil.lua')
luautils={}
extract('shared/luautils.lua','(function luautils.haveToBeTransfered%(.-\nend)')
extract('shared/luautils.lua','(function luautils.walkToContainer%(.-\nend)')
extract('client/ISUI/ISInventoryPaneContextMenu.lua','(function ISInventoryPaneContextMenu.transferIfNeeded%(.-\nend)')
extract('client/ISUI/ISInventoryPaneContextMenu.lua','(ISInventoryPaneContextMenu.unequipItem = function.-\nend)')
extract('client/ISUI/ISInventoryPaneContextMenu.lua','(ISInventoryPaneContextMenu.wearItem = function.-\nend)')
extract('client/ISUI/ISInventoryPaneContextMenu.lua','(ISInventoryPaneContextMenu.onActivateItem = function.-\nend)')
ISWorldObjectContextMenu={}
extract('client/ISUI/ISWorldObjectContextMenu.lua','(function ISWorldObjectContextMenu.transferIfNeeded%(.-\nend)')
extract('client/ISUI/ISWorldObjectContextMenu.lua','(ISWorldObjectContextMenu.equip = function.-\nend)',
    'local function predicateNotBroken(item) return not item:isBroken() end\n')
local function list(values)
    return {size=function()return #values end,get=function(_,index)return values[index+1]end,
        contains=function(_,wanted)for _,value in ipairs(values)do if value==wanted then return true end end;return false end}
end
local player=f.player
player.class='IsoPlayer';player.vars={};player.worn={};player.primary=nil;player.secondary=nil
player.getOnlineID=function()return 101 end
local repeats,currentExercise,fitnessSpeed=0,nil,0
-- Native Fitness.getCurrentExe returns a FitnessExercise object, not its name.
local exerciseStates=setmetatable({},{__index=function(states,name)
    local state={name=name};rawset(states,name,state);return state
end})
local fitness={init=function()end,getCurrentExe=function()return currentExercise and exerciseStates[currentExercise] end,
    setCurrentExercise=function(_,value)currentExercise=value end,exerciseRepeat=function()repeats=repeats+1 end}
player.getFitness=function()return fitness end
player.setFitnessSpeed=function()fitnessSpeed=fitnessSpeed+1 end
player.getPrimaryHandItem=function()return player.primary end;player.getSecondaryHandItem=function()return player.secondary end
player.setPrimaryHandItem=function(_,value)player.primary=value end;player.setSecondaryHandItem=function(_,value)player.secondary=value end
player.isItemInBothHands=function(_,item)return item~=nil and player.primary==item and player.secondary==item end
player.isEquipped=function(_,item)return item~=nil and (player.primary==item or player.secondary==item or player.worn[item:canBeEquipped()]==item)end
player.getWornItems=function()
    local entries={};for location,item in pairs(player.worn)do entries[#entries+1]={getLocation=function()return location end,getItem=function()return item end}end
    local worn=list(entries)
    worn.contains=function(_,item)for _,value in pairs(player.worn)do if value==item then return true end end;return false end
    return worn
end
player.getWornItem=function(_,location)return player.worn[location]end
player.setWornItem=function(_,location,item)player.worn[location]=item end
player.removeWornItem=function(_,item)for location,value in pairs(player.worn)do if value==item then player.worn[location]=nil end end end
player.isEquippedClothing=function(_,item)for _,value in pairs(player.worn)do if value==item then return true end end;return false end
player.getClothingItem_Back=function()end
player.removeFromHands=function(_,item)if player.primary==item then player.primary=nil end;if player.secondary==item then player.secondary=nil end end
player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
player.getVehicle=function()end;player.isClimbing=function()return false end
player.isAiming=function()return false end;player.isSneaking=function()return false end
player.isSittingOnFurniture=function()return false end
player.isSitting=function()return player.sitting==true end
player.isHandItem=function(_,item)return item~=nil and (player.primary==item or player.secondary==item)end
player.isLocalPlayer=function()return true end
player.isDraggingCorpse=function()return false end;player.isFarming=function()return false end
player.isWearingAwkwardGloves=function()return false end;player.hasTrait=function()return false end
player.setVariable=function(_,key,value)player.vars[key]=value end
player.SetVariable=player.setVariable
player.getVariableBoolean=function(_,key)return player.vars[key]==true end
player.clearVariable=function(_,key)player.vars[key]=nil end
player.reportEvent=function()end;player.setMetabolicTarget=function()end
player.PlayAnim=function()end;player.setIsFarming=function()end
player.updateHandEquips=function()end
player.getEmitter=function()return {playSound=function()end,stopSound=function()end}end
player.getCurrentState=function()return {}end
local worlds={}
local here={x=10,y=10,z=0}
function here:getX()return self.x end;function here:getY()return self.y end;function here:getZ()return self.z end
function here:getWorldObjects()return list(worlds)end
function here:isAdjacentTo(other)return self.z==other.z and math.abs(self.x-other.x)<=1 and math.abs(self.y-other.y)<=1 end
function here:isBlockedTo()return false end
function here:getTotalWeightOfItemsOnFloor()
    local weight=0;for _,world in ipairs(worlds)do weight=weight+world:getItem():getUnequippedWeight()end;return weight
end
function here:AddWorldInventoryItem(item)
    local world={getItem=function()return item end,getSquare=function()return self end,
        setIgnoreRemoveSandbox=function()end,setExtendedPlacement=function()end,transmitCompleteItemToClients=function()end}
    item.world=world;worlds[#worlds+1]=world;return item
end
local currentSquare=here
player.getCurrentSquare=function()return currentSquare end
IdleState={instance=function()return {}end};FitnessState={instance=function()return {}end}
local nextID=0
local function container(owner)
    local value={class='ItemContainer',items={},owner=owner}
    function value:getItems()return list(self.items)end
    function value:getItemById(id)for _,item in ipairs(self.items)do if item:getID()==id then return item end end end
    value.getItemWithID=value.getItemById
    function value:contains(wanted,recurse)
        for _,item in ipairs(self.items)do
            if item==wanted or type(wanted)=='string' and (item:getType()==wanted or item:getFullType()==wanted)then return true end
            if recurse and item.inner and item.inner:contains(wanted,true)then return true end
        end
        return false
    end
    function value:containsID(id)return self:getItemById(id)~=nil end
    function value:getFirstTypeEvalRecurse(kind,predicate)
        for _,item in ipairs(self.items)do
            if (item:getType()==kind or item:getFullType()==kind) and (not predicate or predicate(item))then return item end
            if item.inner then local found=item.inner:getFirstTypeEvalRecurse(kind,predicate);if found then return found end end
        end
    end
    function value:Remove(wanted)for index,item in ipairs(self.items)do if item==wanted then table.remove(self.items,index);wanted.source=nil;return end end end
    function value:AddItem(item)self.items[#self.items+1]=item;item.source=self;return item end
    function value:getContainingItem()return self.owner end
    function value:getParent()end
    function value:getType()return self.owner and 'bag' or 'inventory' end
    function value:isInCharacterInventory()return true end
    function value:isExistYet()return true end
    function value:isInside()return false end
    function value:isVehicleSeat()return false end
    function value:getCapacityWeight()return #self.items end
    function value:getMaxWeight()return 50 end
    function value:hasRoomFor(_,item)return self:getCapacityWeight()+item:getWeight()<=self:getMaxWeight() end
    function value:setDrawDirty()end
    return value
end
player.inventory=container()
local floor=container();floor.getType=function()return 'floor'end
floor.isInCharacterInventory=function()return false end
ISInventoryPage.GetFloorContainer=function()return floor end
getPlayerLoot=function()return {refreshBackpacks=function()
    floor.items={}
    for _,world in ipairs(worlds)do floor:AddItem(world:getItem())end
end}end
local function item(kind,source,location,twoHands)
    nextID=nextID+1
    local value={class=location and 'InventoryContainer' or 'InventoryItem',id=nextID,kind=kind,source=source or player.inventory,location=location,twoHands=twoHands,active=false}
    function value:getID()return self.id end;function value:getFullType()return 'Base.'..self.kind end;function value:getType()return self.kind end
    function value:getContainer()return self.source end;function value:getName()return self.kind end
    function value:getDisplayName()return self.kind end;function value:getCategory()return 'Item' end
    function value:isBroken()return false end;function value:IsClothing()return false end
    function value:IsInventoryContainer()return self.location~=nil end;function value:canBeEquipped()return self.location or '' end
    function value:getBodyLocation()return '' end;function value:hasTag()return false end
    function value:isTwoHandWeapon()return self.twoHands end;function value:isRequiresEquippedBothHands()return self.twoHands end
    function value:isForceDropHeavyItem()return false end;function value:canBeActivated()return false end
    function value:isActivated()return self.active end;function value:setActivated(active)self.active=active end
    function value:getCurrentUsesFloat()return 1 end;function value:isHumanCorpse()return false end
    function value:isFavorite()return self.favorite==true end
    function value:getWorldItem()return self.world end
    function value:setWorldZRotation()end
    function value:getUnequippedWeight()return self.weight or 1 end
    function value:getIsCraftingConsumed()return false end;function value:getActualWeight()return 1 end
    function value:getWeight()return self.weight or 1 end
    function value:getEquipSound()end;function value:getUnequipSound()end;function value:setJobDelta()end;function value:setJobType()end
    function value:getClothingItem()end;function value:getScriptItem()return {isItemType=function()return false end}end
    function value:playActivateDeactivateSound()end
    function value:playActivateSound()end
    function value:playDeactivateSound()end
    value.source.items[#value.source.items+1]=value
    if location then value.inner=container(value);value.getInventory=function()return value.inner end end
    return value
end
-- InventoryContainer is also an InventoryItem in the native Java type hierarchy.
instanceof=function(value,name)return type(value)=='table' and (value.class==name or name=='InventoryItem' and value.class=='InventoryContainer')end
Metabolics={Fitness=1,FitnessHeavy=2}
native('shared/Definitions/FitnessExercises.lua')
local function panel(kind,minutes)
    return setmetatable({player=player,selectedExe=kind,exeData=FitnessExercises.exercisesType[kind],fitness=fitness,itemsToReequip={},
        exeTime={getInternalText=function()return tostring(minutes or 10)end}},ISFitnessUI)
end
f.project('ActionQueueOperations');f.project('ActionQueueNativeContinuation');f.project('ActionQueueDefinitions');f.project('BulkActions')
local policy=f.project('ActionQueuePolicy')
ISInventoryPaneContextMenu.getContainers=function()return list({})end
local receipt,preparationReceipts=nil,{}
PZSurvivorToolkit.ActionQueueAcknowledgements={capture=function(action)return preparationReceipts[action] or receipt end,
    state=function(action,captured)
        if captured==preparationReceipts[action] or captured==receipt then return captured.state end
    end,
    observe=function(action,captured)
        if captured==preparationReceipts[action] or captured==receipt then return captured.state end
    end}

local nativeFitness={complete=ISFitnessAction.complete,exeLooped=ISFitnessAction.exeLooped,animEvent=ISFitnessAction.animEvent,
    serverStart=ISFitnessAction.serverStart,serverStop=ISFitnessAction.serverStop}
local lifecycle=f.project('ActionQueueLifecycle')
local lifecycleSweep=assert(tickCallbacks[#tickCallbacks],'guarded stop sweep not registered')
f.project('ActionQueueTidyIntent')
local fitnessQueue=f.project('ActionQueueFitness')
-- BulkFood installs this native binding after ActionQueue/Fitness loads. Execute
-- its real registration so broad native matches cannot hide a second owner.
local foodContractSource=assert(read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/BulkFood.lua')
    :match('(local function installCleanupContract%(%).-\nend)'))
local function installFoodWearContract()
    local cleanup={}
    local bulk={isCleanup=function(action)return cleanup[action]==true end}
    local install=assert(loadstring('local Toolkit,Bulk,Settlement=...\n'..foodContractSource..'\nreturn installCleanupContract',
        '@PZSurvivorToolkit/BulkFood.lua'))(PZSurvivorToolkit,bulk,PZSurvivorToolkit.ActionQueueSettlement)
    install()
    return cleanup,bulk
end
local foodWear,foodOwner=installFoodWearContract()
do
    local bag=item('Bag_Schoolbag',nil,'BACK')
    local owned=ISWearClothing:new(player,bag)
    foodWear[owned]=true
    local contract,adapter=policy.inspect(owned)
    assert(contract and adapter=='native.ISWearClothing','registered food cleanup lost its native contract')
    local foreign=ISWearClothing:new(player,bag)
    assert(not policy.inspect(foreign),'native food registration claimed an unrelated identical Wear')
    foodOwner.isCleanup=function()return true end
    assert(not policy.inspect(foreign),'replacement food predicate widened its captured native applicability')
    local complete=owned.complete;owned.complete=function()end
    assert(not policy.inspect(owned),'registered food cleanup accepted a changed native callback')
    owned.complete=complete
end
local equipmentTick=assert(tickCallbacks[#tickCallbacks-1],'native fitness storage cleanup did not register its window-independent callback')
local settlement=PZSurvivorToolkit.ActionQueueSettlement
local fitnessPrune=assert(tickCallbacks[#tickCallbacks],'fitness did not register explicit record pruning')
local fitnessMenuReset=assert(menuCallbacks[#menuCallbacks],'fitness did not register menu cleanup')
local function head()
    return f.action(ISReadABook,{item=item('BookCarpentry1')})
end
local function request(kind,minutes)
    local q=f.queue(head());local window=panel(kind or 'squats',minutes)
    window:onClick({internal='OK'})
    return assert(q.queue[2],'native fitness OK did not enqueue request'),q,window
end
local nativeStops=0
local function nativeAction()
    return {forceComplete=function()end,forceStop=function()nativeStops=nativeStops+1 end,setUseProgressBar=function()end,
        setActionAnim=function()end,setAnimVariable=function()end,setOverrideHandModels=function()end,
        isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
end
local function removeCurrent(q)
    table.remove(q.queue,1);q.current=q.queue[1]
end
local function runCurrent(q)
    local action=assert(q.queue[1]);q.current=action
    if fitnessQueue.canSkip(action)then removeCurrent(q);return action end
    if action.Type=='ISWearClothing'and fitnessQueue.isManaged(action)then
        local contract,adapter=policy.inspect(action)
        assert(contract and adapter=='toolkit.fitness','native food registration made managed Wear ownership ambiguous')
        assert(settlement.requiredStep(action),'managed Wear lost its exact earned cleanup prerequisite')
    end
    action.action=nativeAction()
    lifecycle.started(action)
    if client and fitnessQueue.isManaged(action) and action.Type~='ISInventoryTransferAction'
        and action.Type~='ISFitnessAction' and action.Type~='ISQueueActionsAction'then
        nextTransaction=nextTransaction+1
        action.toolkitNativeTransaction,action.toolkitNativeKind=nextTransaction,action.Type
        preparationReceipts[action]={state='completed',action=action}
    end
    if action.Type=='ISUnequipAction'then action:start()end
    if action.Type=='ISQueueActionsAction'then action:start()
    elseif action.Type=='ISWaitWhileGettingUp'then
        action:start()
        if player.sitting then
            assert(player.vars.forceGetUp==true,'native get-up action did not request standing')
            player.sitting=false
        end
        assert(action:complete())
    elseif action.Type=='ISInventoryTransferAction'then
        nextTransaction=nextTransaction+1;action.transactionId=nextTransaction;transactions[nextTransaction]='completed'
        repeat
            lifecycle.begin(action,'perform')
            action:checkQueueList()
            local group=table.remove(action.queueList,1)
            for _,member in ipairs(group.items)do
                action.item=member
                if action.srcContainer==floor then
                    for index,world in ipairs(worlds)do if world:getItem()==member then table.remove(worlds,index);break end end
                    member.world=nil
                end
                action.srcContainer:Remove(member);action.destContainer:AddItem(member)
            end
            if #action.queueList>0 then
                action.item=action.queueList[1].items[1]
                nextTransaction=nextTransaction+1;action.transactionId=nextTransaction;transactions[nextTransaction]='completed'
            else action.transactionId=0 end
            lifecycle.finish(action,'perform',true)
        until #action.queueList==0
    elseif action.Type=='ISDropWorldItemAction'then
        assert(action:isValid(),'native ground placement rejected fitness bag')
        lifecycle.begin(action,'perform')
        if not client then lifecycle.finish(action,'perform',true);lifecycle.begin(action,'complete')end
        assert(action:complete());getPlayerLoot(player:getPlayerNum()):refreshBackpacks()
        lifecycle.finish(action,client and 'perform' or 'complete',true)
    elseif action.Type=='ISFitnessAction'then action:start();return action
    else
        lifecycle.begin(action,'perform')
        if not client then lifecycle.finish(action,'perform',true);lifecycle.begin(action,'complete')end
        assert(action:complete()~=nil,'native equipment completion did not run')
        lifecycle.finish(action,client and 'perform' or 'complete',true)
    end
    assert(settlement.completionState(q,action)=='ready','native preparation/return proof did not settle: '..action.Type..':'..tostring(settlement.completionState(q,action)))
    lifecycle.reset(q) -- The fixture advances only after the modeled native removal.
    removeCurrent(q);return action
end
local function expand(requestAction,q)
    assert(q.queue[2]==requestAction);table.remove(q.queue,1);q.current=requestAction
    runCurrent(q)
end
local function reachExercise(q)
    for _=1,20 do
        local action=assert(q.queue[1],'fitness preparation produced no exercise')
        if action.Type=='ISFitnessAction'then return runCurrent(q)end
        runCurrent(q)
    end
    error('fitness preparation did not converge')
end
local function finish(q,action)
    assert(q.queue[1]==action);action:forceStop();removeCurrent(q)
    for _=1,20 do
        if not q.queue[1]then return end
        assert(q.queue[1].toolkitQueueOperation==action.toolkitQueueOperation,'fitness cleanup child lost same-operation ownership')
        runCurrent(q)
    end
    error('fitness cleanup did not converge')
end
local function reset()
    for _,callback in ipairs(menuCallbacks)do callback()end
    player.primary,player.secondary=nil,nil;player.worn={};player.inventory=container();player.vars={}
    enabled,client,receipt=true,false,nil
    currentExercise=nil
    preparationReceipts={}
    player.sitting=false
    worlds={};floor.items={};currentSquare=here
    frameClock.offset=0;frameClock.manual=false;frameClock.ms=0;frameClock.now=now;frameClock.id=frameClock.id+1
end

reset()
local beforeSpeed=fitnessSpeed
local pending,q,window=request('squats',10)
assert(fitnessQueue.isManaged(pending),'native fitness UI producer was not source verified')
assert(pending.Type=='ISQueueActionsAction' and not pending.action,'waiting fitness must remain a deferred request')
assert(currentExercise==nil and fitnessSpeed==beforeSpeed,'waiting request invoked native constructor side effects')
assert(window.currentExercice==nil and next(window.itemsToReequip)==nil,'window acquired ownership of managed cleanup')
local duration=fitnessQueue.describe(pending)
assert(duration and duration.signature=='fitness:squats' and not fitnessQueue.progress(pending),'pending duration contract missing')
now=now+900000
expand(pending,q)
local workout=reachExercise(q)
assert(workout.startMS==now and workout.endMS==now+600000,'workout duration counted time spent waiting')
assert(currentExercise=='squats' and workout.fitnessUI==nil,'native exercise must exist only after preparation and outlive UI')
now=now+150000
assert(fitnessQueue.progress(workout).elapsed==0,'reading progress earned an unobserved frame')
workout:update()
local progress=assert(fitnessQueue.progress(workout))
assert(math.abs(progress.elapsed-2.5)<.000001 and progress.total==10 and math.abs(progress.fraction-.25)<.000001,'fitness progress did not use elapsed game time')
now=workout.endMS+60000
assert(fitnessQueue.progress(workout).fraction==.25,'reading progress advanced the native frame accumulator')
workout:update()
assert(fitnessQueue.progress(workout).fraction==1,'elapsed progress overflowed planned duration')
local effects=repeats
finish(q,workout)
assert(repeats==effects and currentExercise==nil,'managed stop/cleanup replayed native exercise effects')
assert(nativeStops>0,'managed exercise did not use native forceStop')
for name,callback in pairs(nativeFitness)do assert(ISFitnessAction[name]==callback,'adapter replaced native effect callback '..name)end
print('PASS deferred fitness native constructor, elapsed progress and no effect replay')

do
 reset()
 local burpeesPending,burpeesQueue=request('burpees',30)
 local heading=fitnessQueue.describe(burpeesPending).title
 expand(burpeesPending,burpeesQueue)
 local preparation=fitnessQueue.describe(burpeesQueue.queue[1])
 assert(preparation.role=='preparation' and preparation.title~=heading and not preparation.target,
  'fitness preparation was labelled as another full workout')
 local burpees=reachExercise(burpeesQueue)
 local cleanup=assert(burpeesQueue.queue[2])
 assert(#burpeesQueue.queue==2 and burpees.Type=='ISFitnessAction' and cleanup.Type=='ISQueueActionsAction'
  and cleanup.toolkitFitnessStage=='cleanup' and cleanup.toolkitQueueOperation==burpees.toolkitQueueOperation,
  'one burpees workout must group only its exercise and deferred cleanup')
 local description=fitnessQueue.describe(cleanup)
 assert(description.role=='return' and description.title~=heading and not description.target
  and description.signature=='fitness:burpees','fitness cleanup was labelled as another full workout')
 assert(burpees.timeToExe==30 and fitnessQueue.progress(burpees).total==30,
  'stage presentation changed the selected workout duration')
 assert(PZSurvivorToolkit.ActionQueueDefinitions.taskTitle(burpeesQueue,1,2)==heading,
  'fitness stage presentation replaced the operation heading')
 finish(burpeesQueue,burpees)
 print('PASS single 30-minute burpees workout groups distinct preparation and restoration stages')
end

reset()
pending,q=request('squats',10)
window=panel('pushups',20);window:onClick({internal='OK'})
local second=assert(q.queue[3])
assert(pending.toolkitQueueOperation~=second.toolkitQueueOperation,'independent fitness requests shared operation token')
assert(not policy.cancelOperationReason(q,pending),'waiting fitness operation could not cancel')
assert(not policy.moveReason(q,second,pending),'independent waiting fitness operations could not reorder')
pending.toolkitFitnessMinutes=11
assert(not fitnessQueue.isManaged(pending),'modified captured duration retained managed permission')
pending.toolkitFitnessMinutes=10
assert(fitnessQueue.isManaged(pending),'restored captured duration lost permission')
local sourceAction=ISFitnessAction.update
ISFitnessAction.update=function()end
assert(not fitnessQueue.isManaged(second),'late native class replacement retained managed permission')
ISFitnessAction.update=sourceAction
local data=FitnessExercises.exercisesType.pushups
data.xpMod=2
assert(not fitnessQueue.isManaged(second),'modified native exercise data retained managed permission')
data.xpMod=1
assert(fitnessQueue.isManaged(second),'restored native source data did not recover proof')
print('PASS waiting fitness operation contracts and captured source guards')

reset()
local axe=item('Axe',nil,nil,true)
local backpack=item('Bag_BigHikingBag',nil,'BACK')
backpack.favorite=true
local packed=item('WaterBottle',backpack.inner)
local dumbbell=item('DumbBell',backpack.inner)
player.primary,player.secondary=axe,axe;player.worn.BACK=backpack
pending,q,window=request('bicepscurl',10)
assert(currentExercise==nil and dumbbell:getContainer()==backpack.inner and player.primary==axe,
    'waiting weighted exercise changed inventory or hands')
expand(pending,q)
local axeUnequips,bagUnequips=0,0
for _,action in ipairs(q.queue)do
    if action.Type=='ISUnequipAction'then
        local contract,adapter=policy.inspect(action)
        assert(contract and adapter=='native.ISUnequipAction','ordinary native unequip acquired an ambiguous Fitness contract')
    end
    if action.Type=='ISUnequipAction' and action.item==axe then axeUnequips=axeUnequips+1 end
    if action.Type=='ISUnequipAction' and action.item==backpack then bagUnequips=bagUnequips+1 end
end
assert(axeUnequips==1 and bagUnequips==1,'native fitness preparation duplicated two-handed unequip or omitted bag')
workout=reachExercise(q)
assert(player.primary==dumbbell and player.secondary==nil and not player.worn.BACK,'weighted native preparation did not equip exact prop/remove bag')
assert(dumbbell:getContainer()==player.inventory,'borrowed fitness prop was not transferred to root inventory')
assert(backpack:getWorldItem() and not player.inventory:contains(backpack,true),
    'exercise retained the unequipped bag in carried inventory instead of putting it on the ground')
assert(backpack:isFavorite() and packed:getContainer()==backpack.inner,'putting down storage changed its favourite flag or contents')
local token=workout.toolkitQueueOperation
local operation=assert(settlement.operationState(workout))
assert(#operation.borrowings==1 and operation.borrowings[1].id==dumbbell:getID() and operation.borrowings[1].state=='active',
    'shared proof did not earn exact borrowed-prop cleanup: '..#operation.borrowings..':'..tostring(operation.borrowings[1] and operation.borrowings[1].state))
local cleanupCommand=assert(q.queue[2])
assert(settlement.operationState(cleanupCommand),'fitness cleanup lacks shared phase proof')
assert(cleanupCommand.toolkitQueueOperation==token,'cleanup command lost originating operation')
finish(q,workout)
assert(player.primary==axe and player.secondary==axe,'original two-handed equipment was not restored exactly')
assert(player.worn.BACK==backpack,'removed worn bag was not restored')
assert(dumbbell:getContainer()==backpack.inner,'borrowed dumbbell was not returned to its original carried container')
assert(not backpack:getWorldItem() and #worlds==0 and backpack:isFavorite() and packed:getContainer()==backpack.inner,
    'pickup/restoration duplicated storage or lost its contents/favourite flag')
assert(window.currentExercice==nil and next(window.itemsToReequip)==nil,'closed-window-independent cleanup leaked back into native UI')
print('PASS native two-handed and worn-bag restoration with exact carried-container return')

reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');dumbbell=item('DumbBell',backpack.inner)
player.worn.BACK=backpack
pending,q=request('bicepscurl',10);expand(pending,q);workout=reachExercise(q)
assert(player.primary==dumbbell,'empty-hand exercise did not equip prop')
finish(q,workout)
assert(player.primary==nil and player.secondary==nil,'original empty hand slots were not restored')
assert(player.worn.BACK==backpack and dumbbell:getContainer()==backpack.inner,'empty-hand cleanup lost bag/prop')
print('PASS empty-hand restoration does not leave the exercise prop equipped')
reset()
dumbbell=item('DumbBell');player.primary=dumbbell
pending,q=request('bicepscurl',10);expand(pending,q);workout=reachExercise(q)
workout:forceStop();removeCurrent(q);runCurrent(q)
for _,action in ipairs(q.queue)do
    assert(action.Type~='ISUnequipAction','restoring an originally held prop added an extra paid unequip')
end
for _=1,10 do if not q.queue[1]then break end;runCurrent(q)end
assert(player.primary==dumbbell and player.secondary==nil,'originally held prop did not retain its exact slot')
print('PASS originally held fitness prop preserves native restoration action timing')


reset()
local back=item('Bag_BigHikingBag',nil,'BACK')
local pouch=item('Bag_FannyPackFront',nil,'FANNYPACK_FRONT')
local carriedBag=item('Bag_DuffelBag',nil,'SECONDARYBAG')
local spare=item('Bag_Satchel',nil,'SATCHEL')
local shirt=item('Tshirt')
player.worn.BACK,player.worn.FANNYPACK_FRONT,player.worn.SHIRT=back,pouch,shirt
player.primary,player.secondary=carriedBag,carriedBag
pending,q=request('squats',10);expand(pending,q)
local dropCount=0
for _,action in ipairs(q.queue)do if action.Type=='ISDropWorldItemAction'then dropCount=dropCount+1 end end
assert(dropCount==3,'worn/held storage must be put down exactly once, excluding spare inventory bags and clothing')
workout=reachExercise(q)
assert(#worlds==3 and not player.worn.BACK and not player.worn.FANNYPACK_FRONT and player.worn.SHIRT==shirt,
    'multiple storage slots were not grounded independently of ordinary clothing')
assert(spare:getContainer()==player.inventory,'exercise dropped an unequipped spare bag')
finish(q,workout)
assert(player.worn.BACK==back and player.worn.FANNYPACK_FRONT==pouch and player.worn.SHIRT==shirt,
    'storage restoration changed original worn slots or unrelated clothing')
assert(player.primary==carriedBag and player.secondary==carriedBag and #worlds==0,
    'two-handed bag was not recovered/re-equipped exactly once')
print('PASS all worn/held storage slots, two-handed deduplication and unrelated clothing/spare bags')

local function takeWorldItem(bag)
    for index,world in ipairs(worlds)do if world:getItem()==bag then table.remove(worlds,index);break end end
    bag.world=nil
    if bag.source then bag.source:Remove(bag)end
    local external=container();external:AddItem(bag)
end

reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');player.worn.BACK=backpack
pending,q=request('squats',10);expand(pending,q);workout=reachExercise(q)
takeWorldItem(backpack)
local lookalike=item('Bag_BigHikingBag',nil,'BACK');player.inventory:Remove(lookalike);here:AddWorldInventoryItem(lookalike)
finish(q,workout)
assert(not player.worn.BACK and lookalike:getWorldItem() and backpack:getContainer()~=player.inventory,
    'cleanup stole storage or substituted a same-type bag for the original ID')

reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');player.worn.BACK=backpack
pending,q=request('squats',10);expand(pending,q);workout=reachExercise(q)
currentSquare=setmetatable({x=20,y=20,z=0},{__index=here})
finish(q,workout)
assert(backpack:getWorldItem() and not player.worn.BACK,'cleanup teleported distant storage back into inventory')

reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');player.worn.BACK=backpack
pending,q=request('squats',10);expand(pending,q);workout=reachExercise(q)
local occupied=item('Bag_Satchel',nil,'BACK');player.worn.BACK=occupied
finish(q,workout)
assert(player.worn.BACK==occupied and backpack:getWorldItem(),'cleanup displaced a newly worn bag from an occupied slot')
print('PASS missing, distant and occupied-slot storage is left alone without same-type substitution')

reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');dumbbell=item('DumbBell',backpack.inner)
player.worn.BACK=backpack
pending,q=request('bicepscurl',10);expand(pending,q);workout=reachExercise(q)
local cleanupBinding=policy.matchesCleanupPickupBinding
local nativeEnqueue=ISTimedActionQueue.add
local rejectedPickups,rejectedPropReturns=0,0
policy.matchesCleanupPickupBinding=function()return false end
ISTimedActionQueue.add=function(action)
    if action.Type=='ISInventoryTransferAction'then
        if action.srcContainer==floor then rejectedPickups=rejectedPickups+1 end
        if action.item==dumbbell and action.destContainer~=player.inventory then rejectedPropReturns=rejectedPropReturns+1 end
    end
    return nativeEnqueue(action)
end
finish(q,workout)
ISTimedActionQueue.add=nativeEnqueue
policy.matchesCleanupPickupBinding=cleanupBinding
assert(rejectedPickups==0 and rejectedPropReturns==0,
    'rejected cleanup binding enqueued an unproved pickup or invented prop return')
assert(backpack:getWorldItem() and #worlds==1 and not player.inventory:contains(backpack,true) and not player.worn.BACK,
    'rejected cleanup binding recovered or re-equipped the dropped bag without proof')
assert(dumbbell:getContainer()==player.inventory and not player.primary and not player.secondary,
    'rejected bag pickup invented equipment restoration or returned the prop to an absent carrier')
print('PASS rejected cleanup binding leaves exact grounded storage without unproved pickup or prop return')


reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');dumbbell=item('DumbBell',backpack.inner)
player.worn.BACK=backpack
pending,q=request('bicepscurl',10);expand(pending,q);workout=reachExercise(q)
local replica=item('Bag_BigHikingBag',nil,'BACK');player.inventory:Remove(replica)
replica.id=backpack.id;replica.favorite=backpack.favorite
replica.inner=container(replica)
local world=assert(backpack.world);world.getItem=function()return replica end
replica.world=world;backpack.world=nil
finish(q,workout)
assert(player.worn.BACK==replica and dumbbell:getContainer()==replica.inner,
    'Host-style fresh bag replica did not restore by ID or resolve the borrowed-prop destination anew')
print('PASS fresh Host storage replica is resolved by ID before re-equipping and returning the prop')

reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');player.worn.BACK=backpack
pending,q=request('squats',10);expand(pending,q)
while q.queue[1] and q.queue[1].Type~='ISDropWorldItemAction'do runCurrent(q)end
local pendingDrop=assert(q.queue[1])
backpack.weight=60
assert(fitnessQueue.canSkip(pendingDrop),'new ground-capacity failure did not skip unsafe placement')
for _=1,20 do if not q.queue[1]then break end;runCurrent(q)end
assert(currentExercise==nil and player.worn.BACK==backpack and not backpack:getWorldItem(),
    'failed ground placement started an overloaded workout or lost equipment cleanup')
print('PASS failed ground placement skips the workout and restores carried storage')

reset()
local torch=item('HandTorch')
torch.canBeActivated=function()return true end
player.primary=torch
pending,q=request('squats',10);expand(pending,q);workout=reachExercise(q)
finish(q,workout)
assert(player.primary==torch and not torch:isActivated(),'native restore autoactivation overwrote captured off state')
print('PASS native activation cleanup restores captured hand-item state')
reset()
torch=item('HandTorch');torch.canBeActivated=function()return true end;torch.active=true;player.primary=torch
pending,q=request('squats',10);expand(pending,q);workout=reachExercise(q)
assert(not torch:isActivated(),'native preparation did not deactivate the initially active hand torch')
finish(q,workout)
assert(player.primary==torch and torch:isActivated(),'earned hand removal lost captured on-state restoration')
print('PASS native started deactivation restores the captured on-state after earned unequip')

reset()
local original=item('DumbBell')
pending,q=request('bicepscurl',10)
player.inventory:Remove(original)
local replacement=item('DumbBell')
window=panel('squats',10);window:onClick({internal='OK'})
local independent=q.queue[3]
expand(pending,q)
assert(q.queue[1]==independent and currentExercise==nil,'missing exact prop cleared independent tail or substituted same-type item')
assert(replacement:getContainer()==player.inventory,'missing prop fallback moved an unrelated replacement')

reset()
original=item('DumbBell')
pending,q=request('bicepscurl',10);expand(pending,q)
local equip
for _,action in ipairs(q.queue)do if action.Type=='ISEquipWeaponAction'then equip=action end end
assert(equip and fitnessQueue.isManaged(equip),'fitness preparation item contract missing')
local beforeID=original.id;original.id=beforeID+100000
assert(not fitnessQueue.isManaged(equip),'changed item ID retained managed native child permission')
original.id=beforeID
local beforeKind=original.kind;original.kind='BarBell'
assert(not fitnessQueue.isManaged(equip),'changed full item type retained managed child permission')
original.kind=beforeKind
player.inventory:Remove(original)
assert(fitnessQueue.canSkip(equip),'missing exact preparation item could invalidate native independent tail')
q.queue={head(),equip};q.current=q.queue[1]
fitnessQueue.skipUnavailable(q)
assert(#q.queue==1,'missing preparation child was not skipped before native validation')
print('PASS exact item identity and unavailable preparation preserve unrelated work')

reset()
pending,q=request('squats',10)
player.sitting=true
expand(pending,q)
assert(q.queue[1] and q.queue[1].Type=='ISWaitWhileGettingUp','deferred fitness omitted native get-up after earlier queue work sat down')
assert(currentExercise==nil,'fitness constructor ran before queued player stood up')
workout=reachExercise(q)
assert(not player.sitting and player.vars.forceGetUp==true,'queued fitness did not execute native get-up before exercise')
finish(q,workout)
print('PASS deferred fitness gets up from a queued sitting state before exercising')

reset()
pending,q=request('squats',10);expand(pending,q)
for _=1,10 do if q.queue[1].Type=='ISFitnessAction'then break end;runCurrent(q)end
local neverStarted=assert(q.queue[1])
assert(neverStarted.Type=='ISFitnessAction' and not neverStarted.action and currentExercise=='squats',
    'fixture did not reach native constructed/never-started workout')
assert(fitness:getCurrentExe()==exerciseStates.squats and type(fitness:getCurrentExe())=='table',
    'native fitness fixture must expose stable exercise objects instead of names')
local oldVehicle=player.getVehicle;player.getVehicle=function()return {}end
assert(fitnessQueue.canSkip(neverStarted),'unavailable never-started workout cannot be skipped')
neverStarted:forceCancel()
assert(currentExercise==nil,'discarded never-started workout left constructor currentExercise state behind')
assert(repeats==effects,'never-started discard replayed authoritative exercise effects')
player.getVehicle=oldVehicle

reset()
pending,q=request('squats',10);expand(pending,q)
for _=1,10 do if q.queue[1].Type=='ISFitnessAction'then break end;runCurrent(q)end
neverStarted=assert(q.queue[1])
assert(neverStarted.Type=='ISFitnessAction' and not neverStarted.action,'fixture did not construct second unstarted workout')
fitness:setCurrentExercise('pushups')
local unrelatedExercise=fitness:getCurrentExe()
neverStarted:forceCancel()
assert(fitness:getCurrentExe()==unrelatedExercise and currentExercise=='pushups',
    'discarding unstarted workout cleared a different native exercise object')
print('PASS discarded native constructed workout clears only its unstarted exercise state')

-- Exercise the actual core cancellation/cleanup branches with deterministic final advancement.
-- Native Java removal and the Host receipt gate are checked separately from this Lua branch.
local coreSource=read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua')
local coreFrom=assert(coreSource:find('function Queue.cancelOperation',1,true))
local coreTo=assert(coreSource:find('function Queue.move',coreFrom,true))
local coreChunk=coreSource:sub(coreFrom,coreTo-1):gsub('local completed = ISTimedActionQueue.onCompleted',
    'local completed = function(queue,action) queue:removeFromQueue(action);queue.current=queue.queue[1] end',1)
local nativeCompleted=ISTimedActionQueue.onCompleted
local core=assert(loadstring('local Queue,Toolkit,Policy,Operations,Settlement = ...\n'..
    'local craft,live,stoppable=Policy.isCraftAction,Policy.live,Policy.stoppable\n'..
    'local Batch,processPriority,returnMarker=nil,nil,{}\n'..coreChunk..'\nreturn Queue',
    '@PZSurvivorToolkit/ActionQueue.lua'))({},PZSurvivorToolkit,policy,PZSurvivorToolkit.ActionQueueOperations,
        PZSurvivorToolkit.ActionQueueSettlement)
ISInventoryPaneContextMenu.getContainers=function()return list({})end
-- Expanding preparation captures intent, but a completed get-up earns no restoration.
reset()
axe=item('Axe',nil,nil,true);backpack=item('Bag_BigHikingBag',nil,'BACK');dumbbell=item('DumbBell',backpack.inner)
player.primary,player.secondary=axe,axe;player.worn.BACK=backpack;player.sitting=true
pending,q=request('bicepscurl',10);expand(pending,q)
local gettingUp=assert(q.queue[1]);local untouchedTail=head();ISTimedActionQueue.add(untouchedTail)
assert(gettingUp.Type=='ISWaitWhileGettingUp','fixture lacks unearned native preparation')
gettingUp.action=nativeAction();lifecycle.started(gettingUp)
assert(core.cancelOperation(q,gettingUp),'core rejected get-up preparation cancellation')
player.sitting=false;assert(gettingUp:complete());q:onCompleted(gettingUp)
assert(#q.queue==1 and q.queue[1]==untouchedTail,'snapshot-only preparation retained unearned equipment cleanup')
assert(player.primary==axe and player.secondary==axe and player.worn.BACK==backpack and dumbbell:getContainer()==backpack.inner,
    'unearned preparation changed equipment or borrowed a prop')

-- Only the first completed two-handed unequip may authorize restoration.
reset()
axe=item('Axe',nil,nil,true);backpack=item('Bag_BigHikingBag',nil,'BACK');dumbbell=item('DumbBell',backpack.inner)
player.primary,player.secondary=axe,axe;player.worn.BACK=backpack
pending,q=request('squats',10);expand(pending,q)
local firstUnequip=assert(q.queue[1]);local partialTail=head();ISTimedActionQueue.add(partialTail)
assert(firstUnequip.Type=='ISUnequipAction' and firstUnequip.item==axe,'fixture lacks first native hand unequip')
firstUnequip.action=nativeAction();lifecycle.started(firstUnequip)
assert(core.cancelOperation(q,firstUnequip),'core rejected finish-step hand cancellation')
lifecycle.begin(firstUnequip,'perform');lifecycle.finish(firstUnequip,'perform',true)
lifecycle.begin(firstUnequip,'complete');assert(firstUnequip:complete());lifecycle.finish(firstUnequip,'complete',true)
lifecycle.reset(q)
q:onCompleted(firstUnequip)
assert(#q.queue==2 and settlement.requiredStep(q.queue[1]),'earned hand removal lost cleanup or synthesized unearned return')
local partialWear,partialReturn=0,0
for _=1,20 do
    if q.queue[1]==partialTail then break end
    local current=q.queue[1]
    if current.Type=='ISWearClothing'then partialWear=partialWear+1 end
    if current.Type=='ISInventoryTransferAction'then partialReturn=partialReturn+1 end
    runCurrent(q)
end
assert(q.queue[1]==partialTail and currentExercise==nil and partialWear==0 and partialReturn==0,
    'partial preparation restored an untouched bag, borrowed prop or started workout')
assert(player.primary==axe and player.secondary==axe and player.worn.BACK==backpack and dumbbell:getContainer()==backpack.inner,
    'earned two-handed removal did not restore exact equipment')
print('PASS shared fitness cleanup requires exact earned preparation effects')

reset()
axe=item('Axe',nil,nil,true);backpack=item('Bag_BigHikingBag',nil,'BACK');dumbbell=item('DumbBell',backpack.inner)
player.primary,player.secondary=axe,axe;player.worn.BACK=backpack
pending,q=request('bicepscurl',10);expand(pending,q);workout=reachExercise(q)
local tail=head();ISTimedActionQueue.add(tail)
assert(core.cancelOperation(q,workout),'core rejected active whole-fitness cancellation')
assert(q.toolkitGroupCancel and q.toolkitCancel==workout,'core did not request native cancellation for active fitness')
q:onCompleted(workout)
assert(q.queue[1] and settlement.requiredStep(q.queue[1]),'core group cancel dropped required cleanup command')
assert(q.queue[#q.queue]==tail,'core group cancel discarded unrelated independent tail')
assert(#q.queue==2,'core must defer the prop return until its grounded carrier has been recovered')
fitnessPrune()
assert(not fitnessQueue.isManaged(workout),'removed canceled exercise retained a managed record')
assert(fitnessQueue.isManaged(q.queue[1]) and settlement.requiredStep(q.queue[1]),
    'pruning canceled operation discarded its retained cleanup proof')
for _=1,20 do if q.queue[1]==tail then break end;runCurrent(q)end
assert(q.queue[1]==tail,'retained fitness cleanup did not finish before unrelated tail')
assert(player.primary==axe and player.secondary==axe and player.worn.BACK==backpack,
    'active fitness cancellation did not restore original equipment')
assert(dumbbell:getContainer()==backpack.inner,'active fitness cancellation lost exact borrowed-prop return')
local returnCount=0
for _,action in ipairs(q.queue)do if action.Type=='ISInventoryTransferAction' and action.item==dumbbell then returnCount=returnCount+1 end end
assert(returnCount==0,'generic core return duplicated fitness-owned pickup cleanup')

reset()
axe=item('Axe',nil,nil,true);backpack=item('Bag_BigHikingBag',nil,'BACK');dumbbell=item('DumbBell',backpack.inner)
player.primary,player.secondary=axe,axe;player.worn.BACK=backpack
pending,q=request('bicepscurl',10);expand(pending,q)
for _=1,10 do if q.queue[1].Type=='ISInventoryTransferAction'then break end;runCurrent(q)end
local transferPreparation=assert(q.queue[1])
assert(transferPreparation.Type=='ISInventoryTransferAction' and currentExercise==nil,'fixture did not reach in-flight pickup before native fitness constructor')
transferPreparation.action=nativeAction();q.current=transferPreparation
    lifecycle.started(transferPreparation)
    nextTransaction=nextTransaction+1;transferPreparation.transactionId=nextTransaction;transactions[nextTransaction]='completed'
    lifecycle.begin(transferPreparation,'perform')
    transferPreparation:checkQueueList()
tail=head();ISTimedActionQueue.add(tail)
assert(core.cancelOperation(q,transferPreparation),'core rejected cancellation while native fitness pickup was in flight')
assert(q.toolkitGroupCancel and not q.toolkitCancel,'in-flight native pickup was interrupted rather than allowed to settle')
transferPreparation.srcContainer:Remove(dumbbell);transferPreparation.destContainer:AddItem(dumbbell)
table.remove(transferPreparation.queueList,1);lifecycle.finish(transferPreparation,'perform',true)
lifecycle.reset(q)
q:onCompleted(transferPreparation)
assert(#q.queue==3 and settlement.requiredStep(q.queue[1]),'in-flight pickup cancellation lost shared return or equipment cleanup')
for _=1,20 do if q.queue[1]==tail then break end;runCurrent(q)end
assert(q.queue[1]==tail and currentExercise==nil,'preparation cancellation constructed workout or discarded independent tail')
assert(player.primary==axe and player.secondary==axe and player.worn.BACK==backpack and dumbbell:getContainer()==backpack.inner,
    'canceled in-flight pickup did not restore hands/bag and return borrowed prop')
print('PASS core active fitness/pickup cancellation retains cleanup and independent tail')

reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');player.worn.BACK=backpack
pending,q=request('squats',10);expand(pending,q)
while q.queue[1] and q.queue[1].Type~='ISDropWorldItemAction'do runCurrent(q)end
local dropping=assert(q.queue[1]);dropping.action=nativeAction();q.current=dropping
tail=head();ISTimedActionQueue.add(tail)
assert(core.cancelOperation(q,dropping),'core rejected cancellation during storage placement')
assert(q.toolkitGroupCancel and not q.toolkitCancel,'native storage placement was interrupted instead of allowed to settle')
lifecycle.started(dropping)
lifecycle.begin(dropping,'perform');lifecycle.finish(dropping,'perform',true)
lifecycle.begin(dropping,'complete');assert(dropping:complete())
getPlayerLoot(player:getPlayerNum()):refreshBackpacks();lifecycle.finish(dropping,'complete',true)
lifecycle.reset(q);q:onCompleted(dropping)
assert(q.queue[1] and settlement.requiredStep(q.queue[1]),'placement cancellation discarded required recovery')
for _=1,20 do if q.queue[1]==tail then break end;runCurrent(q)end
assert(q.queue[1]==tail and currentExercise==nil and player.worn.BACK==backpack and #worlds==0,
    'cancelled in-flight ground placement lost storage, began exercising or discarded the independent tail')

reset()
backpack=item('Bag_BigHikingBag',nil,'BACK');player.worn.BACK=backpack
pending,q=request('squats',10);expand(pending,q);workout=reachExercise(q)
workout:forceStop();removeCurrent(q);runCurrent(q)
local pickup=assert(q.queue[1]);assert(pickup.Type=='ISInventoryTransferAction','cleanup did not schedule storage pickup')
assert(settlement.requiredStep(pickup),'storage pickup did not inherit its earned recovery obligation')
takeWorldItem(backpack)
assert(fitnessQueue.canSkip(pickup),'bag taken after pickup scheduling did not skip the stale pickup')
for _=1,20 do if not q.queue[1]then break end;runCurrent(q)end
assert(not player.worn.BACK and backpack:getContainer()~=player.inventory,'stale cleanup stole the bag back')
print('PASS in-flight placement cancellation and storage taken between pickup planning and execution')
local coreCompleted=ISTimedActionQueue.onCompleted
ISTimedActionQueue.onCompleted=nativeCompleted

reset();client=true;now=3600000
pending,q=request('burpees',30);expand(pending,q);workout=reachExercise(q)
local stopsBefore=nativeStops
assert(not fitnessQueue.canPreserveStop(workout) and not q.toolkitCancel,'Host stop preserved queue without authoritative started receipt')
local noReceiptContract=assert(policy.inspect(workout))
assert(noReceiptContract.interrupt=='finish-step' and noReceiptContract.cancelOperation==false,
    'Host operation allowed managed interruption before server start was acknowledged')
now=workout.endMS-1
workout:update()
assert(nativeStops==stopsBefore and currentExercise~=nil,'Host workout stopped before its selected duration')
now=workout.endMS
workout:update()
assert(nativeStops==stopsBefore+1 and currentExercise==nil,'Host workout waited an extra calendar minute at its exact deadline')
assert(player.vars.ExerciseStarted==false and player.vars.ExerciseEnded==true,'expired workout did not use native animation ending')
local waiting=assert(q.toolkitOutcomeWait)
assert(q.toolkitCancel==workout and waiting.pendingStart and waiting.generic,'missing started receipt did not hold continuation')
assert(waiting.pendingStart.native==workout.action and waiting.deadline==now+30000,'pending receipt wait lacks native identity or bounded deadline')
local ending=assert(fitnessQueue.progress(workout))
assert(ending.fraction==1 and ending.stopping and fitnessQueue.describe(workout).target=='UI_PZSurvivorToolkit_queue_fitness_stopping',
    'server stop wait still looks like a running 100 percent workout')
local deadline=waiting.deadline
now=now+1000;workout:forceStop()
assert(q.toolkitOutcomeWait==waiting and waiting.deadline==deadline,'repeated native stop extended authoritative deadline')
assert(repeats==effects,'Host stop replayed authoritative exercise effects')
fitnessPrune()
assert(fitnessQueue.isManaged(workout) and fitnessQueue.isManaged(q.queue[2]),
    'queued receipt-waiting exercise or required cleanup lost its record')

reset();client=true
pending,q=request('squats',10);expand(pending,q);workout=reachExercise(q)
receipt={state='started',token='fixture-receipt'}
stopsBefore=nativeStops;workout:forceStop()
assert(nativeStops==stopsBefore+1,'acknowledged Host stop bypassed native forceStop')
assert(q.toolkitCancel==workout and q.toolkitOutcomeWait.acknowledgement==receipt
    and not q.toolkitOutcomeWait.pendingStart,'acknowledged Host fitness stop lost existing receipt gate')
print('PASS Host fitness stops immediately, holds late receipts and shows server settlement separately')

for _,network in ipairs({false,true})do
 for _,boundary in ipairs({'exact','later','movement'})do
  reset();client=network;now=3600000
  pending,q=request('burpees',30);expand(pending,q);workout=reachExercise(q)
  local beforeStops,beforeEffects=nativeStops,repeats
  local movement=player.pressedMovement
  if boundary=='movement'then player.pressedMovement=function()return true end end
  now=workout.endMS+(boundary=='later'and 60000 or 0)
  workout:update();player.pressedMovement=movement
  assert(nativeStops==beforeStops+1 and currentExercise==nil,
   'fitness deadline supplement duplicated or missed the native stop: '..boundary)
  assert(repeats==beforeEffects,'fitness deadline supplement replayed exercise effects')
 end
end
print('PASS exact calendar deadline, later native deadline and movement stop once in SP and Host')

for _,network in ipairs({false,true})do
 reset();client=network;now=3630000;quantizedCalendar=true
 pending,q=request('burpees',30);expand(pending,q);workout=reachExercise(q)
 local beforeStops=nativeStops;local preciseStart=fitnessQueue.progress(workout).startMS
 now=workout.endMS;workout:update()
 assert(nativeStops==beforeStops and currentExercise~=nil,'whole-minute calendar shortened the workout')
 if not network then assert(fitnessQueue.progress(workout).fraction<1,'bar reached 100 percent before the full continuous duration')end
 now=preciseStart+1800000-1;workout:update()
 assert(nativeStops==beforeStops,'continuous workout stopped before selected duration')
 now=preciseStart+1800000+.01;workout:update()
 assert(nativeStops==beforeStops+1 and fitnessQueue.progress(workout).fraction==1,'continuous deadline waited another calendar minute')
 quantizedCalendar=false
end
reset();client=true;now=3600000;quantizedCalendar=true
pending,q=request('burpees',30);expand(pending,q);workout=reachExercise(q)
assert(fitnessQueue.progress(workout).elapsed==0 and not fitnessQueue.progress(workout).confirmed)
now=now+15000;receipt={state='started',token='confirmed-clock-origin'};workout:update()
local confirmedStart=fitnessQueue.progress(workout).startMS
assert(fitnessQueue.progress(workout).confirmed and fitnessQueue.progress(workout).elapsed==0)
now=now+60000;workout:update()
assert(fitnessQueue.progress(workout).startMS==confirmedStart,'repeated receipt observation extended workout')
stopsBefore=nativeStops;now=confirmedStart+1800000-1;workout:update()
assert(nativeStops==stopsBefore,'client start counted time before the confirmed server start')
now=confirmedStart+1800000+.01;workout:update()
assert(nativeStops==stopsBefore+1,'confirmed workout missed its continuous deadline')
quantizedCalendar=false
print('PASS continuous fractional-minute duration and once-only confirmed Host clock origin')

reset();now=3600000
pending,q=request('burpees',30);expand(pending,q);workout=reachExercise(q)
stopsBefore=nativeStops;local savedDeadline=workout.endMS
calendarOffset=2400000;now=now+60000;workout:update();calendarOffset=0
assert(nativeStops==stopsBefore and workout.endMS==savedDeadline,'stale native calendar preempted continuous workout')
now=fitnessQueue.progress(workout).endMS+.01;workout:update()
local stopped=fitnessQueue.progress(workout)
assert(stopped.stopMS>=stopped.endMS and stopped.stopTimestampMS==now,'actual native stop lacks full continuous duration')
now=now+1000;workout:forceStop()
assert(fitnessQueue.progress(workout).stopMS==stopped.stopMS,'repeated stop changed first stop witness')
reset();now=3600000
pending,q=request('burpees',30);expand(pending,q);workout=reachExercise(q)
savedDeadline=workout.endMS
local metabolic=player.setMetabolicTarget
player.setMetabolicTarget=function()error('native update fixture failure')end
local ok,failure=pcall(workout.update,workout);player.setMetabolicTarget=metabolic
assert(not ok and tostring(failure):find('native update fixture failure',1,true) and workout.endMS==savedDeadline,
 'native update failure lost original error or leaked temporary deadline')
print('PASS native checks retain their deadline and errors while continuous time owns completion')

reset();client=true;receipt={state='started',token='storage-fixture-receipt'}
backpack=item('Bag_BigHikingBag',nil,'BACK');backpack.favorite=true
dumbbell=item('DumbBell',backpack.inner);player.worn.BACK=backpack
pending,q=request('bicepscurl',10);expand(pending,q);workout=reachExercise(q)
assert(backpack:getWorldItem() and dumbbell:getContainer()==player.inventory,
    'client-branch preparation retained carried storage or failed to fetch the prop first')
finish(q,workout)
assert(player.worn.BACK==backpack and dumbbell:getContainer()==backpack.inner and backpack:isFavorite() and #worlds==0,
    'client-branch storage cleanup lost native item IDs, contents or the favourite flag')
print('PASS simulated client placement/pickup branches retain exact storage and borrowed-prop cleanup')

reset()
pending,q=request('squats',10)
fitnessPrune()
assert(fitnessQueue.isManaged(pending),'pruning discarded a queued deferred request')
table.remove(q.queue,2)
fitnessPrune()
assert(not fitnessQueue.isManaged(pending),'removed deferred request retained a managed record')
pending,q=request('squats',10)
ISTimedActionQueue.queues[player]=nil
fitnessPrune()
assert(not fitnessQueue.isManaged(pending),'removed player queue retained its fitness record')
pending,q=request('squats',10);expand(pending,q);workout=reachExercise(q)
local oldQueue=q
f.queue(head())
fitnessPrune()
assert(oldQueue.current==workout and not fitnessQueue.isManaged(workout),
    'old queue current action retained a proof after registry replacement')
pending,q=request('squats',10)
fitnessMenuReset()
assert(not fitnessQueue.isManaged(pending),'main menu retained old fitness records')
pending,q=request('squats',10)
assert(fitnessQueue.isManaged(pending),'main menu reset prevented subsequent fitness records')
print('PASS explicit fitness record pruning preserves queued work and releases removed/menu records')

do
    fitnessMenuReset();reset()
    q=f.queue(head())
    local tracked={}
    for i=1,64 do
        panel('squats',10):onClick({internal='OK'})
        tracked[i]=assert(q.queue[i+1])
    end
    local unrelatedOwner={}
    local unrelated={queue={head()}}
    ISTimedActionQueue.queues[unrelatedOwner]=unrelated
    local scans,visits,foreignScans=0,0,0
    local nativeIpairs,nativeNext=ipairs,next
    ipairs=function(values)
        local iterator,state,index=nativeIpairs(values)
        if values==unrelated.queue then foreignScans=foreignScans+1 end
        if values~=q.queue then return iterator,state,index end
        scans=scans+1
        return function(...)
            local key,value=iterator(...)
            if key then visits=visits+1 end
            return key,value
        end,state,index
    end
    next=nil -- Kahlua has no next global.
    fitnessPrune()
    next,ipairs=nativeNext,nativeIpairs
    assert(scans==1 and visits==#q.queue and foreignScans==0,
        'fitness pruning must visit its live queue once and skip unrelated player queues')
    for _,action in ipairs(tracked) do assert(fitnessQueue.isManaged(action),'linear pruning lost queued fitness ownership') end
    tracked[1].character=unrelatedOwner
    fitnessPrune();tracked[1].character=player
    assert(fitnessQueue.isManaged(tracked[1]),'fitness pruning must resolve the captured player queue')
    local oldQueue=q
    q=f.queue(head(),tracked[1]);fitnessPrune()
    assert(oldQueue.queue[2]==tracked[1] and fitnessQueue.isManaged(tracked[1]) and not fitnessQueue.isManaged(tracked[2]),
        'queue replacement must retain only fitness actions in the current registered queue')
    table.remove(q.queue,2);fitnessPrune()
    assert(not fitnessQueue.isManaged(tracked[1]),'completed fitness request retained ownership after the next tick')
    scans=0;ipairs=function(values)
        if values==q.queue then scans=scans+1 end
        return nativeIpairs(values)
    end
    fitnessPrune();ipairs=nativeIpairs
    assert(scans==0,'empty fitness registry must not scan the queue')
    local single
    single,q=request('squats',10);table.remove(q.queue,1);q.current=single
    local tail=head()
    for i=1,4096 do q.queue[#q.queue+1]=tail end
    local function checkPrefix(expected)
        scans,visits=0,0
        ipairs=function(values)
            local iterator,state,index=nativeIpairs(values)
            if values~=q.queue then return iterator,state,index end
            scans=scans+1
            return function(...)
                local key,value=iterator(...)
                if key then visits=visits+1 end
                return key,value
            end,state,index
        end
        fitnessPrune();ipairs=nativeIpairs
        assert(scans==1 and visits==expected,'fitness pruning must stop at the last sought member')
    end
    checkPrefix(1);assert(fitnessQueue.isManaged(single),'tracked current fitness action lost ownership')
    panel('squats',10):onClick({internal='OK'})
    local second=table.remove(q.queue);table.insert(q.queue,2,second);checkPrefix(2)
    assert(fitnessQueue.isManaged(single) and fitnessQueue.isManaged(second),'tracked fitness prefix lost ownership')
    panel('squats',10):onClick({internal='OK'})
    local missing=table.remove(q.queue)
    checkPrefix(#q.queue)
    assert(not fitnessQueue.isManaged(missing) and fitnessQueue.isManaged(second),
        'missing fitness member needs a full scan and must not remove a live member')
    ISTimedActionQueue.queues[unrelatedOwner]=nil
    print('PASS fitness pruning has one linear queue pass and no empty-registry scans')
end

reset();enabled=false
q=f.queue(head());window=panel('squats',10)
window:onClick({internal='OK'})
local nativeWait=assert(q.queue[2])
assert(nativeWait.Type=='ISWaitWhileGettingUp' and not fitnessQueue.isManaged(nativeWait),'disabled feature replaced native UI queue')
local nativeWorkout=assert(nativeWait.onCompleteArgs.p1)
assert(nativeWorkout.Type=='ISFitnessAction' and nativeWorkout.fitnessUI==window and currentExercise=='squats',
    'disabled fitness no longer uses the original immediate constructor/UI callback')
assert(window.currentExercice=='squats','disabled native UI restoration state was intercepted')
enabled=true
print('PASS disabled fitness uses the unchanged native UI producer')
reset()
local transferObservation=PZSurvivorToolkit.ActionQueueTidyIntent.observeTransfers
PZSurvivorToolkit.ActionQueueTidyIntent.observeTransfers=function()end
q=f.queue(head());window=panel('squats',10);window:onClick({internal='OK'})
assert(q.queue[2].Type=='ISWaitWhileGettingUp' and not fitnessQueue.isManaged(q.queue[2]),
    'changed shared observer acquired managed preparation permissions')
PZSurvivorToolkit.ActionQueueTidyIntent.observeTransfers=transferObservation
print('PASS changed shared observation falls back to the original native UI producer')


reset();enabled=false
backpack=item('Bag_BigHikingBag',nil,'BACK');backpack.favorite=true
packed=item('WaterBottle',backpack.inner);player.worn.BACK=backpack
q=f.queue(head());window=panel('squats',10)
assert(window:equipItems(),'native preparation with queue edits off rejected storage')
local preparationCount=#q.queue
assert(not window:equipItems() and #q.queue==preparationCount,'repeated native preparation queued duplicate storage placement')
window.currentExercice='squats';fitness:setCurrentExercise('squats')
removeCurrent(q)
for _=1,20 do if not q.queue[1]then break end;runCurrent(q)end
assert(not player.worn.BACK and backpack:getWorldItem() and not player.inventory:contains(backpack,true),
    'native queue-disabled preparation left storage in carried inventory')
q.queue[1]=head();q.current=q.queue[1];fitness:setCurrentExercise(nil)
equipmentTick() -- No window update: this also covers closing the fitness window.
local restorationCount=#q.queue
equipmentTick();window:update()
assert(#q.queue==restorationCount,'native cleanup tick and window update scheduled duplicate pickups')
removeCurrent(q)
for _=1,20 do if not q.queue[1]then break end;runCurrent(q)end
assert(player.worn.BACK==backpack and backpack:isFavorite() and packed:getContainer()==backpack.inner and #worlds==0,
    'native queue-disabled/window-closed cleanup did not preserve storage identity, contents and favourite flag')

reset();enabled=false
backpack=item('Bag_BigHikingBag',nil,'BACK');player.worn.BACK=backpack
q=f.queue(head());window=panel('squats',10);assert(window:equipItems())
window.currentExercice='squats';fitness:setCurrentExercise('squats');removeCurrent(q)
for _=1,20 do if not q.queue[1]then break end;runCurrent(q)end
currentSquare=setmetatable({x=20,y=20,z=0},{__index=here})
q.queue[1]=head();q.current=q.queue[1];fitness:setCurrentExercise(nil);equipmentTick();removeCurrent(q)
for _=1,20 do if not q.queue[1]then break end;runCurrent(q)end
assert(backpack:getWorldItem() and not player.worn.BACK,'native queue-disabled cleanup teleported distant storage')

reset();enabled=false
backpack=item('Bag_BigHikingBag',nil,'BACK');backpack.weight=60;player.worn.BACK=backpack
q=f.queue(head());window=panel('squats',10)
window:onClick({internal='OK'})
assert(#q.queue==1 and currentExercise==nil and player.worn.BACK==backpack,
    'native preflight floor-capacity failure unequipped storage or constructed a workout')
enabled=true
print('PASS native queue-disabled ground storage, closed-window restoration, distance guards and placement preflight')

-- The source-pinned native producer must restore only the exact prop it really
-- fetched, even when Host replaces the placed carrier's Java replica.
for _,mode in ipairs({'sp','host-replica','host-prop-replica','host-wrong-member','held-bag','empty-hands','rejected','no-effect','missing-bag','same-type-bag','moved-prop','generation','cleanup-generation','changed-callback','full-bag','tampered-snapshot','replayed-command','foreign-actor','copied-snapshot','dead-before-return'})do
 reset();enabled=false;client=mode~='sp'
 local bag=item('Bag_Schoolbag',nil,'BACK');bag.favorite=true;player.worn.BACK=bag
 local prop=item('DumbBell',bag.inner);prop.favorite=true
 local other=item('DumbBell',bag.inner)
 local originalSecondary=item('Screwdriver');player.secondary=originalSecondary;player.primary=item('Hammer')
 if mode=='held-bag'then player.worn.BACK=nil;player.primary=bag end
 if mode=='empty-hands'then player.primary,player.secondary=nil,nil end
 local handPackets=0;local updateHands=player.updateHandEquips
 player.updateHandEquips=function()handPackets=handPackets+1 end
 q=f.queue(head());window=panel('bicepscurl',10)
 assert(window:equipItems())
 assert(handPackets==(client and mode~='empty-hands'and 1 or 0) and not player.secondary,'native immediate secondary clear was not synchronized exactly once')
 player.updateHandEquips=updateHands
 window.currentExercice='bicepscurl';fitness:setCurrentExercise('bicepscurl');removeCurrent(q)
 local pickup=assert(q.queue[1]);assert(pickup.Type=='ISInventoryTransferAction' and pickup.item==prop)
 if mode=='rejected' or mode=='no-effect' then
  pickup.action=nativeAction();pickup.transactionId=100000;transactions[100000]=mode=='rejected'and'rejected'or'completed'
  lifecycle.begin(pickup,'perform');lifecycle.finish(pickup,'perform',true)
  if mode=='no-effect'then bag.inner:Remove(prop);player.inventory:AddItem(prop);removeCurrent(q)end
 elseif mode=='generation'then q.toolkitOperationGeneration=(q.toolkitOperationGeneration or 0)+1
 elseif mode=='host-prop-replica'or mode=='host-wrong-member'then
  -- Host updates action.item/root before perform, while its native group retains
  -- the original detached Java member. No client-side transfer effect is replayed.
  local original=prop;bag.inner:Remove(original)
  prop=item('DumbBell');prop.id=original.id;prop.favorite=true;original.source=nil
  pickup.item=prop;pickup.action=nativeAction();pickup.transactionId=100001;transactions[100001]='completed'
  if mode=='host-wrong-member'then
   local foreign=item('DumbBell');player.inventory:Remove(foreign);foreign.source=nil;foreign.id=prop.id
   pickup.queueList[1].items[1]=foreign
  end
  lifecycle.begin(pickup,'perform')
  table.remove(pickup.queueList,1);pickup.item=original;pickup.transactionId=0
  lifecycle.finish(pickup,'perform',true);removeCurrent(q)
  for _,action in ipairs(q.queue)do if action.item==original then action.item=prop end end
 end
 for _=1,20 do if not q.queue[1]then break end;runCurrent(q)end
 assert(prop:getContainer()==player.inventory and bag:getWorldItem(),'native preparation did not fetch exact prop/place its carrier')
 if mode=='host-replica'then
  local world=bag:getWorldItem();local fresh=item('Bag_Schoolbag',floor,'BACK');fresh.id=bag.id;fresh.favorite=bag.favorite
  floor:Remove(bag);world.getItem=function()return fresh end;fresh.world=world;bag.world=nil
  bag.inner:Remove(other);fresh.inner:AddItem(other);bag=fresh
 elseif mode=='missing-bag' or mode=='same-type-bag'then
  worlds={};floor:Remove(bag);bag.world=nil
  if mode=='same-type-bag'then local spare=item('Bag_Schoolbag',nil,'BACK');player.worn.BACK=spare end
 elseif mode=='moved-prop'then player.inventory:Remove(prop);other.source:AddItem(prop)
 elseif mode=='changed-callback'then prop.changed=true
 elseif mode=='full-bag'then bag.inner.hasRoomFor=function()return false end end
 -- Native stop can legitimately advance generation; the already earned pickup
 -- remains an obligation, without authorizing a second pickup or another prop.
 q.toolkitOperationGeneration=(q.toolkitOperationGeneration or 0)+1
 fitness:setCurrentExercise(nil)
 q.queue[1]=head();q.current=q.queue[1]
 local nativeMatches=policy.matchesNative
 if mode=='changed-callback'then policy.matchesNative=function()return true end end
 equipmentTick();local count=#q.queue;equipmentTick();assert(#q.queue==count,'closed window cleanup was queued twice');removeCurrent(q)
 if mode=='cleanup-generation'then q.toolkitOperationGeneration=q.toolkitOperationGeneration+1 end
 local returnCount,commands=0,0
 local alive=player.isDead
 local specific=getSpecificPlayer
 local foreign={isDead=function()return false end,getPlayerNum=function()return 9 end,getInventory=function()return container()end}
 getSpecificPlayer=function(number)if number==9 then return foreign end;return specific(number)end
 for _=1,30 do
  local action=q.queue[1];if not action then break end
  if action.Type=='ISQueueActionsAction'then
   commands=commands+1
   if mode=='tampered-snapshot'then
    assert(commands>1 or type(action.args[1])=='table'and action.args[1].loan==nil and action.args[1].refs==nil,
     'native cleanup exposed mutable provenance')
    action.args[1].loan={earned=true};action.args[1].refs={}
   end
   if mode=='foreign-actor'then
    local amount=#q.queue;action.addActionsFunction(foreign,action.args[1])
    assert(#q.queue==amount,'foreign actor expanded another actor cleanup')
   end
   if mode=='copied-snapshot'then action.args[1]={loan={earned=true}}end
   if mode=='replayed-command'then
    action.addActionsFunction(player,action.args[1]);local amount=#q.queue
    action.addActionsFunction(player,action.args[1]);assert(#q.queue==amount,'cleanup command replay queued duplicate work')
   end
   if mode=='dead-before-return'and commands==2 then player.isDead=function()return true end end
  end
  if action.Type=='ISInventoryTransferAction'and action.srcContainer==player.inventory and action.item==prop then returnCount=returnCount+1 end
  runCurrent(q)
 end
 policy.matchesNative=nativeMatches;player.isDead=alive;getSpecificPlayer=specific
 local restored=mode=='sp'or mode=='host-replica'or mode=='host-prop-replica'or mode=='held-bag'or mode=='empty-hands'or mode=='tampered-snapshot'or mode=='replayed-command'or mode=='foreign-actor'
 assert(returnCount==(restored and 1 or 0),'unproved/repeated native prop return: '..mode)
 if restored then
  assert(prop:getContainer()==bag.inner and prop:isFavorite()and bag:isFavorite()and (mode=='held-bag'and player.primary==bag or mode~='held-bag'and player.worn.BACK==bag),
   'native cleanup lost exact prop/carrier/favourites: '..mode)
  assert(other:getContainer()==bag.inner,'native cleanup selected another same-type prop')
 end
 if mode=='missing-bag'or mode=='same-type-bag'then assert(prop:getContainer()==player.inventory,'missing carrier substituted another bag')end
 if mode=='cleanup-generation'then assert(not player.worn.BACK,'stale cleanup changed newer equipment intent')end
end
enabled=true
print('PASS native disabled Fitness observed pickup/Host hand sync, fresh carrier and failed/stale/missing-source guards')

-- Execute the selected cart equipment/drop wrappers after Fitness captures native callbacks,
-- exactly as the full mod pack's OnGameStart does. Source pins and the production
-- private equipment/drop admission installers are used rather than unconditional cart approval.
if SaucedCartsSource then
 local restrictionsPath=SaucedCartsSource..'/ContainerRestrictions.lua'
 local restrictions=read(restrictionsPath)
 local coreText=read(SaucedCartsSource..'/Core.lua')
 local clientRoot=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/'
 local compatText=read(clientRoot..'ActionQueueCompat.lua')
 local cartsText=read(clientRoot..'ActionQueueCarts.lua')
 local pinCode='local Proof=assert(loadfile(ProjectRoot..\'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua\'))();local sourceFiles={}\n'
  ..assert(compatText:match('(local function verified%(id, files%).-\nend)'))..'\nlocal Compat={}\n'
  ..assert(compatText:match('(function Compat.isCartMaskSource%(%).-\nend)'))..'\nreturn Compat'
 local admissionCode='local Carts={isTransfer=function()return false end,isReturn=function()return false end};local Toolkit=PZSurvivorToolkit;local core=SaucedCarts;local compat=Toolkit.ActionQueueCompat;local Policy=Toolkit.ActionQueuePolicy\n'
  ..'local function filename(callback)return getFilenameOfClosure(callback):match("([^/]+)$")end\n'
  ..'local function unchanged()return Toolkit.ActionQueueCarts==Carts end\n'
  ..assert(cartsText:match('(local equipmentGuard, equipmentMatch, equipmentPrevious, equipmentReplacement.-)\nfunction Carts.install'))
  ..'\nToolkit.ActionQueueCarts=Carts;installFoodMaskRemoval();installFitnessStorageDrop();return Carts'
 local hookCode='local dropActionHookInitialized=false;local unequipHookInitialized=false\n'
  ..assert(restrictions:match('(local function flushDistanceOnCreate%(character, item, label%).-\nend)'))..'\n'
  ..assert(restrictions:match('(local function wrapDropNew%(%).-\nend)'))..'\n'
  ..assert(restrictions:match('(local function initDropActionHook%(%).-\nend)'))..'\n'
  ..assert(restrictions:match('(local function wrapUnequipNew%(%).-\nend)'))..'\n'
  ..assert(restrictions:match('(local function initUnequipHook%(%).-\nend)'))..'\nreturn function()initUnequipHook();initDropActionHook()end'
 local function source(text,path)return assert(loadstring(text,'@'..path))()end
 local originalStartAdd=Events.OnGameStart.Add
 local originalModReader=getModFileReader
 local originalCompat=PZSurvivorToolkit.ActionQueueCompat
 local originalCarts,originalSaucedCarts=PZSurvivorToolkit.ActionQueueCarts,SaucedCarts
 for _,mode in ipairs({'normal','pickup-cancel','active-cancel','changed-source','preinstalled'})do
  reset()
  native('shared/TimedActions/ISFitnessAction.lua');native('client/ISUI/ISFitnessUI.lua')
  native('shared/TimedActions/ISDropWorldItemAction.lua');native('shared/TimedActions/ISUnequipAction.lua')
  f.project('FitnessEquipment') -- Each source scenario owns its native UI preparation registry.
  f.project('ActionQueueDefinitions');policy=f.project('ActionQueuePolicy')
  local cartCore=assert(loadstring('local Queue,Toolkit,Policy,Operations,Settlement = ...\n'..
   'local craft,live,stoppable=Policy.isCraftAction,Policy.live,Policy.stoppable\n'..
   'local Batch,processPriority,returnMarker=nil,nil,{}\n'..coreChunk..'\nreturn Queue',
   '@PZSurvivorToolkit/ActionQueue.lua'))({},PZSurvivorToolkit,policy,PZSurvivorToolkit.ActionQueueOperations,settlement)
  local callbacks={}
  Events.OnGameStart.Add=function(callback)callbacks[#callbacks+1]=callback end
  SaucedCarts=source('return {CartTypes={},safeIsCart=function(item)return item and item.cart end,debug=function()end}',SaucedCartsSource..'/Core.lua')
  getModFileReader=function(id,path)
   assert(id=='SaucedCarts')
   local text=path:match('/Core.lua$') and coreText or restrictions
   if mode=='changed-source'then text=text..'\n-- changed selected source\n'end
   local offset=1
   return {readLine=function()
    if offset>#text then return end
    local stop=text:find('\n',offset)or #text+1;local line=text:sub(offset,stop-1);offset=stop+1;return line
   end,close=function()end}
  end
  PZSurvivorToolkit.ActionQueueCompat=source(pinCode,clientRoot..'ActionQueueCompat.lua')
  local hook=source(hookCode,restrictionsPath)
  if mode=='preinstalled'then hook()else Events.OnGameStart.Add(hook)end
  local carts=source(admissionCode,clientRoot..'ActionQueueCarts.lua')
  fitnessQueue=f.project('ActionQueueFitness')
  installFoodWearContract()
  for _,callback in ipairs(callbacks)do callback()end
  -- Mirror Compat's synchronous enqueue observation before Fitness binds preparation.
  local nativeAdd=ISTimedActionQueue.add
  local borrowingScope
  ISTimedActionQueue.add=function(action)
   local result=nativeAdd(action)
   if result and action.toolkitQueueOperation then
    borrowingScope=borrowingScope or settlement.deferred(player,action.toolkitQueueOperation)
    settlement.remember(borrowingScope,action,policy.inspect(action))
    if action.Type=='ISInventoryTransferAction' and action.srcContainer:getType()~='floor' and policy.isOrdinaryTransfer(action) then settlement.preparePickup(borrowingScope,action)end
   end
   return result
  end
  local bag=item('Bag_BigHikingBag',nil,'BACK');bag.favorite=true;player.worn.BACK=bag
  local packed=item('WaterBottle',bag.inner);local borrowed=item('DumbBell',bag.inner)
  local axe=item('Axe',nil,nil,true);player.primary,player.secondary=axe,axe
  local requestAction,cartQueue=request('bicepscurl',10)
  if mode=='changed-source' or mode=='preinstalled'then
   assert(not fitnessQueue.isManaged(requestAction)and requestAction.Type=='ISInventoryTransferAction',
    'unverified/preinstalled cart drop source acquired managed producer permission: '..mode)
  else
   assert(fitnessQueue.isManaged(requestAction),'actual selected late cart drop wrappers forced native Fitness fallback')
   expand(requestAction,cartQueue)
   local reviewedUnequips={}
   for _,action in ipairs(cartQueue.queue)do if action.Type=='ISUnequipAction'then reviewedUnequips[#reviewedUnequips+1]=action end end
   local unrelated=head();ISTimedActionQueue.add(unrelated)
   local borrowedReturns=0
   if mode=='pickup-cancel'then
    local pickup=assert(cartQueue.queue[1]);assert(pickup.Type=='ISInventoryTransferAction')
    pickup.action=nativeAction();cartQueue.current=pickup;lifecycle.started(pickup)
    nextTransaction=nextTransaction+1;pickup.transactionId=nextTransaction;transactions[nextTransaction]='completed'
    lifecycle.begin(pickup,'perform');pickup:checkQueueList()
    assert(cartCore.cancelOperation(cartQueue,pickup),'actual cart unequip wrapper blocked in-flight pickup cancellation')
    pickup.srcContainer:Remove(borrowed);pickup.destContainer:AddItem(borrowed)
    table.remove(pickup.queueList,1);lifecycle.finish(pickup,'perform',true);lifecycle.reset(cartQueue);cartQueue:onCompleted(pickup)
   else
    local exercise=reachExercise(cartQueue)
    assert(bag:getWorldItem()and not player.worn.BACK,'approved ordinary bag did not use native paid ground placement')
    if mode=='active-cancel'then
     assert(cartCore.cancelOperation(cartQueue,exercise),'actual cart unequip wrapper blocked active exercise cancellation')
     exercise:forceStop();cartQueue:onCompleted(exercise)
    else exercise:forceStop();removeCurrent(cartQueue)end
   end
   for _=1,20 do
    if cartQueue.queue[1]==unrelated then break end
    local current=assert(cartQueue.queue[1])
    if current.Type=='ISInventoryTransferAction'and current.item==borrowed and current.destContainer==bag.inner then borrowedReturns=borrowedReturns+1 end
    runCurrent(cartQueue)
   end
   assert(cartQueue.queue[1]==unrelated and player.primary==axe and player.secondary==axe and player.worn.BACK==bag
    and borrowed:getContainer()==bag.inner and borrowedReturns==1 and packed:getContainer()==bag.inner and bag:isFavorite()and #worlds==0,
    'actual cart equipment/drop wrappers lost exact hands/storage/prop return before tail: '..mode)
   assert(#reviewedUnequips==2,'actual wrapper fixture omitted hand/bag preparation')
   for _,action in ipairs(reviewedUnequips)do
    local contract,adapter=policy.inspect(action)
    assert(contract and adapter=='toolkit.fitness-cart-unequip','owned wrapped unequip lacks its unambiguous Fitness contract')
    local foreign=ISUnequipAction:new(player,action.item,50)
    assert(not policy.inspect(foreign),'identical unowned wrapped unequip acquired Fitness queue-edit permission')
   end
   local function rejected(message)
    player.primary,player.secondary=nil,nil
    player.worn.BACK=nil -- Fallback is checked without executing a deliberately replaced constructor.
    local rejectedAction,_,rejectedWindow=request('squats',10)
    player.worn.BACK=bag
    assert(not fitnessQueue.isManaged(rejectedAction)and rejectedAction.Type=='ISWaitWhileGettingUp',message)
    -- Each mutation is an independent native fallback. Finish its UI episode
    -- so the repeated-OK preparation guard cannot block the next scenario.
    fitness:setCurrentExercise(nil)
    rejectedWindow:update()
   end
   for _,name in ipairs({'new','isValid','complete'})do
    local callback=ISDropWorldItemAction[name];ISDropWorldItemAction[name]=function()end
    rejected('changed drop callback retained managed permission: '..name)
    ISDropWorldItemAction[name]=callback
   end
   for _,name in ipairs({'new','complete','start'})do
    local callback=ISUnequipAction[name];ISUnequipAction[name]=function()end
    rejected('changed unequip callback retained managed permission: '..name)
    assert(not policy.inspect(reviewedUnequips[1]),'changed unequip callback retained owned contract')
    ISUnequipAction[name]=callback
   end
   for _,name in ipairs({'isUnequipConstructor','isNonCartUnequip'})do
    local helper=carts[name];carts[name]=function()return true end
    rejected('replacement equipment helper retained managed permission: '..name)
    assert(not policy.inspect(reviewedUnequips[1]),'replacement equipment helper retained owned contract')
    carts[name]=helper
   end
   local classifier=SaucedCarts.safeIsCart;SaucedCarts.safeIsCart=function()return false end
   rejected('changed cart classification helper retained managed drop permission');SaucedCarts.safeIsCart=classifier
   local helper=carts.isDropCallback;carts.isDropCallback=function()return true end
   rejected('replacement cart admission helper retained managed permission');carts.isDropCallback=helper
   local removal=reviewedUnequips[1]
   removal.item.cart=true
   assert(not fitnessQueue.isManaged(removal)and not policy.inspect(removal),'cart acquired owned ordinary unequip permission')
   removal.item.cart=nil
   SaucedCarts.CartTypes[removal.item:getFullType()]=true
   assert(not fitnessQueue.isManaged(removal)and not policy.inspect(removal),'known cart type acquired owned unequip permission')
   SaucedCarts.CartTypes[removal.item:getFullType()]=nil
   removal.onCompleteFunc=function()end
   assert(not fitnessQueue.isManaged(removal)and not policy.inspect(removal),'foreign completion callback acquired owned unequip permission')
   removal.onCompleteFunc=nil
   local drop=ISDropWorldItemAction:new(player,bag,here,0,0,0,0,false)
   bag.cart=true;assert(not carts.isNonCartDrop(drop),'cart acquired ordinary ground storage drop permission');bag.cart=nil
   SaucedCarts.CartTypes[bag:getFullType()]=true
   assert(not carts.isNonCartDrop(drop),'known cart type acquired ordinary ground storage drop permission')
   SaucedCarts.CartTypes[bag:getFullType()]=nil
   drop.onCompleteFunc=function()end
   assert(not carts.isNonCartDrop(drop),'drop with foreign completion callback acquired managed permission')
  end
  ISTimedActionQueue.add=nativeAdd
 end
 Events.OnGameStart.Add=originalStartAdd;getModFileReader=originalModReader
 PZSurvivorToolkit.ActionQueueCompat=originalCompat
 PZSurvivorToolkit.ActionQueueCarts,SaucedCarts=originalCarts,originalSaucedCarts
 -- Later timer scenarios need fresh native owners and proofs, without the
 -- intentionally unapproved/preinstalled cart wrappers from the final case.
 native('shared/TimedActions/ISFitnessAction.lua');native('client/ISUI/ISFitnessUI.lua')
 native('shared/TimedActions/ISDropWorldItemAction.lua');native('shared/TimedActions/ISUnequipAction.lua')
 f.project('FitnessEquipment');f.project('ActionQueueDefinitions');policy=f.project('ActionQueuePolicy')
 fitnessQueue=f.project('ActionQueueFitness');installFoodWearContract()
 equipmentTick=assert(tickCallbacks[#tickCallbacks-1],'fresh native fitness cleanup callback missing')
 fitnessPrune=assert(tickCallbacks[#tickCallbacks],'fresh fitness record pruning callback missing')
 fitnessMenuReset=assert(menuCallbacks[#menuCallbacks],'fresh fitness menu cleanup callback missing')
 print('PASS actual late SaucedCarts equipment/drop wrappers preserve normal and cancelled borrowing with guarded admission')
end

-- Run the actual shared Base.stop/tick branches against the native UI producer.
-- Java removal and the server receipt are explicit, separately delayed boundaries.
do
 local savedCompleted=ISTimedActionQueue.onCompleted
 ISTimedActionQueue.onCompleted=coreCompleted
 local beginAt=assert(coreSource:find('local function clearStop(queue)',1,true))
 local endAt=assert(coreSource:find('Queue.label =',beginAt,true))
 assert(loadstring('local Queue,Toolkit,Policy,Operations,Settlement = ...\n'..
  'local craft,live,stoppable,resumableWorld=Policy.isCraftAction,Policy.live,Policy.stoppable,Policy.resumableWorld\n'..
  'local Batch,processPriority=nil,nil\n'..assert(coreSource:match('(local function updateOperationState.-\nend)'))..'\n'..coreSource:sub(beginAt,endAt-1),
  '@PZSurvivorToolkit/ActionQueue.lua'))(core,PZSurvivorToolkit,policy,PZSurvivorToolkit.ActionQueueOperations,settlement)
 PZSurvivorToolkit.ActionQueueAcknowledgements.reset=function()end
 ISLogSystem={logAction=function()end}
 player.getTimedActionToRetrigger=function()end;player.setTimedActionToRetrigger=function()end
 local actions=player.getCharacterActions
 local pressedCancel=player.pressedCancelAction
 player.pressedCancelAction=function()return false end
 player.isRunning=function()return false end;player.isSprinting=function()return false end
 local activeNative
 player.getCharacterActions=function()return {contains=function(_,value)return value==activeNative end}end
 local function nativeWorkout(kind,minutes)
  q=f.queue(head());window=panel(kind,minutes)
  window:onClick({internal='OK'})
  local requested=assert(q.queue[#q.queue].onCompleteArgs.p1)
  local constructorStart=requested.startMS
  local originalTail=head();ISTimedActionQueue.add(originalTail)
  removeCurrent(q);now=now+240000
  for _=1,20 do
   local current=assert(q.queue[1])
   if current.Type=='ISFitnessAction'then break end
   if current.Type=='ISWaitWhileGettingUp'then
    current.action=nativeAction();current:perform()
   else runCurrent(q)end
  end
  local body=runCurrent(q)
  assert(body==requested and not fitnessQueue.isManaged(body),'native control became a managed/editor action')
  assert(body.startMS==now and body.startMS>constructorStart and body.endMS==now+minutes*60000,
   'native workout spent its requested timer in preparation')
  activeNative=body.action
  return body,originalTail
 end
 -- B42.21 SyncClockPacket.processClient bytecode21-36 replaces timeOfDay
 -- with the received server value. Native frame elapsed/frameNo are unchanged.
 -- Exercise the exact source-pinned native/managed action callbacks around that reset.
 for _,managed in ipairs({false,true})do
  for _,host in ipairs({false,true})do
   for _,jump in ipairs({-2400000,2400000})do
    reset();enabled=managed;client=host
    local body
    if managed then
     local pending;pending,q=request('squats',10);expand(pending,q);body=reachExercise(q)
     activeNative=body.action
    else body=nativeWorkout('squats',10)end
    frameClock.manual=true
    local function frame(ms)
     frameClock.id=frameClock.id+1;frameClock.ms=ms;now=now+ms;frameClock.now=now
    end
    if host then receipt={state='started',token='sync-clock-confirmed'};body:update()end
    local beforeStops=nativeStops
    frame(60000);body:update()
    local sample=assert(fitnessQueue.timing(body))
    assert(math.abs(sample.elapsed-1)<1e-6,'first actual active minute missing')
    frameClock.offset=jump -- Actual SyncClock setter semantics; no engine frame has elapsed.
    body:update()
    assert(nativeStops==beforeStops and math.abs(fitnessQueue.timing(body).elapsed-1)<1e-6,
     'SyncClock reset changed earned active duration: '..tostring(managed)..':'..tostring(host)..':'..jump)
    for _=1,10 do
     local read=fitnessQueue.timing(body);if managed then fitnessQueue.progress(body);fitnessQueue.describe(body)end
     assert(math.abs(read.elapsed-1)<1e-6,'read-only timing/progress advanced the workout')
    end
    for minute=2,9 do frame(60000);body:update();assert(nativeStops==beforeStops,'active timer stopped early')end
    frame(60000);body:update()
    local ended=fitnessQueue.timing(body)
    assert(nativeStops==beforeStops+1 and ended.elapsed==10 and ended.fraction==1,
     'SyncClock reset extended or shortened the selected interval')
    assert(ended.source=='active-native-frames'and ended.sampleMS==ended.startMS+600000 and ended.stopMS==ended.sampleMS)
    body:update();assert(nativeStops==beforeStops+1,'same frame replayed native stop')
   end
  end
 end
 print('PASS native/managed SP/Host timers retain earned active duration through forward/backward SyncClock resets')
 for _,managed in ipairs({false,true})do
  reset();enabled=managed;client=true;frameClock.manual=true
  frameClock.ms=900000 -- The frame containing start is not nine earned minutes.
  local body
  if managed then
   local pending;pending,q=request('squats',10);expand(pending,q);body=reachExercise(q);activeNative=body.action
  else body=nativeWorkout('squats',10)end
  body:update();assert(fitnessQueue.timing(body).activeMS==0,'start credited its current/preparation frame')
  local function frame(ms)
   frameClock.id=frameClock.id+1;frameClock.ms=ms;now=now+ms;frameClock.now=now
  end
  frame(300000);body:update()
  assert(fitnessQueue.timing(body).activeMS==300000 and fitnessQueue.timing(body).elapsed==0,
   'unconfirmed active time became confirmed progress or disappeared')
  frame(120000);receipt={state='started',token='skip-confirmation-frame'};body:update()
  local confirmed=fitnessQueue.timing(body)
  assert(confirmed.confirmed and confirmed.activeMS==0 and confirmed.elapsed==0,
   'Host confirmation credited its current frame or pre-confirmation interval')
  local stops=nativeStops
  for _=1,8 do body:update();fitnessQueue.timing(body);if managed then fitnessQueue.progress(body)end end
  assert(fitnessQueue.timing(body).activeMS==0 and nativeStops==stops,'repeated same-frame calls earned time')
  frame(200000);body:update();frameClock.ms=900000;body:update()
  assert(fitnessQueue.timing(body).activeMS==200000,'changed delta replayed an already observed frame')
  for _,bad in ipairs({-1,math.huge,0/0})do
   frameClock.id=frameClock.id+1;frameClock.ms=bad;body:update()
   assert(fitnessQueue.timing(body).activeMS==200000,'invalid native frame delta earned time')
  end
  frame(200000);body:update();frame(199999);body:update()
  assert(nativeStops==stops and fitnessQueue.timing(body).activeMS==599999,'variable native frames shortened full duration')
  frame(1);body:update()
  local stopped=fitnessQueue.timing(body)
  assert(nativeStops==stops+1 and stopped.activeMS==600000 and stopped.stopMS==confirmed.startMS+600000,
   'variable native frames failed the exact full interval')
  frame(1000);receipt={state='started',token='late-started-receipt'};body:update()
  local late=fitnessQueue.timing(body)
  assert(nativeStops==stops+1 and late.startMS==confirmed.startMS and late.activeMS==600000 and late.stopMS==stopped.stopMS,
   'late started receipt restarted or extended an already stopped timer')
 end
 print('PASS start/confirmation frame exclusion, read-only progress, repeated frames, variable native deltas and frozen late-receipt stops')
 for _,managed in ipairs({false,true})do
  reset();enabled=managed
  local body
  if managed then
   local pending;pending,q=request('squats',10);expand(pending,q)
   for _=1,20 do if q.queue[1].Type=='ISFitnessAction'then break end;runCurrent(q)end
   body=assert(q.queue[1]);assert(body.Type=='ISFitnessAction')
  else
   q=f.queue(head());window=panel('squats',10);window:onClick({internal='OK'})
   body=assert(q.queue[#q.queue].onCompleteArgs.p1)
  end
  body.action=nativeAction();local stops=nativeStops
  assert(fitnessQueue.timing(body)==nil,'unstarted constructor acquired active duration')
  body:forceStop()
  assert(nativeStops==stops+1 and fitnessQueue.timing(body)==nil and not currentExercise,
   'stopping an unstarted native body invented time or lost its original stop')
 end
 print('PASS allocated unstarted native/managed bodies stop without inventing an active clock')
 for _,host in ipairs({false,true})do
  reset();enabled=false;client=host
  local bag=item('Bag_Schoolbag',nil,'BACK');bag.favorite=true;player.worn.BACK=bag
  local prop=item('DumbBell',bag.inner);prop.favorite=true
  local primary,secondary=item('Hammer'),item('Screwdriver');player.primary,player.secondary=primary,secondary
  local body,reader=nativeWorkout('bicepscurl',30)
  q.toolkitOperationsInvalid=true;body.toolkitQueueOperation.toolkitCancelled=true
  if host then
   body.toolkitNativeTransaction=91;body.toolkitNativeKind='ISFitnessAction'
   receipt={state='started'};body:update()
  end
  local started=now;local stopsBefore=nativeStops
  now=started+1800000-1;body:update()
  assert(nativeStops==stopsBefore and not q.toolkitCancel,'native thirty-minute workout ended early')
  now=started+1800000;body:update()
  assert(nativeStops==stopsBefore+1 and q.toolkitCancel==body,'native expiry did not arm one exact terminal stop')
  local queued=#q.queue;window:update();equipmentTick()
  assert(#q.queue==queued and q.queue[2]==reader,'native UI appended restoration before its stop settled')
  body:stop();assert(q.queue[1]==body and q.queue[2]==reader and q.toolkitCancelStopped,
   'native stop cleared the independent reader')
  local moodles=player.getMoodles
  if host then player.getMoodles=function()return {getMoodleLevel=function()return 4 end}end end
  -- An already-paid final endurance update cannot retroactively turn a sealed
  -- natural endpoint into an earlier exhaustion stop. Input cancellation still revokes it.
  q:tick();assert(q.queue[1]==body,'queue advanced before native removal')
  activeNative=nil
  if host then
   q:tick();assert(q.queue[1]==body,'Host advanced before matching terminal receipt')
   receipt.state='canceled'
  end
  q:tick()
  player.getMoodles=moodles
  assert(q.queue[1]~=body and q.queue[1]~=reader,'native cleanup was not inserted before independent tail')
  for _=1,30 do if q.queue[1]==reader then break end;runCurrent(q)end
  assert(q.queue[1]==reader and player.primary==primary and player.secondary==secondary and player.worn.BACK==bag
   and prop:getContainer()==bag.inner and bag:isFavorite() and prop:isFavorite() and #worlds==0,
   'native terminal failed exact bag/prop/hands restoration before reader')
  assert(nativeStops==stopsBefore+1,'native terminal replayed exercise stop/effects')
  window:update();equipmentTick();assert(#q.queue==1,'native restoration episode replayed after release')
 end
 for _,cause in ipairs({'move','aim','climb','sit','exhaustion','cancel','cancel-after-expiry','cancel-after-stop','cancel-after-stop-new-panel'})do
  reset();enabled=false;client=true
  local body,reader=nativeWorkout('squats',10)
  body.toolkitNativeTransaction=92;body.toolkitNativeKind='ISFitnessAction';receipt={state='started'};body:update()
  local restore
  if cause=='move'then restore=player.pressedMovement;player.pressedMovement=function()return true end
  elseif cause=='aim'then restore=player.isAiming;player.isAiming=function()return true end
  elseif cause=='climb'then restore=player.isClimbing;player.isClimbing=function()return true end
  elseif cause=='sit'then restore=player.isSittingOnFurniture;player.isSittingOnFurniture=function()return true end
  elseif cause=='exhaustion'then restore=player.getMoodles;player.getMoodles=function()return {getMoodleLevel=function()return 4 end}end end
  now=now+600001
  if cause=='cancel'then window:onClick({internal='CANCEL'})
  else body:update();if cause=='cancel-after-expiry' or cause=='cancel-after-stop' or cause=='cancel-after-stop-new-panel'then
    assert(q.toolkitCancel==body,'fixture failed to reach natural stop wait')
    if cause=='cancel-after-stop' or cause=='cancel-after-stop-new-panel'then body:stop();activeNative=nil end
    if cause=='cancel-after-stop-new-panel'then window=panel('squats',10)end
    window:onClick({internal='CANCEL'});window:update()
   end
  end
  if cause=='cancel-after-stop' or cause=='cancel-after-stop-new-panel'then q:tick()else body:stop();activeNative=nil end
  assert(#q.queue==0 and q.current==nil,cause..' borrowed natural-expiry permission and retained tail')
  if cause=='move'then player.pressedMovement=restore
  elseif cause=='aim'then player.isAiming=restore
  elseif cause=='climb'then player.isClimbing=restore
  elseif cause=='sit'then player.isSittingOnFurniture=restore
  elseif cause=='exhaustion'then player.getMoodles=restore end
 end
 reset();enabled=false;client=true
 local detachedBag=item('Bag_Schoolbag',nil,'BACK');player.worn.BACK=detachedBag
 local detachedProp=item('DumbBell',detachedBag.inner)
 player.primary,player.secondary=item('Hammer'),item('Screwdriver')
 local detachedBody=nativeWorkout('bicepscurl',10)
 detachedBody.toolkitNativeTransaction=93;detachedBody.toolkitNativeKind='ISFitnessAction';receipt={state='started'}
 detachedBody:update();now=now+600001;detachedBody:update();detachedBody:stop();activeNative=nil
 local oldQueue,oldPanel=q,window
 local foreign=head();local replacement=f.queue(foreign)
 local replacementList=replacement.queue;replacement.toolkitOperationGeneration=17
 lifecycleSweep();fitnessPrune();equipmentTick();oldPanel:update();oldQueue:tick();oldPanel:update();equipmentTick()
 assert(ISTimedActionQueue.queues[player]==replacement and replacement.queue==replacementList and #replacement.queue==1
  and replacement.current==foreign and replacement.queue[1]==foreign and replacement.toolkitOperationGeneration==17,
  'detached stop or old UI appended/replayed restoration into replacement queue')
 assert(detachedBag:getWorldItem() and detachedProp:getContainer()==player:getInventory(),
  'detached cleanup replayed native pickup/return effects')
 reset();enabled=false
 q=f.queue(head());window=panel('squats',10);window:onClick({internal='OK'})
 assert(currentExercise=='squats','fixture failed to reserve constructor exercise')
 q:resetQueue();fitnessPrune();equipmentTick()
 assert(currentExercise==nil and window.currentExercice==nil,'canceled native preparation stranded constructor/UI state')
 q.queue[1]=head();q.current=q.queue[1] -- Native Java allocation is modeled by runCurrent in this fixture.
 window:onClick({internal='OK'})
 assert(q.queue[2] and q.queue[2].Type=='ISWaitWhileGettingUp','canceled empty-hand native request blocked later workout')
 reset();enabled=false
 q=f.queue(head());window=panel('squats',10);window:onClick({internal='OK'})
 local replacement=ISFitnessAction:new(player,'squats',10,FitnessExercises.exercisesType.squats,'squats')
 q:resetQueue();fitnessPrune()
 assert(replacement.fitness:getCurrentExe()==exerciseStates.squats,'old unstarted request cleared a later same-kind constructor state')
 player.getCharacterActions=actions;player.pressedCancelAction=pressedCancel
 ISTimedActionQueue.onCompleted=savedCompleted
 print('PASS native UI thirty-minute timer, original stop/removal/Host receipt, exact cleanup before reader and explicit input/cancel distinction')
end

-- A changed source present before capture must not acquire a new permission.
native('shared/TimedActions/ISFitnessAction.lua');native('client/ISUI/ISFitnessUI.lua')
f.project('ActionQueueDefinitions')
sourceOverride=function(path)
    if path=='media/lua/shared/TimedActions/ISFitnessAction.lua'then
        return read(NativeActionRoot..'/shared/TimedActions/ISFitnessAction.lua')..'\n-- altered source\n'
    end
end
local untrusted=f.project('ActionQueueFitness')
reset();q=f.queue(head());window=panel('squats',10);window:onClick({internal='OK'})
nativeWait=assert(q.queue[2])
assert(nativeWait.Type=='ISWaitWhileGettingUp' and not untrusted.isManaged(nativeWait),'unverified native source acquired managed producer permission')
sourceOverride=nil
native('shared/TimedActions/ISFitnessAction.lua');native('client/ISUI/ISFitnessUI.lua')
f.project('ActionQueueDefinitions')
local foreignConstructor=function(self,character,foreignMinutes,foreignData,extraWireField) return {} end
ISFitnessAction.new=foreignConstructor
f.project('ActionQueueFitness')
assert(ISFitnessAction.new==foreignConstructor,'unsupported constructor lost its original parameter-name wire ABI')
print('PASS pre-existing native source/constructor mismatch falls back without managed permissions or wire-schema changes')
