local moduleRoot = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
local function run(initialEnhanced, lateVanilla)
    local options = {}
    if NativeModOptionsSource then
        PZAPI = nil
        assert(loadstring(NativeModOptionsSource))()
        options = PZAPI.ModOptions.Dict
    else
        PZAPI = {ModOptions={getOptions=function(_, id) return options[id] end}}
        function PZAPI.ModOptions:create(id, title)
            local value = {dict={},title=title}
            options[id] = value
            function value:addDescription() end
            function value:addTickBox(id, _, default, tooltip)
                local option = {type='tickbox', value=default, tooltip=tooltip, getValue=function(self) return self.value end,
                    setValue=function(self, value) self.value=value end}
                self.dict[id] = option
                return option
            end
            value.addTextEntry = value.addTickBox
            function value:addComboBox(id)
                local option = {type='combobox',value=1,getValue=function(self) return self.value end,
                    setValue=function(self, value) self.value=value end}
                function option:addItem(_, selected) if selected then self.value = 1 end end
                self.dict[id] = option
                return option
            end
            return value
        end
    end
    Events = {}
    ItemTag = {SHOW_CONDITION='ShowCondition',SHARPENABLE='Sharpenable'}
    instanceof = function(item, class) return item and ((class=='InventoryItem' and item.condition~=nil) or item.kind==class) or false end
    luautils = {stringStarts=function(value, prefix) return value:sub(1,#prefix)==prefix end,
        split=function(value, separator)
            local parts={}; for part in value:gmatch('[^'..separator..']+') do parts[#parts+1]=part end
            return parts
        end}
    local function loadPersisted(text)
        getFileReader=function()
            local lines={}; for line in text:gmatch('[^\r\n]+') do lines[#lines+1]=line end
            local index=0
            return {readLine=function() index=index+1; return lines[index] end,close=function() end}
        end
        PZAPI.ModOptions:load()
    end
    round = function(value, precision) local scale=10^(precision or 0); return math.floor(value*scale+0.5)/scale end
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
            getUseDelta=function() return 0.1 end,getCurrentUses=function(self) return self.uses end,getMaxUses=function(self) return self.maxUses or 100 end,
            getCondition=function(self) return self.condition end,getCurrentCondition=function(self) return self.condition end,
            hasHeadCondition=function(self) return self.head~=nil end,hasSharpness=function(self) return self.sharp~=nil end,
            getHeadCondition=function(self) return self.head end,getHeadConditionMax=function() return 10 end,
            getSharpness=function(self) return self.sharp end,
            getMaxAmmo=function(self) return self.ammoMax or 0 end,getCurrentAmmoCount=function(self) return self.ammo or self.condition end,
            getMagazineType=function() return 'Base.Magazine' end,
            getAmmoType=function() return {getItemKey=function() return 'Base.Bullets9mm' end} end,
            getWorldItem=function(self) return self.worldItem end,isFluidContainer=function(self) return self.fluid~=nil end,
            getFluidContainer=function(self) return self.fluid and {getAmount=function() return self.amount or self.condition end,
                getCapacity=function() return 100 end,getColor=function() return color(0,0,1) end,
                contains=function(_,value) return value.id=='water' or value.id=='milk' end} end,
            getHungerChange=function(self) return self.hunger or 0 end,isCosmetic=function(self) return self.cosmetic or false end,
            getHolesNumber=function(self) return self.holes or 0 end,isRoundChambered=function(self) return self.chambered or false end,
            isIsCookable=function(self) return self.cookable or false end,isFrozen=function() return false end,
            getHeat=function(self) return self.heat or 1 end,getCookingTime=function(self) return self.cooking or 0 end,
            getMinutesToCook=function() return 10 end,getMinutesToBurn=function() return 20 end,
            isBurnt=function(self) return self.burnt or false end,getFreezingTime=function(self) return self.freezing or 0 end,
            getCalories=function() return 312.3 end,getCarbohydrates=function() return 12.5 end,
            getProteins=function() return 5.2 end,getLipids=function() return 2.9 end,
            getAllWeaponParts=function(self) local parts=self.parts or {}; return {size=function() return #parts end,get=function(_,index) return parts[index+1] end} end,
            isContainsClip=function(self) return self.clip or false end}
    end
    local nativeCalls, fallbacks = 0, {}
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
                        for index=stack.cleanUIFirstActualIndex or 2,#stack.items do
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
    local loaded = {}
    require = function(name)
        if name == "PZAPI/ModOptions" then return end
        if not loaded[name] then loaded[name] = dofile(moduleRoot .. name .. ".lua") end
        return loaded[name]
    end
    local nativeDraw, nativeRefresh = ISInventoryPane.drawItemDetails, ISInventoryPane.refreshContainer
    local Settings = require "PZSurvivorToolkit/InventoryDetailOptions"
    local Details = require "PZSurvivorToolkit/InventoryDetails"
    local sorter = require "PZSurvivorToolkit/InventoryDetailSort"
    local function setOptions(values)
        for name, value in pairs(values) do Settings[name]:setValue(value) end
    end
    assert(ISInventoryPane.drawItemDetails == nativeDraw and ISInventoryPane.refreshContainer == nativeRefresh,
        'owned modules installed monkeypatches')
    assert(Settings.showNumeric:getValue() and Settings.enableSort:getValue() and Settings.maxSort:getValue() == '50',
        'defaults missing before main menu')
    assert((options.BravoItemDetails.title or options.BravoItemDetails.name) == 'Toolkit Item Details',
        'persisted option namespace or Toolkit title lost')
    assert(string.format(options.BravoItemDetails.dict.showNumeric.tooltip) == 'Show the numeric value (x/y or x%)')
    -- Model the inventory owner's explicit integration, including each class's
    -- own fallback and native-refresh failure propagation.
    for _,class in ipairs({enhanced,vanilla}) do
        local draw,refresh=class.drawItemDetails,class.refreshContainer
        class.drawItemDetails=function(view,value,...)
            if Details.draw(view,value,...) then return end
            return draw(view,value,...)
        end
        class.refreshContainer=function(view,...)
            local anchor=view.items and view.firstSelect and view.items[view.firstSelect]
            local result=refresh(view,...)
            sorter.refresh(view,class,anchor)
            return result
        end
    end
    local function pane(items)
        local stack={name='parts',items={items[1]},cleanUIDisplayItem=items[1],count=#items+1}
        for _,value in ipairs(items) do stack.items[#stack.items+1]=value end
        return setmetatable({itemslist={stack},collapsed={},selected={},headerHgt=20,itemHgt=32,fontHgt=20,font='Small',
            text={},bars={},centers={},textures={},icons={},bounds={},drawText=function(self,text,x)
                self.text[#self.text+1]=text; self.bounds[#self.bounds+1]={kind='text',x=x,width=#text}
            end,
            drawTextCentre=function(self,text,x)
                self.centers[#self.centers+1]=text; self.bounds[#self.bounds+1]={kind='center',x=x-#text/2,width=#text}
            end,
            drawTextureScaled=function(self,texture,x,_,width)
                self.textures[#self.textures+1]=texture; self.bounds[#self.bounds+1]={kind='texture',x=x,width=width}
            end,
            drawProgressBar=function(self,x,_,width,_,fraction)
                self.bars[#self.bars+1]=fraction; self.bounds[#self.bounds+1]={kind='bar',x=x,width=width}
            end}, {__index=ISInventoryPane})
    end
    local function selectionCalls(view)
        local calls={save=0,restore=0}
        local save,restore=view.saveSelection,view.restoreSelection
        view.saveSelection=function(self,selected) calls.save=calls.save+1; return save(self,selected) end
        view.restoreSelection=function(self,selected) calls.restore=calls.restore+1; return restore(self,selected) end
        return calls
    end
    local nutritionist = false
    CharacterTrait = {NUTRITIONIST2='Nutritionist2'}
    getPlayer=function() return {hasTrait=function(_,trait) return nutritionist and trait==CharacterTrait.NUTRITIONIST2 end} end
    getTexture=function(path) return path end
    ScriptManager={instance={getItem=function(_,id) return id end}}
    getScriptManager=function() return {FindItem=function(_,id)
        assert(id=='Base.Bullets9mm'); return {getDisplayName=function() return '9mm Rounds' end}
    end} end
    ISInventoryItem={renderScriptItemIcon=function(view,value) view.icons[#view.icons+1]=value end,
        renderItemIcon=function(view,value) view.icons[#view.icons+1]=value end}
    local water={id='water',getDisplayName=function() return 'Water' end}
    local milk={id='milk',getDisplayName=function() return 'Milk' end}
    local blood={id='blood',getDisplayName=function() return 'Blood' end}
    Fluid={getAllFluids=function() return {size=function() return 3 end,get=function(_,i) return ({water,milk,blood})[i+1] end} end}
    local function draw(value,layout)
        local view=pane({value})
        local handled=Details.draw(view,value,0,0,0,false,layout)
        return view,handled
    end
    local function equal(actual, expected, label)
        assert(#actual==#expected, label..' count: '..#actual..' expected '..#expected)
        for i,value in ipairs(expected) do assert(actual[i]==value, label..' value '..i..': '..tostring(actual[i])) end
    end
    if NativeModOptionsSource then
        -- Vanilla load changes the option objects without Apply or a main-menu event.
        loadPersisted('tickbox|BravoItemDetails|showBars|false\n'
            ..'combobox|BravoItemDetails|vehicleSortDir|2\n'
            ..'textentry|BravoItemDetails|maxSort|2\n')
        local low,high,tail=item(20),item(80),item(5)
        local view=draw(low)
        assert(#view.bars==0 and #view.text==2, 'loaded display preference was not used by rendering')
        view=pane({high,low,tail}); view:refreshContainer()
        assert(view.itemslist[1].items[2]==low and view.itemslist[1].items[3]==high
            and view.itemslist[1].items[4]==tail, 'loaded direction/limit did not preserve the bounded sort')
        loadPersisted('tickbox|BravoItemDetails|showBars|true\n'
            ..'combobox|BravoItemDetails|vehicleSortDir|1\n'
            ..'textentry|BravoItemDetails|maxSort|50\n')
        view=draw(low); assert(#view.bars==1, 'reloaded display preference remained stale')
        view=pane({low,high}); view:refreshContainer()
        assert(view.itemslist[1].items[2]==high, 'reloaded sort preference remained stale')
    end
    assert(Details.draw(pane({}),nil,0,0,0,false)==false, 'nil bypassed native fallback')
    local uses=item(3,'Other','Drainable')
    uses.maxUses=8
    local rendered,handled=draw(uses)
    assert(handled); equal(rendered.text,{'IGUI_invpanel_Remaining:','3/8'},'uses')
    equal(rendered.bars,{3/8},'uses bar')
    uses.maxUses,uses.uses=200,99
    rendered=draw(uses); equal(rendered.text,{'IGUI_invpanel_Remaining:','50%'},'large uses')
    local weapon=item(80,'Other','HandWeapon')
    weapon.head,weapon.sharp,weapon.ammoMax,weapon.ammo,weapon.chambered=5,0.75,15,7,true
    weapon.clip,weapon.parts=true,{'scope','laser'}
    rendered=draw(weapon)
    equal(rendered.text,{'Tooltip_weapon_Condition:','80%','IGUI_health_Head:','50%','Tooltip_weapon_Sharpness:','75%','8/15'},'weapon details')
    equal(rendered.bars,{0.8,0.5,0.75},'weapon bars')
    equal(rendered.icons,{'Base.Magazine','scope','laser'},'weapon icons')
    local magazine=item(5,'Other','Magazine'); magazine.ammoMax=15
    rendered=draw(magazine)
    equal(rendered.text,{'9mm Rounds:','5/15'},'magazine')
    local food=item(100,'Other','Food'); food.hunger=-0.25
    rendered=draw(food)
    equal(rendered.text,{'IGUI_invpanel_Nutrition:'},'food label')
    equal(rendered.centers,{'-25'},'hunger'); equal(rendered.bars,{0.25},'hunger bar')
    assert(#rendered.textures==0,'Nutritionist shown without trait')
    nutritionist=true
    rendered=draw(food)
    equal(rendered.centers,{'-25','312','13','5','3'},'nutrition stats')
    equal(rendered.textures,{'media/ui/PZSurvivorToolkit/item-details/calories.png','media/ui/PZSurvivorToolkit/item-details/carbs.png',
        'media/ui/PZSurvivorToolkit/item-details/proteins.png','media/ui/PZSurvivorToolkit/item-details/lipids.png'},'nutrition icons')
    -- BC owns a permanent "100%" slot on expanded perishable food rows.
    -- Reserve each baseline field in turn, including icons and the progress bar,
    -- so a layout change cannot solve hunger while leaving another collision.
    local baseline=rendered
    assert(baseline.bounds[1].x==70 and baseline.bounds[2].x==104 and baseline.bounds[2].width==80
        and baseline.bounds[3].x==194.5 and baseline.bounds[4].x==208,
        'unreserved food coordinates changed')
    local function clearOf(view,layout)
        for _,bound in ipairs(view.bounds) do
            assert(bound.x+bound.width<=layout.reservedLeft or bound.x>=layout.reservedRight,
                bound.kind..' overlapped the reserved freshness field')
        end
    end
    for _,bound in ipairs(baseline.bounds) do
        local midpoint=bound.x+bound.width/2
        local layout={reservedLeft=midpoint-2,reservedRight=midpoint+2}
        local shifted=draw(food,layout)
        clearOf(shifted,layout)
        equal(shifted.text,baseline.text,'reserved food labels')
        equal(shifted.bars,baseline.bars,'reserved nutrition bar')
        equal(shifted.centers,baseline.centers,'reserved nutrition values')
        equal(shifted.textures,baseline.textures,'reserved nutrition icons')
    end
    local getCalories=food.getCalories
    food.getCalories=function() return 1234567 end
    local oversized=draw(food)
    local largeValue=oversized.bounds[5]
    local narrowSlot={reservedLeft=largeValue.x,reservedRight=largeValue.x+4}
    clearOf(draw(food,narrowSlot),narrowSlot)
    food.getCalories=getCalories
    local unchanged=draw(food)
    for index,bound in ipairs(baseline.bounds) do
        assert(unchanged.bounds[index].x==bound.x and unchanged.bounds[index].width==bound.width,
            'layout omitted changed the original coordinates')
    end
    local hungerBound=baseline.bounds[3]
    local freshness={reservedLeft=hungerBound.x,reservedRight=hungerBound.x+#'100%'}
    rendered=draw(food,freshness); clearOf(rendered,freshness)
    setOptions{showLabels=false,showBars=false,showNumeric=true}
    rendered=draw(food,freshness); clearOf(rendered,freshness)
    assert(#rendered.text==0 and #rendered.bars==0 and #rendered.centers==5 and #rendered.textures==4,
        'reservation changed numeric/Nutritionist preferences')
    setOptions{showLabels=true,showBars=true,showNumeric=true}
    Settings.showNutritionist:setValue(false)
    rendered=draw(food,freshness); clearOf(rendered,freshness)
    assert(#rendered.textures==0,'Nutritionist toggle ignored')
    Settings.showNutritionist:setValue(true); nutritionist=false
    food.cookable,food.heat,food.cooking=true,2,5
    Settings.showBars:setValue(false)
    rendered=draw(food)
    equal(rendered.text,{'IGUI_invpanel_Cooking:'},'cooking label')
    equal(rendered.bars,{0.5},'cooking bar always visible'); equal(rendered.centers,{'50%','-25'},'cooking stats')
    Settings.showBars:setValue(true); food.cooking=15
    rendered=draw(food); equal(rendered.text,{'IGUI_invpanel_Burning:'},'burning label'); equal(rendered.bars,{0.5},'burning bar')
    food.cooking,food.burnt=25,true
    rendered=draw(food); equal(rendered.text,{'IGUI_invpanel_Burnt'},'burnt label'); equal(rendered.bars,{},'burnt bar')
    food.cookable,food.burnt,food.freezing=false,false,20
    rendered=draw(food); equal(rendered.text,{'IGUI_invpanel_FreezingTime:'},'freezing label')
    equal(rendered.bars,{0.2},'freezing bar'); equal(rendered.centers,{'20%','-25'},'freezing stats')
    food.freezing,food.hunger=0,0
    rendered,handled=draw(food); assert(not handled and #rendered.text==0,'unhandled food bypassed native fallback')
    local fluid=item(100,'Other','Fluid'); fluid.fluid,fluid.amount=true,12.345
    rendered=draw(fluid); equal(rendered.text,{'Water/Milk:','12.35/100.00'},'fluid blend')
    fluid.amount=0
    rendered=draw(fluid); equal(rendered.text,{'Fluid_Empty: ','0.00/100.00'},'empty fluid')
    fluid.amount=12.345
    local ground=item(100,'Other')
    ground.worldItem={kind='IsoWorldInventoryObject',getFluidContainer=function() return fluid:getFluidContainer() end}
    rendered=draw(ground); equal(rendered.text,{'Water/Milk:','12.35/100.00'},'world fluid')
    local clothes=item(40,'Other','Clothing'); clothes.holes=3
    rendered=draw(clothes); equal(rendered.text,{'IGUI_invpanel_Condition:','40%','(3)'},'clothing')
    clothes.cosmetic=true
    rendered,handled=draw(clothes); assert(not handled,'cosmetic clothing bypassed native fallback')
    for _,fullType in ipairs({'Base.PetrolCan','Base.JerryCan'}) do
        local value=item(100,'VehicleMaintenance'); value.fullType=fullType
        rendered,handled=draw(value); assert(not handled,'fuel can acquired vehicle condition details')
    end
    -- Generic native branches (melting/drying/etc.) must retain their renderer.
    rendered,handled=draw(item(20,'Other')); assert(not handled and #rendered.text==0,'native details fallback lost')
    -- Preserve upstream presentation flags: gun ammo/attachments and clothing
    -- holes remain visible while any details representation is enabled.
    setOptions{showLabels=false,showBars=true,showNumeric=false}
    rendered=draw(weapon); equal(rendered.text,{'8/15'},'gun compact ammo'); equal(rendered.icons,{'Base.Magazine','scope','laser'},'gun compact icons')
    clothes.cosmetic=false
    rendered=draw(clothes); equal(rendered.text,{'(3)'},'clothes compact holes')
    setOptions{showLabels=false,showBars=false,showNumeric=false}
    for _,value in ipairs({uses,weapon,magazine,food,fluid,clothes}) do
        rendered,handled=draw(value); assert(not handled and #rendered.text==0 and #rendered.bars==0,'all-off did not use native fallback')
    end
    setOptions{showLabels=true,showBars=true,showNumeric=true}
    -- Comparator tiebreaks remain compatible with the upstream feature set.
    local sameA,sameB=item(50,'Other','HandWeapon'),item(50,'Other','HandWeapon')
    sameA.ammoMax,sameB.ammoMax,sameA.ammo,sameB.ammo=10,10,4,4
    sameA.chambered=true
    assert(sorter.weapon[1](sameA,sameB) and sorter.weapon[2](sameB,sameA),'chambered-round sort lost')
    sameA.chambered=false; sameA.parts={'scope'}
    assert(sorter.weapon[1](sameA,sameB),'attachment sort tiebreak lost')
    sameA.ammoMax,sameB.ammoMax,sameA.head,sameB.head=0,0,8,5
    assert(sorter.tools[1](sameA,sameB) and sorter.tools[2](sameB,sameA),'head sort tiebreak lost')
    sameA.head,sameB.head,sameA.sharp,sameB.sharp=5,5,0.9,0.5
    assert(sorter.weapon[1](sameA,sameB) and sorter.weapon[2](sameB,sameA),'sharpness sort tiebreak lost')
    sameA.holes,sameB.holes=2,1
    assert(sorter.clothes[1](sameA,sameB) and sorter.clothes[2](sameB,sameA),'holes sort tiebreak lost')
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
        -- A refresh can rebuild rows without leaving any prefix for the sorter.
        -- Keep its current selection untouched, but still project its Shift anchor.
        for _,reason in ipairs({'collapsed','virtual','unsupported','single','one-item-prefix'}) do
            local values=reason=='unsupported' and {item(20,'Other'),item(85,'Other')} or {low,high}
            local idle=pane(values)
            local group=idle.itemslist[1]
            local anchor,index=values[2],3
            if reason=='collapsed' then idle.collapsed.parts=true; anchor,index=group,1
            elseif reason=='virtual' then group.cleanUIFirstActualIndex=1; group.items=values
            elseif reason=='single' then group.items={low,low}; anchor,index=low,2
            elseif reason=='one-item-prefix' then Settings.maxSort:setValue('1') end
            idle.selected[index]=anchor
            idle.firstSelect=99
            local calls=selectionCalls(idle)
            sorter.refresh(idle,ISInventoryPane,anchor)
            assert(calls.save==0 and calls.restore==0,reason..' prefix rebuilt selection')
            assert(idle.selected[index]==anchor and next(idle.selected,index)==nil,
                reason..' prefix changed the existing selection')
            assert(idle.firstSelect==index,reason..' prefix lost its Shift anchor')
            Settings.maxSort:setValue('50')
        end
        local ordered=pane({low,high})
        local otherLow,otherHigh=item(10),item(90)
        ordered.itemslist[2]={name='other',items={otherLow,otherLow,otherHigh}}
        ordered.selected[1]=ordered.itemslist[1]
        ordered.selected[5]=otherLow
        local calls=selectionCalls(ordered)
        sorter.refresh(ordered,ISInventoryPane,otherLow)
        assert(calls.save==1 and calls.restore==1,'multiple sorted prefixes rebuilt selection more than once')
        assert(ordered.itemslist[1].items[2]==high and ordered.itemslist[2].items[2]==otherHigh,
            'eligible prefixes were not sorted')
        assert(ordered.selected[1]==ordered.itemslist[1] and ordered.selected[6]==otherLow and ordered.firstSelect==6,
            'sorted prefixes did not retain group, physical selection and Shift anchor')
        local view=pane({low,high})
        local stack=view.itemslist[1]
        view.selected[1]=stack
        view.items={stack,low,high}
        view.firstSelect=1
        view:refreshContainer()
        assert(view.selected[1]==stack and view.firstSelect==1,'selected group lost after its header changed')
        -- CleanUI 42.19 omits collapsed equipment from rendered rows but keeps its separator.
        -- Sort a visible stack after that section so the physical anchor must move within it.
        for _, physical in ipairs({false,true}) do
            local hiddenView=pane({low,high})
            local visible=hiddenView.itemslist[1]
            local equipped={name='equipped',equipped=true,items={low,low}}
            local separator={name='equipment-header',type='separator',items={}}
            hiddenView.itemslist={equipped,separator,visible}
            hiddenView.equippedCollapsed=true
            hiddenView.collapsed.equipped=true
            hiddenView.items={separator,visible,low,high}
            hiddenView.firstSelect=physical and 3 or 2
            hiddenView.selected[hiddenView.firstSelect]=physical and low or visible
            hiddenView:refreshContainer()
            local expected=physical and 4 or 2
            assert(hiddenView.firstSelect==expected,
                'hidden equipment shifted the visible '..(physical and 'physical item' or 'group')..' anchor')
        end
        local virtualView=pane({low,high})
        local visible=virtualView.itemslist[1]
        virtualView.itemslist={
            {name='virtual',cleanUIFirstActualIndex=1,items={low,high}},visible}
        virtualView.items={virtualView.itemslist[1],low,high,visible,low,high}
        virtualView.firstSelect=4
        virtualView:refreshContainer()
        assert(virtualView.firstSelect==4,'virtual headers must count their first actual child')
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
            setOptions{showLabels=flags[1],showBars=flags[2],showNumeric=flags[3]}
            view.text,view.bars={},{}
            local before=#fallbacks
            view:drawItemDetails(high,0,0,0,false)
            assert(#view.text==(flags[1] and 1 or 0)+(flags[3] and 1 or 0) and #view.bars==(flags[2] and 1 or 0))
            if not (flags[1] or flags[2] or flags[3]) then assert(#fallbacks==before+1) end
        end
        setOptions{showLabels=true,showBars=true,showNumeric=true}
        local unknown=item(50,'Other'); unknown.fullType='Base.Unknown'
        local before=#fallbacks
        view:drawItemDetails(unknown,0,0,0,false)
        assert(#fallbacks==before+1 and fallbacks[#fallbacks][1]==(mode and 'enhanced' or 'vanilla'),'wrong UI native fallback')
        Settings.vehicleSortDir:setValue(2)
        view=pane({high,low}); view:refreshContainer()
        assert(view.itemslist[1].items[2]==low,'ascending vehicle setting ignored')
        Settings.vehicleSortDir:setValue(1)
        for _,limit in ipairs({'not-a-number','1.9'}) do
            Settings.maxSort:setValue(limit)
            view=pane({low,high}); view:refreshContainer()
            assert(view.itemslist[1].items[2]==(limit=='1.9' and low or high),'sort limit validation failed')
        end
        Settings.maxSort:setValue('50')
        for _,disabled in ipairs({'collapsed','setting','zero','negative','virtual'}) do
            view=pane({low,high})
            local beforeItems={unpack(view.itemslist[1].items)}
            if disabled=='collapsed' then view.collapsed.parts=true
            elseif disabled=='setting' then Settings.enableSort:setValue(false)
            elseif disabled=='zero' then Settings.maxSort:setValue('0')
            elseif disabled=='negative' then Settings.maxSort:setValue('-5')
            else view.itemslist[1].cleanUIFirstActualIndex=1 end
            view:refreshContainer()
            for index,value in ipairs(beforeItems) do assert(view.itemslist[1].items[index]==value,'disabled sort mutated UI stack') end
            setOptions{enableSort=true,maxSort='50'}
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
                setOptions{usesSortDir=2,weaponSortDir=2,foodSortDir=2,fluidSortDir=2,clothesSortDir=2}
                view=pane({high,low}); view:refreshContainer()
                assert(view.itemslist[1].items[2]==low,'upstream '..kind..' ascending setting ignored')
                setOptions{usesSortDir=1,weaponSortDir=1,foodSortDir=1,fluidSortDir=1,clothesSortDir=1}
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
    assert(#callbacks==0, 'owned modules registered UI toggle hooks')
end
run(true)
run(false)
run(true,true)
print('Owned Item Details rendering, settings, selection and lossless sorting checks passed.')
