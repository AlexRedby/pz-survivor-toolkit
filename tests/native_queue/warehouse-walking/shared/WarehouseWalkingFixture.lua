-- Full identity scans belong exclusively to preparation/admission/release barriers.
local selection=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local F={module='WarehouseWalkingTest',phases={}}
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
 row=row or {};row.suite='warehouse-walking';row.case='walk';row.kind=selection.kind;row.mode='toolkit'
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
local function roots(player)
 local out={};for _,item in ipairs(array(player:getInventory():getItems()))do
  local id=item:getID();assert(integer(id)and not out[id],'duplicate original root ID');out[id]={item=item,ft=item:getFullType()}
 end;return out
end
local function preserve(player,original)
 local seen={};local c=player:getInventory()
 for _,item in ipairs(array(c:getItems()))do local id=item:getID();local saved=original[id]
  assert(saved and not seen[id]and saved.item==item and saved.ft==item:getFullType()and item:getContainer()==c,'original walking root changed');seen[id]=true
 end
 for id in pairs(original)do assert(seen[id],'original walking root missing')end
end
local function descriptor(object)
 local square=assert(object:getSquare());local x,y,z=square:getX(),square:getY(),square:getZ();local index=object:getObjectIndex();local key=x..','..y..','..z
 return {x=x,y=y,z=z,index=index,object=index,ci=0,key=key,id=key..'/'..index..'/0',token=object:getModData()[owner]}
end
function F.prepare(players)
 assert(players.client1 and(selection.kind~='mp'or players.client2),'walking actors absent')
 if players.client2 then assert(players.client1:getOnlineID()~=players.client2:getOnlineID(),'walking actors share online ID')end
 local origin=F.chooseOrigin(players.client1);local s={players=players,crates={},stores={},owned={},initial={},nextIndex=1}
 s.token='warehouse-walking:'..getTimestampMs()..':'..players.client1:getOnlineID();F.preparing=s
 s.ids={token=s.token,crates={},origin={x=origin:getX(),y=origin:getY(),z=origin:getZ()},
  actorOrigins={},routeOrigins={},originalRootIds={}}
 for role,player in pairs(players)do
  local laneY=origin:getY()+(role=='client1'and -2 or 2)
  s.ids.actorOrigins[role]={x=origin:getX()-2,y=laneY,z=origin:getZ()}
  s.ids.routeOrigins[role]={x=origin:getX(),y=laneY,z=origin:getZ()}
  s.initial[role]=roots(player);s.ids.originalRootIds[role]=F.ids(player:getInventory())
 end
 for i,square in ipairs(assert(F.placementAt(origin)))do
  local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{});s.crates[i]=object
  object:getModData()[owner]=s.token..':'..i;object:setCanPassThrough(true);object:setIsContainer(true)
  local c=assert(object:getContainer());s.stores[i]=c;c:setType('crate');c:setCapacity(100);c:setExplored(true)
  square:AddSpecialObject(object);s.ids.crates[i]=descriptor(object)
  if isServer()then object:transmitCompleteItemToClients();object:transmitModData()end
 end;return s
end
function F.resolve(player,packet,role)
 assert(type(packet)=='table'and type(packet.token)=='string'and #packet.crates==12,'invalid walking descriptors')
 local s={player=player,role=role,ids=packet,token=packet.token,crates={},stores={},initial={[role]=roots(player)}}
 assert(F.same(F.ids(player:getInventory()),assert(packet.originalRootIds[role])),'replica original root IDs differ')
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
 if s.players then for role,player in pairs(s.players)do preserve(player,s.initial[role])end
 else preserve(s.player,s.initial[s.role])end
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
 preserved(s);local p=assert(s.phase);local row=F.context(s,{crates={},rootIds={},originals=true,identities=true,itemType='Base.Nails'})
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
 if s.players then for role,player in pairs(s.players)do row.rootIds[role]=F.ids(player:getInventory())end
 else row.rootIds[s.role]=F.ids(s.player:getInventory())end;return row
end
function F.project(native,authority,role)
 assert(native.token==authority.token and native.phaseToken==authority.phaseToken and #native.crates==12 and #authority.crates==12,'walking authority phase differs')
 for i,c in ipairs(native.crates)do local a=authority.crates[i]
  assert(c.id==a.id and c.capacity==a.capacity and F.same(c.itemIds,a.itemIds),'walking replica crate IDs differ')
 end
 assert(F.same(assert(native.rootIds[role]),assert(authority.rootIds[role])),'walking replica root IDs differ')
end
local function cleanupEntries(s)
 preserved(s);local entries={};local seen={}
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
 assert(F.absent(s.ids),'owned walking objects remain');return {token=s.token,index=16,removedCrates=#removed,crates=removed,ownedAbsent=true,ownedRemaining=0,originalRootIds=s.ids.originalRootIds}
end
function F.abort(s)
 if not s then return {restored=true,unprepared=true}end
 local removed=removeItems(s);s.phase=nil;s.nextIndex=17
 local row=F.cleanup(s);row.removedIds=removed;row.restored=true;return row
end
return F
