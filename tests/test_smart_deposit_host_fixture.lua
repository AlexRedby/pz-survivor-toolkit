-- Offline ownership/state checks only; native Host transport/timing needs the live scenario.
local fixtureRoot=ProjectRoot..'/tests/native_queue/contributions/smart-deposit/'
-- PZ's Kahlua exposes pairs but does not expose the Lua 5.1 global next.
local nativeNext=next
next=nil
local config={kind='mp',mode='toolkit'}
local JSON=dofile(ProjectRoot..'/tests/native_queue/health/shared/QueueHealthEvents.lua')
package.preload.QueueTestSelection=function()return config end
package.preload.QueueHealthEvents=function()return JSON end
local callbacks,replies,logs={}, {}, {}
local nativePrint=print
print=function(value)logs[#logs+1]=value end
Events={OnClientCommand={Add=function(callback)callbacks.command=callback end}}
function isServer()return true end
function isClient()return false end
function getTimestampMs()return 1234 end
function sendAddItemToContainer()end
function sendRemoveItemFromContainer()end
function sendServerCommand(player,module,command,row)replies[#replies+1]={command=command,row=row}end
function instanceof(object,kind)return object.kind==kind end
local nextId,squares,failKind=0,{},nil
local function list(values)
 return {size=function()return #values end,get=function(_,i)return values[i+1]end,isEmpty=function()return #values==0 end}
end
local function container()
 local c={values={},capacity=10}
 function c:getItems()return list(self.values)end
 function c:AddItem(value)
  assert(value~=failKind,'simulated native item creation failure')
  local item=value
  if type(value)=='string'then
   nextId=nextId+1;item={id=nextId,kind='InventoryItem',fullType=value,weight=value=='Base.Apple'and .1 or .05}
   function item:getID()return self.id end
   function item:getFullType()return self.fullType end
   function item:getUnequippedWeight()return self.weight end
   function item:getContainer()return self.container end
   function item:setName(v)self.name=v end
   function item:setCustomWeight()end
   function item:setActualWeight(v)self.weight=v end
   function item:setWeight(v)self.weight=v end
  end
  self.values[#self.values+1]=item;item.container=self;return item
 end
 function c:Remove(item)
  for i,value in ipairs(self.values)do if item==value then table.remove(self.values,i);item.container=nil;return end end
  error('remove missing item')
 end
 function c:getItemById(id)for _,item in ipairs(self.values)do if item.id==id then return item end end end
 function c:getCapacityWeight()local n=0;for _,item in ipairs(self.values)do n=n+item.weight end;return n end
 function c:setType(v)self.type=v end
 function c:setCapacity(v)self.capacity=v end
 function c:setExplored()end
 function c:getCapacity()return self.capacity end
 function c:getEffectiveCapacity()return self.capacity end
 function c:hasRoomFor(player,item)
  return self:getCapacityWeight()+(type(item)=='number'and item or item.weight)<=self.capacity
 end
 return c
end
local function square(x,y,z)
 local key=x..','..y..','..z;if squares[key]then return squares[key]end
 local s={x=x,y=y,z=z,objects={}}
 function s:getX()return self.x end
 function s:getY()return self.y end
 function s:getZ()return self.z end
 function s:canStand()return true end
 function s:isFree()return true end
 function s:getRoom()return nil end
 function s:getObjects()return list(self.objects)end
 function s:getSpecialObjects()return list({})end
 function s:isBlockedTo()return false end
 function s:AddSpecialObject(object)self.objects[#self.objects+1]=object;object.square=self end
 function s:transmitRemoveItemFromSquare(object)
  for i,value in ipairs(self.objects)do if value==object then table.remove(self.objects,i);object.square=nil;return end end
 end
 squares[key]=s;return s
end
local cell={getGridSquare=function(_,x,y,z)return square(x,y,z)end}
function getCell()return cell end
IsoThumpable={new=function()
 local object={kind='IsoThumpable',data={},container=container()}
 function object:getModData()return self.data end
 function object:setCanPassThrough()end
 function object:setIsContainer()end
 function object:getContainer()return self.container end
 function object:getSquare()return self.square end
 function object:getObjectIndex()
  if self.square then for i,value in ipairs(self.square.objects)do if value==self then return i-1 end end end;return -1
 end
 function object:transmitCompleteItemToClients()end
 function object:transmitModData()end
 return object
end}
local F=dofile(fixtureRoot..'QueueSmartDepositHostFixture.lua')
package.preload.QueueSmartDepositHostFixture=function()return F end
local function actor(x)
 local player={root=container(),square=square(x,100,0)}
 function player:getInventory()return self.root end
 function player:getUsername()return 'client1'end
 function player:getSquare()return self.square end
 function player:getX()return self.x or self.square:getX()+.5 end
 function player:getY()return self.y or self.square:getY()+.5 end
 function player:getZ()return self.z or self.square:getZ()end
 player.original=player.root:AddItem('Base.Hammer');return player
end
local function rejected(callback,...)
 local ok=pcall(callback,...);assert(not ok,'unsafe/out-of-order operation was accepted')
end
local function transfer(s,phase)
 local ordered={phase.sampleIds[4],phase.sampleIds[3],phase.sampleIds[2],phase.sampleIds[1]}
 for i=1,3 do
  local item=s.player.root:getItemById(ordered[i]);s.player.root:Remove(item);s.stores[phase.order[4-i]]:AddItem(item)
 end
 return ordered
end
local function originalOnly(player)
 assert(#player.root.values==1 and player.root:getItemById(player.original.id)==player.original,'original inventory was not exactly preserved')
end

-- Two native-shaped endpoint transitions keep the fourth item and all rejected extras in root.
local player=actor(100);local s=F.prepare(player)
assert(#s.ids.crates==3 and #s.ids.originalRootIds==1)
for index=1,2 do
 local at=F.origin(s,index);assert(at.ready and at.token==s.token and at.index==index)
 player.x=player.square:getX()+.1
 local away=F.origin(s,index);assert(not away.ready and #F.snapshot(s).items==0,'origin check changed fixture or accepted wrong fractional position')
 rejected(F.seed,s,index,{1,2,3});player.x=nil
 rejected(F.seed,s,index,{1,1,3});rejected(F.seed,s,index,{1,2,4})
 local phase=F.seed(s,index,{2,1,3});rejected(F.seed,s,index,{2,1,3})
 rejected(F.origin,s,index)
 local seed=F.snapshot(s);assert(#seed.items==9 and #seed.rootIds==5)
 rejected(F.extras,s,index);rejected(F.effect,s,index,{phase.sampleIds[1],phase.sampleIds[2],phase.sampleIds[3],player.original.id})
 local ordered=transfer(s,phase);local effect=F.effect(s,index,ordered);assert(#effect.items==9)
 rejected(F.effect,s,index,ordered);rejected(F.extras,s,3-index)
 F.extras(s,index);rejected(F.extras,s,index);rejected(F.release,s,index)
 local full=F.full(s,index);assert(#full.items==12)
 local foreign=s.stores[1]:AddItem('Base.Pencil')
 rejected(F.release,s,index);rejected(F.abort,s)
 assert(F.find(s,phase.sampleIds[1])~=nil and foreign:getContainer()==s.stores[1],'foreign-content refusal deleted owned/foreign items')
 s.stores[1]:Remove(foreign)
 local release=F.release(s,index)
 assert(#release.removedIds==12 and #release.snapshot.items==0 and #release.snapshot.rootIds==1)
 for _,crate in ipairs(release.snapshot.crates)do assert(#crate.itemIds==0 and crate.weight==0)end
 rejected(F.release,s,index);originalOnly(player)
end
local restored=F.cleanup(s)
assert(restored.removedCrates==3 and restored.ownedAbsent and restored.ownedRemaining==0 and F.absent(s.ids))
originalOnly(player)

-- A failed seed already owns several objects/items; abort must find those exact IDs.
player=actor(200);s=F.prepare(player);failKind='Base.Screws'
rejected(F.seed,s,1,{1,2,3});failKind=nil
local abort=F.abort(s)
assert(#abort.removedIds==4 and abort.removedCrates==3 and F.absent(s.ids));originalOnly(player)

-- A forged owner token prevents deletion of a crate even when all its contents are owned.
player=actor(300);s=F.prepare(player);F.seed(s,1,{1,2,3})
local object=s.crates[3];local token=object.data.SmartDepositHostOwner;object.data.SmartDepositHostOwner='foreign'
rejected(F.abort,s)
assert(#player.root.values==5 and object:getObjectIndex()>=0,'foreign-token refusal changed the fixture')
object.data.SmartDepositHostOwner=token;F.abort(s);originalOnly(player)

local function openServer(x)
 replies={};player=actor(x);dofile(fixtureRoot..'ZZSmartDepositHostServer.lua')
 callbacks.command(F.module,'Prepare',player,{case='partial',spawn={x=x,y=100,z=0}})
 local reply=replies[#replies];assert(reply.command=='Prepared');return player,reply.row
end
-- The public server boundary rejects a wrong token/phase and never yields a success receipt.
local ids;player,ids=openServer(400)
callbacks.command(F.module,'Seed',player,{case='partial',token='foreign',index=1,order={1,2,3}})
assert(replies[#replies].command=='Failed'and replies[#replies].row.restored);originalOnly(player);assert(F.absent(ids))
player,ids=openServer(500)
callbacks.command(F.module,'Seed',player,{case='partial',token=ids.token,index=2,order={1,2,3}})
assert(replies[#replies].command=='Failed'and replies[#replies].row.restored);originalOnly(player);assert(F.absent(ids))
player,ids=openServer(600)
callbacks.command(F.module,'Origin',player,{case='partial',token=ids.token,index=1})
assert(replies[#replies].command=='Origind'and replies[#replies].row.ready,'server origin response contract changed')
callbacks.command(F.module,'Seed',player,{case='partial',token=ids.token,index=1,order={1,2,3}})
assert(replies[#replies].command=='Seeded','server seed response contract changed')
callbacks.command(F.module,'Abort',player,{case='partial',token=ids.token,index=1})
assert(replies[#replies].command=='Abortd'and replies[#replies].row.restored);originalOnly(player);assert(F.absent(ids))
assert(logs[#logs]:find('[SMART_DEPOSIT_HOST] ABORT ',1,true),'abort must remain a failing verifier event, never COMPLETE')
print=nativePrint
next=nativeNext
print('PASS Smart Deposit Host fixture: endpoint conservation, retained overflow, exact release/partial abort, replay, foreign IDs/crates and server token/phase guards')
