-- Read-only endpoints for the explicitly selected initial inventory entry.
local config=require 'QueueTestSelection'
assert(config.disposable==true and config.options.cart_lease_inventory==true,'Explicit inventory entry required')
local J=require 'CartMPJSON'
local M={}
function M.loaded(p)
 for x=math.floor(p:getX())-4,math.floor(p:getX())+4 do for y=math.floor(p:getY())-4,math.floor(p:getY())+4 do
  if not getCell():getGridSquare(x,y,p:getZ()) then return false end
 end end
 return true
end
function M.emit(actor,event,p,item,source)
 assert(actor=='server' or actor=='client1' or actor=='client2','Unknown inventory entry role')
 assert(event=='unheld' or event=='held','Unknown inventory entry endpoint')
 assert(p and p:getUsername()=='client1' and item and item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood','Exact inventory entry owner/cart required')
 local a,b=p:getPrimaryHandItem(),p:getSecondaryHandItem()
 assert(event=='unheld' and not a and not b or event=='held' and a==item and b==item,'Inventory entry hand endpoint differs')
 local contents=item:getInventory():getItems();assert(contents:size()==1,'Inventory entry cargo count differs')
 local cargo=contents:get(0);local worlds=0
 for x=math.floor(p:getX())-4,math.floor(p:getX())+4 do for y=math.floor(p:getY())-4,math.floor(p:getY())+4 do
  local square=assert(getCell():getGridSquare(x,y,p:getZ()),'Inventory entry world area unloaded')
  local objects=square:getWorldObjects()
  for i=0,objects:size()-1 do local v=objects:get(i):getItem();if v and v:getID()==item:getID() then worlds=worlds+1 end end
 end end
 local row={actor=actor,event=event,phase=0,owner=p:getOnlineID(),cart=item:getID(),cargoID=cargo:getID(),cargoWeight=cargo:getActualWeight(),
  primaryID=a and a:getID() or -1,secondaryID=b and b:getID() or -1,handSameItem=a~=nil and a==b,
  worldAttached=item:getWorldItem()~=nil,worldCount=worlds,nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),
  inventoryScope=actor=='client2' and 'remote-hand-snapshot' or 'owner-inventory',
  queueScope=actor=='server' and 'native-server-only' or actor=='client1' and 'owner-local' or 'remote-native-only',
  source=tostring(assert(source,'Inventory entry native source missing')),guarded=actor=='server',wall=getTimestampMs()}
 if actor~='client2' then
  local inv=p:getInventory():getItems();local count=0
  for i=0,inv:size()-1 do if inv:get(i):getID()==item:getID() then count=count+1 end end
  row.inventoryCount=count;assert(count==1,'Inventory entry cart duplicated or missing')
 end
 if actor=='client1' then row.luaActions=#ISTimedActionQueue.getTimedActionQueue(p).queue;assert(row.luaActions==0,'Inventory entry Lua queue pending') end
 assert(row.nativeActions==0 and not row.hasPath and not row.worldAttached and worlds==0,'Inventory entry native endpoint unsettled')
 print('[CART_LEASE_INVENTORY] '..J.encode(row));return row
end
return M
