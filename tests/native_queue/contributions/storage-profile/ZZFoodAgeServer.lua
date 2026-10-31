if not isServer()then return end
local F=require 'QueueFoodAgeFixture'
local session,actor,events,lastDiagnostic,preparedAt,finished,closed,completed
Events.OnContainerUpdate.Add(function(item)
 if session and session.phase and item==session.phase.tail then events=events+1 end
end)
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module then return end
 local ok,result=pcall(function()
  assert(player:getUsername()=='client1'and args.case=='inventory-food-age','unexpected food-age actor/case')
  if command=='Prepare'and not session then
   local square=assert(player:getSquare());local spawn=assert(args.spawn)
   if square:getX()~=spawn.x or square:getY()~=spawn.y or square:getZ()~=spawn.z then return {waiting=true}end
   actor=player;session=F.newSession(player);F.setup(session)
  end
  assert(session and actor==player,'wrong food-age session')
  assert(command=='Prepare'and args.index==1 or args.token==session.token,'wrong food-age session token')
  if closed then
   assert(command=='Abort'and completed and not session.phase,'wrong food-age session')
   return {restored=true,alreadyCompleted=true}
  end
  if command=='Abort'then F.release(session,true);closed=true;return {restored=true}end
  if command=='Prepare'then
   events=0;finished=false;preparedAt=getTimestampMs();return F.preparePhase(session,args.index)
  end
  if command=='Cleanup'then
   assert(not session.phase and session.index==#F.phases,'unfinished authority lifecycle')
   local receipt=F.restored(session,{observers=true,ui=true,uiUnchanged=true})
   closed=true;completed=true;return receipt
  end
  local p=assert(session.phase,'food-age authority has no active phase')
  assert(args.index==p.index,'food-age authority phase differs')
  if command=='Ready'then
   assert(args.tailId==p.tail:getID(),'wrong replicated food-age tail')
   local snap=F.snapshot(session,p);assert(snap.tailFresh,'authority expired before client concealment readiness')
   p.clientReady=true;return snap
  elseif command=='Status'then
   assert(p.clientReady,'authority observation before initial native UI proof')
   local snap=F.snapshot(session,p);snap.ready=not snap.tailFresh and snap.headFresh
   return snap
  elseif command=='Finish'then
   assert(p.clientReady and not finished,'duplicate/unready authoritative phase finish')
   local head=assert(p.owned[args.headId]);assert(head~=p.tail and instanceof(head,'Food')and head:isFresh(),'client native header is not owned fresh food')
   p.head=head;local snap=F.snapshot(session,p)
   assert(not snap.tailFresh and snap.headFresh and snap.world>p.beforeWorld and events==0,'native authority did not cross freshness boundary')
   local row=F.receipt(session,p);row.events=events;row.serverOwned=true;row.clientPhaseComplete=true
   F.emit('AGE_PHASE',row);finished=true;return snap
  elseif command=='Release'then
   assert(finished,'owned authority items released before both phase receipts');return F.release(session)
  end
  error('unknown food-age authority command')
 end)
 if ok then sendServerCommand(player,module,command..'d',result)
 else
  local row={error=tostring(result),command=command,index=session and session.index or 0}
  if session and session.phase then local captured,value=pcall(F.snapshot,session,session.phase);if captured then row.snapshot=value end end
  local restored,problem=pcall(function()if session then F.release(session,true)end end)
  row.restored=restored;row.restoreError=tostring(problem);F.emit('FAIL',row);closed=true
  sendServerCommand(player,module,'Failed',{error=tostring(result)})
 end
end)
Events.OnTick.Add(function()
 if not session or closed or not session.phase then return end
 if lastDiagnostic and getTimestampMs()-lastDiagnostic<10000 then return end
 lastDiagnostic=getTimestampMs();local ok,value=pcall(F.snapshot,session,session.phase)
 F.emit('DIAGNOSTIC',{index=session.index,snapshot=ok and value or nil,error=not ok and tostring(value)or nil,
  elapsedMs=preparedAt and getTimestampMs()-preparedAt or 0,events=events or 0})
end)
