-- Fixture-only callback provenance. Exact native constructors remain unmodified;
-- the one allowed local stop wrapper still invokes its captured native delegate.
local M={}
local methods={'new','isValid','isValidStart','waitToStart','start','update','perform','complete','stop','getDuration',
 'animEvent','serverStart','serverStop','forceStop','forceCancel','begin','create','forceComplete','setOnComplete'}
local custom={'onStartFunc','onCancelFunc','onCompleteFunc','onCompleteArgs','onCompleteTarget','onFailFunc',
 'additionalTest','toolkitQueueSafeOnComplete'}
local sources={
 {'client','BulkActions.lua',3109997898},
 {'client','ActionQueuePolicy.lua',2419922613},
 {'shared','SourceProof.lua',3444982222},
}
-- Full native compilation of BulkActions: root child6/child1; creation pc32
-- captures parent register4 (the original transfer.stop) into slot0.
local stopFingerprint='d56b01558730b799ff5a022ed70b3a589bc1816f3f2d16ae82be9f79e490bf5a'
function M.new(toolkit,config,proof,classes)
 local policy,bulk=toolkit.ActionQueuePolicy,toolkit.BulkActions
 local matcher,guarded=policy and policy.matchesNative,bulk and bulk.isGuardedTransfer
 local own,closure,capture,matches=proof.own,proof.closure,proof.captureBindings,proof.matches
 local filename,line=getFilenameOfClosure,getFirstLineOfClosure
 local guardFactory=bulk and bulk.guardTransfer
 local valueType,valueMeta,valuePairs,valueEach=type,getmetatable,pairs,ipairs
 local execution,pickup=toolkit.ActionQueueExecution,toolkit.ActionQueuePickupFailure
 local executionStop,pickupStop=execution and execution.beforeStop,pickup and pickup.beforeStop
 local client,done,rejected,remove=isClient,isItemTransactionDone,isItemTransactionRejected,removeItemTransaction
 local facts,api=toolkitLuaCaptureFactsMatch,toolkitLuaCaptureFactsApiMatches
 assert(type(matcher)=='function'and type(guarded)=='function'and type(facts)=='function'and type(api)=='function'
  and api(facts)==true,'native callback observation API unavailable')
 assert(closure(matcher,'ActionQueuePolicy.lua')and closure(guarded,'BulkActions.lua')
  and closure(own,'SourceProof.lua')and closure(capture,'SourceProof.lua')and closure(matches,'SourceProof.lua'),
  'callback observation source bindings unavailable')
 local function publicCurrent()
  return PZSurvivorToolkit==toolkit and toolkit.ActionQueuePolicy==policy and toolkit.BulkActions==bulk
   and policy.matchesNative==matcher and bulk.isGuardedTransfer==guarded and bulk.guardTransfer==guardFactory
   and proof.own==own and proof.closure==closure and proof.captureBindings==capture and proof.matches==matches
   and toolkitLuaCaptureFactsMatch==facts and toolkitLuaCaptureFactsApiMatches==api
   and getFilenameOfClosure==filename and getFirstLineOfClosure==line
   and type==valueType and getmetatable==valueMeta and pairs==valuePairs and ipairs==valueEach
   and toolkit.ActionQueueExecution==execution and toolkit.ActionQueuePickupFailure==pickup
   and(not execution or execution.beforeStop==executionStop)and(not pickup or pickup.beforeStop==pickupStop)
   and isClient==client and isItemTransactionDone==done and isItemTransactionRejected==rejected and removeItemTransaction==remove
 end
 local globals={'type','getmetatable','pairs','ipairs','isClient','isItemTransactionDone','isItemTransactionRejected','removeItemTransaction','PZSurvivorToolkit','getFilenameOfClosure','getFirstLineOfClosure','toolkitLuaCaptureFactsMatch','toolkitLuaCaptureFactsApiMatches'}
 local baselines={}
 for _,class in ipairs(classes)do
  local baseline={class=class,methods={},own={}}
  for _,name in ipairs(methods)do baseline.methods[name]=class[name]or false end
  for name,value in pairs(class)do if type(value)=='function'then baseline.own[name]=value end end
  baselines[class.Type]=baseline;globals[#globals+1]=class.Type
 end
 for _,source in ipairs(sources)do
  -- Only the archived pre-simplification work profile uses this reviewed
  -- Policy/SourceProof bodies; ordinary runs retain the current exact pins.
  local adler=source[3]
  if config.options and config.options.equip_workload_baseline==true then
   assert(config.options.equip_workload==true,'baseline callback proof requires work profile')
   if source[2]=='ActionQueuePolicy.lua'then adler=3807387550
   elseif source[2]=='SourceProof.lua'then adler=4031039642 end
  end
  assert(matches('media/lua/'..source[1]..'/PZSurvivorToolkit/'..source[2],adler,'PZSurvivorToolkit',true)==true,
   'callback observation source bytes changed '..source[2])
 end
 assert(publicCurrent(),'callback observation source-read rebound a captured API')
 local dependencies={{owner=_G,keys=globals},{owner=toolkit,keys={'ActionQueuePolicy','BulkActions','ActionQueueExecution','ActionQueuePickupFailure'}},
  {owner=policy,keys={'matchesNative'}},{owner=bulk,keys={'isGuardedTransfer','guardTransfer'}},
  {owner=proof,keys={'own','closure','captureBindings','matches'}},{owner=config,keys={'mode','kind'}}}
 if execution then dependencies[#dependencies+1]={owner=execution,keys={'beforeStop'}}end
 if pickup then dependencies[#dependencies+1]={owner=pickup,keys={'beforeStop'}}end
 local watch=assert(capture(dependencies),'callback observation binding capture unavailable')
 assert(publicCurrent()and watch(),'callback observation capture rebound a captured API')
 local observer={}
 function observer.track(action)
  local baseline=assert(baselines[action.Type],'unrecognized native callback class')
  local admittedStop,admittedGuard
  return function(stage)
   local value={schema=1,sourceVerified=true,bindingsCurrent=publicCurrent()and watch()==true,classUnchanged=true,
    customCallbacksAbsent=true,differences={},verified=false}
   local seen={}
   local function difference(scope,name,callback)
    local key=scope..':'..tostring(name);if seen[key]then return end;seen[key]=true
    local source,first=false,false
    if type(callback)=='function'then
     local path=filename(callback);source=type(path)=='string'and path:gsub('\\','/'):match('([^/]+)$')or false
     first=line(callback);if type(first)~='number'or first<1 or first%1~=0 then first=false end
    end
    local row={scope=scope,method=tostring(name),source=source,line=first}
    value.differences[#value.differences+1]=row;return row
   end
   local class=baseline.class
   if getmetatable(action)~=class or _G[action.Type]~=class then value.classUnchanged=false end
   for _,name in ipairs(methods)do
    local expected=baseline.methods[name]
    if (class[name]or false)~=expected then value.classUnchanged=false;difference('class',name,class[name])end
    if (action[name]or false)~=expected then difference('action',name,action[name])end
   end
   local count=0
   for name,callback in pairs(class)do
    count=count+1;if count>128 then value.classUnchanged=false;difference('class','field-bound',nil);break end
    if type(callback)=='function'and baseline.own[name]~=callback then value.classUnchanged=false;difference('class',name,callback)end
   end
   for name,callback in pairs(baseline.own)do if own(class,name)~=callback then value.classUnchanged=false;difference('class',name,class[name])end end
   count=0
   for name,callback in pairs(action)do
    count=count+1;if count>128 then difference('action','field-bound',nil);break end
    if type(callback)=='function'then difference('action',name,callback)end
   end
   for _,name in ipairs(custom)do
    if action[name]~=nil then value.customCallbacksAbsent=false;difference('action',name,action[name])end
   end
   if admittedStop and (own(action,'stop')~=admittedStop or own(action,'toolkitTransferGuard')~=admittedGuard)then
    difference('action','stop-history',action.stop)
   end
   if #value.differences==1 then
    local change=value.differences[1];local stop=own(action,'stop');local guard=own(action,'toolkitTransferGuard')
    if config.mode=='toolkit'and config.kind=='mp'and action.Type=='ISInventoryTransferAction'
     and change.scope=='action'and change.method=='stop'and value.classUnchanged and value.customCallbacksAbsent
     and value.bindingsCurrent and type(guard)=='table'and getmetatable(guard)==nil and type(stop)=='function'
     and own(guard,'stop')==stop and own(guard,'original')==baseline.methods.stop then
     local recipe={fingerprint=stopFingerprint,parameters=1,upvalues=1,
      captures={{slot=0,test='identity',value=baseline.methods.stop}}}
     change.originalBaseline=own(guard,'original')==baseline.methods.stop
     change.guardedTransfer=guarded(action,baseline.methods.stop)==true
     change.exactStopCapture=api(facts)==true and facts(stop,recipe)==true
     if stage=='admission'and change.guardedTransfer and change.exactStopCapture and closure(stop,'BulkActions.lua')
      and matcher(action)==true and publicCurrent()and watch()then admittedStop,admittedGuard=stop,guard end
     change.nativeBindingAtAdmission=admittedStop==stop and admittedGuard==guard
     value.verified=change.originalBaseline and change.guardedTransfer and change.exactStopCapture
      and change.nativeBindingAtAdmission and change.source=='BulkActions.lua'and type(change.line)=='number'
    end
   elseif #value.differences==0 then value.verified=true end
   value.bindingsCurrent=value.bindingsCurrent and publicCurrent()and watch()==true
   value.verified=value.verified and value.bindingsCurrent and value.classUnchanged and value.customCallbacksAbsent
   return value
  end
 end
 return observer
end
return M
