-- Full native consumption has a separately strict identity/output receipt.
local Full={}
function Full.isCase(case)return type(case)=='string'and case:find('food-full-replacement-',1,true)==1 end
local function panRows(container,rows,root)
 root=root or container
 local list=container:getItems()
 for i=0,list:size()-1 do
  local item=list:get(i)
  if item:getFullType()=='Base.RoastingPan'then
   rows[#rows+1]={id=item:getID(),weight=item:getActualWeight(),normal=instanceof(item,'ComboItem')and getClassSimpleName(item)=='ComboItem',
    fluid=item:getFluidContainer()~=nil,root=item:getContainer()==root}
  end
  if instanceof(item,'InventoryContainer')then panRows(item:getItemContainer(),rows,root)end
 end
 table.sort(rows,function(a,b)return a.id<b.id end)
end
function Full.prepare(player,food,ids)
 local root=player:getInventory();local source=food:getScriptItem();local output=assert(ScriptManager.instance:getItem('Base.RoastingPan'))
 assert(instanceof(food,'Food')and tostring(source:getItemType())=='base:food'and not source:hasComponents()
  and not source:getLuaCreate()and not source:getItemConfig()and not source:getItemConfigKey()
  and food:getBaseHunger()==food:getHungChange()and math.abs(food:getBaseHunger()+.1)<.00001
  and math.abs(food:getActualWeight()-1.3)<.00001 and not food:isCookable()and not food:isCooked()
  and not food:isCustomWeight()and not food:haveExtraItems()and not food:getOnEat()and not food:getOnCooked()
  and food:getReplaceOnUseFullType()=='Base.RoastingPan','full dish source provenance differs')
 assert(tostring(output:getItemType())=='base:normal'and not output:hasComponents()and not output:getLuaCreate()
  and not output:getItemConfig()and not output:getItemConfigKey()and math.abs(output:getActualWeight()-1.3)<.00001,
  'full dish output provenance differs')
 assert(not root:getFirstTagRecurse(ItemTag.FORK)and not root:getFirstTagRecurse(ItemTag.SPOON)
  and not root:getFirstTypeRecurse('Base.Fork')and not root:getFirstTypeRecurse('Base.Spoon'),'full fixture needs no cutlery')
 local tail=assert(root:AddItem('Base.WaterBottle'));tail:getFluidContainer():Empty();tail:getFluidContainer():addFluid(Fluid.Water,1)
 local pan=assert(root:AddItem('Base.RoastingPan'))
 ids.tailId,ids.fixturePanId=tail:getID(),pan:getID()
 if isServer()then sendAddItemToContainer(root,tail);sendAddItemToContainer(root,pan)end
end
function Full.snapshot(player,ids,value,food)
 local root=player:getInventory();local tail=root:getItemById(ids.tailId)
 assert(tail and tail:getFullType()=='Base.WaterBottle'and tail:getContainer()==root,'independent water identity missing')
 local function count(container,id)
  local result=0;local list=container:getItems()
  for i=0,list:size()-1 do local item=list:get(i)
   if item:getID()==id then result=result+1 end
   if instanceof(item,'InventoryContainer')then result=result+count(item:getItemContainer(),id)end
  end
  return result
 end
 value.tailId,value.tailType,value.tailCount=tail:getID(),tail:getFullType(),count(root,ids.tailId)
 value.tailAmount=tail:getFluidContainer():getAmount();value.tailThirstChange=tail:getFluidContainer():getProperties():getThirstChange()
 value.fixturePanId=ids.fixturePanId;value.pans={};panRows(root,value.pans);value.panCount=#value.pans
 value.foodWeight=food and food:getActualWeight()or 0
 value.sourceFood=food and instanceof(food,'Food')and getClassSimpleName(food)=='Food'or false
 value.sourcePlain=food and not food:getScriptItem():hasComponents()and not food:isCookable()and not food:isCooked()
  and not food:isCustomWeight()and not food:haveExtraItems()and not food:getOnEat()and not food:getOnCooked()
  and not food:getScriptItem():getLuaCreate()and not food:getScriptItem():getItemConfig()and not food:getScriptItem():getItemConfigKey()or false
 value.consumptionReplacementType=food and food:getReplaceOnUseFullType()or ids.consumptionReplacementType
end
function Full.cleanup(previous)
 local root=previous.player:getInventory()
 local retained={};for _,pan in ipairs(previous.ids.pans)do retained[pan.id]=true end
 local remove={previous.ids.tailId,previous.ids.fixturePanId}
 for _,pan in ipairs(previous.receipt.pans)do if not retained[pan.id]then remove[#remove+1]=pan.id end end
 for _,id in ipairs(remove)do
  local item=assert(root:getItemById(id),'previous full output/tail missing')
  assert(item:getContainer()==root and not previous.player:isEquipped(item),'previous full output/tail moved')
  root:Remove(item);if isServer()then sendRemoveItemFromContainer(root,item)end
 end
end
function Full.verify(state,value)
 local ids=state.ids;local cancelled=state.case=='food-full-replacement-cancel-pending'and require('QueueTestSelection').mode=='toolkit'
 local deleted=not cancelled
 if value.deleted~=deleted or value.foodCount~=(deleted and 0 or 1)or value.foodTypeCount~=ids.foodTypeCount-(deleted and 1 or 0)
  or value.bagCount~=1 or value.anchorCount~=1 or value.panCount~=ids.panCount+(deleted and 1 or 0)
  or value.tailAmount<.49 or value.tailAmount>.5001 then return nil,'full replacement identity/count differs'end
 local present={};for _,row in ipairs(value.pans)do
  if not row.normal or row.fluid or not row.root or math.abs(row.weight-1.3)>.00001 then return nil,'full replacement pan differs'end
  present[row.id]=true
 end
 for _,row in ipairs(ids.pans)do if not present[row.id]then return nil,'pre-existing pan disappeared'end end
 if deleted then
  local original=state.originalFood
  local remaining=original:getHungChange()
  if original:getID()~=ids.foodId or original:getFullType()~=ids.foodType or original:getContainer()or original:getWorldItem()
   or original:getCurrentUses()~=0 or not(remaining==0 or remaining~=remaining)then
   return nil,'exact full original not detached/deleted'end
 elseif value.remaining~=ids.remaining or value.foodWeight~=ids.foodWeight then return nil,'cancelled full changed source'end
 local hunger=ids.hunger+(deleted and ids.baseHunger or 0)
 local thirst=ids.thirst+(ids.anchorAmount-value.anchorAmount)*ids.anchorThirstChange/ids.anchorAmount
  +(ids.tailAmount-value.tailAmount)*ids.tailThirstChange/ids.tailAmount
 if math.abs(value.hunger-hunger)>.01 or math.abs(value.thirst-thirst)>.01 then return nil,'full food/water effect differs'end
 state.verified=true;state.receipt=value;return value
end
return Full
