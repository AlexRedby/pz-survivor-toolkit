assert(NativeActionRoot,'device integration requires --game or --native-action-root')
-- Real native constructors/queue and real Toolkit owners below. Only the Java
-- identity/geometry bridges and engine allocation/phase delivery are doubles.
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
for _,path in ipairs({'shared/RadioCom/ISRadioAction.lua','client/TimedActions/WalkToTimedAction.lua',
 'shared/TimedActions/ISDeviceBatteryAction.lua','shared/TimedActions/ISDeviceMediaAction.lua'})do f.native(path)end
local function text(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local value=file:read('*a');file:close();return value:gsub('\r','')
end
local function reader(value)
 local position=1
 return {close=function()end,readLine=function()
  if position>#value then return end
  local last=value:find('\n',position,true)or #value+1
  local line=value:sub(position,last-1);position=last+1;return line
 end}
end
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined+1 end
getGameFilesInput=function(path)return reader(text(NativeActionRoot..'/'..path:gsub('^media/lua/','')))end
getModFileReader=function(id,path)assert(id=='PZSurvivorToolkit');return reader(text(ProjectRoot..'/PZSurvivorToolkit/42/'..path))end
isClient,isServer=function()return false end,function()return false end
getActivatedMods=function()return {contains=function()return false end}end
getTimestampMs=function()return 100 end
local actor=f.player;actor.class='IsoPlayer'
actor.isLocalPlayer=function()return true end;actor.isDraggingCorpse=function()return false end
getSpecificPlayer=function(index)if index==0 then return actor end end
actor.x,actor.y=.5,.5
actor.getX=function()return actor.x end;actor.getY=function()return actor.y end
actor.getSquare=function()return actor.square end;actor.getCurrentSquare=actor.getSquare
actor.setTimedActionToRetrigger=function()end;actor.setIsFarming=function()end
actor.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
actor.getTimedActionTimeModifier=function()return 1 end
actor.getBodyDamage=function()return {getBodyPart=function()return {getPain=function()return 0 end}end}end
MoodleType={UNHAPPY=1,DRUNK=2}
BodyPartType={Hand_L=1,ForeArm_R=2,ToIndex=function(value)return value end,FromIndex=function(value)return value end}
ISLogSystem={logAction=function()end};DebugType={Action={warn=function(_,message)error(message)end}}
local allocations={}
LuaTimedActionNew={new=function(action)
 local native={owner=action,started=false}
 native.isStarted=function(self)return self.started end
 native.hasStalled=function()return false end
 native.getJobDelta=function()return 0 end
 native.forceComplete=function(self)self.forced=true end
 native.reset=function()end
 native.forceStop=function()error('unexpected native cancellation')end
 allocations[#allocations+1]=native;return native
end}
actor.StartAction=function(_,native)native.started=true end
actor.getCharacterActions=function()return {contains=function(_,native)return native~=nil and not native.removed end}end
local function square(x)
 return {class='IsoGridSquare',x=x,getX=function()return x end,getY=function()return 0 end,getZ=function()return 0 end,
  has=function()return false end,canReachTo=function()return true end}
end
local origin,target,moved=square(0),square(1),square(4);actor.square=origin
getCell=function()return {getGridSquare=function(_,x)if x==0 then return origin elseif x==1 then return target else return moved end end}end
IsoFlagType={collideW='collideW',collideN='collideN'}
luautils={}
local utilities=text(NativeActionRoot..'/shared/luautils.lua')
assert(loadstring(assert(utilities:match('(function luautils.walkAdj%(.-\nend)'))..'\n'..
 assert(utilities:match('(luautils.getCorrectSquareForWall = function.-\nend)')),
 '@'..NativeActionRoot..'/shared/luautils.lua'))()
AdjacentFreeTileFinder={Find=function()error('adjacent live control must not pathfind')end}
local function noMovement(character,destination)return character==actor and destination==target end
local function spatialMatches(callback)return callback==noMovement end
toolkitQueueSpatialNoMovement,toolkitQueueSpatialApiMatches=noMovement,spatialMatches
local anchors={};local captures,reads=0,0
local function deviceTarget(device,data,anchor,route)
 reads=reads+1
 local saved=anchor and anchors[anchor]
 if anchor and not saved then return end
 device=device or saved and saved.device or data and data.parent
 if not device or not data or data.class~='DeviceData'or(device.class~='IsoTelevision'and device.class~='IsoRadio')then return end
 if saved and(saved.device~=device or saved.data~=data)then return end
 if route and route~=(saved and saved.square or device.square)then return end
 if saved then return device.square==saved.square and device.data==data and data.parent==device and device.present end
 if not device.present or not device.square or device.data~=data or data.parent~=device then return end
 local key={};anchors[key]={device=device,data=data,square=device.square};captures=captures+1;return key
end
local function deviceMatches(callback)return callback==deviceTarget end
toolkitQueueDeviceTarget,toolkitQueueDeviceApiMatches=deviceTarget,deviceMatches
getClassSimpleName=function(value)
 if value==noMovement or value==spatialMatches or value==deviceTarget or value==deviceMatches then return 'LuaJavaInvoker'end
 return type(value)=='table'and value.class or type(value)=='function'and'LuaClosure'or nil
end
-- Keep the support fixture's unrelated optional integrations absent, but load
-- every owner of this admission path through its actual require dependency.
local priorRequire=require
local names={ActionQueueOperations=true,ActionQueueDefinitions=true,ActionQueuePolicy=true,ActionQueueApproach=true,
 ActionQueueMedia=true,ActionQueueLifecycle=true,ActionQueueAcknowledgements=true,ActionQueueLabels=true,
 ActionQueueDeviceTargets=true,ActionQueueSettlement=true}
require=function(name)
 local short=name:match('^PZSurvivorToolkit/(.*)$')
 if names[short]then return PZSurvivorToolkit[short]or f.project(short)end
 return priorRequire(name)
end
local ops=require('PZSurvivorToolkit/ActionQueueOperations')
require('PZSurvivorToolkit/ActionQueueDefinitions')
local approach=require('PZSurvivorToolkit/ActionQueueApproach');assert(approach.install())
local policy=require('PZSurvivorToolkit/ActionQueuePolicy')
local media=require('PZSurvivorToolkit/ActionQueueMedia')
f.project('ActionQueue')
local toolkit=PZSurvivorToolkit
local lifecycle,settlement,module=toolkit.ActionQueueLifecycle,toolkit.ActionQueueSettlement,toolkit.ActionQueueDeviceTargets
assert(media.isInstalled()and module.install(),'real Queue bottom must install Media and Device owners')
local observed={}
assert(lifecycle.registerObserver('device-full-core-test',{
 started=function(action)observed[action]=(observed[action]or 0)+1 end,
 begin=function()end,finish=function()end,settled=function()end}))
local effects=0
local function device(kind)
 local value={class=kind,square=target,present=true}
 local data={class='DeviceData',parent=value,volume=.5};value.data=data
 value.getDeviceData=function()return data end;value.getSquare=function()return value.square end
 value.getObjectIndex=function()return value.present and 0 or -1 end
 data.getParent=function()return value end;data.getIsTurnedOn=function()return true end
 data.getPower=function()return 1 end;data.getDeviceVolume=function()return data.volume end
 data.isIsoDevice=function()return true end;data.isVehicleDevice=function()return false end
 data.getIsBatteryPowered=function()return false end;data.canBePoweredHere=function()return true end
 data.setDeviceVolume=function(_,volume)effects=effects+1;data.volume=volume end
 return value,data
end
local function neutral()
 local action=ISBaseTimedAction:new(actor);action.maxTime=1;return action
end
local function perform(action)
 -- Java normally delivers these boundaries around the unchanged native Lua
 -- callback. Never call Module/Kernel admission methods directly in this test.
 action:start()
 lifecycle.begin(action,'perform')
 local ok,result=pcall(function()return action:perform()end)
 lifecycle.finish(action,'perform',ok and result~=false)
 if not ok then error(result,0)end
 lifecycle.begin(action,'complete')
 local completeOk,completeResult=pcall(function()if action.complete then return action:complete()end end)
 lifecycle.finish(action,'complete',completeOk and completeResult~=false)
 if not completeOk then error(completeResult,0)end
 action.action.removed=true
 ISTimedActionQueue.queues[actor]:tick()
end
local cases=0
for _,kind in ipairs({'IsoTelevision','IsoRadio'})do
 for _,loss in ipairs({'live','remove','move'})do
  effects=0
  local object,data=device(kind)
  local queue=ISTimedActionQueue:new(actor)
  local hold=neutral();ISTimedActionQueue.add(hold)
  assert(queue.current==hold and hold.action and observed[hold]==1,'real initial add/begin failed')
  local body,prep
  ops.run(function()
   assert(luautils.walkAdj(actor,target,true))
   body=ISRadioAction:new('SetVolume',actor,object,.75);ISTimedActionQueue.add(body)
  end)
  prep=queue.queue[2]
  local tail=neutral();ISTimedActionQueue.add(tail)
  assert(#queue.queue==4 and queue.queue[3]==body and approach.isAction(prep))
  assert(prep.toolkitQueueOperation==body.toolkitQueueOperation and body.toolkitQueueOperation~=tail.toolkitQueueOperation)
  assert(policy.matchesNative(body),'actual Policy rejected native setter')
  assert(settlement.deviceStep(body)and settlement.deviceStep(prep),'real enqueue failed to bind device/preparation')
  assert(not body.action and not prep.action and not observed[body]and not observed[prep])
  if loss=='remove'then object.square=nil;object.present=false elseif loss=='move'then object.square=moved end
  perform(hold)
  if loss=='live'then
   assert(queue.current==prep and observed[prep]==1 and prep.action,'live preparation was removed: current='..
    tostring(queue.current and queue.current.Type)..' observed='..tostring(observed[prep])..' native='..tostring(prep.action)..' count='..#queue.queue)
   perform(prep)
   assert(queue.current==body and body.action and observed[body]==1,'live body did not reach real begin')
   perform(body)
   assert(data.volume==.75 and effects==1,'live native effect must occur exactly once')
  else
   assert(not prep.action and not body.action and not observed[prep]and not observed[body],
    'lost target crossed native begin/observer boundary')
   assert(data.volume==.5 and effects==0,'lost pending target produced a native effect')
   assert(not body.toolkitQueueOperation.toolkitCancelled,'refusal canceled the source token')
  end
  assert(queue.current==tail and #queue.queue==1 and queue.queue[1]==tail and observed[tail]==1,
   'real onCompleted lost or failed to admit the independent tail')
  perform(tail);assert(queue.current==nil and #queue.queue==0,'real tail failed to complete')
  cases=cases+1
 end
end
assert(captures==cases and reads>captures,'actual enqueue must capture once per native body')
if TestCoverage then TestCoverage('source-contract','passed','Full core native device admission: '..cases..' real-owner enqueue/completion cases; JVM/geometry/engine bridges doubled.')end
print('Device full core integration: '..cases..' native queue/real owner cases passed.')
