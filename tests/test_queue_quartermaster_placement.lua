-- Execute the actual SP fixture and placement protocol; model only game services.
local root=assert(ProjectRoot)..'/tests/native_queue/'
local function same(a,b)return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function fixture(mode)
 local f={now=0,x=100.5,y=100.5,z=0,logs={},rows={},itemRows={},teleports=0,mutations=0,admissions=0,objects={},registry={},id=0}
 local squares={}
 local function square(x,y,z)
  local id=x..','..y..','..z
  if not squares[id]then
   local s={x=x,y=y,z=z,objects={}}
   function s:getX()return self.x end;function s:getY()return self.y end;function s:getZ()return self.z end
   function s:isFree()return true end;function s:getRoom()end
   function s:getObjects()return {size=function()return #self.objects+1 end,get=function(_,i)return i==0 and {}or self.objects[i]end}end
   function s:AddSpecialObject(o)f.mutations=f.mutations+1;self.objects[#self.objects+1]=o end
   function s:RemoveTileObject(o)f.mutations=f.mutations+1;for i,v in ipairs(self.objects)do if v==o then table.remove(self.objects,i);return end end end
   squares[id]=s
  end
  return squares[id]
 end
 f.square=square(100,100,0);f.current=f.square;f.squareAt=square
 local function item(kind)
  f.id=f.id+1;local i={id=f.id,kind=kind,weight=kind=='Base.Nails'and .05 or 1}
  function i:getID()return self.id end;function i:getFullType()return self.kind end
  function i:getDisplayName()return self.kind end;function i:getActualWeight()return self.weight end
  function i:setActualWeight(value)f.mutations=f.mutations+1;self.weight=value end
  function i:setCustomWeight()f.mutations=f.mutations+1 end
  function i:getContainer()return self.container end
  function i:getNumberOfPages()return 20 end
  function i:setAlreadyReadPages()f.mutations=f.mutations+1 end
  return i
 end
 local function container()
  local c={items={},capacity=100}
  function c:getItems()return {size=function()return #c.items end,get=function(_,i)return c.items[i+1]end}end
  function c:AddItem(value)
   f.mutations=f.mutations+1;if type(value)=='string'then value=item(value)end
   self.items[#self.items+1]=value;value.container=self;return value
  end
  function c:Remove(value)
   f.mutations=f.mutations+1
   for i,v in ipairs(self.items)do if value==v then table.remove(self.items,i);value.container=nil;return end end
  end
  function c:getItemById(id)for _,v in ipairs(self.items)do if v.id==id then return v end end end
  function c:setCapacity(v)f.mutations=f.mutations+1;self.capacity=v end
  function c:getEffectiveCapacity()return self.capacity end
  function c:getCapacityWeight()local n=0;for _,v in ipairs(self.items)do n=n+v.weight end;return n end
  function c:setType()f.mutations=f.mutations+1 end;function c:setExplored()f.mutations=f.mutations+1 end
  return c
 end
 local p={inventory=container()};f.player=p;f.q={queue={}}
 for _,key in ipairs({'X','Y','Z'})do p['get'..key]=function()return f[key:lower()]end;p['set'..key]=function(_,v)f[key:lower()]=v end end
 function p:getSquare()return f.square end;function p:getCurrentSquare()return f.current end
 function p:isLocalPlayer()return true end;function p:getInventory()return self.inventory end
 function p:hasTimedActions()return f.timed or #f.q.queue>0 end
 function p:isPlayerMoving()return f.moving or false end
 function p:getPath2()return f.path end
 function p:getDeferredMovement()return {getX=function()return f.dx or 0 end,getY=function()return f.dy or 0 end}end
 function p:setGodMod()end;function p:setGhostMode()end
 function p:setAlreadyReadPages()f.mutations=f.mutations+1 end
 for _,key in ipairs({'NextX','NextY','LastX','LastY'})do p['set'..key]=function()end end
 function p:ensureOnTile()end;function p:setCurrentSquareFromPosition()end;function p:setMovingSquareNow()end
 function p:teleportTo(x,y,z)f.teleports=f.teleports+1;f.teleportTarget={x=x,y=y,z=z}end
 function f:arrive(target)
  target=target or self.teleportTarget;self.x,self.y,self.z=target.x+.5,target.y+.5,target.z
  self.square=square(target.x,target.y,target.z);self.current=self.square
 end
 local window={listBox={items={}}}
 local function key(o)local s=o:getSquare();return s.x..','..s.y..','..s.z end
 local store={containers={}}
 local loot={ADD_GRACE_MS=0}
 function f:refresh()
  store.containers={};local count=0
  for _,o in ipairs(self.objects)do if self.registry[key(o)]then
   local n=0;for _,v in ipairs(o.container.items)do if v.kind=='Base.Nails'then n=n+1 end end
   store.containers[#store.containers+1]={key=key(o),entries={{ft='Base.Nails',n=n}}};count=count+n
  end end
  window.listBox.items={{item={ft='Base.Nails',n=count}}}
 end
 function window:rebuild()f.mutations=f.mutations+1;f:refresh()end
 function window:close()f.mutations=f.mutations+1 end
 function loot.toggleManifest()f.mutations=f.mutations+1;loot._manifestWin=window end
 function loot.setBoxItems(o,_,values)f.mutations=f.mutations+1;f.registry[key(o)]=next(values)and values or nil;f:refresh()end
 function loot.containerIndex()return 1 end;function loot.getRegistry()return f.registry end
 local function opaque()return {new=function()return {kind='custom'}end}end
 loot.WalkAction=opaque();loot.DepositAction=opaque();loot.CraftTriggerAction=opaque()
 local function deny(_,action)
  assert(action.kind=='custom');f.denials=(f.denials or 0)+1
  return false,mode=='native'and'unavailable'or'edit_unknown'
 end
 local toolkit={Settings={actionQueue=function()return mode=='toolkit'end},ManifestAuthority={getStore=function()return store end},
  ActionQueuePolicy={inspect=function(action)return action.kind~='custom'end},ActionQueueOperations={run=function(fn)fn()end},
  ActionQueue={cancel=deny,cancelOperation=deny,move=deny}}
 local encoded
 local env=setmetatable({PZSurvivorToolkit=toolkit,LootSorter=loot,Events={},
  getPlayer=function()return p end,getTimestampMs=function()return f.now end,isClient=function()return false end,isServer=function()return false end,
  isIngameState=function()return true end,getCell=function()return {getGridSquare=function(_,x,y,z)return square(x,y,z)end}end,
  Vector2={new=function()return {}end},instanceItem=item,
  print=function(message)
   f.logs[#f.logs+1]=message
   if message:match('^%[QM_TRANSFER_PLACEMENT%] ')then f.rows[#f.rows+1]={event=message:match('^%[QM_TRANSFER_PLACEMENT%] (%S+)'),value=encoded}end
   if message:match('^%[QM_TRANSFER_ITEMS%] ')then f.itemRows[encoded.point]=encoded end
   if message:match('^%[QM_TRANSFER%] FAIL ')then f.failure=message end
  end},{__index=_G})
 env._G=env
 env.IsoThumpable={new=function(_,s)
  f.mutations=f.mutations+1;local o={square=s,container=container()};f.objects[#f.objects+1]=o
  function o:getSquare()return self.square end;function o:getContainer()return self.container end
  function o:getObjectIndex()return self.detached and -1 or 1 end
  function o:setCanPassThrough()f.mutations=f.mutations+1 end;function o:setIsContainer()f.mutations=f.mutations+1 end
  return o
 end}
 env.ISTimedActionQueue={getTimedActionQueue=function()return f.q end,
  add=function(action)f.admissions=f.admissions+1;f.q.queue[#f.q.queue+1]=action end,
  clear=function()f.q.queue={};f.q.current=nil end}
 env.ISInventoryTransferAction={new=function(_,actor,value,source,dest)
  local a={kind='transfer',item=value,source=source,dest=dest}
  function a:isValid()return self.dest:getCapacityWeight()+self.item.weight<=self.dest.capacity end
  return a
 end}
 env.ISReadABook={new=function()return {kind='book',isStarted=function()return true end,getJobDelta=function()return .5 end}end}
 local function load(path)local fn=assert(loadfile(root..path));setfenv(fn,env);return fn()end
 f.P=load('support/QueueEnergyPlacement.lua');local choose=f.P.choose
 f.P.choose=function(actor)f.chooses=(f.chooses or 0)+1;return choose(actor)end
 env.require=function(name)
  if name=='QueueTestSelection'then return {mode=mode,kind='sp',cases={'manifest'}}end
  if name=='QueueEnergyPlacement'then return f.P end
  if name=='QueueHealthEvents'then return {encode=function(value)encoded=value;return '{}'end}end
  if name=='QueuePreflight'then return {onGameStart=function(_,fn)f.start=fn end,onTick=function(_,fn)f.callback=fn end}end
  return {}
 end
 load('quartermaster-transfers/client/ZZQuartermasterTransfers.lua')
 function f:tick(delta)self.now=self.now+(delta or 1);self:refresh();self.callback()end
 function f:has(event)local n=0;for _,row in ipairs(self.rows)do if row.event==event then n=n+1 end end;return n end
 function f:advanceQueue()
  local q=self.q
  if q.current then table.remove(q.queue,1);q.current=nil;return end
  local moved=false
  while q.queue[1]and q.queue[1].kind=='transfer'do
   local a=table.remove(q.queue,1)
   if a:isValid()then a.source:Remove(a.item);a.dest:AddItem(a.item);moved=true
   elseif not moved then q.queue={};return end
  end
  if q.queue[1]then q.current=q.queue[1]end
 end
 f.start();return f
end

local function settle(f)
 local before=f:has('LOCAL')
 for _=1,20 do
  f:tick(501)
  if f.teleportTarget then f:arrive(f.teleportTarget)end
  assert(not f.failure,f.failure)
  if f:has('LOCAL')>before then return end
 end
 error('placement did not settle')
end

-- A teleport request and centered coordinates cannot replace both loaded squares.
for _,mode in ipairs({'toolkit','native'})do
 local f=fixture(mode);f.moving=true;f:tick();f:tick(501)
 assert(f.mutations==0 and f.admissions==0 and f.teleports==0,'busy actor mutated initial fixture')
 f.moving=false;f:tick();f:tick(501)
 assert(f.teleports==1 and f.mutations==0 and f.admissions==0,'initial setup preceded arrival')
 f:tick(501);assert(f.mutations==0,'position setters hid delayed native squares')
 f:arrive();f.current=nil;f:tick();f:tick(501)
 assert(f.mutations==0 and f:has('LOCAL')==0,'stale current square admitted setup')
 f.current=f.square;settle(f)
 assert(#f.objects==2 and not f.failure,'settled initial fixture was not constructed')
 assert(f.chooses==1,'placement target must be selected once')
end

-- Run every native-transfer branch, protected custom edits and terminal cleanup.
for _,mode in ipairs({'toolkit','native'})do
 local f=fixture(mode)
 for _=1,200 do
  f:tick(501)
  if f.teleportTarget then f:arrive()end
  assert(not f.failure,f.failure)
  f:advanceQueue()
  if f.logs[#f.logs]=='[QM_TRANSFER] COMPLETE case=manifest'then break end
 end
 assert(f.logs[#f.logs]=='[QM_TRANSFER] COMPLETE case=manifest','fixture did not finish')
 assert(f.denials==9,'custom actions lost protected cancellation/reorder checks')
 assert(f.chooses==1,'rounds reselected the stable layout')
 local targets,tokens={},{}
 local round,eventIndex=1,1
 local phases={'success','partial','rejected','withdraw','custom'}
 local events={'LAYOUT','LOCAL','PREPARED','ADMITTED'}
 local roundToken
 for _,row in ipairs(f.rows)do
  local v=assert(row.value,'placement event lacks structured evidence')
  assert(v.case=='manifest'and type(v.phase)=='string'and type(v.index)=='number'and v.token~=nil,'placement event lacks round identity')
  assert(row.event==events[eventIndex]and v.phase==phases[round]and v.index==round,'placement round event order changed')
  if eventIndex==1 then roundToken=v.token end
  assert(v.token==roundToken,'placement proof or admission changed round token')
  assert(same(v.target,f.teleportTarget),'placement event target drifted')
  targets[row.event]=(targets[row.event]or 0)+1
  if row.event=='LAYOUT'or row.event=='PREPARED'then
   assert(v.boxes and same(v.boxes[1],{x=v.target.x+1,y=v.target.y,z=v.target.z})
    and same(v.boxes[2],{x=v.target.x,y=v.target.y+1,z=v.target.z}),'crate roles no longer east/south')
  end
  if row.event=='LOCAL'then
   assert(v.proof.mode=='local'and v.proof.centered and v.proof.teleports==1 and v.proof.centers==1
    and same(v.proof.target,v.target)and same(v.proof.actual.square,v.target)
    and same(v.proof.actual.currentSquare,v.target),'invalid owning actor proof')
  end
  if row.event=='LAYOUT'then assert(not tokens[v.token],'round token reused');tokens[v.token]=true end
  eventIndex=eventIndex+1
  if eventIndex>#events then eventIndex=1;round=round+1 end
 end
 assert(targets.LAYOUT==5 and targets.LOCAL==5 and targets.PREPARED==5 and targets.ADMITTED==5,'placement rounds lost setup or an action phase')
 assert(f.teleports==5,'cleanup created a new placement round')
 for _,o in ipairs(f.objects)do assert(#o.square.objects==0 and not f.registry[o.square.x..','..o.square.y..','..o.square.z],'terminal cleanup left owned fixture')end
end

-- P4 may restore the completed withdrawal during the next placement's idle
-- window. The independent custom round owns fresh exact root/world inputs.
for _,mode in ipairs({'toolkit','native'})do
 local f=fixture(mode)
 local inventory=f.player:getInventory()
 local unrelated=inventory:AddItem('Base.Nails')
 for _=1,200 do
  f:tick(501);assert(not f.failure,f.failure)
  local last=f.rows[#f.rows]
  if last and last.event=='LAYOUT'and last.value.phase=='custom'then break end
  if f.teleportTarget then f:arrive()end
  f:advanceQueue()
 end
 local last=f.rows[#f.rows]
 assert(last.event=='LAYOUT'and last.value.phase=='custom','custom placement not reached')
 local previous=assert(f.itemRows['withdraw-finished']).items
 assert(previous[1].root and previous[2].source,'withdrawal lost the exact requested identity before idle restoration')
 local source,dest=f.objects[1]:getContainer(),f.objects[2]:getContainer()
 local withdrawn=assert(inventory:getItemById(previous[1].id))
 -- This models P4's idle finishSession -> queueRestore effect, after the
 -- withdrawal receipt but before custom LOCAL proves the next idle scene.
 f:tick(1);assert(not f.itemRows['custom-prepared'],'custom inputs seeded before placement settled')
 inventory:Remove(withdrawn);source:AddItem(withdrawn)
 assert(source:getItemById(previous[1].id)==withdrawn and source:getItemById(previous[2].id),
  'idle restoration simulation did not return only the completed withdrawal')
 settle(f)
 local prepared=assert(f.itemRows['custom-prepared']).items
 assert(prepared[1].root and not prepared[1].source and not prepared[1].dest
  and prepared[2].source and not prepared[2].root and not prepared[2].dest,'custom round did not prepare root/world inputs')
 assert(prepared[1].id~=prepared[2].id,'custom IDs alias')
 for _,old in ipairs(previous)do
  assert(prepared[1].id~=old.id and prepared[2].id~=old.id,'custom round reused a restored prior ID')
  assert(not inventory:getItemById(old.id)and not source:getItemById(old.id)and not dest:getItemById(old.id),
   'prior owned transfer item survived custom retirement')
 end
 assert(inventory:getItemById(unrelated:getID())==unrelated and unrelated:getContainer()==inventory,
  'custom retirement removed unrelated original root inventory')
 for _=1,20 do
  f:tick(501);assert(not f.failure,f.failure);f:advanceQueue()
  if f.logs[#f.logs]=='[QM_TRANSFER] COMPLETE case=manifest'then break end
 end
 local after=assert(f.itemRows['custom-after-edits']).items
 assert(after[1].id==prepared[1].id and after[1].root and after[2].id==prepared[2].id and after[2].source,
  'protected custom editing changed independently prepared IDs')
 assert(f.denials==9 and f.logs[#f.logs]=='[QM_TRANSFER] COMPLETE case=manifest','restoration interrupted custom coverage or cleanup')
 assert(inventory:getItemById(unrelated:getID())==unrelated and unrelated:getContainer()==inventory,
  'terminal cleanup removed unrelated original root inventory')
end

-- Every later round waits without editing capacity, items, pages or the UI.
-- The custom round exercises the same wait before its blocker book is created.
for _,wanted in ipairs({'partial','rejected','withdraw','custom'})do
 local f=fixture('toolkit')
 for _=1,200 do
  f:tick(501);assert(not f.failure,f.failure)
  local last=f.rows[#f.rows]
  if last and last.event=='LAYOUT'and last.value.phase==wanted then break end
  if f.teleportTarget then f:arrive()end
  f:advanceQueue()
 end
 local last=f.rows[#f.rows]
 assert(last.event=='LAYOUT'and last.value.phase==wanted,'did not reach requested round')
 local mutations,admissions,teleports=f.mutations,f.admissions,f.teleports
 for _,fault in ipairs({'queue','timed','moving','path','deferred','square'})do
  if fault=='queue'then f.q.queue={{kind='foreign'}}elseif fault=='timed'then f.timed=true
  elseif fault=='moving'then f.moving=true elseif fault=='path'then f.path={}
  elseif fault=='deferred'then f.dy=.1 else f.current=nil end
  f:tick(501);f:tick(501)
  assert(not f.failure,f.failure)
  assert(f.mutations==mutations and f.admissions==admissions and f.teleports==teleports,
   wanted..' modified scene before quiet arrival: '..fault)
  f.q.queue={};f.timed=false;f.moving=false;f.path=nil;f.dy=0;f.current=f.square
 end
 settle(f)
 assert(f.mutations>mutations and f.teleports==teleports+1,'settled round did not prepare fixture')
end

-- Fresh admission must reject drift and motion after the seeding proof.
for _,fault in ipairs({'position','square','queue','timed','path','moving','deferred','moved-crate','detached-crate','unbound-crate'})do
 local f=fixture('toolkit');settle(f)
 assert(f:has('PREPARED')==1 and f.admissions==0,'failed to stop between preparation and prime admission')
 local mutations=f.mutations
 if fault=='position'then f.x=f.x+2 elseif fault=='square'then f.current=nil
 elseif fault=='queue'then f.q.queue={{kind='foreign'}}elseif fault=='timed'then f.timed=true
 elseif fault=='path'then f.path={}elseif fault=='moving'then f.moving=true elseif fault=='deferred'then f.dx=.1
 elseif fault=='moved-crate'then
  local target=f.teleportTarget
  f.objects[1].square=f.squareAt(target.x+2,target.y,target.z)
  f.registry[(target.x+2)..','..target.y..','..target.z]=true
 elseif fault=='detached-crate'then f.objects[1].detached=true
 else f.objects[1].square.objects={}end
 f:tick()
 assert(f.failure and f.admissions==0 and f.mutations==mutations,'stale placement mutated or admitted actions: '..fault)
end
print('QUEUE_QUARTERMASTER_PLACEMENT_PASS')
