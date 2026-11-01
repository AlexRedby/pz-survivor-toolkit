-- Offline fault injection for the shared disposable inventory cleanup journal.
-- Native packet delivery and peer absence still require the live suite gates.
local C=dofile(ProjectRoot..'/tests/native_queue/support/QueueFixtureItemCleanup.lua')
local function rejected(message,fn,...)
 local ok,problem=pcall(fn,...);assert(not ok,'unsafe fixture cleanup accepted')
 assert(tostring(problem):find(message,1,true),'unexpected failure: '..tostring(problem))
end
local function container()
 local c={items={},calls=0,scans=0}
 function c:getItems()
  self.scans=self.scans+1
  return {size=function()return #self.items end,get=function(_,i)return self.items[i+1]end}
 end
 function c:Remove(item)
  self.calls=self.calls+1
  if self.before then self.before(item)end
  local found=false
  for i,value in ipairs(self.items)do if value==item then table.remove(self.items,i);item.container=nil;found=true;break end end
  assert(found,'duplicate local removal')
  if self.after then self.after(item)end
 end
 return c
end
local function item(id,c)
 local value={id=id,ft='Base.Nails',container=c,owner='phase:1'}
 function value:getID()return self.id end
 function value:getFullType()return self.ft end
 function value:getContainer()return self.container end
 if c then c.items[#c.items+1]=value end
 return value
end
local function setup(count,server)
 local c,other=container(),container();local entries={};local lease={generation=1,guards=0,checks=0}
 for i=1,count do local value=item(i,c);entries[i]={id=i,item=value,container=c,ft=value.ft}end
 local j=C.new(entries,{containers={c,other},server=server==true,guard=function(journal)
  lease.guards=lease.guards+1;assert(lease.generation==1,'generation changed')
  for _,pool in ipairs({c,other})do for _,value in ipairs(pool.items)do assert(value.owner=='phase:1','foreign content')end end
  if lease.guard then lease.guard(journal)end
 end,check=function(entry)
  lease.checks=lease.checks+1;assert(entry.item.owner=='phase:1','owner changed')
 end})
 return j,c,other,entries,lease
end
local notices={}
function sendRemoveItemFromContainer(c,value)notices[#notices+1]={container=c,item=value}end
local j,c,other,entries,lease=setup(3,true)
local receipt=C.run(j)
assert(C.started(j)and #receipt.removedIds==3 and receipt.removalCalls==3 and receipt.noticeAttempts==3 and #receipt.recoveries==0)
assert(c.calls==3 and #notices==3 and c.scans==3 and other.scans==3,'normal cleanup did not use bounded full scans')
for _,entry in ipairs(entries)do assert(C.removed(j,entry.item))end
local oldGuards=lease.guards;C.run(j)
assert(c.calls==3 and #notices==3 and lease.guards>oldGuards,'completion replay skipped fresh lease validation')
lease.generation=2;rejected('generation changed',C.run,j);assert(c.calls==3)
-- Receipts and caller entries are copies; neither can rebind the frozen work.
j,c,other,entries=setup(1,false);local exact=entries[1].item;entries[1].id=99;entries[1].item=item(99)
receipt=C.run(j);assert(receipt.removedIds[1]==1 and C.removed(j,exact))
receipt.removedIds[1]=99;assert(C.receipt(j).removedIds[1]==1)
-- Each native error is reconciled before retry. Completed local removals are
-- never repeated, including a prefix completed before another item throws.
for _,afterEffect in ipairs({false,true})do
 j,c,other,entries=setup(3,true);local once=false
 local function fault(value)if value.id==2 and not once then once=true;error('remove interruption')end end
 if afterEffect then c.after=fault else c.before=fault end
 local before=#notices;receipt=C.run(j)
 assert(c.calls==(afterEffect and 3 or 4)and #notices-before==3)
 assert(#receipt.recoveries==1 and receipt.recoveries[1].operation=='remove'and not receipt.recoveries[1].publicationUncertain)
 assert(receipt.removedIds[1]==1 and receipt.removedIds[3]==3)
end
-- Native inventory notices can fail before or after their externally visible
-- effect. Retry only that notice, preserving evidence of delivery uncertainty.
for _,afterEffect in ipairs({false,true})do
 j,c,other,entries=setup(2,true);local attempts,effects=0,0
 sendRemoveItemFromContainer=function(_,value)
  attempts=attempts+1
  if attempts==1 and not afterEffect then error('send interruption')end
  effects=effects+1;if attempts==1 then error('send interruption')end
 end
 receipt=C.run(j)
 assert(c.calls==2 and attempts==3 and effects==(afterEffect and 3 or 2))
 assert(receipt.noticeAttempts==3 and #receipt.recoveries==1 and receipt.recoveries[1].publicationUncertain)
 local copy=C.receipt(j);copy.recoveries[1].error='changed';assert(C.receipt(j).recoveries[1].error:find('send interruption',1,true))
 C.run(j);assert(c.calls==2 and attempts==3)
end
sendRemoveItemFromContainer=function()end
-- Missing identities, impostors, rebound IDs, type changes, duplicates and
-- endpoint movement are rejected before any mutation of a valid prefix.
for _,mutate in ipairs({
 function(_,c,_,e)c.items={e[2].item};e[1].item.container=nil end,
 function(_,c,_,e)local impostor=item(1);impostor.container=c;c.items[1]=impostor end,
 function(_,_,_,e)e[1].item.id=77 end,
 function(_,_,_,e)e[1].item.ft='Base.Hammer'end,
 function(_,c,_,e)c.items[#c.items+1]=e[1].item end,
 function(_,c,other,e)table.remove(c.items,1);other.items[1]=e[1].item;e[1].item.container=other end,
 function(_,_,other,e)e[1].item.container=other end,
})do
 j,c,other,entries=setup(2,false);mutate(j,c,other,entries)
 local ok=pcall(C.run,j);assert(not ok and c.calls==0 and not C.started(j),'invalid preflight mutated valid prefix')
end
-- An item missing from the list but still claiming an endpoint is not a
-- completed removal. Neither pointer repair nor notice publication is allowed.
j,c,other,entries=setup(1,true);c.after=function(value)value.container=c;error('inconsistent mutation')end
rejected('absent item remains attached',C.run,j);assert(c.calls==1 and not C.removed(j,entries[1].item))
-- A foreign item or owner drift after a partial native effect fails the next
-- full guard/check before any retry or notice, while retaining removed proof.
for _,changeOwner in ipairs({false,true})do
 j,c,other,entries,lease=setup(2,true)
 c.after=function(value)
  if changeOwner then value.owner='foreign'else item(90,other).owner='foreign'end
  error('prefix interrupted')
 end
 rejected(changeOwner and 'owner changed'or'foreign content',C.run,j)
 assert(c.calls==1 and C.removed(j,entries[1].item)and C.receipt(j).noticeAttempts==0)
end
-- The total failure budget spans local removal and notice attempts and cannot
-- reset through another C.run invocation.
j,c,other,entries=setup(1,true);local removeFault=true
c.before=function()if removeFault then removeFault=false;error('one remove failure')end end
local sends=0;sendRemoveItemFromContainer=function()sends=sends+1;error('persistent notice failure')end
rejected('native failure limit',C.run,j)
receipt=C.receipt(j);assert(c.calls==2 and sends==2 and #receipt.recoveries==3 and #receipt.removedIds==1)
rejected('native failure limit',C.run,j);assert(c.calls==2 and sends==2)
-- Reentrant entry poisons the journal even if a simulated native callback
-- swallows the nested error; it cannot turn into a successful retry.
j,c,other,entries=setup(1,false);c.before=function()pcall(C.run,j)end
rejected('reentrant fixture cleanup',C.run,j);assert(c.calls==1)
rejected('reentrant fixture cleanup',C.run,j);assert(c.calls==1)
j,c,other,entries,lease=setup(0,true);receipt=C.run(j)
assert(not C.started(j)and #receipt.removedIds==0 and receipt.removalCalls==0 and receipt.noticeAttempts==0 and lease.guards==3)
rejected('duplicate fixture cleanup identity',C.new,{{id=1,item={},container=c,ft='Base.Nails'},{id=1,item={},container=c,ft='Base.Nails'}},
 {containers={c},server=false,guard=function()end,check=function()end})
-- No module registry may retain a value -> guard -> owner -> journal cycle:
-- native Kahlua ignores weak-table __mode. A live opaque handle retains its
-- state, but dropping caller roots collects the cycle without dispose.
local weak=setmetatable({},{__mode='v'})
local function cyclicJournal()
 local owner={generation=1};local pool=container()
 owner.journal=C.new({},{containers={pool},server=false,
  guard=function()assert(owner.generation==1,'cycle owner changed')end,check=function()end})
 weak.owner=owner;weak.journal=owner.journal
 return owner.journal
end
local held=cyclicJournal()
for _=1,3 do collectgarbage('collect')end
assert(weak.owner and weak.journal==held,'held cleanup handle lost its state/owner')
assert(#C.run(held).removedIds==0 and C.receipt(held).removalCalls==0)
assert(held.entries==nil and held.guard==nil and getmetatable(held)=='fixture cleanup journal','journal exposes mutable state')
assert(next(held)==nil,'journal exposes a private state/token through raw keys')
rejected('opaque fixture cleanup journal',function()held.entries={}end)
rejected('protected metatable',setmetatable,held,{})
held=nil
for _=1,3 do collectgarbage('collect')end
assert(weak.owner==nil and weak.journal==nil,'cleanup registry retained an unreachable owner/journal cycle')
-- The source keeps the native inventory-only boundary explicit.
local file=assert(io.open(ProjectRoot..'/tests/native_queue/support/QueueFixtureItemCleanup.lua','r'));local source=file:read('*a');file:close()
assert(source:find('normal send return proves an attempt, never delivery',1,true))
assert(not source:find('transmitRemoveItemFromSquare',1,true)and not source:find('sendClientCommand',1,true))
assert(not source:find('__mode=',1,true),'native Kahlua does not implement weak-table registries')
print('shared fixture item cleanup: PASS')
