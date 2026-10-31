-- Native actions belong to the clients. This fixture only seeds, observes and
-- removes its exact owned identities; it never implements a workload action.
local selection=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local Model=require 'PZSurvivorToolkit/ManifestModel'
local F={module='WarehouseWorkloadTest',modes={'clean','vanilla'},steps={'initial','peer-transfer','peer-replace','peer-craft','hidden-loot'}}
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
 row=row or {};row.suite='warehouse-workload';row.case='peer-edits';row.kind=selection.kind;row.mode=selection.mode
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
 local p={token=s.token,index=index,mode=F.modes[index],phaseToken=s.token..':'..index,items={},outputIds={},recipe='OpenHotdogPack',outputType='Base.Hotdog_single',outputCount=4}
 F.attachPhase(s,p)
 for i,container in ipairs(s.stores)do
  local ft=i==3 and'Base.Bandage'or i==4 and'Base.HotdogPack'or'Base.Nails'
  local name=i==3 and'Warehouse old bandage'or nil
  local id=own(s,p,container,ft,name,'crate'..i)
  if i==1 then p.transferId=id elseif i==3 then p.replacementSourceId=id elseif i==4 then p.craftInputId=id elseif i==5 then p.quickId=id end
 end
 p.replacementId=own(s,p,s.players.client2:getInventory(),'Base.Bandage','Warehouse new bandage','client2')
 p.quickMatchId=own(s,p,s.players.client1:getInventory(),'Base.Nails',nil,'client1')
 p.state='initial';return p
end
function F.expected(p,step)
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
 local entries=s.phase and s.phase.items or {}
 for _,entry in ipairs(entries)do
  local item,endpoint,count=F.find(s,entry.id)
  if item then row.items[#row.items+1]={id=entry.id,ft=item:getFullType(),endpoint=endpoint,count=count,key=assert(Model.item(item)).key,cat=Model.item(item).cat}end
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
function F.native(s,step)
 local p=assert(s.phase)
 if s.players then
  preserved(s,step=='peer-craft'and #p.outputIds==0)
  if(step=='peer-craft'or step=='hidden-loot')and #p.outputIds==0 and not adoptOutputs(s,p)then return end
 end
 local expected=F.expected(p,step);local known={};for _,entry in ipairs(p.items)do known[entry.id]=entry end
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
    assert(item:getContainer()==container and item:getFullType()==entry.ft,'workload native item/type differs')
    local actual=assert(Model.item(item));assert(actual.key==entry.key and actual.cat==entry.cat,'workload native identity/category changed')
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
 local row=F.snapshot(s);row.step=step;row.outputIds=p.outputIds;row.consumedId=(step=='peer-craft'or step=='hidden-loot')and p.craftInputId or nil;return row
end
local function validateCleanup(s)
 preserved(s)
 for slot,object in ipairs(s.crates)do
  assert(object:getModData()[owner]==s.token..':'..slot and object:getContainer()==s.stores[slot],'refusing foreign workload object cleanup')
  for _,item in ipairs(array(s.stores[slot]:getItems()))do assert(s.owned[item:getID()],'refusing foreign workload crate content cleanup')end
 end
 local entries={}
 for id,entry in pairs(s.owned)do
  local item,_,count=F.find(s,id)
  local consumed=s.phase and id==s.phase.craftInputId and #s.phase.outputIds==4
  if consumed then assert(count==0,'consumed workload input reappeared')
  else
   assert(count==1 and item:getFullType()==entry.ft,'refusing missing/foreign workload cleanup identity')
   local output=false;for _,outputId in ipairs(s.phase.outputIds)do if outputId==id then output=true end end
   assert(output or item:getModData()[owner]==s.phase.phaseToken,'refusing foreign workload item token')
   entries[#entries+1]={id=id,item=item,container=assert(item:getContainer())}
  end
 end;return entries
end
function F.release(s,index)
 local p=assert(s.phase);assert(index==p.index and p.state=='hidden-loot'and F.native(s,'hidden-loot'),'unfinished workload release')
 local entries=validateCleanup(s);local removed={}
 for _,entry in ipairs(entries)do entry.container:Remove(entry.item);sendRemoveItemFromContainer(entry.container,entry.item);removed[#removed+1]=entry.id end
 table.sort(removed);s.owned={};s.phase=nil;s.nextIndex=index+1;preserved(s)
 for _,container in ipairs(s.stores)do assert(container:getItems():isEmpty(),'workload crate survived release')end
 return {token=s.token,index=index,phaseToken=p.phaseToken,removedIds=removed,consumedIds={p.craftInputId},ownedRemaining=0,originalRootIds=s.ids.originalRootIds,snapshot=F.snapshot(s)}
end
function F.absent(packet)
 for _,point in ipairs(packet.crates)do
  local square=getCell():getGridSquare(point.x,point.y,point.z);if not square then return false end
  for _,object in ipairs(array(square:getObjects()))do if object:getModData()[owner]==point.token then return false end end
 end;return true
end
function F.cleanup(s)
 assert(not s.phase and s.nextIndex==3 and empty(s.owned),'unfinished workload cleanup');preserved(s)
 -- Validate every object before deleting any of them.
 for slot,object in ipairs(s.crates)do assert(object:getModData()[owner]==s.token..':'..slot and object:getContainer():getItems():isEmpty(),'refusing foreign/nonempty workload crate')end
 local removed={}
 for _,object in ipairs(s.crates)do
  local point=descriptor(object);object:getSquare():transmitRemoveItemFromSquare(object)
  if object:getObjectIndex()>=0 then object:removeFromWorld();object:removeFromSquare()end
  assert(object:getObjectIndex()<0,'owned workload crate survived cleanup')
  point.afterIndex=object:getObjectIndex();removed[#removed+1]=point
 end
 assert(F.absent(s.ids),'owned workload objects remain')
 return {token=s.token,index=2,removedCrates=#removed,crates=removed,ownedAbsent=true,ownedRemaining=0,originalRootIds=s.ids.originalRootIds,snapshot=F.snapshot(s)}
end
function F.abort(s)
 if not s then return {restored=true,unprepared=true}end
 if s.phase and #s.phase.outputIds==0 then
  local _,_,count=F.find(s,s.phase.craftInputId)
  if count==0 then assert(adoptOutputs(s,s.phase),'cannot safely adopt incomplete workload recipe outputs')end
 end
 -- Validate all roots, objects and items before removing even one identity.
 local entries=validateCleanup(s);local removed={}
 for _,entry in ipairs(entries)do entry.container:Remove(entry.item);sendRemoveItemFromContainer(entry.container,entry.item);removed[#removed+1]=entry.id end
 table.sort(removed);s.owned={};s.phase=nil;s.nextIndex=3
 local row=F.cleanup(s);row.removedIds=removed;row.restored=true;return row
end
return F
