-- Real sprite-derived appliances and native Food processing; snapshots only read.
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local F={module='FoodCoolingTest',names={'powered-cooling','cold-to-ambient','ambient-to-cold','power-off-thaw'},hours={.6,.5,.5,1.7}}
F.case=(config.cases or {'appliances'})[1]
F.collapsedStacks=F.case=='collapsed-stacks'
F.controls={ElecShutModifier=-1,AllowExteriorGenerator=true,FoodRotSpeed=3,FridgeFactor=3}
local observedOption='DaysForRottenFoodRemoval'
function F.role()return isServer()and 'server'or isClient()and 'client'or 'sp'end
function F.emit(event,value)
 value=value or {};value.suite='food-cooling';value.case=F.case;value.kind=config.kind;value.mode=config.mode;value.role=F.role()
 print('[FOOD_COOLING_TEST] '..event..' '..JSON.encode(value))
end
function F.configure()
 local original={minutesPerDay=getGameTime():getMinutesPerDay(),sandbox={}}
 for name,value in pairs(F.controls)do
  local option=assert(getSandboxOptions():getOptionByName(name),'missing sandbox option '..name)
  original.sandbox[name]=option:getValue()
 end
 original.sandbox[observedOption]=assert(getSandboxOptions():getOptionByName(observedOption)):getValue()
 for name,value in pairs(F.controls)do getSandboxOptions():getOptionByName(name):setValue(value)end
 getSandboxOptions():toLua();getGameTime():setMinutesPerDay(5)
 return original
end
function F.restore(original)
 assert(getSandboxOptions():getOptionByName(observedOption):getValue()==original.sandbox[observedOption],'unmodified food-removal setting changed')
 for name in pairs(F.controls)do getSandboxOptions():getOptionByName(name):setValue(original.sandbox[name])end
 getSandboxOptions():toLua();getGameTime():setMinutesPerDay(original.minutesPerDay)
end
local function options()
 local result={};for name in pairs(F.controls)do result[name]=getSandboxOptions():getOptionByName(name):getValue()end
 result[observedOption]=getSandboxOptions():getOptionByName(observedOption):getValue();return result
