-- Exercise real fixture setup control flow; native placement and action bodies are doubles.
local root=assert(ProjectRoot)
local function point(x,y,z)return {x=x,y=y,z=z}end
local function same(a,b)return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
local function fixture(role,kind,peers,mode)
 local state={logs={},commands={},responses={},history={},seeds=0,plans=0,prepares=0,begins=0,observes=0,teleports=0,
  localSettled=false,replicaSettled=false,freezeActual=false,mode=mode or 'toolkit'}
 local case=peers and 'peer-cancel'or'repair'
 local config={kind=kind,mode=state.mode,suite=peers and'engine-peers'or'engine',cases={case}}
 local layout={case=case,target=point(10,20,0),generator=point(11,20,0)}
 local values,items={},{}
 local player={point=point(1,2,0),loaded=true}
 function player:getUsername()return 'client1'end
 function player:getOnlineID()return 1 end
 function player:isDead()return false end
 function player:getSquare()return self.loaded and {}or nil end
 function player:getCurrentSquare()return self:getSquare()end
 function player:setGhostMode()end
 function player:isTimedActionInstant()return false end
 function player:setAlreadyReadPages()end
 function player:hasTimedActions()return false end
 function player:teleportTo(x,y,z)
  assert(state.seeds==0,'teleport occurred after fixture seeding')
  state.teleports=state.teleports+1;self.point=point(x,y,z)
 end
 local inventory={getItemById=function(_,id)return items[id]end,getItems=function()return list(values)end}
 function player:getInventory()return inventory end
 local generator={getCondition=function()return 94 end,isActivated=function()return false end,getObjectIndex=function()return 1 end}
 local square={getSpecialObjects=function()return list({generator})end}
 local queue={queue={}}
 local eventNames={'OnGameStart','OnTick','OnServerCommand','OnClientCommand'}
 local events={}
 for _,name in ipairs(eventNames)do
  local handlers={}
  events[name]={Add=function(fn)handlers[#handlers+1]=fn end,fire=function(...)for _,fn in ipairs(handlers)do fn(...)end end}
 end
 local P={}
 function P.target(target)
  assert(type(target)=='table','target absent')
  for _,axis in ipairs({'x','y','z'})do assert(type(target[axis])=='number'and target[axis]%1==0,'target not integer')end
  return point(target.x,target.y,target.z)
 end
 function P.at(actor,target)return same(actor.point,target)end
 function P.begin(actor,target)
  assert(role=='client'and actor==player,'placement began on a remote actor')
  state.begins=state.begins+1;state.history[#state.history+1]='begin'
  return {mode='local',player=actor,target=P.target(target)}
 end
 function P.observe(actor,target)
  assert(role=='server','client attempted replica placement')
  state.observes=state.observes+1;state.history[#state.history+1]='observe'
  return {mode='replica',player=actor,target=P.target(target)}
 end
 function P.poll(pending)
  local settled=pending.mode=='local'and state.localSettled or pending.mode=='replica'and state.replicaSettled
  if not settled then return end
  if not pending.result then
   if pending.mode=='local'and not state.freezeActual then pending.player:teleportTo(pending.target.x,pending.target.y,pending.target.z)end
   pending.result={mode=pending.mode,target=P.target(pending.target)}
   state.history[#state.history+1]='settled-'..pending.mode
  end
  return pending.result
 end
 local function seed()
  state.seeds=state.seeds+1
  local book={getNumberOfPages=function()return 10 end,setAlreadyReadPages=function()end,getFullType=function()return'Base.BookCarpentry1'end}
  items[3]=book;values={}
  for i=1,2 do
   items[i]={getFullType=function()return'Base.ElectronicsScrap'end};values[#values+1]=items[i]
  end
  return {case=case,x=layout.generator.x,y=layout.generator.y,z=layout.generator.z,
   objectIndex=1,scraps={1,2},tail=3,placement=P.target(layout.target)}
 end
 local authority={cancels=function()return peers end}
 function authority.plan(actor,requested)
  assert(requested==case and actor==player)
  state.plans=state.plans+1;state.history[#state.history+1]='plan';return layout
 end
 function authority.prepare(actor,requested,target,proof)
  assert(actor==player and requested==case and same(target,layout.target),'prepared reservation target differs')
  assert(P.at(actor,target),'authority received stale actor arrival')
  assert(proof.mode==(role=='server'and'replica'or'local')and same(proof.target,target),'authority proof role/target differs')
  state.prepares=state.prepares+1;state.preparedProof=proof;state.history[#state.history+1]='prepare'
  return seed()
 end
 local serial=0
 local function action(kind,item)
  serial=serial+1
  return {Type=kind,item=item,toolkitQueueOperation=serial,minutesPerPage=2,maxTime=10,
   getDuration=function()return 150 end,isStarted=function()return false end}
 end
 local env=setmetatable({Events=events,ISTimedActionQueue={queues={[player]=queue},
  getTimedActionQueue=function()return queue end,
  add=function(value)state.history[#state.history+1]='enqueue';queue.queue[#queue.queue+1]=value;queue.current=queue.current or value end},
  ISFixGenerator={new=function()return action('ISFixGenerator')end},
  ISReadABook={new=function(_,actor,item)assert(actor==player);return action('ISReadABook',item)end},
  ISQueueActionsAction={new=function()return action('ISQueueActionsAction')end},
  PZSurvivorToolkit={Settings={actionQueue=function()return state.mode=='toolkit'end},
   ActionQueueLifecycle={begin=function()return state.mode=='toolkit'end,finish=function()end,flush=function()end}},
  getPlayer=function()return player end,getTimestampMs=function()return 100 end,isIngameState=function()return true end,
  isServer=function()return role=='server'end,isClient=function()return kind=='mp'and role=='client'end,
  getCore=function()return {setOptionPauseOnFocusloss=function()end}end,
  getCell=function()return {getGridSquare=function(_,x,y,z)
   assert(same(point(x,y,z),layout.generator),'client looked up a different generator tile');return square end}end,
  instanceof=function(value,name)return value==generator and name=='IsoGenerator'end,
  print=function(message)state.logs[#state.logs+1]=message end,
  sendClientCommand=function(module,command,args)assert(module=='EngineQueueTest');state.commands[#state.commands+1]={command=command,args=args}end,
  sendServerCommand=function(actor,module,command,args)assert(actor==player and module=='EngineQueueTest');state.responses[#state.responses+1]={command=command,args=args}end,
 },{__index=_G})
 env.require=function(name)
  if name=='QueueTestSelection'then return config end
  if name=='QueueEngineAuthority'then return authority end
  if name=='QueueEnergyPlacement'then return P end
  if name=='QueueHealthEvents'then return {encode=function(row)state.placementReceipt=row;return'{}'end}end
  if name=='QueuePreflight'then return {onGameStart=function(_,fn)events.OnGameStart.Add(fn)end,onTick=function(_,fn)events.OnTick.Add(fn)end}end
  assert(name=='PZSurvivorToolkit/ActionQueuePanel'or name:match('^TimedActions/'),name);return true
 end
 setfenv(assert(loadfile(root..'/tests/native_queue/engine/'..role..'/'..(role=='client'and'ZZEngine.lua'or'ZZEngineServer.lua'))),env)()
 function state.tick()events.OnTick.fire()end
 function state.start()events.OnGameStart.fire()end
 function state.reply(command,args)events.OnServerCommand.fire('EngineQueueTest',command,args)end
 function state.request(command,args)events.OnClientCommand.fire('EngineQueueTest',command,player,args)end
 function state.seed()return seed()end
 function state.failure()
  for _,message in ipairs(state.logs)do if message:find('[QUEUE_TEST] FAIL',1,true)then return message end end
 end
 state.player,state.layout,state.queue,state.case=player,layout,queue,case
 return state
end

for _,mode in ipairs({'native','toolkit'})do for _,kind in ipairs({'sp','mp'})do
 local s=fixture('client',kind,false,mode);s.start();s.tick()
 assert(s.seeds==0 and s.prepares==0 and #s.queue.queue==0,'Layout seeded or enqueued before arrival')
 if kind=='mp'then assert(s.commands[1].command=='Layout');s.reply('Layout',s.layout)
 else assert(s.plans==1)end
 for i=1,3 do s.tick()end
 assert(s.begins==1 and s.teleports==0 and s.prepares==0 and #s.commands==(kind=='mp'and 1 or 0),'pending local placement reached Prepare')
 s.localSettled=true;s.tick()
 assert(s.teleports==1 and s.placementReceipt and s.placementReceipt.target.x==s.layout.generator.x-1)
 if kind=='mp'then
  assert(s.commands[2].command=='Prepare'and same(s.commands[2].args.target,s.layout.target))
  assert(s.commands[2].args.clientPlacement==s.placementReceipt.proof and s.seeds==0)
  s.reply('Prepared',s.seed())
 else assert(s.prepares==1 and s.seeds==1)end
 s.tick()
 assert(#s.queue.queue==(mode=='toolkit'and 3 or 2)and s.teleports==1 and not s.failure(),s.failure())
 assert(s.history[#s.history]=='enqueue','native work was not enqueued after settled preparation')
end end

for _,fault in ipairs({'wrong-layout','stale-after-proof','left-after-seed','changed-prepared-target'})do
 local s=fixture('client','mp',false);s.start();s.tick()
 if fault=='wrong-layout'then s.layout.generator.x=s.layout.target.x+2 end
 s.reply('Layout',s.layout);s.localSettled=true;s.freezeActual=fault=='stale-after-proof';s.tick()
 if fault=='left-after-seed'or fault=='changed-prepared-target'then
  local ids=s.seed()
  if fault=='left-after-seed'then s.player.point=point(9,20,0)else ids.placement=point(9,20,0)end
  s.reply('Prepared',ids);s.tick()
 end
 assert(s.failure()and #s.queue.queue==0,'client accepted '..fault)
 if fault=='wrong-layout'or fault=='stale-after-proof'then assert(#s.commands==1 and s.seeds==0,'invalid arrival reached Prepare')end
end

local s=fixture('client','mp',true);s.start();s.tick();s.reply('Layout',s.layout);s.localSettled=true;s.tick()
s.reply('Prepared',s.seed());s.tick();s.tick()
assert(#s.queue.queue==0 and #s.commands==3 and s.commands[3].command=='Ready','peer enqueued before Ready barrier or duplicated Ready')
s.reply('Begin',{case=s.case});s.tick()
assert(#s.queue.queue==3 and s.teleports==1 and not s.failure(),s.failure())

s=fixture('server','mp',false);s.player.loaded=false;s.request('Layout',{case=s.case});s.tick()
assert(s.plans==0 and s.seeds==0 and #s.responses==0,'unloaded authority ran Layout')
s.player.loaded=true;s.tick()
assert(s.plans==1 and s.prepares==0 and s.seeds==0 and s.responses[1].command=='Layout','Layout did not remain side-effect free')
local proof={mode='local',target=point(10,20,0)}
s.request('Prepare',{case=s.case,target=point(10,20,0),clientPlacement=proof})
for i=1,3 do s.tick()end
assert(s.observes==1 and s.prepares==0 and s.seeds==0 and s.teleports==0 and #s.responses==1,'server seeded before replica settled')
s.player.point=point(10,20,0);s.replicaSettled=true;s.tick()
assert(s.prepares==1 and s.seeds==1 and s.preparedProof.mode=='replica'and s.teleports==0 and #s.responses==2 and not s.failure(),s.failure())
s.tick();assert(s.prepares==1,'completed authority placement prepared twice')

for _,fault in ipairs({'stale-replica','mismatched-client-target','missing-client-proof','foreign-proof-role','invalid-target','overlapping-prepare'})do
 s=fixture('server','mp',false)
 local args={case=s.case,target=point(10,20,0),clientPlacement={mode='local',target=point(10,20,0)}}
 if fault=='mismatched-client-target'then args.clientPlacement.target.x=9 end
 if fault=='missing-client-proof'then args.clientPlacement=nil end
 if fault=='foreign-proof-role'then args.clientPlacement.mode='replica'end
 if fault=='invalid-target'then args.target.x='10'end
 s.request('Prepare',args)
 if fault=='overlapping-prepare'then s.request('Prepare',args)end
 s.replicaSettled=true;s.tick()
 assert(s.failure()and s.prepares==0 and s.seeds==0 and s.teleports==0,'server accepted '..fault)
 assert(s.responses[#s.responses].args.ok==false,'server rejection did not reach the owning client')
 if fault~='stale-replica'and fault~='overlapping-prepare'then assert(s.observes==0,'invalid request began authority arrival')end
end
print('Engine placement setup checks passed: local/replica gates, stale-target rejection, final standing tile, no seeded teleport and peer Ready barrier.')
