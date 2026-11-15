-- Source-owner test. The effect provider below is an explicit test double:
-- it proves the Equip boundary, not selected-mod neutrality or live Host.
if not NativeActionRoot then
 if TestCoverage then TestCoverage('source-contract','skipped','Equip source owner requires --game or --native-action-root.')end
 return
end
NativeKahluaTableLookup=true
local setup=assert(loadfile(ProjectRoot..'/tests/support/queue_equip.lua'))()
-- Native-schedule permission is not a renamed SP effect certificate. It
-- reads only the incoming canonical root item and leaves native hooks alone.
do
 local s=setup(nil,true);s.mode(true,false)
 local incoming=s.item();local action=s.action(incoming,true,false)
 s.actor.primary={};s.actor.secondary={};s.actor.back={}
 local contract=assert(s.owner.inspect(action),'ordinary unsubmitted Host Equip rejected')
 assert(contract.nativeSchedule=='unsubmitted'and contract.unknownOutputs==true and contract.edit==nil)
 assert(contract.moveRequiresProjection and contract.cancelWaiting and contract.cancelOperation)
 assert(s.certificate.requests==0 and s.certificate.checks==0 and s.certificate.quietItems[1]==incoming and s.effects()==0)
 assert(contract.items[incoming:getID()]and not action.action,'native schedule performed an action')
 s.certificate.quiet=false;assert(not s.owner.inspect(action),'extra native components accepted')
 s.certificate.quiet=true
 s.certificate.quietCallback=function()action.item=s.item()end
 assert(not s.owner.inspect(action),'reentrant native metadata replaced the scheduled item')
end
for _,change in ipairs({
 function(s,a)a.action={}end,function(s,a)a.started=true end,function(s,a)a.toolkitNativeTransaction=1 end,
 function(s,a)a.toolkitQueueReturn=true end,function(s,a)a.toolkitQueueLinked=true end,
 function(s,a)a.onCancelFunc=function()error('must not execute')end end,
 function(s,a)a.item.container={}end,function(s,a)s.root.items[a.item:getID()]={}end,
 function(s,a)a.item.heavy=true end,function(s,a)a.item.activation=true end,
 function(s,a)s.mode(true,true)end,
})do
 local s=setup(nil,true);s.mode(true,false);local action=s.action(s.item(),true,false);change(s,action)
 assert(not s.owner.inspect(action),'unsupported Host native-schedule source admitted')
 assert(s.certificate.requests==0 and s.effects()==0)
end
local function handResource(contract)
 for _,resource in ipairs(contract.edit.resources)do if resource.domain=='hands'then return resource end end
 error('missing hand resource')
