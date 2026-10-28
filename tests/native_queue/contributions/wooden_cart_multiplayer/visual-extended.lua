-- Opt-in Host visual evidence. Inputs remain native keys; no pose/equip synthesis.
local M={motionDuration=31000,controlDuration=15800,version=1,padVersion=6,setupDuration=5000,controlLead=3000}
function M.validate(config)
 local o=config.options or {}
 assert(o.cart_visual_extended==true and config.disposable==true and config.kind=='mp' and o.mp_host==true
  and o.cart_variant=='shopping-cart' and o.cart_fast_motion==true and o.cart_actions==true,
  'Extended visual bank requires disposable shopping-cart Host, fast motion and native actions')
 for _,key in ipairs({'cart_wall_exit','cart_injury','cart_inventory_equip','cart_lease_control','cart_lease_lifetimes',
  'cart_lease_inventory','cart_lease_menu','cart_action_invalidation','cart_hotkey_setdown','cart_action_admission',
  'cart_time_alignment','cart_timeline','cart_observer_association'}) do
  assert(not o[key],'Extended visual bank cannot combine with '..key)
 end
end
function M.steps(control)
 if control then
  return {{0,0,0,'control-idle'},{1200,1,0,'control-walk'},{2800,0,0,'control-walk-stop'},
   {4000,3,1,'control-run'},{5600,0,0,'control-run-stop'},{8600,1,2,'control-sprint'},
   {10200,5,2,'control-turn'},{11800,0,0,'control-stop'}}
 end
 return {{0,0,0,'idle'},{2000,1,0,'walk'},{5000,8,0,'turn'},{8000,0,0,'stop'},
  {10000,4,2,'reverse'},{12000,0,0,'stop-back'},{15000,5,0,'short-correction'},
  {16500,0,0,'correction-stop'},{18000,1,1,'run-forward'},{19500,5,1,'run-turn'},
  {21000,0,0,'run-stop'},{23000,1,2,'sprint-forward'},{24500,8,2,'sprint-turn'},
  {26000,0,0,'sprint-stop'}}
end
-- Bare native keys are absolute: Forward is NW, Right is NE, Forward+Left is W.
-- Re-centre once before control; never inherit the cart bank's final position/heading.
function M.controlRoute(area)
 local x,y=area.minX+area.size/2+4,area.minY+area.size/2+4
 -- Conservative speeds 3/6/8 tiles/s exceed measured native walk/run (~2.16/5.1).
 -- Include 1/3/5 tiles native braking and 350ms NW-to-W turn response.
 -- Start four tiles SE of geometric centre to reserve that full braking envelope.
 local d=math.sqrt(.5)
 local bounds={minX=-(3*1.6+1)*d-8*1.6*d-(8*1.6+5),maxX=(6*1.6+3)*d,
  minY=-(3*1.6+1)*d-(6*1.6+3)*d-8*1.6*d-8*.35-5,maxY=0}
 assert(area.size==63 and area.margin==2 and x+bounds.minX>area.minX+area.margin
  and x+bounds.maxX<area.minX+area.size-area.margin and y+bounds.minY>area.minY+area.margin,
  'Native control route envelope exceeds guarded pad')
 return {owner={x=x,y=y,z=area.z},observer={x=x+2,y=y+3,z=area.z},heading=-math.pi*.75,bounds=bounds}
