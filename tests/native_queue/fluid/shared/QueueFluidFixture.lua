local Fixture={bagType='Base.Bag_ALICEpack_Army'}
function Fixture.scenario(case)
 -- Repeated quarters stay above the native menu threshold despite Host progress overshoot.
 local direct=case=='fluid-empty-direct-independent-tail'or case=='fluid-root-all-independent-tail'
 local empty=not direct and case:find('fluid-empty-',1,true)==1
 local menu=case:find('smart',1,true)and 'smart'or case:find('-sip-',1,true)and 'sip'
  or case:find('-all-',1,true)and 'all'or (case:find('-quarter-',1,true)or case:find('-same-serial-',1,true))and 'quarter'or 'half'
 return {empty=empty,direct=direct,edit=case:find('-edit-',1,true)~=nil,menu=menu,source=(direct or empty or case:match('^fluid%-root'))and 'root'or 'bag',favorite=case:sub(-9)=='-favorite',
  foodTimer=case:find('-full-',1,true)and 4000 or 0,
  thirst=case:find('smart%-low')and .04 or menu=='smart'and .2 or .8,
  targets=case:find('-cancel-',1,true)and {1,2,3}or case:find('-same-',1,true)and {1,1}
   or case:find('-pair-',1,true)and {1,2}or {case:find('-second-',1,true)and 2 or 1},
  cancel=case:find('-cancel-',1,true)~=nil,
  serial=case:find('-serial-',1,true)~=nil}
end
local function count(container,id)
 local result=0;local items=container:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  if item:getID()==id then result=result+1 end
  if instanceof(item,'InventoryContainer')then result=result+count(item:getItemContainer(),id)end
 end
 return result
end
local function snapshot(player,bag,bottle,weight,empty)
 local root=player:getInventory()
 local source=bottle:getContainer()==root and 'root'or bottle:getContainer()==bag:getItemContainer()and 'bag'
 assert(source,'fluid bottle moved to unrelated endpoint')
 local value={id=bottle:getID(),amount=bottle:getFluidContainer():getAmount(),favorite=bottle:isFavorite(),
  source=source,count=count(root,bottle:getID())}
 if weight or empty then value.weight=bottle:getUnequippedWeight()end
 if empty then
  local fluid=bottle:getFluidContainer()
  value.fullType,value.capacity,value.transferRate=bottle:getFullType(),fluid:getCapacity(),fluid:getTransferRate()
  value.cleanWater=fluid:isEmpty()or fluid:isPureFluid(Fluid.Water)
  value.emptyWeight=ScriptManager.instance:getItem('Base.WaterBottle'):getActualWeight()
 end
 return value
