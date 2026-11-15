local F=require 'VROGameplayFixture'
local P=require 'QueueEnergyPlacement'
local config=require 'QueueVROGameplayConfig'
local module='VROGameplayTest'
local state={players={},originals={},placed={},peers={},receipts={},index=1,since=getTimestampMs()}
local failed=false
local function all(value)return value.client1 and value.client2 end
local function broadcast(command,args)for _,player in pairs(state.players)do sendServerCommand(player,module,command,args or{})end end
local function fail(err)failed=true;F.emit('FAIL',{role='authority',stage=state.stage,reason=tostring(err)})end
local function place()
 state.placed={};state.peers={};state.stage='placing';state.since=getTimestampMs()
 broadcast('place',{packet=F.packet,index=state.index})
end
Events.OnClientCommand.Add(function(mod,command,player,args)
 if mod~=module or failed then return end
 local ok,err=pcall(function()
  local name=player:getUsername();assert(name=='client1'or name=='client2','foreign VRO client')
  if command=='ready'then
   assert(config.case=='bank'and not state.players[name],'duplicate VRO ready')
   state.players[name]=player;state.originals[name]=args.original
   if all(state.players)then F.prepare(state.players.client1);F.clientOriginals=state.originals;place()end
  elseif command=='placed'then
   assert(state.stage=='placing'and args.index==state.index and not state.placed[name],'unexpected placement')
   local ids=F.ids(F.packet,F.phases[state.index]);local target={x=ids.x+4,y=ids.y+(name=='client2'and 3 or 0),z=ids.z}
   assert(F.same(target,args.target),'placement target differs');state.placed[name]=P.observeCentered(player,target)
  elseif command=='action'then
   assert(name=='client1'and state.stage=='action'and args.index==state.index,'unexpected action receipt')
   state.receipt=args.receipt;state.stage='authority'
  elseif command=='peer'then
   assert(state.stage=='peers'and args.index==state.index and not state.peers[name]and F.same(args.world,state.world),'peer world differs')
   state.peers[name]=true
   if all(state.peers)then
    state.receipts[#state.receipts+1]=state.receipt;F.finishPhase();state.index=state.index+1
    if state.index>#F.phases then F.checkpoint(state.players.client1,state.receipts);state.stage='checkpoint';state.acks={};broadcast('checkpoint')
    else place()end
   end
  elseif command=='checkpoint'then
   assert(state.stage=='checkpoint'and not state.acks[name],'unexpected checkpoint ack');state.acks[name]=true
   if all(state.acks)then state.stage='complete';broadcast('complete')end
  elseif command=='reload-ready'then
   assert(config.case=='reload'and not state.players[name],'unexpected reload ready');state.players[name]=player
   if all(state.players)then state.stage='reload-verify'end
  elseif command=='reloaded-peer'then
   assert(state.stage=='reload-peers'and not state.peers[name]and F.same(args.worlds,state.worlds),'reload peer differs')
   state.peers[name]=true
   if all(state.peers)then state.stage='restoring';state.acks={};broadcast('restore-actor')end
  elseif command=='actor-restored'then
   assert(state.stage=='restoring'and args.restored and not state.acks[name],'unexpected actor restore')
   state.acks[name]=true
   if all(state.acks)then state.stage='reload-cleanup'end
  elseif command=='cleaned-peer'then
   assert(state.stage=='cleanup-peers'and not state.peers[name]and args.role==name
    and args.restored and args.ownedAbsent and F.same(args.worlds,state.worlds)
    and require('VROGameplayReload').actorMatches(args.actor,state.checkpoint.clientOriginals[name]),'cleanup peer differs')
   state.peers[name]=true
   if all(state.peers)then state.stage='complete';broadcast('complete')end
  else error('unsupported VRO protocol command '..command)end
 end)
 if not ok then fail(err)end
end)
require('QueuePreflight').onTick(Events,function()
 if failed or not state.stage or state.stage=='complete'then return end
 local ok,err=pcall(function()
  if state.stage=='placing'and all(state.placed)then
   local ready=true;for _,placement in pairs(state.placed)do if not P.poll(placement)then ready=false end end
   if ready then F.begin(state.players.client1,state.index);state.stage='action';sendServerCommand(state.players.client1,module,'action',{packet=F.packet,index=state.index})end
  elseif state.stage=='authority'then
   local world=F.after(state.players.client1,state.receipt)
   if world then state.world=world;state.stage='peers';broadcast('world',{index=state.index,world=world})end
  elseif state.stage=='reload-verify'then
   local reload=require('VROGameplayReload');local receipt=reload.verify(state.players.client1)
   if receipt then
    state.checkpoint=reload.begin(state.players.client1);state.worlds=receipt.worlds;state.peers={}
    F.emit('RELOADED',receipt);state.stage='reload-peers'
    broadcast('reload-world',{checkpoint=state.checkpoint,worlds=state.worlds})
   end
  elseif state.stage=='reload-cleanup'then
   local reload=require('VROGameplayReload')
   if not reload.restoreActor(state.players.client1,state.checkpoint.original,state.checkpoint)then return end
   local receipt=reload.cleanup(state.players.client1)
   if receipt then
    F.emit('CLEANUP',receipt);state.worlds=receipt.worlds;state.peers={};state.stage='cleanup-peers'
    broadcast('cleanup-world',{worlds=state.worlds})
   end
  end
  assert(getTimestampMs()-state.since<360000,'VRO authority phase timed out')
 end)
 if not ok then fail(err)end
end)
