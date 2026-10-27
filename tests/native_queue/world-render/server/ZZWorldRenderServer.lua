local config=require 'QueueTestSelection'
if config.suite~='world-render'or not isServer()then return end
local F=require 'WorldRenderFixture'
local actors,ready={},{}
local resourcesReady,resourcesDone={},{}
local resourceTime,resourcesStarted,resourcesRestored
local failed=false
local function resourceActor(role,player)
 assert(config.options and config.options.world_render_resources==true,'Resource scenario not enabled')
 local state=assert(actors[role],'Unprepared resource actor')
 assert(ready.client1 and ready.client2,'Resource phase requires both prepared actors')
 assert(state.player:getOnlineID()==player:getOnlineID(),'Resource actor identity changed')
 return state
end
local function resourceBroadcast(command,args)
 for _,state in pairs(actors)do sendServerCommand(state.player,F.module,command,args)end
end
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
  elseif command=='ResourcesReady'then
   resourceActor(role,player)
   assert(not resourcesStarted and not resourcesReady[role],'Duplicate resource readiness')
   resourcesReady[role]=true
   if resourcesReady.client1 and resourcesReady.client2 then
    resourceTime=getGameTime():getTimeOfDay()
    assert(type(resourceTime)=='number'and resourceTime>=0 and resourceTime<24,'Invalid original server time')
    getGameTime():setTimeOfDay(12);resourcesStarted=true
    F.emit('RESOURCE_TIME',{stage='day',time=12})
    resourceBroadcast('ResourcesStart',{time=12})
   end
  elseif command=='ResourcesDone'then
   resourceActor(role,player)
   assert(resourcesStarted and not resourcesRestored and resourcesReady[role]and not resourcesDone[role],
    'Duplicate/unstarted resource completion')
   resourcesDone[role]=true
   if resourcesDone.client1 and resourcesDone.client2 then
    getGameTime():setTimeOfDay(resourceTime);resourcesRestored=true
    F.emit('RESOURCE_TIME',{stage='restored',time=resourceTime})
    resourceBroadcast('ResourcesRestored',{time=resourceTime})
   end
  else error('Unexpected fixture command '..tostring(command))end
 end)
 if not ok then failed=true;F.emit('FAIL',{role='server',error=tostring(err)})end
end)
