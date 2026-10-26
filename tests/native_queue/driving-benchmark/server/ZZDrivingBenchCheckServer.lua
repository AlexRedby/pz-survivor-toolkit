if not isServer() then return end
local F=require "DrivingBenchFixture"
local config=require "QueueTestSelection"
local MODULE="PZDrivingBenchTest"
local observed,completed={},false
local function describe(vehicle)
    local script=assert(vehicle:getScript(),"Missing native vehicle script")
    local extents=assert(script:getExtents(),"Missing native vehicle extents")
    assert(extents:x()>0 and extents:z()>0,"Invalid native vehicle extents")
    return "id="..vehicle:getId().." sql="..vehicle:getSqlId()
        .." position="..vehicle:getX()..","..vehicle:getY()..","..vehicle:getZ()
        .." extents="..extents:x()..","..extents:y()..","..extents:z()
        .." modelScale="..script:getModelScale()
end
local function validate(player,args)
    local v=assert(player:getVehicle(),"Driver not present on server")
    assert(v:getId()==args.id and v:getSqlId()==args.sqlId,"Wrong car identity")
    assert(v:getSeat(player)==0 and v:isDriver(player),"Player is not authoritative driver")
    assert(v:isEngineRunning(),"Server engine is stopped")
    local ignition=v:isKeysInIgnition() and v:getCurrentKey()
    assert(player:getInventory():haveThisKeyId(v:getKeyId())
        or ignition and ignition:getKeyId()==v:getKeyId(),"Server actual key missing")
    local tank=assert(v:getPartById("GasTank"))
    assert(tank:getContainerContentAmount()>tank:getContainerCapacity()*.95,"Server tank not full")
    local battery=assert(v:getPartById("Battery")):getInventoryItem()
    assert(battery and battery:getCurrentUsesFloat()>.95,"Server battery not full")
    local before=getCell():getVehicles():size()
    local repeated=F.prepare(player)
    assert(repeated.status=="ready" and repeated.reused and repeated.id==args.id
        and repeated.sqlId==args.sqlId,"Server repeat did not reuse driver car")
    assert(getCell():getVehicles():size()==before,"Server repeat created duplicate car")
    return v
end
Events.OnClientCommand.Add(function(module,command,player,args)
    if module~=MODULE or command~="validate" or not F.allowed() or config.kind~="mp" then return end
    local ok,problem=pcall(function()
        local actor=player:getUsername()
        assert(actor=="client1" or actor=="client2","Unexpected test actor")
        assert(type(args)=="table" and args.request==1 and type(args.id)=="number"
            and type(args.sqlId)=="number","Invalid validation request")
        if completed then
            local old=assert(observed[actor])
            assert(old.args.id==args.id and old.args.sqlId==args.sqlId,"Changed completed request")
            sendServerCommand(player,MODULE,"validated",old.ack)
            return
        end
        observed[actor]={player=player,vehicle=validate(player,args),args=args}
        if not observed.client1 or not observed.client2 then return end
        local a,b=observed.client1,observed.client2
        assert(a.vehicle~=b.vehicle and a.args.id~=b.args.id and a.args.sqlId~=b.args.sqlId,"Players share a car")
        local dx,dy=a.vehicle:getX()-b.vehicle:getX(),a.vehicle:getY()-b.vehicle:getY()
        local distance=math.sqrt(dx*dx+dy*dy)
        local geometry="a={"..describe(a.vehicle).."} b={"..describe(b.vehicle).."}"
        -- Loaded() has already scaled script extents. Use the same world-space
        -- rectangle predicate as IsoChunk's native vehicle placement checks.
        local collisionAB=a.vehicle:testCollisionWithVehicle(b.vehicle)
        local collisionBA=b.vehicle:testCollisionWithVehicle(a.vehicle)
        assert(collisionAB==false and collisionBA==false,"Native benchmark vehicle bodies overlap: "
            ..geometry.." collisionAB="..tostring(collisionAB).." collisionBA="..tostring(collisionBA))
        local count=0
        local vehicles=getCell():getVehicles():iterator()
        while vehicles:hasNext() do
            if vehicles:next():getModData().PZDrivingBenchFixture then count=count+1 end
        end
        assert(count==2,"Expected exactly two owned benchmark cars")
        for _,name in ipairs({"client1","client2"}) do
            local row=observed[name]
            validate(row.player,row.args)
            row.ack={ok=true,actor=name,id=row.args.id,sqlId=row.args.sqlId,request=1}
        end
        completed=true
        print("[DRIVING_BENCH_TEST] PAIR count=2 separated=true method=native-vehicle-rectangles distance="
            ..distance.." "..geometry)
        for _,name in ipairs({"client1","client2"}) do
            local row=observed[name]
            print("[DRIVING_BENCH_TEST] AUTHORITY actor="..name.." id="..row.args.id.." sql="..row.args.sqlId
                .." driver="..row.player:getOnlineID().." reused=true")
            sendServerCommand(row.player,MODULE,"validated",row.ack)
        end
    end)
    if not ok then
        print("[DRIVING_BENCH_TEST] FAIL server "..tostring(problem))
        sendServerCommand(player,MODULE,"validated",{ok=false,reason=tostring(problem)})
    end
end)
