local root=assert(ProjectRoot)
local config,inventory,player,generator,squares,sequence
local arrived,proofMode=true,'local'
Perks={Electricity='Electricity'}
local function list(values)
 return {size=function() return #values end,get=function(_,i) return values[i+1] end}
end
local function seed(kind)
 sequence=sequence+1
 local item={id=sequence,kind=kind,read=0,pages=10}
 function item:getID() return self.id end
 function item:getFullType() return self.kind end
 function item:setCondition(value) self.condition=value end
 function item:setAlreadyReadPages(value) self.read=value end
 function item:getAlreadyReadPages() return self.read end
 function item:getNumberOfPages() return self.pages end
 return item
end
local function fixture(mode,kind,cases)
 config={mode=mode,kind=kind,cases=cases,suite='engine'};sequence=0;squares={};arrived=true;proofMode=kind=='mp'and'replica'or'local'
 inventory={values={}}
 function inventory:getItems() return list(self.values) end
 function inventory:AddItem(kind) local item=seed(kind);self.values[#self.values+1]=item;return item end
 function inventory:getItemById(id) for _,item in ipairs(self.values) do if item.id==id then return item end end end
 function inventory:Remove(item) for i,value in ipairs(self.values) do if value==item then table.remove(self.values,i);return end end end
 player={pages={},getUsername=function() return 'client1' end,getPerkLevel=function() return 0 end,
  getInventory=function() return inventory end,setAlreadyReadPages=function(self,kind,pages) self.pages[kind]=pages end}
 local function square(x,y,z)
  local key=x..','..y..','..z
  if squares[key] then return squares[key] end
  local s={x=x,y=y,z=z,objects={}}
  function s:isFree() return true end
  function s:getRoom() end
  function s:getSpecialObjects() return list(self.objects) end
  function s:getObjects() return list({1}) end
  function s:getX() return x end;function s:getY() return y end;function s:getZ() return z end
  function s:transmitRemoveItemFromSquare(object) assert(self.objects[1]==object);self.objects={};object.removed=true end
  squares[key]=s;return s
 end
 getCell=function() return {getGridSquare=function(_,x,y,z) return square(x,y,z) end} end
 require=function(name)
  if name=='QueueTestSelection' then return config end
  if name=='QueueHealthEvents'then return {encode=function()return '{}'end}end
  assert(name=='QueueEnergyPlacement',name)
  return {choose=function()return {x=0,y=0,z=0}end,target=function(value)
    assert(type(value)=='table'and type(value.x)=='number'and type(value.y)=='number'and type(value.z)=='number')
    return {x=value.x,y=value.y,z=value.z}
   end,at=function()return arrived end}

 end
 instanceItem=seed
 isServer=function() return kind=='mp' end
 sendAddItemToContainer=function() end;sendRemoveItemFromContainer=function() end
 IsoGenerator={new=function(_,_,s)
  local g={condition=94,square=s}
  function g:getObjectIndex() return self.removed and -1 or 1 end
  function g:getSquare() return not self.removed and self.square or nil end
  function g:getX() return s.x end;function g:getY() return s.y end;function g:getZ() return s.z end
  function g:setCondition(value) self.condition=value end
  function g:getCondition() return self.condition end
  s.objects[1]=g;generator=g;return g
 end}
 return assert(loadfile(root..'/tests/native_queue/engine/shared/QueueEngineAuthority.lua'))()
end
local function prepare(authority,actor,case)
 local layout=authority.plan(actor,case)
 return authority.prepare(actor,case,layout.target,{mode=proofMode,target=layout.target})
end
local function read(ids) local book=assert(inventory:getItemById(ids.tail));book.read=book.pages end
do
 local authority=fixture('toolkit','mp',{'repair'})
 config.suite='engine-peers'
 local first=authority.plan(player,'repair')
 assert(not generator and #inventory.values==0,'planning created generator or materials before arrival')
 local other={getUsername=function()return 'client2'end}
 local second=authority.plan(other,'repair')
 assert(second.target.x~=first.target.x and second.target.x~=first.generator.x
  and second.generator.x~=first.target.x and second.generator.x~=first.generator.x,
  'peer final standing/generator reservation overlaps')
 assert(not generator and #inventory.values==0,'peer reservation seeded before arrival')
 local proof={mode='replica',target=first.target}
 arrived=false
 assert(not pcall(authority.prepare,player,'repair',first.target,proof),'authority prepared before current arrival')
 arrived=true
 assert(not pcall(authority.prepare,player,'repair',{x=99,y=0,z=0},proof),'authority accepted unreserved standing target')
 assert(not pcall(authority.prepare,player,'repair',first.target,{mode='local',target=first.target}),'authority accepted client proof as replica')
 assert(not generator and #inventory.values==0,'refused placement caused native effects')
 local ids=authority.prepare(player,'repair',first.target,proof)
 assert(ids.placement.x==first.target.x and ids.x==first.generator.x,'prepared layout changed after arrival')
end
local authority=fixture('native','sp',{'repair'})
local unrelated=inventory:AddItem('Base.Apple')
local ids=prepare(authority,player,'repair')
inventory:Remove(inventory:getItemById(ids.scraps[2]));generator.condition=98;read(ids)
assert(not pcall(authority.verify,player,'repair'),'same scrap count hid consumption of the wrong exact item')

authority=fixture('native','sp',{'repair'})
unrelated=inventory:AddItem('Base.Apple');ids=prepare(authority,player,'repair')
inventory:Remove(inventory:getItemById(ids.scraps[1]));generator.condition=98;read(ids)
local result=authority.verify(player,'repair')
assert(result.scraps==1 and result.condition==98 and result.tailRead)
assert(inventory:getItemById(unrelated.id)==unrelated and not inventory:getItemById(ids.scraps[2]),'cleanup removed unrelated inventory or retained fixture scrap')

authority=fixture('toolkit','mp',{'missing-target','late-continuation'})
ids=prepare(authority,player,'missing-target')
assert(ids.blocker and inventory:getItemById(ids.blocker),'missing-target requires a real blocking reader')
local blockingBook=inventory:getItemById(ids.blocker)
assert(blockingBook.read==blockingBook.pages-1 and player.pages[blockingBook.kind]==blockingBook.pages-1,
 'server and client must start the native blocker on the same last unread page')
authority.invalidate(player,'missing-target')
assert(generator:getObjectIndex()==-1 and not pcall(authority.invalidate,player,'missing-target'),'duplicate target removal passed')
local retired=generator
assert(prepare(authority,player,'missing-target')==ids and generator==retired,'duplicate prepare resurrected a removed pending target')
assert(not pcall(authority.verify,player,'missing-target'),'unread Toolkit tail passed authority verification')
read(ids);assert(authority.verify(player,'missing-target').tailRead)
local removed=generator
ids=prepare(authority,player,'late-continuation')
assert(generator~=removed and generator.square==removed.square,'next case did not recreate only the removed owned generator')
read(ids);result=authority.verify(player,'late-continuation')
assert(result.condition==94 and result.scraps==2 and result.tailRead)

authority=fixture('native','mp',{'cancel'})
ids=prepare(authority,player,'cancel');result=authority.verify(player,'cancel')
assert(not result.tailRead and result.scraps==2,'native cancellation control hid its unread tail')
print('Engine authority fixture checks passed: exact identities, owned cleanup, removed target, recreation and native tail loss.')

-- Exercise the real client observer; native callbacks and queue ownership remain explicit.
do
 local function observer(mode,kind)
  local enabled=mode=='toolkit'
  local actor,queue={},{}
  local present,tailStarted=false,false
  queue.character=actor
  function actor:getCharacterActions()return {contains=function()return present end}end
  local lifecycle={begin=function()return enabled end,finish=function()end,
   flush=function(current)return 'completed',current.current end,current=function()return queue.current end}
  PZSurvivorToolkit={ActionQueueLifecycle=lifecycle}
  ISTimedActionQueue={queues={[actor]=queue}}
  getPlayer=function()return actor end
  Events={OnTick={Add=function()end},OnServerCommand={Add=function()end},OnGameStart={Add=function()end}}
  require=function(name)
   if name=='QueuePreflight'then return {onGameStart=function(events,fn)events.OnGameStart.Add(fn)end,onTick=function(events,fn)events.OnTick.Add(fn)end}end
   if name=='QueueTestSelection' then return {mode=mode,kind=kind,suite='engine'} end
   if name=='QueueEngineAuthority' then return {} end
   return true
  end
  local file=assert(io.open(root..'/tests/native_queue/engine/client/ZZEngine.lua'))
  local source=file:read('*a');file:close()
  local client=assert(loadstring(source..'\nreturn {settled=completionSettled,setTail=function(value)tail=value end,counts=function()return repairs,completes,flushes end}'))()
  client.setTail({isStarted=function()return tailStarted end})
  local function action()
   local value={Type='ISFixGenerator',character=actor,action={}}
   queue.current=value;queue.queue={value};return value
  end
  return lifecycle,client,action,function(value)present=value end,function(value)tailStarted=value end
 end
 for _,mode in ipairs({'native','toolkit'}) do for _,kind in ipairs({'sp','mp'}) do
  local lifecycle,client,action=observer(mode,kind)
  for iteration=1,2 do
   local parent=action()
   assert(lifecycle.begin(parent,'perform')==(mode=='toolkit'))
   lifecycle.finish(parent,'perform',true)
   if kind=='sp' then lifecycle.begin(parent,'complete');lifecycle.finish(parent,'complete',true) end
   lifecycle.flush(ISTimedActionQueue.queues[parent.character])
  end
  client.settled()
  local perform,complete,flush=client.counts()
  local count=mode=='toolkit' and 2 or 0
  assert(perform==count and complete==(kind=='sp' and count or 0) and flush==count,
   'observer counters do not describe real SP/Host/native phases')
 end end
 for _,fault in ipairs({'complete-first','duplicate-perform','duplicate-finish','failed-finish','wrong-owner',
                       'replaced-native','native-present','missing-complete','duplicate-flush','early-tail','unflushed-tail','client-complete'}) do
  local kind=fault=='client-complete' and 'mp' or 'sp'
  local lifecycle,client,action,present,tailStarted=observer('toolkit',kind)
  local parent=action()
  local ok=pcall(function()
   if fault=='complete-first' then lifecycle.begin(parent,'complete');return end
   if fault=='wrong-owner' then ISTimedActionQueue.queues[parent.character].current={};lifecycle.begin(parent,'perform');return end
   lifecycle.begin(parent,'perform')
   if fault=='duplicate-perform' then lifecycle.begin(parent,'perform');return end
   lifecycle.finish(parent,'perform',fault~='failed-finish')
   if fault=='duplicate-finish' then lifecycle.finish(parent,'perform',true);return end
   if fault=='replaced-native' then parent.action={} end
   if fault~='missing-complete' then lifecycle.begin(parent,'complete');lifecycle.finish(parent,'complete',true) end
   if fault=='native-present' then present(true) end
   if fault=='early-tail' then tailStarted(true) end
   if fault=='unflushed-tail' then client.settled();return end
   lifecycle.flush(ISTimedActionQueue.queues[parent.character])
   if fault=='duplicate-flush' then lifecycle.flush(ISTimedActionQueue.queues[parent.character]) end
  end)
  assert(not ok,'native generator observer accepted '..fault)
 end
 print('Engine completion observer checks passed: exact native phases, owner, removal, flush and independent tail.')
end
