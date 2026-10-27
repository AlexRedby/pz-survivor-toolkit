if not NativeActionRoot then print('Pending grooming contracts SKIP.');return end
GroomingNativeSetupOnly=true
local setup=assert(loadfile(ProjectRoot..'/tests/test_action_queue_grooming_active.lua'))()
GroomingNativeSetupOnly=nil
local function pending(kind,options)
 options=options or{};options.pending=true;options.style=options.style or'CrewCut'
 local s=setup(kind,false,options)
 local front=s.f.action(ISReadABook,{item=s.f.item('Base.BookCarpentry1')})
 s.queue=s.f.queue(front,s.tail,s.body);s.front=front
 return s
end
for _,kind in ipairs({'ISCutHair','ISTrimBeard'})do
 local s=pending(kind);local c=assert(s.policy.inspect(s.body))
 assert(c.knownInputs and c.hands==s.player and c.equipment==s.player and c.targets[s.player]
  and c.items[s.tool:getID()]and c.capacityNonIncreasing and c.edit==nil,'complete conservative pending footprint missing')
 local accepted,reason=s.api.move(s.queue,s.body,s.tail,false)
 assert(accepted,'independent pending grooming move rejected: '..tostring(reason))
 assert(s.queue.queue[1]==s.front and s.queue.queue[2]==s.body and s.queue.queue[3]==s.tail,'native current or group order changed')
 assert(not s.body.action and not s.native.stopping,'pending move allocated or stopped native work')
 assert(s.api.move(s.queue,s.body,s.tail,true),'reverse independent move rejected')
 assert(s.queue.queue[2]==s.tail and s.queue.queue[3]==s.body,'reverse pending move lost work')
 -- A separate native use of the same tool is a real ordered prerequisite.
 local same=s.f.action(ISReadABook,{item=s.tool});s.queue=s.f.queue(s.front,same,s.body)
 assert(not s.api.move(s.queue,s.body,same,false),'shared tool prerequisite was detached')
 s.queue=s.f.queue(s.front,s.body,same)
 assert(not s.api.move(s.queue,s.body,same,true),'shared tool consumer was crossed in reverse')
end
print('PASS plain pending haircut/beard moves in both directions around unrelated work, exact shared tools stay ordered')
for _,style in ipairs({'MohawkFan','Spike','GreasedBack','GreasedSide','Buffont','Missing'})do
 local s=pending('ISCutHair',{style=style})
 assert(not s.policy.inspect(s.body).knownInputs and not s.api.move(s.queue,s.body,s.tail,false),'dynamic/invalid haircut got a complete footprint: '..style)
end
for _,kind in ipairs({'ISCutHair','ISTrimBeard'})do
 for _,mutation in ipairs({'base-helper','new-base-helper','instance-helper','pending-helper','pending-owner','pending-adoption','parent-server-hook','native-global','global-classifier','stale-tool','missing-source','callback-container','started-token','native-episode','native-receipt','debug-time'})do
  local s=pending(kind)
  if mutation=='base-helper'then ISBaseTimedAction.getJobDelta=function()end
  elseif mutation=='new-base-helper'then ISBaseTimedAction.foreignHelper=function()end
  elseif mutation=='instance-helper'then s.body.setActionAnim=function()end
  elseif mutation=='pending-helper'then PZSurvivorToolkit.ActionQueueGroomingPending.apply=function()error('foreign proof callback executed')end
  elseif mutation=='pending-owner'then PZSurvivorToolkit.ActionQueueGroomingPending={}
  elseif mutation=='pending-adoption'then PZSurvivorToolkit.ActionQueueGroomingPending.adoptBase=function()end
  elseif mutation=='parent-server-hook'then ISBaseObject.serverStart=function()end
  elseif mutation=='native-global'then getHairStylesInstance=function()end
  elseif mutation=='global-classifier'then s.javaGlobals[getClassSimpleName]=nil
  elseif mutation=='stale-tool'then s.tool.present=false
  elseif mutation=='missing-source'then s.player.inventory.live=false
  elseif mutation=='callback-container'then s.player.inventory.accept='foreignAccept'
  elseif mutation=='started-token'then s.body.toolkitQueueOperation.toolkitStarted=true
  elseif mutation=='native-episode'then s.body.action=s.native
  elseif mutation=='native-receipt'then s.body.toolkitNativeTransaction=7
  elseif mutation=='debug-time'then s.body.maxTime=10;s.body.maxTimeInit=10 end
  local c=s.policy.inspect(s.body)
  assert(not c or not c.knownInputs,'unknown/started pending footprint admitted: '..kind..' '..mutation)
  assert(not s.api.move(s.queue,s.body,s.tail,false),'unknown/started pending move admitted: '..kind..' '..mutation)
 end
