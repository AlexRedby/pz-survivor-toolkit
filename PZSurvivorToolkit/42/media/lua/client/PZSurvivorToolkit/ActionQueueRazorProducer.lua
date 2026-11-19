-- Observe the actual synchronous native menu producer; never synthesize its work.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Toolkit=PZSurvivorToolkit
local Producer={}
Toolkit.ActionQueueRazorProducer=Producer
local active
local pinsQualified
local capture,closure,matches,own=Proof.captureBindings,Proof.closure,Proof.matches,Proof.own
local firstLine,activated=getFirstLineOfClosure,getActivatedMods
local dispatch,observe,owns,bind
local boundRun,boundQuery,boundOperations
local function pack(...)return {n=select('#',...),...}end
local function noProvider()
 if P4TidyUpMeister~=nil or getActivatedMods~=activated or type(activated)~='function'then return false end
 local ok,mods=pcall(activated)
 if not ok or not mods or type(mods.contains)~='function'then return false end
 local checked,selected=pcall(mods.contains,mods,'P4TidyUpMeister')
 return checked and selected==false and P4TidyUpMeister==nil
end
local profiles = {
 onTrimBeard = {line = 538, body = 'ISTrimBeard', styleField = 'beardStyle'},
 onCutHair = {line = 547, body = 'ISCutHair', styleField = 'hairStyle'},
}

function Producer.supports(method, callback)
 local profile = profiles[method]
 return profile ~= nil and closure(callback, 'ISCharacterScreen.lua') and firstLine(callback) == profile.line
end

local function prepare(producer,callback,actor,style,duration)
 local consumer=Toolkit.ActionQueueRazorRestoration
 if type(consumer)~='table'or type(consumer.enabled)~='function'or consumer.enabled(actor)~=true then return end
 if not producer or not noProvider()or type(actor)~='userdata'and type(actor)~='table'
  or not instanceof(actor,'IsoPlayer')or not actor:isLocalPlayer()
  or getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()or actor:isAsleep()then return end
 local menu,world,utils,util=ISCharacterScreen,ISWorldObjectContextMenu,luautils,ISInventoryTransferUtil
 if type(menu)~='table'or type(world)~='table'or type(utils)~='table'or type(util)~='table'
  or producer.owner~=menu or not profiles[producer.method] or producer.callback~=callback
  or own(menu,producer.method)~=producer.wrapper then return end
 local profile = profiles[producer.method]
 if producer.method == 'onCutHair' then
  local pending = Toolkit.ActionQueueGroomingPending
  if duration ~= 300 or type(style) ~= 'string' or style == '' or actor:getClothingItem_Head()
   or actor:getHumanVisual():getNonAttachedHair() or not pending
   or not closure(pending.noStylingCost, 'ActionQueueGroomingPending.lua')
   or not pending.noStylingCost(style) then return end
 end
 local approach=Toolkit.ActionQueueApproach
 local wrappedWalk=own(utils,'walkToContainer')
 local walk=wrappedWalk
 if not closure(walk,'luautils.lua')then
  if type(approach)~='table'or type(approach.nativeHelper)~='function'
   or not closure(approach.nativeHelper,'ActionQueueApproach.lua')then return end
  walk=approach.nativeHelper(utils,'walkToContainer',wrappedWalk)
 end
 local source={
  {callback,'ISCharacterScreen.lua',profile.line},
  {own(world,'equip'),'ISWorldObjectContextMenu.lua',2595},
  {own(world,'transferIfNeeded'),'ISWorldObjectContextMenu.lua',2588},
  {own(utils,'haveToBeTransfered'),'luautils.lua',445},
  {walk,'luautils.lua',307},
  {own(util,'newInventoryTransferAction'),'ISInventoryTransferUtil.lua',15},
  {own(util,'isPlayerCharacter'),'ISInventoryTransferUtil.lua',24},
  {own(util,'isCharacterGrabbingCorpseItem'),'ISInventoryTransferUtil.lua',29},
  {own(util,'isPlayerGrabbingCorpseItem'),'ISInventoryTransferUtil.lua',40},
 }
 if type(firstLine)~='function'or getFirstLineOfClosure~=firstLine then return end
 local watch=capture({
  {owner=_G,keys={'PZSurvivorToolkit','ISCharacterScreen','ISWorldObjectContextMenu','luautils','ISInventoryTransferUtil',
   'getActivatedMods','getFirstLineOfClosure','getSpecificPlayer','instanceof','ItemTag'}},
  {owner=Toolkit,keys={'ActionQueueRazorProducer','ActionQueueRazorRestoration','ActionQueueApproach'}},
  {owner=Producer,keys={'bind','observe','owns'}},
  {owner=boundOperations,keys={'producer'}},
  {owner=Proof,keys={'captureBindings','closure','matches','own'}},
  {owner=menu,keys={producer.method}}, {owner=world,keys={'equip','transferIfNeeded'}},
  {owner=utils,keys={'haveToBeTransfered','walkToContainer'}},
  {owner=util,keys={'newInventoryTransferAction','isPlayerCharacter','isCharacterGrabbingCorpseItem','isPlayerGrabbingCorpseItem'}},
 })
 if not watch then return end
 for _,entry in ipairs(source)do
  if not closure(entry[1],entry[2])or firstLine(entry[1])~=entry[3]or not watch()then return end
 end
 if not pinsQualified then
 for _,entry in ipairs({
  {'media/lua/client/XpSystem/ISUI/ISCharacterScreen.lua',4277275709},
  {'media/lua/client/ISUI/ISWorldObjectContextMenu.lua',3294329449},
  {'media/lua/shared/luautils.lua',937393183},
  {'media/lua/shared/TimedActions/ISInventoryTransferUtil.lua',4121924183},
 })do if not matches(entry[1],entry[2],nil,true)or not watch()then return end end
 pinsQualified=true
 end
 local approachWatch
 if walk~=wrappedWalk then
  approachWatch=capture({{owner=approach,keys={'nativeHelper','isContainer','isAction'}}})
  if not approachWatch or not closure(approach.isContainer,'ActionQueueApproach.lua')then return end
 end
 if type(consumer.observe)~='function'or type(consumer.finish)~='function'then return end
 local consumerWatch=capture({{owner=consumer,keys={'observe','finish','enabled'}}})
 if not consumerWatch then return end
 local episode={actor=actor,consumer=consumer,stage=1,approachOwner=approach,seen={},nativeCallback=callback,
  method=producer.method,profile=profile,style=style or ''}
 local function sourceCheck()
  return PZSurvivorToolkit==Toolkit and Toolkit.ActionQueueRazorProducer==Producer
   and Producer.bind==bind and Producer.observe==observe and Producer.owns==owns
   and Toolkit.ActionQueueOperations==boundOperations and boundOperations.producer==boundQuery
   and Proof.captureBindings==capture and Proof.closure==closure and Proof.matches==matches and Proof.own==own
   and watch()and consumerWatch()and consumer.enabled()==true
   and (not approachWatch or approachWatch()and approach.nativeHelper(utils,'walkToContainer',wrappedWalk)==walk)
   and noProvider()and watch()and consumerWatch()
 end
 episode.source=function()local ok,valid=pcall(sourceCheck);return ok and valid==true end
 if episode.source()then return episode end
