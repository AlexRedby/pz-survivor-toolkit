-- Disposable peer driver. Native movement and item transactions own every effect.
require 'TimedActions/WalkToTimedAction'
require 'TimedActions/ISInventoryTransferUtil'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local C={}
local function identity(item,ref)return item and item:getID()==ref.id and item:getFullType()==ref.kind end
local function coords(square)return{x=square:getX(),y=square:getY(),z=square:getZ()}end
local function position(player)return{x=player:getX(),y=player:getY(),z=player:getZ()}end
local function fail(state,reason)state.problem=reason;error('fitness peer '..reason)end
local function queue(player)return ISTimedActionQueue.getTimedActionQueue(player)end
local function idle(state)
 return #state.queue.queue==0 and not state.queue.current and not state.player:hasTimedActions()
  and state.player:getCharacterActions():isEmpty()
end
local function live(state)
 if state.problem then error('fitness peer '..state.problem)end
 if getSpecificPlayer(state.player:getPlayerNum())~=state.player or state.player:isDead()
  or queue(state.player)~=state.queue or (state.queue.toolkitOperationGeneration or 0)~=state.generation then
  fail(state,'actor or queue changed')
 end
end
local function origin(state)
 local ref=state.spec.origin
 return getCell():getGridSquare(ref.x,ref.y,ref.z)
end
local function reachableSquare(here,square)
 return here and square and here:getZ()==square:getZ() and math.abs(here:getX()-square:getX())<=1
  and math.abs(here:getY()-square:getY())<=1 and (here==square or not square:isBlockedTo(here))
end
local function reachable(player,square)return reachableSquare(player:getCurrentSquare(),square)end
local function directRoot(state)
 local inventory=state.player:getInventory();local result,count=nil,0
 for i=0,inventory:getItems():size()-1 do
  local item=inventory:getItems():get(i)
  if item:getID()==state.spec.bag.id then
   count=count+1
   if not identity(item,state.spec.bag)or item:getContainer()~=inventory then fail(state,'root bag identity differs')end
   result=item
  end
 end
 if count>1 then fail(state,'duplicate root bag')end
 return result
end
local function contents(state,bag)
 local rows={};local contentCount,propCount=0,0
 local function scan(container,parent)
  for i=0,container:getItems():size()-1 do
   local item=container:getItems():get(i)
   rows[#rows+1]={id=item:getID(),kind=item:getFullType(),container=parent}
   if item:getID()==state.spec.content.id then
    if not identity(item,state.spec.content)or parent~=state.spec.bag.id then fail(state,'bag content identity differs')end
    contentCount=contentCount+1
   end
   if item:getID()==state.spec.prop.id then propCount=propCount+1 end
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID())end
  end
 end
 scan(bag:getItemContainer(),bag:getID())
 if contentCount~=1 or propCount~=0 then fail(state,'bag content missing, duplicated or borrowed prop retained')end
 table.sort(rows,function(a,b)return a.id<b.id end)
 return rows
end
local function sameRows(a,b)
 if #a~=#b then return false end
 for i,row in ipairs(a)do local other=b[i]
  if row.id~=other.id or row.kind~=other.kind or row.container~=other.container then return false end
 end
 return true
end
local function worldBag(state)
 local square=origin(state)
 if not reachable(state.player,square)then fail(state,'bag origin not reachable')end
 local found
 local objects=square:getWorldObjects()
 for i=0,objects:size()-1 do
  local world=objects:get(i);local item=instanceof(world,'IsoWorldInventoryObject')and world:getItem()
  if item and item:getID()==state.spec.bag.id then
   if found or not identity(item,state.spec.bag)or world:getSquare()~=square or item:getWorldItem()~=world then
    fail(state,'world bag missing identity or unique linkage')
   end
   found=item
  end
 end
 if not found then fail(state,'exact world bag missing')end
 return found
