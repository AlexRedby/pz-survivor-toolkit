-- Read-only saved-character witness. No item factories, mutations or native
-- admission calls; the server and normal save/quit own persistence.
local M={}
function M.capture(player)
 local descriptor=player:getDescriptor()
 local result={name=descriptor:getForename()..' '..descriptor:getSurname(),items={},worn={}}
 local seen,containers={},{}
 local function visit(container,parent)
  assert(container and not containers[container],'saved inventory has a repeated/cyclic container')
  containers[container]=true
  local items=container:getItems()
  for index=0,items:size()-1 do
   local item=items:get(index);local id=item:getID()
   assert(type(id)=='number'and id%1==0 and id~=-1 and not seen[id],'saved inventory has an invalid/duplicate item ID')
   seen[id]=item
   result.items[#result.items+1]={id=id,fullType=item:getFullType(),parent=parent,count=item:getCount()}
   if instanceof(item,'InventoryContainer')then visit(item:getInventory(),id)end
  end
 end
 visit(player:getInventory(),'root')
 table.sort(result.items,function(a,b)return a.id<b.id end)
 for _,slot in ipairs({'primary','secondary'})do
  local item=slot=='primary'and player:getPrimaryHandItem()or nil
  if slot=='secondary'then item=player:getSecondaryHandItem()end
  result[slot]=item and item:getID()or false
  assert(not item or seen[item:getID()]==item,'saved hand item is outside the captured inventory')
 end
 local worn=player:getWornItems()
 for index=0,worn:size()-1 do
  local entry=worn:get(index);local item=entry:getItem()
  assert(item and seen[item:getID()]==item,'saved worn item is outside the captured inventory')
  result.worn[#result.worn+1]={id=item:getID(),location=tostring(entry:getLocation())}
 end
 table.sort(result.worn,function(a,b)return a.location<b.location end)
 return result
end
return M
