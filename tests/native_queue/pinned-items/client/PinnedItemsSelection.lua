-- Real native panes and row construction; only keyboard predicates are injected.
local F = {}
local quote = require('PinnedItemsFixture').quote
local filtering = require 'PinnedItemsFiltering'

function F.start(config)
    local clean = getActivatedMods():contains('CleanUI')
    local modes = clean and {'clean','vanilla'} or {'vanilla'}
    local modeIndex, nextAt, started, done = 1, 0, false, false
    local inventory, equipped, stack, targets

    local function findRow(pane, item)
        for row, value in ipairs(pane.items) do if value==item then return row end end
    end
    local function groupFor(pane, item)
        for _, group in ipairs(pane.itemslist) do
            for _, child in ipairs(group.items or {}) do
                if child==item then return group end
            end
        end
        error('Fixture item has no native stack')
    end
    local function render(pane)
        pane:refreshContainer()
        pane:renderdetails(false)
    end
    local function exact(pane)
        for row, value in pairs(pane.selected) do
            assert(pane.items[row]==value,'Selected entry differs from rendered row '..tostring(row))
        end
    end
    local function selectAndRefresh(pane, value, semantic)
        local row=assert(findRow(pane,value),'Fixture selection is not rendered')
        pane.selected={[row]=value};pane.firstSelect=row
        local physical=semantic=='item' and value or value.items[1]
        for pass=1,2 do
            render(pane)
            exact(pane)
            local current=semantic=='item' and value or groupFor(pane,physical)
            row=assert(findRow(pane,current),'Selected item/group disappeared')
            assert(pane.selected[row]==current,'Exact '..semantic..' selection was not restored')
            assert(pane.firstSelect==row,'Shift anchor points at a different rendered row')
            assert(pane:saveSelection({})[physical]==semantic,'Selection lost '..semantic..' semantics')
            local count=0
            for _ in pairs(pane.selected) do count=count+1 end
            assert(count==1,'Selection expanded to unrelated rows')
        end
        return row
    end
    local function shift(pane, anchorRow)
        -- A programmatic mouse-down has no physical mouse-up. Restore its drag
        -- setup immediately: saveSelection otherwise imports the old range, and
        -- the next update may dispatch an unintended native drop/transfer.
        local shiftDown,ctrlDown=isShiftKeyDown,isCtrlKeyDown
        local dragging,draggingFocus=ISMouseDrag.dragging,ISMouseDrag.draggingFocus
        local fields={'mouseOverOption','downX','downY','dragging','draggingX','draggingY','dragStarted'}
        local before={}
        for _, field in ipairs(fields) do before[field]=pane[field] end
        local targetRow=anchorRow-1
        assert(targetRow>0 and pane.items[targetRow],'Missing adjacent Shift target')
        pane.mouseOverOption=targetRow
        isShiftKeyDown=function() return true end
        isCtrlKeyDown=function() return false end
        local ok,err=pcall(function() pane:onMouseDown(pane.column2+20,pane.headerHgt+1) end)
        isShiftKeyDown,isCtrlKeyDown=shiftDown,ctrlDown
        ISMouseDrag.dragging,ISMouseDrag.draggingFocus=dragging,draggingFocus
        for _, field in ipairs(fields) do pane[field]=before[field] end
        assert(ok,err)
        exact(pane)
        assert(pane.firstSelect==anchorRow,'Shift callback moved the restored anchor')
        assert(pane.selected[targetRow]==pane.items[targetRow] and pane.selected[anchorRow]==pane.items[anchorRow],
            'Native Shift callback did not include the restored anchor and adjacent row')
        local count=0
        for _ in pairs(pane.selected) do count=count+1 end
        assert(count==2,'Native Shift callback selected rows outside the expected range')
        return targetRow
    end
    local function prepare()
        if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
        if getPlayerInfoPanel and getPlayerInfoPanel(0) then getPlayerInfoPanel(0):setVisible(false) end
        inventory=getPlayer():getInventory()
        equipped=assert(inventory:AddItem('Base.Hammer'));equipped:setName('000 Selection equipped')
        getPlayer():setPrimaryHandItem(equipped)
        stack={};targets={}
        for index=1,55 do
            stack[index]=assert(inventory:AddItem('Base.Nails'))
            stack[index]:setName('AAA Selection stack')
        end
        for index=1,2 do
            targets[index]=assert(inventory:AddItem('Base.Screwdriver'))
            targets[index]:setName('ZZZ Selection target')
        end
        assert(inventory:contains(equipped),'Equipped fixture item is not in the native inventory')
    end
    local function markers(pane, mode)
        local pins=require 'BetterContainers/Upgrades/PinnedItems'
        local options=require 'BetterContainers/_Options'
        options.showFavouritesOnPlayerInventories=true
        for _, item in ipairs({equipped,stack[1],targets[1]}) do pins.setFavourite(item:getFullType(),true) end
        pane.selected={};pane.firstSelect=nil
        local texture=assert(getTexture('media/ui/BetterContainers/PinnedItemMarker.png'))
        local passes=0
        local function check(label, dragged)
            local draws,expected={},{}
            local own=rawget(pane,'drawTextureScaled')
            local original=pane.drawTextureScaled
            local originalIcon=ISInventoryItem.renderItemIcon
            ISInventoryItem.renderItemIcon=function(owner,item,x,y,alpha,width,height,...)
                local row=owner==pane and pane.items[#pane.items]
                if owner==pane and not dragged and options.showFavouritesOnPlayerInventories
                    and type(row)=='table' and row.items and pins.isFavourite(item:getFullType()) then
                    local tex=item:getTex()
                    local w,h=width or tex:getWidthOrig(),height or tex:getHeightOrig()
                    if y+pane:getYScroll()>=pane.headerHgt and y+pane:getYScroll()+math.min(12,h/2)<=pane.height then
                        expected[#expected+1]={x=x,y=y,width=w,height=h}
                    end
                end
                return originalIcon(owner,item,x,y,alpha,width,height,...)
            end
            pane.drawTextureScaled=function(self, tex, x, y, width, height, ...)
                if tex==texture then draws[#draws+1]={x=x,y=y,width=width,height=height} end
                return original(self,tex,x,y,width,height,...)
            end
            local ok,err=pcall(function() pane:renderdetails(dragged==true) end)
            pane.drawTextureScaled=own
            ISInventoryItem.renderItemIcon=originalIcon
            assert(ok,err)
            assert(#draws==#expected, label..' marker count '..#draws..' ~= '..#expected)
            for index, draw in ipairs(draws) do
                local icon=expected[index]
                assert(draw.y==icon.y and draw.x>=icon.x and draw.x+draw.width<=icon.x+icon.width,
                    label..' marker left its actual native header icon')
                assert(draw.width>=8 and draw.width<=11 and draw.height==draw.width,label..' marker size changed')
            end
            passes=passes+1
        end
        render(pane)
        check('expanded')
        local target=groupFor(pane,targets[1])
        local row=assert(findRow(pane,target))
        local dragging,focus=ISMouseDrag.dragging,ISMouseDrag.draggingFocus
        local fields={'selected','dragging','dragStarted','draggingX','draggingY'}
        local before={}
        for _, field in ipairs(fields) do before[field]=pane[field] end
        pane.selected={[row]=target};pane.dragging=row;pane.dragStarted=true
        pane.draggingX,pane.draggingY=getMouseX(),getMouseY()
        ISMouseDrag.dragging,ISMouseDrag.draggingFocus={target},pane
        local ok,err=pcall(function()
            check('drag selection')
            check('drag overlay',true)
        end)
        ISMouseDrag.dragging,ISMouseDrag.draggingFocus=dragging,focus
        for _, field in ipairs(fields) do pane[field]=before[field] end
        assert(ok,err)
        options.showFavouritesOnPlayerInventories=false
        check('disabled player pins')
        options.showFavouritesOnPlayerInventories=true
        if mode=='clean' then
            pane.equippedCollapsed=false;render(pane);check('visible equipment')
            pane.equippedCollapsed=true
        end
        for _, group in ipairs(pane.itemslist) do if group.items then pane.collapsed[group.name]=true end end
        render(pane);check('collapsed')
        return passes
    end
    local function probe(mode)
        local page=getPlayerInventory(0)
        page:setVisible(true);page.isCollapsed=false;page:setPinned()
        page:bringToTop()
        page:selectButtonForContainer(inventory)
        page:setForceSelectedContainer(inventory,60000)
        page:setX(50);page:setY(80);page:setWidth(740);page:setHeight(550)
        local pane=page.inventoryPane
        assert(pane.inventory==inventory and pane.parent.onCharacter,'Fixture is not using the real player inventory pane')
        local expectedClass=clean and (mode=='clean' and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane) or ISInventoryPane
        assert(getmetatable(pane)==expectedClass,'Wrong native inventory class')
        pane:setMode('details');pane:setYScroll(0)
        pane.searchText,pane.searchCategoryText,pane.searchMode=nil,nil,'name'
        pane.toolkitCategory,pane.toolkitTag,pane.toolkitTagRule=nil,nil,nil
        local pins=require 'BetterContainers/Upgrades/PinnedItems'
        for fullType in pairs(pins.FavouritedItems) do pins.setFavourite(fullType,false) end
        pane.selected={};pane.firstSelect=nil;pane.equippedCollapsed=mode=='clean'
        pane.itemSortFunc=ISInventoryPane.itemSortByNameInc
        render(pane)
        local large=groupFor(pane,stack[1])
        local target=groupFor(pane,targets[1])
        pane.collapsed[large.name]=false;pane.collapsed[target.name]=false
        render(pane)
        large,target=groupFor(pane,stack[1]),groupFor(pane,targets[1])
        local largeRow=assert(findRow(pane,large))
        local targetRow=assert(findRow(pane,target))
        local children=0
        for _, item in ipairs(stack) do if findRow(pane,item) then children=children+1 end end
        assert(children==ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER,'Fixture did not reach the native expanded-row cap')
        assert(targetRow>largeRow+children,'Target is not after the capped native stack')
        local equippedGroup=groupFor(pane,equipped)
        assert(equippedGroup.equipped,'Native refresh did not classify the equipped item')
        if mode=='clean' then
            assert(not findRow(pane,equippedGroup) and not findRow(pane,equipped),'Equipped rows are not hidden')
        end
        local headers=0
        for _, row in ipairs(pane.items) do
            if not instanceof(row,'InventoryItem') and row.type=='separator' then headers=headers+1 end
        end
        if mode=='clean' then assert(headers>0,'Hidden equipment has no rendered header') end
        local groupRow=selectAndRefresh(pane,target,'group')
        -- The target child is beyond the capped stack and any hidden equipped rows.
        local actualChild
        for _, item in ipairs(targets) do
            local row=findRow(pane,item)
            if row and (not actualChild or row>findRow(pane,actualChild)) then actualChild=item end
        end
        assert(actualChild,'Target stack has no rendered physical child')
        local childRow=selectAndRefresh(pane,actualChild,'item')
        local shiftRow=shift(pane,childRow)
        -- Select the last rendered child of the large stack, not its group header.
        local lastChild
        for _, item in ipairs(stack) do
            local row=findRow(pane,item)
            if row and (not lastChild or row>findRow(pane,lastChild)) then lastChild=item end
        end
        local capRow=selectAndRefresh(pane,assert(lastChild),'item')
        filtering.probe(pane,mode)
        local markerPasses=markers(pane,mode)
        print('[PIN_ITEMS] SELECTION {"mode":'..quote(mode)..',"status":"passed","input":"programmatic-key-predicates"'..
            ',"class":'..quote(mode=='clean' and 'CleanUI_Clean_ISInventoryPane' or clean and 'CleanUI_Vanilla_ISInventoryPane' or 'ISInventoryPane')..
            ',"stackCount":55,"renderedChildren":'..children..',"equippedHeaders":'..headers..',"equippedHidden":'..tostring(mode=='clean')..
            ',"groupRow":'..groupRow..',"childRow":'..childRow..',"shiftRow":'..shiftRow..',"capRow":'..capRow..
            ',"childId":'..quote(actualChild:getID())..',"exactSelection":true,"groupSemantics":true,"itemSemantics":true,"repeatedRefresh":true,"shiftRange":true'..
            ',"markerPasses":'..markerPasses..',"markerGeometry":true}')
    end
    Events.OnGameStart.Add(function() started=true;nextAt=getTimestampMs()+2500 end)
    Events.OnTick.Add(function()
        if done or not started or not isIngameState() or getTimestampMs()<nextAt then return end
        if not getPlayer() or not getPlayer():getSquare() then return end
        local ok,err=pcall(function()
            if not inventory then prepare() end
            local mode=modes[modeIndex]
            if not mode then done=true;print('[PIN_ITEMS] COMPLETE selection');return end
            if F.shotPhase then
                -- Screenshot reads the last completed frame, not this tick's draw calls.
                local filename=F.shotPhase=='filter' and 'pin-filter-'..mode..'.png'
                    or 'pin-markers-'..mode..'-'..F.shotPhase..'.png'
                getCore():TakeFullScreenshot(filename)
                if F.shotPhase=='collapsed' then
                    local pane=getPlayerInventory(0).inventoryPane
                    pane.collapsed[groupFor(pane,stack[1]).name]=false
                    render(pane)
                    F.shotPhase='expanded';nextAt=getTimestampMs()+750
                elseif F.shotPhase=='expanded' then
                    filtering.snapshot(getPlayerInventory(0).inventoryPane,mode)
                    F.shotPhase='filter';nextAt=getTimestampMs()+750
                else
                    filtering.clear(getPlayerInventory(0).inventoryPane)
                    modeIndex=modeIndex+1;F.modeReady=false;F.shotPhase=nil;nextAt=getTimestampMs()+100
                end
                return
            end
            if not F.modeReady then
                if clean then CleanUI_setCleanInventoryUIEnabled(mode=='clean') end
                F.modeReady=true;nextAt=getTimestampMs()+700;return
            end
            -- Stop on the original failure before scheduling marker screenshots
            -- against a partially filtered fixture.
            local passed,reason=pcall(probe,mode)
            if not passed then
                print('[PIN_ITEMS] SELECTION {"mode":'..quote(mode)..',"status":"failed","reason":'..quote(reason)..'}')
                done=true
                print('[PIN_ITEMS] FAIL selection '..tostring(reason))
                return
            end
            F.shotPhase='collapsed';nextAt=getTimestampMs()+750
        end)
        if not ok then done=true;print('[PIN_ITEMS] FAIL selection '..tostring(err)) end
    end)
end

return F
