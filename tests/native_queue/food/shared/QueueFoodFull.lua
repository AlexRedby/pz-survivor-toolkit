-- Full native consumption shares strict identity/output receipts across plain and empty-fluid outputs.
local Full={}
local plain={foodType='Base.PanFriedVegetables2',outputType='Base.RoastingPan',hunger=-.1,foodWeight=1.3,outputWeight=1.3,capacity=0}
local fluid={foodType='Base.CannedPeachesOpen',outputType='Base.TinCanEmpty',hunger=-.15,foodWeight=.8,outputWeight=.2,capacity=.3}
function Full.spec(case)
 if type(case)~='string'then return end
 if case:find('food-full-fluid-replacement-',1,true)==1 then return fluid end
 if case:find('food-full-replacement-',1,true)==1 then return plain end
end
function Full.isCase(case)return Full.spec(case)~=nil end
function Full.kind(case)return assert(case:match('replacement%-(.*)$'),'unknown full case')end
local function close(a,b)return type(a)=='number'and math.abs(a-b)<.00001 end
local function scriptState(script,spec)
 local components=script:getComponentScripts();local count=components and components:size()or 0
 local fluids,initial=0,0;local valid=true
 for index=0,count-1 do
  local component=components:get(index)
  if getClassSimpleName(component)=='FluidContainerScript'and component==script:getComponentScriptFor(ComponentType.FluidContainer)then
   fluids=fluids+1;local list=component:getInitialFluids();initial=initial+(list and list:size()or 0)
   valid=valid and close(component:getCapacity(),spec.capacity)
  else valid=false end
 end
 local expected=spec.capacity>0 and 1 or 0
 valid=valid and tostring(script:getItemType())=='base:normal'and not script:getLuaCreate()
  and not script:getItemConfig()and not script:getItemConfigKey()and count==expected and fluids==expected and initial==0
  and script:hasComponents()==(expected==1)and close(script:getActualWeight(),spec.outputWeight)
 return valid,count,fluids,initial
end
local function outputRow(item,root,spec)
 local safe,count,fluids,initial=scriptState(item:getScriptItem(),spec)
 local container=item:getFluidContainer();local owner=container and container:getOwner()
 return {id=item:getID(),type=item:getFullType(),weight=item:getActualWeight(),
  normal=instanceof(item,'ComboItem')and getClassSimpleName(item)=='ComboItem',fluid=container~=nil,root=item:getContainer()==root,
  scriptSafe=safe,componentCount=count,fluidCount=fluids,initialFluidCount=initial,
  fluidOwner=container~=nil and owner==item and item:getFluidContainer()==container,
  fluidOwnerId=owner and owner:getID()or -1,fluidAmount=container and container:getAmount()or 0,
  fluidCapacity=container and container:getCapacity()or 0,fluidEmpty=not container or container:isEmpty()}
end
local function validOutput(row,spec)
 local hasFluid=spec.capacity>0;local expected=hasFluid and 1 or 0
 return row.type==spec.outputType and row.normal==true and row.fluid==hasFluid and row.root==true and row.scriptSafe==true
  and row.componentCount==expected and row.fluidCount==expected and row.initialFluidCount==0
  and row.fluidOwner==hasFluid and row.fluidOwnerId==(hasFluid and row.id or -1)
  and close(row.weight,spec.outputWeight)and row.fluidAmount==0 and close(row.fluidCapacity,spec.capacity)and row.fluidEmpty==true
