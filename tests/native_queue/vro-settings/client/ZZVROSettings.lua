local config=require 'QueueTestSelection'
local F=require 'VROSettingsFixture'
local started,done,sent=false,false,false
require('QueuePreflight').onGameStart(Events,function()started=true end)
Events.OnServerCommand.Add(function(module,command,row)
 if module~='VROSettingsTest' or command~='Authority' or not sent or done then return end
 local ok,error=pcall(function()
  F.verify(row,'server');F.emit('AUTHORITY',row)
  F.emit('COMPLETE',{case='custom-controls',role='client1'})
 end)
 done=true;if not ok then print('[VRO_SETTINGS] FAIL '..tostring(error)) end
end)
require('QueuePreflight').onTick(Events,function()
 if not started or done or sent or not isIngameState() then return end
 local player=getPlayer();if not player or not player:getSquare() then return end
 if config.kind=='mp' and (not isClient() or player:getOnlineID()<0) then return end
 local ok,error=pcall(function()
  F.observe('client1')
  if config.kind=='mp' then sent=true;sendClientCommand('VROSettingsTest','Observe',{})
  else done=true;F.emit('COMPLETE',{case='custom-controls',role='client1'}) end
 end)
 if not ok then done=true;print('[VRO_SETTINGS] FAIL '..tostring(error)) end
end)
