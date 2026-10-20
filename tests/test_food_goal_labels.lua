-- Execute the selected upstream menu producer. The tested wrapper may change
-- presentation only; native callback identities, parameters and clicks survive.
if not NativeWishlistWorkshopRoot then
    print('Food goal labels SKIP (pass --wishlist-workshop-root).'); return
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local value = file:read('*a'); file:close(); return value:gsub('\r', '')
end
local upstreamPath = NativeWishlistWorkshopRoot .. '/3456212729/mods/EatSmartInt/42/media/lua/client/ISUI/ES_subMenuEat.lua'
local upstream = read(upstreamPath)
local function reader(value)
    local position = 1
    return {close = function() end, readLine = function()
        if position > #value then return end
        local boundary = value:find('\n', position, true) or #value + 1
        local line = value:sub(position, boundary - 1); position = boundary + 1; return line
    end}
end
local function close(a,b) return type(a)=='number' and type(b)=='number' and math.abs(a-b)<.000001 end
local function copy(value)
    local result = {}; for key,item in pairs(value or {}) do result[key] = item end; return result
end
local function equal(actual,expected)
    for key,value in pairs(expected) do assert(actual[key]==value,'changed native field '..tostring(key)) end
    for key in pairs(actual) do assert(expected[key]~=nil,'added native field '..tostring(key)) end