end
local function outputRows(container,rows,spec,root)
 root=root or container;local list=container:getItems()
 for i=0,list:size()-1 do local item=list:get(i)
  if item:getFullType()==spec.outputType then rows[#rows+1]=outputRow(item,root,spec)end
  if instanceof(item,'InventoryContainer')then outputRows(item:getItemContainer(),rows,spec,root)end
 end
 table.sort(rows,function(a,b)return a.id<b.id end)
end
function Full.prepare(player,food,ids)
 local spec=assert(Full.spec(ids.case));local root=player:getInventory();local source=food:getScriptItem()
 local output=assert(ScriptManager.instance:getItem(spec.outputType))
 assert(instanceof(food,'Food')and tostring(source:getItemType())=='base:food'and not source:hasComponents()
  and not source:getLuaCreate()and not source:getItemConfig()and not source:getItemConfigKey()
  and food:getBaseHunger()==food:getHungChange()and close(food:getBaseHunger(),spec.hunger)
  and close(food:getActualWeight(),spec.foodWeight)and not food:isCookable()and not food:isCooked()
  and not food:isCustomWeight()and not food:haveExtraItems()and not food:getOnEat()and not food:getOnCooked()
  and food:getReplaceOnUseFullType()==spec.outputType,'full source provenance differs')
 assert(scriptState(output,spec),'full output script provenance differs')
 assert(not root:getFirstTagRecurse(ItemTag.FORK)and not root:getFirstTagRecurse(ItemTag.SPOON)
  and not root:getFirstTypeRecurse('Base.Fork')and not root:getFirstTypeRecurse('Base.Spoon'),'full fixture needs no cutlery')
 local tail=assert(root:AddItem('Base.WaterBottle'));tail:getFluidContainer():Empty();tail:getFluidContainer():addFluid(Fluid.Water,1)
 -- Inspect the factory's native default. Never empty or repair the output fixture.
 local item=assert(root:AddItem(spec.outputType));assert(validOutput(outputRow(item,root,spec),spec),'full native default output differs')
 ids.tailId,ids.fixtureOutputId=tail:getID(),item:getID()
 if isServer()then sendAddItemToContainer(root,tail);sendAddItemToContainer(root,item)end
end
function Full.snapshot(player,ids,value,food)
 local spec=assert(Full.spec(ids.case));local root=player:getInventory();local tail=root:getItemById(ids.tailId)
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
 value.fixtureOutputId=ids.fixtureOutputId;value.outputs={};outputRows(root,value.outputs,spec);value.outputCount=#value.outputs
 value.foodWeight=food and food:getActualWeight()or 0
 value.sourceFood=food and instanceof(food,'Food')and getClassSimpleName(food)=='Food'or false
 value.sourcePlain=food and not food:getScriptItem():hasComponents()and not food:isCookable()and not food:isCooked()
  and not food:isCustomWeight()and not food:haveExtraItems()and not food:getOnEat()and not food:getOnCooked()
  and not food:getScriptItem():getLuaCreate()and not food:getScriptItem():getItemConfig()and not food:getScriptItem():getItemConfigKey()or false
 value.consumptionReplacementType=food and food:getReplaceOnUseFullType()or ids.consumptionReplacementType
end
function Full.cleanup(previous)
 local root=previous.player:getInventory()
 local retained={};for _,row in ipairs(previous.ids.outputs)do retained[row.id]=true end
 local remove={previous.ids.tailId,previous.ids.fixtureOutputId}
 for _,row in ipairs(previous.receipt.outputs)do if not retained[row.id]then remove[#remove+1]=row.id end end
 for _,id in ipairs(remove)do
  local item=assert(root:getItemById(id),'previous full output/tail missing')
  assert(item:getContainer()==root and not previous.player:isEquipped(item),'previous full output/tail moved')
  root:Remove(item);if isServer()then sendRemoveItemFromContainer(root,item)end
 end
end
function Full.verify(state,value)
 local ids=state.ids;local spec=assert(Full.spec(state.case))
 local cancelled=Full.kind(state.case)=='cancel-pending'and require('QueueTestSelection').mode=='toolkit'
 local deleted=not cancelled
 if value.deleted~=deleted or value.foodCount~=(deleted and 0 or 1)or value.foodTypeCount~=ids.foodTypeCount-(deleted and 1 or 0)
  or value.bagCount~=1 or value.anchorCount~=1 or value.tailCount~=1 or value.outputCount~=#value.outputs
  or value.outputCount~=ids.outputCount+(deleted and 1 or 0)
  or value.tailAmount<.49 or value.tailAmount>.5001 then return nil,'full replacement identity/count differs'end
 local present={};local new=0;local retained={}
 for _,row in ipairs(ids.outputs)do retained[row.id]=row end
 for _,row in ipairs(value.outputs)do
  if present[row.id]or not validOutput(row,spec)then return nil,'full replacement output differs'end
  present[row.id]=true
  local old=retained[row.id]
  if old then for key,field in pairs(old)do if row[key]~=field then return nil,'pre-existing output changed'end end
  else
   if row.id==ids.foodId or row.id==ids.bagId or row.id==ids.anchorId or row.id==ids.tailId then return nil,'new output overlaps source identity'end
   new=new+1
  end
 end
 for id in pairs(retained)do if not present[id]then return nil,'pre-existing output disappeared'end end
 if new~=(deleted and 1 or 0)then return nil,'full replacement new output count differs'end
 if deleted then
  local original=state.originalFood;local remaining=original:getHungChange()
  if original:getID()~=ids.foodId or original:getFullType()~=ids.foodType or original:getContainer()or original:getWorldItem()
   or original:getCurrentUses()~=0 or not(remaining==0 or remaining~=remaining)then return nil,'exact full original not detached/deleted'end
 else
  local original=state.originalFood
  if value.remaining~=ids.remaining or value.foodWeight~=ids.foodWeight or not value.sourceFood or not value.sourcePlain
   or original:getID()~=ids.foodId or original:getFullType()~=ids.foodType
   or original:getContainer()~=state.player:getInventory()or original:getWorldItem()
   or original:getHungChange()~=ids.remaining or original:getActualWeight()~=ids.foodWeight then
   return nil,'cancelled full changed source'
  end
 end
 local hunger=ids.hunger+(deleted and ids.baseHunger or 0)
 local thirst=ids.thirst+(ids.anchorAmount-value.anchorAmount)*ids.anchorThirstChange/ids.anchorAmount
  +(ids.tailAmount-value.tailAmount)*ids.tailThirstChange/ids.tailAmount
 if math.abs(value.hunger-hunger)>.01 or math.abs(value.thirst-thirst)>.01 then return nil,'full food/water effect differs'end
 state.verified=true;state.receipt=value;return value
end
return Full
