-- Authority must distinguish exact returned fuel, consumption and duplicated IDs.
local root=ProjectRoot or '.'
local selection={mode='toolkit'}
local modules={QueueFireIgnition={cases={}},QueueTestSelection=selection,QueueHealthEvents={encode=function()return '{}' end},['Camping/SCampfireSystem']=true}
local nativeRequire=require
require=function(name)if modules[name]~=nil then return modules[name] end;return nativeRequire(name)end
local nextID,removed,packets=10,{},0
local function list(values)
 return {size=function()return #values end,get=function(_,i)return values[i+1] end}
end
local function container()
 local value={items={}}
 function value:getItems()return list(self.items)end
 function value:getItemById(id)
  for _,item in ipairs(self.items) do
   if item:getID()==id then return item end
   if item.class=='InventoryContainer' then local found=item:getItemContainer():getItemById(id);if found then return found end end
  end
 end
 function value:AddItem(kind)
  nextID=nextID+1
  local item={id=nextID,container=self,condition=100,pages=20,read=0,kind=kind}
  function item:getID()return self.id end
  function item:getContainer()return self.container end
  function item:getCondition()return self.condition end
  function item:getNumberOfPages()return self.pages end
  function item:setAlreadyReadPages(pages)self.read=pages end
  function item:getAlreadyReadPages()return self.read end
  function item:getFullType()return self.kind end
  function item:getFluidContainer()return nil end
  self.items[#self.items+1]=item;return item
 end
 function value:setType()end
 function value:setCapacity()end
 function value:setExplored()end
 return value
end
local squares={}
local function square(x,y,z)
 local key=x..','..y..','..z
 if not squares[key] then
  local value={x=x,y=y,z=z,objects={{}}}
  function value:getX()return self.x end
  function value:getY()return self.y end
  function value:getZ()return self.z end
  function value:AddSpecialObject(object)object.square=self;object.added=true;self.objects[#self.objects+1]=object end
  function value:removeObject(object)
   for i,value in ipairs(self.objects) do if value==object then table.remove(self.objects,i);return end end
  end
  function value:transmitRemoveItemFromSquare(object)removed[#removed+1]=object;self:removeObject(object) end
  squares[key]=value
 end
 return squares[key]
end
local function objectIndex(object)
 for i,value in ipairs(object.square.objects) do if value==object then return i-1 end end
 return -1
end
local cell={getGridSquare=function(_,x,y,z)return square(x,y,z)end}
getCell=function()return cell end
modules.QueueEnergyPlacement=function()return square(1,2,0)end
IsoThumpable={new=function(_,sq)
 local object={container=container(),data={},square=sq}
 function object:setCanPassThrough(value)self.passThrough=value end
 function object:setIsContainer()end
 function object:getContainer()return self.container end
 function object:getModData()return self.data end
 function object:getSquare()return self.square end
 function object:getObjectIndex()return objectIndex(self) end
 function object:transmitCompleteItemToClients()
  assert(self.container.items[1] and self.container.items[1].kind=='Base.Log','source transmitted without exact Log')
  self.transmitted=true;packets=packets+1
 end
 return object
end}
local targets={}
SCampfireSystem={instance={}}
function SCampfireSystem.instance:addCampfire(sq)
 assert(removed.fixture and removed.fixture.added and removed.fixture.transmitted,
  'source must be inserted/transmitted before campfire creation')
 assert(removed.fixture.container.items[1].kind=='Base.Log','source must contain Log before transmission')
 local iso={square=sq,getObjectIndex=objectIndex}
 sq:AddSpecialObject(iso)
 local target={fuelAmt=0,isLit=false,square=sq,iso=iso}
 function target:getIsoObject()
  assert(removed.fixture and removed.fixture.added,'target index captured before source insertion')
  return self.iso
 end
 targets[sq]=target;return target
end
function SCampfireSystem.instance:getLuaObjectAt(x,y,z)return targets[square(x,y,z)]end
function SCampfireSystem.instance:removeCampfire(target)targets[target.square]=nil;target.square:removeObject(target.iso) end
ISCampingMenu={getFuelDurationForItem=function()return 120 end}
isServer=function()return true end
sendAddItemToContainer=function()packets=packets+1 end
instanceof=function(value,class)return value.class==class end
local player={inventory=container()}
function player:getUsername()return 'client1' end
function player:getInventory()return self.inventory end
function player:setAlreadyReadPages()end
local Authority=assert(loadfile(root..'/tests/native_queue/fire/shared/QueueFireAuthority.lua'))()
local function item(ids) return player.inventory:getItemById(ids.book) end
local function take(ids)
 local crate=removed.fixture:getContainer()
 local log=crate:getItemById(ids.log)
 crate.items={};player.inventory.items[#player.inventory.items+1]=log;log.container=player.inventory
 return crate,log
end
-- Capture only the newly created exact crate; unrelated world objects must never be removed.
local newObject=IsoThumpable.new
IsoThumpable.new=function(...)local object=newObject(...);removed.fixture=object;return object end
local ids=Authority.prepare(player,'fuel')
assert(ids.crateX==ids.x and ids.crateY==ids.y and ids.crateZ==ids.z and removed.fixture.passThrough,
 'borrowed source must share the native campfire square and remain pass-through')
assert(ids.crateIndex<ids.objectIndex,'source must precede the removable campfire')
assert(packets==2,'MP preparation did not transmit exact crate/book')
assert(not Authority.verify(player,'fuel'),'unconsumed fuel must not pass')
local crate,log=take(ids)
player.inventory.items={item(ids)}
local target=targets[square(ids.x,ids.y,ids.z)];target.fuelAmt=120
assert(not Authority.verify(player,'fuel'),'independent unread tail must not pass')
item(ids):setAlreadyReadPages(20)
local result=assert(Authority.verify(player,'fuel'))
assert(result.logId==ids.log and result.consumed==1 and result.fuel==120 and result.tailRead)
assert(#removed==1 and removed[1]==removed.fixture,'cleanup touched another world object')
-- Toolkit missing target: borrowed Log must return exactly once to its original crate.
ids=Authority.prepare(player,'missing-target-after-expansion')
crate,log=take(ids)
assert(Authority.invalidate(player,ids.case).ok)
assert(removed.fixture:getObjectIndex()==ids.crateIndex,'campfire removal shifted the native pickup source index')
assert(not Authority.verify(player,ids.case),'borrowed fuel in root must not pass as returned')
for i,value in ipairs(player.inventory.items) do if value==log then table.remove(player.inventory.items,i);break end end
crate.items={log};log.container=crate
item(ids):setAlreadyReadPages(20)
local duplicate=player.inventory:AddItem('Base.Log');duplicate.id=ids.log
assert(not Authority.verify(player,ids.case),'duplicate fuel identity must not pass')
for i,value in ipairs(player.inventory.items) do if value==duplicate then table.remove(player.inventory.items,i);break end end
log.condition=99
assert(not Authority.verify(player,ids.case),'changed returned fuel must not pass as unspent')
log.condition=100
result=assert(Authority.verify(player,ids.case))
assert(result.sourceCount==1 and result.rootCount==0 and result.unspent and result.removed and result.tailRead)
-- Native control remains unspent in root with an unread tail; authority observes, never repairs it.
selection.mode='native'
ids=Authority.prepare(player,'missing-target-after-expansion')
crate,log=take(ids);Authority.invalidate(player,ids.case)
result=assert(Authority.verify(player,ids.case))
assert(result.rootCount==1 and result.sourceCount==0 and not result.tailRead and result.unspent)
-- Native MP observes a lost tail after exact fuel consumption; SP still requires it.
for _,kind in ipairs({'sp','mp'}) do
 selection.kind=kind
 ids=Authority.prepare(player,'fuel');crate,log=take(ids)
 for i,value in ipairs(player.inventory.items) do if value==log then table.remove(player.inventory.items,i);break end end
 target=targets[square(ids.x,ids.y,ids.z)];target.fuelAmt=120
 if kind=='sp' then
  assert(not Authority.verify(player,'fuel'),'native SP must retain the independent tail')
  item(ids):setAlreadyReadPages(20)
 end
 result=assert(Authority.verify(player,'fuel'))
 assert(result.consumed==1 and result.fuel==120 and result.tailRead==(kind=='sp'),'native MP reading observation changed')
end
print('native Fire authority fixture tests passed')

-- MP complete runs after OnTick; next-frame object processing may already burn one unit.
local early,tick
Events={OnTick={Add=function(callback)tick=callback end},OnTickEvenPaused={Add=function(callback)early=callback end}}
isClient=function()return false end
getSprite=function(name)return name end
local sq=square(2,2,0)
sq.AddTileObject=sq.AddSpecialObject
IsoThumpable.new=function(...)
 local object=newObject(...)
 object.transmitCompleteItemToClients=function()end
 return object
end
local barbecue
IsoBarbecue={new=function(_,square)
 barbecue={class='IsoBarbecue',square=square,fuel=0,on=false,getObjectIndex=objectIndex}
 function barbecue:getSquare()return self.square end
 function barbecue:getFuelAmount()return self.fuel end
 function barbecue:setFuelAmount(value)self.fuel=value end
 function barbecue:isLit()return self.on end
 function barbecue:isPropaneBBQ()return false end
 function barbecue:transmitCompleteItemToClients()end
 return barbecue
end}
modules['Camping/ISCampingMenu']=true
local Ignition=assert(loadfile(root..'/tests/native_queue/fire/shared/QueueFireIgnition.lua'))()
ids=Ignition.prepare(player,'bbq-kindle')
tick();barbecue.on=true
if early then early()end
barbecue.fuel=359;tick()
item(ids):setAlreadyReadPages(20)
local observed,problem=Ignition.verify(player,'bbq-kindle')
assert(observed,problem)
assert(observed.effectFuel==360 and observed.fuel==359,'native fuel effect was sampled after burning')
print('Fire ignition observation precedes next-frame native fuel burn.')

-- Report actual failed controls without weakening Toolkit ignition/resource gates.
function SCampfireSystem.instance:addCampfire(sq)
 local iso={square=sq,getObjectIndex=objectIndex};sq:AddSpecialObject(iso)
 local target={fuelAmt=0,isLit=false,square=sq,iso=iso}
 function target:getIsoObject()return self.iso end
 function target:addFuel(value)self.fuelAmt=self.fuelAmt+value end
 targets[sq]=target;return target
end
function player.inventory:Remove(item)
 for i,value in ipairs(self.items) do if value==item then table.remove(self.items,i);return end end
end
sendRemoveItemFromContainer=function()end
selection.mode='toolkit'
ids=Ignition.prepare(player,'kindle-retry')
item(ids):setAlreadyReadPages(20)
assert(not Ignition.verify(player,ids.case),'Toolkit unlit retry with unused sticks must fail')
selection.mode='native'
target=targets[square(ids.x,ids.y,ids.z)];target.fuelAmt=359
assert(not Ignition.verify(player,ids.case),'failed native retry must not hide changed fuel')
target.fuelAmt=360
local reserve=player.inventory:getItemById(ids.resources[3].id);reserve.condition=99
assert(not Ignition.verify(player,ids.case),'failed native retry must not hide changed resource condition')
reserve.condition=100
observed,problem=Ignition.verify(player,ids.case)
assert(observed,problem)
assert(not observed.lit and observed.effectFuel==360 and observed.fuel==360
 and not observed.resources[3].consumed,'failed native retry receipt fabricated ignition or resource consumption')

-- Exercise the real passive observer without installing any hooks into product actions.
do
 local function observer(mode,kind)
  local enabled=mode=='toolkit'
  local config={mode=mode,kind=kind,mods={}}
  local actor={}
  local contains,tailStarted=false,false
  local queue={character=actor}
  function actor:getCharacterActions()return {contains=function()return contains end}end
  local lifecycle={begin=function()return enabled end,finish=function()end,
   flush=function(current)return 'completed',current.current end,
   current=function()return queue.current end}
  PZSurvivorToolkit={ActionQueueLifecycle=lifecycle}
  ISTimedActionQueue={queues={[actor]=queue}}
  getPlayer=function()return actor end
  getTimestampMs=function()return 0 end
  require=function(name)
   if name=='QueueTestSelection' then return config end
   if name=='QueueFireIgnition' or name=='QueueHealthEvents' or name=='QueueFireTidy' then return {} end
   return true
  end
  local file=assert(io.open(root..'/tests/native_queue/fire/client/QueueFireIgnitionClient.lua'))
  local source=file:read('*a');file:close()
  source=source:gsub('\nreturn Client','\nClient.fixtureReset=reset;Client.fixtureState=function()return state end;Client.fixtureSettled=completionSettled\nreturn Client')
  local client=assert(loadstring(source))()
  client.fixtureReset('kindle-retry')
  local state=client.fixtureState()
  state.tail={isStarted=function()return tailStarted end}
  local function action()
   local value={Type='ISLightFromKindle',character=actor,action={}}
   queue.current=value;queue.queue={value,state.tail};return value
  end
  return lifecycle,client,state,action,function(value)contains=value end,function(value)tailStarted=value end
 end
 for _,mode in ipairs({'native','toolkit'}) do for _,kind in ipairs({'sp','mp'}) do
  local lifecycle,client,state,action=observer(mode,kind)
  for iteration=1,2 do
   local parent=action()
   assert(lifecycle.begin(parent,'perform')==(mode=='toolkit'))
   lifecycle.finish(parent,'perform',true)
   if kind=='sp' then
    assert(lifecycle.begin(parent,'complete')==(mode=='toolkit'))
    lifecycle.finish(parent,'complete',true)
   end
   lifecycle.flush(ISTimedActionQueue.queues[parent.character])
  end
  state.attempts=2;client.fixtureSettled()
  local count=mode=='toolkit' and 2 or 0
  assert(state.nativeCompletion.perform==count and state.nativeCompletion.complete==(kind=='sp' and count or 0)
   and state.nativeCompletion.flush==count,'observer phase counters do not describe the real SP/Host mode')
  client.fixtureReset('kindle-retry');state=client.fixtureState()
  assert(state.nativeCompletion.perform==0 and state.nativeCompletion.complete==0 and state.nativeCompletion.flush==0
   and next(state.completionActions)==nil,'a new RNG trial retained the preceding completion counters')
 end end
 for _,fault in ipairs({'complete-first','duplicate-perform','duplicate-finish','wrong-owner','native-present','missing-complete','duplicate-flush','early-tail','unflushed-tail'}) do
  local lifecycle,client,state,action,contains,tailStarted=observer('toolkit','sp')
  local parent=action();state.attempts=1
  local ok=pcall(function()
   if fault=='complete-first' then lifecycle.begin(parent,'complete');return end
   if fault=='wrong-owner' then ISTimedActionQueue.queues[parent.character].current={};lifecycle.begin(parent,'perform');return end
   lifecycle.begin(parent,'perform')
   if fault=='duplicate-perform' then lifecycle.begin(parent,'perform');return end
   lifecycle.finish(parent,'perform',true)
   if fault=='duplicate-finish' then lifecycle.finish(parent,'perform',true);return end
   if fault~='missing-complete' then lifecycle.begin(parent,'complete');lifecycle.finish(parent,'complete',true) end
   if fault=='native-present' then contains(true) end
   if fault=='early-tail' then tailStarted(true) end
   if fault=='unflushed-tail' then client.fixtureSettled();return end
   lifecycle.flush(ISTimedActionQueue.queues[parent.character])
   if fault=='duplicate-flush' then lifecycle.flush(ISTimedActionQueue.queues[parent.character]) end
  end)
  assert(not ok,'native Kindle observer accepted '..fault)
 end
 print('Fire Kindle observer checks passed: phase ownership, exact counts, native removal, tail ordering and trial reset.')
end
