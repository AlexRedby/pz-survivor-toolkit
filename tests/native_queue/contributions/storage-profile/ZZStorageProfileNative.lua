-- Observational profiling of the installed native/selected-mod UI chain.
-- Setup teleports once; every measured tile crossing uses native walking.
require 'TimedActions/WalkToTimedAction'
require 'TimedActions/ISTimedActionQueue'
local selection=require 'QueueTestSelection'
assert(selection.cases[1]=='walk','bounded walking profile required')
local Client=require 'PZSurvivorWishlist/Client'
local Proximity = require 'BetterContainers/Proximity'
local Options = require 'BetterContainers/_Options'
local Fairness = require 'StorageFairnessNative'
local fairness
local entered, starting, started, done = false, false, false, false
local stage, since = 'setup', 0
local objects, containers, restores = {}, {}, {}
local densities, modes, states = {'sparse','dense'}, {'clean','vanilla'}, {'own-only','both-hidden','loot-collapsed','both-open'}
local densityIndex, modeIndex, stateIndex, phaseNumber = 1, 1, 1, 0
local origin, own, loot, active, action, goal, leg, phaseStart, lastTick, lastX, lastY
local fillIndex, fillTarget = 1, 1
local controls={'off-empty','normal-only','wishlist-only','both-enabled','off-repeat'}
local controlIndex,groundItems=0,{}
local featureSaved,groundOption,addedWanted
local outlineAt=0
local startupChecked, reopen, guardIndex, guard = false, nil, 1, nil
local methodPage, methodPane, methodPageFunction, methodPaneFunction
local lastUIDraw
local refreshBegins, refreshEvent, eventInstalled = {}, nil, false
local function now() return getTimestampMs() end
local function pack(...) return {n=select('#',...),...} end
local function json(value)
    if type(value)=='table' then
        local keys,parts={},{}
        for k in pairs(value) do keys[#keys+1]=k end
        table.sort(keys)
        for _,k in ipairs(keys) do parts[#parts+1]=string.format('%q',k)..':'..json(value[k]) end
        return '{'..table.concat(parts,',')..'}'
    elseif type(value)=='string' then return string.format('%q',value)
    elseif type(value)=='boolean' then return value and 'true' or 'false'
    elseif type(value)=='number' then return tostring(value) end
    return 'null'
end
local function log(kind,value) print('[STORAGE_PROFILE] '..kind..(value and ' '..json(value) or '')) end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()).queue end
local function idle() return #queue()==0 and not getPlayer():hasTimedActions() end
local function restore()
    active=nil
    if eventInstalled then Events.OnRefreshInventoryWindowContainers.Remove(refreshEvent);eventInstalled=false end
    refreshBegins={}
    local unexpected={}
    for i=#restores,1,-1 do
        local entry=restores[i]
        if entry.owner[entry.key]~=entry.wrapper then unexpected[#unexpected+1]=entry.key
        else entry.owner[entry.key]=entry.raw end
    end
    restores={}
    assert(#unexpected==0,'profile wrapper replaced unexpectedly: '..table.concat(unexpected,','))
end
local function observe(owner,key,label,inputs)
    local native=assert(owner[key],'missing installed '..key)
    local raw
    for name,value in pairs(owner) do if name==key then raw=value;break end end
    local wrapper
    wrapper=function(self,...)
        local sample=active and active.callbacks[label]
        if not sample then return native(self,...) end
        -- Input cardinalities are native Java-list size() reads, never item iteration.
        local count,stores=inputs(self)
        sample.calls=sample.calls+1; sample.items=sample.items+count
        sample.maxItems=math.max(sample.maxItems,count)
        sample.maxContainers=math.max(sample.maxContainers,stores)
        local before=now()
        local result=pack(pcall(native,self,...))
        local elapsed=math.max(0,now()-before)
        sample.ms=sample.ms+elapsed; sample.maxMs=math.max(sample.maxMs,elapsed)
        if not result[1] then error(result[2]) end
        return unpack(result,2,result.n)
    end
    restores[#restores+1]={owner=owner,key=key,raw=raw,wrapper=wrapper}
    owner[key]=wrapper
end
local function observeGuardUpdate(pane)
    local native=assert(pane.update)
    local raw
    for key,value in pairs(pane)do if key=='update'then raw=value;break end end
    local wrapper=function(self,...)
        local values=pack(native(self,...))
        if guard and self==pane then guard.nativeUpdates=guard.nativeUpdates+1 end
        return unpack(values,1,values.n)
    end
    restores[#restores+1]={owner=pane,key='update',raw=raw,wrapper=wrapper}
    pane.update=wrapper
end
local function paneInput(pane)
    local inv=pane.inventory
    return inv and inv:getItems():size() or 0, inv and 1 or 0
end
local function pageInput(page) return paneInput(page.inventoryPane) end
local function nearbyInput(page)
    local count,stores,seen=0,0,{}
    for _,button in ipairs(page.backpacks or {}) do
        local inv=button.inventory
        if inv and not seen[inv] and not Proximity.isProximityType(inv:getType()) then
            seen[inv]=true; stores=stores+1; count=count+inv:getItems():size()
        end
    end
    return count,stores
end
local function statesNow()
    return {ownVisible=own:getIsVisible()==true,lootVisible=loot:getIsVisible()==true,
        ownReallyVisible=own:isReallyVisible()==true,lootReallyVisible=loot:isReallyVisible()==true,
        ownCollapsed=own.isCollapsed==true,lootCollapsed=loot.isCollapsed==true,
        ownPaneVisible=own.inventoryPane:getIsVisible()==true,lootPaneVisible=loot.inventoryPane:getIsVisible()==true}
end
local function matchesState(value)
    local state=states[stateIndex]
    return value.ownVisible==(state~='both-hidden') and value.lootVisible==(state=='loot-collapsed' or state=='both-open')
        and not value.ownCollapsed and value.lootCollapsed==(state=='loot-collapsed')
end
local function selectedState(pane)
    local values={}
    for _,row in pairs(pane.selected or {}) do
        if instanceof(row,'InventoryItem') then values[#values+1]='item:'..row:getID()
        elseif type(row)=='table' and row.items then values[#values+1]='group:'..tostring(row.name) end
    end
    table.sort(values)
    local anchor=pane.firstSelect and pane.items and pane.items[pane.firstSelect]
    local anchorName=instanceof(anchor,'InventoryItem') and 'item:'..anchor:getID()
        or type(anchor)=='table' and 'group:'..tostring(anchor.name) or ''
    return {count=#values,signature=table.concat(values,'|'),anchorIndex=pane.firstSelect or 0,anchor=anchorName}
end
local function environment()
    local time,climate,player=getGameTime(),getClimateManager(),getPlayer()
    return {year=time:getYear(),month0=time:getMonth(),day0=time:getDay(),timeOfDay=time:getTimeOfDay(),
        rain=climate:getRainIntensity(),fog=climate:getFogIntensity(),wind=climate:getWindIntensity(),
        cloud=climate:getCloudIntensity(),temperature=climate:getTemperature(),light=climate:getGlobalLightIntensity(),
        width=getCore():getScreenWidth(),height=getCore():getScreenHeight(),gameSpeed=getGameSpeed(),
        actorRootItems=player:getInventory():getItems():size(),actorWeight=player:getInventory():getCapacityWeight(),
        originX=origin.x,originY=origin.y,originZ=origin.z}
end
local function rememberMethods()
    methodPage,methodPane=loot,loot.inventoryPane
    methodPageFunction,methodPaneFunction=loot.refreshBackpacks,loot.inventoryPane.refreshContainer
end
local function headerState()
    local inventory=loot.inventoryPane.inventory
    return {count=loot.totalItems,expected=luautils.countItemsRecursive({luautils.findRootInventory(inventory)}),
        weight=inventory:getCapacityWeight()}
end
local function freshContainerTooltips()
    local checked=0
    if CleanUI_isCleanInventoryUIEnabled() then
        local owned={}
        for _,container in ipairs(containers) do owned[container]=true end
        for _,button in ipairs(loot.backpacks or {}) do
            local container=button.inventory
            if owned[container] then
                local suffix='\n'..round(container:getCapacityWeight(),2)..' / '..container:getEffectiveCapacity(getPlayer())
                assert(type(button.tooltip)=='string' and button.tooltip:sub(-#suffix)==suffix,'expanded container tooltip is missing/stale')
                checked=checked+1
            end
        end
        assert(checked>0,'no reachable owned crate tooltip was checked')
    end
    return {checked=checked,fresh=true}
end
local function presentationState()
    local pane=loot.inventoryPane
    local groups,fast=0,0
    for _,group in ipairs(pane.itemslist or {}) do
        if group.items then groups=groups+1;if group.cleanUIFastWeightActive then fast=fast+1 end end
    end
    local state=loot.toolkitRefreshState
    local pending=state and (state.rowsPending or state.countPending or state.tooltipsPending) or false
    return {pending=pending==true,pendingPane=pending==true and state.pane==pane,
        rowsPending=state and state.rowsPending==true or false,countPending=state and state.countPending==true or false,
        tooltipsPending=state and state.tooltipsPending==true or false,nativeBuildCount=pane.refreshContainerCount or 0,
        builtWeightValues=pane._cleanUIBuiltWeightValues==true,builtWeightField=type(pane._cleanUIBuiltWeightValues),
        groups=groups,fastWeightGroups=fast,selection=selectedState(pane),
        pageRefreshIdentityUnchanged=methodPage==loot and loot.refreshBackpacks==methodPageFunction,
        paneRefreshIdentityUnchanged=methodPane==pane and pane.refreshContainer==methodPaneFunction}
end
local function exactRows(oldItem,newItem)
    local target=Proximity.GetItemContainer(0)
    assert(loot.inventoryPane.inventory==target,'native aggregate selection changed')
    local expected,raw,rows={},{},{}
    local expectedCount,rawCount,rowCount=0,0,0
    local seen={}
    for _,button in ipairs(loot.backpacks or {}) do
        local container=button.inventory
        if container and not seen[container] and not Proximity.isProximityType(container:getType()) then
            seen[container]=true
            for i=0,container:getItems():size()-1 do
                local item=container:getItems():get(i)
                if not expected[item] then expected[item]=true;expectedCount=expectedCount+1 end
            end
        end
    end
    for i=0,target:getItems():size()-1 do
        local item=target:getItems():get(i)
        assert(expected[item] and not raw[item],'aggregate native refs stale/duplicated')
        raw[item]=true;rawCount=rawCount+1
    end
    for _,group in ipairs(loot.inventoryPane.itemslist or {}) do
        for _,item in ipairs(group.items or {}) do
            if instanceof(item,'InventoryItem') then
                assert(expected[item],'row references a removed/unreachable native item')
                -- Native group header repeats the first physical child.
                if not rows[item] then rows[item]=true;rowCount=rowCount+1 end
            end
        end
    end
    assert(expectedCount>0 and rawCount==expectedCount and rowCount==expectedCount,'raw/row physical-reference coverage differs')
    for item in pairs(expected) do assert(raw[item] and rows[item],'current native physical item missing') end
    if oldItem then assert(not raw[oldItem] and not rows[oldItem] and raw[newItem] and rows[newItem],'same-count replacement is stale') end
    return {raw=rawCount,rows=rowCount,exact=true}
end
local function sourceCounts()
    local count=0
    for _,container in ipairs(containers) do count=count+container:getItems():size() end
    return count
end
local function area(player)
    local square=player:getSquare()
    for radius=0,18 do for dx=-radius,radius do for dy=-radius,radius do
        if math.abs(dx)==radius or math.abs(dy)==radius then
            local x,y,z=square:getX()+dx,square:getY()+dy,square:getZ()
            local clear=true
            for a=-4,4 do for b=-2,2 do
                local sq=getCell():getGridSquare(x+a,y+b,z)
                if not sq or not sq:isFree(false) or sq:getRoom() or sq:getObjects():size()>1 then clear=false end
            end end
            if clear then
                player:teleportTo(x-2+0.5,y+0.5,z)
                return {x=x,y=y,z=z}
            end
        end
    end end end
    error('No clear loaded 9x5 native corridor')
end
local function features()
    return {normal=PZSurvivorToolkit.Settings.isEnabled(),ground=PZSurvivorWishlist.Settings.groundEnabled(),
        wanted=Client.hasWanted(0),radius=PZSurvivorToolkit.Settings.getRadius()}
end
local function groundSetting(value)
    if groundOption:getValue()~=value then
        groundOption:setValue(value)
        if type(groundOption.onChangeApply)=='function' then groundOption.onChangeApply(groundOption) end
        local options=PZAPI.ModOptions:getOptions('PZSurvivorWishlist')
        if type(options.apply)=='function' then options:apply() end
        PZAPI.ModOptions:save()
    end
end
local function setFeatures(name)
    local wanted=name=='wishlist-only' or name=='both-enabled'
    if wanted and not addedWanted then
        assert(Client.addItem(0,'Base.Nails',1),'public Wishlist add rejected');addedWanted=true
    elseif not wanted and addedWanted then
        assert(Client.edit(0,'remove',{fullType='Base.Nails'}),'public Wishlist remove rejected');addedWanted=false
    end
    local normal=name=='normal-only' or name=='both-enabled'
    if PZSurvivorToolkit.Settings.isEnabled()~=normal then PZSurvivorToolkit.Settings.toggle() end
    groundSetting(name~='normal-only')
    local actual=features()
    assert(actual.normal==normal and actual.wanted==wanted and actual.ground==(name~='normal-only'),'public highlight/Wishlist control did not commit')
end
local function restoreFeatures()
    if not featureSaved then return end
    if addedWanted then assert(Client.edit(0,'remove',{fullType='Base.Nails'}));addedWanted=false end
    if PZSurvivorToolkit.Settings.isEnabled()~=featureSaved.normal then PZSurvivorToolkit.Settings.toggle() end
    groundSetting(featureSaved.ground)
    assert(PZSurvivorToolkit.Settings.isEnabled()==featureSaved.normal
        and groundOption:getValue()==featureSaved.ground and Client.hasWanted(0)==false,'fixture feature settings/list were not restored')
end
local function outlined()
    local highlights,outlines=0,0
    for _,item in ipairs(groundItems) do
        local object=assert(item:getWorldItem(),'owned ground object disappeared')
        if object:isHighlighted(0) then highlights=highlights+1 end
        if object:isOutlineHighlight(0) then outlines=outlines+1 end
    end
    return highlights,outlines
end
local function fillGround()
    for _=1,10 do
        if #groundItems>=200 then break end
        local i=#groundItems
        local square=assert(getCell():getGridSquare(origin.x-2+(i%5),origin.y,origin.z))
        local item=assert(square:AddWorldInventoryItem('Base.Nails',0.15+(math.floor(i/5)%7)*0.1,0.2+(math.floor(i/35)%6)*0.1,0))
        assert(item:getWorldItem() and item:getScriptItem():isWorldRender(),'native ground Nail is not renderable')
        groundItems[#groundItems+1]=item
    end
    if #groundItems==200 then
        local seen={}
        for _,item in ipairs(groundItems) do local object=item:getWorldItem();assert(not seen[object],'ground items merged');seen[object]=true end
        log('GROUND',{objects=200,kind='Base.Nails',native=true})
        controlIndex=1;densityIndex=2;modeIndex=1;stateIndex=2;stage='control-configure';since=now()
    end
end
local function setup()
    assert(not isClient() and not isServer(),'SP required')
    local permissions=Options.getEffectivePermissions()
    assert(permissions and permissions.proximityActive and not permissions.corpseOnly and not permissions.dualMode,'ordinary BC proximity must already be enabled')
    local player=getPlayer(); player:setGodMod(true); player:setGhostMode(true)
    if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
    if getPlayerInfoPanel and getPlayerInfoPanel(0) then getPlayerInfoPanel(0):setVisible(false) end
    origin=area(player)
    Client.sync(0)
    assert(Client.selected(0) and not Client.hasWanted(0),'fresh disposable Wishlist must be ready and empty')
    groundOption=PZAPI.ModOptions:getOptions('PZSurvivorWishlist'):getOption('Ground')
    featureSaved=features()
    for x=-3,2 do for _,y in ipairs({-1,1}) do
        local square=assert(getCell():getGridSquare(origin.x+x,origin.y+y,origin.z))
        local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
        object:setIsContainer(true)
        local container=assert(object:getContainer()); container:setType('crate'); container:setCapacity(10000); container:setExplored(true)
        square:AddSpecialObject(object)
        objects[#objects+1]=object; containers[#containers+1]=container
    end end
    log('SETUP',{native=true,crates=12,itemType='Base.Nails',clock='getTimestampMs',resolutionMs=1,
        movement='ISWalkToTimedAction',setupTeleport=true,video=false,proximity=true,discoveryScope='native-begin-end-events'})
end
local function fill()
    local budget=120
    while fillIndex<=#containers and budget>0 do
        local container=containers[fillIndex]
        while container:getItems():size()<fillTarget and budget>0 do
            assert(container:AddItem('Base.Nails'),'native Nails allocation failed'); budget=budget-1
        end
        if container:getItems():size()==fillTarget then fillIndex=fillIndex+1 end
    end
    if fillIndex>#containers then
        assert(sourceCounts()==(densityIndex==1 and 12 or 4800),'source crate cardinality differs')
        stage=not startupChecked and 'startup-configure' or 'configure';since=now()
    end
end
local function configure(startup)
    assert(idle(),'previous route did not drain')
    if not startup and CleanUI_isCleanInventoryUIEnabled()~=(modeIndex==1) then CleanUI_setCleanInventoryUIEnabled(modeIndex==1) end
    own=getPlayerInventory(0); loot=getPlayerLoot(0)
    for _,page in ipairs({own,loot}) do
        page:setVisible(true); page.isCollapsed=false; page:clearMaxDrawHeight(); page:setPinned()
        page:setY(50); page:setWidth(590); page:setHeight(740)
        page.inventoryPane:setMode('details'); page.inventoryPane:setVisible(true)
        page:refreshBackpacks()
    end
    own:setX(30); loot:setX(640)
    local target=Proximity.GetItemContainer(0)
    local selected=false
    for _,button in ipairs(loot.backpacks) do
        if button.inventory==target then
            if loot.inventoryPane.inventory~=target then loot:onBackpackClick(button) end
            selected=true;break
        end
    end
    assert(selected and loot.inventoryPane.inventory==target,'native BC aggregate not selected')
    local requested=startup and 'both-open' or states[stateIndex]
    if requested=='loot-collapsed' then loot:collapse();loot:collapseNow() end
    if requested=='own-only' or requested=='both-hidden' then loot:setVisible(false) end
    if requested=='both-hidden' then own:setVisible(false) end
    if not startup then assert(matchesState(statesNow()),'requested native page state not established') end
    stage=startup and 'startup-warmup' or 'warmup';since=now()
end
local function metric() return {calls=0,items=0,maxItems=0,maxContainers=0,ms=0,maxMs=0} end
-- Passive engine lifecycle events preserve refreshBackpacks method identity,
-- including the selected product's ownership/coalescing checks. The measured
-- body excludes work before begin and the installed owners' opaque outer tail.
refreshEvent=function(page,phase)
    if not active then return end
    local label=page==own and 'ownDiscoveryBody' or page==loot and 'lootDiscoveryBody'
    if not label then return end
    local stack=refreshBegins[page] or {};refreshBegins[page]=stack
    if phase=='begin' then
        local count,stores=pageInput(page)
        local sample=active.callbacks[label]
        sample.calls=sample.calls+1;sample.items=sample.items+count
        sample.maxItems=math.max(sample.maxItems,count);sample.maxContainers=math.max(sample.maxContainers,stores)
        stack[#stack+1]=now()
    elseif phase=='end' then
        assert(#stack>0,'discovery end without observed begin')
        local elapsed=math.max(0,now()-stack[#stack]);stack[#stack]=nil
        local sample=active.callbacks[label]
        sample.ms=sample.ms+elapsed;sample.maxMs=math.max(sample.maxMs,elapsed)
    end
end
local function walk()
    leg=leg+1
    local x=leg%2==1 and origin.x+2 or origin.x-2
    goal=assert(getCell():getGridSquare(x,origin.y,origin.z))
    action=ISWalkToTimedAction:new(getPlayer(),goal)
    assert(action.Type=='ISWalkToTimedAction','native walking action required')
    ISTimedActionQueue.add(action)
end
local function beginPhase()
    rememberMethods()
    phaseNumber=phaseNumber+1
    active={index=phaseNumber,density=densities[densityIndex],mode=modes[modeIndex],state=states[stateIndex],
        sourceCrates=#containers,sourceItems=sourceCounts(),warmupMs=2000,clockResolutionMs=1,
        control=controlIndex>0 and controls[controlIndex] or 'ordinary',features=features(),groundObjects=#groundItems,
        highlight={sampleTicks=0,maxTracked=0,scanTicks=0,clearTicks=0,outlineSamples=0,maxOwnedHighlighted=0,maxOwnedOutlined=0},
        callbacks={},ticks={},uiIntervals={},pendingTicks=0,movementTicks=0,tileChanges=0,distance=0,reached=0,stateViolations=0,
        initialState=statesNow(),initialPresentation=presentationState(),headerInitial=headerState(),environmentInitial=environment(),observedNearbyMaxItems=0,observedNearbyMaxContainers=0}
    for _,name in ipairs({'ownDiscoveryBody','lootDiscoveryBody','ownUpdateItemCount','lootUpdateItemCount','bcOnButtonsAdded'}) do active.callbacks[name]=metric() end
    Events.OnRefreshInventoryWindowContainers.Add(refreshEvent);eventInstalled=true
    observe(own,'updateItemCount','ownUpdateItemCount',pageInput)
    observe(loot,'updateItemCount','lootUpdateItemCount',pageInput)
    observe(Proximity,'OnButtonsAdded','bcOnButtonsAdded',nearbyInput)
    phaseStart=now();lastTick=phaseStart;lastUIDraw=phaseStart;outlineAt=phaseStart
    local player=getPlayer(); lastX=player:getX();lastY=player:getY()
    leg=0;walk();stage='measure'
end
local function distribution(values)
    table.sort(values)
    local n=#values
    assert(n>=60,'insufficient tick samples')
    return {samples=n,p50=values[math.ceil(n*0.50)],p95=values[math.ceil(n*0.95)],max=values[n]}
end
local function cleanup()
    restoreFeatures()
    local fairnessRemoved=fairness and fairness:cleanup() or 0
    for _,item in ipairs(groundItems) do
        local object=assert(item:getWorldItem());object:getSquare():transmitRemoveItemFromSquare(object)
    end
    for _,object in ipairs(objects) do object:getSquare():RemoveTileObject(object) end
    log('RESTORED',{wrappers=true,cratesRemoved=12,groundRemoved=#groundItems,fairnessRemoved=fairnessRemoved,features=true,phases=phaseNumber})
    log('COMPLETE');done=true;since=now()
end
local function nextPhase()
    if controlIndex>0 then
        controlIndex=controlIndex+1
        if controlIndex<=#controls then stage='control-configure' else stage='guard-configure' end
        since=now();return
    end
    stateIndex=stateIndex+1
    if stateIndex>#states then stateIndex=1;modeIndex=modeIndex+1 end
    if modeIndex>#modes then
        modeIndex=1;densityIndex=densityIndex+1
        if densityIndex>#densities then stage='fill-ground';since=now();return end
        fillTarget=400;fillIndex=1;stage='fill';return
    end
    stage='configure';since=now()
end
local function showLoot()
    loot.isCollapsed=false;loot:clearMaxDrawHeight();loot:setPinned();loot:setVisible(true)
end
local function finishPhase()
    assert(active.reached>=4 and active.distance>=14 and active.movementTicks>=30 and active.tileChanges>=12,'actual native movement evidence insufficient')
    assert(active.stateViolations==0 and matchesState(statesNow()),'page state drifted during native traversal')
    assert(sourceCounts()==active.sourceItems,'owned source items changed during measurement')
    for _,stack in pairs(refreshBegins) do assert(#stack==0,'unpaired native discovery lifecycle') end
    active.discoveryPending=0
    active.elapsedMs=now()-phaseStart;active.tickIntervalsMs=distribution(active.ticks);active.ticks=nil
    active.uiDrawIntervalsMs=distribution(active.uiIntervals);active.uiIntervals=nil
    active.finalState=statesNow();active.finalPresentation=presentationState();active.headerFinal=headerState();active.environmentFinal=environment();active.nativeActions=leg;active.teleportsDuringMeasurement=0
    active.nativeBuildDelta=(active.finalPresentation.nativeBuildCount-active.initialPresentation.nativeBuildCount)%10001
    assert(active.initialPresentation.selection.signature==active.finalPresentation.selection.signature
        and active.initialPresentation.selection.anchor==active.finalPresentation.selection.anchor,'selection/anchor changed during measured native walking')
    local result=active
    restore();log('PHASE',result)
    local reachable={}
    for _,button in ipairs(loot.backpacks or {}) do reachable[button.inventory]=true end
    local source
    for _,container in ipairs(containers) do if reachable[container] then source=container;break end end
    assert(source and source:getItems():size()>0,'no currently reachable owned crate for replacement')
    local before=presentationState()
    local old=source:getItems():get(source:getItems():size()-1)
    source:Remove(old)
    local fresh=assert(source:AddItem('Base.Nails'))
    assert(fresh~=old and sourceCounts()==result.sourceItems,'same-count native replacement failed')
    reopen={index=result.index,old=old,new=fresh,before=before,sourceItems=result.sourceItems}
    -- The native event marks page renderDirty. It models a normal container
    -- invalidation after direct test setup, identically in baseline/candidate.
    triggerEvent('OnContainerUpdate',source:getParent())
    if result.state=='loot-collapsed' then
        -- Native update owns pin expansion; do not call setVisible or clear collapse here.
        reopen.route='native-pin';loot:setPinned();stage='reopen-pin-wait'
    else
        reopen.route='show';showLoot();stage='reopen-draw'
    end
    since=now()
end
local function measure()
    local time=now();local player=getPlayer()
    assert(time-phaseStart<60000,'phase native walk deadline exceeded')
    local refresh=loot.toolkitRefreshState
    if refresh and (refresh.rowsPending or refresh.countPending or refresh.tooltipsPending) then active.pendingTicks=active.pendingTicks+1 end
    local status=PZSurvivorToolkit.Highlighter.getStatus()
    assert(not status.lastError,'native highlighter reported an error')
    local h=active.highlight;h.sampleTicks=h.sampleTicks+1;h.maxTracked=math.max(h.maxTracked,status.highlightedObjects)
    if status.scanning then h.scanTicks=h.scanTicks+1 end
    if status.clearing then h.clearTicks=h.clearTicks+1 end
    if #groundItems>0 and time>=outlineAt then
        local highlights,outlines=outlined()
        h.outlineSamples=h.outlineSamples+1;h.maxOwnedHighlighted=math.max(h.maxOwnedHighlighted,highlights);h.maxOwnedOutlined=math.max(h.maxOwnedOutlined,outlines)
        outlineAt=time+1000
    end
    active.ticks[#active.ticks+1]=math.max(0,time-lastTick);lastTick=time
    local x,y=player:getX(),player:getY()
    local distance=math.sqrt((x-lastX)^2+(y-lastY)^2)
    assert(distance<1.5,'unexpected position jump during measurement')
    active.distance=active.distance+distance
    if math.floor(x)~=math.floor(lastX) or math.floor(y)~=math.floor(lastY) then active.tileChanges=active.tileChanges+1 end
    if player:isPlayerMoving() then active.movementTicks=active.movementTicks+1 end
    lastX=x;lastY=y
    if not matchesState(statesNow()) then active.stateViolations=active.stateViolations+1 end
    -- This observer loops only over nearby container buttons, never their items.
    local items,stores=nearbyInput(loot)
    active.observedNearbyMaxItems=math.max(active.observedNearbyMaxItems,items)
    active.observedNearbyMaxContainers=math.max(active.observedNearbyMaxContainers,stores)
    assert(action.result~=BehaviorResult.Failed,'native walk failed')
    if idle() then
        assert(action.result==BehaviorResult.Succeeded,'native action drained without successful path')
        assert(math.floor(x)==goal:getX() and math.floor(y)==goal:getY(),'native action missed destination')
        active.reached=active.reached+1
        -- End only at the original corridor endpoint; every phase shares its route.
        if leg>=4 and leg%2==0 and time-phaseStart>=12000 then finishPhase() else walk() end
    end
end
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
    if active then local time=now();active.uiIntervals[#active.uiIntervals+1]=math.max(0,time-lastUIDraw);lastUIDraw=time end
    if started and isIngameState() and isGamePaused() then setGameSpeed(1) end
    if not entered or starting or isIngameState() then return end
    starting=true;getCore():setOptionPauseOnFocusloss(false)
    getWorld():setGameMode('Sandbox');getWorld():setWorld('StorageProfileNative');getWorld():setMap('Muldraugh, KY')
    MainScreen.instance:setDefaultSandboxVars()
    for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2}) do getSandboxOptions():getOptionByName(name):setValue(value) end
    getSandboxOptions():toLua()
    MainScreen.instance.createWorld=true
    MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
    MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
    MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
local function failure(problem)
    local actual=own and loot and statesNow() or nil
    local requested=states[stateIndex]
    local selectionGuard
    if guard and loot then
        local ok,value=pcall(function()
            return {mode=guard.mode,itemId=tostring(guard.item:getID()),before=guard.before,
                hidden=guard.hidden,after=presentationState(),renderedRows=#(loot.inventoryPane.items or {})}
        end)
        selectionGuard=ok and value or {error=tostring(value)}
    end
    local restored,restoreError=pcall(restore)
    local featureRestored,featureError=pcall(restoreFeatures)
    log('FAIL',{stage=stage,error=tostring(problem),requested=requested,actualState=actual,selectionGuard=selectionGuard,wrappersRestored=restored,restoreError=tostring(restoreError),featuresRestored=featureRestored,featureError=tostring(featureError),groundObjects=#groundItems})
    done=true;since=now()
end
Events.OnPostUIDraw.Add(function()
    if done or not started then return end
    local ok,problem=pcall(function()
        if stage=='startup-draw' then
            rememberMethods()
            local refs=exactRows()
            log('STARTUP',{untoggled=true,mode=CleanUI_isCleanInventoryUIEnabled() and 'clean' or 'vanilla',
                physical=refs,presentation=presentationState()})
            startupChecked=true
            stage='configure'
            since=now()
        elseif stage=='reopen-draw' or stage=='reopen-pin-wait' and not loot.isCollapsed then
            local refs=exactRows(reopen.old,reopen.new)
            local after=presentationState()
            local header=headerState()
            assert(header.count==header.expected,'reopened visible header count is stale')
            assert(not after.pending,'pending rows remain after normal show/draw')
            assert(after.selection.signature==reopen.before.selection.signature and after.selection.anchor==reopen.before.selection.anchor,'reopen discarded selection/anchor')
            log('REOPEN',{index=reopen.index,replaced=true,sourceItems=reopen.sourceItems,
                physical=refs,oldId=tostring(reopen.old:getID()),newId=tostring(reopen.new:getID()),pendingBefore=reopen.before.pending,pendingAfter=after.pending,
                before=reopen.before,after=after,normalPostDraw=true,route=reopen.route,header=header,tooltips=freshContainerTooltips()})
            reopen=nil;nextPhase()
        elseif stage=='guard-select-draw' then
            local pane=loot.inventoryPane
            local selected,index
            for i,row in ipairs(pane.items or {}) do
                if instanceof(row,'InventoryItem') then selected=row;index=i;break end
            end
            assert(selected,'expanded native child required for selection guard')
            pane:restoreSelection({[selected]='item'});pane.firstSelect=index
            guard={item=selected,before=presentationState(),mode=modes[guardIndex],nativeUpdates=0}
            assert(guard.before.selection.count>0 and guard.before.selection.anchor~='','nonempty native selection/anchor required')
            loot:setVisible(false)
            -- This is an ordinary explicit discovery request outside timing.
            -- The product must retain its conservative non-idle fallback.
            loot:refreshBackpacks()
            guard.hidden=presentationState()
            assert(not guard.hidden.pending,'selected hidden rows were deferred')
            showLoot();observeGuardUpdate(pane);stage='guard-check-draw';since=now()
        elseif stage=='guard-check-draw' and guard.nativeUpdates>0 then
            local refs=exactRows()
            local after=presentationState()
            assert(after.selection.signature==guard.before.selection.signature and after.selection.anchor==guard.before.selection.anchor,'selection guard lost native selection or Shift anchor')
            assert(not after.pending,'selection guard left pending presentation')
            log('SELECTION',{mode=guard.mode,before=guard.before,hidden=guard.hidden,after=after,physical=refs,preserved=true,nativeUpdates=guard.nativeUpdates})
            restore()
            guardIndex=guardIndex+1
            if guardIndex>#modes then
                own:setVisible(false);loot:collapse();loot:collapseNow();loot:setVisible(false)
                fairness=Fairness.new(origin,setFeatures,features,log);stage='fairness'
            else stage='guard-configure';since=now() end
        end
    end)
    if not ok then failure(problem) end
end)
Events.OnGameStart.Add(function() started=true;since=now() end)
Events.OnTick.Add(function()
    if not started or not isIngameState() then return end
    if done then if now()-since>3000 then getCore():quitToDesktop() end;return end
    local ok,problem=pcall(function()
        if stage=='measure' then measure()
        elseif stage=='fairness' then if fairness:tick()then cleanup()end
        elseif stage=='fill' then fill()
        elseif stage=='fill-ground' then fillGround()
        elseif stage=='reopen-draw' or stage=='reopen-pin-wait' or stage=='startup-draw' or stage=='guard-select-draw' or stage=='guard-check-draw' then
            assert(now()-since<10000,'normal draw freshness deadline exceeded')
        elseif now()-since>=2000 then
            if stage=='setup' then setup();stage='fill'
            elseif stage=='startup-configure' then configure(true)
            elseif stage=='startup-warmup' then stage='startup-draw';since=now()
            elseif stage=='configure' then configure()
            elseif stage=='control-configure' then setFeatures(controls[controlIndex]);configure()
            elseif stage=='warmup' then beginPhase()
            elseif stage=='guard-configure' then
                if CleanUI_isCleanInventoryUIEnabled()~=(guardIndex==1) then CleanUI_setCleanInventoryUIEnabled(guardIndex==1) end
                stage='guard-settle';since=now()
            elseif stage=='guard-settle' then
                -- The mode switch may replace/rebind native pages asynchronously.
                -- Reacquire them after the ordinary two-second settle.
                modeIndex=guardIndex;stateIndex=4;configure();rememberMethods()
                local pane=loot.inventoryPane
                for _,group in ipairs(pane.itemslist or {}) do if group.items then pane.collapsed[group.name]=false end end
                pane:refreshContainer();stage='guard-child-settle';since=now()
            elseif stage=='guard-child-settle' then
                assert(loot:isReallyVisible() and not loot.isCollapsed,'settled native loot page is not actually visible')
                stage='guard-select-draw';since=now()
            end
        end
    end)
    if not ok then failure(problem) end
end)
