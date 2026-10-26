local M={}
function M.isCase(case)return case=='bandage-all'or case=='bandage-reset-after-body'end
local function all(container,result)
 result=result or{};local values=container:getItems()
 for i=0,values:size()-1 do local item=values:get(i);result[#result+1]=item;if instanceof(item,'InventoryContainer')then all(item:getItemContainer(),result)end end
 return result
end
local function snapshot(root,source,id)
 local item=root:getItemById(id);local total=0;for _,value in ipairs(all(root))do if value:getID()==id then total=total+1 end end
 return{id=id,kind=item and item:getFullType()or false,favorite=item and item:isFavorite()or false,blood=item and item:getBloodLevel()or false,
  rootCount=item and item:getContainer()==root and 1 or 0,sourceCount=item and item:getContainer()==source and 1 or 0,totalCount=total}
end
function M.seed(state)
 local root=state.root;local source=assert(root:getItemById(state.ids.bagId)):getItemContainer()
 local baseline={};for _,item in ipairs(all(root))do if item:getFullType()=='Base.Bandage'then baseline[#baseline+1]=snapshot(root,source,item:getID())end end
 table.sort(baseline,function(a,b)return a.id<b.id end)
 local item=assert(source:AddItem('Base.BandageDirty'));item:setFavorite(true)
 assert(not instanceof(item,'Clothing')and not instanceof(item,'InventoryContainer')and item:getItemAfterCleaning()=='Base.Bandage','native transforming bandage script differs')
 local option=assert(getSandboxOptions():getOptionByName('WashSmart.BandageWaterPerItem'),'native selected WashFix water option missing')
 local water=option:getValue();assert(type(water)=='number'and water==water and water>=.5 and water<=10,'selected bandage water rule invalid')
 local spec={id=item:getID(),kind=item:getFullType(),afterType=item:getItemAfterCleaning(),favorite=item:isFavorite(),blood=item:getBloodLevel(),
  waterOverride=water,baselineClean=baseline}
 if isServer()then sendAddItemToContainer(source,item)end
 return spec
end
function M.resolve(player,ids)
 local root=player:getInventory();local bag=root:getItemById(ids.bagId);local item=root:getItemById(ids.bandage.id)
 if not bag or not item or item:getContainer()~=bag:getItemContainer()or item:getFullType()~=ids.bandage.kind
  or item:getItemAfterCleaning()~=ids.bandage.afterType or item:isFavorite()~=ids.bandage.favorite or item:getBloodLevel()~=ids.bandage.blood then return false end
 local actual=snapshot(root,bag:getItemContainer(),ids.bandage.id)
 return actual.rootCount==0 and actual.sourceCount==1 and actual.totalCount==1
end
function M.snapshot(player,ids)
 local root=player:getInventory();local source=assert(root:getItemById(ids.bagId)):getItemContainer();local spec=ids.bandage
 local baseline,known={},{};for _,value in ipairs(spec.baselineClean)do known[value.id]=true;baseline[#baseline+1]=snapshot(root,source,value.id)end
 local created={};for _,item in ipairs(all(root))do
  if item:getFullType()==spec.afterType and not known[item:getID()]then created[#created+1]=snapshot(root,source,item:getID())end
 end
 table.sort(created,function(a,b)return a.id<b.id end)
 return{input=snapshot(root,source,spec.id),baselineClean=baseline,created=created}
end
function M.paidInput(player,ids)
 local value=M.snapshot(player,ids);local item=player:getInventory():getItemById(ids.bandage.id)
 if value.input.totalCount~=1 or value.input.kind~=ids.bandage.kind or value.input.favorite~=true or #value.created~=0
  or not item or item:getBloodLevel()~=ids.bandage.blood then return end
 return value
end
function M.cleanup(state)
 local receipt=assert(state.verifiedReceipt and state.verifiedReceipt.bandage,'unverified bandage cleanup')
 local actual=M.snapshot(state.player,state.ids);local root=state.root;local source=assert(root:getItemById(state.ids.bagId)):getItemContainer()
 local expected=state.case=='bandage-all'and receipt.created[1]or receipt.input
 assert(expected and expected.totalCount==1 and expected.favorite==true and(expected.rootCount==1 and expected.sourceCount==0 or expected.rootCount==0 and expected.sourceCount==1),'invalid verified bandage endpoint')
 local value=snapshot(root,source,expected.id)
 assert(value.kind==expected.kind and value.favorite==expected.favorite and value.blood==expected.blood and value.totalCount==1 and value.rootCount==expected.rootCount and value.sourceCount==expected.sourceCount,'bandage left verified endpoint')
 if state.case=='bandage-all'then assert(actual.input.totalCount==0 and #actual.created==1 and actual.created[1].id==expected.id,'bandage output identity changed')
 else assert(#actual.created==0 and actual.input.id==expected.id,'unpaid bandage transformed')end
 return expected.id,expected.kind
end
function M.removeRoot(state,id)
 local item=state.root:getItemById(id)
 if item and item:getContainer()==state.root then state.root:Remove(item);if isServer()then sendRemoveItemFromContainer(state.root,item)end end
end
return M
