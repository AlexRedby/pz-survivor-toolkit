package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/?.lua;'..package.path
local Groups=require 'PZSurvivorToolkit/InventoryCategoryGroups'
local Rows=require 'PZSurvivorToolkit/InventoryRows'
ISInventoryPane={MAX_ITEMS_IN_STACK_TO_RENDER=50}
instanceof=function(value,kind) return kind=='InventoryItem' and value.item==true end
function table.wipe(value) for key in pairs(value)do value[key]=nil end end
local reads=0
local function item(category,weight)
 return {item=true,getDisplayCategory=function()reads=reads+1;return category end,
  getUnequippedWeight=function()return weight end,getEquippedWeight=function()return weight/2 end}
end
local a,b,c=item('a',1),item('b',3),item('a',2)
local function source(headerless)
 return {name='Same display name',items=headerless and {a,b,c} or {a,a,b,c},cat='a',equipped=true,
  cleanUIFirstActualIndex=headerless and 1 or 2,_cleanUICategoryTextCache={value='stale'},
  cleanUIWeightText='stale',matchesSearch=true}
end
for _,headerless in ipairs({false,true})do
 local original=source(headerless)
 local pane={itemslist={original},collapsed={[original.name]=false},selected={},mode='details',
  itemSortFunc=function(left,right)return left.cat<right.cat end}
 local saved={[a]='group',_cleanUISelectedGroups={[original.name]=true}}
 assert(Groups.split(pane,saved) and #pane.itemslist==2,'mixed native/CleanUI stack was not split')
 local first,second=pane.itemslist[1],pane.itemslist[2]
 assert(first.realCount==2 and second.realCount==1 and first.weight==3 and second.weight==3,'split lost items/weights')
 assert(first.equippedWeight==1.5 and second.equippedWeight==1.5 and first.matchesSearch)
 assert(first.items[headerless and 1 or 2]==a and second.items[headerless and 1 or 2]==b)
 assert(first.cleanUIFirstActualIndex==(headerless and 1 or 2) and not first._cleanUICategoryTextCache)
 assert(not pane.collapsed[first.name] and not pane.collapsed[second.name],'collapse state was not inherited')
 Rows.restoreSelection(pane,saved)
 local secondHeader=4
 assert(pane.selected[1]==first and pane.selected[secondHeader]==second,'whole stack selection lost a category bucket')
 Rows.restoreAnchor(pane,b);assert(pane.firstSelect==5,'physical Shift anchor did not follow split row')
 Rows.restoreAnchor(pane,original);assert(pane.firstSelect==1,'group Shift anchor did not follow first physical item')
 Rows.restoreSelection(pane,{[c]='item'})
 assert(pane.selected[3]==c and not pane.selected[1] and not pane.selected[4],'child selection became whole category selection')
 local previous=reads
 assert(not Groups.split(pane,saved) and reads==previous,'same projection rescanned unchanged items')
 assert(#original.items==(headerless and 3 or 4),'projection rewrote native source rows')
 -- Native refresh merges same-name items again. The selected category row is
 -- already identified by its suffix key; it must not select every fresh bucket.
 local oneCategory={[first.items[1]]='group',_cleanUISelectedGroups={[first.name]=true}}
 pane.itemslist={source(headerless)}
 assert(Groups.split(pane,oneCategory),'refresh did not rebuild the mixed-category projection')
 Rows.restoreSelection(pane,oneCategory)
 local selectedCount=0
 for _,selected in pairs(pane.selected)do
  selectedCount=selectedCount+1
  assert(selected.cat=='a','refresh selected the unselected category bucket')
 end
 assert(selectedCount==1 and pane.selected[1]==pane.itemslist[1],
  'refresh widened a single category-row selection to the original unsplit stack')
 -- Ordinary UI saves the header identity without CleanUI's group-name map.
 local nativeSelection={[pane.itemslist[1].items[1]]='group'}
 pane.itemslist={source(headerless)}
 assert(Groups.split(pane,nativeSelection))
 Rows.restoreSelection(pane,nativeSelection)
 selectedCount=0
 for _,selected in pairs(pane.selected)do selectedCount=selectedCount+1;assert(selected.cat=='a')end
 assert(selectedCount==1,'ordinary UI header marker widened a previously split category row')
end
print('InventoryCategoryGroups: native/headerless mixed categories, weights, whole/child selection, Shift anchors and bounded projection passed.')
