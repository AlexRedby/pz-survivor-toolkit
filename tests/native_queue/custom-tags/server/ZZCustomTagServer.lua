local config=require 'QueueTestSelection'
if config.suite~='custom-tags'then return end
local F=require 'CustomTagFixture'
local C=require 'PZSurvivorToolkit/TagCustomization'
local JSON=require 'QueueHealthEvents'
local players,ready,sent,observed={},{},{},{}
local state,pendingPacket,phase,index,startedAt,ownerDone,checking,failed
local reload=config.cases[1]=='reload'
local function emit(event,data)print('[CUSTOM_TAG_TEST] '..event..' '..JSON.encode(data))end
local function broadcast(command,args)for _,p in pairs(players)do sendServerCommand(p,F.module,command,args or {})end end
local function start(nextPhase)
 phase=nextPhase;startedAt=getTimestampMs();ownerDone,checking=false,false;observed={}
 emit('PHASE',{phase=phase});broadcast('Action',{phase=phase,packet=state.packet})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module or failed then return end
 local ok,err=pcall(function()
  local role=player:getUsername();assert(role=='client1'or role=='client2','Unexpected fixture actor')
  if command=='Prepare'then
   assert(not players[role],'Duplicate fixture prepare');players[role]=player
   if role=='client1'then
    if reload then pendingPacket=assert(ModData.get(F.store),'Missing fixture save').packet
    else state=F.prepare(player);emit('PREPARED',state.packet)end
   end
  elseif command=='Ready'then ready[role]=true
  elseif command=='OpenConflict'then
   assert(role=='client1'and phase=='Conflict','Unexpected conflict open')
   sendServerCommand(players.client2,F.module,'Bump',{phase=phase})
  elseif command=='BumpDone'then
   assert(role=='client2'and phase=='Conflict'and args.status=='accepted','Observer catalog bump failed')
   sendServerCommand(players.client1,F.module,'ConflictSave',{})
  elseif command=='Done'then
   assert(role=='client1'and args.phase==phase and not ownerDone,'Stale/duplicate action completion')
   if args.tag then assert(C.isActive(args.tag),'Created tag not authoritative');state.packet.tag=args.tag end
   if args.retired then assert(C.isActive(args.retired),'Retired candidate not authoritative');state.packet.retired=args.retired end
   ownerDone=true
  elseif command=='Observed'then
   assert(checking and args.phase==phase,'Stale observer confirmation');observed[role]=true
  else error('Unknown fixture command '..tostring(command))end
 end)
 if not ok then failed=true;emit('FAIL',{role='server',error=tostring(err)})end
end)
Events.OnTick.Add(function()
 if failed or phase=='Done'or not state and not pendingPacket then return end
 local ok,err=pcall(function()
  local packet=state and state.packet or pendingPacket
  for role,p in pairs(players)do
   if not sent[role]then sent[role]=true;sendServerCommand(p,F.module,'Prepared',{role=role,packet=packet})end
  end
  if not state then state=F.resolve(pendingPacket);if not state then return end;pendingPacket=nil end
  if not phase then
   if not ready.client1 or not ready.client2 then return end
   assert(players.client1:getOnlineID()~=players.client2:getOnlineID(),'Clients share actor')
   if reload then
    phase='Reload';startedAt=getTimestampMs();ownerDone=true;checking=false
   else index=1;start(F.phases[index])end
  end
  if ownerDone and not checking then
   assert(F.check(phase,state),'Server effective state differs in '..phase)
   if phase=='Cancel'then assert(C.getRevision()==state.packet.cancelRevision,'Cancel mutated catalog')end
   if phase=='Conflict'then assert(C.getRevision()==state.packet.conflictRevision+1,'Conflict overwrote concurrent edit')end
   if phase=='Cancel'or phase=='Conflict'then assert(not C.itemDelta(F.item(state,4))[state.packet.tag],'Rejected/canceled assignment leaked')end
   emit('CHECK',{role='server',phase=phase,passed=true,revision=C.getRevision()})
   checking=true;broadcast('Verify',{phase=phase,packet=state.packet,revision=C.getRevision()})
  end
  if checking and observed.client1 and observed.client2 then
   if phase=='Reload'or index==#F.phases then
    assert(F.check('Reload',state),'Final save state differs')
    state.packet.revision=C.getRevision();ModData.getOrCreate(F.store).packet=state.packet
    emit(reload and 'PERSISTED'or 'VERIFIED',F.receipt('server',state));broadcast('Finish',{packet=state.packet});phase='Done';return
   end
   index=index+1
   if F.phases[index]=='Cancel'then state.packet.cancelRevision=C.getRevision()end
   if F.phases[index]=='Conflict'then state.packet.conflictRevision=C.getRevision()end
   start(F.phases[index])
  end
  if phase~='Done'then assert(getTimestampMs()-startedAt<90000,'Custom-tag Host phase timeout '..tostring(phase))end
 end)
 if not ok then failed=true;emit('FAIL',{role='server',error=tostring(err)})end
end)
