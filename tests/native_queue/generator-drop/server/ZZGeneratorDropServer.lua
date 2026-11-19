if not isServer()then return end
local A=require 'QueueGeneratorDropAuthority'
local P=require 'QueueEnergyPlacement'
local waiting,prepared={},false
local function fail(player,case,problem)
 print('[QUEUE_TEST] FAIL generator-drop server '..tostring(problem))
 sendServerCommand(player,'GeneratorDropTest','Failed',{case=case,ok=false,error=tostring(problem)})
end
local function broadcast(command,args)
 for _,player in pairs(A.players())do sendServerCommand(player,'GeneratorDropTest',command,args)end
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='GeneratorDropTest'then return end
 local ok,problem=pcall(function()
  assert(type(args)=='table'and type(args.case)=='string','generator request case missing')
  if command=='Layout'then
   local layout=A.layout(player,args.case)
   if layout then sendServerCommand(player,module,'Layout',layout)end
  elseif command=='Prepare'then
   assert(not waiting[player],'overlapping generator arrival')
   local target=P.target(args.target)
   assert(args.clientPlacement and args.clientPlacement.mode=='local','generator client placement proof missing')
   waiting[player]={case=args.case,target=target,arrival=P.observeCentered(player,target)}
  elseif command=='Ready'then
   if A.ready(player,args.case)then broadcast('Begin',{case=args.case})end
  elseif command=='Started'then A.started(player,args.case)
  elseif command=='Verify'then
   local result=A.verify(player,args.case);if result then broadcast('Verified',result)end
  else error('unexpected generator command')end
 end)
 if not ok then fail(player,type(args)=='table'and args.case or'',problem)end
end)
Events.OnTick.Add(function()
 for player,request in pairs(waiting)do
  local ok,problem=pcall(function()
   local proof=P.poll(request.arrival);if not proof then return end
   A.prepare(player,request.case,request.target,proof);waiting[player]=nil
   local ids=A.seed()
   if ids and not prepared then prepared=true;broadcast('Prepared',ids)end
  end)
  if not ok then waiting[player]=nil;fail(player,request.case,problem)end
 end
end)
