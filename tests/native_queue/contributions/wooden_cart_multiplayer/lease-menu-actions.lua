-- Disposable owner input driver; receipts prove actions, the caller verifies cart effects.
local config=require 'QueueTestSelection'
assert(config.disposable==true and config.options.cart_lease_lifetimes==true
 and config.options.cart_lease_menu==true,'Explicit disposable lease menu bank required')
require 'SaucedCarts/ContextMenu'
require 'ISUI/ISContextMenu'
require 'ISUI/ISInventoryPaneContextMenu'
require 'ISUI/ISWorldObjectContextMenu'
require 'TimedActions/ISTimedActionQueue'
local Ack=require 'PZSurvivorToolkit/ActionQueueAcknowledgements'
local M={}
local ids,nextID=setmetatable({},{__mode='k'}),0
local function identity(value)
 assert(value~=nil,'Exact menu source identity missing')
 if not ids[value] then nextID=nextID+1;ids[value]=nextID end
 return ids[value]
end
local function empty(p,q) return #q.queue==0 and p:getCharacterActions():isEmpty() and not p:hasPath() end
local function emit(s,event)
 local r={kind=s.inventory and 'inventory' or s.pickup and 'pickup' or 'release',phase=s.phase,cart=s.id,actionType=s.action.Type,
  localActionEpoch=identity(s.action),localSourceEpoch=identity(s.source),source=tostring(s.source),
  operation=identity(s.operation),queuedSource=s.queuedSource,generation=s.generation}
 if s.native then r.localNativeEpoch=identity(s.native) end
 if s.inventory then
  r.duration=s.action:getDuration();r.luaMaxTime=s.action.maxTime;r.sourceType=s.action.sourceType
  if s.action.action then r.nativeMaxTime=s.action.action:getTime();r.localNativeEpoch=identity(s.action.action) end
 end
 if s.receipt then
  r.token=s.receipt.token;r.transaction=s.receipt.transaction;r.generation=s.receipt.generation
  r.state=Ack.observe(s.action,s.receipt);r.sealed=true
 end
 s.emit(event,r)
end
local function find(context,predicate)
 local selected
 for _,option in ipairs(context.options) do
  local candidate=predicate(option) and option or nil
  if option.subOption then candidate=find(context:getSubMenu(option.subOption),predicate) or candidate end
  if candidate then assert(not selected,'Ambiguous native menu option');selected=candidate end
 end
 return selected
end
local function matches(s,action)
 if s.inventory then return action.character==s.player and getmetatable(action)==ISCartEquipAction
  and action.Type=='ISCartEquipAction' and action.cartId==s.id and action.sourceType=='inventory' end
 return action.character==s.player and action.Type==(s.pickup and 'ToolkitWoodCartPickup' or 'ToolkitWoodCartSetdown')
  and (s.pickup and action.itemId==s.id or not s.pickup and action.item==s.item)
end
local function inventoryDuration(action)
 assert(action:getDuration()==30 and type(action.maxTime)=='number' and action.maxTime==action.maxTime
  and math.abs(action.maxTime)<math.huge and (not action.action or action.action:getTime()==30),'Native inventory equip duration changed')
end
local function bind(s,action)
 assert(matches(s,action) and action.toolkitQueueOperation==s.operation,'Exact queued native menu action changed')
 if s.pickup then assert(action:findWorldItem()==s.world,'Queued pickup world source changed') end
 if s.inventory then
  assert(action:findCart()==s.item,'Queued inventory cart source changed');inventoryDuration(action);s.queuedNative=action.action
 end
 s.action=action;emit(s,'queued')
