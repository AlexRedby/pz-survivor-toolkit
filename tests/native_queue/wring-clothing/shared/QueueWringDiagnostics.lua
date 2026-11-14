-- Bounded failure-only observations. Never call native admission or mutate
-- queue/ledger/item state, and keep each unavailable section independently visible.
local F=require 'QueueWringClothing'
local D={}
function D.capture(player,ids,state,queue,body,tail,observations)
 local result={schema=1,case=ids and ids.case or false,sections={}}
 if observations and(not ids or observations.case~=ids.case)then observations=nil end
 local function section(name,read)
  local ok,value=pcall(read)
  if ok then
   if value==nil then value=false end
   result.sections[name]={ok=true,value=value}
  else result.sections[name]={ok=false,error=tostring(value)}end
 end
 section('prepared',function()return F.preparedDiagnostic(player,ids)end)
 section('final',function()
  if not state then return{available=false}end
  local verified,issues,snapshot=F.verify(state)
  return{available=true,ready=verified~=nil,issues=issues,snapshot=snapshot}
 end)
 section('body',function()
  if not body then return{present=false}end
  local root=player:getInventory();local item=body.item;local spec=ids.items.target
  local canonical=root:getItemById(spec.id)
  return{present=true,ref=tostring(body),type=body.Type,allocated=body.action~=nil,nativeRef=body.action and tostring(body.action)or false,
   itemRef=item and tostring(item)or false,itemId=item and item:getID()or false,itemType=item and item:getFullType()or false,
   expectedId=spec.id,expectedType=spec.type,canonicalRef=canonical and tostring(canonical)or false,
   canonicalSame=item~=nil and item==canonical,rootOwned=item~=nil and item:getContainer()==root}
 end)
 section('queue',function()
  if not queue then return{available=false}end
  local items={};local values=queue.queue
  for index=1,math.min(#values,32)do local action=values[index]
   items[#items+1]={index=index,ref=tostring(action),type=action.Type,allocated=action.action~=nil,
    current=queue.current==action,body=action==body,tail=action==tail}
  end
  return{count=#values,truncated=#values>32,current=queue.current and tostring(queue.current)or false,items=items}
 end)
 -- Production getters can retire stale bookkeeping. Report only snapshots
 -- already taken by the fixture's existing lifecycle/verification observations.
 for _,name in ipairs({'ledger','debts'})do
  section(name,function()
   return{available=observations~=nil,point=observations and observations.point or false,observedAt=observations and observations.observedAt or false,
    snapshot=observations and observations[name]or false}
  end)
 end
 return result
end
return D
