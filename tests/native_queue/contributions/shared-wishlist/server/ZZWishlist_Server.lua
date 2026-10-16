local states,ready,started={},{},false
Events.OnServerStarted.Add(function() print('[WISHLIST_TEST] SERVER_READY') end)
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='WishlistTest' then return end
 args=args or {}
 local user=player:getUsername()
 if command=='Ready' then
  if not states[user] then
   local ids={};states[user]=ids
   for _,spec in ipairs({{'watch1','Base.AlarmClock2'},{'watch2','Base.AlarmClock2'},{'tool','Base.Screwdriver'}})do
    local item=assert(player:getInventory():AddItem(spec[2]));ids[spec[1]]=item:getID();sendAddItemToContainer(player:getInventory(),item)
   end
   local o=IsoThumpable.new(getCell(),player:getCurrentSquare(),'carpentry_02_0',false,{})
   o:setCanPassThrough(true);o:setIsContainer(true);local c=o:getContainer();c:setType('crate');c:setCapacity(200);c:setExplored(true)
   o:getModData().WishlistTestOwner=user;player:getCurrentSquare():AddSpecialObject(o)
   for i=1,5 do c:AddItem('Base.Nails')end
   o:transmitCompleteItemToClients();o:transmitModData()
  end
  ready[user]=player
  if ready.client1 and ready.client2 and not started then
   started=true
   for name,p in pairs(ready)do sendServerCommand(p,'WishlistTest','Start',states[name])end
  end
 elseif command=='Faction' and user=='client1' then
  local faction=Faction.getFaction('WishlistTest')
  if not faction then faction=Faction.new('WishlistTest','client1');Faction.getFactions():add(faction)end
  if args.remove then faction:removePlayer('client2')else faction:addPlayer('client2')end
  print('[WISHLIST_TEST] FACTION '..tostring(args.remove))
 elseif command=='Verify' then
  local payload=PZSurvivorWishlist.Service.snapshot(player)
  local l;for _,row in ipairs(payload.lists)do if row.id=='client1'then l=row end end
  local ok=l and l.entries['Base.Hammer'] and l.entries['Base.Hammer'].amount==7 or false
  print('[WISHLIST_TEST] SERVER_VERIFY '..user..' ok='..tostring(ok))
  sendServerCommand(player,'WishlistTest','Verified',{ok=ok})
 end
end)
