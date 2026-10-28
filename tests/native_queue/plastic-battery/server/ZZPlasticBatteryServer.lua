if not isServer()then return end
local config=require 'QueueTestSelection'
if config.suite~='plastic-battery'or config.cases[1]~='native-recipes'then return end
local F=require 'PlasticBatteryFixture'
local JSON=require 'QueueHealthEvents'
local owner,state,restore,guard
local function emit(event,data)print('[PLASTIC_BATTERY] '..event..' '..JSON.encode(data))end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module then return end
 local ok,reason=pcall(function()
  assert(player:getUsername()=='client1','unexpected battery actor')
  if command=='Prepare'then
   if not owner then
    emit('RECIPES',F.recipes('server'));owner=F.init(player)
    restore,guard=F.install(function()return state end,function(row)emit('PERFORMED',row)end)
   end
   assert(args.index==(state and state.packet.index+1 or 1),'unexpected phase order')
   state=F.prepare(owner,args.index);emit('PREPARED',state.packet)
   sendServerCommand(player,module,'Prepared',state.packet)
  elseif command=='Diagnose'then
   assert(state and args.index==state.packet.index,'wrong diagnostic phase')
   state.diagnostics=(state.diagnostics or 0)+1;assert(state.diagnostics<=2,'excessive diagnostic requests')
   local row=F.diagnostic(state);row.observerIntact=guard();emit('SERVER_DIAGNOSTIC',row)
   sendServerCommand(player,module,'Diagnostic',row)
  elseif command=='Verify'then
   assert(state and args.index==state.packet.index,'wrong verification phase')
   local row=F.authority(state,guard);emit('AUTHORITY',row);sendServerCommand(player,module,'Verified',row)
  else
   assert(command=='Restore'and state.packet.index==#F.plans,'unexpected restoration')
   F.restore(owner);restore();emit('COMPLETE',{case='native-recipes',role='server',phases=6,restored=true})
   sendServerCommand(player,module,'Restored',{})
  end
 end)
 if not ok then emit('FAIL',{error=tostring(reason)})end
end)
