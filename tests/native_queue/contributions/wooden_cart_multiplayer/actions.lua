require 'SaucedCarts/ContextMenu'
require 'ISUI/ISContextMenu'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISTimedActionQueue'
local J=require 'CartMPJSON'
local Actions={}
local phases={
 {name='drop-complete',drop=true,ground=true}, {name='pickup-complete',ground=false},
 {name='drop-cancel',drop=true,cancel=true,ground=false}, {name='drop-repeat',drop=true,ground=true},
 {name='pickup-cancel',cancel=true,ground=true}, {name='pickup-repeat',ground=false},
}
local session,window,serverDone,doneAt,quietAt=nil,nil,nil,nil,nil
local presentationDone=false
local observed={}
local function marker(kind,row)
 if row.wall then row.serverWall=row.wall end
 row.wall=getTimestampMs();print('[CART_MP_ACTION] '..kind..' '..J.encode(row))
end
local function status(p) return assert(toolkitWoodCartStatus,'Native presentation status required')(p) end
local function queue(p) return ISTimedActionQueue.getTimedActionQueue(p) end
local function empty(p) return #queue(p).queue==0 and p:getCharacterActions():isEmpty() and not p:hasPath() end
local function inspect(p,spec)
 local found,count,worlds=nil,0,0
 local contents=p:getInventory():getItems()
 for i=0,contents:size()-1 do local item=contents:get(i);if item:getID()==spec.id then found=item;count=count+1 end end
 for x=math.floor(p:getX())-4,math.floor(p:getX())+4 do for y=math.floor(p:getY())-4,math.floor(p:getY())+4 do
  local square=getCell():getGridSquare(x,y,p:getZ())
  if square then local objects=square:getWorldObjects();for i=0,objects:size()-1 do
   local item=objects:get(i):getItem();if item and item:getID()==spec.id then found=item;worlds=worlds+1 end
  end end
 end end
 local cargoOK=false
 if found then
  assert(found:getFullType()=='SaucedWheelbarrow.WheelbarrowWood','Exact cart changed type')
  local cargo=found:getInventory():getItems()
  cargoOK=cargo:size()==1 and cargo:get(0):getID()==spec.cargoID and cargo:get(0):getFullType()=='Base.Log'
   and math.abs(cargo:get(0):getActualWeight()-spec.cargoWeight)<.001
 end
 local a,b=p:getPrimaryHandItem(),p:getSecondaryHandItem()
 return {id=spec.id,cargoID=spec.cargoID,cargoWeight=spec.cargoWeight,cargoPreserved=cargoOK,
  inventoryCount=count,worldCount=worlds,primaryID=a and a:getID() or -1,secondaryID=b and b:getID() or -1,
  worldAttached=found and found:getWorldItem()~=nil or false,luaActions=#queue(p).queue,
  nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath()},found
end
local function matches(row,ground)
 return row.cargoPreserved and row.luaActions==0 and row.nativeActions==0 and not row.hasPath
  and (ground and row.inventoryCount==0 and row.worldCount==1 and row.worldAttached and row.primaryID==-1 and row.secondaryID==-1
   or not ground and row.inventoryCount==1 and row.worldCount==0 and not row.worldAttached and row.primaryID==row.id and row.secondaryID==row.id)
end
local function findPush(context)
 for _,option in ipairs(context.options) do
  if option.name==getText('UI_SaucedCarts_PushCart') or option.name=='Push Cart' then return option end
  if option.subOption then local found=findPush(context:getSubMenu(option.subOption));if found then return found end end
 end
end
local function enqueue(p,now)
 assert(empty(p),'Action phase started with pending queue/path')
 local spec=phases[session.index];local row,item=inspect(p,session)
 assert(matches(row,not spec.drop),'Unexpected ownership before '..spec.name)
 session.since=now;session.mode='action';session.cancelled=false;session.active=false;session.progress=false
 session.recovering=false;session.nativeProgress=false;session.quiet=nil;session.ack=nil
 sendClientCommand('CartMP','ActionBegin',{index=session.index,phase=spec.name,id=session.id})
 marker('BEGIN',{actor='client1',index=session.index,phase=spec.name,id=session.id,cancel=spec.cancel==true})
 local function callback()
  if spec.drop then ISInventoryPaneContextMenu.onUnEquip({item},p:getPlayerNum())
  else
   local context=ISContextMenu.get(p:getPlayerNum(),50,50)
   triggerEvent('OnFillWorldObjectContextMenu',p:getPlayerNum(),context,{assert(item:getWorldItem())},false)
   local option=assert(findPush(context),'Native ground Push Cart menu option missing')
   assert(option.onSelect and not option.notAvailable,'Native ground Push Cart menu unavailable');context:hideAndChildren()
   option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,
    option.param6,option.param7,option.param8,option.param9,option.param10)
  end
 end
 assert(PZSurvivorToolkit.ActionQueueOperations,'Action queue operations required').run(callback)
 assert(not empty(p),'Native cart callback queued no action')
