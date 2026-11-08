-- Bounded SP diagnostic: actual refresh callbacks, native items, no bypassed work.
local Profile = require 'InventorySelectionProfile'
local Config = require 'InventorySelectionConfig'
local Usage = require 'PZSurvivorToolkit/ItemUsageTags'
local cohorts={['Base.Nails']={branch='nonfluid',fluidType='none',usage={fuel=false,disinfectant=false}},
    ['Base.PetrolCan']={branch='fluid',fluidType='Petrol',usage={fuel=true,disinfectant=false,beverage=false,alcoholic=false,empty=false}},
    ['Base.Whiskey']={branch='fluid',fluidType='Whiskey',usage={fuel=false,disinfectant=true,beverage=true,alcoholic=true,empty=false}}}
local cohort=assert(type(Config)=='table' and cohorts[Config.itemType],'unsupported selection item cohort')
local fluidAmount,fluidCapacity,setupLogged=0,0,false
local entered, starting, ready, done = false, false, false, false
local player, inventory, pane, initial, originalMode, owned, ids = nil, nil, nil, nil, nil, {}, {}
local initialCount=0
local ownedSet={}
local stage, phase, began, nextAt, samples = 'setup', 1, 0, 0, {}
local cells = {}
for _,mode in ipairs({'clean','vanilla'}) do
    for _,expanded in ipairs({false,true}) do cells[#cells+1]={mode=mode,expanded=expanded} end
end
local function json(value)
    if type(value)=='table' then
        local parts, keys, n = {}, {}, #value
        local array=n>0
        for k in pairs(value) do keys[#keys+1]=k;if type(k)~='number' or k<1 or k>n or k%1~=0 then array=false end end
        if array then for i=1,n do parts[#parts+1]=json(value[i]) end;return '['..table.concat(parts,',')..']' end
        table.sort(keys)
        for _,k in ipairs(keys) do parts[#parts+1]=string.format('%q',k)..':'..json(value[k]) end
        return '{'..table.concat(parts,',')..'}'
    elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge);return tostring(value)
    elseif type(value)=='boolean' then return value and 'true' or 'false'
    elseif type(value)=='string' then return string.format('%q',value) end
    return 'null'
end
local function log(kind,row) print('[STORAGE_PROFILE] SELECTION_'..kind..' '..json(row)) end
local function identity()
    local result={};local list=inventory:getItems()
    for i=0,list:size()-1 do local item=list:get(i);result[item]=item:getID() end
    return result
end
local function verify()
    for item,id in pairs(initial) do assert(item:getContainer()==inventory and item:getID()==id,'original inventory changed') end
    for _,item in ipairs(owned) do
        assert(item:getContainer()==inventory and ids[item:getID()]==item,'probe item identity changed')
        assert(item:getFullType()==Config.itemType and item:IsDrainable()==false,'probe type or drainability changed')
        local container=item:getFluidContainer()
        if cohort.branch=='fluid' then
            assert(container and not container:isEmpty(),'probe fluid component absent or empty')
            assert(container:getCapacity()==fluidCapacity and container:getAmount()==fluidAmount
                and container:getSpecificFluidAmount(Fluid[cohort.fluidType])==fluidAmount,
                'probe fluid quantity or contents changed')
        else assert(container==nil,'nonfluid probe gained fluid component') end
    end
    assert(#owned==4800,'probe cohort incomplete')
    assert(inventory:getItems():size()==#owned+initialCount,'probe population changed')
    local usage,_,isFluid=Usage.read(nil,owned[1])
    assert(isFluid==(cohort.branch=='fluid'),'public usage branch differs')
    local witness={}
    for name,value in pairs(cohort.usage) do
        assert(usage[name]==value,'public usage role differs: '..name);witness[name]=usage[name]
    end
    return {itemType=Config.itemType,branch=cohort.branch,isFluid=isFluid,isDrainable=false,
        fluidType=cohort.fluidType,fluidAmount=fluidAmount,fluidCapacity=fluidCapacity,
        fillPolicy=cohort.branch=='fluid' and 'setup-full-capacity' or 'native-nonfluid',
        verifiedItems=#owned,stateVerified=true,usageWitness=witness}
end
local function cleanup()
    if not inventory then return end
    local valid,before=true,nil
    if #owned==4800 then valid,before=pcall(verify) end
    for _,item in ipairs(owned) do if item:getContainer()==inventory then inventory:Remove(item) end end
    for _,item in ipairs(owned) do assert(item:getContainer()~=inventory,'probe item survived cleanup') end
    if initial then
        for item,id in pairs(initial) do assert(item:getContainer()==inventory and item:getID()==id,'original inventory lost at cleanup') end
        assert(inventory:getItems():size()==initialCount,'cleanup population differs')
    end
    if originalMode~=nil then CleanUI_setCleanInventoryUIEnabled(originalMode) end
    assert(valid,before)
    return before
end
local function setup()
    assert(not isClient() and not isServer(),'one SP client required')
    assert(inventoryWorkProbeInit(),'owned monotonic clock unavailable')
    player=getPlayer();inventory=player:getInventory();originalMode=CleanUI_isCleanInventoryUIEnabled()
    initial=identity();local count=0
    for item,id in pairs(initial) do count=count+1;ids[id]=item end
    initialCount=count
    player:setGodMod(true);player:setGhostMode(true)
    if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
end
local function add()
    for attempt=1,32 do
        local item=assert(instanceItem(Config.itemType))
        assert(item:getFullType()==Config.itemType and item:IsDrainable()==false,'factory type or drainability differs')
        local container=item:getFluidContainer()
        if cohort.branch=='fluid' then
            assert(container and Fluid[cohort.fluidType],'native fluid component or identity missing')
            local capacity=container:getCapacity()
            assert(capacity>0.15,'probe fluid capacity cannot exercise expected usage')
            -- Native initial quantities may vary. Normalize only during setup;
            -- the reader and timed callbacks never fill or mutate these items.
            container:Empty();container:addFluid(Fluid[cohort.fluidType],capacity)
            assert(container:getAmount()==capacity and not container:isEmpty()
                and container:getSpecificFluidAmount(Fluid[cohort.fluidType])==capacity,'native fluid fill differs')
            if #owned==0 then fluidAmount,fluidCapacity=capacity,capacity end
            assert(capacity==fluidCapacity,'cohort fluid capacities differ')
        else assert(container==nil,'nonfluid factory item has fluid component') end
        local id=item:getID()
        if not ids[id] then
            ids[id]=item;owned[#owned+1]=item
            ownedSet[item]=true
            assert(inventory:AddItem(item)==item,'native object insertion differed')
            return
        end
    end
    error('unique probe item allocation exhausted')
end
local function configure()
    if not setupLogged then
        local evidence=verify();evidence.count=4800;evidence.clock='System.nanoTime'
        evidence.sampleWindow='synchronous actual refresh';evidence.physicalInput=false;evidence.fpsMeasurement=false
        log('SETUP',evidence);setupLogged=true
    end
    local cell=cells[phase]
    CleanUI_setCleanInventoryUIEnabled(cell.mode=='clean')
    local page=getPlayerInventory(0);page:setVisible(true);pane=page.inventoryPane
    pane:setVisible(true);pane:setMode('details');table.wipe(pane.selected)
    pane:refreshContainer()
    local found=0
    for _,row in ipairs(pane.itemslist) do
        if row.items then
            local target=false
            for i=row.cleanUIFirstActualIndex or 2,#row.items do if row.items[i]==owned[1] then target=true end end
            if target then found=found+1;pane.collapsed[row.name]=not cell.expanded end
        end
    end
    assert(found==1,'expected one native probe stack')
    samples={};nextAt=getTimestampMs()+1500;stage='measure'
end
local function witness(cell)
    local expected=cell.mode=='clean' and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
    assert(pane==getPlayerInventory(0).inventoryPane and getmetatable(pane)==expected and ISInventoryPane==expected
        and pane.mode=='details' and CleanUI_isCleanInventoryUIEnabled()==(cell.mode=='clean'),'actual renderer/class differs')
    local count,groups=0,0
    for _,row in ipairs(pane.itemslist) do if row.items then
        local found,physical=false,0
        for i=row.cleanUIFirstActualIndex or 2,#row.items do
            local item=row.items[i];if item==owned[1] then found=true end
            if ownedSet[item] then physical=physical+1 end
        end
        if found then
            groups=groups+1
            assert((pane.collapsed[row.name]~=true)==cell.expanded,'actual collapse state differs')
            count=count+physical
        end
    end end
    assert(groups==1 and count==#owned,'actual expanded stack population differs')
    return {renderer=cell.mode,mode=pane.mode,expanded=cell.expanded,probeItems=count,groups=groups,classMatches=true}
end
local function measure()
    local cell=cells[phase]
    table.wipe(pane.selected);local state=verify();local observed=witness(cell)
    for key,value in pairs(state) do observed[key]=value end
    for key,value in pairs(pane:saveSelection({})) do
        if key=='_cleanUISelectedGroups' then for _ in pairs(value) do error('saved group selection is nonempty') end
        else error('saved item selection is nonempty') end
    end
    local name=cell.mode..(cell.expanded and '-expanded' or '-collapsed')
    local index=#samples+1
    Profile.begin(name,inventoryWorkProbeClockMs,pane)
    local start=inventoryWorkProbeClockMs()
    local ok,problem=pcall(function()pane:refreshContainer()end)
    local elapsed=inventoryWorkProbeClockMs()-start
    local receipt=Profile.finish()
    if not ok then error(problem,0) end
    verify();witness(cell);for _ in pairs(pane.selected) do error('empty selection changed') end
    receipt.mapperLabels={}
    for _,label in ipairs({'mapper.'..cell.mode,'mapper.bc'}) do
        if receipt.metrics[label] and receipt.metrics[label].calls>0 then receipt.mapperLabels[#receipt.mapperLabels+1]=label end
    end
    if #receipt.mapperLabels==0 or not receipt.metrics['presentation.refresh'] then
        log('TRACE',receipt);error('required mapper or outer refresh span did not execute')
    end
    for _,m in pairs(receipt.metrics) do assert(m.errors==0 and m.exclusiveMs>=0 and m.inclusiveMs>=m.exclusiveMs,'invalid nested spans') end
    receipt.index=index;receipt.kind=index==1 and 'first-measured-after-setup' or 'repeated'
    receipt.outerMs=elapsed;receipt.count=#owned;receipt.emptySelection=true;receipt.identityVerified=true
    for key,value in pairs(state) do receipt[key]=value end
    receipt.workload=observed
    log('SAMPLE',receipt);samples[#samples+1]=true
    if #samples==7 then phase=phase+1;stage=phase>#cells and 'finish' or 'configure' else nextAt=getTimestampMs()+250 end
end
Events.OnMainMenuEnter.Add(function()entered=true end)
require('QueuePreflight').onGameStart(Events,function()ready=true;began=getTimestampMs()end)
Events.OnPreUIDraw.Add(function()
    if ready and isIngameState() and isGamePaused() then setGameSpeed(1) end
    if not entered or starting or isIngameState() then return end
    starting=true;getCore():setOptionPauseOnFocusloss(false)
    getWorld():setGameMode('Sandbox');getWorld():setWorld('InventorySelectionProfileNative');getWorld():setMap('Muldraugh, KY')
    MainScreen.instance:setDefaultSandboxVars()
    for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2}) do getSandboxOptions():getOptionByName(name):setValue(value) end
    getSandboxOptions():toLua();MainScreen.instance.createWorld=true
    MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
    MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
    MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
require('QueuePreflight').onTick(Events,function()
    if not ready or done then return end
    local ok,problem=pcall(function()
        assert(getTimestampMs()-began<180000,'selection diagnostic deadline exceeded')
        if stage=='setup' then setup();stage='fill'
        elseif stage=='fill' then for i=1,100 do if #owned<4800 then add() end end;if #owned==4800 then stage='configure' end
        elseif stage=='configure' then configure()
        elseif stage=='measure' and getTimestampMs()>=nextAt then measure()
        elseif stage=='finish' then
            local evidence=cleanup();evidence.ownedRemoved=#owned;evidence.originals=initialCount;evidence.phases=#cells
            evidence.identityVerified=true;evidence.remaining=inventory:getItems():size()
            log('RESTORED',evidence);print('[STORAGE_PROFILE] COMPLETE');done=true
        end
    end)
    if not ok then local restored,restoreError=pcall(cleanup);log('FAIL',{error=tostring(problem),restored=restored,restoreError=tostring(restoreError)});print('[STORAGE_PROFILE] FAIL selection');done=true end
end)
