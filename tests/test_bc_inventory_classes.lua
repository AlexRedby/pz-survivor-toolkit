-- Actual BC installers and vanilla update/highlight methods; UI/world are doubles.
if not NativeBCProximityPaneSource or not NativeBCProximityPageSource or not CleanUIVanillaInventoryPaneSource then
    print('SKIP BC inventory class integration: explicit CleanUI and Better Containers sources required')
    return
end
local paneSource=assert(NativeBCProximityPaneSource,'BC proximity pane source required')
local pageSource=assert(NativeBCProximityPageSource,'BC proximity page source required')
local vanillaSource=assert(CleanUIVanillaInventoryPaneSource,'CleanUI vanilla pane source required')
local client=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'
local function pack(...)return{n=select('#',...),...}end
local function method(name)
    local body=assert(vanillaSource:match('(function CleanUI_Vanilla_ISInventoryPane:'..name..'%b().-)\nfunction '))
    return body:gsub('CleanUI_Vanilla_ISInventoryPane','ISInventoryPane')
end
local function run(compatible, initialVanilla, failureMode, initialDerived)
    local callbacks,stats={}, {installs=0,native={},late=0,auto=0}
    local held,hovered={},{}
    local eff={proximityActive=true,autoLock=true,hideIndividualCorpseContainers=true}
    local options={enableProximityHighlight=true,getEffectivePermissions=function()return eff end}
    local function container(kind)return{getType=function()return kind end}end
    local aggregate,corpses=container('proximityInv'),container('twistInv_corpses')
    local prox={invName='proximityInv',invName_corpses='twistInv_corpses',_ForceSwitchIntent={},forceSelectedType={},isForceSelected={}}
    function prox.isProximityType(kind)return kind==prox.invName or kind==prox.invName_corpses end
    function prox.getProximityHoveredItem()return held end
    function prox.getVanillaHoveredItem()return hovered end
    function prox.ForceSelectContainer(page,kind)page.browseKind=kind end
    function prox.shouldHideIndividualCorpseContainers()return eff.hideIndividualCorpseContainers end
    function prox.isHumanCorpseContainer(inv)return inv.human==true end
    function prox.GetCorpseContainer()return corpses end
    function prox.GetCurrentForceContainer()return aggregate end
    function prox.isTransferActive()return stats.transfer==true end
    function prox.DoAutoLock()stats.auto=stats.auto+1 end
    function prox.isHumanContainer(kind)return kind=='inventorymale' end
    local env=setmetatable({PZSurvivorToolkit={},ISMouseDrag={},
        getSpecificPlayer=function()return{}end,getPlayerInventory=function()end,getPlayerLoot=function()end,
        instanceof=function(value,name)return type(value)=='table'and(value.class==name or value.classes and value.classes[name])end,
        getCore=function()return{getObjectHighlitedColor=function()return{getR=function()return 1 end,getG=function()return 1 end,getB=function()return 1 end}end}end,
        CleanUI_RegisterInventoryUiToggleCallback=function(fn)callbacks[#callbacks+1]=fn;fn()end}, {__index=_G})
    env._G=env
    local function execute(source)local fn=assert(loadstring(source));setfenv(fn,env);return fn()end
    local function paneClass(tag)
        local class={updateTooltip=function()end};class.__index=class;env.ISInventoryPane=class
        execute(method('update'));execute(method('doWorldObjectHighlight'));execute(method('clearWorldObjectHighlights'))
        execute(method('saveSelection'));execute(method('restoreSelection'))
        local native=class.update
        class.update=function(self,...)
            if self.fail then error('native '..tag)end
            stats.native[tag]=(stats.native[tag]or 0)+1;native(self,...)
            return tag,nil,19,nil
        end
        return class
    end
    local enhanced,vanilla=paneClass('enhanced'),paneClass('vanilla')
    local function pageClass(tag)
        local class={};class.__index=class
        function class:getContainerParent(inv)return inv.parent end
        function class:addContainerButton(inv)
            return{inventory=inv,onclick=function()return tag,nil,23,nil end}
        end
        for _,name in ipairs({'selectContainer','setNewContainer','selectButtonForContainer','setForceSelectedContainer','onMouseOutButton','update'})do
            class[name]=function(self,value,...)
                if self.fail then error('page '..tag)end
                self.lastNative=tag;self.lastMethod=name;self.lastValue=value;self.args=pack(...)
                return tag,nil,29,nil
            end
        end
        return class
    end
    local enhancedPage,vanillaPage=pageClass('enhanced'),pageClass('vanilla')
    local sourcePane=initialVanilla and vanilla or enhanced
    local sourcePage=initialVanilla and vanillaPage or enhancedPage
    if initialDerived then
        sourcePane=setmetatable({update=function(self,...)
            stats.initialPaneSuper=(stats.initialPaneSuper or 0)+1
            return enhanced.update(self,...)
        end},enhanced);sourcePane.__index=sourcePane
        sourcePage=setmetatable({selectContainer=function(self,...)
            stats.initialPageSuper=(stats.initialPageSuper or 0)+1
            return enhancedPage.selectContainer(self,...)
        end},enhancedPage);sourcePage.__index=sourcePage
    end
    env.ISInventoryPane=sourcePane;env.CleanUI_Clean_ISInventoryPane=enhanced;env.CleanUI_Vanilla_ISInventoryPane=vanilla
    env.ISInventoryPage=sourcePage;env.CleanUI_Clean_ISInventoryPage=enhancedPage;env.CleanUI_Vanilla_ISInventoryPage=vanillaPage
    local loaded={}
    env.require=function(name)
        if name=='ISUI/ISInventoryPane'or name=='ISUI/ISInventoryPage'then return true end
        if name=='BetterContainers/Proximity'then return prox end
        if name=='BetterContainers/_Options'then return options end
        if loaded[name]then return loaded[name]end
        local value
        if name=='BetterContainers/Proximity/Proximity_ISInventoryPane'then value=execute(paneSource)
        elseif name=='BetterContainers/Proximity/Proximity_ISInventoryPage'then value=execute(pageSource)
        elseif name=='PZSurvivorToolkit/InventoryClasses'then
            local owner=assert(loadfile(client..name..'.lua'));setfenv(owner,env);value=owner()
        else error('unexpected require '..name)end
        loaded[name]=value;return value
    end
    local upstreamPane=env.require('BetterContainers/Proximity/Proximity_ISInventoryPane')
    local upstreamPage=env.require('BetterContainers/Proximity/Proximity_ISInventoryPage')
    local originals={update=sourcePane.update,clear=sourcePane.clearWorldObjectHighlights,highlight=sourcePane.doWorldObjectHighlight,alternate=vanilla.update}
    for _,upstream in ipairs({upstreamPane,upstreamPage})do
        local original=upstream.install
        upstream.install=function(...)
            stats.installs=stats.installs+1
            assert(env.ISInventoryPane==sourcePane and env.ISInventoryPage==sourcePage,'installer global class changed')
            if upstream==upstreamPane and failureMode and failureMode~='already-installed'then
                local dispatcher=sourcePane.clearWorldObjectHighlights
                original(...)
                if failureMode=='error'then error('upstream install failure')end
                sourcePane.clearWorldObjectHighlights=dispatcher
                return
            end
            return original(...)
        end
    end
    if compatible then
        if failureMode=='already-installed'then upstreamPane.install()end
        local owner=assert(loadfile(client..'PZSurvivorToolkit/BCInventoryCompatibility.lua'))
        setfenv(owner,env)
        if failureMode=='already-installed'then
            local installed=sourcePane.update
            local ok,problem=pcall(owner)
            assert(not ok and tostring(problem):find('must load before',1,true)and sourcePane.update==installed
                and upstreamPane._installed and stats.installs==1,'wrong load order stole an installed class/guard')
            print('PASS BC bridge wrong load order: explicit error without replacing installed callbacks/guards')
            return
        end
        local first=owner()
        assert(owner()==first,'duplicate module load replaced the compatibility owner')
    end
    if failureMode then
        local ok,problem=pcall(upstreamPane.install)
        assert(not ok and (failureMode~='error'or tostring(problem):find('upstream install failure',1,true)),
            'upstream partial install/unsupported contract error was hidden')
        assert(sourcePane.update==originals.update and sourcePane.clearWorldObjectHighlights==originals.clear
            and sourcePane.doWorldObjectHighlight==originals.highlight and vanilla.update==originals.alternate
            and upstreamPane._installed and not upstreamPage._installed,'partial install was published or its upstream guard reset')
        local again,same=pcall(upstreamPane.install)
        assert(not again and same==problem and stats.installs==1,'failed singleton was retried or changed its error')
        print('PASS BC bridge '..failureMode..': predecessor rollback, unchanged upstream guards and sticky error')
        return
    end
    upstreamPane.install();upstreamPage.install()
    local function pane(class,inventory)
        local source=container('crate')
        local item={class='InventoryItem',getContainer=function()return source end}
        local other={class='InventoryItem',getContainer=function()return source end}
        local group={name='Nails',items={item,item,other}}
        return setmetatable({player=0,inventory=inventory or aggregate,items={group,item,other},selected={[2]=item},
            collapsed={},firstSelect=2,highlightItems={}},class),item,source
    end
    local function assertPane(class,tag)
        for _,inventory in ipairs({aggregate,corpses})do
            local self,item=pane(class,inventory);self:update()
            if not compatible and class==vanilla then
                assert(self.selected[2]==nil and self.firstSelect==2,'negative control must lose only physical selection')
            else
                assert(self.selected[2]==item and self.firstSelect==2,'aggregate physical selection lost in '..tag)
                local saved=self:saveSelection({})
                self.itemslist={{name='Nails',items={self.items[3],self.items[3]}}};self.selected={}
                self:restoreSelection(saved)
                local empty=true
                for _ in pairs(self.selected)do empty=false;break end
                assert(empty,'removed aggregate physical item survived the native refreshed projection')
            end
        end
        if not compatible then return end
        local self,item,source=pane(class)
        self.inventory=source
        local result=pack(self:update('extra',nil))
        assert(result.n==4 and result[1]==tag and result[3]==19 and self.selected[2]==item,'ordinary inventory lost its native class fallback/returns')
        self.inventory=container('other');self:update();assert(self.selected[2]==nil,'ordinary native removal was suppressed')
        self.fail=true;local ok,problem=pcall(self.update,self)
        assert(not ok and tostring(problem):find('native '..tag,1,true),'native update error was swallowed')
        self.fail=nil
        local world={highlighted=true,getChunk=function()return{}end,getItem=function()return{}end,
            setHighlighted=function(self,_,flag)self.highlighted=flag end}
        local ground={class='InventoryItem',getWorldItem=function()return world end}
        self:doWorldObjectHighlight(ground);assert(hovered[world],'hover ownership absent in '..tag)
        held[world]=true;self:clearWorldObjectHighlights()
        assert(world.highlighted and not hovered[world]and self.highlightItems[world]==nil,'shared BC highlight was cleared in '..tag)
        held[world]=nil;self:doWorldObjectHighlight(ground);self:clearWorldObjectHighlights()
        assert(not world.highlighted,'unowned world highlight leaked in '..tag)
    end
    assertPane(enhanced,'enhanced');assertPane(vanilla,'vanilla')
    if not compatible then print('PASS negative control: actual singleton BC installer leaves alternate vanilla physical selections unprotected');return end
    for _,entry in ipairs({{enhancedPage,'enhanced'},{vanillaPage,'vanilla'}})do
        local class,tag=unpack(entry)
        local page=setmetatable({player=0,inventory=aggregate,inventoryPane={inventory=aggregate},backpacks={}},class)
        local ordinary=container('crate');local corpse=container('inventorymale');corpse.human=true
        local button=page:addContainerButton(ordinary)
        local clicked=pack(button.onclick(button,1,2))
        assert(page.browseKind=='crate'and clicked.n==4 and clicked[1]==tag,'button browse intent/native click lost in '..tag)
        local selected=pack(page:selectContainer(button,'trailing',nil))
        assert(page.lastNative==tag and selected.n==4 and selected[1]==tag and page.args.n==2,'page native predecessor/return arity lost')
        page:setNewContainer(corpse);assert(page.lastValue==corpses,'corpse world selection was not remapped in '..tag)
        page:selectButtonForContainer(corpse);assert(page.lastValue==corpses,'corpse button selection was not remapped')
        stats.transfer=true;page.lastMethod=nil
        page:selectButtonForContainer(ordinary);page:setForceSelectedContainer(ordinary)
        assert(page.lastMethod==nil,'transfer aggregate selection guard absent in '..tag)
        stats.transfer=false;page:setForceSelectedContainer(ordinary);assert(page.lastValue==ordinary)
        prox._ForceSwitchIntent[0]=prox.invName;page:update()
        assert(page.lastNative==tag and page.lastMethod=='setForceSelectedContainer'and page.lastValue==aggregate
            and not prox._ForceSwitchIntent[0],'force intent was not consumed through the correct page class')
        local object={classes={IsoObject=true},getR=function()return 1 end,getG=function()return 1 end,getB=function()return 1 end}
        function object:setHighlighted(_,flag)self.highlighted=flag end
        function object:setOutlineHighlight(_,flag)self.outlined=flag end
        function object:setOutlineHlAttached()end
        function object:setHighlightColor()end
        function object:setOutlineHighlightCol()end
        ordinary.parent=object;page.backpacks={{inventory=ordinary}}
        page:update();assert(object.highlighted and object.outlined,'BC page highlight absent in '..tag)
        page.isCollapsed=true;page:update();assert(not object.highlighted and not object.outlined,'collapsed page failed to release BC highlight')
        page.isCollapsed=false;page:onMouseOutButton(button);assert(object.highlighted,'button mouse-out did not restore BC highlight')
        page.fail=true;local ok,problem=pcall(page.selectContainer,page,button)
        assert(not ok and tostring(problem):find('page '..tag,1,true),'page native error was swallowed')
    end
    -- Later owners may wrap shared callbacks. Repeated toggles must retain them;
    -- late-loaded classes need their own native predecessor, never the first UI's.
    local prior=vanillaPage.selectContainer
    local late=function(...)stats.late=stats.late+1;return prior(...)end
    vanillaPage.selectContainer=late
    local priorUpdate=vanilla.update
    local lateUpdate=function(...)stats.lateUpdate=(stats.lateUpdate or 0)+1;return priorUpdate(...)end
    vanilla.update=lateUpdate
    env.ISInventoryPane=vanilla;env.ISInventoryPage=vanillaPage
    for i=1,3 do for _,callback in ipairs(callbacks)do callback()end end
    assert(vanillaPage.selectContainer==late and vanilla.update==lateUpdate and stats.installs==2 and upstreamPane._installed and upstreamPage._installed,
        'toggle replayed singleton install, changed guards or erased a late decorator')
    local selectedPane,selectedItem=pane(vanilla);selectedPane:update()
    assert(stats.lateUpdate==1 and selectedPane.selected[2]==selectedItem,'late pane decorator was bypassed')
    local page=setmetatable({player=0},vanillaPage);local returns=pack(page:selectContainer({inventory=aggregate}))
    assert(stats.late==1 and returns.n==4 and returns[1]=='vanilla')
    local function bounded(callback)
        local guarded=type(debug)=='table'and type(debug.sethook)=='function'
        if guarded then debug.sethook(function()error('derived BC dispatch exceeded instruction budget',0)end,'',50000)end
        local result=pack(pcall(callback))
        if guarded then debug.sethook()end
        assert(result[1],tostring(result[2]))
        return unpack(result,2,result.n)
    end
    if initialDerived then
        local instance,_,source=pane(sourcePane);instance.inventory=source
        local result=pack(bounded(function()return instance:update()end))
        assert(result.n==4 and result[1]=='enhanced'and stats.initialPaneSuper==1,
            'initial own pane override did not call its proper parent predecessor once')
        instance.fail=true
        local ok=pcall(instance.update,instance);assert(not ok,'nested pane native error was swallowed')
        instance.fail=nil
        assert(bounded(function()return instance:update()end)=='enhanced'and stats.initialPaneSuper==3,
            'nested pane error leaked its predecessor owner scope')
        local instance=setmetatable({player=0},sourcePage)
        local result=pack(bounded(function()return instance:selectContainer({inventory=aggregate})end))
        assert(result.n==4 and result[1]=='enhanced'and stats.initialPageSuper==1,
            'initial own page override did not call its proper parent predecessor once')
        instance.fail=true
        local ok=pcall(instance.selectContainer,instance,{inventory=aggregate})
        assert(not ok,'nested page native error was swallowed')
        instance.fail=nil
        assert(bounded(function()return instance:selectContainer({inventory=aggregate})end)=='enhanced'
            and stats.initialPageSuper==3,'nested page error leaked its predecessor owner scope')
    end
    local derivedPane=setmetatable({},vanilla);derivedPane.__index=derivedPane
    local derivedPage=setmetatable({},vanillaPage);derivedPage.__index=derivedPage
    local ownCalls=0
    local ownPane=setmetatable({update=function(self,...)
        ownCalls=ownCalls+1;return vanilla.update(self,...)
    end},vanilla);ownPane.__index=ownPane
    local ownPage=setmetatable({selectContainer=function(self,...)
        ownCalls=ownCalls+1;return vanillaPage.selectContainer(self,...)
    end},vanillaPage);ownPage.__index=ownPage
    for _,pair in ipairs({{derivedPane,derivedPage},{ownPane,ownPage}})do
        env.ISInventoryPane=pair[1];env.CleanUI_Vanilla_ISInventoryPane=pair[1]
        env.ISInventoryPage=pair[2];env.CleanUI_Vanilla_ISInventoryPage=pair[2]
        local oldUpdate,oldSelect=pair[1].update,pair[2].selectContainer
        for _=1,3 do for _,callback in ipairs(callbacks)do callback()end end
        assert(pair[1].update==oldUpdate and pair[2].selectContainer==oldSelect,
            'late derived inheritance/own override was republished')
        local instance,_,source=pane(pair[1]);instance.inventory=source
        local result=pack(bounded(function()return instance:update()end))
        assert(result.n==4 and result[1]=='vanilla','derived pane lost its current parent chain')
        local instance=setmetatable({player=0},pair[2])
        local result=pack(bounded(function()return instance:selectContainer({inventory=aggregate})end))
        assert(result.n==4 and result[1]=='vanilla','derived page lost its current parent chain')
        bounded(function()assertPane(pair[1],'vanilla')end)
    end
    assert(ownCalls>0,'own derived overrides were bypassed')
    local mixed=setmetatable({update=function()return 'own-update'end},vanilla);mixed.__index=mixed
    env.ISInventoryPane=mixed;env.CleanUI_Vanilla_ISInventoryPane=mixed
    for _=1,3 do for _,callback in ipairs(callbacks)do callback()end end
    local mixedInstance=pane(mixed)
    local world={getChunk=function()return{}end,setHighlighted=function()end}
    local ground={class='InventoryItem',getWorldItem=function()return world end}
    bounded(function()mixedInstance:doWorldObjectHighlight(ground)end)
    assert(mixedInstance:update()=='own-update'and hovered[world],
        'mixed own/inherited class lost its override or BC hover registration')
    local latePane,latePage=paneClass('late'),pageClass('late')
    env.CleanUI_Vanilla_ISInventoryPane=latePane;env.CleanUI_Vanilla_ISInventoryPage=latePage
    env.ISInventoryPane=latePane;env.ISInventoryPage=latePage
    for _,callback in ipairs(callbacks)do callback()end
    assertPane(latePane,'late')
    local lateInstance=setmetatable({player=0},latePage)
    assert(lateInstance:selectContainer({inventory=aggregate})=='late','late class used the wrong native predecessor')
    assert(stats.installs==2,'late class reset/replayed upstream installer')
    print('PASS BC class bridge: actual pane update/highlights, both aggregates, native removal/fallbacks, page policies/highlights, arity/errors, late decorators/classes and repeated toggles')
end
run(false)
run(true)
run(true,true)
run(true,false,nil,true)
run(true,false,'error')
run(true,false,'contract')
run(true,false,'already-installed')

-- The early loader must not require BC or touch classes when the mod is absent.
do
    local env={getActivatedMods=function()return{contains=function()return false end}end,
        require=function()error('inactive BC loader required a dependency')end}
    setmetatable(env,{__index=_G})
    local loader=assert(loadfile(client..'000ToolkitBCInventoryCompatibility.lua'));setfenv(loader,env);loader()
    print('PASS BC inactive early loader leaves dependencies/classes untouched')
end
