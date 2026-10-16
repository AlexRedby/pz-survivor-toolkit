local M={}
function M.start(cfg,factory,server)
 local create=require 'QueueAnimalSession'
 local factories={};for _,case in ipairs(cfg.cases) do factories[case]=factory end
 local S=create({user=server and 'server' or 'client1',actors={'client1'},cases=cfg.cases,module='AnimalTrailerBaseline'},factories,server)
 Events.OnTick.Add(S.tick)
 if server then
  Events.OnServerStarted.Add(S.prepare)
  Events.OnClientCommand.Add(function(module,command,player,args) S.command(module,command,player,args) end)
 else
  Events.OnGameStart.Add(S.prepare)
  Events.OnServerCommand.Add(function(module,command,args) S.command(module,command,nil,args) end)
 end
 return S
end
return M
