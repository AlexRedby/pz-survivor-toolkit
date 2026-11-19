return function()
require 'PZSurvivorToolkit/CraftChainRecipes'
local config=require 'QueueTestSelection'
local F=require 'QueueCraftFixture'
local JSON=require 'QueueHealthEvents'
local T=PZSurvivorToolkit
local step,phase,since,started,done=1,'prepare',0,false,false
local state,ids,current,tail,receipt,walk,readySince,settledSince
local picked,returned,starts,seenReturns={},{},{},{}
local progress,tailProgress,stopped,idle=false,false,false,0
local bodyEvidence,originalRows,stopEvidence
local diagnose
local function case()return config.cases[step]end
local function walking()return case()~='complete-pinned-tools'end
local function q()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function sorted(set)local a={};for id in pairs(set)do a[#a+1]=id end;table.sort(a);return a end
local function emit(row)
 row.suite='craft';row.kind=config.kind;row.mode=config.mode;row.actor='client1';JSON.emit(row)
end
local function request(command)
 if config.kind=='mp'then sendClientCommand('CraftQueueTest',command,{case=case()})
 elseif command=='Prepare'then
  state=F.prepare(getPlayer(),case());ids=F.descriptor(state)
  print('[CRAFT_QUEUE_TEST] PREPARED '..JSON.encode(ids))
 else receipt=assert(F.verify(state,false));print('[CRAFT_QUEUE_TEST] WALK_AUTHORITY '..JSON.encode(receipt))end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='CraftQueueTest'then return end
 if value.ok==false then pcall(diagnose,value.error)end
 assert(value.ok~=false,value.error)
 if command=='Prepared'then ids=value elseif command=='Verified'then receipt=value end
end)
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then idle=#q().queue==0 and not player:hasTimedActions()and not player:isPlayerMoving()and idle+1 or 0 end
end)
local function rows()
 local result={}
 for _,action in ipairs(q().queue)do
  local source=action.srcContainer and action.srcContainer:getContainingItem()
  local dest=action.destContainer and action.destContainer:getContainingItem()
  result[#result+1]={row=string.match(tostring(action),'^%S+ %S+'),kind=action.Type,itemId=action.item and action.item:getID(),
   sourceId=source and source:getID(),destId=dest and dest:getID(),started=action:isStarted(),
   native=tostring(action.action),allowMissing=action.allowMissingItems==true}
 end
 return result
end
diagnose=function(problem)
 if not ids or not state then return end
 local endpoints={}
 for i,id in ipairs(ids.tools)do
  local item=state.root:getItemById(id);local container=item and item:getContainer()
  endpoints[i]={id=id,sourceId=ids.bags[i],present=item~=nil,root=container==state.root,
   source=container==state.bags[i]:getItemContainer(),capacity=state.bags[i]:getItemContainer():getCapacity(),
   room=item and state.bags[i]:getItemContainer():hasRoomFor(getPlayer(),item),
   picked=picked[id]==true,returned=returned[id]==true}
 end
 print('[CRAFT_QUEUE_TEST] FAILURE_DIAGNOSTICS '..JSON.encode({case=case(),problem=tostring(problem),phase=phase,
  body=bodyEvidence,originalRows=originalRows,stop=stopEvidence,queue=rows(),endpoints=endpoints,
  returnStarts=starts,pickupIds=sorted(picked),returnIds=sorted(returned),
  walk=walk,nativeStop=stopped,tailProgress=tailProgress,idle=idle}))
end
-- Read-only receipt from the actual engine stop after the original Lua delegate.
craftWalkStopped=function(action,ok)
 if action~=current then return end
 assert(ok and walking()and walk and not stopped,'unexpected or repeated native craft stop')
 stopped=true;walk.stoppedAt=getTimestampMs()
 stopEvidence={x=getPlayer():getX(),y=getPlayer():getY(),queue=rows(),native=tostring(action.action),ok=ok}
