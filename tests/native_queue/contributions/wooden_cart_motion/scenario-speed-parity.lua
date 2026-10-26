-- Native keyboard comparison at equal effective encumbrance and controlled stats.
local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'TimedActions/ISTimedActionQueue'
local p,area=assert(getPlayer()),assert(CartTestArea)
assert(area.ready and CartLabSelectScenes and cartLabNativePoseHeading and cartLabSteeringActive and cartLabNativeHeldModels and cartLabScriptRunSpeedModifier and cartLabMillis,'Speed parity bridges missing')
local kind=config.cartType or 'SaucedWheelbarrow.WheelbarrowWood'
assert(kind=='SaucedWheelbarrow.WheelbarrowWood' or kind=='SaucedWheelbarrow.WheelbarrowMetal' or kind=='SaucedCarts.ShoppingCart','Unsupported cart')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
local cases={}
for _,female in ipairs({false,true}) do for _,full in ipairs({false,true}) do
 for _,injury in ipairs({'healthy','left-mild','left-heavy','right-mild','right-heavy'}) do
  cases[#cases+1]={female=female,full=full,injury=injury,name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..injury}
 end
end end
assert(#cases==20);cases=CartLabSelectScenes(cases)
local phases={{name='idle',duration=1200,drive=0},{name='acceleration',duration=3000,drive=1},
 {name='cruise',duration=5000,drive=1},{name='braking',duration=2000,drive=0}}
local controlled={CharacterStat.ENDURANCE,CharacterStat.FATIGUE,CharacterStat.HUNGER,CharacterStat.THIRST,CharacterStat.PANIC,CharacterStat.STRESS,CharacterStat.PAIN}
local function pinStats()
 for _,stat in ipairs(controlled) do p:getStats():set(stat,stat==CharacterStat.ENDURANCE and 1 or 0) end
end
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c)return string.format('\\u%04x',string.byte(c))end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite speed evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid speed evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function emit(tag,row)print('[CART_SPEED] '..tag..' '..encode(row))end
local index,trialIndex,phaseIndex=0,0,0
local c,cart,ballast,outfit,trial,phase,phaseStart,trialStart,lastSample,sceneStart,targetWeight,targetMax
cart=p:getPrimaryHandItem()
local originalGod=p:isGodMod()
local function remove(item)
 if item and item:getContainer()==p:getInventory() then p:getInventory():Remove(item) end
end
local function clearHands()
 p:setPrimaryHandItem(nil);p:setSecondaryHandItem(nil);SaucedCarts.clearCartPose(p)
end
local function healAndInjure()
 p:getBodyDamage():RestoreToFullHealth();p:setGodMod(false)
 if c.injury~='healthy' then
  local side=c.injury:find('left',1,true) and BodyPartType.Foot_L or BodyPartType.Foot_R
  local part=p:getBodyDamage():getBodyPart(side)
  if c.injury:find('mild',1,true) then
   part:setScratched(true,false);part:setScratchTime(8);part:setBleeding(false);part:setBleedingTime(0)
  else part:setFractureTime(35) end
  part:SetInfected(false);part:setInfectedWound(false)
 end
 pinStats()
end
local function owned()
 assert(not p:isDead() and not p:isGodMod() and not p:isUnlimitedCarry() and not p:isUnlimitedEndurance(),'Ordinary living speed actor required')
 assert(p:isFemale()==c.female and p:getWornItems():size()==3,'Speed actor/outfit changed')
 for _,item in ipairs(outfit) do assert(item:getContainer()==p:getInventory() and p:getWornItem(item:getBodyLocation())==item,'Exact speed outfit changed') end
 assert(#ISTimedActionQueue.getTimedActionQueue(p).queue==0 and p:getCharacterActions():isEmpty() and not p:hasPath(),'Speed created action/path')
 assert(math.abs(p:getInventoryWeight()-targetWeight)<.001 and p:getMaxWeight()==targetMax,'Speed effective encumbrance changed')
 if trial.mode=='cart' then
  assert(p:getPrimaryHandItem()==cart and p:getSecondaryHandItem()==cart and cart:getContainer()==p:getInventory() and not cart:getWorldItem(),'Exact speed cart owner changed')
  assert(not ballast or ballast:getContainer()~=p:getInventory(),'Cart trial retained ballast')
 else
  assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem() and cart:getContainer()~=p:getInventory() and not cart:getWorldItem(),'Bare trial retained cart')
  assert(ballast and ballast:getContainer()==p:getInventory(),'Bare ballast owner changed')
 end
 area.checkPosition(p)
end
local function sample(now)
 if now==lastSample then return end
 owned();lastSample=now
 local left=p:getBodyDamage():getBodyPart(BodyPartType.Foot_L)
 local right=p:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
 local inventory=p:getInventory():getItems();local carts=0
 for i=0,inventory:size()-1 do
  local t=inventory:get(i):getFullType()
  if t=='SaucedCarts.ShoppingCart' or t=='SaucedWheelbarrow.WheelbarrowWood' or t=='SaucedWheelbarrow.WheelbarrowMetal' then carts=carts+1 end
 end
 emit('SAMPLE',{case=c.name,trial=trialIndex,mode=trial.mode,gait=trial.gait,phase=phase.name,
  mono=now,wall=getTimestampMs(),elapsed=now-trialStart,phaseElapsed=now-phaseStart,frame=cartLabFrame(),x=p:getX(),y=p:getY(),z=p:getZ(),heading=cartLabHeading(),
  run=p:isRunning(),sprint=p:isSprinting(),drive=phase.drive,runKey=isKeyDown(getCore():getKey('Run')),sprintKey=isKeyDown(getCore():getKey('Sprint')),
  cartType=kind,cartID=cart:getID(),cargoID=cart:getInventory():getItems():isEmpty() and -1 or cart:getInventory():getItems():get(0):getID(),cargoWeight=cart:getInventory():getCapacityWeight(),
  cartRunSpeedModifier=cartLabScriptRunSpeedModifier(cart),nativeRunSpeedModifier=p:getRunSpeedModifier(),nativeWeapon=p:getVariableString('Weapon') or '',heldModels=cartLabNativeHeldModels(),
  primaryID=p:getPrimaryHandItem() and p:getPrimaryHandItem():getID() or -1,secondaryID=p:getSecondaryHandItem() and p:getSecondaryHandItem():getID() or -1,
  cartCount=carts,ballastID=ballast and ballast:getID() or -1,ballastWeight=ballast and ballast:getActualWeight() or 0,
  inventoryWeight=p:getInventoryWeight(),capacityWeight=p:getInventory():getCapacityWeight(),maxWeight=p:getMaxWeight(),targetWeight=targetWeight,targetMax=targetMax,
  female=p:isFemale(),full=c.full,wornCount=p:getWornItems():size(),outfitIDs=outfit[1]:getID()..','..outfit[2]:getID()..','..outfit[3]:getID(),skill=p:getPerkLevel(Perks.Sprinting),
  walkSpeed=p:getVariableFloat('WalkSpeed',0),runSpeed=p:getVariableFloat('RunSpeed',0),injury=p:getVariableFloat('WalkInjury',0),slowFactor=p:getSlowFactor(),
  thermalMovement=p:getBodyDamage():getThermoregulator():getMovementModifier(),
  endurance=p:getStats():get(CharacterStat.ENDURANCE),fatigue=p:getStats():get(CharacterStat.FATIGUE),pain=p:getStats():get(CharacterStat.PAIN),panic=p:getStats():get(CharacterStat.PANIC),
  hunger=p:getStats():get(CharacterStat.HUNGER),thirst=p:getStats():get(CharacterStat.THIRST),stress=p:getStats():get(CharacterStat.STRESS),
  heavyLoad=p:getMoodles():getMoodleLevel(MoodleType.HEAVY_LOAD),enduranceMoodle=p:getMoodles():getMoodleLevel(MoodleType.ENDURANCE),painMoodle=p:getMoodles():getMoodleLevel(MoodleType.PAIN),
  leftScratch=left:getScratchTime(),rightScratch=right:getScratchTime(),leftFracture=left:getFractureTime(),rightFracture=right:getFractureTime(),
  motion=p:getVariableBoolean('ToolkitCartMotion'),steering=cartLabSteeringActive(),tracks=cartLabTracks(),statsControl='neutral-each-tick'})
end
local function startPhase(now)
 phase=phases[phaseIndex];phaseStart=now;lastSample=now
 cartLabGait(phase.drive==1 and trial.gait or 0);cartLabDrive(phase.drive)
 emit('PHASE',{case=c.name,trial=trialIndex,phase=phase.name,mono=now,elapsed=now-trialStart,drive=phase.drive,gait=phase.drive==1 and trial.gait or 0})
 if phaseIndex==1 then lastSample=-1;sample(now) end
end
local function startTrial()
 trialIndex=trialIndex+1
 if trialIndex>6 then
  emit('SCENE_END',{case=c.name,mono=cartLabMillis(),wall=getTimestampMs()})
  print('[WOOD_BANK] COMPLETE '..c.name..' wall='..sceneStart)
  return false
 end
 trial={gait=math.floor((trialIndex-1)/2),mode=trialIndex%2==1 and 'bare' or 'cart'}
 cartLabDrive(0);cartLabGait(0);clearHands();remove(cart);remove(ballast);ballast=nil
 if trial.mode=='cart' then
  p:getInventory():AddItem(cart);p:setPrimaryHandItem(cart);p:setSecondaryHandItem(cart);SaucedCarts.applyCartPose(p)
 else
  ballast=assert(p:getInventory():AddItem('Base.Log'))
  ballast:setActualWeight(0);ballast:setCustomWeight(true)
  local weight=targetWeight-p:getInventoryWeight();assert(weight>=0,'Negative native ballast')
  ballast:setActualWeight(weight)
 end
 p:updateHandEquips()
 healAndInjure()
 local x,y=area.x+16,area.y+16
 p:setX(x);p:setY(y);p:setZ(area.z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabNativePoseHeading(-math.pi*3/4)
 trialStart=cartLabMillis();phaseIndex=1
 emit('TRIAL',{case=c.name,trial=trialIndex,mode=trial.mode,gait=trial.gait,mono=trialStart,wall=getTimestampMs(),heading=-math.pi*3/4})
 startPhase(trialStart);return true
end
local function nextCase()
 clearHands();remove(cart);remove(ballast);ballast=nil;cart=nil
 if outfit then for _,item in ipairs(outfit) do remove(item) end end
 index=index+1
 if index>#cases then
  cartLabDrive(-1);cartLabGait(0);p:getBodyDamage():RestoreToFullHealth();p:setGodMod(originalGod)
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[WOOD_BANK] ALL_COMPLETE cases='..#cases);return
 end
 c=cases[index];p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:clearWornItems();outfit={}
 for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
  local item=assert(p:getInventory():AddItem(name));outfit[#outfit+1]=item;p:setWornItem(item:getBodyLocation(),item)
 end
 p:resetModel();p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
 cart=assert(p:getInventory():AddItem(kind));p:setPrimaryHandItem(cart);p:setSecondaryHandItem(cart);SaucedCarts.applyCartPose(p)
 if c.full then local cargo=assert(cart:getInventory():AddItem('Base.Log'));cargo:setActualWeight(cart:getInventory():getEffectiveCapacity(p));cargo:setCustomWeight(true) end
 healAndInjure();targetWeight=p:getInventoryWeight();targetMax=p:getMaxWeight()
 sceneStart=getTimestampMs();trialIndex=0
 print('[WOOD_BANK] CASE '..c.name..' attempt=0 wall='..sceneStart)
 emit('SCENE',{case=c.name,wall=sceneStart,cartType=kind,targetWeight=targetWeight,targetMax=targetMax,fullBankCount=20,statsControl='neutral-each-tick'})
 assert(startTrial())
end
local function tick()
 pinStats()
 local now=cartLabMillis();owned()
 if now-lastSample>=50 then sample(now) end
 if now-phaseStart>=phase.duration then
  sample(now)
  emit('PHASE_END',{case=c.name,trial=trialIndex,phase=phase.name,mono=now,elapsed=now-phaseStart})
  phaseIndex=phaseIndex+1
  if phaseIndex>#phases then
   emit('TRIAL_END',{case=c.name,trial=trialIndex,mono=now,wall=getTimestampMs()})
   if not startTrial() then nextCase() end
  else startPhase(now) end
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);cartLabGait(0);p:getBodyDamage():RestoreToFullHealth();p:setGodMod(originalGod)
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
Events.OnTick.Add(WoodPrototypeTick)
print('[WOOD_BANK] RUN_STARTED '..getTimestampMs())
nextCase()
