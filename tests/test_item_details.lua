local adapter = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/000ToolkitItemDetailsCompatibility.lua'
local function run(initialEnhanced, lateVanilla)
    local active, options, config = {}, {}, {}
    getActivatedMods = function() return {contains=function(_, id) return active[id] end} end
    PZAPI = {ModOptions={getOptions=function(_, id) return options[id] end}}
    function PZAPI.ModOptions:create(id)
        local value = {dict={}}
        options[id] = value
        function value:addDescription() end
        function value:addTickBox(id, _, default, tooltip)
            local option = {type='tickbox', value=default, tooltip=tooltip, getValue=function(self) return self.value end}
            self.dict[id] = option
            return option
        end
        value.addTextEntry = value.addTickBox
        function value:addComboBox(id)
            local option = {type='combobox',value=1,getValue=function(self) return self.value end}
            function option:addItem(_, selected) if selected then self.value = 1 end end
            self.dict[id] = option
            return option
        end
        return value
    end
    Events = {OnMainMenuEnter={Add=function() end}}
    ItemTag = {SHOW_CONDITION='ShowCondition',SHARPENABLE='Sharpenable'}
    instanceof = function(item, class) return item and ((class=='InventoryItem' and item.condition~=nil) or item.kind==class) or false end
    luautils = {stringStarts=function(value, prefix) return value:sub(1,#prefix)==prefix end}
    round = function(value) return math.floor(value+0.5) end
    local function color(r,g,b)
        return {getR=function() return r end,getG=function() return g end,getB=function() return b end,
            interp=function(_, _, _, target) target.getR,target.getG,target.getB=function() return r end,function() return g end,function() return b end end}
    end
    ColorInfo = {new=color}
    getCore = function() return {getBadHighlitedColor=function() return color(1,0,0) end,
        getGoodHighlitedColor=function() return color(0,1,0) end} end
    getText = function(value) return value end
    getTextManager = function() return {MeasureStringX=function(_, _, value) return #value end} end

    local function item(condition, category, kind)
        return {condition=condition, category=category or 'mechanicsVehiclePart',kind=kind,uses=condition,
            getDisplayCategory=function(self) return self.category end,getFullType=function(self) return self.fullType or 'Base.NormalTire1' end,
            hasTag=function(self, tag) return self.tags and self.tags[tag] or false end,
            getUseDelta=function() return 0.1 end,getCurrentUses=function(self) return self.uses end,getMaxUses=function() return 100 end,
            getCondition=function(self) return self.condition end,getCurrentCondition=function(self) return self.condition end,
            hasHeadCondition=function() return false end,hasSharpness=function() return false end,
            getMaxAmmo=function(self) return self.ammoMax or 0 end,getCurrentAmmoCount=function(self) return self.condition end,
            getWorldItem=function() end,isFluidContainer=function(self) return self.fluid~=nil end,
            getFluidContainer=function(self) return self.fluid and {getAmount=function() return self.condition end} end,
            getHungerChange=function(self) return self.hunger or 0 end,isCosmetic=function() return false end,
            getHolesNumber=function() return 0 end,isRoundChambered=function() return false end,
            getAllWeaponParts=function() return {size=function() return 0 end} end,isContainsClip=function() return false end}
    end
    local nativeCalls, fallbacks, officialLoads = 0, {}, 0
    local function class(label)
        return {MAX_ITEMS_IN_STACK_TO_RENDER=50,
            drawItemDetails=function(_, value) fallbacks[#fallbacks+1]={label,value}; return label end,
            refreshContainer=function(pane) nativeCalls=nativeCalls+1; if pane.failNative then error('native failure') end; return label end,
            saveSelection=function(pane, selected)
                for _,value in pairs(pane.selected) do
                    if value.items then selected[value.items[1]]='group' else selected[value]='item' end
                end
                return selected
            end,
            restoreSelection=function(pane, selected)
                local row = 1
                for _, stack in ipairs(pane.itemslist) do
                    if selected[stack.items[1]]=='group' then pane.selected[row]=stack end
                    row=row+1
                    if not pane.collapsed[stack.name] then
                        for index=2,#stack.items do
                            if selected[stack.items[index]]=='item' then pane.selected[row]=stack.items[index] end
                            row=row+1
                        end
                    end
                end
            end}
    end
    local enhanced, vanilla = class('enhanced'), class('vanilla')
    CleanUI_Clean_ISInventoryPane, CleanUI_Vanilla_ISInventoryPane = enhanced, lateVanilla and nil or vanilla
    ISInventoryPane = initialEnhanced and enhanced or vanilla
    local callbacks = {}
    CleanUI_RegisterInventoryUiToggleCallback = function(callback) callbacks[#callbacks+1]=callback; callback() end
    local function toggle(value)
        if not value then CleanUI_Vanilla_ISInventoryPane=vanilla end
        ISInventoryPane=value and enhanced or vanilla
        for _, callback in ipairs(callbacks) do callback() end
    end
    local function loadConfig()
        if ItemDetailsConfigSource then
            config = assert(loadstring(ItemDetailsConfigSource))()
        else
            local settings=PZAPI.ModOptions:create('BravoItemDetails')
            settings:addTickBox('showNumeric',nil,true,'Show the numeric value (x/y or x%)')
            config={showLabels=true,showBars=true,showNumeric=true,enableSort=true,maxSort='50',
                usesSortDir=1,weaponSortDir=1,vehicleSortDir=1,clothesSortDir=1,foodSortDir=1,fluidSortDir=1}
        end
        return config
    end
    local sorter
    local function loadSorter()
        if ItemDetailsSorterSource then return assert(loadstring(ItemDetailsSorterSource))() end
        local function directions(property, reversed)
            return {function(a,b) return reversed and a[property]<b[property] or (not reversed and a[property]>b[property]) end,
                function(a,b) return reversed and a[property]>b[property] or (not reversed and a[property]<b[property]) end}
        end
        return {condition=directions('condition'),uses=directions('uses'),weapon=directions('condition'),
            tools=directions('condition'),ammo=directions('condition'),hunger=directions('hunger',true),
            fluid=directions('condition'),clothes=directions('condition')}
    end
    local loaded = {}
    require = function(name)
        if name == "PZSurvivorToolkit/InventoryClasses" then
            return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua")
        end
        if loaded[name] then return loaded[name] end
        if name=='BravoItemDetailsConfig' then loaded[name]=loadConfig()
        elseif name=='BravoItemDetailsSorter' then sorter=loadSorter(); loaded[name]=sorter
        elseif name=='BravoItemDetails' then
            officialLoads=officialLoads+1
            if ItemDetailsSource then assert(loadstring(ItemDetailsSource))()
            else
                local native=ISInventoryPane.drawItemDetails
                function ISInventoryPane:drawItemDetails(value, ...)
                    if value and (value.category=='VehicleMaintenance' or value.tags) and config.showNumeric then
                        self:drawText(value.condition..'%')
                    else native(self,value,...) end
                end
                local refresh=ISInventoryPane.refreshContainer
                function ISInventoryPane:refreshContainer(...)
                    refresh(self,...)
                    if not config.enableSort then return end
                    local limit=tonumber(config.maxSort) or 50
                    for _,stack in ipairs(self.itemslist) do
                        if stack.items[1] and stack.items[1].category=='VehicleMaintenance' and not self.collapsed[stack.name] then
                            local items=stack.items
                            table.remove(items,1)
                            local prefix={}
                            for index=1,math.min(limit,#items) do prefix[index]=items[index] end
                            table.sort(prefix,sorter.condition[config.vehicleSortDir])
                            table.insert(prefix,1,prefix[1])
                            for index=limit+1,#items-limit do prefix[#prefix+1]=items[index] end
                            stack.items=prefix
                        end
                    end
                end
            end
            loaded[name]=true
        else return end
        return loaded[name]
    end
    local function pane(items)
        local stack={name='parts',items={items[1]},cleanUIDisplayItem=items[1],count=#items+1}
        for _,value in ipairs(items) do stack.items[#stack.items+1]=value end
        return setmetatable({itemslist={stack},collapsed={},selected={},headerHgt=20,itemHgt=32,fontHgt=20,font='Small',
            text={},bars={},drawText=function(self,text) self.text[#self.text+1]=text end,
            drawProgressBar=function(self,_,_,_,_,fraction) self.bars[#self.bars+1]=fraction end}, {__index=ISInventoryPane})
    end
    if ItemDetailsUpstreamCheck then
        require('BravoItemDetailsConfig'); require('BravoItemDetailsSorter'); require('BravoItemDetails')
        if options.BravoItemDetails.apply then options.BravoItemDetails:apply() end
        local values={}
        for index=1,60 do values[index]=item(index,ItemDetailsUpstreamCheck=='tail' and 'VehicleMaintenance' or nil) end
        local view=pane(values)
        if ItemDetailsUpstreamCheck=='tail' then
            view:refreshContainer()
            assert(#view.itemslist[1].items==61,'upstream lost the large-stack tail')
        else
            view:drawItemDetails(values[1],0,0,0,false)
            assert(#view.bars>0 or view.text[1]=='1%','upstream omitted organizedCategories vehicle condition')
        end
        return
    end
    local originalDraw, originalRefresh = ISInventoryPane.drawItemDetails, ISInventoryPane.refreshContainer
    dofile(adapter)
    assert(ISInventoryPane.drawItemDetails==originalDraw and ISInventoryPane.refreshContainer==originalRefresh and officialLoads==0)
    active.BravoItemDetails=true
    options.BravoItemDetails={}
    dofile(adapter)
    assert(ISInventoryPane.drawItemDetails==originalDraw and ISInventoryPane.refreshContainer==originalRefresh and officialLoads==0)
    options.BravoItemDetails=nil
    dofile(adapter)
    if options.BravoItemDetails.apply then options.BravoItemDetails:apply() end
    assert(officialLoads==1 and #callbacks==1)
    assert(string.format(options.BravoItemDetails.dict.showNumeric.tooltip)=='Show the numeric value (x/y or x%)')
    for _,mode in ipairs({true,false,true,false}) do
        toggle(mode)
        for _,size in ipairs({2,49,50,51,60,100,101,150}) do
            local values={}
            for index=1,size do values[index]=item(index) end
            local view=pane(values)
            view.selected[3]=values[2]
            view.items={view.itemslist[1],unpack(values)}
            view.firstSelect=3
            local originalItems=view.itemslist[1].items
            local before=nativeCalls
            assert(view:refreshContainer()==(mode and 'enhanced' or 'vanilla') and nativeCalls==before+1)
            local sorted=view.itemslist[1].items
            assert(sorted==originalItems and #sorted==size+1,'UI stack lost real items')
            local count=math.min(size,50)
            assert(sorted[1]==values[count] and sorted[2]==values[count],'header does not match sorted first child')
            assert(view.itemslist[1].cleanUIDisplayItem==sorted[1],'CleanUI cached header is stale')
            local seen={}
            for index=2,#sorted do assert(not seen[sorted[index]],'duplicate real item'); seen[sorted[index]]=true end
            for index,value in ipairs(values) do
                assert(seen[value],'real item lost')
                if index>50 then assert(sorted[index+1]==value,'unsorted tail changed order') end
                assert(value.category=='mechanicsVehiclePart','inventory category mutated')
            end
            local selectionIndex=count -- value 2 is at prefix index count-1, UI child row count+0.
            assert(view.selected[selectionIndex]==values[2],'selected item row did not follow sorting')
            assert(view.firstSelect==selectionIndex,'Shift-selection anchor did not follow the physical item')
        end
        local low, high=item(20),item(85)
        local view=pane({low,high})
        local stack=view.itemslist[1]
        view.selected[1]=stack
        view.items={stack,low,high}
        view.firstSelect=1
        view:refreshContainer()
        assert(view.selected[1]==stack and view.firstSelect==1,'selected group lost after its header changed')
        local large={}
        for index=1,60 do large[index]=item(index) end
        local anchorView=pane(large)
        local later={name='later',items={low,low,high}}
        anchorView.itemslist[2]=later
        anchorView.items={anchorView.itemslist[1]}
        for index=1,50 do anchorView.items[#anchorView.items+1]=large[index] end
        anchorView.items[52]=later
        anchorView.firstSelect=52
        anchorView:refreshContainer()
        assert(anchorView.firstSelect==52,'anchor after a clipped large stack uses invisible child rows')
        view:drawItemDetails(low,0,0,0,false)
        assert(view.text[2]=='20%' and view.bars[1]==0.2,'organized vehicle condition missing')
        for _,flags in ipairs({{true,false,false},{false,true,false},{false,false,true},{false,false,false}}) do
            config.showLabels,config.showBars,config.showNumeric=unpack(flags)
            view.text,view.bars={},{}
            local before=#fallbacks
            view:drawItemDetails(high,0,0,0,false)
            assert(#view.text==(flags[1] and 1 or 0)+(flags[3] and 1 or 0) and #view.bars==(flags[2] and 1 or 0))
            if not (flags[1] or flags[2] or flags[3]) then assert(#fallbacks==before+1) end
        end
        config.showLabels,config.showBars,config.showNumeric=true,true,true
        local unknown=item(50,'Other'); unknown.fullType='Base.Unknown'
        local before=#fallbacks
        view:drawItemDetails(unknown,0,0,0,false)
        assert(#fallbacks==before+1 and fallbacks[#fallbacks][1]==(mode and 'enhanced' or 'vanilla'),'wrong UI native fallback')
        config.vehicleSortDir=2
        view=pane({high,low}); view:refreshContainer()
        assert(view.itemslist[1].items[2]==low,'ascending vehicle setting ignored')
        config.vehicleSortDir=1
        for _,limit in ipairs({'not-a-number','1.9'}) do
            config.maxSort=limit
            view=pane({low,high}); view:refreshContainer()
            assert(view.itemslist[1].items[2]==(limit=='1.9' and low or high),'sort limit validation failed')
        end
        config.maxSort='50'
        for _,disabled in ipairs({'collapsed','setting','zero','negative','virtual'}) do
            view=pane({low,high})
            local beforeItems={unpack(view.itemslist[1].items)}
            if disabled=='collapsed' then view.collapsed.parts=true
            elseif disabled=='setting' then config.enableSort=false
            elseif disabled=='zero' then config.maxSort='0'
            elseif disabled=='negative' then config.maxSort='-5'
            else view.itemslist[1].cleanUIFirstActualIndex=1 end
            view:refreshContainer()
            for index,value in ipairs(beforeItems) do assert(view.itemslist[1].items[index]==value,'disabled sort mutated UI stack') end
            config.enableSort,config.maxSort=true,'50'
        end
        for _,category in ipairs({'mechanicsFuel','Other'}) do
            view=pane({item(20,category),item(85,category)})
            view:refreshContainer(); assert(view.itemslist[1].items[2].condition==20,'unhandled item stack sorted')
        end
        for _,kind in ipairs({'Drainable','HandWeapon','Food','Clothing','Magazine','Fluid','Tool'}) do
            low,high=item(20,'Other',kind),item(85,'Other',kind)
            if kind=='Food' then low.hunger,high.hunger=-0.2,-0.85
            elseif kind=='Magazine' then low.ammoMax,high.ammoMax=100,100
            elseif kind=='Fluid' then low.fluid,high.fluid=true,true
            elseif kind=='Tool' then low.tags,high.tags={[ItemTag.SHOW_CONDITION]=true},{[ItemTag.SHOW_CONDITION]=true} end
            view=pane({low,high}); view:refreshContainer()
            assert(view.itemslist[1].items[2]==high,'upstream '..kind..' comparator not used')
            if kind~='Magazine' then
                config.usesSortDir,config.weaponSortDir,config.foodSortDir,config.fluidSortDir,config.clothesSortDir=2,2,2,2,2
                view=pane({high,low}); view:refreshContainer()
                assert(view.itemslist[1].items[2]==low,'upstream '..kind..' ascending setting ignored')
                config.usesSortDir,config.weaponSortDir,config.foodSortDir,config.fluidSortDir,config.clothesSortDir=1,1,1,1,1
            end
            local values={}
            for index=1,60 do
                values[index]=item(index,'Other',kind)
                if kind=='Food' then values[index].hunger=-index/100
                elseif kind=='Magazine' then values[index].ammoMax=100
                elseif kind=='Fluid' then values[index].fluid=true
                elseif kind=='Tool' then values[index].tags={[ItemTag.SHOW_CONDITION]=true} end
            end
            view=pane(values); view:refreshContainer()
            local sorted=view.itemslist[1].items
            assert(#sorted==61 and sorted[2]==values[50],'upstream '..kind..' large prefix failed')
            for index=51,60 do assert(sorted[index+1]==values[index],kind..' tail lost or reordered') end
        end
        view=pane({item(20),item(85)}); view.failNative=true
        assert(not pcall(view.refreshContainer,view),'native refresh error swallowed')
        assert(view.itemslist[1].items[2].condition==20,'sorting ran after native failure')
        view=pane({item(20),item(85)})
        local before={unpack(view.itemslist[1].items)}
        local compare=sorter.condition[1]
        sorter.condition[1]=function() error('comparator failure') end
        assert(not pcall(view.refreshContainer,view),'comparator error swallowed')
        for index,value in ipairs(before) do assert(view.itemslist[1].items[index]==value,'failed comparator mutated the real-item list') end
        sorter.condition[1]=compare
    end
    assert(officialLoads==1,'Item Details reloaded during UI switches')
end
run(true)
run(false)
run(true,true)
print('Item Details organized categories and stack-tail checks passed.')
