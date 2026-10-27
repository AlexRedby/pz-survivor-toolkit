local Proof=require 'PZSurvivorToolkit/SourceProof'
local M={}
local methods={'new','start','perform','complete','stop','isValid','getDuration'}
local transfer={new={'ISInventoryTransferAction.lua','CartTransferInterceptor.lua','TransferRestrictions.lua'},start={'ISInventoryTransferAction.lua','Proximity_ISInventoryTransferAction.lua','WMI_CleanBandagesContext.lua'},
 perform={'ISInventoryTransferAction.lua','CartTransferInterceptor.lua','VisualUpdateQueue.lua'},complete={},stop={'ISInventoryTransferAction.lua','Proximity_ISInventoryTransferAction.lua'},
 isValid={'ISInventoryTransferAction.lua','Proximity_ISInventoryTransferAction.lua','Nested.lua'},getDuration={'ISBaseTimedAction.lua'}}
local wash={new={'WMI_PatchWashClothing.lua'},start={'ISWashClothing.lua'},perform={'ISWashClothing.lua'},complete={'WMI_PatchWashClothing.lua'},
 stop={'ISWashClothing.lua'},isValid={'WMI_PatchWashClothing.lua'},getDuration={'ISWashClothing.lua'}}
function M.reviewedFallback(action)
 local kind=action.Type;local owner=_G[kind];local expected=kind=='ISInventoryTransferAction'and transfer or kind=='ISWashClothing'and wash
 local origins={};local facts={classMatches=type(owner)=='table'and getmetatable(action)==owner,constructorMatches=type(owner)=='table'and action.new==owner.new or false,
  classCompleteNil=type(owner)=='table'and owner.complete==nil or false,instanceCompleteNil=action.complete==nil,approvedConstructor=false}
 for _,name in ipairs(methods)do
  local ok,value=pcall(getFilenameOfClosure,action[name]);origins[name]=ok and tostring(value)or 'not-closure'
 end
 local function reject()return false,origins,facts end
 if type(owner)~='table'or not expected or getmetatable(action)~=owner then return reject()end
 for _,name in ipairs(methods)do
  local callback=action[name];local found=kind=='ISWashClothing'and name=='complete'and require('PZSurvivorToolkit/WashWaterRule').matchesComplete(callback)
  if kind=='ISInventoryTransferAction'and name=='complete'then found=facts.classCompleteNil and facts.instanceCompleteNil end
  for _,filename in ipairs(name=='complete'and kind=='ISWashClothing'and{}or expected[name])do if Proof.closure(callback,filename)then
   found=true
   if filename=='CartTransferInterceptor.lua'or filename=='VisualUpdateQueue.lua'or filename=='TransferRestrictions.lua'then
    local carts=PZSurvivorToolkit.ActionQueueCarts;if not carts or not carts.status or carts.status()~=true then return reject()end
   elseif (filename=='Proximity_ISInventoryTransferAction.lua'or filename=='Nested.lua')and not PZSurvivorToolkit.ActionQueueCompat.verifySources('EURY_CONTAINERS')then return reject()end
   break
  end end
  if not found then return reject()end
  if kind=='ISInventoryTransferAction'and name=='new'then
   local carts=PZSurvivorToolkit.ActionQueueCarts
   facts.approvedConstructor=carts and carts.isTransferConstructor and carts.isTransferConstructor(callback)==true or false
   if not facts.approvedConstructor and Proof.closure(callback,'ISInventoryTransferAction.lua')then
    facts.approvedConstructor=Proof.matches('media/lua/client/TimedActions/ISInventoryTransferAction.lua',3739549534,nil,true)
     and Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
   end
   if not facts.approvedConstructor then return reject()end
  end
  if callback~=owner[name]and not(name=='start'and kind=='ISInventoryTransferAction'and Proof.closure(callback,'WMI_CleanBandagesContext.lua')
   and action.item and action.wmiFullType==action.item:getFullType())then return reject()end
 end
 for name,value in pairs(action)do
  if type(value)=='function'and name~='start'and name~='onCompleteFunc'then return reject()end
 end
 if action.onCompleteFunc and not Proof.closure(action.onCompleteFunc,'WMI_WashingSubmenus.lua')and not Proof.closure(action.onCompleteFunc,'WMI_CleanBandagesContext.lua')then return reject()end
 if action.onStartFunc or action.onCancelFunc or action.onFailFunc or action.additionalTest or action.retriggerLastAction then return reject()end
 return true,origins,facts
end
return M
