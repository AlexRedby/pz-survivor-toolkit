-- Authority for the final real Project Cook evolved-recipe case.
local Fixture={}
function Fixture.isCase(case)return case=='cook-evolved-return'or case=='cook-water-soup'or case=='cook-water-stew'or case=='cook-water-soup-world'or case=='cook-water-stew-beans'or case=='cook-water-stew-floor-plus'end
local function dishType(case)
 return (case=='cook-water-soup'or case=='cook-water-soup-world')and 'Base.PotOfSoupRecipe'or (case=='cook-water-stew'or case=='cook-water-stew-beans'or case=='cook-water-stew-floor-plus')and 'Base.PotOfStew'or 'Base.Salad'
end
function Fixture.worldItems(spec)
 local square=getCell():getGridSquare(spec.x,spec.y,spec.z)
 local result={};if not square then return result end
 local objects=square:getWorldObjects()
 for i=0,objects:size()-1 do
  local world=objects:get(i);local item=world:getItem()
  if item then result[#result+1]={item=item,world=world,index=i}end
 end
 return result
end
function Fixture.worldCount(spec,id)
 local count=0;for _,entry in ipairs(Fixture.worldItems(spec))do if entry.item:getID()==id then count=count+1 end end
 return count
end
function Fixture.resolveWorldBase(spec)
 local item,world,index
 for _,entry in ipairs(Fixture.worldItems(spec))do
  if entry.item:getID()==spec.id then
   assert(not item,'duplicate original floor Pot ID')
   item,world,index=entry.item,entry.world,entry.index
  end
 end
 if item then
  assert(instanceof(world,'IsoWorldInventoryObject')and world:getItem()==item and item:getWorldItem()==world
   and item:getFullType()=='Base.Pot'and item:getModData().CookWorldOwner==spec.ownerToken,'original floor Pot identity changed')
 end
 return item,world,index
end
function Fixture.resolveBaseSource(spec)
 if not spec then return end
 local square=getCell():getGridSquare(spec.x,spec.y,spec.z)
 if not square or spec.objectIndex<0 or spec.objectIndex>=square:getObjects():size()then return end
 local object=square:getObjects():get(spec.objectIndex)
 if not object or not instanceof(object,'IsoStove')or object:isMicrowave()or object:Activated()
  or object:getSquare()~=square or object:getSprite():getName()~=spec.sprite
  or object:getModData().CookWaterSourceOwner~=spec.ownerToken then return end
 local source=object:getContainerByIndex(spec.containerIndex)
 if not source or source:getParent()~=object or source:getSourceGrid()~=square
  or source:getType()~=spec.containerType or source:getType()~='stove'then return end
 return source,object
end
local function worldBaseSource(player,case)
 local origin=assert(player:getSquare());local square
 for _,offset in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
  local candidate=getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ())
  if candidate and candidate:canStand()and candidate:isFree(false)and not origin:isBlockedTo(candidate)then square=candidate;break end
 end
 assert(square,'no adjacent accessible native stove tile')
 local sprite='appliances_cooking_01_0'
 local nativeSprite=assert(getSprite(sprite),'native stove sprite missing')
 local object=IsoStove.new(getCell(),square,nativeSprite)
 object:createContainersFromSpriteProperties()
 local source=assert(object:getContainerByType('stove'),'native stove sprite has no stove container')
 assert(not object:isMicrowave()and not object:Activated(),'world base fixture requires an inactive native stove')
 source:setExplored(true)
 local token=case..':'..player:getUsername()..':'..tostring(getTimestampMs())
 object:getModData().CookWaterSourceOwner=token;square:AddTileObject(object)
 local spec={x=square:getX(),y=square:getY(),z=square:getZ(),objectIndex=object:getObjectIndex(),
  containerIndex=object:getContainerIndex(source),sprite=sprite,containerType=source:getType(),ownerToken=token}
 assert(Fixture.resolveBaseSource(spec)==source,'native stove identity was not established')
 return source,object,spec
