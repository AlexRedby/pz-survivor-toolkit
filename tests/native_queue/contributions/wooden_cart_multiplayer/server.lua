local config=require 'QueueTestSelection'
assert(config.disposable==true,'Cart MP requires fresh owned disposable profiles')
local J=require 'CartMPJSON'
local players,ready,armed={}, {}, {}
local epoch,last,origin= nil,0,nil
Events.OnServerStarted.Add(function() print('[QUEUE_TEST] SERVER_READY') end)
Events.OnClientCommand.Add(function(module,command,p,args)
 if module~='CartMP' then return end
 local ok,e=pcall(function()
  local user=p:getUsername();assert(user=='client1' or user=='client2','unknown test actor')
  if command=='Ready' then
   if not players[user] then
    if not p:getCurrentSquare() then return end
    if not origin then origin=require('CartMPPlacement')(p) end
    local state={x=origin.x+(user=='client2' and 2 or 0),y=origin.y+(user=='client2' and 3 or 0),z=origin.z}
    if user=='client1' then
     local cart=assert(p:getInventory():AddItem('SaucedWheelbarrow.WheelbarrowWood'));state.cartId=cart:getID()
     local cargo=cart:getInventory():AddItem('Base.Log');cargo:setActualWeight(cart:getInventory():getEffectiveCapacity(p));cargo:setCustomWeight(true)
     sendAddItemToContainer(p:getInventory(),cart)
    end
    p:teleportTo(math.floor(state.x),math.floor(state.y),state.z)
    players[user]=p;ready[user]=state
   end
   sendServerCommand(p,module,'Setup',ready[user])
  elseif command=='Armed' then
   armed[user]=true
   if armed.client1 and armed.client2 and not epoch then
    epoch=getTimestampMs()+25000
    for _,v in pairs(players) do sendServerCommand(v,module,'Start',{epoch=epoch}) end
    print('[CART_MP] START epoch='..epoch)
   end
  else error('unknown test command') end
 end)
 if not ok then print('[QUEUE_TEST] FAIL CART_MP server '..tostring(e)) end
end)
Events.OnTick.Add(function()
 local now=getTimestampMs();if (epoch and now-epoch>16000) or now-last<(epoch and 100 or 500) then return end;last=now
 for _,p in pairs(players) do print('[CART_MP_STATE] '..cartMPState(p)) end
end)