end
local pendingNativeTooltip
local function setup(language,mode)
    local translations = assert(FoodGoalTranslations and FoodGoalTranslations[language], 'runner must load shipped EN/RU translations')
    PZSurvivorToolkit, EatSmart_Debug, ES_subMenuEat = {}, nil, nil
    local events, calls = {}, {}; pendingNativeTooltip=nil
    Events = {OnGameStart = {Add = function(callback) events[#events+1]=callback end}}
    getText = function(key,...)
        local text=translations[key] or key;local args={...}
        return (text:gsub('%%(%d+)',function(index)return tostring(args[tonumber(index)] or '%'..index)end))
    end
    getActivatedMods=function()return {contains=function(_,id)return mode~='inactive' and id=='EatSmartInt'end}end
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getModFileReader=function(id,path)
        assert(id=='EatSmartInt' and path=='media/lua/client/ISUI/ES_subMenuEat.lua')
        return reader(upstream .. (mode=='changed-source' and '\n-- changed\n' or ''))
    end
    local proof=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
    require=function(name)
        if name=='PZSurvivorToolkit/SourceProof'then return proof end
    end
    local options={['1']=true,['2']=true,['3']=5,['4']=true,['5']=true,['6']=true,['7']=200,['8']=true,['9']=50}
    local values={base=-.4,hung=-.3,calories=10000,proteins=1000,hunger=.1,actorCalories=-100,actorProteins=-10,weight=80,trait=false}
    local food={getBaseHunger=function()return values.base end,getHungChange=function()return values.hung end,
        getCalories=function()return values.calories end,getProteins=function()return values.proteins end,
        getID=function()return 42 end,setBaseHunger=function(_,value)values.base=value end}
    food.getHungerChange=food.getHungChange
    local nutrition={getCalories=function()return values.actorCalories end,getProteins=function()return values.actorProteins end,
        getWeight=function()return values.weight end}
    local player={getStats=function()return {getHunger=function()return values.hunger end}end,
        getNutrition=function()return nutrition end,HasTrait=function()return values.trait end}
    getSpecificPlayer=function(index)assert(index==0);return player end
    ISInventoryPane={getActualItems=function(items)return items end}
    ISInventoryPaneContextMenu={addToolTip=function()
            local tooltip={}
            if pendingNativeTooltip then pendingNativeTooltip.tooltip=tooltip;pendingNativeTooltip=nil end
            return tooltip
        end,
        onEatItems=function(items,portion,index,opening,eatPercentage)
            calls[#calls+1]={item=items[1],portion=portion,index=index,opening=opening,eatPercentage=eatPercentage}
        end}
    PZAPI={ModOptions={getOptions=function(_,id)
        assert(id=='EatSmart');return {getOption=function(_,key)return {getValue=function()return options[key] or false end}end}
    end}}
    SandboxVars,Excrementum={},nil
    assert(loadstring(upstream,'@'..upstreamPath))()
    local original=ES_subMenuEat
    if mode=='foreign-method'then ES_subMenuEat=function()end end
    local before=ES_subMenuEat
    local labels=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/FoodGoalLabels.lua'))()
    return {labels=labels,language=language,events=events,options=options,values=values,food=food,player=player,original=original,
        before=before,calls=calls,rows={food},text=function(key)return getText('UI_PZST_FoodGoal_'..key)end}
end
local function menu()
    local result={options={},added={}}
    result.addOption=function(self,name,target,onSelect,...)
        local option={name=name,target=target,onSelect=onSelect,marker={}}
        local parameters={n=select('#',...),...}
        for i=1,parameters.n do option['param'..i]=parameters[i]end
        self.options[#self.options+1]=option
        local created={option=option,name=name,target=target,onSelect=onSelect,parameters=parameters,
            metadata=type(option.param5)=='table' and copy(option.param5) or nil,marker=option.marker}
        self.added[#self.added+1]=created
        if not onSelect then pendingNativeTooltip=created end
        return option
    end
    return result
end
local function choose(option)
    assert(type(option.onSelect)=='function')
    return option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6)
end
local function build(s,expected,options)
    local m=menu();local foreign={name='Foreign result',ES_EatSmart=true,onSelect=function()end,param1={},toolTip={description='foreign why'}}
    m.options[1]=foreign;local saved=copy(foreign)
    ES_subMenuEat(m,s.rows,s.rows,0,s.player,options and options.opening)
    equal(foreign,saved)
    assert(#m.added==#expected,'actual goal visibility differs: '..#m.added..' ~= '..#expected)
    for index,spec in ipairs(expected)do
        local created=m.added[index];local option=created.option
        local expectedName=s.text(spec[1])..(spec[2] and ' ('..spec[2]..')' or '')
        assert(option.name==expectedName,s.language..' goal '..index..': '..tostring(option.name)..' ~= '..expectedName)
        assert(option.ES_EatSmart==true and option.target==created.target and option.onSelect==created.onSelect and option.marker==created.marker,
            'presentation must preserve the native row/callback/target')
        for i=1,6 do assert(option['param'..i]==created.parameters[i],'presentation changed native param'..i)end
        if spec[2]then
            assert(option.target==s.rows and option.param2==0 and option.param3==(options and options.opening),
                'original submenu arguments must reach native callback parameters')
        end
        if created.metadata then equal(option.param5,created.metadata)end
        assert(option.notAvailable==(not spec[2] and true or nil),'availability changed')
        assert(option.toolTip and type(option.toolTip.description)=='string','original numeric target must remain discoverable')
        local targetLine=getText('UI_PZST_FoodGoal_Target',created.name)
        assert(option.toolTip.description:find(targetLine,1,true),'original goal missing from tooltip: '..created.name)
        if not spec[2]then
            assert(option.toolTip==created.tooltip,'disabled row must retain the original tooltip object')
            assert(option.toolTip.description:find(getText(spec[3] or 'Tooltip_Goal_Exceeded'),1,true),'disabled native reason lost')
        end
    end
    return m
end
for _,language in ipairs({'EN','RU'})do
    local s=setup(language)
    for _,key in ipairs({'Full','Snack','FullReserve','GainWeight','EnergyBalance','EnergyReserve','EnergyDeficit','ProteinReserve','ProteinBalance','ProteinDeficit'})do
        local value=s.text(key);assert(value~='UI_PZST_FoodGoal_'..key,'missing shipped translation '..language..' '..key)
        local words=0;for _ in value:gmatch('%S+')do words=words+1 end
        assert(words<=2,language..' outcome label exceeds two words: '..value)
    end
    assert(s.labels.install()==true,'pinned selected EatSmartInt source must install')
    local wrapped=ES_subMenuEat
    assert(wrapped~=s.original and s.labels.install()==true and ES_subMenuEat==wrapped,'installation must be idempotent')
    for _,callback in ipairs(s.events)do callback()end
    assert(ES_subMenuEat==wrapped,'OnGameStart must not stack wrappers')
    local opening={}
    local full=build(s,{{'Full','33%'},{'Snack','17%'},{'FullReserve','38%'},{'GainWeight','11%'},{'EnergyReserve','3%'},{'ProteinReserve','6%'}},{opening=opening})
    local baseline=menu();s.original(baseline,s.rows,s.rows,0,s.player,opening)
    s.values.actorCalories=-50
    choose(baseline.options[5]);choose(full.options[6])
    assert(#s.calls==2 and s.calls[1].item==s.food and s.calls[2].item==s.food
        and close(s.calls[1].portion,s.calls[2].portion)and close(s.calls[2].portion,.01875)
        and s.calls[1].eatPercentage==s.calls[2].eatPercentage and s.calls[1].opening==opening and s.calls[2].opening==opening,
        'renaming must retain actual click-time portion recalculation and native opening recipe')
    s.options['3']=0
    build(s,{{'Full','33%'},{'Full','33%'},{'FullReserve','38%'},{'GainWeight','11%'},{'EnergyReserve','3%'},{'ProteinReserve','6%'}})
    -- Outcome labels classify calories/protein goals by sign. Exercise all three
    -- outcomes without depending on numeric-label parsing or English units.
    s.values.actorCalories=-1000;s.values.actorProteins=-100
    for _,spec in ipairs({{200,50,'EnergyReserve','ProteinReserve','12%','15%'},{0,0,'EnergyBalance','ProteinBalance','10%','10%'},
        {-200,-50,'EnergyDeficit','ProteinDeficit','8%','5%'}})do
        s.options['7'],s.options['9']=spec[1],spec[2]
        build(s,{{'Full','33%'},{'Full','33%'},{'FullReserve','47%'},{'GainWeight','20%'},{spec[3],spec[5]},{spec[4],spec[6]}})
    end
    -- Hidden nutrition goals cannot shift hunger labels; calories absence
    -- cannot accidentally classify a protein row as an energy row.
    SandboxVars={EatSmart={NeedNutritionist=true}}
    build(s,{{'Full','33%'},{'Full','33%'}})
    SandboxVars={};s.values.calories=0
    build(s,{{'Full','33%'},{'Full','33%'},{'ProteinDeficit','5%'}})
    s.values.calories=10000;s.values.hunger=0;s.values.actorCalories=4000;s.values.actorProteins=100
    s.options['3']=5;s.options['7']=3700;s.options['9']=50
    build(s,{{'Full'},{'Snack'},{'FullReserve'},{'GainWeight'},{'EnergyReserve'},{'ProteinReserve'}})
    s.options['4']=false;s.options['5']=false
    build(s,{{'Full'},{'Snack'},{'EnergyReserve'},{'ProteinReserve'}})
    s.options['4'],s.options['5'],s.options['7']=true,true,200
    s.values.hunger=.8;s.values.actorCalories=-1000;s.values.actorProteins=-100
    s.values.calories=100;s.values.proteins=5
    build(s,{{'Full',nil,'Tooltip_Not_enough_food'},{'Snack',nil,'Tooltip_Not_enough_food'},
        {'FullReserve',nil,'Tooltip_Not_enough_food'},{'GainWeight',nil,'Tooltip_Not_enough_food'},
        {'EnergyReserve',nil,'Tooltip_Not_enough_food'},{'ProteinReserve',nil,'Tooltip_Not_enough_food'}})
    -- Fractions displayed are of the remaining food. Snap the tiny native
    -- tail to all; never show a misleading rounded zero for a small portion.
    for _,key in ipairs({'2','4','5','6','8'})do s.options[key]=false end
    s.values.hunger=.001;s.values.hung=-.3
    build(s,{{'Full','<1%'}})
    s.values.hunger=.295
    build(s,{{'Full','100%'}})
    s.values.base=-.1;s.values.hung=-.3;s.values.hunger=.1
    build(s,{{'Full','33%'}})
end
for _,mode in ipairs({'changed-source','foreign-method'})do
    local s=setup('EN',mode)
    assert(not s.labels.install()and ES_subMenuEat==s.before,mode..' must not install over unknown source or predecessor')
end
local s=setup('EN');assert(s.labels.install())
local foreign=function()end;ES_subMenuEat=foreign
assert(not s.labels.install()and ES_subMenuEat==foreign,'later foreign replacement must not be overwritten')
print('Food goal labels: actual pinned EatSmartInt producer, EN/RU compact outcomes, remaining portions, hidden/disabled rows, exact callbacks/parameters and install guards passed.')
