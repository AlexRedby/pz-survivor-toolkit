local root=ProjectRoot..'/tests/native_tags/'
local Fixture=dofile(root..'shared/TagFixture.lua')
local grid,players,packets={}, {}, {}
local created,nextID=0,100
local now,diagnostics=10000,{}
getTimestampMs=function() return now end
local function list(values)
 return {size=function() return #values end,get=function(_,index) return values[index+1] end}
end
IsoDirections={W={-1,0},E={1,0},N={0,-1},S={0,1}}
AdjacentFreeTileFinder={privTrySquare=function() return true end}
local function square(x,y)
 local value={x=x,y=y,moving={},objects={}}
 value.getX=function() return value.x end;value.getY=function() return value.y end;value.getZ=function() return 0 end
 value.canStand=function() return #value.objects==0 end
 value.isFree=function(_,moving) return #value.objects==0 and (not moving or #value.moving==0) end
 value.getMovingObjects=function() return list(value.moving) end
 value.canReachTo=function() return true end
 value.getObjects=function() return list(value.objects) end
 value.getAdjacentSquare=function(_,direction) return grid[(value.x+direction[1])..','..(value.y+direction[2])] end
 value.AddSpecialObject=function(_,object) value.objects[#value.objects+1]=object end
 grid[x..','..y]=value;return value
end
local first,firstCrate,second,secondCrate=square(0,0),square(-1,0),square(8,0),square(9,0)
getCell=function() return {getGridSquare=function(_,x,y,z) if z==0 then return grid[x..','..y] end end} end
local function container()
 local value={items={}}
 value.getItems=function() return list(value.items) end
 value.setType=function() end;value.setCapacity=function() end;value.setExplored=function() end
 value.AddItem=function(_,kind)
  nextID=nextID+1
  local item={id=nextID,md={}}
  item.getID=function() return item.id end;item.getModData=function() return item.md end
  if kind=='Base.Bag_Schoolbag' then item.inventory=container();item.getInventory=function() return item.inventory end end
  value.items[#value.items+1]=item;return item
 end
 return value
end
local function player(name,start,inventory)
 local value={name=name,square=start,inventory=inventory or container()}
 value.getUsername=function() return name end
 value.getCurrentSquare=function() return value.square end
 value.getInventory=function() return value.inventory end
 start.moving={value};players[name]=value;return value
end
local one,two=player('client1',first),player('client2',second)
IsoThumpable={new=function(_,sq,sprite)
 assert(sprite==Fixture.crateSprite);created=created+1
 local object={md={},container=container()}
 object.setBlockAllTheSquare=function(_,value) assert(value) end;object.setIsContainer=function(_,value) assert(value) end
 object.getSquare=function() return sq end;object.getObjectIndex=function() return 0 end
 object.getModData=function() return object.md end;object.hasModData=function() return true end
 object.getContainer=function() return object.container end;object.getContainerByIndex=object.getContainer
 object.getContainerCount=function() return 1 end
 object.transmitCompleteItemToClients=function() end;object.transmitModData=function() end
 return object
end}
sendAddItemToContainer=function() end
sendServerCommand=function(auth,module,command,args)
 assert(module=='TagBaseline');assert(command~='Error',args.reason)
 packets[#packets+1]={player=auth,command=command,args=args}
end
instanceof=function(value,kind) return kind=='InventoryContainer' and value.inventory~=nil end
local handler
Events={OnServerStarted={Add=function() end},OnClientCommand={Add=function(fn) handler=fn end}}
require=function(module)
 if module=='QueueTestSelection' then return {tagRules=true} end
 if module=='TagFixture' then return Fixture end
 if module=='TagTestEvents' then return {encode=function(value)
  if value.reason then diagnostics[#diagnostics+1]=value end;return '{}'
 end} end
 assert(module=='Util/AdjacentFreeTileFinder',module)
end
dofile(root..'server/ZZTagBaseline.lua')
local function command(auth,id,args) handler('TagBaseline',id,auth,args or {}) end
local function placementPackets()
 local result={};for _,packet in ipairs(packets) do if packet.command=='Placement' then result[#result+1]=packet end end
 return result
end
command(one,'Ready')
assert(created==0 and #placementPackets()==0,'first actor created fixtures before second staging')
command(two,'Ready')
local initial=placementPackets()
assert(created==0 and #initial==2,'both actors did not receive placement request before creation')
local signature=initial[1].args.signature
assert(initial[2].args.signature==signature and #initial[1].args.squares==4,'placement signature/square set disagrees')
command(one,'PlacementReady',{signature='wrong'})
local stranger=player('stranger',square(30,30))
command(stranger,'PlacementReady',{signature=signature})
command(one,'Ready')
assert(created==0,'wrong signature or unregistered actor released barrier')
command(one,'PlacementReady',{signature=signature})
local count=#placementPackets();command(one,'Ready')
local repeated=placementPackets()
assert(created==0 and #repeated==count+1 and repeated[#repeated].player==two,'one ack released barrier or acked player was repolled')

-- A changed staging pair invalidates old acknowledgements before any world writes.
firstCrate.objects[1]={};local alternate=square(0,-1)
command(one,'Ready')
local updated=placementPackets();local newSignature=updated[#updated].args.signature
assert(newSignature~=signature and created==0,'changed placement did not revoke acknowledgements')
command(two,'PlacementReady',{signature=signature})
command(one,'PlacementReady',{signature=newSignature})
command(one,'Ready');assert(created==0,'stale second acknowledgement released barrier')
command(two,'PlacementReady',{signature=newSignature})
command(one,'Ready');command(two,'Ready')
assert(created==2 and #alternate.objects==1 and #secondCrate.objects==1,'two current acknowledgements did not permit exact fixture creation')
local setup={}
for _,packet in ipairs(packets) do if packet.command=='Setup' then setup[packet.player.name]=packet.args end end
assert(setup.client1 and setup.client2,'setup missing after barrier release')

-- A real reconnect reuses owned IDs/object and does not depend on the other actor.
two.square=nil
local reconnected=player('client1',first,one.inventory)
local before=#packets
command(reconnected,'Ready',{reconnect=true})
assert(created==2 and #packets==before+1 and packets[#packets].command=='Setup','reconnect recreated fixtures or reentered placement barrier')
assert(packets[#packets].player==reconnected and packets[#packets].args.source==setup.client1.source,
 'reconnect did not refresh authenticated player/preserve source ID')

-- Reloaded chunks contain new square/object references; old squares can be pooled
-- at unrelated coordinates. Inventory replication can also replace item objects.
local freshStart=square(0,0)
local oldCrate=alternate.objects[1]
local freshCrate=square(setup.client1.x,setup.client1.y)
local unowned={getSquare=function() return freshCrate end,hasModData=function() return false end}
local reloadedBox={}
for key,value in pairs(oldCrate) do reloadedBox[key]=value end
reloadedBox.getSquare=function() return freshCrate end;reloadedBox.getObjectIndex=function() return 1 end
freshCrate.objects={unowned,reloadedBox}
first.x,first.y=999,998;alternate.x,alternate.y=997,996
local function replica(original)
 local result=container()
 for _,item in ipairs(original.items) do
  local copy={id=item.id,md=item.md}
  copy.getID=function() return copy.id end;copy.getModData=function() return copy.md end
  if item.inventory then copy.inventory=replica(item.inventory);copy.getInventory=function() return copy.inventory end end
  result.items[#result.items+1]=copy
 end
 return result
end
local replicatedInventory=replica(one.inventory)
local reloadedPlayer=player('client1',freshStart,replicatedInventory)
local lastID=nextID
before=#packets
command(reloadedPlayer,'Ready',{reconnect=true})
assert(created==2 and nextID==lastID and #packets==before+1 and packets[#packets].command=='Setup',
 'chunk reload recreated objects/items, reentered barrier or teleported to a pooled square')
local updatedSetup=packets[#packets].args
assert(updatedSetup.index==1 and updatedSetup.x==setup.client1.x and updatedSetup.y==setup.client1.y,
 'reload did not reacquire exact owned crate at primitive coordinates/new index')
for _,key in ipairs({'source','battery','apple','beans','steak','manualCategory'}) do
 assert(updatedSetup[key]==setup.client1[key],'reload replaced original fixture ID/category '..key)
end
assert(reloadedPlayer.square==freshStart,'reload teleported away from correct fresh starting square')
-- Missing loaded cells remain pending without writes or any identity-based teleport.
now=now+1000;grid['0,0']=nil;before=#packets
command(reloadedPlayer,'Ready',{reconnect=true})
assert(created==2 and nextID==lastID and #packets==before,'missing start cell permitted setup/teleport/creation')
assert(diagnostics[#diagnostics].reason=='start square missing','missing start diagnostic absent')
local diagnosticCount=#diagnostics
command(reloadedPlayer,'Ready',{reconnect=true})
assert(#diagnostics==diagnosticCount,'Ready wait log is not bounded per actor')
grid['0,0']=freshStart;grid[setup.client1.x..','..setup.client1.y]=nil;now=now+1000
command(reloadedPlayer,'Ready',{reconnect=true})
assert(diagnostics[#diagnostics].reason=='crate square missing' and #packets==before)
grid[setup.client1.x..','..setup.client1.y]=freshCrate;freshCrate.objects={unowned};now=now+1000
command(reloadedPlayer,'Ready',{reconnect=true})
assert(diagnostics[#diagnostics].reason=='owned crate object missing' and #packets==before)
freshCrate.objects={unowned,reloadedBox};reloadedPlayer.inventory=container();now=now+1000
command(reloadedPlayer,'Ready',{reconnect=true})
assert(diagnostics[#diagnostics].reason=='owned source bag missing' and #packets==before)
assert(created==2 and nextID==lastID,'pending reconnect paths created new objects/items')
print('Native placement barrier checks passed: two-actor load barrier, invalid/stale ack rejection, reconnect with fresh/pooled squares, exact owner/index and replicated item IDs.')