end
require('QueuePreflight').onGameStart(Events,function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 craftWalkInput(getPlayer(),0)
 if not isClient()then getPlayer():setGhostMode(true)end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
local function enqueue(player)
 local worn=player:getWornItem(state.bags[1]:canBeEquipped())==state.bags[1]
 local held=player:getSecondaryHandItem()==state.bags[2]
 if worn and held and not state.menuRefreshed then
  getPlayerInventory(player:getPlayerNum()):refreshBackpacks();getPlayerLoot(player:getPlayerNum()):refreshBackpacks()
  state.menuRefreshed=true;return false
 end
 local containers=ISInventoryPaneContextMenu.getContainers(player)
 if not worn or not held or not containers:contains(state.bags[1]:getItemContainer())
  or not containers:contains(state.bags[2]:getItemContainer())then return false end
 local recipe=assert(getScriptManager():getCraftRecipe('QueueKeepCraftTools'))
 local logic=HandcraftLogic.new(player,nil,nil);logic:setContainers(containers);logic:setRecipe(recipe)
 logic:setManualSelectInputs(true);logic:clearManualInputs()
 local items={state.material,state.tools[1],state.tools[2]};local inputs,choices,initial={},{},{}
 for i=0,2 do
  local native=recipe:getInputs():get(i);local index=recipe:getIndexForIO(native)
  local item=items[i+1];local selected=ArrayList.new();selected:add(item)
  assert(logic:setManualInputsFor(native,selected),'native manual input refused')
  inputs[#inputs+1]={index=index,native=native,keep=native:isKeep()}
  choices[index]={amount=1,resourceIds={item:getID()},generated=0,fullType=item:getFullType()};initial[item:getID()]=true
 end
 logic:canPerformCurrentRecipe();if not logic:canPerformCurrentRecipe()then return false end
 assert(T.CraftChainRecipes.enqueue(player,{steps={{recipe={native=recipe,inputs=inputs},inputs=choices}},initialIds=initial},{player=player}),
  'real pinned producer refused')
 state.book:setAlreadyReadPages(state.book:getNumberOfPages()-1)
 player:setAlreadyReadPages(state.book:getFullType(),state.book:getNumberOfPages()-1)
 tail=ISReadABook:new(player,state.book);ISTimedActionQueue.add(tail)
 return true
end
local function discover()
 for _,a in ipairs(q().queue)do
  if a.Type=='ISHandcraftAction'and a.craftRecipe==getScriptManager():getCraftRecipe('QueueKeepCraftTools')then
   assert(not current or current==a,'multiple native crafts');current=a
  end
 end
end
local function transfers(action)
 if not action or action.Type~='ISInventoryTransferAction'or not action:isStarted()or action:getJobDelta()<=0 then return end
 local items=action.queueList and action.queueList[1]and action.queueList[1].items or {action.item}
 for _,item in ipairs(items)do for i,id in ipairs(ids.tools)do
  if item:getID()==id then
   local source=state.bags[i]:getItemContainer()
   if action.srcContainer==source and action.destContainer==state.root then picked[id]=true end
   if action.srcContainer==state.root and action.destContainer==source then
    seenReturns[action]=seenReturns[action]or {}
    if not seenReturns[action][id]then starts[#starts+1]=id;seenReturns[action][id]=true end
    returned[id]=true
   end
  end
 end end
end
local function returnsFinished()
 local seen={}
 for _,id in ipairs(starts)do
  assert(not seen[id],'native return started more than once for exact tool');seen[id]=true
  assert(id~=ids.tools[1]or case()~='walk-pinned-full','blocked source received forbidden return')
 end
 for i,id in ipairs(ids.tools)do
  local blocked=case()=='walk-pinned-full'and i==1
  local item=state.root:getItemById(id)
  if blocked then
   assert(not returned[id],'blocked source received forbidden transfer progress')
   if not item or item:getContainer()~=state.root then return false end
  elseif not returned[id]or not seen[id]or not item
   or item:getContainer()~=state.bags[i]:getItemContainer()then return false end
 end
 return true
end
local function chooseDirection(player)
 -- Screen-forward and its rotations follow the cart native keyboard fixture.
 local offsets={{-1,-1},{-1,1},{1,1},{1,-1}}
 for direction,offset in ipairs(offsets)do
  local square=getCell():getGridSquare(math.floor(player:getX())+offset[1],math.floor(player:getY())+offset[2],math.floor(player:getZ()))
  if square and square:canStand()and square:isFree(false)then return direction end
 end
 error('no free neighbouring square for genuine walk interruption')
end
local function finish()
 local value={event='case',id=case(),status='passed',producer='CraftChainRecipes.enqueue',queueEnabled=false,
  toolIds=ids.tools,pickupIds=sorted(picked),returnIds=sorted(returned),returnStarts=starts,
  craftProgress=progress,tailProgress=tailProgress,tailDiscarded=walking()and q():indexOf(tail)==-1 and not tailProgress,
  nativeStop=stopped,nativeDuration=150,authorityVerified=true,
  walkDistance=walk and walk.distance or 0,walkProgress=walk and walk.progress or 0,
  inputReleased=not walk or walk.released==true,blockedToolId=case()=='walk-pinned-full'and ids.tools[1]or false}
 for key,result in pairs(receipt)do if key~='case'then value[key]=result end end
 emit(value)
 if step==#config.cases then
  craftWalkInput(getPlayer(),-1);done=true
  emit({event='complete',cases=config.cases,expected=step,performed=step,failed=0,skipped=0});print('[CRAFT_QUEUE_TEST] COMPLETE')
 else
  step=step+1;phase='prepare';since=getTimestampMs();state,ids,current,tail,receipt,walk,readySince,settledSince=nil,nil,nil,nil,nil,nil,nil,nil
  picked,returned,starts,seenReturns={},{},{},{};progress,tailProgress,stopped,idle=false,false,false,0
  bodyEvidence,originalRows,stopEvidence=nil,nil,nil
 end
end
require('QueuePreflight').onTick(Events,function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<180000,'editor-off craft deadline '..phase)
  local player=getPlayer();if not player or player:isDead()or not player:getSquare()then return end
  if config.kind=='mp'and(not isClient()or player:getOnlineID()<0)then return end
  assert(not T.Settings.actionQueue(),'craft editor unexpectedly enabled')
  if phase=='prepare'then
   assert(P4TidyUpMeister==nil and not getActivatedMods():contains('P4TidyUpMeister'),'foreign returns provider selected')
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=false,nativeDurations=true})end
   request('Prepare');phase='ready';return
  end
  if phase=='ready'then
   if not ids then return end
   state=state or F.resolve(player,ids);if not state then return end
   readySince=readySince or getTimestampMs();assert(getTimestampMs()-readySince<25000,'native container/recipe readiness timeout')
   if not enqueue(player)then return end
   phase='running';since=getTimestampMs();return
  end
  if phase=='running'then
   discover();transfers(q().current);F.fillFirstOrigin(state)
   if current and q().current==current and current.craftStarted==true and current:isStarted()and current:getJobDelta()>0 then
    progress=true;assert(current:getDuration()==150 and current.stopOnWalk==true and not player:isTimedActionInstant())
    if walking()and not walk then
     assert(picked[ids.tools[1]]and picked[ids.tools[2]],'actual pickups missing before walk')
     assert(current:getJobDelta()<=.25,'missed early native craft progress')
     assert(case()~='walk-pinned-full'or state.fullOrigin,'source not blocked before walk')
     bodyEvidence=T.ActionQueueSettlement.operationState(current)or {unavailable=true}
     originalRows=rows()
     walk={x=player:getX(),y=player:getY(),progress=current:getJobDelta(),since=getTimestampMs(),distance=0}
     craftWalkInput(player,chooseDirection(player))
    end
   end
   if walk and not walk.released then
    walk.distance=math.sqrt((player:getX()-walk.x)^2+(player:getY()-walk.y)^2)
    assert(getTimestampMs()-walk.since<7000,'genuine native walk/stop timed out')
    if stopped and walk.distance>=.25 then
     craftWalkInput(player,0);walk.released=true;walk.releasedAt=getTimestampMs();idle=0;settledSince=nil
    end
   end
   if q().current==tail and tail:isStarted()and tail:getJobDelta()>0 then tailProgress=true end
   if walk and walk.released then
    assert(getTimestampMs()-walk.releasedAt<20000,'native earned return settlement timed out')
   end
   if #q().queue>0 or player:hasTimedActions()or player:isPlayerMoving()or idle<3
    or walk and not walk.released or not returnsFinished()then settledSince=nil;return end
   -- Native movement clears the queue before its deferred restoration can start.
   -- Only settle after actual expected transfers, stationary native idle and a
   -- quiet interval; idle accumulated while walking cannot pay this gate.
   settledSince=settledSince or getTimestampMs()
   if getTimestampMs()-settledSince<250 then return end
   assert(current and progress and picked[ids.tools[1]]and picked[ids.tools[2]],'native craft/pickup progress missing')
   assert(walking()and stopped and not tailProgress or not walking()and not stopped and tailProgress,'native stop/tail differs')
   request('Verify');phase='receipt';return
  end
  if phase=='receipt'and receipt then finish()end
 end)
 if not ok then
  pcall(diagnose,problem)
  craftWalkInput(getPlayer(),-1);done=true;emit({event='error',message=tostring(problem)});print('[QUEUE_TEST] FAIL editor-off craft '..tostring(problem))
 end
end)
end
