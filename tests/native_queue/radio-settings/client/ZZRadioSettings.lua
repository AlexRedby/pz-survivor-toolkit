require 'PZSurvivorToolkit/ActionQueuePanel'
require 'RadioCom/ISRadioAction'
require 'RadioCom/ISUIRadio/ISItemDropBox'
require 'RadioCom/ISUIRadio/ISSpeakerButton'
require 'RadioCom/ISUIRadio/ISVolumeBar'
require 'RadioCom/RadioWindowModules/RWMSubEditPreset'
require 'RadioCom/RadioWindowModules/RWMVolume'
require 'RadioCom/RadioWindowModules/RWMGridPower'
require 'RadioCom/RadioWindowModules/RWMChannel'
require 'RadioCom/RadioWindowModules/RWMMicrophone'
local P=require 'QueueEnergyPlacement'
local F=require 'QueueRadioSettings'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local native=config.mode=='native'
local T=PZSurvivorToolkit
local API,Ops=T.ActionQueue,T.ActionQueueOperations
local started,ready,done,phase,index,since=false,false,false,'prepare',1,0
local ids,state,authority,previous,receipt,panels,commands,actions,order,edit,quiet
local initialQueue,editedQueue,initialPhysicalQueue,editedPhysicalQueue
local function case()return config.cases[index]end
local function now()return getTimestampMs()end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,value)print('[RADIO_SETTINGS] '..event..' '..JSON.encode(value))end
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='radio-settings',config.kind,config.mode,'client1';JSON.emit(row)
end
local function fail(problem)
 if done then return end
 local client
 if state then local ok,value=pcall(F.snapshot,state);if ok then client=value end end
 emit({event='case',id=case(),status='failed',reason=tostring(problem),ids=ids,
  commands=commands,order=order,edit=edit,initialQueue=initialQueue,editedQueue=editedQueue,
  client=client,server=receipt})
 print('[QUEUE_TEST] FAIL radio-settings '..tostring(problem));done=true
end
local placement,placementState,clientPlacement
local function request(name)
 assert(name=='Prepare'or name=='Verify','unknown radio authority command')
 local args={case=case()}
 if name=='Prepare'then
  assert(clientPlacement and P.at(getPlayer(),placement),'radio Prepare requires fresh settled placement')
  args.placement=placement;args.clientPlacement=clientPlacement
 end
 if isClient()then sendClientCommand('RadioSettingsTest',name,args);return end
 if name=='Prepare'then
  authority=F.prepare(getPlayer(),case(),config.mode,previous,placement,clientPlacement);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 else receipt=F.snapshot(authority);raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,name,value)
 if module~='RadioSettingsTest'or done then return end
 if name=='Failed'then fail(value and value.error or 'authority failed');return end
 if name=='Prepared'then
  if value.case==case()then ids=value end
 elseif name=='Verified'and value.case==case()then receipt=value end
end)
require('QueuePreflight').onGameStart(Events,function()started=true;since=now()end)
local watchPreparations
local function initialize()
 local player=getPlayer()
 if not isIngameState()or not player or not player:getSquare()or player:isDead()then return false end
 if isClient()~=(config.kind=='mp')then return false end
 if isClient()and (player:getOnlineID()<0 or player:getUsername()~='client1')then return false end
 local option=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'))
 option:setValue(not native)
 assert(T.Settings.actionQueue()==not native,'queue option differs from selected mode')
 assert(not player:isTimedActionInstant(),'radio settings require native timing')
 getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false)
 player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
 watchPreparations();ready=true;since=now()
 emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=not native,
  nativeDurations=true,producer='native RWM callbacks with native doWalkTo'})
 return true
