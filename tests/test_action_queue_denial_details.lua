if not NativeActionRoot then print('Queue denial details SKIP (pass --native-action-root).');return end
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local value=file:read('*a');file:close();return value:gsub('\r','')
end
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
getGameFilesInput=function(path)
 local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''));local position=1
 return {close=function()end,readLine=function()
  if position>#text then return end
  local stop=text:find('\n',position,true)or #text+1
  local line=text:sub(position,stop-1);position=stop+1;return line
 end}
end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/Fluids/ISFluidContainer.lua')
f.native('shared/Fluids/ISFluidTransferAction.lua')
f.native('shared/Fluids/ISFluidEmptyAction.lua')
isClient=function()return false end
f.native('shared/RadioCom/ISRadioAction.lua')
f.native('shared/TimedActions/ISEquipWeaponAction.lua')
f.player.class='IsoPlayer'
local originalRequire=require
local modules={}
require=function(name)
 if name=='PZSurvivorToolkit/ActionQueueEditModel'or name=='PZSurvivorToolkit/ActionQueueEditAdapters'then
  if not modules[name]then modules[name]=f.project(name:match('/([^/]+)$'))end
  return modules[name]
 end
 return originalRequire(name)
end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local function book(kind)return f.action(ISReadABook,{item=f.item(kind or 'Base.BookCarpentry1')})end
local ops=PZSurvivorToolkit.ActionQueueOperations
local function samePreview(actual,preview)
 assert(preview.reason==actual.reason and preview.blocker==actual.blocker and preview.resource==actual.resource,
  'preview and authoritative diagnostic differ')
 assert(preview.snapshot==nil and preview.allowed==nil,'presentation acquired mutation authority')
end
local function cancelDenied(queue,action,whole,legacy,reason,blocker)
 local raw=whole and policy.cancelOperationReason(queue,action)or policy.cancelReason(queue,action)
 assert(raw==legacy,'raw legacy cancellation reason changed: '..tostring(raw))
 local result=policy.evaluateCancel(queue,action,whole)
 assert(not result.allowed and result.reason==reason and result.blocker==blocker,
  'cancellation diagnostic differs: expected '..reason..', got '..tostring(result.reason))
 samePreview(result,policy.previewCancel(queue,action,whole))
 assert(policy.editUnchanged(queue,result.snapshot),'diagnostic inspection changed queue authority')
 return result
end
local function moveDenied(queue,action,target,after,legacy,reason,blocker,resource,context)
 assert(policy.moveReason(queue,action,target,after)==legacy,'raw legacy move reason changed')
 local result=policy.evaluateMove(queue,action,target,after,context)
 assert(not result.allowed and result.reason==reason and result.blocker==blocker and result.resource==resource,
  'move diagnostic differs: expected '..reason..', got '..tostring(result.reason))
 samePreview(result,policy.previewMove(queue,action,target,after))
 assert(policy.editUnchanged(queue,result.snapshot),'move diagnostic inspection changed queue authority')
 return result
end
local function vessel()
 local owner=f.item('Base.Bucket')
 local fluid={class='FluidContainer',amount=5,getOwner=function()return owner end,
  getAmount=function(self)return self.amount end,isEmpty=function(self)return self.amount==0 end,
  canPlayerEmpty=function()return true end,Empty=function(self)self.amount=0 end}
 local wrapper=setmetatable({fluidContainer=fluid,isFluidResource=false,sync=function()end},ISFluidContainer)
 return wrapper,owner,fluid
end
local function empty(wrapper)return f.action(ISFluidEmptyAction,{container=wrapper or vessel(),amount=5})end
local head,unknown=book(),f.action(ISBaseTimedAction:derive('UnsupportedDenialFixture'))
local queue=f.queue(head,unknown)
cancelDenied(queue,unknown,false,'dependent','edit_unknown',unknown)
cancelDenied(queue,unknown,true,'operation_dependent','edit_unknown',unknown)
local ordinary=book('Base.BookFirstAid1')
queue=f.queue(head,unknown,ordinary)
moveDenied(queue,ordinary,unknown,false,'move_dependent','edit_unknown',unknown)
moveDenied(queue,unknown,ordinary,true,'move_dependent','edit_unknown',unknown)
-- A known class with a changed callback is unknown; inspection never invokes it.
local changed=empty();local executions=0
changed.updateEmpty=function()executions=executions+1;error('unreviewed callback must not execute')end
queue=f.queue(head,changed,ordinary)
cancelDenied(queue,changed,false,'dependent','edit_unknown',changed)
cancelDenied(queue,changed,true,'operation_dependent','edit_unknown',changed)
moveDenied(queue,ordinary,changed,false,'move_dependent','edit_unknown',changed)
changed.updateEmpty=nil
for _,field in ipairs({'onStartFunc','onCancelFunc','onCompleteFunc','onFailFunc','additionalTest','retriggerLastAction'})do
 changed[field]=function()executions=executions+1;error('custom callback must not execute')end
 cancelDenied(queue,changed,false,'dependent','edit_unknown',changed)
 changed[field]=nil
