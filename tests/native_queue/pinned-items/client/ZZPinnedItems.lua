local config = require 'QueueTestSelection'
if config.cases[1]=='selection' then
    require('PinnedItemsSelection').start(config)
    return
end
local pins = require 'BetterContainers/Upgrades/PinnedItems'
local F = require 'PinnedItemsFixture'
local mp={active=config.kind=='mp'}
local scenes = {'startup-order'}
local hasOrganizedCategories=getActivatedMods():contains('organizedCategories_core')
local hasCleanUI=getActivatedMods():contains('CleanUI')
if hasOrganizedCategories and hasCleanUI then scenes[#scenes+1]='organized-item-pin' end
for _, name in ipairs({'clean-name','clean-category','clean-weight','clean-name-desc',
    'clean-category-desc','clean-weight-desc','clean-category-filter'}) do scenes[#scenes+1]=name end
if hasOrganizedCategories then scenes[#scenes+1]='category-split' end
if hasCleanUI then
    for _, name in ipairs({'clean-search-match','clean-search','vanilla-name','vanilla-category','vanilla-weight'}) do
        scenes[#scenes+1]=name
    end
end
local vehicle, container, target, originalOrder, selectedItem, countBefore
local accessAttempt=0
local scene, phase, nextAt, started, done = 1, 'setup', 0, false, false
local failures, pinnedOrder, selectedPreserved, expectedFirst, categoryName, categoryCount
local provider, organizedPinned, splitRows, splitCategories, expectedFirstCategory
local pinnedCategories, originalCategories
local searchText, matchingCount, allRowsMatch, targetTypeCount
local activeClass, comparatorIdentity, comparatorName, searchState, searchCategoryState, searchModeState
local toolkitCategoryState, toolkitTagState, toolkitTagRuleState

local function place(x,y)
    local player=getPlayer()
    -- teleportTo floors coordinates; the native trunk access area needs the exact position.
    player:teleportTo(math.floor(x),math.floor(y),0)
    player:setX(x);player:setY(y);player:setNextX(x);player:setNextY(y);player:setLastX(x);player:setLastY(y)
end

local quote=F.quote
local function order(pane)
    local result = {}
    for _, group in ipairs(pane.itemslist) do
        if group.items and group.items[1] then result[#result+1]=group.items[1]:getFullType() end
    end
    return result
end
local function rowCategories(pane)
    local result={}
    for _, group in ipairs(pane.itemslist) do
        if group.items and group.items[1] then
            result[#result+1]=group.cat and quote(group.cat) or 'null'
        end
    end
    return table.concat(result,',')
end
local function typeCount(fullType)
    local count=0
    for index=0,container:getItems():size()-1 do
        if container:getItems():get(index):getFullType()==fullType then count=count+1 end
    end
    return count
end
local function activeClassName(pane)
    local class=getmetatable(pane)
    if class==CleanUI_Clean_ISInventoryPane then return 'CleanUI_Clean_ISInventoryPane' end
    if class==CleanUI_Vanilla_ISInventoryPane then return 'CleanUI_Vanilla_ISInventoryPane' end
    return 'ISInventoryPane'
end
local function comparatorNameOf(pane)
    if not pane.itemSortFunc then return 'nil','nil' end
    for name, value in pairs(ISInventoryPane) do
        if value==pane.itemSortFunc then return tostring(value),name end
    end
    return tostring(pane.itemSortFunc), 'unknown'
end
local function activeRows(pane)
    return pane.toolkitUnfilteredRows or pane.itemslist
end
local function configureSearchMatch(pane)
    local candidates, rows = {}, activeRows(pane)
    for _, group in ipairs(rows) do
        local name=tostring(group.name)
        local index=1
        while index<=#name do
            local byte=name:byte(index)
            local length=byte>=240 and 4 or byte>=224 and 3 or byte>=192 and 2 or 1
            candidates[name:sub(index,index+length-1)]=true
            index=index+length
        end
    end
    local best, bestCount
    for character in pairs(candidates) do
        pane.searchText=character
        pane:refreshContainer()
        rows=activeRows(pane)
        local count=0
        for _, group in ipairs(rows) do if group.matchesSearch then count=count+1 end end
        if not bestCount or count>bestCount then best,bestCount=character,count end
    end
    assert(best and bestCount>=2,'No search character matches multiple fixture item types')
    pane.searchMode,pane.searchText='name',best
    pane:refreshContainer()
    rows=pane.itemslist
    local count, all, sawNonMatch=0,true,false
    for _, group in ipairs(rows) do
        if group.matchesSearch then
            count=count+1
            if sawNonMatch then all=false end
        else sawNonMatch=true end
    end
    assert(count>=2 and all,'Toolkit search did not place matching rows first')
    return best,count,all
end
local function configureCategoryFilter(pane)
    local counts, screwCategory = {}, nil
    for _, group in ipairs(pane.itemslist) do
        if group.type~='separator' and group.cat then
            counts[group.cat]=(counts[group.cat] or 0)+1
            if group.items[1]:getFullType()=='Base.Screwdriver' then screwCategory=group.cat end
        end
    end
    assert(screwCategory and (counts[screwCategory] or 0)>=2,'No Toolkit category contains the duplicate tool and another type')
    pane.toolkitCategory=screwCategory
    pane:refreshContainer()
    pane:renderdetails(false)
    for _, group in ipairs(pane.itemslist) do
        assert(group.cat==screwCategory,'Toolkit category filter retained another category')
    end
    assert(#pane.itemslist>=2,'Toolkit category filter retained fewer than two item types')
    return screwCategory,#pane.itemslist
end
local function configureDescending(pane, kind)
    if kind=='weight' then
        pane:sortByWeight(false)
        assert(pane.itemSortFunc==ISInventoryPane.itemSortByWeightDesc,'Native weight callback did not select descending')
        return
    end
    local ascending=kind=='name' and ISInventoryPane.itemSortByNameInc or ISInventoryPane.itemSortByCatInc
    local descending=kind=='name' and ISInventoryPane.itemSortByNameDesc or ISInventoryPane.itemSortByCatDesc
    local callback=kind=='name' and pane.sortByName or pane.sortByType
    local header=kind=='name' and pane.nameHeader or pane.typeHeader
    if pane.itemSortFunc~=ascending then callback(pane,header) end
    assert(pane.itemSortFunc==ascending,'Native sort callback could not establish ascending order')
    callback(pane,header)
    assert(pane.itemSortFunc==descending,'Native sort callback did not select descending order')
end
local function check(ok, reason)
    if not ok then failures[#failures+1]=reason end
end
local function find(menu, name)
    for _, option in ipairs(menu.options) do
        if option.name==name then return option end
        if option.subOption then
            local child=menu:getSubMenu(option.subOption)
            local found=child and find(child,name)
            if found then return found end
        end
    end
end
local function dispatch(item, unpin, pane)
    local menu=assert(ISInventoryPaneContextMenu.createMenu(0,false,{item},200,160,pane),'No native context menu')
    local key=unpin and 'ContextMenu_BetterContainers_UnpinItemType' or 'ContextMenu_BetterContainers_PinItemType'
    local label=getTextOrNull(key) or (unpin and 'Unpin Item Type' or 'Pin Item Type')
    local option=assert(find(menu,label),'Missing menu option '..label)
    assert(option.onSelect and not option.notAvailable,'Pin menu option unavailable')
    option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6)
    menu:hideAndChildren()
    assert(pins.isFavourite(item:getFullType())==not unpin,'Context-menu pin state did not change')
end
local function spawn()
    if mp.active then
        if not mp.requested then
            mp.requested=true
            sendClientCommand('PinnedItemsTest','prepare',{})
        end
        if not mp.fixture then return false end
        if not mp.placed then place(mp.fixture.x,mp.fixture.y);mp.placed=true end
        vehicle=getVehicleById(mp.fixture.truckId)
        if not vehicle or not vehicle:getSquare() then return false end
        container=assert(vehicle:getPartById('TruckBed'):getItemContainer())
        return true
    end
    vehicle,container=F.spawn(getPlayer())
    local area=assert(vehicle:getAreaCenter(vehicle:getPartById('TruckBed'):getArea()))
    place(area:getX(),area:getY())
    return true
end
local function paneForScene()
    local page=getPlayerLoot(0)
    page:setVisible(true);page.isCollapsed=false;page:setPinned()
    page:refreshBackpacks()
    page:selectButtonForContainer(container)
    page:setForceSelectedContainer(container,60000)
    if page.inventoryPane.inventory~=container then
        local types={}
        for _, button in ipairs(page.backpacks) do types[#types+1]=button.inventory:getType() end
        local player=getPlayer()
        print('[PIN_ITEMS] ACCESS player='..player:getX()..','..player:getY()..' vehicle='..vehicle:getX()..','..vehicle:getY()..' inArea='..tostring(vehicle:isInArea('TruckBed',player))..' buttons='..table.concat(types,','))
        return nil
    end
    page:setX(500);page:setY(80);page:setWidth(740);page:setHeight(550)
    local pane=page.inventoryPane
    pane:setMode('details');pane:setYScroll(0)
    return pane
end
Events.OnServerCommand.Add(function(module,command,args)
    if module~='PinnedItemsTest' then return end
    local ok,err=pcall(function()
        if command=='fixture' then mp.fixture=args
        elseif command=='start' then mp.started=true
        elseif command=='peer-checked' then mp.peerChecked=true
        elseif command=='complete' then mp.complete=true
        elseif command=='probe' then
            assert(vehicle and vehicle:getId()==args.truckId and F.signature(container)==args.itemSignature)
            local absent=not pins.isFavourite(args.target)
            if OrganizedCategories and OrganizedCategories.isItemPinned then
                for index=0,container:getItems():size()-1 do
                    local item=container:getItems():get(index)
                    if item:getFullType()==args.target and OrganizedCategories.isItemPinned(0,item) then absent=false end
                end
            end
            assert(absent,'Another client pin changed this client pin state')
            print('[PIN_ITEMS] PEER {"actor":'..quote(getPlayer():getUsername())..',"pinner":'..quote(args.pinner)..
                ',"provider":'..quote(args.provider)..',"truckId":'..quote(vehicle:getId())..',"target":'..quote(args.target)..
                ',"pinAbsent":true,"itemSignature":'..quote(F.signature(container))..'}')
            sendClientCommand('PinnedItemsTest','peer-checked',{pinner=args.pinner,provider=args.provider,target=args.target,pinAbsent=absent,itemSignature=F.signature(container)})
        else error('Unknown fixture server command '..tostring(command)) end
    end)
    if not ok then done=true;print('[PIN_ITEMS] FAIL server-command '..tostring(err)) end
end)
local function emit()
    local rows={}
    for _, fullType in ipairs(pinnedOrder) do rows[#rows+1]=quote(fullType) end
    print('[PIN_ITEMS] RESULT {'..
        '"scene":'..quote(scenes[scene])..',"status":'..quote(#failures==0 and 'passed' or 'failed')..
        ',"reason":'..quote(table.concat(failures,'; '))..',"truckId":'..quote(vehicle:getId())..
        ',"mp":'..tostring(mp.active)..',"actor":'..quote(getPlayer():getUsername())..
        ',"onlineId":'..getPlayer():getOnlineID()..',"itemSignature":'..quote(F.signature(container))..
        ',"containerType":'..quote(container:getType())..',"rowOrder":['..table.concat(rows,',')..']'..
        ',"selectedPreserved":'..tostring(selectedPreserved)..',"itemCountBefore":'..countBefore..
        ',"itemCountAfter":'..container:getItems():size()..',"target":'..quote(target:getFullType())..
        ',"expectedFirst":'..quote(expectedFirst or target:getFullType())..
        ',"targetTypeCount":'..targetTypeCount..
        ',"filterCategory":'..(categoryName and quote(categoryName) or 'null')..
        ',"filteredTypeCount":'..(categoryCount or 0)..',"searchText":'..(searchText and quote(searchText) or 'null')..
        ',"matchingTypeCount":'..(matchingCount or 0)..',"allRowsMatch":'..tostring(allRowsMatch==true)..
        ',"activeClass":'..quote(activeClass)..',"comparatorIdentity":'..quote(comparatorIdentity)..
        ',"comparatorName":'..quote(comparatorName)..',"searchState":'..(searchState and quote(searchState) or 'null')..
        ',"searchCategoryState":'..(searchCategoryState and quote(searchCategoryState) or 'null')..
        ',"searchModeState":'..(searchModeState and quote(searchModeState) or 'null')..
        ',"toolkitCategoryState":'..(toolkitCategoryState and quote(toolkitCategoryState) or 'null')..
        ',"toolkitTagState":'..(toolkitTagState and quote(toolkitTagState) or 'null')..
        ',"toolkitTagRuleActive":'..tostring(toolkitTagRuleState==true)..
        ',"provider":'..quote(provider or 'BetterContainers')..
        ',"organizedPinned":'..tostring(organizedPinned==true)..
        ',"splitRows":'..(splitRows or 0)..',"splitCategories":['..(splitCategories or '')..']'..
        ',"rowCategories":['..(pinnedCategories or '')..']'..
        ',"expectedFirstCategory":'..(expectedFirstCategory and quote(expectedFirstCategory) or 'null')..'}')
end
local function unpinCurrent()
    local pane=getPlayerLoot(0).inventoryPane
    if scenes[scene]=='organized-item-pin' then
        local page=getPlayerLoot(0)
        local button=assert(page.ocItemPinButton,'Organized Categories pin button disappeared')
        button.onmousedown(page,button)
        check(not OrganizedCategories.isItemPinned(0,target),'Organized Categories provider did not unpin selected item')
    else
        dispatch(target,true,pane)
    end
    phase='unpin';nextAt=getTimestampMs()+500
end
local function run()
    nextAt=getTimestampMs()+100
    local label=phase..' scene='..tostring(scenes[scene])
    if mp.loggedPhase~=label then mp.loggedPhase=label;print('[PIN_ITEMS] PHASE '..label) end
    if phase=='setup' then
        if SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
        if spawn() then phase='access';nextAt=getTimestampMs()+1000 end
    elseif phase=='access' then
        if paneForScene() then
            if mp.active then
                if F.signature(container)~=mp.fixture.itemSignature then return end
                assert(container:getItems():size()==6)
                if not mp.ready then
                    mp.ready=true
                    print('[PIN_ITEMS] REPLICA {"actor":'..quote(getPlayer():getUsername())..
                        ',"onlineId":'..getPlayer():getOnlineID()..',"truckId":'..quote(vehicle:getId())..
                        ',"itemCount":6,"itemSignature":'..quote(F.signature(container))..'}')
                    sendClientCommand('PinnedItemsTest','ready',{itemSignature=F.signature(container)})
                end
                phase='mp-wait'
            else phase='mode' end
            return
        end
        accessAttempt=accessAttempt+1
        assert(accessAttempt<=16,'No naturally accessible trunk position')
        local area=assert(vehicle:getAreaCenter(vehicle:getPartById('TruckBed'):getArea()))
        local angle=accessAttempt*math.pi/4
        local radius=accessAttempt<=8 and .6 or 1.1
        place(area:getX()+radius*math.cos(angle),area:getY()+radius*math.sin(angle))
        nextAt=getTimestampMs()+500
    elseif phase=='mp-wait' then
        if mp.started then phase='mode' end
    elseif phase=='mp-finish' then
        if mp.complete then done=true;print('[PIN_ITEMS] COMPLETE trunk') end
    elseif phase=='mode' then
        if scene>#scenes then
            if mp.active then
                sendClientCommand('PinnedItemsTest','done',{itemSignature=F.signature(container)})
                phase='mp-finish'
            else done=true;print('[PIN_ITEMS] COMPLETE trunk') end
            return
        end
        local name=scenes[scene]
        if name~='startup-order' and name~='organized-item-pin' and CleanUI_setCleanInventoryUIEnabled then
            CleanUI_setCleanInventoryUIEnabled(name:match('^vanilla%-')==nil)
        end
        phase='pin';nextAt=getTimestampMs()+700
    elseif phase=='pin' then
        failures={}
        local pane=assert(paneForScene(),'Real trunk not selected after inventory mode change')
        local name=scenes[scene]
        if getActivatedMods():contains('CleanUI') and name~='startup-order' then
            local expected=name:match('^vanilla%-') and CleanUI_Vanilla_ISInventoryPane or CleanUI_Clean_ISInventoryPane
            assert(getmetatable(pane)==expected,'Wrong inventory class for '..scenes[scene])
        end
        activeClass=activeClassName(pane)
        comparatorIdentity,comparatorName=comparatorNameOf(pane)
        searchState,searchCategoryState,searchModeState=pane.searchText,pane.searchCategoryText,pane.searchMode
        toolkitCategoryState,toolkitTagState=pane.toolkitCategory,pane.toolkitTag
        toolkitTagRuleState=pane.toolkitTagRule~=nil
        categoryName,categoryCount,searchText,matchingCount,allRowsMatch=nil,nil,nil,nil,nil
        if name~='startup-order' and name~='organized-item-pin' then
            pane.searchText,pane.searchCategoryText,pane.searchMode=nil,nil,'name'
            pane.toolkitCategory,pane.toolkitTag,pane.toolkitTagRule=nil,nil,nil
            for fullType in pairs(pins.FavouritedItems) do pins.setFavourite(fullType,false) end
            pane.selected={};pane.firstSelect=nil
            local kind=name:match('^.-%-(%w+)')
            local descending=name:match('%-desc$')~=nil
            if descending then configureDescending(pane,kind)
            else
                pane.itemSortFunc=kind=='category' and ISInventoryPane.itemSortByCatInc
                    or kind=='weight' and ISInventoryPane.itemSortByWeightAsc or ISInventoryPane.itemSortByNameInc
            end
            if name=='clean-search-match' or name=='clean-search' then
                searchText,matchingCount,allRowsMatch=configureSearchMatch(pane)
            elseif name=='clean-category-filter' then
                categoryName,categoryCount=configureCategoryFilter(pane)
            elseif name=='category-split' then
                assert(hasOrganizedCategories and OrganizedCategories.setItemDisplayCategory,
                    'Organized Categories instance display API unavailable')
                local duplicateItems={}
                for index=0,container:getItems():size()-1 do
                    local item=container:getItems():get(index)
                    if item:getFullType()=='Base.Screwdriver' then duplicateItems[#duplicateItems+1]=item end
                end
                assert(#duplicateItems==2,'Expected two screwdriver instances')
                assert(OrganizedCategories.setItemDisplayCategory(duplicateItems[1],'toolElectrical',true))
                assert(OrganizedCategories.setItemDisplayCategory(duplicateItems[2],'toolCarpentry',true))
            end
            pane:refreshContainer();pane:renderdetails(false)
        end
        originalOrder=order(pane)
        assert(#originalOrder>=2,'Not enough visible fixture rows')
        provider='BetterContainers';organizedPinned=false;splitRows=0;splitCategories='';expectedFirstCategory=nil
        pinnedCategories='';originalCategories=rowCategories(pane)
        if name=='category-split' then
            local categories={}
            for _, group in ipairs(pane.itemslist) do
                if group.items and group.items[1] and group.items[1]:getFullType()=='Base.Screwdriver' then
                    splitRows=splitRows+1;categories[group.cat]=true
                end
            end
            local values={};for category in pairs(categories) do values[#values+1]=quote(category) end
            splitCategories=table.concat(values,',')
            assert(splitRows==2 and #values==2,'Organized Categories did not split duplicate screwdriver rows')
        end
        target=nil
        if name=='clean-category-filter' then
            for _, group in ipairs(pane.itemslist) do
                if group.items and group.items[1] and group.items[1]:getFullType()=='Base.Screwdriver' then
                    target=group.items[1];break
                end
            end
        elseif name=='category-split' then
            local firstCategory
            for _, group in ipairs(pane.itemslist) do
                if group.items and group.items[1] and group.items[1]:getFullType()=='Base.Screwdriver' then
                    firstCategory=firstCategory or group.cat
                    if group.cat~=firstCategory then target=group.items[1];break end
                end
            end
            assert(target,'Could not select the second split screwdriver row')
            -- BC pins both instances by type, retaining their chosen column order.
            expectedFirstCategory=firstCategory
        else
            for i=#pane.itemslist,1,-1 do
                local group=pane.itemslist[i]
                if group.items and group.items[1] and (name~='clean-search-match' or group.matchesSearch) then
                    target=group.items[1];break
                end
            end
        end
        assert(target,'No visible pin target')
        targetTypeCount=typeCount(target:getFullType())
        selectedItem=pane.itemslist[1].items[1]
        pane.selected={[1]=pane.itemslist[1]}
        if name=='organized-item-pin' then
            selectedItem=target
            for index, group in ipairs(pane.itemslist) do
                if group.items then
                    for _, item in ipairs(group.items) do
                        if item==target then pane.selected={[index]=group} end
                    end
                end
            end
        end
        countBefore=container:getItems():size()
        expectedFirst=target:getFullType()
        if name=='organized-item-pin' then
            local page=getPlayerLoot(0)
            local button=assert(page.ocItemPinButton,'Organized Categories pin toolbar button unavailable')
            assert(button.onmousedown,'Organized Categories pin button has no native mouse-down handler')
            provider='organizedCategories_core'
            button.onmousedown(page,button)
            organizedPinned=OrganizedCategories.isItemPinned(0,target)==true
            assert(organizedPinned,'Organized Categories provider did not pin selected item')
        else
            dispatch(target,false,pane)
        end
        phase='capture';nextAt=getTimestampMs()+800
    elseif phase=='capture' then
        local pane=getPlayerLoot(0).inventoryPane
        assert(pane.inventory==container,'Loot UI lost the trunk after pin')
        pinnedOrder=order(pane)
        pinnedCategories=rowCategories(pane)
        check(pinnedOrder[1]==expectedFirst,'Pinned type did not move to expected first visible row')
        if scenes[scene]=='category-split' then
            check(getPlayerLoot(0).inventoryPane.itemslist[1].cat==expectedFirstCategory,
                'Pin changed the chosen order between same-type split rows')
            check(pinnedOrder[2]==expectedFirst,'A same-type split row remained below unpinned types')
        end
        local saved=pane:saveSelection({})
        selectedPreserved=saved[selectedItem]~=nil
        check(selectedPreserved,'Selection moved to a different item after pinning')
        check(container:getItems():size()==countBefore,'Pin changed trunk contents')
        if mp.active then check(F.signature(container)==mp.fixture.itemSignature,'Replicated item IDs changed') end
        getCore():TakeFullScreenshot('pin-'..scenes[scene]..'.png')
        pane:refreshContainer();pane:renderdetails(false)
        check(order(pane)[1]==expectedFirst,'Pin priority lost after refresh/render')
        if mp.active and (scene==1 or scenes[scene]=='organized-item-pin') then
            mp.peerChecked=false
            sendClientCommand('PinnedItemsTest','probe',{provider=provider,target=target:getFullType()})
            phase='peer-check'
        else
            unpinCurrent()
        end
    elseif phase=='peer-check' then
        if mp.peerChecked then
            local held=provider=='BetterContainers' and pins.isFavourite(target:getFullType())
                or provider=='organizedCategories_core' and OrganizedCategories.isItemPinned(0,target)
            check(held==true,'Pin disappeared before peer confirmation')
            unpinCurrent()
        end
    elseif phase=='unpin' then
        local pane=getPlayerLoot(0).inventoryPane
        assert(pane.inventory==container,'Loot UI lost the trunk after unpin')
        check(table.concat(order(pane),'|')==table.concat(originalOrder,'|'),'Unpin did not restore chosen column order')
        check(rowCategories(pane)==originalCategories,'Unpin did not restore split category order')
        emit()
        scene=scene+1;phase='mode'
    end
end
Events.OnGameStart.Add(function()
    local options=require 'BetterContainers/_Options'
    local helpers=require 'BetterContainers/Helpers'
    local advanced=config.options and config.options.advanced_categories==true
    PZAPI.ModOptions:getOptions(helpers.MODULE_ID):getOption('showAdvancedDisplayCategories'):setValue(advanced)
    options.showAdvancedDisplayCategories=advanced
    print('[PIN_ITEMS] SETTINGS advancedCategories='..tostring(advanced))
    started=true;nextAt=getTimestampMs()+2000
end)
Events.OnTick.Add(function()
    if done or not started or not isIngameState() or getTimestampMs()<nextAt then return end
    if not getPlayer() or not getPlayer():getSquare() then return end
    local ok,err=pcall(run)
    if not ok then done=true;print('[PIN_ITEMS] FAIL phase='..phase..' '..tostring(err)) end
end)
