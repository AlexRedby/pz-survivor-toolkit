if not NativeActionRoot then print('Animal terminal stops SKIP (pass --native-action-root).');return end
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function exists(path)
 if NativeFileExists then return NativeFileExists(path)end
 local file=io.open(path);if file then file:close();return true end;return false
end
local function setup(client,options)
 options=options or{}
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 f.native('shared/TimedActions/Animals/ISPetAnimal.lua')
 local nativePet={};for key,value in pairs(ISPetAnimal)do if type(value)=='function'then nativePet[key]=value end end
 local nativeBaseNew=ISBaseTimedAction.new
 local now,enabled,receive=1000,true,nil
 local callbacks,live,starts={},{},{}
 local effects,stopCalls,stopFinishes=0,0,0
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
 getGameFilesInput=function(path)
  local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
  if options.source==path then text=text..'\n-- changed source\n'end
  local position=1
  return {close=function()end,readLine=function()
   if position>#text then return end
   local stop=text:find('\n',position,true)or #text+1
   local line=text:sub(position,stop-1);position=stop+1;return line
  end}
 end
 Events.OnTick.Add=function(callback)callbacks[#callbacks+1]=callback end
 Events.OnServerCommand.Add=function(callback)receive=callback end
 Events.OnMainMenuEnter={Add=function()end}
 isClient=function()return client==true end;isServer=function()return false end
 getTimestampMs=function()return now end
 getCore=function()return {getGameMode=function()return 'Sandbox'end}end
 PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
 local player=f.player;player.class='IsoPlayer';player.variables={}
 player.getOnlineID=function()return 101 end
 player.isLocalPlayer=function()return true end
 player.isAsleep=function()return player.asleep==true end
 player.isDead=function()return player.dead==true end
 player.isPlayerMoving=function()return player.moving==true end
 player.pressedMovement=function()return player.movement==true end
 player.pressedCancelAction=function()return player.cancelPressed==true end
 player.isRunning=function()return player.running==true end
 player.isSprinting=function()return player.sprinting==true end
 player.isAiming=function()return player.aiming==true end
 player.getVehicle=function()return player.vehicle end
 player.isClimbing=function()return false end
 player.isSittingOnFurniture=function()return false end
 player.setVariable=function(_,key,value)player.variables[key]=value end
 player.getVariableBoolean=function(_,key)return player.variables[key]==true end
 player.setIsFarming=function()end
 player.setIsAiming=function(_,value)player.aiming=value end
 player.faceThisObject=function()end;player.shouldBeTurning=function()return false end
 player.setTimedActionToRetrigger=function()end;player.getTimedActionToRetrigger=function()end
 player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
 player.getTimedActionTimeModifier=function()return 1 end
 player.getBodyDamage=function()return {getBodyPart=function()return {getPain=function()return 0 end}end}end
 player.getCharacterActions=function()return {contains=function(_,native)return live[native]==true end}end
 player.StartAction=function(_,native)live[native]=true;native.started=true;starts[native.owner]=(starts[native.owner]or 0)+1 end
 player.square={DistTo=function(_,square)assert(square,'native distance requires an animal square');return player.distance or 1 end}
 player.getSquare=function()return player.square end
 MoodleType={UNHAPPY='unhappy',DRUNK='drunk'}
 BodyPartType={Hand_L=0,ForeArm_R=0,ToIndex=function(value)return value end,FromIndex=function(value)return value end}
 ISLogSystem={logAction=function()end};DebugType={Action={warn=function()end}}
 LuaTimedActionNew={new=function(action)
  local native={owner=action,forceStops=0}
  function native:getTable()return self.owner end
  function native:isStarted()return self.started==true end
  function native:finished()return self.done==true end
  function native:isForceComplete()return self.forcedComplete==true end
  function native:forceStop()self.forceStops=self.forceStops+1;self.stopping=true end
  function native:hasStalled()return false end
  function native:getJobDelta()return .5 end
  function native:setOverrideHandModelsObject()end
  return native
 end}
 forceDropHeavyItems=function()end
 local animal={class='IsoAnimal',health=100,variables={},blocked=false}
 animal.getHealth=function()return animal.health end
 animal.getSquare=function()return animal.square end
 animal.square={}
 animal.getData=function()return {getMaxSize=function()return 1 end,getMinSize=function()return 0 end,getSize=function()return .5 end}end
 animal.getBehavior=function()return {setBlockMovement=function(_,value)animal.blocked=value end}end
 animal.faceThisObject=function()end;animal.hasGeneticDisorder=function()return false end
 animal.isBaby=function()return false end;animal.getAnimalType=function()return 'hen'end
 animal.setVariable=function(_,key,value)animal.variables[key]=value end
 animal.clearVariable=function(_,key)animal.variables[key]=nil end
 animal.petAnimal=function(_,actor)assert(actor==player);effects=effects+1 end
 local fixtureRequire=require
 require=function(name)
  if name=='PZSurvivorToolkit/ActionQueueAnimalStops'then
   local path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua'
   if not options.omitModule and exists(path)then return assert(loadfile(path))()end
  end
  if name=='PZSurvivorToolkit/ActionQueueLifecycle'then return PZSurvivorToolkit.ActionQueueLifecycle end
  if name=='PZSurvivorToolkit/ActionQueueAcknowledgements'then return PZSurvivorToolkit.ActionQueueAcknowledgements end
  return fixtureRequire(name)
 end
 f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');f.project('ActionQueueLabels')
 local policy=f.project('ActionQueuePolicy')
 if options.preinstalled then options.preinstalled(f,player,animal)end
 local api=f.project('ActionQueue')
 local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
 local ack=PZSurvivorToolkit.ActionQueueAcknowledgements
 assert(lifecycle.registerObserver('fixture.pet-stop',{begin=function(_,step)if step=='stop'then stopCalls=stopCalls+1 end end,
  finish=function(_,step,succeeded)if step=='stop'and succeeded then stopFinishes=stopFinishes+1 end end}))
 local body=ISPetAnimal:new(player,animal)
 body.toolkitQueueOperation={}
 local tail=f.action(ISReadABook,{item=f.item('Base.BookFirstAid1'),maxTime=100,ignoreHandsWounds=true})
 local queue=f.queue(body,tail)
 body:begin();body:start()
 assert(body.maxTime==400 and body.useProgressBar==false,'native pet duration/constructor flags changed')
 if client then body.toolkitNativeTransaction=7;body.toolkitNativeKind='ISPetAnimal'end
 local function receipt(state,overrides)
  assert(client and receive,'real ACK receiver unavailable')
  local args={protocol=1,player=101,transaction=7,kind='ISPetAnimal',
   token='11111111-1111-4111-8111-111111111111',state=state}
  for key,value in pairs(overrides or{})do args[key]=value end
  receive('PZSurvivorToolkitActions','State',args)
 end
 local function engineStop()
  assert(body.action.stopping,'native forceStop was not requested')
  body:stop()
 end
 local function remove()live[body.action]=nil end
 return {f=f,api=api,policy=policy,lifecycle=lifecycle,ack=ack,player=player,animal=animal,body=body,tail=tail,queue=queue,
  native=nativePet,baseNew=nativeBaseNew,receipt=receipt,engineStop=engineStop,remove=remove,
  tick=function()queue:tick()end,sweep=function()for _,callback in ipairs(callbacks)do callback()end end,
  enabled=function(value)enabled=value end,advance=function(value)now=now+value end,
  counts=function()return effects,stopCalls,stopFinishes,starts[tail]or 0 end}
end

-- Native control: omitting only the proposed adapter reproduces the lost tail.
do
 local s=setup(false,{omitModule=true})
 s.body:animEvent('pettingFinished');s.engineStop();s.remove()
 local effects,_,_,tails=s.counts()
 assert(effects==1 and tails==0 and #s.queue.queue==0 and s.queue.current==nil,
  'source-native pet stop no longer reproduces the independent-tail reset')
end
local function natural(s)
 assert(ISPetAnimal.new==s.native.new and ISPetAnimal.complete==s.native.complete,
  'adapter replaced constructor wire schema or native completion')
 assert(not s.policy.inspect(s.body)and not s.api.cancel(s.queue,s.body)
  and not s.api.cancelOperation(s.queue,s.body),'terminal adapter granted editing rights')
 s.body:animEvent('pettingFinished')
 assert(s.body.action.forceStops==1,'natural event did not retain native forceStop')
 s.engineStop()
 local effects,stops,finishes,tails=s.counts()
 assert(effects==1 and stops==1 and finishes==1 and tails==0,
  'native natural event/stop replayed gameplay or started the independent tail early')
 assert(#s.queue.queue==2 and s.queue.current==s.body and s.queue.toolkitCancel==s.body,
  'successful native pet stop discarded the independent tail')
 assert(s.player.variables.petanimal==false and s.animal.variables.idleAction==nil and not s.animal.blocked,
  'native pet stop cleanup did not run')
end
local function advanced(s)
 local effects,stops,finishes,tails=s.counts()
 assert(s.queue.current==s.tail and #s.queue.queue==1 and tails==1,
  'exact settled natural pet stop did not release one independent tail')
 assert(effects==1 and stops==1 and finishes==1,'advancement replayed native pet/stop callbacks')
 assert(not s.queue.toolkitCancel and not s.queue.toolkitOutcomeWait and not s.queue.toolkitStopIntent,
  'settled natural pet retained stop capability')
end
-- SP preserves only this natural stop; actual native removal owns advancement.
do
 local s=setup(false);natural(s)
 s.tick();assert(s.queue.current==s.body and select(4,s.counts())==0,'tail preceded native removal')
 s.remove();s.tick();advanced(s)
 s.tick();assert(select(4,s.counts())==1,'settled stop advanced its independent tail twice')
end
-- Host source test models only client Lua and real sealed receipts, not server pet effects.
for _,terminal in ipairs({'canceled','completed'})do
 for _,lateStart in ipairs({false,true})do
  local s=setup(true)
  if not lateStart then s.receipt('started')end
  natural(s);s.remove();s.tick()
  assert(s.queue.current==s.body and select(4,s.counts())==0,'tail preceded exact authoritative outcome')
  if lateStart then
   s.receipt(terminal);s.tick()
   assert(s.queue.current==s.body,'terminal without Started invented a bound acknowledgement')
   s.receipt('started');s.tick()
  end
  s.advance(1000);s.tick();assert(s.queue.current==s.body,'Started alone released the independent tail')
  s.receipt(terminal);s.tick();advanced(s)
  s.receipt(terminal);s.tick();assert(select(4,s.counts())==1,'duplicate receipt advanced the tail again')
 end
end
print('PASS actual SP/client pet terminal callback, unchanged duration/effects, native cleanup/removal and delayed exact ACK gates')

local function nativeReset(s,invoke,effects)
 invoke(s)
 if s.body.action.stopping then s.engineStop()end
 assert(#s.queue.queue==0 and s.queue.current==nil and select(4,s.counts())==0,
  'unadmitted stop retained the independent tail')
 assert(select(1,s.counts())==effects,'adapter changed original native event gameplay')
end
nativeReset(setup(false),function(s)s.body:forceStop()end,0)
nativeReset(setup(false),function(s)s.body:stop()end,0)
do
 local s=setup(false);s.body:animEvent('unrelated')
 assert(not s.body.action.stopping and not s.queue.toolkitCancel and select(1,s.counts())==0,
  'unrelated event created a terminal stop')
 nativeReset(s,function(value)value.body:forceStop()end,0)
end
for _,mode in ipairs({'disabled','animal-dead','animal-invalid','actor-dead','actor-asleep','cancel-input','movement',
 'pressed-movement','run','sprint','not-started','finished','force-complete','removed-before-event','foreign-native',
 'animal-unloaded','actor-unloaded','custom-callback'})do
 local s=setup(false)
 if mode=='disabled'then s.enabled(false)
 elseif mode=='animal-dead'then s.animal.health=0
 elseif mode=='animal-invalid'then s.player.distance=3
 elseif mode=='actor-dead'then s.player.dead=true
 elseif mode=='actor-asleep'then s.player.asleep=true
 elseif mode=='cancel-input'then s.player.cancelPressed=true
 elseif mode=='movement'then s.player.moving=true
 elseif mode=='pressed-movement'then s.player.movement=true
 elseif mode=='run'then s.player.running=true
 elseif mode=='sprint'then s.player.sprinting=true
 elseif mode=='not-started'then s.body.action.started=false
 elseif mode=='finished'then s.body.action.done=true
 elseif mode=='force-complete'then s.body.action.forcedComplete=true
 elseif mode=='removed-before-event'then
  s.remove();assert(s.body.action:isStarted()and not s.player:getCharacterActions():contains(s.body.action),
   'removed native episode fixture lost the stale-started reproduction')
 elseif mode=='foreign-native'then
  local otherOwner=s.f.action(ISReadABook,{item=s.f.item('Base.BookFirstAid2')})
  local foreign=LuaTimedActionNew.new(otherOwner,s.player);s.player:StartAction(foreign);s.body.action=foreign
  assert(foreign:isStarted()and foreign:getTable()~=s.body and s.player:getCharacterActions():contains(foreign),
   'foreign native-owner fixture did not retain actual membership')
 elseif mode=='animal-unloaded'then s.animal.square=nil
 elseif mode=='actor-unloaded'then s.player.square=nil
 else s.body.onCompleteFunc=function()error('custom callback must never run')end end
 nativeReset(s,function(value)value.body:animEvent('pettingFinished')end,1)
end
print('PASS direct stops, unrelated events, disabled queue, invalid actors/animals and explicit native input remain native resets')

-- Runtime method changes cannot borrow already-installed source authority.
for _,mode in ipairs({'class-new','class-forceStop','class-stop','class-helper','class-replaced','base-new','base-stop','instance-callback'})do
 local s=setup(false)
 if mode=='class-new'then ISPetAnimal.new=function()end
 elseif mode=='class-forceStop'then local previous=ISPetAnimal.forceStop;ISPetAnimal.forceStop=function(...)return previous(...)end
 elseif mode=='class-stop'then local previous=ISPetAnimal.stop;ISPetAnimal.stop=function(...)return previous(...)end
 elseif mode=='class-helper'then ISPetAnimal.unreviewed=function()end
 elseif mode=='class-replaced'then ISPetAnimal={}
 elseif mode=='base-new'then ISBaseTimedAction.new=function()end
 elseif mode=='base-stop'then local previous=ISBaseTimedAction.stop;ISBaseTimedAction.stop=function(...)return previous(...)end
 else s.body.stop=function(action)return s.native.stop(action)end end
 nativeReset(s,function(value)value.body:animEvent('pettingFinished')end,1)
end
-- Proof failure before installation must preserve even an already-installed foreign effect.
for _,mode in ipairs({'base-new','base-stop','class-stop','class-forceStop','class-helper','base-source','class-source'})do
 local options={}
 if mode=='base-source'then options.source='media/lua/shared/TimedActions/ISBaseTimedAction.lua'
 elseif mode=='class-source'then options.source='media/lua/shared/TimedActions/Animals/ISPetAnimal.lua'
 else options.preinstalled=function(_,player)
  if mode=='base-new'then
   local previous=ISBaseTimedAction.new;ISBaseTimedAction.new=function(self,actor)
    player.foreignConstructorEffects=(player.foreignConstructorEffects or 0)+1;return previous(self,actor)
   end
  elseif mode=='base-stop'then
   local previous=ISBaseTimedAction.stop;ISBaseTimedAction.stop=function(action)
    player.foreignStopEffects=(player.foreignStopEffects or 0)+1;return previous(action)
   end
  elseif mode=='class-helper'then ISPetAnimal.unreviewed=function()end
  else
   local name=mode=='class-stop'and 'stop'or 'forceStop';local previous=ISPetAnimal[name]
   ISPetAnimal[name]=function(...)return previous(...)end
  end
 end end
 local s=setup(false,options)
 nativeReset(s,function(value)value.body:animEvent('pettingFinished')end,1)
 if mode=='base-new'then assert(s.player.foreignConstructorEffects==2,'actual foreign constructor effect was not exercised')end
 if mode=='base-stop'then assert(s.player.foreignStopEffects==1,'adapter suppressed an actual foreign base.stop predecessor')end
end
print('PASS changed class/base/instance callbacks, source pins and actual preinstalled constructor/stop effects fail closed')

-- A granted stop is one current episode, not permission to finish historical work.
for _,mode in ipairs({'native','generation','settings','actor','animal','queue','input','class-callback','base-stop','bridge-owner','token','list','duplicate-stop'})do
 local s=setup(false);natural(s)
 if mode=='native'then
  local replacement={};for key,value in pairs(s.body.action)do replacement[key]=value end;s.body.action=replacement
 elseif mode=='generation'then s.queue.toolkitOperationGeneration=(s.queue.toolkitOperationGeneration or 0)+1
 elseif mode=='settings'then s.enabled(false)
 elseif mode=='actor'then s.player.dead=true
 elseif mode=='animal'then s.body.animal={clearVariable=function()end,getBehavior=function()return {setBlockMovement=function()end}end}
 elseif mode=='queue'then ISTimedActionQueue.queues[s.player]=s.f.queue(s.tail)
 elseif mode=='input'then s.player.cancelPressed=true
 elseif mode=='class-callback'then ISPetAnimal.complete=function()error('changed complete must not run')end
 elseif mode=='base-stop'then local previous=ISBaseTimedAction.stop;ISBaseTimedAction.stop=function(...)return previous(...)end
 elseif mode=='bridge-owner'then PZSurvivorToolkit.ActionQueue={}
 elseif mode=='token'then s.body.toolkitQueueOperation.toolkitCancelled=true
 elseif mode=='list'then s.queue.queue={s.body,s.tail}
 else s.body:stop()end
 if mode=='duplicate-stop'then
  assert(#s.queue.queue==0,'repeated native stop reused one-shot terminal capability')
 elseif mode=='queue'then
  s.sweep();s.queue:tick()
  assert(select(4,s.counts())==0 and s.queue.current~=s.tail,'replaced queue advanced historical tail')
 else
  s.remove();s.tick()
  assert(#s.queue.queue==0 and select(4,s.counts())==0,'stale terminal capability advanced independent work: '..mode)
 end
end
-- Duplicate original events stay original callbacks; they never create another advancement.
do
 local s=setup(false);s.body:animEvent('pettingFinished');s.body:animEvent('pettingFinished');s.engineStop();s.remove();s.tick()
 local effects,stops,finishes,tails=s.counts()
 assert(effects==2 and stops==1 and finishes==1 and tails==1 and s.queue.current==s.tail,
  'duplicate native event changed gameplay or reused terminal advancement')
end
-- A missing or revoked authority may not be treated as a successful result.
for _,mode in ipairs({'no-started','no-terminal','foreign-terminal','reset'})do
 local s=setup(true)
 if mode~='no-started'then s.receipt('started')end
 natural(s);s.remove()
 if mode=='foreign-terminal'then
  -- A foreign identity is delivered through the real receiver, never a fabricated ACK object.
  s.receipt('completed',{token='22222222-2222-4222-8222-222222222222'})
 elseif mode=='reset'then s.ack.reset(s.queue)end
 s.tick();assert(select(4,s.counts())==0,'missing/foreign/revoked receipt released the tail')
 s.advance(30001);s.tick()
 assert(#s.queue.queue==0 and select(4,s.counts())==0,'expired native outcome invented success')
end
print('PASS stale episode/settings/queue/input/duplicate-stop revocation and bounded missing/foreign ACK failures')
