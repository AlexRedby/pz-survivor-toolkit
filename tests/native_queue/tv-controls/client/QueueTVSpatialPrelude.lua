require 'TimedActions/WalkToTimedAction'
local F=require 'QueueTVControls'
local JSON=require 'QueueHealthEvents'
local Observation=require 'QueueTVSpatialObservation'
local T=PZSurvivorToolkit
local M={}
function M.new(state,send)
 local p,s,ids=state.player,state.spatial,state.ids
 local q=ISTimedActionQueue.getTimedActionQueue(p)
 assert(#q.queue==0 and not p:hasTimedActions(),'spatial prelude must start idle')
 local self={phase='hold',startedAt=getTimestampMs(),commands={},children={},acks={},order={},state=state}
 local tracked,byToken={},{}
 local function position()return{x=p:getX(),y=p:getY(),z=p:getZ()}end
 local lifecycle={}
 for _,class in ipairs({ISReadABook,ISRadioAction,ISQueueActionsAction,ISWalkToTimedAction})do
  for _,name in ipairs({'new','start','stop','update','perform','complete','isValid','waitToStart'})do
   lifecycle[#lifecycle+1]={class=class,name=name,callback=class[name]}
  end
 end
 local function unchanged()
  for _,row in ipairs(lifecycle)do assert(row.class[row.name]==row.callback,'spatial prelude changed native lifecycle '..row.name)end
 end
 local function track(action,name,book,collection)
  local row={name=name,type=action.Type,constructorDuration=action.maxTime,started=false,progress=false,starts=0,
   completed=false,cancelled=false}
  collection=collection or self.commands;tracked[action]=row;collection[#collection+1]=row
  if book then row.itemId=action.item:getID()end
  return row
 end
 assert(T.ActionQueueLifecycle.registerObserver('fixture.tv-spatial-prelude',{
  started=function(action)
   local row=tracked[action]
   if not row and byToken[action.toolkitQueueOperation]and action.Type=='ISWalkToTimedAction'then
    local owner=byToken[action.toolkitQueueOperation]
    row={type=action.Type,owner=owner.name,started=false,progress=false,starts=0,duration=action.maxTime,
     destination={x=action.location:getX(),y=action.location:getY(),z=action.location:getZ()}}
    tracked[action]=row;self.children[#self.children+1]=row
   end
   if row then
    row.starts=row.starts+1;assert(row.starts==1,'spatial native action replayed')
    row.started=true;row.startedAt=getTimestampMs();row.startPosition=position()
    if row.cancelled then self.failure='cancelled cold-positive action started';return end
    if row.name then self.order[#self.order+1]=row.name end
   end
  end,
  begin=function(action,step)
   local row=tracked[action]
   if row and row.type=='ISQueueActionsAction'and step=='perform'then
    local count=0
    for _,child in ipairs(q.queue)do
     if child~=action and child.toolkitQueueOperation==action.toolkitQueueOperation and not tracked[child]then
      assert(child.Type=='ISWalkToTimedAction','native walkAdj emitted an unexpected child')
      tracked[child]={type=child.Type,owner=byToken[action.toolkitQueueOperation].name,started=false,progress=false,
       starts=0,duration=child.maxTime,destination={x=child.location:getX(),y=child.location:getY(),z=child.location:getZ()}}
      self.children[#self.children+1]=tracked[child];count=count+1
     elseif child~=action and tracked[child]and tracked[child].owner==byToken[action.toolkitQueueOperation].name then count=count+1 end
    end
    row.preparation.children=count
   end
  end,
  finish=function(action,step,succeeded)
   local row=tracked[action]
   if row and step=='perform'then
    row.completed=succeeded==true
    if row.type=='ISQueueActionsAction'then row.preparation.completed=row.completed end
   end
  end,
 }),'spatial prelude lifecycle observer missing')
 Events.OnServerCommand.Add(function(module,command,args)
  if self.done or not args then return end
  if module=='TVControlsTest'then
   if args.case~=ids.case then return end
   if command=='SpatialVerified'then self.authority=args
   elseif command=='SpatialCleaned'then self.cleanup=args end
  elseif module=='PZSurvivorToolkitActions'and command=='State'and isClient()then
   local found
   for action,row in pairs(tracked)do
    if row.name=='first'or row.name=='last'then
     if args.state=='started'and q.current==action and action.toolkitNativeTransaction==args.transaction
      and action.toolkitNativeKind==args.kind and p:getOnlineID()==args.player
      or row.ack and row.ack.token==args.token then assert(not found,'ambiguous spatial native ACK');found=row end
    end
   end
   if not found then return end
   assert(args.protocol==1 and args.kind=='ISRadioAction'and type(args.token)=='string'and #args.token==36)
   if args.state=='started'then
    assert(not found.ack,'duplicate spatial native start');found.ack={token=args.token,transaction=args.transaction,kind=args.kind,state='started'}
   else assert(found.ack and found.ack.state=='started'and args.state=='completed','spatial setter did not complete')
    assert(found.ack.transaction==args.transaction and found.ack.kind==args.kind);found.ack.state='completed'
   end
   self.acks[#self.acks+1]={name=found.name,kind=args.kind,transaction=args.transaction,token=args.token,state=args.state}
  end
 end)
 self.hold=ISReadABook:new(p,s.hold);track(self.hold,'hold',true);ISTimedActionQueue.add(self.hold)
 function self:observe()
  assert(not self.failure,self.failure)
  unchanged()
  for action,row in pairs(tracked)do
   if q.current==action and action:isStarted()then
    if row.name=='hold'or row.name=='tail'then
     if action.item:getAlreadyReadPages()>ids.spatial[row.name].initial then row.progress=true end
    elseif row.type=='ISWalkToTimedAction'then
     local at=position();if row.startPosition and math.abs(at.x-row.startPosition.x)+math.abs(at.y-row.startPosition.y)>.05 then row.progress=true end
    elseif row.type=='ISRadioAction'and action:getJobDelta()>0 then row.progress=true end
   end
  end
 end
 local function enqueue(name,value,panel,device,collection)
  device=device or s.tv
  local emitted={};local add=ISTimedActionQueue.add
  ISTimedActionQueue.add=function(action)emitted[#emitted+1]=action;return add(action)end
  local ok,problem=pcall(function()T.ActionQueueOperations.run(function()
   panel:onVolumeChange(value*panel.volumeBar:getVolumeSteps())
  end)end)
  ISTimedActionQueue.add=add;assert(ok,problem)
  assert(#emitted==2,'far native RWM producer shape differs')
  local preparation,body=emitted[1],emitted[2]
  assert(T.ActionQueueApproach.isAction(preparation)and body.Type=='ISRadioAction'and body.mode=='SetVolume'
   and body.device==device and body.deviceData==device:getDeviceData()and body.secondaryItem==value and body.maxTime==30)
  local token=body.toolkitQueueOperation;assert(type(token)=='table'and preparation.toolkitQueueOperation==token)
  local request=preparation.toolkitQueueCommand.snapshot
  assert(request.binding.owner==luautils and request.binding.name=='walkAdj'and request.args.n==3
   and request.args[1]==p and request.args[2]==device:getSquare()and request.args[3]==true)
  local prep=track(preparation,name..':approach',false,collection);prep.preparation={sameOperation=true,children=false,completed=false}
  local row=track(body,name,false,collection);row.value=value
  row.preparation=prep.preparation;byToken[token]=row
  return body,prep,preparation
 end
 local function panelFor(device)
  local panel=RWMVolume:new(-1000,-1000,300,100);panel:initialise();panel:instantiate()
  assert(panel:readFromObject(p,device,device:getDeviceData(),'IsoObject'),'native TV panel binding rejected')
  return panel
 end
 function self:poll()
  self:observe();assert(getTimestampMs()-self.startedAt<180000,'spatial prelude timeout '..self.phase)
  if self.phase=='hold'and tracked[self.hold].progress then
   -- The first device-policy query of the session uses a genuinely adjacent
   -- native producer. Cancel both untouched .5 setters after measuring, before
   -- introducing the real movement bank. Reading continues naturally.
   local near=assert(state.nearTV);local nearData=near:getDeviceData();local coldCommands={}
   local function coldWorld()return JSON.encode({nearVolume=nearData:getDeviceVolume(),
    nearOn=nearData:getIsTurnedOn(),spatial=F.spatialSnapshot(state)})end
   local coldBefore=coldWorld();local nativeHold=self.hold.action
   assert(#q.queue==1 and q.current==self.hold and nativeHold,'cold bank lost its native reader hold')
   local nearPanel=panelFor(near)
   local coldFirst,_,coldFirstPrep=enqueue('cold-first',.5,nearPanel,near,coldCommands)
   local coldLast,_,coldLastPrep=enqueue('cold-last',.5,nearPanel,near,coldCommands)
   local coldTiming=Observation.capture(q,coldLast,coldFirst,coldLast,coldWorld,'cold-positive')
   for _,metric in ipairs(coldTiming.metrics)do assert(metric.first.allowed,'cold adjacent native decision denied')end
   assert(T.ActionQueue.cancelOperation(q,coldLast)and T.ActionQueue.cancelOperation(q,coldFirst),'cold native groups could not be removed whole')
   for _,action in ipairs({coldFirstPrep,coldFirst,coldLastPrep,coldLast})do
    local row=tracked[action];row.cancelled=true
    assert(q:indexOf(action)==-1 and not action.action and not row.started and row.starts==0,'cold cancelled group allocated or survived')
   end
   assert(#q.queue==1 and q.queue[1]==self.hold and q.current==self.hold and self.hold.action==nativeHold
    and coldWorld()==coldBefore,'cold bank changed native hold/device facts')
   self.cold={schema=1,status='performed',scope='cold-positive-native-pending-device-decisions',device=ids.tv,
    queueBefore=1,queueAfter=1,queueRestoredToHold=true,sameCurrentNative=true,worldUnchanged=true,
    cancelledTogether=true,commands=coldCommands,timing=coldTiming,noReplay=false}
   self.before=F.spatialSnapshot(state)
   local panel=panelFor(s.tv)
   local first,firstPrep=enqueue('first',.25,panel);local last=enqueue('last',.75,panel)
   self.first,self.last=first,last
   self.tail=ISReadABook:new(p,s.tail);track(self.tail,'tail',true);ISTimedActionQueue.add(self.tail)
   self.timing=Observation.capture(q,last,first,last,function()return JSON.encode(F.spatialSnapshot(state))end,'warm-after-positive-bank')
   local saved=toolkitQueueSpatialNoMovement;toolkitQueueSpatialNoMovement=nil
   local checked,legacy=pcall(T.ActionQueuePolicy.evaluateCancel,q,last,true)
   toolkitQueueSpatialNoMovement=saved;assert(checked,legacy)
   for _,metric in ipairs(self.timing.metrics)do
    if metric.name=='previewMove'or metric.name=='evaluateMove'then assert(not metric.first.allowed,'movement-required move acquired permission')
    else assert(metric.first.allowed==legacy.allowed and metric.first.reason==(legacy.reason or false),'spatial fallback changed legacy removal permission')end
   end
   assert(not T.ActionQueue.move(q,last,first),'movement-required pending movement accepted')
   self.denied={move=true,cancel=not legacy.allowed,cancelLegacyAllowed=legacy.allowed,cancelParity=true,
    cancelApplied=false,queueUnchanged=true}
   assert(q.current==self.hold and not first.action and not last.action and not firstPrep.started)
   self.phase='running'
  elseif self.phase=='running'and #q.queue==0 and not p:hasTimedActions()then
   if not F.verifySpatial(state)then self.quiet=nil;return end
   if isClient()then
    for _,name in ipairs({'first','last'})do local row=tracked[self[name]]
     if not row.ack or row.ack.state~='completed'then return end
    end
   end
   self.quiet=self.quiet or getTimestampMs()
   if getTimestampMs()-self.quiet<1000 then return end
   self.client=assert(F.verifySpatial(state));self.settleMilliseconds=getTimestampMs()-self.quiet
   self.phase='authority';send('SpatialVerify')
  elseif self.phase=='authority'and self.authority then
   assert(self.authority.case==ids.case,'spatial authority case differs')
   self.returnWalk=ISWalkToTimedAction:new(p,assert(getCell():getGridSquare(ids.origin.x,ids.origin.y,ids.origin.z)))
   track(self.returnWalk,'return');ISTimedActionQueue.add(self.returnWalk);self.phase='return'
  elseif self.phase=='return'and #q.queue==0 and not p:hasTimedActions()then
   if not require('QueueEnergyPlacement').at(p,ids.origin)then return end
   self.returnQuiet=self.returnQuiet or getTimestampMs()
   if getTimestampMs()-self.returnQuiet<1000 then return end
   self.phase='cleanup';send('SpatialCleanup')
  elseif self.phase=='cleanup'and self.cleanup then
   assert(self.cleanup.removed==true and self.cleanup.case==ids.case,'spatial cleanup authority missing')
   if s.tv:getObjectIndex()>=0 then return end
   assert(#self.children>=1,'native far approach never expanded walking work')
   local progressed=false;for _,row in ipairs(self.children)do
    assert(row.started and row.completed and row.starts==1 and row.duration==-1,'native spatial child lifecycle missing')
    if row.progress then progressed=true end
   end
   assert(progressed,'native spatial child never moved the actor')
   local expected={'hold','first:approach','first','last:approach','last','tail','return'}
   assert(#self.order==#expected);for i,name in ipairs(expected)do assert(self.order[i]==name,'spatial native start order differs')end
   assert(tracked[self.first].preparation.children>=1,'first native approach emitted no real child')
   for _,action in ipairs({self.hold,self.first,self.last,self.tail,self.returnWalk})do
    local row=tracked[action];assert(row.started and row.progress and row.completed and row.starts==1,'spatial body/tail lifecycle missing '..row.name)
   end
   for _,row in ipairs(self.cold.commands)do assert(row.cancelled and not row.started and row.starts==0 and not row.completed,'cold group replayed')end
   self.cold.noReplay=true;unchanged();self.done=true
   return {schema=1,case=ids.case,scope='native-walking-success-move-denial-and-legacy-cancel-parity',denied=self.denied,
    before=self.before,client=self.client,authority=self.authority,cleanup=self.cleanup,commands=self.commands,
    children=self.children,order=self.order,acks=self.acks,timing=self.timing,coldPositive=self.cold,settleMilliseconds=self.settleMilliseconds,
    returnedToOrigin=true,returnSettleMilliseconds=getTimestampMs()-self.returnQuiet,lifecycleUnchanged=true,
    queueIdle=true,noReplay=true,lateLossQualified=false,lateLossReason='native-device-validity-does-not-bind-object-liveness'}
  end
 end
 function self:authorityReply(name,value)
  if name=='SpatialVerify'then self.authority=value elseif name=='SpatialCleanup'then self.cleanup=value end
 end
 return self
end
return M
