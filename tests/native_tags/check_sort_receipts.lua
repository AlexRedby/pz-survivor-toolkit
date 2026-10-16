local Fixture=dofile(ProjectRoot..'/tests/native_tags/shared/TagFixture.lua')
local registry,presets,calls=false,false,0
local dest={}
local object={getContainerByIndex=function() return dest end}
local record={obj=object,container=dest}
LootSorter={isRegistrySynced=function() return registry end,arePresetsSynced=function() return presets end,
 gatherBoxes=function() calls=calls+1;return {record},true end}
assert(not Fixture.sortTarget({},object) and calls==0,'gather ran before registry sync')
registry=true
assert(not Fixture.sortTarget({},object) and calls==0,'gather ran before presets sync')
presets=true
assert(Fixture.sortTarget({},object)==record and calls==1,'ready owned target was not returned')
LootSorter.gatherBoxes=function() return {{obj={},container=dest}},true end
assert(not Fixture.sortTarget({},object),'another player target satisfied owned-box readiness')
local function container(ids)
 local items={}
 for _,id in ipairs(ids) do items[#items+1]={getID=function() return id end} end
 return {getItems=function() return {size=function() return #items end,get=function(_,index) return items[index+1] end} end}
end
instanceof=function() return false end
local ids={battery=1,apple=2,beans=3,steak=4}
assert(Fixture.receipt(container({1,2,3,4}),container({}),ids,'disabled')=='pending','pre-transfer state was treated as failure/success')
assert(Fixture.receipt(container({2,3,4}),container({}),ids,'disabled')=='pending','in-flight missing item was treated as completed')
assert(Fixture.receipt(container({2,3,4}),container({1}),ids,'disabled')=='ready','disabled exact receipt rejected')
assert(Fixture.receipt(container({3,4}),container({1,2}),ids,'enabled')=='ready','enabled exact receipt rejected')
assert(Fixture.receipt(container({3,4}),container({1,2}),ids,'disabled')=='invalid','nonmatching moved item was treated as transient')
assert(Fixture.receipt(container({1,2,3,4}),container({1}),ids,'disabled')=='invalid','duplicate item was treated as transient')
print('Native tag sort/receipt fixture checks passed: synchronization barrier, exact target, pending replication, ready states, duplicate/nonmatching rejection.')
local planting={sunflower=11,candy=12,carrot=13,fullPacket=14,emptyPacket=15,potato=16,lemongrass=17,hemp=18}
assert(Fixture.plantingReceipt(container({11,12,13,14,15,16,17,18}),container({}),planting,'setup')=='ready')
assert(Fixture.plantingReceipt(container({12,15,18}),container({11,13,14,16,17}),planting,'seed')=='ready')
assert(Fixture.plantingReceipt(container({11,12,13,14,15,16,17,18}),container({}),planting,'reset')=='ready')
for _,phase in ipairs({'exclude','restored'}) do
 assert(Fixture.plantingReceipt(container({11,13,14,15,16,17,18}),container({12}),planting,phase)=='ready')
end
assert(Fixture.plantingReceipt(container({12,15,18}),container({13,14,16,17}),planting,'seed')=='pending','missing in-flight seed was completed')
for _,wrong in ipairs({12,15,18}) do
 local destination={11,13,14,16,17,wrong}
 assert(Fixture.plantingReceipt(container({12,15,18}),container(destination),planting,'seed')=='invalid','negative planting control moved')
end
assert(Fixture.plantingReceipt(container({11,12,13,14,15,16,17,18}),container({11}),planting,'seed')=='invalid','duplicate planting seed accepted')
assert(not pcall(Fixture.plantingReceipt,container({}),container({}),planting,'unknown'),'unknown planting phase accepted')
local duplicate={};for key,id in pairs(planting) do duplicate[key]=id end;duplicate.candy=duplicate.sunflower
assert(not pcall(Fixture.plantingReceipt,container({}),container({}),duplicate,'setup'),'reused planting setup ID accepted')
assert(Fixture.sameRule({mode='all',include={'seed'},exclude={}},Fixture.plantingRule('seed')))
assert(not Fixture.sameRule({mode='all',include={'food'},exclude={}},Fixture.plantingRule('exclude')))
print('Native planting receipt checks passed: eight exact IDs, five seed inputs, candy/empty/hemp negatives, pickup reset and exclusion.')
-- Exercise the server setup body with inventory doubles; the native run uses its real AddItem/network calls.
local reader=assert(io.open(ProjectRoot..'/tests/native_tags/server/ZZTagBaseline.lua','r'))
local serverSource=reader:read('*a');reader:close()
local begin=assert(serverSource:find('local function plantingSetup(state)',1,true))
local finish=assert(serverSource:find('local function verifyPlanting(state,phase)',begin,true))
local sourceItems={{getID=function() return 3 end},{getID=function() return 4 end}}
local created,transmitted,logged,replies=0,0,0,0
local sourceContainer={getItems=function()
 return {size=function() return #sourceItems end,get=function(_,index) return sourceItems[index+1] end}
end}
function sourceContainer:AddItem(fullType)
 created=created+1;local id,md=100+created,{}
 local item={getID=function() return id end,getFullType=function() return fullType end,getModData=function() return md end}
 sourceItems[#sourceItems+1]=item;return item
end
local state={owner='client1',player={},source=sourceContainer,battery=1,apple=2,beans=3,steak=4,baseSorted=true,
 box={getContainerByIndex=function() return container({1,2}) end}}
local states={client1=state,client2={baseSorted=false}}
local env=setmetatable({Fixture=Fixture,config={plantingTags=true},states=states,
 json={encode=function(value)
  logged=logged+1;assert(value.actor=='client1')
  local count=0;for _,entry in pairs(value.items) do assert(entry.id>100 and entry.fullType:sub(1,5)=='Base.');count=count+1 end
  assert(count==8);return '{}'
 end},print=function() end,
 sendAddItemToContainer=function(actual,item) assert(actual==sourceContainer and item:getModData().PZSTTagFixtureOwner=='client1');transmitted=transmitted+1 end,
 sendServerCommand=function(_,module,command,args)
  assert(module=='TagBaseline' and command=='PlantingSetup' and args.ids==state.planting);replies=replies+1
 end}, {__index=_G})
local chunk=assert(loadstring(serverSource:sub(begin,finish-1)..'\nreturn plantingSetup'));setfenv(chunk,env)
local setupPlanting=chunk()
setupPlanting(state);assert(created==0 and replies==0,'planting spawned before both base sorts')
states.client2.baseSorted=true;setupPlanting(state)
assert(created==8 and transmitted==8 and logged==1 and replies==1,'server setup did not spawn/log/transmit exact eight once')
local firstIDs=state.planting;setupPlanting(state);state.reconnected=true;setupPlanting(state)
assert(state.planting==firstIDs and created==8 and logged==1 and replies==3,'retry/reconnect recreated planting IDs')
state.planting=nil
assert(not pcall(setupPlanting,state) and created==8,'server recreated planting setup after reconnect')
print('Native planting server setup checks passed: two-actor base-sort gate, exact server spawns, immutable retries and reconnect guard.')
