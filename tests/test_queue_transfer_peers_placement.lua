-- Source-backed regressions for the peer fixture's placement barriers.
local root=ProjectRoot or(arg and arg[1])or'.'
local base=root..'/tests/native_queue/'
local function copy(value)
 if type(value)~='table'then return value end
 local result={};for key,v in pairs(value)do result[key]=copy(v)end;return result
end
local function list(values)return{size=function()return #values end,get=function(_,i)return values[i+1]end,isEmpty=function()return #values==0 end}end
local function point(x,y,z)return{x=x,y=y,z=z or 0}end
local function fixture(server)
 local f={now=0,server=server~=false,mutations=0,teleports=0,sent={},commands={},events={},logs={},squares={},nextId=10}
 local env=setmetatable({},{__index=_G});f.env=env
 local function mutate()f.mutations=f.mutations+1 end
 local function container()
  local c={items={},capacity=100}
  function c:getItems()return list(self.items)end
  function c:getCapacity()return self.capacity end
  function c:setCapacity(n)mutate();self.capacity=n end
  function c:getCapacityWeight()return #self.items end
  function c:hasRoomFor()return #self.items<self.capacity end
  function c:setType()mutate()end;function c:setExplored()mutate()end
  function c:AddItem(ft)
   mutate();f.nextId=f.nextId+1
   local item={id=f.nextId,ft=ft,container=self,modData={},pages=0}
   function item:getID()return self.id end;function item:getFullType()return self.ft end
   function item:getContainer()return self.container end;function item:getModData()return self.modData end
   function item:getNumberOfPages()return 220 end;function item:getAlreadyReadPages()return self.pages end
   function item:setAlreadyReadPages(n)mutate();self.pages=n end;function item:setFavorite()mutate()end
   function item:getActualWeight()return 1 end;function item:getWeight()return self.ft=='Base.Nails'and .1 or 1 end
   self.items[#self.items+1]=item;return item
  end
  function c:Remove(item)mutate();for i,v in ipairs(self.items)do if v==item then table.remove(self.items,i);return end end;error('unknown removal')end
  return c
 end
 function f.square(x,y,z)
  local key=x..':'..y..':'..z
  if not f.squares[key]then
   local s={x=x,y=y,z=z,objects={}}
   function s:getX()return self.x end;function s:getY()return self.y end;function s:getZ()return self.z end
   function s:isFree(checkMoving)
    if checkMoving then for _,player in pairs(f.players or{})do
     if player.loaded and math.floor(player.x)==self.x and math.floor(player.y)==self.y and player.z==self.z then return false end
    end end
    return true
   end
   function s:getRoom()return nil end;function s:isBlockedTo()return false end
   function s:getFloor()return{}end;function s:TreatAsSolidFloor()return true end
   function s:getObjects()return list(self.objects)end
   function s:AddSpecialObject(o)mutate();self.objects[#self.objects+1]=o end
   function s:transmitRemoveItemFromSquare(o)mutate();for i,v in ipairs(self.objects)do if v==o then table.remove(self.objects,i);return end end end
   f.squares[key]=s
  end
  return f.squares[key]
 end
 f.players={}
 for index,role in ipairs({'client1','client2'})do
  local player={role=role,id=index,x=100.5+index,y=100.5,z=0,loaded=true,inventory=container(),pages={}}
  function player:getUsername()return self.role end;function player:getOnlineID()return self.id end
  function player:getX()return self.x end;function player:getY()return self.y end;function player:getZ()return self.z end
  function player:getSquare()return self.loaded and(self.square or f.square(math.floor(self.x),math.floor(self.y),self.z))or nil end
  function player:getCurrentSquare()return self.loaded and not self.currentMissing and self:getSquare()or nil end
  function player:isLocalPlayer()return not f.server end
  function player:getInventory()return self.inventory end
  function player:hasTimedActions()return false end;function player:getCharacterActions()return list({})end
  function player:isPlayerMoving()return false end;function player:getPath2()return nil end
  function player:getDeferredMovement(out)return out end;function player:isTimedActionInstant()return false end
  function player:teleportTo(x,y,z)mutate();f.teleports=f.teleports+1;self.x,self.y,self.z=x,y,z;self.square=nil end
  for _,axis in ipairs({'X','Y','Z'})do player['set'..axis]=function(self,n)mutate();self[axis:lower()]=n end end
  for _,name in ipairs({'setNextX','setNextY','setLastX','setLastY','ensureOnTile','setCurrentSquareFromPosition','setMovingSquareNow',
   'setGodMod','setGhostMode','setAutoDrink','setPerkLevelDebug'})do player[name]=function()mutate()end end
  function player:setAlreadyReadPages(ft,n)mutate();self.pages[ft]=n end
  function player:getAlreadyReadPages(ft)return self.pages[ft]or 0 end
  function player:tooDarkToRead()return false end;function player:hasTrait()return false end
  f.players[role]=player
 end
 function f.arrive(role,target)
  local p=f.players[role];p.x,p.y,p.z=target.x+.5,target.y+.5,target.z;p.square=nil;p.currentMissing=false;p.loaded=true
 end
 env.isServer=function()return f.server end;env.isClient=function()return not f.server end
 env.getTimestampMs=function()return f.now end
 env.getOnlinePlayers=function()return list({f.players.client1,f.players.client2})end
 env.getCell=function()return{getGridSquare=function(_,x,y,z)return f.square(x,y,z)end}end
 env.Vector2={new=function()return{getX=function()return 0 end,getY=function()return 0 end}end}
 env.ISTimedActionQueue={getTimedActionQueue=function()return{queue={}}end}
 env.instanceof=function(item,name)return name=='Literature'and item.ft~='Base.Nails'end
 env.IsoThumpable={new=function(_,square)
  mutate();local o={square=square,container=container(),modData={}}
  function o:getSquare()return self.square end;function o:getContainer()return self.container end
  function o:getModData()return self.modData end
  function o:getObjectIndex()for i,v in ipairs(self.square.objects)do if v==self then return i-1 end end;return -1 end
  for _,name in ipairs({'setCanPassThrough','setIsContainer','transmitCompleteItemToClients','transmitModData'})do o[name]=function()mutate()end end
  return o
 end}
 env.Perks={Woodwork='Woodwork',Cooking='Cooking'};env.CharacterTrait={DISORGANIZED='d',ILLITERATE='i'}
 env.getGameTime=function()return{setTimeOfDay=function()mutate()end}end
 env.sendAddItemToContainer=function()mutate()end;env.sendRemoveItemFromContainer=function()mutate()end
 env.print=function(text)f.logs[#f.logs+1]=text end
 local function event(name)return{Add=function(fn)f[name]=fn end}end
 env.Events={OnTick=event('tick'),OnClientCommand=event('command'),OnServerCommand=event('reply'),OnGameStart=event('start')}
 env.sendServerCommand=function(player,module,command,row)
  f.sent[#f.sent+1]={role=player:getUsername(),module=module,command=command,row=row}
 end
 env.sendClientCommand=function(module,command,row)f.commands[#f.commands+1]={module=module,command=command,row=row}end
 function f.load(path)local chunk=assert(loadfile(base..path));setfenv(chunk,env);return chunk()end
 f.P=f.load('support/QueueEnergyPlacement.lua')
 f.config={suite='queue-transfer-peers',kind='mp',mode='toolkit',disposable=true,cases={'disjoint-returns','shared-capacity','partial-accepted'}}
 f.modules={QueueEnergyPlacement=f.P,QueueHealthEvents={encode=function()return'{}'end},QueueTestSelection=f.config,
  QueuePreflight={onGameStart=function(_,fn)f.start=fn end,onTick=function(_,fn)f.tick=fn end}}
 env.require=function(name)return f.modules[name]or{}end
 f.F=f.load('queue-transfer-peers/shared/QueueTransferPeers.lua');f.modules.QueueTransferPeers=f.F
 f.F.emit=function(event,row)f.events[#f.events+1]={event=event,row=row}end
 function f.proofs(layout,mode)
  local values={}
  if mode=='local'then
   -- Owner proofs come from the same real helper in a separate client VM
   -- double; moving that owner must not move the authority's replica.
   local client=fixture(false)
   for _,role in ipairs(f.F.roles)do
    local pending=client.P.beginCentered(client.players[role],layout.targets[role])
    client.P.poll(pending);client.now=client.now+500;client.P.poll(pending)
    client.P.poll(pending);client.now=client.now+500
    values[role]=assert(client.P.poll(pending))
   end
   return values
  end
  for _,role in ipairs(f.F.roles)do
   f.arrive(role,layout.targets[role]);local p=f.players[role]
   local observe=f.P.observeCentered(p,layout.targets[role]);f.P.poll(observe);f.now=f.now+500
   values[role]=assert(f.P.poll(observe))
  end
  return values
 end
 function f.has(event)for _,row in ipairs(f.events)do if row.event==event then return row end end end
 function f.request(role,command,args)f.command(f.F.module,command,f.players[role],args)end
 return f
end

-- Reserving a common layout is read-only, and later phases keep its origin.
local f=fixture();local F=f.F
local layout=F.plan(f.players,'disjoint-returns',1)
assert(f.mutations==0 and f.teleports==0,'planning mutated the fixture')
assert(layout.case=='disjoint-returns'and layout.index==1 and type(layout.token)=='string')
assert(F.same(layout.origin,layout.targets.client1))
assert(layout.targets.client2.x==layout.origin.x+1 and layout.targets.client2.y==layout.origin.y and layout.targets.client2.z==layout.origin.z)
local proofs=f.proofs(layout)
local before=f.mutations;f.players.client2.x=f.players.client2.x+.3
assert(not pcall(F.prepare,f.players,layout,proofs),'stale second actor permitted physical setup')
assert(f.mutations==before,'failed placement mutated scene')
f.arrive('client2',layout.targets.client2)
local s=F.prepare(f.players,layout,proofs)
assert(f.teleports==0,'authority moved remote actors')
local nextLayout=F.plan(f.players,'shared-capacity',2,s)
assert(F.same(layout.origin,nextLayout.origin)and F.same(layout.targets,nextLayout.targets),'phase planning moved owned shelves')

-- All seed preconditions run before capacity, inventory, pages or perks change.
for _,fault in ipairs({'actor-drift','square-delay','wrong-mode','wrong-target','missing-proof'})do
 local g=fixture();local l=g.F.plan(g.players,'disjoint-returns',1);local p=g.proofs(l)
 local state=g.F.prepare(g.players,l,p)
 if fault=='actor-drift'then g.players.client2.x=g.players.client2.x+.3
 elseif fault=='square-delay'then g.players.client2.currentMissing=true
 elseif fault=='wrong-mode'then p.client2.mode='local'
 elseif fault=='wrong-target'then p.client2.target=point(l.targets.client2.x+1,l.targets.client2.y,l.targets.client2.z)
 else p.client2=nil end
 local n=g.mutations
 assert(not pcall(g.F.seed,state,l.case,l.index,l,p),'seed accepted '..fault)
 assert(g.mutations==n and not state.seed,'rejected seed changed native state: '..fault)
end
local ids=F.seed(s,layout.case,layout.index,layout,proofs)
assert(F.same(ids.placement,layout.targets)and ids.token==layout.token,'seed lost reserved placement identity')
local count=#ids.items
F.release(s);assert(not s.seed)
for _,spec in ipairs(ids.items)do local _,_,n=F.find(s,spec.id);assert(n==0,'owned identity survived release')end
assert(count>0)
for _,fault in ipairs({'wrong-mode','wrong-target','missing-proof'})do
 local g=fixture();local l=g.F.plan(g.players,'disjoint-returns',1);local p=g.proofs(l)
 if fault=='wrong-mode'then p.client2.mode='local'
 elseif fault=='wrong-target'then p.client2.target=l.targets.client1
 else p.client2=nil end
 local n=g.mutations
 assert(not pcall(g.F.prepare,g.players,l,p)and g.mutations==n,'physical prepare accepted '..fault)
end

-- Actual coordinator: both clients and both independently settled replicas
-- must pass before any fixture mutation. One release ack cannot advance it.
local function serverFixture()
 local g=fixture()
 local prepare=g.F.prepare
 g.F.prepare=function(...)
  local seen={}
  for _,entry in ipairs(g.events)do if entry.event=='AUTHORITY_PLACEMENT'then seen[entry.row.role]=true end end
  assert(seen.client1 and seen.client2,'scene mutation preceded both authority placement receipts')
  return prepare(...)
 end
 g.load('queue-transfer-peers/server/ZZQueueTransferPeersServer.lua')
 function g.layout()for i=#g.sent,1,-1 do if g.sent[i].command=='Layout'then return g.sent[i].row end end end
 function g.seed()for i=#g.sent,1,-1 do if g.sent[i].command=='Seeded'then return g.sent[i].row end end end
 function g.args(l,role)
  return{case=l.case,index=l.index,token=l.token,role=role,target=l.targets[role],proof=g.proofs(l,'local')[role]}
 end
 function g.hello()
  for _,role in ipairs(g.F.roles)do g.request(role,'Hello',{case=g.config.cases[1],index=1})end
 end
 function g.placed(l)
  for _,role in ipairs(g.F.roles)do g.request(role,'Placed',g.args(l,role))end
 end
 function g.settle(l)
  for _,role in ipairs(g.F.roles)do g.arrive(role,l.targets[role])end
  g.tick();g.now=g.now+500;g.tick()
 end
 return g
end
f=serverFixture();f.players.client2.loaded=false;f.hello();f.tick()
assert(not f.layout()and f.mutations==0,'unloaded peer allowed layout or scene setup')
f.players.client2.loaded=true;f.tick();layout=assert(f.layout())
assert(f.mutations==0 and not f.seed(),'layout prepared physical scene')
local localProofs=f.proofs(layout,'local')
-- Hold the authority's replica away after the owner reports its local proof.
f.arrive('client1',layout.targets.client1);f.arrive('client2',layout.targets.client2)
f.players.client2.x=f.players.client2.x+2
for _,role in ipairs(f.F.roles)do
 f.request(role,'Placed',{case=layout.case,index=layout.index,token=layout.token,role=role,target=layout.targets[role],proof=localProofs[role]})
end
f.tick();f.now=f.now+500;f.tick()
assert(f.mutations==0 and not f.seed()and f.teleports==0,'client proof bypassed authority replica barrier')
f.arrive('client2',layout.targets.client2);f.tick();f.now=f.now+500;f.tick()
ids=assert(f.seed(),'settled replicas never seeded')
assert(f.teleports==0 and f.has('AUTHORITY_PLACEMENT'),'authority placement evidence absent')
for _,role in ipairs(f.F.roles)do f.request(role,'Ready',{case=ids.case,index=ids.index,token=ids.token})end
for _,role in ipairs(f.F.roles)do f.request(role,'Result',{case=ids.case,index=ids.index,token=ids.token,result={role=role}})end
f.tick();assert(f.has('RESULT')and not f.has('FAIL'))
local prior=f.layout();local mutations=f.mutations
f.request('client1','Released',{case=ids.case,index=ids.index,token=ids.token});f.tick()
assert(f.layout()==prior and f.mutations==mutations,'single release acknowledgement advanced fixture')
f.request('client2','Released',{case=ids.case,index=ids.index,token=ids.token});f.tick()
local later=assert(f.layout())
assert(later.index==2 and f.F.same(later.origin,layout.origin)and f.has('AUTHORITY_CLEARED'),'release barrier lost common origin')
assert(f.mutations==mutations,'next layout seeded before new placement proofs')

-- Reject forged or out-of-phase owner reports before any seed mutations.
for _,fault in ipairs({'stale-token','wrong-case','wrong-index','wrong-role','wrong-target','wrong-proof-target','replica-proof','unsettled-proof','native-motion','duplicate','ready-before-seed','missing-arguments','foreign-actor'})do
 local g=serverFixture();g.hello();g.tick();local l=assert(g.layout());local a=g.args(l,'client1')
 if fault=='stale-token'then a.token='old'
 elseif fault=='wrong-case'then a.case='other'
 elseif fault=='wrong-index'then a.index=2
 elseif fault=='wrong-role'then a.role='client2'
 elseif fault=='wrong-target'then a.target=l.targets.client2
 elseif fault=='wrong-proof-target'then a.proof.target=l.targets.client2
 elseif fault=='replica-proof'then a.proof.mode='replica'
 elseif fault=='unsettled-proof'then a.proof.stableMs=0
 elseif fault=='native-motion'then a.proof.actual.queued=1
 elseif fault=='duplicate'then g.request('client1','Placed',a)end
 if fault=='missing-arguments'then g.request('client1','Placed',nil)
 elseif fault=='foreign-actor'then g.command(g.F.module,'Placed',{getUsername=function()return'client1'end},a)
 else g.request('client1',fault=='ready-before-seed'and'Ready'or'Placed',a)end
 g.tick()
 assert(g.has('FAIL')and not g.seed()and g.mutations==0,'server accepted '..fault)
end

f=serverFixture();f.hello();f.tick();layout=f.layout()
for _,role in ipairs(f.F.roles)do f.arrive(role,layout.targets[role]);f.request(role,'Placed',f.args(layout,role))end
f.tick();f.players.client2.currentMissing=true;f.now=f.now+500;f.tick()
assert(not f.seed()and f.mutations==0)
f.players.client1.x=f.players.client1.x+.3;f.players.client2.currentMissing=false
f.tick();f.now=f.now+500;f.tick()
assert(f.has('FAIL')and not f.seed()and f.mutations==0,'consumed replica proof masked drift before scene mutation')

local function clientFixture(case,role)
 local g=fixture();role=role or'client1';case=case or'disjoint-returns'
 g.config.cases={case}
 g.layout=g.F.plan(g.players,case,1);local p=g.proofs(g.layout)
 g.authority=g.F.prepare(g.players,g.layout,p)
 g.ids=copy(g.F.seed(g.authority,case,1,g.layout,p))
 g.server=false;g.player=g.players[role];g.queue={queue={}};g.produced=0
 local env=g.env
 env.getPlayer=function()return g.player end;env.isIngameState=function()return true end
 function g.player:getPlayerNum()return 0 end
 env.getCore=function()return{setOptionPauseOnFocusloss=function()end,setOptionAutoDrink=function()end}end
 env.PZAPI={ModOptions={getOptions=function()return{getOption=function()return{setValue=function()end}end}end}}
 env.ISTimedActionQueue.getTimedActionQueue=function()return g.queue end
 env.ISTimedActionQueue.add=function(action)g.queue.queue[#g.queue.queue+1]=action end
 local function action(kind,item)
  return{Type=kind,item=item,character=g.player,maxTime=150,transactionId=0,isStarted=function()return false end}
 end
 local function producer(items)
  g.produced=g.produced+1;local item=items[1]
  if item==g.resolved.front then
   local pickup=action('ISInventoryTransferAction',item);pickup.srcContainer=g.resolved.frontSource;pickup.destContainer=g.player:getInventory()
   g.queue.queue[#g.queue.queue+1]=pickup
   g.queue.queue[#g.queue.queue+1]=action('ISReadABook',item)
   local back=action('ISInventoryTransferAction',item);back.destContainer=g.resolved.frontSource
   g.queue.queue[#g.queue.queue+1]=back
  else g.queue.queue[#g.queue.queue+1]=action('ISReadABook',item)end
 end
 env.ISInventoryPaneContextMenu={onLiteratureItems=producer,readItem=function()end,onGrabItems=function(items)
  g.grabbed=true
  for _,item in ipairs(items)do
   local transfer=action('ISInventoryTransferAction',item);transfer.toolkitQueueOperation=1
   transfer.canMergeAction=function()return true end
   g.queue.queue[#g.queue.queue+1]=transfer
  end
 end}
 env.isItemTransactionDone=function()return false end;env.isItemTransactionRejected=function()return false end
 env.PZSurvivorToolkit={
  ActionQueuePickupFailure={nativeRequestState=function()return false end},
  ActionQueueSettlement={nativeRequestState=function()return false end},
  ActionQueuePolicy={matchesNative=function()return true end},
  ActionQueueExecution={blockedReturns=function()return{}end},
  ActionQueueLifecycle={registerObserver=function()return true end},
  ActionQueueOperations={run=function(fn,...)return fn(...)end},
 }
 env.queuePeersGrabOriginal=function()return env.ISInventoryPaneContextMenu.onGrabItems end
 env.queuePeersGrabOriginState=function()return{}end
 env.queuePeersArmPartialClient=function()return true end
 env.queuePeersPartialState=function()return{failure='',closed='',expired=true}end
 g.modules['PZSurvivorToolkit/SourceProof']={closure=function()return true end}
 local resolve=g.F.resolve
 g.F.resolve=function(...)
  if g.delayResolve then return end
  g.resolved=resolve(...);return g.resolved
 end
 g.load('queue-transfer-peers/client/ZZQueueTransferPeers.lua')
 function g.respond(command,args)g.reply(g.F.module,command,copy(args))end
 function g.hasCommand(command)for _,entry in ipairs(g.commands)do if entry.command==command then return entry end end end
 function g.boot()g.start();g.tick()end
 function g.place()
  g.respond('Layout',g.layout);g.tick();g.now=g.now+500;g.tick()
  g.tick();g.now=g.now+500;g.tick()
 end
 return g
end

-- The owning client proves actual centered arrival before Placed; replicated
-- identities may arrive later, and Seeded must never teleport it again.
f=clientFixture();f.boot()
assert(f.hasCommand('Hello').row.case=='disjoint-returns'and f.hasCommand('Hello').row.index==1,'Hello lost selected phase arguments')
local teleports=f.teleports;local mutations=f.mutations
f.respond('Layout',f.layout);f.tick()
assert(not f.hasCommand('Placed')and f.produced==0 and f.mutations==mutations)
f.now=f.now+500;f.tick()
assert(f.teleports==teleports+1 and not f.hasCommand('Placed'),'client claimed arrival at teleport dispatch')
f.player.currentMissing=true;f.now=f.now+500;f.tick();assert(not f.hasCommand('Placed'),'missing current square acquired proof')
f.player.currentMissing=false;f.tick();f.now=f.now+500;f.tick()
assert(f.hasCommand('Placed')and f.has('CLIENT_PLACEMENT')and f.produced==0)
teleports=f.teleports;f.delayResolve=true;f.respond('Seeded',f.ids);f.tick()
assert(not f.hasCommand('Ready')and f.teleports==teleports,'seed response moved actor or bypassed delayed replica')
f.delayResolve=false;f.tick();assert(f.hasCommand('Ready')and f.has('CLIENT_READY')and f.produced==0)
f.respond('Go',{case=f.ids.case,index=1,token=f.ids.token})
assert(f.has('ADMITTED')and f.produced==2 and f.teleports==teleports,'native producer admission missing or moved actor')
assert(not f.has('FAIL'))

-- Terminal evidence survives until replica absence, then Released is sent
-- exactly once; the next phase cannot be locally admitted prematurely.
f.queue.queue={};f.queue.current=nil;f.tick();f.now=f.now+1500;f.tick()
assert(f.hasCommand('Result'),'native drain failed to produce terminal result')
f.respond('Released',{case=f.ids.case,index=1,token=f.ids.token});f.tick()
assert(not f.hasCommand('Released'),'release ack raced owned replica removal')
f.server=true;f.F.release(f.authority);f.server=false;f.tick()
assert(f.hasCommand('Released')and f.has('CLIENT_CLEARED'),'replica absence failed to acknowledge release')
local commands=#f.commands;f.tick();assert(#f.commands==commands,'release acknowledgement duplicated')

for _,fault in ipairs({'drift-before-seeded','drift-before-go','seeded-target','seeded-token','go-token','go-case','go-index','layout-role-target','duplicate-layout'})do
 local g=clientFixture();g.boot()
 if fault=='layout-role-target'then g.layout.targets.client1=g.layout.targets.client2 end
 g.place()
 if fault=='duplicate-layout'then g.respond('Layout',g.layout)
 elseif fault=='layout-role-target'then -- Layout validation must have failed already.
 else
  if fault=='drift-before-seeded'then g.player.x=g.player.x+.3
  elseif fault=='seeded-target'then g.ids.placement.client1=g.layout.targets.client2
  elseif fault=='seeded-token'then g.ids.token='other'end
  g.respond('Seeded',g.ids);g.tick()
  if fault=='drift-before-go'then g.player.x=g.player.x+.3 end
  if fault=='drift-before-go'or fault:match('^go%-')then
   g.respond('Go',{case=fault=='go-case'and'other'or g.ids.case,index=fault=='go-index'and 2 or 1,token=fault=='go-token'and'old'or g.ids.token})
  end
 end
 assert(g.has('FAIL')and g.produced==0,'client admitted '..fault)
end

for _,fault in ipairs({'token','case','index'})do
 local g=clientFixture();g.boot();g.place();g.respond('Seeded',g.ids);g.tick()
 g.respond('Go',{case=g.ids.case,index=1,token=g.ids.token})
 g.queue.queue={};g.queue.current=nil;g.tick();g.now=g.now+1500;g.tick()
 assert(g.hasCommand('Result'))
 g.respond('Released',{case=fault=='case'and'other'or g.ids.case,index=fault=='index'and 2 or 1,token=fault=='token'and'old'or g.ids.token})
 assert(g.has('FAIL')and not g.hasCommand('Released'),'client accepted foreign release '..fault)
end

-- Preserve the intentionally scheduled native step in partial-accepted.
f=clientFixture('partial-accepted');f.boot();f.place();f.respond('Seeded',f.ids);f.tick()
local walks=0
local Walk={start=function()end,update=function()end,perform=function()end}
function Walk:setOnComplete(fn,...)
 assert(not self.onCompleteFunc,'native walk completion callback replaced')
 self.onCompleteFunc,self.onCompleteArgs=fn,{...}
end
function Walk:new(player,square)
 walks=walks+1
 assert(player==f.player and square:getX()==f.ids.origin.x-1 and square:getY()==f.ids.origin.y and square:getZ()==f.ids.origin.z,'partial walk must use vacant west tile')
 assert(square:isFree(true),'partial walk entered an occupied actor target')
 local source=f.resolved.frontSource:getItems():get(0):getContainer()
 local sourceSquare=f.authority.objects.source1:getSquare()
 local dx,dy=square:getX()-sourceSquare:getX(),square:getY()-sourceSquare:getY()
 assert(math.sqrt(dx*dx+dy*dy)<2 and source==f.resolved.frontSource,'partial walk lost native source adjacency')
 local action=setmetatable({Type='ISWalkToTimedAction',character=player,location=square},{__index=self})
 f.walk=action;return action
end
f.env.ISWalkToTimedAction=Walk;f.env.BehaviorResult={Succeeded='Succeeded'}
f.respond('Go',{case=f.ids.case,index=1,token=f.ids.token})
assert(not f.has('FAIL')and f.has('ADMITTED')and walks==1 and f.grabbed and #f.queue.queue==3,
 f.has('FAIL')and f.has('FAIL').row.error or'native partial walk/grouped producer changed')
assert(not f.has('NATIVE_WALK'),'walk receipt preceded native completion')
local walk=f.walk;local target=point(walk.location:getX(),walk.location:getY(),walk.location:getZ())
f.arrive('client1',target);walk.result=f.env.BehaviorResult.Succeeded
assert(type(walk.onCompleteFunc)=='function','native walk completion was not observed')
walk.onCompleteFunc(unpack(walk.onCompleteArgs))
local receipt=assert(f.has('NATIVE_WALK'),'native walk completion receipt missing').row
assert(receipt.case==f.ids.case and receipt.index==1 and receipt.token==f.ids.token and receipt.role=='client1'
 and receipt.sourceBound==true and f.F.same(receipt.target,target)and f.F.same(receipt.actual.currentSquare,target),'native walk receipt lost exact phase/arrival')

print('queue-transfer-peers placement regressions passed')