end
local function enqueue(player,item,pickup,phase,callback,inventory)
 assert(player==getPlayer() and player:getUsername()=='client1','Exact local menu owner required')
 assert(type(pickup)=='boolean' and type(callback)=='function' and phase~=nil,'Menu operation arguments missing')
 assert(item and item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood','Exact wooden menu cart required')
 assert(not player:isTimedActionInstant(),'Native menu action duration required')
 local q=ISTimedActionQueue.getTimedActionQueue(player)
 assert(empty(player,q),'Menu operation requires empty native/Lua queues and path')
 local s={player=player,item=item,id=item:getID(),pickup=pickup,inventory=inventory,phase=phase,emit=callback,queue=q,
  source=assert(cartLeaseCurrent(),'Exact queued menu connection missing')}
 local context,option
 if inventory then
  assert(not player:getPrimaryHandItem() and not player:getSecondaryHandItem(),'Inventory equip requires released hands')
  local owned=player:getInventory()
  assert(not item:getWorldItem() and item:getContainer()==owned and owned:contains(item) and owned:getItemById(s.id)==item,'Exact owned inventory cart required')
  local items={item};context=assert(ISInventoryPaneContextMenu.createMenu(player:getPlayerNum(),true,items,50,50),'Inventory menu missing')
  option=find(context,function(o)
   if type(o.onSelect)~='function' or type(getFilenameOfClosure)~='function' then return false end
   local ok,path=pcall(getFilenameOfClosure,o.onSelect)
   return ok and type(path)=='string' and path:gsub('\\','/'):sub(-28)=='/SaucedCarts/ContextMenu.lua'
    and (o.name==getText('UI_SaucedCarts_PushCart') or o.name=='Push Cart')
    and o.target==items and o.param1==player:getPlayerNum() and o.param2==item
  end)
 elseif pickup then
  assert(not player:getPrimaryHandItem() and not player:getSecondaryHandItem(),'Pickup requires released hands')
  s.world=assert(item:getWorldItem(),'Exact ground menu cart missing')
  assert(s.world:getItem()==item,'Ground menu cart replaced')
  local objects={s.world};context=ISContextMenu.get(player:getPlayerNum(),50,50)
  triggerEvent('OnFillWorldObjectContextMenu',player:getPlayerNum(),context,objects,false)
  option=find(context,function(o) return (o.name==getText('UI_SaucedCarts_PushCart') or o.name=='Push Cart')
   and o.target==objects and o.param1==player:getPlayerNum() and o.param2==s.world end)
 else
  assert(player:getPrimaryHandItem()==item and player:getSecondaryHandItem()==item and not item:getWorldItem(),
   'Release requires exact held menu cart')
  -- Sauced removes inventory Unequip. Vanilla's world DropNamedItem retains onUnEquip.
  local square=assert(player:getCurrentSquare(),'Native owner menu square missing')
  local floor=assert(square:getFloor(),'Native owner menu floor missing')
  assert(floor:getSquare()==square,'Native owner menu floor source changed')
  context=assert(ISWorldObjectContextMenu.createMenu(player:getPlayerNum(),{floor},50,50,false),'Native world menu missing')
  option=find(context,function(o) return o.onSelect==ISInventoryPaneContextMenu.onUnEquip
   and type(o.target)=='table' and #o.target==1 and o.target[1]==item and o.param1==player:getPlayerNum() end)
 end
 assert(option and type(option.onSelect)=='function' and not option.notAvailable,'Native cart menu option unavailable')
 context:hideAndChildren()
 assert(PZSurvivorToolkit.ActionQueueOperations,'Native queue operation scope missing').run(function()
  option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,
   option.param6,option.param7,option.param8,option.param9,option.param10)
 end)
 assert(getPlayer()==player and cartLeaseCurrent()==s.source,'Native menu callback changed owner/source')
 assert(ISTimedActionQueue.queues[player]==q and #q.queue==1,'Native menu callback must queue exactly one action')
 local action=q.queue[1]
 s.operation=action.toolkitQueueOperation;s.generation=q.toolkitOperationGeneration or 0
 assert(type(s.operation)=='table' and not s.operation.toolkitCancelled,'Exact native menu operation missing')
 s.queuedSource=action.Type
 if matches(s,action) then bind(s,action)
 else
  assert(pickup and action.character==player and action.Type=='ISWalkToTimedActionF'
   and action.toolkitWoodCartItem==item,'Unexpected native menu approach action')
  s.walk=action
 end
 return s
end
function M.enqueue(player,item,pickup,phase,callback) return enqueue(player,item,pickup,phase,callback,false) end
function M.inventory(player,item,phase,callback)
 assert(config.options.cart_lease_inventory==true,'Explicit inventory lifetime input required')
 return enqueue(player,item,false,phase,callback,true)
end
function M.poll(s)
 local p,q=s.player,s.queue
 assert(getPlayer()==p and p:getUsername()=='client1' and cartLeaseCurrent()==s.source
  and ISTimedActionQueue.queues[p]==q and (q.toolkitOperationGeneration or 0)==s.generation
  and not s.operation.toolkitCancelled,'Native menu owner/source/operation changed')
 assert(s.item:getID()==s.id and s.item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood','Native menu cart identity changed')
 if s.walk then
  assert(s.walk.toolkitQueueOperation==s.operation and s.walk.character==p
   and s.walk.toolkitWoodCartItem==s.item,'Deferred native menu source changed')
  local selected
  for _,action in ipairs(q.queue) do
   assert(action==s.walk or matches(s,action),'Unexpected deferred native menu action')
   if action~=s.walk then assert(not selected,'Duplicate native menu continuation');selected=action end
  end
  if not selected then assert(not empty(p,q),'Deferred native menu pickup disappeared');return false end
  assert(selected.toolkitQueueOperation==s.operation,'Exact queued native menu action changed')
  if q.queue[1]==s.walk then return false end
  bind(s,selected);s.walk=nil
 end
 local action=s.action
 assert(matches(s,action) and action.toolkitQueueOperation==s.operation,'Native menu action binding changed')
 if s.inventory then
  inventoryDuration(action);s.queuedNative=s.queuedNative or action.action
  assert(not s.queuedNative or action.action==s.queuedNative,'Native inventory action identity changed')
 end
 for _,queued in ipairs(q.queue) do assert(queued==action,'Native menu action replaced or queue expanded') end
 if not s.receipt then
  if q.current==action and action.action then
   local receipt=Ack.capture(action)
   if receipt then
    assert(receipt.generation==s.generation and Ack.observe(action,receipt)=='started','Exact native menu start missing')
    s.receipt=receipt;s.native=action.action;emit(s,'start')
   end
  end
  assert(not empty(p,q),'Native menu action ended without captured start');return false
 end
 assert(action.action==s.native,'Native menu action identity changed')
 local terminal=assert(Ack.observe(action,s.receipt),'Native menu receipt revoked')
 assert(terminal=='started' or terminal=='completed','Native menu action did not complete')
 if terminal~='completed' or not empty(p,q) then return false end
 if not s.done then s.done=true;emit(s,'terminal') end
 return true
end
return M
