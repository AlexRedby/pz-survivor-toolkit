-- Test-only observers forward every native draw. No renderer, item or queue mocks.
local entered, starting, started, done = false, false, false, false
local steps, step, since = {}, 1, 0
local pane, page, samples, batteries, button, probe, current, buttonProbe
local iconObserver
local function add(fn) steps[#steps + 1] = fn end
local function shot(name)
    getCore():TakeFullScreenshot('inventory-' .. name .. '.png')
    print('[INVENTORY_SCREEN] SHOT ' .. name)
end
local function options() return require('PZSurvivorToolkit/InventoryDetailOptions').config end
local function observe(target)
    if not iconObserver then
        iconObserver = ISInventoryItem.renderItemIcon
        ISInventoryItem.renderItemIcon = function(owner, item, ...)
            if probe and owner==pane then
                if item==samples.bag then probe.capacityExpected=probe.capacityExpected+1 end
                if item==samples.mag then probe.magazineExpected=probe.magazineExpected+1 end
            end
            return iconObserver(owner,item,...)
        end
    end
    local details, render, text, centre, bar, rect = target.drawItemDetails, target.renderdetails,
        target.drawText, target.drawTextCentre, target.drawProgressBar, target.drawRect
    target.drawText = function(self, value, ...)
        if current then current.text[#current.text + 1] = tostring(value) end
        return text(self, value, ...)
    end
    target.drawTextCentre = function(self, value, ...)
        if current then current.text[#current.text + 1] = tostring(value) end
        return centre(self, value, ...)
    end
    target.drawProgressBar = function(self, x, y, w, h, fraction, ...)
        if current then current.bars[#current.bars + 1] = fraction end
        return bar(self, x, y, w, h, fraction, ...)
    end
    target.drawItemDetails = function(self, item, y, ...)
        if probe then
            local key = tostring(item:getID()) .. ':' .. tostring(y)
            assert(not probe.rows[key], 'detail row drawn twice: ' .. key)
            current = {item=item, text={}, bars={}}
            probe.rows[key] = current
        end
        local result = details(self, item, y, ...)
        current = nil
        return result
    end
    target.drawRect = function(self, x, y, w, h, a, ...)
        if probe and h==2 and a==0.95 then probe.capacityFills[#probe.capacityFills+1]={x=x,y=y,w=w} end
        if probe and h==2 and a==0.98 then probe.magazineFilled=probe.magazineFilled+1 end
        if probe and h == 4 then
            if a == 0.88 then probe.capacity = probe.capacity + 1; probe.capacityRects[#probe.capacityRects+1]={x=x,y=y,w=w} end
            if a == 0.92 then probe.magazine = probe.magazine + 1 end
        end
        return rect(self, x, y, w, h, a, ...)
    end
    target.renderdetails = function(self, dragged, ...)
        if dragged then return render(self, dragged, ...) end
        probe = {rows={}, capacity=0, magazine=0, capacityExpected=0, magazineExpected=0,
            capacityRects={}, capacityFills={}, magazineFilled=0}
        local result = render(self, dragged, ...)
        self.inventoryFixtureFrame = probe
        probe, current = nil, nil
        return result
    end
end
local function inventory(clean)
    CleanUI_setCleanInventoryUIEnabled(clean)
    page = getPlayerInventory(0)
    pane = page.inventoryPane
    page:setVisible(true); page:setX(30); page:setY(50); page:setWidth(1200); page:setHeight(800)
    page.isCollapsed=false; page:setPinned(); page:setMaxDrawHeight(800); pane:setVisible(true)
    getPlayerLoot(0):setVisible(false)
end
local function reflow()
    pane:setWidth(1150); pane:setHeight(720); pane.smoothScrollY=nil; pane.smoothScrollTargetY=nil; pane:setYScroll(0)
    pane:setMode('details'); pane:refreshContainer()
    for _, group in ipairs(pane.itemslist) do
        local item=group.items and group.items[1]
        pane.collapsed[group.name] = item==samples.bag or (item and item:getFullType()=='Base.Battery')
    end
    if page.cleanUIApplyScaleSettings then page:cleanUIApplyScaleSettings(true) end
    pane:onResize(); pane:refreshContainer()
    observe(pane)
    button = page:addContainerButton(samples.bag:getInventory(), samples.bag:getTex(), 'Fixture bag', '')
    assert(button and button.inventory == samples.bag:getInventory(), 'native container button missing')
    local render, rect = button.render, button.drawRect
    button.drawRect = function(self, x, y, w, h, a, ...)
        if buttonProbe and h == 4 and a == 0.88 then buttonProbe.count = buttonProbe.count + 1 end
        return rect(self, x, y, w, h, a, ...)
    end
    button.render = function(self, ...)
        buttonProbe = {count=0}
        local result = render(self, ...)
        self.inventoryFixtureBars = buttonProbe.count
        buttonProbe=nil
        return result
    end
end
local function rowFor(frame, item)
    local found
    for _, row in pairs(frame.rows) do
        if row.item == item then assert(not found, 'collapsed item detail repeated'); found = row end
    end
    return assert(found, 'representative native item not rendered: ' .. item:getFullType())
end
local function hasText(row, expected)
    local n=0; for _, text in ipairs(row.text) do if text == expected then n=n+1 end end
    assert(n == 1, 'expected exactly one detail text ' .. expected .. ', got ' .. n .. ' for ' .. row.item:getFullType())
end
local function check(name)
    local frame=assert(pane.inventoryFixtureFrame, 'native render did not run')
    assert(frame.capacityExpected>0 and frame.capacity == frame.capacityExpected, 'bag indicator count differs from actual native icons')
    assert(frame.magazineExpected>0 and frame.magazine == frame.magazineExpected, 'magazine indicator count differs from actual native icons')
    local container=samples.bag:getInventory()
    local ratio=container:getCapacityWeight()/container:getEffectiveCapacity(getPlayer())
    assert(ratio>0 and ratio<1 and #frame.capacityFills==#frame.capacityRects,'bag native capacity fraction missing')
    for index, rect in ipairs(frame.capacityRects) do
        local fill=frame.capacityFills[index]
        assert(fill.x==rect.x+1 and fill.y==rect.y+1 and fill.w==math.max(1,math.floor((rect.w-2)*ratio)), 'bag fill differs from native used/capacity')
    end
    assert(frame.magazineFilled==frame.magazineExpected*math.min(math.ceil(3/samples.mag:getMaxAmmo()*4),3), 'magazine visible segments differ from native ammo')
    assert(button.inventoryFixtureBars == 1, 'native container button capacity must draw once')
    hasText(rowFor(frame,samples.mag), '3/' .. samples.mag:getMaxAmmo())
    hasText(rowFor(frame,samples.gun), '5/' .. samples.gun:getMaxAmmo())
    hasText(rowFor(frame,samples.knife), '62%')
    local food=rowFor(frame,samples.food)
    hasText(food, tostring(round(samples.food:getCalories())))
    local fluid=rowFor(frame,samples.fluid)
    assert(#fluid.text>0 and #fluid.bars>0, 'native fluid details absent')
    for _, key in ipairs({'clothes','part'}) do
        local row=rowFor(frame,samples[key]); assert(#row.text>0 and #row.bars>0, key .. ' details absent')
    end
    print('[INVENTORY_SCREEN] DRAW ' .. name .. ' details=once bag=icons magazine=icons button=1 nativeTypes=true')
    shot(name)
end
add(function()
    assert(not isClient() and not isServer(), 'SP required')
    for _, id in ipairs({'BravoItemDetails','ContainerCapacityIndicator','Quartermaster'}) do
        assert(not getActivatedMods():contains(id), 'external owner enabled: ' .. id)
    end
    local p=getPlayer(); p:setGodMod(true); p:setGhostMode(true); p:setAutoDrink(false)
    getCore():setOptionAutoDrink(false)
    if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
    if getPlayerInfoPanel and getPlayerInfoPanel(0) then getPlayerInfoPanel(0):setVisible(false) end
    p:getWornItems():clear(); p:setPrimaryHandItem(nil); p:setSecondaryHandItem(nil)
    local inv=p:getInventory(); inv:getItems():clear()
    local function item(id) return assert(inv:AddItem(id), 'missing B42 fixture item ' .. id) end
    samples={bag=item('Base.Bag_Schoolbag'), mag=item('Base.9mmClip'), gun=item('Base.Pistol'),
        knife=item('Base.HuntingKnife'), food=item('Base.Steak'), fluid=item('Base.WaterBottle'),
        clothes=item('Base.Shirt_Denim'), part=item('Base.CarBattery1')}
    assert(instanceof(samples.bag,'InventoryContainer') and instanceof(samples.gun,'HandWeapon')
        and instanceof(samples.food,'Food') and instanceof(samples.clothes,'Clothing'), 'real native types required')
    samples.bag:getInventory():AddItem('Base.TinnedBeans')
    samples.mag:setCurrentAmmoCount(3); samples.gun:setCurrentAmmoCount(4); samples.gun:setRoundChambered(true)
    assert(samples.knife:hasSharpness(), 'knife has no native sharpness'); samples.knife:setSharpness(0.62)
    samples.part:setCondition(math.floor(samples.part:getConditionMax()*0.57))
    local fc=assert(samples.fluid:getFluidContainer(), 'native fluid component missing')
    fc:Empty(); fc:addFluid(Fluid.Water,0.5)
    p:getCharacterTraits():add(CharacterTrait.NUTRITIONIST2)
    batteries={}
    for i=1,7 do
        local b=item('Base.Battery'); b:setUsedDelta(i/8); batteries[#batteries+1]=b
    end
    local c=options(); c.showLabels=true; c.showBars=true; c.showNumeric=true; c.showNutritionist=true
    local bc=require 'BetterContainers/_Options'; bc.showAdvancedDisplayCategories=false
    print('[INVENTORY_SCREEN] SETUP nativeItems=15 externalOwners=false')
    inventory(true)
end)
add(reflow)
add(function() check('01-clean') end)
add(function() inventory(false) end)
add(reflow)
add(function() check('02-vanilla') end)
add(function() inventory(true) end)
add(reflow)
add(function() check('03-clean-again') end)
local baseline, tail, selected
local function batteryGroup()
    for _, group in ipairs(pane.itemslist) do
        local first=group.items and group.items[1]
        if first and first:getFullType()=='Base.Battery' then return group end
    end
    error('native battery stack missing')
end
add(function()
    options().enableSort=false; options().maxSort='3'
    pane:refreshContainer(); local group=batteryGroup(); pane.collapsed[group.name]=false; pane:refreshContainer()
    group=batteryGroup(); baseline={}; tail={}
    local first=group.cleanUIFirstActualIndex or 2
    assert(first==2,'sort requires native physical-child stack')
    for i=first,#group.items do baseline[#baseline+1]=group.items[i] end
    assert(#baseline==7,'native stack lost fixture items before sort')
    for i=4,#baseline do tail[i]=baseline[i] end
    selected=baseline[2]
end)
add(function()
    local selectedRow
    for index, row in ipairs(pane.items) do if row==selected then selectedRow=index end end
    assert(selectedRow,'physical child not in rendered rows')
    pane.selected={[selectedRow]=selected}; pane.firstSelect=selectedRow
    options().enableSort=true; pane:refreshContainer()
end)
add(function()
    local group=batteryGroup(); local children={}
    for i=2,#group.items do children[#children+1]=group.items[i] end
    assert(#children==7,'bounded sort dropped native tail')
    local ids={}; for _, item in ipairs(children) do assert(not ids[item:getID()],'duplicate physical child');ids[item:getID()]=true end
    for i=4,#baseline do assert(children[i]==tail[i],'bounded sort reordered tail') end
    assert(children[1]:getCurrentUses()>=children[2]:getCurrentUses() and children[2]:getCurrentUses()>=children[3]:getCurrentUses(),'native uses prefix sort failed')
    local found=false
    for index, item in pairs(pane.selected) do
        if item==selected then assert(pane.items[index]==selected,'selection offset changed'); found=true end
    end
    assert(found and pane.items[pane.firstSelect]==selected,'selection/Shift anchor lost native item')
    print('[INVENTORY_SCREEN] SORT count=7 bound=3 tail=4 selection=true anchor=true')
    shot('04-sort')
end)
add(function() print('[INVENTORY_SCREEN] COMPLETE'); done=true end)
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
    if started and isIngameState() then setGameSpeed(1) end
    if not entered or starting or isIngameState() then return end
    starting=true; getCore():setOptionPauseOnFocusloss(false)
    getWorld():setGameMode('Sandbox'); getWorld():setWorld('InventoryPresentationScreens'); getWorld():setMap('Muldraugh, KY')
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
    if done then if getTimestampMs()-since>4000 then getCore():quitToDesktop() end; return end
    if getTimestampMs()-since<1800 then return end
    local ok,err=pcall(steps[step])
    if not ok then print('[INVENTORY_SCREEN] FAIL step='..step..' '..tostring(err)); getCore():TakeFullScreenshot('inventory-failed.png'); done=true; since=getTimestampMs(); return end
    step=step+1; since=getTimestampMs()
end)
