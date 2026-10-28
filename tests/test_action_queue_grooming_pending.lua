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
for _,beard in ipairs({false,true})do
 for _,amount in ipairs({1,.25})do
  local dye=pending('ISDyeHair',{effects=true,amount=amount});dye.body.beard=beard
  assert(dye.policy.inspect(dye.body).knownInputs,'exact live dye-fluid footprint missing')
  assert(dye.api.move(dye.queue,dye.body,dye.tail,false),'independent dye move rejected')
  assert(dye.api.move(dye.queue,dye.body,dye.tail,true),'reverse independent dye move rejected')
  assert(not dye.player.fluidChanges and not dye.player.visualSync and not dye.player.itemSync and not dye.player.events,'dye inspection ran effects')
  local use=dye.f.action(ISReadABook,{item=dye.tool})
  dye.queue=dye.f.queue(dye.front,use,dye.body)
  assert(not dye.api.move(dye.queue,dye.body,use,false),'shared dye resource crossed')
  dye.queue=dye.f.queue(dye.front,dye.body,use)
  assert(not dye.api.move(dye.queue,dye.body,use,true),'shared dye resource crossed in reverse')
  assert(dye.body:complete(),'actual native dye completion failed')
  local visual=dye.player:getHumanVisual()
  assert((beard and visual.beardColor or visual.hairColor).r==.2 and (beard and not visual.hairColor or not beard and not visual.beardColor),'dye changed wrong cosmetic field')
  assert(dye.tool:getFluidContainer():getAmount()==math.max(0,amount-.5)and dye.player.fluidChanges==1
   and dye.player.itemSync==1 and dye.player.visualSync==1 and dye.player.modelResets==1 and dye.player.events==1,'native dye cost/result synchronization changed')
 end
end
for _,mutation in ipairs({'empty','negative','nan','infinite','overfull','foreign-fluid','stats','constructor','color-owner','debug','beard-target','missing-dye','wrong-slot'})do
 local s=pending('ISDyeHair');local fluid=s.tool:getFluidContainer()
 if mutation=='empty'then fluid.amount=0
 elseif mutation=='negative'then fluid.amount=-1
 elseif mutation=='nan'then fluid.amount=0/0
 elseif mutation=='infinite'then fluid.capacity=math.huge
 elseif mutation=='overfull'then fluid.amount=2
 elseif mutation=='foreign-fluid'then fluid.kind='Unknown'
 elseif mutation=='stats'then sendItemStats=function()error('foreign stats executed')end
 elseif mutation=='constructor'then ImmutableColor.new=function()error('foreign color executed')end
 elseif mutation=='color-owner'then ImmutableColor={new=ImmutableColor.new}
 elseif mutation=='debug'then s.body.maxTime=1
 elseif mutation=='beard-target'then s.body.beard='foreign'
 elseif mutation=='missing-dye'then s.body.hairDye=nil
 elseif mutation=='wrong-slot'then s.body.hairDye=nil;s.body.item=s.tool end
 local c=s.policy.inspect(s.body)
 assert(not c or not c.knownInputs,'unproved dye gained footprint: '..mutation)
 assert(not s.api.move(s.queue,s.body,s.tail,false),'unproved dye moved: '..mutation)
end
print('PASS exact pending dye resources move in both directions; native full/partial hair/beard costs and synchronization unchanged, unknown inputs remain protected')
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

for _,style in ipairs({'MohawkFan','GreasedBack','Buffont','GreasedSide'})do
 local s=pending('ISCutHair',{style=style,styling=true})
 local context={contracts={},items={}}
 local c=assert(s.policy.inspect(s.body,context))
 assert(c.knownInputs and c.dynamicInputsByType,'complete styling selector footprint missing: '..style..' '..tostring(c.pendingMoveBlocker))
 if style=='MohawkFan'or style=='GreasedBack'then
  local reads=s.player.catalogReads
  local second=ISCutHair:new(s.player,style,s.tool,300);second.toolkitQueueOperation={}
  assert(s.policy.inspect(second,context).knownInputs and s.player.catalogReads==reads,'Definitions discarded shared evaluation context or cached live material incorrectly')
  assert(s.policy.inspect(second,{contracts={},items={}}).knownInputs and s.player.catalogReads==reads+1,'new evaluation reused stale script metadata')
 end
 assert(s.api.move(s.queue,s.body,s.tail,false),'independent paid style did not move: '..style)
 assert(s.api.move(s.queue,s.body,s.tail,true),'reverse paid style did not move: '..style)
 local gel=s.f.item(style=='Buffont'and'Base.Hairspray2'or'Base.Hairgel');local other=s.f.action(ISReadABook,{item=gel})
 s.queue=s.f.queue(s.front,other,s.body);assert(not s.api.move(s.queue,s.body,other,false),'late styling input crossed')
 s.queue=s.f.queue(s.front,s.body,other);assert(not s.api.move(s.queue,s.body,other,true),'late styling input crossed in reverse')
 if style=='MohawkFan'or style=='GreasedBack'then
  local wax=s.f.item('Mod.StyleWax');other=s.f.action(ISReadABook,{item=wax})
  s.queue=s.f.queue(s.front,other,s.body);assert(not s.api.move(s.queue,s.body,other,false),'future tagged input absent at admission was ignored')
  s.queue=s.f.queue(s.front,s.body,other);assert(not s.api.move(s.queue,s.body,other,true),'future tagged input crossed in reverse')
 end
