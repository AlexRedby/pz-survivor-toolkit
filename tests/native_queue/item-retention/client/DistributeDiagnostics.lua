-- Passive fixture telemetry. Never update/restart navigation or manipulate the queue.
local JSON=require 'QueueHealthEvents'
local D={}
local function read(fn,fallback)
 local ok,value=pcall(fn)
 if ok and value~=nil then return value end
 return fallback
end
local function point(square)
 if not square then return {}end
 return {x=square:getX(),y=square:getY(),z=square:getZ(),free=square:isFree(true),
  canStand=square:canStand(),vehicleIntersecting=square:isVehicleIntersecting()}
end
local function container(state,value)
 if not value then return {}end
 local part=value:getVehiclePart()
 local square=part and part:getVehicle():getCurrentSquare()or value:getSourceGrid()
 local parent=value:getParent()
 if not square and parent and parent.getSquare then square=parent:getSquare()end
 return {fixture=value==state.container and 'trunk'or value==state.crate:getContainer()and 'crate'
   or value==state.player:getInventory()and 'actor'or 'other',type=value:getType(),square=point(square),
  part=part and part:getIndex()or -1,vehicle=part and part:getVehicle():getId()or -1}
end
local function action(state,value)
 if not value then return {}end
 local batches={}
 for index,batch in ipairs(value.queueList or {})do
  local ids={};for _,item in ipairs(batch.items or {})do ids[#ids+1]=item:getID()end
  batches[#batches+1]={index=index,ids=ids}
 end
 return {type=value.Type or 'unknown',id=value.item and value.item:getID()or -1,
  src=container(state,value.srcContainer),dest=container(state,value.destContainer),
  standpoint=point(value.location),result=tostring(value.result),phase=value.lsPhase or '',
  run=value.lsRunId or -1,leg=value.lsLegIndex or -1,seq=value.lsSeq or -1,
  nativeAction=value.action~=nil,started=value.started==true,skip=value._lsSkip==true,
  transaction=value.transactionId or -1,batches=batches,
  progress=value.action and read(function()return value:getJobDelta()end,-1)or -1}
end
local function queue(state)
 local queues=ISTimedActionQueue.queues
 return queues and queues[state.player]
end
function D.start(state)
 D.started=getTimestampMs();D.count=0;D.nextAt=1;D.last=nil
 D.debugBefore=LootSorter.DEBUG;LootSorter.DEBUG=true
end
function D.stop()
 if D.started then LootSorter.DEBUG=D.debugBefore;D.started=nil end
end
function D.sample(state,role,force)
 if not D.started or D.count>=20 then return end
 local q=queue(state);local current=q and q.current
 local entries=q and q.queue or {}
 local elapsed=getTimestampMs()-D.started
 local signature=tostring(current)..':'..tostring(current and current.result)..':'..#entries
 local elapsedPoints={0,1000,5000,20000,60000}
 local timed=elapsedPoints[D.nextAt]and elapsed>=elapsedPoints[D.nextAt]
 if not force and not timed and signature==D.last then return end
 if timed then D.nextAt=D.nextAt+1 end
 D.count=D.count+1;D.last=signature
 local player=state.player
 local part=state.vehicle:getPartById('TruckBed')
 local cargo=state.vehicle:getAreaCenter(part:getArea())
 local path=player:getPathFindBehavior2()
 local pending={};for index,value in ipairs(entries)do pending[#pending+1]=action(state,value)end
 local physical={}
 for _,id in ipairs(state.packet.ids)do
  local item=state.container:getItemById(id)or state.crate:getContainer():getItemById(id)
   or player:getInventory():getItemWithIDRecursiv(id)
  physical[#physical+1]={id=id,container=item and container(state,item:getContainer())or {}}
 end
 local payload={role=role,elapsed=elapsed,count=D.count,actor={x=player:getX(),y=player:getY(),z=player:getZ(),
   square=point(player:getCurrentSquare()),vehicle=player:getVehicle()~=nil,hasTimedActions=player:hasTimedActions()},
  cargo={x=cargo:getX(),y=cargo:getY(),square=point(state.vehicle:getCurrentSquare()),
   accessible=state.vehicle:canAccessContainer(part:getIndex(),player)},
  destination=point(state.crate:getSquare()),current=action(state,current),queue=pending,physical=physical,
  path={targetX=path:getTargetX(),targetY=path:getTargetY(),targetZ=path:getTargetZ(),
   cancelled=path:getIsCancelled(),length=path:getPathLength(),startedMoving=path:hasStartedMoving(),
   movingUsingPathFind=path:isMovingUsingPathFind(),goalLocation=path:isGoalLocation(),goalNone=path:isGoalNone()}}
 if current and current.Type=='LootSorterDeposit'and current.action then
  payload.depositAdmission=read(function()return current:lsDiagnose()end,'diagnosis failed')
 end
 print('[ITEM_RETENTION_TEST] DISTRIBUTE_DIAGNOSTIC '..JSON.encode(payload))
end
return D
