-- UI previews belong to the avatar, never to the real worn/inventory state.
require 'TimedActions/ISApplyMakeUp'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local T=PZSurvivorToolkit
local Makeup={}
local actionClass,base=ISApplyMakeUp,ISBaseTimedAction
if not T or type(actionClass)~='table'or type(base)~='table'then
 function Makeup.install()return false end
 function Makeup.installUI()return false end
 return Makeup
end
T.ActionQueueMakeup=Makeup
local baseNew,forceCancel=base.new,base.forceCancel
local receiptKey,previewKey={},{}
local uiClass,expected,original,wrappers,bindings,operations,runWith,slotValues,avatarClass,avatarSet
local actionMethods={}
for name,value in pairs(actionClass)do if type(value)=='function'then actionMethods[name]=value end end
local function pack(...)return {n=select('#',...),...}end
local function enabled()return T.Settings and T.Settings.actionQueue()end
local function ownPreview(ui)
 local seal=Proof.own(ui,previewKey)
 return type(seal)=='function'and seal(ui)or nil
end
local function savePreview(ui,record)
 ui[previewKey]=record and function(owner)if owner==ui then return record end end or nil
end
local function clearPreview(ui)
 ui.makeUpSelected,ui.previousMakeUp=nil,nil
 if ui.add then ui.add.enable=false end
 ui.needsUpdateAvatar=true
 savePreview(ui,nil)
