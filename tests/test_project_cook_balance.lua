-- Actual selected panel/helpers and shipped compatibility installer; UI/logic
-- effects are explicit doubles. This does not claim evolved-recipe edit support.
if not NativeActionRoot or not (NativeCookCraftPanelSourcePath or NativeWishlistWorkshopRoot) then
    if TestCoverage then TestCoverage('source-contract','skipped','Project Cook balance requires native and Workshop sources.')end
    return
end
local inputs={
    Project_Cook={
        ['client/Project_Cook/HandCraftPanel/PJCK_CraftActionPanel.lua']={NativeCookCraftPanelSourcePath,NativeCookCraftPanelSource},
        ['client/Project_Cook/PJCK_UIScale.lua']={NativeCookUIScaleSourcePath,NativeCookUIScaleSource},
        ['client/Project_Cook/PJCK_Config.lua']={NativeCookConfigSourcePath,NativeCookConfigSource},
        ['client/Project_Cook/PJCK_Viewport.lua']={NativeCookViewportSourcePath,NativeCookViewportSource},
        ['shared/Project_Cook/PJCK_FrozenCooking.lua']={NativeCookFrozenSourcePath,NativeCookFrozenSource},
        ['client/Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction.lua']={NativeCookActionOverridesSourcePath,NativeCookActionOverridesSource},
    },
    Neat_Crafting={['client/Neat_Crafting/NC_CraftActionPanel.lua']={NativeNeatCraftPanelSourcePath,NativeNeatCraftPanelSource}},
}
local bound={}
for _,files in pairs(inputs)do for _,entry in pairs(files)do if entry[1]and entry[2]then bound[entry[1]]=entry[2]end end end
local function sourcePath(id,relative)
    local entry=inputs[id]and inputs[id][relative]
    if entry and entry[1]then return entry[1]end
    if not NativeWishlistWorkshopRoot then return end
    local root=id=='Neat_Crafting'and'/3502080466/mods/Neat_Crafting/common/media/lua/'
        or'/3490188370/mods/Project_Cook/common/media/lua/'
    return NativeWishlistWorkshopRoot..root..relative
end
local function read(path)
    if bound[path]then return bound[path]:gsub('\r','')end
    if NativeReadText then return NativeReadText(path):gsub('\r','')end
    local file=assert(io.open(path));local value=file:read('*a');file:close();return value:gsub('\r','')
end
local function setup(change,withNeat)
    NativeKahluaTableLookup=true
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    for _,name in ipairs({'PJCK_CraftActionPanel','PJCK_Config','PJCK_UIScale','PJCK_Viewport','PJCK_FrozenCooking'})do _G[name]=nil end
    ISPanel=ISBaseObject:derive('ISPanel')
    UIFont={Small='small',Medium='medium',Large='large'}
    SandboxVars={ProjectCook={AllowFrozenCooking=false}}
    f.native('shared/TimedActions/ISDumpContentsAction.lua')
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined+1 end
    getActivatedMods=function()return {contains=function(_,id)return id=='Project_Cook'or withNeat and id=='Neat_Crafting'end}end
    getModFileReader=function(id,path)
        assert(id=='Project_Cook'or withNeat and id=='Neat_Crafting')
        local text=read(assert(sourcePath(id,path:gsub('^media/lua/',''))))
        if change and path:find(change,1,true)then text=text..'-- unreviewed source\n'end
        local position=1
        return {close=function()end,readLine=function()
            if position>#text then return end
            local boundary=text:find('\n',position,true)or #text+1
            local line=text:sub(position,boundary-1);position=boundary+1;return line
        end}
    end
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
    local previous,loaded,nativeComplete=require,{},nil
    require=function(module)
        if loaded[module]then return loaded[module]end
        if module:match('^Project_Cook/')then
            local path
            for _,side in ipairs({'client','shared','server'})do
                local candidate=sourcePath('Project_Cook',side..'/'..module..'.lua')
                local exists=candidate and (bound[candidate]or NativeFileExists and NativeFileExists(candidate))
                if candidate and not exists and not NativeFileExists then local file=io.open(candidate);exists=file~=nil;if file then file:close()end end
                if exists then path=candidate;break end
            end
            assert(path,'missing selected Project Cook module '..module)
            loaded[module]=true
            local ok,value=pcall(assert(loadstring(read(path),'@'..path)))
            if not ok then loaded[module]=nil;error(value)end
            if module=='Project_Cook/HandCraftPanel/PJCK_CraftActionPanel'then
                nativeComplete=PJCK_CraftActionPanel.onHandcraftActionComplete
                if change=='foreign-complete'then PJCK_CraftActionPanel.onHandcraftActionComplete=function()error('foreign complete executed')end end
            end
            loaded[module]=value or true;return loaded[module]
        elseif module:match('^PZSurvivorToolkit/')then
            local name=module:match('/([^/]+)$')
            if PZSurvivorToolkit[name]then return PZSurvivorToolkit[name]end
            loaded[module]=true
            local value=f.project(name)
            loaded[module]=value or PZSurvivorToolkit[name]or true;return loaded[module]
        elseif module=='TimedActions/ISAddItemInRecipe'then
            f.native('shared/TimedActions/ISAddItemInRecipe.lua');return true
        elseif module=='Entity/TimedActions/ISHandcraftAction'then
            f.native('shared/Entity/TimedActions/ISHandcraftAction.lua');return true
        end
        return previous(module)
    end
    if change=='preloaded'then require('Project_Cook/HandCraftPanel/PJCK_CraftActionPanel')end
    local compat=f.project('ActionQueueCompat');compat.install()
    return compat,nativeComplete
