-- Disposable fixture inventory only. Native server inventory removal notices
-- address a container and numeric item ID; duplicate missing IDs are no-ops.
-- This requires a frozen ownership/generation lease until every relevant peer
-- proves absence. A normal send return proves an attempt, never delivery.
-- World-object removal packets use mutable square indices and cannot use this
-- retry contract. This module deliberately exposes no arbitrary RPC callback.
local C={}
-- Native Kahlua tables use strong Java maps and ignore __mode. Avoid any global
-- handle registry: the opaque handle's protected closure retains only its own
-- state. Ordinary cycle collection can reclaim handle/state/owner together.
local privateToken={}
local function state(j)
 assert(type(j)=='table'and getmetatable(j)=='fixture cleanup journal','invalid fixture cleanup journal')
 local s=j[privateToken]
 assert(type(s)=='table'and s.handle==j,'invalid fixture cleanup journal');return s
end
local function integer(id)return type(id)=='number'and id%1==0 and id>=-2147483648 and id<=2147483647 end
function C.new(entries,opts)
 assert(type(entries)=='table'and type(opts)=='table','fixture cleanup options missing')
 assert(type(opts.containers)=='table'and type(opts.guard)=='function'and type(opts.check)=='function'
  and type(opts.server)=='boolean','fixture cleanup lease/check/server missing')
 local j={};local s={entries={},containers={},byId={},byItem={},removed={},guard=opts.guard,check=opts.check,
  server=opts.server,removalCalls=0,noticeAttempts=0,recoveries={},failures=0,started=false}
 local controlled={}
 for _,container in ipairs(opts.containers)do
  assert(container and not controlled[container],'duplicate fixture cleanup container')
  controlled[container]=true;s.containers[#s.containers+1]=container
 end
 for _,entry in ipairs(entries)do
  assert(type(entry)=='table'and integer(entry.id)and entry.item and controlled[entry.container]
   and type(entry.ft)=='string'and entry.ft~='','invalid fixture cleanup entry')
  assert(not s.byId[entry.id]and not s.byItem[entry.item],'duplicate fixture cleanup identity')
  local copy={id=entry.id,item=entry.item,container=entry.container,ft=entry.ft,status='pending',notice=false}
  s.entries[#s.entries+1]=copy;s.byId[copy.id]=copy;s.byItem[copy.item]=copy
 end
 s.handle=j
 setmetatable(j,{__index=function(_,key)if key==privateToken then return s end end,
  __newindex=function()error('opaque fixture cleanup journal')end,__metatable='fixture cleanup journal'})
 return j
end
function C.removed(j,item)return state(j).removed[item]==true end
function C.started(j)return state(j).started end
function C.receipt(j)
 local s=state(j);local out={removedIds={},removalCalls=s.removalCalls,noticeAttempts=s.noticeAttempts,recoveries={}}
 for _,entry in ipairs(s.entries)do if s.removed[entry.item]then out.removedIds[#out.removedIds+1]=entry.id end end
 table.sort(out.removedIds)
 for _,entry in ipairs(s.recoveries)do local copy={};for k,v in pairs(entry)do copy[k]=v end;out.recoveries[#out.recoveries+1]=copy end
 return out
end
local function preflight(j,s)
 -- One scan of the entire leased namespace, including containers not holding
 -- cleanup entries. The lease guard handles foreign contents and originals.
 local found={}
 for _,container in ipairs(s.containers)do local items=container:getItems()
  for index=0,items:size()-1 do local item=items:get(index);local entry=s.byId[item:getID()]
   if entry then
    assert(item==entry.item and container==entry.container and not found[entry],
     'fixture cleanup duplicate/replaced/moved identity')
    assert(item:getContainer()==container,'fixture cleanup list/pointer mismatch');found[entry]=true
   elseif s.byItem[item]then error('fixture cleanup rebound item ID')end
  end
 end
 for _,entry in ipairs(s.entries)do
  assert(entry.item:getID()==entry.id and entry.item:getFullType()==entry.ft,'fixture cleanup identity/type changed')
  local endpoint=entry.item:getContainer()
  if found[entry]then
   assert(entry.status~='removed','removed fixture cleanup item reappeared')
  else
   assert(entry.status~='pending','fixture cleanup item missing before removal')
   assert(endpoint==nil,'fixture cleanup absent item remains attached/moved')
   entry.status='removed';s.removed[entry.item]=true
  end
 end
 -- Reconciliation precedes callbacks so their exact ownership checks can use
 -- C.removed even when native removal threw after its local mutation.
 s.guard(j)
 for _,entry in ipairs(s.entries)do s.check(entry)end
 assert(not s.poisoned,'reentrant fixture cleanup')
end
local function failed(j,s,entry,operation,problem)
 s.failures=s.failures+1
 s.recoveries[#s.recoveries+1]={operation=operation,id=entry.id,error=tostring(problem),
  failure=s.failures,publicationUncertain=operation=='notice'}
 -- Guard/check errors propagate directly; they are never treated as a native
 -- retry. Even terminal native failures reconcile their physical mutation.
 preflight(j,s)
 assert(not s.poisoned,'reentrant fixture cleanup')
 assert(s.failures<3,'fixture cleanup native failure limit reached: '..tostring(problem))
end
local function run(j,s)
 preflight(j,s)
 assert(s.failures<3,'fixture cleanup native failure limit reached')
 -- Batch local removals, then reconcile all physical state before publishing.
 -- The successful path has a bounded number of namespace scans, not one per
 -- item in a dense fixture. An error adds a full scan before any retry.
 for _,entry in ipairs(s.entries)do
  while entry.status~='removed'do
   entry.status='started';s.started=true;s.removalCalls=s.removalCalls+1
   local ok,problem=pcall(function()entry.container:Remove(entry.item)end)
   if not ok then failed(j,s,entry,'remove',problem)
   else
    assert(entry.item:getContainer()==nil,'native fixture cleanup removal left item attached')
    break
   end
  end
 end
 preflight(j,s)
 for _,entry in ipairs(s.entries)do
  assert(entry.status=='removed','native fixture cleanup removal left item present')
  while s.server and not entry.notice do
   s.noticeAttempts=s.noticeAttempts+1
   local ok,problem=pcall(sendRemoveItemFromContainer,entry.container,entry.item)
   if not ok then failed(j,s,entry,'notice',problem)else entry.notice=true end
  end
 end
 preflight(j,s);return C.receipt(j)
end
function C.run(j)
 local s=state(j)
 if s.running then s.poisoned=true;error('reentrant fixture cleanup')end
 assert(not s.poisoned,'reentrant fixture cleanup')
 s.running=true;local ok,result=pcall(run,j,s);s.running=false
 if not ok then error(result,0)end;return result
end
return C