end
local function worldAbsent(state)
 local square=origin(state);if not square then fail(state,'origin unloaded')end
 local objects=square:getWorldObjects()
 for i=0,objects:size()-1 do
  local world=objects:get(i);local item=instanceof(world,'IsoWorldInventoryObject')and world:getItem()
  if item and item:getID()==state.spec.bag.id then return false end
 end
 return true
end
local function pristine(action,kind)
 return action.Type==kind.Type and getmetatable(action)==kind and not action.onStartFunc
  and not action.onCompleteFunc and not action.onCancelFunc and not action.additionalTest and not action.retriggerLastAction
end
local function walkProducer()
 return Proof.matches('media/lua/client/TimedActions/WalkToTimedAction.lua',2037641019,nil,true)
  and Proof.closure(ISWalkToTimedAction.new,'WalkToTimedAction.lua')
end
local function actionValid(state,action,walk)
 local kind=walk and ISWalkToTimedAction or ISInventoryTransferAction
 if not pristine(action,kind)or action.character~=state.player then fail(state,'native action changed')end
 local toolkit=PZSurvivorToolkit;local policy=toolkit and toolkit.ActionQueuePolicy
 if policy~=state.policy or not policy or policy.matchesNative~=state.matchesNative
  or policy.matchesCleanupPickupBinding~=state.matchesCleanupPickupBinding then fail(state,'native policy changed')end
 if walk then
  if not walkProducer()or not policy.matchesNative(action)then
   fail(state,'native walk provenance differs')
  end
 -- Approved BetterContainers methods intentionally exclude ordinary floor
 -- transfers. Its cleanup binding verifier checks the same adopted native
 -- methods for this exact floor->root shape, without claiming edit permission.
 elseif not policy.matchesNative(action)and not policy.matchesCleanupPickupBinding(action)then
  fail(state,'native pickup provenance differs')
 end
 local methods=walk and state.walkMethods or state.pickupMethods
 for name,callback in pairs(methods)do if action[name]~=callback then fail(state,'native callback changed')end end
 if walk then
  if action.location~=state.destination or action.maxTime~=-1 then fail(state,'native walk changed')end
 elseif action.srcContainer~=state.source or action.destContainer~=state.player:getInventory()
  or not identity(action.item,state.spec.bag)then fail(state,'native pickup endpoints changed')end
end
local function methods(action)
 local result={}
 for _,name in ipairs({'start','perform','stop','transferItem'})do if action[name]then result[name]=action[name]end end
 return result
end
function C.approach(player,spec)
 assert(isClient()and not isServer(),'fitness competition requires actual Host client')
 assert(type(spec)=='table'and type(spec.origin)=='table','fitness peer specification absent')
 local frozen={origin={}}
 for _,key in ipairs({'x','y','z'})do
  local value=spec.origin[key];assert(type(value)=='number'and value%1==0,'fitness peer origin differs');frozen.origin[key]=value
 end
 local expected={bag='Base.Bag_Schoolbag',prop='Base.DumbBell',content='Base.BookCarpentry1'};local ids={}
 for name,kind in pairs(expected)do local ref=spec[name]
  assert(type(ref)=='table'and type(ref.id)=='number'and ref.id%1==0 and ref.kind==kind and not ids[ref.id],
   'fitness peer resource identity differs')
  frozen[name]={id=ref.id,kind=ref.kind};ids[ref.id]=true
 end
 local state={player=player,spec=frozen,queue=queue(player),phase='approaching'}
 local toolkit=PZSurvivorToolkit
 state.policy=toolkit and toolkit.ActionQueuePolicy
 assert(state.policy and type(state.policy.matchesNative)=='function'and type(state.policy.matchesCleanupPickupBinding)=='function',
  'fitness peer native policy missing')
 state.matchesNative=state.policy.matchesNative;state.matchesCleanupPickupBinding=state.policy.matchesCleanupPickupBinding
 if toolkit and toolkit.ActionQueue and toolkit.ActionQueue.updateOperationState then toolkit.ActionQueue.updateOperationState(state.queue)end
 state.generation=state.queue.toolkitOperationGeneration or 0;live(state)
 if not idle(state)then fail(state,'approach requires idle queue')end
 state.initialPosition=position(player)
 local square=origin(state);if not square then fail(state,'origin unloaded')end
 if reachable(player,square)then state.phase='ready';return state end
 local best,distance
 for dx=-1,1 do for dy=-1,1 do
  local target=getCell():getGridSquare(frozen.origin.x+dx,frozen.origin.y+dy,frozen.origin.z)
  if target and target:isFree(false)and target:TreatAsSolidFloor()and reachableSquare(target,square)then
   local value=(target:getX()+.5-player:getX())^2+(target:getY()+.5-player:getY())^2
   if not distance or value<distance then best,distance=target,value end
  end
 end end
 if not best then fail(state,'no reachable approach target')end
 if not walkProducer()then fail(state,'native walk provenance differs')end
 state.destination=best;state.walk=ISWalkToTimedAction:new(player,best);state.walkMethods=methods(state.walk)
 actionValid(state,state.walk,true)
 return state
