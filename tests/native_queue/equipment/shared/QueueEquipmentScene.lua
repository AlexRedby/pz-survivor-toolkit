-- Disposable scene preparation runs once, before the first fixture snapshot.
-- It is separate from the native actions under test and never removes inventory.
local Scene={}
local Clothing=require 'QueueEquipmentClothing'
local prepared={}
function Scene.needed(cases)
 for _,id in ipairs(cases or {})do
  if Clothing.headwear({id=id})then return true end
 end
 return false
end
local function conflicting(group,location)
 for _,target in ipairs({ItemBodyLocation.HAT,ItemBodyLocation.FULL_HAT})do
  if location==target or group:isExclusive(target,location)then return true end
 end
 return false
end
local function emptyHead(player,ids)
 local values=player:getWornItems();local group=values:getBodyLocationGroup()
 local allowed
 if ids and Clothing.headwear({id=ids.case})and not Clothing.removes({id=ids.case})and not ids.clothingSetupPending then
  local spec=Clothing.spec({id=ids.case})
  allowed=ids.items and player:getInventory():getItemById(ids.items.clothingItem)
  if not allowed or allowed:getFullType()~=spec.fullType or allowed:getContainer()~=player:getInventory()
   or tostring(allowed:getBodyLocation())~=spec.location or player:getWornItem(allowed:getBodyLocation())~=allowed then return false end
 end
 for i=0,values:size()-1 do
  local entry=values:get(i)
  if conflicting(group,entry:getLocation())and entry:getItem()~=allowed then return false end
 end
 return true
end
local function retained(player,proof)
 local root=player:getInventory();local worn=player:getWornItems()
 for _,record in ipairs(proof.normalizedItems)do
  local item=root:getItemById(record.id)
  if not item or item:getFullType()~=record.fullType or item:getContainer()~=root or worn:contains(item)then return false end
 end
 return true
end
function Scene.proof(player)
 local proof=prepared[player]
 if proof then assert(retained(player,proof),'normalized starter clothing left root or became worn')end
 return proof
end
function Scene.prepare(player,cases)
 if not Scene.needed(cases)then return nil end
 assert(not isClient(),'headwear scene preparation belongs to SP/server authority')
 if prepared[player]then return Scene.proof(player)end
 local root=player:getInventory();local values=player:getWornItems();local group=values:getBodyLocationGroup()
 local originals,removed={},{}
 local inventory=root:getItems()
 for i=0,inventory:size()-1 do
  local item=inventory:get(i);originals[item:getID()]={item=item,fullType=item:getFullType()}
 end
 for i=0,values:size()-1 do
  local entry=values:get(i);local location,item=entry:getLocation(),entry:getItem()
  if conflicting(group,location)then
   assert(root:getItemById(item:getID())==item and item:getContainer()==root,'starter headwear must already be in root')
   removed[#removed+1]={item=item,location=location,id=item:getID(),fullType=item:getFullType()}
  end
 end
 for _,record in ipairs(removed)do
  -- A native exclusive-slot removal can also clear another collected entry.
  if player:getWornItem(record.location)==record.item then player:removeWornItem(record.item,false)end
 end
 if isServer()then for _,record in ipairs(removed)do sendClothing(player,record.location,nil)end end
 assert(emptyHead(player),'scene failed to clear conflicting starter worn slots')
 local count=0;inventory=root:getItems()
 for i=0,inventory:size()-1 do
  local item=inventory:get(i);local before=originals[item:getID()]
  assert(before and before.item==item and before.fullType==item:getFullType(),'scene changed starter inventory identity')
  count=count+1
 end
 local expected=0;for _ in pairs(originals)do expected=expected+1 end
 assert(count==expected,'scene lost or duplicated a starter inventory item')
 local proof={prepared=true,authority=isServer()and 'server'or 'sp',rootRetained=true,normalizedItems={}}
 for _,record in ipairs(removed)do
  proof.normalizedItems[#proof.normalizedItems+1]={id=record.id,fullType=record.fullType,location=tostring(record.location)}
 end
 table.sort(proof.normalizedItems,function(a,b)return a.id<b.id end)
 prepared[player]=proof
 return Scene.proof(player)
end
function Scene.available(player,proof,ids)
 if type(proof)~='table'or proof.prepared~=true or proof.rootRetained~=true
  or (proof.authority~='server'and proof.authority~='sp')or type(proof.normalizedItems)~='table'then return false end
 local previous
 for _,record in ipairs(proof.normalizedItems)do
  if type(record)~='table'or type(record.id)~='number'or record.id%1~=0 or record.id==-1
   or previous and record.id<=previous or type(record.fullType)~='string'or record.fullType==''
   or type(record.location)~='string'or record.location==''then return false end
  previous=record.id
 end
 return retained(player,proof)and emptyHead(player,ids)
end
return Scene
