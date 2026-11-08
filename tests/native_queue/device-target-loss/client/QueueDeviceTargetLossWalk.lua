require 'TimedActions/WalkToTimedAction'
local W={}
local function position(player)return{x=player:getX(),y=player:getY(),z=player:getZ()}end
local function tile(square)return{x=square:getX(),y=square:getY(),z=square:getZ()}end
function W.new(state,tracked,captureFunctions,mode)
 local player=state.player;local q=ISTimedActionQueue.getTimedActionQueue(player)
 local class,parent=ISWalkToTimedAction,getmetatable(ISWalkToTimedAction)
 local methods={}
 for _,name in ipairs({'new','begin','start','update','stop','perform','complete','isValid','isValidStart',
  'waitToStart','adjustMaxTime','getDuration','forceStop','forceComplete','forceCancel'})do methods[name]=class[name]end
 for _,name in ipairs({'new','start','update','stop','perform','isValid'})do
  local source=getFilenameOfClosure(methods[name])
  assert(type(source)=='string'and source:gsub('\\','/'):match('([^/]+)$')=='WalkToTimedAction.lua',
   'paid walk native source differs '..name)
 end
 local self={proof={schema=1,producer='native RWM walkAdj',mode=mode,children=0,child=false,
  initialPending=false,mutation=false,observed=false},state=state}
 local child,body,preparation,token,native,tail,tailToken
 local function unchanged()
  assert(ISWalkToTimedAction==class and getmetatable(class)==parent and rawget(class,'__index')==class
   and(not parent or rawget(parent,'__index')==parent),'paid walk native class changed')
  for name,callback in pairs(methods)do assert(class[name]==callback,'paid walk native callback changed '..name)end
  if not child then return end
  assert(getmetatable(child)==class and child.character==player and child.maxTime==-1
   and child.stopOnWalk==false and child.stopOnRun==false and child.allowedWhileDraggingCorpses==true
   and not child.additionalTest and not child.additionalContext and not child.onCompleteFunc and not child.onFailFunc,
   'paid walk native flags/selectors changed')
  assert(child.toolkitQueueOperation==token and body.toolkitQueueOperation==token
   and(not preparation or preparation.toolkitQueueOperation==token)
   and(not token.toolkitCancelled or mode=='native'and native and child.action==native
    and q:indexOf(child)==-1 and not player:getCharacterActions():contains(native)),
   'paid walk operation/lifetime changed')
  if native then assert(child.action==native,'paid walk native handle changed')end
  if tail then assert(tail.toolkitQueueOperation==tailToken and tailToken~=token,'paid walk independent tail token changed')end
 end
 local function bind(action)
  assert(not child and getmetatable(action)==class,'paid walk child replaced or duplicated')
  child=action
  assert(type(token)=='table','paid walk original operation missing')
  local destination=assert(action.location)
  assert(getCell():getGridSquare(destination:getX(),destination:getY(),destination:getZ())==destination,
   'paid walk native destination not live')
  local row={name='setter:walk',type=action.Type,duration=action.maxTime,started=false,progress=false,
   starts=0,performed=false,stopped=false,allocated=false,destination=tile(destination),
   sameOperation=true,nativeCallbacks=true,nativeHandleStable=true,retired=false}
  self.proof.children=1;self.proof.child=row;tracked[action]=row;captureFunctions(action);unchanged()
 end
 function self:produced(emitted)
  assert(#emitted==2,'far native RWM producer must emit preparation/walk and setter')
  body=emitted[2]
  token=body.toolkitQueueOperation;assert(type(token)=='table','paid walk produced operation missing')
  if mode=='native'then bind(emitted[1])else preparation=emitted[1]end
  self.proof.initialPending=true
 end
 function self:tail(action)
  assert(not tail and action.Type=='ISReadABook'and type(action.toolkitQueueOperation)=='table'
   and action.toolkitQueueOperation~=token,'paid walk tail must be a separate native book operation')
  tail=action;tailToken=action.toolkitQueueOperation;self.proof.tailIndependent=true
 end
 function self:started(action)
  if action~=child then return end
  -- Lifecycle.started observes admission before Base.begin allocates Java work.
  unchanged()
  self.proof.child.startPosition=position(player)
 end
 function self:begin(action,step)
  if action==preparation and step=='perform'then
   unchanged()
   local found
   for _,member in ipairs(q.queue)do
    if member~=preparation and member~=body and member.toolkitQueueOperation==body.toolkitQueueOperation then
     assert(not found and getmetatable(member)==class,'unexpected native deferred walking expansion');found=member
    end
   end
   bind(assert(found,'native walkAdj emitted no walking child'))
  elseif action==child and step=='perform'then
   unchanged()
   local row=self.proof.child
   row.arrival=position(player);row.resultSucceeded=action.result==BehaviorResult.Succeeded
   row.atDestination=player:getSquare()==action.location and player:getCurrentSquare()==action.location
  end
 end
 function self:observe()
  unchanged();if not child then return end
  local row=self.proof.child
  if q.current==child and child:isStarted()and row.startPosition then
   if not native then
    native=assert(child.action,'started paid walk has no native handle')
    row.nativeAllocatedAt=getTimestampMs()
   end
   local at=position(player)
   if math.abs(at.x-row.startPosition.x)+math.abs(at.y-row.startPosition.y)>.05 then
    row.progress=true;row.progressAt=row.progressAt or getTimestampMs()
   end
  end
  if row.started and q:indexOf(child)==-1 and native and not player:getCharacterActions():contains(native)then
   row.retired=true;row.retiredAt=row.retiredAt or getTimestampMs()
  end
 end
 function self:ready()
  self:observe()
  return child and q.current==child and self.proof.child.started and self.proof.child.progress
 end
 function self:requestMutation()
  assert(self:ready()and not body.action and not body.started,'paid walk mutation requires active native walk and pending body')
  self.proof.mutation={at=getTimestampMs(),position=position(player),currentNativeSame=child.action==native,
   bodyUnallocated=true,bodyUnstarted=true,sameOperation=true}
 end
 function self:observed()
  assert(self:ready()and not body.action and not body.started,'paid walk ended/body admitted before replicated target loss')
  self.proof.observed={at=getTimestampMs(),position=position(player),currentNativeSame=child.action==native,
   bodyUnallocated=true,bodyUnstarted=true,sameOperation=true}
 end
 function self:safe()
  self:observe();local row=self.proof.child
  return row and row.started and row.progress and row.performed and row.resultSucceeded and row.atDestination
   and row.retired and row.starts==1 and not row.stopped
 end
 return self
end
return W
