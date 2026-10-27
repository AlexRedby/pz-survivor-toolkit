local config=require 'QueueTestSelection'
if config.suite~='lot-streaming'or not isServer()then return end
local F=require 'LotStreamingFixture'
local actors,ready,failed={},{},false
local beforeReleased=false
local phases={'before','away','returned'}
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module or failed then return end
 local ok,err=pcall(function()
  local role=player:getUsername();assert(role=='client1'or role=='client2','Unexpected native actor')
  if command=='Prepare'then
   assert(not actors[role],'Duplicate actor preparation')
   assert(F.near(player,F.start),'Authority actor did not start at fixture origin')
   actors[role]={player=player,nextPhase=1}
   F.baseline(config,role)
   sendServerCommand(player,F.module,'Prepared',{role=role})
  elseif command=='Ready'then
   assert(actors[role]and not ready[role],'Duplicate/unprepared readiness');ready[role]=true
   F.emit('READY',{role=role,onlineID=player:getOnlineID()})
   if ready.client1 and ready.client2 then
    assert(actors.client1.player:getOnlineID()~=actors.client2.player:getOnlineID(),'Shared native actor identity')
    for _,state in pairs(actors)do sendServerCommand(state.player,F.module,'Start',{})end
   end
  elseif command=='Probe'then
   local state=assert(actors[role]);assert(ready.client1 and ready.client2,'Peers not ready')
   assert(args.phase==phases[state.nextPhase],'Reordered/duplicate authority phase')
   assert(args.phase=='before'or beforeReleased,'Initial authority snapshots not captured for both peers')
   assert(F.near(player,args.phase=='away'and F.away or F.start),'Authority streaming position differs')
   local snapshot=F.snapshot(role,args.phase)
   if args.phase=='returned'then F.store(snapshot,role)end
   state.nextPhase=state.nextPhase+1
   if args.phase=='before'then
    state.beforeCaptured=true
    if actors.client1.beforeCaptured and actors.client2.beforeCaptured then
     beforeReleased=true
     for _,actor in pairs(actors)do sendServerCommand(actor.player,F.module,'Probe',{phase='before'})end
    end
   else sendServerCommand(player,F.module,'Probe',{phase=args.phase})end
  else error('Unexpected native fixture command '..tostring(command))end
 end)
 if not ok then failed=true;F.emit('FAIL',{role='server',error=tostring(err)})end
end)
