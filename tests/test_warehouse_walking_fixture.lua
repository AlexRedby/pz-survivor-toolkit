-- Offline protocol/ownership checks. Actual actions and replication need fresh Host clients.
local fixtureRoot=ProjectRoot..'/tests/native_queue/warehouse-walking/'
local nativeNext=next;next=nil
local config={kind='mp',mode='toolkit',cases={'walk'}}
package.preload.QueueTestSelection=function()return config end
package.preload.QueueHealthEvents=function()return dofile(ProjectRoot..'/tests/native_queue/health/shared/QueueHealthEvents.lua')end
package.preload['PZSurvivorToolkit/ManifestModel']=function()return {item=function(item)
 local name=item.custom and item.name or nil
 local cat=item.fullType:find('Hotdog',1,true)and'Food'or item.fullType=='Base.Bandage'and'FirstAid'or'Material'
 return {ft=item.fullType,name=name,cat=cat,key=item.fullType..':'..(name or '')..':'..cat}
end}end
local callbacks,replies,logs={},{},{}
local nativePrint=print;print=function(value)logs[#logs+1]=value end
Events={OnClientCommand={Add=function(fn)callbacks.command=fn end},OnTick={Add=function(fn)callbacks.tick=fn end}}
function isServer()return true end
function isClient()return false end
local clock=1234
function getTimestampMs()return clock end
function sendAddItemToContainer()end
function sendRemoveItemFromContainer()end
function sendServerCommand(player,module,command,row)replies[#replies+1]={role=player:getUsername(),command=command,row=row}end
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
   function item:setCustomName(v)self.custom=v end
   function item:getModData()self.data=self.data or {};return self.data end
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
 function c:getType()return self.type end
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
 function s:getWorldObjects()return list(self.worldObjects or {})end
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
local F=dofile(fixtureRoot..'shared/WarehouseWalkingFixture.lua')
package.preload.WarehouseWalkingFixture=function()return F end
local function actor(role,x)
 local p={root=container(),square=square(x,100,0),role=role}
 function p:getInventory()return self.root end
 function p:getUsername()return self.role end
 function p:getOnlineID()return self.role=='client1'and 1 or 2 end
 function p:getSquare()return self.square end
 function p:getX()return self.square:getX()+.5 end
 function p:getY()return self.square:getY()+.5 end
 function p:getZ()return self.square:getZ()end
 p.original=p.root:AddItem('Base.Hammer');return p
end
local function players(x)return {client1=actor('client1',x),client2=actor('client2',x)}end
local function rejected(fn,...)assert(not pcall(fn,...),'unsafe walking operation accepted')end
local s=F.prepare(players(100));assert(#s.crates==12 and #F.phases==16)
assert(s.ids.actorOrigin==nil and s.ids.actorOrigins.client1.y==s.ids.origin.y-2 and s.ids.actorOrigins.client2.y==s.ids.origin.y+2)
for _,role in ipairs({'client1','client2'})do local route=s.ids.routeOrigins[role];assert(route.x==s.ids.origin.x and route.y==s.ids.actorOrigins[role].y and route.z==s.ids.origin.z)end
-- Outside lanes discover one crate row only; nearby ground tiles must be clean.
local clearOrigin=square(80,100,0);assert(F.placementAt(clearOrigin),'clear outside lane rejected')
local outside=square(80,97,0);outside.worldObjects={{}}
assert(not F.placementAt(clearOrigin),'outside-lane foreign floor stock admitted');outside.worldObjects={};assert(F.placementAt(clearOrigin))
rejected(F.seed,s,2)
for index=1,16 do
 local phase=F.seed(s,index);assert(phase.itemsPerCrate==(index<=8 and 1 or 400))
 local before=assert(F.snapshot(s));local client=assert(F.resolve(s.players.client1,s.ids,'client1'));F.attach(client,phase)
 local replica=assert(F.snapshot(client));F.project(replica,before,'client1')
 assert(replica.rootIds.client2==nil,'client enumerated remote root')
 for i,c in ipairs(s.stores)do assert(#c.values==phase.itemsPerCrate and c:getCapacity()==100 and c:getCapacityWeight()<=100)end
 for _,role in ipairs({'client1','client2'})do local point=s.ids.actorOrigins[role];local nearby=0
  for i,crate in ipairs(s.ids.crates)do if math.abs(crate.x-point.x)<=1 and math.abs(crate.y-point.y)<=1 then nearby=nearby+#s.stores[i].values end end
  assert(nearby==3*phase.itemsPerCrate,'outside lane endpoint did not expose exact three-crate stock')
 end
 rejected(F.seed,s,index)
 local id=phase.crateIds[1][1];local original=s.stores[1]:getItemById(id)
 local foreign=s.stores[1]:AddItem('Base.Nails');rejected(F.release,s,index);rejected(F.abort,s)
 assert(original:getContainer()==s.stores[1]and foreign:getContainer()==s.stores[1],'foreign rejection partially deleted cohort');s.stores[1]:Remove(foreign)
 local savedType=original.fullType;original.fullType='Base.Bandage';rejected(F.snapshot,s);original.fullType=savedType
 local savedToken=original:getModData().PZSTWarehouseWalkingOwner;original:getModData().PZSTWarehouseWalkingOwner='foreign';rejected(F.abort,s)
 original:getModData().PZSTWarehouseWalkingOwner=savedToken
 local crateToken=s.crates[12].data.PZSTWarehouseWalkingOwner;s.crates[12].data.PZSTWarehouseWalkingOwner='foreign';rejected(F.abort,s)
 assert(s.stores[1]:getItemById(id)==original,'late foreign crate rejection partially cleaned early crate');s.crates[12].data.PZSTWarehouseWalkingOwner=crateToken
 assert(F.same(assert(F.snapshot(s)).crates[1].itemIds,before.crates[1].itemIds))
 local released=F.release(s,index);assert(#released.removedIds==12*phase.itemsPerCrate and released.phaseToken==phase.phaseToken)
 for _,player in pairs(s.players)do assert(#player.root.values==1 and player.root.values[1]==player.original)end
end
local cleanup=F.cleanup(s);assert(cleanup.removedCrates==12 and F.absent(s.ids))
-- Exact object identity matters even if an impostor keeps its ID and type.
s=F.prepare(players(200));F.seed(s,1)
local root=s.players.client1.root;local original=s.players.client1.original;root:Remove(original)
local impostor=root:AddItem(original.fullType);impostor.id=original.id
rejected(F.abort,s);assert(#s.stores[1].values==1);root:Remove(impostor);root:AddItem(original);F.abort(s)
-- Failed seeding remains owned and safely removable, without an invented cohort.
s=F.prepare(players(300));local add=s.stores[4].AddItem;s.stores[4].AddItem=function()error('allocation failed')end
rejected(F.seed,s,1);s.stores[4].AddItem=add
local aborted=F.abort(s);assert(#aborted.removedIds==3 and aborted.removedCrates==12 and F.absent(s.ids))
-- Partly built geometry also uses actual objects and counts at cleanup.
local nativeNew,created=IsoThumpable.new,0
IsoThumpable.new=function(...)created=created+1;assert(created<5,'object allocation failed');return nativeNew(...)end
rejected(F.prepare,players(400));IsoThumpable.new=nativeNew
aborted=F.abort(F.preparing);assert(aborted.removedCrates==4 and F.absent(F.preparing.ids))
local function openServer(x)
 replies={};local peers=players(x);dofile(fixtureRoot..'server/ZZWarehouseWalkingServer.lua')
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Prepare',peers[role],{case='walk'})end
 local packet=replies[#replies].row.ids;return peers,packet
end
local function args(packet,index,stage)return {case='walk',token=packet.token,index=index,phaseToken=packet.token..':'..index,stage=stage}end
local function noRunnerFailure(first)
 for i=first,#logs do assert(not logs[i]:find('[WAREHOUSE_WALKING] FAIL ',1,true)and not logs[i]:find('[QUEUE_TEST] FAIL ',1,true),'failure marker preceded restoration barrier')end
end
local function restored(peers,packet,role,value)
 local a=args(packet,1);a.restored=value~=false;callbacks.command(F.module,'AbortRestored',peers[role],a)
end
local function ready(peers,packet,index)
 for role,peer in pairs(peers)do local point=packet.actorOrigins[role];peer.square=square(point.x,point.y,point.z)end
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Ready',peers[role],args(packet,index))end
end
local peers,packet=openServer(500)
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Ready',peers[role],args(packet,1))end
assert(replies[#replies].command=='Prepared'and #F.preparing.stores[1].values==0,'seed preceded authoritative actor positions')
for role,peer in pairs(peers)do local point=packet.actorOrigins[role];peer.square=square(point.x,point.y,point.z)end
callbacks.tick();assert(replies[#replies].command=='Seeded')
callbacks.command(F.module,'Seen',peers.client1,args(packet,1,'before'))
assert(replies[#replies].command=='Seeded','single replica admitted both actors')
callbacks.command(F.module,'Seen',peers.client2,args(packet,1,'before'));assert(replies[#replies].command=='Go')
callbacks.command(F.module,'Ended',peers.client1,args(packet,1));assert(replies[#replies].command=='Go','single ended actor passed authority barrier')
callbacks.command(F.module,'Ended',peers.client2,args(packet,1));assert(replies[#replies].command=='Observed')
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Seen',peers[role],args(packet,1,'after'))end
assert(replies[#replies].command=='Released'and #F.preparing.stores[1].values==0)
ready(peers,packet,2)
local earlyFailureAt=#logs+1
callbacks.command(F.module,'Seen',peers.client1,args(packet,1,'before'))
assert(replies[#replies].command=='AbortRequested'and not F.absent(packet),'stale phase accepted or unsafe immediate cleanup')
callbacks.command(F.module,'AbortReady',peers.client1,args(packet,2));assert(not F.absent(packet),'single native drain allowed cleanup')
callbacks.command(F.module,'Ended',peers.client2,args(packet,2)) -- in-flight completion drains harmlessly
callbacks.command(F.module,'AbortReady',peers.client2,args(packet,2))
assert(replies[#replies].command=='Abortd'and replies[#replies].row.restored and F.absent(packet))
noRunnerFailure(earlyFailureAt)
restored(peers,packet,'client1');noRunnerFailure(earlyFailureAt);assert(replies[#replies].command=='Abortd','single client restoration closed abort')
restored(peers,packet,'client2');assert(replies[#replies].command=='Failed'and replies[#replies].row.restored and replies[#replies].row.clientsRestored.client1 and replies[#replies].row.clientsRestored.client2)
assert(logs[#logs]:find('[QUEUE_TEST] FAIL ',1,true),'terminal failure absent after all clients restored')
peers,packet=openServer(600);ready(peers,packet,1)
callbacks.command(F.module,'Seen',peers.client1,args(packet,1,'before'));callbacks.command(F.module,'Seen',peers.client1,args(packet,1,'before'))
assert(replies[#replies].command=='AbortRequested'and not F.absent(packet),'replayed admission accepted')
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortReady',peers[role],args(packet,1))end
for _,role in ipairs({'client1','client2'})do restored(peers,packet,role)end
peers,packet=openServer(700);ready(peers,packet,1)
callbacks.command(F.module,'Abort',peers.client1,args(packet,1));clock=clock+45001;callbacks.tick()
assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored and not F.absent(packet),'drain timeout removed potentially active fixture')
F.abort(F.preparing)
-- The complete coordinator lifecycle uses all16 phase barriers and only native notifications.
peers,packet=openServer(800)
for index=1,16 do
 ready(peers,packet,index);assert(replies[#replies].command=='Seeded')
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Seen',peers[role],args(packet,index,'before'))end
 assert(replies[#replies].command=='Go')
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Ended',peers[role],args(packet,index))end
 assert(replies[#replies].command=='Observed')
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Seen',peers[role],args(packet,index,'after'))end
 assert(replies[#replies].command==(index==16 and 'Done'or'Released'))
end
assert(F.absent(packet))
-- Preparation errors drain authenticated known clients before partial cleanup.
replies={};peers=players(900);dofile(fixtureRoot..'server/ZZWarehouseWalkingServer.lua')
created=0;IsoThumpable.new=function(...)created=created+1;assert(created<5,'prepare failed');return nativeNew(...)end
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Prepare',peers[role],{case='walk'})end
IsoThumpable.new=nativeNew;assert(replies[#replies].command=='AbortRequested'and not F.absent(F.preparing.ids))
local partialToken=replies[#replies].row.token;assert(type(partialToken)=='string')
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortReady',peers[role],{case='walk',token=partialToken})end
assert(replies[#replies].command=='Abortd'and replies[#replies].row.restored and F.absent(F.preparing.ids))
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortRestored',peers[role],{case='walk',token=partialToken,restored=true})end
assert(replies[#replies].command=='Failed'and replies[#replies].row.restored)
-- Restoration acknowledgements are token-bound, authenticated and non-replayable.
peers,packet=openServer(950);ready(peers,packet,1)
callbacks.command(F.module,'Abort',peers.client1,args(packet,1))
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortReady',peers[role],args(packet,1))end
restored(peers,packet,'client1');restored(peers,packet,'client1')
assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored,'duplicate client restoration accepted')
peers,packet=openServer(960);ready(peers,packet,1)
callbacks.command(F.module,'Abort',peers.client1,args(packet,1))
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortReady',peers[role],args(packet,1))end
local foreign=args(packet,1);foreign.token='foreign';foreign.restored=true
callbacks.command(F.module,'AbortRestored',peers.client1,foreign)
assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored,'foreign restoration token accepted')
peers,packet=openServer(970);ready(peers,packet,1)
callbacks.command(F.module,'Abort',peers.client1,args(packet,1))
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortReady',peers[role],args(packet,1))end
clock=clock+45001;callbacks.tick()
assert(replies[#replies].command=='Failed'and replies[#replies].row.error:find('restore timeout',1,true),'missing restoration did not time out')
peers,packet=openServer(980);ready(peers,packet,1)
callbacks.command(F.module,'Abort',peers.client1,args(packet,1))
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortReady',peers[role],args(packet,1))end
local beforeFailedRestore=#logs+1;restored(peers,packet,'client1',false);noRunnerFailure(beforeFailedRestore)
restored(peers,packet,'client2');assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored,'failed original/UI restoration reported success')
-- SP shares geometry and loads while retaining a single root projection.
config.kind='sp';s=F.prepare({client1=actor('client1',1000)});F.seed(s,1)
assert(F.snapshot(s).rootIds.client2==nil and #s.stores[1].values==1 and s.ids.actorOrigins.client2==nil and s.ids.routeOrigins.client1.y==s.ids.origin.y-2);F.abort(s)
print=nativePrint;next=nativeNext