end
local function items(container,out)
 out=out or {}
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i);out[#out+1]=item
  if instanceof(item,'InventoryContainer')then items(item:getItemContainer(),out)end
 end
 return out
end
local function count(root,id)
 local n=0;for _,item in ipairs(items(root))do if item:getID()==id then n=n+1 end end;return n
end
local function strings(list)
 local result={};if list then for i=0,list:size()-1 do result[#result+1]=list:get(i)end end
 table.sort(result);return result
end
local function meta(item,food)
 local value={id=item:getID(),kind=item:getFullType()}
 if food then value.hunger=item:getHungChange()end
 return value
end
function Fixture.resolveIngredient(root,metadata)
 local source=metadata.source and Fixture.resolveBaseSource(metadata.source)
 if metadata.source and not source then return end
 local item=root:getItemById(metadata.id)or source and source:getItemById(metadata.id)
 if not item or item:getFullType()~=metadata.kind
  or count(root,metadata.id)+(source and count(source,metadata.id)or 0)~=1 then return nil,source end
 return item,source
end
function Fixture.prepare(player,case)
 local root=player:getInventory()
 local state={player=player,case=case,root=root,bags={},baselineDishIds={},cookingLevel=player:getPerkLevel(Perks.Cooking)}
 if case=='cook-water-stew-floor-plus'then
  state.inputDispatch='plus-cook'
  state.floorBase=case=='cook-water-stew-floor-plus'
 end
 for _,item in ipairs(items(root))do
  if item:getFullType()==dishType(case)then state.baselineDishIds[#state.baselineDishIds+1]=item:getID()end
 end
 table.sort(state.baselineDishIds)
 local sources={}
 for i=1,2 do local bag=assert(root:AddItem('Base.Bag_Schoolbag'));sources[i]=bag;state.bags[i]=bag:getID()end
 local water=case~='cook-evolved-return'
 local baseSource,baseObject,baseSpec
 if case=='cook-water-soup-world'or case=='cook-water-stew-beans'or state.inputDispatch and not state.floorBase then baseSource,baseObject,baseSpec=worldBaseSource(player,case)end
 local base
 if state.floorBase then base=assert(instanceItem('Base.Pot'))
 else base=assert((baseSource or water and root or sources[1]:getItemContainer()):AddItem(water and 'Base.Pot'or 'Base.Bowl'))end
 state.base=meta(base)
 if baseSpec then state.base.source=baseSpec;state.baseSource=baseSource;state.baseObject=baseObject end
 if water then
  assert(not instanceof(base,'Food'),'water fixture must start with a non-Food pot')
  local fluid=assert(base:getFluidContainer(),'native pot has no fluid container')
  local capacity=fluid:getCapacity();assert(capacity>0,'native pot capacity must be positive')
  fluid:Empty();fluid:addFluid(Fluid.Water,capacity)
  state.base.fluidCapacity=capacity;state.base.waterAmount=fluid:getAmount()
  assert(fluid:isPureFluid(Fluid.Water)and math.abs(state.base.waterAmount-capacity)<0.00001,
   'water fixture must fill the native pot capacity')
 end
 if state.floorBase then
  local square=assert(player:getSquare());local token=case..':'..player:getUsername()..':'..tostring(getTimestampMs())
  base:getModData().CookWorldOwner=token
  state.baselineWorldDishIds={}
  local location={x=square:getX(),y=square:getY(),z=square:getZ()}
  for _,entry in ipairs(Fixture.worldItems(location))do
   if entry.item:getFullType()==dishType(case)then state.baselineWorldDishIds[#state.baselineWorldDishIds+1]=entry.item:getID()end
  end
  square:AddWorldInventoryItem(base,0.5,0.5,0,true)
  local world=assert(base:getWorldItem(),'real native floor Pot object missing')
  state.base.world={x=location.x,y=location.y,z=location.z,id=base:getID(),
   worldObjectIndex=square:getWorldObjects():indexOf(world),ownerToken=token}
  assert(Fixture.resolveWorldBase(state.base.world)==base,'real floor Pot identity was not established')
 end
 local beans=case=='cook-water-stew-beans'or state.inputDispatch
 local ingredient=assert((beans and baseSource or sources[2]:getItemContainer()):AddItem(beans and 'Base.DriedWhiteBeans'or 'Base.Tomato'))
 state.ingredient=meta(ingredient,true)
 if beans then
  state.ingredient.source=baseSpec;state.ingredient.recipeUse=10
  assert(ingredient:getContainer()==(state.floorBase and sources[2]:getItemContainer()or baseSource)and math.abs(state.ingredient.hunger+0.60)<0.00001
   and math.abs(ingredient:getActualWeight()-2)<0.00001 and not ingredient:isCooked()and not ingredient:isFrozen()
   and not ingredient:isRotten(),'ordinary untouched dry beans fixture differs')
 end
 local spice=assert(sources[2]:getItemContainer():AddItem('Base.Pepper'))
 -- A nearly depleted physical fixture exercises the mod's native post-use cleanup;
 -- all recipe application, nutrition changes and removal remain production code.
 if not water then spice:setHungChange(-0.005)end
 state.spice=meta(spice,true)
 local book=assert(root:AddItem('Base.BookCarpentry1'));state.book=book:getID()
 book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 if isServer()then
  for _,bag in ipairs(sources)do sendAddItemToContainer(root,bag)end
  if baseObject then baseObject:transmitCompleteItemToClients();baseObject:transmitModData()
  elseif water and not state.floorBase then sendAddItemToContainer(root,base)end
  sendAddItemToContainer(root,book)
 end
 return state
end
function Fixture.descriptor(state)
 return {case=state.case,bags=state.bags,book=state.book,base=state.base,ingredient=state.ingredient,
  spice=state.spice,baselineDishIds=state.baselineDishIds,cookingLevel=state.cookingLevel,
  inputDispatch=state.inputDispatch,baselineWorldDishIds=state.baselineWorldDishIds}
end
function Fixture.resolve(player,ids)
 local root=player:getInventory();local containers=ArrayList.new();containers:add(root)
 local function waiting(reason)
  if ids.base.world and Fixture.resolveWaitReason~=reason then
   Fixture.resolveWaitReason=reason
   local spec=ids.base.world;local worlds={}
   for _,entry in ipairs(Fixture.worldItems(spec))do worlds[#worlds+1]=entry.item:getFullType()..':'..entry.item:getID()end
   print('[CRAFT_UI_TEST] FLOOR_WAIT reason='..reason..' rootCount='..count(root,ids.base.id)
    ..' worldCount='..Fixture.worldCount(spec,ids.base.id)..' worldItems='..table.concat(worlds,',')
    ..' player='..player:getX()..','..player:getY()..','..player:getZ()..' tile='..spec.x..','..spec.y..','..spec.z)
  end
 end
 local baseSource,baseObject
 local floorBase
 if ids.base.world then
  floorBase=Fixture.resolveWorldBase(ids.base.world)
  if not floorBase then return waiting('world-id-not-replicated')end
  if count(root,ids.base.id)+Fixture.worldCount(ids.base.world,ids.base.id)~=1 then return waiting('original-conservation')end
  -- Use the game's ordinary loot refresh to associate the received world item
  -- with its native floor cache. No fixture-created ItemContainer is inserted.
  assert(getPlayerLoot(player:getPlayerNum()),'native loot UI missing'):refreshBackpacks()
  baseSource=floorBase:getContainer()
  if not baseSource then return waiting('container-missing-after-native-refresh')end
 end
 if ids.base.source then
  baseSource,baseObject=Fixture.resolveBaseSource(ids.base.source)
  if not baseSource then return end
  if count(root,ids.base.id)+count(baseSource,ids.base.id)~=1 then return end
 end
 for _,id in ipairs(ids.bags)do
  local bag=root:getItemById(id);if not bag then return end
  containers:add(bag:getItemContainer())
 end
 for _,meta in ipairs({ids.base,ids.ingredient,ids.spice})do
  local item
  if meta==ids.ingredient then item=Fixture.resolveIngredient(root,meta)
  else item=root:getItemById(meta.id)or meta==ids.base and (floorBase or baseSource and baseSource:getItemById(meta.id))end
  if not item or item:getFullType()~=meta.kind then return waiting('item-'..meta.kind..':'..meta.id)end
  if meta.hunger and math.abs(item:getHungChange()-meta.hunger)>0.00001 then return waiting('hunger-'..meta.kind..':'..item:getHungChange())end
  if meta.waterAmount then
   local fluid=item:getFluidContainerFromSelfOrWorldItem()
   if (item:getContainer()~=root and item:getContainer()~=baseSource)or instanceof(item,'Food')or not fluid or not fluid:isPureFluid(Fluid.Water)
    or math.abs(fluid:getCapacity()-meta.fluidCapacity)>0.00001
    or math.abs(fluid:getAmount()-meta.waterAmount)>0.00001 then return waiting('fluid-'..tostring(fluid and fluid:getAmount())..':'..tostring(fluid and fluid:getCapacity())..':'..tostring(fluid and fluid:isPureFluid(Fluid.Water)))end
  end
 end
 local book=root:getItemById(ids.book);if not book then return waiting('book-'..ids.book)end
 return {root=root,containers=containers,book=book,base=root:getItemById(ids.base.id)or floorBase or baseSource and baseSource:getItemById(ids.base.id),
  baseSource=baseSource,baseObject=baseObject}
end
function Fixture.verify(state)
 local root=state.root;local baseline={};local dishIds,dishes={},{}
 local baseSource
 if state.base.source then
  baseSource=Fixture.resolveBaseSource(state.base.source)
  if not baseSource then return nil,'evolved native stove identity changed'end
 end
 local function conserved(id)return count(root,id)+(baseSource and count(baseSource,id)or 0)
  +(state.base.world and Fixture.worldCount(state.base.world,id)or 0)end
 if state.base.world then
  for _,id in ipairs(state.baselineWorldDishIds or {})do
   assert(Fixture.worldCount(state.base.world,id)==1,'unrelated original floor dish changed')
   baseline[id]=true
  end
 end
 for _,id in ipairs(state.baselineDishIds)do
  local item=root:getItemById(id)
  if not item or item:getFullType()~=dishType(state.case)or count(root,id)~=1 then return nil,'evolved baseline dish changed'end
  baseline[id]=true
 end
 local bags={}
 for i,id in ipairs(state.bags)do
  local bag=root:getItemById(id)
  if not bag or not instanceof(bag,'InventoryContainer')or bag:getContainer()~=root or count(root,id)~=1 then return nil,'evolved source bag changed'end
  bags[i]=bag:getItemContainer()
 end
 local all=items(root);if baseSource then items(baseSource,all)end
 if state.base.world then for _,entry in ipairs(Fixture.worldItems(state.base.world))do all[#all+1]=entry.item end end
 for _,item in ipairs(all)do
  if item:getFullType()==dishType(state.case)and not baseline[item:getID()]then dishIds[#dishIds+1]=item:getID()end
 end
 table.sort(dishIds)
 for _,id in ipairs(dishIds)do
  local item=root:getItemById(id)or baseSource and baseSource:getItemById(id)
  if not item and state.base.world then for _,entry in ipairs(Fixture.worldItems(state.base.world))do if entry.item:getID()==id then item=entry.item end end end
  dishes[#dishes+1]={id=id,kind=item:getFullType(),sourceCount=count(bags[1],id),
   rootCount=item:getContainer()==root and 1 or 0,totalCount=conserved(id),
   extras=strings(item:getExtraItems()),spices=strings(item:getSpices())}
  if state.base.world then dishes[#dishes].worldCount=Fixture.worldCount(state.base.world,id)end
 end
 local input,ingredientSource=Fixture.resolveIngredient(root,state.ingredient)
 local ingredient={id=state.ingredient.id,kind=state.ingredient.kind,hunger=input and input:getHungChange()or 0,
  sourceCount=count(ingredientSource or bags[2],state.ingredient.id),rootCount=input and input:getContainer()==root and 1 or 0,
  totalCount=count(root,state.ingredient.id)}
 local book=root:getItemById(state.book)
 if not book or book:getFullType()~='Base.BookCarpentry1'or book:getContainer()~=root or count(root,state.book)~=1 then return nil,'evolved reader changed'end
 local value={case=state.case,bags=state.bags,base={id=state.base.id,totalCount=conserved(state.base.id)},
  ingredient=ingredient,spice={id=state.spice.id,kind=state.spice.kind,totalCount=count(root,state.spice.id)},
  dishes=dishes,outputIds=dishIds,outputs=#dishIds,bookId=state.book,
  tailRead=book:getAlreadyReadPages()==book:getNumberOfPages()}
 -- Host replication can trail client quiescence. Keep observed native deviations in a
 -- terminal receipt after a short settling period instead of inventing successful effects.
 local water=state.case~='cook-evolved-return'
 if water then
  local spice=root:getItemById(state.spice.id)
  value.spice.sourceCount=count(bags[2],state.spice.id)
  value.spice.hunger=spice and spice:getHungChange()or 0
 end
 if baseSource then
  value.base.rootCount=count(root,state.base.id);value.base.sourceCount=count(baseSource,state.base.id)
  value.base.source=state.base.source
  value.base.sourceItemCount=baseSource:getItems():size()
  value.ingredient.totalCount=conserved(state.ingredient.id)
  value.spice.totalCount=conserved(state.spice.id)
 end
 if state.ingredient.source then value.ingredient.source=state.ingredient.source end
 if state.base.world then
  value.base.world=state.base.world;value.base.rootCount=count(root,state.base.id)
  value.base.worldCount=Fixture.worldCount(state.base.world,state.base.id)
 end
 local consumed=water and state.ingredient.hunger+(state.ingredient.recipeUse or 12)/100*(1-0.03*state.cookingLevel)>=-0.0200001
 local settled=#dishes==1 and dishes[1].sourceCount==(water and 0 or 1)
  and (not water or dishes[1].rootCount==1)and ingredient.sourceCount==(consumed and 0 or 1)
  and ingredient.totalCount==(consumed and 0 or 1)
  and value.spice.totalCount==(water and 1 or 0)and value.base.totalCount==0 and value.tailRead
 if (state.case=='cook-water-stew-beans'or state.inputDispatch)and not state.floorBase then settled=settled and value.base.sourceItemCount==1
  and ingredient.rootCount==0 and math.abs(ingredient.hunger-(state.ingredient.hunger+0.10*(1-0.03*state.cookingLevel)))<0.00001 end
 state.verifySince=state.verifySince or getTimestampMs()
 if isServer()and not settled and getTimestampMs()-state.verifySince<3000 then return nil,'evolved effects settling'end
 state.verified=true;state.frozenReceipt=state.frozenReceipt or value
 return value
end
return Fixture
