local config = require "QueueTestSelection"
local F = require "VehicleWishlistFixture"
local stage, nextAt, ids, requested, failure = 1, 0, nil, false, false
local window, donor, wish, authority, screenshots
local nextDebug = 0
local W = PZSurvivorWishlist
local function pass(name) print('[VEHICLE_WISHLIST] PASS ' .. name) end
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "VehicleWishlistTest" then return end
    if command == "vehicles" then ids = args.ids end
    if command == "verified" then authority = args.removed and ('removed-'..args.removed) or (args.done and 'done' or 'open') end
end)
local function open(vehicle)
    local player=getPlayer()
    player:teleportTo(vehicle:getX()+1,vehicle:getY()+1,0)
    if SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
    local ui=ISVehicleMechanics:new(30,30,player,vehicle)
    ui:initialise();ui:addToUIManager();ui:setVisible(true);ui:bringToTop()
    return ui
end
local function vehicle(index)
    if not isClient() then return F.vehicles and F.vehicles[index] end
    return ids and getVehicleById(ids[index])
end
local function run()
    if stage==1 then
        if not W.Client.selected(0) then return end
        if not requested then
            requested=true
            if isClient() then sendClientCommand('VehicleWishlistTest','prepare',{}) else ids=F.prepare(getPlayer()) end
        end
        if not ids then return end
        for i=1,4 do if not vehicle(i) then return end end
        local source=vehicle(1);donor=vehicle(2)
        if source:getPartById('TireFrontLeft'):getInventoryItem() then return end
        local item=donor:getPartById('TireFrontLeft'):getInventoryItem()
        if not item or item:getFullType()~='Base.ModernTire2' then return end
        window=open(source)
        local part=source:getPartById('TireFrontLeft')
        for i=1,2 do
            window:doPartContextMenu(part,100,100)
            local option=assert(window.context:getOptionFromName(getText('UI_PZSW_AddVehicleWanted')))
            assert(window.context:getIsVisible())
            if i==2 then option.onSelect(option.target) end
        end
        window.context:hideAndChildren();window:close();window:removeFromUIManager()
        pass('native-menu');stage=2
    elseif stage==2 then
        if W.Client.state(0).pending then return end
        wish=assert(W.Client.selected(0).entries['vehicle:Base.OldTire2'])
        assert(wish.amount==1 and wish.vehicleClass==2 and #wish.vehicleTypes==3)
        for _,tier in ipairs({'Old','Normal','Modern'}) do
            assert(W.Client.isWanted(0,'Base.'..tier..'Tire2'))
            assert(not W.Client.isWanted(0,'Base.'..tier..'Tire1'))
            assert(not W.Client.isWanted(0,'Base.'..tier..'Tire3'))
        end
        assert(W.Vehicles.isWanted(0,donor:getPartById('TireFrontLeft')))
        assert(not W.Vehicles.isWanted(0,vehicle(1):getPartById('TireFrontLeft')))
        assert(not W.Vehicles.isWanted(0,vehicle(3):getPartById('TireFrontLeft')))
        assert(not W.Vehicles.isWanted(0,vehicle(4):getPartById('TireFrontLeft')))
        if isClient() then sendClientCommand('VehicleWishlistTest','verify',{done=false}) end
        pass('variants-and-classes');stage=3
    elseif stage==3 then
        if isClient() and authority~='open' then return end
        for _,type in ipairs({'Base.OldTire2','Base.NormalTire2','Base.ModernTire2','Base.ModernTire1'}) do getPlayer():getInventory():AddItem(type) end
        assert(W.Client.carriedCount(W.Client.carried(0),'vehicle:Base.OldTire2',wish)==3)
        local page=getPlayerInventory(0);page:setVisible(true);page:setPinned();page:refreshBackpacks()
        page.inventoryPane:refreshContainer();page.inventoryPane:renderdetails(false)
        assert(#W.Inventory.marks(page.inventoryPane)>0)
        pass('inventory-and-counts')
        window=open(donor)
        local pane=window.listbox
        for index,row in ipairs(pane.items) do
            if row.item.part==donor:getPartById('TireFrontLeft') then pane:ensureVisible(index) end
        end
        screenshots=getTimestampMs()+1000;stage=4
    elseif stage==4 then
        if getTimestampMs()<screenshots then return end
        assert(window:isReallyVisible(),'mechanics window disappeared before capture')
        window:bringToTop()
        local pane=window.listbox
        local borders=0;local original=pane.drawRectBorder
        pane.drawRectBorder=function(self,x,y,w,h,a,r,g,b)
            if math.abs(r-.25)<.001 and math.abs(g-.85)<.001 and math.abs(b-.75)<.001 then borders=borders+1 end
            return original(self,x,y,w,h,a,r,g,b)
        end
        local ok,err=pcall(function()pane:prerender()end);pane.drawRectBorder=original;assert(ok,err)
        assert(borders>0,'wanted installed tire row not rendered')
        getCore():TakeFullScreenshot('vehicle-wishlist-mechanics.png')
        pass('mechanics-row');stage=4.5;nextAt=getTimestampMs()+600
    elseif stage==4.5 then
        window:close();window:removeFromUIManager()
        window=W.UI.open(0);window:prerender()
        local found=false
        for _,row in ipairs(window.list.items) do
            if row.item.fullType=='vehicle:Base.OldTire2' then
                found=true
                local _,finish=row.item.name:find(getText('IGUI_VehicleType_2'),1,true)
                assert(finish and not row.item.name:find(getText('IGUI_VehicleType_2'),finish+1,true))
                assert(row.item.detail:find(getText('UI_PZSW_VehicleVariants'),1,true))
            end
        end
        assert(found);pass('wishlist-label');screenshots=getTimestampMs()+1000;stage=5
    elseif stage==5 then
        if getTimestampMs()<screenshots then return end
        getCore():TakeFullScreenshot('vehicle-wishlist-list.png');stage=5.5;nextAt=getTimestampMs()+600
    elseif stage==5.5 then
        W.Client.edit(0,'done',{fullType='vehicle:Base.OldTire2',done=true});stage=6
    elseif stage==6 then
        if W.Client.state(0).pending then return end
        assert(not W.Client.isWanted(0,'Base.ModernTire2'))
        assert(not W.Vehicles.isWanted(0,donor:getPartById('TireFrontLeft')))
        if isClient() then sendClientCommand('VehicleWishlistTest','verify',{done=true}) end
        stage=7
    elseif stage==7 then
        if isClient() and authority~='done' then return end
        window:close();pass('done')
        window=open(donor)
        window:doPartContextMenu(donor:getPartById('TireFrontLeft'),100,100)
        local option=assert(window.context:getOptionFromName(getText('UI_PZSW_RemoveVehicleWanted')))
        option.onSelect(option.target)
        window.context:hideAndChildren();window:close();window:removeFromUIManager();stage=8
    elseif stage==8 then
        if W.Client.state(0).pending then return end
        assert(not W.Client.selected(0).entries['vehicle:Base.OldTire2'])
        assert(not W.Client.isWanted(0,'Base.ModernTire2'))
        if isClient() then sendClientCommand('VehicleWishlistTest','verify',{removed='mechanics'}) end
        stage=9
    elseif stage==9 then
        if isClient() and authority~='removed-mechanics' then return end
        pass('mechanics-remove')
        window=open(vehicle(1))
        window:doPartContextMenu(vehicle(1):getPartById('TireFrontLeft'),100,100)
        local option=assert(window.context:getOptionFromName(getText('UI_PZSW_AddVehicleWanted')))
        option.onSelect(option.target)
        window.context:hideAndChildren();window:close();window:removeFromUIManager();stage=10
    elseif stage==10 then
        if W.Client.state(0).pending then return end
        assert(W.Client.selected(0).entries['vehicle:Base.OldTire2'])
        assert(W.Client.isWanted(0,'Base.ModernTire2'))
        local items=getPlayer():getInventory():getItems()
        local item
        for i=0,items:size()-1 do
            if items:get(i):getFullType()=='Base.ModernTire2' then item=items:get(i);break end
        end
        assert(item,'missing carried compatible tire')
        local context=ISContextMenu.get(0,100,100)
        triggerEvent('OnFillInventoryObjectContextMenu',0,context,{item})
        local label=getText('UI_PZSW_RemoveVehicleWanted')
        local option
        for _,candidate in ipairs(context.options) do
            if candidate.name:sub(1,#label)==label then assert(not option);option=candidate end
        end
        assert(option,'compatible inventory tire has no smart-group Remove option')
        option.onSelect(option.target);context:hideAndChildren();stage=11
    elseif stage==11 then
        if W.Client.state(0).pending then return end
        assert(not W.Client.selected(0).entries['vehicle:Base.OldTire2'])
        assert(not W.Client.isWanted(0,'Base.ModernTire2'))
        if isClient() then sendClientCommand('VehicleWishlistTest','verify',{removed='inventory'}) end
        stage=12
    elseif stage==12 then
        if isClient() and authority~='removed-inventory' then return end
        pass('inventory-remove');stage=13
        print('[VEHICLE_WISHLIST] COMPLETE mechanics')
    end
end
Events.OnTick.Add(function()
    if failure or stage==13 or not isIngameState() or not getPlayer() or not getPlayer():getSquare() or getTimestampMs()<nextAt then return end
    nextAt=getTimestampMs()+250
    if getTimestampMs()>=nextDebug then
        nextDebug=getTimestampMs()+5000
        local status='stage='..stage..' lists='..#W.Client.state(0).lists..' ids='..tostring(ids and #ids)
        if ids then for i=1,4 do
            local v=vehicle(i);local part=v and v:getPartById('TireFrontLeft');local item=part and part:getInventoryItem()
            status=status..' vehicle'..i..'='..tostring(v~=nil)..'/'..tostring(item and item:getFullType())
        end end
        print('[VEHICLE_WISHLIST] WAIT '..status)
    end
    local ok,err=pcall(run)
    if not ok then failure=true;print('[VEHICLE_WISHLIST] FAIL stage='..stage..' '..tostring(err)) end
end)
