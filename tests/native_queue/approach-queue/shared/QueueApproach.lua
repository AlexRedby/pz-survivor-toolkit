-- Preparation alone mutates the fixture. All subsequent authority reads observe stock effects.
local F={}
local P=require 'QueueEnergyPlacement';local JSON=require 'QueueHealthEvents'
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
local function footprint(origin)
 local cell=getCell()
 for a=-2,8 do for b=-1,1 do local sq=cell:getGridSquare(origin.x+a,origin.y+b,origin.z)
  if not sq or not sq:getFloor()or not sq:TreatAsSolidFloor()or sq:getRoom()or sq:isVehicleIntersecting()then return false end
 end end
 return true
end
function F.plan(player,case)
 local config=require 'QueueTestSelection'
 assert(config.disposable==true and not isClient(),'Approach preparation requires disposable authority')
 assert(case=='bush'or case=='manual-grass','unexpected approach layout case')
 local start=P.choose(player);local cell=getCell();local origin
 local function candidate(dx,dy)
  local target=P.target({x=start.x+dx,y=start.y+dy,z=start.z})
  local standing=cell:getGridSquare(target.x,target.y,target.z)
  if footprint(target)and standing:isFree(false)then return target end
 end
 origin=candidate(0,0)
 for radius=1,12 do
  if not origin then for dx=-radius,radius do for dy=-radius,radius do
   if not origin and(math.abs(dx)==radius or math.abs(dy)==radius)then origin=candidate(dx,dy)end
  end end end
 end
 assert(origin,'No loaded solid outdoor approach footprint')
 return{case=case,target=P.target(origin)}
end
-- The owned disposable strip is changed only after the actor's final centered
-- arrival. Preserve native floors and recalculate stock collision/path data.
local function corridor(origin)
 assert(footprint(origin),'Approach footprint changed before preparation')
 local cell=getCell()
 for a=-2,8 do for b=-1,1 do local sq=assert(cell:getGridSquare(origin.x+a,origin.y+b,origin.z));local floor=sq:getFloor()
  for i=sq:getObjects():size()-1,0,-1 do local object=sq:getObjects():get(i)
   if object~=floor then sq:transmitRemoveItemFromSquare(object)end
  end
 end end
 for a=-2,8 do for b=-1,1 do local sq=assert(cell:getGridSquare(origin.x+a,origin.y+b,origin.z))
  sq:RecalcAllWithNeighbours(true)
  assert(sq:getFloor()and sq:TreatAsSolidFloor()and sq:isFree(false),'Prepared native approach floor is blocked')
 end end
end
function F.prepare(player,case,mode,target,proof)
 assert(case=='bush' or case=='manual-grass')
 assert(require('QueueTestSelection').disposable==true and not isClient(),'Approach preparation requires disposable authority')
 local origin=P.target(target)
 assert(type(proof)=='table'and proof.mode==(isServer()and'replica'or'local')and proof.centered==true
  and proof.teleports==(isServer()and 0 or 1)and proof.centers==(isServer()and 0 or 1),'approach centered authority proof missing')
 local observed=P.target(proof.target)
 assert(observed.x==origin.x and observed.y==origin.y and observed.z==origin.z and P.atCentered(player,origin),'approach authority left final centered placement')
 -- Validate both cases before the first scene mutation. Native flags stay untouched.
 local bush=stockSprite('f_bushes_1_0',IsoFlagType.canBeCut)
 local grass=stockSprite('e_newgrass_1_0',IsoFlagType.canBeRemoved)
 local s=case=='bush'and bush or grass
 assert(footprint(origin),'Approach footprint changed before preparation')
 print('[QUEUE_APPROACH] AUTHORITY_PLACEMENT '..JSON.encode({case=case,actor='client1',target=P.target(origin),proof=proof}))
 corridor(origin)
 assert(P.atCentered(player,origin),'approach authority moved during corridor preparation')
 local spec={case=case,mode=mode,origin=origin,placement=P.target(origin),targets={}}
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
 local target=P.target(spec.placement)
 assert(target.x==spec.origin.x and target.y==spec.origin.y and target.z==spec.origin.z,'approach prepared origin differs from placement')
 if not P.atCentered(player,target)then return nil,{case=spec.case,reason='centered placement differs',
  actual={x=player:getX(),y=player:getY(),z=player:getZ()},origin=target}end
 local book=player:getInventory():getItemById(spec.book.id);local tool=player:getInventory():getItemById(spec.tool.id)
 if not book or not tool then return nil,{case=spec.case,reason='items not replicated',book=book~=nil,tool=tool~=nil,bookId=spec.book.id,toolId=spec.tool.id}end
 for name,id in pairs(spec.targets)do local found=false;local actual=objects(square(id))
  for _,o in ipairs(actual)do if o.marker==id.marker and o.sprite==id.sprite and o.index==id.index then found=true end end
  if not found then return nil,{case=spec.case,reason='target not replicated',target=name,expected=id,actual=actual}end
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
 local pages=state.ids.book.pages
 if v.book.pages~=pages or v.book.characterPages~=pages then return nil,v end
 return v
end
return F
