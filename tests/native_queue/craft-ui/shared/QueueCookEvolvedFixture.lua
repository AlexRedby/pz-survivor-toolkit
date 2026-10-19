-- Authority for the final real Project Cook evolved-recipe case.
local Fixture={}
function Fixture.isCase(case)return case=='cook-evolved-return'end
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
function Fixture.prepare(player,case)
 local root=player:getInventory()
 local state={player=player,case=case,root=root,bags={},baselineDishIds={},cookingLevel=player:getPerkLevel(Perks.Cooking)}
 for _,item in ipairs(items(root))do
  if item:getFullType()=='Base.Salad'then state.baselineDishIds[#state.baselineDishIds+1]=item:getID()end
 end
 table.sort(state.baselineDishIds)
 local sources={}
 for i=1,2 do local bag=assert(root:AddItem('Base.Bag_Schoolbag'));sources[i]=bag;state.bags[i]=bag:getID()end
 state.base=meta(assert(sources[1]:getItemContainer():AddItem('Base.Bowl')))
 state.ingredient=meta(assert(sources[2]:getItemContainer():AddItem('Base.Tomato')),true)
 local spice=assert(sources[2]:getItemContainer():AddItem('Base.Pepper'))
 -- A nearly depleted physical fixture exercises the mod's native post-use cleanup;
 -- all recipe application, nutrition changes and removal remain production code.
 spice:setHungChange(-0.005)
 state.spice=meta(spice,true)
 local book=assert(root:AddItem('Base.BookCarpentry1'));state.book=book:getID()
 book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 if isServer()then for _,bag in ipairs(sources)do sendAddItemToContainer(root,bag)end;sendAddItemToContainer(root,book)end
 return state
end
function Fixture.descriptor(state)
 return {case=state.case,bags=state.bags,book=state.book,base=state.base,ingredient=state.ingredient,
  spice=state.spice,baselineDishIds=state.baselineDishIds,cookingLevel=state.cookingLevel}
end
function Fixture.resolve(player,ids)
 local root=player:getInventory();local containers=ArrayList.new();containers:add(root)
 for _,id in ipairs(ids.bags)do
  local bag=root:getItemById(id);if not bag then return end
  containers:add(bag:getItemContainer())
 end
 for _,meta in ipairs({ids.base,ids.ingredient,ids.spice})do
  local item=root:getItemById(meta.id)
  if not item or item:getFullType()~=meta.kind then return end
  if meta.hunger and math.abs(item:getHungChange()-meta.hunger)>0.00001 then return end
 end
 local book=root:getItemById(ids.book);if not book then return end
 return {root=root,containers=containers,book=book}
end
function Fixture.verify(state)
 local root=state.root;local baseline={};local dishIds,dishes={},{}
 for _,id in ipairs(state.baselineDishIds)do
  local item=root:getItemById(id)
  if not item or item:getFullType()~='Base.Salad'or count(root,id)~=1 then return nil,'evolved baseline dish changed'end
  baseline[id]=true
 end
 local bags={}
 for i,id in ipairs(state.bags)do
  local bag=root:getItemById(id)
  if not bag or not instanceof(bag,'InventoryContainer')or bag:getContainer()~=root or count(root,id)~=1 then return nil,'evolved source bag changed'end
  bags[i]=bag:getItemContainer()
 end
 for _,item in ipairs(items(root))do
  if item:getFullType()=='Base.Salad'and not baseline[item:getID()]then dishIds[#dishIds+1]=item:getID()end
 end
 table.sort(dishIds)
 for _,id in ipairs(dishIds)do
  local item=root:getItemById(id)
  dishes[#dishes+1]={id=id,kind=item:getFullType(),sourceCount=count(bags[1],id),
   rootCount=item:getContainer()==root and 1 or 0,totalCount=count(root,id),
   extras=strings(item:getExtraItems()),spices=strings(item:getSpices())}
 end
 local input=root:getItemById(state.ingredient.id)
 local ingredient={id=state.ingredient.id,kind=state.ingredient.kind,hunger=input and input:getHungChange()or 0,
  sourceCount=count(bags[2],state.ingredient.id),rootCount=input and input:getContainer()==root and 1 or 0,
  totalCount=count(root,state.ingredient.id)}
 local book=root:getItemById(state.book)
 if not book or book:getFullType()~='Base.BookCarpentry1'or book:getContainer()~=root or count(root,state.book)~=1 then return nil,'evolved reader changed'end
 local value={case=state.case,bags=state.bags,base={id=state.base.id,totalCount=count(root,state.base.id)},
  ingredient=ingredient,spice={id=state.spice.id,kind=state.spice.kind,totalCount=count(root,state.spice.id)},
  dishes=dishes,outputIds=dishIds,outputs=#dishIds,bookId=state.book,
  tailRead=book:getAlreadyReadPages()==book:getNumberOfPages()}
 -- Host replication can trail client quiescence. Keep observed native deviations in a
 -- terminal receipt after a short settling period instead of inventing successful effects.
 local settled=#dishes==1 and dishes[1].sourceCount==1 and ingredient.sourceCount==1
  and value.spice.totalCount==0 and value.base.totalCount==0 and value.tailRead
 state.verifySince=state.verifySince or getTimestampMs()
 if isServer()and not settled and getTimestampMs()-state.verifySince<3000 then return nil,'evolved effects settling'end
 state.verified=true
 return value
end
return Fixture
