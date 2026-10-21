-- Ordinary exact-ID food portions. Native Eat uses original base hunger, not remaining fractions.
local Fixture={bagType='Base.Bag_ALICEpack_Army',foodType='Base.Cereal',anchorType='Base.WaterBottle'}
local function finite(value)return type(value)=='number'and value==value and value~=math.huge and value~=-math.huge end
function Fixture.scenario(case)
 local replacement=case=='food-cooking-replacement-move-portions'or case=='food-cooking-replacement-cancel-first-portion'
 local customWeight=case=='food-custom-weight-move-portions'or case=='food-custom-weight-cancel-first-portion'
 local consumption=customWeight or case=='food-consumption-replacement-move-portions'or case=='food-consumption-replacement-cancel-first-portion'
 return {bag=case=='food-bag-edit-pickup-return',
  cancel=case=='food-root-cancel-first-portion'or case=='food-smart-cancel-first-portion'or case=='food-utensil-cancel-first-portion'
   or case=='food-cooked-cancel-first-portion'or case=='food-raw-cookable-cancel-first-portion'
   or case=='food-cooking-replacement-cancel-first-portion'or case=='food-consumption-replacement-cancel-first-portion'
   or case=='food-custom-weight-cancel-first-portion',
  smart=case=='food-smart-move-portions'or case=='food-smart-cancel-first-portion',
  utensil=case=='food-utensil-move-portions'or case=='food-utensil-cancel-first-portion',
  cooked=case=='food-cooked-move-portions'or case=='food-cooked-cancel-first-portion',
  replacement=replacement,consumption=consumption,customWeight=customWeight,
  cookable=replacement or case=='food-cooked-move-portions'or case=='food-cooked-cancel-first-portion'
   or case=='food-raw-cookable-move-portions'or case=='food-raw-cookable-cancel-first-portion',
  depletion=case=='food-root-depletion'}
end
local function foodType(case)
 local spec=Fixture.scenario(case)
 return spec.consumption and 'Base.CannedPeachesOpen'or spec.replacement and 'Base.BreadSlices'
  or spec.cookable and (spec.cooked and 'Base.ChickenFillet'or 'Base.Cabbage')
  or spec.utensil and 'Base.OatsRaw'or Fixture.foodType
end
local function count(container,id,fullType)
 local n=0;local items=container:getItems()
 for i=0,items:size()-1 do local item=items:get(i)
  if fullType and item:getFullType()==fullType or not fullType and item:getID()==id then n=n+1 end
  if instanceof(item,'InventoryContainer')then n=n+count(item:getItemContainer(),id,fullType)end
 end
 return n
end
function Fixture.items(player,ids,allowDeleted)
 local root=player:getInventory();local bag=root:getItemById(ids.bagId)
 local food=root:getItemById(ids.foodId);local anchor=root:getItemById(ids.anchorId)
 if not bag or bag:getFullType()~=Fixture.bagType or bag:getContainer()~=root
  or not food and not(allowDeleted and Fixture.scenario(ids.case).depletion)
  or food and food:getFullType()~=foodType(ids.case) or not anchor or anchor:getFullType()~=Fixture.anchorType then return end
 local result={bag=bag,food=food,anchor=anchor}
 if Fixture.scenario(ids.case).utensil then
  for _,kind in ipairs({'fork','spoon'})do
   local item=root:getItemById(ids[kind..'Id'])
   if not instanceof(item,'HandWeapon')or item:getFullType()~=(kind=='fork'and 'Base.Fork'or 'Base.Spoon')then return end
   result[kind]=item
  end
 end
 return result
