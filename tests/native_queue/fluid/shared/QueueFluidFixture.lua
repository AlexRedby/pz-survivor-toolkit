local Fixture={bagType='Base.Bag_ALICEpack_Army'}
function Fixture.scenario(case)
 local menu=case:find('smart',1,true)and 'smart'or case:find('-sip-',1,true)and 'sip'
  or case:find('-all-',1,true)and 'all'or case:find('-quarter-',1,true)and 'quarter'or 'half'
 return {menu=menu,source=case:match('^fluid%-root')and 'root'or 'bag',favorite=case:sub(-9)=='-favorite',
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
local function snapshot(player,bag,bottle)
 local root=player:getInventory()
 local source=bottle:getContainer()==root and 'root'or bottle:getContainer()==bag:getItemContainer()and 'bag'
 assert(source,'fluid bottle moved to unrelated endpoint')
 return {id=bottle:getID(),amount=bottle:getFluidContainer():getAmount(),favorite=bottle:isFavorite(),
  source=source,count=count(root,bottle:getID())}
end
function Fixture.prepare(player,case,previous)
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
 for index=1,spec.cancel and 3 or 2 do
  local bottle=assert(source:AddItem('Base.WaterBottle'));bottle:setFavorite(spec.favorite)
  local fluid=assert(bottle:getFluidContainer());fluid:Empty();fluid:addFluid(Fluid.Water,1)
  bottles[index]=bottle
  descriptors[index]={id=bottle:getID(),amount=fluid:getAmount(),favorite=bottle:isFavorite(),source=spec.source,
   thirstChange=fluid:getProperties():getThirstChange()}
 end
 player:getStats():set(CharacterStat.THIRST,spec.thirst)
 player:getBodyDamage():setHealthFromFoodTimer(spec.foodTimer);player:getMoodles():Update()
 if isServer()then
  sendAddItemToContainer(root,bag)
  if source==root then for _,bottle in ipairs(bottles)do sendAddItemToContainer(root,bottle)end end
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
function Fixture.verify(state)
 local player=state.player;local root=player:getInventory();local ids=state.ids
 local bag=root:getItemById(ids.bagId)
 if not bag or bag:getContainer()~=root or bag:getFullType()~=Fixture.bagType or count(root,bag:getID())~=1 then
  return nil,'fluid fixture bag identity differs'
 end
 local bottles={}
 for index,value in ipairs(ids.bottles)do
  local bottle=root:getItemById(value.id)
  if not bottle or bottle:getFullType()~='Base.WaterBottle'then return nil,'fluid fixture bottle identity differs'end
  bottles[index]=snapshot(player,bag,bottle)
 end
 state.verified=true
 return {case=state.case,bagId=bag:getID(),bagType=bag:getFullType(),bottles=bottles,
  thirst=player:getStats():get(CharacterStat.THIRST),foodLevel=player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)}
end
return Fixture
