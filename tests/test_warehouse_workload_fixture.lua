-- Offline protocol/ownership checks. Actual actions and replication need fresh Host clients.
local fixtureRoot=ProjectRoot..'/tests/native_queue/warehouse-workload/'
local nativeNext=next;next=nil
local config={kind='mp',mode='toolkit',cases={'peer-edits'}}
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
local F=dofile(fixtureRoot..'shared/WarehouseWorkloadFixture.lua')
package.preload.WarehouseWorkloadFixture=function()return F end
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
local function rejected(fn,...)local ok=pcall(fn,...);assert(not ok,'unsafe workload operation accepted')end
local function players(x)return {client1=actor('client1',x),client2=actor('client2',x)}end
local function move(s,id,endpoint)
 local item=assert(F.find(s,id));local source=item:getContainer();source:Remove(item)
 local dest=s.players[endpoint]and s.players[endpoint]:getInventory()or s.stores[tonumber(endpoint:match('crate(%d+)'))]
 dest:AddItem(item)
end
local function originals(s)
 for _,p in pairs(s.players)do assert(#p.root.values==1 and p.root:getItemById(p.original.id)==p.original,'original root changed')end
end
local function effect(s,step)
 local p=s.phase
 if step=='peer-transfer'then move(s,p.transferId,'crate2')
 elseif step=='peer-replace'then move(s,p.replacementSourceId,'client2');move(s,p.replacementId,'crate3')
 elseif step=='peer-craft'then
  move(s,p.craftInputId,'client2');local input=assert(F.find(s,p.craftInputId));input:getContainer():Remove(input)
  for i=1,4 do s.players.client2.root:AddItem('Base.Hotdog_single')end
 elseif step=='hidden-loot'then move(s,p.quickId,'client1')end
end
local s=F.prepare(players(100));assert(#s.crates==12 and #s.ids.crates==12)
rejected(F.seed,s,2)
for index=1,2 do
 local p=F.seed(s,index);assert(#p.items==14 and F.native(s,'initial'))
 rejected(F.seed,s,index);rejected(F.release,s,index)
 assert(not F.native(s,'peer-transfer'),'unperformed native action passed')
 for _,step in ipairs({'peer-transfer','peer-replace','peer-craft','hidden-loot'})do
  effect(s,step);local receipt=assert(F.native(s,step));p.state=step
  assert(receipt.visibility=='both-roots')
  if step=='peer-replace'then assert(#s.stores[3].values==1 and F.find(s,p.replacementSourceId):getContainer()==s.players.client2.root,'same-count replacement did not change identity')end
  if step=='peer-craft'then assert(#p.outputIds==4 and #p.items==18 and receipt.consumedId==p.craftInputId,'native outputs were not adopted')end
 end
 local foreign=s.stores[6]:AddItem('Base.Pencil')
 rejected(F.release,s,index);rejected(F.abort,s)
 assert(foreign:getContainer()==s.stores[6]and F.find(s,p.quickId),'foreign rejection partially deleted fixture')
 s.stores[6]:Remove(foreign)
 local token=s.crates[12].data.PZSTWarehouseWorkloadOwner;s.crates[12].data.PZSTWarehouseWorkloadOwner='foreign'
 rejected(F.release,s,index);assert(F.find(s,p.quickId),'foreign token partially deleted workload')
 s.crates[12].data.PZSTWarehouseWorkloadOwner=token
 local receipt=F.release(s,index);assert(#receipt.removedIds==17 and #receipt.consumedIds==1 and receipt.ownedRemaining==0)
 originals(s);rejected(F.release,s,index)
end
local cleanup=F.cleanup(s);assert(cleanup.removedCrates==12 and #cleanup.crates==12 and F.absent(s.ids));originals(s)
for i,point in ipairs(cleanup.crates)do
 for _,field in ipairs({'x','y','z','index','object','ci','key','id','token'})do assert(point[field]==s.ids.crates[i][field],'removed object descriptor differs')end
 assert(point.afterIndex<0,'removed crate has a native object index')
end
-- Never require a client to enumerate the remote root. Its proof is a projection.
s=F.prepare(players(200));local p=F.seed(s,1);effect(s,'peer-transfer');assert(F.native(s,'peer-transfer'))
local c=assert(F.resolve(s.players.client1,s.ids,'client1'));F.attachPhase(c,p)
assert(F.native(c,'peer-transfer').visibility=='client1')
effect(s,'peer-replace');effect(s,'peer-craft');assert(F.native(s,'peer-craft'))
F.attachPhase(c,p);assert(F.native(c,'peer-craft'),'remote output invisibility invalidated local proof')
local abort=F.abort(s);assert(abort.restored and abort.removedCrates==12);originals(s)
-- A foreign output candidate must never be adopted or removed during cleanup.
s=F.prepare(players(300));p=F.seed(s,1)
effect(s,'peer-transfer');effect(s,'peer-replace');effect(s,'peer-craft')
local foreign=s.players.client2.root:AddItem('Base.Pencil')
rejected(F.native,s,'peer-craft');rejected(F.abort,s)
assert(foreign:getContainer()==s.players.client2.root and #s.stores[2].values==2,'foreign output changed fixture')
s.players.client2.root:Remove(foreign);assert(F.native(s,'peer-craft'));F.abort(s);originals(s)
s=F.prepare(players(350));p=F.seed(s,1)
effect(s,'peer-transfer');effect(s,'peer-replace');effect(s,'peer-craft')
local extra=s.players.client2.root:AddItem('Base.Hotdog_single')
rejected(F.native,s,'peer-craft');rejected(F.abort,s)
assert(extra:getContainer()==s.players.client2.root,'extra output refusal deleted a candidate')
s.players.client2.root:Remove(extra);assert(F.native(s,'peer-craft'));F.abort(s);originals(s)
s=F.prepare(players(375));p=F.seed(s,1)
local original=s.players.client1.original;s.players.client1.root:Remove(original)
rejected(F.abort,s);assert(F.find(s,p.transferId),'missing original caused partial owned cleanup')
s.players.client1.root:AddItem(original);F.abort(s);originals(s)
-- Keeping an original ID/type while replacing the Java object is not preservation.
s=F.prepare(players(385));p=F.seed(s,1)
original=s.players.client1.original;s.players.client1.root:Remove(original)
local impostor=s.players.client1.root:AddItem(original.fullType);impostor.id=original.id
rejected(F.abort,s);assert(F.find(s,p.transferId),'original replacement caused partial cleanup')
s.players.client1.root:Remove(impostor);s.players.client1.root:AddItem(original);F.abort(s);originals(s)
local nativeNew,created=IsoThumpable.new,0
IsoThumpable.new=function(...)
 created=created+1;assert(created<5,'simulated partial workload object creation failure');return nativeNew(...)
end
rejected(F.prepare,players(395));IsoThumpable.new=nativeNew
s=F.preparing;abort=F.abort(s)
assert(abort.removedCrates==4 and #abort.crates==4 and F.absent(s.ids),'partial cleanup reported a hardcoded object count');originals(s)
local function openServer(x)
 replies={};local peers=players(x);dofile(fixtureRoot..'server/ZZWarehouseWorkloadServer.lua')
 for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Prepare',peers[role],{case='peer-edits'})end
 assert(replies[#replies].command=='Prepared');local packet=replies[#replies].row.ids
 for _,peer in pairs(peers)do peer.square=square(packet.actorOrigin.x,packet.actorOrigin.y,packet.actorOrigin.z)end
 return peers,packet
end
local function args(packet,index,step)return {case='peer-edits',token=packet.token,index=index,phaseToken=packet.token..':'..index,step=step}end
-- Public boundary rejects wrong token, phase and role without implementing an effect.
local peers,packet=openServer(400)
callbacks.command(F.module,'Ready',peers.client1,{case='peer-edits',token='foreign',index=1})
assert(replies[#replies].command=='Failed'and F.absent(packet))
peers,packet=openServer(500)
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Ready',peers[role],args(packet,1))end
assert(replies[#replies].command=='Seeded')
callbacks.command(F.module,'Seen',peers.client1,args(packet,1,'initial'))
callbacks.command(F.module,'Seen',peers.client2,args(packet,1,'initial'))
assert(replies[#replies].command=='Go'and replies[#replies].row.actor=='client2')
callbacks.command(F.module,'Acted',peers.client1,args(packet,1,'peer-transfer'))
assert(replies[#replies].command=='Failed'and F.absent(packet),'wrong actor did not close/restore session')
peers,packet=openServer(600)
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Ready',peers[role],args(packet,1))end
callbacks.command(F.module,'Seen',peers.client1,args(packet,1,'initial'))
callbacks.command(F.module,'Seen',peers.client1,args(packet,1,'initial'))
assert(replies[#replies].command=='Failed'and F.absent(packet),'replayed Seen accepted')
peers,packet=openServer(700)
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Ready',peers[role],args(packet,1))end
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Seen',peers[role],args(packet,1,'initial'))end
local forged=args(packet,1,'peer-transfer');forged.phaseToken='foreign-phase'
callbacks.command(F.module,'Acted',peers.client2,forged)
assert(replies[#replies].command=='Failed'and F.absent(packet),'foreign phase token accepted')
-- Acted is a notification, never a request for the server to perform the action.
peers,packet=openServer(800)
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Ready',peers[role],args(packet,1))end
local seed=replies[#replies].row.phase
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Seen',peers[role],args(packet,1,'initial'))end
callbacks.command(F.module,'Acted',peers.client2,args(packet,1,'peer-transfer'));callbacks.tick()
assert(replies[#replies].command=='Go','server performed a missing native action')
clock=clock+30001;callbacks.tick()
assert(replies[#replies].command=='Failed'and F.absent(packet),'native convergence timeout failed to restore exact owned fixture')
peers,packet=openServer(900)
callbacks.command(F.module,'Abort',peers.client1,{case='peer-edits',token=packet.token,error='test quiescent client failure'})
assert(replies[#replies].command=='AbortRequested'and not F.absent(packet),'abort removed fixtures before both native queues drained')
callbacks.command(F.module,'Acted',peers.client2,args(packet,1,'peer-transfer'))
assert(replies[#replies].command=='AbortRequested'and not F.absent(packet),'in-flight native notification interrupted safe abort drain')
callbacks.command(F.module,'AbortReady',peers.client1,{case='peer-edits',token=packet.token})
assert(not F.absent(packet),'one client drain allowed premature deletion')
callbacks.command(F.module,'AbortReady',peers.client2,{case='peer-edits',token=packet.token})
assert(replies[#replies].command=='Abortd'and replies[#replies].row.restored and #replies[#replies].row.cleanup.crates==12 and F.absent(packet),'authenticated client abort did not return cleanup proof')
-- Both peers can fail before either receives AbortRequested. The second role
-- joins the existing drain without resetting its deadline or acknowledgements.
peers,packet=openServer(925)
for _,role in ipairs({'client1','client2'})do callbacks.command(F.module,'Ready',peers[role],args(packet,1))end
seed=replies[#replies].row.phase
callbacks.command(F.module,'Abort',peers.client1,args(packet,1,'initial'))
callbacks.command(F.module,'AbortReady',peers.client1,args(packet,1,'initial'))
callbacks.command(F.module,'Abort',peers.client2,args(packet,1,'initial'))
assert(replies[#replies].command=='AbortRequested'and not F.absent(packet),'distinct peer abort was rejected or deleted active sources')
callbacks.command(F.module,'AbortReady',peers.client2,args(packet,1,'initial'))
local aborted=replies[#replies].row
assert(replies[#replies].command=='Abortd'and aborted.restored and #aborted.cleanup.crates==12 and #aborted.cleanup.removedIds==14 and F.absent(packet),'simultaneous peer abort did not preserve first readiness and clean exact identities')
local removed={};for _,id in ipairs(aborted.cleanup.removedIds)do removed[id]=true end
for _,entry in ipairs(seed.items)do assert(removed[entry.id],'simultaneous peer abort removed another item cohort')end
for _,peer in pairs(peers)do assert(#peer.root.values==1 and peer.root:getItemById(peer.original.id)==peer.original,'simultaneous abort changed originals')end
peers,packet=openServer(935)
callbacks.command(F.module,'Abort',peers.client1,{case='peer-edits',token=packet.token})
callbacks.command(F.module,'Abort',peers.client1,{case='peer-edits',token=packet.token})
assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored and not F.absent(packet),'same-role abort replay was accepted')
F.abort(F.preparing)
peers,packet=openServer(940)
callbacks.command(F.module,'Abort',peers.client1,{case='peer-edits',token=packet.token})
callbacks.command(F.module,'Abort',actor('client2',940),{case='peer-edits',token=packet.token})
assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored and not F.absent(packet),'foreign player joined owned abort drain')
F.abort(F.preparing)
peers,packet=openServer(945)
callbacks.command(F.module,'Abort',peers.client1,{case='peer-edits',token=packet.token})
callbacks.command(F.module,'Abort',peers.client2,{case='peer-edits',token='foreign'})
assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored and not F.absent(packet),'foreign token joined owned abort drain')
F.abort(F.preparing)
peers,packet=openServer(950)
callbacks.command(F.module,'Abort',peers.client1,{case='peer-edits',token=packet.token})
callbacks.command(F.module,'AbortReady',peers.client1,{case='peer-edits',token=packet.token})
callbacks.command(F.module,'AbortReady',peers.client1,{case='peer-edits',token=packet.token})
assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored and not F.absent(packet),'duplicate drain acknowledgement caused unsafe cleanup')
F.abort(F.preparing)
peers,packet=openServer(1000)
callbacks.command(F.module,'Abort',peers.client1,{case='peer-edits',token=packet.token})
clock=clock+44000
callbacks.command(F.module,'Abort',peers.client2,{case='peer-edits',token=packet.token})
clock=clock+1001;callbacks.tick()
assert(replies[#replies].command=='Failed'and not replies[#replies].row.restored and not F.absent(packet),'abort drain timeout deleted potentially active sources')
F.abort(F.preparing)
-- A locally settled Ready may arrive before the native server pose packet.
-- Keep the request pending; neither an early request nor one arrived actor may seed.
peers,packet=openServer(1100)
local targetSquare=square(packet.actorOrigin.x,packet.actorOrigin.y,packet.actorOrigin.z)
peers.client1.square=square(1100,100,0);peers.client2.square=square(1101,100,0)
for _,role in ipairs({'client1','client2'})do
 local request=args(packet,1);request.x=targetSquare:getX()+.5;request.y=targetSquare:getY()+.5;request.z=0
 callbacks.command(F.module,'Ready',peers[role],request)
end
assert(replies[#replies].command=='Prepared'and #F.preparing.stores[1].values==0,'Ready seeded from client-reported coordinates before replicated poses')
clock=clock+100;peers.client1.square=targetSquare;callbacks.tick()
assert(replies[#replies].command=='Prepared'and #F.preparing.stores[1].values==0,'one arrived server actor seeded before its peer')
clock=clock+150;peers.client2.square=targetSquare;callbacks.tick()
assert(replies[#replies].command=='Seeded'and #F.preparing.stores[1].values==1,'replicated server positions did not release seed barrier')
local seeded=replies[#replies].row
for _,role in ipairs({'client1','client2'})do local proof=seeded.readiness[role]
 assert(proof.waitMs==250 and proof.confirmedAt-proof.requestedAt==250 and proof.deadlineMs==15000,'readiness proof lost its first request deadline')
 assert(proof.onlineId==peers[role]:getOnlineID()and proof.x==targetSquare:getX()+.5 and proof.y==targetSquare:getY()+.5 and proof.z==0
  and proof.squareX==targetSquare:getX()and proof.squareY==targetSquare:getY()and proof.squareZ==0,'readiness proof is not the authoritative native pose')
end
local replyCount=#replies;callbacks.tick();assert(#replies==replyCount,'settled readiness seeded more than once')
F.abort(F.preparing)
peers,packet=openServer(1150)
peers.client1.getSquare=function()return nil end
callbacks.command(F.module,'Ready',peers.client1,args(packet,1));callbacks.tick()
assert(replies[#replies].command=='Prepared','missing replicated square was rejected before convergence deadline')
callbacks.command(F.module,'Ready',peers.client1,args(packet,1))
assert(replies[#replies].command=='Failed'and F.absent(packet),'pending Ready replay was accepted')
peers,packet=openServer(1200)
peers.client1.square=square(1200,100,0);peers.client2.square=square(1201,100,0)
callbacks.command(F.module,'Ready',peers.client1,args(packet,1));clock=clock+14000
callbacks.command(F.module,'Ready',peers.client2,args(packet,1));clock=clock+1001;callbacks.tick()
local failed=replies[#replies].row
assert(replies[#replies].command=='Failed'and failed.error:find('position convergence timeout',1,true)and F.absent(packet),'server readiness deadline was reset/unbounded')
assert(failed.readiness.client1.waitMs==15001 and failed.readiness.client2.waitMs==1001 and #failed.cleanup.removedIds==0,'position timeout lost pending native diagnostics or seeded items')
print=nativePrint;next=nativeNext
print('PASS warehouse workload fixture: sparse capacities, exact IDs/endpoints, same-count replacement, craft adoption, visibility projection, exact cleanup and protocol guards')
