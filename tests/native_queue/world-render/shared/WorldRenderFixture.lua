local F={module='WorldRenderTest'}
local JSON=require 'QueueHealthEvents'
function F.emit(event,value) print('[WORLD_RENDER] '..event..' '..JSON.encode(value))end
function F.prepare(player)
 local item=assert(player:getInventory():AddItem('Base.Torch'),'Native Torch unavailable')
 item:setCurrentUses(item:getMaxUses());item:setActivated(false);player:setPrimaryHandItem(item)
 if isServer()then sendAddItemToContainer(player:getInventory(),item);sendEquip(player);syncItemActivated(player,item)end
 return item
end
function F.torch(player,item,active)
 assert(item and item:getContainer()==player:getInventory()and item:getFullType()=='Base.Torch','Owned torch missing')
 item:setActivated(active)
 if isServer()then syncItemActivated(player,item)end
 return item:isActivated()
end
function F.object(packet,kind)
 local square=getCell():getGridSquare(packet.x,packet.y,packet.z)
 if not square or packet.index<0 or packet.index>=square:getObjects():size()then return end
 local obj=square:getObjects():get(packet.index)
 if instanceof(obj,kind)then return obj end
end
function F.descriptor(obj)
 local sq=obj:getSquare();return {x=sq:getX(),y=sq:getY(),z=sq:getZ(),index=obj:getObjectIndex()}
end
function F.free(square)
 return square and square:TreatAsSolidFloor()and square:canStand()and square:isFree(false)
end
-- One discovery pass after load, never a per-frame world scan. Existing map objects stay intact.
function F.discover(player)
 local origin=player:getSquare();local scene={};local nearest={}
 for dx=-24,24 do for dy=-24,24 do
  local sq=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
  if sq then
   local dist=dx*dx+dy*dy
   for i=0,sq:getObjects():size()-1 do
    local obj=sq:getObjects():get(i)
    if instanceof(obj,'IsoLightSwitch')and obj:getBulbItem()and obj:canSwitchLight()
      and (not nearest.switch or dist<nearest.switch)then scene.switch=F.descriptor(obj);nearest.switch=dist end
    if instanceof(obj,'IsoTree')and (not nearest.tree or dist<nearest.tree)then
     for _,v in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
      local beside=getCell():getGridSquare(sq:getX()+v[1],sq:getY()+v[2],sq:getZ())
      if F.free(beside)then scene.tree={x=beside:getX(),y=beside:getY(),z=beside:getZ()};nearest.tree=dist;break end
     end
    end
    if instanceof(obj,'IsoWindow')and (not nearest.window or dist<nearest.window)then
     local other=getCell():getGridSquare(sq:getX()-(obj:isNorth()and 0 or 1),sq:getY()-(obj:isNorth()and 1 or 0),sq:getZ())
     if other and (sq:getRoom()~=nil)~=(other:getRoom()~=nil)then
      local inside=sq:getRoom()and sq or other;local outside=sq:getRoom()and other or sq
      if F.free(inside)and F.free(outside)then
       scene.window={inside={x=inside:getX(),y=inside:getY(),z=inside:getZ()},outside={x=outside:getX(),y=outside:getY(),z=outside:getZ()}}
       nearest.window=dist
      end
     end
    end
   end
  end
 end end
 return scene
end
-- Select a real unblocked cardinal corridor for the native flashlight cone.
function F.corridor(player)
 local origin=player:getSquare();local best
 for _,v in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
  local previous=origin;local length=0
  for step=1,6 do
   local square=getCell():getGridSquare(origin:getX()+v[1]*step,origin:getY()+v[2]*step,origin:getZ())
   if not F.free(square)or previous:isBlockedTo(square)then break end
   length=step;previous=square
  end
  if length>=3 and(not best or length>best.length)then best={dx=v[1],dy=v[2],length=length}end
 end
 return best
