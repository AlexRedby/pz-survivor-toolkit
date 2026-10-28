local F=require 'TorchRefillFixture'
local JSON=require 'QueueHealthEvents'
local function emit(event,data)print('[TORCH_REFILL] '..event..' '..JSON.encode(data))end
return function(context)
 local pending,restorePending,restored
 context.cleanup=function()
  assert(context.state and not pending and not restorePending and restored,'authority requests/baseline not drained')
  context.receipt=F.remove(context.state);context.receipt.baselineRestored=true;emit('REMOVED',context.receipt);return true
 end
 context.events.OnClientCommand.Add(function(module,command,player,args)
  assert(not isServer()or player:getUsername()=='client1','unexpected refill actor')
  if command=='Prepare'then
   assert(not context.state,'duplicate preparation');context.state=F.prepare(player,context.case,context.epoch)
   emit('PREPARED',context.state.packet);context.reply(player,'Prepared',context.state.packet)
  elseif command=='Verify'then
   assert(context.state and not pending,'unexpected refill verification');pending=getTimestampMs()
  elseif command=='RestoreBaseline'then
   assert(context.state and not pending and not restorePending and not restored,'unexpected baseline restoration')
   for _,key in ipairs({'x','y','z','primaryID','secondaryID'})do assert(type(args[key])=='number','invalid baseline field '..key)end
   restorePending={args=args,since=getTimestampMs()}
  else error('unexpected refill command '..tostring(command))end
 end)
 context.events.OnTick.Add(function()
  if restorePending then
   local player,args=context.state.player,restorePending.args
   local primary,secondary=player:getPrimaryHandItem(),player:getSecondaryHandItem()
   if math.abs(player:getX()-args.x)<.01 and math.abs(player:getY()-args.y)<.01 and player:getZ()==args.z
    and(primary and primary:getID()or -1)==args.primaryID and(secondary and secondary:getID()or -1)==args.secondaryID then
    restored=true;restorePending=nil;context.reply(player,'BaselineRestored',{})
   else assert(getTimestampMs()-restorePending.since<12000,'authority baseline restoration timeout')end
  end
  if not pending then return end
  local value,reason=F.receipt(context.state)
  if value then
   emit('AUTHORITY',value);context.reply(context.state.player,'Verified',value);pending=nil
  elseif getTimestampMs()-pending>20000 then error('authority effect timeout '..tostring(reason))end
 end)
end
