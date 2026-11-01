local config=require 'QueueTestSelection'
if config.suite~='loot-demand' then return end
-- Actual stopped-world contents; the caller owns save/quit. No FPP claim.
local B=assert(LootDemandBank,'LootDemandBank must be loaded')
local KEY='PZLootDemandPersistenceV1'
local function check(value,message) assert(value,'loot-demand persistence: '..message) end
local function authority(player)
 check(player and not isClient() and lootDemandInstalled(),'native authority required')
end
local function treeCount(container,seen,depth)
 seen,depth=seen or {},depth or 0
 check(depth<=32,'unexpected nesting depth')
 local count=0
 for index=0,container:getItems():size()-1 do
  local item=container:getItems():get(index);local id=item:getID()
  check(not seen[id],'duplicate item ID '..tostring(id));seen[id]=true;count=count+1
  if instanceof(item,'InventoryContainer') then count=count+treeCount(item:getInventory(),seen,depth+1) end
 end
 return count
end
local function describe(object)
 local square=assert(object:getSquare());local container=assert(object:getContainer())
 return {x=square:getX(),y=square:getY(),z=square:getZ(),name=object:getName(),
  sprite=object:getSprite():getName(),kind=container:getType()}
end
local function locate(record)
 local square=getCell():getGridSquare(record.x,record.y,record.z)
 if not square then return nil end
 local found
 for index=0,square:getObjects():size()-1 do
  local object=square:getObjects():get(index)
  if object:getName()==record.name then check(not found,'duplicate fixture name');found=object end
 end
 check(found,'persisted object absent from loaded square: '..record.name)
 check(found:getSprite() and found:getSprite():getName()==record.sprite,'saved sprite changed')
 local container=assert(found:getContainer())
 check(container:getType()==record.kind,'saved container kind changed')
 return found,container
end
local function nestedSentinel(container)
 local outer=assert(container:AddItem('Base.Nails'))
 local bag=assert(container:AddItem('Base.Garbagebag'))
 check(instanceof(bag,'InventoryContainer'),'Garbagebag is not a native bag')
 local inner=bag:getInventory();inner:setExplored(true)
 local child=assert(inner:AddItem('Base.Nails'))
 return {outer=outer:getID(),bag=bag:getID(),child=child:getID()}
end
local function checkSentinel(container,sentinel)
 local outer,bag
 for index=0,container:getItems():size()-1 do
  local item=container:getItems():get(index)
  if item:getID()==sentinel.outer then outer=item end
  if item:getID()==sentinel.bag then bag=item end
 end
 check(outer and outer:getFullType()=='Base.Nails','saved outer sentinel missing')
 check(bag and bag:getFullType()=='Base.Garbagebag' and instanceof(bag,'InventoryContainer'),'saved bag sentinel missing')
 local inner=bag:getInventory();local child
 for index=0,inner:getItems():size()-1 do
  local item=inner:getItems():get(index)
  if item:getID()==sentinel.child then child=item end
 end
 check(child and child:getFullType()=='Base.Nails','saved nested sentinel missing')
end
local function automatic(object)
 lootDemandAutomatic(object,false);lootDemandAutomatic(object,true)
end
local function observedFill(containers,work)
 local rows={}
 for _,container in ipairs(containers) do rows[container]={calls=0} end
 local function callback(room,kind,container)
  local row=rows[container];if not row then return end
  row.calls=row.calls+1;check(row.calls==1,'repeated native fill callback')
  row.sentinel=nestedSentinel(container)
 end
 Events.OnFillContainer.Add(callback)
 local ok,result=pcall(function() return work(rows) end)
 Events.OnFillContainer.Remove(callback)
 if not ok then error(result) end
 return result
