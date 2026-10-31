-- Shared authority and read-only evidence. Only preparePhase seeds food ages.
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local F={module='StorageFoodAgeTest',fillersPerPhase=60,phases={}}
for _,mode in ipairs({'clean','vanilla'})do for _,size in ipairs({199,200})do
 for _,exposure in ipairs({'visible','hidden','clipped'})do F.phases[#F.phases+1]={paneMode=mode,size=size,exposure=exposure}end
end end
function F.role()return isServer()and 'server'or isClient()and 'client'or 'sp'end
function F.emit(event,row)
 row=row or {};row.schema=2;row.suite='storage-profile';row.case='inventory-food-age'
 row.kind=config.kind;row.mode=config.mode;row.role=F.role()
 print('[STORAGE_PROFILE] '..event..' '..JSON.encode(row))
end
function F.clock()
 return {minutesPerDay=getGameTime():getMinutesPerDay(),foodRotSpeed=getSandboxOptions():getOptionByName('FoodRotSpeed'):getValue(),
  foodRemoval=getSandboxOptions():getOptionByName('DaysForRottenFoodRemoval'):getValue()}
end
function F.sameClock(a,b)
 for key,value in pairs(a)do assert(b[key]==value,'food-age clock/sandbox changed: '..key)end
end
function F.originalItems(player)
 local out={};local items=player:getInventory():getItems()
 for i=0,items:size()-1 do local item=items:get(i);assert(not out[item:getID()]);out[item:getID()]=item end
 return out
end
function F.originalPreserved(player,initial,owned)
 local items=player:getInventory():getItems();local count=0
 for i=0,items:size()-1 do local item=items:get(i)
  assert(initial[item:getID()]==item or owned and owned[item:getID()]==item,'unexpected original inventory item')
  if initial[item:getID()]==item then count=count+1 end
 end
 local expected=0;for id,item in pairs(initial)do expected=expected+1;assert(player:getInventory():getItemById(id)==item,'original item identity changed')end
 assert(count==expected,'original inventory cardinality changed');return count
end
function F.newSession(player)
 return {player=player,token='food-age:'..player:getUsername()..':'..getTimestampMs(),initial=F.originalItems(player),
  clock=F.clock(),removed=0,fillerRemoved=0,objectsRemoved=0,index=0}
end
function F.setup(s,extra)
 local row={phases=#F.phases,foodType=(isClient()or isServer())and 'Base.Cabbage'or 'Base.Apple',
  naturalAgeing=true,ageControl='phase-setup-only',physicalInput=false,clockUnchanged=true,forcedAgeUpdates=0,
  observationAgeWrites=0,fillersPerPhase=F.fillersPerPhase,clock=s.clock,minutesPerDay=s.clock.minutesPerDay,originalMinutesPerDay=s.clock.minutesPerDay,
  network=isClient()or isServer(),initialStateReplication=isClient()or isServer(),periodicAgeReplication=false}
 for key,value in pairs(extra or {})do assert(row[key]==nil,'duplicate food-age setup field');row[key]=value end
 F.emit('AGE_SETUP',row)
end
function F.placementAt(origin)
 if not origin or not origin:isOutside()or not origin:canStand()then return end
 for _,offset in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}})do
  local square=getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ())
  if square and square:isOutside()and not square:getRoom()and square:canStand()and square:isFree(false)
   and square:getObjects():size()<=1 and square:getSpecialObjects():size()==0 and not origin:isBlockedTo(square)then return square end
 end
end
function F.chooseOrigin(player)
 local origin=assert(player:getSquare());if F.placementAt(origin)then return origin end
 for radius=1,12 do for dx=-radius,radius do for dy=-radius,radius do
  if math.max(math.abs(dx),math.abs(dy))==radius then
   local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
   if square and square:isFree(false)and F.placementAt(square)then return square end
  end
 end end end
 error('no loaded outdoor food-age fixture origin within twelve tiles')
end
local function objectAt(desc)
 local square=desc and getCell():getGridSquare(desc.x,desc.y,desc.z)
 if not square or desc.index<0 or desc.index>=square:getObjects():size()then return end
 local object=square:getObjects():get(desc.index)
 if object and object:getSquare()==square and object:getModData().FoodAgeOwner==desc.token then return object end