end
for _,mode in ipairs({'primary','secondary','both'})do
 local s=setup();local held=s.item();s.actor.primary=held;s.actor.secondary=held
 local incoming=s.item('HandWeapon',mode=='both',mode=='primary')
 local action=s.action(incoming,mode=='primary',mode=='both')
 local contract=assert(s.owner.inspect(action),'ordinary native equip rejected: '..mode)
 assert(contract.hands==s.actor and contract.equipment==s.actor and contract.moveRequiresProjection)
 assert(contract.preparation and contract.preparationFinish and contract.cancelOperation and contract.cancelWaiting)
 assert(not contract.cancelTailOnly and contract.interrupt=='finish-step'and contract.edit.complete and contract.edit.capacity=='external')
 assert(contract.items[incoming:getID()]and contract.items[held:getID()])
 for _ in pairs(contract.targets)do error('unexpected target footprint')end
 assert(#contract.edit.resources==3 and #s.certificate.items==2,'same-object hands produced duplicate item resources')
 assert(s.certificate.actor==s.actor and s.certificate.checks>=2 and s.certificate.requests==1)
 assert(handResource(contract).facts.primary==held and handResource(contract).facts.secondary==held)
 assert(s.effects()==0 and s.actor.primary==held and s.actor.secondary==held and not action.action,'inspection executed native effects')
 action.action={};assert(not s.owner.inspect(action),'active native action gained pending edit authority')
end
-- Initial dependency collection and final revalidation must read native item
-- facts in the same order, including duplicate hand identities. The final pass
-- must short-circuit at a newly disallowed fact before querying later branches.
for _,changed in ipairs({false,true})do
 local s=setup();local incoming=s.item('HandWeapon');local held=s.item('HandWeapon')
 s.actor.primary=held;s.actor.secondary=held;local action=s.action(incoming,true,false)
 local phase='initial';local traces={initial={},stable={}}
 local function record(item,name)
  local list=traces[phase][item]or{};traces[phase][item]=list;list[#list+1]=name
 end
 for _,item in ipairs({incoming,held})do
  for _,name in ipairs({'getID','getFullType','getContainer','getAttachedSlot','isForceDropHeavyItem','canBeActivated',
   'getWorldItem','getIsCraftingConsumed','hasTag','isRequiresEquippedBothHands','getSwingAnim','isTwoHandWeapon'})do
   local previous=item[name]
   item[name]=function(self,...)record(self,name);return previous(self,...)end
  end
 end
 local lookup=s.root.getItemWithID
 s.root.getItemWithID=function(self,id)local item=self.items[id];record(item,'lookup');return lookup(self,id)end
 local worn=s.actor.isEquippedClothing
 s.actor.isEquippedClothing=function(self,item)record(item,'isEquippedClothing');return worn(self,item)end
 s.certificate.before=function()phase='stable';if changed then incoming.activation=true end end
 local contract=s.owner.inspect(action)
 local facts='getID,getFullType,getContainer,lookup,getAttachedSlot,isForceDropHeavyItem,canBeActivated,getWorldItem,getIsCraftingConsumed,hasTag,hasTag,isEquippedClothing,isRequiresEquippedBothHands,getSwingAnim'
 local location='getID,getFullType,getContainer,lookup'
 assert(table.concat(traces.initial[incoming],',')==facts..',isTwoHandWeapon,getFullType','initial incoming fact order changed')
 assert(table.concat(traces.initial[held],',')==facts..','..facts..',getFullType','duplicate hand fact order changed')
 if changed then
  assert(not contract,'revalidation accepted a newly activatable item')
  assert(table.concat(traces.stable[incoming],',')==location..',getID,getFullType,getContainer,lookup,getAttachedSlot,isForceDropHeavyItem,canBeActivated',
   'revalidation did not stop at the first rejected native fact')
  assert(table.concat(traces.stable[held],',')==location,'revalidation continued into later hand facts after rejection')
 else
  assert(contract,'traced ordinary native equip rejected')
  assert(table.concat(traces.stable[incoming],',')==location..','..facts..',isTwoHandWeapon','incoming revalidation read order changed')
  assert(table.concat(traces.stable[held],',')==location..','..facts..','..facts,'duplicate hand revalidation read order changed')
 end
end
-- Every declaration starts from the same live snapshot. Later conditional hand
-- reads must use projected state, including traits and shared hand identities.
do
 local s=setup();local held=s.item('HandWeapon',true);s.actor.primary=held;s.actor.secondary=held
 local a=s.item('HandWeapon',false,true);local b=s.item('HandWeapon');local c=s.item()
 local actions={s.action(a,true,false),s.action(b,false,false),s.action(c,true,false)}
 local entries={}
 for _,action in ipairs(actions)do entries[#entries+1]={action=action,edit=assert(s.owner.inspect(action)).edit}end
 local function probe(primary,secondary)
  return {action={},edit={version=1,complete=true,capacity='external',resources={{domain='hands',key=s.actor,
   facts=handResource(assert(s.owner.inspect(actions[1]))).facts,
   requires={{field='primary',equal=primary},{field='secondary',equal=secondary}}}}}}
 end
 entries[#entries+1]=probe(c,b)
 assert(s.model.evaluate(entries).status=='allowed','pending chain failed to project handgun clearing and later equip')
 entries[1].snapshotOnly=true
 assert(s.model.evaluate(entries).status=='allowed','removed first assignment still altered surviving chain')
 entries[2].snapshotOnly=true;entries[#entries]=probe(c,false)
 assert(s.model.evaluate(entries).status=='allowed','surviving first one-hand action ignored required-both clearing')
 assert(s.actor.primary==held and s.actor.secondary==held and s.effects()==0)
end
do
 local s=setup();local back=s.item('InventoryContainer');s.actor.back=back
 back.getClothingItemExtra=function()error('back extra getter executed')end
 local action=s.action(s.item(),true,false);local contract=assert(s.owner.inspect(action),'ordinary inert back item rejected')
 assert(not contract.items[back:getID()]and contract.locationReads[back:getID()]
  and contract.itemTypes[back:getFullType()]and contract.equipment==s.actor and #contract.edit.resources==3)
 assert(#s.certificate.items==1,'worn backpack was passed as a hand-transition input')
 back.tags={[ItemTag.REPLACE_PRIMARY]=true}
 assert(not s.owner.inspect(action),'replace-primary back branch gained contract')
end
-- Actual shared Policy routing uses the new source owner, while the effect
-- provider remains the explicit double above. No native effect is executed.
-- A carried child's return and the ordinary Pen's Back location read commute.
-- The loan itself is earned through the real Settlement native-effect model;
-- moving the owner or using the same child still retains the dependency fence.
for _,conflict in ipairs({'none','owner','child'})do
 local s=setup();local back=s.item('InventoryContainer');s.actor.back=back
 s.f.native('client/TimedActions/ISInventoryTransferAction.lua')
 getTimestampMs=function()return 100 end
 local bag={class='ItemContainer',items={},getParent=function()end,getContainingItem=function()return back end,
  getAcceptItemFunction=function()end,isExistYet=function()return true end}
 bag.getItemById=function(self,id)return self.items[id]end
 back.getInventory=function()return bag end;back.getItemContainer=back.getInventory
 s.root.getItemById=s.root.getItemWithID;s.root.isExistYet=function()return true end
 s.root.getAcceptItemFunction=function()end
 for _,container in ipairs({s.root,bag})do
  container.getType=function()return'none'end;container.getOnlyAcceptCategory=function()end
 end
 s.actor.getOnlineID=function()return 10 end
 s.actor.isLocalPlayer=function()return true end
 s.f.project('ActionQueueOperations');s.f.project('ActionQueueDefinitions')
 local policy=s.f.project('ActionQueuePolicy');local settlement=s.f.project('ActionQueueSettlement')
 local bulk=s.f.project('BulkActions');s.f.project('ActionQueueExecution')
 local book=s.item();book.getType=function()return'BookCarpentry1'end
 book.getFullType=function()return'Base.BookCarpentry1'end
 s.root.items[book:getID()]=nil;book.container=bag;bag.items[book:getID()]=book
 local pickup=s.f.action(ISInventoryTransferAction,{item=book,srcContainer=bag,destContainer=s.root,
  queueList={{items={book}}},transactionId=0,action={}})
 local reader=s.f.action(ISReadABook,{item=book,action={isStarted=function()return true end,
  finished=function()return false end,isForceComplete=function()return false end}})
 reader.toolkitQueueOperation=pickup.toolkitQueueOperation
 pickup.toolkitQueueOperation.toolkitPickups={[book]=bag}
 local returned=s.f.action(ISInventoryTransferAction,{item=book,srcContainer=s.root,destContainer=bag,allowMissingItems=true,
  queueList={{items={book}}},transactionId=0})
 returned.toolkitQueueOperation=pickup.toolkitQueueOperation
 bulk.guardTransfer(returned)
 local equip=s.action(conflict=='child'and book or s.item(),true,false)
 local q=s.f.queue(pickup,reader,returned,equip)
 local scope=settlement.deferred(s.actor,pickup.toolkitQueueOperation)
 assert(settlement.remember(scope,pickup,{items={[book:getID()]=true}}))
 assert(settlement.preparePickup(scope,pickup))
 assert(settlement.beginPickup(scope,pickup,function()return true end))
 book.container=s.root;bag.items[book:getID()]=nil;s.root.items[book:getID()]=book;pickup.queueList={}
 assert(settlement.finishPickup(scope,pickup,true),'fixture failed to earn its exact native pickup')
 settlement.poll(scope)
 table.remove(q.queue,1);q.current=reader
 settlement.track(reader,'body');settlement.track(returned,'body');settlement.track(equip,'body')
 if conflict=='owner'then
  local destination={class='ItemContainer',getParent=function()end,getContainingItem=function()end,getAcceptItemFunction=function()end}
  q.queue[4]=s.f.action(ISInventoryTransferAction,{item=back,srcContainer=s.root,destContainer=destination})
 end
 local eligible=policy.returnFailureIndependent(q,returned)
 assert(eligible==(conflict=='none'),'return failure isolation lost its typed owner dependency: '..conflict)
 local whole=policy.evaluateCancel(q,reader,true)
 assert(whole.allowed==(conflict=='none'),'whole book cancellation lost its typed owner dependency: '..tostring(whole.reason))
 if conflict~='owner'then
  local available,detail=settlement.canWaivePendingReturn(returned,function()return true end)
  local view=settlement.operationState(reader)
  assert(available,'fixture pending loan unavailable: '..tostring(detail)..'/'..tostring(view.borrowings[1].state)..'/'..tostring(view.steps[1].state))
  local decision=policy.evaluateCancel(q,returned,false)
  assert(decision.allowed==(conflict=='none'),'pending Keep lost its exact child/owner footprint: '..tostring(decision.reason))
  if decision.allowed then
   assert(policy.commitReturnCancellation(returned,decision.returnWaiver),'earned Keep did not commit its private capability')
   assert(settlement.operationState(reader).borrowings[1].state=='waived'and q.current==reader
    and not reader.toolkitQueueOperation.toolkitCancelled,'Keep changed its reading body or retained unpaid debt')
  end
 end
 assert(s.actor.back==back and back:getContainer()==s.root and book:getContainer()==s.root and s.effects()==0)
end
do
 local s=setup()
 s.f.project('ActionQueueOperations');s.f.project('ActionQueueDefinitions')
 local policy=s.f.project('ActionQueuePolicy')
 s.f.project('ActionQueueLabels');local api=s.f.project('ActionQueue')
 local front=s.f.action(ISReadABook,{item=s.item()})
 local a=s.action(s.item(),true,false);local b=s.action(s.item(),false,false)
 local q=s.f.queue(front,a,b)
 local contract=assert(policy.inspect(a))
 assert(contract.edit and contract.moveRequiresProjection and contract.cancelWaiting and not contract.cancelTailOnly,
  'Policy did not use the complete pending Equip source owner')
 local move=policy.evaluateMove(q,b,a,false)
 assert(move.allowed,'independent pending Equip move denied: '..tostring(move.reason))
 local cancel=policy.evaluateCancel(q,a)
 assert(cancel.allowed,'pending Equip cancellation before surviving suffix denied: '..tostring(cancel.reason))
 assert(api.cancel(q,a)and #q.queue==2 and q.queue[1]==front and q.queue[2]==b and s.effects()==0,
  'real Queue did not erase only the qualified pending operation')
end
-- The full Host policy uses actual private enqueue/started history, then the
-- real Queue API changes only the unsubmitted order. No effect certificate,
-- server result or synthetic native action is supplied for the pending rows.
local function hostQueue()
 local s=setup(nil,true);s.mode(true,false)
 s.f.project('ActionQueueOperations');s.f.project('ActionQueueDefinitions')
 local policy=s.f.project('ActionQueuePolicy');s.f.project('ActionQueueLabels');local api=s.f.project('ActionQueue')
 local front=s.f.action(ISReadABook,{item=s.item()});local tail=s.f.action(ISReadABook,{item=s.item()})
 local a=s.action(s.item(),true,false);local b=s.action(s.item(),false,false)
 local q=s.f.queue(front,a,b,tail);local ledger=PZSurvivorToolkit.ActionQueueSettlement
 for _,member in ipairs(q.queue)do assert(ledger.track(member,'body'))end
 ledger.started(front);front.toolkitQueueOperation.toolkitStarted=true;front.action={}
 return s,policy,api,q,front,a,b,tail,ledger
end
do
 local s,policy,api,q,front,a,b,tail=hostQueue()
 local move=policy.evaluateMove(q,b,a,false)

 assert(move.allowed and move.nativeSchedule,'native-unsubmitted Host route was not used: '..tostring(move.reason))
 assert(not policy.moveReason(q,b,a,false)and not policy.cancelOperationReason(q,a)and not policy.cancelReason(q,a),
  'reason-only APIs disagreed with authoritative native scheduling')
 assert(api.move(q,b,a)and q.queue[1]==front and q.queue[2]==b and q.queue[3]==a and q.queue[4]==tail)
 local cancel=policy.evaluateCancel(q,a,true)
 assert(cancel.allowed and cancel.nativeSchedule,'Host native cancellation before a root reader denied')
 assert(api.cancelOperation(q,a)and #q.queue==3 and q.queue[2]==b and q.queue[3]==tail)
 assert(s.certificate.requests==0 and s.effects()==0 and not a.action and not b.action and front.action,
  'Host schedule edit ran/replayed native work')
end
-- The common decision must not rebuild one standalone private proof per row.
-- Replacing the unused APIs before capture is harmless; using either is a bug.
do
 local s,p,api,q,front,a,b,tail,ledger=hostQueue()
 local function obsolete()error('standalone native lease rebuilt inside cohort decision')end
 ledger.nativePlanLease,ledger.nativePlanSingleton=obsolete,obsolete
 local move=p.evaluateMove(q,b,a,false)
 local cancel=p.evaluateCancel(q,a,true)
 assert(move.allowed and move.nativeSchedule and cancel.allowed and cancel.nativeSchedule,
  'shared cohort decision still depends on standalone per-row proofs')
 assert(api.move(q,b,a)and api.cancelOperation(q,a)and q.queue[1]==front and q.queue[2]==b and q.queue[3]==tail)
 assert(s.effects()==0)
end
do
 local s,p,api,q,front,a,b,tail=hostQueue()
 front.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
 local ordinary=p.evaluateMove(q,a,front,false)
 s.certificate.quiet=false -- Explicit control: refuse the new owner and retain native legacy inspection.
 local legacy=p.evaluateMove(q,a,front,false)
 assert(ordinary.allowed and legacy.allowed and ordinary.reason==legacy.reason and not ordinary.nativeSchedule,
  'pending Host owner replaced an already-qualified active-reading route')
end
do
 local s,p,api,q,front,a,b,tail,ledger=hostQueue()
 s.f.native('client/TimedActions/WalkToTimedAction.lua');p.installContracts()
 local walk=s.f.action(ISWalkToTimedAction,{})
 table.insert(q.queue,3,walk);assert(ledger.track(walk,'body'))
 local ordinary=p.evaluateMove(q,a,walk,true)
 s.certificate.quiet=false
 local legacy=p.evaluateMove(q,a,walk,true)
 assert(ordinary.allowed and legacy.allowed and not ordinary.nativeSchedule,
  'native scheduling tightened an already-supported mixed walking/equipment edit')
end
for index,mutate in ipairs({
 function(s,p,a,q,front,x,y,tail,l)q.queue[3],q.queue[4]=tail,y;y.toolkitQueueOperation=x.toolkitQueueOperation end,
 function(s,p,a,q,front,x,y,tail,l)l.cleanupAfter(tail,{})end,
 function(s,p,a,q,front,x,y,tail,l)tail.item.container={}end,
 function(s,p,a,q,front,x,y,tail,l)y.item=x.item end,
 function(s,p,a,q,front,x,y,tail,l)y.action={}end,
})do
 local s,p,a,q,front,x,y,tail,l=hostQueue();mutate(s,p,a,q,front,x,y,tail,l)
 local move,cancel=p.evaluateMove(q,y,x,false),p.evaluateCancel(q,x,true)
 assert(not move.allowed and not cancel.allowed,'unsupported Host cohort gained permission '..index..' move='..tostring(move.allowed)..' cancel='..tostring(cancel.allowed))
end
-- Late metadata and final Settings calls can mutate an already inspected row.
-- Both the decision and the actual public commit must reject that stale proof.
for _,late in ipairs({'metadata','private','commit'})do
 local s,p,a,q,front,x,y,tail,l=hostQueue()
 local function mutate()
  if late=='private'then assert(l.track(x,'cleanup'))
  else x.onCancelFunc=function()error('foreign cancellation executed')end end
 end
 if late~='commit'then
  tail.item.getID=function(self)mutate();return self.id end
  assert(not p.evaluateMove(q,y,x,false).allowed,'later item metadata invalidated an earlier row without rejection')
 else
  local original=PZSurvivorToolkit.Settings.actionQueue
  local armed=false
  PZSurvivorToolkit.Settings.actionQueue=function()if armed then mutate()end;return original()end
  local decision=assert(p.evaluateMove(q,y,x,false));assert(decision.allowed)
  armed=true
  assert(not p.editUnchanged(q,decision.snapshot),'final settings callback bypassed callback-free commit lease')
 end
 assert(q.queue[2]==x and q.queue[3]==y and s.effects()==0)
end
do
 local s,p,a,q,front,x,y=hostQueue();local calls=0
 for key,value in pairs(x.toolkitQueueOperation)do
  if type(key)=='table'and type(value)=='function'then
   x.toolkitQueueOperation[key]=function()calls=calls+1;error('foreign operation seal executed')end
  end
 end
 assert(not p.evaluateMove(q,y,x,false).allowed and not p.evaluateCancel(q,x,true).allowed)
 assert(calls==0 and q.queue[2]==x and q.queue[3]==y,'full Policy invoked an untrusted private-operation seal')
end
-- Distinct instances of the same native type must stay separate resources
-- when a third pending assignment crosses them through the public Queue API.
do
 local s=setup();s.f.project('ActionQueueOperations');s.f.project('ActionQueueDefinitions')
 s.f.project('ActionQueuePolicy');s.f.project('ActionQueueLabels');local api=s.f.project('ActionQueue')
 local front=s.f.action(ISReadABook,{item=s.item()});local tail=s.f.action(ISReadABook,{item=s.item()})
 local a=s.action(s.item(),false,false);local b=s.action(s.item('HandWeapon'),true,false)
 local c=s.action(s.item('HandWeapon'),false,false);local q=s.f.queue(front,a,b,c,tail)
 assert(b.item:getFullType()==c.item:getFullType()and b.item:getID()~=c.item:getID())
 assert(api.move(q,c,a)and #q.queue==5 and q.queue[1]==front and q.queue[2]==c
  and q.queue[3]==a and q.queue[4]==b and q.queue[5]==tail,'same-type instance crossing lost identity or projected order')
 assert(s.actor.primary==nil and s.actor.secondary==nil and s.effects()==0,'pending move executed an effect')
end
-- A refused certificate or Host mode must preserve the old native boundary;
-- it cannot recover the new shared-hands permission through legacy fallback.
for _,client in ipairs({false,true})do
 local s=setup();s.f.project('ActionQueueOperations');s.f.project('ActionQueueDefinitions')
 local policy=s.f.project('ActionQueuePolicy');s.f.project('ActionQueueLabels');local api=s.f.project('ActionQueue')
 s.mode(client,false);s.certificate.allow=false
 local front=s.f.action(ISReadABook,{item=s.item()})
 local a=s.action(s.item(),true,false);local b=s.action(s.item(),false,false);local q=s.f.queue(front,a,b)
 local contract=assert(policy.inspect(a))
 assert(not contract.edit and contract.cancelTailOnly and contract.cancelWaiting,'refused owner changed the native fallback contract')
 assert(not policy.evaluateMove(q,b,a,false).allowed,'unknown hand effects escaped through the legacy move route')
 assert(not policy.evaluateCancel(q,a).allowed,'unknown hand effects gained cancellation before a surviving hand consumer')
 assert(api.cancel(q,b)and #q.queue==2 and q.queue[1]==front and q.queue[2]==a and s.effects()==0,
  'refused owner broke the already qualified pending native tail erasure')
end
-- Existing required cleanup has precedence over a complete family contract.
do
 local s=setup();s.f.project('ActionQueueOperations');s.f.project('ActionQueueDefinitions')
 local policy=s.f.project('ActionQueuePolicy');s.f.project('ActionQueueLabels');s.f.project('ActionQueue')
 local front=s.f.action(ISReadABook,{item=s.item()});local a=s.action(s.item(),true,false);local b=s.action(s.item(),false,false)
 local q=s.f.queue(front,a,b);local settlement=PZSurvivorToolkit.ActionQueueSettlement
 local previous=settlement.requiredStep
 settlement.requiredStep=function(action)return action==a or previous(action)end
 assert(not policy.inspect(a).edit,'required cleanup acquired the pending Equip contract')
 assert(not policy.evaluateMove(q,b,a,false).allowed and not policy.evaluateCancel(q,a).allowed,
  'a complete neighbouring owner bypassed required cleanup')
 assert(#q.queue==3 and q.current==front and s.effects()==0)
end
for _,mutation in ipairs({'client','server','actor','root','bag','stale','id','unknown-class','worn','attached','hotbar','heavy','activation','replace','wearable','back','world','crafting','primary','twoHands','requires-both','single-hand','always-on','duration','flags','active','started','cancelled','transaction','cleanup','linked','continuation','token-meta','callback','class-method','constructor','helper','hands','provider','certificate','stale-certificate','reentrant-provider','reentrant-hand','reentrant-mode','reentrant-item','reentrant-hands','reentrant-traits','reentrant-location','base','ancestry','hidden-action'})do
 local s=setup();local incoming=s.item('HandWeapon');local action=s.action(incoming,true,false);local calls=0
 local function foreign()calls=calls+1;error('foreign callback invoked')end
 if mutation=='client'then s.mode(true,false)
 elseif mutation=='server'then s.mode(false,true)
 elseif mutation=='actor'then s.actor.class='IsoGameCharacter'
 elseif mutation=='root'then s.root.getParent=function()return{}end
 elseif mutation=='bag'then incoming.container={class='ItemContainer'}
 elseif mutation=='stale'then s.root.items[incoming:getID()]={}
 elseif mutation=='id'then incoming.id=-1
 elseif mutation=='unknown-class'then incoming.class='Food'
 elseif mutation=='worn'then incoming.worn=true
 elseif mutation=='attached'then incoming.attachedSlot=2
 elseif mutation=='hotbar'then action.fromHotbar=true
 elseif mutation=='heavy'then incoming.heavy=true
 elseif mutation=='activation'then incoming.activation=true
 elseif mutation=='replace'then incoming.tags={[ItemTag.REPLACE_PRIMARY]=true}
 elseif mutation=='wearable'then incoming.tags={[ItemTag.WEARABLE]=true}
 elseif mutation=='back'then s.actor.back={getClothingItemExtra=foreign,hasTag=function()return true end}
 elseif mutation=='world'then incoming.world={}
 elseif mutation=='crafting'then incoming.crafting=true
 elseif mutation=='primary'then action.primary='primary'
 elseif mutation=='twoHands'then action.twoHands='both'
 elseif mutation=='requires-both'then incoming.requiresBoth=true
 elseif mutation=='single-hand'then action.twoHands=true
 elseif mutation=='always-on'then action.alwaysTurnOn=true
 elseif mutation=='duration'then action.maxTime=20
 elseif mutation=='flags'then action.stopOnAim=true
 elseif mutation=='active'then action.action={}
 elseif mutation=='started'then action.toolkitQueueOperation.toolkitStarted=true
 elseif mutation=='cancelled'then action.toolkitQueueOperation.toolkitCancelled=true
 elseif mutation=='transaction'then action.toolkitNativeTransaction={}
 elseif mutation=='cleanup'then action.toolkitQueueReturn={}
 elseif mutation=='linked'then action.toolkitQueueLinked=true
 elseif mutation=='continuation'then action.toolkitQueueOperation.toolkitContinuations=1
 elseif mutation=='token-meta'then setmetatable(action.toolkitQueueOperation,{__index=foreign})
 elseif mutation=='callback'then action.onCompleteFunc=foreign
 elseif mutation=='class-method'then ISEquipWeaponAction.complete=foreign
 elseif mutation=='constructor'then ISEquipWeaponAction.new=foreign
 elseif mutation=='helper'then forceDropHeavyItems=foreign
 elseif mutation=='hands'then s.hands.equipResource=foreign
 elseif mutation=='provider'then s.provider.certify=foreign
 elseif mutation=='certificate'then s.certificate.allow=false
 elseif mutation=='stale-certificate'then s.certificate.stale=true
 elseif mutation=='reentrant-provider'then s.certificate.before=function()s.provider.certify=foreign end
 elseif mutation=='reentrant-hand'then s.certificate.before=function()s.hands.equipResource=foreign end
 elseif mutation=='reentrant-mode'then s.certificate.before=function()action.primary=false end
 elseif mutation=='reentrant-item'then s.certificate.before=function()action.item=s.item()end
 elseif mutation=='reentrant-hands'then s.certificate.before=function()s.actor.primary=s.item()end
 elseif mutation=='reentrant-traits'then s.certificate.before=function()incoming.swing='Handgun'end
 elseif mutation=='reentrant-location'then s.certificate.before=function()incoming.container={}end
 elseif mutation=='base'then ISBaseTimedAction.new=foreign
 elseif mutation=='ancestry'then ISBaseTimedAction.__index=foreign
 elseif mutation=='hidden-action'then setmetatable(action,{__metatable=ISEquipWeaponAction,__index=foreign})end
 assert(not s.owner.inspect(action),'unsupported '..mutation..' gained native edit authority')
 assert(calls==0 and s.effects()==0,'rejection executed native/foreign effect: '..mutation)
end
-- Both currently held items are dependencies, even when another incoming item
-- would overwrite only one side. Neither unknown aliases nor branches vanish.
for _,side in ipairs({'primary','secondary'})do
 for _,mutation in ipairs({'alias','class','activation','heavy','worn'})do
  local s=setup();local held=s.item();s.actor[side]=held;local action=s.action(s.item(),true,false)
  if mutation=='alias'then s.root.items[held:getID()]={}
  elseif mutation=='class'then held.class='DrainableComboItem'
  elseif mutation=='activation'then held.activation=true
  elseif mutation=='heavy'then held.heavy=true
  else held.worn=true end
  assert(not s.owner.inspect(action),'unsupported current '..side..' '..mutation..' omitted from dependencies')
 end
end
for _,path in ipairs({'ISEquipWeaponAction.lua','ISBaseTimedAction.lua','ActionQueueHands.lua'})do
 local s=setup(path);assert(not s.owner.inspect(s.action(s.item(),true,false)),'unreviewed '..path..' accepted')
end
if TestCoverage then TestCoverage('source-contract','passed','Pending native Equip source ownership with an explicit effect-certificate double; no selected-pack effects or live Host qualification.')end
print('Pending native Equip source ownership, exact item dependencies and projected hand chains passed.')