end
assert(executions==0,'diagnosis executed gameplay or callback effects')
print('PASS unknown native classes, changed helpers/custom callbacks and exact preview blockers')

-- Native expansion and the actual continuation tracker have distinct unfinished-work evidence.
for _,mode in ipairs({'expansion','continuation'})do
 local pending=book('Base.BookFirstAid1');local following=book('Base.BookFirstAid2')
 queue=f.queue(head,pending,following)
 local continuation
 if mode=='expansion'then pending._isAddingActions=true
 else continuation=assert(ops.attachContinuation(pending.toolkitQueueOperation,f.player))end
 cancelDenied(queue,pending,false,'dependent','edit_in_flight',pending)
 cancelDenied(queue,pending,true,'operation_dependent','edit_in_flight',pending)
 moveDenied(queue,pending,following,true,'move_dependent','edit_in_flight',pending)
 moveDenied(queue,following,pending,false,'move_dependent','edit_in_flight',pending)
 if continuation then ops.finishContinuation(continuation)else pending._isAddingActions=nil end
 assert(policy.evaluateCancel(queue,pending,true).allowed and policy.evaluateMove(queue,following,pending).allowed,
  'finished expansion/continuation retained a stale denial')
end
print('PASS native expansion/continuation denies without consuming or invalidating unfinished work')

-- Earn a private cleanup step through the actual native completion and Settlement path.
local settlement=f.project('ActionQueueSettlement')
local wrapper,owner,fluid=vessel()
local preparation,cleanup,tail=empty(wrapper),empty(),book('Base.BookFirstAid3')
cleanup.toolkitQueueOperation=preparation.toolkitQueueOperation
queue=f.queue(preparation,cleanup,tail)
local handle=assert(settlement.track(preparation,'prepare'))
local effect=settlement.captureEffect(preparation)
assert(preparation:complete()and fluid.amount==0,'actual native empty completion did not occur')
assert(settlement.earn(handle,effect,fluid.amount==0)and settlement.cleanup(cleanup,handle),
 'native completed effect did not earn its exact private cleanup prerequisite')
ISInventoryPaneContextMenu.getContainers=function()return {contains=function()return false end}end
local released=0
assert(settlement.finish(queue,{action=preparation,token=preparation.toolkitQueueOperation},function(action,completed)
 assert(action==preparation and completed);released=released+1
end))
assert(released==1 and queue.queue[2]==cleanup and queue.queue[3]==tail and settlement.requiredStep(cleanup),
 'retained cleanup did not acquire genuine required-step ownership')
cancelDenied(queue,cleanup,false,'dependent','edit_required_cleanup',cleanup)
cancelDenied(queue,cleanup,true,'operation_dependent','edit_required_cleanup',cleanup)
local copy=f.action(ISFluidEmptyAction,{container=cleanup.container,amount=5,toolkitQueueReturn=cleanup.toolkitQueueReturn})
queue=f.queue(head,copy,tail)
assert(not settlement.requiredStep(copy)and policy.evaluateCancel(queue,copy,true).allowed,
 'copied cleanup presentation manufactured required ownership')
print('PASS required cleanup is private earned settlement evidence, not a copied presentation flag')

-- Genuine legacy barriers must retain their meaning rather than becoming generic unknowns.
local linked=book('Base.BookFirstAid4');linked.toolkitQueueLinked=true
queue=f.queue(head,linked)
cancelDenied(queue,linked,false,'dependent','dependent',nil)
local first,between,last=book('Base.BookFirstAid5'),book('Base.BookFirstAid6'),book('Base.BookFirstAid7')
last.toolkitQueueOperation=first.toolkitQueueOperation
queue=f.queue(head,first,between,last)
cancelDenied(queue,first,true,'operation_dependent','operation_dependent',nil)
moveDenied(queue,first,between,true,'move_dependent','move_dependent',nil)
local shared=vessel();local left,right=empty(shared),empty(shared)
queue=f.queue(head,left,right)
local resource=shared.fluidContainer:getOwner():getID()
moveDenied(queue,right,left,false,'move_shared_item','move_shared_item',left,resource)
local equipA=f.action(ISEquipWeaponAction,{item=f.item('Base.Hammer')})
local equipB=f.action(ISEquipWeaponAction,{item=f.item('Base.Screwdriver')})
queue=f.queue(head,equipA,equipB)
moveDenied(queue,equipB,equipA,false,'move_dependent','move_dependent',equipA,f.player)
print('PASS linked/split groups and known item/hand dependencies retain precise legacy barriers')

-- Reuse analysis only within unchanged facts; a previous reason must not leak to another edit.
local context={contracts={},items={}}
local otherUnknown=f.action(ISBaseTimedAction:derive('SecondUnsupportedDenialFixture'))
local one,two=book('Base.BookFirstAid8'),book('Base.BookFirstAid9')
queue=f.queue(head,otherUnknown,one,two)
moveDenied(queue,one,otherUnknown,false,'move_dependent','edit_unknown',otherUnknown,nil,context)
local success=policy.evaluateMove(queue,two,one,false,context)
assert(success.allowed and success.reason==nil and success.blocker==nil and success.resource==nil,
 'reused context retained a previous unrelated denial')
