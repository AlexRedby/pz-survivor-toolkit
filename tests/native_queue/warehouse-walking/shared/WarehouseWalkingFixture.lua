-- Full identity scans belong exclusively to preparation/admission/release barriers.
local selection=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local A=require 'WarehouseWalkingActor'
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
 local origin=F.chooseOrigin(players.client1);local s={players=players,crates={},stores={},owned={},initial={},actors=actors or {},nextIndex=1}
 s.token=token or F.sessionToken(players.client1);F.preparing=s
 s.ids={token=s.token,crates={},origin={x=origin:getX(),y=origin:getY(),z=origin:getZ()},
  actorOrigins={},routeOrigins={},originalRootIds={},originalEquipment={},actorLoads={}}
 -- Capture and correlate every authority baseline before either actor changes.
 for role,player in pairs(players)do
  if not s.actors[role]then s.actors[role]=A.save(player)end
  local actor=s.actors[role];s.initial[role]=actor.original;s.ids.originalRootIds[role]=actor.rootIds;s.ids.originalEquipment[role]=actor.equipment
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
 for role,player in pairs(players)do
  local laneY=origin:getY()+(role=='client1'and -2 or 2)
  s.ids.actorOrigins[role]={x=origin:getX()-2,y=laneY,z=origin:getZ()}
  s.ids.routeOrigins[role]={x=origin:getX(),y=laneY,z=origin:getZ()}
  local actor=s.actors[role];if not actor.detached then A.detach(actor)end
  s.ids.actorLoads[role]=A.seed(actor,s.token..':actor:'..role)
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
 local s={player=player,role=role,ids=packet,token=packet.token,crates={},stores={},actors={[role]=actor},initial={[role]=actor.original}}
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
 for i,c in ipairs(s.stores)do
  assert(c:getItems():isEmpty(),'walking crate not empty');p.crateIds[i]={}
  for _=1,p.itemsPerCrate do
   local item=assert(c:AddItem('Base.Nails'));local id=item:getID()
   assert(integer(id)and not s.owned[id],'invalid walking owned ID')
   for _,initial in pairs(s.initial)do assert(not initial[id],'walking owned ID aliases original')end
   item:getModData()[owner]=p.phaseToken;s.owned[id]={item=item,container=c,ft='Base.Nails'};p.crateIds[i][#p.crateIds[i]+1]=id
   if isServer()then sendAddItemToContainer(c,item)end
  end;table.sort(p.crateIds[i])
 end;return p
end
-- Returns nil only while a replica has not yet received the declared cohort.
-- Once admitted, the caller requires this result instead of retrying a mutation.
function F.snapshot(s)
 preserved(s);local p=assert(s.phase);local row=F.context(s,{crates={},rootIds={},actorLoads={},originals=true,identities=true,itemType='Base.Nails'})
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
   assert(entry and not seen[id]and item==entry.item and c==entry.container and item:getContainer()==c and item:getFullType()==entry.ft
    and s.phase and item:getModData()[owner]==s.phase.phaseToken,'refusing foreign walking item cleanup')
   seen[id]=true;entries[#entries+1]=entry
  end
 end
 for id in pairs(s.owned)do assert(seen[id],'refusing missing walking identity cleanup')end;return entries
end
local function removeItems(s)
 local entries=cleanupEntries(s);local removed={}
 for _,entry in ipairs(entries)do local id=entry.item:getID();entry.container:Remove(entry.item)
  if isServer()then sendRemoveItemFromContainer(entry.container,entry.item)end;removed[#removed+1]=id
 end;table.sort(removed);s.owned={};return removed
end
function F.release(s,index)
 assert(s.phase and s.phase.index==index and F.snapshot(s),'unfinished walking release')
 local row=F.context(s,{removedIds=removeItems(s),ownedRemaining=0,originalRootIds=s.ids.originalRootIds})
 s.phase=nil;s.nextIndex=index+1;preserved(s);return row
end
function F.absent(packet)
 for _,point in ipairs(packet.crates)do local square=getCell():getGridSquare(point.x,point.y,point.z);if not square then return false end
  for _,object in ipairs(array(square:getObjects()))do if object:getModData()[owner]==point.token then return false end end
 end;return true
end
function F.cleanup(s)
 assert(not s.phase and s.nextIndex==17,'unfinished walking cleanup');cleanupEntries(s)
 for i,object in ipairs(s.crates)do assert(object:getModData()[owner]==s.token..':'..i and object:getContainer():getItems():isEmpty(),'refusing foreign/nonempty walking cleanup')end
 local removed={};for _,object in ipairs(s.crates)do local point=descriptor(object)
  object:getSquare():transmitRemoveItemFromSquare(object)
  if object:getObjectIndex()>=0 then object:removeFromWorld();object:removeFromSquare()end
  assert(object:getObjectIndex()<0,'owned walking object survived');point.afterIndex=object:getObjectIndex();removed[#removed+1]=point
 end
 assert(F.absent(s.ids),'owned walking objects remain');local actors,equipment={},{}
 for role,actor in pairs(s.actors)do actors[role]=A.restore(actor,true);equipment[role]=A.equipmentProof(actor)end
 return {cleanupTransport=F.cleanupTransport,actorRestored=actors,originalEquipment=equipment,token=s.token,index=16,removedCrates=#removed,crates=removed,ownedAbsent=true,ownedRemaining=0,originalRootIds=s.ids.originalRootIds}
end
function F.abort(s)
 if not s then return {cleanupTransport=F.cleanupTransport,restored=true,unprepared=true}end
 local removed=removeItems(s);s.phase=nil;s.nextIndex=17
 local row=F.cleanup(s);row.removedIds=removed;row.restored=true;return row
end
return F
