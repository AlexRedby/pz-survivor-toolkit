-- Full identity scans belong exclusively to preparation/admission/release barriers.
local selection=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local A=require 'WarehouseWalkingActor'
local Items=require 'WarehouseWalkingItems'
local Cleanup=require 'QueueFixtureItemCleanup'
local F={module='WarehouseWalkingTest',phases={},initialTransport=selection.kind=='mp'and'native-reliable-ordered-channel0'or'in-process-shared-authority',
 materializationTransport=selection.kind=='mp'and'native-reliable-ordered-channel1'or'in-process-shared-authority',
 cleanupTransport=selection.kind=='mp'and'native-reliable-ordered-channel1'or'in-process-shared-authority'}
local initialEvents={READY=true,BASELINE_SEEN=true,BASELINES=true,NORMALIZED=true,BASELINE=true}
local owner='PZSTWarehouseWalkingOwner'
for _,density in ipairs({'sparse','dense'})do for _,mode in ipairs({'clean','vanilla'})do
 for _,state in ipairs({'own-only','both-hidden','loot-collapsed','both-open'})do
  F.phases[#F.phases+1]={density=density,paneMode=mode,paneState=state,itemsPerCrate=density=='sparse'and 1 or 400}
 end
end end
local function array(list)local out={};for i=0,list:size()-1 do out[#out+1]=list:get(i)end;return out end
local function integer(n)return type(n)=='number'and n==math.floor(n)end
function F.ids(container)local out={};for _,item in ipairs(array(container:getItems()))do out[#out+1]=item:getID()end;table.sort(out);return out end
function F.same(a,b)if #a~=#b then return false end;for i,id in ipairs(a)do if id~=b[i]then return false end end;return true end
function F.emit(event,row)
 row=row or {};if initialEvents[event]then row.initialTransport=F.initialTransport elseif event=='SETUP'then row.materializationTransport=F.materializationTransport end;row.suite='warehouse-walking';row.case='walk';row.kind=selection.kind;row.mode='toolkit'
 row.role=row.role or'server';print('[WAREHOUSE_WALKING] '..event..' '..JSON.encode(row))
end
function F.context(s,row)
 row=row or {};row.token=s and s.token;local p=s and s.phase;row.index=p and p.index or s and s.nextIndex
 if p then for _,k in ipairs({'phaseToken','density','paneMode','paneState'})do row[k]=p[k]end end;return row
end
function F.placementAt(origin)
 if not origin then return end
 for dx=-4,3 do for dy=-3,3 do
  local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
  if not square or not square:canStand()or not square:isFree(false)or square:getRoom()
   or square:getObjects():size()>1 or square:getSpecialObjects():size()>0 or square:getWorldObjects():size()>0 then return end
 end end
 local squares={};for dx=-3,2 do for _,dy in ipairs({-1,1})do squares[#squares+1]=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())end end;return squares
end
function F.chooseOrigin(player)
 local origin=assert(player:getSquare());if F.placementAt(origin)then return origin end
 for radius=1,12 do for dx=-radius,radius do for dy=-radius,radius do
  if math.max(math.abs(dx),math.abs(dy))==radius then
   local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
   if F.placementAt(square)then return square end
  end
 end end end;error('no loaded clear warehouse walking area within twelve tiles')
end
local function descriptor(object)
 local square=assert(object:getSquare());local x,y,z=square:getX(),square:getY(),square:getZ();local index=object:getObjectIndex();local key=x..','..y..','..z
 return {x=x,y=y,z=z,index=index,object=index,ci=0,key=key,id=key..'/'..index..'/0',token=object:getModData()[owner]}
end
function F.sessionToken(player)return 'warehouse-walking:'..getTimestampMs()..':'..player:getOnlineID()end
function F.capture(players,actors,baselines,token)
 assert(players.client1 and(selection.kind~='mp'or players.client2),'walking actors absent')
 if players.client2 then assert(players.client1:getOnlineID()~=players.client2:getOnlineID(),'walking actors share online ID')end
 local origin=F.chooseOrigin(players.client1);local s={players=players,crates={},stores={},owned={},actors=actors or {},nextIndex=1}
 s.token=token or F.sessionToken(players.client1);F.preparing=s
 s.ids={token=s.token,crates={},origin={x=origin:getX(),y=origin:getY(),z=origin:getZ()},
  actorOrigins={},routeOrigins={},originalRootIds={},originalEquipment={},actorLoads={}}
 -- Capture and correlate every authority baseline before either actor changes.
 for role,player in pairs(players)do
  if not s.actors[role]then s.actors[role]=A.save(player)end
  local actor=s.actors[role];s.ids.originalRootIds[role]=actor.rootIds;s.ids.originalEquipment[role]=actor.equipment
  if baselines then A.matchBaseline(s.actors[role],assert(baselines[role],'missing owning actor baseline'),role)end
 end
 return s
end
function F.materialize(s)
 assert(s.players and not s.materialized and not s.phase,'duplicate/out-of-order walking materialization')
 -- Every actor's original state must still match before either authority root
 -- changes. SP shares the owning client's already normalized native actor.
 for _,actor in pairs(s.actors)do
  A.originalProof(actor)
  if actor.detached then assert(selection.kind=='sp','authority normalized before both acknowledgements');A.normalizedProof(actor)
  else A.equipmentProof(actor)end
 end
 local players=s.players;local origin=getCell():getGridSquare(s.ids.origin.x,s.ids.origin.y,s.ids.origin.z)
 local reserved={};for _,actor in pairs(s.actors)do A.reserveIds(actor,reserved)end
 for role,player in pairs(players)do
  local laneY=origin:getY()+(role=='client1'and -2 or 2)
  s.ids.actorOrigins[role]={x=origin:getX()-2,y=laneY,z=origin:getZ()}
  s.ids.routeOrigins[role]={x=origin:getX(),y=laneY,z=origin:getZ()}
  local actor=s.actors[role];if not actor.detached then A.detach(actor)end
  s.ids.actorLoads[role]=A.seed(actor,s.token..':actor:'..role,reserved)
  local weight=s.ids.actorLoads[role].weight;assert(not s.actorWeight or math.abs(s.actorWeight-weight)<.000001,'walking actor cohort weights differ');s.actorWeight=weight
 end
 for i,square in ipairs(assert(F.placementAt(origin)))do
  local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{});s.crates[i]=object
  object:getModData()[owner]=s.token..':'..i;object:setCanPassThrough(true);object:setIsContainer(true)
  local c=assert(object:getContainer());s.stores[i]=c;c:setType('crate');c:setCapacity(100);c:setExplored(true)
  square:AddSpecialObject(object);s.ids.crates[i]=descriptor(object)
  if isServer()then object:transmitCompleteItemToClients();object:transmitModData()end
 end;s.materialized=true;return s
end
function F.prepare(players,actors,baselines)
 return F.materialize(F.capture(players,actors,baselines))
end
function F.resolve(player,packet,role,actor)
 assert(type(packet)=='table'and type(packet.token)=='string'and #packet.crates==12,'invalid walking descriptors')
 assert(actor and F.same(actor.rootIds,assert(packet.originalRootIds[role])),'replica original root IDs differ')
 A.matchBaseline(actor,{rootIds=packet.originalRootIds[role],equipment=packet.originalEquipment[role]})
 A.bind(actor,assert(packet.actorLoads[role]))
 local s={player=player,role=role,ids=packet,token=packet.token,crates={},stores={},actors={[role]=actor}}
 if not A.snapshot(actor)then return end
 for i,point in ipairs(packet.crates)do
  local square=getCell():getGridSquare(point.x,point.y,point.z)
  if not square or not integer(point.index)or point.index<0 or point.index>=square:getObjects():size()then return end
  local object=square:getObjects():get(point.index)
  if not object or object:getModData()[owner]~=packet.token..':'..i or object:getModData()[owner]~=point.token or not object:getContainer()then return end
  s.crates[i]=object;s.stores[i]=object:getContainer()
 end;return s
end
function F.attach(s,p)
 local spec=assert(F.phases[p.index]);assert(p.token==s.token and p.phaseToken==s.token..':'..p.index,'wrong walking phase token')
 for _,k in ipairs({'density','paneMode','paneState','itemsPerCrate'})do assert(p[k]==spec[k],'walking phase specification changed')end
 assert(p.itemType=='Base.Nails'and #p.crateIds==12,'walking phase load contract differs');s.phase=p
end
local function preserved(s)
 for _,actor in pairs(s.actors)do A.originalProof(actor)end
end
function F.seed(s,index)
 assert(s.players and not s.phase and index==s.nextIndex and F.phases[index],'out-of-order walking seed');preserved(s)
 local spec=F.phases[index];local p={token=s.token,index=index,phaseToken=s.token..':'..index,itemType='Base.Nails',crateIds={}}
 for k,v in pairs(spec)do p[k]=v end;s.phase=p
 -- Stage the whole cohort before any container mutation or packet. Native
 -- IDs are random; only this phase's live reservations survive staging.
 for _,c in ipairs(s.stores)do assert(c:getItems():isEmpty(),'walking crate not empty')end
 local reserved={};for _,actor in pairs(s.actors)do A.reserveIds(actor,reserved)end
 local staged=Items.stage(p.itemType,#s.stores*p.itemsPerCrate,reserved);local slot=0
 for i,c in ipairs(s.stores)do
  p.crateIds[i]={}
  for _=1,p.itemsPerCrate do
   slot=slot+1;local item=staged[slot];local id=item:getID()
   s.owned[id]={item=item,id=id,container=c,ft=p.itemType,state='staged'}
   item:getModData()[owner]=p.phaseToken;p.crateIds[i][#p.crateIds[i]+1]=id
  end;table.sort(p.crateIds[i])
 end
 for _,item in ipairs(staged)do local entry=s.owned[item:getID()];entry.state='inserting'
  local added=entry.container:AddItem(item)
  assert(added==item and item:getContainer()==entry.container and item:getID()==entry.id,'native walking insertion changed identity/endpoint')
  entry.state='inserted'
  if isServer()then sendAddItemToContainer(entry.container,item)end
 end;p.seedComplete=true;return p
end
-- Returns nil only while a replica has not yet received the declared cohort.
-- Once admitted, the caller requires this result instead of retrying a mutation.
function F.snapshot(s)
 preserved(s);local p=assert(s.phase);assert(p.seedComplete,'walking cohort insertion is incomplete')
 local row=F.context(s,{crates={},rootIds={},actorLoads={},originals=true,identities=true,itemType='Base.Nails'})
 local seen={};local actor=s.players and s.players.client1 or s.player
 for i,c in ipairs(s.stores)do
  local object=s.crates[i];assert(object:getModData()[owner]==s.token..':'..i and object:getContainer()==c,'foreign walking crate')
  assert(c:getType()=='crate'and c:getCapacity()==100,'walking crate type/capacity changed')
  local itemIds={};for _,item in ipairs(array(c:getItems()))do
   local id=item:getID();assert(integer(id)and not seen[id],'duplicate walking item ID');seen[id]=true
   assert(item:getContainer()==c and item:getFullType()=='Base.Nails'and item:getModData()[owner]==p.phaseToken,'walking item type/ownership/endpoint changed')
   if s.players then local entry=s.owned[id];assert(entry and entry.item==item and entry.container==c,'foreign walking owned identity')end
   itemIds[#itemIds+1]=id
  end;table.sort(itemIds)
  if not F.same(itemIds,p.crateIds[i])then return end
  local effective=c:getEffectiveCapacity(actor);local weight=c:getCapacityWeight();assert(effective<=100 and weight<=effective,'walking crate overfilled')
  row.crates[i]={slot=i,id=s.ids.crates[i].id,capacity=100,effectiveCapacity=effective,weight=weight,itemIds=itemIds}
 end
 for role,actor in pairs(s.actors)do local load=A.snapshot(actor);if not load then return end;row.actorLoads[role]=load;row.rootIds[role]=load.itemIds end;return row
end
function F.project(native,authority,role)
 assert(native.token==authority.token and native.phaseToken==authority.phaseToken and #native.crates==12 and #authority.crates==12,'walking authority phase differs')
 for i,c in ipairs(native.crates)do local a=authority.crates[i]
  assert(c.id==a.id and c.capacity==a.capacity and F.same(c.itemIds,a.itemIds),'walking replica crate IDs differ')
 end
 assert(F.same(assert(native.rootIds[role]),assert(authority.rootIds[role])),'walking replica root IDs differ')
 local n,a=native.actorLoads[role],authority.actorLoads[role]
 assert(n.itemType==a.itemType and n.count==a.count and n.weight==a.weight and n.equipment==a.equipment and n.originalsStashed and a.originalsStashed,'walking replica actor load differs')
end
local function cleanupEntries(s)
 preserved(s);for _,actor in pairs(s.actors)do A.validateRestore(actor,true)end;local entries={};local seen={}
 -- Validate all identities before any removal, including partially seeded loads.
 for i,c in ipairs(s.stores)do
  assert(s.crates[i]:getModData()[owner]==s.token..':'..i and s.crates[i]:getContainer()==c,'refusing foreign walking crate cleanup')
  for _,item in ipairs(array(c:getItems()))do local id=item:getID();local entry=s.owned[id]
   assert(entry and entry.state~='staged'and not seen[id]and item==entry.item and c==entry.container and item:getContainer()==c and item:getFullType()==entry.ft
    and s.phase and item:getModData()[owner]==s.phase.phaseToken,'refusing foreign walking item cleanup')
   seen[id]=true;entries[#entries+1]=entry
  end
 end
 for id,entry in pairs(s.owned)do
  assert(entry.id==id and entry.item:getID()==id and entry.item:getFullType()==entry.ft,'refusing changed walking identity cleanup')
  local endpoint=entry.item:getContainer()
  local removed=s.removalJournal and Cleanup.removed(s.removalJournal,entry.item)
  assert((removed and endpoint==nil)or(entry.state=='staged'and endpoint==nil)or(entry.state=='inserting'and(endpoint==nil or endpoint==entry.container))
   or(entry.state=='inserted'and endpoint==entry.container),'refusing missing/moved walking identity cleanup')
  assert(endpoint==nil or seen[id],'refusing unlisted walking identity cleanup')
 end;return entries
end
local function removeItems(s)
 if not s.removalJournal then
  local entries=cleanupEntries(s);local containers={}
  for _,c in ipairs(s.stores)do containers[#containers+1]=c end
  for _,actor in pairs(s.actors)do containers[#containers+1]=actor.root end
  local phase,token,phaseToken,index=s.phase,s.token,s.phase and s.phase.phaseToken,s.phase and s.phase.index
  local owned=s.owned;local identities,stores,crates,actors,addresses={},{},{},{},{}
  for id,entry in pairs(owned)do identities[id]={entry=entry,item=entry.item,container=entry.container,ft=entry.ft,state=entry.state}end
  for i,c in ipairs(s.stores)do
   stores[i]=c;crates[i]=s.crates[i];local square=crates[i]:getSquare()
   assert(square or #entries==0 and s.worldCleanup and s.worldCleanup[i].done,'walking namespace missing before item cleanup')
   addresses[i]={square=square,id=square and descriptor(crates[i]).id or false}
  end
  for role,actor in pairs(s.actors)do actors[role]={actor=actor,player=actor.player,root=actor.root,online=actor.player:getOnlineID()}end
  s.removalJournal=Cleanup.new(entries,{containers=containers,server=isServer(),
   guard=function()
    assert(s.phase==phase and s.token==token and s.owned==owned and(not phase or phase.phaseToken==phaseToken and phase.index==index),'walking cleanup generation changed')
    assert(#s.stores==#stores and #s.crates==#crates,'walking cleanup namespace changed')
    for i,c in ipairs(stores)do
     assert(s.stores[i]==c and s.crates[i]==crates[i]and crates[i]:getSquare()==addresses[i].square
      and(addresses[i].id and descriptor(crates[i]).id==addresses[i].id or not addresses[i].id and crates[i]:getObjectIndex()<0),'walking cleanup namespace changed')
    end
    for role,actor in pairs(s.actors)do assert(actors[role]and actors[role].actor==actor,'walking cleanup actors changed')end
    for role,entry in pairs(actors)do assert(s.actors[role]==entry.actor and entry.actor.player==entry.player and entry.actor.root==entry.root
     and entry.player:getInventory()==entry.root and entry.player:getOnlineID()==entry.online,'walking cleanup actor/root changed')end
    for id,entry in pairs(owned)do assert(identities[id]and identities[id].entry==entry,'walking cleanup cohort changed')end
    for id,entry in pairs(identities)do
     local current=owned[id];assert(current==entry.entry and current.item==entry.item and current.container==entry.container
      and current.ft==entry.ft and current.state==entry.state,'walking cleanup cohort changed')
    end
    cleanupEntries(s)
   end,
   check=function(entry)assert(phase and entry.item:getModData()[owner]==phase.phaseToken,'walking cleanup owner changed')end})
 end
 local receipt=Cleanup.run(s.removalJournal);s.owned={};s.removalJournal=nil;return receipt
end
function F.release(s,index)
 if s.lastRelease and s.lastRelease.index==index and not s.phase and s.nextIndex==index+1 then
  cleanupEntries(s);for _,c in ipairs(s.stores)do assert(c:getItems():isEmpty(),'released walking stock reappeared')end
  return s.lastRelease
 end
 assert(s.phase and s.phase.index==index,'unfinished walking release')
 if not s.removalJournal then assert(F.snapshot(s),'unfinished walking release')end
 local receipt=removeItems(s)
 local row=F.context(s,{removedIds=receipt.removedIds,cleanupJournal=receipt,ownedRemaining=0,originalRootIds=s.ids.originalRootIds})
 s.phase=nil;s.nextIndex=index+1;preserved(s);s.lastRelease=row;return row
end
function F.absent(packet)
 for _,point in ipairs(packet.crates)do local square=getCell():getGridSquare(point.x,point.y,point.z);if not square then return false end
  for _,list in ipairs({square:getObjects(),square:getSpecialObjects()})do
   for _,object in ipairs(array(list))do if object:getModData()[owner]==point.token then return false end end
  end
 end;return true
end
function F.cleanup(s)
 assert(not s.phase and s.nextIndex==17,'unfinished walking cleanup');cleanupEntries(s)
 assert(not s.worldUncertain,'uncertain walking world removal cannot be retransmitted')
 if not s.worldCleanup then
  s.worldCleanup={};s.worldToken=s.token
  for i,object in ipairs(s.crates)do
   assert(object:getModData()[owner]==s.token..':'..i and object:getContainer():getItems():isEmpty(),'refusing foreign/nonempty walking cleanup')
   s.worldCleanup[i]={object=object,container=s.stores[i],square=object:getSquare(),point=descriptor(object)}
  end
 end
 assert(s.token==s.worldToken and #s.worldCleanup==#s.crates and #s.stores==#s.crates,'walking world cleanup generation/cohort changed')
 for i,entry in ipairs(s.worldCleanup)do
  local object,point=entry.object,entry.point
  assert(s.crates[i]==object and s.stores[i]==entry.container and object:getContainer()==entry.container
   and object:getModData()[owner]==point.token and object:getContainer():getItems():isEmpty(),'walking cleanup object changed')
  if entry.done then
   assert(object:getObjectIndex()<0 and F.absent({crates={point}}),'removed walking object reappeared')
  else assert(object:getSquare()==entry.square and object:getObjectIndex()>=0 and descriptor(object).id==point.id,'walking object missing/moved before removal')end
 end
 local removed={}
 for _,entry in ipairs(s.worldCleanup)do
  local object,point=entry.object,entry.point
  if not entry.done then
   -- Native world packets address a mutable index. A thrown transmit is
   -- permanently uncertain; replay could delete a different peer object.
   local ok,problem=pcall(function()
    object:getSquare():transmitRemoveItemFromSquare(object)
    if object:getObjectIndex()>=0 then object:removeFromWorld();object:removeFromSquare()end
    assert(object:getObjectIndex()<0 and F.absent({crates={point}}),'owned walking object survived')
   end)
   if not ok then s.worldUncertain=true;error(problem)end
   entry.done=true;point.afterIndex=object:getObjectIndex()
  end;removed[#removed+1]=point
 end
 assert(F.absent(s.ids),'owned walking objects remain');local actors,equipment,journals={},{},{}
 for role,actor in pairs(s.actors)do
  actors[role]=A.restore(actor,true);equipment[role]=A.equipmentProof(actor);journals[role]=A.cleanupReceipt(actor)
 end
 return {cleanupTransport=F.cleanupTransport,actorRestored=actors,actorCleanup=journals,originalEquipment=equipment,token=s.token,index=16,removedCrates=#removed,crates=removed,ownedAbsent=true,ownedRemaining=0,originalRootIds=s.ids.originalRootIds}
end
function F.abort(s)
 if not s then return {cleanupTransport=F.cleanupTransport,restored=true,unprepared=true}end
 if not s.abortRemoval then s.abortRemoval=removeItems(s);s.phase=nil;s.nextIndex=17 end
 local row=F.cleanup(s);row.removedIds=s.abortRemoval.removedIds;row.cleanupJournal=s.abortRemoval;row.restored=true;return row
end
return F
