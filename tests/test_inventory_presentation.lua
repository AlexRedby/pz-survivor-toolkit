-- Real Toolkit presenters; small layout owners expose separators, scaling and late UI classes.
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
function table.wipe(values) for key in pairs(values) do values[key]=nil end end
local function run(initialEnhanced, lateVanilla, withFreshness)
    local magazineEnabled, callbacks, modules = true, {}, {}
    getActivatedMods=function() return {contains=function(_, id) return withFreshness and id=='EURY_CONTAINERS' end} end
    instanceof=function(item,kind)
        return type(item)=='table' and ((kind=='Food' and item.food) or (kind=='InventoryItem' and item.getFullType~=nil))
    end
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
    for index,item in ipairs({a,b,magazine,weapon}) do
        item.getTex=function() return texture end
        item.getFullType=function() return 'Base.Item'..index end
    end
    local wishlistEnabled=false
    local wishlistBorders={}
    PZSurvivorWishlist={
        Client={isWanted=function(player,fullType) return player==1 and fullType==b:getFullType() end},
        Settings={rowsEnabled=function() return wishlistEnabled end, color=function() return {r=.25,g=.85,b=.75} end}}
    Events={OnFillInventoryObjectContextMenu={Add=function() end}}
    modules['PZSurvivorWishlist/Client']=PZSurvivorWishlist.Client
    modules['PZSurvivorWishlist/Settings']=PZSurvivorWishlist.Settings
    local alpha, nativeCalls, fallbacks, sorts = nil, 0, 0, 0
    ISInventoryItem = {renderItemIcon=function(_,_,_,_,value) alpha=value end}
    local function nativeRender(pane)
        nativeCalls=nativeCalls+1
        if pane.fail then error('native failure') end
        if pane.dirty then pane.items={}; pane:refreshContainer(); pane.dirty=false end
        pane.items={}
        for row, entry in ipairs(pane.rows) do
            pane.items[#pane.items+1]=entry
            if entry ~= 'separator' then
                local item=entry.items and entry.items[1] or entry
                if item:getTex() then
                    ISInventoryItem.renderItemIcon(pane,item,26,pane.headerHgt+(row-1)*pane.itemHgt,1,pane.iconSize,pane.iconSize)
                end
            end
        end
        return 'rendered'
    end
    local function paneClass()
        return {renderdetails=nativeRender, rendericons=nativeRender,
            drawItemDetails=function() fallbacks=fallbacks+1 end,
            refreshContainer=function(pane)
                if pane.failRefresh then error('refresh failure') end
                if pane.rebuiltGroups then
                    -- CleanUI refresh cannot capture an anchor after dirty
                    -- rendering wiped the physical row cache.
                    pane.itemslist=pane.rebuiltGroups
                    pane.selected={[4]=a}
                    pane.firstSelect=nil
                end
                return 'refreshed'
            end}
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
    local indicatorDraws={}
    local retentionDraws, retentionInvalidations = 0, 0
    modules['PZSurvivorToolkit/InventoryRetention']={
        draw=function(pane) assert(#pane.items==#pane.rows);retentionDraws=retentionDraws+1 end,
        invalidate=function() retentionInvalidations=retentionInvalidations+1 end}
    modules['PZSurvivorToolkit/InventoryIndicators']={drawIcon=function(_,item,x,y,w,h,details,group,researchContext)
        assert(type(researchContext)=="table", "render context missing")
        indicatorDraws[#indicatorDraws+1]={item=item,group=group,details=details,context=researchContext}
    end}
    modules['PZSurvivorToolkit/InventoryPlantingTooltip']={install=function() end}
    modules['PZSurvivorToolkit/InventoryDetails']={draw=function(_,_,_,_,_,_,layout) lastLayout=layout; return handleDetails end}
    local freshness={}
    freshness.install=function() freshness._installed=true end
    local freshnessOptions={showFoodFreshnessPercentage=true}
    modules['BetterContainers/_Options']=freshnessOptions
    modules['BetterContainers/Upgrades/FoodFreshness']=freshness
    local detailSortEnabled,realDetailSort=true,nil
    modules['PZSurvivorToolkit/InventoryDetailOptions']={enableSort={getValue=function() return detailSortEnabled end}}
    modules['PZSurvivorToolkit/InventoryDetailSort']={refresh=function(pane,class,anchor)
        sorts=sorts+1; assert(anchor==a, 'refresh captured another physical item as the Shift anchor')
        if not detailSortEnabled then return realDetailSort.refresh(pane,class,anchor) end
    end}
    require=function(name)
        if modules[name] then return modules[name] end
        if not name:match('^PZSurvivorToolkit/') and name~='PZSurvivorWishlist/Inventory' then return end
        if not modules[name] then modules[name]=dofile(root..name..'.lua') end
        return modules[name]
    end
    realDetailSort=dofile(root..'PZSurvivorToolkit/InventoryDetailSort.lua')
    local presenter=require 'PZSurvivorToolkit/InventoryPresentation'
    assert(#callbacks==1)
    local freshnessClass=ISInventoryPane
    local freshnessDraws=0
    local freshnessPresenter=modules['PZSurvivorToolkit/InventoryFreshness']
    local originalFreshnessDraw=freshnessPresenter.draw
    freshnessPresenter.draw=function(value,class)
        assert(#value.items==#value.rows,'freshness ran before native row publication')
        freshnessDraws=freshnessDraws+1
        return originalFreshnessDraw(value,class)
    end
    if withFreshness then freshness.install() end
    local rects={}
    local pane={rows={a,'separator',b,magazine,weapon},mode='details',height=500,width=400,headerHgt=20,itemHgt=46,iconSize=44,player=1,column3=330,font='Small',
        items={a},firstSelect=1,getYScroll=function(self) return self.scroll or 0 end,
        isReallyVisible=function() return true end,
        getIsVisible=function() return true end,
        setStencilRect=function() end,clearStencilRect=function() end,repaintStencilRect=function() end,
        getHeight=function(self) return self.height end,getWidth=function() return 400 end,
        drawRect=function(_,...) rects[#rects+1]={...} end,
        drawRectBorder=function(_,x,y,w,h,alpha,r,g,b)
            if alpha==.7 and r==.25 and g==.85 and b==.75 then
                wishlistBorders[#wishlistBorders+1]={y=y,h=h}
            end
        end}
    local function backgrounds()
        local values={}
        for _,rect in ipairs(rects) do if rect[4]==4 then values[#values+1]=rect end end
        return values
    end
    local previousRenderContext
    for _,enhanced in ipairs({true,false,true,false}) do
        toggle(enhanced)
        presenter.install() -- repeated callbacks must not add another layer
        setmetatable(pane,{__index=ISInventoryPane})
        rects={}
        local before=nativeCalls
        local beforeIcons=#indicatorDraws
        local retainedBefore=retentionDraws
        local freshnessBefore=freshnessDraws
        assert(pane:renderdetails(false)=='rendered' and nativeCalls==before+1)
        local renderContext=indicatorDraws[beforeIcons+1].context
        assert(renderContext~=previousRenderContext, 'research context survived a render/mode switch')
        for i=beforeIcons+1,#indicatorDraws do assert(indicatorDraws[i].context==renderContext) end
        previousRenderContext=renderContext
        assert(retentionDraws==retainedBefore+1, 'retention markers missing or duplicated across UI class changes')
        assert(freshnessDraws==freshnessBefore+1,'freshness missing or duplicated across UI class changes')
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
        local invalidated=retentionInvalidations
        assert(pane:refreshContainer()=='refreshed' and sorts==sorted+1)
        assert(retentionInvalidations==invalidated+1, 'retention cache survived refresh')
        retainedBefore=retentionDraws;freshnessBefore=freshnessDraws
        rects={}; pane:renderdetails(true); assert(#rects==0,'drag preview decorated')
        rects={}; pane:rendericons(); assert(#backgrounds()==3,'icon view lost overlays')
        assert(retentionDraws==retainedBefore, 'drag/icon grid received retention row markers')
        assert(freshnessDraws==freshnessBefore,'drag/icon grid received freshness rows')
    end
    -- Native dirty rendering clears row identities before it invokes refresh.
    local beforeSort=sorts; pane.dirty=true; pane:renderdetails(false)
    assert(sorts==beforeSort+1,'dirty render did not refresh with its physical Shift anchor')
    -- Stack/retention ordering is independent of optional detail sorting.
    -- Mirror CleanUI's wipe-before-refresh and nil-anchor restoration, then
    -- require the exact physical child to follow its moved group.
    local target,other={name='target',items={a,a}},{name='other',items={b,b}}
    for _,enhanced in ipairs({true,false}) do
        toggle(enhanced);setmetatable(pane,{__index=ISInventoryPane})
        pane.items={target,a,other,b};pane.firstSelect=2
        pane.itemslist={target,other};pane.collapsed={}
        pane.rebuiltGroups={other,target};pane.rows={other,b,target,a}
        detailSortEnabled=false
        -- Host packets and pane refreshes can run more than once before the
        -- next render. The new anchor index must not read the previous map.
        pane:refreshContainer();pane:refreshContainer()
        assert(pane.firstSelect==4,
            'repeated refresh read the new Shift anchor from stale rendered rows')
        pane.dirty=true;pane:renderdetails(false)
        assert(pane.firstSelect==4 and pane.items[pane.firstSelect]==a,
            'dirty refresh lost the physical Shift anchor with detail sorting disabled')
        assert(pane.selected[4]==a and pane.items[4]==a,
            'anchor restoration changed the exact physical selection')
    end
    pane.rebuiltGroups=nil;pane.itemslist=nil;detailSortEnabled=true
    pane.rows={a,'separator',b,magazine,weapon};pane.firstSelect=1
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
    local freshnessBefore=freshnessDraws
    pane.fail=true; assert(not pcall(pane.renderdetails,pane,false)); pane.fail=false
    assert(freshnessDraws==freshnessBefore,'failed native render decorated stale freshness rows')
    rects={}; ISInventoryItem.renderItemIcon(pane,a,0,0); assert(alpha==1 and #rects==0,'render context leaked')
    ISInventoryItem.renderItemIcon(pane,a,0,0,0); assert(alpha==0)
    -- The same physical item can be a stack representative and its first child.
    -- The icon callback must capture each row, not inspect the completed cache.
    pane.rows={{items={a,a,b}},a,b}
    for _, enhanced in ipairs({true,false}) do
        toggle(enhanced); setmetatable(pane,{__index=ISInventoryPane})
        indicatorDraws={}; pane:renderdetails(false)
        assert(#indicatorDraws==3 and indicatorDraws[1].item==a and indicatorDraws[2].item==a)
        assert(indicatorDraws[1].group and not indicatorDraws[2].group and not indicatorDraws[3].group,
            'native header identity was reconstructed from final rows')
        indicatorDraws={}; pane:rendericons()
        for _,draw in ipairs(indicatorDraws) do assert(not draw.group and not draw.details) end
        indicatorDraws={}; pane:renderdetails(true); assert(#indicatorDraws==0)
    end
    -- Full-row Wishlist overlays share the class lifecycle, not the icon stream.
    -- A mixed header matches through b even when its representative a is not wanted.
    wishlistEnabled=true
    for _,enhanced in ipairs({true,false,true}) do
        toggle(enhanced); presenter.install(); setmetatable(pane,{__index=ISInventoryPane})
        pane.rows={{items={a,a,b}},a,b}; pane.scroll=-5
        wishlistBorders={}; local before=nativeCalls
        pane:renderdetails(false)
        assert(nativeCalls==before+1 and #wishlistBorders==2,'Wishlist missing or duplicated across class changes')
        assert(wishlistBorders[1].y==25 and wishlistBorders[1].h==41,'Wishlist covered the fixed header')
        assert(wishlistBorders[2].y==112 and wishlistBorders[2].h==46)
        local getter=b.getTex; b.getTex=function() end
        wishlistBorders={}; pane:renderdetails(false); assert(#wishlistBorders==2,'textureless wanted row lost its highlight')
        b.getTex=getter
        pane.dragging=true; pane.dragStarted=true; pane.selected={[3]=true}
        wishlistBorders={}; pane:renderdetails(false); assert(#wishlistBorders==1,'dragged row highlighted at its old position')
        pane.dragging=nil; pane.dragStarted=nil; pane.selected=nil
        wishlistBorders={}; pane:renderdetails(true); assert(#wishlistBorders==0,'drag preview highlighted')
        pane:rendericons(); assert(#wishlistBorders==0,'icon grid received full-row highlights')
        wishlistEnabled=false; pane:renderdetails(false); assert(#wishlistBorders==0,'disabled Wishlist still highlighted')
        wishlistEnabled=true
        pane.fail=true; assert(not pcall(pane.renderdetails,pane,false)); pane.fail=false
        assert(#wishlistBorders==0,'failed native render decorated stale rows')
    end
    -- The invalidation belongs before native refresh, even if rebuilding fails.
    pane.pzswRowTypes={retained=true}; pane.failRefresh=true
    assert(not pcall(pane.refreshContainer,pane))
    assert(next(pane.pzswRowTypes)==nil,'failed native refresh retained the previous membership summary')
    pane.failRefresh=nil
    local capacity=require 'PZSurvivorToolkit/InventoryCapacity'
    assert(capacity.ratio(inventory(12,10),{})==1 and capacity.ratio(inventory(-1,10),{})==0)
    assert(capacity.ratio(inventory(0,0),{})==nil)
end
run(true,false); run(false,false); run(true,true); run(true,false,true); run(false,false,true)

-- Summary ownership follows refresh and the final native row projection.
-- Count work, rather than wall time, so a collapsed huge stack stays cheap
-- without losing a wanted child beyond the owner's rendered-child limit.
local function rowSummaryChecks()
    local typeReads, wantedCalls, wantedEnabled, enabled = 0, 0, true, true
    PZSurvivorWishlist={Client={isWanted=function(player, fullType)
        wantedCalls=wantedCalls+1
        return wantedEnabled and player==1 and fullType=='Base.Wanted'
    end},Settings={rowsEnabled=function() return enabled end}}
    local Inventory=dofile(root..'PZSurvivorWishlist/Inventory.lua')
    local function item(fullType)
        return {getFullType=function() typeReads=typeReads+1; return fullType end}
    end
    local ordinary, target=item('Base.Ordinary'),item('Base.Wanted')
    local group={name='same display name',items={ordinary}}
    for index=2,5001 do group.items[index]=ordinary end
    group.items[5001]=target
    local pane={player=1,items={group},itemHgt=20,collapsed={[group.name]=true},
        getYScroll=function(self) return self.scroll or 0 end,
        getHeight=function(self) return self.height or 20 end}
    Inventory.invalidate(pane)
    assert(#Inventory.marks(pane)==1 and typeReads==5001 and wantedCalls==2,
        'collapsed mixed stack lost its wanted child beyond the render cap')
    typeReads,wantedCalls=0,0
    assert(#Inventory.marks(pane)==1 and typeReads==0 and wantedCalls==2,
        'steady redraw walked physical children instead of unique types')
    wantedEnabled=false; wantedCalls=0
    assert(#Inventory.marks(pane)==0 and typeReads==0 and wantedCalls==2,
        'cached row retained stale wanted state after a server update')
    wantedEnabled=true
    assert(#Inventory.marks(pane)==1 and typeReads==0,'wanted reactivation required a container refresh')

    -- OC pin projection can retain a source row while replacing its items.
    local replacement={}
    for index=1,5001 do replacement[index]=ordinary end
    group.items=replacement
    typeReads,wantedCalls=0,0
    assert(#Inventory.marks(pane)==0 and typeReads==5001 and wantedCalls==1,
        'same-count items-table replacement reused the old type set')
    group.items[5001]=target
    Inventory.invalidate(pane)
    typeReads=0
    assert(#Inventory.marks(pane)==1 and typeReads==5001,
        'refresh invalidation missed a same-table same-count replacement')
    group.items[5001]=ordinary
    group.items[#group.items+1]=target
    typeReads=0
    assert(#Inventory.marks(pane)==1 and typeReads==5002,'changed membership count reused a summary')

    -- Filter projection shallow-copies metadata but supplies different items.
    local filtered={}
    for key,value in pairs(group) do filtered[key]=value end
    filtered.items={ordinary,ordinary}
    pane.items={filtered}; typeReads=0
    assert(#Inventory.marks(pane)==0 and typeReads==2,'filtered group inherited an unwanted summary')
    assert(group.pzswRowTypes==nil and filtered.pzswRowTypes==nil,'summary leaked into row metadata')

    -- Each draw retires offscreen, dragged, disabled and absent groups.
    local second={items={target,target}}
    pane.items={filtered,second}; pane.scroll=0
    Inventory.marks(pane)
    assert(pane.pzswRowTypes[filtered] and not pane.pzswRowTypes[second])
    pane.scroll=-20; typeReads=0
    assert(#Inventory.marks(pane)==1 and typeReads==2)
    assert(not pane.pzswRowTypes[filtered] and pane.pzswRowTypes[second],'offscreen row retained')
    pane.dragging=true; pane.dragStarted=true; pane.selected={[2]=true}
    assert(#Inventory.marks(pane)==0 and next(pane.pzswRowTypes)==nil,'dragged row retained')
    pane.dragging=nil; pane.dragStarted=nil
    Inventory.marks(pane); enabled=false
    assert(#Inventory.marks(pane)==0 and next(pane.pzswRowTypes)==nil,'disabled rows retained')
    enabled=true; Inventory.marks(pane); pane.items={}
    assert(#Inventory.marks(pane)==0 and next(pane.pzswRowTypes)==nil,'empty pane retained groups')

    -- Standalone consumers have no refresh owner: preserve live scanning.
    local live={items={ordinary,ordinary}}
    local unmanaged={player=1,items={live},itemHgt=20,getYScroll=pane.getYScroll,getHeight=pane.getHeight}
    assert(#Inventory.marks(unmanaged)==0)
    live.items[2]=target
    assert(#Inventory.marks(unmanaged)==1 and unmanaged.pzswRowTypes==nil,
        'unmanaged pane cached an unobservable in-place mutation')
end
rowSummaryChecks()
print('inventory presentation: actual icon coordinates, modes, settings, details boundary and pooled buttons passed')
