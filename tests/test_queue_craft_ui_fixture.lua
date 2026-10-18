local Fixture=assert(loadfile(ProjectRoot..'/tests/native_queue/craft-ui/shared/QueueCraftUIFixture.lua'))()
instanceof=function(item,class)return class=='InventoryContainer'and item.bag end
local function container()
 local c={items={}}
 function c:getItems()return {size=function()return #self.items end,get=function(_,i)return self.items[i+1]end}end
 function c:getItemById(id)
  for _,item in ipairs(self.items)do
   if item.id==id then return item end
   if item.bag then local found=item.source:getItemById(id);if found then return found end end
  end
 end
 return c
end
local function item(c,id,kind)
 local value={id=id,container=c,kind=kind,condition=10}
 function value:getID()return self.id end
 function value:getFullType()return self.kind end
 function value:getContainer()return self.container end
 function value:getCondition()return self.condition end
 c.items[#c.items+1]=value;return value
end
local root=container()
local state={case='vanilla-batch',player={getInventory=function()return root end},materials={20,21},
 bags={1,2},toolMeta={},baselineOutputIds={30},book=40}
local tools,sources={},{}
for i,kind in ipairs({'Base.Hammer','Base.Saw'})do
 local bag=item(root,i,'Base.Bag_Schoolbag');bag.bag=true;bag.source=container()
 function bag:getItemContainer()return self.source end
 sources[i]=bag.source;tools[i]=item(bag.source,10+i,kind)
 state.toolMeta[i]={id=10+i,kind=kind,condition=10,uses=0}
end
local baseline=item(root,30,'Base.WoodenStick2')
item(root,31,'Base.WoodenStick2');item(root,32,'Base.WoodenStick2')
local book=item(root,40,'Base.BookCarpentry1');book.pages=100
function book:getAlreadyReadPages()return self.pages end
function book:getNumberOfPages()return 100 end
local receipt=assert(Fixture.verify(state))
assert(receipt.consumed==2 and receipt.outputs==2 and receipt.toolsReturned==2 and receipt.tailRead)
assert(receipt.materialIds[1]==20 and receipt.outputIds[1]==31 and receipt.outputIds[2]==32)
item(root,20,'Base.Plank');assert(not Fixture.verify(state),'an unspent exact input must fail');table.remove(root.items)
item(root,33,'Base.WoodenStick2');assert(not Fixture.verify(state),'extra output must fail');table.remove(root.items)
root.items[5].id=31;assert(not Fixture.verify(state),'duplicate new output identity must fail');root.items[5].id=32
baseline.kind='Base.Plank';assert(not Fixture.verify(state),'baseline replacement must fail');baseline.kind='Base.WoodenStick2'
tools[1].condition=9;assert(not Fixture.verify(state),'changed tool must fail');tools[1].condition=10
item(sources[2],11,'Base.Hammer');assert(not Fixture.verify(state),'duplicate nested identity must fail');table.remove(sources[2].items)
tools[1].container=root;assert(not Fixture.verify(state),'recursive lookup alone cannot prove endpoint');tools[1].container=sources[1]
table.remove(sources[1].items);root.items[#root.items+1]=tools[1];tools[1].container=root
receipt=assert(Fixture.verify(state));assert(receipt.toolsReturned==1 and receipt.resources[1].rootCount==1,'record real native endpoint')
book.pages=99;receipt=assert(Fixture.verify(state));assert(not receipt.tailRead,'retain native unread outcome')
book.kind='Base.BookCooking1';assert(not Fixture.verify(state),'reader substitution must fail')
print('craft UI exact authority fixture checks passed')