end
local function checkReceipt(actual,expected,label)
 assert(actual and actual.case==case(),label..' case identity differs')
 for _,key in ipairs({'a','b'})do
  local device=assert(actual.devices[key],label..' device missing '..key)
  local identity=assert(ids[key],label..' fixture identity missing '..key)
  for _,field in ipairs({'x','y','z','index'})do
   assert(device[field]==identity[field],label..' world identity differs '..key..'.'..field)
  end
  for field,value in pairs(expected[key])do
   local observed=device[field]
   assert(type(observed)==type(value),label..' field type differs '..key..'.'..field)
   if type(value)=='number'then
    assert(math.abs(observed-value)<.0001,label..' value differs '..key..'.'..field..' actual='..tostring(observed)..' expected='..tostring(value))
   else assert(observed==value,label..' value differs '..key..'.'..field)end
  end
  assert(device.on==true and device.powered==true,label..' radio lost power '..key)
 end
end
local function initialReady()
 local snapshot=F.snapshot(state)
 for _,device in pairs(snapshot.devices)do
  if math.abs(device.volume-.5)>.0001 or device.channel~=90000 or device.micMuted~=false
   or not device.on or not device.powered then return false end
 end
 return true
end
local function panel(class,device)
 local result=class:new(-1000,-1000,300,100)
 result:initialise();result:instantiate()
 assert(result:readFromObject(getPlayer(),device,device:getDeviceData(),'IsoObject'),
  'native '..class.Type..' rejected fixture radio')
 return result
end
local function createPanels()
 panels={}
 for _,key in ipairs({'a','b'})do
  local device=state[key]
  assert(device:getDeviceData():getIsTwoWay()and not device:getDeviceData():isNoTransmit(),
   'fixture requires a native two-way radio')
  panels[key]={volume=panel(RWMVolume,device),power=panel(RWMGridPower,device),channel=panel(RWMChannel,device),mic=panel(RWMMicrophone,device)}
 end
end
-- A deferred walkAdj dispatcher is physical preparation owned by its setter.
-- Native adjacency is resolved at execution; observe it without replacing callbacks.
local preparations={}
local function ownedPreparation(action,device)
 local owner=T.ActionQueueApproach
 if not owner or not owner.isAction(action)or not owner.capture(action)then return false end
 local request=action.toolkitQueueCommand.snapshot
 return T.ActionQueueOperations.commandConstructionTrusted()and action.character==getPlayer()
  and request.binding.owner==luautils and request.binding.name=='walkAdj'and request.args.n==3
  and request.args[1]==getPlayer()and request.args[2]==device:getSquare()and request.args[3]==true
end
local function capturePreparation(action,name,device)
 assert(not native and ownedPreparation(action,device),'foreign native approach dispatcher '..name)
 local square=device:getSquare()
 local proof={name=name,helper='walkAdj',target={x=square:getX(),y=square:getY(),z=square:getZ()},
  argumentCount=3,keepActions=true,owned=true,constructor=true,resolver=true,sameOperation=false,
  started=false,completed=false,cancelled=false}
 preparations[action]={proof=proof,device=device}
 return proof
end
local function pairPreparation(action,setter)
 local record=assert(preparations[action],'unobserved native preparation')
 assert(action.toolkitQueueOperation==setter.toolkitQueueOperation and type(action.toolkitQueueOperation)=='table',
  'native preparation/setter operation differs')
 record.proof.sameOperation=true
 return record.proof
end
local function preparationName(action)
 local record=preparations[action]
 if not record then return end
 assert(ownedPreparation(action,record.device),'queued preparation binding changed')
 return record.proof.name..':approach'
end
local function cancelPreparation(name)
 for action,record in pairs(preparations)do if record.proof.name==name then
  assert(not record.proof.started and not record.proof.completed and queue():indexOf(action)==-1,
   'cancelled setter retained or ran native preparation')
  record.proof.cancelled=true
 end end
end
local function verifyPreparations()
 for action,record in pairs(preparations)do
  local proof=record.proof
  assert(proof.sameOperation and queue():indexOf(action)==-1,'native preparation retained or unpaired')
  if proof.cancelled then assert(not proof.started and not proof.completed,'cancelled preparation executed')
  else assert(proof.started and proof.completed and proof.succeeded and proof.children==0,
   'adjacent native preparation did not complete without inserted work')end
 end
