local config=require 'QueueTestSelection'
local Cart=require 'QueueCartPickup'
if not Cart.selected(config) then return end
Cart.validate(config)
require 'PZSurvivorToolkit/ActionQueuePanel'
require 'SaucedCarts/TimedActions/ISCartPickupAction'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISTimedActionQueue'
local Fixture=require 'QueueEquipmentFixture'
local JSON=require 'QueueHealthEvents'
local native=config.mode=='native'
local option=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'))
option:setValue(not native)
local started,done=false,false
local index,step,phase,since=1,1,'prepare',0
local spec,prepared,audited,cleaned,action,hold,lastSnapshot=nil,nil,nil,nil,nil,nil,nil
local idleUpdates,performed=0,0
local seenStarted,seenProgress=false,false
local receipts={}
local function player() return assert(getPlayer()) end
local function queue() return ISTimedActionQueue.getTimedActionQueue(player()) end
local function empty() return #queue().queue==0 and not player():hasTimedActions() and not player():hasPath() end
local function emit(row)
 row.suite='equipment';row.kind='mp';row.mode=config.mode;row.actor='client1';JSON.emit(row)
end
local function finish(problem)
 if done then return end;done=true
 if problem then
  emit({event='case',id='cart-pickup',status='failed',reason=tostring(problem)})
  print('[QUEUE_TEST] FAIL equipment cart '..tostring(problem))
 else
  emit({event='case',id='cart-pickup',status='passed',outcome={cartPickup=true,inventoryPreserved=true,
   equipmentMatches=true,cargoPreserved=true,nativeDurations=true,postprocessingVerified=true,authoritative=true,
   repeatedPickup=true,nativeDrop=true,cartTypes=Cart.types,phases=#receipts,receipts=receipts}})
  print('[EQUIPMENT_TEST] RECEIPT case=cart-pickup')
 end
 emit({event='complete',cases=config.cases,expected=1,performed=1,skipped=0,failed=problem and 1 or 0})
 print('[EQUIPMENT_TEST] COMPLETE')
end
local function diagnostic(stage)
 if not spec then return end
 local row=Cart.inspect(player(),spec)
 row.actor='client1';row.phase=Cart.phases[step];row.stage=stage;row.queueSize=#queue().queue
 row.actionType=action and action.Type or '';row.isStarted=false;row.isValid=false
 if action then
  row.isStarted=action:isStarted()==true
  local ok,value=pcall(action.isValid,action)
  row.isValid=ok and value==true;row.validError=not ok and tostring(value) or ''
 end
 local encoded=JSON.encode(row)
 -- Compare semantic fields; JSON table iteration order is stable within this process.
 if encoded~=lastSnapshot then Cart.marker('STATE',row);lastSnapshot=encoded end
end
local function enqueue()
 assert(empty(),'cart phase started with pending action')
 action=nil;hold=nil;lastSnapshot=nil;idleUpdates=0;seenStarted=false;seenProgress=false
 local _,item=Cart.inspect(player(),spec);assert(item,'exact cart missing before native callback')
 local function callback()
  if Cart.phases[step]=='drop' then ISInventoryPaneContextMenu.onUnEquip({item},player():getPlayerNum())
  else ISTimedActionQueue.add(ISCartPickupAction.FromWorldItem(player(),assert(item:getWorldItem()))) end
 end
 if native then callback() else PZSurvivorToolkit.ActionQueueOperations.run(callback) end
 assert(not empty(),'native cart callback queued no action')
 phase='action';since=getTimestampMs();diagnostic('queued')
 Cart.marker('BEGIN',{actor='client1',index=index,id=spec.id,type=spec.type,phase=Cart.phases[step]})
end
Events.OnPlayerUpdate.Add(function(actor)
 if started and not done and actor==getPlayer() then idleUpdates=empty() and idleUpdates+1 or 0 end
end)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='CartPickupTest' or done then return end
 local ok,problem=pcall(function()
  assert(args and args.ok~=false,args and args.error or 'missing cart response')
  assert(args.index==index,'wrong cart response index')
  if command=='Prepared' then assert(phase=='ready' and not prepared,'duplicate cart prepared');prepared=args
  elseif command=='Audited' then
   assert(phase=='audit' and not audited and args.id==spec.id and args.phase==Cart.phases[step],'wrong cart phase acknowledgement')
   audited=args
  elseif command=='Cleaned' then assert(phase=='cleanup' and not cleaned and args.id==spec.id,'wrong cart cleanup response');cleaned=args
  else error('unknown cart server response') end
 end)
 if not ok then finish(problem) end
end)
Events.OnGameStart.Add(function()
 local ok,problem=pcall(function()
  assert(isClient() and not isServer(),'cart fixture requires actual Host client')
  assert(Translator.getLanguage():name()==config.languages[1],'cart language differs')
  assert(not player():isTimedActionInstant(),'native cart durations required')
  assert(not player():isAiming(),'baseline cart fixture requires no aim input')
  player():setGhostMode(true);getCore():setOptionAutoDrink(false);player():setAutoDrink(false)
  if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
  emit({event='setup',cases=config.cases,expected=1,nativeDurations=true,queueEnabled=not native})
  started=true;since=getTimestampMs()
 end)
 if not ok then finish(problem) end
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,problem=pcall(function()
  local now=getTimestampMs()
  assert(now-since<30000,'cart phase deadline '..phase..':'..tostring(Cart.phases[step]))
  assert(PZSurvivorToolkit.Settings.actionQueue()==not native,'cart queue mode changed')
  assert(not player():isAiming(),'unexpected aim input during baseline cart fixture')
  if phase=='prepare' then
   if not empty() or player():isPlayerMoving() or not player():getCurrentSquare() then return end
   sendClientCommand('CartPickupTest','Prepare',{index=index});phase='ready';since=now
  elseif phase=='ready' then
   if not prepared then return end
   assert(prepared.type==Cart.types[index] and type(prepared.id)=='number' and type(prepared.cargo)=='number','cart descriptor differs')
   spec=prepared
   if math.abs(player():getX()-spec.spawn.x)>.1 or math.abs(player():getY()-spec.spawn.y)>.1 or player():getZ()~=spec.spawn.z then
    Fixture.relocate(player(),spec.spawn);return
   end
   local row=Cart.inspect(player(),spec)
   if not Cart.matches(row,true) then return end
   assert(not player():isPlayerMoving(),'cart actor still moving after setup')
   enqueue()
  elseif phase=='action' then
   local current=queue().current
   if Cart.pickup(current) then
    action=current
    seenStarted=seenStarted or action:isStarted()==true
    seenProgress=seenProgress or action:isStarted() and action:getJobDelta()>0
   end
   diagnostic(empty() and 'empty' or 'running')
   if not empty() or idleUpdates<6 or not Fixture.transactionsSettled() then hold=nil;return end
   if Cart.phases[step]~='drop' then assert(seenStarted and seenProgress,'pickup never made native active progress') end
   -- P4 deferred restoration begins after two empty player updates; verify after its queue drains.
   local row=Cart.inspect(player(),spec)
   if not Cart.matches(row,Cart.phases[step]=='drop') then hold=nil;return end
   if not hold then hold=now;return end
   if now-hold<500 then return end
   row=Cart.receipt(player(),spec,Cart.phases[step],'client1')
   row.holdMs=now-hold;row.queueEmpty=true;row.idleUpdates=idleUpdates
   row.nativeDurations=true;row.actionStarted=seenStarted;row.actionProgress=seenProgress
   if action then row.actionType=action.Type;row.actionDuration=action:getDuration() end
   Cart.marker('RECEIPT',row);receipts[#receipts+1]=row
   sendClientCommand('CartPickupTest','Audit',{index=index,id=spec.id,phase=Cart.phases[step]})
   phase='audit';since=now
  elseif phase=='audit' then
   diagnostic('audit')
   -- Retain exact state while the server independently verifies it.
   assert(Cart.matches(Cart.inspect(player(),spec),Cart.phases[step]=='drop'),'cart ownership changed while awaiting server audit')
   if not audited then return end
   assert(audited.type==spec.type and audited.cargoID==spec.cargo and audited.cargoPreserved==true and audited.holdMs>=500,
    'authoritative cart/cargo acknowledgement differs')
   audited=nil;step=step+1
   if step<=#Cart.phases then enqueue()
   else
    sendClientCommand('CartPickupTest','Cleanup',{index=index,id=spec.id});phase='cleanup';since=now
   end
  elseif phase=='cleanup' then
   if not cleaned then return end
   local row=Cart.inspect(player(),spec)
   if row.inventoryCount~=0 or row.worldCount~=0 or row.primaryID==spec.id or row.secondaryID==spec.id then return end
   Cart.marker('CLEANED',{actor='client1',index=index,id=spec.id})
   performed=performed+1;index=index+1;step=1;spec=nil;prepared=nil;cleaned=nil;phase='prepare';since=now
   if index>#Cart.types then assert(performed==3);finish() end
  end
 end)
 if not ok then pcall(diagnostic,'failed');finish(problem) end
end)
