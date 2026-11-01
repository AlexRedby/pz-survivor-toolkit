-- Offline allocation boundary: only collisions may retry, and every created
-- object must remain detached until the complete cohort has been accepted.
local Items=dofile(ProjectRoot..'/tests/native_queue/warehouse-walking/shared/WarehouseWalkingItems.lua')
local factory,calls,created
local function forbidden()error('allocator mutated or published an item')end
sendAddItemToContainer=forbidden;sendRemoveItemFromContainer=forbidden
ZombRand=forbidden;ZombRandFloat=forbidden
InventoryItemFactory={CreateItem=forbidden}
local function item(id,fullType,container)
 local value={id=id,fullType=fullType or'Base.Nails',kind='InventoryItem',container=container}
 function value:getID()return self.id end
 function value:getFullType()return self.fullType end
 function value:getContainer()return self.container end
 value.setID=forbidden;value.setContainer=forbidden;value.SynchSpawn=forbidden
 value.dispose=forbidden;value.Remove=forbidden;value.AddItem=forbidden
 created[#created+1]=value
 return value
end
function instanceof(value,kind)return value.kind==kind end
function instanceItem(fullType)
 assert(fullType=='Base.Nails','factory type changed');calls=calls+1
 return factory(calls)
end
local function setup(fn)calls=0;created={};factory=fn end
local function detached()
 for _,value in ipairs(created)do assert(value:getContainer()==nil,'allocator attached a staged/rejected item')end
end
local function rejected(message,fn,...)
 local ok,err=pcall(fn,...);assert(not ok,'invalid allocation accepted')
 assert(tostring(err):find(message,1,true),'unexpected allocation failure: '..tostring(err))
end
-- An original/live ID and an intra-cohort duplicate are both retried before
-- accepting the next exact factory object; reservations span separate calls.
setup(function(n)return item(({41,42,42,43,43,44})[n])end)
local reserved={[41]=true}
local first=Items.stage('Base.Nails',2,reserved)
assert(calls==4 and first[1]==created[2]and first[2]==created[4])
assert(reserved[41]and reserved[42]and reserved[43])
local second=Items.stage('Base.Nails',1,reserved)
assert(calls==6 and second[1]==created[6]and reserved[44]);detached()
-- The same native object returned twice is still a duplicate and gets retried.
local repeated
setup(function(n)if n==1 then repeated=item(50);return repeated elseif n==2 then return repeated end;return item(51)end)
local cohort=Items.stage('Base.Nails',2,{})
assert(calls==3 and cohort[1]==repeated and cohort[2]==created[2]);detached()
-- The bound is per slot, including slot one; later failure does not attach the
-- earlier accepted objects or touch any container/publication API.
setup(function()return item(60)end)
rejected('allocation exhausted at slot 1',Items.stage,'Base.Nails',1,{[60]=true})
assert(calls==32);detached()
setup(function(n)return item(n==32 and 64 or 63)end)
cohort=Items.stage('Base.Nails',1,{[63]=true})
assert(calls==32 and cohort[1]==created[32]and cohort[1]:getID()==64);detached()
setup(function(n)return item(n==1 and 61 or 62)end)
reserved={[62]=true}
rejected('allocation exhausted at slot 2',Items.stage,'Base.Nails',2,reserved)
assert(calls==33 and reserved[61]and reserved[62]);detached()
-- A fresh ownership scope permits IDs released with the previous fixture.
setup(function()return item(70)end)
local old=Items.stage('Base.Nails',1,{})[1]
local fresh=Items.stage('Base.Nails',1,{})[1]
assert(old~=fresh and old:getID()==fresh:getID()and calls==2);detached()
-- Foreign factory results are rejected immediately and never removed, altered
-- or disposed, including attached objects which remain in their foreign home.
for _,case in ipairs({
 {message='returned nil',make=function()return nil end},
 {message='factory exploded',make=function()error('factory exploded')end},
 {message='nonnative inventory item',make=function()local value=item(80);value.kind='IsoObject';return value end},
 {message='wrong item type',make=function()return item(80,'Base.Apple')end},
 {message='not an int32',make=function()return item('80')end},
 {message='not an int32',make=function()return item(80.5)end},
 {message='not an int32',make=function()return item(2147483648)end},
 {message='not an int32',make=function()return item(-2147483649)end},
 {message='not an int32',make=function()return item(0/0)end},
 {message='not an int32',make=function()return item(math.huge)end},
 {message='not an int32',make=function()return item(nil)end},
})do
 setup(case.make);reserved={}
 rejected(case.message,Items.stage,'Base.Nails',1,reserved)
 assert(calls==1 and next(reserved)==nil);detached()
end
local foreign={AddItem=forbidden,Remove=forbidden}
setup(function()return item(81,nil,foreign)end)
reserved={};rejected('attached item',Items.stage,'Base.Nails',1,reserved)
assert(calls==1 and created[1]:getContainer()==foreign and next(reserved)==nil)
-- Malformed second results also preserve the accepted detached prefix.
setup(function(n)if n==1 then return item(82)end;return nil end)
reserved={};rejected('returned nil',Items.stage,'Base.Nails',2,reserved)
assert(calls==2 and reserved[82]);detached()
-- reserve is idempotent and accepts precisely signed int32 endpoints.
reserved={}
for _,id in ipairs({-2147483648,0,2147483647})do
 assert(Items.reserve(reserved,id)==id and reserved[id]);Items.reserve(reserved,id)
end
for _,id in ipairs({'1',1.5,-2147483649,2147483648,math.huge,-math.huge,0/0})do
 rejected('not an int32',Items.reserve,{},id)
end
rejected('not an int32',Items.reserve,{},nil)
rejected('reservations missing',Items.reserve,nil,1)
setup(function()return item(90)end)
for _,count in ipairs({-1,1.5,'1',math.huge,0/0})do rejected('count invalid',Items.stage,'Base.Nails',count,{})end
rejected('type missing',Items.stage,'',1,{})
rejected('reservations missing',Items.stage,'Base.Nails',1,nil)
assert(#Items.stage('Base.Nails',0,{})==0 and calls==0)
local savedFactory=instanceItem;instanceItem=nil
rejected('factory unavailable',Items.stage,'Base.Nails',1,{})
instanceItem=savedFactory
print('PASS warehouse walking detached native item allocation')
