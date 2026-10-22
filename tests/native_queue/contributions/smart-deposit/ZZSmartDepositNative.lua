-- Real B42 inventory items, world storage, UI drag validation and transfer actions.
-- No renderer, global helper, planner or native action is replaced.
require 'TimedActions/ISInventoryTransferAction'
require 'TimedActions/ISInventoryTransferUtil'
local Proximity = require 'BetterContainers/Proximity'
local BCOptions = require 'BetterContainers/_Options'
local Category = require 'BetterContainers/Categorize/InventoryCategory'
local entered, starting, started, done = false, false, false, false
local phase, since, modeIndex = 'setup', 0, 1
local modes = {'clean', 'vanilla'}
local objects, stores, seeds, samples, extras, expected, durations = {}, {}, {}, {}, {}, {}, {}
local source, sourcePane, loot, pane, button, target, fixtureSquare
local holdDrag = false
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()).queue end
local function empty(container)
    for i=container:getItems():size()-1,0,-1 do container:Remove(container:getItems():get(i)) end
end
local function idle() return #queue()==0 and not getPlayer():hasTimedActions() end
local function clearDrag()
    holdDrag=false
    ISMouseDrag.dragging=nil; ISMouseDrag.draggingFocus=nil
    if sourcePane then sourcePane.dragging=nil; sourcePane.dragStarted=false; sourcePane.draggedItems:reset() end
    if loot then loot.mouseOverButton=nil end
end
local function drag(items)
    ISMouseDrag.dragging=items
    -- No physical button is held. Keep native drag state for rendered feedback,
    -- without asking onMouseUp to dispatch an additional transfer.
    ISMouseDrag.draggingFocus=nil
    sourcePane.dragging=1; sourcePane.dragStarted=true
    -- Native onMouseDown stores pane-local x/y. Both renderdetails passes
    -- subtract these from the current local mouse position for dragged rows.
    sourcePane.draggingX=sourcePane:getMouseX()
    sourcePane.draggingY=sourcePane:getMouseY()
    assert(type(sourcePane.draggingX)=='number' and type(sourcePane.draggingY)=='number','native drag coordinates missing')
    sourcePane.draggedItems:reset()
    loot.mouseOverButton=button
    holdDrag=true
    sourcePane.draggedItems:update()
end
local function nativeArea(player)
    local origin=player:getCurrentSquare()
    for radius=2,12 do
        for dx=-radius,radius do for dy=-radius,radius do
            if math.abs(dx)==radius or math.abs(dy)==radius then
                local x,y,z=origin:getX()+dx,origin:getY()+dy,origin:getZ()
                local clear=true
                for a=-1,1 do for b=-1,1 do
                    local sq=getCell():getGridSquare(x+a,y+b,z)
                    if not sq or not sq:isFree(false) or sq:getRoom() or sq:getObjects():size()>1 then clear=false end
                end end
                if clear then player:teleportTo(x+0.5,y+0.5,z); return getCell():getGridSquare(x,y,z) end
            end
        end end
    end
    error('No clear loaded 3x3 Smart Deposit fixture area')
