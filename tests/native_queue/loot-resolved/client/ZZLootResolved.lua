local config=require 'QueueTestSelection'
if config.suite~='loot-resolved' then return end
local JSON=require 'QueueHealthEvents'
local module='LootResolvedNativeTest'
local mode=config.options.loot_runtime_mode
local case=config.cases and config.cases[1] or 'bank'
local counts={bank=8,semantics=12,reload=1}
local banks={bank='base',semantics='semantics',reload='reload'}
local count=assert(counts[case],'Unknown loot bank case')
local function run(player)
 assert(type(lootResolvedRuntimeBank)=='function' and lootResolvedRuntimeBank()==banks[case],'Runtime bank differs')
 if case=='bank' then return lootResolvedRuntimeRun() end
 assert(type(lootResolvedRuntimeRunFor)=='function','Runtime actor API missing')
 return lootResolvedRuntimeRunFor(player)
end
local started,sent,done=false,false,false
local sentAt
local function emit(event,value) print('[LOOT_RESOLVED_TEST] '..event..' '..JSON.encode(value)) end
local failed=false
local function fail(problem)
 if failed then return end
 failed=true
 done=true;emit('FAIL',{role='client1',case=case,error=tostring(problem)})
end
local function finish(source)
 emit('AUTHORITY',{role='client1',case=case,runtimeMode=mode,status='complete',cases=count,source=source})
 done=true
 emit('COMPLETE',{role='client1',case=case,runtimeMode=mode,status='complete',authority=true})
end
Events.OnGameStart.Add(function() started=true end)
Events.OnServerCommand.Add(function(name,command,args)
 if name~=module then return end
 local ok,problem=pcall(function()
  assert(config.kind=='mp' and isClient() and sent and not done,'Unrequested/duplicate authority response')
  assert(command=='BankStatus' and type(args)=='table','Unexpected bank response')
  assert(args.role=='client1' and args.case==case and args.runtimeMode==mode,'Authority response identity differs')
  assert(args.status=='complete' and args.cases==count,'Authority bank failed: '..tostring(args.status))
  assert(type(lootResolvedRuntimeStatus)=='function' and lootResolvedRuntimeStatus()=='not-run','Client ran authority bank')
  finish('server-response')
 end)
 if not ok then fail(problem) end
end)
Events.OnTick.Add(function()
 if done or not started or not isIngameState() then return end
 local ok,problem=pcall(function()
  local player=getPlayer()
  if not player or player:isDead() or not player:getSquare() then return end
  assert(type(lootResolvedRuntimeRun)=='function' and type(lootResolvedRuntimeStatus)=='function','Runtime API missing')
  if config.kind=='mp' then
   if not isClient() or player:getOnlineID()<0 then return end
   if sent then assert(getTimestampMs()-sentAt<120000,'Authority response timed out');return end
   local reader=assert(getFileReader('smoke-user.txt',false),'Owned client marker missing')
   local role=reader:readLine();reader:close();assert(role=='client1' and player:getUsername()=='client1','Foreign fixture actor')
   assert(lootResolvedRuntimeStatus()=='not-run','Client bank status differs before request')
   sent=true;sentAt=getTimestampMs()
   emit('REQUEST',{role='client1',case=case,runtimeMode=mode,onlineID=player:getOnlineID()})
   sendClientCommand(module,'RunBank',{role='client1',case=case,runtimeMode=mode})
  else
   assert(not isClient() and not isServer(),'SP authority differs')
   assert(not sent and lootResolvedRuntimeStatus()=='not-run','Duplicate SP bank')
   sent=true
   assert(run(player)==true and lootResolvedRuntimeStatus()=='complete','SP bank failed')
   finish('sp-main-tick')
  end
 end)
 if not ok then fail(problem) end
end)