samePreview(success,policy.previewMove(queue,two,one))
assert(policy.editUnchanged(queue,success.snapshot))
queue.toolkitOperationGeneration=(queue.toolkitOperationGeneration or 0)+1
assert(not policy.editUnchanged(queue,success.snapshot),'stale diagnostic decision retained mutation authority')
local refreshed=policy.evaluateMove(queue,two,one)
assert(refreshed.allowed and policy.editUnchanged(queue,refreshed.snapshot),'fresh edit retained stale generation denial')
one.onCompleteFunc=function()error('new callback must not execute')end
cancelDenied(queue,one,false,'dependent','edit_unknown',one)
one.onCompleteFunc=nil
assert(policy.evaluateCancel(queue,one,false).allowed,'restored native reader remained denied')
print('PASS successful edits, context diagnostic isolation, stale snapshots and fresh callback revalidation')

-- Existing native model reasons outrank diagnostic fallback and preserve their exact device proof.
local object={class='IsoTelevision'}
local data={class='DeviceData',on=false,volume=.5}
object.getObjectIndex=function()return 0 end;object.getSquare=function()return {}end;object.getDeviceData=function()return data end
for name,callback in pairs({getParent=function()return object end,isIsoDevice=function()return true end,isVehicleDevice=function()return false end,
 getIsTurnedOn=function()return data.on end,getPower=function()return 1 end,getDeviceVolume=function()return data.volume end,
 getChannel=function()return 200 end,getMicIsMuted=function()return false end,getIsBatteryPowered=function()return false end,
 canBePoweredHere=function()return true end})do data[name]=callback end
local function radio(mode,value)
 local action=ISRadioAction:new(mode,f.player,object,value);action.toolkitQueueOperation={};return action
end
local power,volume=radio('ToggleOnOff'),radio('SetVolume',.25)
queue=f.queue(head,power,volume)
local state=policy.evaluateMove(queue,volume,power)
assert(not state.allowed and state.reason=='edit_required_state'and state.blocker==volume and state.resource==object,
 'native state proof was replaced by generic diagnostic')
samePreview(state,policy.previewMove(queue,volume,power))
assert(policy.evaluateCancel(queue,power,true).reason=='edit_required_state')
data.on=true
local mute,zero=radio('MuteVolume'),radio('SetVolume',0)
queue=f.queue(head,mute,zero)
local amount=policy.evaluateMove(queue,zero,mute)
assert(not amount.allowed and amount.reason=='edit_resource_amount'and amount.blocker==mute and amount.resource==object,
 'native numeric resource proof was replaced by generic diagnostic')
samePreview(amount,policy.previewMove(queue,zero,mute))
assert(data.on==true and data.volume==.5,'native model diagnosis executed device effects')
print('PASS source-bound native radio state/amount model denial evidence retains precedence')

-- Native hand changes retain the existing conservative carried-weight proof.
local previousInstanceof=instanceof
instanceof=function(value,kind)return previousInstanceof(value,kind)
 or kind=='InventoryItem'and type(value)=='table'and value.class=='InventoryContainer'
 or kind=='IsoGameCharacter'and value==f.player end
local root=f.player:getInventory();root.class='ItemContainer'
root.getParent=function()return f.player end;root.getContainingItem=function()end
local bag=f.item('Base.Bag_Schoolbag');bag.class='InventoryContainer'
local source={class='ItemContainer',getParent=function()end,getContainingItem=function()return bag end}
local transfer=f.action(ISInventoryTransferAction,{item=f.item('Base.Nails'),srcContainer=source,destContainer=root})
local equipment=f.action(ISEquipWeaponAction,{item=f.item('Base.Screwdriver')})
queue=f.queue(head,transfer,equipment)
moveDenied(queue,equipment,transfer,false,'container_capacity','container_capacity',transfer,root)
local capacity=policy.evaluateCancel(queue,transfer,true)
assert(not capacity.allowed and capacity.reason=='container_capacity'and capacity.blocker==equipment and capacity.resource==root,
 'known carried-capacity evidence was replaced by generic diagnostic')
samePreview(capacity,policy.previewCancel(queue,transfer,true))
instanceof=previousInstanceof
print('PASS native carried-capacity reason and exact container evidence retain precedence')

-- Demoting an active reader diagnoses the crossed range without restarting it.
local reader=book('Base.BookFirstAid15')
reader.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
local opaque=f.action(ISBaseTimedAction:derive('DemotionUnsupportedDenialFixture'))
queue=f.queue(reader,opaque)
moveDenied(queue,reader,opaque,true,'move_dependent','edit_unknown',opaque)
local expanding=book('Base.BookFirstAid16');expanding._isAddingActions=true
queue=f.queue(reader,expanding)
moveDenied(queue,reader,expanding,true,'move_dependent','edit_in_flight',expanding)
assert(queue.current==reader and queue.queue[1]==reader and reader.action:isStarted(),
 'a demotion explanation changed current reading or queue order')
print('PASS active reading demotion identifies unknown/expanding crossed work without interruption')
