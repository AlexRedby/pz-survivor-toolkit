local Session=QueueWishlistSession
local Events=Session and Session.events or Events
local function reply(player,command,args)
 if Session then Session.reply(player,command,args) else sendServerCommand(player,'WishlistTest',command,args or {}) end
end
local states,ready,started={},{},false
local observations,index={},1
local barriers={'completion-observed','faction-edit-observed','faction-revocation-observed'}
Events.OnServerStarted.Add(function()
 if WishlistSeedRestore then WishlistSeedRestore()end
 print('[WISHLIST_TEST] SERVER_READY')
end)
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='WishlistTest' then return end
 args=args or {}
 local user=player:getUsername()
 if user~='client1'and user~='client2'then print('[WISHLIST_TEST] FAIL unexpected fixture actor '..tostring(user));return end
 if command=='Ready' then
  if not states[user] then
   if Session then Session.player(player) end
   local ids={};states[user]=ids
   for _,spec in ipairs({{'watch1','Base.AlarmClock2'},{'watch2','Base.AlarmClock2'},{'tool','Base.Screwdriver'}})do
    local item=assert(player:getInventory():AddItem(spec[2]));ids[spec[1]]=item:getID();if Session then Session.ownItem(item) end;sendAddItemToContainer(player:getInventory(),item)
   end
   local o=IsoThumpable.new(getCell(),player:getCurrentSquare(),'carpentry_02_0',false,{})
   o:setCanPassThrough(true);o:setIsContainer(true);local c=o:getContainer();c:setType('crate');c:setCapacity(200);c:setExplored(true)
   o:getModData().WishlistTestOwner=user;player:getCurrentSquare():AddSpecialObject(o)
   if Session then Session.ownObject(o) end
   for i=1,5 do local item=c:AddItem('Base.Nails');if Session then Session.ownItem(assert(item)) end end
   o:transmitCompleteItemToClients();o:transmitModData()
  end
  ready[user]=player
  if ready.client1 and ready.client2 and not started then
   started=true
   for name,p in pairs(ready)do reply(p,'Start',states[name])end
  end
 elseif command=='Observed' then
  if not started or ready[user]~=player or args.key~=barriers[index]or observations[user]then
   print('[WISHLIST_TEST] FAIL invalid joint observation '..tostring(user)..' '..tostring(args.key));return
  end
  observations[user]=true
  if observations.client1 and observations.client2 then
   print('[WISHLIST_TEST] BARRIER_RELEASE '..args.key..' actors=client1,client2')
   for _,p in pairs(ready)do reply(p,'Continue',{key=args.key})end
   observations={};index=index+1
  end
 elseif command=='Faction' and user=='client1' then
  local faction=Faction.getFaction('WishlistTest')
  if not faction then faction=Faction.new('WishlistTest','client1');Faction.getFactions():add(faction);if Session then Session.faction=faction end end
  if args.remove then faction:removePlayer('client2')else faction:addPlayer('client2')end
  print('[WISHLIST_TEST] FACTION '..tostring(args.remove))
 elseif command=='Verify' then
  local payload=PZSurvivorWishlist.Service.snapshot(player)
  local l;for _,row in ipairs(payload.lists)do if row.id=='client1'then l=row end end
  local ok=l and l.entries['Base.Hammer'] and l.entries['Base.Hammer'].amount==7 or false
  print('[WISHLIST_TEST] SERVER_VERIFY '..user..' ok='..tostring(ok))
  reply(player,'Verified',{ok=ok})
 end
end)

if Session then
 Session.ownerKey='WishlistTestOwner'
 assert(not Faction.getFaction('WishlistTest'),'preexisting fixture faction must not be changed')
 local function empty(values)
  for _ in pairs(values) do return false end
  return true
 end
 Session.cleanup=function()
  for user,player in pairs(ready) do
   local snapshot=PZSurvivorWishlist.Service.snapshot(player);assert(not snapshot.error,'wishlist storage error during reset')
   if Session.case=='visual' then
    for _,list in ipairs(snapshot.lists) do
     assert(list.owner==user and empty(list.entries) and empty(list.members) and not list.faction,'visual case mutated wishlist data')
    end
   end
  end
  if Session.faction then
   assert(Faction.getFaction('WishlistTest')==Session.faction,'fixture faction identity changed')
   Faction.getFactions():remove(Session.faction);assert(not Faction.getFaction('WishlistTest'),'owned faction survived reset')
  end
  Session.cleanOwned();states={};ready={};observations={};started=false
  return true
 end
end