end
for _,mutation in ipairs({'owner','apply'})do
 local s=pending('ISCutHair',{style='MohawkFan',styling=true})
 if mutation=='owner'then PZSurvivorToolkit.ActionQueueGroomingCosts={}
 else PZSurvivorToolkit.ActionQueueGroomingCosts.apply=function()error('foreign cost proof executed')end end
 assert(not s.policy.inspect(s.body).knownInputs and not s.api.move(s.queue,s.body,s.tail,false),'changed styling proof retained move permission')
end
print('PASS actual styling helper integration and late full-type/tag selector dependencies in both directions; foreign proof APIs never execute')

local function heldStyle(style,kind,hand,uses)
 local s=pending('ISCutHair',{style=style,styling=true,stylingKind=kind,stylingUses=uses})
 local supply=assert(s.stylingSupply)
 if hand~='secondary'then s.player.primary=supply end
 if hand~='primary'then s.player.secondary=supply end
 supply.equipParent=s.player
 assert(type(s.supplyUse)=='table'and s.sourceProof.closure(s.supplyUse.supportsRetainedHeld,'DrainableSupplyUse.lua'),
  'held styling integration did not load the actual shared native-state proof')
 return s,supply
end
local function noStyleEffects(s,supply,uses,primary,secondary)
 assert(supply.uses==uses and supply:getContainer()==s.player:getInventory()and supply.equipParent==s.player
  and s.player.primary==primary and s.player.secondary==secondary and not s.tool.delta
  and not s.player.modelResets and not s.player.growthResets and not s.player.visualSync
  and not s.player.itemSync and not s.player.events,'pending held styling inspection executed effects or changed ownership')
end
for _,spec in ipairs({{'MohawkFan','Base.Hairgel','primary',2},{'MohawkFan','Base.Hairgel','both',2},
 {'Buffont','Base.Hairspray2','secondary',2},{'GreasedBack','Base.Hairgel','both',3}})do
 local s,supply=heldStyle(unpack(spec));local primary,secondary=s.player.primary,s.player.secondary
 local c=assert(s.policy.inspect(s.body))
 assert(c.knownInputs and c.items[supply:getID()]and c.itemTypes[supply:getFullType()]and c.hands==s.player
  and c.equipment==s.player and c.targets[s.player]and c.capacityNonIncreasing,'held supply lost conservative resource/actor footprint')
 assert(s.api.move(s.queue,s.body,s.tail,false),'retained held styling cannot move earlier around independent reader')
 assert(s.api.move(s.queue,s.body,s.tail,true),'retained held styling cannot move later around independent reader')
 noStyleEffects(s,supply,spec[4],primary,secondary)
 assert(s.policy.evaluateCancel(s.queue,s.body).allowed,'retained held style lost unpaid pending cancellation')
end
for _,spec in ipairs({{'MohawkFan','Base.Hairgel',1,2},{'Buffont','Base.Hairspray2',1,2},{'GreasedBack','Base.Hairgel',2,3}})do
 for _,uses in ipairs({spec[3],spec[4]})do
  local s,supply=heldStyle(spec[1],spec[2],'primary',uses)
  local expected=uses==spec[4];local c=assert(s.policy.inspect(s.body))
  assert(c.knownInputs==expected,'held styling did not reserve the entire native branch budget: '..spec[1]..' '..uses)
  assert(s.api.move(s.queue,s.body,s.tail,false)==expected,'held style crossed its depletion budget boundary')
  assert(s.policy.evaluateCancel(s.queue,s.body).allowed,'depletion budget refusal disabled unpaid cancellation')
  noStyleEffects(s,supply,uses,supply,nil)
 end
