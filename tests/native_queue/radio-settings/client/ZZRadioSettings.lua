require 'PZSurvivorToolkit/ActionQueuePanel'
require 'RadioCom/ISRadioAction'
require 'TimedActions/WalkToTimedAction'
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
local preparationDiagnostic
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
  initialPhysicalQueue=initialPhysicalQueue,editedPhysicalQueue=editedPhysicalQueue,
  preparations=preparationDiagnostic and preparationDiagnostic()or false,client=client,server=receipt})
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
local walking,walkMethods,walkClass,walkParent={},nil,nil,nil
local walkNames={'new','begin','create','start','update','stop','perform','complete','isValid','waitToStart',
 'isValidStart','adjustMaxTime','getDuration','animEvent','serverStart','serverStop',
 'forceComplete','forceStop','forceCancel','invoke','isStarted'}
local function nativeWalkUnchanged(action)
 local binding=walking[action]
 if binding then
  binding.proof.sameOperation=rawequal(action.toolkitQueueOperation,binding.token)
   and rawequal(binding.preparation.toolkitQueueOperation,binding.token)
   and binding.setter~=nil and rawequal(binding.record.setter,binding.setter)
   and rawequal(binding.setter.toolkitQueueOperation,binding.token)
  if not binding.proof.sameOperation then return false end
 end
 if not walkMethods or ISWalkToTimedAction~=walkClass or type(action)~='table'or getmetatable(action)~=walkClass
  or getmetatable(walkClass)~=walkParent or rawget(walkClass,'__index')~=walkClass
  or walkParent and rawget(walkParent,'__index')~=walkParent or action.Type~='ISWalkToTimedAction'
  or action.maxTime~=-1 or action.stopOnWalk~=false or action.stopOnRun~=false
  or action.allowedWhileDraggingCorpses~=true
  or action.additionalTest or action.additionalContext or action.onCompleteFunc or action.onFailFunc then return false end
 for _,name in ipairs(walkNames)do if action[name]~=walkMethods[name]then return false end end
 for _,value in pairs(action)do if type(value)=='function'then return false end end
 return true
end
local function nativeNear(player,target)
 local x,y=player:getX(),player:getY()
 local west,north=target:has(IsoFlagType.collideW),target:has(IsoFlagType.collideN)
 local corrected=target
 if west and x<target:getX()then corrected=getCell():getGridSquare(target:getX()+1,target:getY(),target:getZ())
 elseif north and y<target:getY()then corrected=getCell():getGridSquare(target:getX(),target:getY()+1,target:getZ())end
 assert(corrected,'native radio correction target unloaded')
 local dx,dy=math.abs(corrected:getX()+.5-x),math.abs(corrected:getY()+.5-y)
 local reach=dx<=1.6 and dy<=1.6
 local canReach=reach and player:getSquare():canReachTo(corrected)or false
 local function point(s)return{x=s:getX(),y=s:getY(),z=s:getZ()}end
 return {version=1,noMovement=reach and canReach,actor={x=x,y=y,z=player:getZ()},square=point(player:getSquare()),
  target=point(target),correctedTarget=point(corrected),collideW=west,collideN=north,diffX=dx,diffY=dy,
  reachEvaluated=reach,canReach=canReach}
end
local function observeWalking()
 for action,entry in pairs(walking)do
  assert(nativeWalkUnchanged(action),'native radio walking callbacks/duration changed')
  local proof=entry.proof
  if queue().current==action and action:isStarted()and proof.startPosition then
   local player=getPlayer()
   if math.abs(player:getX()-proof.startPosition.x)+math.abs(player:getY()-proof.startPosition.y)>.02 then
    proof.progress=true;proof.progressAt=proof.progressAt or getTimestampMs()
   end
  end
 end
end
local diagnosticActions,diagnosticTokens={},{}
local diagnosticActionSerial,diagnosticTokenSerial=0,0
local function actionId(action)
 if not action then return false end
 if not diagnosticActions[action]then diagnosticActionSerial=diagnosticActionSerial+1;diagnosticActions[action]=diagnosticActionSerial end
 return diagnosticActions[action]
