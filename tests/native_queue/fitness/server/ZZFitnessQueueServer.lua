if not isServer()then return end
local F=require 'QueueFitnessFixture'
local O=require 'QueueFitnessObservation'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local index,state,previous,pending,peer,peerBook=1
local readyReports,readySince,peersReady={},nil,false
O.onRep=function(action,row)
 if state and action.character==state.player then
  sendServerCommand(state.player,'FitnessQueueTest','NativeRep',{case=state.case,exercise=row.exercise,reps=row.reps})
 end
end
local function online(name)
 local values=getOnlinePlayers();for i=0,values:size()-1 do if values:get(i):getUsername()==name then return values:get(i)end end
end
local function raw(marker,row)print('[FITNESS_TEST] '..marker..' '..JSON.encode(row))end
local function fail(player,error)
 print('[QUEUE_TEST] FAIL fitness authority '..tostring(error));sendServerCommand(player,'FitnessQueueTest','Failed',{error=tostring(error)})
end
local function peersMatch()
 if getOnlinePlayers():size()~=2 then return false end
 for _,actor in ipairs({'client1','client2'})do
  local report=readyReports[actor];local player=online(actor)
  if not report or not player or report.player~=player or report.onlineID~=player:getOnlineID()
   or player:getOnlineID()<0 or player:isDead()or not player:getCurrentSquare()then return false end
 end
 return true
end
local function verifyDiagnostic(problem)
 local player=state and state.player;local current=player and player:getFitness():getCurrentExe()
 raw('VERIFY_FAILED',{case=state and state.case or false,reason=tostring(problem),waitingFor=pending and pending.waitingFor or false,
  hasTimedActions=player and player:hasTimedActions()or false,characterActions=player and player:getCharacterActions():size()or 0,
  currentExercise=current and tostring(current)or false,observerActive=O.active~=nil,observerRecords=#O.records,
  peerConnected=peer~=nil and online('client2')==peer,
  peerRead=peer~=nil and peerBook~=nil and peer:getAlreadyReadPages(peerBook:getFullType())==peerBook:getNumberOfPages()})
end
Events.OnServerStarted.Add(function()print('[FITNESS_TEST] SERVER_READY')end)
Events.OnClientCommand.Add(function(module,name,player,args)
 if module~='FitnessQueueTest'then return end
 local ok,problem=pcall(function()
  if name=='Ready'then
   local actor=player:getUsername()
   assert((actor=='client1'or actor=='client2')and args.actor==actor and type(args.onlineID)=='number'
    and args.onlineID>=0 and args.onlineID==player:getOnlineID()and online(actor)==player,'fitness readiness actor/online identity differs')
   local previousReport=readyReports[actor]
   assert(not previousReport or previousReport.player==player and previousReport.onlineID==args.onlineID,'fitness readiness identity changed')
   readyReports[actor]={player=player,onlineID=args.onlineID};readySince=readySince or getTimestampMs();return
  end
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'fitness authority actor/order differs')
  if name=='Prepare'then
   assert(peersReady and peersMatch(),'both actual clients must report fixture-ready before preparation')
   assert(not state and not pending,'previous fitness case not settled')
   peer=assert(online('client2'),'second actual Host client required')
   if peerBook then
    assert(peer:getAlreadyReadPages(peerBook:getFullType())==peerBook:getNumberOfPages(),'peer independent reader did not finish')
    local live=peer:getInventory():getItemById(peerBook:getID());assert(live,'peer exact reader missing')
    peer:getInventory():Remove(live);sendRemoveItemFromContainer(peer:getInventory(),live)
   end
   peerBook=assert(peer:getInventory():AddItem('Base.BookMechanic1'))
   peer:setPerkLevelDebug(Perks.Mechanics,0);peerBook:setAlreadyReadPages(peerBook:getNumberOfPages()-1)
   peer:setAlreadyReadPages(peerBook:getFullType(),peerBook:getNumberOfPages()-1);sendAddItemToContainer(peer:getInventory(),peerBook)
   state=F.prepare(player,args.case,previous);previous=nil
   state.ids.peerBook=peerBook:getID();state.ids.peerOnlineID=peer:getOnlineID()
   raw('PREPARED',state.ids);sendServerCommand(player,module,'Prepared',state.ids)
   sendServerCommand(peer,module,'Peer',{case=args.case,book=peerBook:getID()})
  elseif name=='Mutate'then
   assert(state and not pending,'fitness mutation out of order');local row=F.mutate(state)
   raw('MUTATED',row);sendServerCommand(player,module,'Mutated',row)
  elseif name=='Verify'then
   assert(state and not pending,'fitness verify out of order');assert(args.clientQuiescent==true,'fitness verify requires empty actor queue')
   pending={since=getTimestampMs(),quiet=nil,clientQuiescent=true,waitingFor='native-stop'}
  elseif name=='Next'then
   assert(state and state.verified and not pending,'fitness next before receipt')
   if state.strandedCurrent then
    assert(config.mode=='native'and args.failedCaseRecorded==true,'stranded state requires published failed client case')
    state.failedCaseRecorded=true;raw('RECOVERY',F.recoverStranded(state))
   end
   F.releaseEquipment(state);previous=state;state=nil;index=index+1
   if not config.cases[index]then sendServerCommand(peer,module,'PeerComplete',{})end
   sendServerCommand(player,module,'Released',{case=args.case})
  else error('unexpected fitness command '..tostring(name))end
 end)
 if not ok then if name=='Verify'then verifyDiagnostic(problem)end;fail(player,problem)end
