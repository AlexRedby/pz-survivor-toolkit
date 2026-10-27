if not isServer()then return end
local config=require 'QueueTestSelection'
if config.suite~='torch-refill'then return end
local session=require('TorchRefillSession').create(config,require 'TorchRefillAuthority',true)
Events.OnServerStarted.Add(session.prepare)
Events.OnClientCommand.Add(function(...)local ok,reason=pcall(session.command,...);if not ok then session.quarantine(reason)end end)
Events.OnTick.Add(session.tick)
