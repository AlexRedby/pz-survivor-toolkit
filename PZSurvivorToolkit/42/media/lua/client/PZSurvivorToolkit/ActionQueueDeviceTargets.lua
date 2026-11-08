-- Pending admission only. Native effects, paid completion and networking retain
-- their existing owners; this module never invokes an action callback.
local Toolkit=PZSurvivorToolkit
local Device={}
Toolkit.ActionQueueDeviceTargets=Device
local Proof=require 'PZSurvivorToolkit/SourceProof'
local origin,capture=Proof and Proof.closure,Proof and Proof.captureBindings
local kind,meta,each,pairsOf,equal,call,raw,set=type,getmetatable,ipairs,pairs,rawequal,pcall,rawget,rawset
local actualMeta=toolkitLuaMetatableMatches
local globals=_G
local strings,stringSubstitute,stringMatch=string,string.gsub,string.match
local filenameAccessor=getFilenameOfClosure
local api={read=toolkitQueueDeviceTarget,check=toolkitQueueDeviceApiMatches,classify=getClassSimpleName,call=pcall}
local slot,sealSlot,nonce={},{},{}
local installed
local file='ActionQueueDeviceTargets.lua'
local modes={ToggleOnOff=true,SetChannel=true,SetVolume=true,MuteVolume=true,UnMuteVolume=true,
 MuteMicrophone=true,TogglePlayMedia=true,AddHeadphones=true,RemoveHeadphones=true}
local immutable={'character','toolkitQueueOperation','device','deviceData','mode','secondaryItem','isRemove','parameter',
 'stopOnWalk','stopOnRun','ignoreHandsWounds','maxTime','onStartFunc','onCompleteFunc','onCancelFunc',
 'onFailFunc','additionalTest','retriggerLastAction'}
local function actualPlain(owner)
 if kind(owner)~='table'or meta(owner)~=nil or kind(actualMeta)~='function'then return false end
 local ok,value=call(actualMeta,owner,nil)
 return ok and value==true
end
local function own(owner,key)
 if kind(owner)~='table'then return end
 -- Kahlua rawget follows inheritance. Use it only after the captured native
 -- identity predicate proves the ACTUAL metatable is nil, including protection.
 -- Plain env/module lookups remain O(1) even with hundreds of native globals.
 if actualPlain(owner)then return raw(owner,key)end
 local count=0
 for name,value in pairsOf(owner)do
  count=count+1;if count>128 then return end
  if equal(name,key)then return value end
 end
end
local function plain(value)return actualPlain(value)end
local function accepted(callback,...)
 local ok,value=call(callback,...);return ok and value==true