end
owns=function(episode)
 if active~=episode or episode.invalid or episode.source()~=true then return false end
 local ok,callback,owner,method=pcall(boundQuery,episode.currentAction)
 return ok and callback==episode.nativeCallback and owner==ISCharacterScreen and method==episode.method
end
Producer.owns=owns
local function observeAction(action)
 local episode=active
 if not episode or episode.finalizing or episode.invalid or episode.seen[action] then return end
 if not episode.source()or action.character~=episode.actor then episode.invalid=true;return end
 episode.seen[action]=true
 local root=episode.actor:getInventory()
 if episode.stage==1 then
  if action.Type=='ISQueueActionsAction'and not episode.approach and episode.approachOwner then
   local command=own(action,'toolkitQueueCommand')
   local snapshot=type(command)=='table'and getmetatable(command)==nil and own(command,'snapshot')
   local args=type(snapshot)=='table'and getmetatable(snapshot)==nil and own(snapshot,'args')
   local source=type(args)=='table'and getmetatable(args)==nil and own(args,1)
   if source and episode.approachOwner.isContainer(action,source,episode.actor)then
    episode.approach,episode.approachSource=action,source;return
   end
  end
  if action.Type~='ISInventoryTransferAction'or not action.item or action.destContainer~=root
   or action.srcContainer==root or action.srcContainer~=action.item:getContainer()
   or episode.approach and(action.srcContainer~=episode.approachSource
    or not episode.approachOwner.isContainer(episode.approach,action.srcContainer,episode.actor))then episode.invalid=true;return end
  episode.tool,episode.pickup=action.item,action
 elseif episode.stage==2 then
  if action.Type~='ISEquipWeaponAction'or action.item~=episode.tool or action.primary~=true
   or action.twoHands~=nil and action.twoHands~=false or action.maxTime~=50 then episode.invalid=true;return end
  episode.equip=action
 elseif episode.stage==3 then
  if action.Type~=episode.profile.body or action.item~=episode.tool or action.maxTime~=300
   or action[episode.profile.styleField]~=episode.style then episode.invalid=true;return end
  episode.body=action
 else episode.invalid=true;return end
 episode.stage=episode.stage+1
 episode.currentAction=action
 local ok=pcall(episode.consumer.observe,episode,action)
 if not ok then episode.invalid=true end
end
observe=function(action)
 local ok=pcall(observeAction,action)
 if not ok and active then active.invalid=true end
end
Producer.observe=observe
dispatch=function(token,producer,callback,actor,style,...)
 local prepared,episode=pcall(prepare,producer,callback,actor,style,...)
 if not prepared then episode=nil end
 if not episode then return callback(actor,style,...)end
 local previous=active
 active=episode
 local function invoke(...)
  local results=pack(pcall(callback,...))
  if results[1]and not episode.invalid and episode.stage==4 and episode.source()then
   episode.finalizing=true
   pcall(episode.consumer.finish,episode)
  end
  if not results[1]then error(results[2],0)end
  return unpack(results,2,results.n)
 end
 local results=pack(pcall(boundRun,token,producer,invoke,actor,style,...))
 active=previous
 if not results[1]then error(results[2],0)end
 return unpack(results,2,results.n)
end
-- Bind once to the actual private queue runner. Public observers and a caller's
-- runner cannot construct the synchronous receipt consumed by owns().
bind=function(run)
 if boundRun then return end
 local operations=Toolkit.ActionQueueOperations
 if type(operations)~='table'or type(firstLine)~='function'
  or not closure(run,'ActionQueueOperations.lua')or firstLine(run)~=125
  or not closure(operations.producer,'ActionQueueOperations.lua')or firstLine(operations.producer)~=389
  or not matches('media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua',249283561,'PZSurvivorToolkit',true)then return end
 boundRun,boundQuery,boundOperations=run,operations.producer,operations
 return function(_,token,producer,callback,...)return dispatch(token,producer,callback,...)end
end
Producer.bind=bind
return Producer
