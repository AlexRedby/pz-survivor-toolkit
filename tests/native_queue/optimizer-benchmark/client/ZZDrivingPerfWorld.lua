local config=require 'QueueTestSelection'
local entered,starting,readyAt,saved=false,false,nil,false
PZDrivingPerfSeeding=config.cases[1]=='seed'
local point,arrived,total,begun=0,nil,0,nil
local seedZoom=false
local pendingTeleport,nextTeleportAt
local perf=config.options and config.options.driving_perf or {}
local muldraugh=perf.scenario=='muldraugh-extinction'
local urban=muldraugh or perf.scenario=='west-point-extinction'
local nativePopulation=urban and perf.population_mode=='native'
local startX,startY=urban and 11050 or 10590,urban and 6902 or 11680
if muldraugh then startX,startY=10594,10650 end
local points={11660,11615,11570,11525,11480,11435,11390,11345,11300,11255}
if urban then
    points={}
    for i=0,24 do points[#points+1]=11090+40*i end
end
local function checkUrbanPreset()
    if not urban then return end
    local z=SandboxVars.ZombieConfig
    assert(z and z.PopulationMultiplier==1.2 and z.PopulationStartMultiplier==1.5
        and z.PopulationPeakMultiplier==2 and z.PopulationPeakDay==28,'Extinction population changed')
    assert(SandboxVars.ZombieRespawn==4 and SandboxVars.ZombieMigrate==true
        and z.RespawnHours==0 and z.RespawnUnseenHours==0 and z.RespawnMultiplier==0
        and z.RedistributeHours==12,'Respawn/migration settings differ')
    print('[DRIVING_PERF_WORLD] POPULATION Extinction population=1.2 start=1.5 peak=2.0 peak_day=28 lore=ordinary-default speed='..tostring(SandboxVars.ZombieLore.Speed)
        ..' cognition='..tostring(SandboxVars.ZombieLore.Cognition)..' respawn=off migration=true redistribute_hours='..z.RedistributeHours)
end
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
    if not entered or starting or isIngameState() then return end
    starting=true
    local ok,problem=pcall(function()
        getCore():setOptionPauseOnFocusloss(false)
        if config.cases[1]=='drive' then
            MainScreen.continueLatestSave('Sandbox','PZDrivingBench-Perf')
            print('[DRIVING_PERF_WORLD] RESTORED')
            return
        end
        getWorld():setGameMode('Sandbox');getWorld():setWorld('PZDrivingBench-Perf');getWorld():setMap('Muldraugh, KY')
        MainScreen.instance:setDefaultSandboxVars()
        if urban then
            local extinction=require 'Sandbox/Extinction'
            for _,name in ipairs({'PopulationMultiplier','PopulationStartMultiplier','PopulationPeakMultiplier','PopulationPeakDay'}) do
                getSandboxOptions():set('ZombieConfig.'..name,extinction.ZombieConfig[name])
            end
            getSandboxOptions():set('ZombieRespawn',4)
            getSandboxOptions():set('ZombieMigrate',true)
            for _,name in ipairs({'RespawnHours','RespawnUnseenHours','RespawnMultiplier'}) do
                getSandboxOptions():set('ZombieConfig.'..name,0)
            end
            getSandboxOptions():set('ZombieConfig.RedistributeHours',12)
            getSandboxOptions():toLua();checkUrbanPreset()
        end
        local current,active=ActiveMods.getById('currentGame'),getActivatedMods()
        current:getMods():clear()
        for i=0,active:size()-1 do current:getMods():add(active:get(i)) end
        MainScreen.instance.createWorld=true
        MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=startX,posY=startY,posZ=0}}}}
        MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
        MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
    end)
    if not ok then print('[DRIVING_PERF_WORLD] FAIL '..tostring(problem)) end
