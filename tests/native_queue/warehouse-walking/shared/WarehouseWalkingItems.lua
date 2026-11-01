-- Native IDs are random, not unique. Allocate the entire fixture cohort while
-- detached so collisions cannot enter a container or become network-visible.
local Items={}
local attemptsPerItem=32
local function validID(id)
 return type(id)=='number'and id>=-2147483648 and id<=2147483647 and id==math.floor(id)
end
function Items.reserve(reserved,id)
 assert(type(reserved)=='table','walking item reservations missing')
 assert(validID(id),'walking native item ID is not an int32')
 reserved[id]=true
 return id
end
function Items.stage(fullType,count,reserved)
 assert(type(fullType)=='string'and fullType~='','walking item type missing')
 assert(type(count)=='number'and count>=0 and count<math.huge and count==math.floor(count),'walking item count invalid')
 assert(type(reserved)=='table','walking item reservations missing')
 -- B42 exposes this detached factory as a global LuaMethod; the Java factory
 -- class itself is not the supported Lua entry point.
 assert(type(instanceItem)=='function','walking native instanceItem factory unavailable')
 local staged={}
 for slot=1,count do
  local accepted
  for _=1,attemptsPerItem do
   local item=assert(instanceItem(fullType),'walking native item factory returned nil')
   assert(instanceof(item,'InventoryItem'),'walking factory returned a nonnative inventory item')
   assert(item:getFullType()==fullType,'walking factory returned the wrong item type')
   assert(item:getContainer()==nil,'walking factory returned an attached item')
   local id=item:getID()
   assert(validID(id),'walking native item ID is not an int32')
   if not reserved[id]then
    Items.reserve(reserved,id);staged[#staged+1]=item;accepted=true;break
   end
  end
  assert(accepted,'walking native item ID allocation exhausted at slot '..slot)
 end
 return staged
end
return Items
