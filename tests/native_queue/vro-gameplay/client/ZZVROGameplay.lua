local F=require 'VROGameplayFixture'
local P=require 'QueueEnergyPlacement'
local config=require 'QueueVROGameplayConfig'
local state={stage='ready',index=1,receipts={},since=getTimestampMs()}
local module='VROGameplayTest'
local failed,done=false,false
local function role()return isClient()and getPlayer():getUsername()or'client1'end
local function fail(err)failed=true;F.emit('FAIL',{stage=state.stage,reason=tostring(err)})end
local function send(command,args)sendClientCommand(module,command,args or{})end
local function complete()
 done=true;F.emit('COMPLETE',{role=role(),case=config.case})
end
local function savedQuit()
 local writer=assert(getFileWriter('vro-gameplay-exit.txt',true,false));writer:write(config.case);writer:close()
 state.stage='exiting';setGameSpeed(1);getCore():quit()
end
Events.OnMainMenuEnter.Add(function()
 local reader=getFileReader('vro-gameplay-exit.txt',false)
 if not reader then return end
 local pending=reader:readLine();reader:close()
 if pending~=config.case then return end
 F.emit('SAVED_RETURN',{case=config.case,role='client1',saved=true,returned=true})
 F.emit('COMPLETE',{role='client1',case=config.case});done=true
end)
local function place(packet,index)
 state.packet=packet;state.index=index;state.phase=F.phases[index];state.ids=F.ids(packet,state.phase)
 local target={x=state.ids.x+4,y=state.ids.y,z=state.ids.z}
 if role()=='client2'then target.y=target.y+3 end
 state.placement=P.beginCentered(getPlayer(),target);state.stage='placing';state.since=getTimestampMs()
end
Events.OnServerCommand.Add(function(mod,command,args)
 if mod~=module or failed or done then return end
 local ok,err=pcall(function()
  if command=='place'then place(args.packet,args.index)
  elseif command=='action'then
   assert(role()=='client1'and state.stage=='await-action'and args.index==state.index,'unexpected action grant')
   if state.index==1 then F.skills(getPlayer())end
   state.packet=args.packet;state.ids=F.ids(args.packet,state.phase);state.stage='inputs'
  elseif command=='world'then
   assert(args.index==state.index,'world receipt phase mismatch');state.expected=args.world;state.stage='world'
  elseif command=='checkpoint'then
   assert(state.index==#F.phases and state.stage=='await-next','premature checkpoint')
   F.emit('CHECKPOINT_PEER',{role=role(),retainedForReload=true});send('checkpoint',{});state.stage='checkpoint'
  elseif command=='complete'then complete()
  elseif command=='reload-world'then state.expectedWorlds=args.worlds;state.checkpoint=args.checkpoint;state.stage='reload-world'
  elseif command=='cleanup-world'then state.expectedWorlds=args.worlds;state.cleanupSince=getTimestampMs();state.stage='cleanup-world'
  elseif command=='restore-actor'then state.stage='restore-actor'
  end
 end)
 if not ok then fail(err)end
end)
local function peer(world)
 F.emit('PEER',{phase=state.phase,index=state.index,role=role(),world=world})
 if isClient()then send('peer',{index=state.index,world=world});state.stage='await-next'
 else
  F.finishPhase();state.index=state.index+1
  if state.index>#F.phases then F.checkpoint(getPlayer(),state.receipts);savedQuit()
  else place(state.packet,state.index)end
 end
end
local function run()
 local player=getPlayer()
 if state.stage=='ready'then
  if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:onClose()end
  state.original=F.actor(player)
  if config.case=='reload'then
   if isClient()then send('reload-ready',{});state.stage='reload-wait'
   else state.stage='reload-verify'end
  elseif isClient()then
   send('ready',{original=state.original});state.stage='await-place'
  else place(F.prepare(player),1)end
 elseif state.stage=='placing'then
  if not P.poll(state.placement)then return end
  if isClient()then send('placed',{index=state.index,target=state.placement.target});state.stage='await-action'
  else state.packet=F.begin(player,state.index);state.ids=F.ids(state.packet,state.phase);state.stage='inputs'end
 elseif state.stage=='inputs'then
  if not F.ready(player,state.ids)then return end
  state.action=F.family(state.phase).start(player,state.ids,F.mode(state.phase));state.stage='action'
 elseif state.stage=='action'then
  local receipt=F.family(state.phase).poll(state.action)
  if not receipt then return end
  F.family(state.phase).close(state.action);state.action=nil;state.receipts[#state.receipts+1]=receipt
  if isClient()then send('action',{index=state.index,receipt=receipt});state.stage='await-world'
  else state.expected=assert(F.after(player,receipt));state.stage='world'end
 elseif state.stage=='world'then
  local world=F.world(state.ids)
  if not world or not F.same(world,state.expected)then return end
  peer(world)
 elseif state.stage=='reload-verify'then
  local receipt=require('VROGameplayReload').verify(player)
  if not receipt then return end
  F.emit('RELOADED',receipt)
  F.emit('RELOADED',{role='client1',worlds=receipt.worlds});state.stage='reload-cleanup'
 elseif state.stage=='reload-cleanup'then
  local receipt=require('VROGameplayReload').cleanup(player)
  if not receipt then return end
  if isClient()then send('actor-restored',receipt);state.stage='reload-wait'
  else
   local reload=require('VROGameplayReload');local checkpoint=reload.begin(player)
   local actor=assert(reload.cleanedActor(player,checkpoint.clientOriginals.client1,checkpoint),'SP owned inventory cleanup incomplete')
   F.emit('CLEANUP',receipt);F.emit('CLEANUP',{role='client1',worlds=receipt.worlds,actor=actor,restored=true,ownedAbsent=true});savedQuit()
  end
 elseif state.stage=='restore-actor'then
  local original=assert(state.checkpoint.clientOriginals[role()])
  local receipt=require('VROGameplayReload').restoreActor(player,original,state.checkpoint)
  if not receipt then return end
  send('actor-restored',receipt);state.stage='reload-wait'
 elseif state.stage=='reload-world'or state.stage=='cleanup-world'then
  local reload=require('VROGameplayReload')
  if state.stage=='reload-world'and role()=='client1'and not reload.verify(player,state.checkpoint)then return end
  local worlds=reload.worlds(state.checkpoint)
  if not worlds or not F.same(worlds,state.expectedWorlds)then return end
  local event=state.stage=='reload-world'and'RELOADED'or'CLEANUP'
  local receipt={role=role(),worlds=worlds}
  if event=='CLEANUP'then
   local actor=reload.cleanedActor(player,state.checkpoint.clientOriginals[role()],state.checkpoint)
   if not actor then
    assert(getTimestampMs()-state.cleanupSince<20000,'client original actor or owned inventory absence did not settle')
    return
   end
   receipt.actor=actor;receipt.restored=true;receipt.ownedAbsent=true
  end
  F.emit(event,receipt);send(event=='RELOADED'and'reloaded-peer'or'cleaned-peer',receipt)
  state.stage='reload-wait'
 end
 assert(getTimestampMs()-state.since<600000,'VRO gameplay bank timed out')
end
require('QueuePreflight').onTick(Events,function()
 if failed or done or not isIngameState()or not getPlayer()or not getPlayer():getSquare()then return end
 local ok,err=pcall(run);if not ok then fail(err)end
end)
