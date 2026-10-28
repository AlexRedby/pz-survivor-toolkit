-- Preparation alone mutates the fixture. All subsequent authority reads observe stock effects.
local F={}
local function objects(square)
 local rows={};for i=0,square:getObjects():size()-1 do local o=square:getObjects():get(i)
  local marker=o:getModData().queueApproachIdentity
  if marker then rows[#rows+1]={marker=marker,index=i,sprite=o:getSprite():getName()}end
 end;return rows
end
local function items(container)
 local rows={};for i=0,container:getItems():size()-1 do local item=container:getItems():get(i)
  rows[#rows+1]={id=item:getID(),type=item:getFullType()}
 end;table.sort(rows,function(a,b)return a.id<b.id end);return rows
end
-- Exact installed erosion tiles, not guessed prefix candidates. Their flags are
-- declared by tiledefinitions_erosion.tiles.txt and independently checked at stage.
local function stockSprite(name,flag)
 local value=assert(getSprite(name),'Missing stock vegetation sprite '..name)
 assert(value:getName()==name and value:getProperties():has(flag),'Stock vegetation flag missing '..name..' '..tostring(flag))
 return value
end
local function square(id)return assert(getCell():getGridSquare(id.x,id.y,id.z))end
local function identity(sq,marker,sprite)return{x=sq:getX(),y=sq:getY(),z=sq:getZ(),marker=marker,sprite=sprite:getName(),index=sq:getObjects():size()-1}end
-- The disposable test scene owns this bounded strip before baseline. Preserve
-- native ground floors, clear decorative/collision objects and let native square
-- recalculation build the normal pathfinding/collision data for both routes.
-- teleportTo(float,float,int) floors X/Y in this build. Setup therefore uses
-- the same native floating-position setters as the existing cart fixtures.
local function center(player,origin)
 assert(not player:hasTimedActions(),'Cannot center during native timed actions')
 local x,y,z=origin.x+.5,origin.y+.5,origin.z
 player:setX(x);player:setY(y);player:setZ(z);player:setNextX(x);player:setNextY(y);player:setLastX(x);player:setLastY(y)
 player:ensureOnTile();player:setCurrentSquareFromPosition();player:setMovingSquareNow()
 assert(math.abs(player:getX()-x)<.01 and math.abs(player:getY()-y)<.01 and player:getZ()==z,'Native pre-baseline centering failed')
end
local function corridor(player)
 local config=require 'QueueTestSelection'
 assert(config.disposable==true and not isClient(),'Approach preparation requires disposable authority')
 local start=require('QueueEnergyPlacement')(player);local cell=getCell();local origin
 local function candidate(dx,dy)
  local x,y,z=start:getX()+dx,start:getY()+dy,start:getZ()
  for a=-2,8 do for b=-1,1 do local sq=cell:getGridSquare(x+a,y+b,z)
   if not sq or not sq:getFloor()or not sq:TreatAsSolidFloor()or sq:getRoom()or sq:isVehicleIntersecting()then return end
  end end
  return{x=x,y=y,z=z}
 end
 origin=candidate(0,0)
 for radius=1,12 do
  if not origin then for dx=-radius,radius do for dy=-radius,radius do
   if not origin and(math.abs(dx)==radius or math.abs(dy)==radius)then origin=candidate(dx,dy)end
  end end end
 end
 assert(origin,'No loaded solid outdoor approach footprint')
 -- Preflight above finishes before the first scene edit. These are preparation
 -- writes only; all gameplay effects and reads after baseline remain stock.
 for a=-2,8 do for b=-1,1 do local sq=assert(cell:getGridSquare(origin.x+a,origin.y+b,origin.z));local floor=sq:getFloor()
  for i=sq:getObjects():size()-1,0,-1 do local object=sq:getObjects():get(i)
   if object~=floor then sq:transmitRemoveItemFromSquare(object)end
  end
 end end
 for a=-2,8 do for b=-1,1 do local sq=assert(cell:getGridSquare(origin.x+a,origin.y+b,origin.z))
  sq:RecalcAllWithNeighbours(true)
  assert(sq:getFloor()and sq:TreatAsSolidFloor()and sq:isFree(false),'Prepared native approach floor is blocked')
 end end
 center(player,origin)
 return origin
end
function F.prepare(player,case,mode)
 assert(case=='bush' or case=='manual-grass')
 -- Validate both cases before the first scene mutation. Native flags stay untouched.
 local bush=stockSprite('f_bushes_1_0',IsoFlagType.canBeCut)
 local grass=stockSprite('e_newgrass_1_0',IsoFlagType.canBeRemoved)
 local s=case=='bush'and bush or grass
 local origin=corridor(player)
 local spec={case=case,mode=mode,origin=origin,targets={}}
 for i,name in ipairs({'first','second'})do
  local sq=assert(getCell():getGridSquare(origin.x+(i==1 and 7 or -1),origin.y,origin.z))
  local object=IsoObject.new(getCell(),sq,s:getName());object:getModData().queueApproachIdentity=case..'-'..name
  sq:AddTileObject(object);spec.targets[name]=identity(sq,case..'-'..name,s)
  if isServer()then object:transmitCompleteItemToClients()end
 end
 local tool=assert(player:getInventory():AddItem('Base.HuntingKnife'));player:setPrimaryHandItem(tool)
 local book=assert(player:getInventory():AddItem('Base.BookCarpentry1'));local pages=book:getNumberOfPages()
 book:setAlreadyReadPages(pages-1);player:setAlreadyReadPages(book:getFullType(),pages-1)
 spec.tool={id=tool:getID(),type=tool:getFullType()};spec.book={id=book:getID(),type=book:getFullType(),pages=pages,initial=pages-1}
 if isServer()then sendAddItemToContainer(player:getInventory(),tool);sendAddItemToContainer(player:getInventory(),book)end
 return{player=player,ids=spec,order={},effects={},book=book,tool=tool}
end
function F.resolve(player,spec)
 local book=player:getInventory():getItemById(spec.book.id);local tool=player:getInventory():getItemById(spec.tool.id)
 if not book or not tool then return nil,{case=spec.case,reason='items not replicated',book=book~=nil,tool=tool~=nil,bookId=spec.book.id,toolId=spec.tool.id}end
 for name,id in pairs(spec.targets)do local found=false;local actual=objects(square(id))
  for _,o in ipairs(actual)do if o.marker==id.marker and o.sprite==id.sprite and o.index==id.index then found=true end end
  if not found then return nil,{case=spec.case,reason='target not replicated',target=name,expected=id,actual=actual}end
 end
 local p=spec.origin
 if math.abs(player:getX()-p.x-.5)>.1 or math.abs(player:getY()-p.y-.5)>.1 or player:getZ()~=p.z then
  local before={x=player:getX(),y=player:getY(),z=player:getZ()};center(player,p)
  return nil,{case=spec.case,reason='centered pre-baseline position',before=before,actual={x=player:getX(),y=player:getY(),z=player:getZ()},origin=p}
 end
 player:setPrimaryHandItem(tool);book:setAlreadyReadPages(spec.book.initial);player:setAlreadyReadPages(spec.book.type,spec.book.initial)
 return{player=player,ids=spec,order={},effects={},book=book,tool=tool}
end
function F.snapshot(state)
 local p,spec=state.player,state.ids;local changed={};local result={case=spec.case,targets={},root=items(p:getInventory()),order={},
  book={id=state.book:getID(),type=state.book:getFullType(),pages=state.book:getAlreadyReadPages(),characterPages=p:getAlreadyReadPages(spec.book.type),root=state.book:getContainer()==p:getInventory()},ground={}}
 for _,name in ipairs({'first','second'})do
  local id=spec.targets[name];local sq=square(id);local matched={};for _,o in ipairs(objects(sq))do if o.marker==id.marker then matched[#matched+1]=o end end
  result.targets[name]={identity=id,objects=matched}
  local ground={};for i=0,sq:getWorldObjects():size()-1 do local object=sq:getWorldObjects():get(i);local item=object:getItem();ground[#ground+1]={id=item:getID(),type=item:getFullType()}end
  table.sort(ground,function(a,b)return a.id<b.id end);result.ground[name]=ground
  if #matched==0 and not state[name..'Gone']then state[name..'Gone']=true;state.order[#state.order+1]=name;changed[#changed+1]=name end
 end
 for _,name in ipairs(changed)do state.effects[#state.effects+1]={name=name,root=result.root,ground=result.ground}end
 result.effects={};for _,effect in ipairs(state.effects)do result.effects[#result.effects+1]=effect end
 for _,name in ipairs(state.order)do result.order[#result.order+1]=name end
 return result
end
function F.baseline(state)
 local value=F.snapshot(state)
 if #value.targets.first.objects~=1 or #value.targets.second.objects~=1 then return end
 if value.book.pages~=state.ids.book.initial or value.book.characterPages~=state.ids.book.initial then return end
 state.baseline=value;return value
end
function F.verify(state)
 local v=F.snapshot(state);local enabled=state.ids.mode=='toolkit'
 if #v.targets.first.objects~=(enabled and 0 or 1)or #v.targets.second.objects~=0 then return nil,v end
 local nativeHost=state.ids.mode=='native'and require('QueueTestSelection').kind=='mp'
 local pages=nativeHost and state.ids.book.initial or state.ids.book.pages
 if v.book.pages~=pages or v.book.characterPages~=pages then return nil,v end
 return v
end
return F