end
-- Find existing outdoor pavement once, before the daylight decal scene. No tiles are replaced.
function F.decalScene(player)
 local origin=assert(player:getSquare(),'Decal scene requires a loaded actor square')
 local vehicleClear={}
 local function paving(square)
  if not F.free(square)or not square:isOutside()or square:getRoom()then return end
  local floor=square:getFloor();local sprite=floor and floor:getSprite()
  local name=sprite and sprite:getName()
  -- Native asphalt/road tiles. Do not admit grass, dirt, or arbitrary outdoor floors.
  if name and string.sub(name,1,14)=='blends_street_'then
   -- isFree(false) ignores cars. Include a one-tile margin for their visible body.
   local key=square:getX()..':'..square:getY()
   if vehicleClear[key]==nil then
    local clear=true
    for dx=-1,1 do for dy=-1,1 do
     local nearby=getCell():getGridSquare(square:getX()+dx,square:getY()+dy,square:getZ())
     if nearby and nearby:isVehicleIntersecting()then clear=false end
    end end
    vehicleClear[key]=clear
   end
   if vehicleClear[key]then return name end
  end
 end
 local best,bestFacing,bestDistance
 local directions={{1,0},{0,1},{-1,0},{0,-1}}
 for ox=-24,24 do for oy=-24,24 do
  local distance=ox*ox+oy*oy
  if distance<=24*24 then
   local x,y,z=origin:getX()+ox,origin:getY()+oy,origin:getZ()
   local start=getCell():getGridSquare(x,y,z);local floorName=paving(start)
   if floorName then for rank,v in ipairs(directions)do
    local previous=start;local length=0
    for step=1,6 do
     local dx,dy=ox+v[1]*step,oy+v[2]*step
     if dx*dx+dy*dy>24*24 then break end
     local square=getCell():getGridSquare(x+v[1]*step,y+v[2]*step,z)
     if not paving(square)or previous:isBlockedTo(square)then break end
     length=step;previous=square
    end
    -- Prefer screen-lower directions, then the nearest matching corridor.
    local facing=rank<=2 and 0 or 1
    if length>=4 and(not best or facing<bestFacing or facing==bestFacing and
      (distance<bestDistance or distance==bestDistance and length>best.length))then
     best={x=x,y=y,z=z,dx=v[1],dy=v[2],length=length,floorName=floorName}
     bestFacing,bestDistance=facing,distance
    end
   end end
  end
 end end
 return best
end
function F.delta(newer,older)
 local delta=0
 for _,a in ipairs(newer)do for _,b in ipairs(older)do if a.x==b.x and a.y==b.y and a.z==b.z then
  delta=math.max(delta,a.r-b.r,a.g-b.g,a.b-b.b)
  for i=1,8 do for _,shift in ipairs({1,256,65536})do
   local after=math.floor(a.vertices[i]/shift)%256
   local before=math.floor(b.vertices[i]/shift)%256
   delta=math.max(delta,(after-before)/255)
  end end
 end end end
 return delta
end
-- Ordinary visibility getters may refresh lighting; snapshot colours/corners after them.
-- No direct cacheLightInfo/getChunkDirty/getSquareDirty call or forced lighting update.
function F.probe(player)
 local out={};local origin=player:getSquare();if not origin then return out end
 for dx=-3,3 do for dy=-3,3 do
  local sq=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
  if sq then
   -- Same ordinary getters as before, evaluated before the RGB/corner snapshot.
   local canSee=sq:isCanSee(player:getPlayerNum());local couldSee=sq:isCouldSee(player:getPlayerNum())
   local color=sq:getLightInfo(player:getPlayerNum())
   if color then
    local vertices={};for corner=0,7 do vertices[#vertices+1]=sq:getVertLight(corner,player:getPlayerNum())end
    out[#out+1]={x=sq:getX(),y=sq:getY(),z=sq:getZ(),r=color:getR(),g=color:getG(),b=color:getB(),
     canSee=canSee,couldSee=couldSee,room=sq:getRoom()~=nil,vertices=vertices}
   end
  end
 end end
 return out
end
return F
