local Fixture=assert(loadfile(ProjectRoot..'/tests/native_queue/craft/shared/QueueCraftFixture.lua'))()
instanceof=function(item,class) return class=='InventoryContainer' and item.bag end
local function container()
 local c={items={}}
 function c:getItems()
  return {size=function() return #self.items end,get=function(_,index) return self.items[index+1] end}
 end
 function c:getItemById(id)
  for _,item in ipairs(self.items) do
   if item:getID()==id then return item end
   if item.bag then local found=item:getItemContainer():getItemById(id);if found then return found end end
  end
 end
 return c
end
local function item(c,id,kind)
 local value={id=id,container=c,condition=10}
 function value:getID() return self.id end
 function value:getFullType() return kind end
 function value:getContainer() return self.container end
 function value:getCondition()return self.condition end
 c.items[#c.items+1]=value;return value
end
local root=container()
local state={root=root,player={getInventory=function() return root end},bags={},tools={},outputs=0}
for i,kind in ipairs({'Base.Hammer','Base.Saw'}) do
 local bag=item(root,i,'Base.Bag_Schoolbag');bag.bag=true
 local source=container();bag.getItemContainer=function() return source end
 state.bags[i]=bag;state.tools[i]=item(source,10+i,kind)
end
state.material={getID=function() return 20 end}
state.book=item(root,21,'Base.BookCarpentry1');state.book.pages=100
state.book.getNumberOfPages=function() return 100 end
state.book.getAlreadyReadPages=function(self) return self.pages end
local output=item(root,22,'Base.WoodenStick2')
assert(root:getItemById(11)==state.tools[1],'fixture must model native recursive lookup')
local result=assert(Fixture.verify(state))
assert(result.consumed==1 and result.outputs==1 and result.toolsReturned==2 and result.tailRead)
local source=state.bags[2]:getItemContainer()
local duplicate=item(source,11,'Base.Hammer')
local outcome,reason=Fixture.verify(state)
assert(not outcome and reason=='borrowed tool identity duplicated')
table.remove(source.items)
state.tools[1].container=root
assert(not Fixture.verify(state),'a nested lookup cannot prove direct container ownership')
state.tools[1].container=state.bags[1]:getItemContainer()
local material=item(root,20,'Base.Plank')
assert(not Fixture.verify(state),'unconsumed input must not pass')
table.remove(root.items)
state.book.pages=99
assert(not Fixture.verify(state),'unfinished reader must not pass')
state.book.pages=100
local extra=item(root,23,'Base.WoodenStick2')
assert(not Fixture.verify(state),'extra craft output must not pass')
table.remove(root.items)
assert(Fixture.verify(state))
print('Craft fixture: recursive native lookup, exact container/ID conservation, consumption, output and reading passed.')

state.case='cancel-pickup';state.outputs=1
state.materialCondition,state.materialUses=10,0
state.toolMeta={}
for i,tool in ipairs(state.tools)do state.toolMeta[i]={id=tool:getID(),kind=tool:getFullType(),condition=10,uses=0}end
local plank=item(root,20,'Base.Plank')
local aborted=assert(Fixture.verify(state,true))
assert(aborted.consumed==0 and aborted.removed==0 and aborted.outputs==0 and aborted.materialPresent and aborted.toolsReturned==2)
state.tools[1].condition=9;assert(not Fixture.verify(state,true),'abort must conserve tool condition');state.tools[1].condition=10
local firstSource=state.bags[1]:getItemContainer()
table.remove(firstSource.items,1);root.items[#root.items+1]=state.tools[1];state.tools[1].container=root
state.book.pages=99
aborted=assert(Fixture.verify(state,false));assert(not aborted.tailRead and aborted.toolsReturned==1)
assert(not Fixture.verify(state,true),'Toolkit abort requires exact early borrowed returns')
table.remove(root.items);firstSource.items[#firstSource.items+1]=state.tools[1];state.tools[1].container=firstSource
state.case='missing-input'
assert(not Fixture.verify(state,false),'missing-input requires actual authority removal')
function root:Remove(value)for i,entry in ipairs(self.items)do if entry==value then table.remove(self.items,i);return end end end
isServer=function()return false end
local removal=Fixture.removeInput(state)
assert(removal.materialId==20 and removal.removed==1 and not root:getItemById(20))
assert(not pcall(Fixture.removeInput,state),'removal cannot be acknowledged twice')
aborted=assert(Fixture.verify(state,false));assert(aborted.removed==1 and not aborted.materialPresent and not aborted.tailRead)
assert(not Fixture.verify(state,true),'Toolkit abort requires completed independent reading')
state.book.pages=100
aborted=assert(Fixture.verify(state,true));assert(aborted.tailRead and aborted.toolsReturned==2)
item(root,24,'Base.WoodenStick2');assert(not Fixture.verify(state,true),'aborted craft must not produce an output')
print('Craft abort authority: exact tools, preserved/removed inputs, zero outputs and native negative reading passed.')

local nextId,savedPages=100,{}
local function preparedContainer()
 local inventory=container()
 function inventory:AddItem(kind)
  nextId=nextId+1;local value=item(self,nextId,kind)
  if kind=='Base.Bag_Schoolbag' then
   value.bag=true;local source=preparedContainer();value.getItemContainer=function()return source end
  elseif kind:find('Base.Book',1,true)then
   value.getNumberOfPages=function()return 200 end
   value.setAlreadyReadPages=function(self,pages)self.pages=pages end
  end
  return value
 end
 return inventory
end
local preparedRoot=preparedContainer()
local prepared=Fixture.prepare({getInventory=function()return preparedRoot end,
 setAlreadyReadPages=function(_,kind,pages)savedPages[kind]=pages end},'missing-input')
for _,book in ipairs({prepared.book,prepared.blocker})do
 assert(book.pages==book:getNumberOfPages()-1 and savedPages[book:getFullType()]==book.pages,
  'authority must seed both book and character pages before native Host duration/startPage reconstruction')
end
print('Craft preparation: authority seeds the independent reader and blocker at their final native page.')
