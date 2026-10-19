local Fixture={bagType='Base.Bag_ALICEpack_Army',sprite='appliances_cooking_01_28'}
function Fixture.spec(case)return {bag=case:sub(1,3)=='bag',one=case:sub(-3)=='one'}end
local function count(container,id)
 local total=0
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i)
  if item:getID()==id then total=total+1 end
  if instanceof(item,'InventoryContainer')then total=total+count(item:getItemContainer(),id)end
 end
 return total
end
function Fixture.prepare(player,case,previous)
 player:setAutoDrink(false)
 local root=player:getInventory()
 if previous then
  assert(previous.verified and not player:isEquipped(previous.bag),'previous inventory grab fixture not settled')
  for _,item in ipairs(previous.bottles)do
   local source=item:getContainer();source:Remove(item)
   if isServer()then sendRemoveItemFromContainer(source,item)end
  end
  root:Remove(previous.bag);if isServer()then sendRemoveItemFromContainer(root,previous.bag)end
  previous.object:getSquare():transmitRemoveItemFromSquare(previous.object)
 end
 local here=player:getSquare();local square
 for _,offset in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
  local candidate=getCell():getGridSquare(here:getX()+offset[1],here:getY()+offset[2],here:getZ())
  if candidate and candidate:canStand()and candidate:isFree(false)then square=candidate;break end
 end
 assert(square,'no adjacent free microwave square')
 -- Same native construction and sprite-container initialization as movable appliances.
 local object=IsoStove.new(getCell(),square,getSprite(Fixture.sprite))
 object:createContainersFromSpriteProperties()
 local source=assert(object:getContainer(),'microwave sprite has no native container')
 assert(instanceof(object,'IsoStove')and object:isMicrowave()and source:getType()=='microwave','fixture is not native microwave')
 source:setExplored(true);object:getModData().InventoryGrabFixture=case;square:AddTileObject(object)
 local bag=assert(root:AddItem(Fixture.bagType));local bottles,descriptors={},{}
 for i=1,2 do
  local item=assert(source:AddItem('Base.WaterBottle'));local fluid=assert(item:getFluidContainer())
  fluid:Empty();fluid:addFluid(Fluid.Water,1);bottles[i]=item
  descriptors[i]={id=item:getID(),amount=fluid:getAmount(),kind=item:getFullType()}
 end
 if isServer()then object:transmitCompleteItemToClients();sendAddItemToContainer(root,bag)end
 local ids={case=case,bagId=bag:getID(),bagType=Fixture.bagType,bottles=descriptors,
  x=square:getX(),y=square:getY(),z=square:getZ(),index=object:getObjectIndex(),sprite=Fixture.sprite,sourceType=source:getType(),nativeMicrowave=true}
 return {player=player,case=case,object=object,bag=bag,bottles=bottles,ids=ids}
end
function Fixture.resolve(player,ids)
 local square=getCell():getGridSquare(ids.x,ids.y,ids.z)
 if not square or ids.index>=square:getObjects():size()then return end
 local object=square:getObjects():get(ids.index)
 if not instanceof(object,'IsoStove')or not object:isMicrowave()or object:getSprite():getName()~=ids.sprite then return end
 local bag=player:getInventory():getItemById(ids.bagId);if not bag then return end
 local bottles={}
 for i,value in ipairs(ids.bottles)do
  local item=object:getContainer():getItemById(value.id)
  if not item or math.abs(item:getFluidContainer():getAmount()-value.amount)>.0001 then return end
  bottles[i]=item
 end
 return {player=player,bag=bag,object=object,bottles=bottles,case=ids.case,ids=ids}
end
function Fixture.receipt(state,target)
 local root=state.player:getInventory();local source=state.object:getContainer()
 local bagItem=assert(root:getItemById(state.ids.bagId),'fixture backpack missing')
 assert(bagItem:getContainer()==root and bagItem:getFullType()==Fixture.bagType and count(root,bagItem:getID())==1,'fixture backpack identity differs')
 local bag=bagItem:getItemContainer()
 local spec=Fixture.spec(state.case);local destination=spec.bag and bag or root
 local rows={}
 for i,descriptor in ipairs(state.ids.bottles)do
  local id=descriptor.id;local sourceCount,rootCount=count(source,id),count(root,id)
  local total=sourceCount+rootCount
  assert(total==1,'bottle identity missing or duplicated '..id)
  local expected=id==target and destination or source
  -- MP replication can replace the Java item instance. Resolve the current exact ID;
  -- a retained source proxy is not evidence of the current container endpoint.
  local item=expected:getItemById(id)
  if not item or item:getContainer()~=expected then
   return nil,'bottle endpoint differs '..id..' source='..sourceCount..' root='..rootCount..' bag='..count(bag,id)
  end
  local original=state.bottles[i]
  if original and original~=item then print('[INVENTORY_GRAB_TEST] REBOUND id='..id)end
  local fluid=assert(item:getFluidContainer())
  assert(item:getFullType()=='Base.WaterBottle'and math.abs(fluid:getAmount()-1)<.0001,'bottle type/volume changed')
  rows[i]={id=id,kind=item:getFullType(),amount=fluid:getAmount(),count=total,endpoint=id==target and (spec.bag and 'bag'or 'root')or 'microwave'}
 end
 assert(source:getItems():size()==1 and bag:getItems():size()==(spec.bag and 1 or 0),'unrelated fixture contents changed')
 assert(state.player:getClothingItem_Back()==bagItem,'military backpack is not worn')
 state.verified=true
 return {case=state.case,targetId=target,bagId=bagItem:getID(),bagType=bagItem:getFullType(),bottles=rows,
  sourceType=source:getType(),nativeMicrowave=instanceof(state.object,'IsoStove')and state.object:isMicrowave()}
end
return Fixture
