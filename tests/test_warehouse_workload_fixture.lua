-- Offline protocol/ownership checks. Actual actions and replication need fresh Host clients.
local fixtureRoot=ProjectRoot..'/tests/native_queue/warehouse-workload/'
local nativeNext=next;next=nil
local config={kind='mp',mode='toolkit',cases={'peer-edits'}}
local function category(item)
 return item.displayCategory or item.fullType:find('Hotdog',1,true)and'Food'or item.fullType=='Base.Bandage'and'FirstAid'
  or item.fullType=='Base.Screwdriver'and'Tool'or'Material'
end
package.preload.QueueTestSelection=function()return config end
package.preload.QueueFixtureItemCleanup=function()return dofile(ProjectRoot..'/tests/native_queue/support/QueueFixtureItemCleanup.lua')end
package.preload.QueueHealthEvents=function()return dofile(ProjectRoot..'/tests/native_queue/health/shared/QueueHealthEvents.lua')end
local modelCalls,forbidModel=0,false
package.preload['PZSurvivorToolkit/ManifestModel']=function()return {item=function(item)
 assert(not forbidModel,'client affinity observer invoked mutating Model.item')
 modelCalls=modelCalls+1
 local name=item.custom and item.name or nil
 local cat=category(item)
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
   function item:getDisplayCategory()return category(self)end
   function item:isCustomName()return self.custom==true end
   function item:getDisplayName()return self.name or self.fullType end
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
 local s={x=x,y=y,z=z,objects={},special={}}
 function s:getX()return self.x end
 function s:getY()return self.y end
 function s:getZ()return self.z end
 function s:canStand()return true end
 function s:isFree()return true end
 function s:getRoom()return nil end
 function s:getObjects()return list(self.objects)end
 function s:getSpecialObjects()return list(self.special)end
 function s:isBlockedTo()return false end
 function s:AddSpecialObject(object)self.objects[#self.objects+1]=object;self.special[#self.special+1]=object;object.square=self end
 function s:transmitRemoveItemFromSquare(object)
  for i,value in ipairs(self.special)do if value==object then table.remove(self.special,i);break end end
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
 function p:isEquipped(item)return self.equipped==item end
 function p:getUsername()return self.role end
 function p:getOnlineID()return self.onlineID or(self.role=='client1'and 1 or 2)end
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
 if index==2 then rejected(F.release,s,1);assert(F.find(s,p.transferId),'stale cached release changed new generation')end
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
 originals(s);assert(F.release(s,index)==receipt,'repeat release changed receipt')
 local refill=s.stores[1]:AddItem('Base.Pencil');rejected(F.release,s,index)
 assert(refill:getContainer()==s.stores[1],'cached release deleted foreign refill');s.stores[1]:Remove(refill)
 local retiredToken=s.crates[1].data.PZSTWarehouseWorkloadOwner;s.crates[1].data.PZSTWarehouseWorkloadOwner='foreign'
 rejected(F.release,s,index);s.crates[1].data.PZSTWarehouseWorkloadOwner=retiredToken
 local original=s.players.client1.original;s.players.client1.root:Remove(original);rejected(F.release,s,index)
 s.players.client1.root:AddItem(original);assert(F.release(s,index)==receipt)
end
local cleanup=F.cleanup(s);assert(cleanup.removedCrates==12 and #cleanup.crates==12 and F.absent(s.ids));originals(s)
rejected(F.release,s,2)
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
-- Both suite cleanup paths use the shared bounded inventory journal. Notice
-- returns are attempts only; these offline checks do not establish delivery.
local function finished(x)
 local state=F.prepare(players(x));local phase=F.seed(state,1)
 for _,step in ipairs({'peer-transfer','peer-replace','peer-craft','hidden-loot'})do
  effect(state,step);assert(F.native(state,step));phase.state=step
 end;return state,phase
end
local testX=2000
for _,mode in ipairs({'abort','release'})do
 for _,operation in ipairs({'remove','notice'})do for _,when in ipairs({'before','after'})do
  testX=testX+100
  local state,phase
  if mode=='release'then state,phase=finished(testX)else state=F.prepare(players(testX));phase=F.seed(state,1)end
  local fired,calls=false,0
  local function inject(native,...)
   calls=calls+1
   if not fired then
    fired=true
    if when=='after'then native(...)end
    error('injected '..operation..' '..when)
   end;return native(...)
  end
  if operation=='notice'then
   sendRemoveItemFromContainer=function(...)return inject(function()end,...)end
  else
   local containers={};for _,c in ipairs(state.stores)do containers[#containers+1]=c end
   for _,p in pairs(state.players)do containers[#containers+1]=p.root end
   for _,c in ipairs(containers)do local native=c.Remove;c.Remove=function(...)return inject(native,...)end end
  end
  local row=mode=='release'and F.release(state,1)or F.abort(state)
  local count=mode=='release'and 17 or 14;local journal=row.cleanupJournal
  assert(#journal.removedIds==count and #journal.recoveries==1,'native exception did not retain exact recovery evidence')
  assert(journal.removalCalls==count+(operation=='remove'and when=='before'and 1 or 0),'local remove replayed or omitted')
  assert(journal.noticeAttempts==count+(operation=='notice'and 1 or 0),'inventory notice was not retried')
  local before=calls
  assert((mode=='release'and F.release(state,1)or F.abort(state))==row and calls==before,'completed cleanup replayed native calls')
  originals(state);sendRemoveItemFromContainer=function()end
  if mode=='release'then F.abort(state)end
 end end
end
-- Inventory notices encode native addresses, so pin the square/object index
-- and online ID as well as Java references. A fault cannot move that namespace
-- and then cause the journal to publish a retry to its replacement address.
for _,mode in ipairs({'abort','release'})do
 for _,operation in ipairs({'remove','notice'})do for _,when in ipairs({'before','after'})do
  for _,mutation in ipairs({'square','index','onlineID'})do
   testX=testX+100;local state,phase
   if mode=='release'then state,phase=finished(testX)else state=F.prepare(players(testX));phase=F.seed(state,1)end
   local object=state.crates[1];local oldSquare=object:getSquare();local foreign={foreign=true}
   local calls,notices,removed=0,0,0;local fired=false
   local function changeDescriptor()
    if mutation=='onlineID'then state.players.client1.onlineID=999
    elseif mutation=='index'then table.insert(oldSquare.objects,1,foreign)
    else
     for index,candidate in ipairs(oldSquare.objects)do if candidate==object then table.remove(oldSquare.objects,index);break end end
     for index,candidate in ipairs(oldSquare.special)do if candidate==object then table.remove(oldSquare.special,index);break end end
     square(testX,700,0):AddSpecialObject(object)
    end
   end
   local function fault(native,...)
    calls=calls+1
    if not fired then
     fired=true;if when=='after'then native(...)end;changeDescriptor();error('native cleanup descriptor changed')
    end;return native(...)
   end
   sendRemoveItemFromContainer=function(...)
    if operation=='notice'then return fault(function()notices=notices+1 end,...)end
    notices=notices+1
   end
   if operation=='remove'then
    local containers={};for _,container in ipairs(state.stores)do containers[#containers+1]=container end
    for _,peer in pairs(state.players)do containers[#containers+1]=peer.root end
    for _,container in ipairs(containers)do local native=container.Remove
     container.Remove=function(...)return fault(function(...)removed=removed+1;return native(...)end,...)end
    end
   end
   local invoke=function()return mode=='release'and F.release(state,1)or F.abort(state)end
   rejected(invoke);assert(calls==1 and notices==(operation=='notice'and when=='after'and 1 or 0),
    'changed native namespace was retried or published')
   local beforeRemoved=removed;rejected(invoke)
   assert(calls==1 and removed==beforeRemoved and state.phase==phase and not state.worldCleanup,
    'changed native descriptor caused later deletion/publication')
   if mutation=='index'then assert(oldSquare.objects[1]==foreign,'foreign indexed object was deleted')end
   sendRemoveItemFromContainer=function()end
  end
 end end
end
-- Equipment is not an owned disposable inventory endpoint, even when its
-- item token is valid. Never let native cleanup implicitly unequip it.
for _,mode in ipairs({'abort','release'})do
 testX=testX+100;local state,phase
 if mode=='release'then state,phase=finished(testX)else state=F.prepare(players(testX));phase=F.seed(state,1)end
 state.players.client1.equipped=assert(F.find(state,phase.quickMatchId))
 if mode=='release'then rejected(F.release,state,1)else rejected(F.abort,state)end
 assert(F.find(state,phase.transferId),'equipped refusal partially removed fixture')
 state.players.client1.equipped=nil;F.abort(state);originals(state)
end
-- Missing before the journal begins is not a completed removal.
testX=testX+100;s=F.prepare(players(testX));p=F.seed(s,1)
local missing=assert(F.find(s,p.transferId));local missingContainer=missing:getContainer();missingContainer:Remove(missing)
rejected(F.abort,s);assert(F.find(s,p.quickMatchId),'missing identity permitted partial cleanup')
missingContainer:AddItem(missing);F.abort(s)
-- An interrupted journal retains its exact live Java references and generation;
-- a same-ID/type/token replacement after freezing must never inherit that lease.
for _,mode in ipairs({'abort','release'})do
 testX=testX+100;local state,phase
 if mode=='release'then state,phase=finished(testX)else state=F.prepare(players(testX));phase=F.seed(state,1)end
 local originalToken=state.token;local fired=false
 local containers={};for _,c in ipairs(state.stores)do containers[#containers+1]=c end
 for _,peer in pairs(state.players)do containers[#containers+1]=peer.root end
 for _,c in ipairs(containers)do local native=c.Remove;c.Remove=function(...)
  if not fired then fired=true;native(...);state.token='foreign-generation';error('interrupted after local removal')end
  return native(...)
 end end
 local invoke=function()return mode=='release'and F.release(state,1)or F.abort(state)end
 rejected(invoke);assert(state.phase==phase and state.inventoryCleanup,'interrupted cleanup discarded phase or journal')
 rejected(invoke);state.token=originalToken
 local live
 for _,c in ipairs(containers)do for _,item in ipairs(c.values)do if state.owned[item.id]then live=item;break end end;if live then break end end
 local endpoint=live:getContainer();endpoint:Remove(live)
 local replacement=endpoint:AddItem(live.fullType);replacement.id=live.id;replacement.name=live.name;replacement.custom=live.custom
 replacement.data=live.data
 rejected(invoke);assert(replacement:getContainer()==endpoint,'frozen same-ID impostor was removed')
 endpoint:Remove(replacement);endpoint:AddItem(live)
 local foreign=state.stores[1]:AddItem('Base.Pencil');rejected(invoke)
 assert(foreign:getContainer()==state.stores[1],'foreign content was removed during retry');state.stores[1]:Remove(foreign)
 local row=invoke();assert(#row.cleanupJournal.recoveries==1,'interrupted native evidence missing');originals(state)
 if mode=='release'then F.abort(state)end
end
-- A permanently failing native primitive has one shared finite failure budget.
testX=testX+100;s=F.prepare(players(testX));p=F.seed(s,1)
local budgetCalls=0
for _,c in ipairs(s.stores)do c.Remove=function()budgetCalls=budgetCalls+1;error('persistent removal failure')end end
for _,peer in pairs(s.players)do peer.root.Remove=function()budgetCalls=budgetCalls+1;error('persistent removal failure')end end
rejected(F.abort,s);assert(budgetCalls==3 and s.phase==p,'native failure budget or phase retention differs')
rejected(F.abort,s);assert(budgetCalls==3,'terminal journal restarted native removals')
-- Mutable square-index packets have a different contract: any uncertain send
-- latches permanently, and previously completed object descriptors stay retained.
for _,when in ipairs({'before','after'})do
 testX=testX+100;local state=F.prepare(players(testX));local calls={}
 for index,object in ipairs(state.crates)do local sq=object:getSquare();local native=sq.transmitRemoveItemFromSquare
  sq.transmitRemoveItemFromSquare=function(self,value)
   calls[index]=(calls[index]or 0)+1
   if index==3 then if when=='after'then native(self,value)end;error('uncertain world packet '..when)end
   return native(self,value)
  end
 end
 rejected(F.abort,state);assert(#state.worldCleanup.removed==2,'completed world prefix was lost')
 assert(calls[1]==1 and calls[2]==1 and calls[3]==1 and calls[4]==nil,'world cleanup crossed uncertain packet')
 rejected(F.abort,state);assert(calls[1]==1 and calls[2]==1 and calls[3]==1 and calls[4]==nil,'world index packet replayed')
end
-- Publication returned normally but a later local world removal failed. The
-- sent object can finish locally; neither it nor the completed prefix is resent.
testX=testX+100;s=F.prepare(players(testX))
local worldCalls={};local failedLocal=false
for index,object in ipairs(s.crates)do local sq=object:getSquare();local native=sq.transmitRemoveItemFromSquare
 sq.transmitRemoveItemFromSquare=function(self,value)
  worldCalls[index]=(worldCalls[index]or 0)+1
  if index~=3 then return native(self,value)end
 end
 if index==3 then
  object.removeFromWorld=function()if not failedLocal then failedLocal=true;error('local world removal failed')end end
  object.removeFromSquare=function(self)native(sq,self)end
 end
end
rejected(F.abort,s);assert(#s.worldCleanup.removed==2 and worldCalls[3]==1,'local failure lost completed prefix')
local restored=F.abort(s);assert(restored.removedCrates==12 and #restored.crates==12,'local world retry did not finish exact cohort')
for index=1,12 do assert(worldCalls[index]==1,'local world retry retransmitted a square index')end
assert(F.abort(s)==restored,'repeat abort regenerated world proof')
-- Cached abort receipts still validate originals, exact object ownership and
-- actual absence before returning; a completed receipt is not a live proof.
local retired=s;local retiredObject=retired.crates[1];local retiredEntry=retired.worldCleanup.entries[1]
local retiredOriginal=retired.players.client1.original
retired.players.client1.root:Remove(retiredOriginal);rejected(F.abort,retired)
retired.players.client1.root:AddItem(retiredOriginal)
local retiredToken=retiredObject.data.PZSTWarehouseWorkloadOwner
retiredObject.data.PZSTWarehouseWorkloadOwner='foreign';rejected(F.abort,retired)
retiredObject.data.PZSTWarehouseWorkloadOwner=retiredToken
retiredEntry.square:AddSpecialObject(retiredObject);rejected(F.abort,retired)
assert(retiredObject:getSquare()==retiredEntry.square,'cached abort removed a reappeared object')
for index=1,12 do assert(worldCalls[index]==1,'cached abort failure replayed native world deletion')end
-- Restore the test double directly, without invoking the fixture cleanup.
retiredEntry.square.objects={};retiredEntry.square.special={};retiredObject.square=nil
assert(F.abort(retired)==restored,'valid cached abort no longer returns its receipt')
-- World absence includes the special-object collection, not only ordinary objects.
testX=testX+100;s=F.prepare(players(testX));local object=s.crates[1];local sq=object:getSquare()
sq.objects={};assert(not F.absent(s.ids),'special-only owned object was ignored')
-- A normal native transfer may reconstruct an InventoryItem before cleanup.
-- Freeze the final live reference instead of imposing seed-reference identity.
testX=testX+100;s,p=finished(testX)
local live=assert(F.find(s,p.quickId));local endpoint=live:getContainer();endpoint:Remove(live)
local reconstructed=endpoint:AddItem(live.fullType);reconstructed.id=live.id;reconstructed.data=live.data
assert(F.native(s,'hidden-loot'));F.release(s,1);originals(s);F.abort(s)

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
-- Hidden-affinity owns a distinct type/category probe cohort. Changed transfers
-- remain cleanable evidence; the later verifier requires the native aggregate's
-- rejected eligibility and exact no-effect callback outcome.
config.cases={'physical-affinity'}
local physicalF=dofile(fixtureRoot..'shared/WarehouseWorkloadFixture.lua')
testX=testX+100;local physicalState=physicalF.prepare(players(testX))
assert(physicalF.physical and #physicalF.modes==4)
for index=1,4 do
 local phase=physicalF.seed(physicalState,index)
 assert(phase.transferMethod==(index<=2 and'1'or'2')and phase.affinityKind==(index%2==1 and'type'or'category'))
 effect(physicalState,'peer-replace');assert(physicalF.native(physicalState,'peer-replace'))
 if index%2==1 then move(physicalState,phase.newCandidateId,'crate3')end
 assert(physicalF.native(physicalState,'personal-quick').affinityOutcome==(index%2==1 and'fresh'or'blocked'))
 phase.state='personal-quick';local released=physicalF.release(physicalState,index)
 assert(#released.removedIds==15 and #released.consumedIds==0)
end
assert(physicalF.cleanup(physicalState).removedCrates==12)
config.cases={'hidden-affinity'}
local affinityF=dofile(fixtureRoot..'shared/WarehouseWorkloadFixture.lua')
config.cases={'peer-edits'}
assert(affinityF.case=='hidden-affinity'and affinityF.affinity and #affinityF.modes==2
 and affinityF.modes[1]=='clean'and affinityF.modes[2]=='clean'and #affinityF.steps==3
 and affinityF.steps[3]=='personal-quick','affinity case manufactured unsupported vanilla controls')
affinityF.emit('CASE',{});assert(logs[#logs]:find('hidden-affinity',1,true),'affinity receipt used another case')
local function checkReadOnlyAffinity(state,phase,step)
 local stockId=step=='initial'and phase.replacementSourceId or phase.replacementId
 local stock=assert(F.find(state,stockId));local raw=stock.displayCategory
 stock.displayCategory='UnpreparedReplicatedCategory'
 local before=modelCalls;forbidModel=true
 for _,role in ipairs({'client1','client2'})do
  local client=assert(affinityF.resolve(state.players[role],state.ids,role));affinityF.attachPhase(client,phase)
  for _,receipt in ipairs({assert(affinityF.native(client,step)),affinityF.snapshot(client)})do
   assert(receipt.projection=='native-identity'and receipt.visibility==role,'client affinity claimed a semantic metadata projection')
   local found=false
   for _,entry in ipairs(receipt.items)do
    assert(entry.key==nil and entry.cat==nil and type(entry.customName)=='boolean','client fabricated semantic key/category evidence')
    if entry.id==stockId then
     found=true;assert(entry.rawCategory=='UnpreparedReplicatedCategory'and entry.ft==stock.fullType
      and entry.name==(stock.custom and stock.name or nil),'client observer hid raw category/custom-name state')
    end
   end
   assert(found,'client read-only observation omitted exact shared stock ID')
  end
  assert(stock.displayCategory=='UnpreparedReplicatedCategory','client observation repaired replicated category state')
  -- Raw category differences are observable; native identity differences are
  -- still rejected before either readiness or diagnostic snapshot can qualify.
  local name,custom,kind,source=stock.name,stock.custom,stock.fullType,stock.container
  stock.name='Foreign custom label';stock.custom=true
  rejected(affinityF.native,client,step);rejected(affinityF.snapshot,client)
  stock.name=name;stock.custom=custom;stock.fullType='Base.Pencil'
  rejected(affinityF.native,client,step);rejected(affinityF.snapshot,client)
  stock.fullType=kind;stock.container=state.players[role].root
  rejected(affinityF.native,client,step);rejected(affinityF.snapshot,client)
  stock.container=source
 end
 assert(modelCalls==before,'client readiness/diagnostics called Model.item')
 forbidModel=false
 rejected(affinityF.native,state,step)
 stock.displayCategory=raw
 local authority=assert(affinityF.native(state,step))
 assert(authority.projection==nil,'authority lost full semantic scope')
 for _,entry in ipairs(authority.items)do assert(entry.key and entry.cat,'authority omitted prepared semantic metadata')end
end
for _,outcome in ipairs({'fresh','stale','blocked'})do
 testX=testX+100;local state=affinityF.prepare(players(testX))
 for index=1,#affinityF.modes do
  local phase=affinityF.seed(state,index)
  assert(#phase.items==15 and phase.affinityKind==(index==1 and'type'or'category')
   and phase.quickMatchId==nil and phase.recipe==nil and phase.outputType==nil and #phase.outputIds==0,
   'affinity phase retained unrelated craft/quick setup')
  assert(phase.oldCategory=='FirstAid'and phase.newCategory=='Tool'and phase.oldCategory~=phase.newCategory,
   'affinity setup categories do not distinguish admission')
  assert(affinityF.native(state,'initial')and not affinityF.native(state,'peer-replace'))
  checkReadOnlyAffinity(state,phase,'initial')
  effect(state,'peer-replace');phase.state='peer-replace'
  assert(#state.stores[3].values==1 and affinityF.native(state,'peer-replace')
   and F.find(state,phase.replacementId):getFullType()=='Base.Screwdriver',
   'affinity replacement did not preserve count and change physical type')
  checkReadOnlyAffinity(state,phase,'peer-replace')
  rejected(affinityF.expected,phase,'personal-quick','stale','crate13')
  rejected(affinityF.expected,phase,'personal-quick','stale','client2')
  rejected(affinityF.native,state,'peer-craft')
  local blocked=assert(affinityF.native(state,'personal-quick'))
  assert(blocked.affinityOutcome=='blocked'and phase.oldDestination=='client1',
   'unchanged candidates did not produce the exact no-effect projection')
  -- Physical projection alone proves no effect; the driver/verifier separately
  -- require the actual callback, rejected eligibility and post-call settling.
  phase.affinityOutcome=nil;phase.oldDestination=nil
  rejected(affinityF.release,state,index)
  -- An unrelated moved stock ID invalidates the whole result, even when the
  -- candidate pair alone appears fresh.
  move(state,phase.newCandidateId,'crate3');move(state,phase.transferId,'crate2')
  assert(not affinityF.native(state,'personal-quick')and phase.affinityOutcome==nil,
   'candidate inference ignored another moved owned item')
  move(state,phase.transferId,'crate1')
  move(state,phase.oldCandidateId,'crate3')
  assert(not affinityF.native(state,'personal-quick')and phase.affinityOutcome==nil,
   'both candidates moving produced an accepted affinity outcome')
  move(state,phase.oldCandidateId,'client1');move(state,phase.newCandidateId,'crate4')
  assert(not affinityF.native(state,'personal-quick'),'fresh candidate accepted another destination')
  move(state,phase.newCandidateId,'client1');move(state,phase.oldCandidateId,'client2')
  assert(not affinityF.native(state,'personal-quick'),'stale candidate accepted another player root')
  move(state,phase.oldCandidateId,'client1')
  if outcome=='fresh'then move(state,phase.newCandidateId,'crate3')
  elseif outcome=='stale'then move(state,phase.oldCandidateId,'crate12')end
  local duplicate=state.stores[4]:AddItem('Base.Bandage');duplicate.id=phase.oldCandidateId
  rejected(affinityF.native,state,'personal-quick');state.stores[4]:Remove(duplicate)
  local foreign=state.stores[7]:AddItem('Base.Pencil')
  rejected(affinityF.native,state,'personal-quick');state.stores[7]:Remove(foreign)
  local candidate=assert(F.find(state,phase.newCandidateId));candidate.displayCategory='Changed'
  rejected(affinityF.native,state,'personal-quick');candidate.displayCategory=nil
  local receipt=assert(affinityF.native(state,'personal-quick'));phase.state='personal-quick'
  checkReadOnlyAffinity(state,phase,'personal-quick')
  local destination=outcome=='stale'and'crate12'or'client1'
  assert(receipt.affinityOutcome==outcome and phase.affinityOutcome==outcome
   and receipt.oldDestination==destination and phase.oldDestination==destination
   and receipt.consumedId==nil and #receipt.outputIds==0,'affinity authority outcome/recipe facts differ')
  local expected=affinityF.expected(phase,'personal-quick')
  assert(expected[phase.oldCandidateId]==destination
   and expected[phase.newCandidateId]==(outcome=='fresh'and'crate3'or'client1'))
  -- Each client checks its own visibility projection; a remote root is absent,
  -- while the exact moved candidate is visible in the same owned crate.
  for _,role in ipairs({'client1','client2'})do
   local client=assert(affinityF.resolve(state.players[role],state.ids,role));affinityF.attachPhase(client,phase)
   local localReceipt=assert(affinityF.native(client,'personal-quick'))
   assert(localReceipt.visibility==role and localReceipt.affinityOutcome==outcome and localReceipt.oldDestination==destination,
    'affinity result required a remote root or lost exact endpoint inference')
  end
  if outcome=='stale'then
   move(state,phase.oldCandidateId,'crate11')
   assert(not affinityF.native(state,'personal-quick'),'completed affinity outcome changed its accepted endpoint')
   rejected(affinityF.release,state,index);move(state,phase.oldCandidateId,'crate12')
  end
  local released=affinityF.release(state,index)
  assert(#released.removedIds==#phase.items and #released.consumedIds==0 and released.affinityOutcome==outcome
   and released.oldDestination==destination and released.ownedRemaining==0,
   'affinity release did not remove the exact unconsumed owned cohort')
  originals(state);assert(affinityF.release(state,index)==released)
 end
 local cleaned=affinityF.cleanup(state)
 assert(cleaned.index==#affinityF.modes and cleaned.removedCrates==12 and affinityF.absent(state.ids))
 originals(state)
end
-- Affinity abort must neither adopt recipe outputs nor excuse a missing
-- HotdogPack as a consumed input; this case performs no crafting.
testX=testX+100;local affinityState=affinityF.prepare(players(testX));local affinityPhase=affinityF.seed(affinityState,1)
local missingInput=assert(F.find(affinityState,affinityPhase.craftInputId));local inputContainer=missingInput:getContainer()
inputContainer:Remove(missingInput);rejected(affinityF.abort,affinityState)
inputContainer:AddItem(missingInput)
local unownedOutput=affinityState.players.client2.root:AddItem('Base.Hotdog_single')
rejected(affinityF.abort,affinityState);assert(not affinityState.owned[unownedOutput.id],'affinity adopted an unrelated craft output')
affinityState.players.client2.root:Remove(unownedOutput)
local affinityAbort=affinityF.abort(affinityState)
assert(affinityAbort.restored and #affinityAbort.removedIds==15 and affinityF.absent(affinityState.ids))
originals(affinityState)
print=nativePrint;next=nativeNext
print('PASS warehouse workload fixture: sparse capacities, exact IDs/endpoints, same-count replacement, craft adoption, visibility projection, exact cleanup and protocol guards')
