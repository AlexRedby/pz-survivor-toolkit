-- Source-owner test. The effect provider below is an explicit test double:
-- it proves the Equip boundary, not selected-mod neutrality or live Host.
if not NativeActionRoot then
 if TestCoverage then TestCoverage('source-contract','skipped','Equip source owner requires --game or --native-action-root.')end
 return
end
NativeKahluaTableLookup=true
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local f=assert(io.open(path));local value=f:read('*a');f:close();return value:gsub('\r','')
end
local function setup(changed)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 f.native('shared/ISBaseObject.lua');f.native('shared/TimedActions/ISBaseTimedAction.lua')
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)
  -- Mirror native first-instruction metadata for these source-backed methods.
  -- Lua 5.1 debug.linedefined reports the declaration instead.
  local info=debug.getinfo(callback,'S');local text=read(info.source:gsub('^@',''));local lines={}
  for value in (text..'\n'):gmatch('(.-)\n')do lines[#lines+1]=value end
  for number=info.linedefined+1,info.lastlinedefined do
   local value=lines[number]:match('^%s*(.-)%s*$')
   if value~=''and not value:match('^%-%-')then return number end
  end
 end
 local function input(path)
  local value=read(path)
  if changed and path:find(changed,1,true)then value=value..'-- unreviewed\n'end
  local cursor=1
  return {close=function()end,readLine=function()
   if cursor>#value then return end
   local boundary=value:find('\n',cursor,true)or #value+1
   local result=value:sub(cursor,boundary-1);cursor=boundary+1;return result
  end}
 end
 getGameFilesInput=function(path)return input(NativeActionRoot..'/'..path:gsub('^media/lua/',''))end
 getModFileReader=function(mod,path)assert(mod=='PZSurvivorToolkit');return input(ProjectRoot..'/PZSurvivorToolkit/42/'..path)end
 local client,server=false,false
 isClient=function()return client end;isServer=function()return server end;isMultiplayer=function()return client or server end
 ItemTag={REPLACE_PRIMARY={},WEARABLE={},LIGHTER={}};ItemType={RADIO={}}
 local actor=f.player;actor.class='IsoPlayer'
 local root={class='ItemContainer',items={},getParent=function()return actor end,getContainingItem=function()end}
 root.getItemWithID=function(self,id)return self.items[id]end
 actor.inventory=root
 actor.getPrimaryHandItem=function()return actor.primary end;actor.getSecondaryHandItem=function()return actor.secondary end
 actor.getClothingItem_Back=function()return actor.back end
 actor.isEquippedClothing=function(_,item)return item.worn==true end
 local hotbar={isItemAttached=function(_,item)return item.attached==true end}
 getPlayerHotbar=function()return hotbar end
 getClassSimpleName=function(value)return type(value)=='table'and value.class or 'KahluaClosure'end
 instanceof=function(value,kind)return type(value)=='table'and(value.class==kind or kind=='InventoryItem'and(value.class=='ComboItem'or value.class=='HandWeapon'or value.class=='InventoryContainer'))end
 local effects=0
 getPlayerInventory=function()effects=effects+1;error('inventory UI effect executed')end
 sendEquip=function()effects=effects+1;error('network effect executed')end
 triggerEvent=function()effects=effects+1;error('clothing effect executed')end
 syncItemActivated=function()effects=effects+1;error('activation effect executed')end
 instanceItem=function()effects=effects+1;error('item factory executed')end
 f.native('shared/TimedActions/ISEquipWeaponAction.lua')
 local proof=f.project('SourceProof');local hands=f.project('ActionQueueHands');local model=f.project('ActionQueueEditModel')
 local helper,isHeavy=forceDropHeavyItems,isForceDropHeavyItem
 local certificate={allow=true,checks=0,requests=0}
 -- The source name deliberately states the owned provider seam. Production
 -- source bytes are still read separately; no mod effect is qualified here.
 local factory=assert(loadstring([[return function(state)
  return {certify=function(actor,items)
   state.requests=state.requests+1;state.items=items;state.actor=actor
   if state.before then state.before()end
   if not state.allow then return end
   local check=function()state.checks=state.checks+1;return state.allow and not state.stale and state.helpers() end
   if check()then return check end
  end}
 end]],'@media/lua/client/PZSurvivorToolkit/ActionQueueHandEffects.lua'))()
 certificate.helpers=function()return forceDropHeavyItems==helper and isForceDropHeavyItem==isHeavy end
 local provider=factory(certificate);PZSurvivorToolkit.ActionQueueHandEffects=provider
 local saved=require
 require=function(name)
  if name=='PZSurvivorToolkit/SourceProof'then return proof end
  if name=='PZSurvivorToolkit/ActionQueueEquip'then return PZSurvivorToolkit.ActionQueueEquip end
  if name=='PZSurvivorToolkit/ActionQueueEditModel'then return model end
  if name=='PZSurvivorToolkit/ActionQueueHands'then return hands end
  if name=='PZSurvivorToolkit/ActionQueueHandEffects'then return provider end
  return saved(name)
 end
 local owner=f.project('ActionQueueEquip')
 local function item(class,requiresBoth,handgun)
  local item=f.item(class=='HandWeapon'and'Base.Screwdriver'or'Base.Nails');item.class=class or'ComboItem'
  item.container=root;item.requiresBoth=requiresBoth==true;item.twoHand=item.requiresBoth;item.swing=handgun and'Handgun'or'Other'
  item.getContainer=function(self)return self.container end
  item.getAttachedSlot=function(self)return self.attachedSlot or -1 end
  item.isForceDropHeavyItem=function(self)return self.heavy==true end
  item.canBeActivated=function(self)return self.activation==true end
  item.getWorldItem=function(self)return self.world end;item.getIsCraftingConsumed=function(self)return self.crafting==true end
  item.hasTag=function(self,tag)return self.tags and self.tags[tag]==true or false end
  item.isRequiresEquippedBothHands=function(self)return self.requiresBoth end
  item.isTwoHandWeapon=function(self)return self.twoHand end;item.getSwingAnim=function(self)return self.swing end
  item.getName=function()return 'Item'end
  root.items[item:getID()]=item;return item
 end
 local function action(item,primary,two)
  local result=ISEquipWeaponAction:new(actor,item,50,primary,two,nil);result.toolkitQueueOperation={};return result
 end
 return {owner=owner,f=f,actor=actor,root=root,item=item,action=action,model=model,proof=proof,hands=hands,
  provider=provider,certificate=certificate,effects=function()return effects end,
  mode=function(c,s)client,server=c,s end}
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
 assert(contract.items[back:getID()]and contract.equipment==s.actor and #contract.edit.resources==3)
 assert(#s.certificate.items==1,'worn backpack was passed as a hand-transition input')
 back.tags={[ItemTag.REPLACE_PRIMARY]=true}
 assert(not s.owner.inspect(action),'replace-primary back branch gained contract')
end
-- Actual shared Policy routing uses the new source owner, while the effect
-- provider remains the explicit double above. No native effect is executed.
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
