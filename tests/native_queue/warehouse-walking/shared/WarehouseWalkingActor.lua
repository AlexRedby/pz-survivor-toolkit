-- Disposable actor load. Originals stay as exact native objects outside every
-- measured inventory, independently on authority and owning replica. Never send
-- original item packets: receiving one would replace the replica's saved object.
local A={count=8,itemType='Base.Nails'}
local Items=require 'WarehouseWalkingItems'
local Cleanup=require 'QueueFixtureItemCleanup'
local owner='PZSTWarehouseWalkingActor'
local function array(list)local out={};for i=0,list:size()-1 do out[#out+1]=list:get(i)end;return out end
local function ids(items)local out={};for _,item in ipairs(items)do out[#out+1]=item:getID()end;table.sort(out);return out end
local function same(a,b)if #a~=#b then return false end;for i,v in ipairs(a)do if v~=b[i]then return false end end;return true end
local function payload(item)
 return {ft=item:getFullType(),name=item:getName(),condition=item:getCondition(),favorite=item:isFavorite(),weight=item:getUnequippedWeight()}
end
local function visit(c,out)
 for _,item in ipairs(array(c:getItems()))do
  assert(not out[item:getID()],'duplicate original actor ID');out[item:getID()]={item=item,container=c,payload=payload(item)}
  if instanceof(item,'InventoryContainer')then visit(item:getItemContainer(),out)end
 end
end
local function savedProof(s)
 local seen={}
 local function inspect(item)
  local id=item:getID();local entry=s.original[id]
  assert(entry and entry.item==item and not seen[id],'stashed original actor topology changed');seen[id]=true
  if instanceof(item,'InventoryContainer')then for _,child in ipairs(array(item:getItemContainer():getItems()))do inspect(child)end end
 end
 for _,item in ipairs(s.roots)do inspect(item)end
 for id,entry in pairs(s.original)do
  assert(seen[id]and entry.item:getID()==id,'stashed original actor ID changed/missing')
  local actual=payload(entry.item);for key,value in pairs(entry.payload)do assert(actual[key]==value,'stashed original actor payload changed: '..key)end
  local expected=entry.container
  if entry.container==s.root and s.detached then expected=nil end
  assert(entry.item:getContainer()==expected or((s.detaching or s.restoring)and entry.container==s.root and entry.item:getContainer()==s.root),'stashed original actor endpoint changed')
 end
 if s.restored then A.equipmentProof(s)end
 return {ids=s.originalIds,identity=true,payload=true,equipment=true}
end
local function equipmentEmpty(player)
 return player:getPrimaryHandItem()==nil and player:getSecondaryHandItem()==nil and player:getWornItems():size()==0 and player:getAttachedItems():size()==0
end
-- B42's ordinary clothing/attachment/hand setters send native packets. This
-- disposable fresh-actor fixture supports empty hands and no attached items;
-- it changes only the native worn collection, never those networked setters.
local function freshEquipment(player)
 assert(player:getPrimaryHandItem()==nil and player:getSecondaryHandItem()==nil and player:getAttachedItems():size()==0,
  'walking fresh actor requires empty hands and no attached items before normalization')
end
local function wornDescriptor(worn)
 local out={};for _,entry in ipairs(worn)do
  out[#out+1]={location=tostring(entry.location),id=entry.item:getID(),fullType=entry.item:getFullType()}
 end
 return {primaryEmpty=true,secondaryEmpty=true,attachedCount=0,worn=out}
end
local function refreshClothing(player)
 -- clearWornItems invalidates the native wetness cache without SyncClothing.
 -- onWornItemsChanged updates ragdoll state and server clothing modifiers;
 -- the client also needs the native modifier update, then its model refresh.
 player:onWornItemsChanged()
 if not isServer()then player:OnClothingUpdated()end
 player:resetModelNextFrame()
end
function A.save(player)
 freshEquipment(player)
 local s={player=player,root=player:getInventory(),original={},worn={},cohort={},processed={}}
 s.roots=array(s.root:getItems());s.rootIds=ids(s.roots);visit(s.root,s.original);s.originalIds={}
 local cell=getCell();local active,removing=cell:getProcessItems(),cell:getProcessItemsRemove()
 for id,entry in pairs(s.original)do
  s.originalIds[#s.originalIds+1]=id;s.processed[id]=active:contains(entry.item)and not removing:contains(entry.item)
 end;table.sort(s.originalIds)
 for _,entry in ipairs(array(player:getWornItems()))do
  local item=entry:getItem();local original=s.original[item:getID()]
  assert(original and original.item==item,'walking original worn item is not the exact inventory object')
  s.worn[#s.worn+1]={location=entry:getLocation(),item=item}
 end
 s.equipment=wornDescriptor(s.worn)
 return s
end
function A.baseline(s)return {rootIds=s.rootIds,equipment=s.equipment}end
function A.matchBaseline(s,expected,role)
 local label=role and (' ['..role..']')or''
 assert(type(expected)=='table'and type(expected.rootIds)=='table'and same(s.rootIds,expected.rootIds),
  'walking authority original root baseline differs before normalization'..label)
 local wanted,actual=expected.equipment,s.equipment
 assert(type(wanted)=='table'and wanted.primaryEmpty==true and wanted.secondaryEmpty==true and wanted.attachedCount==0
  and type(wanted.worn)=='table'and #wanted.worn==#actual.worn,
  'walking authority original equipment baseline differs before normalization'..label..' actualWorn='..#actual.worn..' expectedWorn='..tostring(wanted and type(wanted.worn)=='table'and #wanted.worn))
 for i,entry in ipairs(actual.worn)do local other=wanted.worn[i]
  assert(type(other)=='table'and other.location==entry.location and other.id==entry.id and other.fullType==entry.fullType,
   'walking authority original worn slot/ID baseline differs before normalization'..label..' slot='..i)
 end
 return true
end
function A.equipmentProof(s)
 freshEquipment(s.player)
 local actual=array(s.player:getWornItems());assert(#actual==#s.worn,'original actor worn count not restored')
 for i,entry in ipairs(actual)do
  assert(entry:getLocation()==s.worn[i].location and entry:getItem()==s.worn[i].item,'original actor exact worn object/slot not restored')
 end
 return wornDescriptor(s.worn)
end
function A.detach(s)
 assert(not s.detached,'actor already detached');savedProof(s);A.equipmentProof(s)
 -- Record the transition before mutating so preparation failures remain restorable.
 s.detached=true;s.detaching=true
 for _,entry in pairs(s.original)do getCell():addToProcessItemsRemove(entry.item)end
 s.player:clearWornItems()
 for _,item in ipairs(s.roots)do s.root:Remove(item)end
 refreshClothing(s.player);s.detaching=false
 assert(s.root:getItems():isEmpty()and equipmentEmpty(s.player),'original actor load did not detach');savedProof(s)
end
function A.normalizedProof(s)
 savedProof(s);assert(s.detached and s.root:getItems():isEmpty()and equipmentEmpty(s.player),'actor normalization barrier not empty')
 return {rootEmpty=true,equipmentEmpty=true,originalsStashed=true}
end
function A.reserveIds(s,reserved)
 reserved=reserved or {}
 for id in pairs(s.original)do Items.reserve(reserved,id)end
 for _,item in ipairs(s.cohort)do Items.reserve(reserved,item:getID())end
 return reserved
end
function A.seed(s,token,reserved)
 assert(s.detached and s.root:getItems():isEmpty()and not s.seedEntries,'actor root not empty or already seeded');s.token=token
 s.cohort=Items.stage(A.itemType,A.count,A.reserveIds(s,reserved));s.seedEntries={}
 for _,item in ipairs(s.cohort)do
  s.seedEntries[item]={id=item:getID(),state='staged'}
 end
 for _,item in ipairs(s.cohort)do item:getModData()[owner]=token end
 for _,item in ipairs(s.cohort)do
  local entry=s.seedEntries[item];entry.state='inserting'
  local added=s.root:AddItem(item)
  assert(added==item and item:getContainer()==s.root and item:getID()==entry.id,'native actor insertion changed identity/endpoint')
  entry.state='inserted'
  if isServer()then sendAddItemToContainer(s.root,item)end
 end;s.seedComplete=true
 local proof=assert(A.snapshot(s));return {token=token,itemIds=proof.itemIds,itemType=A.itemType,count=A.count,weight=proof.weight,equipment='empty'}
end
function A.bind(s,descriptor)
 assert(s.detached and descriptor.itemType==A.itemType and descriptor.count==A.count and descriptor.equipment=='empty','actor load contract changed')
 s.token=descriptor.token;s.descriptor=descriptor
end
function A.snapshot(s)
 savedProof(s);assert(s.detached and equipmentEmpty(s.player),'deterministic actor equipment changed')
 local items=array(s.root:getItems());if #items~=A.count then return end
 local weight=0
 for _,item in ipairs(items)do
  assert(item:getContainer()==s.root and item:getFullType()==A.itemType and item:getModData()[owner]==s.token,'foreign deterministic actor item')
  assert(not s.original[item:getID()],'actor cohort aliases original');weight=weight+item:getUnequippedWeight()
 end
 local itemIds=ids(items);for i=2,#itemIds do assert(itemIds[i]~=itemIds[i-1],'duplicate actor cohort ID')end
 if s.descriptor then if not same(itemIds,s.descriptor.itemIds)then return end;assert(math.abs(weight-s.descriptor.weight)<.000001,'actor cohort weight differs')end
 if #s.cohort>0 then
  assert(s.seedComplete,'authority actor cohort is incomplete')
  assert(same(itemIds,ids(s.cohort)),'authority actor cohort identity changed')
  local own={};for _,item in ipairs(s.cohort)do own[item]=true end
  for _,item in ipairs(items)do assert(own[item],'authority actor cohort object replaced')end
 end
 return {itemIds=itemIds,itemType=A.itemType,count=A.count,weight=weight,equipment='empty',originalsStashed=true}
end
function A.originalProof(s)return savedProof(s)end
function A.validateRestore(s,authority)
 if s.restored or not s.detached then
  assert(s.player:getInventory()==s.root,'original actor root changed')
  local actual=array(s.root:getItems());assert(#actual==#s.roots,'restored original actor root count changed')
  for i,item in ipairs(actual)do assert(item==s.roots[i],'restored original actor root identity/order changed')end
  A.equipmentProof(s);return savedProof(s)
 end
 freshEquipment(s.player)
 if not s.detaching and not s.restoring then assert(equipmentEmpty(s.player),'unexpected equipment before actor cleanup')end
 local items=array(s.root:getItems());local own,seen={},{}
 if authority then
  for _,item in ipairs(s.cohort)do
   local entry=assert(s.seedEntries and s.seedEntries[item],'missing actor insertion ledger');own[item]=entry
   assert(item:getID()==entry.id and item:getFullType()==A.itemType,'owned actor identity/type changed')
   local endpoint=item:getContainer()
   local removed=s.cleanupJournal and Cleanup.removed(s.cleanupJournal,item)
   assert((removed and endpoint==nil)or(entry.state=='staged'and endpoint==nil)or(entry.state=='inserting'and(endpoint==nil or endpoint==s.root))
    or(entry.state=='inserted'and endpoint==s.root),'owned actor insertion endpoint changed/missing')
  end
 end
 for _,item in ipairs(items)do
  assert(not seen[item:getID()],'duplicate actor identity before cleanup');seen[item:getID()]=true
  local original=s.original[item:getID()]
  assert(((s.detaching or s.restoring)and original and original.item==item and original.container==s.root)or(item:getFullType()==A.itemType and item:getModData()[owner]==s.token
   and(not authority or own[item]and own[item].state~='staged')),'refusing foreign actor cleanup')
 end
 if authority then for item,entry in pairs(own)do
  if item:getContainer()==s.root then assert(seen[entry.id],'owned actor item missing from root')end
 end end
 savedProof(s)
 return items
end
function A.cleanupReceipt(s)
 return s.cleanupJournal and Cleanup.receipt(s.cleanupJournal)or{removedIds={},removalCalls=0,noticeAttempts=0,recoveries={}}
end
function A.restore(s,authority)
 if s.restored or not s.detached then
  A.validateRestore(s,authority);if s.cleanupJournal then Cleanup.run(s.cleanupJournal)end
  return savedProof(s)
 end
 if not s.cleanupJournal then
  local items=A.validateRestore(s,authority);local entries={}
  for _,item in ipairs(items)do if not s.original[item:getID()]then
   entries[#entries+1]={id=item:getID(),item=item,container=s.root,ft=A.itemType}
  end end
  local token,root,player,online=s.token,s.root,s.player,s.player:getOnlineID()
  s.cleanupJournal=Cleanup.new(entries,{containers={root},server=authority and isServer()or false,
   guard=function()
    assert(s.token==token and s.root==root and s.player==player and player:getInventory()==root and player:getOnlineID()==online,'actor cleanup generation/root changed')
    A.validateRestore(s,authority)
   end,
   check=function(entry)assert(entry.item:getModData()[owner]==token,'actor cleanup owner changed')end})
 end
 Cleanup.run(s.cleanupJournal);s.restoring=true
 -- A partly failed detach may leave a suffix in the root. Reinsert every
 -- original locally in its exact initial order; none of these are network packets.
 if not s.restoreOrderReady then
  for _,item in ipairs(s.roots)do
   if item:getContainer()==s.root then s.root:Remove(item)else assert(item:getContainer()==nil,'original root unexpectedly attached')end
  end;s.restoreOrderReady=true
 end
 for index,item in ipairs(s.roots)do
  local current=array(s.root:getItems())
  for i,present in ipairs(current)do assert(present==s.roots[i],'original root restoration order changed')end
  if item:getContainer()==s.root then assert(current[index]==item,'original root restoration prefix changed')
  else
   assert(item:getContainer()==nil and #current==index-1,'original root restoration gap/foreign endpoint')
   assert(s.root:AddItem(item)==item and item:getContainer()==s.root,'original root insertion changed identity')
  end
 end
 for id,entry in pairs(s.original)do
  if s.processed[id]then getCell():addToProcessItems(entry.item)else getCell():addToProcessItemsRemove(entry.item)end
 end
 s.player:clearWornItems()
 for _,entry in ipairs(s.worn)do s.player:getWornItems():setItem(entry.location,entry.item)end
 refreshClothing(s.player)
 assert(same(ids(array(s.root:getItems())),s.rootIds),'original actor roots not restored')
 A.equipmentProof(s)
 s.detached=false;s.detaching=false;s.restoring=false;s.restored=true;return savedProof(s)
end
return A
