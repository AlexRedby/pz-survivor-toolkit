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
 local value={id=id,container=c}
 function value:getID() return self.id end
 function value:getFullType() return kind end
 function value:getContainer() return self.container end
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
