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
local function options() return require('PZSurvivorToolkit/InventoryDetailOptions') end
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
    for _, id in ipairs({'BravoItemDetails','ContainerCapacityIndicator','Quartermaster','HasResearch','SeedSeasonIndicator'}) do
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
    local c=options(); c.showLabels:setValue(true); c.showBars:setValue(true); c.showNumeric:setValue(true); c.showNutritionist:setValue(true)
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
    options().enableSort:setValue(false); options().maxSort:setValue('3')
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
    options().enableSort:setValue(true); pane:refreshContainer()
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
-- A separate native inventory makes every owned research/season badge identifiable.
local indicatorProbe, indicatorSamples, researchRecipes, growingTooltip, tooltipProbe
local Research = require 'PZSurvivorToolkit/InventoryResearch'
local Planting = require 'PZSurvivorToolkit/InventoryPlanting'
local PlantingOptions = require 'PZSurvivorToolkit/InventoryPlantingOptions'
local PlantingTooltip = require 'PZSurvivorToolkit/InventoryPlantingTooltip'
local function indicatorObserve(target)
    if target.inventoryIndicatorObserved then return end
    target.inventoryIndicatorObserved=true
    local render, draw = target.renderdetails, target.drawTextureScaled
    target.drawTextureScaled = function(self, texture, x, y, width, height, alpha, r, g, b, ...)
        if indicatorProbe then
            if texture==Research.texture() then
                indicatorProbe.research[#indicatorProbe.research+1]={x=x,y=y,w=width,h=height,texture=texture,r=r,g=g,b=b}
            elseif texture==getTexture('media/ui/circle.png') or texture==getTexture('media/ui/MP/mp_ui_star.png') then
                indicatorProbe.season[#indicatorProbe.season+1]={x=x,y=y,w=width,h=height,texture=texture,r=r,g=g,b=b}
            end
        end
        return draw(self,texture,x,y,width,height,alpha,r,g,b,...)
    end
    target.renderdetails=function(self, dragged, ...)
        if dragged then return render(self,dragged,...) end
        indicatorProbe={icons={},research={},season={}}
        local result=render(self,dragged,...)
        self.inventoryIndicatorFrame=indicatorProbe
        indicatorProbe=nil
        return result
    end
end
local function indicatorReflow()
    pane:setWidth(1150); pane:setHeight(720); pane.smoothScrollY=nil; pane.smoothScrollTargetY=nil; pane:setYScroll(0)
    pane:setMode('details'); pane:refreshContainer()
    for _,group in ipairs(pane.itemslist) do pane.collapsed[group.name]=true end
    if page.cleanUIApplyScaleSettings then page:cleanUIApplyScaleSettings(true) end
    pane:onResize(); pane:refreshContainer()
    indicatorObserve(pane)
end
local function markerAt(draws,x,y,size,best)
    local count=0
    for _,draw in ipairs(draws) do
        if draw.x==x and draw.y==y and draw.w==size and draw.h==size then
            if best then
                assert(draw.texture==getTexture('media/ui/MP/mp_ui_star.png') and draw.r==0.25 and draw.g==0.95 and draw.b==0.40,
                    'native best month must draw its green star')
            end
            count=count+1
        end
    end
    assert(count==1,'badge must draw once at actual native icon coordinates')
end
local function indicatorCheck(name,research,season)
    local frame=assert(pane.inventoryIndicatorFrame,'indicator render absent')
    local researchCount,seasonCount,seen=0,0,{}
    for _,icon in ipairs(frame.icons) do
        seen[icon.item]=true
        local size=math.min(12,icon.width/2,icon.height/2)
        if icon.item==indicatorSamples.research and research then
            markerAt(frame.research,icon.x,icon.y,size); researchCount=researchCount+1
        end
        if (icon.item==indicatorSamples.seed or icon.item==indicatorSamples.packet) and season then
            markerAt(frame.season,icon.x+icon.width-size,icon.y,size,true); seasonCount=seasonCount+1
        end
    end
    for _,item in pairs(indicatorSamples) do assert(seen[item],'fixture item not rendered: '..item:getFullType()) end
    assert(#frame.research==researchCount and #frame.season==seasonCount,'unexpected/duplicate indicator or empty packet marked')
    print('[INVENTORY_SCREEN] INDICATORS '..name..' research='..tostring(research)..' season='..tostring(season)..' coords=actual once=true empty=false')
    if name=='05-indicators-clean' or name=='06-indicators-vanilla' then shot(name) end
end
add(function()
    local nativeIcon=ISInventoryItem.renderItemIcon
    ISInventoryItem.renderItemIcon=function(owner,item,x,y,alpha,width,height,...)
        if indicatorProbe and owner==pane then
            local texture=item:getTex()
            indicatorProbe.icons[#indicatorProbe.icons+1]={item=item,x=x,y=y,
                width=width or texture:getWidthOrig(),height=height or texture:getHeightOrig()}
        end
        return nativeIcon(owner,item,x,y,alpha,width,height,...)
    end
    local p=getPlayer(); p:getInventory():getItems():clear()
    local function item(id) return assert(p:getInventory():AddItem(id),'missing native indicator item '..id) end
    indicatorSamples={seed=item('Base.CarrotSeed'),packet=item('Base.CarrotBagSeed2'),
        empty=item('Base.CarrotBagSeed2_Empty'),research=item('Base.BarbedWire')}
    p:setKnowAllRecipes(false); p:setPerkLevelDebug(Perks.Maintenance,1); p:setPerkLevelDebug(Perks.MetalWelding,0)
    researchRecipes=indicatorSamples.research:getScriptItem():getResearchableRecipes()
    assert(researchRecipes:size()>0,'native research source missing')
    for i=0,researchRecipes:size()-1 do p:getKnownRecipes():remove(researchRecipes:get(i)) end
    assert(indicatorSamples.research:getScriptItem():getResearchableRecipes(p,true):size()>0,'research skill/knowledge setup not eligible')
    local crop,props=Planting.resolve(indicatorSamples.seed)
    assert(crop=='Carrots' and props.seasonRecipe,'native carrot crop unresolved')
    p:learnRecipe(props.seasonRecipe)
    getGameTime():setMonth(5)
    getSandboxOptions():getOptionByName('PlantGrowingSeasons'):setValue(true)
    PlantingOptions.config.enabled:setValue(true); PlantingOptions.config.tooltip:setValue(true)
    PlantingOptions.config.badMonth:setValue(true)
    assert(Planting.describe(p,indicatorSamples.seed,false).status=='best','native June carrot month not best')
    assert(Planting.describe(p,indicatorSamples.packet,false),'full packet has no native growing information')
    assert(not Planting.describe(p,indicatorSamples.empty,false),'empty packet is not a planting input')
    print('[INVENTORY_SCREEN] INDICATOR_SETUP nativeItems=4 recipe=unknown season=known status=best')
    inventory(true)
end)
add(indicatorReflow)
add(function() indicatorCheck('05-indicators-clean',true,true) end)
add(function() inventory(false) end)
add(indicatorReflow)
add(function() indicatorCheck('06-indicators-vanilla',true,true) end)
add(function()
    for i=0,researchRecipes:size()-1 do getPlayer():learnRecipe(researchRecipes:get(i)) end
    assert(indicatorSamples.research:getScriptItem():getResearchableRecipes(getPlayer(),true):size()==0,'native recipe did not become known')
end)
add(function() indicatorCheck('learned',false,true) end)
add(function() getSandboxOptions():getOptionByName('PlantGrowingSeasons'):setValue(false) end)
add(function() indicatorCheck('seasons-disabled',false,false) end)
add(function()
    getSandboxOptions():getOptionByName('PlantGrowingSeasons'):setValue(true)
    PlantingOptions.config.enabled:setValue(false)
end)
add(function() indicatorCheck('option-disabled',false,false) end)
add(function()
    PlantingOptions.config.enabled:setValue(true)
    local append=PlantingTooltip.append
    PlantingTooltip.append=function(target,state)
        local before=target:getHeight()
        local result=append(target,state)
        if growingTooltip and target==growingTooltip.tooltip then
            tooltipProbe.calls=tooltipProbe.calls+1
            assert(target:getHeight()>before,'growing tooltip added no layout height')
            assert(target:getWidth()<=getCore():getScreenWidth(),'growing tooltip wider than screen')
            assert(state.crop=='Carrots' and state.status=='best','tooltip lost native crop context')
            assert(state.texture and getTexture(state.texture),'native carrot crop texture absent')
        end
        return result
    end
    growingTooltip=ISToolTipInv:new(indicatorSamples.seed)
    growingTooltip:initialise(); growingTooltip:setCharacter(getPlayer()); growingTooltip.followMouse=false
    growingTooltip:setX(500); growingTooltip:setY(200)
    local render=growingTooltip.render
    growingTooltip.render=function(self,...)
        tooltipProbe={calls=0}
        local result=render(self,...)
        self.inventoryGrowingCalls=tooltipProbe.calls
        tooltipProbe=nil
        return result
    end
    growingTooltip:addToUIManager(); growingTooltip:setVisible(true)
end)
add(function()
    assert(growingTooltip.inventoryGrowingCalls==2,'expected one growing extension in each native measure/draw pass')
    assert(growingTooltip:getHeight()<getCore():getScreenHeight(),'growing tooltip taller than screen')
    assert(growingTooltip:getX()>=0 and growingTooltip:getX()+growingTooltip:getWidth()<getCore():getScreenWidth(),'growing tooltip clipped horizontally')
    assert(growingTooltip:getY()>=0 and growingTooltip:getY()+growingTooltip:getHeight()<getCore():getScreenHeight(),'growing tooltip clipped vertically')
    print('[INVENTORY_SCREEN] TOOLTIP native=true measure=1 draw=1 fits=true')
    shot('07-growing-tooltip')
    PlantingOptions.config.tooltip:setValue(false)
end)
add(function()
    assert(growingTooltip.inventoryGrowingCalls==0,'disabled growing tooltip still extended')
    print('[INVENTORY_SCREEN] TOOLTIP_DISABLED extension=0')
    growingTooltip:removeFromUIManager(); growingTooltip:setVisible(false)
end)
-- Pin state/options remain BC-owned. Only forwarded native draw calls are observed.
local Pins = require 'BetterContainers/Upgrades/PinnedItems'
local BCOptions = require 'BetterContainers/_Options'
local pinTexture = getTexture('media/ui/BetterContainers/PinnedItemMarker.png')
local pinProbe, pinSamples, seedResearch, addedSeedResearch, pinBaseWidth
local pinZoom=1
local function pinObserve(target)
    if target.inventoryPinObserved then return end
    target.inventoryPinObserved=true
    local render,draw=target.renderdetails,target.drawTextureScaled
    target.drawTextureScaled=function(self,texture,x,y,w,h,...)
        if pinProbe then
            local kind=texture==pinTexture and 'pin' or texture==Research.texture() and 'research'
                or (texture==getTexture('media/ui/circle.png') or texture==getTexture('media/ui/MP/mp_ui_star.png')) and 'season'
            if kind then pinProbe[kind][#pinProbe[kind]+1]={x=x,y=y,w=w,h=h} end
        end
        return draw(self,texture,x,y,w,h,...)
    end
    target.renderdetails=function(self,dragged,...)
        if dragged then return render(self,dragged,...) end
        pinProbe={icons={},pin={},research={},season={}}
        local result=render(self,dragged,...)
        self.inventoryPinFrame=pinProbe
        pinProbe=nil
        return result
    end
end
local function pinReflow()
    pane.zoom=pinZoom
    pane:onInventoryFontChanged()
    indicatorReflow()
    local expanded=false
    for _,group in ipairs(pane.itemslist) do
        local item=group.items and group.items[1]
        if item and item:getFullType()=='Base.CarrotSeed' then
            pane.collapsed[group.name]=false; expanded=true
        end
    end
    assert(expanded,'native seed stack missing')
    pane:refreshContainer(); pinObserve(pane)
end
local function pinCheck(name,enabled,scaled)
    local frame=assert(pane.inventoryPinFrame,'pin render absent')
    local expected={pin=0,research=0,season=0}
    local headers,children,allThree,pinnedHeaders=0,0,0,0
    for _,icon in ipairs(frame.icons) do
        local item=icon.item
        local seed=item:getFullType()=='Base.CarrotSeed'
        local research=seed or item==pinSamples.research
        local season=seed or item==pinSamples.packet
        local header=type(icon.row)=='table' and icon.row.items~=nil
        if header and Pins.isFavourite(item:getFullType()) then pinnedHeaders=pinnedHeaders+1 end
        local pinned=enabled and header and Pins.isFavourite(item:getFullType())
        local size=math.min(12,icon.width/2,icon.height/2)
        local twoRows=false
        if pinned and research and season then
            local across=math.min(size,(icon.width-2)/3)
            twoRows=across<8
            size=twoRows and math.min(12,icon.width/2,(icon.height-1)/2) or across
        end
        if research then markerAt(frame.research,icon.x,icon.y,size); expected.research=expected.research+1 end
        if season then markerAt(frame.season,icon.x+icon.width-size,icon.y,size); expected.season=expected.season+1 end
        if pinned then
            local pinSize=math.min(11,size)
            if pinSize>=8 then
                local x,y=icon.x,icon.y
                if research then x=season and icon.x+(icon.width-pinSize)/2 or icon.x+icon.width-pinSize end
                if twoRows then y=icon.y+icon.height-pinSize end
                assert(y+pane:getYScroll()+pinSize<=pane.height,'pin extends below the native pane')
                markerAt(frame.pin,x,y,pinSize); expected.pin=expected.pin+1
                assert(x>=icon.x and y>=icon.y and x+pinSize<=icon.x+icon.width and y+pinSize<=icon.y+icon.height,
                    'pin extends outside its native icon')
                if research and season then
                    local rectangles={{x=icon.x,y=icon.y,w=size,h=size},
                        {x=icon.x+icon.width-size,y=icon.y,w=size,h=size}, {x=x,y=y,w=pinSize,h=pinSize}}
                    for i=1,#rectangles do for j=i+1,#rectangles do
                        local a,b=rectangles[i],rectangles[j]
                        assert(a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y,'three badges overlap')
                    end end
                    allThree=allThree+1
                end
            end
        end
        if seed then
            if header then headers=headers+1 else children=children+1 end
            if scaled then assert(icon.width>pinBaseWidth,'native scale did not enlarge the seed icon') end
        end
    end
    assert(headers==1 and children==3,'expanded native stack must have one header and three physical children')
    assert(pinnedHeaders==4,'native pin fixture must render all four type headers')
    for _,kind in ipairs({'pin','research','season'}) do
        assert(#frame[kind]==expected[kind],'unexpected/duplicate '..kind..' marker')
    end
    if enabled then assert(allThree==1 and expected.pin==4,'all pinned headers, including all-three, must have one marker') end
    print('[INVENTORY_SCREEN] PINS '..name..' enabled='..tostring(enabled)..' headers=4 children=3 coords=actual once=true overlap=false')
    if name=='08-pins-clean' or name=='09-pins-clean-scaled' or name=='10-pins-vanilla' then shot(name) end
end
add(function()
    assert(pinTexture and PZSurvivorToolkit.BCPinCompatibility,'owned BC pin integration missing')
    local originalIcon=ISInventoryItem.renderItemIcon
    ISInventoryItem.renderItemIcon=function(owner,item,x,y,alpha,width,height,...)
        if pinProbe and owner==pane then
            local texture=item:getTex()
            pinProbe.icons[#pinProbe.icons+1]={item=item,x=x,y=y,width=width or texture:getWidthOrig(),
                height=height or texture:getHeightOrig(),row=owner.items[#owner.items]}
        end
        return originalIcon(owner,item,x,y,alpha,width,height,...)
    end
    -- This synthetic eligibility overlap uses real native ScriptItem recipe metadata.
    -- Existing scenes above independently prove ordinary native research and planting eligibility.
    local p=getPlayer(); p:getInventory():getItems():clear()
    local function item(id) return assert(p:getInventory():AddItem(id),'missing native pin item '..id) end
    pinSamples={seed=item('Base.CarrotSeed'),packet=item('Base.CarrotBagSeed2'),
        research=item('Base.BarbedWire'),plain=item('Base.CarrotBagSeed2_Empty')}
    item('Base.CarrotSeed'); item('Base.CarrotSeed')
    for i=0,researchRecipes:size()-1 do p:getKnownRecipes():remove(researchRecipes:get(i)) end
    seedResearch=pinSamples.seed:getScriptItem():getResearchableRecipes()
    addedSeedResearch=researchRecipes:get(0)
    assert(not seedResearch:contains(addedSeedResearch),'synthetic recipe already on native seed script')
    seedResearch:add(addedSeedResearch)
    assert(pinSamples.seed:getScriptItem():getResearchableRecipes(p,true):size()>0,'native combined research setup not eligible')
    local old={}; for fullType in pairs(Pins.FavouritedItems) do old[#old+1]=fullType end
    for _,fullType in ipairs(old) do Pins.setFavourite(fullType,false) end
    for _,sample in pairs(pinSamples) do Pins.setFavourite(sample:getFullType(),true) end
    BCOptions.showFavouritesOnPlayerInventories=true
    PlantingOptions.config.enabled:setValue(true)
    local cleanOptions=assert(PZAPI.ModOptions:getOptions('CleanUI'),'native CleanUI options missing')
    cleanOptions:getOption('uiScale'):setValue(100)
    inventory(true)
end)
add(pinReflow)
add(function()
    for _,icon in ipairs(assert(pane.inventoryPinFrame).icons) do
        if icon.item==pinSamples.seed then pinBaseWidth=icon.width; break end
    end
    assert(pinBaseWidth,'baseline native seed icon missing')
    pinCheck('08-pins-clean',true,false)
    pinZoom=2
    PZAPI.ModOptions:getOptions('CleanUI'):getOption('uiScale'):setValue(140)
end)
add(pinReflow)
add(function() pinCheck('09-pins-clean-scaled',true,true) end)
add(function() inventory(false) end)
add(pinReflow)
add(function() pinCheck('10-pins-vanilla',true,true); BCOptions.showFavouritesOnPlayerInventories=false end)
add(function() pinCheck('player-option-disabled',false,false); inventory(true) end)
add(pinReflow)
add(function()
    pinCheck('clean-player-option-disabled',false,true)
    seedResearch:remove(addedSeedResearch)
    assert(not seedResearch:contains(addedSeedResearch),'synthetic native recipe was not restored')
    for _,sample in pairs(pinSamples) do Pins.setFavourite(sample:getFullType(),false) end
    print('[INVENTORY_SCREEN] PIN_SETUP_RESTORED nativeRecipe=true')
end)
-- Wishlist state is isolated here; the real renderer and native pane rows remain in use.
local WishlistInventory = require 'PZSurvivorWishlist/Inventory'
local WishlistClient = require 'PZSurvivorWishlist/Client'
local WishlistSettings = require 'PZSurvivorWishlist/Settings'
local wishlistProbe, wishlistWanted, wishlistRows, wishlistRowsBefore, wishlistDraw
local function wishlistObserve(target)
    if target.inventoryWishlistObserved then return end
    target.inventoryWishlistObserved=true
    local render,border=target.renderdetails,target.drawRectBorder
    target.drawRectBorder=function(self,x,y,w,h,a,r,g,b,...)
        local colour=WishlistSettings.color()
        if wishlistProbe and a==0.7 and r==colour.r and g==colour.g and b==colour.b then
            wishlistProbe.borders[#wishlistProbe.borders+1]={x=x,y=y,w=w,h=h}
        end
        return border(self,x,y,w,h,a,r,g,b,...)
    end
    target.renderdetails=function(self,dragged,...)
        if dragged then return render(self,dragged,...) end
        wishlistProbe={calls=0,borders={}}
        local result=render(self,dragged,...)
        self.inventoryWishlistFrame=wishlistProbe
        wishlistProbe=nil
        return result
    end
end
local function wishlistReflow()
    pane.zoom=1; pane:onInventoryFontChanged()
    indicatorReflow()
    wishlistObserve(pane)
end
local function wishlistCheck(name,enabled)
    local frame=assert(pane.inventoryWishlistFrame,'Wishlist native render absent')
    assert(frame.calls==1,'Wishlist renderer must run once per native details pass')
    local index
    for i,row in ipairs(pane.items) do
        local matches=row==pinSamples.plain
        if type(row)=='table' and row.items then
            for _,item in ipairs(row.items) do if item==pinSamples.plain then matches=true end end
        end
        if matches then assert(not index,'Wishlist target has duplicate native rows'); index=i end
    end
    assert(index,'Wishlist target missing from native rows')
    local scroll=pane:getYScroll()
    local top=(index-1)*pane.itemHgt+pane.headerHgt
    assert(top+scroll>=pane.headerHgt and top+pane.itemHgt+scroll<=pane:getHeight(),
        'Wishlist target must be fully visible in the native pane')
    assert(#frame.borders==(enabled and 1 or 0),'Wishlist border missing, duplicated or enabled with Rows off')
    if enabled then
        local rect=frame.borders[1]
        local right=pane:getWidth()
        if pane.vscroll and pane.vscroll:getHeight()<pane:getScrollHeight() then right=right-pane.vscroll:getWidth() end
        assert(rect.x>=0 and rect.w>0 and rect.x+rect.w<=right,'Wishlist border outside native pane width')
        assert(rect.y==top and rect.h==pane.itemHgt,'Wishlist border does not match its actual native row')
        assert(rect.y+scroll>=pane.headerHgt and rect.y+rect.h+scroll<=pane:getHeight(),
            'Wishlist border extends outside native pane content')
    end
    print('[INVENTORY_SCREEN] WISHLIST '..name..' calls=1 borders='..#frame.borders..' target=visible bounds=true')
end
add(function()
    local state=WishlistClient.state(0)
    wishlistWanted=state.wanted
    state.wanted={[pinSamples.plain:getFullType()]=true}
    wishlistRows=PZAPI.ModOptions:getOptions('PZSurvivorWishlist'):getOption('Rows')
    wishlistRowsBefore=wishlistRows:getValue(); wishlistRows:setValue(true)
    wishlistDraw=WishlistInventory.draw
    WishlistInventory.draw=function(owner,...)
        if wishlistProbe and owner==pane then wishlistProbe.calls=wishlistProbe.calls+1 end
        return wishlistDraw(owner,...)
    end
    inventory(true)
end)
add(wishlistReflow)
add(function() wishlistCheck('clean',true); shot('11-wishlist-clean') end)
add(function() inventory(false) end)
add(wishlistReflow)
add(function() wishlistCheck('vanilla',true); shot('12-wishlist-vanilla') end)
add(function() inventory(true) end)
add(wishlistReflow)
add(function() wishlistCheck('clean-again',true); wishlistRows:setValue(false) end)
add(function()
    wishlistCheck('rows-disabled',false)
    WishlistClient.state(0).wanted=wishlistWanted
    wishlistRows:setValue(wishlistRowsBefore)
    WishlistInventory.draw=wishlistDraw
    assert(WishlistClient.state(0).wanted==wishlistWanted and wishlistRows:getValue()==wishlistRowsBefore,
        'Wishlist fixture state was not restored')
    print('[INVENTORY_SCREEN] WISHLIST_SETUP_RESTORED state=true rows=true renderer=true')
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
