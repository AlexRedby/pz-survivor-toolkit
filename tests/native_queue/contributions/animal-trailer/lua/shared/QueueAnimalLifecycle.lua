local M={}
function M.start(cfg,factory,server)
 local create=require 'QueueAnimalSession'
 local factories={};for _,case in ipairs(cfg.cases) do factories[case]=factory end
 local S=create({user=server and 'server' or 'client1',actors={'client1'},cases=cfg.cases,module='AnimalTrailerBaseline'},factories,server)
 S.configure=function(context) context.quarantine=S.quarantine end
 Events.OnTick.Add(S.tick)
 if server then
  Events.OnServerStarted.Add(S.prepare)
  Events.OnClientCommand.Add(function(module,command,player,args) S.command(module,command,player,args) end)
 else
  local function disconnected(reason)
   if S.current() and S.phase~='done' and S.phase~='quarantined' then S.quarantine(reason) end
  end
  Events.OnDisconnect.Add(function() disconnected('native disconnect during animal session') end)
  Events.OnMainMenuEnter.Add(function() disconnected('left world during animal session') end)
  Events.OnPreUIDraw.Add(function()
   if animalFixtureDisconnected() then disconnected('native server disconnect/kick during animal session') end
  end)
  Events.OnGameStart.Add(S.prepare)
  Events.OnServerCommand.Add(function(module,command,args) S.command(module,command,nil,args) end)
 end
 return S
end
return M
