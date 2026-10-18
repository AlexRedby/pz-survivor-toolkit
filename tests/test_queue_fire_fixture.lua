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
