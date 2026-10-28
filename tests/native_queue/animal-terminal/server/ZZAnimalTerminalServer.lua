if not isServer()then return end
local F=require 'QueueAnimalTerminal';local JSON=require 'QueueHealthEvents';local cfg=require 'QueueTestSelection'
local state,previous,index,baseline=nil,nil,1,nil
local pending
local function prepared(player,target)
 state=F.prepare(player,cfg.cases[index],previous,target)
 if not state then return false end
 previous=nil;return true
end
local function raw(name,row)print('[ANIMAL_TERMINAL] '..name..' '..JSON.encode(row))end
Events.OnServerStarted.Add(function()raw('SERVER_READY',{})end)
Events.OnClientCommand.Add(function(module,name,player,args)
 if module~='AnimalTerminalTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==cfg.cases[index],'animal terminal actor/order differs')
  local result
  if name=='Prepare'then
   assert(not state and not pending,'animal terminal previous case not settled')
   local target=F.placementTarget(args.placement)
   if not prepared(player,target)then pending={player=player,target=target,since=getTimestampMs()};return end
   result=state.ids;raw('PREPARED',result)
  elseif name=='Baseline'then
   assert(state and not baseline,'duplicate animal terminal baseline');baseline=F.snapshot(state)
   assert(baseline.petTimer==0 and baseline.cooldownReady and #baseline.xpLedger==0 and player:getSquare():getX()==state.ids.origin.x and player:getSquare():getY()==state.ids.origin.y and player:getSquare():getZ()==state.ids.origin.z,'authority native placement/timer/XP baseline changed');result=baseline;raw('BASELINE',result)
  elseif name=='Verify'then
   assert(state and baseline and not player:hasTimedActions()and player:getCharacterActions():isEmpty(),'authority native queue not idle')
   local final=F.snapshot(state);assert(F.effect(state,final)and F.clean(final),'authority native pet effect/cleanup differs')
   assert(final.book.pages==state.ids.book.total and final.book.itemPages==state.ids.book.total,'authority independent book incomplete')
   result={case=args.case,baseline=baseline,final=final};raw('VERIFIED',result)
   previous=state;state,baseline=nil,nil;index=index+1
  else error('unknown animal terminal command')end
  sendServerCommand(player,module,({Prepare='Prepared',Baseline='Baselined',Verify='Verified'})[name],result)
 end)
 if not ok then print('[QUEUE_TEST] FAIL animal-terminal server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)

Events.OnTick.Add(function()
 if not pending then return end
 local waiting=pending
 local ok,problem=pcall(function()
  assert(getTimestampMs()-waiting.since<30000,'native fixture placement did not settle')
  if not prepared(waiting.player,waiting.target)then return end
  pending=nil;raw('PREPARED',state.ids);sendServerCommand(waiting.player,'AnimalTerminalTest','Prepared',state.ids)
 end)
 if not ok then pending=nil;print('[QUEUE_TEST] FAIL animal-terminal server '..tostring(problem));sendServerCommand(waiting.player,'AnimalTerminalTest','Failed',{error=tostring(problem)})end
end)
