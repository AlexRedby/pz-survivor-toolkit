local preflight=require 'QueuePreflight'
local config=require 'QueueTestSelection'
if config.suite~='loot-demand' or config.kind~='mp' or config.cases[1]~='natural' then return end
require 'TimedActions/ISWalkToTimedAction'
require 'TimedActions/ISTimedActionQueue'
local options=config.options or {}
local arm=options.loot_demand_arm
assert(arm=='observe' or arm=='defer','natural Host requires exact arm')
local PREFIX='[LOOT_NATURAL] '
local started,done,sent=false,false,false
local beginAt,target,goal,walk,approachAt,approachClock,authority,matchedAt
local nativeSeen,seenCount={},0
local nearAt, listedAt, previousState
local checkPage, originalCheck, tracedCheck, ownedCheck, checkLogged
local function emit(kind,text) print(PREFIX..kind..' role=client arm='..arm..' '..text) end
-- AeroSpace may resize the disposable client when a sleeping display wakes
-- during Host startup. Restore its requested windowed resolution before the
-- shared preflight samples it. Never resize once the test has entered the world.
local lastWindowRequest
local function prepareWindow()
 if started or done or isIngameState() then return end
 local core,size=getCore(),config.window_size
 if core:getScreenWidth()==size[1] and core:getScreenHeight()==size[2] then return end
 local now=getTimestampMs()
 if lastWindowRequest and now-lastWindowRequest<3000 then return end
 lastWindowRequest=now
 core:setResolutionAndFullScreen(size[1],size[2],false)
 emit('WINDOW','requested_width='..size[1]..' requested_height='..size[2])
end
Events.OnPreUIDraw.Add(prepareWindow)
Events.OnConnected.Add(prepareWindow)
local function dump(phase)
 emit('ROW','phase='..phase..' clock_ns='..tostring(lootDemandClock())..' format=status')
 for line in lootDemandCensusStatus():gmatch('[^\r\n]+') do emit('ROW','phase='..phase..' status='..line) end
 for line in lootDemandCensus():gmatch('[^\r\n]+') do emit('ROW','phase='..phase..' csv='..line) end
end
local function restoreCheck()
 if checkPage and checkPage.checkExplored==tracedCheck then
  checkPage.checkExplored=ownedCheck and originalCheck or nil
 end
 checkPage,originalCheck,tracedCheck,ownedCheck=nil,nil,nil,nil
end
local function fail(problem)
 if done then return end
 done=true;restoreCheck();emit('FAIL','problem='..tostring(problem))
 if isClient() and getPlayer() then sendClientCommand('LootNatural','Failure',{problem=tostring(problem)}) end
end
local function nativeTarget()
 local square=getCell():getGridSquare(target.x,target.y,target.z)
 if not square or target.index>=square:getObjects():size() then return end
 local object=square:getObjects():get(target.index)
 if not object or not object:getSprite() or object:getSprite():getName()~=target.sprite then return end
 local container=object:getContainer()
 if not container or container:getType()~=target.kind then return end
 return object,container
