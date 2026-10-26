-- Run from the repository root: luajit tests/driving_benchmark/check_fixture.lua [source-lua-directory]
local source = arg[1] or "tests/driving_benchmark/mods/PZDrivingBench/42/media/lua"
source = source:gsub("/$", "")
assert(loadfile(source .. "/shared/DrivingBenchFixture.lua"))
assert(loadfile(source .. "/server/DrivingBenchServer.lua"))
local state
local function noop() end

function isClient() return state.mode == "client" end
function isServer() return state.mode == "server" end
function getServerName() return state.serverName end
function getWorld() return {getWorld=function() return state.world end} end
function getTimestampMs() return state.now end
ModData = {getOrCreate=function(key)
    state.store[key] = state.store[key] or {}
    return state.store[key]
end}
IsoDirections = {N="N", E="E"}

local function square(x, y)
    return {x=x, y=y, isOutside=function() return true end,
        isFree=function() return true end, getVehicleContainer=noop,
        getFloor=function() return {getSprite=function()
            return {getName=function() return "blends_street_01_1" end}
        end} end}
end
function getCell()
    return {getVehicles=function() return {
        size=function() return #state.vehicles end,
        iterator=function()
            local i=0
            return {hasNext=function() return i < #state.vehicles end,
                next=function() i=i+1;return state.vehicles[i] end}
        end,
    } end, getGridSquare=function(_, x, y)
        if state.mapLoaded then return square(x,y) end
    end}
end
function sendAddItemToContainer(inventory, key)
    assert(inventory == state.inventory and key.keyId == 123)
    state.replicated = state.replicated + 1
