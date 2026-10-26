local config=require "QueueTestSelection"
local F=require "DrivingBenchFixture"
local MODULE="PZDrivingBenchTest"
local began, nextRequest, sampled, failed, preparedSql, acknowledged
local function fail(problem)
    if failed or sampled then return end
    failed=true
    print("[DRIVING_BENCH_TEST] FAIL "..tostring(problem))
end
local function checkedVehicle()
    local C=assert(PZDrivingBenchClient)
    local p=assert(getPlayer())
    local v=assert(p:getVehicle())
    assert(v==C.vehicle and v:getSeat(p)==0 and v:isDriver(p),"Not the benchmark driver")
    assert(v:isEngineRunning(),"Engine stopped")
    local ignition=v:isKeysInIgnition() and v:getCurrentKey()
    assert(p:getInventory():haveThisKeyId(v:getKeyId())
        or ignition and ignition:getKeyId()==v:getKeyId(),"No actual key")
    local tank=assert(v:getPartById("GasTank"))
    assert(tank:getContainerContentAmount()>tank:getContainerCapacity()*.95,"Tank not full")
    local battery=assert(v:getPartById("Battery")):getInventoryItem()
    assert(battery and battery:getCurrentUsesFloat()>.95,"Battery not charged")
    return p,v
end
local function finish(p,v,sqlId,authority)
    if sampled then return end
    local actor=isClient() and p:getUsername() or "client1"
    getCore():TakeFullScreenshot("driving-benchmark-ready.png")
    sampled=true
    print("[DRIVING_BENCH_TEST] COMPLETE driver-key-fuel-engine-idempotency actor="..actor
        .." id="..v:getId().." sql="..sqlId.." authority="..authority)
end
Events.OnServerCommand.Add(function(module, command, args)
    if module==F.MODULE and command=="ready" and type(args)=="table" then preparedSql=args.sqlId end
    if module~=MODULE or failed or sampled then return end
    local ok,problem=pcall(function()
        assert(command=="validated" and args.ok,"Server validation failed: "..tostring(args.reason))
        local p,v=checkedVehicle()
        assert(args.actor==p:getUsername() and args.id==v:getId() and args.sqlId==preparedSql
            and args.request==1,"Wrong authority acknowledgement")
        if not acknowledged then
            acknowledged=true
            print("[DRIVING_BENCH_TEST] AUTHORITY_ACK actor="..args.actor.." id="..args.id.." sql="..args.sqlId)
        end
        finish(p,v,args.sqlId,"server")
    end)
    if not ok then fail(problem) end
end)
Events.OnTick.Add(function()
    local C=PZDrivingBenchClient
    if failed or sampled or not C or not C.ready or not F.allowed() then return end
    local now=getTimestampMs()
    if not began then began=now end
    if now-began<3000 then return end
    if now-began>120000 then fail("Timed out waiting for both Host authority checks");return end
    if nextRequest and now<nextRequest then return end
    nextRequest=now+2000
    local ok,problem=pcall(function()
        local p,v=checkedVehicle()
        if isClient() then
            assert(config.kind=="mp" and config.clients==2,"Requires two-client Host")
            assert(type(preparedSql)=="number" and preparedSql>0,"Missing authoritative prepared SQL id")
            sendClientCommand(MODULE,"validate",{request=1,id=v:getId(),sqlId=preparedSql})
        else
            assert(config.kind=="sp","Expected real SP")
            local before=getCell():getVehicles():size()
            local repeated=F.prepare(p)
            assert(repeated.status=="ready" and repeated.reused and repeated.sqlId==v:getSqlId(),"Repeated prepare changed car")
            assert(getCell():getVehicles():size()==before,"Duplicate car")
            finish(p,v,repeated.sqlId,"sp")
        end
    end)
    if not ok then fail(problem) end
end)
