-- Server-owned native objects/items and read-only cross-role evidence.
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local F={module='SmartDepositHostTest',modes={'clean','vanilla'}}
local offsets={{1,0},{0,1},{-1,0}}
local ownerField='SmartDepositHostOwner'
local function array(list)local out={};for i=0,list:size()-1 do out[#out+1]=list:get(i)end;return out end
local function finite(value)assert(type(value)=='number'and value==value and math.abs(value)<math.huge,'non-finite deposit weight');return value end
local function integer(value) return type(value)=='number'and value==math.floor(value)end
local function empty(values)for _ in pairs(values)do return false end;return true end
function F.role()return isServer()and 'server'or isClient()and 'client'or 'sp'end
function F.emit(event,row)
 row=row or {};row.suite='smart-deposit';row.case='partial';row.kind=config.kind;row.mode=config.mode;row.role=F.role()
 row.token=row.token or F.activeToken;row.index=row.index or F.activeIndex or 0
 row.paneMode=row.paneMode or row.phase and row.phase.mode or F.activePaneMode
 assert(type(row.token)=='string'and row.token~='','deposit receipt has no session token')
 print('[SMART_DEPOSIT_HOST] '..event..' '..JSON.encode(row))
end
function F.originalItems(player)
 local out={};for _,item in ipairs(array(player:getInventory():getItems()))do local id=item:getID();assert(integer(id)and not out[id],'invalid original identity');out[id]=item end;return out
end
local function idsOf(items)local out={};for id in pairs(items)do out[#out+1]=id end;table.sort(out);return out end
local function containerIds(container)local out={};for _,item in ipairs(array(container:getItems()))do out[#out+1]=item:getID()end;table.sort(out);return out end
local function point(object)
 local square=assert(object:getSquare());return {x=square:getX(),y=square:getY(),z=square:getZ(),index=object:getObjectIndex(),token=object:getModData()[ownerField]}
end
local function objectAt(desc)
 local square=desc and getCell():getGridSquare(desc.x,desc.y,desc.z)
 if not square or not integer(desc.index)or desc.index<0 or desc.index>=square:getObjects():size()then return end
 local object=square:getObjects():get(desc.index)
 if object and object:getSquare()==square and object:getModData()[ownerField]==desc.token then return object end
end
function F.absent(ids)
 for _,desc in ipairs(ids.crates)do
  -- Indices can shift during removal. Search the tile for the owner token too.
  local square=getCell():getGridSquare(desc.x,desc.y,desc.z)
  if not square then return false end
  for _,object in ipairs(array(square:getObjects()))do if object:getModData()[ownerField]==desc.token then return false end end
 end
 return true
end
function F.placementAt(origin)
 if not origin or not origin:canStand()or not origin:isFree(false)or origin:getRoom()then return end
 for dx=-1,1 do for dy=-1,1 do
  local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
  if not square or not square:canStand()or not square:isFree(false)or square:getRoom()
   or square:getObjects():size()>1 or square:getSpecialObjects():size()>0 then return end
 end end
 local squares={};for i,offset in ipairs(offsets)do
  local square=getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ())
  if origin:isBlockedTo(square)then return end;squares[i]=square
 end;return squares
end
function F.chooseOrigin(player)
 local origin=assert(player:getSquare());if F.placementAt(origin)then return origin end
 for radius=1,12 do for dx=-radius,radius do for dy=-radius,radius do
  if math.max(math.abs(dx),math.abs(dy))==radius then
   local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
   if F.placementAt(square)then return square end
  end
 end end end
 error('no loaded clear 3x3 Smart Deposit fixture area within twelve tiles')
end
function F.prepare(player)
 local s={player=player,initial=F.originalItems(player),crates={},stores={},owned={},nextIndex=1}
 s.token='smart-deposit:'..player:getUsername()..':'..getTimestampMs();F.activeToken=s.token;F.activeIndex=0;F.preparing=s
 local origin=assert(player:getSquare());local squares=assert(F.placementAt(origin),'Smart Deposit origin no longer clear')
 s.ids={token=s.token,crates={},origin={x=origin:getX(),y=origin:getY(),z=origin:getZ()},originalRootIds=idsOf(s.initial)}
 for i,square in ipairs(squares)do
  local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
  s.crates[i]=object;object:getModData()[ownerField]=s.token..':'..i
  object:setCanPassThrough(true);object:setIsContainer(true)
  local container=assert(object:getContainer());s.stores[i]=container
  container:setType('crate');container:setCapacity(10);container:setExplored(true);square:AddSpecialObject(object)
  s.ids.crates[i]=point(object)
  if isServer()then object:transmitCompleteItemToClients();object:transmitModData()end
 end
 F.emit('SETUP',{ids=s.ids,originalRootIds=idsOf(s.initial),snapshot=F.snapshot(s)})
 return s
end
function F.resolve(player,ids)
 assert(type(ids.token)=='string'and #ids.crates==3,'invalid deposit descriptors')
 local s={player=player,ids=ids,token=ids.token,crates={},stores={},owned={}}
 for i,desc in ipairs(ids.crates)do
  local object=objectAt(desc);if not object then return end
  if not instanceof(object,'IsoThumpable')or not object:getContainer()then return end
  s.crates[i]=object;s.stores[i]=object:getContainer()
 end
 F.activeToken=ids.token;F.activeIndex=0;return s
end
function F.find(s,id)
 local found,endpoint,count=nil,nil,0
 for slot=0,3 do
  local container=slot==0 and s.player:getInventory()or s.stores[slot]
  if container then for _,item in ipairs(array(container:getItems()))do
   if item:getID()==id then found=item;endpoint=slot==0 and 'root'or 'crate'..slot;count=count+1 end
  end end
 end
 return found,endpoint,count
end
function F.phaseIds(phase)
 local out,seen={},{}
 for _,name in ipairs({'sampleIds','stockIds','fillerIds','extraIds'})do for _,id in ipairs(phase[name]or {})do
  assert(integer(id)and not seen[id],'duplicate/invalid phase identity');seen[id]=true;out[#out+1]=id
 end end;return out
end
function F.attachPhase(s,phase)
 assert(phase.token==s.ids.token and F.modes[phase.index]==phase.mode,'wrong deposit phase')
 s.phase=phase;F.activeToken=s.ids.token;F.activeIndex=phase.index;F.activePaneMode=phase.mode;return s
end
function F.resolvePhase(s,phase)
 F.attachPhase(s,phase)
 local owned={};for _,id in ipairs(F.phaseIds(phase))do local item,_,count=F.find(s,id);if not item or count~=1 then return end;owned[id]=item end
 s.owned=owned;return s
end
function F.absentPhase(s,phase)
 for _,id in ipairs(F.phaseIds(phase))do local _,_,count=F.find(s,id);if count~=0 then return false end end;return true
end
function F.snapshot(s)
 local row={index=s.phase and s.phase.index or F.activeIndex or 0,phaseMode=s.phase and s.phase.mode or nil,items={},crates={},rootIds=containerIds(s.player:getInventory()),originalRootIds=s.initial and idsOf(s.initial)or s.ids.originalRootIds}
 for _,id in ipairs(s.phase and F.phaseIds(s.phase)or idsOf(s.owned))do
  local item,endpoint,count=F.find(s,id)
  row.items[#row.items+1]={id=id,endpoint=endpoint or 'absent',count=count,type=item and item:getFullType()or '',weight=item and finite(item:getUnequippedWeight())or 0}
 end
 for slot,container in ipairs(s.stores)do row.crates[slot]={slot=slot,capacity=container:getCapacity(),effectiveCapacity=container:getEffectiveCapacity(s.player),weight=finite(container:getCapacityWeight()),itemIds=containerIds(container)}end
 return row
end
local function originalPreserved(s)
 for id,item in pairs(s.initial)do assert(s.player:getInventory():getItemById(id)==item,'original deposit inventory identity changed')end
 for _,item in ipairs(array(s.player:getInventory():getItems()))do assert(s.initial[item:getID()]==item or s.owned[item:getID()]==item,'foreign item added to deposit root')end
end
local function own(s,container,kind,name,weight)
 local item=assert(container:AddItem(kind),'missing native deposit item '..kind);local id=item:getID()
 assert(integer(id)and not s.initial[id]and not s.owned[id],'duplicate deposit owned identity');s.owned[id]=item
 if name then item:setName(name)end
 if weight then item:setCustomWeight(true);item:setActualWeight(weight);item:setWeight(weight)end
 if isServer()then sendAddItemToContainer(container,item)end;return item
end
local function orderOf(order)
 assert(type(order)=='table'and #order==3,'three deposit crate slots required');local seen={}
 for _,slot in ipairs(order)do assert(integer(slot)and slot>=1 and slot<=3 and not seen[slot],'deposit crate order is not a full permutation');seen[slot]=true end
 return {order[1],order[2],order[3]}
end
function F.origin(s,index)
 assert(not s.phase and index==s.nextIndex and F.modes[index],'out-of-order deposit origin check')
 local player,origin=s.player,s.ids.origin;local square=player:getSquare()
 local x,y,z=player:getX(),player:getY(),player:getZ()
 local row={token=s.token,index=index,x=x,y=y,z=z,squareX=square and square:getX(),squareY=square and square:getY(),squareZ=square and square:getZ()}
 row.ready=square~=nil and row.squareX==origin.x and row.squareY==origin.y and row.squareZ==origin.z
  and math.abs(x-origin.x-.5)<=.02 and math.abs(y-origin.y-.5)<=.02 and math.abs(z-origin.z)<=.02
 return row
end
function F.seed(s,index,order)
 assert(not s.phase and index==s.nextIndex and F.modes[index],'out-of-order deposit seed');assert(empty(s.owned),'old deposit items remain')
 assert(F.origin(s,index).ready,'deposit actor is not at authoritative fixture origin')
 originalPreserved(s)
 for _,container in ipairs(s.stores)do assert(container:getItems():isEmpty(),'deposit crate is not empty')end
 local p={token=s.token,index=index,mode=F.modes[index],order=orderOf(order),sampleIds={},stockIds={},stockTypes={'Base.Screws','Base.Nails'},fillerIds={}}
 F.attachPhase(s,p);p.state='seeded'
 for i=1,4 do p.sampleIds[i]=own(s,s.player:getInventory(),'Base.Nails','Deposit '..i):getID()end
 local sample=assert(s.owned[p.sampleIds[1]]);local weight=sample:getUnequippedWeight();assert(weight>0,'zero deposit sample weight')
 p.stockIds[1]=own(s,s.stores[p.order[2]],'Base.Screws'):getID();p.stockIds[2]=own(s,s.stores[p.order[3]],'Base.Nails'):getID()
 for slot,container in ipairs(s.stores)do
  local stockWeight=container:getCapacityWeight();local fillerWeight=container:getEffectiveCapacity(s.player)-stockWeight-weight*1.5
  assert(fillerWeight>0,'invalid native deposit filler weight')
  p.fillerIds[slot]=own(s,container,'Base.Apple',nil,fillerWeight):getID()
  assert(container:hasRoomFor(s.player,sample)and not container:hasRoomFor(s.player,weight*2,weight*2),'native deposit one-item capacity differs')
 end
 F.emit('SEED',{index=index,phase=p,snapshot=F.snapshot(s)});return p
end
local function sampleOrder(p,ids)
 assert(type(ids)=='table'and #ids==4,'four sorted deposit samples required');local expected,seen={},{}
 for _,id in ipairs(p.sampleIds)do expected[id]=true end
 for _,id in ipairs(ids)do assert(expected[id]and not seen[id],'sorted deposit samples are not the same four IDs');seen[id]=true end
 return {ids[1],ids[2],ids[3],ids[4]}
end
function F.verify(s,full)
 local p=assert(s.phase);assert(p.sortedSampleIds,'deposit sample order missing');originalPreserved(s)
 local expected={}
 for i,id in ipairs(p.sortedSampleIds)do expected[id]=i<4 and 'crate'..p.order[4-i]or 'root'end
 expected[p.stockIds[1]]='crate'..p.order[2];expected[p.stockIds[2]]='crate'..p.order[3]
 for slot,id in ipairs(p.fillerIds)do expected[id]='crate'..slot end
 for _,id in ipairs(p.extraIds or {})do expected[id]='root'end
 local count=0
 for id,endpoint in pairs(expected)do
  local item,actual,occurrences=F.find(s,id);assert(item==s.owned[id]and occurrences==1 and actual==endpoint,'authoritative deposit identity/endpoint differs: '..id)
  count=count+1
 end
 assert(count==(full and 12 or 9),'deposit owned count differs')
 for slot,container in ipairs(s.stores)do
  local expectedCount=slot==p.order[1]and 2 or 3
  assert(container:getItems():size()==expectedCount,'unexpected deposit crate cardinality')
  for _,item in ipairs(array(container:getItems()))do assert(s.owned[item:getID()]==item,'foreign deposit crate content')end
  assert(container:getCapacity()==10 and container:getCapacityWeight()<=container:getEffectiveCapacity(s.player)+.0001,'deposit crate overfilled/capacity changed')
 end
 assert(s.player:getInventory():getItems():size()==#idsOf(s.initial)+(full and 4 or 1),'deposit overflow/root cardinality differs')
 return F.snapshot(s)
end
function F.effect(s,index,ids)
 local p=assert(s.phase);assert(p.index==index and p.state=='seeded','out-of-order deposit effect')
 p.sortedSampleIds=sampleOrder(p,ids);local snap=F.verify(s,false);p.state='effect'
 F.emit('EFFECT',{index=index,sampleIds=p.sortedSampleIds,phase=p,snapshot=snap});return snap
end
function F.extras(s,index)
 local p=assert(s.phase);assert(p.index==index and p.state=='effect','out-of-order deposit extras');F.verify(s,false)
 p.extraIds={};for i=1,3 do p.extraIds[i]=own(s,s.player:getInventory(),'Base.Nails','Overflow '..i):getID()end;p.state='extras'
 local row={token=s.token,index=index,extraIds=p.extraIds,phase=p,snapshot=F.snapshot(s)};F.emit('EXTRAS',row);return row
end
function F.full(s,index)
 local p=assert(s.phase);assert(p.index==index and p.state=='extras','out-of-order full deposit receipt')
 local snap=F.verify(s,true);p.state='full';F.emit('FULL',{index=index,phase=p,snapshot=snap});return snap
end
local function removeOwned(s)
 local removed,entries={},{}
 for id,owned in pairs(s.owned)do
  local item,_,count=F.find(s,id);assert(count==1 and item==owned,'refusing unknown/missing deposit cleanup item')
  local container=item:getContainer();assert(container,'owned deposit item has no container')
  entries[#entries+1]={id=id,item=item,container=container}
 end
 for _,entry in ipairs(entries)do
  entry.container:Remove(entry.item);if isServer()then sendRemoveItemFromContainer(entry.container,entry.item)end;removed[#removed+1]=entry.id
 end
 table.sort(removed);s.owned={};return removed
end
function F.release(s,index)
 local p=assert(s.phase);assert(p.index==index and p.state=='full','out-of-order deposit release');F.verify(s,true)
 local removed=removeOwned(s);assert(#removed==12,'wrong deposit release count');s.phase=nil;s.nextIndex=index+1;originalPreserved(s)
 local crates={};for slot,container in ipairs(s.stores)do assert(container:getItems():isEmpty(),'foreign deposit item survived release');crates[slot]=containerIds(container)end
 local row={token=s.token,index=index,removedIds=removed,remainingOwnedIds={},rootIds=containerIds(s.player:getInventory()),originalRootIds=idsOf(s.initial),crateItemIds=crates,snapshot=F.snapshot(s)}
 F.emit('RELEASE',row);return row
end
local function removeCrates(s)
 local removed={}
 for slot,object in ipairs(s.crates)do
  assert(object:getModData()[ownerField]==s.token..':'..slot,'refusing foreign deposit crate cleanup')
  assert(object:getContainer():getItems():isEmpty(),'refusing deposit crate with foreign content')
  local desc=point(object);object:getSquare():transmitRemoveItemFromSquare(object)
  if object:getObjectIndex()>=0 then object:removeFromWorld();object:removeFromSquare()end
  assert(object:getObjectIndex()<0,'owned deposit crate survived cleanup');desc.afterIndex=object:getObjectIndex();removed[#removed+1]=desc
 end;return removed
end
function F.cleanup(s)
 assert(not s.phase and s.nextIndex==3 and empty(s.owned),'unfinished deposit lifecycle');originalPreserved(s)
 local removed=removeCrates(s);assert(#removed==3 and F.absent(s.ids),'owned deposit objects remain')
 local row={token=s.token,index=2,removedCrates=#removed,crates=removed,ownedRemaining=0,ownedAbsent=true,rootIds=containerIds(s.player:getInventory()),originalRootIds=idsOf(s.initial)}
 F.emit('RESTORED',row);F.emit('COMPLETE',{token=s.token,index=2,phases=2,restored=true});return row
end
function F.abort(s)
 if not s then return {restored=true,unprepared=true}end
 -- Check every object/content before mutating anything during partial cleanup.
 for slot,object in ipairs(s.crates)do
  assert(object:getModData()[ownerField]==s.token..':'..slot,'refusing foreign partial deposit crate')
  local container=object:getContainer()
  if container then for _,item in ipairs(array(container:getItems()))do assert(s.owned[item:getID()]==item,'refusing partial crate with foreign content')end end
 end
 local removed=removeOwned(s)
 local objects={}
 for slot,object in ipairs(s.crates)do if object:getObjectIndex()>=0 then
  local desc=point(object);object:getSquare():transmitRemoveItemFromSquare(object)
  if object:getObjectIndex()>=0 then object:removeFromWorld();object:removeFromSquare()end
  assert(object:getObjectIndex()<0,'partial deposit object survived');desc.afterIndex=object:getObjectIndex();objects[#objects+1]=desc
 end end
 s.phase=nil;originalPreserved(s)
 return {token=s.token,index=F.activeIndex or 0,restored=true,removedIds=removed,removedCrates=#objects,crates=objects,ownedRemaining=0,rootIds=containerIds(s.player:getInventory()),originalRootIds=idsOf(s.initial)}
end
return F
