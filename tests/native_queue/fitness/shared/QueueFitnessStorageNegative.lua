-- Disposable negative-case witnesses. Native producers alone move players/items.
local N={}
function N.matches(id)return id=='storage-walk-away'or id=='storage-peer-pickup'end
function N.competition(id)return id=='storage-peer-pickup'end
local function position(player)
 return player and {x=player:getX(),y=player:getY(),z=player:getZ(),onlineID=(isClient()or isServer())and player:getOnlineID()or -1}or false
end
N.position=position
local function ref(item)return {id=item:getID(),kind=item:getFullType(),favorite=item:isFavorite()}end
local function same(item,wanted)return item and item:getID()==wanted.id and item:getFullType()==wanted.kind end
local function originSquare(spec)return getCell():getGridSquare(spec.origin.x,spec.origin.y,spec.origin.z)end
function N.prepare(state)
 local player,items=state.player,state.items
 items.bag:setFavorite(true);items.dumbbell:setFavorite(true)
 local sq=assert(player:getCurrentSquare());local origin={x=sq:getX(),y=sq:getY(),z=sq:getZ()}
 state.ids.negativeStorage={origin=origin,bag=ref(items.bag),prop=ref(items.dumbbell),content=ref(items.front)}
end
function N.ready(state)
 local p,items=state.player,state.items;local spec=state.ids.negativeStorage
 return spec and same(items.bag,spec.bag)and items.bag:getContainer()==p:getInventory()and items.bag:isFavorite()
  and items.front:getContainer()==items.bag:getItemContainer()and items.dumbbell:getContainer()==items.bag:getItemContainer()
  and items.dumbbell:isFavorite()and p:getWornItem(items.bag:canBeEquipped())==items.bag
  and p:getPrimaryHandItem()==items.hammer and p:getSecondaryHandItem()==items.screwdriver
