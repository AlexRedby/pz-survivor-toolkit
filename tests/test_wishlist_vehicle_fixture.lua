-- Vehicle insertion is deferred; getVehicles() is a Set in B42.21.
local source = ProjectRoot .. '/tests/native_queue/vehicle-wishlist/shared/VehicleWishlistFixture.lua'
next = nil
local server, spawned, transmissions = false, {}, 0
local function list(values)
    return {size=function()return #values end,get=function(_,i)return values[i+1]end}
end
instanceof=function(value, class)return value.class==class end
isServer=function()return server end
IsoDirections={N=1}
local cell={}
function cell:getVehicles()error('Do not index the native Set')end
function cell:getGridSquare(x,y,z)
    return {getX=function()return x end,getY=function()return y end,
        isOutside=function()return math.abs(x)>1 or math.abs(y)>1 end,
        isFree=function(_,allowMoving)assert(allowMoving==false);return true end,
        getMovingObjects=function()return list(x==4 and y==4 and {{class='BaseVehicle'}} or {})end}
end
getCell=function()return cell end
instanceItem=function(fullType)return{type=fullType,setCondition=function(_,value)assert(value==80)end}end
addVehicleDebug=function(name,direction,skin,square)
    assert(square:isOutside())
    for _,old in ipairs(spawned)do
        assert(math.abs(old:getX()-square:getX())>=7 or math.abs(old:getY()-square:getY())>=7,
            'deferred fixture spawns must reserve distinct positions')
    end
    local part={setInventoryItem=function(self,item)self.item=item end}
    local id=#spawned+100
    local class=name=='Base.PickUpVan' and 2 or (name=='Base.CarNormal' and 1 or 3)
    local vehicle={getId=function()return id end,getSquare=function()return square end,
        getX=function()return square:getX()end,getY=function()return square:getY()end,
        getScript=function()return{getMechanicType=function()return class end}end,
        getPartById=function(_,key)assert(key=='TireFrontLeft');return part end,
        transmitPartItem=function(_,value)assert(server and value==part);transmissions=transmissions+1 end}
    spawned[#spawned+1]=vehicle
    return vehicle
end
local player={getX=function()return 0 end,getY=function()return 0 end}
for _,mode in ipairs({false,true})do
    server,spawned,transmissions=mode,{},0
    local F=dofile(source)
    local ids=F.prepare(player)
    assert(#ids==4 and #spawned==4 and #F.vehicles==4)
    assert(not spawned[1]:getPartById('TireFrontLeft').item)
    for i=2,4 do
        local item=spawned[i]:getPartById('TireFrontLeft').item
        assert(item.type=='Base.ModernTire'..spawned[i]:getScript():getMechanicType())
    end
    assert(transmissions==(server and 4 or 0))
end
print('PASS vehicle fixture: exterior placement, deferred reservations, native Set boundary and SP/server part setup')
