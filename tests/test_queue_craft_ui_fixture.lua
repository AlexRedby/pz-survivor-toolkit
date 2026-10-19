local nativeRequire=require
require=function(module)
 if module=='QueueCookEvolvedFixture'then return assert(loadfile(ProjectRoot..'/tests/native_queue/craft-ui/shared/'..module..'.lua'))()end
 return nativeRequire(module)
end
local Fixture=assert(loadfile(ProjectRoot..'/tests/native_queue/craft-ui/shared/QueueCraftUIFixture.lua'))()
instanceof=function(item,class)return class=='InventoryContainer'and item.bag end
local makeItem
local nextId=1000
local function container()
 local c={items={}}
 function c:getItems()return {size=function()return #self.items end,get=function(_,i)return self.items[i+1]end}end
 function c:AddItem(kind)
  nextId=nextId+1;local value=makeItem(self,nextId,kind)
  if kind=='Base.Bag_Schoolbag'then
   value.bag=true;value.source=container()
   function value:getItemContainer()return self.source end
  elseif kind=='Base.BookCarpentry1'then
   value.pages=99
   function value:setAlreadyReadPages(pages)self.pages=pages end
   function value:getAlreadyReadPages()return self.pages end
   function value:getNumberOfPages()return 100 end
  end
  return value
 end
 function c:Remove(item)
  for index,value in ipairs(self.items)do if value==item then table.remove(self.items,index);return end end
 end
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
makeItem=item
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

-- Active cancellation preserves every exact input and records native unread controls.
root=container()
state={case='vanilla-cancel-active',player={getInventory=function()return root end,getOnlineID=function()return 0 end,isEquipped=function()return false end},
 materials={20,21},bags={1,2},toolMeta={},baselineOutputIds={30},book=40,
 materialMeta={{id=20,kind='Base.Plank',condition=10,uses=0},{id=21,kind='Base.Plank',condition=10,uses=0}},
 sparePlanks={{id=50,kind='Base.Plank',condition=10,uses=0}}}
for i,kind in ipairs({'Base.Hammer','Base.Saw'})do
 local bag=item(root,i,'Base.Bag_Schoolbag');bag.bag=true;bag.source=container()
 function bag:getItemContainer()return self.source end
 item(bag.source,10+i,kind);state.toolMeta[i]={id=10+i,kind=kind,condition=10,uses=0}
end
item(root,30,'Base.WoodenStick2')
local material=item(root,20,'Base.Plank');item(root,21,'Base.Plank');local spare=item(root,50,'Base.Plank')
book=item(root,40,'Base.BookCarpentry1');book.pages=99
function book:getAlreadyReadPages()return self.pages end
function book:getNumberOfPages()return 100 end
receipt=assert(Fixture.verify(state))
assert(receipt.consumed==0 and receipt.outputs==0 and not receipt.tailRead)
assert(#receipt.materialStates==2 and receipt.materialStates[1].id==20 and receipt.materialStates[1].state=='surviving')
assert(receipt.sparePlanks[1].id==50)
assert(Fixture.descriptor(state).materialMeta==state.materialMeta)
material.condition=9;assert(not Fixture.verify(state),'canceled input metadata must survive');material.condition=10
material.kind='Base.Log';assert(not Fixture.verify(state),'canceled input identity cannot be substituted');material.kind='Base.Plank'
material.id=99;assert(not Fixture.verify(state),'canceled exact input cannot be lost');material.id=20
spare.condition=9;assert(not Fixture.verify(state),'cancellation cannot change unrelated input');spare.condition=10
item(root,31,'Base.WoodenStick2');assert(not Fixture.verify(state),'active cancellation cannot produce output');table.remove(root.items)
book.pages=100;receipt=assert(Fixture.verify(state));assert(receipt.tailRead)
print('craft UI active cancellation authority checks passed')

-- Pool removal records actual cached output without claiming normal input consumption.
isServer=function()return false end
state.case='vanilla-missing-batch-pool';state.root=root
local removed=Fixture.removePool(state)
assert(removed.removedMaterials[1].id==20 and removed.removedMaterials[2].id==21)
local introduced=root:getItemById(removed.introducedSpare.id)
assert(introduced and introduced~=spare and #state.sparePlanks==1 and state.sparePlanks[1].id==50)
assert(Fixture.sparePresent(state.player,removed.introducedSpare))
assert(not root:getItemById(20)and not root:getItemById(21))
receipt=assert(Fixture.verify(state))
assert(receipt.consumed==0 and receipt.outputs==0 and #receipt.spentMaterials==0 and #receipt.survivingMaterials==0)
assert(#receipt.removedMaterials==2 and receipt.materialStates[1].state=='removed')
assert(receipt.introducedSpare==removed.introducedSpare)
introduced.condition=9;assert(not Fixture.verify(state),'introduced spare metadata must survive');introduced.condition=10
introduced.kind='Base.Log';assert(not Fixture.verify(state),'introduced spare type must survive');introduced.kind='Base.Plank'
introduced.container=sources[2];assert(not Fixture.verify(state),'introduced spare must remain directly at root');introduced.container=root
local nested=root:getItemById(2):getItemContainer()
item(nested,introduced.id,'Base.Plank');assert(not Fixture.verify(state),'introduced spare identity must be unique');table.remove(nested.items)
root:Remove(introduced);assert(not Fixture.verify(state),'introduced spare cannot be consumed');root.items[#root.items+1]=introduced
local cachedOutput=item(root,31,'Base.WoodenStick2')
function cachedOutput:getModData()return {['Base.Plank']=1}end
receipt=assert(Fixture.verify(state));assert(receipt.consumed==0 and receipt.outputs==1 and receipt.outputPlankCounts[1]==1)
local extraOutput=item(root,32,'Base.WoodenStick2')
function extraOutput:getModData()return {['Base.Plank']=1}end
receipt=assert(Fixture.verify(state));assert(receipt.outputs==2 and #receipt.outputPlankCounts==2,'authority must retain extra native output')
item(root,20,'Base.Plank');assert(not Fixture.verify(state),'a removed exact ID cannot remain');table.remove(root.items)
spare.condition=9;assert(not Fixture.verify(state),'pool loss cannot consume or change an unrelated Plank');spare.condition=10
assert(not pcall(Fixture.removePool,state),'duplicate pool removal is rejected')
print('craft UI shared-pool removal authority checks passed')

-- The next authority preparation cleans only its verified previous probe before snapshotting.
state.player.setAlreadyReadPages=function()end
introduced.condition=9
assert(not pcall(Fixture.prepare,state.player,'neat-missing-batch-pool',state),'cleanup cannot delete a changed probe')
assert(root:getItemById(introduced.id)==introduced and root:getItemById(spare.id)==spare)
introduced.condition=10;state.verified=false
assert(not pcall(Fixture.prepare,state.player,'neat-missing-batch-pool',state),'unverified probe cannot be cleaned')
state.verified=true
local sent={}
isServer=function()return true end
sendRemoveItemFromContainer=function(c,value)sent[#sent+1]={container=c,item=value}end
sendAddItemToContainer=function()end
local nextState=Fixture.prepare(state.player,'neat-missing-batch-pool',state)
assert(#sent==#state.cleanupRootItems+#state.cleanupBags and sent[1].container==root and sent[1].item==introduced)
assert(not root:getItemById(introduced.id)and root:getItemById(spare.id)==spare)
assert(not root:getItemById(31)and not root:getItemById(32)and root:getItemById(30),'only new owned outputs may be cleaned')
assert(not root:getItemById(state.book)and not root:getItemById(state.bags[1])and not root:getItemById(state.toolMeta[1].id))
assert(#nextState.sparePlanks==1 and nextState.sparePlanks[1].id==spare.id,'previous probe cannot expand the next manual pool')
local nextRemoval=Fixture.removePool(nextState)
assert(nextRemoval.introducedSpare.id~=introduced.id and root:getItemById(nextRemoval.introducedSpare.id))
assert(Fixture.verify(nextState))
isServer=function()return false end
local lastState=Fixture.prepare(state.player,'vanilla-batch',nextState)
assert(not root:getItemById(nextRemoval.introducedSpare.id)and root:getItemById(spare.id)==spare)
assert(not lastState.introducedSpare,'normal preparation cannot add a probe')
print('craft UI introduced spare and exact previous-case cleanup checks passed')

-- Fresh normal batches can leave no pre-existing Planks; the new probe remains mandatory.
root:Remove(spare)
for _,id in ipairs(lastState.materials)do root:Remove(root:getItemById(id))end
root:AddItem('Base.WoodenStick2');root:AddItem('Base.WoodenStick2')
local lastReceipt=assert(Fixture.verify(lastState))
local emptyState=Fixture.prepare(state.player,'cook-missing-batch-pool',lastState)
assert(#emptyState.sparePlanks==0,'zero-spare setup must be real')
for _,id in ipairs(lastReceipt.outputIds)do assert(not root:getItemById(id),'successful owned output must be removed before next case')end
assert(not root:getItemById(lastReceipt.bookId)and not root:getItemById(lastState.bags[1])and root:getItemById(30))
local emptyRemoval=Fixture.removePool(emptyState)
local emptyReceipt=assert(Fixture.verify(emptyState))
assert(#emptyReceipt.sparePlanks==0 and emptyReceipt.introducedSpare.id==emptyRemoval.introducedSpare.id)
local onlyProbe=root:getItemById(emptyReceipt.introducedSpare.id)
root:Remove(onlyProbe)
assert(not Fixture.verify(emptyState),'empty pre-existing spares cannot make probe conservation vacuous')
print('craft UI zero-preexisting-spare probe checks passed')

-- Cancellation-owned survivors are cleaned atomically; unrelated root items survive.
local cancelRoot=container()
local unrelated=item(cancelRoot,700,'Base.Plank')
local unrelatedOutput=item(cancelRoot,701,'Base.WoodenStick2')
local cancelPlayer={getInventory=function()return cancelRoot end,getOnlineID=function()return 0 end,
 setAlreadyReadPages=function()end,isEquipped=function(self,value)return self.equipped and self.equipped[value.id]or false end}
local cancelled=Fixture.prepare(cancelPlayer,'vanilla-cancel-active')
local beforeCleanup=assert(Fixture.verify(cancelled))
local owned1=cancelRoot:getItemById(cancelled.materials[1])
local owned2=cancelRoot:getItemById(cancelled.materials[2])
local function intact()
 assert(cancelRoot:getItemById(owned1.id)==owned1 and cancelRoot:getItemById(owned2.id)==owned2)
 assert(cancelRoot:getItemById(700)==unrelated and cancelRoot:getItemById(701)==unrelatedOutput)
end
owned2.condition=9
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',cancelled),'all cleanup targets must validate before any removal')
intact();owned2.condition=10
cancelled.verified=false
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',cancelled),'unverified survivors cannot be cleaned')
intact();cancelled.verified=true
local originalId=cancelled.cleanupRootItems[1].id
cancelled.cleanupRootItems[1].id=700
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',cancelled),'malformed ownership cannot delete an unrelated spare')
intact();cancelled.cleanupRootItems[1].id=originalId
sent={};isServer=function()return true end
local afterCancel=Fixture.prepare(cancelPlayer,'vanilla-missing-batch-pool',cancelled)
assert(#sent==#cancelled.cleanupRootItems+#cancelled.cleanupBags and sent[1].item==owned1 and sent[2].item==owned2)
assert(not cancelRoot:getItemById(owned1.id)and not cancelRoot:getItemById(owned2.id))
assert(cancelRoot:getItemById(700)==unrelated and cancelRoot:getItemById(701)==unrelatedOutput)
assert(#afterCancel.sparePlanks==1 and afterCancel.sparePlanks[1].id==700)
assert(#afterCancel.baselineOutputIds==1 and afterCancel.baselineOutputIds[1]==701)
assert(beforeCleanup.materialStates[1].state=='surviving'and beforeCleanup.materialStates[1].id==owned1.id,
 'cleanup cannot rewrite the prior resource receipt')
print('craft UI previous cancellation exact atomic cleanup checks passed')

-- Full fixture cleanup includes root tools and source bags after native unequip.
local toolCase=Fixture.prepare(cancelPlayer,'vanilla-cancel-active')
local rootTool=cancelRoot:getItemById(toolCase.toolMeta[1].id)
local oldSource=rootTool:getContainer();oldSource:Remove(rootTool)
rootTool.container=cancelRoot;cancelRoot.items[#cancelRoot.items+1]=rootTool
local sourceTool=cancelRoot:getItemById(toolCase.toolMeta[2].id)
local sourceBag=cancelRoot:getItemById(toolCase.bags[2])
local unrelatedTool=item(cancelRoot,702,'Base.Hammer')
local nativeReceipt=assert(Fixture.verify(toolCase))
assert(#toolCase.cleanupRootItems==4 and toolCase.cleanupRootItems[4].id==rootTool.id)
assert(nativeReceipt.resources[1].rootCount==1 and nativeReceipt.resources[2].sourceCount==1)
local firstMaterial=cancelRoot:getItemById(toolCase.materials[1])
rootTool.condition=9
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',toolCase),
 'an invalid final root-tool target cannot allow earlier material removals')
assert(cancelRoot:getItemById(firstMaterial.id)==firstMaterial and cancelRoot:getItemById(rootTool.id)==rootTool)
rootTool.condition=10;toolCase.verified=false
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',toolCase),'unverified root tools cannot be deleted')
assert(cancelRoot:getItemById(firstMaterial.id)==firstMaterial and cancelRoot:getItemById(rootTool.id)==rootTool)
toolCase.verified=true
sourceBag.condition=9
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',toolCase),'changed bag metadata must prevent every removal')
assert(cancelRoot:getItemById(firstMaterial.id)==firstMaterial and cancelRoot:getItemById(rootTool.id)==rootTool)
sourceBag.condition=10
sourceTool.condition=9
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',toolCase),'changed source tool metadata must prevent every removal')
assert(cancelRoot:getItemById(firstMaterial.id)==firstMaterial and cancelRoot:getItemById(rootTool.id)==rootTool)
sourceTool.condition=10
local unexpected=item(sourceBag:getItemContainer(),703,'Base.Log')
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',toolCase),'unexpected bag contents must prevent every removal')
assert(cancelRoot:getItemById(firstMaterial.id)==firstMaterial and cancelRoot:getItemById(rootTool.id)==rootTool)
sourceBag:getItemContainer():Remove(unexpected)
cancelPlayer.equipped={[sourceBag.id]=true}
assert(not pcall(Fixture.prepare,cancelPlayer,'vanilla-missing-batch-pool',toolCase),'an equipped bag must prevent every removal')
assert(cancelRoot:getItemById(firstMaterial.id)==firstMaterial and cancelRoot:getItemById(rootTool.id)==rootTool)
cancelPlayer.equipped={};sent={}
local afterTools=Fixture.prepare(cancelPlayer,'vanilla-missing-batch-pool',toolCase)
assert(#sent==6 and sent[4].item==rootTool and not cancelRoot:getItemById(rootTool.id))
assert(not cancelRoot:getItemById(sourceTool.id)and not cancelRoot:getItemById(sourceBag.id))
assert(cancelRoot:getItemById(702)==unrelatedTool and cancelRoot:getItemById(700)==unrelated)
assert(cancelRoot:getItemById(701)==unrelatedOutput and not cancelRoot:getItemById(toolCase.bags[1]))
assert(nativeReceipt.resources[1].rootCount==1 and nativeReceipt.resources[1].id==rootTool.id,
 'cleanup must not rewrite the prior authoritative root-tool receipt')
print('craft UI full owned cleanup, contents/equipped guards and unrelated conservation checks passed')

-- The evolved authority keeps exact physical IDs and portions separate from native
-- output effects; these envelope tests do not execute or replace game recipes.
do
 local Evolved=require 'QueueCookEvolvedFixture'
 local evolvedRoot=container()
 local previousMake=makeItem
 makeItem=function(source,id,kind)
  local value=previousMake(source,id,kind)
  value.hunger=kind=='Base.Tomato'and -0.12 or -0.1
  function value:getHungChange()return self.hunger end
  function value:setHungChange(hunger)self.hunger=hunger end
  return value
 end
 local previousServer,previousClock=isServer,getTimestampMs
 isServer=function()return false end;getTimestampMs=function()return 100 end
 Perks={Cooking='Cooking'}
 local evolvedPlayer={getInventory=function()return evolvedRoot end,getPerkLevel=function()return 0 end,setAlreadyReadPages=function()end}
 local baseline=makeItem(evolvedRoot,80000,'Base.Salad')
 local prepared=Evolved.prepare(evolvedPlayer,'cook-evolved-return')
 local descriptor=Evolved.descriptor(prepared)
 assert(descriptor.base.kind=='Base.Bowl'and descriptor.ingredient.hunger==-0.12 and descriptor.spice.hunger==-0.005)
 assert(descriptor.baselineDishIds[1]==baseline.id and descriptor.cookingLevel==0)
 local source=evolvedRoot:getItemById(prepared.bags[1]):getItemContainer()
 local ingredientSource=evolvedRoot:getItemById(prepared.bags[2]):getItemContainer()
 local old=evolvedRoot:getItemById(prepared.base.id)
 local spice=evolvedRoot:getItemById(prepared.spice.id)
 source:Remove(old);old.container=nil
 ingredientSource:Remove(spice);spice.container=nil
 local tomato=evolvedRoot:getItemById(prepared.ingredient.id);tomato.hunger=-0.06
 local dish=makeItem(source,80001,'Base.Salad')
 local function strings(values)return {size=function()return #values end,get=function(_,index)return values[index+1]end}end
 function dish:getExtraItems()return strings({'Base.Tomato'})end
 function dish:getSpices()return strings({'Base.Pepper'})end
 evolvedRoot:getItemById(prepared.book).pages=100
 local value=assert(Evolved.verify(prepared))
 assert(value.base.totalCount==0 and value.spice.totalCount==0 and value.outputs==1 and value.tailRead)
 assert(value.dishes[1].id==dish.id and value.dishes[1].sourceCount==1 and value.dishes[1].totalCount==1)
 assert(value.ingredient.id==tomato.id and value.ingredient.sourceCount==1 and value.ingredient.hunger==-0.06)
 assert(value.dishes[1].extras[1]=='Base.Tomato'and value.dishes[1].spices[1]=='Base.Pepper')
 source:Remove(dish);dish.container=evolvedRoot;evolvedRoot.items[#evolvedRoot.items+1]=dish
 local deviation=assert(Evolved.verify(prepared))
 assert(deviation.dishes[1].sourceCount==0 and deviation.dishes[1].rootCount==1,
  'native misplaced dish must remain an observed endpoint deviation')
 assert(value.dishes[1].sourceCount==1,'later verification cannot rewrite a prior receipt')
 baseline.kind='Base.Bowl';assert(not Evolved.verify(prepared),'baseline replacement cannot be relabelled as a new dish')
 baseline.kind='Base.Salad'
 local duplicate=makeItem(evolvedRoot,prepared.bags[1],'Base.Bowl')
 assert(not Evolved.verify(prepared),'duplicate source identity must reject authority verification')
 evolvedRoot:Remove(duplicate)
 makeItem=previousMake;isServer,getTimestampMs=previousServer,previousClock
end
print('craft UI evolved replacement/leftover/spice/endpoint authority envelope checks passed')