end
-- These mirrors only read own fields and identities. They perform no source IO,
-- native getters or Lua metatable lookup after the final Java world observation.
local function mirror(specifications)
 local records={}
 for _,spec in each(specifications)do
  local owner=spec.owner;if kind(owner)~='table'then return end
  local entries,count={},0
  if spec.exact then
   for key,value in pairsOf(owner)do
    count=count+1;if count>128 then return end
    entries[#entries+1]={key,value}
   end
  else
   for _,key in each(spec.keys)do entries[#entries+1]={key,own(owner,key)}end
  end
  records[#records+1]={owner=owner,parent=meta(owner),entries=entries,exact=spec.exact,count=count}
 end
 return function()
  for _,record in each(records)do
   if not equal(meta(record.owner),record.parent)then return false end
   for _,entry in each(record.entries)do if not equal(own(record.owner,entry[1]),entry[2])then return false end end
   if record.exact then
    local count=0;for _ in pairsOf(record.owner)do count=count+1;if count>record.count then return false end end
    if count~=record.count then return false end
   end
  end
  return true
 end
end
local function primitives()
 -- Establish the actual plain env before reading any possibly inherited global.
 return plain(globals)and equal(raw(globals,'toolkitLuaMetatableMatches'),actualMeta)
  and equal(raw(globals,'type'),kind)and equal(raw(globals,'getmetatable'),meta)
  and equal(raw(globals,'ipairs'),each)and equal(raw(globals,'pairs'),pairsOf)
  and equal(raw(globals,'rawequal'),equal)and equal(raw(globals,'pcall'),call)
  and equal(raw(globals,'rawget'),raw)and equal(raw(globals,'rawset'),set)
  and equal(raw(globals,'getFilenameOfClosure'),filenameAccessor)
  and equal(own(Proof,'closure'),origin)and equal(own(Proof,'captureBindings'),capture)
  and equal(raw(globals,'string'),strings)and plain(strings)
  and equal(raw(strings,'gsub'),stringSubstitute)and equal(raw(strings,'match'),stringMatch)
  and equal(raw(globals,'PZSurvivorToolkit'),Toolkit)and equal(own(Toolkit,'ActionQueueDeviceTargets'),Device)
  and equal(raw(globals,'toolkitQueueDeviceTarget'),api.read)
  and equal(raw(globals,'toolkitQueueDeviceApiMatches'),api.check)
  and equal(raw(globals,'getClassSimpleName'),api.classify)
end
local function foundation()
 return installed~=nil and primitives()and installed.watch()
end
local function privateSealOrigin(seal)
 -- A seal closes over its action and native world anchor. Never insert these
 -- per-action closures into SourceProof's bounded strong callback memo.
 if kind(filenameAccessor)~='function'then return false end
 local ok,path=call(filenameAccessor,seal)
 return ok and kind(path)=='string'and stringMatch(stringSubstitute(path,'\\','/'),'([^/]+)$')==file
end
local function unseal(action,descriptor)
 if not foundation()or kind(action)~='table'or not plain(descriptor)
  or not equal(own(action,slot),descriptor)then return end
 -- A foreign own-field function is rejected by origin before it can execute.
 local seal=own(descriptor,sealSlot)
 if kind(seal)~='function'or not privateSealOrigin(seal)or not foundation()
  or not equal(own(action,slot),descriptor)or not equal(own(descriptor,sealSlot),seal)then return end
 local ok,state=call(seal,nonce,action,descriptor)
 if ok and kind(state)=='table'and equal(state.action,action)and equal(state.descriptor,descriptor)then return state end
end
local function stateOf(action)
 return unseal(action,own(action,slot))
end
local function remember(action,state)
 local descriptor={}
 descriptor[sealSlot]=function(key,candidate,value)
  if equal(key,nonce)and equal(candidate,action)and equal(value,descriptor)then return state end
 end
 state.action,state.descriptor=action,descriptor
 set(action,slot,descriptor)
 return descriptor
end
local function bind(action,state)
 if not state.bound and foundation()and accepted(installed.bind,action,state.descriptor)then state.bound=true end
end
local function source(action,device)
 if not foundation()then return end
 local specifications={{owner=action,keys=device and immutable or {'character','toolkitQueueOperation'}}}
 local seen={}
 local function lineage(value,depth)
  if value==nil then return true end
  if kind(value)~='table'or depth>8 then return false end
  if seen[value]then return true end
  seen[value]=true;specifications[#specifications+1]={owner=value,exact=true}
  local index=own(value,'__index')
  if index~=nil and kind(index)~='table'then return false end
  return lineage(meta(value),depth+1)and(index==nil or equal(index,value)or lineage(index,depth+1))
 end
 if not lineage(meta(action),1)then return end
 -- The existing actual-metatable checker rejects protected/foreign inheritance
 -- during preparation. The retained final watcher below uses only raw mirrors.
 local certificate=capture(specifications)
 if kind(certificate)~='function'or not certificate()or not foundation()then return end
 local watch=mirror(specifications)
 if not watch then return end
 return function()
  if not foundation()or not watch()then return false end
  if device then
   local count=0
   for key,value in pairsOf(action)do
    count=count+1;if count>128 then return false end
    if kind(value)=='function'and not equal(key,slot)then return false end
   end
  end
  return true
 end,certificate
end
local function certified(watch)
 if not foundation()or not watch()then return false end
 local ok,name=call(api.classify,api.check)
 if not ok or name~='LuaJavaInvoker'and name~='MultiLuaJavaInvoker'or not watch()then return false end
 local certified,yes=call(api.check,api.read)
 return certified and yes==true and watch()and foundation()
end
local function localActor(actor,watch)
 if not watch()then return false end
 local ok,name=call(api.classify,actor)
 if not ok or name~='IsoPlayer'or not watch()then return false end
 for index=0,3 do
  local observed,player=call(installed.player,index)
  if not observed or not watch()then return false end
  if equal(player,actor)then return true end
 end
 return false
end
local function pending(action,state)
 return not state.admitted and not state.revoked and own(action,'action')==nil and not own(action,'started')
  and own(action,'toolkitNativeTransaction')==nil and own(action,'toolkitNativeKind')==nil
  and(own(action,'transactionId')==nil or own(action,'transactionId')==0)
end
local function positionSource(state)
 return state.source()and accepted(state.certificate)and accepted(state.positionWatch)and state.source()
end
local function link(position,device)
 if position.revoked or device.revoked or position.role~='position'or device.role~='device'
  or not equal(own(position.action,'character'),own(device.action,'character'))
  or not equal(own(position.action,'toolkitQueueOperation'),own(device.action,'toolkitQueueOperation'))then return false end
 if position.device and not equal(position.device,device.descriptor)then position.revoked=true;return false end
 if not positionSource(position)or not device.source()or not certified(device.source)then return false end
 local ok,value=call(api.read,device.device,device.data,device.anchor,position.square)
 if not ok or value~=true and value~=false or not positionSource(position)or not device.source()then return false end
 position.device=device.descriptor;return true
end
local function adoptPosition(action,parent)
 if not foundation()or own(action,slot)~=nil then return end
 local watch,square
 local ok;ok,watch,square=call(installed.position,action,parent)
 if not ok or kind(watch)~='function'or square==nil or not foundation()then return end
 local guard,certificate=source(action,false)
 if not guard or not localActor(own(action,'character'),guard)or not guard()or not accepted(watch)then return end
 local state={role='position',source=guard,certificate=certificate,positionWatch=watch,square=square}
 remember(action,state);bind(action,state)
 return state
end
local function linkPending(device)
 local queue=ISTimedActionQueue.queues[own(device.action,'character')]
 local list=queue and own(queue,'queue')
 if not plain(list)or #list>32 then return end
 for _,action in each(list)do
  if equal(own(action,'toolkitQueueOperation'),own(device.action,'toolkitQueueOperation'))then
   local position=stateOf(action)
   if not position and equal(meta(action),installed.command)and not own(action,'action')then
    position=adoptPosition(action)
   end
   if position and position.role=='position'and not position.admitted then
    position.deviceAction=device.action;link(position,device)
   end
  end
 end
end
function Device.enqueued(action)
 if kind(action)~='table'or not Device.install()then return end
 local existing=stateOf(action)
 if existing then bind(action,existing);if existing.role=='device'then linkPending(existing)end;return end
 if own(action,slot)~=nil then return end
 local class=meta(action)
 local radio=equal(class,installed.radio)
 local media=equal(class,installed.media)or equal(class,installed.battery)
 if not radio and not media then
  local queue=ISTimedActionQueue.queues[own(action,'character')]
  local list=queue and own(queue,'queue')
  if equal(class,installed.command)and(list==nil or plain(list)and #list==0)then adoptPosition(action)end
  return
 end
 if own(action,'action')or own(action,'started')then return end
 if radio and(not modes[own(action,'mode')]or own(action,'maxTime')~=30
  or own(action,'stopOnWalk')~=false or own(action,'stopOnRun')~=true or own(action,'ignoreHandsWounds')~=true)then return end
 local guard,certificate=source(action,true)
 if not guard or not guard()then return end
 local trusted=radio and accepted(installed.native,action)or not radio and accepted(installed.mediaSupported,action)
 if not trusted or not guard()or not localActor(own(action,'character'),guard)or not certified(guard)then return end
 local device=radio and own(action,'device')or nil
 local data,route=own(action,'deviceData'),media and own(action,'parameter')or nil
 local observed,anchor=call(api.read,device,data,nil,route)
 if not observed or anchor==nil or kind(anchor)=='boolean'or not guard()then return end
 local state={role='device',device=device,data=data,route=route,anchor=anchor,source=guard,certificate=certificate}
 remember(action,state);bind(action,state);linkPending(state)
end
function Device.positionEnqueued(action,parent)
 -- Generic approach expansion pays no source/metadata cost for device binding.
 if not parent or own(parent,slot)==nil or not foundation()then return end
 local previous=stateOf(parent)
 local device=previous and previous.device and unseal(previous.deviceAction,previous.device)
 if not device then return end
 local state=stateOf(action)or adoptPosition(action,parent)
 if state and state.role=='position'then state.deviceAction=device.action;link(state,device)end
end
function Device.admitting(action)
 local state=stateOf(action)
 if not state then return end
 if state.admitted then state.revoked=true;return end
 state.admitted=true
end
function Device.owns(action,descriptor)
 return unseal(action,descriptor)~=nil
end
function Device.validateNativeRole(action,descriptor,stage)
 local state=unseal(action,descriptor)
 if not state or state.revoked or not state.source()then return end
 if state.role=='device'then
  if stage=='pending'and pending(action,state)and accepted(state.certificate)and state.source()then return 'device'end
  return
 end
 if not positionSource(state)or not state.device then return end
 local device=unseal(state.deviceAction,state.device)
 if not device or not device.source()then return end
 if stage=='pending'then if pending(action,state)then return 'position'end
 elseif state.admitted and state.startedObserved and not state.failed
  and equal(state.native,own(action,'action'))then
  if stage=='current-position'and(state.performing or state.performed)then return 'position'end
  if stage=='completed-position'and state.completed then return 'position'end
 end
end
function Device.watchSources(action,descriptor)
 local state=unseal(action,descriptor)
 return state~=nil and not state.revoked and state.source()and accepted(state.certificate)and state.source()
end
function Device.worldLost(action,descriptor)
 local state=unseal(action,descriptor)
 if not state or state.role~='device'or not pending(action,state)or not state.source()
  or not accepted(state.certificate)or not certified(state.source)then return false end
 local observed,value=call(api.read,state.device,state.data,state.anchor,state.route)
 -- No metadata/getter/classifier runs after this final native observation.
 return observed and value==false and state.source()
end
function Device.skipUnavailable(queue,current)
 if not Device.install()or not equal(own(queue,'current'),current)then return false end
 local list=own(queue,'queue')
 if not plain(list)or #list>32 or not equal(list[1],current)then return false end
 local changed=false
 for _=1,32 do
  local first=list[2];if not first then break end
  local token=own(first,'toolkitQueueOperation');if kind(token)~='table'then break end
  local members={}
  for index=2,#list do
   local action=list[index]
   if not equal(own(action,'toolkitQueueOperation'),token)then break end
   members[#members+1]=action
  end
  local state=stateOf(first)
  if not state then break end
  local ok,commit=call(installed.refuse,queue,current,members)
  if not ok or kind(commit)~='function'or not accepted(commit,Device.worldLost,Device.watchSources)then break end
  changed=true
  if not equal(own(queue,'queue'),list)or equal(list[2],first)then break end
 end
 return changed
end
function Device.install()
 if installed then return foundation()end
 if kind(api.read)~='function'or kind(api.check)~='function'or kind(api.classify)~='function'
  or not Proof or kind(origin)~='function'or kind(capture)~='function'or not primitives()then return false end
 local policy,media,approach,settlement,lifecycle=Toolkit.ActionQueuePolicy,Toolkit.ActionQueueMedia,
  Toolkit.ActionQueueApproach,Toolkit.ActionQueueSettlement,Toolkit.ActionQueueLifecycle
 if not plain(policy)or not plain(media)or not plain(approach)or not plain(settlement)or not plain(lifecycle)then return false end
 local native,mediaSupported,position,bindStep,refuse,register=own(policy,'matchesNative'),own(media,'pendingDeviceSupported'),
  own(approach,'prepareDevicePosition'),own(settlement,'bindDeviceStep'),own(settlement,'prepareDeviceRefusal'),own(lifecycle,'registerObserver')
 for _,entry in each({{native,'ActionQueuePolicy.lua'},{mediaSupported,'ActionQueueMedia.lua'},
  {position,'ActionQueueApproach.lua'},{bindStep,'ActionQueueSettlement.lua'},
  {refuse,'ActionQueueSettlement.lua'},{register,'ActionQueueLifecycle.lua'}})do
  if not primitives()or kind(entry[1])~='function'or not origin(entry[1],entry[2])or not primitives()then return false end
 end
 if not equal(Toolkit.ActionQueuePolicy,policy)or not equal(Toolkit.ActionQueueMedia,media)
  or not equal(Toolkit.ActionQueueApproach,approach)or not equal(Toolkit.ActionQueueSettlement,settlement)
  or not equal(Toolkit.ActionQueueLifecycle,lifecycle)or not equal(own(policy,'matchesNative'),native)
  or not equal(own(media,'pendingDeviceSupported'),mediaSupported)or not equal(own(approach,'prepareDevicePosition'),position)
  or not equal(own(settlement,'bindDeviceStep'),bindStep)or not equal(own(settlement,'prepareDeviceRefusal'),refuse)
  or not equal(own(lifecycle,'registerObserver'),register)then return false end
 local watch=mirror({{owner=globals,keys={'PZSurvivorToolkit','toolkitQueueDeviceTarget','toolkitQueueDeviceApiMatches',
  'getClassSimpleName','getSpecificPlayer','getFilenameOfClosure','type','getmetatable','ipairs','pairs','rawequal','pcall','rawget','rawset','toolkitLuaMetatableMatches',
  'ISRadioAction','ISDeviceMediaAction','ISDeviceBatteryAction','ISBaseTimedAction','ISQueueActionsAction','ISTimedActionQueue'}},
  {owner=Toolkit,keys={'ActionQueueDeviceTargets','ActionQueuePolicy','ActionQueueMedia','ActionQueueApproach','ActionQueueSettlement','ActionQueueLifecycle'}},
  {owner=Device,exact=true},{owner=Proof,keys={'closure','captureBindings'}},
  {owner=policy,keys={'matchesNative'}},{owner=media,keys={'pendingDeviceSupported'}},
  {owner=approach,keys={'prepareDevicePosition'}},{owner=settlement,keys={'bindDeviceStep','prepareDeviceRefusal'}},
  {owner=lifecycle,keys={'registerObserver'}}})
 if not watch or not watch()then return false end
 installed={watch=watch,native=native,mediaSupported=mediaSupported,position=position,bind=bindStep,refuse=refuse,
  player=getSpecificPlayer,radio=ISRadioAction,media=ISDeviceMediaAction,battery=ISDeviceBatteryAction,command=ISQueueActionsAction}
 local observer={
  started=function(action)
   local state=stateOf(action)
   if state then
    if not state.admitted or state.startedObserved then state.revoked=true else state.startedObserved=true end
   end
  end,
  begin=function(action,phase)
   local state=stateOf(action)
   if not state or state.role~='position'or phase~='perform'then return end
   if not state.admitted or not state.startedObserved or state.performing or state.performed or not own(action,'action')then
    state.revoked=true;return
   end
   state.native=own(action,'action');state.performing=true
  end,
  finish=function(action,phase,succeeded)
   local state=stateOf(action)
   if not state or state.role~='position'or phase~='perform'then return end
   if not state.performing or not equal(state.native,own(action,'action'))or succeeded~=true then state.failed=true end
   state.performed=succeeded==true and state.performing==true;state.performing=false
  end,
  settled=function(action)
   local state=stateOf(action)
   if state and state.role=='position'and state.performed and not state.failed
    and equal(state.native,own(action,'action'))then state.completed=true end
  end,
 }
 if not accepted(register,'device-target-admission',observer)or not foundation()then installed=nil;return false end
 return true
end
return Device
