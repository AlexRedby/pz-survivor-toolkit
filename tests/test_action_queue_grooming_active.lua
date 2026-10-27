if not NativeActionRoot then print('Active grooming contracts SKIP.');return end
local function text(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local value=file:read('*a');file:close();return value:gsub('\r','')
end
local function setup(kind,client,options)
 options=options or{}
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 for _,name in ipairs({'ISCutHair','ISTrimBeard','ISDyeHair'})do f.native('shared/TimedActions/'..name..'.lua')end
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
 getGameFilesInput=function(path)
  local source=text(NativeActionRoot..'/'..path:gsub('^media/lua/',''));local at=1
  return {close=function()end,readLine=function()
   if at>#source then return end
   local last=source:find('\n',at,true)or #source+1;local line=source:sub(at,last-1);at=last+1;return line
  end}
 end
 local receive,live,enabled,now=nil,{},true,1000
 isClient=function()return client end;isServer=function()return false end
 Events.OnServerCommand.Add=function(callback)receive=callback end
 getTimestampMs=function()return now end
 PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
 local player=f.player;player.class='IsoPlayer'
 player.isLocalPlayer=function()return true end
 player.getOnlineID=function()return 101 end
 player.getCharacterActions=function()return {contains=function(_,native)return live[native]==true end}end
 player.setIsFarming=function()end
 player.getEmitter=function()return {isPlaying=function()return true end}end
 player.stops=0;player.stopOrTriggerSound=function()player.stops=player.stops+1 end
 player.pressedCancelAction=function()return false end
 local tool=f.item(kind=='ISDyeHair'and'Base.HairDyeCommon'or'Base.Scissors')
 tool.setJobDelta=function(_,value)tool.delta=value end
 f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');f.project('ActionQueueLabels')
 local savedRequire=require
 local grooming=options.earlyGrooming and f.project('ActionQueueGrooming')or nil
 require=function(name)
  if name=='PZSurvivorToolkit/ActionQueueGrooming'then grooming=grooming or f.project('ActionQueueGrooming');return grooming end
  if name=='PZSurvivorToolkit/ActionQueuePolicy'then return f.project('ActionQueuePolicy')end
  return savedRequire(name)
 end
 if options.foreignForceStop then ISBaseTimedAction.forceStop=function(action)action.character.foreignEffect=true end end
 if options.foreignStop then
  local original=ISBaseTimedAction.stop
  ISBaseTimedAction.stop=function(action)return original(action)end
 end
 local api=f.project('ActionQueue');local policy=PZSurvivorToolkit.ActionQueuePolicy
 local class=_G[kind]
 local body=kind=='ISCutHair'and class:new(player,'GreasedBack',tool,300)
  or kind=='ISTrimBeard'and class:new(player,'',tool)or class:new(player,tool,false)
 body.toolkitQueueOperation={}
 local tail=f.action(ISReadABook,{item=f.item('Base.BookFirstAid1')})
 local queue=f.queue(body,tail)
 local native={owner=body,started=true}
 function native:isStarted()return self.started end
 function native:finished()return self.done==true end
 function native:isForceComplete()return self.forcedComplete==true end
 function native:getTable()return self.owner end
 function native:forceStop()self.stopping=true end
 function native:getJobDelta()return .5 end
 body.action=native;live[native]=true;body.sound=123
 if client then body.toolkitNativeTransaction=7;body.toolkitNativeKind=kind end
 local function receipt(state)
  receive('PZSurvivorToolkitActions','State',{protocol=1,player=101,transaction=7,kind=kind,
   token='11111111-1111-4111-8111-111111111111',state=state})
 end
 return {f=f,api=api,policy=policy,body=body,tail=tail,queue=queue,native=native,tool=tool,player=player,
  receipt=receipt,remove=function()live[native]=nil end,enabled=function(value)enabled=value end,
  advance=function(value)now=now+value end}
end
for _,kind in ipairs({'ISCutHair','ISTrimBeard','ISDyeHair'})do
 for _,client in ipairs({false,true})do
  local s=setup(kind,client)
  if client then
   assert(not s.policy.stoppable(s.body)and not s.api.cancelOperation(s.queue,s.body),'unacknowledged Host body gained interruption')
   s.receipt('started')
  end
  local contract=assert(s.policy.inspect(s.body))
  assert(contract.interrupt=='audited-stop'and contract.cancelOperation and not contract.cancelWaiting
   and not contract.knownInputs and not contract.preparationFinish,'active grooming gained the wrong contract')
  assert(s.policy.stoppable(s.body),'reviewed native body did not gain interruption')
  local accepted,reason=s.api.cancelOperation(s.queue,s.body)
  assert(accepted,'source-bound native grooming cancellation rejected: '..tostring(reason))
  assert(s.native.stopping and s.queue.current==s.body and s.queue.queue[2]==s.tail,'cancel did not request native stop/retain tail')
  s.body:stop()
  assert(s.queue.toolkitCancelStopped and s.queue.queue[2]==s.tail,'native stop reset the unrelated tail')
  if kind~='ISDyeHair'then assert(s.player.stops==1,'native sound cleanup was skipped')end
  if kind=='ISCutHair'then assert(s.tool.delta==0,'native item job cleanup was skipped')end
  if client then
   s.receipt('canceled')
   assert(not s.policy.stoppable(s.body),'terminal server receipt retained active interruption')
  end
 end
end
print('PASS actual queue contracts request native grooming stops and preserve native cleanup/independent tail in SP/Host source models')
for _,kind in ipairs({'ISCutHair','ISTrimBeard','ISDyeHair'})do
 for _,case in ipairs({'unstarted','finished','force-complete','stale','foreign-owner','wrong-head','wrong-current','foreign-stop','foreign-force-stop','late-force-stop','modified-method','callback','disabled'})do
  local s=setup(kind,false,{foreignStop=case=='foreign-stop',foreignForceStop=case=='foreign-force-stop'})
  if case=='unstarted'then s.native.started=false
  elseif case=='finished'then s.native.done=true
  elseif case=='force-complete'then s.native.forcedComplete=true
  elseif case=='stale'then s.remove()
  elseif case=='foreign-owner'then s.native.owner=s.tail
  elseif case=='wrong-head'then s.queue.queue[1]=s.tail
  elseif case=='wrong-current'then s.queue.current=s.tail
  elseif case=='late-force-stop'then ISBaseTimedAction.forceStop=function()end
  elseif case=='modified-method'then s.body.stop=function()end
  elseif case=='callback'then s.body.onCompleteFunc=function()end
  elseif case=='disabled'then s.enabled(false)end
  assert(case=='disabled'or not s.policy.stoppable(s.body),'invalid active episode retained contract: '..kind..' '..case)
  assert(not s.api.cancelOperation(s.queue,s.body),'invalid active episode was canceled: '..kind..' '..case)
  assert(not s.native.stopping,'invalid active episode requested native stop')
 end
 local s=setup(kind,true);s.receipt('started');s.receipt('completed')
 assert(not s.policy.stoppable(s.body)and not s.api.cancelOperation(s.queue,s.body),'earned completion retained interruption rights')
end
print('PASS stale/foreign/native-terminal/modified/disabled grooming and completed server outcomes stay protected')

-- The real 000ToolkitGeneratorCompatibility entrypoint loads Policy/Grooming
-- through Generators before Queue has required Lifecycle/Acknowledgements.
for _,kind in ipairs({'ISCutHair','ISTrimBeard','ISDyeHair'})do
 local s=setup(kind,false,{earlyGrooming=true})
 assert(s.policy.stoppable(s.body),'early generator/Policy bootstrap froze missing interruption dependencies')
 assert(s.api.cancelOperation(s.queue,s.body),'early source-bound grooming cancellation was not admitted')
end
print('PASS early generator/Policy bootstrap binds interruption only after the owned Queue stop bridge exists')