end)
Events.OnTick.Add(function()
 if readySince and not peersReady then
  local ok,problem=pcall(function()
   assert(getTimestampMs()-readySince<90000,'fitness peer readiness deadline')
   if not peersMatch()then return end
   peersReady=true
   local ids={client1=readyReports.client1.onlineID,client2=readyReports.client2.onlineID}
   raw('PEERS_READY',ids)
   for _,actor in ipairs({'client1','client2'})do sendServerCommand(readyReports[actor].player,'FitnessQueueTest','PeersReady',ids)end
  end)
  if not ok then
   raw('PEERS_NOT_READY',{client1Reported=readyReports.client1~=nil,client2Reported=readyReports.client2~=nil,players=getOnlinePlayers():size()})
   for _,report in pairs(readyReports)do fail(report.player,problem)end
   readySince=nil;return
  end
 end
 if state and state.exhausted then state.player:getStats():set(CharacterStat.ENDURANCE,.01)end
 if not pending then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-pending.since<30000,'authoritative fitness verification deadline')
  local player=state.player
  local nativeIdle=not player:hasTimedActions()and player:getCharacterActions():isEmpty()
  local current=player:getFitness():getCurrentExe()
  local stranded=config.mode=='native'and (state.case=='missing-dumbbell'or state.case=='exhaustion')
   and current and not O.active and #O.records==0 and nativeIdle and pending.clientQuiescent
  -- A never-started native constructor can leave currentExe set forever. Snapshot
  -- that failed state; the cleanup branch runs only after the failed case is emitted.
  if O.active or not nativeIdle or (current and not stranded)then pending.waitingFor='native-stop';pending.quiet=nil;return end
  pending.waitingFor='settle-window'
  if not pending.quiet then pending.quiet=getTimestampMs();return end
  if getTimestampMs()-pending.quiet<2000 then return end
  local receipt=F.receipt(state)
  receipt.peerBook=peerBook:getID();receipt.peerOnlineID=peer:getOnlineID()
  receipt.peerRead=peer:getAlreadyReadPages(peerBook:getFullType())==peerBook:getNumberOfPages()
  if not receipt.peerRead then pending.waitingFor='peer-reader';return end
  receipt.serverSettleMilliseconds=getTimestampMs()-pending.quiet;state.verified=true;state.lastReceipt=receipt
  raw('VERIFIED',receipt);sendServerCommand(state.player,'FitnessQueueTest','Verified',receipt);pending=nil
 end)
 if not ok then verifyDiagnostic(problem);fail(state.player,problem);pending=nil end
end)
