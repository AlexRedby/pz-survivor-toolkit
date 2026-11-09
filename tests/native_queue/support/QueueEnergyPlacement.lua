-- Fixture setup only. Selection is not proof that an actor has arrived.
local P={timeoutMs=30000,stableMs=500}
local function finite(value)
 return type(value)=='number'and value==value and math.abs(value)<1000000
end
function P.target(value)
 assert(type(value)=='table','placement target missing')
 local count=0
 for key in pairs(value)do assert(key=='x'or key=='y'or key=='z','foreign placement target field');count=count+1 end
 assert(count==3,'placement target fields missing')
 for _,key in ipairs({'x','y','z'})do
  assert(finite(value[key])and value[key]%1==0,'placement target requires finite integer coordinates')
 end
 return {x=value.x,y=value.y,z=value.z}
end
local function same(a,b)return a.x==b.x and a.y==b.y and a.z==b.z end
local function tile(square)
 return square and{x=square:getX(),y=square:getY(),z=square:getZ()}or false
end
function P.snapshot(player,localMotion,probe)
 local value={x=player:getX(),y=player:getY(),z=player:getZ(),
  square=tile(player:getSquare()),currentSquare=tile(player:getCurrentSquare())}
 if localMotion then
  assert(ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue,'native placement queue unavailable')
  local queue=ISTimedActionQueue.getTimedActionQueue(player)
  local motion=player:getDeferredMovement(probe)
  value.queued=#queue.queue;value.timed=player:hasTimedActions()
  value.moving=player:isPlayerMoving();value.hasPath=player:getPath2()~=nil
  value.deferredX,value.deferredY=motion:getX(),motion:getY()
 end
 return value
end
local function arrived(value,target)
 return finite(value.x)and finite(value.y)and finite(value.z)
  and math.floor(value.x)==target.x and math.floor(value.y)==target.y
  and math.abs(value.z-target.z)<=.01
  and value.square and same(value.square,target)
  and value.currentSquare and same(value.currentSquare,target)
end
local function centered(value,target)
 return arrived(value,target)and math.abs(value.x-target.x-.5)<=.1 and math.abs(value.y-target.y-.5)<=.1
end
function P.at(player,target)
 local ok,validated=pcall(P.target,target)
 return ok and player~=nil and arrived(P.snapshot(player),validated)and true or false
end
function P.atCentered(player,target)
 local ok,validated=pcall(P.target,target)
 return ok and player~=nil and centered(P.snapshot(player),validated)and true or false
end
function P.choose(player)
 local origin=assert(player:getCurrentSquare(),'placement origin is not loaded')
 for radius=2,12 do
  for dx=-radius,radius do for dy=-radius,radius do
   if math.abs(dx)==radius or math.abs(dy)==radius then
    local x,y,z=origin:getX()+dx,origin:getY()+dy,origin:getZ()
    local clear=true
    for a=-1,1 do for b=-1,1 do
     local sq=getCell():getGridSquare(x+a,y+b,z)
     if not sq or not sq:isFree(false)or sq:getRoom()or sq:getObjects():size()>1 then clear=false end
    end end
    if clear then return P.target({x=x,y=y,z=z})end
   end
  end end
 end
 error('No clear loaded 3x3 native energy fixture area')
end
local function owns(player)return not isServer()and player:isLocalPlayer()end
local function state(player,target,mode)
 assert(player,'placement actor missing')
 target=P.target(target)
 return {player=player,target=target,expected=P.target(target),mode=mode,
  phase=mode=='local'and'quiet'or'arrival',began=getTimestampMs(),teleports=0}
end
function P.begin(player,target)
 assert(owns(player),'placement must move the owning local client only')
 local value=state(player,target or P.choose(player),'local')
 value.probe=Vector2.new()
 return value
end
function P.observe(player,target)return state(player,target,'replica')end
function P.beginCentered(player,target)
 local value=P.begin(player,target);value.centered=true;value.centers=0;return value
end
function P.observeCentered(player,target)
 local value=P.observe(player,target);value.centered=true;value.centers=0;return value