end
function M.positioned(p,target)
 if isClient() then
  local q=assert(ISTimedActionQueue and ISTimedActionQueue.queues,'Client native setup queues missing')[p]
  if q and (#q.queue~=0 or q.current) then return false end
 end
 return math.abs(p:getX()-target.x)+math.abs(p:getY()-target.y)<.2 and math.abs(p:getZ()-target.z)<.25
  and not p:getPrimaryHandItem() and not p:getSecondaryHandItem() and p:getCharacterActions():isEmpty() and not p:hasPath()
end
local targets={['short-correction']={-.16,350},['run-turn']={-.35,1000},['sprint-turn']={.35,1000}}
local function delta(a,b) return math.atan2(math.sin(a-b),math.cos(a-b)) end
-- Snapshot accepted heading once, then release steering permanently at the small target.
function M.drive(step,state,heading,elapsed)
 local target=targets[step[4]]
 if not target then return step[2] end
 local s=state[step[4]]
 if not s then s={heading=heading};state[step[4]]=s end
 local yaw=delta(heading,s.heading)
 if s.released or yaw*(target[1]<0 and -1 or 1)>=math.abs(target[1]) or elapsed-step[1]>=target[2] then
  s.released=true;return 1
 end
 return step[2]
end
function M.emit(kind,row,observedWall)
 -- Correlated epoch/elapsed/wall values share the caller's observed tick.
 -- Command-only events without derived timing take their own clock sample.
 row.version=M.version;row.wall=observedWall or getTimestampMs();print('[CART_MP_VISUAL] '..kind..' '..require('CartMPJSON').encode(row))
end
function M.ground(p,spec)
 assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem(),'No-cart control requires empty hands')
 local items=p:getInventory():getItems()
 for i=0,items:size()-1 do assert(items:get(i):getID()~=spec.id,'Control cart unexpectedly in actor inventory') end
 local pose=assert(spec.worldPose,'Exact released world pose missing')
 local square=assert(getCell():getGridSquare(math.floor(pose.x),math.floor(pose.y),math.floor(pose.z)),'Control cart square missing')
 local found,count=nil,0
 for x=math.floor(pose.x)-4,math.floor(pose.x)+4 do for y=math.floor(pose.y)-4,math.floor(pose.y)+4 do
  local candidate=getCell():getGridSquare(x,y,math.floor(pose.z))
  if candidate then local objects=candidate:getWorldObjects()
   for i=0,objects:size()-1 do local item=objects:get(i):getItem()
    if item and item:getID()==spec.id then found=item;count=count+1 end
   end
  end
 end end
 assert(found and count==1 and found:getFullType()=='SaucedCarts.ShoppingCart','Exact released control cart missing/duplicated')
 local world=found:getWorldItem();local cargo=found:getInventory():getItems()
 assert(world and world:getItem()==found and world:getSquare()==square and cargo:size()==1
  and cargo:get(0):getID()==spec.cargoID and cargo:get(0):getFullType()=='Base.Log'
  and math.abs(cargo:get(0):getActualWeight()-spec.cargoWeight)<.001,'Control cart/cargo identity changed')
 assert(math.abs(world:getWorldPosX()-pose.x)<=.002 and math.abs(world:getWorldPosY()-pose.y)<=.002
  and math.abs(world:getWorldPosZ()-pose.z)<=.002
  and math.abs(delta(math.rad(found:getWorldZRotation()),math.rad(pose.rotation)))<=math.rad(.01),'Control cart placement changed')
 local luaActions
 if isClient() then
  local queues=assert(ISTimedActionQueue and ISTimedActionQueue.queues,'Client Lua timed-action queues missing')
  local q=queues[p];luaActions=q and #q.queue or 0
  assert(luaActions==0 and (not q or not q.current),'No-cart control has Lua action')
 end
 -- Remote network interpolation also owns path2 (IsoPlayer.updateRemotePlayer);
 -- hasPath() is not an authoritative queued-approach signal on that replica.
 local remote=isClient() and not p:isLocalPlayer()
 assert(p:getCharacterActions():isEmpty() and (remote or not p:hasPath()),'No-cart control has native action/path')
 return {id=spec.id,cargoID=spec.cargoID,cargoWeight=spec.cargoWeight,worldPose=pose,
  primaryID=-1,secondaryID=-1,worldCount=1,cargoPreserved=true,luaActions=luaActions,
  queueScope=isClient() and 'client-lua-and-native' or 'native-server',nativeActions=0,hasPath=p:hasPath(),
  pathScope=remote and 'remote-network' or 'authoritative-approach'},world
end
local owned={}
function M.ownFloor(square,object)
 assert(isServer() and not isClient() and cartMPPadHost() and square:getFloor()==object and not owned[object],
  'Exact fresh Host floor ownership required')
 owned[object]=square
end
function M.cleanup(spec,area)
 assert(isServer() and not isClient() and cartMPPadHost(),'Host cleanup authority required')
 local pose=spec.worldPose;local square=assert(getCell():getGridSquare(math.floor(pose.x),math.floor(pose.y),math.floor(pose.z)))
 local world
 for i=0,square:getWorldObjects():size()-1 do local candidate=square:getWorldObjects():get(i)
  if candidate:getItem():getID()==spec.id then assert(not world,'Duplicate cleanup cart');world=candidate end
 end
 assert(world and world:getItem():getInventory():getItems():size()==1
  and world:getItem():getInventory():getItems():get(0):getID()==spec.cargoID,'Owned cleanup cart/cargo changed')
 local plan={}
 for object,sq in pairs(owned) do
  local objects=sq:getObjects();local floorSeen=false
  for i=0,objects:size()-1 do
   local value=objects:get(i);assert(value==object or sq==square and value==world,'Foreign object on owned floor')
   floorSeen=floorSeen or value==object
  end
  assert(floorSeen and sq:getFloor()==object and object:getSpriteName()==area.floorSprite
   and sq:getSpecialObjects():size()==0 and sq:getStaticMovingObjects():size()==0 and sq:getMovingObjects():size()==0
   and sq:getWorldObjects():size()==(sq==square and 1 or 0),'Owned floor changed or occupied before cleanup')
  plan[#plan+1]={square=sq,object=object}
 end
 assert(#plan==area.size*area.size,'Owned floor count differs')
 assert(square:transmitRemoveItemFromSquare(world,false)>=0,'Native owned cart removal failed')
 for _,entry in ipairs(plan) do
  assert(entry.square:transmitRemoveItemFromSquare(entry.object,false)>=0,'Native owned floor removal failed')
  assert(entry.square:getFloor()~=entry.object,'Owned floor survived cleanup');owned[entry.object]=nil
 end
 return #plan
end
function M.cleanupReady(area)
 for x=area.minX,area.minX+area.size-1 do for y=area.minY,area.minY+area.size-1 do
  local square=getCell():getGridSquare(x,y,area.z)
  if not square or square:getFloor() or square:getWorldObjects():size()>0 then return false end
 end end
 return true
end
return M