end)
Events.OnTick.Add(function()
    if not PZDrivingPerfSeeding or not isIngameState() then return end
    local player=getPlayer()
    if not player or not player:getSquare() then return end
    local now=getTimestampMs()
    if not begun then
        begun=now;player:setGodMod(true);player:setGhostMode(true);checkUrbanPreset()
        getGameTime():setTimeOfDay(12)
        if nativePopulation then
            PZDrivingPerfSeeding=false
            local record=ModData.getOrCreate('PZDrivingPerfWorld')
            record.scenario=perf.scenario;record.population_mode='native';record.seeded=0
            print('[DRIVING_PERF_WORLD] NATIVE_POPULATION scripted_zombies=0 corridor_previsited=false')
            return
        end
    end
    local ok,problem=pcall(function()
        assert(now-begun<300000,'Crowd preparation timed out')
        if not seedZoom then
            drivingPerfSetZoom(player,getCore():getMaxZoom());seedZoom=true
        end
        if not arrived then
            point=point+1
            if urban then pendingTeleport={points[point] or startX,startY}
            else pendingTeleport={points[point] and 10594 or startX,points[point] or startY} end
            arrived=now
            return
        end
        if pendingTeleport or now-arrived<2000 then return end
        local current=player:getCurrentSquare()
        local actual=getCell():getGridSquare(math.floor(player:getX()),math.floor(player:getY()),0)
        if not current or not actual then return end
        assert(current==actual and current:getX()==math.floor(player:getX())
            and current:getY()==math.floor(player:getY()),'Seed player square is stale after teleport')
        local y=points[point]
        if not y then
            assert(math.abs(player:getX()-startX)<2 and math.abs(player:getY()-startY)<2,'Did not return to start')
            player:setGhostMode(false)
            PZDrivingPerfSeeding=false
            local record=ModData.getOrCreate('PZDrivingPerfWorld')
            record.scenario=perf.scenario or 'highway';record.seeded=total
            print('[DRIVING_PERF_WORLD] CROWD_SEEDED total='..total..' ai=ordinary ghost=false godModePlayer=true scenario='..record.scenario)
            return
        end
        if urban then
            if math.abs(player:getX()-y)>2 then return end
            -- Wait for the complete candidate band, then choose only exterior walkable squares.
            for _,dx in ipairs({-16,16}) do for _,dy in ipairs({-28,28}) do
                if not getCell():getGridSquare(y+dx,startY+dy,0) then return end
            end end
            local positions={}
            for _,side in ipairs({-1,1}) do
                local count=0
                for dx=-12,12,2 do for offset=6,28,2 do
                    local x,zy=y+dx,startY+side*offset
                    local square=getCell():getGridSquare(x,zy,0)
                    if count<32 and square and square:isOutside() and square:isFree(false)
                        and square:getFloor() and not square:getVehicleContainer() then
                        positions[#positions+1]={x,zy};count=count+1
                    end
                end end
                assert(count==32,'Insufficient exterior spawn squares at station '..point..' side '..side)
            end
            for _,position in ipairs(positions) do
                local zombies=addZombiesInOutfit(position[1],position[2],0,1,nil,50)
                assert(zombies and zombies:size()==1,'Native urban zombie spawn failed')
                local zombie=zombies:get(0)
                assert(not zombie:isDead() and not zombie:isUseless() and not zombie:isFakeDead(),'Nonordinary urban zombie')
                zombie:getModData().PZDrivingPerfSeed=point;total=total+1
            end
            print('[DRIVING_PERF_WORLD] SEEDED point='..point..' x='..y..' total='..total)
            arrived=nil
            return
        end
        if math.abs(player:getY()-y)>2 then return end
        for _,side in ipairs({-1,1}) do
            for row=0,3 do for column=0,2 do
                if not getCell():getGridSquare(10592+side*(14+column*2),y-6+row*4,0) then return end
            end end
        end
        for _,side in ipairs({-1,1}) do
            for row=0,3 do for column=0,2 do
                local x,zy=10592+side*(14+column*2),y-6+row*4
                local zombies=addZombiesInOutfit(x,zy,0,1,nil,50)
                assert(zombies and zombies:size()==1,'Native spawn failed at '..x..','..zy)
                local zombie=zombies:get(0)
                assert(not zombie:isDead() and not zombie:isUseless() and not zombie:isFakeDead(),'Nonordinary spawned zombie')
                zombie:getModData().PZDrivingPerfSeed=point
                total=total+1
            end end
        end
        print('[DRIVING_PERF_WORLD] SEEDED point='..point..' y='..y..' total='..total)
        arrived=nil
    end)
    if not ok then
        PZDrivingPerfSeeding=false;saved=true
        print('[DRIVING_PERF_WORLD] FAIL '..tostring(problem))
    end
end)
Events.OnTick.Add(function()
    if saved or config.cases[1]~='seed' or not PZDrivingBenchClient or not PZDrivingBenchClient.ready then return end
    if not readyAt then
        getPlayer():setGhostMode(false)
        readyAt=getTimestampMs()
        print('[DRIVING_PERF_WORLD] DRIVER_READY ghost=false')
    end
    if getTimestampMs()-readyAt<5000 then return end
    saved=true
    local ok,problem=pcall(function()
        assert(math.abs(PZDrivingBenchClient.vehicle:getCurrentSpeedKmHour())<.5,'Seed car moved')
        if urban then assert(total==(nativePopulation and 0 or 1600) and PZDrivingBenchClient.vehicle:getScriptName()=='Base.SportsCar','Wrong urban seed');checkUrbanPreset() end
        if muldraugh then
            local choice=require("DrivingApproachLane").seal(PZDrivingApproachLaneChoice,
                PZDrivingBenchClient.vehicle,perf.approach_tiles or 40)
            ModData.getOrCreate('PZDrivingPerfWorld').approach_lane=choice
        end
        save(true)
        getCore():TakeFullScreenshot('driving-perf-seed.png')
        print('[DRIVING_PERF_WORLD] SEED_SAVED')
    end)
    if not ok then print('[DRIVING_PERF_WORLD] FAIL '..tostring(problem)) end
end)

-- Match the native debug-map teleport phase. OnTick runs after world reconciliation
-- and before ambient audio, so retaining the old square there can access a recycled chunk.
Events.OnPreUIDraw.Add(function()
    if not pendingTeleport or not PZDrivingPerfSeeding or not isIngameState() then return end
    local player=getPlayer()
    if not player then return end
    local now=getTimestampMs()
    if nextTeleportAt and now<nextTeleportAt then return end
    local target=pendingTeleport
    local x,y=math.floor(player:getX()),math.floor(player:getY())
    local dx,dy=target[1]-x,target[2]-y
    local length=math.max(math.abs(dx),math.abs(dy))
    if length>16 then
        x=x+math.floor(dx*16/length);y=y+math.floor(dy*16/length)
    else x,y=target[1],target[2] end
    -- Never clear the current square while its destination is still unloaded.
    if not getCell():getGridSquare(x,y,0) then return end
    player:teleportTo(x,y,0)
    player:setCurrentSquareFromPosition()
    nextTeleportAt=now+200
    if x==target[1] and y==target[2] then pendingTeleport=nil;arrived=now end
end)

Events.OnGameStart.Add(function()
    if urban and config.cases[1]=='drive' then
        local ok,problem=pcall(function()
            checkUrbanPreset()
            local record=ModData.getOrCreate('PZDrivingPerfWorld')
            assert(record.scenario==perf.scenario,'Wrong urban world template')
            if nativePopulation then assert(record.population_mode=='native' and record.seeded==0,
                'Native drive requires an unseeded, unvisited corridor') end
        end)
        if not ok then print('[DRIVING_PERF_WORLD] FAIL '..tostring(problem)) end
    end
end)

local lastNativeSeedStatus=0
Events.OnTick.Add(function()
    if not nativePopulation or config.cases[1]~='seed' or saved or not isIngameState() then return end
    local now=getTimestampMs()
    if now-lastNativeSeedStatus<5000 then return end
    lastNativeSeedStatus=now
    local p=getPlayer();local c=PZDrivingBenchClient
    local q=p and p:getCurrentSquare();local floor=q and q:getFloor();local sprite=floor and floor:getSprite()
    print('[DRIVING_PERF_WORLD] START_STATUS stage='..tostring(c and c.stage)..' wait='..tostring(c and c.lastWait)
        ..' dead='..tostring(p and p:isDead())..' x='..tostring(p and p:getX())..' y='..tostring(p and p:getY())
        ..' square='..tostring(q~=nil)..' floor='..tostring(sprite and sprite:getName()))
end)