end
local function java(callback)
 if type(callback)~='function'or not bindings then return false end
 local ok,kind=pcall(bindings.getClassSimpleName,callback)
 return ok and (kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
local function bindingMatches()
 if not bindings or T~=PZSurvivorToolkit or T.ActionQueueMakeup~=Makeup then return false end
 for name,callback in pairs(bindings)do
  if name~='locations'and (_G[name]~=callback or not java(callback))then return false end
 end
 if ItemBodyLocation~=bindings.locations or T.ActionQueueOperations~=operations or operations.runWith~=runWith
  or ISUI3DModel~=avatarClass or avatarClass.setCharacter~=avatarSet then return false end
 for name,value in pairs(slotValues or{})do if ItemBodyLocation[name]~=value then return false end end
 return bindings.toolkitMakeupAvatarPreviewSupported()
end
local function uiMatches(ui)
 if not uiClass or ISMakeUpUI~=uiClass or not bindingMatches()then return false end
 for name,callback in pairs(expected)do
  if uiClass[name]~=callback or ui and ui[name]~=callback then return false end
 end
 for name,callback in pairs(uiClass)do
  if type(callback)=='function'and name~='derive'and expected[name]~=callback then return false end
 end
 return not ui or getmetatable(ui)==uiClass and ui.avatarPanel and ui.avatarPanel.setCharacter==avatarSet
end
local function localActor(actor)
 return actor and instanceof(actor,'IsoPlayer')and actor:isLocalPlayer()
  and getSpecificPlayer(actor:getPlayerNum())==actor and not actor:isDead()and not actor:isAsleep()
end
local function slotAllowed(slot)
 local loc=bindings and bindings.locations
 return loc and (slot==loc.MAKE_UP_FULL_FACE or slot==loc.MAKE_UP_EYES
  or slot==loc.MAKE_UP_EYES_SHADOW or slot==loc.MAKE_UP_LIPS)
end
local function scriptFor(kind)
 if type(kind)~='string'then return end
 local script=bindings.getScriptManager():FindItem(kind)
 if not script or bindings.getClassSimpleName(script)~='Item'or script:getFullName()~=kind
  or script:getLuaCreate()~=nil or script:getItemConfigKey()~=nil or script:getItemConfig()~=nil
  or not slotAllowed(script:getBodyLocation())then return end
 return script
end
local function selection(ui)
 local combo=ui.comboMakeup
 local option=combo and combo.options and combo.options[combo.selected]
 local data=option and option.data
 if type(data)~='table'or getmetatable(data)or type(data.makeuptypes)~='table'or getmetatable(data.makeuptypes)
  or not ui.item or not data.makeuptypes[ui.item:getMakeUpType()]then return end
 for _,definition in ipairs(MakeUpDefinitions and MakeUpDefinitions.makeup or{})do
  if definition==data then return scriptFor(data.item)end
 end
end
local function bodyUnchanged(action)
 if ISApplyMakeUp~=actionClass or ISBaseTimedAction~=base or base.new~=baseNew or base.forceCancel~=forceCancel
  or not Proof.closure(baseNew,'ISBaseTimedAction.lua')or not Proof.closure(forceCancel,'ISBaseTimedAction.lua')
  or getmetatable(action)~=actionClass or action.character==nil then return false end
 for name,callback in pairs(actionMethods)do if actionClass[name]~=callback or action[name]~=callback then return false end end
 for name,callback in pairs(actionClass)do if type(callback)=='function'and actionMethods[name]~=callback then return false end end
 return not action.onStartFunc and not action.onCancelFunc and not action.onCompleteFunc and not action.onFailFunc
  and not action.additionalTest and not action.retriggerLastAction
end
local function pendingProof(action)
 local seal=Proof.own(action,receiptKey)
 local r=type(seal)=='function'and seal(action)
 local q=r and r.queue
 if not q then return false end
 local matches=0
 for _,member in ipairs(q.queue)do
  if member==action then matches=matches+1
  elseif member.toolkitQueueOperation==r.token then return false end
 end
 if matches~=1 then return false end
 return r and uiMatches()and bodyUnchanged(action)and localActor(action.character)
  and q==ISTimedActionQueue.queues[action.character]and q.character==action.character and q:indexOf(action)~=-1
  and (q.toolkitOperationGeneration or 0)==r.generation and action.toolkitQueueOperation==r.token
  and action.item==r.item and action.type==r.kind and action.character==r.actor and action.maxTime==1
  and not action.action and not action.started and not action.toolkitNativeTransaction and not action.toolkitNativeKind
  and type(r.token)=='table'and not r.token.toolkitStarted and not r.token.toolkitCancelled
end
function Makeup.install(policy,resources)
 if type(policy)~='table'or type(policy.registerNative)~='function'or type(resources)~='function'
  or not Proof.matches('media/lua/shared/TimedActions/ISApplyMakeUp.lua',3487330035,nil,true)
  or not Proof.closure(actionClass.new,'ISApplyMakeUp.lua')then return false end
 policy.registerNative('ISApplyMakeUp',function(action)
  if not bodyUnchanged(action)then return end
  local c=resources(action)
  c.targets[action.character]=true
  c.hands,c.equipment=action.character,action.character
  c.knownInputs,c.unknownOutputs=false,true
  c.preparation,c.preparationFinish=false,false
  c.interrupt='finish-step'
  c.cancelWaiting=pendingProof(action)and true or false
  c.cancelOperation=c.cancelWaiting
  return c
 end)
 return true
end
local function apply(ui,...)
 local record=ownPreview(ui)
 if not record then return original.onApplyMakeUp(ui,...)end
 if not enabled()or not uiMatches(ui)or not localActor(ui.character)or record.actor~=ui.character
  or ui.makeUpSelected~=record.item or record.item:getContainer()~=nil or not record.rendered then
  ui.add.enable=false;return
 end
 local actor,preview=ui.character,record.item
 if not isClient()then
  -- SP is still its native immediate commit, with one native use/output.
  ui.previousMakeUp=actor:getWornItem(preview:getBodyLocation())
  actor:setWornItem(preview:getBodyLocation(),preview)
  savePreview(ui,nil)
  return original.onApplyMakeUp(ui,...)
 end
 local queue=ISTimedActionQueue.getTimedActionQueue(actor)
 local before={};for _,a in ipairs(queue.queue)do before[a]=true end
 local token={}
 local result=pack(pcall(runWith,token,original.onApplyMakeUp,ui,...))
 savePreview(ui,nil)
 if not result[1]then error(result[2],0)end
 local created
 for _,a in ipairs(queue.queue)do
  if not before[a]then
   if created or getmetatable(a)~=actionClass or a.character~=actor or a.item~=ui.item
    or a.type~=preview:getFullType()or a.toolkitQueueOperation~=token then created=false;break end
   created=a
  end
 end
 if created and uiMatches()and bodyUnchanged(created)then
  local r={actor=actor,item=created.item,kind=created.type,token=token,queue=queue,generation=queue.toolkitOperationGeneration or 0}
  created[receiptKey]=function(a)if a==created then return r end end
 end
 return unpack(result,2,result.n)
end
local function selectMakeup(ui,...)
 if not enabled()or not uiMatches(ui)or not localActor(ui.character)then
  if ownPreview(ui)then clearPreview(ui);ui.add.enable=false;return end
  return original.onSelectMakeUp(ui,...)
 end
 -- A native/foreign preview already owns restoration state. Keep that window
 -- on its original path until it has cleared it; never discard unowned effects.
 if not ownPreview(ui)and (ui.makeUpSelected or ui.previousMakeUp)then
  return original.onSelectMakeUp(ui,...)
 end
 if not selection(ui)then
  if ownPreview(ui)then clearPreview(ui)end
  return original.onSelectMakeUp(ui,...) -- unsupported producers retain native behavior and no edit receipt
 end
 -- The native selector makes exactly one preview. Its three worn operations are
 -- directed to a detached view; restore the real actor before ANY UI event.
 clearPreview(ui)
 local actor=ui.character
 local selected,slot,visualReady
 local facade={getWornItem=function(_,where)return actor:getWornItem(where)end,
  removeWornItem=function()end,
  setWornItem=function(_,where,item)
   selected,slot=item,where
   visualReady=item:getVisual()~=nil -- native getter initializes once when its asset is ready
  end}
 ui.character=facade
 local result=pack(pcall(original.onSelectMakeUp,ui,...))
 ui.character=actor
 if not result[1]then clearPreview(ui);error(result[2],0)end
 if selected and ui.makeUpSelected==selected and selected:getContainer()==nil and slotAllowed(slot)
  and selected:getBodyLocation()==slot then
  savePreview(ui,{actor=actor,item=selected,slot=slot,rendered=false,visualReady=visualReady})
  ui.add.enable=false
 else clearPreview(ui);ui.add.enable=false end
 return unpack(result,2,result.n)
end
function Makeup.installUI()
 if uiClass then return uiMatches()end
 local class=ISMakeUpUI
 if type(class)~='table'or type(class.windows)~='table'then return false end
 for _ in pairs(class.windows)do return false end
 if not Proof.matches('media/lua/client/ISUI/ISMakeUpUI.lua',1476281680,nil,true)
  or not Proof.matches('media/lua/shared/Definitions/MakeUpDefinitions.lua',2881080941,nil,true)
  or not Proof.matches('media/lua/client/ISUI/ISUI3DModel.lua',916715343,nil,true)
  or not Proof.matches('media/lua/shared/TimedActions/ISApplyMakeUp.lua',3487330035,nil,true)
  or ISApplyMakeUp~=actionClass or ISBaseTimedAction~=base or base.new~=baseNew
  or not Proof.closure(baseNew,'ISBaseTimedAction.lua')then return false end
 local avatar=ISUI3DModel
 if type(avatar)~='table'or not Proof.closure(avatar.setCharacter,'ISUI3DModel.lua')then return false end
 local saved={}
 for name,callback in pairs(class)do
  if type(callback)=='function'and name~='derive'then
   if not Proof.closure(callback,'ISMakeUpUI.lua')then return false end
   saved[name]=callback
  end
 end
 for _,name in ipairs({'onApplyMakeUp','onSelectMakeUp','onSelectLocation','reinit','close','prerender'})do if not saved[name]then return false end end
 local globs={locations=ItemBodyLocation}
 for _,name in ipairs({'instanceof','getClassSimpleName','isClient','getSpecificPlayer','getScriptManager','instanceItem',
  'toolkitMakeupAvatarPreviewSupported','toolkitMakeupAvatarPreview'})do globs[name]=_G[name];if type(globs[name])~='function'then return false end end
 bindings=globs
 for name,callback in pairs(globs)do if name~='locations'and not java(callback)then bindings=nil;return false end end
 if not globs.toolkitMakeupAvatarPreviewSupported()then bindings=nil;return false end
 operations=T.ActionQueueOperations
 runWith=operations and operations.runWith
 if not operations or type(runWith)~='function'or not Proof.closure(runWith,'ActionQueueOperations.lua')then bindings=nil;return false end
 slotValues={}
 for _,name in ipairs({'MAKE_UP_FULL_FACE','MAKE_UP_EYES','MAKE_UP_EYES_SHADOW','MAKE_UP_LIPS'})do
  if not ItemBodyLocation or ItemBodyLocation[name]==nil then bindings=nil;return false end
  slotValues[name]=ItemBodyLocation[name]
 end
 avatarClass,avatarSet=avatar,avatar.setCharacter
 uiClass,original,expected,wrappers=class,saved,{},{}
 for name,callback in pairs(saved)do expected[name]=callback end
 wrappers.onSelectMakeUp=selectMakeup
 wrappers.onApplyMakeUp=apply
 for _,name in ipairs({'onSelectLocation','reinit','close'})do
  local callback=saved[name]
  wrappers[name]=function(ui,...)
   if ownPreview(ui)then clearPreview(ui)end
   return callback(ui,...)
  end
 end
 wrappers.updateAvatar=function(ui,...)
  if ownPreview(ui)and (not enabled()or not uiMatches(ui))then ui.add.enable=false;return end
  return saved.updateAvatar(ui,...)
 end
 wrappers.prerender=function(ui,...)
  local r=ownPreview(ui)
  if r and (not enabled()or not uiMatches(ui))then ui.add.enable=false;return end
  local result=pack(saved.prerender(ui,...))
  if r then
   -- An async clothing asset may be absent on selection. Its native getter is
   -- pure while absent and initializes only this detached object once ready.
   if not r.visualReady then r.visualReady=r.item:getVisual()~=nil end
   r.rendered=r.visualReady and r.actor==ui.character and ui.makeUpSelected==r.item
    and bindings.toolkitMakeupAvatarPreview(ui.avatarPanel.javaObject,ui.character,r.item)==true
   ui.add.enable=r.rendered==true
  end
  return unpack(result,1,result.n)
 end
 for name,callback in pairs(wrappers)do class[name],expected[name]=callback,callback end
 return true
end
if Events and Events.OnGameStart then Events.OnGameStart.Add(Makeup.installUI)end
return Makeup
