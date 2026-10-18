if not isServer() then return end
local config=require 'QueueTestSelection'
local Cart=require 'QueueCartPickup'
if not Cart.selected(config) then return end
Cart.validate(config)
local Fixture=require 'QueueEquipmentFixture'
local session,pending=nil,nil
local index,step=1,1
local function reply(player,command,args) sendServerCommand(player,'CartPickupTest',command,args) end
local function fail(player,problem)
 print('[QUEUE_TEST] FAIL equipment cart server '..tostring(problem))
 reply(player,'Failed',{ok=false,error=tostring(problem)})
end
local function remove(player,spec)
 local _,item=Cart.inspect(player,spec)
 assert(item,'cleanup lost exact fixture cart')
 player:removeFromHands(item)
 local world=item:getWorldItem()
 if world then local square=assert(world:getSquare());square:transmitRemoveItemFromSquare(world);square:removeWorldObject(world);item:setWorldItem(nil) end
 local container=item:getContainer()
 if container then container:Remove(item);sendRemoveItemFromContainer(container,item) end
 sendEquip(player)
 local row=Cart.inspect(player,spec)
 assert(row.inventoryCount==0 and row.worldCount==0,'fixture cart survived cleanup')
end
Events.OnServerStarted.Add(function() print('[EQUIPMENT_TEST] SERVER_READY') end)
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='CartPickupTest' then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1' and type(args)=='table','unexpected cart fixture actor/request')
  assert(args.index==index and Cart.types[index],'wrong cart fixture index')
  if command=='Prepare' then
   assert(not session and not pending and step==1,'out-of-order cart prepare')
   assert(player:getCurrentSquare(),'cart actor square unavailable')
   if index==1 then Fixture.position(player) end
   player:setGhostMode(true)
   assert(not player:getPrimaryHandItem() and not player:getSecondaryHandItem(),'cart fixture requires empty initial hands')
   local square=assert(player:getCurrentSquare())
   local cart=assert(instanceItem(Cart.types[index]),'cart item creation failed')
   local cargo=assert(cart:getInventory():AddItem('Base.Nails'),'cart cargo creation failed')
   session={index=index,id=cart:getID(),type=Cart.types[index],cargo=cargo:getID(),weight=cargo:getActualWeight(),
    x=square:getX(),y=square:getY(),z=square:getZ(),spawn={x=player:getX(),y=player:getY(),z=player:getZ()}}
   square:AddWorldInventoryItem(cart,.5,.5,0,true)
   assert(cart:getWorldItem(),'authoritative fixture world object missing')
   Cart.marker('PREPARED',Cart.receipt(player,session,'drop','server'))
   reply(player,'Prepared',session)
  elseif command=='Audit' then
   assert(session and not pending and args.id==session.id and args.phase==Cart.phases[step],'out-of-order cart audit')
   pending={player=player,since=getTimestampMs(),phase=args.phase}
  elseif command=='Cleanup' then
   assert(session and not pending and step==4 and args.id==session.id,'unverified cart cleanup')
   assert(Fixture.transactionsSettled(),'cart transfers active during cleanup')
   local spec=session;remove(player,spec)
   reply(player,'Cleaned',{index=index,id=spec.id,ok=true})
   Cart.marker('CLEANED',{actor='server',index=index,id=spec.id})
   session=nil;index=index+1;step=1
  else error('unknown cart fixture command') end
 end)
 if not ok then fail(player,problem) end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,problem=pcall(function()
  local now=getTimestampMs();assert(now-pending.since<20000,'authoritative cart state failed to converge '..pending.phase)
  local row=Cart.inspect(pending.player,session)
  if not pending.logged or now-pending.logged>=2000 then
   pending.logged=now;row.phase=pending.phase;row.actor='server';Cart.marker('STATE',row)
  end
  if not Fixture.transactionsSettled() or not Cart.matches(row,pending.phase=='drop') then pending.hold=nil;return end
  if not pending.hold then pending.hold=now;return end
  if now-pending.hold<500 then return end
  row=Cart.receipt(pending.player,session,pending.phase,'server');row.holdMs=now-pending.hold
  Cart.marker('RECEIPT',row)
  reply(pending.player,'Audited',row);step=step+1;pending=nil
 end)
 if not ok then local player=pending.player;pending=nil;fail(player,problem) end
end)
