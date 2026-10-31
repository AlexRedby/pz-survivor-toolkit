if not isServer()then return end
local F=require 'QueueFoodCoolingFixture'
local state,actor,cleaned,lastDiagnostic
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module then return end
 local ok,result=pcall(function()
  assert(player:getUsername()=='client1'and args.case==F.case,'unexpected cooling actor/case')
  if command=='Prepare'then
   assert(not state,'duplicate cooling preparation');local square=assert(player:getSquare());local spawn=assert(args.spawn)
   if square:getX()~=spawn.x or square:getY()~=spawn.y or square:getZ()~=spawn.z then return {waiting=true}end
   actor=player;state=F.prepare(player);return state.ids
  end
  assert(state and actor==player and args.token==state.ids.token and not cleaned,'wrong cooling session')
  if command=='Abort'then F.abort(state);cleaned=true;return {restored=true}
  elseif command=='Origin'then return F.settled(state,args.index,args.sequence,args.purpose)
  elseif command=='Ready'then return F.phaseReadiness(state,args.index,args.sequence)
  elseif command=='Begin'then return F.begin(state,args.index)
  elseif command=='End'then return F.finish(state,args.index)
  elseif command=='Cleanup'then assert(state.phaseIndex==4 and not state.before,'unfinished cooling phases');local receipt=F.cleanup(state);cleaned=true;return receipt end
  error('unknown cooling command')
 end)
 if ok then sendServerCommand(player,module,command..'d',result)
 else
  local failure=F.failureSnapshot(state or F.preparing,{error=tostring(result),command=command})
  local restored,restoreError=pcall(F.abort,state or F.preparing)
  failure.restored=restored;failure.restoreError=tostring(restoreError)
  F.emit('FAIL',failure);print('[QUEUE_TEST] FAIL food cooling server '..tostring(result));sendServerCommand(player,module,'Failed',{error=tostring(result)})
 end
end)
Events.OnTick.Add(function()
 if not state or cleaned then return end
 F.originStatus(state)
 if lastDiagnostic and getTimestampMs()-lastDiagnostic<5000 then return end
 lastDiagnostic=getTimestampMs()
 F.emit('DIAGNOSTIC',F.failureSnapshot(state,{index=state.phaseIndex or 0,phase=state.before and 'observe'or 'between'}))
end)