end
function C.pickup(state)
 live(state)
 if state.phase~='ready'or state.pickup or not idle(state)then fail(state,'pickup outside ready idle boundary')end
 -- The caller enters only after its source-bound server grant. Refresh the real
 -- floor projection; never construct a world object or move an item ourselves.
 local loot=getPlayerLoot(state.player:getPlayerNum());if not loot then fail(state,'floor UI missing')end
 loot:refreshBackpacks()
 local item=worldBag(state);local floor=ISInventoryPage.GetFloorContainer(state.player:getPlayerNum())
 if directRoot(state)or not floor or floor:getItemById(state.spec.bag.id)~=item or item:getContainer()~=floor then
  fail(state,'exact floor source differs')
 end
 state.favorite=item:isFavorite();state.contents=contents(state,item);state.source=floor;state.member=item
 state.pickup=ISInventoryTransferUtil.newInventoryTransferAction(state.player,item,floor,state.player:getInventory())
 state.pickupMethods=methods(state.pickup);state.phase='picking'
 actionValid(state,state.pickup,false);ISTimedActionQueue.add(state.pickup)
 return state.pickup
end
function C.begin(state,action,phase)
 if not state or action~=state.walk and action~=state.pickup then return false end
 live(state);local walk=action==state.walk;actionValid(state,action,walk)
 if phase=='start'then
  local key=walk and 'walkStarted'or 'pickupStarted'
  if state[key]then fail(state,'native start repeated')end
  if state.queue.current~=action or state.queue.queue[1]~=action then fail(state,'native start not current')end
  state[key]=true
  if walk then state.walkStart=position(state.player)
  else
   if state.phase~='picking'or worldBag(state)~=state.member or action.item~=state.member then fail(state,'pickup source changed before start')end
   state.pickupStart={callback='ISBaseTimedAction.begin',id=state.spec.bag.id,kind=state.spec.bag.kind,
    source='world',destination='peer-root',origin=coords(origin(state)),position=position(state.player),timestampMS=getTimestampMs()}
  end
  return false
 end
 if phase~='perform'then return false end
 if walk then
  if not state.walkStarted or state.walkPerform then fail(state,'walk perform lacks unique start')end
  if action.result~=BehaviorResult.Succeeded or not reachable(state.player,origin(state))then fail(state,'walk did not reach origin')end
  state.walkPerform=true;return true
 end
 if not state.pickupStarted or state.performCount then fail(state,'pickup perform lacks unique start')end
 if state.phase~='picking'or not action.started then fail(state,'pickup perform not started')end
 local groups=action.queueList
 if type(groups)~='table'or #groups~=1 or type(groups[1].items)~='table'or #groups[1].items~=1
  or groups[1].items[1]~=state.member or groups[1].type~=state.spec.bag.kind then fail(state,'pickup native members differ')end
 local transaction=action.transactionId
 if type(transaction)~='number'or transaction%1~=0 or transaction==0 or not isItemTransactionDone(transaction)
  or isItemTransactionRejected(transaction)then fail(state,'pickup transaction incomplete or rejected')end
 local item=directRoot(state)
 if not item or item:getWorldItem()or not worldAbsent(state)or item:isFavorite()~=state.favorite
  or not sameRows(contents(state,item),state.contents)then fail(state,'pickup transaction effect differs')end
 state.performCount=1;state.performAction=action;state.performTransaction=transaction
 state.performWitness={callback='ISInventoryTransferAction.perform',transactionId=transaction,completed=true,rejected=false,
  id=state.spec.bag.id,kind=state.spec.bag.kind,source='world',destination='peer-root',timestampMS=getTimestampMs()}
 return true
