-- Read-only witnesses around real native methods. Never synthesize animation events,
-- shorten timers, call exerciseRepeat directly, or award XP.
require 'TimedActions/ISFitnessAction'
local O={records={},active=nil,violations={},epoch=0}
local previousSamples={}
local postStopAction
local function clock()return getGameTime():getCalender():getTimeInMillis()end
O.clock=clock
local function durationClock()
 local time=getGameTime();local hour=time:getTimeOfDay()
 return (time:getNightsSurvived()*24+(hour>=7 and hour-7 or hour+17))*3600000
end
O.durationClock=durationClock
local function durationFrame()
 local time=getGameTime()
 return time:getGameWorldSecondsSinceLastUpdate()*1000,time:getRealworldSecondsSinceLastUpdate()*1000
end
function O.clinical(player)
 local fit=player:getFitness();local xp=player:getXp();local regularity,stiffness,timers={},{},{}
 for _,kind in ipairs({'squats','pushups','bicepscurl','burpees'})do regularity[kind]=fit:getRegularity(kind)end
 for _,part in ipairs({'legs','arms','chest','abs'})do
  stiffness[part]=fit:getCurrentExeStiffnessInc(part);timers[part]=fit:getCurrentExeStiffnessTimer(part)
 end
 return {fitnessXP=xp:getXP(Perks.Fitness),strengthXP=xp:getXP(Perks.Strength),endurance=player:getStats():get(CharacterStat.ENDURANCE),
  regularity=regularity,stiffness=stiffness,timers=timers}
end
-- Snapshot predicates at the real stop boundary. A server stop is authoritative
-- cleanup/effect evidence; its predicates alone do not identify the client's cause.
function O.stopState(action)
 local player=action.character
 return {clinical=O.clinical(player),enduranceMoodle=player:getMoodles():getMoodleLevel(MoodleType.ENDURANCE),
  threshold=ISFitnessUI and ISFitnessUI.enduranceLevelThreshold or false,
  pressedMovement=player:pressedMovement(true),moving=player:isPlayerMoving(),aiming=player:isAiming(),
  climbing=player:isClimbing(),sittingFurniture=player:isSittingOnFurniture(),vehicle=player:getVehicle()~=nil,
  dead=player:isDead(),asleep=player:isAsleep(),pressedCancel=player:pressedCancelAction(),
  exerciseStarted=player:getVariableBoolean('ExerciseStarted'),exerciseEnded=player:getVariableBoolean('ExerciseEnded'),
  calendarMS=clock(),durationMS=durationClock(),started=action:isStarted(),type=action.Type,
  exercise=action.exeDataType,minutes=action.timeToExe}
end
function O.noteStop(action)
 local state=O.stopState(action)
 local row=action.fitnessWitness
 if O.case=='late-exhaustion'and action.character==O.player and row and not row.stopEntry then
  row.stopEntry=state;row.postStopXP={baseline=state.clinical,events={}};postStopAction=action
 end
 return state
end
function O.reset(player,id)
 assert(not O.active and not player:getFitness():getCurrentExe(),'previous native fitness session not settled')
 O.records,O.violations,O.epoch={}, {}, O.epoch+1;O.tailStart=nil;O.placements={};O.player,O.case=player,id
 previousSamples={};postStopAction=nil
