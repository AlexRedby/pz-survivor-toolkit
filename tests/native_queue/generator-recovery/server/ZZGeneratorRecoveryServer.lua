if not isServer()then return end
local A=require 'QueueGeneratorRecoveryAuthority'
local P=require 'QueueEnergyPlacement'
local waiting,prepared={},{}
local function fail(player,case,problem)
 print('[QUEUE_TEST] FAIL generator-recovery server '..tostring(problem))
 sendServerCommand(player,'GeneratorRecoveryTest','Failed',{case=case,ok=false,error=tostring(problem)})
end
local function broadcast(command,args)
 for _,player in pairs(A.players())do sendServerCommand(player,'GeneratorRecoveryTest',command,args)end
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='GeneratorRecoveryTest'then return end
 local ok,problem=pcall(function()
  assert(type(args)=='table'and type(args.case)=='string','missing recovery request case')
  if command=='Layout'then local row=A.layout(player,args.case);if row then sendServerCommand(player,module,'Layout',row)end
  elseif command=='Prepare'then
   assert(not waiting[player]and args.clientPlacement and args.clientPlacement.mode=='local','invalid recovery arrival')
   local target=P.target(args.target);waiting[player]={case=args.case,target=target,arrival=P.observeCentered(player,target)}
  elseif command=='Ready'then if A.ready(player,args.case)then broadcast('Begin',{case=args.case})end
  elseif command=='TrimStarted'then A.trimStarted(player,args.case)
  elseif command=='PeerGo'then
   assert(type(args.delta)=='number'and(args.case=='peer-pickup'and args.delta>=.8 and args.delta<.95
    or args.case=='owner-pickup-first'and args.delta>0 and args.delta<.5),'peer overlap request missed the native pickup ordering boundary')
   -- Boundary observation was already made once; inspect the same exact target without reseeding or completing anything.
   local players=A.players();assert(player==players.client1 and players.client2,'peer request has no distinct actor')
   local square=player:getCurrentSquare();local objects=square:getObjects();local target,decoy
   for i=0,objects:size()-1 do local object=objects:get(i)
    if instanceof(object,'IsoGenerator')then if object:getCondition()==73 then assert(not target);target=object elseif object:getCondition()==41 then decoy=object end end
   end
   assert(target and decoy and target~=decoy,'exact peer target/decoy missing')
   sendServerCommand(players.client2,module,'PeerGo',{case=args.case,x=square:getX(),y=square:getY(),z=square:getZ(),objectIndex=target:getObjectIndex()})
  elseif command=='PeerStarted'then A.peerStarted(player,args.case,args)
  elseif command=='Observed'then if A.acknowledge(player,args.case)then broadcast('Advance',{case=args.case})end
  elseif command=='Verify'then local row=A.verify(player,args.case);if row then broadcast('Verified',row)end
  else error('unexpected recovery request '..command)end
 end)
 if not ok then fail(player,type(args)=='table'and args.case or'',problem)end
end)
Events.OnTick.Add(function()
 local ok,problem=pcall(A.observe)
 if not ok then for _,player in pairs(A.players())do fail(player,'',problem)end end
 for player,request in pairs(waiting)do
  local ready,error=pcall(function()
   local proof=P.poll(request.arrival);if not proof then return end
   A.prepare(player,request.case,request.target,proof);waiting[player]=nil
   local ids=A.seed();if ids and not prepared[request.case]then prepared[request.case]=true;broadcast('Prepared',ids)end
  end)
  if not ready then waiting[player]=nil;fail(player,request.case,error)end
 end
end)
