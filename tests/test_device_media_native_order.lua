-- Expected native baseline defect, independent of Toolkit/media-mod hooks.
-- Real native Lua classes execute below. DeviceData effects, Java action handles
-- and the IsoGameCharacter update boundary are explicit Lua models, not Java or
-- network execution. This test does not establish any live run's packet order.
if not NativeActionRoot then
 print('Native media completion order SKIP (pass --native-action-root).');return
end

local function setup()
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 f.native('shared/TimedActions/ISDeviceBatteryAction.lua')
 f.native('shared/TimedActions/ISDeviceMediaAction.lua')
 f.native('shared/RadioCom/ISRadioAction.lua')
 assert(not PZSurvivorToolkit.ActionQueue and not PZSurvivorToolkit.ActionQueueMedia
  and not PZSurvivorToolkit.ActionQueueReading and not PZSurvivorToolkit.ActionQueueLifecycle,
  'native baseline must not load Toolkit runtime hooks')
 local player=f.player
 player.class='IsoPlayer'
 player.isLocalPlayer=function()return true end
 player.isDraggingCorpse=function()return false end
 player.isFarming=function()return false end
 player.setIsFarming=function()end
 player.setTimedActionToRetrigger=function()end
 player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
 player.getTimedActionTimeModifier=function()return 1 end
 MoodleType={UNHAPPY='unhappy',DRUNK='drunk'}
 ISLogSystem={logAction=function()end}
 local begun={}
 -- These are the Java-facing APIs called by the real native begin/create.
 -- StartAction/valid/waitToStart/start are represented, not Java-executed.
 LuaTimedActionNew={new=function(action)
  return {table=action,started=false,forceComplete=false,
   isStarted=function(self)return self.started end,
   getJobDelta=function()return 0 end}
 end}
 player.StartAction=function(_,native)
  assert(native.table:isValid(),'control tried to begin an invalid native action')
  begun[#begun+1]=native.table
  native.started=true;native.table:start()
 end
 local function device()
  local data={media=false,index=-1,consumed=0,playing=false}
  local tv={getDeviceData=function()return data end}
  local square={class='IsoGridSquare',getDeviceData=function()return data end}
  data.hasMedia=function(self)return self.media end
  data.getMediaType=function()return 1 end
  data.getIsTurnedOn=function()return true end
  -- Model native DeviceData.addMediaItem's successful exact-tape debit and
  -- installed media. The native Java method and replication are not executed.
  data.addMediaItem=function(self,tape)
   assert(not self.media and tape.container==player.inventory)
   self.media=true;self.index=tape:getRecordedMediaIndex()
   self.consumed=self.consumed+1;tape.container=nil
  end
  data.isPlayingMedia=function(self)return self.playing end
  data.StartPlayMedia=function(self)self.playing=true end
  return data,tv,square
 end
 local function tape()
  return {container=player.inventory,getMediaType=function()return 1 end,
   getRecordedMediaIndex=function()return 16 end}
 end
 local data,tv,square=device()
 local clientTape=tape()
 local insert=ISDeviceMediaAction:new(player,false,clientTape,square)
 local play=ISRadioAction:new('TogglePlayMedia',player,tv)
 local q=f.queue()
 isClient,isServer=function()return true end,function()return false end
 ISTimedActionQueue.add(insert);ISTimedActionQueue.add(play)
 assert(q.current==insert and #q.queue==2 and begun[1]==insert and play.action==nil)
 assert(insert:isValid() and not play:isValid() and play:isValidStart(),
  'native pending play reads live media state; it must not be prevalidated on add')
 local serverData,_,serverSquare=device()
 local serverTape=tape()
 local serverInsert=ISDeviceMediaAction:new(player,false,serverTape,serverSquare)
 isClient,isServer=function()return false end,function()return true end
 assert(serverInsert:isValid() and serverInsert:complete(),
  'real native Lua complete/invoke must accept the modelled server insertion')
 assert(serverData.consumed==1 and serverData.media and serverTape.container==nil)
 isClient,isServer=function()return true end,function()return false end
 local function replicateEffects()
  data.media,data.index=serverData.media,serverData.index
  clientTape.container=nil
 end
 return {q=q,insert=insert,play=play,begun=begun,data=data,
  serverData=serverData,replicateEffects=replicateEffects}
end

local function modeledJavaFrame(s,doneReceived)
 -- IsoGameCharacter.updateInternal snapshots valid() before calling the native
 -- LuaTimedActionNew.update that translates ActionManager.isDone into forceComplete.
 -- Here we model that Java order explicitly, while calling actual Lua stop/perform.
 local current=s.q.current
 local valid=current:isValid()
 if valid and not current.action.forceComplete then
  current:update()
  if doneReceived then current.action.forceComplete=true end
 end
 if current.action.forceComplete then
  current:perform();return 'performed'
 elseif not valid then
  current:stop();return 'stopped'
 end
 return 'waiting'
end

for _,doneReceived in ipairs({false,true})do
 local s=setup()
 s.replicateEffects()
 assert(not s.insert:isValid() and s.play:isValid(),
  'successful insertion invalidates itself, while the ordinary pending play becomes valid')
 assert(modeledJavaFrame(s,doneReceived)=='stopped',
  'native validity can stop insertion before update translates even a received Done')
 assert(s.q.current==nil and #s.q.queue==0 and s.play.action==nil and #s.begun==1,
  'actual native Lua stop/reset must discard pending play without beginning it')
 assert(s.data.media and not s.data.playing and s.serverData.consumed==1,
  'queue reset must not undo or replay the successful server insertion')
end

do
 local s=setup()
 -- Narrow completion control: model a Done already translated to forceComplete,
 -- then expose the insertion effects. This verifies the native completion branch;
 -- it does not claim to reproduce whole-frame scheduling or Done-first packets.
 s.insert.action.forceComplete=true
 s.replicateEffects()
 assert(not s.insert:isValid() and s.play:isValid())
 assert(modeledJavaFrame(s,false)=='performed')
 assert(s.q.current==s.play and #s.q.queue==1 and s.q.queue[1]==s.play
  and s.begun[2]==s.play and s.play:isStarted(),
  'actual native Lua perform/onCompleted must preserve and begin the valid pending play')
 s.play:perform()
 assert(s.data.playing and s.q.current==nil and #s.q.queue==0 and s.serverData.consumed==1,
  'ordinary native play callback must play the inserted media without a second tape debit')
end

print('Native media order baseline reproduced: native Lua only; modeled Java validity-before-Done resets pending play; pending play itself is valid; translated-Done completion control continues. Java/network/DeviceData effects are modeled, not executed.')
