-- Native actions belong to the clients. This fixture only seeds, observes and
-- removes its exact owned identities; it never implements a workload action.
local selection=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local Model=require 'PZSurvivorToolkit/ManifestModel'
local Cleanup=require 'QueueFixtureItemCleanup'
local physical=selection.cases[1]=='physical-affinity'
local affinity=selection.cases[1]=='hidden-affinity'or physical
local F={module='WarehouseWorkloadTest',case=selection.cases[1],affinity=affinity,physical=physical,
 modes=physical and{'clean','clean','clean','clean'}or affinity and{'clean','clean'}or{'clean','vanilla'},
 steps=affinity and{'initial','peer-replace','personal-quick'}or{'initial','peer-transfer','peer-replace','peer-craft','hidden-loot'}}
local owner='PZSTWarehouseWorkloadOwner'
local function array(list)local out={};for i=0,list:size()-1 do out[#out+1]=list:get(i)end;return out end
local function integer(n)return type(n)=='number'and n==math.floor(n)end
local function empty(t)for _ in pairs(t)do return false end;return true end
local function ids(container)local out={};for _,item in ipairs(array(container:getItems()))do out[#out+1]=item:getID()end;table.sort(out);return out end
local function original(player)
 local out={};for _,item in ipairs(array(player:getInventory():getItems()))do
  local id=item:getID();assert(integer(id)and not out[id],'invalid original workload ID')
  out[id]={id=id,ft=item:getFullType(),item=item}
 end;return out
end
local function originalIds(items)local out={};for id in pairs(items)do out[#out+1]=id end;table.sort(out);return out end
function F.emit(event,row)
 row=row or {};row.suite='warehouse-workload';row.case=F.case;row.kind=selection.kind;row.mode=selection.mode
 row.role=row.role or(isServer()and'server'or isClient()and'client'or'sp')
 print('[WAREHOUSE_WORKLOAD] '..event..' '..JSON.encode(row))
end
function F.placementAt(origin)
 if not origin then return end
 -- Same six by two crate pattern as the existing SP walking fixture; the
 -- middle aisle remains clear and all capacities use the engine maximum.
 for dx=-4,3 do for dy=-2,2 do
  local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
  if not square or not square:canStand()or not square:isFree(false)or square:getRoom()
   or square:getObjects():size()>1 or square:getSpecialObjects():size()>0 then return end
 end end
 local squares={};for dx=-3,2 do for _,dy in ipairs({-1,1})do squares[#squares+1]=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())end end
 return squares
end
function F.chooseOrigin(player)
 local origin=assert(player:getSquare());if F.placementAt(origin)then return origin end
 for radius=1,12 do for dx=-radius,radius do for dy=-radius,radius do
  if math.max(math.abs(dx),math.abs(dy))==radius then
   local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
   if F.placementAt(square)then return square end
  end
 end end end;error('no loaded clear warehouse workload area within twelve tiles')
end
local function descriptor(object)
 local square=assert(object:getSquare());local x,y,z=square:getX(),square:getY(),square:getZ();local index=object:getObjectIndex()
 local key=x..','..y..','..z
 return {x=x,y=y,z=z,index=index,object=index,ci=0,key=key,id=key..'/'..index..'/0',token=object:getModData()[owner]}
end
function F.prepare(players)
 assert(isServer()and players.client1 and players.client2,'two server workload actors required')
 assert(players.client1:getOnlineID()~=players.client2:getOnlineID(),'workload peers share online ID')
 local origin=F.chooseOrigin(players.client1)
 local s={players=players,crates={},stores={},owned={},initial={},nextIndex=1}
 s.token='warehouse-workload:'..getTimestampMs()..':'..players.client1:getOnlineID()..':'..players.client2:getOnlineID()
 F.preparing=s
 s.ids={token=s.token,crates={},origin={x=origin:getX(),y=origin:getY(),z=origin:getZ()},
  actorOrigin={x=origin:getX()-2,y=origin:getY(),z=origin:getZ()},
  walkTarget={x=origin:getX()-3,y=origin:getY(),z=origin:getZ()},originalRootIds={}}
 for _,role in ipairs({'client1','client2'})do s.initial[role]=original(players[role]);s.ids.originalRootIds[role]=originalIds(s.initial[role])end
 for i,square in ipairs(assert(F.placementAt(origin)))do
  local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
  s.crates[i]=object;object:getModData()[owner]=s.token..':'..i;object:setCanPassThrough(true);object:setIsContainer(true)
  local container=assert(object:getContainer());s.stores[i]=container;container:setType('crate');container:setCapacity(100);container:setExplored(true)
  square:AddSpecialObject(object);s.ids.crates[i]=descriptor(object)
  object:transmitCompleteItemToClients();object:transmitModData()
 end
 return s
end
function F.resolve(player,packet,role)
 assert(type(packet)=='table'and type(packet.token)=='string'and #packet.crates==12,'invalid workload descriptors')
 role=role or player:getUsername();assert(role=='client1'or role=='client2','unknown workload observer')
 local s={player=player,role=role,ids=packet,token=packet.token,crates={},stores={},owned={}}
 for i,point in ipairs(packet.crates)do
  local square=getCell():getGridSquare(point.x,point.y,point.z)
  if not square or not integer(point.index)or point.index<0 or point.index>=square:getObjects():size()then return end
  local object=square:getObjects():get(point.index)
  if not object or object:getModData()[owner]~=packet.token..':'..i or object:getModData()[owner]~=point.token or not object:getContainer()then return end
  s.crates[i]=object;s.stores[i]=object:getContainer()
 end;return s
end
function F.attachPhase(s,p)
 assert(p.token==s.token and F.modes[p.index]==p.mode and p.phaseToken==s.token..':'..p.index,'wrong workload phase')
 s.phase=p;return s
end
local function eachContainer(s,callback)
 for i,container in ipairs(s.stores)do callback(container,'crate'..i)end
 if s.players then for _,role in ipairs({'client1','client2'})do callback(s.players[role]:getInventory(),role)end
 else callback(s.player:getInventory(),s.role)end
end
function F.find(s,id)
 local found,endpoint,count=nil,nil,0
 eachContainer(s,function(container,where)for _,item in ipairs(array(container:getItems()))do
  if item:getID()==id then found=item;endpoint=where;count=count+1 end
 end end);return found,endpoint,count
end
local function metadata(item,endpoint)
 local entry=assert(Model.item(item),'workload model identity missing')
 return {id=item:getID(),ft=item:getFullType(),name=entry.name,key=entry.key,cat=entry.cat,initialEndpoint=endpoint}
end
local function nativeIdentity(item,entry,container)
 assert(item:getContainer()==container and item:getFullType()==entry.ft,'workload native item/type differs')
 local custom=item:isCustomName()==true
 local name=custom and item:getDisplayName()or nil
 assert(custom==(entry.name~=nil)and name==entry.name,'workload native custom name changed')
 return name,custom
end
local function own(s,p,container,ft,name,endpoint)
 local item=assert(container:AddItem(ft),'missing native workload item '..ft);local id=item:getID()
 assert(integer(id)and not s.owned[id],'duplicate workload identity')
 for _,items in pairs(s.initial)do assert(not items[id],'workload ID aliases original')end
 item:getModData()[owner]=p.phaseToken
 if name then item:setName(name);item:setCustomName(true)end
 local entry=metadata(item,endpoint);p.items[#p.items+1]=entry;s.owned[id]=entry
 sendAddItemToContainer(container,item);return id
end
local function preserved(s,allowOutputs)
 for role,initial in pairs(s.initial)do
  local root=s.players[role]:getInventory()
  for id,entry in pairs(initial)do local item=root:getItemById(id);assert(item==entry.item and item:getContainer()==root and item:getFullType()==entry.ft,'original workload inventory changed')end
  for _,item in ipairs(array(root:getItems()))do
   local id=item:getID()
   assert(initial[id]or s.owned[id]or(allowOutputs and role=='client2'and item:getFullType()=='Base.Hotdog_single'),'foreign workload root content')
  end
 end
end
function F.seed(s,index)
 assert(isServer()and not s.phase and index==s.nextIndex and F.modes[index]and empty(s.owned),'out-of-order workload seed')
 preserved(s)
 for _,container in ipairs(s.stores)do assert(container:getItems():isEmpty(),'workload crate is not empty')end
 local p={token=s.token,index=index,mode=F.modes[index],phaseToken=s.token..':'..index,items={},outputIds={}}
 if not F.affinity then p.recipe='OpenHotdogPack';p.outputType='Base.Hotdog_single';p.outputCount=4 end
 F.attachPhase(s,p)
 for i,container in ipairs(s.stores)do
  local ft=i==3 and'Base.Bandage'or i==4 and'Base.HotdogPack'or'Base.Nails'
  local name=i==3 and'Warehouse old bandage'or nil
  local id=own(s,p,container,ft,name,'crate'..i)
  if i==1 then p.transferId=id elseif i==3 then p.replacementSourceId=id elseif i==4 then p.craftInputId=id elseif i==5 then p.quickId=id end
 end
 local replacementType,replacementName='Base.Bandage','Warehouse new bandage'
 if F.affinity then replacementType='Base.Screwdriver';replacementName=nil end
 p.replacementId=own(s,p,s.players.client2:getInventory(),replacementType,replacementName,'client2')
 if F.affinity then
  p.affinityKind=index%2==1 and'type'or'category'
  if F.physical then p.transferMethod=index<=2 and'1'or'2'end
  p.oldCandidateId=own(s,p,s.players.client1:getInventory(),'Base.Bandage',nil,'client1')
  p.newCandidateId=own(s,p,s.players.client1:getInventory(),'Base.Screwdriver',nil,'client1')
  local function category(id)
   local item=assert(F.find(s,id));local value=item:getDisplayCategory()
   return value and value~=''and value or'Other'
  end
  p.oldCategory=category(p.replacementSourceId);p.newCategory=category(p.replacementId)
  assert(p.oldCategory~=p.newCategory and category(p.oldCandidateId)==p.oldCategory
   and category(p.newCandidateId)==p.newCategory,'workload affinity category controls differ')
  for slot,container in ipairs(s.stores)do if slot~=3 then
   for _,item in ipairs(array(container:getItems()))do local value=category(item:getID())
    assert(value~=p.oldCategory and value~=p.newCategory,'unrelated workload stock masks affinity category controls')
   end
  end end
 else p.quickMatchId=own(s,p,s.players.client1:getInventory(),'Base.Nails',nil,'client1')end
 p.state='initial';return p
end
function F.expected(p,step,outcome,oldDestination)
 if F.affinity then
  local rank={initial=1,['peer-replace']=2,['personal-quick']=3}
  local n=assert(rank[step],'unknown workload step');local expected={}
  for _,entry in ipairs(p.items)do expected[entry.id]=entry.initialEndpoint end
  if n>=2 then expected[p.replacementSourceId]='client2';expected[p.replacementId]='crate3'end
  if n>=3 then
   outcome=outcome or p.affinityOutcome or'fresh';oldDestination=oldDestination or p.oldDestination
   assert(outcome=='fresh'or outcome=='stale'or outcome=='blocked','unknown workload affinity outcome')
   if outcome=='fresh'then expected[p.newCandidateId]='crate3'
   elseif outcome=='stale'then
    local ownedDestination=false
    for _,entry in ipairs(p.items)do if entry.initialEndpoint==oldDestination and string.sub(entry.initialEndpoint,1,5)=='crate'then ownedDestination=true end end
    assert(ownedDestination,'missing workload stale destination');expected[p.oldCandidateId]=oldDestination
   end
  end
  return expected
 end
 local rank={initial=1,['peer-transfer']=2,['peer-replace']=3,['peer-craft']=4,['hidden-loot']=5}
 local n=assert(rank[step],'unknown workload step');local expected={}
 for _,entry in ipairs(p.items)do expected[entry.id]=entry.initialEndpoint end
 if n>=2 then expected[p.transferId]='crate2'end
 if n>=3 then expected[p.replacementSourceId]='client2';expected[p.replacementId]='crate3'end
 if n>=4 then expected[p.craftInputId]='consumed';for _,id in ipairs(p.outputIds)do expected[id]='client2'end end
 if n>=5 then expected[p.quickId]='client1'end
 return expected
end
function F.snapshot(s)
 local row={token=s.token,index=s.phase and s.phase.index or 0,phaseToken=s.phase and s.phase.phaseToken,items={},crates={},rootIds={},visibility=s.players and'both-roots'or s.role}
 local readOnly=F.affinity and not s.players;local containers={}
 if readOnly then
  row.projection='native-identity'
  eachContainer(s,function(container,endpoint)containers[endpoint]=container end)
 end
 local entries=s.phase and s.phase.items or {}
 for _,entry in ipairs(entries)do
  local item,endpoint,count=F.find(s,entry.id)
  if item then
   local observed={id=entry.id,ft=item:getFullType(),endpoint=endpoint,count=count}
   if readOnly then
    assert(count==1,'duplicated workload native ID')
    observed.name,observed.customName=nativeIdentity(item,entry,containers[endpoint])
    observed.rawCategory=item:getDisplayCategory()
   else
    local actual=assert(Model.item(item));observed.key=actual.key;observed.cat=actual.cat
    if F.affinity then observed.name=actual.name;observed.customName=item:isCustomName()==true end
   end
   row.items[#row.items+1]=observed
  end
 end
 local actor=s.players and s.players.client1 or s.player
 for i,container in ipairs(s.stores)do row.crates[i]={slot=i,id=s.ids.crates[i].id,capacity=container:getCapacity(),
  effectiveCapacity=container:getEffectiveCapacity(actor),weight=container:getCapacityWeight(),itemIds=ids(container)}end
 if s.players then for role,player in pairs(s.players)do row.rootIds[role]=ids(player:getInventory())end
 else row.rootIds[s.role]=ids(s.player:getInventory())end
 return row
end
local function adoptOutputs(s,p)
 local out={};local root=s.players.client2:getInventory()
 for _,item in ipairs(array(root:getItems()))do
  local id=item:getID()
  if not s.initial.client2[id]and not s.owned[id]then
   assert(item:getFullType()==p.outputType and integer(id),'foreign craft output candidate')
   out[#out+1]=item
  end
 end
 assert(#out<=p.outputCount,'extra native workload recipe output')
 if #out~=p.outputCount then return end
 local _,_,inputCount=F.find(s,p.craftInputId);if inputCount~=0 then return end
 table.sort(out,function(a,b)return a:getID()<b:getID()end)
 for _,item in ipairs(out)do
  local entry=metadata(item,'client2');s.owned[entry.id]=entry;p.items[#p.items+1]=entry;p.outputIds[#p.outputIds+1]=entry.id
  -- Adoption changes ownership bookkeeping only, never the native recipe effect.
 end;return true
end
local function affinityOutcome(s,p)
 local function at(id,target)
  local _,endpoint,count=F.find(s,id);assert(count<=1,'duplicated workload native ID')
  local visible=s.players or target==s.role or string.sub(target,1,5)=='crate'
  return visible and count==1 and endpoint==target or not visible and count==0
 end
 if at(p.oldCandidateId,'client1')and at(p.newCandidateId,'crate3')then return'fresh','client1'end
 if at(p.oldCandidateId,'client1')and at(p.newCandidateId,'client1')then return'blocked','client1'end
 if at(p.newCandidateId,'client1')then
  for slot in ipairs(s.stores)do local destination='crate'..slot
   if at(p.oldCandidateId,destination)then return'stale',destination end
  end
 end
end
function F.native(s,step)
 local p=assert(s.phase)
 if s.players then
  preserved(s,not F.affinity and step=='peer-craft'and #p.outputIds==0)
  if not F.affinity and(step=='peer-craft'or step=='hidden-loot')and #p.outputIds==0 and not adoptOutputs(s,p)then return end
 end
 local outcome,oldDestination
 if F.affinity and step=='personal-quick'then
  outcome,oldDestination=affinityOutcome(s,p)
  if not outcome or p.affinityOutcome and(p.affinityOutcome~=outcome or p.oldDestination~=oldDestination)then return end
 end
 local expected=F.expected(p,step,outcome,oldDestination);local known={};for _,entry in ipairs(p.items)do known[entry.id]=entry end
 local complete=true
 eachContainer(s,function(container,endpoint)
  local crate=string.sub(endpoint,1,5)=='crate'
  if crate then
   local actor=s.players and s.players.client1 or s.player
   assert(container:getCapacity()==100 and container:getCapacityWeight()<=container:getEffectiveCapacity(actor),'workload crate capacity changed/overfilled')
  end
  for _,item in ipairs(array(container:getItems()))do
   local id=item:getID();local entry=known[id]
   if crate then assert(entry,'foreign workload crate content')end
   if entry then
    if F.affinity and not s.players then nativeIdentity(item,entry,container)
    else
     assert(item:getContainer()==container and item:getFullType()==entry.ft,'workload native item/type differs')
     local actual=assert(Model.item(item));assert(actual.key==entry.key and actual.cat==entry.cat,'workload native identity/category changed')
    end
   end
  end
 end)
 for id,target in pairs(expected)do
  local _,endpoint,count=F.find(s,id);assert(count<=1,'duplicated workload native ID')
  local visible=s.players or target=='consumed'or target==s.role or string.sub(target,1,5)=='crate'
  if visible then if target=='consumed'then if count~=0 then complete=false end elseif count~=1 or endpoint~=target then complete=false end
  elseif count~=0 then complete=false end
 end
 if not complete then return end
 if outcome then p.affinityOutcome=outcome;p.oldDestination=oldDestination end
 local row=F.snapshot(s);row.step=step;row.outputIds=p.outputIds
 row.consumedId=not F.affinity and(step=='peer-craft'or step=='hidden-loot')and p.craftInputId or nil
 row.affinityOutcome=p.affinityOutcome;row.oldDestination=p.oldDestination;return row
end
local function validateCleanup(s,journal)
 preserved(s)
 local found={}
 eachContainer(s,function(container,endpoint)
  for _,item in ipairs(array(container:getItems()))do
   local id=item:getID()
   if string.sub(endpoint,1,5)=='crate'then assert(s.owned[id],'refusing foreign workload crate content cleanup')end
   if s.owned[id]then
    assert(not found[id],'duplicated workload cleanup identity')
    found[id]={item=item,container=container}
   end
  end
 end)
 for slot,object in ipairs(s.crates)do
  assert(object:getModData()[owner]==s.token..':'..slot and object:getContainer()==s.stores[slot],'refusing foreign workload object cleanup')
 end
 local entries={}
 for id,entry in pairs(s.owned)do
  local live=found[id];local item=live and live.item
  local consumed=s.phase and id==s.phase.craftInputId and #s.phase.outputIds==4
  if consumed then assert(not live,'consumed workload input reappeared')
  elseif journal and journal.byId[id]and Cleanup.removed(journal.j,journal.byId[id].item)then
   assert(not live,'removed workload identity reappeared')
  else
   assert(item and item:getFullType()==entry.ft,'refusing missing/foreign workload cleanup identity')
   assert(item:getContainer()==live.container,'workload cleanup pointer differs')
   local output=false;for _,outputId in ipairs(s.phase.outputIds)do if outputId==id then output=true end end
   assert(output or item:getModData()[owner]==s.phase.phaseToken,'refusing foreign workload item token')
   for _,player in pairs(s.players)do assert(not player:isEquipped(item),'refusing equipped workload item cleanup')end
   entries[#entries+1]={id=id,item=item,container=live.container,ft=entry.ft}
  end
 end;return entries
end
local function cleanupInventory(s)
 local lease=s.inventoryCleanup
 if not lease then
  local entries=validateCleanup(s);local containers={};eachContainer(s,function(container)containers[#containers+1]=container end)
  lease={phase=s.phase,token=s.token,phaseToken=s.phase and s.phase.phaseToken,index=s.phase and s.phase.index,
   owned=s.owned,byId={},metadata={},metadataValues={},outputs={},craftInputId=s.phase and s.phase.craftInputId,containers=containers,crates={},stores={},points={},players={}}
  for id,entry in pairs(s.owned)do lease.metadata[id]=entry;lease.metadataValues[id]={ft=entry.ft,key=entry.key,cat=entry.cat}end
  if s.phase then for i,id in ipairs(s.phase.outputIds)do lease.outputs[i]=id end end
  for i,object in ipairs(s.crates)do
   lease.crates[i]=object;lease.stores[i]=s.stores[i]
   lease.points[i]={square=assert(object:getSquare()),point=descriptor(object)}
   assert(lease.points[i].point.index>=0,'workload cleanup native object missing')
  end
  for role,player in pairs(s.players)do lease.players[role]={player=player,root=player:getInventory(),onlineID=player:getOnlineID()}end
  for _,entry in ipairs(entries)do lease.byId[entry.id]=entry end
  lease.j=Cleanup.new(entries,{containers=containers,server=true,guard=function()
   assert(s.token==lease.token and s.phase==lease.phase and s.owned==lease.owned
    and(not s.phase or(s.phase.phaseToken==lease.phaseToken and s.phase.index==lease.index)),
    'workload cleanup generation changed')
   assert(#s.crates==#lease.crates and #s.stores==#lease.stores,'workload cleanup objects changed')
   for i,object in ipairs(lease.crates)do
    local frozen=lease.points[i];local point=frozen.point
    assert(s.crates[i]==object and s.stores[i]==lease.stores[i],'workload cleanup endpoints changed')
    assert(object:getSquare()==frozen.square and object:getObjectIndex()==point.index
     and frozen.square:getX()==point.x and frozen.square:getY()==point.y and frozen.square:getZ()==point.z,
     'workload cleanup native object descriptor changed')
   end
   for role,entry in pairs(lease.players)do assert(s.players[role]==entry.player and entry.player:getInventory()==entry.root
    and entry.player:getOnlineID()==entry.onlineID,'workload cleanup player/root descriptor changed')end
   for id,entry in pairs(s.owned)do assert(lease.metadata[id]==entry,'workload cleanup ownership cohort changed')end
   for id,entry in pairs(lease.metadata)do
    local frozen=lease.metadataValues[id]
    assert(s.owned[id]==entry and entry.ft==frozen.ft and entry.key==frozen.key and entry.cat==frozen.cat,'workload cleanup ownership cohort changed')
   end
   if s.phase then
    assert(s.phase.craftInputId==lease.craftInputId and #s.phase.outputIds==#lease.outputs,'workload cleanup recipe cohort changed')
    for i,id in ipairs(lease.outputs)do assert(s.phase.outputIds[i]==id,'workload cleanup recipe cohort changed')end
   end
   validateCleanup(s,lease)
  end,check=function(entry)
   assert(lease.byId[entry.id].item==entry.item and s.owned[entry.id]and s.owned[entry.id].ft==entry.ft,
    'workload cleanup ownership changed')
   local output=false;for _,id in ipairs(lease.outputs)do if id==entry.id then output=true end end
   assert(output or entry.item:getModData()[owner]==lease.phaseToken,'workload cleanup item token changed')
   local actual=assert(Model.item(entry.item));local metadata=lease.metadataValues[entry.id]
   assert(actual.key==metadata.key and actual.cat==metadata.cat,'workload cleanup item metadata changed')
   for _,player in pairs(s.players)do assert(not player:isEquipped(entry.item),'refusing equipped workload item cleanup')end
  end})
  s.inventoryCleanup=lease
 end
 return Cleanup.run(lease.j)
end
function F.release(s,index)
 if s.releases and s.releases[index]then
  local lease=assert(s.releaseLeases[index]);local row=s.releases[index]
  assert(not s.phase and not s.worldCleanup and s.nextIndex==index+1 and s.token==lease.token
   and s.owned==lease.releasedOwned and empty(s.owned),'stale workload release generation')
  preserved(s)
  assert(#s.crates==#lease.crates and #s.stores==#lease.stores,'released workload object cohort changed')
  for role,entry in pairs(lease.players)do
   assert(s.players[role]==entry.player and entry.player:getInventory()==entry.root
    and entry.player:getOnlineID()==entry.onlineID,'released workload root descriptor changed')
  end
  for slot,object in ipairs(lease.crates)do
   local frozen=lease.points[slot];local point=frozen.point
   assert(s.crates[slot]==object and s.stores[slot]==lease.stores[slot]
    and object:getContainer()==lease.stores[slot]and object:getModData()[owner]==lease.token..':'..slot
    and object:getSquare()==frozen.square and object:getObjectIndex()==point.index
    and frozen.square:getX()==point.x and frozen.square:getY()==point.y and frozen.square:getZ()==point.z,
    'released workload ownership changed')
   assert(lease.stores[slot]:getItems():isEmpty(),'released workload crate refilled')
  end
  assert(row.token==lease.token and row.index==index and row.phaseToken==lease.phaseToken,'released workload receipt changed')
  return row
 end
 local p=assert(s.phase);local finalStep=F.steps[#F.steps]
 assert(index==p.index and p.state==finalStep,'unfinished workload release')
 if not s.inventoryCleanup then assert(F.native(s,finalStep),'unfinished workload release')end
 local receipt=cleanupInventory(s)
 for _,container in ipairs(s.stores)do assert(container:getItems():isEmpty(),'workload crate survived release')end
 preserved(s);local lease=s.inventoryCleanup
 s.owned={};lease.releasedOwned=s.owned;s.phase=nil;s.nextIndex=index+1;s.inventoryCleanup=nil
 local row={token=s.token,index=index,phaseToken=p.phaseToken,removedIds=receipt.removedIds,cleanupJournal=receipt,
  consumedIds=F.affinity and{}or{p.craftInputId},affinityOutcome=p.affinityOutcome,oldDestination=p.oldDestination,
  ownedRemaining=0,originalRootIds=s.ids.originalRootIds,snapshot=F.snapshot(s)}
 s.releases=s.releases or {};s.releaseLeases=s.releaseLeases or {}
 s.releases[index]=row;s.releaseLeases[index]=lease;return row
end
local function present(square,object)
 for _,getter in ipairs({'getObjects','getSpecialObjects'})do
  for _,candidate in ipairs(array(square[getter](square)))do if candidate==object then return true end end
 end;return false
end
function F.absent(packet)
 for _,point in ipairs(packet.crates)do
  local square=getCell():getGridSquare(point.x,point.y,point.z);if not square then return false end
  for _,getter in ipairs({'getObjects','getSpecialObjects'})do
   for _,object in ipairs(array(square[getter](square)))do if object:getModData()[owner]==point.token then return false end end
  end
 end;return true
end
function F.cleanup(s)
 assert(not s.phase and s.nextIndex==#F.modes+1 and empty(s.owned),'unfinished workload cleanup');preserved(s)
 local world=s.worldCleanup
 if not world then
  world={entries={},removed={},token=s.token}
  -- Freeze all exact objects and packet descriptors before deleting any.
  for slot,object in ipairs(s.crates)do
   assert(object:getModData()[owner]==s.token..':'..slot and object:getContainer()==s.stores[slot]
    and object:getContainer():getItems():isEmpty(),'refusing foreign/nonempty workload crate')
   local square=assert(object:getSquare());assert(present(square,object)and object:getObjectIndex()>=0,'missing workload crate before cleanup')
   world.entries[#world.entries+1]={object=object,container=s.stores[slot],square=square,point=descriptor(object),status='pending'}
  end
  s.worldCleanup=world
 end
 assert(s.token==world.token and #s.crates==#world.entries,'workload world cleanup cohort changed')
 for slot,entry in ipairs(world.entries)do
  local object=entry.object
  assert(s.crates[slot]==object and object:getModData()[owner]==entry.point.token
   and s.stores[slot]==entry.container and object:getContainer()==entry.container
   and object:getContainer():getItems():isEmpty(),'workload world cleanup ownership changed')
  assert(entry.status~='uncertain','workload world publication uncertain; refusing index retransmission')
  if entry.status=='done'then assert(not present(entry.square,object),'removed workload crate reappeared')
  else assert(present(entry.square,object)or entry.status=='sent','workload crate missing before publication')end
 end
 for _,entry in ipairs(world.entries)do
  local object=entry.object
  if entry.status~='done'then
   if entry.status=='pending'then
    local point=descriptor(object)
    assert(point.id==entry.point.id and object:getSquare()==entry.square,'workload world cleanup index changed')
    -- A throw may follow publication: never send this mutable square index again.
    entry.status='uncertain';entry.square:transmitRemoveItemFromSquare(object);entry.status='sent'
   end
   if present(entry.square,object)then object:removeFromWorld();object:removeFromSquare()end
   assert(not present(entry.square,object)and object:getObjectIndex()<0,'owned workload crate survived cleanup')
   entry.point.afterIndex=object:getObjectIndex();world.removed[#world.removed+1]=entry.point;entry.status='done'
  end
 end
 assert(F.absent(s.ids),'owned workload objects remain')
 return {token=s.token,index=#F.modes,removedCrates=#world.removed,crates=world.removed,ownedAbsent=true,
  ownedRemaining=0,originalRootIds=s.ids.originalRootIds,snapshot=F.snapshot(s)}
end
function F.abort(s)
 if not s then return {restored=true,unprepared=true}end
 if s.abortReceipt then F.cleanup(s);return s.abortReceipt end
 if not s.abortInventory then
  if not F.affinity and not s.inventoryCleanup and s.phase and #s.phase.outputIds==0 then
   local _,_,count=F.find(s,s.phase.craftInputId)
   if count==0 then assert(adoptOutputs(s,s.phase),'cannot safely adopt incomplete workload recipe outputs')end
  end
  local receipt=cleanupInventory(s)
  s.abortInventory=receipt;s.owned={};s.phase=nil;s.nextIndex=#F.modes+1;s.inventoryCleanup=nil
 end
 local row=F.cleanup(s);row.removedIds=s.abortInventory.removedIds;row.cleanupJournal=s.abortInventory;row.restored=true
 s.abortReceipt=row;return row
end
return F
