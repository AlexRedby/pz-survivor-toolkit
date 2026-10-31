local config=require 'QueueTestSelection'
if config.suite~='loot-resolved' or config.kind~='mp' or not isServer() then return end
local JSON=require 'QueueHealthEvents'
local module='LootResolvedNativeTest'
local mode=config.options.loot_runtime_mode
local pending,requested,done=nil,false,false
local function emit(event,value) print('[LOOT_RESOLVED_TEST] '..event..' '..JSON.encode(value)) end
local failed=false
local function fail(problem,player)
 if failed then return end
 failed=true
 done=true;emit('FAIL',{role='server',case='bank',error=tostring(problem)})
 if player then sendServerCommand(player,module,'BankStatus',{role='client1',case='bank',runtimeMode=mode,status='failed',cases=0}) end
end
Events.OnClientCommand.Add(function(name,command,player,args)
 if name~=module then return end
 local ok,problem=pcall(function()
  assert(not requested and not done and command=='RunBank','Duplicate/unknown authority request')
  assert(player and player:getUsername()=='client1' and player:getOnlineID()>=0 and player:getSquare(),'Foreign authority actor')
  assert(type(args)=='table' and args.role=='client1' and args.case=='bank' and args.runtimeMode==mode,'Request identity differs')
  requested=true;pending=player
  emit('REQUEST',{role='server',case='bank',runtimeMode=mode,onlineID=player:getOnlineID()})
 end)
 if not ok then fail(problem,player) end
end)
Events.OnTick.Add(function()
 if done or not pending then return end
 local player=pending;pending=nil
 local ok,problem=pcall(function()
  assert(isServer() and type(lootResolvedRuntimeRun)=='function' and type(lootResolvedRuntimeStatus)=='function','Server runtime API missing')
  assert(lootResolvedRuntimeStatus()=='not-run','Duplicate authoritative bank')
  assert(lootResolvedRuntimeRun()==true and lootResolvedRuntimeStatus()=='complete','Authoritative bank failed')
  emit('AUTHORITY',{role='server',case='bank',runtimeMode=mode,status='complete',cases=8,source='server-main-tick'})
  done=true
  sendServerCommand(player,module,'BankStatus',{role='client1',case='bank',runtimeMode=mode,status='complete',cases=8})
 end)
 if not ok then fail(problem,player) end
end)
