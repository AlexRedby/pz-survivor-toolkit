local config=require 'QueueTestSelection'
if config.suite~='world-render'or not isServer()then return end
local F=require 'WorldRenderFixture'
local actors,ready={},{}
local failed=false
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module or failed then return end
 local ok,err=pcall(function()
  local role=player:getUsername();assert(role=='client1'or role=='client2','Unexpected actor')
  if command=='Prepare'then
   assert(not actors[role],'Duplicate preparation')
   local torch=F.prepare(player);actors[role]={player=player,torch=torch}
   sendServerCommand(player,F.module,'Prepared',{role=role,id=torch:getID()})
  elseif command=='Ready'then
   assert(actors[role]and not ready[role],'Duplicate/unprepared readiness');ready[role]=true
   F.emit('READY',{role=role,id=player:getOnlineID()})
   if ready.client1 and ready.client2 then
    assert(actors.client1.player:getOnlineID()~=actors.client2.player:getOnlineID(),'Shared peer identity')
    for _,state in pairs(actors)do sendServerCommand(state.player,F.module,'Start',{})end
   end
  elseif command=='Torch'then
   local state=assert(actors[role]);assert(type(args.active)=='boolean','Invalid torch state')
   local active=F.torch(player,state.torch,args.active)
   F.emit('AUTHORITY',{role=role,kind='torch',active=active})
   sendServerCommand(player,F.module,'Torch',{active=active})
  elseif command=='Switch'then
   assert(role=='client1'and ready.client2,'Only prepared owner controls switch')
   local obj=assert(F.object(args.target,'IsoLightSwitch'),'Native switch unavailable')
   assert(math.abs(player:getX()-args.target.x)<30 and math.abs(player:getY()-args.target.y)<30,'Switch outside fixture scene')
   obj:setActive(args.active)
   F.emit('AUTHORITY',{role=role,kind='switch',active=obj:isActivated()})
   sendServerCommand(player,F.module,'Switch',{active=obj:isActivated()})
  else error('Unexpected fixture command '..tostring(command))end
 end)
 if not ok then failed=true;F.emit('FAIL',{role='server',error=tostring(err)})end
end)
