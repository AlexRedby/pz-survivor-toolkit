-- Injuries are real BodyDamage; the engine alone computes WalkInjury and gait eligibility.
local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'TimedActions/ISTimedActionQueue'
local p,area=assert(getPlayer()),assert(CartTestArea)
assert(area.ready and CartLabKey and CartLabSelectScenes and cartLabDrive and cartLabGait and cartLabTracks and cartLabPoseHeading and cartLabHeading and cartLabSteeringHeading,'CartLab bootstrap required')
assert(toolkitCartInjurySupported and toolkitCartInjurySupported(p),'Candidate cart injury source gate unsupported')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
local kind=config.cartType or 'SaucedWheelbarrow.WheelbarrowWood'
assert(kind=='SaucedWheelbarrow.WheelbarrowWood' or kind=='SaucedWheelbarrow.WheelbarrowMetal' or kind=='SaucedCarts.ShoppingCart','Unsupported cart')
local cases={}
for _,female in ipairs({false,true}) do for _,full in ipairs({false,true}) do
 for _,side in ipairs({'left','right'}) do for _,severity in ipairs({'mild','heavy'}) do
  cases[#cases+1]={female=female,full=full,side=side,severity=severity,
   name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..side..'-'..severity}
 end end
end end
cases=CartLabSelectScenes(cases)
local phases={
 {name='forward',start=0,drive=1,gait=0},
 {name='left',start=1800,drive=5,gait=0},
 {name='right',start=3000,drive=8,gait=0},
 {name='reverse',start=4200,drive=4,gait=0},
 {name='run-request',start=5600,drive=1,gait=1},
 {name='sprint-request',start=6800,drive=1,gait=2},
 {name='stop',start=8000,drive=0,gait=0},
 {name='healed-forward',start=9000,drive=1,gait=0,heal=true},
 {name='healed-stop',start=11000,drive=0,gait=0},
}
local index,stage,since,videoSince,lastSample,phaseSince=0,0,0,0,0,0
local item,id,cargoID,cargoWeight,mode
local fixtureClothing={}
local originalGod=p:isGodMod()
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite injury evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid injury evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function heal()
 p:getBodyDamage():RestoreToFullHealth()
