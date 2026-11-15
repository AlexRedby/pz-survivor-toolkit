-- Observe upstream VRO; its menu callback and native timed action own all effects.
local R = {}
local JSON = require 'QueueHealthEvents'
local function item(player, id) return player:getInventory():getItemById(id) end
local function uses(value)
    assert(value and value.getCurrentUses, 'repair torch does not expose native uses')
    if value.getDrainableUsesInt then return value:getDrainableUsesInt() end
    return value:getCurrentUses()
end
function R.resolve(ids)
    -- SP vehicles need not be registered in the multiplayer ID lookup.
    local resolved=ids.vehicle or getVehicleById(ids.vehicleID)
    assert(resolved, 'repair fixture vehicle is unavailable')
    assert(resolved:getId()==ids.vehicleID, 'repair fixture vehicle ID was rebound')
    return resolved
end
function R.observe(player, ids)
    local part = assert(R.resolve(ids):getPartById('EngineDoor'), 'repair hood is unavailable')
    local installed = assert(part:getInventoryItem(), 'repair hood lost its installed item')
    local torch, mask = item(player, ids.torchID), item(player, ids.maskID)
    local row = {vehicleID=ids.vehicleID, vehicleKey=ids.vehicleKey, partID=part:getId(), itemID=installed:getID(),
        itemType=installed:getFullType(), condition=part:getCondition(), itemCondition=installed:getCondition(),
        itemMax=installed:getConditionMax(), hbr=installed:getHaveBeenRepaired(), metal={},
        torch={id=ids.torchID, present=torch~=nil}, mask={id=ids.maskID, present=mask~=nil}, xp={}, levels={}}
    if torch then row.torch.fullType=torch:getFullType(); row.torch.uses=uses(torch) end
    if mask then row.mask.fullType=mask:getFullType(); row.mask.condition=mask:getCondition() end
    for _, id in ipairs(ids.metalIDs) do
        local owned = item(player, id)
        row.metal[#row.metal+1] = {id=id, present=owned~=nil, fullType=owned and owned:getFullType() or nil}
    end
    for _, name in ipairs({'Mechanics', 'MetalWelding'}) do
        row.xp[name]=player:getXp():getXP(Perks[name]); row.levels[name]=player:getPerkLevel(Perks[name])
    end
    return row
end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for key,value in pairs(a) do if not same(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
local function check(before, after, mode)
    if not (before.vehicleID==after.vehicleID and before.vehicleKey==after.vehicleKey
        and before.partID=='EngineDoor' and after.partID==before.partID
        and before.itemID==after.itemID and before.itemType==after.itemType and before.itemMax==after.itemMax)
        then return false,'repair identity differs' end
    if mode=='cancel' then return same(before,after),'cancelled repair changed target, resources or XP' end
    if not (before.condition==40 and before.itemCondition==40 and before.hbr==0 and before.itemMax==100
        and after.condition==76 and after.itemCondition==76 and after.hbr==1)
        then return false,'repair condition or history differs' end
    if #before.metal~=2 or #after.metal~=2 then return false,'repair material ownership set differs' end
    for i,owned in ipairs(before.metal) do
        if not (owned.present and owned.fullType=='Base.SheetMetal' and after.metal[i].id==owned.id
            and after.metal[i].present==false) then return false,'repair did not consume the owned sheet metal' end
    end
    if not (before.torch.present and after.torch.present and before.torch.id==after.torch.id
        and before.torch.fullType=='Base.BlowTorch' and after.torch.fullType==before.torch.fullType
        and before.torch.uses-after.torch.uses==3) then return false,'repair torch identity or fuel consumption differs' end
    if not same(before.mask,after.mask) then return false,'repair changed the kept welding mask' end
    for _,name in ipairs({'Mechanics','MetalWelding'}) do
        if not (before.levels[name]==4 and after.levels[name]==4 and after.xp[name]>before.xp[name]) then
            return false,'repair skill setup or native XP award differs: '..name
        end
    end
    return true
end
function R.validate(before, after, mode)
    assert(mode=='cancel' or mode=='complete', 'unknown repair mode')
    local ok,reason=check(before,after,mode)
    assert(ok,reason)
    return true
end
local function queue(player) return ISTimedActionQueue.getTimedActionQueue(player) end
local function findLeaf(context, part, found)
    for _,option in ipairs(context.options or {}) do
        if option.param1==part and type(option.param2)=='table' and option.param2.name=='Fix Hood Welding'
            and type(option.param3)=='table' and option.param3.item=='Base.SheetMetal' and option.param4==1 then
            assert(not found, 'duplicate native VRO hood welding menu leaf'); found=option
        end
        if option.subOption then
            local sub=context:getSubMenu(option.subOption)
            if sub then found=findLeaf(sub,part,found) end
        end
    end
    return found
end
local function visible(ui) return ui and ui:getIsVisible() end
local function ownsMenu(context,state)
    for _,option in ipairs(context.options or {}) do
        if option==state.option and option.param1==state.part and option.param2==state.fixing then return true end
        local sub=option.subOption and context:getSubMenu(option.subOption)
        if sub and ownsMenu(sub,state) then return true end
    end
    return false
end
function R.close(state)
    if not state or state.closed then return end
    if state.window then
        -- Context roots are shared by the player. Do not hide a later menu
        -- which another producer has opened on the same root.
        if state.window.context and ownsMenu(state.window.context,state) then
            state.window.context:hideAndChildren()
        end
        state.window:close()
    end
    state.closed=true
end
function R.start(player, ids, mode)
    assert(mode=='cancel' or mode=='complete', 'unknown repair mode')
    require 'Vehicles/ISUI/ISVehicleMechanics'
    require 'zzz_VRO_Fixing'
    assert(not VRO.IsDiminishingRepairsDisabled() and not VRO.UseVanillaFixingRecipes(),
        'repair qualification needs native VRO recipes and diminishing repair history')
    local q=queue(player)
    assert(not q.current and #q.queue==0, 'repair producer requires an idle native queue')
    local number=player:getPlayerNum()
    assert(not visible(getPlayerContextMenu(number)), 'refusing to replace an unowned visible context menu')
    assert(not visible(getPlayerMechanicsUI(number)), 'refusing to replace an unowned visible mechanics window')
    local stack=UIManager.getUI()
    for i=0,stack:size()-1 do
        local element=stack:get(i)
        local panel=element and element.getTable and element:getTable()
        assert(not (type(panel)=='table' and getmetatable(panel)==ISVehicleMechanics and visible(panel)),
            'refusing to overlap an unowned mechanics window')
    end
    local state={player=player,ids=ids,vehicle=R.resolve(ids),mode=mode,before=R.observe(player,ids),since=getTimestampMs()}
    local before=state.before
    assert(before.condition==40 and before.itemCondition==40 and before.hbr==0 and before.itemMax==100
        and before.levels.Mechanics==4 and before.levels.MetalWelding==4 and before.mask.present
        and before.torch.present and before.torch.fullType=='Base.BlowTorch' and before.torch.uses>=3
        and #before.metal==2 and before.metal[1].id~=before.metal[2].id
        and before.metal[1].present and before.metal[2].present
        and before.metal[1].fullType=='Base.SheetMetal' and before.metal[2].fullType=='Base.SheetMetal',
        'repair fixture baseline is not ready')
    local ok,err=pcall(function()
        local part=assert(state.vehicle:getPartById('EngineDoor'))
        state.part=part
        local window=ISVehicleMechanics:new(30,30,player,state.vehicle); state.window=window
        window:initialise(); window:addToUIManager(); window:setVisible(true)
        window:doPartContextMenu(part,100,100)
        local option=assert(findLeaf(assert(window.context),part), 'native VRO hood repair menu leaf missing')
        state.option=option
        assert(not option.notAvailable and option.onSelect and option.target==player,
            'native VRO hood repair menu leaf is disabled')
        local fixing,fixer=option.param2,option.param3
        state.fixing=fixing; state.fixer=fixer
        assert(fixing.time==280 and fixing.conditionModifier==1 and fixer.uses==2
            and fixer.skills.Mechanics==3 and fixer.skills.MetalWelding==3
            and fixing.globalItem.item=='Base.BlowTorch' and fixing.globalItem.uses==3,
            'installed VRO repair recipe drifted from qualified expectations')
        state.recipeDuration=fixing.time
        option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,
            option.param6,option.param7,option.param8,option.param9,option.param10)
        state.menuCallback=true
        state.sawQueued=q.current~=nil or #q.queue>0
        window.context:hideAndChildren()
    end)
    if not ok then R.close(state); error(err) end
    return state
end
local function actionObservation(state,q)
    local current=q.current
    local types={}
    for _,entry in ipairs(q.queue) do types[#types+1]=entry.Type or 'unknown' end
    local row={family='repair',mode=state.mode,elapsedMs=getTimestampMs()-state.since,
        currentType=current and current.Type or 'none',queueTypes=types,
        nativeActions=state.player:getCharacterActions():size(),
        started=state.started==true,cancelled=state.cancelled==true,
        turning=state.player:shouldBeTurning(),hasPath=state.player:hasPath(),partArea=state.part:getArea(),
        pressedMovement=state.player:pressedMovement(false),pressedCancel=state.player:pressedCancelAction(),
        actor={x=state.player:getX(),y=state.player:getY(),z=state.player:getZ()},
        vehicle={x=state.vehicle:getX(),y=state.vehicle:getY(),z=state.vehicle:getZ()}}
    local square=state.part:getSquare()
    if square then row.partSquare={x=square:getX(),y=square:getY(),z=square:getZ()} end
    if current and current.action then
        row.currentStarted=current:isStarted()==true
        row.currentProgress=current:getJobDelta()
    end
    if current and current.Type=='ISPathFindAction' and current.goal and current.goal[1]=='VehicleArea' then
        row.pathVehicleMatches=current.goal[2]==state.vehicle
        if row.pathVehicleMatches and type(current.goal[3])=='string' then
            local area=current.goal[3]
            local center=state.vehicle:getAreaCenter(area)
            local path=state.player:getPathFindBehavior2()
            row.path={area=area,areaCenterPresent=center~=nil,
                target={x=path:getTargetX(),y=path:getTargetY(),z=path:getTargetZ()}}
            if center then row.path.areaCenter={x=center:getX(),y=center:getY()} end
            local target=row.path.target
            local targetSquare=getCell():getGridSquare(math.floor(target.x),math.floor(target.y),math.floor(target.z))
            row.path.targetSquare={loaded=targetSquare~=nil}
            if targetSquare then
                local properties=row.path.targetSquare
                properties.free=targetSquare:isFree(false);properties.solidFloor=targetSquare:TreatAsSolidFloor()
                properties.solid=targetSquare:isSolid();properties.solidTrans=targetSquare:isSolidTrans()
            end
        end
    end
    state.observation=row
    -- Progress and positions stay in the payload; stage changes and the periodic
    -- sample avoid logging every moving frame of an ordinary native action.
    local signature=table.concat({row.currentType,table.concat(types,','),tostring(row.nativeActions),
        tostring(row.started),tostring(row.cancelled),tostring(row.currentStarted),
        tostring(row.turning),tostring(row.hasPath),tostring(row.pressedMovement),tostring(row.pressedCancel)},'|')
    local now=getTimestampMs()
    if state.waitSignature~=signature or not state.waitLoggedAt or now-state.waitLoggedAt>=5000 then
        print('[VRO_GAMEPLAY] ACTION_WAIT '..JSON.encode(row))
        state.waitSignature=signature;state.waitLoggedAt=now
    end
    return row
end
function R.poll(state)
    if state.receipt then return state.receipt end
    assert(not state.closed, 'repair observer was closed before settlement')
    assert(R.resolve(state.ids)==state.vehicle, 'repair fixture vehicle reference was replaced')
    local q=queue(state.player)
    local observed=actionObservation(state,q)
    if observed.elapsedMs>=120000 then
        error('native repair did not settle: '..(state.lastError or 'ordinary native progress or queue settlement missing')
            ..'; observed='..JSON.encode(observed))
    end
    local idle=not q.current and #q.queue==0 and observed.nativeActions==0
    if not idle then state.sawQueued=true end
    if idle and state.sawQueued and not state.started then
        error('native repair queue drained before ordinary progress was observed; observed='..JSON.encode(observed))
    end
    local action=q.current
    if action and action.Type=='VRO_DoFixAction' then
        assert(action.part==state.part and action.part==state.vehicle:getPartById('EngineDoor') and action.fixing==state.fixing
            and action.fixer==state.fixer and action.fixerIndex==1 and action.character==state.player,
            'native repair queue action differs from selected menu leaf')
        assert(not state.action or state.action==action, 'native repair action was replaced')
        state.action=action
        if action.action and action:isStarted() and action:getJobDelta()>0 then
            state.started=true; state.nativeDuration=action:getDuration()
            assert(state.nativeDuration>1 and state.nativeDuration>=state.recipeDuration,
                'repair duration was shortened below the normal native recipe')
            if state.mode=='cancel' and not state.cancelled then
                assert(action:getJobDelta()<0.25, 'repair cancel arrived after its early active window')
                state.cancelled=true; action:forceStop()
            end
        end
    end
    if not state.started or not idle then state.quietSince=nil; return end
    state.quietSince=state.quietSince or getTimestampMs()
    if getTimestampMs()-state.quietSince<250 then return end
    local after=R.observe(state.player,state.ids)
    local ok,err=check(state.before,after,state.mode)
    if not ok then
        state.lastError=err
        if state.mode=='cancel' then error(err) end
        return
    end
    state.receipt={mode=state.mode,vehicleID=state.ids.vehicleID,vehicleKey=state.ids.vehicleKey,before=state.before,after=after,
        started=true,nativeDuration=state.nativeDuration,recipeDuration=state.recipeDuration,
        cancelled=state.cancelled==true,menuCallback=state.menuCallback}
    return state.receipt
end
return R
