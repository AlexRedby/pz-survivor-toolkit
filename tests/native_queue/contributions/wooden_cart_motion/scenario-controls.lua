local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'TimedActions/ISTimedActionQueue'
local area,p=assert(CartTestArea),assert(getPlayer())
assert(area.ready and CartLabKey and CartLabSelectScenes and cartLabDrive and cartLabGait and cartLabHeading and cartLabSteeringHeading and cartLabFrame and cartLabPoseHeading,'CartLab bootstrap required')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
local cases={
 {name='shopping-cart',kind='SaucedCarts.ShoppingCart'},
 {name='wooden-wheelbarrow',kind='SaucedWheelbarrow.WheelbarrowWood'},
 {name='metal-wheelbarrow',kind='SaucedWheelbarrow.WheelbarrowMetal'},
}
cases=CartLabSelectScenes(cases)
local phases={
 {name='forward-0',drive=1,gait=0,duration=1000,pose=0},
 {name='forward-angle',drive=1,gait=0,duration=1000,pose=2.1},
 {name='left-held',drive=5,gait=1,duration=4000,pose=0},
 {name='left-release',drive=1,gait=0,duration=600},
 {name='right-held',drive=8,gait=1,duration=4000,pose=0},
 {name='right-release',drive=1,gait=0,duration=600},
 {name='pivot-left',drive=2,gait=0,duration=1300,pose=0},
 {name='pivot-right',drive=3,gait=0,duration=1300,pose=0},
 {name='pivot-release',drive=0,gait=0,duration=700},
 {name='reverse',drive=4,gait=0,duration=1200,pose=.8},
 {name='reverse-left',drive=6,gait=0,duration=1500,pose=.8},
 {name='reverse-right',drive=7,gait=0,duration=1500,pose=.8},
 {name='moving-forward',drive=1,gait=0,duration=1000,pose=1.3},
 {name='moving-reverse',drive=4,gait=0,duration=1800},
 {name='run',drive=1,gait=1,duration=1000,pose=1.3},
 {name='run-stop',drive=0,gait=0,duration=1200},
 {name='sprint',drive=1,gait=2,duration=1000,pose=1.3},
 {name='sprint-stop',drive=0,gait=0,duration=1500},
}
local index,step,since,videoStart,sample,lastSample=0,0,0,0,0,0
local item,id,cargoID,cargoWeight,mode,gaitSeen
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite controls evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid controls evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function ownership()
 local queue=ISTimedActionQueue.getTimedActionQueue(p).queue
 assert(#queue==0 and p:getCharacterActions():isEmpty() and not p:hasPath(),'Controls must not enqueue actions/path')
 assert(item:getID()==id and item:getFullType()==cases[index].kind and item:getContainer()==p:getInventory() and not item:getWorldItem(),'Controls changed cart owner/identity')
 assert(p:getPrimaryHandItem()==item and p:getSecondaryHandItem()==item,'Controls lost exact cart hands')
 local contents=item:getInventory():getItems()
 assert(contents:size()==1 and contents:get(0):getID()==cargoID and math.abs(item:getInventory():getCapacityWeight()-cargoWeight)<.001,'Controls changed cargo identity/weight')
 local count=0;local inventory=p:getInventory():getItems()
 for i=0,inventory:size()-1 do if inventory:get(i):getID()==id then count=count+1 end end
 assert(count==1,'Controls duplicated cart inventory identity')
 area.checkPosition(p)
 return count
end
local function position(heading)
 p:setX(area.x);p:setY(area.y);p:setZ(area.z);p:setNextX(area.x);p:setNextY(area.y);p:setLastX(area.x);p:setLastY(area.y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(heading)
end
local function record(now)
 print('[CART_CONTROLS] SAMPLE '..encode({case=cases[index].name,phase=phases[step].name,sample=sample,
  elapsed=now-since,frame=cartLabFrame(),x=p:getX(),y=p:getY(),heading=cartLabHeading(),acceptedHeading=cartLabSteeringHeading()}))
 sample=sample+1;lastSample=now
end
local function startPhase(now)
 local phase=phases[step]
 if phase.pose~=nil then position(phase.pose) end
 p:getStats():reset(CharacterStat.ENDURANCE)
 since=now;sample=0;gaitSeen=false;mode='drive'
 cartLabGait(phase.gait);cartLabDrive(phase.drive);record(now)
end
local function nextPhase(now)
 step=step+1
 if step>#phases then cartLabDrive(0);cartLabGait(0);assert(toolkitVideoStop(),'Video stop rejected');mode='finish';since=now;return end
 if phases[step].pose~=nil then cartLabDrive(0);cartLabGait(0);mode='settle';since=now
 else startPhase(now) end
end
local function nextCase()
 index=index+1;step=0
 if index>#cases then
  cartLabDrive(-1);cartLabGait(0);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[CART_CONTROLS] ALL_COMPLETE cases='..#cases);print('[WOOD_BANK] ALL_COMPLETE cases='..#cases);return
 end
 if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()==cases[index].kind and p:getPrimaryHandItem():getInventory():getCapacityWeight()>0 then CartLabKey(Keyboard.KEY_F5) end
 for _=1,3 do
  if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()==cases[index].kind then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 item=assert(p:getPrimaryHandItem(),'Fixture cart missing');assert(item:getFullType()==cases[index].kind,'Fixture cart type mismatch')
 assert(item:getInventory():getCapacityWeight()==0,'Expected new empty fixture cart')
 local cargo=assert(item:getInventory():AddItem('Base.Log'));cargo:setActualWeight(1);cargo:setCustomWeight(true)
 id=item:getID();cargoID=cargo:getID();cargoWeight=item:getInventory():getCapacityWeight();ownership()
 videoStart=getTimestampMs()
 assert(toolkitVideoStart(config.videoRoot..'/controls-'..cases[index].name..'-'..videoStart,config.ffmpeg),'Video start rejected')
 print('[WOOD_BANK] CASE '..cases[index].name..' wall='..videoStart);nextPhase(videoStart)
end
local function tick()
 local now=getTimestampMs();local video=toolkitVideoStatus()
 assert(video.state~='failed','Controls video failed: '..tostring(video.error))
 ownership()
 assert(now-since<10000,'Controls phase timed out: '..tostring(phases[step] and phases[step].name))
 if mode=='finish' then
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..cases[index].name..' wall='..videoStart..' file='..video.file..' frames='..video.frames..' seconds='..video.seconds)
   nextCase()
  end
 elseif mode=='settle' then if now-since>=600 then startPhase(now) end
 elseif mode=='drive' then
  local phase=phases[step]
  if phase.gait==0 and not p:isRunning() and not p:isSprinting() or phase.gait==1 and p:isRunning() or phase.gait==2 and p:isSprinting() then gaitSeen=true end
  if now-lastSample>=100 or now-since>=phase.duration then record(now) end
  if now-since>=phase.duration then
   print('[CART_CONTROLS] PHASE '..encode({case=cases[index].name,kind=item:getFullType(),phase=phase.name,
    id=id,cargoID=cargoID,cargoWeight=cargoWeight,primaryID=p:getPrimaryHandItem():getID(),secondaryID=p:getSecondaryHandItem():getID(),
    inventoryCount=ownership(),worldCount=0,luaActions=0,nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),
    drive=phase.drive,gait=phase.gait,gaitSeen=gaitSeen,elapsed=now-since,samples=sample}))
   nextPhase(now)
  end
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);cartLabGait(0);toolkitVideoStop();Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[CART_CONTROLS] FAIL '..tostring(why));print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
print('[WOOD_BANK] RUN_STARTED')
print('[CART_CONTROLS] SCOPE SP physical keyboard controls with light cargo; animation/mesh equivalence not assessed')
nextCase();Events.OnTick.Add(WoodPrototypeTick)