end
local dye=pending('ISDyeHair')
assert(not dye.policy.inspect(dye.body).knownInputs and not dye.api.move(dye.queue,dye.body,dye.tail,false),'unproved dye-fluid effects gained move permission')
local tie=pending('ISCutHair',{style='PonyTail',duration=100});tie.body.item=nil
assert(tie.policy.inspect(tie.body).knownInputs and tie.api.move(tie.queue,tie.body,tie.tail,false),'native no-tool tie was not independent')
local untie=pending('ISCutHair',{style='CrewCut',duration=100,untie='CrewCut'});untie.body.item=nil
assert(untie.policy.inspect(untie.body).knownInputs,'captured native no-tool untie was not supported')
local invalid=pending('ISCutHair');invalid.body.item=nil
assert(not invalid.policy.inspect(invalid.body).knownInputs,'ordinary no-tool cut bypassed native preparation')
print('PASS native inheritance/global/tool/episode guards, unknown styling/dye protection and exact no-tool tie/untie boundary')

for _,reverse in ipairs({false,true})do
 local s=pending('ISCutHair')
 local other=ISTrimBeard:new(s.player,'Moustache',s.f.item('Base.Razor'));other.toolkitQueueOperation={}
 s.queue=reverse and s.f.queue(s.front,s.body,other)or s.f.queue(s.front,other,s.body)
 assert(not s.api.move(s.queue,s.body,other,reverse),'shared cosmetic/equipment state was reordered')
end
print('PASS actor cosmetic/equipment dependencies remain ordered in both directions without a projected result claim')

if NativeWishlistWorkshopRoot then
 local bc=pending('ISCutHair',{bcText=true})
 assert(bc.policy.inspect(bc.body).knownInputs and bc.api.move(bc.queue,bc.body,bc.tail,false),'actual late BC text resolver blocked an independent pending cut')
 PZSurvivorToolkit.TextResolverProof.matches=function()error('foreign text proof called')end
 assert(not bc.policy.inspect(bc.body).knownInputs,'modified text proof retained pending permissions')
 print('PASS actual late BC text installation preserves pending grooming rights; replacing its proof closes admission')
end

local completedUntie=pending('ISCutHair',{style='CrewCut',duration=100,untie='CrewCut',effects=true});completedUntie.body.item=nil
assert(completedUntie.api.move(completedUntie.queue,completedUntie.body,completedUntie.tail,false),'captured untie did not move independently')
assert(not completedUntie.player.modelResets and not completedUntie.player.growthResets and not completedUntie.player.visualSync,'inspection or move executed cosmetic effects')
string.contains=string.contains or function(value,part)return value:find(part,1,true)~=nil end
assert(completedUntie.body:complete(),'unchanged native untie did not complete')
local appearance=completedUntie.player:getHumanVisual()
assert(appearance.model=='CrewCut'and appearance.nonAttached==nil and completedUntie.player.modelResets==1
 and completedUntie.player.growthResets==1 and completedUntie.player.visualSync==1,'native untie lost captured style, attachment cleanup or growth/model synchronization')
print('PASS actual native untie completion retains captured target, clears attachment and resets/synchronizes once; inspection executes no effects')
