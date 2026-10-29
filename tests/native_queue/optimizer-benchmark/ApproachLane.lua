-- Disposable Muldraugh fixture only. Does not create/load chunks or alter traffic.
local M = {}
local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end
local function footprint(street, x, y)
    for ahead=-4,4 do for side=-2,2 do
        if not street(x+side,y+ahead) then return false end
    end end
    return true
end
local function assessment(x,y,distance)
    local value=drivingPerfAssessApproach(x,y,distance)
    assert(type(value)=="table" and finite(value.checked_distance)
        and finite(value.requested_distance) and value.requested_distance==distance
        and value.checked_distance>=0 and value.checked_distance<=distance
        and finite(value.blocker_count) and value.blocker_count>=0,
        "Invalid native approach assessment")
    if value.status=="unknown" then error("Unknown approach geometry: "..tostring(value.reason)) end
    assert(value.status=="blocked" or value.status=="clear_loaded", "Unknown approach status")
    assert(value.coverage=="partial" or value.coverage=="complete", "Unknown approach coverage")
    assert((value.coverage=="complete")== (value.checked_distance==distance), "Inconsistent approach coverage")
    assert((value.status=="blocked")== (value.blocker_count>0), "Inconsistent approach blockers")
    for _,key in ipairs({"target_half_width","target_half_length","clearance"}) do
        assert(finite(value[key]) and value[key]>0, "Invalid approach dimension: "..key)
    end
    return value
end
function M.choose(player, original, street, distance)
    PZDrivingApproachLaneChoice=nil
    assert(type(drivingPerfAssessApproach)=="function", "Missing native approach assessor")
    assert(finite(distance) and distance>=10 and distance<=500, "Invalid approach distance")
    local base,direction,yaw=original(player)
    if not base then return end -- Existing unloaded/blocked-footprint retry stays unchanged.
    assert(direction=="N" and yaw==180, "Approach selector requires north-facing native starter")
    local x,y=base:getX(),base:getY()
    assert(finite(x) and finite(y) and footprint(street,x,y), "Original approach footprint changed")
    local first=assessment(x,y,distance)
    assert(first.checked_distance>0, "No loaded approach prefix")
    local function consider(cx, value)
        if value.status~="clear_loaded" then return end
        if value.checked_distance<first.checked_distance then
            print("[DRIVING_APPROACH] REJECTED x="..cx.." y="..y.." reason=shorter_loaded_prefix")
            return
        end
        local choice={format=1,x=cx,y=y,baseline_x=x,baseline_y=y,
            requested_distance=distance,checked_distance=value.checked_distance,
            baseline_checked_distance=first.checked_distance,coverage=value.coverage,
            target_half_width=value.target_half_width,target_half_length=value.target_half_length,
            clearance=value.clearance,script="Base.SportsCar"}
        PZDrivingApproachLaneChoice=choice
        print("[DRIVING_APPROACH] SELECTED x="..cx.." y="..y.." baseline_x="..x.." baseline_y="..y
            .." checked_distance="..choice.checked_distance.." requested_distance="..distance
            .." coverage="..choice.coverage.." unknown_tail="..tostring(choice.coverage=="partial"))
        return street(cx,y),"N",180
    end
    if first.status=="clear_loaded" then return consider(x,first) end
    local stopped={}
    for offset=2,32,2 do
        for _,side in ipairs({1,-1}) do
            if not stopped[side] then
                local cx=x+side*offset
                -- Overlapping 9x5 street footprints retain one connected cross-section.
                if not footprint(street,cx,y) then stopped[side]=true
                else
                    local value=assessment(cx,y,distance)
                    local square,heading,angle=consider(cx,value)
                    if square then return square,heading,angle end
                end
            end
        end
        if stopped[1] and stopped[-1] then break end
    end
    error("Blocked approach: no loaded lateral lane with equal coverage on the same street; traffic retained")
end
local function validate(choice, vehicle, distance)
    assert(type(choice)=="table" and choice.format==1 and choice.script=="Base.SportsCar",
        "Missing lane-qualified seed; create a fresh seed before driving")
    assert(finite(distance) and choice.requested_distance==distance,
        "Seed approach distance differs from drive")
    for _,key in ipairs({"x","y","baseline_x","baseline_y","checked_distance","baseline_checked_distance",
                         "target_half_width","target_half_length","clearance"}) do
        assert(finite(choice[key]), "Invalid saved lane field: "..key)
    end
    assert(choice.y==choice.baseline_y and math.abs(choice.x-choice.baseline_x)<=32
        and choice.checked_distance>=choice.baseline_checked_distance and choice.baseline_checked_distance>0
        and choice.checked_distance<=distance and choice.target_half_width>0
        and choice.target_half_length>0 and choice.clearance>0, "Invalid saved lane geometry")
    assert((choice.coverage=="complete" or choice.coverage=="partial")
        and (choice.coverage=="complete")== (choice.checked_distance==distance), "Invalid saved lane coverage")
    -- Keep start drift below .05; the native heading check separately bounds course drift
    -- to .05, leaving margin within the .25 assessed clearance for corner rotation.
    assert(vehicle and vehicle:getScriptName()==choice.script
        and math.abs(vehicle:getX()-choice.x)<0.05 and math.abs(vehicle:getY()-choice.y)<0.05,
        "Starter no longer matches saved lane")
    assert(type(drivingPerfVerifyApproachVehicle)=="function"
        and drivingPerfVerifyApproachVehicle(vehicle,distance,choice.target_half_width,
            choice.target_half_length,choice.clearance)==true,
        "Starter no longer has the assessed dimensions or north-facing ground pose")
    local id=vehicle:getSqlId()
    assert(finite(id) and id>0 and id==math.floor(id), "Starter database identity unavailable")
    return id
end
function M.seal(choice,vehicle,distance)
    choice.sql_id=validate(choice,vehicle,distance)
    return choice
end
function M.verify(choice,vehicle,distance)
    local id=validate(choice,vehicle,distance)
    assert(choice.sql_id==id, "Starter identity differs from lane-qualified seed")
    return choice
end
return M