end
function Fixture.snapshot(player,ids)
 local state=Fixture.items(player,ids,true);if not state then return end
 local root=player:getInventory();local food,anchor=state.food,state.anchor
 -- Non-finite values are never accepted for a present food instance.
 if food and(not finite(food:getBaseHunger())or not finite(food:getHungChange()))then return end
 local source=not food and 'deleted'or food:getContainer()==root and 'root'or food:getContainer()==state.bag:getItemContainer()and 'bag'
 if not source or anchor:getContainer()~=root then return end
 local result={case=ids.case,bagId=ids.bagId,bagType=state.bag:getFullType(),foodId=ids.foodId,foodType=food and food:getFullType()or ids.foodType,
  baseHunger=food and food:getBaseHunger()or ids.baseHunger,remaining=food and food:getHungChange()or 0,source=source,
  foodCount=count(root,ids.foodId),foodTypeCount=count(root,nil,foodType(ids.case)),deleted=not food,
  anchorId=ids.anchorId,anchorType=anchor:getFullType(),anchorAmount=anchor:getFluidContainer():getAmount(),anchorCount=count(root,ids.anchorId),anchorThirstChange=anchor:getFluidContainer():getProperties():getThirstChange(),
  hunger=player:getStats():get(CharacterStat.HUNGER),thirst=player:getStats():get(CharacterStat.THIRST),bagCount=count(root,ids.bagId)}
 if Fixture.scenario(ids.case).cookable then
  if not food or not finite(food:getHeat())or not finite(root:getTemperature())then return end
  result.cookable,result.cooked=food:isCookable(),food:isCooked()
  result.burnt,result.rotten,result.fertilized=food:isBurnt(),food:isRotten(),food:isFertilized()
  result.heat,result.inventoryTemperature=food:getHeat(),root:getTemperature()
 end
 if Fixture.scenario(ids.case).replacement then
  local outputs=food:getReplaceOnCooked()
  if not outputs or outputs:size()~=1 or not finite(food:getCookingTime())then return end
  result.replacementType=outputs:get(0)
  result.replacementCount=count(root,nil,result.replacementType)
  result.cookingTime=food:getCookingTime()
 end
 if Fixture.scenario(ids.case).consumption then
  if not food or not finite(food:getActualWeight())or not food:getReplaceOnUseFullType()then return end
  result.consumptionReplacementType=food:getReplaceOnUseFullType()
  result.consumptionReplacementCount=count(root,nil,result.consumptionReplacementType)
  result.foodWeight=food:getActualWeight()
  result.customWeight,result.extraItems=food:isCustomWeight(),food:haveExtraItems()
 end
 for _,kind in ipairs({'fork','spoon'})do
  local item=state[kind]
  if item then
   local source=item:getContainer()==root and 'root'or item:getContainer()==state.bag:getItemContainer()and 'bag'
   if not source then return end
   result[kind..'Id'],result[kind..'Type']=item:getID(),item:getFullType()
   result[kind..'Source'],result[kind..'Condition'],result[kind..'Count']=source,item:getCondition(),count(root,item:getID())
  end
 end
 return result
