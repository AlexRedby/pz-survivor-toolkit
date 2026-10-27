if not isServer()then return end
local F=require 'QueueMakeup';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local state,previous,pending,placement=nil,nil,nil,nil;local index,sequence=1,0
local function raw(marker,row)print('[MAKEUP_TEST] '..marker..' '..JSON.encode(row))end
local function fail(player,problem)
 print('[QUEUE_TEST] FAIL makeup server '..tostring(problem));sendServerCommand(player,'MakeupTest','Failed',{error=tostring(problem)})
end
Events.OnServerStarted.Add(function()raw('SERVER_READY',{})end)
Events.OnClientCommand.Add(function(module,name,player,args)
 if module~='MakeupTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'makeup authority actor/case/order differs')
  if name=='Prepare'then
   assert(not state and not pending,'previous makeup case unsettled')
   if config.options and (config.options.makeup_supplies==true or config.options.makeup_moves==true or config.options.makeup_carried_moves==true or config.options.makeup_world_moves==true) then
    assert(F.validPlacement(args.placement)and(not placement or F.same(placement,args.placement)),'makeup authority placement target differs')
    pending={prepare=true,since=getTimestampMs(),player=player,placement=args.placement,case=args.case}
   else
    state=F.prepare(player,args.case,previous);sequence=0;raw('PREPARED',state.ids)
    sendServerCommand(player,module,'Prepared',state.ids)
   end
  elseif name=='WearPrepared'then
   assert(state and not pending and args.item==state.ids.items.old,'prepared root acknowledgement differs')
   F.wearPrepared(state);raw('PREPARED',state.ids);sendServerCommand(player,module,'WornPrepared',state.ids)
  elseif name=='Snapshot'then
   assert(state and not pending and type(args.label)=='string'and args.sequence==sequence+1,'makeup authority snapshot ordering differs')
   pending={since=getTimestampMs(),player=player,label=args.label,sequence=args.sequence}
  elseif name=='Finish'then
   assert(state and not pending and not player:hasTimedActions()and player:getCharacterActions():isEmpty(),'makeup authority not idle')
   local row={case=args.case,sequence=sequence,snapshot=F.snapshot(state)}
   raw('VERIFIED',row);sendServerCommand(player,module,'Verified',row)
   previous=state.ids;state=nil;index=index+1
  else error('unknown makeup authority command')end
 end)
 if not ok then fail(player,problem)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local player=pending.player
 local ok,problem=pcall(function()
  local time=getTimestampMs();assert(time-pending.since<30000,'makeup authority placement/checkpoint timed out')
  if pending.prepare then
   if not F.atPlacement(player,pending.placement)then return end
   placement=pending.placement;state=F.prepare(player,pending.case,previous,placement);sequence=0;if not state.ids.wearPending then raw('PREPARED',state.ids)end
   sendServerCommand(player,'MakeupTest','Prepared',state.ids);pending=nil;return
  end
  local value=F.snapshot(state)
  if not pending.snapshot or not F.same(value,pending.snapshot)then pending.snapshot=value;pending.quiet=time;return end
  if time-pending.quiet<500 then return end
  sequence=pending.sequence
  local row={case=state.ids.case,label=pending.label,sequence=sequence,at=time,snapshot=value}
  raw('SNAPSHOT',row);sendServerCommand(player,'MakeupTest','Snapshot',row);pending=nil
 end)
 if not ok then pending=nil;fail(player,problem)end
end)
