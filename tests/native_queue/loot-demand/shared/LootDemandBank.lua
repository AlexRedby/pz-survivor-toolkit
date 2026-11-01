local config=require 'QueueTestSelection'
if config.suite~='loot-demand' then return end
LootDemandBank={}
local B=LootDemandBank
local function check(value,message) assert(value,'loot-demand: '..message) end
local function identities(container)
 local out={}
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i)
  check(out[item:getID()]==nil,'duplicate item identity '..tostring(item:getID()))
  out[item:getID()]=item:getFullType()
 end
 return out
end
local function same(container,saved)
 local now=identities(container)
 for id,name in pairs(saved) do check(now[id]==name,'changed/lost item '..tostring(id));now[id]=nil end
 for _ in pairs(now) do error('loot-demand: unexpected additional items') end
end
function B.run(player)
 check(not isClient() and lootDemandInstalled(),'authority hook required')
 check(LootDemandFurniture and LootDemandFurniture.installed,'furniture integration inactive')
 local owned,observed={},{}
 local function create(kind,spriteName)
  local square=player:getSquare()
  local object=IsoObject.new(getCell(),square,assert(getSprite(spriteName or lootDemandSprite(kind))))
  object:createContainersFromSpriteProperties()
  square:AddTileObject(object);owned[#owned+1]=object
  local container=assert(object:getContainer())
  check(container:getType()==kind and not container:isExplored() and container:isEmpty(),'fresh native container')
  observed[container]={calls=0}
  return object,container,observed[container]
 end
 local function fill(room,kind,container)
  local row=observed[container];if not row then return end
  row.calls=row.calls+1
  check(row.calls==1,'repeated fill callback')
  -- One fixture sentinel makes a legitimate empty random draw observable.
  row.sentinel=assert(container:AddItem('Base.Nails')):getID()
  if row.reenter then ItemPickerJava.fillContainer(container,player) end
  row.generated=identities(container)
 end
 Events.OnFillContainer.Add(fill)
 local ok,problem=pcall(function()
  for _,kind in ipairs({'bin','dumpster'}) do
   local object,container,row=create(kind)
   check(lootDemandPending(container),'pristine target must be pending')
   lootDemandAutomatic(object,false);lootDemandAutomatic(object,true)
   check(not container:isExplored() and container:isEmpty() and row.calls==0,'automatic path filled pending '..kind)
   check(lootDemandSerialized(container),'pending native serialization')
   row.reenter=true
   local started=getTimestampMs()
   check(lootDemandEnsure(container,player),'authority ensure returned false')
   local elapsed=getTimestampMs()-started
   check(container:isExplored() and row.calls==1 and not container:isEmpty(),'first demand must fill once')
   local saved=identities(container)
   check(lootDemandEnsure(container,player),'repeat demand failed');same(container,saved)
   check(row.calls==1 and lootDemandSerialized(container),'repeat or completed serialization differs')
   print('[LOOT_DEMAND_TEST] PASS '..kind..' first_access_ms='..elapsed..' items='..container:getItems():size())
  end
  local object,container,row=create('bin')
  local existing=assert(container:AddItem('Base.Nails'))
  lootDemandAutomatic(object,false)
  check(container:isExplored() and container:getItems():contains(existing),'existing owned item changed')
  print('[LOOT_DEMAND_TEST] PASS existing-items')
  local object,container,row=create('bin')
  lootDemandAutomatic(object,false)
  check(not container:isExplored(),'destroy target was eagerly filled')
  object:dumpContentsInSquare()
  check(row.calls==1 and container:isExplored(),'destruction did not ensure')
  check(container:isEmpty(),'native dump left items inside destroyed target')
  local found={}
  local ground=object:getSquare():getWorldObjects()
  for i=0,ground:size()-1 do local item=ground:get(i):getItem();found[item:getID()]=item:getFullType() end
  for id,name in pairs(row.generated) do check(found[id]==name,'destruction lost generated item '..id) end
  print('[LOOT_DEMAND_TEST] PASS destroy-fill')
  local object,container,row=create('bin',lootDemandTrashSprite())
  lootDemandAutomatic(object,false)
  check(lootDemandPending(container) and row.calls==0,'trash target not pending')
  lootDemandTrash(player,object)
  check(container:isExplored() and container:isEmpty() and row.calls==0,'empty-trash must cancel uncreated loot')
  lootDemandTrash(player,object)
  check(lootDemandEnsure(container,player) and row.calls==0 and container:isEmpty(),'trash command permitted later refill')
  print('[LOOT_DEMAND_TEST] PASS empty-trash')
 end)
 Events.OnFillContainer.Remove(fill)
 -- Everything created here is fixture-owned in a disposable world. Do not remove preexisting objects/items.
 for _,object in ipairs(owned) do
  if object:getSquare() then object:getSquare():RemoveTileObject(object) end
 end
 if not ok then error(problem) end
 return true
end


-- One real Host request/replication exchange in the same run. The custom command
-- only sets up and verifies the object; native RequestItemsForContainer fills it.
local network
function B.prepareNetwork(player)
 check(isServer() and not isClient() and not network,'fresh Host authority required')
 local origin=player:getSquare();local square
 for dx=4,7 do
  local candidate=getCell():getGridSquare(origin:getX()+dx,origin:getY(),origin:getZ())
  if candidate and candidate:getFloor() then square=candidate;break end
 end
 check(square,'no loaded square outside nearby inventory scan')
 local object=IsoObject.new(getCell(),square,assert(getSprite(lootDemandSprite('bin'))))
 object:createContainersFromSpriteProperties();object:setName('LootDemandNativeProbe');square:AddTileObject(object)
 local container=assert(object:getContainer());check(lootDemandPending(container),'native request source not pending')
 lootDemandAutomatic(object,false)
 check(not container:isExplored() and container:isEmpty(),'native request source eagerly filled')
 network={object=object,container=container,calls=0}
 network.callback=function(room,kind,current)
  if current~=container then return end
  network.calls=network.calls+1;check(network.calls==1,'duplicate Host packet fill')
  assert(container:AddItem('Base.Nails'))
 end
 Events.OnFillContainer.Add(network.callback)
 object:transmitCompleteItemToClients()
 return {x=square:getX(),y=square:getY(),z=square:getZ(),index=object:getObjectIndex(),name=object:getName()}
end
function B.verifyNetwork(player,args)
 check(network and type(args)=='table' and type(args.fingerprint)=='string','missing native observation')
 check(network.container:isExplored() and network.calls==1,'Host did not fill exactly once')
 check(lootDemandFingerprint(network.container)==args.fingerprint,'client contents differ from authority')
 check(args.requests==2,'expected repeated native content request')
 Events.OnFillContainer.Remove(network.callback)
 network.object:getSquare():transmitRemoveItemFromSquare(network.object)
 network=nil
 print('[LOOT_DEMAND_TEST] PASS native-request')
 return true
end