end
function Actions.command(command,args)
 if command=='ActionPhase' then
  assert(phases[args.index] and phases[args.index].name==args.phase,'Wrong server action phase')
  window=args;marker('WINDOW',args)
 elseif command=='ActionAck' then
  assert(args.ok==true,'Server rejected action check: '..tostring(args.error))
  marker('SERVER_ACK',args)
  if session then
   assert(session.mode=='audit' and args.index==session.index and args.id==session.id,'Out-of-order action acknowledgement')
   session.ack=args
  end
 elseif command=='ActionsDone' then
  assert(args.ok==true and args.phases==#phases,'Incomplete authoritative action sequence')
  serverDone=args;doneAt=getTimestampMs();marker('SERVER_DONE',args)
 elseif command=='ActionFailed' then error('Server action failure: '..tostring(args.error))
 end
end
function Actions.sample(owner,actor)
 if not owner or not window then return end
 local s=status(owner);local row={actor=actor,index=window.index,phase=window.phase,id=window.id,
  active=s.active==true,recovering=s.recovering==true,progress=s.progress or 0,pickup=s.pickup==true,
  rendered=s.rendered==true,ik=s.ik==true,primaryID=owner:getPrimaryHandItem() and owner:getPrimaryHandItem():getID() or -1,
  secondaryID=owner:getSecondaryHandItem() and owner:getSecondaryHandItem():getID() or -1}
 local seen=observed[window.index] or {};observed[window.index]=seen
 seen.active=seen.active or row.active;seen.progress=seen.progress or row.active and row.progress>.05
 seen.recovering=seen.recovering or row.recovering
 marker('PRESENTATION',row)
end
function Actions.tick(p,setup,now)
 if session and session.mode=='complete' then return end
 if not session then
  assert(not p:isTimedActionInstant(),'Native cart action durations required')
  local cart=assert(p:getPrimaryHandItem(),'Initial held cart missing')
  assert(cart:getID()==setup.cartId and p:getSecondaryHandItem()==cart,'Initial exact cart hands differ')
  local cargo=cart:getInventory():getItems();assert(cargo:size()==1,'Initial cart cargo differs')
  session={index=1,id=setup.cartId,cargoID=cargo:get(0):getID(),cargoWeight=cargo:get(0):getActualWeight(),started=now}
  enqueue(p,now)
 end
 assert(now-session.started<35000,'MP cart action sequence deadline')
 local spec=phases[session.index]
 if not spec then return end
 local s=status(p)
 if session.mode=='action' then
  assert(now-session.since<10000,'Native cart action deadline '..spec.name)
  session.active=session.active or s.active==true
  session.progress=session.progress or s.active and (s.progress or 0)>.05
  session.recovering=session.recovering or s.recovering==true
  local action=queue(p).current
  if action and (action.Type=='ToolkitWoodCartPickup' or action.Type=='ToolkitWoodCartSetdown' or action.Type=='ToolkitWoodCartDrop') and action:isStarted() then
   local progress=action:getJobDelta();session.nativeProgress=session.nativeProgress or progress>.05
   if spec.cancel and not session.cancelled and progress>=.35 then
    assert(progress<.55 and action.action and not action.action:finished(),'Missed native cancellation window')
    session.cancelled=true;marker('CANCEL',{actor='client1',index=session.index,phase=spec.name,id=session.id,progress=progress})
    action.action:forceStop()
   end
  end
  if not empty(p) or s.active or s.recovering then session.quiet=nil;return end
  local row=inspect(p,session)
  if not matches(row,spec.ground) then session.quiet=nil;return end
  if not session.quiet then session.quiet=now;return end
  if now-session.quiet<200 then return end
  assert(session.active and session.progress and session.nativeProgress,'Native action/presentation progress not observed')
  assert(not spec.cancel or session.cancelled and session.recovering,'Cancellation/recovery not observed')
  row.index=session.index;row.phase=spec.name;row.actor='client1';row.cancelled=session.cancelled
  row.presentationProgress=session.progress;row.nativeProgress=session.nativeProgress;row.recoveryObserved=session.recovering
  row.recoveryEnded=not s.active and not s.recovering;row.elapsed=now-session.since;marker('RECEIPT',row)
  sendClientCommand('CartMP','ActionCheck',{index=session.index,phase=spec.name,id=session.id})
  session.mode='audit';session.since=now
 elseif session.mode=='audit' then
  assert(now-session.since<3500,'Authoritative action acknowledgement deadline')
  assert(matches(inspect(p,session),spec.ground),'Ownership changed while awaiting authoritative check')
  if session.ack then
   session.index=session.index+1
   if phases[session.index] then enqueue(p,now) else session.mode='complete' end
  end
 end
end
function Actions.done(owner,now,actor)
 if presentationDone then return true end
 if not serverDone then return false end
 assert(now-doneAt<3000,'Observer presentation recovery did not finish after server completion')
 local s=status(assert(owner,'Action owner disappeared'))
 if s.active or s.recovering then quietAt=nil;return false end
 if not quietAt then quietAt=now;return false end
 if now-quietAt<300 then return false end
 for index,spec in ipairs(phases) do
  local seen=observed[index]
  assert(seen and seen.active and seen.progress and (not spec.cancel or seen.recovering),'Missing native observed presentation coverage '..actor..'/'..spec.name)
 end
 presentationDone=true;return true
end
return Actions
