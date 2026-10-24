-- Actual native/CleanUI rows, native saved selection and independent Host peers.
local R = require 'PZSurvivorToolkit/ItemRetention'
local Pins = require 'BetterContainers/Upgrades/PinnedItems'
local Checks = {}

function Checks.ready(state,mode)
 local page=getPlayerLoot(0)
 local expected=mode=='clean'and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
 if not page or getmetatable(page.inventoryPane)~=expected then return false end
 page:refreshBackpacks()
 page:selectButtonForContainer(state.container)
 page:setForceSelectedContainer(state.container,90000)
 return page.inventoryPane.inventory==state.container
end

local function childRow(pane, item)
 for index,value in ipairs(pane.items)do if value==item then return index end end
end
local function render(pane)
 pane:refreshContainer()
 for _,group in ipairs(pane.itemslist)do if group.items then pane.collapsed[group.name]=false end end
 pane:refreshContainer();pane:renderdetails(false)
end
local function selection(pane,item)
 local function physical(entry,accept)
  if instanceof(entry,'InventoryItem')then accept(entry)
  elseif type(entry)=='table'and entry.items then
   local first=entry.cleanUILargeStackOptimized and 1 or entry.cleanUIFirstActualIndex or 2
   for index=first,#entry.items do accept(entry.items[index])end
  end
 end
 local selected={}
 for index,value in pairs(pane.selected)do
  assert(pane.items[index]==value,'Selected row differs from rendered row')
  physical(value,function(child)selected[child:getID()]=true end)
 end
 -- Native update promotes a selected singleton child to its header, then its
 -- next saveSelection stores the equivalent group marker. Compare physical
 -- identity so this ordinary normalization remains accepted in both classes.
 local count=0
 for id in pairs(selected)do assert(id==item:getID(),'Retention selected an unrelated physical copy');count=count+1 end
 assert(count==1,'Retention lost the selected physical screwdriver')
 local saved=pane:saveSelection({})
 assert(saved[item]~=nil,'Retention lost the saved physical selection')
 for selectedItem,semantic in pairs(saved)do
  if semantic=='item'or semantic=='group'then
   assert(selectedItem==item,'Saved selection includes an unrelated physical copy')
  end
 end
 local anchor=assert(pane.firstSelect,'Retention lost the physical Shift anchor')
 local anchored={}
 physical(pane.items[anchor],function(child)anchored[child:getID()]=true end)
 local anchorCount=0
 for id in pairs(anchored)do assert(id==item:getID(),'Retention moved the Shift anchor to another item');anchorCount=anchorCount+1 end
 assert(anchorCount==1,'Retention Shift anchor does not resolve to the selected physical item')
 return anchor
end

function Checks.snapshot(state)
 local pane=getPlayerLoot(0).inventoryPane
 local function value(entry)
  if instanceof(entry,'InventoryItem')then return {id=entry:getID(),retained=R.isRetained(entry)}end
  return {name=type(entry)=='table'and entry.name or 'missing',group=true}
 end
 local groups,rendered,selected={},{},{}
 for index,group in ipairs(pane.itemslist or {})do
  local items={}
  for child,item in ipairs(group.items or {})do items[#items+1]={index=child,id=item:getID(),retained=R.isRetained(item)}end
  groups[#groups+1]={index=index,name=group.name or '',category=group.cat or '',items=items,
   first=group.cleanUILargeStackOptimized and 1 or group.cleanUIFirstActualIndex or 2,
   equipped=group.equipped==true,matchesSearch=group.matchesSearch==true,collapsed=pane.collapsed[group.name]==true}
 end
 for index,entry in ipairs(pane.items or {})do local row=value(entry);row.index=index;rendered[#rendered+1]=row end
 for index,entry in pairs(pane.selected or {})do
  local row=value(entry);row.index=index;row.exact=pane.items[index]==entry;selected[#selected+1]=row
 end
 local class=getmetatable(pane)==CleanUI_Clean_ISInventoryPane and 'clean'
  or getmetatable(pane)==CleanUI_Vanilla_ISInventoryPane and 'vanilla'or 'unknown'
 return {class=class,fixtureRoot=pane.inventory==state.container,groups=groups,rendered=rendered,
  selected=selected,anchor=pane.firstSelect or -1}
end

function Checks.prepare(state)
 local pane=getPlayerLoot(0).inventoryPane
 assert(pane.inventory==state.container,'Retention order source is not the native trunk')
 for fullType in pairs(Pins.FavouritedItems)do Pins.setFavourite(fullType,false)end
 Pins.setFavourite('Base.Screwdriver',true)
 assert(Pins.displayPinnedItem(pane.inventoryPage),'BC pin ordering is disabled for the trunk')
 pane.itemSortFunc=ISInventoryPane.itemSortByNameInc
 render(pane)
 local item=assert(state.container:getItemById(state.packet.ids[2]))
 local row=assert(childRow(pane,item),'Unmarked physical screwdriver child is missing')
 pane.selected={[row]=item};pane.firstSelect=row
 selection(pane,item)
end

function Checks.probe(state,mode,hostUpdate)
 Checks.before=Checks.snapshot(state)
 local pane=getPlayerLoot(0).inventoryPane
 local expected=mode=='clean'and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
 assert(getmetatable(pane)==expected,'Wrong native inventory class in retention order check')
 local plain=assert(state.container:getItemById(state.packet.ids[2]))
 local retained=assert(state.container:getItemById(state.packet.ids[1]))
 if not hostUpdate then Checks.prepare(state)end
 render(pane)
 Checks.after=Checks.snapshot(state)
 local physical,groups,order={}, {}, {}
 for row,group in ipairs(pane.itemslist)do
  if group.items then
   local first=group.cleanUILargeStackOptimized and 1 or group.cleanUIFirstActualIndex or 2
   local status
   for index=first,#group.items do
    local item=group.items[index]
    assert(not physical[item:getID()],'Physical item duplicated in retention groups')
    physical[item:getID()]=row;groups[item:getID()]=group
    local kept=R.isRetained(item)
    if status~=nil then assert(status==kept,'Mixed retained/unretained physical copies remain grouped')end
    status=kept
    order[#order+1]=item:getID()
   end
  end
 end
 local ordinary=assert(physical[plain:getID()],'Unmarked physical copy disappeared')
 for _,index in ipairs({1,3,4})do
  assert(assert(physical[state.packet.ids[index]],'Retained physical item disappeared')<ordinary,
   'Retained item stayed below the unretained BC-pinned screwdriver')
 end
 assert(groups[plain:getID()]~=groups[retained:getID()],'Same-type retained copies were not split')
 assert(Pins.isFavourite(plain:getFullType()),'Unmarked control is not BC-pinned')
 local selected=selection(pane,plain)
 -- A second refresh must retain the new rows, exact selection and Shift anchor.
 render(pane);assert(selection(pane,plain)==selected,'Repeat refresh changed retained ordering')
 return {mode=mode,hostUpdate=hostUpdate,physicalOrder=order,selectedId=plain:getID(),
  retainedBeforePinned=true,mixedCopiesSplit=true,exactSelection=true,repeatedRefresh=true}
end
return Checks
