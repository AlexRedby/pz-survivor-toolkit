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
function sendServerCommand(player,module,command,row)assert(command~='CaptureBaseline'and command~='Normalize'and command~='Prepared'and command~='Abortd'and command~='Done','initial/terminal command used unordered server sender');replies[#replies+1]={role=player:getUsername(),command=command,row=row}end
function warehouseWalkingOrderedServer(player,module,command,row)
 assert(command=='CaptureBaseline'or command=='Normalize'or command=='Prepared'or command=='Abortd'or command=='Done','noninitial/terminal server command changed transport')
 replies[#replies+1]={role=player:getUsername(),command=command,row=row};return true
end
local nextId,squares,failKind=0,{},nil
local function list(values)
 return {size=function()return #values end,get=function(_,i)return values[i+1]end,isEmpty=function()return #values==0 end,contains=function(_,wanted)for _,value in ipairs(values)do if value==wanted then return true end end;return false end}
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
   function item:getName()return self.name or self.fullType end
   function item:getCondition()return self.condition or 100 end
   function item:isFavorite()return self.favorite or false end
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
local cell={getGridSquare=function(_,x,y,z)return square(x,y,z)end,processing={},removing={}}
function cell:getProcessItems()return list(self.processing)end
function cell:getProcessItemsRemove()return list(self.removing)end
local function erase(values,item)for i,value in ipairs(values)do if value==item then table.remove(values,i);return end end end
function cell:addToProcessItems(item)erase(self.removing,item);if not list(self.processing):contains(item)then self.processing[#self.processing+1]=item end end
function cell:addToProcessItemsRemove(item)if not list(self.removing):contains(item)then self.removing[#self.removing+1]=item end end
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
local A=dofile(fixtureRoot..'shared/WarehouseWalkingActor.lua');package.preload.WarehouseWalkingActor=function()return A end
function instanceof(item,kind)return item.kind==kind end
local F=dofile(fixtureRoot..'shared/WarehouseWalkingFixture.lua')
package.preload.WarehouseWalkingFixture=function()return F end
local function actor(role,x)
 local p={root=container(),square=square(x,100,0),role=role}
 function p:getInventory()return self.root end
 function p:getPrimaryHandItem()return self.primary end
 function p:getSecondaryHandItem()return self.secondary end
 function p:setPrimaryHandItem(v)assert(not self.forbidEquipmentSetters,'fixture used packet-producing primary setter');self.primary=v end
 function p:setSecondaryHandItem(v)assert(not self.forbidEquipmentSetters,'fixture used packet-producing secondary setter');self.secondary=v end
 p.worn={};p.attached={}
 function p:getAttachedItems()return list(self.attached)end
 function p:setAttachedItem(location,item)
  assert(not self.forbidEquipmentSetters,'fixture used packet-producing attachment setter')
  for i,entry in ipairs(self.attached)do if entry:getLocation()==location then table.remove(self.attached,i);break end end
  if item then self.attached[#self.attached+1]={getLocation=function()return location end,getItem=function()return item end}end
 end
 local function setWorn(location,item)
  for i,entry in ipairs(p.worn)do if entry:getLocation()==location then table.remove(p.worn,i);break end end
  if item then p.worn[#p.worn+1]={getLocation=function()return location end,getItem=function()return item end}end
 end
 function p:getWornItems()local worn=list(self.worn);worn.setItem=function(_,location,item)setWorn(location,item)end;return worn end
 function p:clearWornItems()self.worn={};self.wetnessInvalidations=(self.wetnessInvalidations or 0)+1;self:onWornItemsChanged()end
 function p:onWornItemsChanged()self.wornChanged=(self.wornChanged or 0)+1 end
 function p:OnClothingUpdated()self.modifierUpdates=(self.modifierUpdates or 0)+1 end
 function p:resetModelNextFrame()self.modelUpdates=(self.modelUpdates or 0)+1 end
 function p:setWornItem(location,item)
  assert(not self.forbidEquipmentSetters,'fixture used packet-producing clothing setter')
  self.equipmentPackets=(self.equipmentPackets or 0)+1;setWorn(location,item)
  if self.equipmentPeer then
   -- Native SyncClothing removes authority slots absent from the packet. This
   -- deliberately models the race that the fixture's silent API must avoid.
   self.equipmentPeer.worn={}
  end
 end
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
-- Authority and owning replica retain distinct native original objects while
-- converging on a server-ID cohort; equipment and nested payload return exactly.
local authorityActor,replicaActor=actor('client1',40),actor('client1',40)
replicaActor.original.id=authorityActor.original.id
for _,player in ipairs({authorityActor,replicaActor})do
 player.original.name='preserved payload';player.original.favorite=true;player.original.condition=73
 local bag=player.root:AddItem('Base.Bag_Schoolbag');bag.kind='InventoryContainer';bag.contents=container()
 function bag:getItemContainer()return self.contents end
 local child=bag.contents:AddItem('Base.Bandage');child.name='nested payload';cell:addToProcessItems(child)
 player:setWornItem('Back',bag);player.forbidEquipmentSetters=true
end
local savedAuthority,savedReplica=A.save(authorityActor),A.save(replicaActor)
A.detach(savedAuthority);local serverMode=isServer;isServer=function()return false end;A.detach(savedReplica);isServer=serverMode
for _,saved in ipairs({savedAuthority,savedReplica})do
 local nested=saved.roots[2].contents.values[1];assert(cell:getProcessItemsRemove():contains(nested),'stashed nested original still processes')
end
local descriptor=A.seed(savedAuthority,'actor-transport');A.bind(savedReplica,descriptor)
assert(not A.snapshot(savedReplica),'unreplicated actor load admitted')
for _,item in ipairs(savedAuthority.cohort)do
 local copy=replicaActor.root:AddItem(item:getFullType());copy.id=item:getID();copy:getModData().PZSTWarehouseWalkingActor='actor-transport'
end
assert(F.same(A.snapshot(savedAuthority).itemIds,A.snapshot(savedReplica).itemIds))
local nestedBag=savedReplica.roots[2];local foreignChild=nestedBag.contents:AddItem('Base.Hammer');rejected(A.originalProof,savedReplica);nestedBag.contents:Remove(foreignChild)
local foreign=replicaActor.root:AddItem('Base.Hammer');rejected(A.restore,savedReplica,false)
assert(#replicaActor.root.values==9,'foreign actor cleanup partially removed cohort');replicaActor.root:Remove(foreign)
-- A same-ID impostor must fail the authority's exact-object contract.
local exact=savedAuthority.cohort[1];authorityActor.root:Remove(exact)
local impostor=authorityActor.root:AddItem('Base.Nails');impostor.id=exact.id;impostor:getModData().PZSTWarehouseWalkingActor='actor-transport'
rejected(A.snapshot,savedAuthority);rejected(A.restore,savedAuthority,true)
authorityActor.root:Remove(impostor);authorityActor.root:AddItem(exact)
A.restore(savedAuthority,true);isServer=function()return false end;A.restore(savedReplica,false);isServer=serverMode
assert(savedReplica.player.modifierUpdates==2,'silent client clothing modifiers not refreshed')
for _,saved in ipairs({savedAuthority,savedReplica})do
 assert(saved.player.root.values[1]==saved.roots[1]and saved.player.root.values[2]==saved.roots[2],'original root order changed')
 assert(saved.player.primary==nil and saved.player.secondary==nil,'fresh hands changed')
 assert(saved.player.equipmentPackets==1 and saved.player.modelUpdates==2 and saved.player.wetnessInvalidations==2,'silent native clothing transition/refresh contract changed')
 A.originalProof(saved)
 local nested=saved.roots[2].contents.values[1]
 assert(cell:getProcessItems():contains(nested)and not cell:getProcessItemsRemove():contains(nested),'original nested processing did not resume')
end
-- Empty hands/attachments are an admission contract, not state to rewrite.
for _,unsupported in ipairs({'primary','secondary','attached'})do
 local player=actor('client1',45)
 if unsupported=='attached'then player:setAttachedItem('Belt Left',player.original)else player[unsupported]=player.original end
 local wornBefore=player:getWornItems():size();local packets=player.equipmentPackets
 rejected(A.save,player)
 assert(player.root.values[1]==player.original and player.original:getContainer()==player.root
  and player:getWornItems():size()==wornBefore and player.equipmentPackets==packets and not player.modelUpdates,'unsupported fresh actor mutated')
end
-- Native standard clothing setters send SyncClothing before Prepare. Model its
-- authority clearing effect and reject that baseline without touching either
-- authority actor or inventing equipment from the owning client's descriptor.
local client=actor('client1',46);local authority=actor('client1',46);authority.original.id=client.original.id
client:setWornItem('base:Shirt',client.original);authority:setWornItem('base:Shirt',authority.original)
local expected=A.baseline(A.save(client));client.equipmentPeer=authority;client:setWornItem('base:Shirt',nil)
assert(authority:getWornItems():size()==0,'native automatic packet reproduction did not clear authority clothing')
local peer=actor('client2',46);local current={client1=authority,client2=peer}
rejected(F.prepare,current,nil,{client1=expected,client2=A.baseline(A.save(peer))})
for _,player in pairs(current)do assert(#player.root.values==1 and player.root.values[1]==player.original and not player.modelUpdates,'baseline mismatch normalized an authority actor')end
F.abort(F.preparing);assert(authority:getWornItems():size()==0,'authority baseline was invented from client message')
-- A failure halfway through detachment restores the already moved subset too.
local partialPlayer=actor('client1',50);partialPlayer.root:AddItem('Base.Bandage')
local partial=A.save(partialPlayer);local remove=partial.root.Remove
partial.root.Remove=function(c,item)remove(c,item);error('injected detach failure')end
rejected(A.detach,partial);partial.root.Remove=remove;A.restore(partial,true);assert(partial.player.root.values[1]==partial.roots[1]and partial.player.root.values[2]==partial.roots[2])

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
 local before=assert(F.snapshot(s));local client=assert(F.resolve(s.players.client1,s.ids,'client1',s.actors.client1));F.attach(client,phase)
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
 for _,player in pairs(s.players)do assert(#player.root.values==8 and player.original:getContainer()==nil)end
end
local cleanup=F.cleanup(s);assert(cleanup.removedCrates==12 and F.absent(s.ids))
-- Exact object identity matters even if an impostor keeps its ID and type.
s=F.prepare(players(200));F.seed(s,1)
local root=s.players.client1.root;local original=s.players.client1.original;local impostor=root:AddItem(original.fullType);impostor.id=original.id
rejected(F.abort,s);assert(#s.stores[1].values==1);root:Remove(impostor);F.abort(s)
-- Failed seeding remains owned and safely removable, without an invented cohort.
s=F.prepare(players(300));local add=s.stores[4].AddItem;s.stores[4].AddItem=function()error('allocation failed')end
rejected(F.seed,s,1);s.stores[4].AddItem=add
local aborted=F.abort(s);assert(#aborted.removedIds==3 and aborted.removedCrates==12 and F.absent(s.ids))
-- Partly built geometry also uses actual objects and counts at cleanup.
local nativeNew,created=IsoThumpable.new,0
IsoThumpable.new=function(...)created=created+1;assert(created<5,'object allocation failed');return nativeNew(...)end
rejected(F.prepare,players(400));IsoThumpable.new=nativeNew
aborted=F.abort(F.preparing);assert(aborted.removedCrates==4 and F.absent(F.preparing.ids))
local function announceServer(peers)
 replies={};dofile(fixtureRoot..'server/ZZWarehouseWalkingServer.lua')
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Prepare',peers[role],{case='walk'})end
 assert(replies[#replies].command=='CaptureBaseline','baseline capture was not gated by both ready actors')
 return replies[#replies].row.token
end
local function captureServer(peers,token)
 local baselines={}
 for _,role in ipairs({'client1','client2'})do
  baselines[role]=A.baseline(A.save(peers[role]))
  callbacks.command(F.module,'Baseline',peers[role],{case='walk',token=token,baseline=baselines[role]})
 end
 assert(replies[#replies].command=='Normalize','authority baselines did not gate normalization')
 return replies[#replies].row.ids,baselines
end
local function normalizeServer(peers,token,baselines,role)
 callbacks.command(F.module,'Normalized',peers[role],{case='walk',token=token,baseline=baselines[role],
  proof={rootEmpty=true,equipmentEmpty=true,originalsStashed=true}})
end
local function openServer(x)
 local peers=players(x);local token=announceServer(peers);local packet,baselines=captureServer(peers,token)
 for _,role in ipairs({'client1','client2'})do normalizeServer(peers,token,baselines,role)end
 return peers,packet
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
-- All peers enter before any original snapshot or mutation. The first actor
-- may legitimately change while a slow second client joins; capture is fresh.
local waiting=players(470);replies={};dofile(fixtureRoot..'server/ZZWarehouseWalkingServer.lua')
local save=A.save;local captures=0;A.save=function(...)captures=captures+1;return save(...)end
callbacks.command(F.module,'Prepare',waiting.client1,{case='walk'})
assert(captures==0 and #replies==0 and F.preparing==nil,'first-ready client captured or normalized early')
waiting.client1.original.name='changed while peer joined';clock=clock+70000
callbacks.command(F.module,'Prepare',waiting.client2,{case='walk'})
assert(captures==0 and replies[#replies].command=='CaptureBaseline','all-ready did not precede original capture')
local token=replies[#replies].row.token
local captured={client1=A.baseline(save(waiting.client1)),client2=A.baseline(save(waiting.client2))}
callbacks.command(F.module,'Baseline',waiting.client1,{case='walk',token=token,baseline=captured.client1})
assert(captures==0 and replies[#replies].command=='CaptureBaseline','one baseline captured either authority actor')
callbacks.command(F.module,'Baseline',waiting.client2,{case='walk',token=token,baseline=captured.client2})
assert(captures==2 and replies[#replies].command=='Normalize','both baselines did not establish authority capture')
for _,player in pairs(waiting)do assert(#player.root.values==1 and not player.modelUpdates,'capture mutated authority originals')end
normalizeServer(waiting,token,captured,'client1')
assert(replies[#replies].command=='Normalize','one normalization acknowledgement created owned load')
for _,player in pairs(waiting)do assert(#player.root.values==1 and not player.modelUpdates,'single normalization mutated authority originals')end
normalizeServer(waiting,token,captured,'client2');assert(replies[#replies].command=='Prepared')
assert(waiting.client1.original:getName()=='changed while peer joined','early payload capture survived the all-ready barrier')
A.save=save;F.abort(F.preparing)
-- Replay, forged token, malformed proof and early phase readiness all abort
-- before any authority normalization, retaining real original object refs.
for _,failure in ipairs({'duplicate-baseline','foreign-baseline-token','duplicate-normalized','false-normalized','early-phase-ready'})do
 local peers=players(480);local currentToken=announceServer(peers)
 local base={client1=A.baseline(A.save(peers.client1)),client2=A.baseline(A.save(peers.client2))}
 if failure=='duplicate-baseline'or failure=='foreign-baseline-token'then
  callbacks.command(F.module,'Baseline',peers.client1,{case='walk',token=currentToken,baseline=base.client1})
  callbacks.command(F.module,'Baseline',peers.client1,{case='walk',token=failure=='foreign-baseline-token'and'foreign'or currentToken,baseline=base.client1})
 else
  for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Baseline',peers[role],{case='walk',token=currentToken,baseline=base[role]})end
  if failure=='duplicate-normalized'then normalizeServer(peers,currentToken,base,'client1');normalizeServer(peers,currentToken,base,'client1')
  elseif failure=='false-normalized'then callbacks.command(F.module,'Normalized',peers.client1,{case='walk',token=currentToken,baseline=base.client1,proof={rootEmpty=false,equipmentEmpty=true,originalsStashed=true}})
  else callbacks.command(F.module,'Ready',peers.client1,{case='walk',token=currentToken,index=1})end
 end
 assert(replies[#replies].command=='AbortRequested','invalid initial barrier accepted: '..failure)
 callbacks.command(F.module,'Baseline',peers.client2,{case='walk',token=currentToken,baseline=base.client2})
 assert(replies[#replies].command=='AbortRequested','in-flight peer baseline bypassed restoration barrier')
 for _,player in pairs(peers)do assert(#player.root.values==1 and player.root.values[1]==player.original and not player.modelUpdates,'initial barrier failure changed authority originals')end
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortReady',peers[role],{case='walk',token=currentToken})end
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortRestored',peers[role],{case='walk',token=currentToken,restored=true})end
 assert(replies[#replies].command=='Failed'and replies[#replies].row.restored,'initial barrier abort did not restore unchanged originals')
end
-- Swallowed exposed-Java errors return nil: dispatch must fail immediately,
-- before any client timeout, and leave original authority actors untouched.
local failedPeers=players(490);replies={};dofile(fixtureRoot..'server/ZZWarehouseWalkingServer.lua')
local orderedServer=warehouseWalkingOrderedServer;warehouseWalkingOrderedServer=function()return nil end
callbacks.command(F.module,'Prepare',failedPeers.client1,{case='walk'})
callbacks.command(F.module,'Prepare',failedPeers.client2,{case='walk'})
warehouseWalkingOrderedServer=orderedServer
assert(replies[#replies].command=='AbortRequested'and replies[#replies].row.error:find('native ordered walking server dispatch failed: CaptureBaseline',1,true),'nil native sender result became a client timeout')
local failedToken=replies[#replies].row.token
for _,player in pairs(failedPeers)do assert(#player.root.values==1 and not player.modelUpdates,'failed capture dispatch mutated authority originals')end
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortReady',failedPeers[role],{case='walk',token=failedToken})end
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'AbortRestored',failedPeers[role],{case='walk',token=failedToken,restored=true})end
-- Authenticated cancellation is allowed when CaptureBaseline never delivered a
-- token. It cannot authorize another actor, learned-token requests or any ack.
for _,scenario in ipairs({'not-delivered','after-baseline','after-capture','impostor'})do
 local peers=players(495);replies={};dofile(fixtureRoot..'server/ZZWarehouseWalkingServer.lua')
 callbacks.command(F.module,'Prepare',peers.client1,{case='walk'})
 local token
 if scenario=='after-baseline'or scenario=='after-capture'then
  callbacks.command(F.module,'Prepare',peers.client2,{case='walk'});token=replies[#replies].row.token
  callbacks.command(F.module,'Baseline',peers.client1,{case='walk',token=token,baseline=A.baseline(A.save(peers.client1))})
  if scenario=='after-capture'then callbacks.command(F.module,'Baseline',peers.client2,{case='walk',token=token,baseline=A.baseline(A.save(peers.client2))})end
 end
 local source=scenario=='impostor'and actor('client1',495)or peers.client1
 callbacks.command(F.module,'Abort',source,{case='walk',error='original pre-token failure'})
 assert(replies[#replies].command=='AbortRequested','pre-token abort did not enter guarded restoration')
 local row=replies[#replies].row;token=token or row.token
 assert((row.error=='original pre-token failure')==(scenario=='not-delivered'),'pre-token cancellation acceptance differs: '..scenario)
 assert(#peers.client1.root.values==1 and not peers.client1.modelUpdates,'pre-token abort changed authority originals')
 callbacks.command(F.module,'AbortReady',peers.client1,{case='walk',token=token})
 if scenario=='after-baseline'or scenario=='after-capture'then callbacks.command(F.module,'AbortReady',peers.client2,{case='walk',token=token})end
 callbacks.command(F.module,'AbortRestored',peers.client1,{case='walk',token=token,restored=true})
 if scenario=='after-baseline'or scenario=='after-capture'then callbacks.command(F.module,'AbortRestored',peers.client2,{case='walk',token=token,restored=true})end
 assert(replies[#replies].command=='Failed'and replies[#replies].row.restored,'pre-token abort never completed native restoration')
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
created=0;IsoThumpable.new=function(...)created=created+1;assert(created<5,'prepare failed');return nativeNew(...)end
peers,packet=openServer(900)
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
