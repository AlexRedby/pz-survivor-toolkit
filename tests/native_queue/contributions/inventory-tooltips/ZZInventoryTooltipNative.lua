-- Test-only forwarding observers. Items, ObjectTooltip and renderers stay native.
local Planting = require 'PZSurvivorToolkit/InventoryPlanting'
local PlantingOptions = require 'PZSurvivorToolkit/InventoryPlantingOptions'
local PlantingTooltip = require 'PZSurvivorToolkit/InventoryPlantingTooltip'
local MediaTooltip = require 'PZSurvivorToolkit/InventoryMediaTooltip'
local ClothingTooltip = require 'PZSurvivorToolkit/InventoryClothingTooltip'
local Media = require 'SVSIT_logic'
local entered, starting, started, complete, failed, ready = false, false, false, false, false, false
local steps, step, since = {}, 1, 0
local panel, active, seed, tape, clothing, worn, mediaId, mediaData, menu
local contextPage, contextPane, contextRenders
local clothingBaseHeight, clothingFlagHeight, menuOptionRect
local startupFrames=0
local function add(fn) steps[#steps + 1] = fn end
local function fadeClear()
    return UIManager.getFadeAlpha()<=0.001 and UIManager.getFadeAlpha(0)<=0.001
end
local function shot(name)
    assert(ready and fadeClear(),'screenshot requested before native fade completed')
    local filename = 'inventory-tooltip-' .. name .. '.png'
    getCore():TakeFullScreenshot(filename)
    print('[INVENTORY_TOOLTIP] SHOT ' .. filename)
end
local function hidePanel()
    if panel then panel:setVisible(false); panel:removeFromUIManager(); panel=nil end
end
local function appendObserver(module, kind)
    local append = module.append
    module.append = function(target, data)
        local frame = active and target==active.panel.tooltip and active
        local before = target:getHeight()
        local result = append(target, data)
        if frame then
            assert(frame.phase=='measure' or frame.phase=='draw', 'append outside a native tooltip pass')
            assert(target:getHeight()>before, 'extension added no native layout height')
            if kind=='vhs' then
                assert(data==mediaData and data==Media.RecMedia[Media.getMediaIdFromItemName(tape)],
                    'extension differs from upstream public media data')
                local width=0
                for _, values in ipairs({data.skillTexts,data.recipeTexts}) do
                    for _, value in ipairs(values) do
                        width=math.max(width,12+getTextManager():MeasureStringX(target:getFont(),'- '..value)+12)
                    end
                end
                assert(target:getWidth()>=width, 'native layout width excludes media text')
            else
                assert(data.crop=='Carrots' and data.status=='best', 'known native growing state changed')
            end
            frame.appends[#frame.appends+1]={kind=kind,phase=frame.phase,w=target:getWidth(),h=target:getHeight()}
        end
        return result
    end
end
appendObserver(PlantingTooltip,'growing')
appendObserver(MediaTooltip,'vhs')

local appendFlags=ClothingTooltip.appendFlags
ClothingTooltip.appendFlags=function(target,item,...)
    local frame=active and target==active.panel.tooltip and active
    local before=target:getHeight()
    local marked=item:isNoRecipes(target:getCharacter())
    local result=appendFlags(target,item,...)
    if frame then
        assert(item==clothing,'flag extension received a different native clothing item')
        assert(frame.phase=='measure' or frame.phase=='draw','flag extension outside a tooltip pass')
        local after=target:getHeight()
        assert((marked and after>before) or (not marked and after==before),
            'native NoRecipes state and appended layout height disagree')
        frame.flags[#frame.flags+1]={phase=frame.phase,marked=marked,before=before,h=after,w=target:getWidth()}
    end
    return result
end

local observedTooltipMethods
local function observePhases(target)
    local methods=assert(getmetatable(target).__index,'native ObjectTooltip metatable missing')
    if observedTooltipMethods then assert(observedTooltipMethods==methods); return end
    observedTooltipMethods=methods
    local setMeasureOnly=assert(methods.setMeasureOnly)
    methods.setMeasureOnly=function(value,measure,...)
        if active and value==active.panel.tooltip then active.phase=measure and 'measure' or 'draw' end
        return setMeasureOnly(value,measure,...)
    end
end
local function observePanel(target)
    if target.fixtureObserved then return end
    target.fixtureObserved=true
    observePhases(target.tooltip)
    local render,rect,border=target.render,target.drawRect,target.drawRectBorder
    target.drawRect=function(self,x,y,w,h,...)
        if active and self==active.panel then active.backgrounds[#active.backgrounds+1]={x=x,y=y,w=w,h=h} end
        return rect(self,x,y,w,h,...)
    end
    target.drawRectBorder=function(self,x,y,w,h,...)
        if active and self==active.panel then active.borders[#active.borders+1]={x=x,y=y,w=w,h=h} end
        return border(self,x,y,w,h,...)
    end
    target.render=function(self,...)
        assert(not active,'overlapping tooltip render')
        active={panel=self,appends={},flags={},backgrounds={},borders={},main=0,comparison=0}
        local result=render(self,...)
        self.fixtureFrame=active
        self.fixtureRenders=(self.fixtureRenders or 0)+1
        active=nil
        return result
    end
end
local function show(item,font,edge)
    hidePanel()
    getCore():setOptionTooltipFont(font)
    panel=ISToolTipInv:new(item)
    panel:initialise(); panel:setCharacter(getPlayer()); panel.followMouse=false
    panel:setX(edge and getCore():getScreenWidth()-4 or 150)
    panel:setY(edge and getCore():getScreenHeight()-4 or 110)
    observePanel(panel)
    panel:addToUIManager(); panel:setVisible(true)
end
local function fits()
    assert(panel:getWidth()>0 and panel:getHeight()>0,'empty native tooltip')
    assert(panel:getX()>=0 and panel:getX()+panel:getWidth()<getCore():getScreenWidth(),'tooltip clipped horizontally')
    assert(panel:getY()>=0 and panel:getY()+panel:getHeight()<getCore():getScreenHeight(),'tooltip clipped vertically')
end
local function clothingFrame(marked)
    local frame=assert(panel.fixtureFrame,'native clothing render absent')
    assert(frame.main==2 and frame.comparison==2 and #frame.appends==0,'BCI native comparison pipeline changed')
    assert(#frame.backgrounds==2 and #frame.borders==2,'BCI main/side backgrounds missing')
    assert(#frame.flags==2,'expected one flag extension in each BCI pass')
    local measure,draw=frame.flags[1],frame.flags[2]
    assert(measure.phase=='measure' and draw.phase=='draw','BCI flag measure/draw order changed')
    assert(measure.marked==marked and draw.marked==marked,'BCI flag receipt differs from native item state')
    assert(measure.before==draw.before and measure.h==draw.h and measure.w==draw.w,
        'BCI flag passes disagree on native layout dimensions')
    local main,side=frame.backgrounds[1],frame.backgrounds[2]
    assert(main.x==0 and main.y==0 and main.h>=draw.h and main.w>=draw.w,'BCI background excludes flag layout')
    assert(side.x>=main.x+main.w and side.y==0,'BCI comparison overlaps main content')
    for i,background in ipairs(frame.backgrounds) do
        local border=frame.borders[i]
        assert(border.x==background.x and border.y==background.y and border.w==background.w and border.h==background.h,
            'BCI border differs from content background')
        assert(background.x+background.w<=panel:getWidth() and background.y+background.h<=panel:getHeight(),
            'BCI window excludes main/comparison content')
    end
    fits()
    return frame
end
local function closeMenu()
    hidePanel()
    if menu then
        menu:hideAndChildren(); menu:setVisible(false); menu.visibleCheck=false; menu.joyfocus=nil
    end
end
local function openClothingMenu(joyfocus)
    hidePanel()
    menu=ISContextMenu.get(0,joyfocus and getCore():getScreenWidth()-260 or 300,180)
    menu.joyfocus=joyfocus and {} or nil
    menu:addOption('Inspect native denim shirt',nil,function() end)
    assert(menu:isAnyVisible(),'real clothing context menu is not visible')
end
local function attachClothingMenu()
    assert(menu:isAnyVisible() and menu.currentOptionRect,'real menu did not render an option rectangle')
    -- Native menu generates the rectangle. Programmatic attachment avoids physical hover input.
    show(clothing,'Small',false)
    panel:setContextMenu(menu); panel:setOwner(menu)
end
local function checkClothingMenu(joyfocus)
    clothingFrame(false)
    assert(menu:isAnyVisible() and panel:isVisible() and panel.contextMenu==menu and panel.owner==menu,
        'open context menu hid its own item tooltip')
    local rect=assert(menu.currentOptionRect,'native menu option rectangle missing')
    menuOptionRect={x=rect.x,y=rect.y,width=rect.width,height=rect.height}
    assert(not panel:overlaps({x=panel:getX(),y=panel:getY(),width=panel:getWidth(),height=panel:getHeight()},menuOptionRect),
        'clothing main/comparison window overlaps the real context option')
    if joyfocus then
        assert(panel:getX()==getPlayerScreenLeft(0)+60 and panel:getY()==getPlayerScreenTop(0)+60,
            'BCI joyfocus ignored the native player screen origin')
    end
    print('[INVENTORY_TOOLTIP] MENU '..(joyfocus and 'joyfocus' or 'option')..
        ' visible=true owner=menu nativeRect=true nonoverlap=true main=2 comparison=2 fits=true')
end
local function check(name,kind,font)
    local frame=assert(panel.fixtureFrame,'native UI render absent')
    -- This frame belongs to exactly one forwarded render, not a global tick count.
    assert(#frame.appends==2,'expected one append in each native pass')
    local measure,draw=frame.appends[1],frame.appends[2]
    assert(measure.kind==kind and draw.kind==kind and measure.phase=='measure' and draw.phase=='draw',
        'native measure/draw extension order changed')
    assert(measure.w==draw.w and measure.h==draw.h,'native passes disagree on extended dimensions')
    assert(#frame.backgrounds==1 and #frame.borders==1,'duplicate/missing native background')
    local bg,border=frame.backgrounds[1],frame.borders[1]
    assert(bg.x==0 and bg.y==0 and bg.w>=draw.w and bg.h>=draw.h,'native background excludes appended layout')
    assert(border.w==bg.w and border.h==bg.h,'native border excludes background')
    assert(panel:getWidth()>=draw.w and panel:getHeight()>=draw.h,'native window excludes appended layout')
    assert(panel.tooltip:getFont()==UIFont[font],'requested native tooltip font was not used')
    fits()
    print('[INVENTORY_TOOLTIP] DRAW '..name..' native=true measure=1 draw=1 background=true fits=true font='..font)
    shot(name)
end
add(function()
    assert(not isClient() and not isServer(),'SP required')
    for _,id in ipairs({'VHSSkillNameInTooltip','EURY_CLOTHINGINFO'}) do
        assert(getActivatedMods():contains(id),'required selected mod missing: '..id)
    end
    assert(MediaTooltip.installed and ISToolTipInv._vhsHooked,'upstream renderer guard was not installed')
    assert(BCI_TooltipInv_Active and EuryTooltipController and EuryTooltipController.providers.BetterClothingInfo,
        'selected BCI provider is inactive')
    assert(ClothingTooltip.installed,'BCI clothing adapter is inactive')
    local p=getPlayer(); p:setGodMod(true); p:setGhostMode(true); p:setAutoDrink(false)
    getCore():setOptionAutoDrink(false)
    if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
    if getPlayerInfoPanel and getPlayerInfoPanel(0) then getPlayerInfoPanel(0):setVisible(false) end
    getPlayerInventory(0):setVisible(false); getPlayerLoot(0):setVisible(false)
    p:getWornItems():clear(); p:setPrimaryHandItem(nil); p:setSecondaryHandItem(nil)
    p:getInventory():getItems():clear()
    seed=assert(p:getInventory():AddItem('Base.CarrotSeed'))
    local crop,props=Planting.resolve(seed)
    assert(crop=='Carrots' and props.seasonRecipe,'native seed season missing')
    p:learnRecipe(props.seasonRecipe); getGameTime():setMonth(5)
    getSandboxOptions():getOptionByName('PlantGrowingSeasons'):setValue(true)
    PlantingOptions.config.enabled:setValue(true); PlantingOptions.config.tooltip:setValue(true)
    PlantingOptions.config.badMonth:setValue(true)
    assert(Planting.describe(p,seed,false).status=='best','known June carrot state missing')
    local ids,both={},false
    local recorded=getZomboidRadio():getRecordedMedia()
    for id,data in pairs(Media.RecMedia) do
        if RecMedia[id] and string.find(RecMedia[id].category or '','VHS') and #data.skillTexts>0
            and recorded:getMediaData(id) then
            ids[#ids+1]=id
            if #data.recipeTexts>0 then both=true end
        end
    end
    table.sort(ids)
    for _,id in ipairs(ids) do
        if not both or #Media.RecMedia[id].recipeTexts>0 then mediaId=id; break end
    end
    assert(mediaId,'native skill VHS not available in upstream data')
    mediaData=Media.RecMedia[mediaId]
    tape=assert(p:getInventory():AddItem(RecMedia[mediaId].category=='Home-VHS' and 'Base.VHS_Home' or 'Base.VHS_Retail'))
    tape:setRecordedMediaData(recorded:getMediaData(mediaId))
    assert(instanceof(tape,'InventoryItem') and tape:isRecordedMedia() and tape:getMediaType()==1,'real VHS setup failed')
    assert(Media.getMediaIdFromItemName(tape)==mediaId,'normal native VHS display name does not match upstream API')
    print('[INVENTORY_TOOLTIP] MEDIA id='..mediaId..' skills='..#mediaData.skillTexts..' recipes='..#mediaData.recipeTexts..' bothAvailable='..tostring(both))
    print('[INVENTORY_TOOLTIP] SETUP SP native=true upstreamData=true bci=true')
    show(seed,'Large',true)
end)
add(function() check('01-growing-large-edge','growing','Large'); show(tape,'Small',false) end)
add(function() check('02-vhs','vhs','Small'); show(tape,'Large',true) end)
add(function()
    check('03-vhs-large-edge','vhs','Large')
    hidePanel()
    contextPage=getPlayerInventory(0); contextPane=contextPage.inventoryPane
    contextPage:setVisible(true); contextPage.isCollapsed=false; contextPage:setPinned()
    contextPane:setVisible(true); contextPane:setMode('details'); contextPane:refreshContainer()
    contextPane.doController=true; contextPane.joyselection=0
end)
add(function()
    local index
    for i,row in ipairs(contextPane.items) do
        local item=instanceof(row,'InventoryItem') and row or row.items and row.items[1]
        if item==tape then index=i; break end
    end
    assert(index,'actual inventory pane did not render native VHS row')
    contextPane.joyselection=index-1
    contextPane:updateTooltip()
    panel=assert(contextPane.toolRender,'actual pane did not create controller tooltip')
    assert(panel.item==tape and panel:isVisible() and panel.owner==contextPane,'actual pane does not own VHS tooltip')
    observePanel(panel)
end)
add(function()
    assert(panel.fixtureFrame and #panel.fixtureFrame.appends==2,'pane-owned VHS tooltip did not extend before menu opened')
    menu=ISContextMenu.get(0,30,30)
    menu:addOption('Native tooltip visibility check',nil,function() end)
    assert(menu:isAnyVisible(),'real player context menu is not visible')
    contextPane:updateTooltip()
    assert(not panel:isVisible(),'actual inventory pane did not hide its tooltip')
    contextRenders=panel.fixtureRenders
end)
add(function()
    assert(menu:isAnyVisible() and not panel:isVisible(),'context menu did not retain inventory-tooltip suppression')
    assert(panel.fixtureRenders==contextRenders,'hidden pane-owned tooltip rendered after context menu opened')
    assert(not UIManager.getUI():contains(panel.javaObject),'hidden inventory tooltip was re-added to UIManager')
    print('[INVENTORY_TOOLTIP] CONTEXT visible=true owner=inventory hidden=true removed=true renderDelta=0')
    menu:hideAndChildren(); menu:setVisible(false); menu.visibleCheck=false
    contextPane.doController=false; contextPage:setVisible(false)
    PlantingOptions.config.tooltip:setValue(false)
    show(seed,'Small',false)
end)
add(function()
    local frame=assert(panel.fixtureFrame)
    assert(#frame.appends==0 and #frame.backgrounds==1,'disabled growing section changed native fallback')
    print('[INVENTORY_TOOLTIP] DISABLED growing=true append=0 nativeBackground=true')
    local p=getPlayer()
    worn=assert(p:getInventory():AddItem('Base.Shirt_Denim'))
    clothing=assert(p:getInventory():AddItem('Base.Shirt_Denim'))
    assert(instanceof(worn,'Clothing') and instanceof(clothing,'Clothing'),'real native clothing required')
    worn:setCondition(math.max(1,math.floor(worn:getConditionMax()/2)))
    p:setWornItem(worn:getBodyLocation(),worn)
    assert(worn:isEquipped(),'native comparison baseline was not equipped')
    require('BCI/Options').UseKeybindForComparison:setValue(false)
    local preview=assert(BCI_GetClothingWearPreview(clothing,p),'native BCI wear preview missing')
    assert(#preview.replacedItems==1 and preview.replacedItems[1]==worn,'BCI comparison did not resolve native worn item')
    local provider=EuryTooltipController.providers.BetterClothingInfo
    local main=provider.renderMain
    provider.renderMain=function(self,ctx,...)
        if active and ctx.panel==active.panel then active.main=active.main+1 end
        return main(self,ctx,...)
    end
    local compare=BCI_RenderClothingWearPreview
    BCI_RenderClothingWearPreview=function(target,value,...)
        if active and target==active.panel.tooltip then
            assert(value.item==clothing and value.replacedItems[1]==worn,'rendered BCI comparison baseline changed')
            active.comparison=active.comparison+1
        end
        return compare(target,value,...)
    end
    show(clothing,'Small',false)
    assert(EuryTooltipController:findOwnerProvider(EuryTooltipController:getContext(panel))==provider,
        'BCI does not own clothing tooltip')
end)
add(function()
    local frame=clothingFrame(false)
    clothingBaseHeight=frame.backgrounds[1].h
    print('[INVENTORY_TOOLTIP] CLOTHING owner=BetterClothingInfo main=2 comparison=2 replaced=true extension=0 fits=true')
    shot('04-clothing')
    clothing:setNoRecipes(getPlayer(),true)
    assert(clothing:isNoRecipes(getPlayer()),'native NoRecipes marker was not set')
end)
add(function()
    local frame=clothingFrame(true)
    clothingFlagHeight=frame.backgrounds[1].h
    assert(clothingFlagHeight>clothingBaseHeight,'native NoRecipes label added no main background height')
    print('[INVENTORY_TOOLTIP] FLAGS marked=true native=true measure=1 draw=1 heightAdded=true comparison=true')
    shot('05-clothing-no-recipes')
    clothing:setNoRecipes(getPlayer(),false)
    assert(not clothing:isNoRecipes(getPlayer()),'native NoRecipes marker was not cleared')
end)
add(function()
    local frame=clothingFrame(false)
    assert(frame.backgrounds[1].h==clothingBaseHeight and frame.backgrounds[1].h<clothingFlagHeight,
        'cleared native NoRecipes label retained layout height')
    print('[INVENTORY_TOOLTIP] FLAGS marked=false native=true measure=1 draw=1 heightRestored=true comparison=true')
    shot('06-clothing-recipes-restored')
    show(clothing,'Small',true)
    panel.anchorBottomLeft={x=getCore():getScreenWidth()-4,y=getCore():getScreenHeight()-4}
end)
add(function()
    clothingFrame(false)
    assert(panel:getY()+panel:getHeight()<=panel.anchorBottomLeft.y,'BCI anchor did not place combined window above anchor')
    print('[INVENTORY_TOOLTIP] CLOTHING anchor=true rightEdge=true main=2 comparison=2 fits=true')
    shot('07-clothing-anchor-edge')
    openClothingMenu(false)
end)
add(function() attachClothingMenu() end)
add(function()
    checkClothingMenu(false)
    shot('08-clothing-context-option')
    closeMenu(); openClothingMenu(true)
end)
add(function() attachClothingMenu() end)
add(function()
    checkClothingMenu(true)
    shot('09-clothing-context-joyfocus')
    closeMenu()
    print('[INVENTORY_TOOLTIP] COMPLETE'); complete=true
end)
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
    if started and isIngameState() then setGameSpeed(1); startupFrames=startupFrames+1 end
    if not entered or starting or isIngameState() then return end
    starting=true; getCore():setOptionPauseOnFocusloss(false)
    getWorld():setGameMode('Sandbox'); getWorld():setWorld('InventoryTooltipNative'); getWorld():setMap('Muldraugh, KY')
    MainScreen.instance:setDefaultSandboxVars()
    for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2}) do
        getSandboxOptions():getOptionByName(name):setValue(value)
    end
    getSandboxOptions():toLua(); MainScreen.instance.createWorld=true
    MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
    MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
    MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
Events.OnGameStart.Add(function() started=true; since=getTimestampMs(); getCore():setOptionPauseOnFocusloss(false) end)
Events.OnTick.Add(function()
    if not started or failed then return end
    if complete then
        if getTimestampMs()-since>4000 then getCore():quitToDesktop() end
        return
    end
    if not ready then
        if startupFrames<10 or not fadeClear() then return end
        ready=true; since=getTimestampMs()
        print('[INVENTORY_TOOLTIP] READY fadeClear=true')
    end
    if getTimestampMs()-since<1800 then return end
    local ok,err=pcall(steps[step])
    if not ok then
        print('[INVENTORY_TOOLTIP] FAIL step='..step..' '..tostring(err))
        getCore():TakeFullScreenshot('inventory-tooltip-failed.png')
        failed=true -- Only the isolated runner may terminate a failed process.
        return
    end
    step=step+1; since=getTimestampMs()
end)
