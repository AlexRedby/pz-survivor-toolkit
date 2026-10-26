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
    print('PASS inventory refresh '..label..': 40 turn/tile changes ->40 raw rebuilds, zero hidden row/count builds; baseline80builds, BC raw contents, reopen, pending pane/class rebind, selections/drag/controller/filters, late hooks and errors remain live')
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
    require=function(name)if name=='PZSurvivorToolkit/InventoryClasses'then return{onToggle=function()end}end end
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
    inventory.weight=99
    local visibleReturns=pack(hidden:setVisible(true))
    assert(visibleReturns.n==4 and visibleReturns[1]=='visible' and visibleReturns[4]==nil
        and stats.weights==1 and stats.late==2 and hidden.button.tooltip=='capacity:99'
        and hidden.inventoryPane.builtWeight==99 and hidden.countedWeight==99
        and not hidden.toolkitRefreshState.tooltipsPending,
        'show did not restore fresh complete CleanUI tooltip/rows/count')
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
        elseif kind=='character'then immediate.onCharacter=true end
        before=stats.weights
        immediate:refreshBackpacks()
        assert(stats.weights==before+1 and immediate.button.tooltip=='capacity:'..inventory.weight,
            kind..' path unexpectedly suppressed an immediate tooltip')
        CleanUI_Clean_ISInventoryPage=Page
    end
    print('PASS CleanUI hidden tooltip workload: zero hidden weight reads; argument/result arity, late hooks, reopen, early/failure obligations and immediate fallbacks preserved')
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
    local function item(id)return{id=id,getCategory=function()return 'Item'end}end
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
    print('PASS full actual CleanUI refreshBackpacks + BC begin/buttonsAdded: hidden rows/count/tooltips defer, floor/aggregate remain live, reopen fresh')
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