end
function sendServerCommand(player, module, command, payload)
    assert(player == state.player and module == "PZDrivingBench")
    state.responses[#state.responses+1] = {command=command, payload=payload}
end
function addVehicleDebug(script, direction, skin, sq)
    assert(script == "Base.CarNormal" and (direction == "N" or direction == "E") and skin == nil)
    state.created = state.created + 1
    local md = {}
    local vehicle = {sqlId=state.initialSqlId or state.created, networkId=state.initialNetworkId or 10}
    local tank = {getContainerCapacity=function() return 40 end,
        setContainerContentAmount=function(_, amount) state.fuel = amount end}
    local door = {setLocked=function(_, locked) state.locked=locked end,
        setLockBroken=function(_, broken) state.lockBroken=broken end}
    local doorPart = {getDoor=function() return door end}
    vehicle.getSquare = function() if not state.reject then return sq end end
    vehicle.getModData = function() return md end
    vehicle.getSqlId = function() return vehicle.sqlId end
    vehicle.getId = function() return state.mode == "sp" and -1 or vehicle.networkId end
    vehicle.getX = function() return sq.x end
    vehicle.getY = function() return sq.y end
    vehicle.getZ = function() return 0 end
    vehicle.setAngles = function()
        if state.failSetup then error("injected angle setup failure") end
    end
    vehicle.repair = function() state.repairs=state.repairs+1 end
    vehicle.getCurrentSpeedKmHour = function() return state.speed or 0 end
    vehicle.getPartById = function(_, id)
        assert(id == "GasTank" or id == "DoorFrontLeft")
        if id == "GasTank" then return not state.noTank and tank or nil end
        return doorPart
    end
    vehicle.transmitPartModData = function(_, part)
        assert(part == tank);state.fuelTransmitted=true
    end
    vehicle.transmitPartDoor = function(_, part)
        assert(part == doorPart);state.doorTransmitted=true
    end
    vehicle.setAlarmed = function(_, alarmed) state.alarmed=alarmed end
    vehicle.transmitAlarmed = function() state.alarmTransmitted=true end
    vehicle.getKeyId = function() return 123 end
    vehicle.createVehicleKey = function() return {keyId=123} end
    if not state.reject then state.vehicles[#state.vehicles+1]=vehicle end
    return vehicle
end

local function reset(mode)
    state = {mode=mode or "sp", world="PZDrivingBench-check", serverName="PZDrivingBench",
        now=0, store={}, vehicles={}, responses={}, created=0, repairs=0, keys={}, added=0,
        replicated=0, mapLoaded=true, playerModData={}}
    state.inventory = {haveThisKeyId=function(_, id) return state.keys[id] end,
        AddItem=function(_, item) state.keys[item.keyId]=item;state.added=state.added+1 end}
    state.player = {getUsername=function() return "guest" end, getPlayerNum=function() return 0 end,
        getX=function() return 10818 end, getY=function() return 10118 end,
        isDead=function() return false end, getCurrentSquare=function() return square(10818,10118) end,
        getInventory=function() return state.inventory end, getModData=function() return state.playerModData end,
        getVehicle=function() return state.seated and state.vehicles[1] or nil end,
        getNearVehicle=function() if state.nearCar ~= false then return state.vehicles[1] end end,
        Say=function(_,message) state.message=message end}
end
local F = assert(loadfile(source .. "/shared/DrivingBenchFixture.lua"))()
local function prepare() return F.prepare(state.player) end
local function ready(result) assert(result.status == "ready", result.reason) end

reset()
state.world="Survival-save"
assert(not F.allowed() and prepare().status == "error" and state.created == 0)
state.world="PZDrivingBench-check"
local result=prepare();ready(result)
assert(result.id == -1 and result.sqlId == 1 and result.script == "Base.CarNormal")
assert(state.repairs == 1 and state.fuel == 40 and state.fuelTransmitted)
assert(state.locked == false and state.lockBroken == false and state.doorTransmitted)
assert(state.alarmed == false and state.alarmTransmitted and state.added == 1 and state.replicated == 0)
state.fuel=10;state.keys={}
result=prepare();ready(result)
assert(result.reused and state.created == 1 and state.repairs == 1 and state.fuel == 10 and state.added == 1)
state.vehicles={}
result=prepare()
assert(result.status == "error" and not result.retryable and result.x and state.created == 1)

reset("server")
state.serverName="servertest"
assert(not F.allowed() and prepare().status == "error" and state.created == 0)
state.serverName="PZDrivingBench"
result=prepare();ready(result)
assert(result.id == 10 and state.added == 1 and state.replicated == 1)
ready(prepare());assert(state.created == 1 and state.replicated == 1)
state.mode="client"
for _,label in ipairs({"", "A friend's Steam Host", "Native startup test", "PZDrivingBench"}) do
    state.serverName=label
    assert(F.allowed() and prepare().status == "error" and state.created == 1)
    assert(state.repairs == 1 and state.added == 1 and state.replicated == 1)
end
state.mode="server";state.serverName="A friend's Steam Host"
assert(not F.allowed() and prepare().status == "error" and state.created == 1)
assert(state.repairs == 1 and state.added == 1 and state.replicated == 1)

reset()
state.mapLoaded=false
result=prepare();assert(result.status == "error" and result.retryable and state.created == 0)
state.mapLoaded=true;state.reject=true
result=prepare();assert(result.status == "error" and state.created == 1 and #state.vehicles == 0)
assert(next(state.store.PZDrivingBenchFixture.players) == nil)
state.reject=false
ready(prepare());assert(state.created == 2 and state.repairs == 1)

reset()
state.failSetup=true
result=prepare();assert(result.status == "error" and state.created == 1)
assert(state.store.PZDrivingBenchFixture.players["local:0"])
state.failSetup=false
ready(prepare());ready(prepare())
assert(state.created == 1 and state.repairs == 1 and state.added == 1)

reset()
state.initialSqlId=-1
result=prepare();assert(result.status == "error" and result.retryable and state.created == 1)
state.vehicles[1].sqlId=42
result=prepare();ready(result)
assert(result.sqlId == 42 and state.created == 1 and state.repairs == 1 and state.added == 1)
assert(state.store.PZDrivingBenchFixture.players["local:0"].sqlId == 42)

reset("server")
state.initialNetworkId=-1
result=prepare();assert(result.status == "error" and result.retryable and state.created == 1)
state.vehicles[1].networkId=21
result=prepare();ready(result);assert(result.id == 21 and state.created == 1)

local callback
Events={OnClientCommand={Add=function(fn) callback=fn end}}
package.preload.DrivingBenchFixture=function() return F end
assert(loadfile(source .. "/server/DrivingBenchServer.lua"))()
reset("server")
callback("other", "prepare", state.player)
callback("PZDrivingBench", "other", state.player)
assert(#state.responses == 0)
callback("PZDrivingBench", "prepare", state.player)
assert(state.responses[1].command == "ready")
callback("PZDrivingBench", "prepare", state.player)
assert(state.responses[2].command == "error" and state.responses[2].payload.retryable)
for i=1,19 do
    state.now=i*1000
    callback("PZDrivingBench", "prepare", state.player)
    assert(state.responses[#state.responses].command == "ready")
end
state.now=20000
callback("PZDrivingBench", "prepare", state.player)
assert(state.responses[#state.responses].command == "error")
state.now=60000
callback("PZDrivingBench", "prepare", state.player)
assert(state.responses[#state.responses].command == "ready" and state.created == 1 and state.repairs == 1)
local count=#state.responses
state.serverName="servertest"
callback("PZDrivingBench", "prepare", state.player)
assert(#state.responses == count)
print("PASS driving fixture: isolation, fuel/key, idempotency, unloaded persistence, rejected placement, setup retry, delayed IDs, Host rate limits")

-- Explicit manual recovery must not affect any unrelated world/car or run on ticks/reload.
reset()
ready(prepare())
local car=state.vehicles[1]
local repairs, created, keys = state.repairs, state.created, state.added
state.fuel=3
assert(F.canRepair(state.player,car))
result=F.repairVehicle(state.player,car)
assert(result.status=="repaired" and state.repairs==repairs+1 and state.fuel==40)
assert(state.created==created and state.added==keys and state.vehicles[1]==car)
state.fuel=7
ready(prepare())
assert(state.repairs==repairs+1 and state.fuel==7,"reload/prepare silently repairs the car")
repairs=state.repairs
state.speed=-20
local allowed,reason,owned=F.canRepair(state.player,car)
assert(not allowed and owned and reason:find("Stop"))
assert(F.repairVehicle(state.player,car).status=="error" and state.repairs==repairs and state.fuel==7)
state.speed=0
state.nearCar=false
assert(F.repairVehicle(state.player,car).status=="error" and state.repairs==repairs)
state.seated=true
assert(F.canRepair(state.player,car))
state.seated=false;state.nearCar=true
local record=state.store.PZDrivingBenchFixture.players["local:0"]
local tag=car:getModData().PZDrivingBenchFixture
-- Reload can deserialize the registry and vehicle tag as different tables.
local clone={}
for k,v in pairs(tag) do clone[k]=v end
car:getModData().PZDrivingBenchFixture=clone
assert(F.canRepair(state.player,car))
clone.owner="local:1"
assert(not F.canRepair(state.player,car))
clone.owner="local:0"
clone.sqlId=999
assert(not F.canRepair(state.player,car))
clone.sqlId=record.sqlId
record.sqlId=999
assert(not F.canRepair(state.player,car))
record.sqlId=car:getSqlId()
state.noTank=true
allowed,reason,owned=F.canRepair(state.player,car)
assert(not allowed and owned and reason:find("wreck"))
assert(F.repairVehicle(state.player,car).status=="error" and state.repairs==repairs)
state.noTank=false
for _,mode in ipairs({"client","server"}) do
    state.mode=mode
    assert(not F.canRepair(state.player,car))
    assert(F.repairVehicle(state.player,car).status=="error" and state.repairs==repairs)
end
state.mode="sp";state.world="normal-save"
assert(not F.canRepair(state.player,car))
assert(F.repairVehicle(state.player,car).status=="error" and state.repairs==repairs)
state.world="PZDrivingBench-check"

local fill, probes, options = nil, 0, {}
Events.OnFillWorldObjectContextMenu={Add=function(fn) fill=fn end}
ISWorldObjectContextMenu={setTest=function() probes=probes+1;return true end,
    addToolTip=function() return {} end}
package.preload["ISUI/ISWorldObjectContextMenu"]=function() return ISWorldObjectContextMenu end
function getSpecificPlayer(index) assert(index==0);return state.player end
local context={addOption=function(_,label,target,callback,vehicle)
    local option={label=label,target=target,callback=callback,vehicle=vehicle}
    options[#options+1]=option
    return option
end}
assert(loadfile(source .. "/client/DrivingBenchRecovery.lua"))()
assert(fill(0,context,{},true)==true and probes==1 and #options==0 and state.repairs==repairs)
fill(0,context,{},false)
assert(#options==1 and options[1].label=="Driving test: repair + refuel")
local option=options[1]
state.nearCar=false
option.callback(option.target,option.vehicle)
assert(state.repairs==repairs,"stale remote menu repaired a vehicle")
state.nearCar=true;state.speed=30
fill(0,context,{},false)
assert(options[2].notAvailable and options[2].toolTip.description:find("Stop"))
option.callback(option.target,option.vehicle)
assert(state.repairs==repairs,"stale moving menu repaired a vehicle")
state.speed=0
option.callback(option.target,option.vehicle)
assert(state.repairs==repairs+1 and state.fuel==40 and state.message:find("repaired"))
local before=#options
for _,mode in ipairs({"client","server"}) do
    state.mode=mode;fill(0,context,{},false)
    assert(#options==before)
end
state.mode="sp";state.world="normal-save"
fill(0,context,{},false)
assert(#options==before)
print("PASS manual recovery: native menu probe, explicit action, owner/SQL/nearby/stopped guards, SP isolation, no passive repair/new vehicles/keys")
