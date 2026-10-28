-- Source-backed movement scheduling + real BC aggregation; UI/world are doubles.
-- B42.21 Kahlua rawget follows the table's metatable (KahluaTableImpl.rawget),
-- unlike standard Lua 5.1. Use the engine lookup contract with native-style
-- direct class metatables so an inherited refresh cannot look like an override.
local luaRawget = rawget
rawget = function(owner, key)
    local value = luaRawget(owner, key)
    if value ~= nil then return value end
    local class = getmetatable(owner)
    if class then return rawget(class, key) end
end
table.wipe=table.wipe or function(t)for key in pairs(t)do t[key]=nil end end
local client=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'
local function method(source,name)
    if not source then return end
    local normalized=source:gsub('CleanUI_Vanilla_ISInventoryPage','ISInventoryPage')
    return normalized:match('(function ISInventoryPage:'..name..'%b().-)\nfunction ')
end
local function run(source,label,bcSource)
    local stats={discovery=0,rows=0,count=0,copied=0,events=0}
    local function pack(...)return {n=select('#',...),...}end
    local function event() local handlers={};return {Add=function(fn) handlers[#handlers+1]=fn end,
        fire=function(...) for _,fn in ipairs(handlers) do fn(...) end end} end
    Events={OnGameBoot=event(),OnGameStart=event()}
    PZSurvivorToolkit={};ISMouseDrag={};JoypadState={players={}}
    instanceof=function() return false end
    local player={dir=0,square={},joypad=-1}
    function player:getDir() return self.dir end
    function player:getCurrentSquare() return self.square end
    function player:getJoypadBind() return self.joypad end
    function player:isAiming()return false end
    getSpecificPlayer=function() return player end
    isClient=function()return false end
    isGamePaused=function()return false end
    isKeyDown=function()return false end
    isMouseButtonDown=function()return false end
    KeybindId={PAN_CAMERA='PanCamera'}
    local eff={proximityActive=true}
    local options={getEffectivePermissions=function() return eff end}
    getTexture=function() return {} end
    require=function(name)
        if name=='BetterContainers/_Options' then return options end
        return {}
    end
    local proximity=bcSource and assert(loadstring(bcSource))()
    local function list(n)
        return {n=n,size=function(self) return self.n end,
            clear=function(self) self.n=0 end,
            addAll=function(self,items) self.n=self.n+items.n;stats.copied=stats.copied+items.n end}
    end
    local function inventory(kind,n)
        return {contents=list(n),getType=function() return kind end,getParent=function() end,
            getItems=function(self) return self.contents end,getEffectiveCapacity=function() return 100 end}
    end
    local aggregate=inventory('proximityInv',0)
    local sources={}
    for i=1,12 do sources[i]=inventory('crate',400) end
    local Pane={};Pane.__index=Pane
    function Pane:refreshContainer()
        stats.rows=stats.rows+1
        if self.failRows then error('row rebuild failure') end
        self.builtCount=self.inventory:getItems():size()
        self.itemslist={{name='fresh',items={}}}
        return 'rows',nil,17
    end
    local Page={};Page.__index=Page
    function Page:getIsVisible() return self.visible end
    function Page:setVisible(value) self.visible=value;return 'visible' end
    function Page:updateItemCount() stats.count=stats.count+1;self.totalItems=self.inventory:getItems():size() end
    function Page:refreshBackpacks()
        stats.discovery=stats.discovery+1
        if self.failDiscovery then error('discovery failure') end
        self.backpacks={}
        for _,container in ipairs(sources) do self.backpacks[#self.backpacks+1]={inventory=container,getBottom=function()return 100 end} end
        local button={inventory=aggregate,getBottom=function()return 100 end}
        self.backpacks[#self.backpacks+1]=button
        if proximity then
            proximity.itemContainer[0]=aggregate;proximity.inventoryButtonRef[0]=button
            proximity.OnButtonsAdded(self)
        else
            aggregate.contents:clear()
            for _,container in ipairs(sources) do aggregate.contents:addAll(container.contents) end
        end
        stats.events=stats.events+1
        self.inventoryPane.inventory=aggregate;self.inventory=aggregate
        self.inventoryPane:refreshContainer()
        self:updateItemCount()
        if self.afterDiscovery then self:afterDiscovery() end
        return 'discovery',nil,29
    end
    function Page:updateContainerHighlight() end
    function Page:titleBarHeight() return 20 end
    function Page:updateContainerOpenCloseSounds() end
    function Page:prerender() self.renderedCount=self.totalItems;return 'draw',nil,43,nil end
    function Page:clearMaxDrawHeight()self.clipCleared=true end
    function Page:getMouseY()return 0 end
    if source then
        ISInventoryPage=Page
        assert(loadstring(assert(method(source,'update'),'missing upstream update')))()
        assert(loadstring(assert(method(source,'onMouseMove'),'missing upstream hover expansion')))()
    else
        function Page:onMouseMove()self.isCollapsed=false;self:clearMaxDrawHeight()end
        function Page:update()
            if self.pin or (ISMouseDrag.dragging and #ISMouseDrag.dragging>0)then
                self.isCollapsed=false;self:clearMaxDrawHeight()
            end
            if self.lastDir~=player:getDir() then self.lastDir=player:getDir();self:refreshBackpacks()
            elseif self.lastSquare~=player:getCurrentSquare() then self.lastSquare=player:getCurrentSquare();self:refreshBackpacks() end
        end
    end
    local originalUpdate=Page.update
    Page.update=function(self,...)originalUpdate(self,...);return 'update',nil,41,nil end
    local function makePage()
        local page=setmetatable({player=0,visible=false,lastDir=player.dir,lastSquare=player.square,
            inventory=aggregate,capacity=100,inventoryPane=setmetatable({mode='details',selected={},items={}},Pane),
            backpacks={{getBottom=function()return 100 end}},height=200,resizeWidget={height=10},
            containerButtonPanel={setHeight=function()end,setY=function()end,setScrollHeight=function()end}},Page)
        page.inventoryPane.parent=page;page.inventoryPane.height=100;page.inventoryPane.y=20
        return page
    end
    -- Negative control uses the same unmodified upstream scheduler before the
    -- optimization is installed, including both calls after each changed pose.
    local baseline=makePage()
    for i=1,40 do
        player.dir=i;player.square={}
        baseline:update();baseline:update()
    end
    assert(stats.discovery==80 and stats.rows==80 and stats.count==80,
        'unoptimized simultaneous turn/tile changes must perform 80 full rebuilds')
    assert(stats.copied==384000 and stats.events==80,'baseline BC aggregation/event workload changed')
    for key in pairs(stats) do stats[key]=0 end
    player.dir,player.square=0,{}
    local page=makePage()
    ISInventoryPage=Page;CleanUI_Clean_ISInventoryPage=nil;CleanUI_Vanilla_ISInventoryPage=nil
    local callbacks={}
    CleanUI_RegisterInventoryUiToggleCallback=function(fn)callbacks[#callbacks+1]=fn;fn()end
    require=function(name)
        if name=='PZSurvivorToolkit/InventoryClasses' then return dofile(client..name..'.lua') end
        if name=='PZSurvivorToolkit/ItemCategories' then return {prepareContainer=function()end} end
    end
    local R=dofile(client..'PZSurvivorToolkit/InventoryRefresh.lua')
    Events.OnGameBoot.fire();Events.OnGameStart.fire()
    for i=1,40 do
        player.dir=i;player.square={}
        page:update();page:update()
    end
    assert(stats.discovery==40,'one successful pose discovery must acknowledge turn and tile together')
    assert(stats.rows==0 and stats.count==0,'hidden idle rows/count must not enumerate warehouse contents')
    assert(stats.copied==192000 and stats.events==40,'native discovery/BC raw aggregation must stay live')
    assert(aggregate.contents:size()==4800 and #page.backpacks==13,'hidden transfer/craft consumers lost raw contents')
    assert(#page.inventoryPane.items==0,'hidden pending rows must not retain stale input targets')
    -- The player window has no movement scheduler, but item/container events
    -- call refreshBackpacks directly. Only its fully hidden idle rows defer.
    local character=makePage();character.onCharacter=true
    local playerStats={};for key,value in pairs(stats)do playerStats[key]=value end
    local beforePlayerRows,beforePlayerCount=stats.rows,stats.count
    character.inventoryPane.items={{stale='player-row'}}
    character:refreshBackpacks();character:refreshBackpacks()
    assert(stats.rows==beforePlayerRows and stats.count==beforePlayerCount
        and character.toolkitRefreshState.rowsPending and character.toolkitRefreshState.countPending
        and #character.inventoryPane.items==0,'hidden idle PLAYER did not defer rows/count')
    isGamePaused=function()return true end
    character:setVisible(true)
    assert(stats.rows==beforePlayerRows+1 and stats.count==beforePlayerCount+1
        and not character.toolkitRefreshState.rowsPending,'paused PLAYER reopen did not flush rows/count')
    character.isCollapsed=true;character:refreshBackpacks()
    assert(stats.rows==beforePlayerRows+2 and stats.count==beforePlayerCount+2,
        'visible collapsed PLAYER must retain its immediate refresh path')
    isGamePaused=function()return false end
    for key,value in pairs(playerStats)do stats[key]=value end
    -- The gate delegates to the current complete class chain, not a stale closure.
    local oldRefresh,lateCalls=Pane.refreshContainer,0
    Pane.refreshContainer=function(...)lateCalls=lateCalls+1;return oldRefresh(...)end
    sources[1].contents.n=401
    local a,b,c=page:refreshBackpacks()
    assert(a=='discovery' and b==nil and c==29 and stats.rows==0 and aggregate.contents:size()==4801)
    assert(page:setVisible(true)=='visible')
    assert(stats.rows==1 and lateCalls==1 and stats.count==1 and page.totalItems==4801)
    assert(page.inventoryPane.builtCount==4801,'opening must observe same-count and remote contents changes')
    page:update();assert(stats.rows==1,'opening must not cause a duplicate discovery on unchanged pose')
    -- Collapse clips only details. Header counts and raw discovery remain live;
    -- idle update/prerender must not immediately cancel the deferred row work.
    for _,expansion in ipairs({'hover','pin','drag'})do
        page.visible=true;page.isCollapsed=true;page.pin=false;page.clipCleared=false
        ISMouseDrag={};sources[1].contents.n=402;player.square={}
        local beforeRows,beforeCount,beforeDiscovery=stats.rows,stats.count,stats.discovery
        local updated=pack(page:update())
        assert(updated.n==4 and updated[1]=='update' and updated[3]==41 and updated[4]==nil,
            'update wrapper lost return arity')
        local pending=page.toolkitRefreshState
        assert(stats.rows==beforeRows and stats.count==beforeCount+1 and page.totalItems==4802
            and pending.rowsPending and not pending.countPending and #page.inventoryPane.items==0,
            'collapsed idle discovery must defer rows while keeping visible header counts live')
        page:prerender();page:update()
        assert(stats.rows==beforeRows and stats.count==beforeCount+1 and stats.discovery==beforeDiscovery+1
            and page.renderedCount==4802 and pending.rowsPending,
            'collapsed draw/update flushed unused rows or repeated discovery')
        -- Remote changes after the last deferred scan must be observed even when
        -- expansion itself does not move/turn the player or toggle visibility.
        sources[1].contents.n=403
        if expansion=='hover'then page:onMouseMove(0,0)
        elseif expansion=='pin'then page.pin=true;page:update()
        else ISMouseDrag.dragging={{}};page:update();ISMouseDrag={} end
        assert(not page.isCollapsed and page.clipCleared,'upstream '..expansion..' did not expand details')
        if expansion~='hover'then
            assert(not pending.rowsPending and page.inventoryPane.builtCount==4803,
                'native update expansion did not flush before returning to child input consumers')
        end
        local drawn=pack(page:prerender())
        assert(drawn.n==4 and drawn[1]=='draw' and drawn[3]==43 and drawn[4]==nil,
            'prerender wrapper lost return arity')
        assert(stats.rows==beforeRows+1 and stats.count==beforeCount+2 and page.renderedCount==4803
            and page.inventoryPane.builtCount==4803 and not pending.rowsPending and not pending.countPending,
            'expanded '..expansion..' draw did not synchronously consume fresh rows/count')
        page:update();page:prerender()
        assert(stats.rows==beforeRows+1 and stats.discovery==beforeDiscovery+2,
            'settled expansion repeated the fresh discovery')
    end
    page.pin=false;sources[1].contents.n=401;page:refreshBackpacks()
    page.visible=false;page.isCollapsed=false
    -- Rebind a retained pane while the previous pane still has deferred work.
    -- The new pane may come with old rendered input targets of its own.
    page.inventoryPane.items={{stale='old-pane'}}
    page:refreshBackpacks()
    local oldPane,state=page.inventoryPane,page.toolkitRefreshState
    assert(state.rowsPending and state.countPending and #oldPane.items==0)
    local replacement=setmetatable({mode='details',selected={},items={{stale='replacement'}},
        parent=page,height=100,y=20},Pane)
    page.inventoryPane=replacement
    sources[2].contents.n=402
    page:refreshBackpacks()
    assert(state.pane==replacement and state.rowsPending and state.countPending and #replacement.items==0,
        'pending pane rebind retained stale input targets or lost deferred work')
    local beforeOld=stats.rows
    oldPane:refreshContainer()
    assert(stats.rows==beforeOld+1 and state.rowsPending and state.countPending,
        'retired pane refresh cleared the current pane pending state')
    sources[3].contents.n=403 -- remote contents change between last defer and opening
    local beforeRows,beforeCount=stats.rows,stats.count
    page:setVisible(true)
    assert(stats.rows==beforeRows+1 and stats.count==beforeCount+1
        and replacement.builtCount==4806 and page.totalItems==4806
        and not state.rowsPending and not state.countPending and #replacement.items==0,
        'opening after a pending pane rebind failed to flush fresh rows/count')
    -- A UI mode switch may replace both class tables on retained instances.
    page.visible=false
    replacement.items={{stale='before-class-switch'}}
    page:refreshBackpacks()
    assert(state.rowsPending and state.countPending and #replacement.items==0)
    local AlternatePane={};AlternatePane.__index=AlternatePane
    setmetatable(AlternatePane,{__index=Pane})
    local switchedRows=0
    function AlternatePane:refreshContainer(...)
        switchedRows=switchedRows+1
        return Pane.refreshContainer(self,...)
    end
    local AlternatePage={}
    for key,value in pairs(Page) do AlternatePage[key]=value end
    AlternatePage.__index=AlternatePage
    setmetatable(page,AlternatePage);setmetatable(replacement,AlternatePane)
    CleanUI_Clean_ISInventoryPage=AlternatePage
    R.install()
    sources[4].contents.n=404
    page:refreshBackpacks()
    assert(switchedRows==0 and state.rowsPending and state.countPending and #replacement.items==0,
        'pending UI class switch rebuilt prematurely or retained stale input rows')
    sources[5].contents.n=405
    beforeRows,beforeCount=stats.rows,stats.count
    page:setVisible(true)
    assert(switchedRows==1 and stats.rows==beforeRows+1 and stats.count==beforeCount+1
        and replacement.builtCount==4815 and page.totalItems==4815
        and not state.rowsPending and not state.countPending and #replacement.items==0,
        'opening after pending UI class switch used stale class/contents/count')
    page.visible=false
    -- Explicit pane refreshes/quick-transfer owners are always immediate, even hidden.
    local before=stats.rows
    local x,y,z=page.inventoryPane:refreshContainer()
    assert(x=='rows' and y==nil and z==17 and stats.rows==before+1)
    for _,owner in ipairs({'loot','player'})do
    for _,visibility in ipairs({'hidden','collapsed'})do
        page.visible=visibility=='collapsed';page.isCollapsed=visibility=='collapsed'
        for _,kind in ipairs({'selected','firstSelect','drag','dragFocus','dragging','marquee','pendingMarquee',
            'controller','pageFocus','paneFocus','joypad','visibleFilter','filter','tag','rule','search','categorySearch','icons','character'}) do
            local pane=page.inventoryPane
            pane.selected={};ISMouseDrag={};page.joyfocus=nil;page.onCharacter=owner=='player';player.joypad=-1
            for _,field in ipairs({'firstSelect','dragging','draggingMarquis','toolkitPendingMarquee','doController',
                'joyfocus','toolkitVisibleItems','toolkitCategory','toolkitTag','toolkitTagRule','searchText','searchCategoryText'})do pane[field]=nil end
            pane.mode='details'
            if kind=='selected' then pane.selected[1]={}
            elseif kind=='firstSelect' then pane.firstSelect=1
            elseif kind=='drag' then ISMouseDrag.dragging={{}}
            elseif kind=='dragFocus' then ISMouseDrag.draggingFocus=pane
            elseif kind=='dragging' then pane.dragging=1
            elseif kind=='marquee' then pane.draggingMarquis=true
            elseif kind=='pendingMarquee' then pane.toolkitPendingMarquee='onMouseMoveOutside'
            elseif kind=='controller' then pane.doController=true
            elseif kind=='pageFocus' then page.joyfocus={}
            elseif kind=='paneFocus' then pane.joyfocus={}
            elseif kind=='joypad' then player.joypad=0
            elseif kind=='visibleFilter' then pane.toolkitVisibleItems={}
            elseif kind=='filter' then pane.toolkitCategory='Tool'
            elseif kind=='tag' then pane.toolkitTag='tools'
            elseif kind=='rule' then pane.toolkitTagRule={}
            elseif kind=='search' then pane.searchText='nails'
            elseif kind=='categorySearch' then pane.searchCategoryText='Tool'
            elseif kind=='icons' then pane.mode='icons'
            elseif kind=='character' then page.onCharacter=true;page.visible=true end
            before=stats.rows;page:refreshBackpacks()
            assert(stats.rows==before+1,owner..' '..visibility..' '..kind..' input/filter state must retain the live path')
        end
    end
    end
    page.visible=false;page.isCollapsed=false;page.onCharacter=false
    page.inventoryPane.mode='details'
    -- Opaque per-instance refresh owners are not replaced or deferred.
    local custom=0
    page.inventoryPane=setmetatable({mode='details',selected={},items={},
        refreshContainer=function()custom=custom+1 end},Pane)
    page:refreshBackpacks();assert(custom==1)
    -- Even an own callback identical to the inherited one belongs to that
    -- instance's owner; comparing resolved callback identity cannot prove absence.
    page.inventoryPane=setmetatable({mode='details',selected={},items={},
        refreshContainer=Pane.refreshContainer},Pane)
    before=stats.rows
    page:refreshBackpacks()
    assert(stats.rows==before+1,'a genuine own callback must retain its immediate path')
    -- Failed discovery does not acknowledge a pose or leak a suppression scope.
    page.inventoryPane=setmetatable({mode='details',selected={},items={}},Pane)
    local oldSquare=page.lastSquare
    player.square={};page.failDiscovery=true
    assert(not pcall(page.update,page));assert(page.lastSquare==nil and page.lastDir==nil and page.toolkitRefreshState.scope==0)
    page.failDiscovery=false;page:update();assert(page.toolkitRefreshState.rowsPending)
    page.inventoryPane.failRows=true
    assert(not pcall(page.setVisible,page,true))
    assert(not page.toolkitRefreshState.force and page.toolkitRefreshState.scope==0)
    page.inventoryPane.failRows=false;page:update()
    assert(not page.toolkitRefreshState.rowsPending and not page.toolkitRefreshState.countPending)
    -- An unusual callback moving the player during discovery must not hide that change.
    page.afterDiscovery=function(self)self.afterDiscovery=nil;player.square={}end
    oldSquare=page.lastSquare;page:refreshBackpacks();assert(page.lastSquare==oldSquare)
    before=stats.discovery;page:update();assert(stats.discovery==before+1)
    print('PASS inventory refresh '..label..': 40 turn/tile changes ->40 raw rebuilds, zero hidden row/count builds; collapsed rows defer/count stays live, hover/pin/drag reopen; BC contents, pane/class rebind, input guards, arity, late hooks and errors remain live')
end
run(nil,'doubles',NativeBCProximitySource)
if NativeInventoryPageSource then run(NativeInventoryPageSource,'native B42',NativeBCProximitySource) end
if CleanUIInventoryPageSource then run(CleanUIInventoryPageSource,'CleanUI',NativeBCProximitySource) end
if CleanUIVanillaInventoryPageSource then run(CleanUIVanillaInventoryPageSource,'CleanUI vanilla',NativeBCProximitySource) end

-- CleanUI builds capacity tooltip text inside addContainerButton. Suppression
-- must retain the call contract and keep an independent reopen obligation even
-- when discovery stops before row/count construction.
do
    local function pack(...)return {n=select('#',...),...}end
    local stats={weights=0,late=0,rows=0,counts=0}
    local inventory={weight=10}
    function inventory:getCapacityWeight()stats.weights=stats.weights+1;return self.weight end
    local Pane={};Pane.__index=Pane
    function Pane:refreshContainer()stats.rows=stats.rows+1;self.builtWeight=inventory.weight end
    local Page={};Page.__index=Page
    function Page:getIsVisible()return self.visible end
    function Page:setVisible(value)self.visible=value;return 'visible',nil,'end',nil end
    function Page:addContainerButton(container,texture,name,tooltip,...)
        stats.args=pack(container,texture,name,tooltip,...)
        local button={inventory=container,name=name}
        if tooltip then button.tooltip=tooltip..':'..container:getCapacityWeight() end
        return button,nil,31,nil
    end
    function Page:refreshBackpacks()
        stats.returns=pack(self:addContainerButton(inventory,'texture','crate','capacity','extra',nil))
        self.button=stats.returns[1]
        if self.failAfterButton then error('failed after tooltip creation')end
        if self.earlyAfterButton then return 'early',nil end
        self.inventoryPane:refreshContainer()
        self:updateItemCount()
    end
    function Page:updateItemCount()stats.counts=stats.counts+1;self.countedWeight=inventory.weight end
    function Page:update()end
    function Page:prerender()end
    PZSurvivorToolkit={};ISMouseDrag={}
    ISInventoryPage=Page;CleanUI_Clean_ISInventoryPage=Page;CleanUI_Vanilla_ISInventoryPage=nil
    local player={getJoypadBind=function()return -1 end,getCurrentSquare=function()return 1 end,getDir=function()return 1 end}
    getSpecificPlayer=function()return player end
    Events={OnGameBoot={Add=function()end},OnGameStart={Add=function()end}}
    require=function(name)
        if name=='PZSurvivorToolkit/InventoryClasses'then return{onToggle=function()end}end
        if name=='PZSurvivorToolkit/ItemCategories'then return{prepareContainer=function()end}end
    end
    local R=dofile(client..'PZSurvivorToolkit/InventoryRefresh.lua');R.install()
    local prior=Page.addContainerButton
    Page.addContainerButton=function(...)stats.late=stats.late+1;return prior(...)end
    local function page()
        local p=setmetatable({player=0,visible=false},Page)
        p.inventoryPane=setmetatable({mode='details',selected={},items={},parent=p},Pane)
        return p
    end
    local hidden=page()
    hidden:refreshBackpacks()
    assert(stats.weights==0 and stats.late==1 and hidden.button.inventory==inventory and hidden.button.tooltip==nil,
        'hidden CleanUI tooltip suppression changed button identity or read stock weight')
    assert(stats.args.n==6 and stats.args[1]==inventory and stats.args[2]=='texture'
        and stats.args[3]=='crate' and stats.args[4]==nil and stats.args[5]=='extra' and stats.args[6]==nil,
        'tooltip suppression lost trailing nil arguments or changed another argument')
    assert(stats.returns.n==4 and stats.returns[2]==nil and stats.returns[3]==31 and stats.returns[4]==nil,
        'tooltip suppression changed addContainerButton return arity')
    assert(hidden.toolkitRefreshState.tooltipsPending)
    inventory.weight=99;hidden.isCollapsed=true
    local visibleReturns=pack(hidden:setVisible(true))
    assert(visibleReturns.n==4 and visibleReturns[1]=='visible' and visibleReturns[4]==nil
        and stats.weights==1 and stats.late==2 and hidden.button.tooltip=='capacity:99'
        and hidden.inventoryPane.builtWeight==99 and hidden.countedWeight==99
        and not hidden.toolkitRefreshState.tooltipsPending,
        'show did not restore fresh complete CleanUI tooltip/rows/count')
    local beforeRows,beforeCounts,beforeWeights=stats.rows,stats.counts,stats.weights
    inventory.weight=100;hidden:refreshBackpacks();hidden:update();hidden:prerender()
    assert(stats.rows==beforeRows and stats.weights==beforeWeights and stats.counts==beforeCounts+1
        and hidden.countedWeight==100 and hidden.button.inventory==inventory and hidden.button.tooltip==nil
        and hidden.toolkitRefreshState.rowsPending and hidden.toolkitRefreshState.tooltipsPending
        and not hidden.toolkitRefreshState.countPending,
        'collapsed CleanUI must defer clipped rows/tooltips while keeping title values live')
    inventory.weight=99;hidden.isCollapsed=false;hidden:prerender()
    assert(stats.rows==beforeRows+1 and stats.weights==beforeWeights+1
        and hidden.button.tooltip=='capacity:99' and hidden.inventoryPane.builtWeight==99
        and not hidden.toolkitRefreshState.rowsPending and not hidden.toolkitRefreshState.tooltipsPending,
        'expanded CleanUI draw retained deferred rows or a stale/missing container tooltip')
    hidden.visible=false
    local before=stats.weights
    local direct=pack(hidden:addContainerButton(inventory,'texture','crate','direct',nil))
    assert(stats.weights==before+1 and direct.n==4 and direct[1].tooltip=='direct:99',
        'explicit button construction outside discovery was suppressed')
    for _,kind in ipairs({'early','failure'})do
        local pending=page()
        pending.earlyAfterButton=kind=='early';pending.failAfterButton=kind=='failure'
        local ok=pcall(pending.refreshBackpacks,pending)
        assert(ok==(kind=='early'))
        local state=pending.toolkitRefreshState
        assert(state.tooltipsPending and not state.rowsPending and not state.countPending and state.scope==0,
            'early/failed discovery lost the separate tooltip flush obligation')
        pending.earlyAfterButton,pending.failAfterButton=false,false
        inventory.weight=inventory.weight+1
        before=stats.weights
        pending:setVisible(true)
        assert(stats.weights==before+1 and pending.button.tooltip=='capacity:'..inventory.weight
            and pending.inventoryPane.builtWeight==inventory.weight and pending.countedWeight==inventory.weight
            and not state.tooltipsPending and not state.force,
            'opening after early/failed discovery left a missing or stale tooltip')
    end
    for _,kind in ipairs({'icons','opaque','other-class','character'})do
        local immediate=page()
        if kind=='icons'then immediate.inventoryPane.mode='icons'
        elseif kind=='opaque'then immediate.inventoryPane.refreshContainer=function()end
        elseif kind=='other-class'then CleanUI_Clean_ISInventoryPage={}
        elseif kind=='character'then immediate.onCharacter=true;immediate.visible=true end
        before=stats.weights
        immediate:refreshBackpacks()
        assert(stats.weights==before+1 and immediate.button.tooltip=='capacity:'..inventory.weight,
            kind..' path unexpectedly suppressed an immediate tooltip')
        CleanUI_Clean_ISInventoryPage=Page
    end
    print('PASS CleanUI hidden/collapsed tooltip workload: clipped rows/tooltips defer, title counts stay live; argument/result arity, late hooks, fresh expand, early/failure obligations and immediate fallbacks preserved')
end

-- Execute both Toolkit category owners: displayCategory mutates the actual item
-- instance even when hidden player row construction is deferred. Native row/UI
-- leaves are doubles; unknown per-instance callbacks and late hooks stay owned.
do
    local function event()
        local callbacks={}
        return {Add=function(fn)callbacks[#callbacks+1]=fn end,
            fire=function()for _,fn in ipairs(callbacks)do fn()end end}
    end
    local stats={rows=0,classifications=0,late=0,counts=0}
    local physical={category='old',wanted='toolSurvival'}
    function physical:getDisplayCategory()return self.category end
    function physical:setDisplayCategory(value)self.category=value end
    local inventory={getItems=function()return{size=function()return 1 end,get=function()return physical end}end}
    local Pane={};Pane.__index=Pane
    function Pane:refreshContainer()
        stats.rows=stats.rows+1
        self.rowCategory=physical:getDisplayCategory()
        return 'rows',nil,19,nil
    end
    local Page={};Page.__index=Page
    function Page:getIsVisible()return self.visible end
    function Page:setVisible(value)self.visible=value end
    function Page:refreshBackpacks()
        self.inventoryPane:refreshContainer()
        self:updateItemCount()
    end
    function Page:updateItemCount()stats.counts=stats.counts+1 end
    function Page:update()end
    function Page:prerender()end
    local events={OnGameBoot=event(),OnGameStart=event(),OnCreatePlayer=event()}
    local env=setmetatable({PZSurvivorToolkit={},Events=events,ISInventoryPage=Page,
        CleanUI_Clean_ISInventoryPage=false,CleanUI_Vanilla_ISInventoryPage=false,ISMouseDrag={},
        getSpecificPlayer=function()return nil end}, {__index=_G})
    local categories
    env.require=function(name)
        if name=='PZSurvivorToolkit/InventoryClasses'then
            return{onToggle=function()end,panes=function(fn)fn(Pane)end}
        elseif name=='PZSurvivorToolkit/ItemCategoryRules'then
            return{forItem=function(value)stats.classifications=stats.classifications+1;return value.wanted end}
        elseif name=='PZSurvivorToolkit/ItemCategories'then return categories
        elseif name=='PZSurvivorToolkit/LegacyItemCategories'then return{reset=function()end}
        elseif name=='PZSurvivorToolkit/InventoryRows'then
            return{captureAnchor=function()end,restoreAnchor=function()end}
        end
        return{}
    end
    local categoryChunk=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemCategories.lua'))
    setfenv(categoryChunk,env);categories=categoryChunk()
    local categoryHook=assert(loadfile(client..'ToolkitItemCategories.lua'));setfenv(categoryHook,env);categoryHook()
    local refreshHook=assert(loadfile(client..'PZSurvivorToolkit/InventoryRefresh.lua'));setfenv(refreshHook,env);refreshHook()
    events.OnGameBoot.fire()
    local page=setmetatable({onCharacter=true,visible=false},Page)
    local pane=setmetatable({inventory=inventory,mode='details',selected={},items={{stale=true}}},Pane)
    page.inventoryPane=pane
    -- This models NeatUI's OnClothingUpdated/OnEquip* refreshFor: it calls
    -- pane:refreshContainer directly, outside refreshBackpacks' scope.
    local inherited=Pane.refreshContainer
    Pane.refreshContainer=function(...)
        stats.late=stats.late+1
        return inherited(...)
    end
    page:refreshBackpacks()
    assert(stats.rows==0 and stats.late==0 and stats.classifications==1 and stats.counts==0
        and physical.category=='toolSurvival' and #pane.items==0,
        'hidden PLAYER did not preserve actual item classification without building rows')
    physical.wanted='foodBeverage';page:refreshBackpacks()
    assert(stats.classifications==2 and physical.category=='foodBeverage' and stats.rows==0,
        'pending hidden PLAYER ignored a changed per-instance category')
    local a,b,c,d=pane:refreshContainer()
    assert(a=='rows' and b==nil and c==nil and d==nil and stats.rows==1 and stats.late==1
        and stats.classifications==3 and pane.rowCategory=='foodBeverage'
        and not page.toolkitRefreshState.rowsPending,
        'explicit PLAYER pane refresh skipped category/foreign chain or lost return values')
    page:refreshBackpacks()
    physical.wanted='mechanicsFuel';page:setVisible(true)
    assert(stats.rows==2 and stats.late==2 and stats.classifications==5
        and pane.rowCategory=='mechanicsFuel' and physical.category=='mechanicsFuel'
        and stats.counts==1 and not page.toolkitRefreshState.countPending,
        'PLAYER reopen failed to consume fresh actual categories/rows/count')
    page.isCollapsed=true;page:refreshBackpacks()
    assert(stats.rows==3 and stats.late==3 and stats.classifications==6 and stats.counts==2,
        'visible collapsed PLAYER should keep its original complete callback chain')
    page.visible=false
    local calls=0
    page.inventoryPane=setmetatable({inventory=inventory,mode='details',selected={},items={},
        refreshContainer=function()calls=calls+1 end},Pane)
    page:refreshBackpacks()
    assert(calls==1 and stats.classifications==6,
        'opaque PLAYER callback was replaced or category work escaped its owner')
    -- A loot defer must never add the separate category pass required by PLAYER.
    page.onCharacter=false
    page.inventoryPane=setmetatable({inventory=inventory,mode='details',selected={},items={}},Pane)
    page:refreshBackpacks()
    assert(stats.classifications==6 and stats.rows==3,'loot deferral acquired extra category enumeration')
    print('PASS hidden PLAYER actual ItemCategories/ToolkitItemCategories: physical displayCategory stays live; rows/count defer, explicit late chain/reopen/collapsed/opaque/loot contracts hold')
end

-- Unlike the scheduling fixture above, execute the entire installed CleanUI
-- discovery body and the actual BC begin/buttonsAdded handlers. World/UI leaves
-- are doubles, so this isolates Lua lifecycle from native object side effects.
if CleanUIInventoryPageSource and NativeBCProximitySource then
    local stats={rows=0,counts=0,weights=0,phases={}}
    local function list(values)
        local result={values=values or {}}
        function result:size()return #self.values end
        function result:get(index)return self.values[index+1]end
        function result:clear()self.values={}end
        function result:addAll(other)for _,value in ipairs(other.values)do self.values[#self.values+1]=value end end
        return result
    end
    local function inventory(kind,values)
        local result={items=list(values)}
        function result:getItems()return self.items end
        function result:getType()return kind end
        function result:getParent()end
        function result:getCustomName()end
        function result:getMaxWeight()return 100 end
        function result:getEffectiveCapacity()return 100 end
        function result:getCapacityWeight()stats.weights=stats.weights+1;return self.items:size()end
        function result:clear()self.items:clear()end
        function result:removeItemsFromProcessItems()end
        function result:AddItem(value)self.items.values[#self.items.values+1]=value end
        function result:setExplored()end
        function result:setOnlyAcceptCategory()end
        function result:setCapacity()end
        return result
    end
    local function item(id)return{id=id,getCategory=function()return 'Item'end,
        isItemType=function()return false end,hasTag=function()return false end}end
    local ground={item('ground')}
    local floor=inventory('floor')
    local chest=inventory('crate',{item('stock1'),item('stock2')})
    local chestObject={getContainerCount=function()return 1 end,getContainerByIndex=function()return chest end}
    local worldObjects={size=function()return #ground end,get=function(_,index)
        return{getItem=function()return ground[index+1]end}
    end}
    local square={getWorldObjects=function()return worldObjects end,getStaticMovingObjects=function()return list()end,
        getObjects=function()return list({chestObject})end,getVehicleContainer=function()end,canReachTo=function()return true end}
    local player={getX=function()return .5 end,getY=function()return .5 end,getZ=function()return 0 end,
        getDir=function()return 1 end,getCurrentSquare=function()return square end,
        getVehicle=function()end,getJoypadBind=function()return -1 end}
    local Pane={};Pane.__index=Pane
    function Pane:hideButtons()end
    function Pane:bringToTop()end
    function Pane:refreshContainer()
        stats.rows=stats.rows+1
        self.itemslist={}
        for _,value in ipairs(self.inventory:getItems().values)do self.itemslist[#self.itemslist+1]=value end
    end
    local Page={};Page.__index=Page
    function Page.GetFloorContainer()return floor end
    function Page:getIsVisible()return self.visible end
    function Page:setVisible(value)self.visible=value end
    function Page:checkExplored()end
    function Page:prerender()self.renderedCount=self.totalItems end
    function Page:refreshWeight()end -- actual CleanUI method is an empty return
    function Page:titleBarHeight()return 20 end
    function Page:updateItemCount()stats.counts=stats.counts+1;self.totalItems=self.inventoryPane.inventory:getItems():size()end
    function Page:addContainerButton(container,texture,name,tooltip)
        local button={inventory=container,name=name,capacity=container:getEffectiveCapacity(player),
            getBottom=function()return 24 end,setTextureRGBA=function()end}
        if tooltip then button.tooltip=tooltip..':'..container:getCapacityWeight()end
        self.backpacks[#self.backpacks+1]=button
        return button
    end
    local eff={proximityActive=true}
    local proximity
    local env=setmetatable({PZSurvivorToolkit={},ISInventoryPage=Page,CleanUI_Clean_ISInventoryPage=Page,
        CleanUI_Vanilla_ISInventoryPage=false,ISMouseDrag={},ISHandCraftPanel={},ISBuildPanel={},
        ItemType={KEY_RING='KeyRing'},ItemTag={KEY_RING='KeyRing'},
        ContainerButtonIcons={floor={}},IsoDirections={},
        getSpecificPlayer=function()return player end,getTimestampMs=function()return 100 end,
        getText=function(value)return value end,getTextOrNull=function(value)return value end,
        instanceof=function()return false end,isClient=function()return true end,
        SafeHouse={isSafehouseAllowLoot=function()return true end},
        ItemContainer={new=function(kind)return inventory(kind)end},getTexture=function()return{}end,
        Events={OnGameBoot={Add=function()end},OnGameStart={Add=function()end}},
        getCell=function()return{getGridSquare=function(_,x,y,z)
            if math.floor(x)==0 and math.floor(y)==0 and z==0 then return square end
        end}end}, {__index=_G})
    env.require=function(name)
        if name=='PZSurvivorToolkit/InventoryClasses'then return{onToggle=function()end}end
        if name=='PZSurvivorToolkit/ItemCategories'then return{prepareContainer=function()end}end
        if name=='BetterContainers/_Options'then return{getEffectivePermissions=function()return eff end}end
        return{}
    end
    env.triggerEvent=function(_,page,phase)
        stats.phases[phase]=(stats.phases[phase]or 0)+1
        if phase=='begin'then proximity.OnBeginRefresh(page)
        elseif phase=='buttonsAdded'then proximity.OnButtonsAdded(page)end
    end
    local bc=assert(loadstring(NativeBCProximitySource));setfenv(bc,env);proximity=bc()
    local body=assert(method(CleanUIInventoryPageSource,'refreshBackpacks'),'missing full CleanUI refreshBackpacks')
    -- Keep upstream lexical helpers (including B42.21 container-title lookup)
    -- in the same chunk as the extracted discovery body.
    local preamble=assert(CleanUIInventoryPageSource:match('^(.-)\nISInventoryPage%s*=%s*ISPanel:derive'),
        'missing CleanUI page class boundary')
    local full=assert(loadstring(preamble..'\nlocal sqsContainers,sqsVehicles={},{}\n'..body));setfenv(full,env);full()
    local owner=assert(loadfile(client..'PZSurvivorToolkit/InventoryRefresh.lua'));setfenv(owner,env)
    local R=owner();R.install()
    local aggregate=proximity.GetItemContainer(0)
    local pane=setmetatable({inventory=aggregate,mode='details',selected={},items={}},Pane)
    local page=setmetatable({player=0,visible=true,lookDir=player:getDir(),inventory=aggregate,inventoryPane=pane,
        backpacks={},buttonPool={},height=200,padding=2,containerButtonPanelWidth=40,
        resizeWidget={bringToTop=function()end},containerButtonPanel={removeChild=function()end,
            setHeight=function()end,setWidth=function()end,setScrollHeight=function()end}},Page)
    pane.parent=page
    page:refreshBackpacks()
    assert(stats.rows==1 and stats.counts==1 and pane.inventory==aggregate and aggregate:getItems():size()==3,
        'full CleanUI/BC body baseline did not discover chest and floor contents')
    local oldRows,oldCount=pane.itemslist,page.totalItems
    page:setVisible(false)
    ground[#ground+1]=item('late-ground')
    page:refreshBackpacks();page:refreshBackpacks()
    local state=assert(page.toolkitRefreshState)
    assert(state.rowsPending and state.countPending and state.tooltipsPending,
        'full actual CleanUI discovery body did not retain hidden pending work')
    assert(stats.rows==1 and stats.counts==1 and pane.itemslist==oldRows and page.totalItems==oldCount,
        'full actual CleanUI discovery unexpectedly rebuilt hidden rows/count')
    assert(aggregate:getItems():size()==4 and floor:getItems():size()==2
        and stats.phases.begin==3 and stats.phases.buttonsAdded==3 and stats.phases['end']==3,
        'full actual CleanUI/BC phase lifecycle lost live stock discovery')
    page:setVisible(true)
    assert(not state.rowsPending and not state.countPending and not state.tooltipsPending
        and stats.rows==2 and stats.counts==2 and page.totalItems==4 and #pane.itemslist==4,
        'full actual CleanUI body did not synchronously rebuild on reopen: rows='..stats.rows..' counts='..stats.counts..' total='..tostring(page.totalItems)..' rowCount='..#pane.itemslist..' pending='..tostring(state.rowsPending)..'/'..tostring(state.countPending)..'/'..tostring(state.tooltipsPending))
    page.isCollapsed=true
    oldRows=pane.itemslist
    local collapsedRows,collapsedCounts,collapsedWeights=stats.rows,stats.counts,stats.weights
    ground[#ground+1]=item('collapsed-ground')
    page:refreshBackpacks();page:refreshBackpacks();page:prerender()
    assert(stats.rows==collapsedRows and pane.itemslist==oldRows and stats.weights==collapsedWeights
        and stats.counts==collapsedCounts+2 and page.totalItems==5 and page.renderedCount==5
        and state.rowsPending and not state.countPending and state.tooltipsPending
        and aggregate:getItems():size()==5 and floor:getItems():size()==3,
        'full actual CleanUI/BC collapsed discovery lost live contents/count or built clipped presentation')
    page.isCollapsed=false;page:prerender()
    assert(stats.rows==collapsedRows+1 and stats.counts==collapsedCounts+3
        and #pane.itemslist==5 and page.renderedCount==5
        and not state.rowsPending and not state.countPending and not state.tooltipsPending,
        'full actual CleanUI/BC expanded draw did not flush deferred presentation')
    print('PASS full actual CleanUI refreshBackpacks + BC begin/buttonsAdded: hidden/collapsed rows/tooltips defer, collapsed counts and floor/aggregate remain live, reopen fresh')
    -- Run the actual upstream onCharacter branch as well: inventory/bag
    -- buttons and BC event phases remain live while only presentation defers.
    local carried=inventory('inventory',{item('carried')})
    local equipped=inventory('bag',{item('bag-stock')})
    local bag=item('bag')
    bag.getCategory=function()return 'Container'end
    bag.getInventory=function()return equipped end
    bag.getTex=function()return{}end
    bag.getName=function()return 'equipped bag'end
    bag.getVisual=function()end
    carried.items.values[#carried.items.values+1]=bag
    player.getInventory=function()return carried end
    player.isEquipped=function(_,value)return value==bag end
    local characterPane=setmetatable({inventory=carried,mode='details',selected={},items={{stale=true}}},Pane)
    local character=setmetatable({player=0,onCharacter=true,visible=false,inventory=carried,
        inventoryPane=characterPane,backpacks={},buttonPool={},height=200,padding=2,containerButtonPanelWidth=40,
        resizeWidget=page.resizeWidget,containerButtonPanel=page.containerButtonPanel},Page)
    characterPane.parent=character
    local playerRows,playerCounts,playerWeights=stats.rows,stats.counts,stats.weights
    local playerBegins,playerEnds=stats.phases.begin,stats.phases['end']
    character:refreshBackpacks();character:refreshBackpacks()
    local characterState=assert(character.toolkitRefreshState)
    local playerButtons={}
    for _,button in ipairs(character.backpacks)do playerButtons[button.inventory]=true end
    assert(stats.rows==playerRows and stats.counts==playerCounts and stats.weights==playerWeights
        and characterState.rowsPending and characterState.countPending and characterState.tooltipsPending
        and #characterPane.items==0 and #character.backpacks==3
        and playerButtons[carried] and playerButtons[equipped] and playerButtons[aggregate]
        and stats.phases.begin==playerBegins+2 and stats.phases['end']==playerEnds+2,
        'actual PLAYER discovery lost inventory/bag/BC lifecycle or built hidden presentation: rows='
            ..stats.rows..'/'..playerRows..' counts='..stats.counts..'/'..playerCounts
            ..' weights='..stats.weights..'/'..playerWeights..' pending='..tostring(characterState.rowsPending)
            ..'/'..tostring(characterState.countPending)..'/'..tostring(characterState.tooltipsPending)
            ..' buttons='..#character.backpacks..' phases='..stats.phases.begin..'/'..stats.phases['end'])
    -- Native equip/clothing integrations refresh the pane directly and must
    -- still rebuild immediately without requiring the player page to be shown.
    characterPane:refreshContainer()
    assert(stats.rows==playerRows+1 and #characterPane.itemslist==2 and not characterState.rowsPending,
        'actual hidden PLAYER explicit pane refresh was suppressed')
    character:refreshBackpacks()
    carried.items.values[#carried.items.values+1]=item('late-carried')
    character:setVisible(true)
    assert(stats.rows==playerRows+2 and stats.counts==playerCounts+1 and #characterPane.itemslist==3
        and character.totalItems==3 and not characterState.rowsPending
        and not characterState.countPending and not characterState.tooltipsPending,
        'actual PLAYER reopen failed to rebuild fresh carried contents/count/tooltips')
    character.isCollapsed=true;character:refreshBackpacks()
    assert(stats.rows==playerRows+3 and stats.counts==playerCounts+2,
        'actual visible collapsed PLAYER unexpectedly deferred presentation')
    print('PASS full actual CleanUI PLAYER refreshBackpacks + BC: hidden inventory/bag discovery live, rows/count/tooltips defer, direct equip refresh/reopen/collapsed preserve native contracts')
    if NativeBCProximityPaneSource then
        -- Actual BC update assumes every group has a duplicate header. A
        -- headerless singleton has no j=2 children, so it selects the header
        -- without mouse/controller input after a rendered baseline.
        local oldRequire=env.require
        env.require=function(name)
            if name=='BetterContainers/Proximity'then return proximity end
            return oldRequire(name)
        end
        env.ISInventoryPane=Pane
        env.getPlayerInventory=function()end;env.getPlayerLoot=function()end
        Pane.update=function()end;Pane.updateTooltip=function()end
        local adapter=assert(loadstring(NativeBCProximityPaneSource));setfenv(adapter,env)
        adapter().install()
        local physical={class='InventoryItem'}
        env.instanceof=function(value,name)return type(value)=='table'and value.class==name end
        local singleton={name='singleton',items={physical},cleanUIFirstActualIndex=1}
        pane.items={singleton};pane.collapsed={singleton=false};pane.selected={}
        pane:update()
        assert(pane.selected[1]==singleton,'actual BC update did not reproduce headerless singleton auto-selection')
        local dummy={name='dummy',items={physical,physical}}
        pane.items={dummy};pane.collapsed={dummy=false};pane.selected={};pane:update()
        assert(pane.selected[1]==nil,'native duplicate-header control was spuriously selected')
        pane.items={singleton};pane.collapsed={singleton=true};pane.selected={};pane:update()
        assert(pane.selected[1]==nil,'collapsed singleton control was spuriously selected')
        pane.collapsed.singleton=false;pane:update()
        assert(pane.selected[1]==singleton)
        page:setVisible(false)
        local beforeRows,beforeCounts=stats.rows,stats.counts
        page:refreshBackpacks()
        assert(stats.rows==beforeRows+1 and stats.counts==beforeCounts+1
            and not state.rowsPending and not state.countPending,
            'BC-selected singleton must preserve immediate input-safe refresh fallback')
        pane.selected={} -- same-frame fixture setup, with no intervening BC update
        beforeRows,beforeCounts=stats.rows,stats.counts
        page:refreshBackpacks()
        assert(stats.rows==beforeRows and stats.counts==beforeCounts
            and state.rowsPending and state.countPending and #pane.items==0,
            'same-frame cleared selection did not restore hidden deferral')
        print('PASS actual BC pane.update: headerless singleton auto-selects without input, guard retains immediate rows/count; same-frame cleared selection defers')
    end
end