end
F.options=options
local function array(list)local out={};for i=0,list:size()-1 do out[#out+1]=list:get(i)end;return out end
function F.originalItems(player)
 local out={};for _,item in ipairs(array(player:getInventory():getItems()))do out[item:getID()]=item end;return out
end
function F.actor(player)
 local square=assert(player:getSquare())
 return {x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square:getX(),squareY=square:getY(),squareZ=square:getZ(),
  moving=player:isPlayerMoving(),hasPath=player:getPath2()~=nil,state=player:getCurrentStateName(),timedActions=player:hasTimedActions()}
end
function F.originStatus(s,luaQueueIdle)
 local actor=F.actor(s.player);local origin=s.ids.origin
 local at=actor.squareX==origin.x and actor.squareY==origin.y and actor.squareZ==origin.z
  and not actor.moving and not actor.hasPath and not actor.timedActions and luaQueueIdle~=false
 if at then
  local previous=s.originStablePosition
  if not previous or math.abs(actor.x-previous.x)>.01 or math.abs(actor.y-previous.y)>.01 or math.abs(actor.z-previous.z)>.01 then
   s.originStableAt=getTimestampMs();s.originStablePosition={x=actor.x,y=actor.y,z=actor.z}
  end
 else s.originStableAt=nil;s.originStablePosition=nil end
 local stable=s.originStableAt and getTimestampMs()-s.originStableAt or 0
 return {ready=at and stable>=1000,actor=actor,origin=origin,stableMs=stable}
end
function F.settled(s,index,sequence,purpose)
 local row=F.originStatus(s);row.index=index;row.sequence=sequence;row.purpose=purpose
 if row.ready and s.settledSequence~=sequence then
  s.settledSequence=sequence;s.settledIndex=index
  if isServer()then F.emit('SETTLED',row)end
 end
 return row
end
local function point(object)
 local square=assert(object:getSquare());return {x=square:getX(),y=square:getY(),z=square:getZ(),index=object:getObjectIndex(),token=object:getModData().FoodCoolingOwner}
end
local function objectAt(descriptor)
 local square=getCell():getGridSquare(descriptor.x,descriptor.y,descriptor.z)
 if not square or descriptor.index<0 or descriptor.index>=square:getObjects():size()then return end
 local object=square:getObjects():get(descriptor.index)
 if object and object:getSquare()==square and object:getModData().FoodCoolingOwner==descriptor.token then return object end
end
function F.placementAt(origin)
 if not origin or not origin:isOutside()or not origin:canStand()then return end
 local squares={}
 for _,offset in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}})do
  local square=getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ())
  if square and square:isOutside()and not square:getRoom()and square:canStand()and square:isFree(false)
   and square:getObjects():size()<=1 and square:getSpecialObjects():size()==0 and not origin:isBlockedTo(square)then squares[#squares+1]=square end
 end
 if #squares>=3 then return squares end
end
function F.chooseOrigin(player)
 local origin=assert(player:getSquare());if F.placementAt(origin)then return origin end
 for radius=1,12 do for dx=-radius,radius do for dy=-radius,radius do
  if math.max(math.abs(dx),math.abs(dy))==radius then
   local candidate=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
   if candidate and candidate:isFree(false)and F.placementAt(candidate)then return candidate end
  end
 end end end
 error('no loaded outdoor fixture origin within twelve tiles')
end
function F.prepare(player)
 local s={player=player,originalItems=F.originalItems(player),owned={}}
 F.preparing=s
 s.original=F.configure();local squares=assert(F.placementAt(player:getSquare()),'need three free outdoor adjacent appliance tiles');local token='food-cooling:'..player:getUsername()..':'..getTimestampMs();s.token=token
 s.appliance=IsoObject.new(getCell(),squares[1],assert(getSprite('appliances_refrigeration_01_0')))
 s.appliance:createContainersFromSpriteProperties()
 s.fridge=assert(s.appliance:getContainerByType('fridge'),'native refrigerator sprite has no fridge')
 s.freezer=assert(s.appliance:getContainerByType('freezer'),'native refrigerator sprite has no freezer')
 s.appliance:getModData().FoodCoolingOwner=token;squares[1]:AddTileObject(s.appliance)
 s.crate=IsoThumpable.new(getCell(),squares[2],'carpentry_01_16',false,{})
 s.crate:setBlockAllTheSquare(true);s.crate:setIsContainer(true);s.ambient=assert(s.crate:getContainer());s.ambient:setType('crate');s.ambient:setCapacity(100)
 s.crate:getModData().FoodCoolingOwner=token;squares[2]:AddSpecialObject(s.crate)
 s.generator=IsoGenerator.new(assert(instanceItem('Base.Generator')),getCell(),squares[3])
 s.generator:getModData().FoodCoolingOwner=token;s.generator:setCondition(100);s.generator:setFuel(20)
 assert(not s.generator:isConnected()and not s.generator:isActivated(),'generator must begin unplugged and inactive')
 local world=getGameTime():getWorldAgeHours();local foods={};local stackMembers={}
 for _,spec in ipairs({{'chilled',s.fridge,0},{'frozen',s.freezer,90},{'control',s.ambient,0}})do
  local count=F.collapsedStacks and (spec[1]=='chilled'and 199 or spec[1]=='frozen'and 200 or 1)or 1
  local members={};stackMembers[spec[1]]=members
  for i=1,count do
   local item=assert(spec[2]:AddItem('Base.Cabbage'));assert(instanceof(item,'Food')and item:isCookable()and item:canBeFrozen(),'ordinary processable frozen food required')
   item:setAge(.1);item:setLastAged(world);item:setFreezingTime(spec[3]);s.owned[item:getID()]=item;members[#members+1]=item:getID()
   if i==count then foods[spec[1]]=item:getID()end
  end
 end
 local capacities={}
 if F.collapsedStacks then
  for _,name in ipairs({'fridge','freezer'})do local container=s[name];local original=container:getCapacity();local weight=container:getContentsWeight()
   local required=math.max(original,math.ceil(weight));assert(required<=100,'owned cooling stack needs capacity above native limit')
   if required>original then container:setCapacity(required)end
   assert(container:getCapacity()>=weight,'owned cooling stack exceeds native appliance capacity')
   capacities[name]={original=original,configured=container:getCapacity(),fullWeight=weight}
  end
 end
 for _,container in ipairs({s.fridge,s.freezer,s.ambient})do container:setExplored(true)end
 s.ids={token=token,fridge=point(s.appliance),ambient=point(s.crate),generator=point(s.generator),foods=foods,
  stackMembers=F.collapsedStacks and stackMembers or nil,capacities=F.collapsedStacks and capacities or nil,
  fridgeIndex=s.appliance:getContainerIndex(s.fridge),freezerIndex=s.appliance:getContainerIndex(s.freezer),
  origin={x=player:getSquare():getX(),y=player:getSquare():getY(),z=player:getSquare():getZ()}}
 if isServer()then
  s.appliance:transmitCompleteItemToClients();s.appliance:transmitModData();s.crate:transmitCompleteItemToClients();s.crate:transmitModData();s.generator:transmitModData()
 end
 F.emit('SETUP',{ids=s.ids,original=s.original,controls=F.controls,minutesPerDay=5,snapshot=F.snapshot(s),
  limits={physicalInput=false,observationAgeWrites=0,forcedAgeUpdates=0,nativeDurations=true,nativeInventoryRendering=true,stackFoodProcessing=F.collapsedStacks and 'active-cookable'or nil,
   rootTransfer=F.collapsedStacks and 'singleton'or nil}})
 return s
end
function F.abort(s)
 if not s then return end
 local ok,problem=pcall(function()
  for _,item in pairs(s.owned or {})do
   local container=item:getContainer()
   if container then container:Remove(item);if isServer()then sendRemoveItemFromContainer(container,item)end end
  end
  if s.generator and s.generator:getObjectIndex()>=0 then s.generator:setActivated(false);s.generator:setConnected(false)end
  for _,key in ipairs({'appliance','crate','generator'})do
   local object=s[key]
   if object and object:getObjectIndex()>=0 then
    assert(object:getModData().FoodCoolingOwner==s.token,'refusing foreign partial fixture cleanup')
    for i=0,object:getContainerCount()-1 do assert(object:getContainerByIndex(i):getItems():isEmpty(),'refusing partial fixture with foreign content')end
    object:getSquare():transmitRemoveItemFromSquare(object)
    if object:getObjectIndex()>=0 then object:removeFromWorld();object:removeFromSquare()end
   end
  end
 end)
 if s.original then F.restore(s.original)end
 assert(ok,problem)
end
function F.resolve(player,ids)
 local appliance,crate,generator=objectAt(ids.fridge),objectAt(ids.ambient),objectAt(ids.generator)
 if not appliance or not crate or not generator or not instanceof(generator,'IsoGenerator')then return end
 local s={player=player,ids=ids,appliance=appliance,crate=crate,generator=generator,
  fridge=appliance:getContainerByIndex(ids.fridgeIndex),freezer=appliance:getContainerByIndex(ids.freezerIndex),ambient=crate:getContainer()}
 if not s.fridge or not s.freezer or not s.ambient then return end
 if ids.capacities then for name,capacity in pairs(ids.capacities)do
  assert(s[name]:getCapacity()==capacity.configured,'replicated native appliance capacity differs '..name)
 end end
 for _,id in pairs(ids.foods)do if not F.find(s,id)then return end end
 return s
end
function F.find(s,id)
 local found,endpoint,count=nil,nil,0
 for _,name in ipairs({'fridge','freezer','ambient','root'})do
  local container=name=='root'and s.player:getInventory()or s[name]
  for _,item in ipairs(array(container:getItems()))do if item:getID()==id then found,endpoint,count=item,name,count+1 end end
 end
 assert(count<=1,'duplicate native food identity');return found,endpoint,count
end
local function finite(value)assert(type(value)=='number'and value==value and math.abs(value)<math.huge,'non-finite cooling value');return value end
function F.snapshot(s)
 local row={world=finite(getGameTime():getWorldAgeHours()),minutesPerDay=getGameTime():getMinutesPerDay(),sandbox=options(),actor=F.actor(s.player),origin=s.ids.origin,foods={},containers={},
  generator={active=s.generator:isActivated(),connected=s.generator:isConnected(),fuel=finite(s.generator:getFuel()),condition=s.generator:getCondition()},
  appliance={nickLoaded=TurnOffFridges~=nil,auto=s.appliance:getModData().TOF_auto==true,unplugged=TurnOffFridges and TurnOffFridges.isUnplugged(s.appliance)or false}}
 if s.original then assert(row.sandbox[observedOption]==s.original.sandbox[observedOption],'food-removal setting changed during observation')end
 for _,name in ipairs({'fridge','freezer','ambient','root'})do
  local container=name=='root'and s.player:getInventory()or s[name];local square=container:getSourceGrid()or s.player:getSquare()
  row.containers[name]={capacity=container:getCapacity(),contentsWeight=finite(container:getContentsWeight()),type=container:getType(),powered=container:isPowered(),temperature=finite(container:getTemperature()),customTemperature=finite(container:getCustomTemperature()),
   x=square:getX(),y=square:getY(),z=square:getZ(),electricity=square:haveElectricity()}
 end
 for name,id in pairs(s.ids.foods)do
  local item,endpoint,count=F.find(s,id);assert(item,'owned food missing '..name)
  row.foods[name]={id=id,type=item:getFullType(),endpoint=endpoint,count=count,age=finite(item:getAge()),lastAged=finite(item:getLastAged()),heat=finite(item:getHeat()),
   freezingTime=finite(item:getFreezingTime()),frozen=item:isFrozen(),isFreezing=item:isFreezing(),isThawing=item:isThawing()}
 end
 return row
end
function F.begin(s,index)
 assert(F.originStatus(s).ready and s.settledIndex==index,'cooling phase needs stable authoritative observation origin')
 assert(index==(s.phaseIndex or 0)+1,'out-of-order cooling phase');s.phaseIndex=index;s.before=F.snapshot(s)
 F.emit('BEGIN',{index=index,name=F.names[index],snapshot=s.before})
 return {index=index,name=F.names[index],before=s.before}
end
function F.failureSnapshot(s,row)
 row=row or {};local ok,value=pcall(F.snapshot,s)
 if ok then row.snapshot=value else row.snapshotError=tostring(value)end;return row
end
function F.readiness(before,after,index)
 local elapsed=after.world-before.world
 if elapsed<F.hours[index]then return false,'native observation interval' end
 local chilled,frozen=after.foods.chilled,after.foods.frozen
 if index==1 or index==3 then
  if chilled.heat>.35 then return false,'food still cooling' end
 else
  if chilled.heat<.65 then return false,'food still warming' end
 end
 if index==4 then
  if frozen.frozen or frozen.freezingTime~=0 then return false,'food still thawing' end
 elseif not frozen.frozen or frozen.freezingTime~=100 then return false,'food not naturally frozen' end
 return true,'native final conditions'
end
function F.phaseReadiness(s,index,sequence)
 assert(index==s.phaseIndex and s.before,'cooling phase not begun')
 local after=F.snapshot(s);local thermalReady,reason=F.readiness(s.before,after,index);local origin=F.originStatus(s)
 local row={index=index,name=F.names[index],sequence=sequence,ready=thermalReady and origin.ready,thermalReady=thermalReady,
  reason=not origin.ready and 'observation origin not settled'or reason,elapsedWorldHours=after.world-s.before.world,snapshot=after,origin=origin}
 if row.ready and s.readinessPublished~=index then s.readinessPublished=index;F.emit('PHASE_READY',row)end
 return row
end
function F.finish(s,index)
 local readiness=F.phaseReadiness(s,index)
 assert(readiness.ready,'authoritative cooling phase not ready: '..readiness.reason)
 local after=readiness.snapshot
 local row={index=index,name=F.names[index],before=s.before,after=after,elapsedWorldHours=after.world-s.before.world}
 F.emit('PHASE',row);s.before=nil;return row
end
function F.cleanup(s)
 local before=getGameTime():getMinutesPerDay();local sandboxBefore=options();local removed=0
 -- Never delete a foreign object or item even if preparation/observation failed.
 for _,object in ipairs({s.appliance,s.crate,s.generator})do assert(object:getModData().FoodCoolingOwner==s.ids.token,'foreign cooling object')end
 for _,container in ipairs({s.fridge,s.freezer,s.ambient})do
  for _,item in ipairs(array(container:getItems()))do assert(s.owned[item:getID()]==item,'foreign appliance content')end
 end
 for id in pairs(s.owned)do
  local item=F.find(s,id)
  if item then local container=item:getContainer();container:Remove(item);if isServer()then sendRemoveItemFromContainer(container,item)end end
 end
 s.generator:setActivated(false);s.generator:setConnected(false)
 for _,object in ipairs({s.appliance,s.crate,s.generator})do
  object:getSquare():transmitRemoveItemFromSquare(object)
  if object:getObjectIndex()>=0 then object:removeFromWorld();object:removeFromSquare()end
  assert(object:getObjectIndex()<0,'owned cooling object survived cleanup');removed=removed+1
 end
 F.restore(s.original)
 return F.cleanupReceipt(s.player,s.ids,s.original,s.originalItems,removed,before,sandboxBefore)
end
function F.absent(ids)
 if objectAt(ids.fridge)or objectAt(ids.ambient)or objectAt(ids.generator)then return false end
 return true
end
function F.cleanupReceipt(player,ids,original,initial,removed,before,sandboxBefore)
 local root=player:getInventory();local count=0
 for id,item in pairs(initial)do count=count+1;assert(root:getItemById(id)==item,'original inventory identity changed')end
 local remaining=root:getItems():size();assert(remaining==count,'unexpected item in original inventory')
 for _,members in pairs(ids.stackMembers or {foods=ids.foods})do
  for _,id in pairs(members)do assert(not root:getItemById(id),'owned cooling food remains')end
 end
 assert(F.absent(ids),'owned cooling object remains')
 local row={objectsRemoved=removed==3,objectCount=removed,ownedIdsAbsent=true,ownedItemCount=ids.stackMembers and 400 or 3,originalItemsPreserved=true,originalItemCount=count,remainingOriginalCount=remaining,
  minutesPerDayBefore=before,minutesPerDayAfter=getGameTime():getMinutesPerDay(),sandboxBefore=original.sandbox,activeSandboxBeforeCleanup=sandboxBefore or F.controls,sandboxAfter=options(),queueIdle=not player:hasTimedActions()}
 assert(row.minutesPerDayAfter==original.minutesPerDay,'cooling time rate not restored')
 for name,value in pairs(original.sandbox)do assert(row.sandboxAfter[name]==value,'cooling sandbox not restored '..name)end
 F.emit('CLEANUP',row);F.emit('COMPLETE',{phases=4,restored=true});return row
end
return F
