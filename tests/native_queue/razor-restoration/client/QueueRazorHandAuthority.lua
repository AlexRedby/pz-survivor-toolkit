-- Disposable Host-only fault: delay a genuine stopped cleanup receipt, never effects.
local D={}
function D.install(config,context)
 local delay=config.options and config.options.razor_hand_ack_delay_ms
 if delay==nil then return end
 assert(config.kind=='mp'and config.cases[1]=='restore-success'and #config.cases==1 and delay==1000,
  'hand authority fault requires isolated Host restore-success and 1000ms delay')
 local T=PZSurvivorToolkit;local A=T.ActionQueueAcknowledgements;local L=T.ActionQueueLifecycle
 assert(L.delayNativeReceipt==nil,'foreign receipt intervention already installed')
 local saved,releasing,stopped,kept,rows
 rows={}
 local function signature(args)
  return table.concat({args.protocol,args.player,args.transaction,args.kind,args.token,args.state},'|')
 end
 local function sample(phase,extra)
  local action,row,tail,tailRow,state=context.current();local queue=context.queue()
  assert(saved and action==saved.action and row.receipt==saved.receipt and action.action==saved.native
   and signature(saved.args)==saved.signature,'hand authority exact receipt/episode changed')
  local snapshot=context.snapshot()
  local value={phase=phase,at=getTimestampMs(),actionRef=row.actionRef,nativeRef=tostring(action.action),
   packetRef=tostring(saved.args),signature=saved.signature,ack=A.observe(action,row.receipt)or false,
   current=queue.current==action,head=queue.queue[1]==action,nativeAbsent=not state.player:getCharacterActions():contains(saved.native),
   waiting=T.ActionQueueSettlement.waitingForHandAuthority(queue,action)==true,
   tailStarted=tailRow.started,tailProgress=tailRow.progress,tailUnallocated=tail.action==nil,
   tailPages=snapshot.tail.characterPages,debts=T.ActionQueueExecution.blockedReturns(state.player),snapshot=snapshot}
  if extra then for key,item in pairs(extra)do value[key]=item end end
  rows[#rows+1]=value;context.emit('HAND_AUTHORITY',value);return value
 end
 L.delayNativeReceipt=function(module,command,args)
  if releasing or saved or not stopped or module~='PZSurvivorToolkitActions'or command~='State'or type(args)~='table'then return false end
  local action,row,tail,tailRow,state=context.current()
  if not action or action~=stopped.action or action.action~=stopped.native or row.receipt~=stopped.receipt
   or args.protocol~=1 or args.player~=state.player:getOnlineID()or args.kind~='ISEquipWeaponAction'
   or args.transaction~=row.receipt.transaction or args.kind~=row.receipt.kind or args.token~=row.receipt.token or args.state~='canceled'then return false end
  saved={action=action,native=action.action,receipt=row.receipt,args=args,signature=signature(args),
   module=module,command=command,at=getTimestampMs()}
  -- Nothing here polls Settlement: native stopped-state publication owns that boundary.
  return true
 end
 return {poll=function()
  local action,row,tail,tailRow,state=context.current();if not action then return end
  if not stopped and row.progress and context.queue().current==action and row.receipt and A.state(action,row.receipt)=='started'then
   stopped={action=action,native=action.action,receipt=row.receipt};context.evidence().handStop={at=getTimestampMs(),
    actionRef=row.actionRef,nativeRef=tostring(action.action),player=state.player:getOnlineID(),transaction=row.receipt.transaction,kind=row.receipt.kind,token=row.receipt.token}
   action:forceStop()
  end
  if not saved then return end
  if not kept then
   local debts=T.ActionQueueExecution.blockedReturns(state.player)
   if #debts==0 then return end
   assert(#debts==1 and debts[1].itemId==state.ids.items.razor.id and debts[1].state=='blocked','stopped cleanup location debt differs')
   local before=sample('pending')
   assert(before.ack=='started'and before.current and before.head and before.nativeAbsent and before.waiting
    and not before.tailStarted and before.tailUnallocated and before.tailPages==state.ids.items.tail.initial,'tail advanced before exact hand authority')
   local panel=context.panel();local button=assert(panel.keepReturnButton);local entry=assert(panel.returnEntries[panel.returnIndex or 1])
   assert(panel:getIsVisible()and button:getIsVisible()and entry.id==debts[1].id,'real Keep footer missing exact location debt')
   button:onMouseDown(1,1);assert(button.returnId==entry.id,'Keep press did not capture exact location debt')
   panel:keepFailedReturn(button);assert(not panel.returnRejected,'real Keep rejected exact location debt');panel:removeFromUIManager()
   local after=sample('kept',{keep={source='ActionQueuePanel.KeepReturn',id=entry.id,visible=true,pressCaptured=true,accepted=true}})
   assert(#after.debts==0 and after.waiting and after.current and after.head and after.tailUnallocated
    and not after.tailStarted and after.tailPages==state.ids.items.tail.initial,'Keep waived hand authority or advanced tail')
   kept=true;saved.keptAt=getTimestampMs();context.evidence().handAuthority=rows
  elseif not saved.released and getTimestampMs()-saved.keptAt>=delay then
   sample('held');assert(signature(saved.args)==saved.signature,'genuine packet mutated')
   releasing=true;triggerEvent('OnServerCommand',saved.module,saved.command,saved.args);releasing=false
   saved.released=true;local value=sample('released');assert(value.ack=='canceled','exact late terminal failed to authenticate')
  elseif saved.released and not saved.duplicate then
   releasing=true;triggerEvent('OnServerCommand',saved.module,saved.command,saved.args);releasing=false
   saved.duplicate=true;assert(sample('duplicate').ack=='canceled','duplicate changed exact terminal')
  end
 end,complete=function()
  assert(saved and saved.released and saved.duplicate and kept,'hand authority fault did not complete')
  if rows[#rows].phase~='finished'then sample('finished')end;return rows
 end}
end
return D
