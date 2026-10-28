-- Fixture traffic only. Product RPC schemas never receive lifecycle fields.
return function(config,factories,server)
 local participants=config.actors
 if participants==nil then participants={'client1','client2'} end
 assert(type(participants)=='table' and (#participants==1 or #participants==2) and participants[1]=='client1'
  and (#participants==1 or participants[2]=='client2'),'invalid fixture actor list')
 local allowed={}
 for index,actor in pairs(participants) do
  assert(type(index)=='number' and index%1==0 and index>=1 and index<=#participants and not allowed[actor],'invalid fixture actor list')
  allowed[actor]=true
 end
 local S={index=1,epoch=1,phase='prepare',actors={},cases=config.cases,config=config}
 local context,prepared,finished,cleaned
 local function actorFor(player)
  if config.actor then return config.actor(player) end
  return player:getUsername()
 end
 local function transport(module,command,player,args,authority)
  if config.transport then return config.transport(module,command,player,args,authority) end
  if authority then sendServerCommand(player,module,command,args)
  else sendClientCommand(module,command,args) end
 end
 local function log(kind,actor,extra)
  print('[QUEUE_SESSION] '..kind..' case='..tostring(S.cases[S.index])..' epoch='..S.epoch..' actor='..actor..(extra and ' '..extra or ''))
 end
 local function envelope(args,actor)
  args=args or {};args.fixtureCase=S.cases[S.index];args.fixtureEpoch=S.epoch;args.fixtureActor=actor;return args
 end
 local function matches(args,actor)
  return type(args)=='table' and args.fixtureCase==S.cases[S.index] and args.fixtureEpoch==S.epoch and args.fixtureActor==actor
 end
 local function transmit(player,command,args)
  transport('QueueFixtureSession',command,player,envelope(args,server and actorFor(player) or config.user),server)
 end
 local function broadcast(command,args)
  for _,player in pairs(S.actors) do
   local copy={};for key,value in pairs(args or {}) do copy[key]=value end
   transmit(player,command,copy)
  end
 end
 function S.quarantine(reason)
  if S.phase=='done' or S.phase=='quarantined' then return end
  S.phase='quarantined';S.reason=tostring(reason);log('QUARANTINE',config.user,'reason='..tostring(reason))
  if server then broadcast('Quarantine',{reason=tostring(reason)}) else transmit(nil,'Quarantine',{reason=tostring(reason)}) end
 end
 local function callbacks(name,...)
  for _,fn in ipairs(context.handlers[name] or {}) do fn(...) end
 end
 local function instantiate()
  prepared,finished,cleaned={},{},{};S.deadline=getTimestampMs()+720000
  context={case=S.cases[S.index],epoch=S.epoch,handlers={},events={}}
  for _,name in ipairs({'OnTick','OnGameStart','OnClientCommand','OnServerCommand','OnServerStarted'}) do
   context.handlers[name]={};context.events[name]={Add=function(fn) table.insert(context.handlers[name],fn) end}
  end
  context.send=function(command,args) transport(config.module or 'CraftChainTest',command,nil,envelope(args,config.user),false) end
  context.reply=function(player,command,args) transport(config.module or 'CraftChainTest',command,player,envelope(args,actorFor(player)),true) end
  local function finishClean()
   local clean,result,reason=pcall(context.cleanup)
   if not clean or result~=true then S.quarantine('client cleanup '..tostring(reason or result));return end
   S.phase='finish';log('LOCAL_CLEAN',config.user,'ok=true');transmit(nil,'Finish',{ok=S.result})
  end
  context.finish=function(ok,uncertain)
   if S.phase~='running' then return end
   if uncertain then S.quarantine('unknown effects after deadline');return end
   S.result=ok;log('FINISH',config.user,'ok='..tostring(ok))
   S.phase='drain';S.drainSince=getTimestampMs();S.finishClean=finishClean
   if not context.readyToClean then finishClean() end
  end
  if S.configure then S.configure(context) end
  log('BEGIN',config.user);factories[context.case](context)
 end
 function S.prepare()
  if S.phase~='prepare' then return end
  local ok,error=pcall(instantiate)
  if not ok then S.quarantine('prepare '..tostring(error));return end
  if not server then S.pendingPrepare=true end
 end
 local function both(values)
  for _,actor in ipairs(participants) do if not values[actor] then return false end end
  return true
 end
 local function advance()
  log('JOINT_CLEAN',config.user,'ok=true');broadcast('JointClean')
  if S.index==#S.cases then S.phase='done';log('COMPLETE',config.user,'cases='..#S.cases);broadcast('Complete');return end
  S.index=S.index+1;S.epoch=S.epoch+1;S.phase='prepare'
  local ok,error=pcall(instantiate)
  if not ok then S.quarantine('prepare '..tostring(error));return end
  broadcast('Next')
 end
 function S.receive(command,player,args)
  local actor=server and actorFor(player) or config.user
  if not allowed[actor] then S.quarantine('unexpected actor');return end
  if not matches(args,actor) then log('REJECT',actor,'command='..tostring(command));return end
  if command=='Quarantine' then S.quarantine(args.reason);return end
  if S.phase=='quarantined' then
   if server then transmit(player,'Quarantine',{reason=S.reason}) end
   return
  end
  if S.phase=='done' then return end
  if server then
   if S.actors[actor] and S.actors[actor]~=player then S.quarantine('actor reconnected');return end
   S.actors[actor]=player
   if command=='Prepare' and S.phase=='prepare' and not prepared[actor] then
    prepared[actor]=true;log('PREPARE',actor)
    if both(prepared) then S.phase='running';log('START','server');broadcast('Start') end
   elseif command=='Finish' and (S.phase=='running' or S.phase=='finish') and not finished[actor] and type(args.ok)=='boolean' then
    finished[actor]=true;log('FINISH',actor,'ok='..tostring(args.ok))
    if both(finished) then
     S.phase='finish'
     local ok,result,reason=pcall(context.cleanup)
     if not ok or result~=true then S.quarantine('server cleanup '..tostring(reason or result));return end
     S.phase='clean';log('CLEANUP','server','ok=true');broadcast('Clean',context.receipt)
    end
   elseif command=='Cleaned' and S.phase=='clean' and not cleaned[actor] then
    cleaned[actor]=true;log('CLEANUP',actor,'ok=true');if both(cleaned) then advance() end
   else S.quarantine('duplicate or out-of-phase '..tostring(command)) end
  else
   if command=='Start' and S.phase=='prepare' then S.phase='running';log('START',actor);callbacks('OnGameStart')
   elseif command=='Clean' and S.phase=='finish' then S.phase='clean';S.cleanSince=getTimestampMs();S.cleanReceipt=args
   elseif command=='JointClean' and S.phase=='cleaned' then log('JOINT_CLEAN',actor,'ok=true');S.phase='between'
   elseif command=='Complete' and S.phase=='between' then S.phase='done';log('COMPLETE',actor,'cases='..#S.cases)
   else S.quarantine('unexpected server '..tostring(command)) end
  end
 end
 function S.command(module,command,player,args)
  if module=='QueueFixtureSession' then
   if not server and (command=='Next' or command=='Quarantine') and S.phase=='between' and type(args)=='table'
    and args.fixtureCase==S.cases[S.index+1] and args.fixtureEpoch==S.epoch+1 and args.fixtureActor==config.user then
    S.index=S.index+1;S.epoch=S.epoch+1;S.phase='prepare'
    if command=='Quarantine' then S.quarantine(args.reason) else S.prepare() end
    return
   end
   return S.receive(command,player,args)
  end
  if not server and context and context.observeProduct then context.observeProduct(module,command,args) end
  if module~=(config.module or 'CraftChainTest') or S.phase~='running' then return end
  local actor=server and actorFor(player) or config.user
  if not matches(args,actor) then log('REJECT',actor,'command='..tostring(command));return end
  if server and S.actors[actor]~=player then S.quarantine('fixture actor reconnected');return end
  if server then callbacks('OnClientCommand',module,command,player,args)
  else callbacks('OnServerCommand',module,command,args) end
 end
 function S.tick()
  if S.deadline and getTimestampMs()>S.deadline and S.phase~='done' and S.phase~='quarantined' then S.quarantine('session deadline; effects unknown');return end
  if not server and S.phase=='prepare' and S.pendingPrepare then
   local player=getPlayer()
   local ready=false
   if player then
    if config.localPlayerReady then ready=config.localPlayerReady(player)
    else ready=player:getOnlineID()>=0 end
   end
   if ready then
    -- OnGameStart precedes MP connection; native OnTick runs after ingame becomes true.
    S.pendingPrepare=false;log('PREPARE',config.user);transmit(nil,'Prepare')
   end
  elseif S.phase=='drain' then
   local ok,ready=pcall(context.readyToClean)
   if not ok then S.quarantine(ready)
   elseif ready then S.finishClean()
   elseif getTimestampMs()-S.drainSince>15000 then S.quarantine('pending product RPC deadline; effects unknown') end
  elseif S.phase=='running' then
   local ok,error=pcall(callbacks,'OnTick');if not ok then S.quarantine(error) end
  elseif not server and S.phase=='clean' then
   local ok,ready,reason=pcall(context.clean,S.cleanReceipt)
   if not ok then S.quarantine('cleanup verification '..tostring(ready))
   elseif ready==true then S.phase='cleaned';log('CLEANUP',config.user,'ok=true');transmit(nil,'Cleaned')
   elseif getTimestampMs()-S.cleanSince>15000 then S.quarantine('replicated cleanup deadline '..tostring(reason)) end
  end
 end
 function S.performed(action) if S.phase=='running' and context.performed then context.performed(action) end end
 function S.current() return context end
 return S
end