end
function B.seedPersistence(player)
 authority(player)
 check(not ModData.get(KEY),'persistence seed already exists')
 local origin=player:getSquare();local squares={}
 for dx=4,8 do for dy=-3,3 do
  local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
  if #squares<2 and square and square:getFloor() and square:isFree(false)
   and square:getObjects():size()<=1 then squares[#squares+1]=square end
 end end
 check(#squares==2,'need two loaded free squares outside nearby UI scan')
 local objects,containers={},{}
 for index,kind in ipairs({'bin','dumpster'}) do
  local object=IsoObject.new(getCell(),squares[index],assert(getSprite(lootDemandSprite(kind))))
  object:createContainersFromSpriteProperties();object:setName('LootDemandPersist'..index)
  squares[index]:AddTileObject(object);objects[index]=object;containers[index]=assert(object:getContainer())
  check(lootDemandPending(containers[index]) and containers[index]:isEmpty(),'new source not pending')
 end
 return observedFill(containers,function(rows)
  local pending,completed=containers[1],containers[2]
  automatic(objects[1]);automatic(objects[2])
  check(not pending:isExplored() and pending:isEmpty() and rows[pending].calls==0,'automatic pending source filled')
  check(not completed:isExplored() and completed:isEmpty() and rows[completed].calls==0,'automatic completed candidate filled')
  check(lootDemandEnsure(completed,player) and rows[completed].calls==1,'seed demand must fill once')
  check(rows[completed].sentinel,'completed nested sentinel absent')
  checkSentinel(completed,rows[completed].sentinel)
  local fingerprint=lootDemandFingerprint(completed);local count=treeCount(completed)
  check(lootDemandEnsure(completed,player) and rows[completed].calls==1,'seed repeat filled again')
  check(lootDemandFingerprint(completed)==fingerprint,'seed repeat changed IDs/types/tree')
  local meta=ModData.getOrCreate(KEY)
  meta.schema=1;meta.phase='seeded';meta.pending=describe(objects[1]);meta.completed=describe(objects[2])
  meta.completed.fingerprint=fingerprint;meta.completed.count=count;meta.completed.sentinel=rows[completed].sentinel
  meta.completed.rows=lootDemandRows(completed)
  meta.completed.roundtripRows=lootDemandRoundtripRows(completed)
  print('[LOOT_DEMAND_TEST] DETAIL seed-before '..meta.completed.rows:gsub('\n',';'))
  print('[LOOT_DEMAND_TEST] DETAIL seed-native-roundtrip '..meta.completed.roundtripRows:gsub('\n',';'))
  -- Leave both actual world objects intact. SP caller saves; Host runner saves/quits.
  print('[LOOT_DEMAND_TEST] PASS persist-seed pending_explored=false completed_explored=true nested=true count='..count..' fingerprint='..fingerprint)
  return true
 end)
end
function B.reloadPersistence(player)
 authority(player)
 local meta=ModData.get(KEY)
 check(meta and meta.schema==1 and meta.phase=='seeded','wrong/missing stopped-world seed metadata')
 local pendingObject,pending=locate(meta.pending);local completedObject,completed=locate(meta.completed)
 if not pendingObject or not completedObject then return false end -- Caller may poll until its bounded deadline.
 return observedFill({pending,completed},function(rows)
  check(not pending:isExplored() and pending:isEmpty() and lootDemandPending(pending),'pending did not survive stopped-world reload')
  check(completed:isExplored(),'completed explored state did not persist')
  checkSentinel(completed,meta.completed.sentinel)
  check(treeCount(completed)==meta.completed.count,'completed recursive count changed')
  print('[LOOT_DEMAND_TEST] DETAIL reload-expected '..tostring(meta.completed.rows):gsub('\n',';'))
  print('[LOOT_DEMAND_TEST] DETAIL reload-actual '..lootDemandRows(completed):gsub('\n',';'))
  check(type(meta.completed.roundtripRows)=='string','seed lacks native serialized reference; preserve legacy failure evidence')
  check(lootDemandRows(completed)==meta.completed.roundtripRows,'completed IDs/native saved types/tree changed')
  automatic(pendingObject);automatic(completedObject)
  check(not pending:isExplored() and pending:isEmpty() and rows[pending].calls==0,'reload automatic path filled pending')
  check(lootDemandEnsure(completed,player) and rows[completed].calls==0,'completed source filled again after reload')
  check(lootDemandRows(completed)==meta.completed.roundtripRows,'completed repeat changed saved contents')
  check(lootDemandEnsure(pending,player) and pending:isExplored() and rows[pending].calls==1,'reloaded pending first demand did not fill once')
  check(rows[pending].sentinel,'pending first demand sentinel absent');checkSentinel(pending,rows[pending].sentinel)
  local fingerprint=lootDemandFingerprint(pending);local count=treeCount(pending)
  check(lootDemandEnsure(pending,player) and rows[pending].calls==1,'pending repeat demand filled twice')
  check(lootDemandFingerprint(pending)==fingerprint,'pending repeat changed IDs/types/tree')
  check(lootDemandMoveableRoundtrip(),'native movable load normalization regression')
  print('[LOOT_DEMAND_TEST] PASS native-moveable-roundtrip original=Base.Mov_PalletEmpty saved=Base.construction_01_5 same_id=true')
  print('[LOOT_DEMAND_TEST] PASS persist-reload pending_cold_unexplored=true completed_ids_persist=true nested=true completed_count='..meta.completed.count..' pending_count='..count)
  return true
 end)
end
-- Read-only load-phase observation helps distinguish deserialization from later
-- ticking. It is diagnostic only and never changes acceptance.
if config.cases[1]=='persist-reload' and not isClient() then
 local seen=false
 Events.LoadGridsquare.Add(function(square)
  if seen or not lootDemandInstalled() then return end
  local meta=ModData.get(KEY);local record=meta and meta.completed
  if not record or square:getX()~=record.x or square:getY()~=record.y or square:getZ()~=record.z then return end
  for index=0,square:getObjects():size()-1 do
   local object=square:getObjects():get(index)
   if object:getName()==record.name and object:getContainer() then
    seen=true
    print('[LOOT_DEMAND_TEST] DETAIL reload-grid original_sha='..meta.completed.fingerprint..' actual_sha='..lootDemandFingerprint(object:getContainer()))
    print('[LOOT_DEMAND_TEST] DETAIL reload-grid-rows '..lootDemandRows(object:getContainer()):gsub('\n',';'))
   end
  end
 end)
end
return B
