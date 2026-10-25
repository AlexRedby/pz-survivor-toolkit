if not isServer()then return end
local config=require 'QueueTestSelection'
if config.suite~='torch-refill'then return end
local F=require 'TorchRefillFixture'
local JSON=require 'QueueHealthEvents'
local state,pending
local function emit(event,data)print('[TORCH_REFILL] '..event..' '..JSON.encode(data))end
Events.OnClientCommand.Add(function(module,command,player)
 if module~=F.module then return end
 local ok,reason=pcall(function()
  assert(player:getUsername()=='client1','unexpected refill actor')
  if command=='Prepare'then
   assert(not state,'duplicate preparation');state=F.prepare(player)
   emit('PREPARED',state.packet);sendServerCommand(player,module,'Prepared',state.packet)
  else assert(command=='Verify'and state and not pending,'unexpected refill command');pending=getTimestampMs()end
 end)
 if not ok then emit('FAIL',{error=tostring(reason)})end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value,reason=pcall(F.receipt,state)
 if ok and value then
  emit('AUTHORITY',value);sendServerCommand(state.player,F.module,'Verified',value);pending=nil
 elseif not ok or getTimestampMs()-pending>20000 then
  emit('FAIL',{error=tostring(ok and reason or value)});pending=nil
 end
end)
