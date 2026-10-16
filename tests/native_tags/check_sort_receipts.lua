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
