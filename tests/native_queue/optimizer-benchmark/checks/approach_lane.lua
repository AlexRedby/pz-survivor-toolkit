local M=dofile(arg[1])
local calls, road, answers, forced={},{},{}
local poseOK=true
function drivingPerfVerifyApproachVehicle(vehicle,distance,width,length,clearance)
    return poseOK and distance==120 and width==1 and length==2 and clearance==.25
end
local function square(x,y) return {getX=function()return x end,getY=function()return y end} end
local function street(x,y)
    if forced and forced(x,y) then return end
    if x>=90 and x<=110 and y>=196 and y<=204 then return square(x,y) end
end
local function original()return square(100,200),"N",180 end
local function value(status,checked,coverage)
    return {status=status or "clear_loaded",checked_distance=checked or 60,requested_distance=120,
        coverage=coverage or "partial",blocker_count=status=="blocked" and 1 or 0,
        target_half_width=1,target_half_length=2,clearance=.25}
end
function drivingPerfAssessApproach(x,y,d)
    calls[#calls+1]={x,y,d}
    assert(y==200 and d==120,"same longitudinal track and distance")
    return answers[x] or value("blocked")
end
local function reset()
    calls={};answers={};forced=nil;PZDrivingApproachLaneChoice=nil
end
local function rejected(fn,part)
    local ok,err=pcall(fn);assert(not ok and tostring(err):find(part,1,true), tostring(err))
end
reset();answers[100]=value();local s,h,yaw=M.choose({},original,street,120)
assert(s:getX()==100 and h=="N" and yaw==180 and #calls==1,"clear original retained")
assert(PZDrivingApproachLaneChoice.coverage=="partial","unvisited tail not qualified")
reset();answers[104]=value();answers[98]=value()
s=M.choose({},original,street,120)
assert(s:getX()==98 and #calls==3 and calls[2][1]==102 and calls[3][1]==98,"nearest lateral deterministic tie")
reset();answers[102]=value(nil,58);answers[98]=value(nil,61)
s=M.choose({},original,street,120)
assert(s:getX()==98,"shorter coverage rejected")
reset();answers[102]=value("unknown")
rejected(function()M.choose({},original,street,120)end,"Unknown approach geometry")
reset();answers[100]=value(nil,120,"complete")
s=M.choose({},original,street,120);assert(PZDrivingApproachLaneChoice.coverage=="complete")
local choice=PZDrivingApproachLaneChoice
local vehicle={getScriptName=function()return "Base.SportsCar" end,getX=function()return 100 end,getY=function()return 200 end,getSqlId=function()return 14 end}
assert(M.seal(choice,vehicle,120)==choice and choice.sql_id==14)
assert(M.verify(choice,vehicle,120)==choice)
choice.sql_id=13;rejected(function()M.verify(choice,vehicle,120)end,"identity differs");choice.sql_id=14
poseOK=false;rejected(function()M.verify(choice,vehicle,120)end,"ground pose");poseOK=true
rejected(function()M.verify(nil,vehicle,120)end,"fresh seed")
rejected(function()M.verify(choice,vehicle,100)end,"distance differs")
choice.y=199;rejected(function()M.verify(choice,vehicle,120)end,"geometry");choice.y=200
for _,offset in ipairs({.051,.249,.5}) do
    vehicle.getX=function()return 100+offset end
    rejected(function()M.verify(choice,vehicle,120)end,"matches saved lane")
end
vehicle.getX=function()return 100.049 end
assert(M.verify(choice,vehicle,120)==choice,"bounded start drift retained")
vehicle.getX=function()return 100 end
vehicle.getY=function()return 200.051 end
rejected(function()M.verify(choice,vehicle,120)end,"matches saved lane")
vehicle.getY=function()return 200 end
for _,field in ipairs({"target_half_width","target_half_length","clearance"}) do
    local saved=choice[field];choice[field]=saved+.01
    rejected(function()M.verify(choice,vehicle,120)end,"assessed dimensions")
    choice[field]=saved
end
reset();forced=function(x,y)return x==103 end;answers[104]=value()
rejected(function()M.choose({},original,street,120)end,"Blocked approach")
for _,c in ipairs(calls)do assert(c[1]<=100,"cannot jump a disconnected street band")end
reset();answers[100]=value("unknown",0)
rejected(function()M.choose({},original,street,120)end,"Unknown approach geometry")
reset();answers[100]=value(nil,60,"complete")
rejected(function()M.choose({},original,street,120)end,"Inconsistent approach coverage")
reset();answers[100]=value();answers[100].blocker_count=1
rejected(function()M.choose({},original,street,120)end,"Inconsistent approach blockers")
reset();answers[100]=value();answers[100].target_half_width=0/0
rejected(function()M.choose({},original,street,120)end,"Invalid approach dimension")
reset();assert(M.choose({},function()return nil end,street,120)==nil and #calls==0,"original wait retained")
assert(PZDrivingApproachLaneChoice==nil,"no stale receipt")
print("APPROACH_LANE_CHECKS_PASS")