end
for _,resource in ipairs({'same-supply','future-short-type','future-tag-type','hands','equipment','actor'})do
 for _,reverse in ipairs({false,true})do
  local s,supply=heldStyle('GreasedBack','Base.Hairgel','primary',3)
  assert(s.policy.inspect(s.body).knownInputs,'valid held style missing before dependency check')
  local other=s.f.action(ISBaseTimedAction,{Type='HeldStylingDependency'})
  local c={items={},itemTypes={},targets={},knownInputs=true}
  if resource=='same-supply'then c.items[supply:getID()]=true
  elseif resource=='future-short-type'then c.outputTypes={['Mod.Hairgel']=true}
  elseif resource=='future-tag-type'then c.outputTypes={['Mod.StyleWax']=true}
  elseif resource=='hands'then c.hands=s.player
  elseif resource=='equipment'then c.equipment=s.player
  else c.targets[s.player]=true end
  PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('test.held-styling-dependency',{
   types={'HeldStylingDependency'},matches=function(action)return action==other end,inspect=function()return c end})
  s.queue=reverse and s.f.queue(s.front,s.body,other)or s.f.queue(s.front,other,s.body)
  assert(not s.api.move(s.queue,s.body,other,reverse),'held style crossed '..resource..' in '..tostring(reverse))
  noStyleEffects(s,supply,3,supply,nil)
 end
end
for _,mutation in ipairs({'helper','module-metatable','components','replacement','script-components','script-create','equip-parent',
 'worn','activated','attached','auto-equipped','auto-unequipped','fractional','other-hand-source'})do
 local s,supply=heldStyle('GreasedBack','Base.Hairgel','primary',3)
 assert(s.policy.inspect(s.body).knownInputs,'held styling proof failed before mutation')
 if mutation=='helper'then s.supplyUse.supportsRetainedHeld=function()error('foreign retained-held helper executed')end
 elseif mutation=='module-metatable'then setmetatable(s.supplyUse,{})
 elseif mutation=='components'then supply.components=true
 elseif mutation=='replacement'then supply.replacement='Base.Unknown'
 elseif mutation=='script-components'then supply:getScriptItem().components=true
 elseif mutation=='script-create'then supply:getScriptItem().luaCreate='Unknown.Callback'
 elseif mutation=='equip-parent'then supply.equipParent={}
 elseif mutation=='worn'then s.player.worn.back=supply
 elseif mutation=='activated'then supply.activated=true
 elseif mutation=='attached'then supply.attachedSlot=0
 elseif mutation=='auto-equipped'then supply.autoEquipped=true
 elseif mutation=='auto-unequipped'then supply.autoUnequipped=true
 elseif mutation=='fractional'then supply.uses=3.5
 elseif mutation=='other-hand-source'then
  local other=s.f.item('Base.Hammer');other.equipParent=s.player;other.container={};s.player.secondary=other
 end
 local c=assert(s.policy.inspect(s.body))
 assert(not c.knownInputs and c.cancelWaiting,'unproved held styling gained a complete contract: '..mutation)
 assert(not s.api.move(s.queue,s.body,s.tail,false),'unproved held styling moved: '..mutation)
 assert(s.policy.evaluateCancel(s.queue,s.body).allowed,'unproved held styling lost pending cancellation: '..mutation)
 assert(supply.uses==(mutation=='fractional'and 3.5 or 3)and not s.player.itemSync and not s.player.visualSync,
  'rejected held styling consumed or synchronized supplies')
end
print('PASS real shared root-held drainable integration, whole styling budgets, read-only proof, material/actor dependencies in both directions and fail-closed state/API guards')

local female=pending('ISCutHair',{female=true,maleOnlyStyle=true})
assert(not female.policy.inspect(female.body).knownInputs and not female.api.move(female.queue,female.body,female.tail,false),'unavailable female style fell back to male catalog')
local validFemale=pending('ISCutHair',{female=true})
assert(validFemale.policy.inspect(validFemale.body).knownInputs and validFemale.api.move(validFemale.queue,validFemale.body,validFemale.tail,false),'valid female style lost native eligibility')
print('PASS unavailable female style cannot borrow a male target; valid female metadata retains pending support')
