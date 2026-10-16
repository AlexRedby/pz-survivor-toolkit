local Fixture=dofile(ProjectRoot..'/tests/native_tags/shared/TagFixture.lua')
IsoDirections={W='W',E='E',N='N',S='S'}
local function square(x,y,stand,free,reach)
 local moving={}
 return {getX=function() return x end,getY=function() return y end,getZ=function() return 0 end,
  canStand=function() return stand~=false end,isFree=function(_,checkMoving) return free~=false and (not checkMoving or #moving==0) end,
  moving=moving,getMovingObjects=function() return {size=function() return #moving end,get=function(_,i) return moving[i+1] end} end,
  canReachTo=function() return reach~=false end}
end
local start=square(10,10)
local unsupported=square(9,10,false)
local occupied=square(11,10,true,false)
local walled=square(10,9,true,true,false)
local valid=square(10,11)
local neighbors={W=unsupported,E=occupied,N=walled,S=valid}
start.getAdjacentSquare=function(_,direction) return neighbors[direction] end
local player={getCurrentSquare=function() return start end}
AdjacentFreeTileFinder={privTrySquare=function(_,target) return target~=walled end}
assert(Fixture.crateSquare(player)==valid,'placement accepted blocked, occupied or walled square')
assert(player:getCurrentSquare()==start,'placement moved player')
neighbors.S=nil
assert(not Fixture.crateSquare(player),'placement fell back to player tile')
start.canStand=function() return false end
neighbors.S=valid
assert(not Fixture.crateSquare(player),'placement accepted blocked player start')
assert(Fixture.crateSprite=='carpentry_01_16','fixture does not use native crate sprite')
start.canStand=function() return true end
start.moving[1]=player
assert(Fixture.startFree(start,player),'own player made starting square unavailable')
start.moving[2]={}
assert(not Fixture.startFree(start,player),'another moving object accepted on player staging square')
start.moving[2]=nil
valid.moving[1]={}
assert(not Fixture.crateSquare(player),'occupied crate tile accepted')
valid.moving[1]=nil
local grid={}
local function addSquare(value)
 grid[value:getX()..','..value:getY()]=value
 value.getAdjacentSquare=function(_,direction)
  local offsets={W={-1,0},E={1,0},N={0,-1},S={0,1}}
  local offset=offsets[direction]
  return grid[(value:getX()+offset[1])..','..(value:getY()+offset[2])]
 end
 return value
end
addSquare(square(18,10,false)) -- The intended +8 offset is not valid floor.
addSquare(square(17,10));addSquare(square(17,11)) -- Valid pair, too near the first actor.
local safe=addSquare(square(19,10));local crate=addSquare(square(19,11))
getCell=function() return {getGridSquare=function(_,x,y,z) if z==0 then return grid[x..','..y] end end} end
local reservations={first={start=start,crate=valid}}
local pair=assert(Fixture.stagePair(player,{x=18,y=10,z=0},reservations,'second'))
assert(pair.start==safe and pair.crate==crate,'staging accepted invalid offset, unloaded tile or overlapping actor area')
assert(reservations.second==nil and player:getCurrentSquare()==start,'selection mutated player/world/reservations')
assert(not Fixture.stagePair(player,{x=100,y=100,z=0},reservations,'second'),'staging escaped bounded loaded area')
local placement={signature='two-loaded-clients',squares={{x=19,y=10,z=0},{x=19,y=11,z=0},{x=17,y=10,z=0},{x=100,y=100,z=0}}}
assert(not Fixture.placementLoaded(placement),'client acknowledged an unloaded peer square')
addSquare(square(100,100))
assert(Fixture.placementLoaded(placement),'client failed to acknowledge all four loaded staging squares')
assert(not Fixture.placementLoaded({signature='x',squares={}}),'empty placement acknowledged')
assert(not Fixture.placementLoaded({squares=placement.squares}),'placement without identity acknowledged')

-- Exercise the real native update so diagnostics distinguish its cancellation branches
-- without changing inputs, result, completion or the action's duration.
require=function() end
ISBaseTimedAction={derive=function() return {} end}
dofile(NativePZLuaRoot..'/client/TimedActions/WalkToTimedAction.lua')
BehaviorResult={Failed='Failed',Working='Working',Succeeded='Succeeded'}
instanceof=function() return true end
local movement,cancel,result=false,false,BehaviorResult.Working
local updates,stops,completions=0,0,0
local behavior={update=function() updates=updates+1;return result end}
player.getX=function() return 10.5 end;player.getY=function() return 10.5 end;player.getZ=function() return 0 end
player.pressedMovement=function() return movement end;player.pressedCancelAction=function() return cancel end
player.getPathFindBehavior2=function() return behavior end
start.canStand=function() return true end
local events={}
local function make()
 return Fixture.traceWalk({character=player,location=valid,maxTime=-1,
  update=ISWalkToTimedAction.update,
  start=function(_,arg) return arg end,stop=function(_,arg) return arg end,
  forceStop=function() stops=stops+1 end,forceComplete=function() completions=completions+1 end},
  function(value) events[#events+1]=value end)
end
local action=make()
assert(action:start('native-start')=='native-start')
action:update()
assert(updates==1 and stops==0 and completions==0 and action.maxTime==-1)
result=BehaviorResult.Failed
action:update()
assert(stops==1 and events[#events].branch=='path-failed' and action.result==BehaviorResult.Failed)
assert(action:stop('native-stop')=='native-stop' and events[#events].branch=='path-failed')
movement=true;action=make();action:update()
assert(stops==2 and updates==2 and events[#events].branch=='input' and events[#events].movement)
movement=false;cancel=true;action=make();action:update()
assert(stops==3 and updates==2 and events[#events].branch=='input' and events[#events].cancel)
cancel=false;result=BehaviorResult.Succeeded;action=make();action:update()
assert(stops==3 and updates==3 and completions==1,'trace changed native completion')
assert(events[1].origin.x==10.5 and events[1].destination.y==11,'trace omitted actual path endpoints')
action.result=BehaviorResult.Failed;action:forceStop()
assert(events[#events].branch=='external','external stop misattributed to an earlier native result')
print('Native tag placement/walk checks passed: adjacent free floor, no player-tile fallback, native input/path branches and completion preserved.')