end
local function setup()
    assert(not isClient() and not isServer(),'SP required')
    for _,id in ipairs({'ContainerCapacityIndicator','BravoItemDetails','Quartermaster','HasResearch','SeedSeasonIndicator'}) do
        assert(not getActivatedMods():contains(id),'external inventory owner enabled: '..id)
    end
    assert(PZSurvivorToolkit.SmartDeposit and PZSurvivorToolkit.SmartDeposit.plan,'owned Smart Deposit missing')
    local player=getPlayer(); player:setGodMod(true); player:setGhostMode(true); player:setAutoDrink(false)
    getCore():setOptionAutoDrink(false)
    if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
    if getPlayerInfoPanel and getPlayerInfoPanel(0) then getPlayerInfoPanel(0):setVisible(false) end
    player:getWornItems():clear(); player:setPrimaryHandItem(nil); player:setSecondaryHandItem(nil)
    source=player:getInventory(); empty(source)
    BCOptions.enableProximity=true; BCOptions.enableCorpseOnly=false; BCOptions.enableDualMode=false
    BCOptions.enableNestedContainers_Loot=false; BCOptions.enableAutoLock=false
    local origin=nativeArea(player)
    fixtureSquare=origin
    for _,offset in ipairs({{1,0},{0,1},{-1,0}}) do
        local square=assert(getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ()))
        local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
        object:setCanPassThrough(true); object:setIsContainer(true)
        local container=assert(object:getContainer()); container:setType('crate'); container:setCapacity(10); container:setExplored(true)
        square:AddSpecialObject(object); objects[#objects+1]=object
    end
    print('[SMART_DEPOSIT] SETUP SP native=true storage=3')
end
local function showMode()
    assert(idle(),'previous native transfers did not drain')
    clearDrag()
    -- Real transfers may reposition the actor at a crate. Start each UI case
    -- from the same centre so all three fixture containers remain in reach.
    getPlayer():teleportTo(fixtureSquare:getX()+0.5,fixtureSquare:getY()+0.5,fixtureSquare:getZ())
    for _,item in ipairs(samples) do if item:getContainer()==source then source:Remove(item) end end
    for _,item in ipairs(extras) do if item:getContainer()==source then source:Remove(item) end end
    for _,object in ipairs(objects) do empty(object:getContainer()) end
    samples={}; extras={}; seeds={}; expected={}; durations={}
    CleanUI_setCleanInventoryUIEnabled(modeIndex==1)
    if getPlayerInfoPanel and getPlayerInfoPanel(0) then getPlayerInfoPanel(0):setVisible(false) end
    local page=getPlayerInventory(0); sourcePane=page.inventoryPane
    page:setVisible(true); page:setX(30); page:setY(50); page:setWidth(650); page:setHeight(760)
    page.isCollapsed=false; page:setPinned(); page:setMaxDrawHeight(760)
    sourcePane:setMode('details'); sourcePane:setVisible(true)
    loot=getPlayerLoot(0); pane=loot.inventoryPane
    loot:setVisible(true); loot:setX(700); loot:setY(50); loot:setWidth(550); loot:setHeight(760)
    loot.isCollapsed=false; loot:setPinned(); loot:setMaxDrawHeight(760)
    pane:setMode('details'); pane:setVisible(true)
    loot:refreshBackpacks()
end
local function prepare()
    loot:refreshBackpacks()
    target=Proximity.GetItemContainer(0)
    button=nil; stores={}
    local known={}; for _,object in ipairs(objects) do known[object:getContainer()]=true end
    for _,entry in ipairs(loot.backpacks) do
        if entry.inventory==target then button=entry end
        local container=entry.inventory
        if container and container:getType()=='crate' then
            assert(known[container],'unexpected nearby storage would change admission')
            stores[#stores+1]=container
        elseif container and container~=target and container:getType()~='floor' then
            error('unexpected nearby storage: '..tostring(container:getType()))
        end
    end
    local kinds={};for _,entry in ipairs(loot.backpacks)do kinds[#kinds+1]=entry.inventory and entry.inventory:getType()or 'nil'end
    assert(button and #stores==3,'native proximity button or three world crates missing: mode='..modes[modeIndex]..' button='..tostring(button~=nil)..' stores='..#stores..' types='..table.concat(kinds,',')..' position='..getPlayer():getX()..','..getPlayer():getY())
    loot:onBackpackClick(button)
    assert(pane.inventory==target and PZSurvivorToolkit.SmartDeposit.isTarget(target),'real proximity target not selected')
    -- Roles follow BC's actual button order: an early fallback and category
    -- candidate must lose to the later full-type candidate.
    seeds[2]=assert(stores[2]:AddItem('Base.Screws'))
    seeds[3]=assert(stores[3]:AddItem('Base.Nails'))
    for i=1,4 do
        samples[i]=assert(source:AddItem('Base.Nails'))
        samples[i]:setName('Deposit '..i)
        assert(instanceof(samples[i],'InventoryItem'),'real native input required')
    end
    assert(seeds[2]:getFullType()~=samples[1]:getFullType() and Category.get(seeds[2])==Category.get(samples[1]),'native Nails/Screws category precondition changed')
    local weight=samples[1]:getUnequippedWeight()
    assert(weight>0,'native item weight is zero')
    for i,container in ipairs(stores) do
        local filler=assert(container:AddItem('Base.Apple'))
        assert(Category.get(filler)~=Category.get(samples[1]),'fallback filler matches moving category')
        filler:setActualWeight(container:getEffectiveCapacity(getPlayer())-(seeds[i] and seeds[i]:getUnequippedWeight() or 0)-weight*1.5)
        filler:setCustomWeight(true)
        assert(container:hasRoomFor(getPlayer(),samples[1]) and not container:hasRoomFor(getPlayer(),weight*2,weight*2),'native one-item capacity precondition differs')
        seeds['filler'..i]=filler
    end
    sourcePane:sortItemsByTypeAndWeight(samples)
    expected[samples[1]]=stores[3]; expected[samples[2]]=stores[2]; expected[samples[3]]=stores[1]
    sourcePane:refreshContainer(); sourcePane.selected={}
    for _,group in ipairs(sourcePane.itemslist) do sourcePane.collapsed[group.name]=false end
    sourcePane:refreshContainer()
    local selected={}; for _,item in ipairs(samples) do selected[item]='item' end
    sourcePane:restoreSelection(selected)
    local count=0; for _,item in pairs(sourcePane.selected) do assert(expected[item] or item==samples[4],'unexpected selected native row'); count=count+1 end
    assert(count==4,'four physical child rows must be selected for per-item feedback')
    drag(samples)
end
local function preview()
    loot.mouseOverButton=button
    sourcePane.draggedItems:update()
    local previous=assert(sourcePane.draggedItems.toolkitSmartDepositPreview,'advisory preview missing')
    for _=1,16 do
        sourcePane.draggedItems:update()
        local current=assert(sourcePane.draggedItems.toolkitSmartDepositPreview)
        if current~=previous then
            assert(current.at-previous.at>=200,'unchanged native hover rebuilt its plan before expiry')
        end
        previous=current
    end
    assert(pane:canPutIn()==true and loot:canPutIn()==true,'partial batch must allow drop')
    assert(not sourcePane.draggedItems:cannotDropAnyItem(),'partial batch marked wholly rejected')
    for _,item in ipairs(samples) do
        assert((sourcePane.draggedItems.itemNotOK[item]==true)==(expected[item]==nil),'per-item preview disagrees with finite admission: '..item:getID())
        assert(sourcePane.draggedItems:cannotDropItem(item)==(expected[item]==nil),'native cannotDropItem differs')
    end
    -- The public planner is additional routing evidence. Acceptance above came
    -- through the installed pane/page/draggedItems paths.
    local plan=assert(PZSurvivorToolkit.SmartDeposit.plan(sourcePane,samples,target))
    for _,item in ipairs(samples) do assert(plan.accepted[item]==expected[item],'full-type/category/fallback destination differs') end
    print('[SMART_DEPOSIT] PREVIEW '..modes[modeIndex]..' accepted=3 rejected=1 pane=true page=true exact=true category=true fallback=true')
    local name='smart-deposit-'..modes[modeIndex]..'-partial.png'
    getCore():TakeFullScreenshot(name); print('[SMART_DEPOSIT] SHOT '..name)
end
local function transfer()
    assert(not getPlayer():isPlayerMoving(),'duration control requires a stationary native player')
    for item,dest in pairs(expected) do
        local baseline=ISInventoryTransferUtil.newInventoryTransferAction(getPlayer(),item,source,dest)
        assert(baseline.Type=='ISInventoryTransferAction','ordinary Nail must use native transfer factory branch')
        durations[item]={raw=baseline.maxTime,created=baseline:adjustMaxTime(baseline.maxTime)}
    end
    holdDrag=false
    assert(loot:dropItemsInContainer(button),'native container-button drop did not dispatch')
    clearDrag()
    local seen, count={},0
    for _,action in ipairs(queue()) do
        if action.Type=='ISInventoryTransferAction' then
            assert(expected[action.item] and not seen[action.item],'native transfer queued rejected/duplicate item')
            assert(action.srcContainer==source and action.destContainer==expected[action.item],'native transfer endpoints differ')
            local baseline=assert(durations[action.item])
            -- addToQueue immediately begins the first action. Native create()
            -- applies adjustMaxTime for moodles, wounds and body temperature;
            -- waiting actions still retain the factory's constructor time.
            local expectedTime=action.action and baseline.created or baseline.raw
            local queuedTime=action.queueList and action.queueList[1] and action.queueList[1].time
            local detail='item='..action.item:getID()..' factory='..tostring(baseline.raw)..' created='..tostring(action.action~=nil)..' expected='..tostring(expectedTime)..' observed='..tostring(action.maxTime)..' queueTime='..tostring(queuedTime)
            print('[SMART_DEPOSIT] DURATION '..modes[modeIndex]..' '..detail)
            assert(queuedTime==baseline.raw and action.maxTime==expectedTime,'native transfer duration changed '..detail)
            seen[action.item]=true; count=count+1
        end
    end
    assert(count==3,'three real native transfer actions required')
    print('[SMART_DEPOSIT] QUEUED '..modes[modeIndex]..' nativeActions=3 rejected=false durationUnchanged=true')
end
local function effects()
    local all={source,stores[1],stores[2],stores[3]}
    for _,item in ipairs(samples) do
        local dest=expected[item] or source
        local count=0
        for _,container in ipairs(all) do if container:getItemById(item:getID())==item then count=count+1; assert(container==dest,'wrong native destination') end end
        assert(count==1 and item:getContainer()==dest,'native item lost/duplicated')
    end
    for i,container in ipairs(stores) do
        assert(container:getCapacityWeight()<=container:getEffectiveCapacity(getPlayer())+0.0001,'destination overfilled')
        if seeds[i] then assert(container:getItemById(seeds[i]:getID())==seeds[i],'routing seed moved') end
        assert(container:getItemById(seeds['filler'..i]:getID())==seeds['filler'..i],'capacity filler moved')
        assert(container:getItems():size()==(i==1 and 2 or 3),'unexpected destination item count')
    end
    assert(source:getItems():size()==1,'source did not retain exactly overflow')
    print('[SMART_DEPOSIT] EFFECT '..modes[modeIndex]..' moved=3 retained=1 unique=true seeds=true capacity=true')
    local batch={samples[4]}
    for i=1,3 do extras[i]=assert(source:AddItem('Base.Nails')); batch[#batch+1]=extras[i] end
    drag(batch)
    assert(pane:canPutIn()==false and loot:canPutIn()==false,'full storage still allows drop')
    assert(sourcePane.draggedItems:cannotDropAnyItem(),'full storage preview accepts an item')
    for _,item in ipairs(batch) do assert(sourcePane.draggedItems.itemNotOK[item]==true,'full storage item not rejected') end
    clearDrag(); sourcePane:transferItemsByWeight(batch,target)
    assert(idle(),'rejected batch queued native work')
    for _,item in ipairs(batch) do assert(item:getContainer()==source,'rejected batch changed source') end
    print('[SMART_DEPOSIT] FULL '..modes[modeIndex]..' accepted=0 rejected=4 pane=false page=false nativeActions=0')
end
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
    if holdDrag and sourcePane then
        -- This programmatic held drag has no physical cursor movement. Keep
        -- the native dragged-row offset at zero so feedback stays in view.
        sourcePane.draggingX=sourcePane:getMouseX()
        sourcePane.draggingY=sourcePane:getMouseY()
    end
    if holdDrag and loot then loot.mouseOverButton=button end
    if started and isIngameState() then setGameSpeed(1) end
    if not entered or starting or isIngameState() then return end
    starting=true; getCore():setOptionPauseOnFocusloss(false)
    getWorld():setGameMode('Sandbox'); getWorld():setWorld('SmartDepositNative'); getWorld():setMap('Muldraugh, KY')
    MainScreen.instance:setDefaultSandboxVars()
    for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2}) do getSandboxOptions():getOptionByName(name):setValue(value) end
    getSandboxOptions():toLua(); MainScreen.instance.createWorld=true
    MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
    MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
    MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
Events.OnGameStart.Add(function() started=true; since=getTimestampMs(); getCore():setOptionPauseOnFocusloss(false) end)
Events.OnTick.Add(function()
    if not started then return end
    local now=getTimestampMs()
    if done then if now-since>4000 then getCore():quitToDesktop() end; return end
    if phase=='wait' and not idle() then
        if now-since>=60000 then getCore():TakeFullScreenshot('smart-deposit-failed.png'); print('[SMART_DEPOSIT] FAIL native transfers did not drain'); done=true; since=now end
        return
    end
    if now-since<1800 then return end
    local ok,err=pcall(function()
        if phase=='setup' then setup(); phase='mode'
        elseif phase=='mode' then showMode(); phase='prepare'
        elseif phase=='prepare' then prepare(); phase='preview'
        elseif phase=='preview' then preview(); phase='transfer'
        elseif phase=='transfer' then transfer(); phase='wait'
        elseif phase=='wait' then
            effects(); modeIndex=modeIndex+1
            if modeIndex>#modes then
                for _,object in ipairs(objects) do object:getSquare():RemoveTileObject(object) end
                print('[SMART_DEPOSIT] COMPLETE'); done=true
            else phase='mode' end
        end
    end)
    if not ok then
        -- Preserve the native held-drag scene until the failed capture is
        -- rendered. No transfer dispatch uses the drag focus (it remains nil).
        getCore():TakeFullScreenshot('smart-deposit-failed.png')
        print('[SMART_DEPOSIT] FAIL phase='..phase..' heldDrag='..tostring(holdDrag)..' dragging='..tostring(sourcePane and sourcePane.dragging)..' x='..tostring(sourcePane and sourcePane.draggingX)..' y='..tostring(sourcePane and sourcePane.draggingY)..' '..tostring(err))
        done=true
    end
    since=now
end)
