local create=require 'QueueFixtureSession'
local F=require 'TorchRefillFixture'
local JSON=require 'QueueHealthEvents'
local M={}
function M.create(config,factory,server)
 local options={cases=config.cases,user=server and 'server'or 'client1',actors={'client1'},module=F.module}
 if config.kind=='sp'then
  options.actor=function()return 'client1'end
  options.localPlayerReady=function(player)return player~=nil and player:getCurrentSquare()~=nil end
  options.transport=function(module,command,player,args,authority)
   M.messages[#M.messages+1]={module=module,command=command,player=player or getPlayer(),args=args,authority=authority}
  end
 end
 local factories={};for _,case in ipairs(config.cases)do factories[case]=factory end
 local session=create(options,factories,server)
 local quarantine=session.quarantine
 session.quarantine=function(reason)
  if session.phase~='quarantined'and session.phase~='done'then
   print('[TORCH_REFILL] FAIL '..JSON.encode({case=config.cases[session.index],epoch=session.epoch,error=tostring(reason)}))
  end
  quarantine(reason)
 end
 return session
end
function M.singleplayer(config,clientFactory)
 M.messages={}
 local authority=M.create(config,require 'TorchRefillAuthority',true)
 local client=M.create(config,clientFactory,false)
 M.localState=function()local context=authority.current();return context and context.state end
 authority.prepare();client.prepare()
 return function()
  -- Deliver only the previous tick's messages. A reply cannot enter a half-finished transition.
  local messages=M.messages;M.messages={}
  for _,entry in ipairs(messages)do
   local target=entry.authority and client or authority
   local ok,reason=pcall(target.command,entry.module,entry.command,entry.authority and nil or entry.player,entry.args)
   if not ok then target.quarantine(reason)end
  end
  authority.tick();client.tick()
 end
end
return M
