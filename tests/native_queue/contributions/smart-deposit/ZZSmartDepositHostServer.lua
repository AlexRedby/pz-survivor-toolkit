if not isServer()then return end
local F=require 'QueueSmartDepositHostFixture'
local session,actor,closed
local replies={Prepare='Prepared',Origin='Origind',Seed='Seeded',Effect='Effected',Extras='Extrasd',Full='Fulld',Release='Released',Cleanup='Cleanupd',Abort='Abortd'}
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module then return end
 local ok,result=pcall(function()
  assert(type(args)=='table'and args.case=='partial'and player:getUsername()=='client1','unexpected Smart Deposit actor/case')
  assert(not closed,'closed Smart Deposit session')
  if command=='Prepare'then
   assert(not session,'duplicate Smart Deposit preparation');local square=assert(player:getSquare());local spawn=assert(args.spawn)
   if square:getX()~=spawn.x or square:getY()~=spawn.y or square:getZ()~=spawn.z then return {waiting=true}end
   actor=player;session=F.prepare(player);return session.ids
  end
  assert(session and actor==player and args.token==session.token,'wrong Smart Deposit session')
  if command=='Abort'then local receipt=F.abort(session);closed=true;F.emit('ABORT',receipt);return receipt end
  if command=='Origin'then return F.origin(session,args.index)
  elseif command=='Seed'then return F.seed(session,args.index,args.order)
  elseif command=='Effect'then return F.effect(session,args.index,args.sampleIds)
  elseif command=='Extras'then return F.extras(session,args.index)
  elseif command=='Full'then return F.full(session,args.index)
  elseif command=='Release'then return F.release(session,args.index)
  elseif command=='Cleanup'then local receipt=F.cleanup(session);closed=true;return receipt end
  error('unknown Smart Deposit command')
 end)
 if ok then sendServerCommand(player,module,assert(replies[command]),result)
 else
  local s=session or F.preparing;local row={token=s and s.token or 'unprepared',index=s and s.phase and s.phase.index or 0,command=command,error=tostring(result)}
  if s then local captured,snapshot=pcall(F.snapshot,s);if captured then row.snapshot=snapshot end end
  local restored,receipt=pcall(F.abort,s);row.restored=restored
  if restored then row.cleanup=receipt else row.restoreError=tostring(receipt)end
  closed=true;F.emit('FAIL',row);print('[QUEUE_TEST] FAIL Smart Deposit server '..tostring(result))
  sendServerCommand(player,module,'Failed',{error=tostring(result),restored=restored})
 end
end)
