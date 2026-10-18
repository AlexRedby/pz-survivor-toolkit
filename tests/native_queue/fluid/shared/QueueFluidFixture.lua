local Fixture={}
local function count(container,id)
 local result=0;local items=container:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  if item:getID()==id then result=result+1 end
  if instanceof(item,'InventoryContainer')then result=result+count(item:getItemContainer(),id)end
 end
 return result
end
function Fixture.prepare(player,case,previous)
 local root=player:getInventory()
 if previous then
  assert(previous.player==player and previous.verified,'previous fluid state unverified')
  local ids=previous.ids
  local bag,bottle,book=root:getItemById(ids.bagId),root:getItemById(ids.bottleId),root:getItemById(ids.bookId)
  assert(bag and bottle and book and bag:getContainer()==root and book:getContainer()==root
   and bag:getFullType()=='Base.Bag_Schoolbag'and bottle:getFullType()=='Base.WaterBottle'
   and book:getFullType()=='Base.BookCarpentry1'and not player:isEquipped(bag)
   and not player:isEquipped(bottle)and not player:isEquipped(book),'previous fluid item changed or equipped')
  local inside=bottle:getContainer()==bag:getItemContainer()
  assert((inside or bottle:getContainer()==root)and bag:getItemContainer():getItems():size()==(inside and 1 or 0)
   and count(root,ids.bagId)==1 and count(root,ids.bottleId)==1 and count(root,ids.bookId)==1,
   'previous fluid contents or identities changed')
  local targets={book,bag};if not inside then targets[#targets+1]=bottle end
  for _,item in ipairs(targets)do root:Remove(item);if isServer()then sendRemoveItemFromContainer(root,item)end end
 end
 local bag=assert(root:AddItem('Base.Bag_Schoolbag'))
 local source=case:match('^fluid%-bag')and bag:getItemContainer()or root
 local bottle=assert(source:AddItem('Base.WaterBottle'))
 bottle:setFavorite(case:sub(-9)=='-favorite')
 local fluid=assert(bottle:getFluidContainer());fluid:Empty();fluid:addFluid(Fluid.Water,1)
 local book=assert(root:AddItem('Base.BookCarpentry1'))
 book:setAlreadyReadPages(book:getNumberOfPages()-1)
 player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 player:getStats():set(CharacterStat.THIRST,.8)
 if isServer()then
  sendAddItemToContainer(root,bag)
  if source==root then sendAddItemToContainer(root,bottle)end
  sendAddItemToContainer(root,book)
 end
 return {player=player,case=case,bag=bag,bottle=bottle,book=book,
  ids={case=case,bottleId=bottle:getID(),bagId=bag:getID(),bookId=book:getID(),
   amount=fluid:getAmount(),thirst=player:getStats():get(CharacterStat.THIRST),favorite=bottle:isFavorite(),
   source=source==root and 'root'or 'bag'}}
end
function Fixture.resolve(player,ids)
 local root=player:getInventory()
 local bag,bottle,book=root:getItemById(ids.bagId),root:getItemById(ids.bottleId),root:getItemById(ids.bookId)
 if not bag or not bottle or not book then return end
 if bag:getContainer()~=root or book:getContainer()~=root
  or bottle:getContainer()~=(ids.source=='bag'and bag:getItemContainer()or root)then return end
 if math.abs(bottle:getFluidContainer():getAmount()-ids.amount)>0.0001 or bottle:isFavorite()~=ids.favorite then return end
 return {bag=bag,bottle=bottle,book=book}
end
function Fixture.verify(state)
 local player=state.player;local root=player:getInventory();local ids=state.ids
 local bag,bottle,book=root:getItemById(ids.bagId),root:getItemById(ids.bottleId),root:getItemById(ids.bookId)
 if not bag or bag:getContainer()~=root or bag:getFullType()~='Base.Bag_Schoolbag'
  or not bottle or bottle:getFullType()~='Base.WaterBottle'
  or not book or book:getFullType()~='Base.BookCarpentry1'or book:getContainer()~=root
  or count(root,bag:getID())~=1 or count(root,book:getID())~=1 then return nil,'fluid fixture identity differs'end
 local source=bottle:getContainer()==root and 'root'or bottle:getContainer()==bag:getItemContainer()and 'bag'
 if not source then return nil,'fluid bottle moved to an unrelated endpoint'end
 state.verified=true
 return {case=state.case,bottleId=bottle:getID(),bagId=bag:getID(),bookId=book:getID(),
  amount=bottle:getFluidContainer():getAmount(),thirst=player:getStats():get(CharacterStat.THIRST),
  bottleCount=count(root,bottle:getID()),tailRead=book:getAlreadyReadPages()==book:getNumberOfPages(),source=source,
  favorite=bottle:isFavorite()}
end
return Fixture
