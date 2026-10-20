-- Real Toolkit presenters; small layout owners expose separators, scaling and late UI classes.
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
local function run(initialEnhanced, lateVanilla, withFreshness)
    local magazineEnabled, callbacks, modules = true, {}, {}
    getActivatedMods=function() return {contains=function(_, id) return withFreshness and id=='EURY_CONTAINERS' end} end
    instanceof=function(item,kind) return kind=='Food' and item.food end
    getTextManager=function() return {MeasureStringX=function() return 28 end} end
    PZAPI = {ModOptions={create=function(_, id)
        assert(id == 'ContainerCapacityIndicator', 'persisted preferences must keep their key')
        return {addTickBox=function() return {getValue=function() return magazineEnabled end} end}
    end}}
    getSpecificPlayer = function(index) return {index=index} end
    local function inventory(used, capacity)
        return {getEffectiveCapacity=function() return capacity end, getCapacityWeight=function() return used end}
    end
    local function bag(used, capacity)
        return {IsInventoryContainer=function() return true end, getInventory=function() return inventory(used,capacity) end}
    end
    local texture={getWidthOrig=function() return 24 end,getHeightOrig=function() return 40 end}
    local a, b = bag(2,10), bag(10,10)
    local ammo = 8
    local magazine = {IsWeapon=function() return false end, getMaxAmmo=function() return 16 end,
        getCurrentAmmoCount=function() return ammo end, getAmmoType=function() return '9mm' end}
    local weapon = {IsWeapon=function() return true end, getMaxAmmo=magazine.getMaxAmmo,
        getCurrentAmmoCount=magazine.getCurrentAmmoCount, getAmmoType=magazine.getAmmoType}
    for _,item in ipairs({a,b,magazine,weapon}) do item.getTex=function() return texture end end
    local alpha, nativeCalls, fallbacks, sorts = nil, 0, 0, 0
    ISInventoryItem = {renderItemIcon=function(_,_,_,_,value) alpha=value end}
    local function nativeRender(pane)
        nativeCalls=nativeCalls+1
        if pane.fail then error('native failure') end
        if pane.dirty then pane.items={}; pane:refreshContainer(); pane.dirty=false end
        for row, item in ipairs(pane.rows) do
            if item ~= 'separator' then
                ISInventoryItem.renderItemIcon(pane,item,26,pane.headerHgt+(row-1)*pane.itemHgt,1,pane.iconSize,pane.iconSize)
            end
        end
        return 'rendered'
    end
    local function paneClass()
        return {renderdetails=nativeRender, rendericons=nativeRender,
            drawItemDetails=function() fallbacks=fallbacks+1 end,
            refreshContainer=function() return 'refreshed' end}
    end
    local button = {getWidth=function() return 32 end,getHeight=function() return 32 end,
        drawRect=function(self,...) self.rects[#self.rects+1]={...} end,drawRectBorder=function() end,
        render=function(self) self.original=(self.original or 0)+1 end,rects={}}
    local function pageClass()
        return {addContainerButton=function(_, inv) button.inventory=inv; return button end}
    end
    CleanUI_Clean_ISInventoryPane, CleanUI_Clean_ISInventoryPage=paneClass(),pageClass()
    local vanilla, vanillaPage=paneClass(),pageClass()
    CleanUI_Vanilla_ISInventoryPane=not lateVanilla and vanilla or nil
    CleanUI_Vanilla_ISInventoryPage=not lateVanilla and vanillaPage or nil
    local function toggle(enhanced)
        if not enhanced then CleanUI_Vanilla_ISInventoryPane, CleanUI_Vanilla_ISInventoryPage=vanilla,vanillaPage end
        ISInventoryPane=enhanced and CleanUI_Clean_ISInventoryPane or vanilla
        ISInventoryPage=enhanced and CleanUI_Clean_ISInventoryPage or vanillaPage
        for _,callback in ipairs(callbacks) do callback(enhanced) end
    end
    toggle(initialEnhanced)
    CleanUI_RegisterInventoryUiToggleCallback=function(callback) callbacks[#callbacks+1]=callback; callback(initialEnhanced) end
    local handleDetails=true
    local lastLayout
    modules['PZSurvivorToolkit/InventoryIndicators']={drawIcon=function() end}
    modules['PZSurvivorToolkit/InventoryPlantingTooltip']={install=function() end}
    modules['PZSurvivorToolkit/InventoryDetails']={draw=function(_,_,_,_,_,_,layout) lastLayout=layout; return handleDetails end}
    local freshness={}
    freshness.install=function() freshness._installed=true end
    local freshnessOptions={showFoodFreshnessPercentage=true}
    modules['BetterContainers/_Options']=freshnessOptions
    modules['BetterContainers/Upgrades/FoodFreshness']=freshness
    modules['PZSurvivorToolkit/InventoryDetailSort']={refresh=function(_,_,anchor) sorts=sorts+1; assert(anchor==a) end}
    require=function(name)
        if modules[name] then return modules[name] end
        if not name:match('^PZSurvivorToolkit/') then return end
        if not modules[name] then modules[name]=dofile(root..name..'.lua') end
        return modules[name]
    end
    local presenter=require 'PZSurvivorToolkit/InventoryPresentation'
    assert(#callbacks==1)
    local freshnessClass=ISInventoryPane
    if withFreshness then freshness.install() end
    local rects={}
    local pane={rows={a,'separator',b,magazine,weapon},height=500,headerHgt=20,itemHgt=46,iconSize=44,player=1,column3=330,font='Small',
        items={a},firstSelect=1,getYScroll=function(self) return self.scroll or 0 end,
        drawRect=function(_,...) rects[#rects+1]={...} end,drawRectBorder=function() end}
    local function backgrounds()
        local values={}
        for _,rect in ipairs(rects) do if rect[4]==4 then values[#values+1]=rect end end
        return values
    end
    for _,enhanced in ipairs({true,false,true,false}) do
        toggle(enhanced)
        presenter.install() -- repeated callbacks must not add another layer
        setmetatable(pane,{__index=ISInventoryPane})
        rects={}
        local before=nativeCalls
        assert(pane:renderdetails(false)=='rendered' and nativeCalls==before+1)
        local bars=backgrounds()
        assert(#bars==3,'bag/magazine indicator missing or duplicated')
        assert(bars[1][1]==27 and bars[1][2]==60 and bars[1][3]==42,'actual scaled icon geometry lost')
        assert(bars[2][2]==152,'separator row was not respected')
        assert(bars[3][5]==0.92,'loose magazine indicator missing')
        local prior=fallbacks
        pane:drawItemDetails(a,0,0,0,false)
        assert(fallbacks==prior)
        handleDetails=false; pane:drawItemDetails(a,0,0,0,false); handleDetails=true
        assert(fallbacks==prior+1,'native fallback must run once')
        local food={food=true,getOffAgeMax=function() return 10 end}
        pane:drawItemDetails(food,0,0,0,false)
        if withFreshness and ISInventoryPane==freshnessClass then
            assert(lastLayout and lastLayout.reservedLeft==302 and lastLayout.reservedRight==330)
            freshnessOptions.showFoodFreshnessPercentage=false
            pane:drawItemDetails(food,0,0,0,false); assert(lastLayout==nil)
            freshnessOptions.showFoodFreshnessPercentage=true
        else assert(lastLayout==nil,'freshness space reserved on a class without the overlay') end
        local sorted=sorts
        assert(pane:refreshContainer()=='refreshed' and sorts==sorted+1)
        rects={}; pane:renderdetails(true); assert(#rects==0,'drag preview decorated')
        rects={}; pane:rendericons(); assert(#backgrounds()==3,'icon view lost overlays')
    end
    -- Native dirty rendering clears row identities before it invokes refresh.
    local beforeSort=sorts; pane.dirty=true; pane:renderdetails(false)
    assert(sorts==beforeSort+1,'dirty render did not refresh with its physical Shift anchor')
    pane.items={a}
    -- Unscaled icon view uses texture dimensions, including non-square icons.
    pane.iconSize=nil; pane.rows={a}; rects={}; pane:rendericons()
    assert(backgrounds()[1][2]==56 and backgrounds()[1][3]==22)
    local textureGetter=a.getTex; a.getTex=function() end; rects={}; pane:rendericons(); assert(#rects==0)
    a.getTex=textureGetter; pane.iconSize=44
    -- Header clipping uses the actual bar, without changing scroll or drawing methods.
    pane.rows={a}; pane.scroll=-45; rects={}; pane:renderdetails(false); assert(#rects==0)
    pane.scroll=-39; rects={}; pane:renderdetails(false); assert(#backgrounds()==1)
    pane.scroll=0; pane.rows={magazine}; magazineEnabled=false; rects={}; pane:renderdetails(false); assert(#rects==0)
    magazineEnabled=true
    for _,count in ipairs({0,1,8,15,16}) do
        ammo=count; rects={}; pane:renderdetails(false)
        local fill=0
        for _,rect in ipairs(rects) do if rect[5]==0.98 then fill=fill+1 end end
        local expected=({[0]=0,[1]=1,[8]=2,[15]=3,[16]=4})[count]
        assert(fill==expected,'magazine fullness segment changed')
    end
    for _,enhanced in ipairs({false,true,false}) do
        toggle(enhanced)
        local page=setmetatable({player=1},{__index=ISInventoryPage})
        local result=page:addContainerButton(inventory(9,10))
        button.rects={}; local before=button.original or 0; result:render()
        assert(button.original==before+1 and #button.rects==2,'pooled button double wrapped')
        assert(button.rects[1][1]==2 and button.rects[1][2]==26 and button.rects[2][3]==23)
        assert(button.toolkitCapacityPlayer==1)
    end
    pane.fail=true; assert(not pcall(pane.renderdetails,pane,false)); pane.fail=false
    rects={}; ISInventoryItem.renderItemIcon(pane,a,0,0); assert(alpha==1 and #rects==0,'render context leaked')
    ISInventoryItem.renderItemIcon(pane,a,0,0,0); assert(alpha==0)
    local capacity=require 'PZSurvivorToolkit/InventoryCapacity'
    assert(capacity.ratio(inventory(12,10),{})==1 and capacity.ratio(inventory(-1,10),{})==0)
    assert(capacity.ratio(inventory(0,0),{})==nil)
end
run(true,false); run(false,false); run(true,true); run(true,false,true); run(false,false,true)
print('inventory presentation: actual icon coordinates, modes, settings, details boundary and pooled buttons passed')