end
local function ownership()
 assert(not p:isDead() and not p:isGodMod(),'Real living injury actor required')
 assert(item:getID()==id and item:getFullType()==kind and item:getContainer()==p:getInventory() and not item:getWorldItem(),'Injury changed cart identity/owner')
 assert(p:getPrimaryHandItem()==item and p:getSecondaryHandItem()==item,'Injury lost exact cart hands')
 local contents=item:getInventory():getItems()
 assert(contents:size()==(cargoID==-1 and 0 or 1),'Injury changed cargo count')
 assert(cargoID==-1 or contents:get(0):getID()==cargoID,'Injury changed cargo identity')
 assert(math.abs(item:getInventory():getCapacityWeight()-cargoWeight)<.01,'Injury changed cargo weight')
 assert(#ISTimedActionQueue.getTimedActionQueue(p).queue==0 and p:getCharacterActions():isEmpty() and not p:hasPath(),'Injury enqueued action/path')
 area.checkPosition(p)
end
local function finish()
 cartLabDrive(-1);cartLabGait(0);heal();p:setGodMod(originalGod)
 Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
end
local function startPhase(now)
 local phase=phases[stage]
 if phase.heal then heal() end
 p:getStats():reset(CharacterStat.ENDURANCE)
 cartLabGait(phase.gait);cartLabDrive(phase.drive)
 now=getTimestampMs();phaseSince=now
 print('[CART_INJURY] PHASE '..encode({case=cases[index].name,phase=phase.name,wall=now,start=videoSince,elapsed=now-videoSince,drive=phase.drive,gait=phase.gait,heal=phase.heal==true}))
end
local function dress()
 p:clearWornItems()
 local inventory=p:getInventory()
 for _,clothing in ipairs(fixtureClothing) do
  assert(clothing:getContainer()==inventory,'Fixture clothing changed owner')
  inventory:Remove(clothing)
 end
 fixtureClothing={}
 for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
  local clothing=assert(inventory:AddItem(name));fixtureClothing[#fixtureClothing+1]=clothing
  p:setWornItem(clothing:getBodyLocation(),clothing)
 end
end
local function nextCase()
 cartLabDrive(0);cartLabGait(0);heal();index=index+1;stage=0
 if index>#cases then finish();print('[WOOD_BANK] ALL_COMPLETE cases='..#cases);return end
 local c=cases[index]
 p:setFemale(c.female);p:getDescriptor():setFemale(c.female)
 dress();p:getHumanVisual():setHairModel(c.female and 'Kate' or 'CrewCut');p:getHumanVisual():setBeardModel('')
 p:resetModel()
 for _=1,3 do
  if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()==kind then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 item=assert(p:getPrimaryHandItem(),'Cart missing');assert(item:getFullType()==kind,'Wrong cart')
 if (item:getInventory():getCapacityWeight()>0)~=c.full then CartLabKey(Keyboard.KEY_F6) end
 item=p:getPrimaryHandItem();id=item:getID();cargoWeight=item:getInventory():getCapacityWeight()
 local contents=item:getInventory():getItems();cargoID=contents:isEmpty() and -1 or contents:get(0):getID()
 assert(c.full and math.abs(cargoWeight-item:getInventory():getEffectiveCapacity(p))<.01 or not c.full and cargoWeight==0,'Wrong injury cargo')
 p:setX(area.x);p:setY(area.y);p:setZ(area.z);p:setNextX(area.x);p:setNextY(area.y);p:setLastX(area.x);p:setLastY(area.y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(0)
 p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
 p:setGodMod(false)
 local part=p:getBodyDamage():getBodyPart(c.side=='left' and BodyPartType.Foot_L or BodyPartType.Foot_R)
 if c.severity=='mild' then part:setScratched(true,false);part:setScratchTime(8);part:setBleeding(false);part:setBleedingTime(0)
 else part:setFractureTime(35) end
 part:SetInfected(false);part:setInfectedWound(false)
 ownership();mode='settle';since=getTimestampMs()
end
local function record(now)
 local phase,c=phases[stage],cases[index]
 local left=p:getBodyDamage():getBodyPart(BodyPartType.Foot_L)
 local right=p:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
 print('[CART_INJURY] SAMPLE '..encode({case=c.name,phase=phase.name,start=videoSince,wall=now,elapsed=now-videoSince,
  cartType=kind,female=p:isFemale(),full=c.full,id=id,primaryID=p:getPrimaryHandItem():getID(),secondaryID=p:getSecondaryHandItem():getID(),
  cargoID=cargoID,cargoWeight=cargoWeight,x=p:getX(),y=p:getY(),heading=cartLabHeading(),acceptedHeading=cartLabSteeringHeading(),
  actorInventoryWeight=p:getInventory():getCapacityWeight(),
  injury=p:getVariableFloat('WalkInjury',0),walkSpeed=p:getVariableFloat('WalkSpeed',0),legPace=p:getVariableFloat('ToolkitCartLegPace',0),
  leftScratch=left:getScratchTime(),rightScratch=right:getScratchTime(),leftFracture=left:getFractureTime(),rightFracture=right:getFractureTime(),
  run=p:isRunning(),sprint=p:isSprinting(),requestedGait=phase.gait,drive=phase.drive,
  motion=p:getVariableBoolean('ToolkitCartMotion'),pivot=p:getVariableBoolean('ToolkitCartPivot'),brake=p:getVariableBoolean('ToolkitCartWoodBrake'),
  stepX=p:getVariableFloat('ToolkitCartStepX',0),stepY=p:getVariableFloat('ToolkitCartStepY',0),tracks=cartLabTracks()}))
 lastSample=now
end
local function tick()
 local now=getTimestampMs();ownership()
 if mode=='settle' then
  if now-since<1000 then return end
  area.check(p)
  local injury=p:getVariableFloat('WalkInjury',0)
  assert(cases[index].side=='left' and injury>.15 or cases[index].side=='right' and injury<-.15,'Engine did not derive expected real injury scalar')
  assert(p:getVariableBoolean('ToolkitCartMotion'),'Candidate cart motion did not remain active with injury')
  stage=1;mode='record'
  assert(toolkitVideoStart(config.videoRoot..'/injury-'..cases[index].name..'-'..now,config.ffmpeg),'Video start rejected')
  videoSince=getTimestampMs()
  print('[WOOD_BANK] CASE '..cases[index].name..' attempt=0 wall='..videoSince);startPhase(videoSince);return
 end
 local video=toolkitVideoStatus();assert(video.state~='failed','Injury video failed: '..tostring(video.error))
 if mode=='finish' then
  assert(now-since<10000,'Injury video finalization timed out')
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..cases[index].name..' wall='..videoSince..' file='..video.file..' frames='..video.frames..' seconds='..video.seconds);nextCase()
  end
  return
 end
 -- Each input gets its full requested duration even after a slow game tick.
 -- Never catch up several controls in one tick: that would omit real engine updates.
 if stage<#phases and now-phaseSince>=phases[stage+1].start-phases[stage].start then
  stage=stage+1;startPhase(now)
  now=getTimestampMs()
 end
 if now-lastSample>=50 then record(now) end
 if stage==#phases and now-phaseSince>=12000-phases[stage].start then
  print('[CART_INJURY] END '..encode({case=cases[index].name,start=videoSince,wall=now,elapsed=now-videoSince}))
  cartLabDrive(0);cartLabGait(0);assert(toolkitVideoStop(),'Video stop rejected');mode='finish';since=now
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then toolkitVideoStop();finish();print('[WOOD_BANK] FAIL '..tostring(why)) end
end
print('[WOOD_BANK] RUN_STARTED')
print('[CART_INJURY] SCOPE Native Foot_L/Foot_R scratch/fracture with engine WalkInjury; requested gaits do not force actor flags')
nextCase();Events.OnTick.Add(WoodPrototypeTick)
