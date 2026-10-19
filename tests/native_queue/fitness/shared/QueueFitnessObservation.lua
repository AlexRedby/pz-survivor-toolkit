-- Read-only witnesses around real native methods. Never synthesize animation events,
-- shorten timers, call exerciseRepeat directly, or award XP.
require 'TimedActions/ISFitnessAction'
local O={records={},active=nil,violations={},epoch=0}
local function clock()return getGameTime():getCalender():getTimeInMillis()end
O.clock=clock
function O.clinical(player)
 local fit=player:getFitness();local xp=player:getXp();local regularity,stiffness,timers={},{},{}
 for _,kind in ipairs({'squats','pushups','bicepscurl'})do regularity[kind]=fit:getRegularity(kind)end
 for _,part in ipairs({'legs','arms','chest','abs'})do
  stiffness[part]=fit:getCurrentExeStiffnessInc(part);timers[part]=fit:getCurrentExeStiffnessTimer(part)
 end
 return {fitnessXP=xp:getXP(Perks.Fitness),strengthXP=xp:getXP(Perks.Strength),endurance=player:getStats():get(CharacterStat.ENDURANCE),
  regularity=regularity,stiffness=stiffness,timers=timers}
end
function O.reset(player,id)
 assert(not O.active and not player:getFitness():getCurrentExe(),'previous native fitness session not settled')
 O.records,O.violations,O.epoch={}, {}, O.epoch+1;O.player,O.case=player,id
end
local function start(action)
 if action.character~=O.player then return end
 if O.active then O.violations[#O.violations+1]='next-workout-before-server-stop'end
 local row={exercise=action.exeDataType,minutes=action.timeToExe,maxTime=action:getDuration(),reps=0,
  startMS=clock(),before=O.clinical(action.character),minEndurance=O.clinical(action.character).endurance,
  previousStopSettled=not O.active,startEquipment=O.inventory and O.inventory(action.character)or nil}
 O.records[#O.records+1]=row;O.active=action;action.fitnessWitness=row
end
local function stopped(action,method)
 local row=action.fitnessWitness
 if not row or row.stopMS then return end
 row.stopMS=clock();row.stopMethod=method;row.after=O.clinical(action.character)
 row.currentExerciseCleared=action.character:getFitness():getCurrentExe()==nil
 row.serverStopReturned=not isClient();if O.active==action then O.active=nil end
end
function O.receipt(player)
 return {records=O.records,violations=O.violations,currentExerciseCleared=not player:getFitness():getCurrentExe(),
  serverStopSettled=O.active==nil,clinical=O.clinical(player)}
end
-- SP reads the real live action without replacing any source-guarded client method.
function O.sample(current)
 if isClient()or isServer()then return end
 if O.active and O.active~=current then stopped(O.active,'observed-native-removal')end
 if not current or current.Type~='ISFitnessAction'or not current:isStarted()then return end
 if not current.fitnessWitness then start(current);current.fitnessWitness.startMS=current.startMS end
 local row=current.fitnessWitness
 if current.repnb>row.reps then
  row.reps=current.repnb;row.lastRepMS=clock();row.lastRep=O.clinical(current.character)
  row.minEndurance=math.min(row.minEndurance,row.lastRep.endurance)
 end
end
if not isServer()then return O end
local begin='serverStart'
local beginOriginal=ISFitnessAction[begin]
ISFitnessAction[begin]=function(action,...)
 start(action);return beginOriginal(action,...)
end
local repeatOriginal=ISFitnessAction.exeLooped
ISFitnessAction.exeLooped=function(action,...)
 local result=repeatOriginal(action,...);local row=action.fitnessWitness
 if row then
  row.reps=row.reps+1;row.minEndurance=math.min(row.minEndurance,O.clinical(action.character).endurance)
  row.lastRepMS=clock();row.lastRep=O.clinical(action.character)
  if O.onRep then O.onRep(action,row)end
 end
 return result
end
for _,method in ipairs({'serverStop','complete'})do
 local original=ISFitnessAction[method]
 ISFitnessAction[method]=function(action,...)
  local result=original(action,...);stopped(action,method);return result
 end
end

return O
