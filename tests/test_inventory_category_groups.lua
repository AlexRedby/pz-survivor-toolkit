package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/?.lua;'..package.path
local tagMode=false
local fakeTags={enabled=function()return tagMode end,forItem=function(item)return item.tags or {} end,
 signature=function(tags)local ids={};for _,id in ipairs(tags)do ids[#ids+1]=id end;table.sort(ids);return table.concat(ids,'|')end}
package.loaded['PZSurvivorToolkit/ItemTags']=fakeTags
package.loaded['PZSurvivorToolkit/ItemRetention']={isRetained=function(item)return item.retained==true or item.legacyRetained==true end}
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

-- Identical native-category items with different explicit tags need separate chips
-- and physical selection must remain exact if a later tag change merges them.
tagMode=true
local x,y=item('same',1),item('same',2);x.tags={'tool'};y.tags={'tool','custom'}
local function raw()return {name='same',cat='same',items={x,x,y}}end
local pane={itemslist={raw()},collapsed={},selected={}}
assert(Groups.split(pane,{}) and #pane.itemslist==2,'different instance tags merged')
local selected={[pane.itemslist[1].items[1]]='group'}
x.tags=y.tags;pane.itemslist={raw()}
assert(not Groups.split(pane,selected) and #pane.itemslist==1)
Rows.restoreSelection(pane,selected)
assert(pane.selected[2]==x and not pane.selected[1] and not pane.selected[3],
 'tag merge widened previously selected instances')
print('Inventory tag groups: per-instance split and exact selection on merge passed.')

-- A stable signature/name does not imply stable physical membership. Keep the
-- original selected copies when another item joins/leaves that signature.
for _, scenario in ipairs({'joins', 'leaves', 'swaps', 'header'}) do
 local a,b,c=item('same',1),item('same',1),item('same',1)
 a.tags={'tagged'};b.tags={'plain'};c.tags={'plain'}
 local order={a,a,b,c}
 local function rawGroup() return {name='membership',cat='same',items=order} end
 local pane={itemslist={rawGroup()},collapsed={},selected={}}
 Groups.split(pane,{})
 local target=(scenario=='leaves' or scenario=='header') and pane.itemslist[2] or pane.itemslist[1]
 local selected={[target.items[1]]='group',_cleanUISelectedGroups={[target.name]=true}}
 local wanted=(scenario=='leaves' or scenario=='header') and {[b]=true,[c]=true} or {[a]=true}
 if scenario=='joins' or scenario=='leaves' then b.tags={'tagged'}
 elseif scenario=='swaps' then a.tags={'plain'};b.tags={'tagged'}
 else order={c,c,a,b} end
 pane.itemslist={rawGroup()};Groups.split(pane,selected)
 for _,row in ipairs(pane.itemslist)do pane.collapsed[row.name]=false end
 Rows.restoreSelection(pane,selected)
 local actual={}
 for _,value in pairs(pane.selected)do
  if value.items then
   for index=value.cleanUIFirstActualIndex or 2,#value.items do actual[value.items[index]]=true end
  else actual[value]=true end
 end
 for _,physical in ipairs({a,b,c})do
  assert((actual[physical] or false)==(wanted[physical] or false),
   'tag membership '..scenario..' widened or dropped an originally selected physical copy')
 end
end
print('Inventory tag groups: surviving row names preserve exact physical membership and changed display markers.')

-- Collapsed children have no selectable row indices. Membership recovery must
-- expose partial selections, while preserving whole-row and unrelated collapse.
for _,headerless in ipairs({false,true})do
 for _,scenario in ipairs({'joins','leaves','swaps','merge','header'})do
  local a,b,c=item('same',1),item('same',1),item('same',1)
  a.tags={'tagged'};b.tags={'plain'};c.tags={'plain'}
  local order=headerless and {a,b,c} or {a,a,b,c}
  local function rawGroup()return {name='collapsed-membership',cat='same',items=order,
   cleanUIFirstActualIndex=headerless and 1 or 2}end
  local pane={itemslist={rawGroup()},collapsed={['collapsed-membership']=true},selected={}}
  Groups.split(pane,{})
  local target=(scenario=='leaves' or scenario=='header') and pane.itemslist[2] or pane.itemslist[1]
  local saved={[target.items[1]]='group',_cleanUISelectedGroups={[target.name]=true}}
  local wanted=(scenario=='leaves' or scenario=='header') and {[b]=true,[c]=true} or {[a]=true}
  if scenario=='joins' or scenario=='leaves' then b.tags={'tagged'}
  elseif scenario=='swaps' then a.tags={'plain'};b.tags={'tagged'}
  elseif scenario=='merge' then a.tags={'plain'}
  else order=headerless and {c,a,b} or {c,c,a,b} end
  pane.itemslist={rawGroup()};Groups.split(pane,saved)
  Rows.restoreSelection(pane,saved)
  local actual={}
  for _,value in pairs(pane.selected)do
   if value.items then
    for index=value.cleanUIFirstActualIndex or 2,#value.items do actual[value.items[index]]=true end
   else actual[value]=true end
  end
  for _,physical in ipairs({a,b,c})do
   assert((actual[physical] or false)==(wanted[physical] or false),
    'collapsed tag membership '..scenario..' widened or dropped a selected physical copy')
  end
  for _,row in ipairs(pane.itemslist)do
   local count,total=0,0
   for index=row.cleanUIFirstActualIndex or 2,#row.items do
    total=total+1;if wanted[row.items[index]]then count=count+1 end
   end
   if count>0 and count<total then
    assert(pane.collapsed[row.name]==false,'partial selected row kept its exact children hidden')
   else assert(pane.collapsed[row.name]~=false,'whole-selected or unrelated collapsed row expanded unnecessarily')end
  end
 end
end
print('Inventory tag groups: collapsed native/headerless membership preserves exact selection without unnecessary expansion.')

-- Stick splits exact copies even with tags disabled. Selecting an ordinary
-- child must not expand to the whole native stack when another copy is marked.
for _,headerless in ipairs({false,true})do
 tagMode=false
 local a,b,c=item('same',1),item('same',2),item('same',3)
 a.retained,c.legacyRetained=true,true
 local function rawGroup()return {name='retained-copies',cat='same',items=headerless and {a,b,c} or {a,a,b,c},
  cleanUIFirstActualIndex=headerless and 1 or 2}end
 local pane={itemslist={rawGroup()},collapsed={['retained-copies']=false},selected={}}
 local saved={[b]='item'}
 assert(Groups.split(pane,saved) and #pane.itemslist==2,'retained/ordinary copies merged with tags off')
 local kept,ordinary=pane.itemslist[1],pane.itemslist[2]
 assert(kept.realCount==2 and kept.weight==4 and ordinary.realCount==1 and ordinary.weight==2)
 Rows.restoreSelection(pane,saved)
 local selectedCount=0
 for _,value in pairs(pane.selected)do selectedCount=selectedCount+1;assert(value==b,'ordinary child selection widened')end
 assert(selectedCount==1)
 local retainedSelected={[kept.items[1]]='group',_cleanUISelectedGroups={[kept.name]=true}}
 a.retained,c.legacyRetained=false,false
 pane.itemslist={rawGroup()};Groups.split(pane,retainedSelected)
 Rows.restoreSelection(pane,retainedSelected)
 local actual={}
 for _,value in pairs(pane.selected)do actual[value]=true end
 assert(actual[a] and actual[c] and not actual[b] and not actual[pane.itemslist[1]],
  'releasing retained copies selected the previously ordinary copy')
end
print('Inventory retained groups: exact mixed copies, legacy flags, tags disabled, weights and release selection passed.')