end
function Fixture.prepare(player,case,previous)
 -- Host player-state packets can overwrite setAutoDrink after preparation.
 -- Disable the isolated process option too, before publishing thirsty actors' water.
 getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
 local root=player:getInventory()
 if previous then
  assert(previous.player==player and previous.verified,'unverified previous food fixture')
  local old=assert(Fixture.items(player,previous.ids,true),'previous fixture identities missing')
  assert(not player:isEquipped(old.bag)and count(root,old.bag:getID())==1,'previous bag equipped/duplicated')
  local cleanup={old.anchor}
  if old.fork then cleanup[#cleanup+1]=old.fork;cleanup[#cleanup+1]=old.spoon end
  if old.food then cleanup[#cleanup+1]=old.food else
   assert(previous.receipt and previous.receipt.deleted and previous.receipt.foodCount==0
    and count(root,previous.ids.foodId)==0,'previous missing food was not verified deleted')
  end
  for _,item in ipairs(cleanup)do
   assert(not player:isEquipped(item)and count(root,item:getID())==1,'previous food fixture changed')
   local source=item:getContainer();source:Remove(item);if isServer()then sendRemoveItemFromContainer(source,item)end
  end
  assert(old.bag:getItemContainer():getItems():isEmpty(),'previous bag has foreign contents')
  root:Remove(old.bag);if isServer()then sendRemoveItemFromContainer(root,old.bag)end
 end
 local spec=Fixture.scenario(case);local bag=assert(root:AddItem(Fixture.bagType))
 local food=assert((spec.bag and bag:getItemContainer()or root):AddItem(foodType(case)))
 assert(instanceof(food,'Food')and food:getBaseHunger()<-.04 and food:getHungChange()==food:getBaseHunger()
  and not food:getOnEat()and (spec.consumption or not food:getReplaceOnUse())
  and (not food:getRequireInHandOrInventory()or food:getRequireInHandOrInventory():isEmpty())
  and not food:hasTag(ItemTag.SMOKABLE),'fixture must be ordinary unreplaced food')
 if spec.cookable then
  -- No cooking callback or special cooked mutation runs during preparation.
  -- Bread keeps its native replacement, which is dormant throughout this cold range.
  -- Native setCooked also establishes the minimum cooking time.
  food:setCooked(spec.cooked);food:setHeat(1)
  assert(food:isCookable()and food:isCooked()==spec.cooked and not food:isBurnt()and not food:isRotten()
   and not food:isFertilized()and not food:getOnCooked()and root:getTemperature()==1,
   'cold carried cookable fixture differs')
 end
 if spec.replacement then
  local outputs=food:getReplaceOnCooked()
  assert(outputs and outputs:size()==1 and outputs:get(0)=='Base.Toast'and food:getCookingTime()==0,
   'native cold bread replacement differs')
 end
 if spec.consumption then
  assert(food:getReplaceOnUseFullType()=='Base.TinCanEmpty'and not food:isCookable()and not food:isCooked()
   and not food:isCustomWeight()and not food:haveExtraItems()and not food:getOnCooked()
   and math.abs(food:getActualWeight()-.8)<.00001,'native partial can replacement differs')
  if spec.customWeight then
   -- Exercise the native per-item weight branch without evolved ingredients.
   -- Set fields before publication; no eating callback or timer is replaced.
   food:setActualWeight(1.1);food:setWeight(1.1);food:setCustomWeight(true)
   assert(math.abs(food:getActualWeight()-1.1)<.00001 and food:isCustomWeight(),
    'custom food weight preparation differs')
  end
 end
 local anchor=assert(root:AddItem(Fixture.anchorType));local fluid=assert(anchor:getFluidContainer())
 fluid:Empty();fluid:addFluid(Fluid.Water,1)
 local fork,spoon
 if spec.utensil then
  -- Fork wins even over a root spoon; a broken fork is skipped by the native
  -- constructor and leaves the bag spoon selected for the cancellation case.
  fork=assert((spec.cancel and root or bag:getItemContainer()):AddItem('Base.Fork'))
  spoon=assert((spec.cancel and bag:getItemContainer()or root):AddItem('Base.Spoon'))
  if spec.cancel then fork:setCondition(0)end
  assert(spoon:getCondition()>0 and (spec.cancel or fork:getCondition()>0),'utensil fixture condition differs')
 end
 -- Native Eat uses this helper for remaining hunger/nutrients. Prepare before
 -- publication without Eat's premature SyncItemFields for an unknown client ID.
 if spec.smart then
  local base=food:getBaseHunger()
  assert(not food:isCustomWeight(),'partial food fixture needs native derived weight')
  food:multiplyFoodValues(.75)
  assert(food:getContainer()==root and food:getBaseHunger()==base and math.abs(food:getHungChange()-base*.75)<.00001,
   'native partial-food preparation failed')
 end
 player:getStats():set(CharacterStat.HUNGER,spec.smart and .2 or .8);player:getStats():set(CharacterStat.THIRST,.8)
 player:getBodyDamage():setHealthFromFoodTimer(0);player:getMoodles():Update()
 if isServer()then
  sendAddItemToContainer(root,bag);if not spec.bag then sendAddItemToContainer(root,food)end;sendAddItemToContainer(root,anchor)
  if spec.utensil then sendAddItemToContainer(root,spec.cancel and fork or spoon)end
 end
 local ids={case=case,bagId=bag:getID(),foodId=food:getID(),anchorId=anchor:getID()}
 if spec.utensil then ids.forkId,ids.spoonId=fork:getID(),spoon:getID()end
 local initial=assert(Fixture.snapshot(player,ids));initial.foodTimer=0;initial.foodLevel=player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)
 assert(root:getItemById(food:getID())==food,'prepared original food reference differs from exact root item')
 return {player=player,case=case,ids=initial,originalFood=food}
end
function Fixture.resolve(player,ids)
 local result=Fixture.items(player,ids);local current=result and Fixture.snapshot(player,ids)
 if not current or current.source~=ids.source or math.abs(current.remaining-ids.remaining)>.00001
  or math.abs(current.anchorAmount-ids.anchorAmount)>.00001 then return end
 return result
end
function Fixture.checkDeletion(state,value)
 local original=state.originalFood;local container=original:getContainer();local world=original:getWorldItem()
 local remaining=original:getHungChange()
 local serializedRemaining=remaining~=remaining and 'NaN'or remaining==math.huge and 'Infinity'or remaining==-math.huge and '-Infinity'or remaining
 local proof={case=state.case,expectedId=state.ids.foodId,expectedType=state.ids.foodType,
  id=original:getID(),foodType=original:getFullType(),remaining=serializedRemaining,uses=original:getCurrentUses(),
  deleted=value.deleted,foodCount=value.foodCount,foodTypeCount=value.foodTypeCount,
  hasContainer=container~=nil,hasWorldItem=world~=nil,
  containerContainsId=container~=nil and container:getItemById(state.ids.foodId)~=nil,
  worldOnSquare=world~=nil and world:getSquare()~=nil}
 -- B42.21 Eat(full) sets hunger0; UseAndSync -> Food.setCurrentUses(0) ->
 -- consumeHunger(0) divides 0/0, leaving NaN before Use removes the exhausted item.
 -- Only an exact absent, detached, zero-use original may have this disposal artifact.
 local disposedHunger=remaining==0 or remaining~=remaining
 local expectedHunger=state.ids.hunger+state.ids.baseHunger
 local reason=not Fixture.scenario(state.case).depletion and 'not-depletion-case'
  or not value.deleted and 'still-present'
  or (value.foodCount~=0 or value.foodTypeCount~=state.ids.foodTypeCount-1)and 'inventory-count'
  or proof.id~=state.ids.foodId and 'original-id'
  or proof.foodType~=state.ids.foodType and 'original-type'
  or proof.hasContainer and 'original-container'
  or proof.hasWorldItem and 'original-world-item'
  or proof.uses~=0 and 'original-uses'
  or not disposedHunger and 'original-hunger'
  or (not finite(value.hunger)or math.abs(value.hunger-expectedHunger)>.01)and 'actor-hunger'
 return reason,proof
end
function Fixture.verify(state)
 local value=Fixture.snapshot(state.player,state.ids)
 if not value then return nil,'food fixture exact identity/endpoint missing'end
 local depletion=Fixture.scenario(state.case).depletion
 if value.foodCount~=(depletion and 0 or 1)or value.bagCount~=1 or value.anchorCount~=1
  or value.foodTypeCount~=state.ids.foodTypeCount-(depletion and 1 or 0)then return nil,'food fixture identity count differs'end
 if Fixture.scenario(state.case).utensil then
  for _,kind in ipairs({'fork','spoon'})do
   for _,suffix in ipairs({'Id','Type','Source','Condition','Count'})do
    local field=kind..suffix
    if value[field]~=state.ids[field]then return nil,'food utensil changed: '..field end
   end
  end
 end
 if Fixture.scenario(state.case).cookable then
  for _,field in ipairs({'cookable','cooked','burnt','rotten','fertilized','inventoryTemperature'})do
   if value[field]~=state.ids[field]then return nil,'cookable food state changed: '..field end
  end
  if value.heat<0 or value.heat>1.6 then return nil,'cookable food left the cold range'end
 end
 if Fixture.scenario(state.case).replacement then
  for _,field in ipairs({'replacementType','replacementCount','cookingTime'})do
   if value[field]~=state.ids[field]then return nil,'cold cooking replacement changed: '..field end
  end
 end
 if Fixture.scenario(state.case).consumption then
  for _,field in ipairs({'consumptionReplacementType','consumptionReplacementCount','customWeight','extraItems'})do
   if value[field]~=state.ids[field]then return nil,'partial consumption replacement changed: '..field end
  end
 end
 if depletion then
  local reason,proof=Fixture.checkDeletion(state,value)
  print('[FOOD_TEST] DELETION_PROOF '..require('QueueHealthEvents').encode(proof))
  if reason then return nil,'food deletion proof differs: '..reason end
 end
 state.verified=true;state.receipt=value;return value
end
return Fixture
