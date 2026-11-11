local F=require 'VROSettingsFixture'
local done=false
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='VROSettingsTest' or command~='Observe' or done or not player or player:getUsername()~='client1' then return end
 done=true
 local ok,error=pcall(function()
  local row=F.observe('server');F.emit('COMPLETE',{case='custom-controls',role='server'})
  sendServerCommand(player,'VROSettingsTest','Authority',row)
 end)
 if not ok then print('[VRO_SETTINGS] FAIL '..tostring(error)) end
end)
