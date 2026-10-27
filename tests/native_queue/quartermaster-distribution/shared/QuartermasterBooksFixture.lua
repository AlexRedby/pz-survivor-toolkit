-- Additional sort pass: existing copies and reservations for the same native transfer batch.
local F={types={'Base.BookCarpentry1','Base.BookCarpentry1','Base.BookCarpentry2','Base.BookCarpentry2','Base.BookCarpentry1'}}
function F.prepare(state)
 assert(not state.bookIds,'duplicate book preparation')
 state.bookIds={}
 for index,kind in ipairs(F.types)do
  local container=state.boxes[index==5 and 3 or 1]:getContainer()
  local item=assert(container:AddItem(kind));state.bookIds[index]=item:getID()
  if isServer()then sendAddItemToContainer(container,item)end
 end
 return {ids=state.bookIds,types=F.types}
end
function F.resolve(boxes,packet)
 for index,id in ipairs(packet.ids)do
  local item=boxes[index==5 and 3 or 1]:getContainer():getItemById(id)
  if not item then return false end
  assert(item:getFullType()==F.types[index],'unexpected native skill book full type')
 end
 return true
end
function F.receipt(player,boxes,packet)
 local containers={boxes[1]:getContainer(),boxes[2]:getContainer(),boxes[3]:getContainer(),player:getInventory()}
 local rows,destinations={},{}
 for index,id in ipairs(packet.ids)do
  local count,destination,item=0,nil,nil
  for target,container in ipairs(containers)do
   local all=container:getItems()
   for i=0,all:size()-1 do
    local candidate=all:get(i)
    if candidate:getID()==id then count=count+1;destination=target;item=candidate end
   end
  end
  assert(count<=1,'duplicated native book identity '..id)
  if count~=1 or destination==1 or destination==4 then return end
  assert(item:getFullType()==F.types[index],'book full type changed')
  destinations[index]=destination;rows[index]={id=id,fullType=item:getFullType(),container=destination}
 end
 assert(destinations[1]==2 and destinations[2]==2 and destinations[5]==3,'existing volume did not skip unique destination')
 assert(destinations[3]~=destinations[4]and destinations[3]+destinations[4]==5,
  'same-batch volume did not reserve one direct destination copy')
 local unique,fallback=boxes[3]:getModData(),boxes[2]:getModData()
 assert(unique.LSBoxNoDuplicates and unique.LSBoxNoDuplicates['0']==true,'authoritative unique flag missing')
 assert(not(fallback.LSBoxNoDuplicates and fallback.LSBoxNoDuplicates['0']),'fallback gained unique restriction')
 assert(unique.LSBoxPriority['0']==7 and fallback.LSBoxPriority['0']==5,'book destination priorities changed')
 return {ids=packet.ids,items=rows,noDuplicates=true,fallbackNoDuplicates=false,priorities={7,5},
  existingCopy=true,sameBatch=true,differentVolume=true,moved=4,conserved=5}
end
return F
