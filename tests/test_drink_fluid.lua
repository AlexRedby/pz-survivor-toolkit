require=function(name)assert(name=='TimedActions/ISDrinkFluidAction'or name=='TimedActions/ISBaseTimedAction')end
MoodleType={FOOD_EATEN=1}
ISDrinkFluidAction={isValidStart=function(self)return self.nativeResult end}
if NativeActionRoot then
 ISBaseTimedAction={derive=function()return {}end}
 assert(loadfile(NativeActionRoot..'/shared/TimedActions/ISDrinkFluidAction.lua'))()
end
local native=ISDrinkFluidAction.isValidStart
local valid=ISDrinkFluidAction.isValid
local level,empty,hunger=3,false,0
local action={nativeResult=false,
 fluidContainer={isEmpty=function()return empty end,
  getProperties=function()return {getHungerChange=function()return hunger end}end},
 character={getMoodles=function()return {getMoodleLevel=function()return level end}end}}
assert(not native(action),'native fullness rejection must reproduce before the fix')
dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/DrinkFluidAction.lua')
for _,foodLevel in ipairs({0,1,2,3,4})do
 level=foodLevel
 empty=false
 assert(ISDrinkFluidAction.isValidStart(action),'non-nutritious water must ignore fullness')
 empty=true
 assert(not ISDrinkFluidAction.isValidStart(action),'empty water must remain invalid')
 empty=false;hunger=-.1
 if NativeActionRoot then
  assert(ISDrinkFluidAction.isValidStart(action)==(level<3),'nutritious drinks must retain native fullness limits')
 else
  for _,result in ipairs({false,true})do
   action.nativeResult=result
   assert(ISDrinkFluidAction.isValidStart(action)==result,'retain native decisions for nutritious drinks')
  end
 end
 hunger=0
end
assert(ISDrinkFluidAction.isValid==valid,'inventory ownership validation must remain native')
print('Drink fluid: water after transfer, empty rejection and native nutritious-drink guards passed.')
