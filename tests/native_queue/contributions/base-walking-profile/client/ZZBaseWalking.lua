-- Observe the imported character and world without changing inventory or geometry.
require 'TimedActions/WalkToTimedAction'
require 'TimedActions/ISTimedActionQueue'
local selection = require 'QueueTestSelection'
local warmupMs = (selection.options.base_walking.warmup_seconds or 90)*1000
assert(warmupMs>=20000 and warmupMs<=180000,'Warmup must be 20..180 seconds')
local state, started, done = 'waiting', false, false
local since, phase, active, player, origin, destination, action, goal, legStart
local legs, rows, phaseRows = 0, {}, {}
local lastX, lastY, lastZ, lastTick
local profilerActive = false
local newMusicRequested, newMusicProof = nil, nil
local highlightBridge = selection.options.base_walking.ground_highlight_bridge
local highlightDistance, highlightMatches, highlightDistanceCalls, highlightMatchesCalls
Events.OnServerCommand.Add(function(module, command, args)
    if module == 'BaseWalkingProfile' and command == 'newmusic-proof' then newMusicProof = args end
end)
local warmupWalking, warmupSettledAt = false, nil
local function now() return getTimestampMs() end
local function json(v)
    if type(v)=='table' then
        local keys, parts = {}, {}
        for k in pairs(v) do keys[#keys+1]=k end
        table.sort(keys)
        for _,k in ipairs(keys) do parts[#parts+1]=string.format('%q',tostring(k))..':'..json(v[k]) end
        return '{'..table.concat(parts,',')..'}'
    elseif type(v)=='string' then return string.format('%q',v)
    elseif type(v)=='number' then return tostring(v)
    elseif type(v)=='boolean' then return v and 'true' or 'false' end
    return 'null'
end
local function log(kind,data) print('[BASE_WALK] '..kind..' '..json(data)) end
local function pos() return {x=player:getX(),y=player:getY(),z=player:getZ()} end
local function idle()
    return #ISTimedActionQueue.getTimedActionQueue(player).queue==0 and not player:hasTimedActions()
end
local function flush()
    -- B42 permits txt/json/log/ini/cfg, but rejects a jsonl extension.
    local writer=assert(getFileWriter('base-walking-motion.jsonl.txt',true,false))
    for _,row in ipairs(rows) do writer:write(json(row)..'\n') end
    writer:close()
end
local function fail(problem)
    if done then return end
    done=true
    if profilerActive then pcall(baseWalkingProfileFinish);profilerActive=false end
    pcall(flush)
    log('FAIL',{stage=state,error=tostring(problem),legs=legs,position=player and pos() or nil})
end
-- Find a real walkable route within five tiles of the saved base position.
-- Native timed actions still perform and validate all measured movement.
local function chooseDestination()
    local queue, seen = {{square=origin,depth=0}}, {}
    local index,best,bestScore=1,nil,-1
    seen[origin:getX()..':'..origin:getY()]=true
    while index<=#queue do
        local node=queue[index];index=index+1
        local sq=node.square
        local manhattan=math.abs(sq:getX()-origin:getX())+math.abs(sq:getY()-origin:getY())
        if manhattan>=3 and manhattan<=5 then
            -- Prefer the west side where this save's dense storage is situated.
            local score=manhattan*10+(origin:getX()-sq:getX())
            if score>bestScore then best,bestScore=sq,score end
        end
        if node.depth<7 then
            for _,d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                local x,y=sq:getX()+d[1],sq:getY()+d[2]
                local key=x..':'..y
                if not seen[key] and math.abs(x-origin:getX())<=5 and math.abs(y-origin:getY())<=5 then
                    local nextSquare=getCell():getGridSquare(x,y,origin:getZ())
                    if nextSquare and nextSquare:TreatAsSolidFloor() and nextSquare:isFree(false)
                            and not sq:isBlockedTo(nextSquare) then
                        seen[key]=true
                        queue[#queue+1]={square=nextSquare,depth=node.depth+1}
                    end
                end
            end
        end
    end
    return assert(best,'No walkable route within five tiles of imported player')
end
local function beginPhase(number)
    phase=number
    assert(baseWalkingProfilePhase(number),'Profiler rejected phase')
    active={phase=number,name=({'stationary','walking','post-stationary'})[number],
        elapsedMs=0,samples=0,distance=0,tileChanges=0,movementTicks=0,maxTickMs=0}
    since=now();lastTick=since
    lastX,lastY,lastZ=player:getX(),player:getY(),player:getZ()
end
local function finishPhase()
    if highlightBridge then
        local expectedDistance=highlightBridge=='native' and highlightDistance or nil
        local expectedMatches=highlightBridge=='native' and highlightMatches or nil
        assert(toolkitGroundHighlightDistance==expectedDistance and toolkitGroundHighlightMatches==expectedMatches,
            'Ground highlight bridge mode changed during measurement')
        local count=PZSurvivorToolkit.Highlighter.getStatus().highlightedObjects
        assert(count>0,'Ground highlight workload disappeared during measurement')
        log('HIGHLIGHT_BRIDGE_PHASE',{phase=phase,mode=highlightBridge,highlightedObjects=count,unchanged=true})
    end
    active.elapsedMs=now()-since
    assert(active.samples>0,'No movement samples')
    if phase==2 then
        assert(active.tileChanges>=12 and active.distance>=15 and legs>=4,'Insufficient native traversal')
    else assert(active.distance<1,'Stationary phase moved unexpectedly') end
    phaseRows[#phaseRows+1]=active
    log('PHASE',active)
end
local function walk()
    goal=(legs%2==0) and destination or origin
    legStart=pos()
    action=ISWalkToTimedAction:new(player,goal)
    assert(action.Type=='ISWalkToTimedAction','Native walk producer required')
    ISTimedActionQueue.add(action)
end
local function sample(time)
    local x,y,z=player:getX(),player:getY(),player:getZ()
    local d=math.sqrt((x-lastX)^2+(y-lastY)^2)
    assert(d<1.5 and z==lastZ,'Unexpected position jump during measurement')
    local changed=math.floor(x)~=math.floor(lastX) or math.floor(y)~=math.floor(lastY)
    local moving=player:isPlayerMoving()
    active.samples=active.samples+1;active.distance=active.distance+d
    active.tileChanges=active.tileChanges+(changed and 1 or 0)
    active.movementTicks=active.movementTicks+(moving and 1 or 0)
    active.maxTickMs=math.max(active.maxTickMs,time-lastTick)
    rows[#rows+1]={t=time,frame=baseWalkingProfileFrameId and baseWalkingProfileFrameId() or -1,
        phase=phase,x=x,y=y,z=z,moving=moving,tileChanged=changed,dt=time-lastTick}
    lastX,lastY,lastZ,lastTick=x,y,z,time
end
Events.OnGameStart.Add(function() started=true end)
Events.OnTick.Add(function()
    if done or not started or not isIngameState() then return end
    local ok,problem=pcall(function()
        local time=now()
        if state=='waiting' then
            player=getPlayer()
            if not player or not player:getSquare() or not isClient() or player:getOnlineID()<0 then return end
            assert(not player:isDead(),'Imported character is dead')
            local expected=selection.options.base_walking.expected_position
            assert(math.abs(player:getX()-expected[1])<1 and math.abs(player:getY()-expected[2])<1
                and player:getZ()==expected[3],'Imported character identity or position mismatch')
            assert(idle(),'Imported character unexpectedly has queued actions')
            if selection.options.base_walking.verify_toolkit_newmusic_control then
                local compat=assert(PZSurvivorToolkit.NewMusicCompatibility,'Toolkit NewMusic compatibility missing')
                assert(compat.sharedInstalled and compat.clientInstalled,'Toolkit NewMusic install incomplete')
                assert(NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled==compat.disabled
                    and NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled()==false,'Client conversion enabled')
                local probe=assert(NMClientVanillaDiscVisibleProbe)
                assert(probe.onTick==compat.noop and probe.onRefreshInventoryWindowContainers==compat.noop
                    and probe.scanVisibleLoot==compat.noop,'Client scan entrypoint remains enabled')
                if not newMusicRequested then
                    newMusicRequested=time
                    sendClientCommand('BaseWalkingProfile','newmusic-proof',{})
                end
                assert(time-newMusicRequested<20000,'Server NewMusic proof timeout')
                if not newMusicProof then return end
                assert(newMusicProof.serverDisabled==true,newMusicProof.error or 'Server conversion enabled')
                assert(newMusicProof.savedSettingEnabled==true,'Saved conversion=true was not exercised')
                log('TOOLKIT_NEWMUSIC',{clientDisabled=true,serverDisabled=true,savedSettingEnabled=true})
            end
            if highlightBridge then
                assert(PZSurvivorToolkit.Settings.isEnabled(),'Ground highlight comparison requires normal highlight enabled')
                highlightDistance=assert(toolkitGroundHighlightDistance,'Native distance helper missing')
                highlightMatches=assert(toolkitGroundHighlightMatches,'Native ownership helper missing')
                assert(highlightDistance(nil,getCell(),player:getPlayerNum(),0,0,0,15)==-1,
                    'Native highlight helpers do not support this game')
                highlightDistanceCalls,highlightMatchesCalls=0,0
                if highlightBridge=='lua' then
                    toolkitGroundHighlightDistance,toolkitGroundHighlightMatches=nil,nil
                else
                    -- Prove real use during warmup, then remove observer wrappers before timing.
                    toolkitGroundHighlightDistance=function(...)
                        highlightDistanceCalls=highlightDistanceCalls+1;return highlightDistance(...)
                    end
                    toolkitGroundHighlightMatches=function(...)
                        highlightMatchesCalls=highlightMatchesCalls+1;return highlightMatches(...)
                    end
                end
            end
            origin=player:getSquare();destination=chooseDestination()
            local own,loot=getPlayerInventory(player:getPlayerNum()),getPlayerLoot(player:getPlayerNum())
            assert(own and loot,'Inventory pages missing')
            own:setVisible(false);loot:setVisible(false)
            local containers=require 'BetterContainers/_Options'
            local probeRemoved=selection.options.base_walking.disable_newmusic_inventory_probe==true
            if probeRemoved then
                local callback=assert(NMClientVanillaDiscVisibleProbe and NMClientVanillaDiscVisibleProbe.onRefreshInventoryWindowContainers)
                local proof=require 'PZSurvivorToolkit/SourceProof'
                assert(proof.closure(callback,'NMClientVanillaDiscVisibleProbe.lua'),'Unexpected NewMusic probe callback')
                Events.OnRefreshInventoryWindowContainers.Remove(callback)
            end
            log('READY',{position=pos(),inventoryItems=player:getInventory():getItems():size(),
                inventoryWeight=player:getInventory():getCapacityWeight(),ownVisible=own:getIsVisible(),
                lootVisible=loot:getIsVisible(),origin={x=origin:getX(),y=origin:getY(),z=origin:getZ()},
                destination={x=destination:getX(),y=destination:getY(),z=destination:getZ()},
                nestedLoot=containers.enableNestedContainers_Loot,nestedPlayer=containers.enableNestedContainers_Player,
                proximity=containers.enableProximity,proximityNested=containers.proximityIncludeNestedContainers,
                newMusicInventoryProbeRemoved=probeRemoved,
                teleport=false,inventoryChanged=false,worldChanged=false})
            since=time;state='warmup'
        elseif state=='warmup' then
            -- Exercise the same native route before the stationary baseline so
            -- first movement/JIT work does not masquerade as steady step cost.
            if warmupMs>=60000 and not warmupSettledAt then
                if not warmupWalking and time-since>=20000 then
                    warmupWalking=true;walk()
                elseif warmupWalking and idle() then
                    assert(action.result==BehaviorResult.Succeeded,'Warmup native walk failed')
                    assert(math.floor(player:getX())==goal:getX() and math.floor(player:getY())==goal:getY(),'Warmup destination missed')
                    legs=legs+1
                    if time-since>=warmupMs-30000 and legs%2==0 then
                        log('WARMUP',{elapsedMs=time-since,legs=legs,position=pos()})
                        legs=0;warmupSettledAt=time
                    else walk() end
                end
                assert(time-since<warmupMs+40000,'Warmup native walking deadline exceeded')
                return
            end
            if time-since<warmupMs or warmupSettledAt and time-warmupSettledAt<20000 then return end
            if highlightBridge then
                if highlightBridge=='native' then
                    assert(highlightDistanceCalls>0 and highlightMatchesCalls>0,'Native highlight helpers were not exercised')
                    toolkitGroundHighlightDistance,toolkitGroundHighlightMatches=highlightDistance,highlightMatches
                end
                log('HIGHLIGHT_BRIDGE',{mode=highlightBridge,distanceCalls=highlightDistanceCalls,
                    matchesCalls=highlightMatchesCalls,highlightedObjects=PZSurvivorToolkit.Highlighter.getStatus().highlightedObjects})
            end
            assert(idle(),'Warmup actions remain at profile begin')
            assert(baseWalkingProfileBegin(),'Profiler did not begin')
            profilerActive=true;beginPhase(1);state='stationary'
        else
            assert(not player:isDead(),'Character died during traversal')
            sample(time)
            if state=='stationary' and time-since>=22000 then
                finishPhase();beginPhase(2);state='walking';walk()
            elseif state=='walking' then
                assert(time-since<100000,'Walking phase exceeded deadline')
                assert(action.result~=BehaviorResult.Failed,'Native walk path failed')
                if idle() then
                    assert(action.result==BehaviorResult.Succeeded,'Walk ended without native success')
                    assert(math.floor(player:getX())==goal:getX() and math.floor(player:getY())==goal:getY(),'Destination not reached')
                    legs=legs+1
                    local finish=pos()
                    log('MOVEMENT',{leg=legs,action=action.Type,reached=true,start=legStart,finish=finish,
                        distance=math.sqrt((finish.x-legStart.x)^2+(finish.y-legStart.y)^2)})
                    if time-since>=60000 and legs%2==0 then
                        finishPhase();beginPhase(3);state='post-stationary'
                    else walk() end
                end
            elseif state=='post-stationary' and time-since>=22000 then
                finishPhase()
                local path=baseWalkingProfileFinish();profilerActive=false
                flush();done=true
                log('COMPLETE',{case='walk',profile=path,phases=3,legs=legs})
            end
        end
    end)
    if not ok then fail(problem) end
end)
