-- Optional test workload and coarse wall-clock observation, never an edit owner.
local C={instances=128,warmup=2,calls=16,rounds=2}
local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
local function integer(value)return finite(value)and value%1==0 end
local function fields(item,bag)
 return{id=item:getID(),type=item:getFullType(),class=getClassSimpleName(item),count=item:getCount(),uses=item:getCurrentUses(),
  actualWeight=item:getActualWeight(),capacityWeight=item:getUnequippedWeight(),ownerBag=bag:getID()}
end
function C.seed(s)
 assert(s.ids.case=='worn-bag'and s.bag and s.source==s.bag:getItemContainer(),'profile payload needs owned bag')
 local items=s.source:getItems();local before=items:size();local rows,seen={},{}
 for _=1,C.instances do
  -- Native AddItem(String) creates and appends exactly one factory instance;
  -- its script Count is metadata, not an AddItems quantity expansion.
  local item=assert(s.source:AddItem('Base.Nails'));local row=fields(item,s.bag)
  assert(row.type=='Base.Nails'and row.class=='ComboItem'and row.count==5 and integer(row.uses)and row.uses>0
   and integer(row.id)and not seen[row.id]and item:getContainer()==s.source and math.abs(row.actualWeight-.05)<.000001
   and row.capacityWeight==row.actualWeight,'native Nails instance/weight differs')
  seen[row.id]=true;rows[#rows+1]=row
 end
 assert(items:size()==before+C.instances,'native Nails quantity expanded or merged')
 table.sort(rows,function(a,b)return a.id<b.id end)
 assert(s.source:getCapacityWeight()<=s.source:getEffectiveCapacity(s.player),'native profile payload exceeds bag capacity')
 s.ids.capacityProfile={instances=C.instances,bag=s.bag:getID(),items=rows}
end
local function scan(root,ids)
 local found,seen={},{ }
 local function walk(container)
  assert(not seen[container],'profile owner-container alias/cycle');seen[container]=true
  local values=container:getItems()
  for index=0,values:size()-1 do local item=values:get(index);local id=item:getID()
   if ids[id]then found[id]=found[id]or{};found[id][#found[id]+1]={item=item,owner=container}end
   if instanceof(item,'InventoryContainer')then walk(item:getItemContainer())end
  end
 end
 walk(root);return found
end
function C.snapshot(s)
 local spec=assert(s.ids.capacityProfile);local root=s.player:getInventory();local bag=s.bag;local source=s.source
 assert(root:getItemById(spec.bag)==bag and bag:getContainer()==root and bag:getFullType()=='Base.Bag_Military'
  and bag:getItemContainer()==source and source:getContainingItem()==bag,'profile canonical bag owner changed')
 assert(spec.instances==C.instances and #spec.items==C.instances,'profile manifest size changed')
 local wanted={[spec.bag]=true};for _,row in ipairs(spec.items)do assert(not wanted[row.id],'profile manifest duplicate ID');wanted[row.id]=row end
 local found=scan(root,wanted);assert(found[spec.bag]and #found[spec.bag]==1 and found[spec.bag][1].item==bag and found[spec.bag][1].owner==root,'profile bag duplicate/alias')
 local rows,total,uses={},0,0
 for _,expected in ipairs(spec.items)do
  local entries=found[expected.id];assert(entries and #entries==1,'missing/duplicate profile instance')
  local item,owner=entries[1].item,entries[1].owner;local row=fields(item,bag)
  assert(owner==source and item:getContainer()==source,'profile item left exact source')
  for key,value in pairs(expected)do assert(row[key]==value,'profile native instance fields changed '..key)end
  rows[#rows+1]=row;total=total+row.actualWeight;uses=uses+row.uses
 end
 local sourceItems=source:getItems();local count=0
 for index=0,sourceItems:size()-1 do local item=sourceItems:get(index)
  if item:getFullType()=='Base.Nails'then assert(wanted[item:getID()],'unexpected profile Nails ID');count=count+1 end
 end
 assert(count==C.instances and #rows==C.instances,'profile source instance count differs')
 return{bag=spec.bag,bagType=bag:getFullType(),bagRoot=true,bagWorn=s.player:getWornItems():contains(bag),instances=#rows,uses=uses,
  totalWeight=total,items=rows,sourceInstances=count,actorInstances=#rows,rootInstances=0,
  sourceWeight=source:getCapacityWeight(),bagCapacity=source:getCapacity(),effectiveCapacity=source:getEffectiveCapacity(s.player),rootWeight=root:getCapacityWeight()}
end
function C.cleanupProof(s)
 local wanted={[s.ids.capacityProfile.bag]=true};local ids={}
 for _,row in ipairs(s.ids.capacityProfile.items)do wanted[row.id]=true;ids[#ids+1]=row.id end
 local found=scan(s.player:getInventory(),wanted)
 for id in pairs(wanted)do assert(not found[id],'profile cleanup ID remains reachable from actor root')end
 assert(not s.player:getWornItems():getItemById(s.ids.capacityProfile.bag)and s.bag:getWorldItem()==nil,'profile cleanup bag still worn/in world')
 -- Detached Java objects may remain referenced by this read-only receipt state.
 return{case=s.ids.case,bag=s.ids.capacityProfile.bag,ids=ids,actorInstances=0,bagReachable=false,bagWorn=false,bagWorld=false,
  scope='removed from actor inventory; no object-destruction claim'}
end
function C.measure(s,queue,snapshot)
 local JSON=require 'QueueHealthEvents';local Proof=require 'PZSurvivorToolkit/SourceProof'
 local owner=assert(PZSurvivorToolkit.ActionQueueWeights);local capacity=assert(owner.capacity);local player=s.player;local root=player:getInventory()
 assert(player==getPlayer()and queue.character==player and not queue.current and #queue.queue==0 and not player:hasTimedActions(),'capacity profile needs idle owned player')
 assert(Proof.closure(capacity,'ActionQueueWeights.lua'),'capacity profile helper source differs')
 local before=snapshot();assert(before.capacityPayload.bagWorn,'profile bag must be natively worn/canonical')
 local nativeWeight=root:getCapacityWeight();assert(finite(nativeWeight)and nativeWeight>=0,'native profile root weight unavailable')
 local function call(path)
  assert(owner==PZSurvivorToolkit.ActionQueueWeights and owner.capacity==capacity,'capacity helper pointer changed')
  local upper,lower;if path=='legacy'then upper,lower=capacity(root,player,nil)else upper,lower=capacity(root,player,0)end
  assert(finite(upper)and finite(lower)and upper>=0 and lower>=0 and upper>=nativeWeight and lower<=nativeWeight,'profile capacity not a finite conservative bound')
  return upper,lower
 end
 for _=1,C.warmup do call('legacy');call('qualified')end
 local samples={};local groupTime=0;local began=getTimestampMs()
 for round=1,C.rounds do
  for _,path in ipairs(round%2==1 and{'legacy','qualified'}or{'qualified','legacy'})do
   local started=getTimestampMs();local minUpper,maxUpper,minLower,maxLower
   for _=1,C.calls do local upper,lower=call(path)
    minUpper=minUpper and math.min(minUpper,upper)or upper;maxUpper=maxUpper and math.max(maxUpper,upper)or upper
    minLower=minLower and math.min(minLower,lower)or lower;maxLower=maxLower and math.max(maxLower,lower)or lower
   end
   local elapsed=getTimestampMs()-started;assert(integer(elapsed)and elapsed>=0,'profile wall clock moved backwards')
   groupTime=groupTime+elapsed
   samples[#samples+1]={path=path,calls=C.calls,elapsedMilliseconds=elapsed,minUpper=minUpper,maxUpper=maxUpper,minLower=minLower,maxLower=maxLower}
  end
 end
 local finished=getTimestampMs();local elapsed=finished-began;assert(integer(elapsed)and elapsed>=groupTime,'invalid profile total clock observation');local after=snapshot()
 assert(owner==PZSurvivorToolkit.ActionQueueWeights and owner.capacity==capacity,'capacity helper changed during samples')
 assert(not queue.current and #queue.queue==0 and not player:hasTimedActions()and JSON.encode(before)==JSON.encode(after),'capacity profiling changed physical state or native queue')
 return{case=s.ids.case,point='before-wring-producers',clock='getTimestampMs',units='coarse wall-clock milliseconds',instances=C.instances,
  startedAt=began,finishedAt=finished,callsPerPath=C.calls*C.rounds,warmupPerPath=C.warmup,samples=samples,totalMilliseconds=elapsed,nativeWeight=nativeWeight,
  before=before,after=after,queueIdle=true,helperSource=true,helperUnchanged=owner.capacity==capacity,
  scope='actual Java-backed own-player root and carried bag; synchronous idle tick including Lua loop/validation overhead; no FPS or other inventory-size extrapolation'}
end
return C