end
function C.finish(state,action,phase,succeeded)
 if not state or action~=state.walk and action~=state.pickup or phase~='perform'then return end
 live(state);local walk=action==state.walk;actionValid(state,action,walk)
 if walk then
  if not state.walkPerform or state.walkFinished or not succeeded then fail(state,'walk callback failed or repeated')end
  state.walkFinished=true;state.walkEnd=position(state.player);return
 end
 if state.performAction~=action or state.performCount~=1 or state.callbackCount or not succeeded
  or action.transactionId~=0 then fail(state,'pickup callback failed, repeated or transaction not retired')end
 local item=directRoot(state)
 if not item or item:getWorldItem()or not worldAbsent(state)or item:isFavorite()~=state.favorite
  or not sameRows(contents(state,item),state.contents)then fail(state,'completed pickup effect differs')end
 state.callbackCount=1;state.finished=true
end
function C.poll(state)
 live(state)
 if state.phase=='approaching'then
  actionValid(state,state.walk,true)
  -- The first native begin is synchronous. Defer enqueue until the caller has
  -- stored this state and can route its Lifecycle.started observation to C.begin.
  if not state.walkQueued then state.walkQueued=true;ISTimedActionQueue.add(state.walk)end
  local now=position(state.player);local before=state.walkStart
  if before and (math.abs(now.x-before.x)+math.abs(now.y-before.y)>.02 or now.z~=before.z)then state.walkMoved=true end
  if idle(state)then
   if not state.walkFinished or not state.walkMoved or not reachable(state.player,origin(state))then fail(state,'approach disappeared without native arrival')end
   state.phase='ready'
  end
 elseif state.phase=='ready'then
  if not idle(state)or not reachable(state.player,origin(state))then fail(state,'ready peer moved or queued foreign work')end
 elseif state.phase=='picking'then
  actionValid(state,state.pickup,false)
  if idle(state)then
   if not state.finished then fail(state,'pickup disappeared without completed callback')end
   state.phase='picked'
  end
 end
 return state.phase
end
function C.result(state)
 if C.poll(state)~='picked'then fail(state,'result before completed pickup')end
 local item=directRoot(state)
 if not item or item:getWorldItem()or not worldAbsent(state)or item:isFavorite()~=state.favorite
  or not sameRows(contents(state,item),state.contents)then fail(state,'settled pickup effect changed')end
 return {phase='picked',id=state.spec.bag.id,kind=state.spec.bag.kind,favorite=state.favorite,contents=contents(state,item),
  origin=coords(origin(state)),position=position(state.player),initialPosition=state.initialPosition,
  walkRequired=state.walk~=nil,walkStarted=state.walkStarted==true,walkMoved=state.walkMoved==true,
  walkFinished=state.walkFinished==true,walkStart=state.walkStart or false,walkEnd=state.walkEnd or false,
  pickupStart=state.pickupStart,transaction=state.performWitness,callbacks=state.callbackCount,queueDrained=true}
end
return C