end
function N.snapshot(player,spec,peer,role)
 role=role or 'client1'
 local wanted={[spec.bag.id]=true,[spec.prop.id]=true,[spec.content.id]=true};local rows={}
 local function scan(container,parent,owner,all)
  local entries=container:getItems()
  for i=0,entries:size()-1 do
   local item=entries:get(i)
   if all or wanted[item:getID()]then rows[#rows+1]={id=item:getID(),kind=item:getFullType(),container=parent,owner=owner,favorite=item:isFavorite()}end
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID(),owner,all or item:getID()==spec.bag.id)end
  end
 end
 scan(player:getInventory(),role..'-root',role,false)
 if peer then scan(peer:getInventory(),'client2-root','client2',false)end
 local squares,seen={},{}
 local function add(sq)if sq and not seen[sq]then seen[sq]=true;squares[#squares+1]=sq end end
 add(originSquare(spec));add(player:getCurrentSquare());if peer then add(peer:getCurrentSquare())end
 local bags={}
 for _,sq in ipairs(squares)do local objects=sq:getWorldObjects()
  for i=0,objects:size()-1 do local world=objects:get(i);local item=instanceof(world,'IsoWorldInventoryObject')and world:getItem()
   if item and wanted[item:getID()]then
    local row={id=item:getID(),kind=item:getFullType(),container='world',owner='world',favorite=item:isFavorite(),
     world={x=sq:getX(),y=sq:getY(),z=sq:getZ(),linked=world:getSquare()==sq and item:getWorldItem()==world}}
    rows[#rows+1]=row
    if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID(),'world',item:getID()==spec.bag.id)end
   end
  end
 end
 table.sort(rows,function(a,b)if a.id~=b.id then return a.id<b.id end;return a.owner<b.owner end)
 local worn={};for i=0,player:getWornItems():size()-1 do local entry=player:getWornItems():get(i)
  worn[#worn+1]={location=tostring(entry:getLocation()),id=entry:getItem():getID()}
 end;table.sort(worn,function(a,b)return a.location<b.location end)
 return {resources=rows,position=position(player),peerPosition=position(peer),primary=player:getPrimaryHandItem()and player:getPrimaryHandItem():getID()or false,
  secondary=player:getSecondaryHandItem()and player:getSecondaryHandItem():getID()or false,worn=worn}
end
function N.endpoint(snapshot,id)
 local found
 for _,entry in ipairs(snapshot.resources)do if entry.id==id then if found then return false end;found=entry end end
 return found
end
local function target(player,spec)
 local origin=assert(originSquare(spec),'exercise origin unloaded')
 for _,direction in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
  local previous=origin;local candidate
  for distance=1,4 do
   local sq=getCell():getGridSquare(spec.origin.x+direction[1]*distance,spec.origin.y+direction[2]*distance,spec.origin.z)
   if not sq or not sq:TreatAsSolidFloor()or not sq:isFree(false)or sq:isBlockedTo(previous)then candidate=nil;break end
   candidate=sq;previous=sq
  end
  if candidate then return candidate end
 end
 error('no native unobstructed four-tile walk from exercise origin')
end
function N.walk(state,tail)
 require 'BuildingObjects/ISWalkToCursor'
 local p,spec=state.player,state.ids.negativeStorage;local q=ISTimedActionQueue.getTimedActionQueue(p)
 local pages,total=p:getAlreadyReadPages(state.items.tail:getFullType()),state.items.tail:getNumberOfPages()
 assert(pages<total and q:indexOf(tail)~=-1,'original independent reader already started or finished')
 local destination=target(p,spec);local before=N.position(p)
 local proof=require 'PZSurvivorToolkit/SourceProof'
 assert(proof.matches('media/lua/server/BuildingObjects/ISWalkToCursor.lua',2852789671,nil,true)
  and proof.matches('media/lua/client/TimedActions/WalkToTimedAction.lua',2037641019,nil,true)
  and proof.closure(ISWalkToCursor.new,'ISWalkToCursor.lua')and proof.closure(ISWalkToCursor.create,'ISWalkToCursor.lua')
  and proof.closure(ISWalkToCursor.locateTargetSquare,'ISWalkToCursor.lua')and proof.closure(ISWalkToTimedAction.new,'WalkToTimedAction.lua'),'native walk producer changed')
 state.negativeWalk={destination=destination,witness={producer='ISWalkToCursor.create',before=before,
  destination={x=destination:getX(),y=destination:getY(),z=destination:getZ()},maxTime=-1,
  nativeStarted=false,maxDisplacement=0,tailId=state.ids.items.tail,tailPages=pages,tailTotal=total,requestedAt=getTimestampMs()}}
 local cursor=ISWalkToCursor:new('','',p)
 cursor:create(destination:getX(),destination:getY(),destination:getZ(),false,nil)
 local walk
 for _,action in ipairs(q.queue)do if action.Type=='ISWalkToTimedAction'and getmetatable(action)==ISWalkToTimedAction
  and action.character==p and action.location==destination then assert(not walk,'duplicate native walk');walk=action end end
 assert(walk and walk.maxTime==-1 and PZSurvivorToolkit.ActionQueuePolicy.matchesNative(walk),'native movement cursor failed to enqueue its walk')
 assert(not state.negativeWalk.action or state.negativeWalk.action==walk,'native walk admission changed')
 state.negativeWalk.action=walk;state.negativeWalk.witness.oldTailCancelled=q:indexOf(tail)==-1
 return state.negativeWalk.witness
end
function N.begin(state,action,phase)
 local value=state and state.negativeWalk
 if not value or not action or action.character~=state.player or action.Type~='ISWalkToTimedAction' then return false end
 if phase=='start' and not value.action and action.location==value.destination then value.action=action;value.witness.nativeBegin=true;return false end
 if action~=value.action or phase~='perform' then return false end
 assert(action.result==BehaviorResult.Succeeded and value.witness.nativeStarted and not value.witness.nativePerformCalls,'native walk did not perform once successfully')
 value.witness.nativePerformCalls=1;return true
end
function N.finish(state,action,phase,succeeded)
 local value=state and state.negativeWalk
 if value and action==value.action and phase=='perform' then
  assert(succeeded and value.witness.nativePerformCalls==1 and not value.witness.nativeCompleted,'native walk callback failed or repeated')
  value.witness.nativeCompleted=true;value.witness.nativeResult='Succeeded';value.witness.completedAt=getTimestampMs()
 end
end
function N.observeWalk(state)
 local value=state.negativeWalk;if not value then return end
 local p,action,w=state.player,value.action,value.witness
 if action.action and action:isStarted()then w.nativeStarted=true end
 local now=position(p);local dx,dy=now.x-w.before.x,now.y-w.before.y
 w.maxDisplacement=math.max(w.maxDisplacement,math.sqrt(dx*dx+dy*dy));w.after=now
 assert(action.maxTime==-1,'native walk duration changed')
 return w
end
return N
