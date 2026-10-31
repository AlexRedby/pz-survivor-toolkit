-- Exercise the actual coordinator after a post-Prepare local failure. A runner
-- marker must wait for owned cleanup and complete original/UI/position return.
local nativePrint=print
local function run(kind,stuck,lateDone,duplicateCapture,failedDispatch)
 local clock,owned,restored,positionReturned=0,false,false,false
 local paused,speedCalls=true,0
 local errorText
 local callbacks,logs,effects,commands={},{},{},{}
 print=function(value)logs[#logs+1]=value end
 local function event(name)return {Add=function(fn)callbacks[name]=fn end}end
 Events={OnTick=event('tick'),OnServerCommand=event('server'),OnMainMenuEnter=event('menu'),OnGameStart=event('game'),OnPreUIDraw=event('draw')}
 local selection={kind=kind,cases={'walk'},mode='toolkit'}
 local packet={token='walking-client-failure',crates={},originalRootIds={client1={1}},originalEquipment={client1={}},actorOrigins={client1={x=98,y=98,z=0}},routeOrigins={client1={x=100,y=98,z=0}}}
 local F={initialTransport='fixture-transport',cleanupTransport='fixture-cleanup-transport',module='WarehouseWalkingTest',phases={{paneMode='clean'}}}
 function F.context(state,row)row=row or {};row.token=state and state.token;row.index=state and state.nextIndex or 1;return row end
 function F.emit(name,row)
  row=row or {};row.role=row.role or'server';logs[#logs+1]='[WAREHOUSE_WALKING] '..name..' role='..row.role
  if name=='FAIL'then effects[#effects+1]='terminal'end
  if name=='ERROR'then errorText=row.error end
 end
 function F.sessionToken()return packet.token end
 function F.capture()return {token=packet.token,ids=packet,nextIndex=1}end
 function F.materialize()owned=true end
 function F.resolve()return {token=packet.token}end
 function F.abort()owned=false;effects[#effects+1]='cleanup';return {token=packet.token,crates={},cleanupTransport=F.cleanupTransport}end
 function F.absent()return not owned end
 local inventory={getItems=function()return {size=function()return owned and 8 or 0 end}end}
 local pages={}
 for i=1,2 do
  local pane={inventory=inventory};local page={inventoryPane=pane}
  for name,value in pairs({X=0,Y=0,Width=590,Height=740})do
   page['get'..name]=function()return value end;pane['get'..name]=function()return value end
  end;pages[i]=page
 end
 local U={pages=function()return pages end,normalize=function()end}
 function U.save()return {}end
 function U.original()return {}end
 function U.originalProof()assert(not restored or not owned);return {ids={1},identity=true,payload=true,equipment=true}end
 function U.position()return {x=10.5,y=10.5,z=0,squareX=10,squareY=10,squareZ=0}end
 function U.protect()end
 function U.configure()error('injected configuration failure')end
 function U.place(_,transition)
  if transition.target.x==10.5 then positionReturned=true;effects[#effects+1]='position'end
  return {target=transition.target}
 end
 function U.restore()assert(not owned and positionReturned,'UI restored before owned cleanup/position');if lateDone then error('late original UI restoration failure')end;restored=true;effects[#effects+1]='ui';return {}end
 function U.flags()end
 local N={}
 function N.idle()return not(stuck and owned)end
 function N.abortProfile()end
 function N.saveLock()return {}end
 function N.restoreLock()end
 function N.restoreLockGlobals()end
 function N.finishLockRestoration()return {restored=true,methodUnchanged=true}end
 local player={}
 function player:getInventory()return inventory end
 function player:getPlayerNum()return 0 end
 function player:getSquare()return {}end
 function player:getUsername()return 'client1'end
 function player:getOnlineID()return 1 end
 function getPlayer()return player end
 function getPlayerInventory()return pages[1]end
 function getPlayerLoot()return pages[2]end
 function getTimestampMs()return clock end
 function isIngameState()return true end
 function isGamePaused()return paused end
 function setGameSpeed(value)assert(value==1);speedCalls=speedCalls+1;paused=false end
 function isClient()return kind=='mp'end
 local function dispatch(module,command,args)
  commands[#commands+1]={command=command,args=args}
  if command=='Prepare'then callbacks.server(module,'CaptureBaseline',{token=packet.token});if duplicateCapture then callbacks.server(module,'CaptureBaseline',{token=packet.token})end
  elseif command=='Baseline'then F.capture();callbacks.server(module,'Normalize',{ids=packet,role='client1'})
  elseif command=='Normalized'then F.materialize();callbacks.server(module,'Prepared',{ids=packet,role='client1'});if lateDone then local cleanup=F.abort();callbacks.server(module,'Done',cleanup)end
  elseif command=='Abort'then callbacks.server(module,'AbortRequested',{token=packet.token,error='injected configuration failure'})
  elseif command=='AbortReady'then local cleanup=F.abort();callbacks.server(module,'Abortd',{restored=true,cleanup=cleanup,cleanupTransport=F.cleanupTransport})
  elseif command=='AbortRestored'then assert(not owned and restored and positionReturned and args.restored and args.token==packet.token,'premature/unbound restoration acknowledgement')end
 end
 function sendClientCommand(module,command,args)
  assert(command~='Prepare'and command~='Baseline'and command~='Normalized','initial command used unordered client sender')
  dispatch(module,command,args)
 end
 function warehouseWalkingOrderedClient(actor,module,command,args)
  assert(actor==player and(command=='Prepare'or command=='Baseline'or command=='Normalized'),'noninitial client command changed transport')
  if failedDispatch==command then return nil end
  dispatch(module,command,args);return true
 end
 for name,value in pairs({QueueTestSelection=selection,WarehouseWalkingFixture=F,WarehouseWorkloadUI=U,WarehouseWalkingNative=N,WarehouseWalkingActor={save=function()return {}end,detach=function(s)s.detached=true end,restore=function(s)s.restored=true end,baseline=function()return {}end,equipmentProof=function()return {}end,originalProof=function()return {}end,matchBaseline=function()end,normalizedProof=function()return {rootEmpty=true,equipmentEmpty=true,originalsStashed=true}end}})do
  package.loaded[name]=nil;package.preload[name]=function()return value end
 end
 dofile(ProjectRoot..'/tests/native_queue/warehouse-walking/client/ZZWarehouseWalking.lua')
 if kind=='sp'then
  callbacks.draw();assert(paused and speedCalls==0,'SP resumed before world entry')
  callbacks.game();assert(paused and not owned,'world entry must not initialize the first-tick fixture')
  callbacks.draw();assert(not paused and speedCalls==1 and not owned,'paused world entry deadlocked before first OnTick')
 end
 for _=1,20 do clock=clock+(stuck and 5000 or 200);callbacks.tick()end
 local early,abort,terminal
 for i,line in ipairs(logs)do
  if line:find('[WAREHOUSE_WALKING] ERROR ',1,true)then early=early or i end
  if line:find('[WAREHOUSE_WALKING] ABORT ',1,true)then abort=abort or i end
  if line:find('[WAREHOUSE_WALKING] FAIL ',1,true)or line:find('[QUEUE_TEST] FAIL ',1,true)then terminal=terminal or i end
 end
 assert(early and abort and early<abort,'missing diagnostic-first abort lifecycle')
 for i=early,abort-1 do assert(not logs[i]:find('[QUEUE_TEST] FAIL ',1,true)and not logs[i]:find('[WAREHOUSE_WALKING] FAIL ',1,true),'early failure would kill restoration')end
 if failedDispatch then assert(errorText and errorText:find('native ordered walking client dispatch failed: '..failedDispatch,1,true),'nil native client sender became a timeout')end
 if failedDispatch=='Prepare'then
  assert(terminal and abort<terminal and restored and not owned,'undispatched Prepare failed before local UI restoration')
  assert(#commands==0,'undispatched Prepare sent an unauthenticated cancellation')
 elseif lateDone then
  assert(terminal and abort<terminal and not restored,'closed coordinator restoration failure never terminated')
  for _,entry in ipairs(commands)do assert(entry.command~='Abort'and entry.command~='AbortRestored','closed coordinator received unusable abort request')end
 elseif kind=='sp'then
  assert(terminal and abort<terminal,'SP terminal failure preceded ABORT')
  if not stuck then assert(not owned and restored and effects[#effects]=='terminal','SP failed before full restoration')end
 else
  assert(not terminal and restored and not owned,'MP client killed pending peer restoration')
  assert(commands[#commands].command=='AbortRestored','MP original restoration never acknowledged')
 end
end
run('sp',false);run('mp',false);run('sp',true);run('mp',false,true);run('mp',false,false,true);run('mp',false,false,false,'Prepare');run('mp',false,false,false,'Baseline');run('mp',false,false,false,'Normalized')
print=nativePrint
