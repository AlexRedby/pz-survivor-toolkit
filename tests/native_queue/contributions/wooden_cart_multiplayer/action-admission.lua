-- Test-only observation of native transactions and the existing sealed owner receipts.
local config=require 'QueueTestSelection'
assert(config.disposable==true and config.options.cart_action_admission==true,'Explicit disposable action admission experiment required')
local J=require 'CartMPJSON'
if CartActionAdmissionProbe then return CartActionAdmissionProbe end
local M={};CartActionAdmissionProbe=M
local module='CartActionAdmissionProbe'
-- Native counters cross Kahlua as doubles. Emit safe integers in decimal so
-- tostring's scientific representation cannot lose receipt precision. Native
-- Kahlua modulo narrows its quotient to int; its formatter can round 2^53-1.
local function integerText(value)
 assert(value==value and math.abs(value)<=9007199254740991 and math.floor(value)==value,'Admission log requires exact safe integers')
 local negative=value<0;if negative then value=-value end
 if value==0 then return '0' end
 local digits={}
 while value>0 do
  local quotient=math.floor(value/10)
  digits[#digits+1]=string.char(48+(value-quotient*10));value=quotient
 end
 local text=negative and '-' or ''
 for i=#digits,1,-1 do text=text..digits[i] end
 return text
end
local function encodeRow(row)
 local parts={}
 for key,value in pairs(row) do
  assert(type(key)=='string','Admission log key must be text')
  local encoded
  if type(value)=='number' then
   encoded=integerText(value)
  else
   assert(type(value)=='string' or type(value)=='boolean','Admission log requires scalar fields')
   encoded=J.encode(value)
  end
  parts[#parts+1]=J.encode(key)..':'..encoded
 end
 return '{'..table.concat(parts,',')..'}'
end
local function emit(marker,row)
 row.wallMs=getTimestampMs();print(marker..' '..encodeRow(row))
 if row.event=='error' then print('[CART_ADMISSION] ERROR '..tostring(row.reason)) end
end
if isServer() then
 Events.OnClientCommand.Add(function(mod,command,p,args)
  if mod~=module then return end
  local ok,err=pcall(function()
   assert(command=='Query' and p:getUsername()=='client1','Exact owner query required')
   assert(cartLeaseSource(p),'Exact native query source missing')
   assert(type(args)=='table' and args.owner==p:getOnlineID() and type(args.nonce)=='string'
    and #args.nonce<=120 and type(args.token)=='string' and #args.token==36,'Exact query identity missing')
   local native=assert(cartActionAdmission(p),'Native transaction admission unavailable')
   assert(native.token==args.token and native.cart==args.cart and native.owner==args.owner,'Query does not match exact native admission')
   assert(native.tokenObserved==true and native.sourceValidated==true and native.admittedBindingValid==true
    and (native.stage=='accepted' or native.stage=='terminal'),'Native transaction not admitted')
   local row={actor='server',event='query',index=args.index,phase=args.phase,nonce=args.nonce,guarded=true}
   for k,v in pairs(native) do row[k]=v end
   emit('[CART_ADMISSION_QUERY]',row)
   native.nonce=args.nonce;native.index=args.index;native.phase=args.phase
   sendServerCommand(p,module,'Reply',native)
  end)
  if not ok then emit('[CART_ADMISSION_QUERY]',{actor='server',event='error',reason=tostring(err)}) end
 end)
 return M
end
local reader=assert(getFileReader('smoke-user.txt',false));local user=reader:readLine();reader:close()
local Ack=require 'PZSurvivorToolkit/ActionQueueAcknowledgements'
local entries,pending={},{}
local identities=setmetatable({},{__mode='k'});local nextIdentity=0
local function identity(object)
 assert(object~=nil,'Exact local action/native identity required')
 if not identities[object] then nextIdentity=nextIdentity+1;identities[object]=nextIdentity end
 return identities[object]
end
local function row(entry,event)
 local r={actor=user,event=event,ownerProcess=cartLeaseSeed(),owner=entry.owner:getOnlineID(),index=entry.index,
  phase=entry.phase,cart=entry.cart,localActionEpoch=entry.localActionEpoch,localNativeEpoch=entry.localNativeEpoch}
 if entry.snapshot then
  r.token=entry.snapshot.token;r.transaction=entry.snapshot.transaction;r.kind=entry.snapshot.kind
  r.captureGeneration=entry.snapshot.generation
 end
 return r
end
function M.track(action,spec)
 if user~='client1' then return end
 assert(action and action.character==getPlayer() and spec.index==#entries+1 and spec.index<=6,'Exact phase action missing')
 local entry={action=action,owner=action.character,index=spec.index,phase=spec.phase,cart=spec.id,
  localActionEpoch=identity(action)}
 entries[#entries+1]=entry;emit('[CART_ADMISSION_OWNER]',row(entry,'track'))
end
function M.trackQueued(queued,spec)
 if user~='client1' then return end
 local kind=spec.phase:sub(1,6)=='pickup' and 'ToolkitWoodCartPickup'
  or config.options.cart_hotkey_setdown==true and 'ToolkitWoodCartDrop' or 'ToolkitWoodCartSetdown'
 local selected
 for _,action in ipairs(queued) do
  if action.Type==kind then
   local cart=kind=='ToolkitWoodCartPickup' and action.itemId or action.item and action.item:getID()
   if cart==spec.id then assert(not selected,'Ambiguous queued cart action identity');selected=action end
  end
 end
 M.track(assert(selected,'Exact queued cart action missing'),spec)
end
function M.sample()
 if user~='client1' then return end
 for _,entry in ipairs(entries) do
  if not entry.receipt then
   local action=entry.action
   local queue=ISTimedActionQueue.queues[entry.owner]
   if queue and queue.current==action and action.action then
    local receipt=Ack.capture(action)
    if receipt then
     entry.receipt=receipt;entry.native=action.action;entry.localNativeEpoch=identity(entry.native)
     entry.snapshot={token=receipt.token,transaction=receipt.transaction,kind=receipt.kind,generation=receipt.generation,queue=receipt.queue}
     entry.connection=assert(cartLeaseCurrent(),'Owned source connection missing')
     local observed=assert(Ack.observe(action,receipt),'Sealed native receipt unavailable')
     assert(observed=='started','Native start receipt was not observed while current')
     local capture=row(entry,'capture');capture.state=observed;capture.sealed=true;emit('[CART_ADMISSION_OWNER]',capture)
     local nonce=assert(cartLeaseSeed())..':action:'..entry.index;pending[nonce]=entry;entry.nonce=nonce
     local request=row(entry,'query');request.nonce=nonce;request.guarded=true;emit('[CART_ADMISSION_OWNER]',request)
     sendClientCommand(entry.owner,module,'Query',{owner=entry.owner:getOnlineID(),token=receipt.token,nonce=nonce,
      index=entry.index,phase=entry.phase,cart=entry.cart})
    end
   end
  elseif not entry.terminal and not entry.revoked then
   local observed=Ack.observe(entry.action,entry.receipt)
   if observed and observed~='started' then
    entry.terminal=observed;local terminal=row(entry,'terminal');terminal.state=observed;terminal.sealed=true
    emit('[CART_ADMISSION_OWNER]',terminal)
   elseif observed==nil then
    entry.revoked=true
    local current=ISTimedActionQueue.queues[entry.owner]
    local generation=current and (current.toolkitOperationGeneration or 0)
    local revoked=row(entry,'seal-revoked');revoked.sealed=false;revoked.currentAuthority=false
    revoked.observedGeneration=generation
    revoked.reason=current==entry.snapshot.queue and generation~=entry.snapshot.generation
     and 'operation-generation-changed' or 'observe-unavailable'
    emit('[CART_ADMISSION_OWNER]',revoked)
   end
  end
 end
end
Events.OnServerCommand.Add(function(mod,command,args)
 -- Observe the original native terminal delivery independently from the API seal.
 -- Queue reset deliberately revokes observe(); this historical receipt grants no rights.
 if mod=='PZSurvivorToolkitActions' then
  if user~='client1' or command~='State' or type(args)~='table' or args.state=='started' then return end
  for _,entry in ipairs(entries) do
   local frozen=entry.snapshot
   if frozen and args.token==frozen.token then
    local ok,err=pcall(function()
     assert(args.protocol==1 and args.player==entry.owner:getOnlineID() and args.transaction==frozen.transaction
      and args.kind==frozen.kind and (args.state=='completed' or args.state=='canceled' or args.state=='rejected'),
      'Native terminal differs from exact captured receipt')
     assert(cartLeaseIngress()==entry.connection and cartLeaseCurrent()==entry.connection
      and getPlayer()==entry.owner and entry.action.character==entry.owner,'Native terminal source/actor changed')
     assert(not entry.nativeTerminal,'Duplicate native terminal delivery')
     entry.nativeTerminal=args.state
     local terminal=row(entry,'native-terminal-receipt');terminal.state=args.state
     terminal.guarded=true;terminal.sealed=false;terminal.currentAuthority=false
     emit('[CART_ADMISSION_OWNER]',terminal)
    end)
    if not ok then emit('[CART_ADMISSION_OWNER]',{actor=user,event='error',reason=tostring(err)}) end
    return
   end
  end
  return
 end
 if mod~=module then return end
 local ok,err=pcall(function()
  assert(user=='client1' and command=='Reply','Unexpected owner admission response')
  local entry=assert(pending[args.nonce],'Unrequested native admission response')
  assert(cartLeaseIngress()==entry.connection and cartLeaseCurrent()==entry.connection,'Exact response ingress changed')
  assert(getPlayer()==entry.owner and entry.action.character==entry.owner and entry.action.action==entry.native,
   'Exact local actor/action binding changed')
  assert(Ack.observe(entry.action,entry.receipt),'Sealed receipt invalidated before native association')
  assert(args.index==entry.index and args.phase==entry.phase and args.owner==entry.owner:getOnlineID()
   and args.cart==entry.cart and args.token==entry.receipt.token and args.transaction==entry.receipt.transaction
   and args.kind==entry.receipt.kind and args.tokenObserved==true and args.sourceValidated==true
   and args.admittedBindingValid==true and (args.stage=='accepted' or args.stage=='terminal'),'Native/owner transaction association differs')
  local reply=row(entry,'reply');for k,v in pairs(args) do reply[k]=v end
  reply.guarded=true;reply.sealed=true;emit('[CART_ADMISSION_OWNER]',reply)
  pending[args.nonce]=nil;entry.replied=true
 end)
 if not ok then emit('[CART_ADMISSION_OWNER]',{actor=user,event='error',reason=tostring(err)}) end
end)
function M.done()
 if user~='client1' then return true end
 if #entries~=6 then return false end
 for _,entry in ipairs(entries) do if not entry.receipt or not entry.nativeTerminal or not (entry.terminal or entry.revoked) or not entry.replied then return false end end
 return true
end
return M
