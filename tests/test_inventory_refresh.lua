-- Source-backed movement scheduling + real BC aggregation; UI/world are doubles.
table.wipe=table.wipe or function(t)for key in pairs(t)do t[key]=nil end end
local client=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'
local function method(source,name)
    if not source then return end
    local normalized=source:gsub('CleanUI_Vanilla_ISInventoryPage','ISInventoryPage')
    return normalized:match('(function ISInventoryPage:'..name..'%b().-)\nfunction ')
end
local function run(source,label,bcSource)
    local stats={discovery=0,rows=0,count=0,copied=0,events=0}
    local function event() local handlers={};return {Add=function(fn) handlers[#handlers+1]=fn end,
        fire=function(...) for _,fn in ipairs(handlers) do fn(...) end end} end
    Events={OnGameBoot=event(),OnGameStart=event()}
    PZSurvivorToolkit={};ISMouseDrag={};JoypadState={players={}}
    instanceof=function() return false end
    local player={dir=0,square={},joypad=-1}
    function player:getDir() return self.dir end
    function player:getCurrentSquare() return self.square end
    function player:getJoypadBind() return self.joypad end
    getSpecificPlayer=function() return player end
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
    function Page:prerender() self.renderedCount=self.totalItems end
    if source then
        ISInventoryPage=Page
        assert(loadstring(assert(method(source,'update'),'missing upstream update')))()
    else
        function Page:update()
            if self.lastDir~=player:getDir() then self.lastDir=player:getDir();self:refreshBackpacks()
            elseif self.lastSquare~=player:getCurrentSquare() then self.lastSquare=player:getCurrentSquare();self:refreshBackpacks() end
        end
    end
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
    -- Visible collapsed headers retain current counts and the ordinary live rows.
    page.isCollapsed=true;player.square={};page:update()
    assert(stats.rows==2 and stats.count==2)
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
    for _,kind in ipairs({'selected','firstSelect','drag','controller','filter','search','icons'}) do
        page.inventoryPane.selected={};page.inventoryPane.firstSelect=nil;ISMouseDrag={}
        page.inventoryPane.doController=false;page.inventoryPane.toolkitCategory=nil
        page.inventoryPane.searchText=nil;page.inventoryPane.mode='details'
        if kind=='selected' then page.inventoryPane.selected[1]={}
        elseif kind=='firstSelect' then page.inventoryPane.firstSelect=1
        elseif kind=='drag' then ISMouseDrag.dragging={{}}
        elseif kind=='controller' then page.inventoryPane.doController=true
        elseif kind=='filter' then page.inventoryPane.toolkitCategory='Tool'
        elseif kind=='search' then page.inventoryPane.searchText='nails'
        elseif kind=='icons' then page.inventoryPane.mode='icons' end
        before=stats.rows;page:refreshBackpacks()
        assert(stats.rows==before+1,kind..' input/filter state must retain the live path')
    end
    page.inventoryPane.mode='details'
    -- Opaque per-instance refresh owners are not replaced or deferred.
    local custom=0
    page.inventoryPane=setmetatable({mode='details',selected={},items={},
        refreshContainer=function()custom=custom+1 end},Pane)
    page:refreshBackpacks();assert(custom==1)
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
    print('PASS inventory refresh '..label..': 40 turn/tile changes ->40 raw rebuilds, zero hidden row/count builds; baseline80builds, BC raw contents, reopen, pending pane/class rebind, selections/drag/controller/filters, late hooks and errors remain live')
end
run(nil,'doubles',NativeBCProximitySource)
if NativeInventoryPageSource then run(NativeInventoryPageSource,'native B42',NativeBCProximitySource) end
if CleanUIInventoryPageSource then run(CleanUIInventoryPageSource,'CleanUI',NativeBCProximitySource) end
if CleanUIVanillaInventoryPageSource then run(CleanUIVanillaInventoryPageSource,'CleanUI vanilla',NativeBCProximitySource) end