end
if TestProjectCookBalanceFixtureOnly then return setup end
local function batch(class)
    class.__index=class -- Native UI construction owns this child slot.
    local starts,stops,refreshes,text=0,0,0,nil
    local logic={startCraftAction=function()starts=starts+1 end,stopCraftAction=function()stops=stops+1 end,
        autoPopulateInputs=function()end,sortRecipeList=function()end}
    local panel=setmetatable({logic=logic,craftTimes=2,
        HandCraftPanel={updateContainers=function()refreshes=refreshes+1 end},
        quantityInput={setText=function(_,value)text=value end}},class)
    return panel,function()return starts,stops,refreshes,text end
end
do
    local compat,native=setup()
    assert(compat.isInstalled('Project_Cook_Balance')and not compat.isInstalled('Project_Cook')
        and not compat.isInstalled('Project_Cook_FirstAddition'),'balance proof acquired evolved-recipe authority')
    local class=PJCK_CraftActionPanel
    local panel,counts=batch(class)
    assert(not compat.isCraftOwner('PJCK_CraftActionPanel',panel,{}),'balance-only panel acquired a craft edit contract')
    for _=1,2 do class.onHandcraftActionStart(panel,{});native(panel)end
    local starts,stops=counts()
    assert(starts==2 and stops==1,'actual selected native panel did not reproduce its start/stop imbalance')
    panel,counts=batch(class)
    for _=1,2 do class.onHandcraftActionStart(panel,{});class.onHandcraftActionComplete(panel)end
    local refreshed,displayed
    starts,stops,refreshed,displayed=counts()
    assert(starts==stops and stops==2 and refreshed==2 and displayed=='1'and panel.craftTimes==nil,
        'source-verified repair changed native batch completion or failed to balance native starts')
    panel,counts=batch(class)
    PZSurvivorToolkit.Settings.actionQueue=function()return false end
    class.onHandcraftActionStart(panel,{});class.onHandcraftActionComplete(panel)
    starts,stops=counts();assert(starts==1 and stops==0,'disabled queue changed native completion')
end
for _,changed in ipairs({'PJCK_CraftActionPanel.lua','PJCK_UIScale.lua','PJCK_Config.lua','PJCK_Viewport.lua','PJCK_FrozenCooking.lua','foreign-complete','preloaded'})do
    local compat,native=setup(changed)
    assert(not compat.isInstalled('Project_Cook_Balance')and not compat.isInstalled('Project_Cook'),
        'unknown/early source acquired a balance or edit contract: '..changed)
    if changed=='preloaded'then assert(PJCK_CraftActionPanel.onHandcraftActionComplete==native,'early callback was rewritten')end
end
do
    local compat=setup();local class=PJCK_CraftActionPanel
    local panel,counts=batch(class)
    class.onHandcraftActionCancelled=function()error('changed helper executed')end
    class.onHandcraftActionStart(panel,{});class.onHandcraftActionComplete(panel)
    local starts,stops=counts()
    assert(starts==1 and stops==0,'changed class retained the extra cleanup callback')
end
do
    setup();local class=PJCK_CraftActionPanel
    local panel,counts=batch(class)
    panel.onHandcraftActionStart=function()error('foreign instance callback executed')end
    class.onHandcraftActionComplete(panel)
    local _,stops=counts();assert(stops==0,'foreign instance acquired the extra cleanup callback')
    panel,counts=batch(class)
    local failure={}
    panel.HandCraftPanel.updateContainers=function()error(failure,0)end
    local ok,reason=pcall(class.onHandcraftActionComplete,panel)
    _,stops=counts()
    assert(not ok and rawequal(reason,failure)and stops==0,'balance wrapper changed native error/callback ordering')
end
print('PASS current Project Cook balance: actual native imbalance, source-verified repair, original completion, disabled/changed/early guards; evolved-recipe edits remain unsupported')
if TestCoverage then TestCoverage('source-contract','passed')end