end
function F.absent(ids)return not ids.object or not objectAt(ids.object)end
function F.conserved(s,p)
 F.sameClock(s.clock,F.clock());F.originalPreserved(s.player,s.initial,p.endpoint=='root'and p.owned or nil)
 local items=p.container:getItems();local count=0
 for i=0,items:size()-1 do local item=items:get(i);local id=item:getID()
  if p.owned[id]then assert(p.owned[id]==item and item:getContainer()==p.container,'owned identity/endpoint changed');count=count+1
  else assert(p.endpoint=='root'and s.initial[id]==item,'foreign fixture content')end
 end
 assert(count==#p.foods+#p.fillers,'owned fixture cardinality changed')
 for id,item in pairs(p.owned)do assert(p.container:getItemById(id)==item,'owned fixture item missing')end
end
function F.preparePhase(s,index)
 assert(not s.phase and index==s.index+1 and F.phases[index],'out-of-order food-age phase')
 local spec=F.phases[index];local p={index=index,spec=spec,foods={},fillers={},owned={},foodIds={},fillerIds={}}
 s.phase=p;s.index=index;p.endpoint=isServer()and 'ambient'or 'root';p.container=s.player:getInventory()
 if isServer()then
  local square=assert(F.placementAt(s.player:getSquare()),'no free adjacent food-age crate tile')
  p.object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
  p.object:setBlockAllTheSquare(true);p.object:setIsContainer(true);p.container=assert(p.object:getContainer())
  p.container:setType('crate');p.container:setCapacity(100);p.object:getModData().FoodAgeOwner=s.token..':'..index
  square:AddSpecialObject(p.object)
 end
 local world=getGameTime():getWorldAgeHours();local foodType=isServer()and 'Base.Cabbage'or 'Base.Apple'
 for i=1,spec.size do
  local item=assert(p.container:AddItem(foodType));assert(instanceof(item,'Food'),'native food required')
  assert(item:getOffAge()==(isServer()and 2 or 5)and item:getOffAgeMax()==(isServer()and 4 or 8),'native freshness thresholds changed')
  if isServer()then assert(item:isCookable(),'authority food must remain in native process list')end
  item:setAge(i==spec.size and item:getOffAge()-(isServer()and .008 or .004)or .1);item:setLastAged(world)
  p.foods[i]=item;p.foodIds[i]=item:getID();p.owned[item:getID()]=item
 end
 for i=1,F.fillersPerPhase do
  local item=assert(p.container:AddItem('Base.Pencil'));assert(not instanceof(item,'Food'),'nonfood viewport filler required')
  p.fillers[i]=item;p.fillerIds[i]=item:getID();p.owned[item:getID()]=item
 end
 p.tail=p.foods[#p.foods];p.head=p.foods[1];p.beforeAge=p.tail:getAge();p.beforeWorld=world
 p.rotSpeed=({1.7,1.4,1,.7,.4})[s.clock.foodRotSpeed]or 1
 p.potentialThresholdWorld=world+(p.tail:getOffAge()-p.beforeAge)*24/p.rotSpeed
 p.ids={index=index,token=s.token,foodType=foodType,foodIds=p.foodIds,fillerIds=p.fillerIds,tailId=p.tail:getID(),
  endpoint=p.endpoint,ageBefore=p.beforeAge,worldBefore=world,potentialThresholdWorld=p.potentialThresholdWorld,clock=s.clock}
 if p.object then
  local square=p.object:getSquare();p.ids.object={x=square:getX(),y=square:getY(),z=square:getZ(),index=p.object:getObjectIndex(),token=p.object:getModData().FoodAgeOwner}
  p.container:setExplored(true);p.object:transmitCompleteItemToClients();p.object:transmitModData()
 end
 F.conserved(s,p);return p.ids
end
function F.resolve(s,ids)
 local object=objectAt(ids.object);if not object then return end
 local container=object:getContainer();if not container then return end
 local p={index=ids.index,spec=F.phases[ids.index],ids=ids,object=object,container=container,endpoint='ambient',
  foodIds=ids.foodIds,fillerIds=ids.fillerIds,foods={},fillers={},owned={},beforeAge=ids.ageBefore,beforeWorld=ids.worldBefore,
  potentialThresholdWorld=ids.potentialThresholdWorld}
 for _,pair in ipairs({{ids.foodIds,p.foods},{ids.fillerIds,p.fillers}})do
  for _,id in ipairs(pair[1])do local item=container:getItemById(id);if not item then return end
   pair[2][#pair[2]+1]=item;p.owned[id]=item
  end
 end
 p.tail=assert(container:getItemById(ids.tailId));p.head=p.foods[1]
 for _,item in ipairs(p.foods)do assert(instanceof(item,'Food')and item:getFullType()==ids.foodType,'replicated food type differs')end
 F.conserved(s,p);return p
end
function F.snapshot(s,p)
 F.conserved(s,p);assert(not p.tail:isFrozen()and not p.tail:isBurnt(),'ordinary unfrozen food required')
 return {index=p.index,headId=p.head:getID(),tailId=p.tail:getID(),foodType=p.tail:getFullType(),endpoint=p.endpoint,
  world=getGameTime():getWorldAgeHours(),headAge=p.head:getAge(),tailAge=p.tail:getAge(),lastAged=p.tail:getLastAged(),
  headFresh=p.head:isFresh(),tailFresh=p.tail:isFresh(),count=#p.foods,identities=true,clock=F.clock()}
end
function F.receipt(s,p)
 local snap=F.snapshot(s,p);local spec=p.spec
 return {index=p.index,size=spec.size,paneMode=spec.paneMode,exposure=spec.exposure,foodType=snap.foodType,
  foodIds=p.foodIds,headId=snap.headId,tailId=snap.tailId,ageBefore=p.beforeAge,ageAfter=snap.tailAge,
  offAge=p.tail:getOffAge(),offAgeMax=p.tail:getOffAgeMax(),worldBefore=p.beforeWorld,worldAfter=snap.world,
  headFresh=snap.headFresh,tailFresh=snap.tailFresh,identities=true,endpoint=p.endpoint,naturalAgeing=true,
  observationAgeWrites=0,forcedAgeUpdates=0,minutesPerDay=s.clock.minutesPerDay,clock=F.clock()}
end
function F.release(s,abort)
 local p=s.phase;if not p then return end
 if not abort then F.conserved(s,p)end
 for _,pair in ipairs({{p.foods,'removed'},{p.fillers,'fillerRemoved'}})do for _,item in ipairs(pair[1])do
  local container=item:getContainer()
  if container then assert(container==p.container,'refusing foreign fixture endpoint');container:Remove(item)
   if isServer()then sendRemoveItemFromContainer(container,item)end
   s[pair[2]]=s[pair[2]]+1
  end
 end end
 if p.object and p.object:getObjectIndex()>=0 then
  assert(p.object:getModData().FoodAgeOwner==s.token..':'..p.index,'refusing foreign food-age crate')
  assert(p.container:getItems():isEmpty(),'refusing crate cleanup with foreign content')
  p.object:getSquare():transmitRemoveItemFromSquare(p.object)
  if p.object:getObjectIndex()>=0 then p.object:removeFromWorld();p.object:removeFromSquare()end
  assert(p.object:getObjectIndex()<0,'owned food-age crate survived');s.objectsRemoved=s.objectsRemoved+1
 end
 s.phase=nil;return {index=p.index,removed=#p.foods,fillerRemoved=#p.fillers,objectRemoved=p.object~=nil}
end
function F.restored(s,extra)
 assert(not s.phase,'unfinished food-age phase');F.sameClock(s.clock,F.clock())
 local row=extra or {};row.ownedRemoved=s.removed;row.fillerRemoved=s.fillerRemoved;row.objectsRemoved=s.objectsRemoved
 row.originalItems=F.originalPreserved(s.player,s.initial);row.items=true;row.settings=true;row.phases=s.index
 row.clock=F.clock();row.minutesPerDay=s.clock.minutesPerDay;row.originalMinutesPerDay=s.clock.minutesPerDay;row.clockUnchanged=true
 F.emit('AGE_RESTORED',row);F.emit('AGE_COMPLETE',{phases=s.index,restored=true});return row
end
return F