end
local function center(player,target)
 local x,y,z=target.x+.5,target.y+.5,target.z
 player:setX(x);player:setY(y);player:setZ(z);player:setNextX(x);player:setNextY(y);player:setLastX(x);player:setLastY(y)
 player:ensureOnTile();player:setCurrentSquareFromPosition();player:setMovingSquareNow()
 assert(math.abs(player:getX()-x)<.01 and math.abs(player:getY()-y)<.01 and player:getZ()==z,'Native pre-baseline centering failed')
end
local function coordinate(value)return value and(tostring(value.x)..','..tostring(value.y)..','..tostring(value.z))or'absent'end
function P.describe(value)
 local actual=value.actual
 local detail=actual and actual.queued~=nil and(' queued='..tostring(actual.queued)..' timed='..tostring(actual.timed)
  ..' moving='..tostring(actual.moving)..' path='..tostring(actual.hasPath)
  ..' deferred='..tostring(actual.deferredX)..','..tostring(actual.deferredY))or''
 return 'mode='..value.mode..' phase='..value.phase..' target='..coordinate(value.target)
  ..' actual='..coordinate(actual)..' square='..coordinate(actual and actual.square)
  ..' currentSquare='..coordinate(actual and actual.currentSquare)..' teleports='..value.teleports..detail
end
local function idle(actual)
 return actual.queued==0 and not actual.timed and not actual.moving and not actual.hasPath
  and actual.deferredX==0 and actual.deferredY==0
end
local function stable(value,actual,eligible,now)
 if not eligible or not value.stableAt or not value.last or not same(actual,value.last)then
  value.stableAt=eligible and now or nil;value.samples=eligible and 1 or 0
 else value.samples=value.samples+1 end
 value.last=actual
 return value.stableAt and now-value.stableAt>=P.stableMs and value.samples>=2
end
function P.poll(value)
 -- A consumed proof is historical, not permission to assume the actor stayed
 -- there. Consumers requiring a current position use at() again.
 if value.result then return value.result end
 local now=getTimestampMs()
 assert(same(P.target(value.target),value.expected),'placement target changed while pending')
 assert(now>=value.began,'placement clock moved backwards')
 if value.mode=='local'then assert(owns(value.player),'placement local ownership changed')end
 value.actual=P.snapshot(value.player,value.mode=='local',value.probe)
 assert(now-value.began<P.timeoutMs,'placement timed out '..P.describe(value))
 if not value.loggedAt or now-value.loggedAt>=5000 then
  value.loggedAt=now;print('[QUEUE_TEST] PLACEMENT_WAIT '..P.describe(value))
 end
 if value.phase=='quiet'then
  local here={x=math.floor(value.actual.x),y=math.floor(value.actual.y),z=math.floor(value.actual.z)}
  if not stable(value,value.actual,idle(value.actual)and arrived(value.actual,here),now)then return end
  value.quietMs=now-value.stableAt
  -- B42's float teleport floors x/y. Centered fixtures explicitly perform
  -- their one setup adjustment here; subsequent polls only observe arrival.
  value.player:teleportTo(value.target.x,value.target.y,value.target.z)
  value.teleports=1;value.phase='arrival';value.last=nil;value.stableAt=nil;value.samples=0
  if value.centered then value.centers=1;center(value.player,value.target)end
  return
 end
 if not stable(value,value.actual,(value.centered and centered(value.actual,value.target)or not value.centered and arrived(value.actual,value.target))
  and(value.mode~='local'or idle(value.actual)),now)then return end
 value.result={mode=value.mode,target=P.target(value.target),actual=value.actual,
  teleports=value.teleports,stableMs=now-value.stableAt,quietMs=value.quietMs or 0,elapsedMs=now-value.began}
 if value.centered then value.result.centered=true;value.result.centers=value.centers end
 value.phase='settled';print('[QUEUE_TEST] PLACEMENT_READY '..P.describe(value))
 return value.result
end

-- Temporary compatibility for synchronous fixtures awaiting protocol migration.
-- New callers use begin/poll locally and observe/poll on authority.
return setmetatable(P,{__call=function(_,player)
 local target=P.choose(player)
 player:teleportTo(target.x+.5,target.y+.5,target.z)
 print('[QUEUE_TEST] ENERGY_PLACEMENT '..coordinate(target))
 return getCell():getGridSquare(target.x,target.y,target.z)
end})