end
function Fixture.prepare(player,case,previous)
 -- Host can tick the server actor before its first client option sync; disable before issuing root bottles.
 getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
 assert(not player:getAutoDrink(),'fluid fixture auto-drink still enabled')
 local root=player:getInventory()
 if previous then
  assert(previous.player==player and previous.verified,'previous fluid state unverified')
  local bag=assert(root:getItemById(previous.ids.bagId))
  assert(bag:getFullType()==Fixture.bagType and bag:getContainer()==root and not player:isEquipped(bag)
   and count(root,bag:getID())==1,'previous fluid bag changed or equipped')
  local outside,inside={},0
  for _,ids in ipairs(previous.ids.bottles)do
   local bottle=assert(root:getItemById(ids.id))
   assert(bottle:getFullType()=='Base.WaterBottle'and not player:isEquipped(bottle)
    and bottle:isFavorite()==ids.favorite and count(root,ids.id)==1,'previous fluid bottle changed or equipped')
   local endpoint=snapshot(player,bag,bottle)
   if endpoint.source=='bag'then inside=inside+1 else outside[#outside+1]=bottle end
  end
  assert(bag:getItemContainer():getItems():size()==inside,'previous fluid bag contents changed')
  outside[#outside+1]=bag
  for _,item in ipairs(outside)do root:Remove(item);if isServer()then sendRemoveItemFromContainer(root,item)end end
 end
 local spec=Fixture.scenario(case)
 local bag=assert(root:AddItem(Fixture.bagType))
 local source=spec.source=='bag'and bag:getItemContainer()or root
 local bottles,descriptors={},{}
 for index=1,(spec.empty or spec.cancel)and 3 or 2 do
  local endpoint=spec.edit and index==1 and root or source
  local bottle=assert(endpoint:AddItem('Base.WaterBottle'));bottle:setFavorite(spec.favorite)
  local fluid=assert(bottle:getFluidContainer());fluid:Empty();fluid:addFluid(Fluid.Water,1)
  bottles[index]=bottle
  descriptors[index]={id=bottle:getID(),amount=fluid:getAmount(),favorite=bottle:isFavorite(),source=endpoint==root and 'root'or 'bag',
   thirstChange=fluid:getProperties():getThirstChange()}
  if spec.empty or spec.direct then
   descriptors[index]=snapshot(player,bag,bottle,true,true)
   descriptors[index].thirstChange=fluid:getProperties():getThirstChange()
  elseif spec.edit then descriptors[index].weight=bottle:getUnequippedWeight()end
 end
 player:getStats():set(CharacterStat.THIRST,spec.thirst)
 player:getBodyDamage():setHealthFromFoodTimer(spec.foodTimer);player:getMoodles():Update()
 if isServer()then
  sendAddItemToContainer(root,bag)
  for _,bottle in ipairs(bottles)do if bottle:getContainer()==root then sendAddItemToContainer(root,bottle)end end
 end
 return {player=player,case=case,bag=bag,bottles=bottles,
  ids={case=case,bagId=bag:getID(),bagType=Fixture.bagType,thirst=spec.thirst,foodTimer=spec.foodTimer,
   foodLevel=player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN),bottles=descriptors}}
end
function Fixture.resolve(player,ids)
 local root=player:getInventory();local bag=root:getItemById(ids.bagId)
 if not bag or bag:getContainer()~=root then return end
 local bottles={}
 for index,value in ipairs(ids.bottles)do
  local bottle=root:getItemById(value.id)
  if not bottle or bottle:getContainer()~=(value.source=='bag'and bag:getItemContainer()or root)
   or math.abs(bottle:getFluidContainer():getAmount()-value.amount)>.0001 or bottle:isFavorite()~=value.favorite then return end
  bottles[index]=bottle
 end
 return {bag=bag,bottles=bottles}
end
function Fixture.snapshot(player,ids)
 local root=player:getInventory()
 local bag=root:getItemById(ids.bagId)
 if not bag or bag:getContainer()~=root or bag:getFullType()~=Fixture.bagType or count(root,bag:getID())~=1 then
  return nil,'fluid fixture bag identity differs'
 end
 local bottles={}
 for index,value in ipairs(ids.bottles)do
  local bottle=root:getItemById(value.id)
  if not bottle or bottle:getFullType()~='Base.WaterBottle'then return nil,'fluid fixture bottle identity differs'end
  local spec=Fixture.scenario(ids.case)
  bottles[index]=snapshot(player,bag,bottle,spec.edit,spec.empty or spec.direct)
  if (spec.empty or spec.direct)and (bottles[index].source~='root'or bottles[index].count~=1 or not bottles[index].cleanWater)then
   return nil,'empty fluid fixture endpoint/identity/purity differs'
  end
 end
 return {case=ids.case,bagId=bag:getID(),bagType=bag:getFullType(),bottles=bottles,
  thirst=player:getStats():get(CharacterStat.THIRST),foodLevel=player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)}
end
function Fixture.verify(state)
 local value,reason=Fixture.snapshot(state.player,state.ids)
 if not value then return nil,reason end
 state.verified=true;return value
end
return Fixture