end
local function tokenId(token)
 if type(token)~='table'then return false end
 if not diagnosticTokens[token]then diagnosticTokenSerial=diagnosticTokenSerial+1;diagnosticTokens[token]=diagnosticTokenSerial end
 return diagnosticTokens[token]
end
preparationDiagnostic=function(selected)
 local q=queue();local player=getPlayer();local records,members={},{}
 local function square(value)return value and{x=value:getX(),y=value:getY(),z=value:getZ()}or false end
 local function bodyName(action)
  for name,body in pairs(actions or{})do if action==body then return name end end
  return false
 end
 for action,record in pairs(preparations)do
  records[#records+1]={name=record.proof.name,action=actionId(action),setter=actionId(record.setter),
   setterName=bodyName(record.setter),index=q:indexOf(action),setterIndex=record.setter and q:indexOf(record.setter)or false,
   token=tokenId(action.toolkitQueueOperation),setterToken=record.setter and tokenId(record.setter.toolkitQueueOperation)or false,
   proof=record.proof,begin=record.begin or false}
 end
 table.sort(records,function(a,b)return a.name<b.name end)
 for i,action in ipairs(q.queue)do
  local record=preparations[action]
  members[#members+1]={index=i,action=actionId(action),name=record and record.proof.name..':approach'or bodyName(action),
   type=action.Type,mode=action.mode or false,token=tokenId(action.toolkitQueueOperation),
   native=action.action~=nil,started=action.started==true,location=square(action.location),
   selectedOperation=selected~=nil and action.toolkitQueueOperation==selected.toolkitQueueOperation}
 end
 local pose=false
 if player and player.getX and player.getSquare then
  pose={x=player:getX(),y=player:getY(),z=player:getZ(),square=square(player:getSquare()),currentSquare=square(player:getCurrentSquare()),
   isMoving=player:isMoving(),isPlayerMoving=player:isPlayerMoving(),isPathfindRunning=player:isPathfindRunning(),hasPath2=player:getPath2()~=nil}
 end
 local record=selected and preparations[selected]
 return {case=case(),name=record and record.proof.name or false,selected=actionId(selected),
  setter=record and actionId(record.setter)or false,setterName=record and bodyName(record.setter)or false,
  current=actionId(q.current),queue=members,records=records,pose=pose}
