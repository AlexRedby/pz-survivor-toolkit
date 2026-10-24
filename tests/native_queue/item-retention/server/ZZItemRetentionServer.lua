local config=require 'QueueTestSelection'
if config.suite~='item-retention'then return end
local F=require 'ItemRetentionFixture'
local R=require 'PZSurvivorToolkit/ItemRetention'
local Access=require 'PZSurvivorToolkit/ItemAccess'
local JSON=require 'QueueHealthEvents'
local players,ready,arriving,observed,vehicleReady,sent={},{},{},{},{},{}
local state,phase,since,diagnosed,pendingPacket
local reload=config.cases[1]=='reload'
local function emit(event,data)print('[ITEM_RETENTION_TEST] '..event..' '..JSON.encode(data))end
local function broadcast(command,args)for _,p in pairs(players)do sendServerCommand(p,F.module,command,args or {})end end
local function advance(nextPhase)phase=nextPhase;since=getTimestampMs();emit('PHASE',{phase=phase});broadcast(nextPhase,{})end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module==R.MODULE and command=='Set'then
  local ok,err=pcall(function()
   local locator=args.items and args.items[1]
   local item,root,square,part
   if type(locator)=='table'then item,root,square,part=Access.resolve(player,locator)end
   emit('NATIVE_REQUEST',{role=player:getUsername(),request=args.request,retained=args.retained,
    locator=locator or {},valid=Access.validLocator(locator),resolved=item~=nil,
    current=item and Access.locate(item,player)or {},sameLocation=item and Access.sameLocation(item,player,locator)or false,
    applied=R.isRetained(item),fixtureRoot=state and root==state.container or false,
    x=player:getX(),y=player:getY(),z=player:getZ(),dead=player:isDead(),
    containerAccess=root and player:canAccessContainer(root)or false,
    vehicleAccess=part and part:getVehicle():canAccessContainer(part:getIndex(),player)or false,
    safehouse=square and SafeHouse and SafeHouse.isSafehouseAllowLoot
     and SafeHouse.isSafehouseAllowLoot(square,player)==true or false})
  end)
  if not ok then emit('REQUEST_DIAGNOSTIC_ERROR',{error=tostring(err)})end
  return
 end
 if module~=F.module then return end
 local ok,err=pcall(function()
  local role=player:getUsername();assert(role=='client1'or role=='client2','Unexpected fixture actor')
  if command=='Prepare'then
   assert(not players[role],'Duplicate fixture prepare');players[role]=player
   if role=='client1' then
    if reload then
     local saved=assert(ModData.get(F.persistence),'No persisted fixture data in restored world')
     pendingPacket=assert(saved.packet,'No persisted item IDs')
    else state=F.prepare(player);emit('PREPARED',state.packet)end
   end
  elseif command=='VehicleReady'then
   vehicleReady[role]=true
   -- Vehicle streaming already sends its inventory. Resending a complete
   -- container here would deliver duplicate native item IDs to both clients.
  elseif command=='Ready'then arriving[role]=true
  elseif command=='Observed'then
   assert(args.phase==phase,'Stale observer confirmation');observed[role]=phase
  else error('Unknown fixture command '..tostring(command))end
 end)
 if not ok then emit('FAIL',{role='server',error=tostring(err)})end
end)
Events.OnTick.Add(function()
 if not state and not pendingPacket then return end
 local ok,err=pcall(function()
  if pendingPacket then
   for role,p in pairs(players)do
    if not sent[role]then
     sent[role]=true
     sendServerCommand(p,F.module,'Prepared',{target=pendingPacket,role=role})
    end
   end
   local vehicle,container,crate=F.resolve(pendingPacket)
   if not vehicle then return end
   state={vehicle=vehicle,container=container,crate=crate,packet=pendingPacket,player=players.client1}
   pendingPacket=nil
  end
  for role,p in pairs(players)do
   if not ready[role]and not sent[role]then
    sent[role]=true
    sendServerCommand(p,F.module,'Prepared',{target=state.packet,role=role})
   end
   if arriving[role]and math.abs(p:getX()-state.packet.x)<3 and math.abs(p:getY()-state.packet.y)<3 then ready[role]=true end
  end
  if not phase then
   if ready.client1 and ready.client2 then
    assert(players.client1:getOnlineID()~=players.client2:getOnlineID(),'Clients share identity')
    if reload then
     assert(F.check(state,'released'),'Saved native item identities or retention flags changed')
     emit('PERSISTED',F.persisted('server',state));advance('Reloaded')
    else advance('Mark')end
   end
  elseif phase=='Mark'then
   if F.check(state,'marked')then advance('Marked')end
  elseif phase=='Marked'then
   if observed.client1==phase and observed.client2==phase then advance('Distribute')end
  elseif phase=='Distribute'then
   if F.check(state,'distributed')then advance('Distributed')end
  elseif phase=='Distributed'then
   if observed.client1==phase and observed.client2==phase then advance('Manual')end
  elseif phase=='Manual'then
   if F.check(state,'manual')then advance('Moved')end
  elseif phase=='Moved'then
   if observed.client1==phase and observed.client2==phase then advance('Release')end
  elseif phase=='Release'then
   if F.check(state,'released')then
    ModData.getOrCreate(F.persistence).packet=state.packet
    emit('VERIFIED',F.receipt('server',state));advance('Done')
   end
  elseif phase=='Reloaded'then return
  elseif phase=='Done'then return end
  if since and getTimestampMs()-since>80000 and diagnosed~=phase then
   diagnosed=phase;emit('DIAGNOSTIC',{phase=phase,items=F.diagnostic(state)})
  end
  assert(not since or getTimestampMs()-since<90000,'Host phase timeout '..tostring(phase))
 end)
 if not ok then phase='Done';emit('FAIL',{role='server',error=tostring(err)})end
end)
