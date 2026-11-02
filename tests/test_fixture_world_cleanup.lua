-- Exact fixture cleanup with native stale pointers and modeled send failures.
-- Reprocessing an index message is modeled below; network duplication is not claimed.
local W=assert(loadfile((ProjectRoot or '.')..'/tests/native_queue/support/QueueFixtureWorldCleanup.lua'))()
local function list(values)
 return {size=function()return #values end,get=function(_,i)return values[i+1]end}
end
local function remove(values,object)
 for i=#values,1,-1 do if values[i]==object then table.remove(values,i)end end
end
local function expectFailure(fn,part)
 local ok,reason=pcall(fn);assert(not ok,'expected cleanup refusal')
 if part then assert(tostring(reason):find(part,1,true),tostring(reason))end
end
local function scene(ground)
 local s={objects={},special={},world={},notices={},localCalls=0,guardCalls=0,generation=1}
 local square={getX=function()return 10 end,getY=function()return 20 end,getZ=function()return 0 end}
 s.square=square;s.loaded=square
 square.getObjects=function()return list(s.objects)end
 square.getSpecialObjects=function()return list(s.special)end
 square.getWorldObjects=function()return list(s.world)end
 getCell=function()return {getGridSquare=function(_,x,y,z)if x==10 and y==20 and z==0 then return s.loaded end end}end
 function s.object(name,isGround)
  local object={name=name,square=square,container=nil}
  object.getSquare=function(self)return self.square end
  object.getObjectIndex=function(self)for i,value in ipairs(s.objects)do if value==self then return i-1 end end;return -1 end
  object.getContainer=function(self)return self.container end
  object.removeFromWorld=function(self)
   s.localCalls=s.localCalls+1
   if s.localBefore then error('local before effect')end
   self.worldRemoved=true
  end
  object.removeFromSquare=function(self)
   if s.localSquareBefore then error('local square before effect')end
   if s.localNoop then return end
   remove(s.objects,self);remove(s.special,self);remove(s.world,self)
   -- Match native removeFromSquare: back-pointers can remain attached to the old references.
   if s.localAfter then error('local after effect')end
  end
  if isGround then
   local item={id=12,ft='Base.Nails',world=object}
   item.getID=function(self)return self.id end;item.getFullType=function(self)return self.ft end
   item.getWorldItem=function(self)return self.world end;item.getContainer=function(self)return self.container end
   object.item=item;object.getItem=function(self)return self.item end
   s.world[#s.world+1]=object
  end
  s.objects[#s.objects+1]=object;return object
 end
 s.before=s.object('foreign-before');s.first=s.object('first',ground);s.between=s.object('foreign-between')
 s.second=s.object('second');s.after=s.object('foreign-after')
 square.transmitRemoveItemFromSquare=function(_,object,multi)
  assert(multi==false,'fixture cleanup may not remove multi-square partners')
  s.notices[#s.notices+1]={object=object,index=object:getObjectIndex()}
  if s.reenter then s.reenter()end
  if s.throwBefore then error('transmit before effect')end
  if not s.publishOnly then
   remove(s.objects,object);remove(s.special,object);remove(s.world,object)
  end
  if s.throwAfter then error('transmit after effect')end
 end
 function s.journal(objects)
  local entries={};for _,object in ipairs(objects or{s.first,s.second})do entries[#entries+1]={object=object,square=square}end
  local journal=W.new(entries,{server=true,guard=function(j)
   s.guardCalls=s.guardCalls+1;assert(s.j==j and s.generation==1,'fixture generation changed')
  end})
  assert(s.guardCalls==0,'new invoked guard before caller could bind its handle')
  s.j=journal;return journal
 end
 return s
end
do
 local s=scene(true);local j=s.journal()
 assert(W.receipt(j).publicationAttempts==0 and not W.removed(j,s.first))
 local r=W.run(j)
 assert(r.publicationAttempts==2 and r.removedObjects==2 and not r.publicationUncertain and #r.recoveries==0)
 assert(s.notices[1].object==s.second and s.notices[1].index==3 and s.notices[2].object==s.first and s.notices[2].index==1,
  'same-square removals must publish descending original indices')
 assert(#s.objects==3 and s.objects[1]==s.before and s.objects[2]==s.between and s.objects[3]==s.after)
 assert(W.absent(s.square,s.first,s.first.item)and s.first:getSquare()==s.square and s.first.item:getWorldItem()==s.first)
 W.run(j);assert(#s.notices==2 and s.localCalls==0,'repeat cleanup republished or reremoved an absent object')
 r.recoveries[1]={error='forged'};r.states[1].status='forged'
 assert(#W.receipt(j).recoveries==0 and W.receipt(j).states[1].status=='removed','receipt exposes journal mutation')
 expectFailure(function()j.changed=true end,'opaque')
end
for _,boundary in ipairs({'before','after'})do
 local s=scene();local j=s.journal({s.first});s[boundary=='before'and'throwBefore'or'throwAfter']=true
 expectFailure(function()W.run(j)end,'publication uncertain')
 local r=W.receipt(j);assert(r.publicationAttempts==1 and r.publicationUncertain and #r.recoveries==1)
 assert(r.removedObjects==(boundary=='after'and 1 or 0))
 s.throwBefore,s.throwAfter=false,false
 expectFailure(function()W.run(j)end,'remains uncertain')
 assert(#s.notices==1,'uncertain native transmit was retried')
end
for _,boundary in ipairs({'localBefore','localSquareBefore','localAfter'})do
 local s=scene(true);local j=s.journal({s.first});s.publishOnly=true;s[boundary]=true
 expectFailure(function()W.run(j)end,'local removal failed')
 local before=W.receipt(j);assert(before.publicationAttempts==1 and not before.publicationUncertain and #before.recoveries==1)
 assert(before.removedObjects==(boundary=='localAfter'and 1 or 0))
 local calls=s.localCalls;s[boundary]=false
 local after=W.run(j);assert(after.publicationAttempts==1 and after.removedObjects==1 and #s.notices==1)
 if boundary~='localBefore'then assert(s.localCalls==calls,'known completed local world-detach was replayed')end
end
do
 local s=scene();local j=s.journal({s.first});s.publishOnly=true;s.localBefore=true
 for _=1,3 do expectFailure(function()W.run(j)end,'local removal failed')end
 expectFailure(function()W.run(j)end,'local failure limit')
 assert(#s.notices==1 and #W.receipt(j).recoveries==3)
end
do
 local s=scene();local j=s.journal({s.first});s.publishOnly=true;s.localNoop=true
 for _=1,3 do expectFailure(function()W.run(j)end,'exact object still present')end
 expectFailure(function()W.run(j)end,'local failure limit');assert(#s.notices==1)
end
do
 -- A failed lower target preserves the already removed higher-index prefix.
 local s=scene();local j=s.journal();local native=s.square.transmitRemoveItemFromSquare
 s.square.transmitRemoveItemFromSquare=function(square,object,multi)
  if object==s.first then s.throwBefore=true end;return native(square,object,multi)
 end
 expectFailure(function()W.run(j)end,'publication uncertain')
 assert(W.removed(j,s.second)and not W.removed(j,s.first)and W.receipt(j).removedObjects==1)
 expectFailure(function()W.run(j)end,'remains uncertain');assert(#s.notices==2)
end
for _,mutation in ipairs({'foreign-removed','foreign-added','foreign-order','moved','unloaded','replaced-square',
 'nonempty','rebound-container','ground-id','ground-type','ground-object','ground-moved','ground-container','generation'})do
 local s=scene(true);local j=s.journal()
 if mutation=='foreign-removed'then remove(s.objects,s.before)
 elseif mutation=='foreign-added'then s.object('unexpected')
 elseif mutation=='foreign-order'then s.objects[1],s.objects[3]=s.objects[3],s.objects[1]
 elseif mutation=='moved'then s.first.square={}
 elseif mutation=='unloaded'then s.loaded=nil
 elseif mutation=='replaced-square'then s.loaded={}
 elseif mutation=='nonempty'then s.first.container={getItems=function()return list({{}})end}
 elseif mutation=='rebound-container'then s.first.container={getItems=function()return list({})end}
 elseif mutation=='ground-id'then s.first.item.id=99
 elseif mutation=='ground-type'then s.first.item.ft='Base.Other'
 elseif mutation=='ground-object'then s.first.item={}
 elseif mutation=='ground-moved'then s.first.item.world={}
 elseif mutation=='ground-container'then s.first.item.container={getType=function()return 'none'end}
 else s.generation=2 end
 expectFailure(function()W.run(j)end)
 assert(#s.notices==0,'identity/lease drift published a deletion: '..mutation)
end
do
 local s=scene(true);local j=s.journal();W.run(j)
 table.insert(s.objects,2,s.first)
 expectFailure(function()W.run(j)end,'reappeared')
 assert(#s.notices==2)
end
do
 local s=scene();local j=s.journal();s.reenter=function()W.run(j)end
 expectFailure(function()W.run(j)end)
 s.reenter=nil;expectFailure(function()W.run(j)end)
 assert(#s.notices==1,'reentrant cleanup republished its in-flight deletion')
end
do
 local s=scene(true);local object=s.first
 remove(s.objects,object);remove(s.world,object);s.special[1]=object
 assert(not W.absent(s.square,object,object.item),'special-list membership was mistaken for absence')
 s.special={};assert(W.absent(s.square,object,object.item))
 s.loaded=nil;assert(not W.absent(s.square,object,object.item),'unloaded square certified absence')
 s.loaded={};assert(not W.absent(s.square,object,object.item),'same-coordinate replacement certified absence')
end
do
 local s=scene(true)
 local floor={getType=function()return 'floor'end,getParent=function()end,getContainingItem=function()end}
 s.first.item.container=floor
 local j=s.journal({s.first});W.run(j)
 assert(s.first.item:getContainer()==floor and W.absent(s.square,s.first,s.first.item),
  'stale virtual floor view was mistaken for physical world membership')
 W.run(j);assert(#s.notices==1)
 s.first.item.container={getType=function()return 'none'end}
 assert(not W.absent(s.square,s.first,s.first.item),'a moved root item certified world absence')
 expectFailure(function()W.run(j)end)
end
do
 local s=scene(true)
 local function floor()return {getType=function()return 'floor'end,getParent=function()end,getContainingItem=function()end}end
 s.first.item.container=floor();local j=s.journal({s.first});s.first.item.container=floor()
 expectFailure(function()W.run(j)end,'moved/attached');assert(#s.notices==0)
end
do
 local s=scene()
 for _,entries in ipairs({{[2]={object=s.first}},{{object=s.first},unexpected={object=s.second}},
  {setmetatable({object=s.first},{})},setmetatable({{object=s.first}},{})})do
  expectFailure(function()W.new(entries,{server=true,guard=function()end})end)
 end
end
do
 -- Handler-level demonstration only: the wire index has no identity field.
 local objects={'owned','foreign'};table.remove(objects,1);table.remove(objects,1)
 assert(#objects==0,'model must retain the native duplicate-index hazard')
 local s=scene();local j=s.journal();W.run(j)
 assert(#s.notices==2 and #s.objects==3,'helper repeated an index deletion')
end
print('PASS fixture world cleanup: one-shot publication, stale pointers, exact neighbors, local-only recovery and quarantine')
