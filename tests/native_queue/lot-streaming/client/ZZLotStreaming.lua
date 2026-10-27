local config=require 'QueueTestSelection'
if config.suite~='lot-streaming'then return end
local F=require 'LotStreamingFixture'
local started,done,go,prepared=false,false,false,false
local role,phase,at,beginAt,workBegin='client1','prepare',0,0,nil
local ack,pending,steps,maxStep,fromX,fromY,phaseTarget=nil,nil,0,0,0,0,nil
local function now()return getTimestampMs()end
local function wait(name,ms)phase=name;at=now()+(ms or 2000)end
local function observe(name)
 local snapshot=F.snapshot(role,name)
 F.probe('TREES',role,name,lotQualTreeCounts(F.chunks))
 ack=nil
 if isClient()then sendClientCommand(F.module,'Probe',{phase=name})else ack=name end
 return snapshot
end
local function beginMove(target,name)
 local p=getPlayer();pending={target=target,name=name};steps,maxStep=0,0;fromX,fromY=p:getX(),p:getY()
 wait('moving',200)
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=F.module then return end
 if command=='Prepared'then role=args.role;prepared=true
 elseif command=='Start'then go=true
 elseif command=='Probe'then ack=args.phase end
end)
Events.OnGameStart.Add(function()
 started=true;beginAt=now();at=beginAt
 local player=getPlayer();player:setGodMod(true);player:setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
local finalSnapshot
local function tick()
 local player=getPlayer()
 if phase=='prepare'then
  if not player:getSquare()then return end
  assert(F.near(player,F.start),'Player did not start at saved/native fixture origin')
  if isClient()then sendClientCommand(F.module,'Prepare',{})else
   F.baseline(config,role);prepared=true;go=true
  end
  wait('ready',200)
 elseif phase=='ready'then
  if not prepared then return end
  if isClient()then sendClientCommand(F.module,'Ready',{})end
  wait('start',200)
 elseif phase=='start'then
  if not go then return end
  workBegin=now()
  observe('before');wait('before_ack',500)
 elseif phase=='before_ack'then
  if ack~='before'then return end
  beginMove(F.away,'away')
 elseif phase=='moving'then
  if pending then return end
  wait('arrived',2500)
 elseif phase=='arrived'then
  assert(F.near(player,phaseTarget or F.away),'Native transition destination differs')
  local name=phaseTarget==F.start and 'returned'or 'away'
  F.emit('TRANSITION',{role=role,phase=name,steps=steps,maxStep=maxStep,
   distance=math.sqrt((player:getX()-fromX)^2+(player:getY()-fromY)^2),x=player:getX(),y=player:getY(),z=player:getZ()})
  finalSnapshot=observe(name);wait(name..'_ack',500)
 elseif phase=='away_ack'then
  if ack~='away'then return end
  beginMove(F.start,'returned')
 elseif phase=='returned_ack'then
  if ack~='returned'then return end
  if not isClient()then F.store(finalSnapshot);save(true)end
  F.emit('SAVE_READY',{role=role,case=config.cases[1],nativeSave=not isClient()})
  F.emit('COMPLETE',{role=role,case=config.cases[1]});done=true
 end
end
-- Follow the native debug-map teleport phase; never clear the player's square while
-- the next destination is unloaded. Each step is <=16 tiles and uses real streaming.
Events.OnPreUIDraw.Add(function()
 if done or not started or not pending or not isIngameState()or now()<at then return end
 local ok,err=pcall(function()
  local p=getPlayer();local target=pending.target
  local x,y=math.floor(p:getX()),math.floor(p:getY());local dx,dy=target[1]-x,target[2]-y
  local length=math.max(math.abs(dx),math.abs(dy))
  if length>12 then x=x+math.floor(dx*12/length);y=y+math.floor(dy*12/length)else x,y=target[1],target[2]end
  local chosen
  for radius=0,2 do for ox=-radius,radius do for oy=-radius,radius do
   local square=getCell():getGridSquare(x+ox,y+oy,0)
   if not chosen and square and square:TreatAsSolidFloor()and square:canStand()then chosen=square end
  end end end
  if not chosen then return end
  local step=math.max(math.abs(chosen:getX()+.5-p:getX()),math.abs(chosen:getY()+.5-p:getY()))
  assert(step<=16,'Native streaming step exceeded bound')
  p:teleportTo(chosen:getX()+.5,chosen:getY()+.5,0);p:setCurrentSquareFromPosition()
  steps=steps+1;maxStep=math.max(maxStep,step);assert(steps<=40,'Native streaming exceeded step budget')
  at=now()+250
  if F.near(p,target)then phaseTarget=target;pending=nil end
 end)
 if not ok then done=true;F.emit('FAIL',{role=role,phase=phase,error=tostring(err)})end
end)
Events.OnTick.Add(function()
 if done or not started or not isIngameState()or now()<at then return end
 local ok,err=pcall(function()
  if workBegin then assert(now()-workBegin<180000,'Bounded native streaming timed out')
  else assert(now()-beginAt<900000,'Bounded peer/setup wait timed out')end
  tick()
 end)
 if not ok then done=true;F.emit('FAIL',{role=role,phase=phase,error=tostring(err)})end
end)