end
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
 record.setter=setter
 for _,entry in pairs(walking)do
  if entry.record==record then assert(not entry.setter or entry.setter==setter,'native walking setter changed');entry.setter=setter end
 end
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
 observeWalking()
 for action,record in pairs(preparations)do
  local proof=record.proof
  assert(proof.sameOperation and queue():indexOf(action)==-1,'native preparation retained or unpaired')
  if proof.cancelled then assert(not proof.started and not proof.completed,'cancelled preparation executed')
  else
   assert(proof.started and proof.completed and proof.succeeded and proof.resolution and proof.walks
    and proof.children==#proof.walks,'native radio preparation did not complete with its exact expansion')
   assert(proof.children==(proof.resolution.noMovement and 0 or 1),'native radio expansion differs from the native near predicate')
   for _,walk in ipairs(proof.walks)do assert(walk.started and walk.progress and walk.completed and walk.succeeded
    and walk.atDestination and walk.nativeCallbacks and walk.sameOperation and walk.starts==1 and walk.duration==-1,
    'native radio walking child lifecycle/arrival missing')end
  end
 end
end
watchPreparations=function()
 walkClass,walkParent=ISWalkToTimedAction,getmetatable(ISWalkToTimedAction)
 walkMethods={}
 for _,name in ipairs(walkNames)do walkMethods[name]=ISWalkToTimedAction[name]end
 for _,name in ipairs({'new','start','update','stop','perform','isValid'})do
  local ok,path=pcall(getFilenameOfClosure,walkMethods[name])
  assert(ok and type(path)=='string'and path:gsub('\\','/'):match('([^/]+)$')=='WalkToTimedAction.lua',
   'native radio walking method source differs: '..name)
 end
 assert(T.ActionQueueLifecycle.registerObserver('fixture.radio-settings-preparation',{
  started=function(action)
   local entry=walking[action]
   if entry then
    assert(nativeWalkUnchanged(action)and queue().current==action and queue().queue[1]==action,'native radio walking ownership changed')
    local proof=entry.proof;proof.starts=proof.starts+1;assert(proof.starts==1,'native radio walking child replayed')
    proof.started=true;proof.startedAt=getTimestampMs()
    proof.startPosition={x=getPlayer():getX(),y=getPlayer():getY(),z=getPlayer():getZ()};return
   end
   local record=preparations[action];if not record then return end
   assert(T.ActionQueueApproach.isAction(action)and queue().current==action,'preparation started without ownership')
   record.proof.started=true
  end,
  begin=function(action,step)
   local record=preparations[action];if not record or step~='perform'then return end
   local q=queue()
   if type(raw)=='function'then
    local diagnostic=preparationDiagnostic(action)
    record.begin={name=diagnostic.name,setter=diagnostic.setter,setterName=diagnostic.setterName,
     selected=diagnostic.selected,current=diagnostic.current,queue=diagnostic.queue,pose=diagnostic.pose}
    raw('PREPARATION_BEGIN',diagnostic)
   end
   assert(T.ActionQueueApproach.isAction(action)and q.current==action and q.queue[1]==action,'preparation lost resolver ownership')
   local args=action.toolkitQueueCommand.snapshot.args
   assert(args.n==3 and args[1]==getPlayer()and args[2]==record.device:getSquare()and args[3]==true,'native radio route intent changed')
   local resolution=nativeNear(getPlayer(),args[2]);local children,seen={},{}
   if record.setter then assert(record.setter.toolkitQueueOperation==action.toolkitQueueOperation,'native radio setter operation changed')end
   local index=2
   while q.queue[index]and q.queue[index]~=record.setter do
    local child=q.queue[index]
    if not record.setter and child.toolkitQueueOperation~=action.toolkitQueueOperation then break end
    assert(child.character==getPlayer()and child.toolkitQueueOperation==action.toolkitQueueOperation
     and nativeWalkUnchanged(child)and not child.action and not child.started,'foreign or active radio walking child')
    assert(not walking[child],'native radio child admitted twice')
    local location=child.location
    assert(instanceof(location,'IsoGridSquare')and getCell():getGridSquare(location:getX(),location:getY(),location:getZ())==location,
     'native radio child destination is unavailable')
    local proof={type=child.Type,duration=child.maxTime,sameOperation=true,nativeCallbacks=true,starts=0,
     started=false,progress=false,completed=false,succeeded=false,atDestination=false,
     destination={x=location:getX(),y=location:getY(),z=location:getZ()}}
    children[#children+1]=proof;seen[child]=true
    walking[child]={proof=proof,record=record,preparation=action,setter=record.setter,token=action.toolkitQueueOperation}
    index=index+1
   end
   if record.setter then assert(q.queue[index]==record.setter,'native radio expansion lost its exact original setter')end
   for _,member in ipairs(q.queue)do
    assert(member==action or member==record.setter or member.toolkitQueueOperation~=action.toolkitQueueOperation or seen[member],
     'unexpected work shares the native radio operation')
   end
   record.proof.resolution,record.proof.walks,record.proof.children=resolution,children,#children
   assert(#children==(resolution.noMovement and 0 or 1),'native radio child count differs from the native near predicate')
  end,
  finish=function(action,step,succeeded)
   local entry=walking[action]
   if entry and step=='perform'then
    local proof=entry.proof;local player=getPlayer()
    assert(nativeWalkUnchanged(action),'native radio child callback changed before completion')
    proof.completed=succeeded==true;proof.succeeded=action.result==BehaviorResult.Succeeded
    proof.completedAt=getTimestampMs()
    proof.atDestination=player:getSquare()==action.location and player:getCurrentSquare()==action.location
    proof.arrival={x=player:getX(),y=player:getY(),z=player:getZ()};return
   end
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
 observeWalking()
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
 walking={}
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