end
watchPreparations=function()
 assert(T.ActionQueueLifecycle.registerObserver('fixture.radio-settings-preparation',{
  started=function(action)
   local record=preparations[action];if not record then return end
   assert(T.ActionQueueApproach.isAction(action)and queue().current==action,'preparation started without ownership')
   record.proof.started=true
  end,
  begin=function(action,step)
   local record=preparations[action];if not record or step~='perform'then return end
   assert(T.ActionQueueApproach.isAction(action)and queue().current==action,'preparation lost resolver ownership')
   record.proof.children=action._numAddedActions
   assert(record.proof.children==0,'adjacent preparation inserted native walking work')
  end,
  finish=function(action,step,succeeded)
   local record=preparations[action];if not record or step~='perform'then return end
   record.proof.completed=true;record.proof.succeeded=succeeded==true
  end,
 }),'native preparation observer unavailable')
end
local function queueNames()
 local names={}
 for _,action in ipairs(queue().queue)do
  local name
  for key,value in pairs(actions or {})do if value==action then name=key;break end end
  if not preparationName(action)then names[#names+1]=assert(name,'unexpected queue member '..tostring(action.Type))end
 end
 return names
end
local function physicalNames()
 local result={}
 for _,action in ipairs(queue().queue)do
  local name=preparationName(action)
  if not name then for key,value in pairs(actions or {})do if action==value then name=key;break end end end
  result[#result+1]=assert(name,'untracked physical radio queue member')
 end
 return result
end
local function sameOrder(left,right)
 if #left~=#right then return false end
 for i,value in ipairs(left)do if value~=right[i]then return false end end
 return true
end
local function enqueue(name,mode,target,value)
 local emitted,declared={},{ }
 local original=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)
  emitted[#emitted+1]=action
  declared[#emitted]=action.maxTime
  if action.Type=='ISQueueActionsAction'then capturePreparation(action,name,state[target])end
  return original(action)
 end
 local ok,problem=pcall(function()
  local function invoke()
   local widgets=panels[target]
   if mode=='SetVolume'then
    widgets.volume:onVolumeChange(value*widgets.volume.volumeBar:getVolumeSteps())
   elseif mode=='SetChannel'then
    local selected
    for i=0,widgets.channel.presets:size()-1 do
     if widgets.channel.presets:get(i):getFrequency()==value then selected=i+1;break end
    end
    widgets.channel.comboBox.selected=assert(selected,'requested native preset missing')
    widgets.channel:comboChange();widgets.channel:doTuneInButton()
   elseif mode=='MuteMicrophone'then
    assert(not state[target]:getDeviceData():getMicIsMuted(),'native microphone producer requires initial unmuted state')
    widgets.mic:onMuteButton()
   elseif mode=='MuteVolume'then widgets.volume:onSpeakerButton(true)
   elseif mode=='ToggleOnOff'then widgets.power:toggleOnOff()
   else error('unsupported radio producer '..mode)end
  end
  if native then invoke()else Ops.run(invoke)end
 end)
 ISTimedActionQueue.add=original
 assert(ok,problem)
 -- Both objects must actually be adjacent. Never replace walkAdj or discard an emitted walk.
 assert(#emitted==(native and 1 or 2),'native radio producer shape differs '..name..' count='..#emitted)
 local index=native and 1 or 2;local action=emitted[index]
 local preparation=not native and pairPreparation(emitted[1],action)or nil
 assert(getmetatable(action)==ISRadioAction and action.mode==mode and action.device==state[target],
  'native radio producer binding differs '..name)
 if mode~='MuteVolume'then assert(action.secondaryItem==value,'native radio value differs '..name)end
 assert(declared[index]==30 and action.stopOnWalk==false and action.stopOnRun==true and action.ignoreHandsWounds==true,
  'native radio duration/flags differ '..name)
 if not native then assert(type(action.toolkitQueueOperation)=='table','command operation was not captured '..name)end
 local row={name=name,mode=mode,target=target,value=value,duration=declared[index],preparation=preparation,
  started=false,progress=false,cancelled=false,producer='native RWM callback'}
 commands[#commands+1]=row;actions[name]=action
 return action
end
local function observe()
 local current=queue().current
 for _,command in ipairs(commands)do
  local action=actions[command.name]
  if current==action and action:isStarted()then
   assert(not command.cancelled,'cancelled radio command started '..command.name)
   if not command.started then
    command.started=true;command.startedAt=now();order[#order+1]=command.name
    -- Native creation adjusts the constructor's 30 ticks for mood/body temperature.
    -- Sample its unchanged calculator at start, allowing only sub-tick float drift.
    command.nativeDurationExpected=action:adjustMaxTime(command.duration)
    command.effectiveDuration=action.maxTime
    assert(math.abs(action.maxTime-command.nativeDurationExpected)<.001,
     'duration differs from native adjustment '..command.name)
   end
   assert(action.maxTime==command.effectiveDuration,'active duration changed '..command.name)
   if action:getJobDelta()>0 then command.progress=true end
  end
 end
end
local function unchangedValues(before,after)
 for _,key in ipairs({'a','b'})do
  for _,field in ipairs({'volume','channel','micMuted','on','powered'})do
   if before.devices[key][field]~=after.devices[key][field]then return false end
  end
 end
 return true
end
local function pending()
 local anchor=actions.anchor
 assert(queue().current==anchor and anchor:isStarted()and anchor:getJobDelta()>0,
  'pending edits need native anchor progress')
 local before=F.snapshot(state)
 enqueue('firstVolume','SetVolume','a',.25)
 if case()=='barrier'then
  enqueue('channel','SetChannel','a',95000)
  enqueue('powerOff','ToggleOnOff','a',nil)
  enqueue('powerOn','ToggleOnOff','a',nil)
  enqueue('legacyMute','MuteVolume','a',true)
 else
  enqueue('channel','SetChannel','a',95000)
  enqueue('lastVolume','SetVolume','a',.75)
  enqueue('mic','MuteMicrophone','a',true)
 end
 enqueue('tail','SetChannel','b',96000)
 initialQueue=queueNames();initialPhysicalQueue=physicalNames()
 local expected=case()=='barrier'and {'anchor','firstVolume','channel','powerOff','powerOn','legacyMute','tail'}
  or {'anchor','firstVolume','channel','lastVolume','mic','tail'}
 assert(sameOrder(initialQueue,expected),'native producer order differs')
 for _,command in ipairs(commands)do if command.name~='anchor'then
  assert(not actions[command.name].action and not command.started,'pending action started before edit '..command.name)
 end end
 edit={reordered=false,cancelled={},denied=false,untouchedBefore=false,nativeDurations=true}
 if not native then
  if case()=='reorder'then
   assert(API.move(queue(),actions.lastVolume,actions.firstVolume),'last volume reorder rejected')
   assert(API.move(queue(),actions.mic,actions.channel),'microphone reorder rejected')
   edit.reordered=true
   expected={'anchor','lastVolume','firstVolume','mic','channel','tail'}
  elseif case()=='cancel'then
   for _,name in ipairs({'lastVolume','mic'})do
    assert(API.cancelOperation(queue(),actions[name]),'pending cancellation rejected '..name)
    for _,command in ipairs(commands)do if command.name==name then command.cancelled=true end end
    edit.cancelled[#edit.cancelled+1]=name
    cancelPreparation(name)
    assert(queue():indexOf(actions[name])==-1,'cancelled member retained '..name)
   end
   expected={'anchor','firstVolume','channel','tail'}
  elseif case()=='barrier'then
   local allowed,reason=API.move(queue(),actions.channel,actions.powerOff,true)
   assert(not allowed and reason,'native channel-after-power-off dependency incorrectly allowed movement')
   edit.denied=true;edit.reason=reason
  else error('unknown radio settings case '..tostring(case()))end
 end
 editedQueue=queueNames();editedPhysicalQueue=physicalNames()
 assert(sameOrder(editedQueue,expected),'edited queue member order differs')
 edit.untouchedBefore=unchangedValues(before,F.snapshot(state))
 assert(edit.untouchedBefore,'pending producer/edit wrote native device state')
 assert(math.abs(before.devices.a.volume-.5)<.0001 and before.devices.a.channel==90000
  and before.devices.a.micMuted==false,'target radio already changed before edits')
 edit.before=before;phase='running';quiet=nil
end
local function finish()
 assert(empty(),'native queue restarted before verification');verifyPreparations()
 local client=F.snapshot(state)
 checkReceipt(client,F.expected(case(),config.mode,false),'client')
 checkReceipt(receipt,F.expected(case(),config.mode,isClient()),isClient()and 'server'or 'single-player authority')
 local expectedOrder={}
 for _,name in ipairs(editedQueue)do expectedOrder[#expectedOrder+1]=name end
 assert(sameOrder(order,expectedOrder),'observed native execution order differs')
 for _,command in ipairs(commands)do
  if command.cancelled then
   assert(not command.started and not command.progress and not actions[command.name].action,
    'cancelled command executed '..command.name)
  else assert(command.started and command.progress,'native start/progress missing '..command.name)end
 end
 emit({event='case',id=case(),status='passed',ids=ids,clientPlacement=clientPlacement,commands=commands,order=order,edit=edit,
  initialQueue=initialQueue,editedQueue=editedQueue,initialPhysicalQueue=initialPhysicalQueue,editedPhysicalQueue=editedPhysicalQueue,client=client,server=receipt,queueIdle=true,
  settleMilliseconds=now()-quiet})
 previous=authority;index=index+1
 if not case()then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=index-1,failed=0,skipped=0})
  print('[RADIO_SETTINGS] COMPLETE');done=true;return
 end
 ids,state,authority,receipt,panels,commands,actions,order,edit,quiet=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 preparations={};initialPhysicalQueue,editedPhysicalQueue=nil,nil
 placement,placementState,clientPlacement=nil,nil,nil
 initialQueue,editedQueue=nil,nil;phase='prepare';since=now()
end
require('QueuePreflight').onTick(Events,function()
 if not started or done then return end
 local ok,problem=pcall(function()
  if not ready and not initialize()then return end
  local player=getPlayer()
  if not player or not player:getSquare()then return end
  assert(now()-since<90000,'radio settings timeout '..tostring(case())..' phase='..phase)
  if phase=='prepare'then
   assert(empty(),'radio settings require an empty initial native queue')
   if not placementState then placement=P.choose(player);placementState=P.begin(player,placement)end
   if not clientPlacement then
    clientPlacement=P.poll(placementState);if not clientPlacement then return end
    raw('CLIENT_PLACEMENT',{case=case(),proof=clientPlacement})
   end
   phase='prepared';request('Prepare');return
  elseif phase=='prepared'and ids then
   state=F.resolve(player,ids);if not state or not initialReady()then return end
   assert(empty(),'fixture preparation added native work')
   createPanels();commands,actions,order={},{},{}
   enqueue('anchor','SetVolume','b',.25);phase='anchor';return
  elseif phase=='anchor'then
   observe()
   if commands[1].progress then pending()end
  elseif phase=='running'then
   observe()
   if empty()then
    quiet=quiet or now()
    if now()-quiet>=2000 then phase='verified';request('Verify')end
   else quiet=nil end
  elseif phase=='verified'and receipt then finish()end
 end)
 if not ok then fail(problem)end
end)
