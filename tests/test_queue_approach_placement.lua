-- Exercise the real placement state machine and approach RPC/setup entry points.
local root=ProjectRoot..'/tests/native_queue/'
local function same(a,b)return a.x==b.x and a.y==b.y and a.z==b.z end
local function fixture(kind,selection)
 local server,client=kind=='server',kind=='mp'
 local f={now=0,x=100.5,y=100.5,z=0,teleports=0,positionWrites=0,mutations=0,gear=0,pages=0,
  messages={},events={},rows={},logs={},emitted={},squares={},inventory={},queue={},cursors=0}
 local function list(rows)return {size=function()return #rows end,get=function(_,i)return rows[i+1]end}end
 local function sprite(name)return {getName=function()return name end,getProperties=function()return {has=function()return true end}end}end
 local function object(name)
  local data={};return {getModData=function()return data end,getSprite=function()return sprite(name)end,
   transmitCompleteItemToClients=function()f.mutations=f.mutations+1 end}
 end
 local function square(x,y,z)
  local key=x..','..y..','..z;if f.squares[key]then return f.squares[key]end
  local floor=object('floor');local rows={floor};local sq={}
  function sq:getX()return x end;function sq:getY()return y end;function sq:getZ()return z end
  function sq:getFloor()if not self.missingFloor then return floor end end
  function sq:TreatAsSolidFloor()return not self.missingFloor end
  function sq:getRoom()return self.room end
  function sq:isVehicleIntersecting()return self.vehicle or false end
  function sq:isFree()
   self.freeCalls=(self.freeCalls or 0)+1
   return not self.blocked and not(self.blockAfter and self.freeCalls>self.blockAfter)
  end
  function sq:decorate()rows[#rows+1]=object('decoration')end
  function sq:getObjects()return list(rows)end
  function sq:getWorldObjects()return list({})end
  function sq:transmitRemoveItemFromSquare(value)
   f.mutations=f.mutations+1;for i=#rows,1,-1 do if rows[i]==value then table.remove(rows,i)end end
  end
  function sq:RecalcAllWithNeighbours()f.mutations=f.mutations+1 end
  function sq:AddTileObject(value)f.mutations=f.mutations+1;rows[#rows+1]=value end
  f.squares[key]=sq;return sq
 end
 f.square=square(100,100,0);f.current=f.square;f.grid=square
 local inventory={}
 function inventory:AddItem(name)
  f.mutations=f.mutations+1;local item={id=#f.inventory+1,name=name,read=0}
  function item:getID()return self.id end;function item:getFullType()return self.name end
  function item:getNumberOfPages()return 100 end;function item:getAlreadyReadPages()return self.read end
  function item:setAlreadyReadPages(value)f.pages=f.pages+1;self.read=value end
  function item:getContainer()return inventory end
  f.inventory[#f.inventory+1]=item;return item
 end
 function inventory:getItemById(id)for _,item in ipairs(f.inventory)do if item.id==id then return item end end end
 function inventory:getItems()return list(f.inventory)end
 local p={};f.player=p
 for _,key in ipairs({'X','Y','Z'})do p['get'..key]=function()return f[key:lower()]end end
 for _,key in ipairs({'X','Y','Z','NextX','NextY','LastX','LastY'})do p['set'..key]=function(_,value)
  f.positionWrites=f.positionWrites+1;if key=='X'or key=='Y'or key=='Z'then f[key:lower()]=value end
 end end
 for _,key in ipairs({'ensureOnTile','setCurrentSquareFromPosition','setMovingSquareNow'})do p[key]=function()
  f.positionWrites=f.positionWrites+1
  if not f.staleSquares then f.square=square(math.floor(f.x),math.floor(f.y),math.floor(f.z));f.current=f.square end
 end end
 function p:getSquare()return f.square end;function p:getCurrentSquare()return f.current end
 function p:isLocalPlayer()return not server end;function p:getUsername()return f.username or 'client1'end
 function p:getOnlineID()return 1 end;function p:hasTimedActions()return false end
 function p:isPlayerMoving()return false end;function p:getPath2()end;function p:getDeferredMovement(out)return out end
 function p:isTimedActionInstant()return false end;function p:pressedMovement()return false end;function p:pressedCancelAction()return false end
 function p:getCharacterActions()return list({})end;function p:getInventory()return inventory end
 function p:setPrimaryHandItem()f.gear=f.gear+1 end
 function p:setAlreadyReadPages(_,value)f.pages=f.pages+1;f.characterPages=value end
 function p:getAlreadyReadPages()return f.characterPages or 0 end
 for _,key in ipairs({'setGodMod','setGhostMode','setAutoDrink'})do p[key]=function()end end
 function p:teleportTo(x,y,z)f.teleports=f.teleports+1;f.target={x=x,y=y,z=z}end
 function f:arrive(target,offset)
  self.x,self.y,self.z=target.x+(offset or .5),target.y+(offset or .5),target.z
  self.square=square(target.x,target.y,target.z);self.current=self.square
 end
 local function event(name)return {Add=function(fn)f[name]=fn end}end
 local env={Events={OnClientCommand=event('command'),OnServerCommand=event('serverCommand'),OnTick=event('tick')}}
 env.getTimestampMs=function()return f.now end;env.isServer=function()return server end;env.isClient=function()return client end
 env.getCell=function()return {getGridSquare=function(_,x,y,z)return square(x,y,z)end}end
 env.getPlayer=function()return p end;env.isIngameState=function()return true end
 env.Vector2={new=function()return {getX=function()return 0 end,getY=function()return 0 end}end}
 env.ISTimedActionQueue={getTimedActionQueue=function()return {queue=f.queue,indexOf=function()return -1 end}end,add=function()end}
 env.ISRemoveBush={};env.ISRemoveGrass={};env.ISWalkToTimedAction={};env.ISReadABook={}
 env.ISRemovePlantCursor={new=function()return {isValid=function()return true end,tryBuild=function()f.cursors=f.cursors+1 end}end}
 env.ISBuildMenu={cheat=false};env.IsoFlagType={canBeCut='cut',canBeRemoved='grass'};env.getSprite=sprite
 env.IsoObject={new=function(_,_,name)return object(name)end};env.sendAddItemToContainer=function()end
 env.getCore=function()return {setOptionPauseOnFocusloss=function()end,setOptionAutoDrink=function()end}end
 env.PZAPI={ModOptions={getOptions=function()return {getOption=function()return {setValue=function()end}end}end}}
 env.PZSurvivorToolkit={Settings={actionQueue=function()return true end}}
 env.print=function(value)
  f.logs[#f.logs+1]=value;local name=value:match('^%[QUEUE_APPROACH%] (%S+) ')
  if name then f.events[#f.events+1]={name=name,value=f.rows[#f.rows],mutations=f.mutations}end
 end
 env.sendClientCommand=function(_,command,args)f.messages[#f.messages+1]={command=command,value=args}end
 env.sendServerCommand=function(_,_,command,args)f.messages[#f.messages+1]={command=command,value=args}end
 setmetatable(env,{__index=function(_,key)if key~='next'then return _G[key]end end});f.env=env
 local function load(path)local chunk=assert(loadfile(root..path));setfenv(chunk,env);return chunk()end
 f.P=load('support/QueueEnergyPlacement.lua')
 local config={cases={'bush','manual-grass'},mode='toolkit',kind=client and'mp'or'sp',disposable=true}
 for key,value in pairs(selection or{})do config[key]=value end
 local modules={QueueEnergyPlacement=f.P,QueueTestSelection=config,
  QueueHealthEvents={encode=function(value)f.rows[#f.rows+1]=value;return '{}'end,emit=function(value)f.emitted[#f.emitted+1]=value end},
  QueuePreflight={onGameStart=function(_,fn)f.start=fn end,onTick=function(_,fn)f.tick=fn end}}
 env.require=function(name)return modules[name]or{}end
 f.F=load('approach-queue/shared/QueueApproach.lua');modules.QueueApproach=f.F
 local prepare,resolve=f.F.prepare,f.F.resolve
 function f.F.prepare(...)local value=prepare(...);f.prepared=value;return value end
 function f.F.resolve(...)f.resolves=(f.resolves or 0)+1;return resolve(...)end
 load(server and'approach-queue/server/ZZQueueApproachServer.lua'or'approach-queue/client/ZZQueueApproach.lua')
 return f
end
local function event(f,name)
 for _,value in ipairs(f.events)do if value.name==name then return value end end
end
local function exact(value,names)
 local expected={};for _,name in ipairs(names)do expected[name]=true end
 local count=0;for key in pairs(value)do assert(expected[key],'unexpected field '..key);count=count+1 end
 assert(count==#names)
end
local function proof(target,mode)
 local count=mode=='replica'and 0 or 1
 return {mode=mode or'local',target=target,centered=true,centers=count,teleports=count}
end
local function command(f,name,args)f.command('QueueApproachTest',name,f.player,args or{case='bush'})end
local function reserve(f)
 command(f,'Layout');local value=f.messages[#f.messages];assert(value.command=='Layout');return value.value.target
end
local function prepareRequest(f,target,value)
 command(f,'Prepare',{case='bush',target=target,clientPlacement=value or proof(target)})
end
local function failed(f)
 assert(not f.prepared and f.mutations==0 and f.teleports==0 and f.positionWrites==0)
 assert(f.messages[#f.messages].command=='Failed')
end
-- Planning is a read-only search. A loaded but invalid far end of the first
-- strip makes the real planner select another complete outdoor strip.
for _,case in ipairs({'bush','manual-grass'})do
 local f=fixture('sp');local start=f.P.choose(f.player)
 f.grid(start.x+8,start.y,start.z).missingFloor=true
 local layout=f.F.plan(f.player,case)
 exact(layout,{'case','target'});assert(layout.case==case and not same(layout.target,start))
 assert(f.mutations==0 and f.teleports==0 and f.positionWrites==0 and f.gear==0 and f.pages==0)
end
local blocked=fixture('sp');local initial=blocked.P.choose(blocked.player)
local standing=blocked.grid(initial.x,initial.y,initial.z);standing.freeCalls=0;standing.blockAfter=1
local alternate=blocked.F.plan(blocked.player,'bush')
assert(not same(initial,alternate.target)and blocked.mutations==0 and blocked.positionWrites==0 and blocked.teleports==0)
-- Shared setup guards run before strip edits, inventory or equipment changes.
for _,kind in ipairs({'sp','server'})do for _,bad in ipairs({'proof','role','count','target','stale','footprint'})do
 local f=fixture(kind);local target=f.F.plan(f.player,'bush').target;f:arrive(target);f.grid(target.x,target.y,target.z):decorate()
 local value=proof(target,kind=='server'and'replica'or'local')
 if bad=='proof'then value={}
 elseif bad=='role'then value.mode=kind=='server'and'local'or'replica'
 elseif bad=='count'then value.centers=2
 elseif bad=='target'then value.target={x=target.x+1,y=target.y,z=target.z}
 elseif bad=='stale'then f.x=target.x
 else f.grid(target.x+8,target.y,target.z).missingFloor=true end
 assert(not pcall(f.F.prepare,f.player,'bush','toolkit',target,value))
 assert(f.mutations==0 and f.gear==0 and f.pages==0 and f.positionWrites==0)
end end
for _,kind in ipairs({'sp','server'})do for _,case in ipairs({'bush','manual-grass'})do
 local f=fixture(kind);local target=f.F.plan(f.player,case).target;f:arrive(target);f.grid(target.x,target.y,target.z):decorate()
 local state=f.F.prepare(f.player,case,'toolkit',target,proof(target,kind=='server'and'replica'or'local'))
 assert(same(state.ids.origin,target)and same(state.ids.placement,target))
 local authority=assert(event(f,'AUTHORITY_PLACEMENT'));assert(authority.mutations==0)
 exact(authority.value,{'case','actor','target','proof'});assert(authority.value.actor=='client1')
 assert(f.mutations>0 and f.positionWrites==0 and f.teleports==0)
 local gear,pages=f.gear,f.pages;f.x=target.x
 local resolved,why=f.F.resolve(f.player,state.ids)
 assert(not resolved and why.reason=='centered placement differs'and f.gear==gear and f.pages==pages and f.positionWrites==0)
 f:arrive(target);state.ids.origin={x=target.x+1,y=target.y,z=target.z}
 assert(not pcall(f.F.resolve,f.player,state.ids)and f.gear==gear and f.pages==pages and f.positionWrites==0)
end end
-- Authority Layout waits for loaded origin without positioning the replica.
local f=fixture('server');f.current=nil;command(f,'Layout');assert(#f.messages==0)
f.now=1000;f.tick();assert(#f.messages==0 and f.mutations==0)
f.current=f.square;f.tick();assert(f.messages[1].command=='Layout')
local target=f.messages[1].value.target;local layoutEvent=assert(event(f,'LAYOUT'))
exact(layoutEvent.value,{'case','actor','target'});assert(layoutEvent.value.actor=='client1'and same(layoutEvent.value.target,target))
f.grid(target.x,target.y,target.z):decorate()
prepareRequest(f,target);f.tick();f.now=1500;f.tick();assert(not f.prepared and f.mutations==0)
f:arrive(target);f.current=nil;f.now=1501;f.tick();assert(not f.prepared)
f.current=f.square;f.now=1502;f.tick();f.now=2001;f.tick();assert(not f.prepared)
f.now=2002;f.tick();assert(f.prepared and f.messages[#f.messages].command=='Prepared')
assert(f.teleports==0 and f.positionWrites==0 and event(f,'AUTHORITY_PLACEMENT').value.proof.centers==0)
f.now=2502;f.tick();assert(f.teleports==0 and f.positionWrites==0)
-- Layout reservation and pending arrival reject all overlapping setup/work.
for _,stage in ipairs({'loading','layout','arrival'})do for _,name in ipairs({'Layout','Prepare','Baseline','Snapshot','Verify','Unknown'})do
 if stage~='layout'or name~='Prepare'then
 f=fixture('server');if stage=='loading'then f.current=nil;command(f,'Layout')else target=reserve(f);if stage=='arrival'then prepareRequest(f,target)end end
 command(f,name,{case='bush',target=target,clientPlacement=proof(target)})
 failed(f);f.now=1000;f.tick();assert(not f.prepared and f.mutations==0)
 end
end end
for _,stage in ipairs({'loading','arrival'})do
 f=fixture('server');if stage=='loading'then f.current=nil;command(f,'Layout')else target=reserve(f);prepareRequest(f,target)end
 f.tick();f.now=30000;f.tick();failed(f)
end
f=fixture('server');prepareRequest(f,{x=98,y=98,z=0});failed(f)
f=fixture('server');target=reserve(f);prepareRequest(f,{x=target.x+1,y=target.y,z=target.z});failed(f)
for _,bad in ipairs({'missing','role','count','corner','target','actor','case'})do
 f=fixture('server');target=reserve(f);local value=proof(target)
 if bad=='missing'then value={}elseif bad=='role'then value.mode='replica'
 elseif bad=='count'then value.centers=0 elseif bad=='corner'then value.centered=false
 elseif bad=='target'then value.target={x=target.x+1,y=target.y,z=target.z}
 elseif bad=='actor'then f.username='client2'end
 command(f,'Prepare',{case=bad=='case'and'manual-grass'or'bush',target=target,clientPlacement=value});failed(f)
end
-- The actual client requests Layout first, then waits for centered local proof.
local function localReady(kind)
 local f=fixture(kind);f.staleSquares=true;f.start();f.tick()
 if kind=='mp'then
  assert(#f.messages==1 and f.messages[1].command=='Layout'and f.teleports==0)
  f.now=1000;f.tick();assert(f.teleports==0 and not f.prepared)
  local authority=fixture('server');local planned=authority.F.plan(authority.player,'bush')
  f.serverCommand('QueueApproachTest','Layout',planned)
 end
 f.tick();local began=f.now;assert(f.teleports==0)
 f.now=began+500;f.tick();assert(f.teleports==1 and not f.prepared)
 f.now=began+1000;f.tick();assert(not f.prepared)
 f:arrive(f.target);f.now=began+1001;f.tick();f.now=began+1500;f.tick();assert(not f.prepared)
 f.now=began+1501;f.tick()
 local e=assert(event(f,'CLIENT_PLACEMENT'));exact(e.value,{'case','actor','target','proof'})
 assert(e.value.actor=='client1'and e.value.proof.centered and e.value.proof.centers==1 and same(e.value.target,f.target))
 if kind=='mp'then
  local request=f.messages[#f.messages];assert(request.command=='Prepare');exact(request.value,{'case','target','clientPlacement'})
  assert(request.value.clientPlacement==e.value.proof and same(request.value.target,f.target)and not f.prepared)
  -- Replicated scene contents may arrive independently of the server message.
  local authority=fixture('server');authority:arrive(f.target)
  local state=authority.F.prepare(authority.player,'bush','toolkit',f.target,proof(f.target,'replica'))
  -- Build the replicated fixture through the real shared setup in this isolated
  -- world, while retaining client=true for all actual client-script execution.
  local old=f.env.isClient;f.env.isClient=function()return false end
  f.prepared=f.F.prepare(f.player,'bush','toolkit',f.target,e.value.proof);f.env.isClient=old
  f.serverCommand('QueueApproachTest','Prepared',state.ids)
 else assert(f.prepared)end
 return f
end
for _,kind in ipairs({'sp','mp'})do
 f=localReady(kind);local writes=f.positionWrites
 f.now=f.now+1;f.tick();assert(f.resolves==1 and f.cursors==0)
 if kind=='mp'then assert(f.messages[#f.messages].command=='Baseline');f.serverCommand('QueueApproachTest','Baselined',f.F.baseline(f.prepared))end
 f.now=f.now+1;f.tick();assert(f.cursors==1 and event(f,'ADMITTED')and f.positionWrites==writes and f.teleports==1)
end
-- Fresh guards precede replica gear/page writes and native cursor admission.
for _,kind in ipairs({'sp','mp'})do for _,stage in ipairs({'resolve','admit'})do for _,bad in ipairs({'drift','binding'})do
 f=localReady(kind);local writes=f.positionWrites
 if stage=='admit'then
  f.now=f.now+1;f.tick();assert(f.resolves==1)
  if kind=='mp'then f.serverCommand('QueueApproachTest','Baselined',f.F.baseline(f.prepared))end
 end
 local gear,pages=f.gear,f.pages
 if bad=='drift'then f.x=f.target.x else f.prepared.ids.placement={x=f.target.x+1,y=f.target.y,z=f.target.z}end
 -- MP Prepared receives a separate server table; mutate the received binding too.
 if kind=='mp'and bad=='binding'then
  local ids={};for key,value in pairs(f.prepared.ids)do ids[key]=value end
  f.serverCommand('QueueApproachTest','Prepared',ids)
 end
 f.now=f.now+1;f.tick();local last=f.emitted[#f.emitted]
 assert(last and last.status=='failed'and f.cursors==0 and not event(f,'ADMITTED'))
 assert(f.positionWrites==writes and f.teleports==1 and f.gear==gear and f.pages==pages)
 if stage=='resolve'then assert(not f.resolves)end
end end end
-- Queue-off native completion preserves the independent reader tail. The Host
-- authority must observe its complete item and character pages, just as SP does.
for _,case in ipairs({'bush','manual-grass'})do
 local host=fixture('server',{mode='native',kind='mp'})
 local target=host.F.plan(host.player,case).target;host:arrive(target)
 local state=host.F.prepare(host.player,case,'native',target,proof(target,'replica'))
 assert(host.F.baseline(state),'Host native initial scene must establish its baseline')
 local id=state.ids.targets.second;local sq=host.grid(id.x,id.y,id.z)
 local removed=false
 for i=sq:getObjects():size()-1,0,-1 do
  local object=sq:getObjects():get(i)
  if object:getModData().queueApproachIdentity==id.marker then sq:transmitRemoveItemFromSquare(object);removed=true end
 end
 assert(removed,'native second target must be removed independently of the reader')
 local function observe(itemPages,characterPages,complete)
  state.book:setAlreadyReadPages(itemPages);host.player:setAlreadyReadPages(state.ids.book.type,characterPages)
  local mutations,gear,pages,writes,teleports=host.mutations,host.gear,host.pages,host.positionWrites,host.teleports
  local receipt,waiting=host.F.verify(state);local actual=receipt or waiting
  assert((receipt~=nil)==complete,'Host native completion must require both full reader page witnesses')
  assert(#actual.targets.first.objects==1 and #actual.targets.second.objects==0,
   'reader verification must retain the exact native vegetation outcome')
  assert(actual.book.pages==itemPages and actual.book.characterPages==characterPages and actual.book.root)
  assert(host.mutations==mutations and host.gear==gear and host.pages==pages
   and host.positionWrites==writes and host.teleports==teleports,'verification must only observe native completion')
 end
 local initial,full=state.ids.book.initial,state.ids.book.pages
 observe(initial,initial,false)
 observe(initial-1,initial-1,false)
 observe(full,initial,false)
 observe(initial,full,false)
 observe(full,full,true)
end
print('QUEUE_APPROACH_PLACEMENT_PASS')
