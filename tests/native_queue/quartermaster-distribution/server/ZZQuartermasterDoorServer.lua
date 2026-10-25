local config=require 'QueueTestSelection'
if config.cases[1]~='barricaded-door' or not isServer()then return end
local F=require 'QuartermasterDoorFixture'
local JSON=require 'QueueHealthEvents'
local state,preparing,pending,cleaning,done
local function emit(event,value)print('[QM_DOOR] '..event..' '..JSON.encode(value))end
local function fail(problem)done=true;print('[QM_DOOR] FAIL server '..tostring(problem))end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module or done then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1','unexpected door distribution actor')
  if command=='Prepare'then
   assert(not state and not preparing,'duplicate door preparation')
   assert(type(args)=='table','missing door preparation point')
   for _,key in ipairs({'x','y','z'})do
    local value=args[key]
    assert(type(value)=='number'and value==value and value~=math.huge and value~=-math.huge
     and value==math.floor(value),'invalid door preparation coordinate '..key)
   end
   preparing={player=player,point={x=args.x,y=args.y,z=args.z},since=getTimestampMs()}
  elseif command=='Verify'then
   assert(state and player==state.player and not preparing and not pending and not state.verified,
    'invalid door authority verification')
   pending=getTimestampMs()
  elseif command=='Cleanup'then
   assert(state and player==state.player and state.verified and not pending and not cleaning,
    'door cleanup before authority verification')
   cleaning=getTimestampMs()
  else error('unknown door fixture command '..tostring(command))end
 end)
 if not ok then fail(problem)end
end)
Events.OnTick.Add(function()
 if done then return end
 local ok,problem=pcall(function()
  if preparing then
   local request=preparing;local player,point=request.player,request.point
   assert(getTimestampMs()-request.since<20000,'door server positioning timeout')
   if player:getCurrentSquare()and player:getCurrentSquare():getZ()==point.z
    and math.abs(player:getX()-point.x)<2 and math.abs(player:getY()-point.y)<2 then
    state=F.prepare(player,point);preparing=nil
    emit('PREPARED',{ids=state.ids})
    sendServerCommand(player,F.module,'Prepared',F.descriptor(state))
   end
  end
  if pending then
   assert(getTimestampMs()-pending<20000,'door authority convergence timeout')
   local result=F.receipt(state.player,state)
   if result then
    emit('AUTHORITY',result);state.verified=true;pending=nil
    sendServerCommand(state.player,F.module,'Verified',result)
   end
  end
  if cleaning then
   assert(getTimestampMs()-cleaning<LootSorter.ADD_GRACE_MS+21000,'door authority cleanup timeout')
   local result=F.cleanup(state)
   if result then
    emit('CLEANUP',result);sendServerCommand(state.player,F.module,'Cleaned',result);done=true
   end
  end
 end)
 if not ok then fail(problem)end
end)