end
local function start(action)
 if action.character~=O.player then return end
 if O.active then O.violations[#O.violations+1]='next-workout-before-server-stop'end
 local frameGameMS,frameRealMS=durationFrame()
 local row={exercise=action.exeDataType,minutes=action.timeToExe,maxTime=action:getDuration(),reps=0,
  startMS=clock(),durationStartMS=durationClock(),before=O.clinical(action.character),minEndurance=O.clinical(action.character).endurance,
  durationStartFrameGameMS=frameGameMS,durationStartFrameRealMS=frameRealMS,
  previousStopSettled=not O.active,startEquipment=O.inventory and O.inventory(action.character)or nil,
  startStorage=O.captureStorage and O.storage(action.character)or nil}
 if O.case=='empty-restore'then row.nativeClock={constructorStartMS=action.startMS,deadlineMS=action.endMS,
  observedBodyStartMS=row.startMS,source=isServer()and 'ISFitnessAction.serverStart'or 'SP first started sample'}end
 O.records[#O.records+1]=row;O.active=action;action.fitnessWitness=row
end
local function stopped(action,method)
 local row=action.fitnessWitness
 if not row or row.stopMS then return end
 row.stopMS=clock();row.durationStopMS=durationClock();row.stopMethod=method;row.after=O.clinical(action.character)
 if row.postStopXP then row.afterXPEventCount=#row.postStopXP.events end
 row.durationStopFrameGameMS,row.durationStopFrameRealMS=durationFrame()
 if row.nativeClock then row.nativeClock.constructorStartAtStopMS=action.startMS;row.nativeClock.deadlineAtStopMS=action.endMS end
 row.currentExerciseCleared=action.character:getFitness():getCurrentExe()==nil
 row.serverStopReturned=not isClient();if O.active==action then O.active=nil end
end
-- Native XP.AddXP publishes this event after updating the XP map (SP/server).
-- It has no caller/reason field. Preserve every relevant event, including invalid
-- idle predicates; the verifier decides whether its exact effect is accounted for.
Events.AddXP.Add(function(player,perk,amount)
 local action=postStopAction
 if isClient()or O.case~='late-exhaustion'or player~=O.player or not action
  or (perk~=Perks.Fitness and perk~=Perks.Strength)then return end
 local row=action.fitnessWitness;local ledger=row and row.postStopXP
 if not ledger then return end
 local ok,entry=pcall(function()
  return {perk=perk==Perks.Fitness and 'Fitness'or 'Strength',amount=amount,clinical=O.clinical(player),
   calendarMS=clock(),durationMS=durationClock(),currentExerciseCleared=player:getFitness():getCurrentExe()==nil,
   -- Server NetTimedAction lives in ActionManager, not the BaseAction stack.
   -- A missing pointer is unavailable evidence, never proof of body removal.
   observerActive=O.active~=nil,nativeAbsent=not isServer()and action.action~=nil
    and not player:getCharacterActions():contains(action.action),
   reps=action.repnb,enduranceWarning=player:getStats():getEnduranceDangerWarning()}
 end)
 if ok then ledger.events[#ledger.events+1]=entry else ledger.error=tostring(entry)end
end)
local function copyValues(value)
 if type(value)~='table'then return value end
 local result={};for key,entry in pairs(value)do result[key]=copyValues(entry)end
 return result
end
function O.receipt(player)
 local receipt={records=O.records,violations=O.violations,currentExerciseCleared=not player:getFitness():getCurrentExe(),
  serverStopSettled=O.active==nil,clinical=O.clinical(player),tailStart=O.tailStart,placements=O.placements}
 if O.case=='late-exhaustion'then
  -- A later idle AddXP must not change the event horizon of an issued receipt.
  receipt.records=copyValues(O.records)
  receipt.receiptCalendarMS=clock();receipt.receiptDurationMS=durationClock()
 end
 return receipt
end
-- SP reads the real live action without replacing any source-guarded client method.
function O.sample(current)
 if isClient()or isServer()then return end
 if O.active and O.active~=current then stopped(O.active,'observed-native-removal')end
 if not current or current.Type~='ISFitnessAction'or not current:isStarted()then return end
 if not current.fitnessWitness then
  start(current);if O.case~='empty-restore'then current.fitnessWitness.startMS=current.startMS end
  local fitness=PZSurvivorToolkit and PZSurvivorToolkit.ActionQueueFitness
  local progress=fitness and fitness.progress(current)
  if progress then current.fitnessWitness.durationStartMS=progress.startMS end
 end
 local row=current.fitnessWitness
 local sample=O.case=='late-exhaustion'and {reps=current.repnb,clinical=O.clinical(current.character),
  enduranceMoodle=current.character:getMoodles():getMoodleLevel(MoodleType.ENDURANCE)}or nil
 if current.repnb>row.reps then
  row.reps=current.repnb;row.lastRepMS=clock();row.lastRep=sample and sample.clinical or O.clinical(current.character)
  row.minEndurance=math.min(row.minEndurance,row.lastRep.endurance)
  if sample then
   -- Adjacent observations establish a real repetition increment, not an exact
   -- native call boundary: ordinary metabolism can run between these samples.
   local previous=previousSamples[current];local delta=previous and current.repnb-previous.reps
   row.repSampleDelta=delta or false
   row.repObservationSource=delta==1 and 'SP adjacent native samples'or 'SP skipped native samples'
   row.lastRepBefore=delta==1 and previous.clinical or nil
   row.lastRepBeforeEnduranceMoodle=delta==1 and previous.enduranceMoodle or nil
   row.lastRepEnduranceMoodle=sample.enduranceMoodle;row.lastRepDurationMS=durationClock()
  end
 end
 if sample then previousSamples[current]=sample end
end
if not isServer()then return O end
require 'TimedActions/ISReadABook'
local tailStartOriginal=ISReadABook.serverStart
ISReadABook.serverStart=function(action,...)
 if action.character==O.player and action.item:getID()==O.tailID then
  O.tailStart={id=action.item:getID(),kind=action.item:getFullType(),callback='ISReadABook.serverStart',inventory=O.inventory(action.character),
   activation=O.activation(action.character),storage=O.captureStorage and O.storage(action.character)or nil,workouts=#O.records,observerActive=O.active~=nil}
 end
 return tailStartOriginal(action,...)
end
require 'TimedActions/ISDropWorldItemAction'
local dropCompleteOriginal=ISDropWorldItemAction.complete
ISDropWorldItemAction.complete=function(action,...)
 local result=dropCompleteOriginal(action,...)
 if O.captureStorage and action.character==O.player and action.item and action.item:getID()==O.bagID then
  O.placements[#O.placements+1]=O.placement(action.character,'ISDropWorldItemAction.complete',result==true)
 end
 return result
end
local begin='serverStart'
local beginOriginal=ISFitnessAction[begin]
ISFitnessAction[begin]=function(action,...)
 start(action);return beginOriginal(action,...)
end
local repeatOriginal=ISFitnessAction.exeLooped
ISFitnessAction.exeLooped=function(action,...)
 local row=action.fitnessWitness
 local before,moodle
 if O.case=='late-exhaustion'and row then
  before=O.clinical(action.character);moodle=action.character:getMoodles():getMoodleLevel(MoodleType.ENDURANCE)
 end
 local result=repeatOriginal(action,...);row=action.fitnessWitness
 if row then
  row.reps=row.reps+1;row.minEndurance=math.min(row.minEndurance,O.clinical(action.character).endurance)
  row.lastRepMS=clock();row.lastRep=O.clinical(action.character)
  if before then
   row.repSampleDelta=1;row.repObservationSource='server exeLooped'
   row.lastRepBefore=before;row.lastRepBeforeEnduranceMoodle=moodle
   row.lastRepEnduranceMoodle=action.character:getMoodles():getMoodleLevel(MoodleType.ENDURANCE)
   row.lastRepDurationMS=durationClock()
  end
  if O.onRep then O.onRep(action,row)end
 end
 return result
end
for _,method in ipairs({'serverStop','complete'})do
 local original=ISFitnessAction[method]
 ISFitnessAction[method]=function(action,...)
  local row=action.fitnessWitness
  if row then row.stopCallbacks=row.stopCallbacks or {};row.stopCallbacks[method]=(row.stopCallbacks[method] or 0)+1 end
  if O.case=='late-exhaustion'then O.noteStop(action)end
  local result=original(action,...);stopped(action,method);return result
 end
end

return O