end
local function chooseGoal(player)
 local choices={}
 local targetSquare=assert(getCell():getGridSquare(target.x,target.y,target.z),'target square unavailable')
 for _,delta in ipairs({{-1,0},{0,-1},{0,1},{1,0}}) do
  local square=getCell():getGridSquare(target.x+delta[1],target.y+delta[2],target.z)
  if square and square:getFloor() and square:canStand() and square:isFree(false)
   and square:canReachTo(targetSquare) then
   local dx,dy=square:getX()-player:getX(),square:getY()-player:getY()
   choices[#choices+1]={square=square,distance=dx*dx+dy*dy}
  end
 end
 table.sort(choices,function(a,b)
  if a.distance~=b.distance then return a.distance<b.distance end
  if a.square:getX()~=b.square:getX() then return a.square:getX()<b.square:getX() end
  return a.square:getY()<b.square:getY()
 end)
 assert(choices[1],'no loaded free cardinal square with native inventory reach');return choices[1].square
end
preflight.onGameStart(Events,function() started=true end)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='LootNatural' or done then return end
 local ok,problem=pcall(function()
  assert(type(args)=='table','malformed native Host response')
  if command=='Failure' then error('authority failure: '..tostring(args.problem))
  elseif command=='Target' then
   assert(sent and not target,'unrequested target');target=args
   local player=assert(getPlayer());assert(not player:getVehicle(),'natural actor must walk')
   assert(math.max(math.abs(target.x-player:getX()),math.abs(target.y-player:getY()))>3,'target started inside nearby inventory scan')
   assert(nativeTarget(),'server-selected real target not replicated locally')
   goal=chooseGoal(player);dump('before')
   emit('READY','phase=target x='..target.x..' y='..target.y..' z='..target.z..' index='..target.index..' goal_x='..goal:getX()..' goal_y='..goal:getY())
   sendClientCommand('LootNatural','Approaching',{})
  elseif command=='Armed' then
   assert(target and not walk,'unrequested approach arm')
   local player=getPlayer();local loot=getPlayerLoot(player:getPlayerNum())
   assert(loot and loot.inventoryPane,'normal loot inventory unavailable')
   loot:setVisible(true)
   loot:setPinned()
   checkPage=loot;originalCheck=loot.checkExplored
   assert(type(originalCheck)=='function','native loot checkExplored unavailable')
   ownedCheck=false
   for key in pairs(loot) do if key=='checkExplored' then ownedCheck=true;break end end
   local forward=originalCheck
   tracedCheck=function(page,container,actor)
    local _,selected=nativeTarget()
    if container==selected and not checkLogged then
     checkLogged=true
     emit('CHECK','phase=native explored='..tostring(container:isExplored())..' client='..tostring(isClient()))
    end
    return forward(page,container,actor)
   end
   loot.checkExplored=tracedCheck
   approachAt=getTimestampMs();approachClock=lootDemandClock()
   emit('APPROACH','phase=start clock_ns='..tostring(approachClock)..' x='..player:getX()..' y='..player:getY()..' goal_x='..goal:getX()..' goal_y='..goal:getY())
   walk=ISWalkToTimedAction:new(player,goal);assert(walk.Type=='ISWalkToTimedAction','actual native walk required');ISTimedActionQueue.add(walk)
  elseif command=='Authority' then
   assert(walk and not authority,'unrequested native authority result');authority=args
   emit('RESULT','phase=authority-received items='..args.count..' fill_kind='..args.fill_kind..' fill_ns='..tostring(args.fill_ns)..' server_clock_ns='..tostring(args.clock_ns)..' client_clock_ns='..tostring(lootDemandClock()))
  elseif command=='Complete' then
   assert(matchedAt and args.ok==true,'authority did not accept actual client inventory')
   done=true;restoreCheck();dump('complete');emit('COMPLETE','case=natural outcome='..(args.empty and 'empty-no-client-packet-receipt' or 'native-inventory-matched'))
  else error('unknown authority command '..tostring(command)) end
 end)
 if not ok then fail(problem) end
end)
preflight.onTick(Events,function()
 if done or not started or not isIngameState() then return end
 local player=getPlayer();if not player or not player:getSquare() or not isClient() or player:getOnlineID()<0 then return end
 local ok,problem=pcall(function()
  assert(not player:isDead(),'natural actor died');assert(lootDemandInstalled(),'client hooks inactive')
  if not sent then
   sent=true;beginAt=getTimestampMs()
   emit('READY','phase=begin x='..player:getX()..' y='..player:getY()..' z='..player:getZ()..' clock_ns='..tostring(lootDemandClock()))
   sendClientCommand('LootNatural','Begin',{});return
  end
  assert(getTimestampMs()-beginAt<180000,'natural client timeout')
  if walk and not matchedAt then
   assert(getTimestampMs()-approachAt<100000,'native walk/inventory availability timeout')
   local _,container=nativeTarget();assert(container,'real target changed during approach')
   local dx,dy=player:getX()-target.x,player:getY()-target.y
   local page=getPlayerLoot(player:getPlayerNum());local listed=false
   for _,button in ipairs(page and page.backpacks or {}) do if button.inventory==container then listed=true;break end end
   local close=math.max(math.abs(dx),math.abs(dy))<=1.9
   local current=assert(player:getCurrentSquare(),'native standing square unavailable')
   local targetSquare=container:getParent():getSquare()
   local reachable=current:canReachTo(targetSquare)
   local atGoal=current:getX()==goal:getX() and current:getY()==goal:getY() and current:getZ()==goal:getZ()
   local standing=current:getX()..','..current:getY()..','..current:getZ()
   assert(walk.result~=BehaviorResult.Failed,'native walk failed at '..standing..' reachable='..tostring(reachable))
   local arrived=walk.result==BehaviorResult.Succeeded and atGoal and reachable
   local state=tostring(close)..'/'..tostring(listed)..'/'..tostring(container:isExplored())
    ..' standing='..standing..' at_goal='..tostring(atGoal)..' reachable='..tostring(reachable)..' walk='..tostring(walk.result)
   if state~=previousState then
    previousState=state
    emit('STATE','x='..player:getX()..' y='..player:getY()..' near/listed/explored='..state..' items='..container:getItems():size())
   end
   if not nearAt and close then nearAt=getTimestampMs() end
   if listed and not listedAt then listedAt=getTimestampMs() end
   if listed and math.max(math.abs(dx),math.abs(dy))<=1.9 and container:isExplored() then
    local fingerprint=lootDemandFingerprint(container)
    if not nativeSeen[fingerprint] then
     seenCount=seenCount+1;assert(seenCount<=64,'native inventory kept mutating during observation')
     nativeSeen[fingerprint]={at=getTimestampMs(),clock=lootDemandClock(),count=container:getItems():size()}
    end
   end
   local observed=authority and nativeSeen[authority.fingerprint]
   if arrived and observed and observed.count==authority.count then
    matchedAt=observed.at;local elapsed=matchedAt-approachAt
    dump('matched')
    emit('RESULT','phase=client-native-inventory x='..target.x..' y='..target.y..' items='..authority.count..' elapsed_ms='..elapsed..' nearby_to_ready_ms='..(matchedAt-nearAt)..' listed_to_ready_ms='..(matchedAt-listedAt)..' clock_ns='..tostring(observed.clock)..' empty_packet_receipt='..tostring(authority.count~=0))
    sendClientCommand('LootNatural','Observe',{count=authority.count,fingerprint=authority.fingerprint,elapsed_ms=elapsed})
   end
  end
 end)
 if not ok then fail(problem) end
end)
