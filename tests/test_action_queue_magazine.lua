-- Installed native action/producers and real Policy; Java state/transport are
-- explicit doubles here. Native SP/Host conservation is a separate bank.
if not NativeActionRoot then
 if TestCoverage then TestCoverage('source-contract','skipped','Magazine contracts require --game.')end
 return
end
NativeKahluaTableLookup=true
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local f=assert(io.open(path));local text=f:read('*a');f:close();return text:gsub('\r','')
end
local function setup(changed,observePlainReads,withFirearm)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 for _,path in ipairs({'shared/ISBaseObject.lua','shared/TimedActions/ISBaseTimedAction.lua',
  'client/TimedActions/ISTimedActionQueue.lua','client/TimedActions/ISQueueActionsAction.lua',
  'shared/TimedActions/ISReadABook.lua','client/TimedActions/ISInventoryTransferAction.lua'})do f.native(path)end
 Events.OnPressReloadButton={Add=function()end};Events.OnPressRackButton={Add=function()end}
 Events.OnWeaponSwingHitPoint={Add=function()end};Events.OnPlayerAttackFinished={Add=function()end}
 Events.OnFillInventoryObjectContextMenu={Add=function()end};Hook={Attack={Add=function()end}}
 f.native('shared/TimedActions/ISReloadWeaponAction.lua');f.native('shared/TimedActions/ISRackFirearm.lua')
 f.native('shared/TimedActions/ISUnloadBulletsFromMagazine.lua')
 if withFirearm then f.native('shared/TimedActions/ISUnloadBulletsFromFirearm.lua')end
 f.native('shared/RadioCom/ISRadioAction.lua');f.native('shared/TimedActions/ISWringClothing.lua')
 for _,path in ipairs({'Fluids/ISFluidUtil.lua','Fluids/ISFluidContainer.lua','Fluids/ISFluidTransferAction.lua',
  'Fluids/ISFluidEmptyAction.lua','TimedActions/ISTransferAction.lua','TimedActions/ISDrinkFluidAction.lua'})do f.native('shared/'..path)end
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined end
 local function input(path)
  local text=read(path)
  if changed and path:find(changed,1,true)then text=text..'-- unreviewed source\n'end
  local position=1
  return {close=function()end,readLine=function()
   if position>#text then return end
   local boundary=text:find('\n',position,true)or #text+1
   local line=text:sub(position,boundary-1);position=boundary+1;return line
  end}
 end
 getGameFilesInput=function(path)return input(NativeActionRoot..'/'..path:gsub('^media/lua/',''))end
 getModFileReader=function(mod,path)
  assert(mod=='PZSurvivorToolkit');return input(ProjectRoot..'/PZSurvivorToolkit/42/'..path)
 end
 local modules={};local inheritedRequire=require
 require=function(name)
  if name:match('^PZSurvivorToolkit/')then
   local leaf=name:match('/([^/]+)$')
   if leaf=='SourceProof'or leaf=='ActionQueueEditModel'or leaf=='ActionQueueEditAdapters'
    or leaf=='ActionQueueFirearms'or leaf=='ActionQueueMagazine'or leaf=='ActionQueueWring'
    or leaf=='BulkActions'or leaf=='BulkFirearms'then
    if not modules[name]then modules[name]=f.project(leaf)or PZSurvivorToolkit[leaf]or true end
    return modules[name]
   end
  end
  return inheritedRequire(name)
 end
 local client,server=false,false
 isClient=function()return client end;isServer=function()return server end;isMultiplayer=function()return client or server end
 local nativeGlobals={}
 getClassSimpleName=function(value)
  if nativeGlobals[value]then return 'LuaJavaInvoker'end
  return type(value)=='function'and 'KahluaClosure'or type(value)=='table'and value.class
 end
 nativeGlobals[getClassSimpleName]=true
 local oldInstanceof=instanceof
 instanceof=function(value,kind)return oldInstanceof(value,kind)or type(value)=='table'and
  (kind=='InventoryItem'and(value.class=='ComboItem'or value.class=='Clothing'or value.class=='HandWeapon')or kind=='IsoGameCharacter'and value.class=='IsoPlayer')end
 CharacterActionAnims={RemoveBullets='remove',Reload='reload'};Metabolics={LightDomestic='light'}
 Perks={Reloading='reload'};MoodleType={PANIC='panic'};ItemBodyLocation={AMMO_STRAP='strap'}
 ItemTag={RELOAD_FAST_SHELLS='shells',RELOAD_FAST_BULLETS='bullets',RELOAD_FAST_MAGAZINES='magazines'}
 ItemType={NORMAL='base:normal'}
 AmmoType={}
 for _,name in ipairs({'BULLETS_9MM','SHOTGUN_SHELLS'})do
  AmmoType[name]={key=name=='BULLETS_9MM'and 'Base.Bullets9mm'or 'Base.ShotgunShells',getItemKey=function(self)return self.key end}
 end
 local scripts={}
 local function script(key)
  local value={getFullName=function()return key end,getItemType=function()return 'base:normal'end}
  for _,name in ipairs({'getLuaCreate','getItemConfig','getItemConfigKey','getReplaceOnUse','getReplaceOnDeplete','getOnBreak'})do
   value[name]=function(self)return self[name..'Value']end
  end
  value.hasComponents=function(self)return self.components==true end
  value.getObsolete=function(self)return self.obsolete==true end
  scripts[key]=value;return value
 end
 script('Base.9mmClip');script('Base.ShotgunClip');script('Base.Bullets9mm');script('Base.ShotgunShells')
 ScriptManager={instance={getItem=function(_,key)return scripts[key]end}}
 local actor=f.player;actor.class='IsoPlayer';actor.vars={}
 local root={class='ItemContainer',items={},getType=function()return 'none'end,getParent=function()return actor end,
  getContainingItem=function()end,getAcceptItemFunction=function()end,getOnlyAcceptCategory=function()end,
  getCapacityWeight=function()return 0 end,getEffectiveCapacity=function()return 100 end}
 root.getItemWithID=function(self,id)for _,v in ipairs(self.items)do if v:getID()==id then return v end end end
 root.getItemById=root.getItemWithID
 root.contains=function(self,item)for _,v in ipairs(self.items)do if v==item then return true end end;return false end
 root.containsID=function(self,id)return self:getItemWithID(id)~=nil end
 root.AddItem=function(self,item)self.items[#self.items+1]=item;return item end
 actor.inventory=root
 actor.getPrimaryHandItem=function()return actor.primary end;actor.getSecondaryHandItem=function()return actor.secondary end
 actor.getWornItem=function()end;actor.hasEquippedTag=function()return false end;actor.hasWornTag=function()return false end
 actor.isEquippedClothing=function(_,item)return item.worn==true end;actor.getVehicle=function()end
 actor.getPerkLevel=function()return 0 end;actor.getMoodles=function()return{getMoodleLevel=function()return 0 end}end
 actor.setVariable=function(_,key,value)actor.vars[key]=value end
 actor.getVariableFloat=function(_,key,default)return actor.vars[key]or default end
 actor.getAnimationTimeDelta=function()return .1 end;actor.setMetabolicTarget=function()end
 local created,sent,synced,weaponSyncs=0,0,0,0
 instanceItem=function(key)created=created+1;return f.item(key)end
 sendAddItemToContainer=function()sent=sent+1 end;syncItemFields=function()synced=synced+1 end
 syncHandWeaponFields=function()weaponSyncs=weaponSyncs+1 end;emulateAnimEventOnce=function()end
 local scheduled={}
 emulateAnimEvent=function(net,time,event,parameter)scheduled[#scheduled+1]={net,time,event,parameter}end
 for _,name in ipairs({'instanceItem','sendAddItemToContainer','syncItemFields','syncHandWeaponFields','emulateAnimEventOnce','emulateAnimEvent'})do nativeGlobals[_G[name]]=true end
 local function magazine(count,ammo)
  local item=f.item(ammo==AmmoType.SHOTGUN_SHELLS and 'Base.ShotgunClip'or 'Base.9mmClip')
  item.class='ComboItem';item.count=count==nil and 3 or count;item.container=root;item.ammo=ammo or AmmoType.BULLETS_9MM
  item.getContainer=function(self)return self.container end;item.getScriptItem=function(self)return scripts[self:getFullType()]end
  item.getCurrentAmmoCount=function(self)self.countReads=(self.countReads or 0)+1;return self.count end
  item.setCurrentAmmoCount=function(self,count)self.count=count end
  item.getAmmoType=function(self)return self.ammo end;item.getMaxAmmo=function()return 15 end
  item.isFavorite=function(self)return self.favorite==true end
  item.setJobType=function()end;item.setJobDelta=function()end
  root.items[#root.items+1]=item;return item
 end
 -- Execute the installed native producer, without loading unrelated UI setup.
 local ui=read(NativeActionRoot..'/client/ISUI/ISInventoryPaneContextMenu.lua')
 local a=assert(ui:find('ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine = function',1,true))
 local b=assert(ui:find('ISInventoryPaneContextMenu.getEvoItemCategories',a,true))
 assert(loadstring(ui:sub(a,b-1),'@media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'))()
 if withFirearm then
  local ga=assert(ui:find('ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm = function',1,true))
  local gb=assert(ui:find('ISInventoryPaneContextMenu.doMagazineMenu = function',ga,true))
  assert(loadstring(ui:sub(ga,gb-1),'@media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'))()
  -- Admission-only gun scenarios: the separate native bank proves the actual
  -- A,B,A,B equip chain. This double emits no equip or held-input permission.
  ISInventoryPaneContextMenu.equipWeapon=function()end
 end
 ISInventoryPaneContextMenu.transferIfNeeded=function()end
 PZSurvivorToolkit.Settings.bulkUnload=function()return true end
 require('PZSurvivorToolkit/BulkActions')
 local bindingScans={plain=0,action=0};local watchedPlain,watchedAction={},nil
 if observePlainReads then
  local proof=require('PZSurvivorToolkit/SourceProof')
  watchedPlain[PZSurvivorToolkit],watchedPlain[proof]=true,true
  local ordinaryPairs=pairs
  -- Instrument only BulkFirearms' captured iterator; restore the global before
  -- other consumers load, so this measures its own() calls specifically.
  pairs=function(owner)
   if watchedPlain[owner]then bindingScans.plain=bindingScans.plain+1 end
   if owner==watchedAction then bindingScans.action=bindingScans.action+1 end
   return ordinaryPairs(owner)
  end
  require('PZSurvivorToolkit/BulkFirearms')
  pairs=ordinaryPairs
  watchedPlain[PZSurvivorToolkit.BulkFirearms]=true
 else require('PZSurvivorToolkit/BulkFirearms')end
 f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
 local policy=f.project('ActionQueuePolicy');f.project('ActionQueueLabels');f.project('ActionQueue')
 local adapter=assert(PZSurvivorToolkit.ActionQueueMagazine);local installed=adapter.install()
 if not changed then assert(installed,'native magazine binding failed')end
 local function action(item,owned)
  if not owned then local value=ISUnloadBulletsFromMagazine:new(actor,item);value.toolkitQueueOperation={};return value end
  local values={};local add=ISTimedActionQueue.add
  ISTimedActionQueue.add=function(value)values[#values+1]=value;return value end
  local entry={item=item,kind=item.class=='HandWeapon'and 'gun'or 'magazine'}
  PZSurvivorToolkit.BulkFirearms.queueUnload(actor,{entry})
  ISTimedActionQueue.add=add
  assert(#values==1,'root producer unexpectedly expanded');values[1].toolkitQueueOperation={};return values[1],entry
 end
 local function firearm(count)
  assert(withFirearm)
  local gun=magazine(count,AmmoType.SHOTGUN_SHELLS);gun.class='HandWeapon';gun.chamber=true;gun.spent=2
  gun.getFullType=function()return 'Base.Shotgun'end;gun.getMagazineType=function()end
  gun.getWeaponReloadType=function()return 'shotgun'end;gun.isInsertAllBulletsReload=function()return false end
  gun.setJobDelta=function(self,value)self.jobDelta=value end
  for _,name in ipairs({'getEjectAmmoStartSound','getEjectAmmoStopSound','getEjectAmmoSound'})do gun[name]=function()end end
  return gun
 end
 return {f=f,root=root,actor=actor,magazine=magazine,firearm=firearm,weaponSyncs=function()return weaponSyncs end,installed=installed,action=action,adapter=adapter,policy=policy,
  definitions=PZSurvivorToolkit.ActionQueueDefinitions,scripts=scripts,bulk=PZSurvivorToolkit.BulkFirearms,
  bindingScans=bindingScans,watchPlain=function(owner)watchedPlain[owner]=true end,
  watchAction=function(owner)watchedAction=owner end,
  mode=function(c,s)client,server=c,s end,counts=function()return created,sent,synced end,scheduled=scheduled}
end

for _,owned in ipairs({false,true})do
 local s=setup();local item=s.magazine();local action=s.action(item,owned)
 local constructor,event=ISUnloadBulletsFromMagazine.new,ISUnloadBulletsFromMagazine.animEvent
 local reads=item.countReads or 0
 local descriptor,source=s.definitions.inspect(action)
 assert((item.countReads or 0)==reads+1,'matching duplicated mutable count/fact reads')
 assert(source==(owned and 'toolkit.bulk'or 'native.ISUnloadBulletsFromMagazine')and descriptor and descriptor.edit,
  'real native/owned action not uniquely migrated')
 assert(descriptor.edit.capacity=='external'and descriptor.edit.resources[1].effects[1].set==0)
 assert(descriptor.edit.resources[1].facts.item==item and descriptor.edit.resources[1].requires[1].equal==s.root)
 assert(descriptor.outputTypes['Base.Bullets9mm']and descriptor.freshOutputTypes['Base.Bullets9mm'])
 assert(descriptor.equipment==s.actor and next(descriptor.targets)==nil and descriptor.items[item:getID()])
 assert(s.counts()==0 and item.count==3,'inspection executed native consumption/output or owned guard')
 if owned then
  local guard=action.isValidStart
  assert(s.bulk.magazineUnloadBinding(action,guard))
  assert(guard(action),'owned native start guard rejected original item')
 end
 action.ammoCountStart=3;action.action={}
 item.getCurrentAmmoCount=function()error('active count read')end
 local active=s.adapter.inspect(action)
 assert(active and not active.edit and not active.moveRequiresProjection and not active.cancelWaiting and not active.cancelOperation,'active gained edit authority')
 assert(ISUnloadBulletsFromMagazine.new==constructor and ISUnloadBulletsFromMagazine.animEvent==event,'execution callbacks were replaced')
end

-- Real Policy must project distinct same-caliber pending magazines behind an
-- active unload, while keeping active itself outside editing authority.
do
 local s=setup();local current=s.action(s.magazine(),true);current.action={}
 local a=s.action(s.magazine(),true);local b=s.action(s.magazine(),true)
 local q=s.f.queue(current,a,b)
 local cancelContext={}
 local cancel=s.policy.evaluateCancel(q,a,true,cancelContext)
 assert(cancelContext.editFallback==nil,'positive cancellation fell back to legacy')
 assert(cancel.allowed,'independent same-caliber pending cancellation behind active unload rejected: '..tostring(cancel.reason))
 local moveContext={}
 local move=s.policy.evaluateMove(q,b,a,false,moveContext)
 assert(moveContext.editFallback==nil,'positive move fell back to legacy')
 assert(move.allowed,'independent same-caliber move behind active unload rejected: '..tostring(move.reason))
 assert(not s.policy.evaluateCancel(q,current,true).allowed and not s.policy.evaluateMove(q,current,b,true).allowed,'active unload gained permission')

end

-- A source-owned active footprint is not a completed count projection. This
-- move must not regain a weaker permit through a legacy incomplete path.
-- Removing untouched pending work remains allowed when no dependent tail exists.
for _,operation in ipairs({'move','cancel'})do
 local s=setup();local item=s.magazine();local head=s.action(item,true);head.action={}
 local pending=s.action(item,true);local other=s.action(s.magazine(),true)
 local q=s.f.queue(head,pending,other);local context={}
 local result
 if operation=='move'then result=s.policy.evaluateMove(q,pending,other,true,context)
 else result=s.policy.evaluateCancel(q,pending,true,context)end
 if operation=='move'then
  assert(not result.allowed,'shared active magazine move escaped incomplete common projection: '..tostring(context.editFallback and context.editFallback.reason))
 else
  assert(result.allowed,'untouched pending cancellation wrongly claimed active effect')
  assert(q.current==head and q.queue[1]==head and q.queue[2]==pending and item.count==3 and s.counts()==0,
   'cancellation preview changed active/paid state')
 end
end

-- Unsupported native loading consumes by type. Output/selector edges must not
-- disappear just because the producer now has a complete common contract.
for _,same in ipairs({false,true})do
 local s=setup();s.f.native('shared/TimedActions/ISLoadBulletsInMagazine.lua')
 local current=s.f.action(ISReadABook,{item=s.f.item('Base.Book')});current.action={}
 local item=s.magazine();local unload=s.action(item,true)
 local load=ISLoadBulletsInMagazine:new(s.actor,same and item or s.magazine(),3);load.toolkitQueueOperation={}
 local q=s.f.queue(current,unload,load)
 assert(not s.policy.evaluateCancel(q,unload,true).allowed,'unproven native ammo consumer gained cancellation')
 assert(not s.policy.evaluateMove(q,load,unload,false).allowed,'unproven ammo consumer moved before its producer')
 q=s.f.queue(current,load,unload)
 assert(not s.policy.evaluateMove(q,unload,load,false).allowed,'producer crossed unproven shared ammo consumer')
end

for _,mutation in ipairs({'count-negative','count-fraction','count-excess','bag','stale','class','favorite','callback','copied-guard','helper','output','output-components','input-script','missing-input-script','source-key'})do
 local s=setup();local item=s.magazine();local action=s.action(item,true)
 if mutation=='count-negative'then item.count=-1
 elseif mutation=='count-fraction'then item.count=.5
 elseif mutation=='count-excess'then item.count=16
 elseif mutation=='bag'then item.container={class='ItemContainer'}
 elseif mutation=='stale'then s.root.items={s.magazine()};s.root.items[1].id=item.id
 elseif mutation=='class'then item.class='InventoryItem'
 elseif mutation=='favorite'then item.favorite=true
 elseif mutation=='callback'then action.isValidStart=function()error('foreign guard invoked')end
 elseif mutation=='copied-guard'then local original=action;action=s.action(item);action.isValidStart=original.isValidStart;action.toolkitIndependentBulk=true;action.toolkitMagazineUnloadGuard=original.toolkitMagazineUnloadGuard
 elseif mutation=='helper'then ISReloadWeaponAction.setReloadSpeed=function()error('helper invoked')end
 elseif mutation=='output'then s.scripts['Base.Bullets9mm'].getLuaCreateValue='Foreign.Create'
 elseif mutation=='output-components'then s.scripts['Base.Bullets9mm'].components=true
 elseif mutation=='input-script'then s.scripts['Base.9mmClip'].getItemConfigValue='Foreign'
 elseif mutation=='missing-input-script'then s.scripts['Base.9mmClip']=nil
 elseif mutation=='source-key'then AmmoType.BULLETS_9MM.key='Base.Foreign'end
 assert(not s.adapter.inspect(action),'unsupported '..mutation..' gained contract')
 assert(s.counts()==0,'rejection executed native output')
end

-- One owner preserves prior unknown-output contracts/cancellation outside
-- the canonical/root/plain proof, without a second eligibility/fact pass.
for _,change in ipairs({'bag','stale','dirty-script','foreign-wrapper'})do
 local s=setup();local item=s.magazine();local action=s.action(item,true)
 if change=='bag'then item.container={class='ItemContainer'}
 elseif change=='stale'then s.root.items={}
 elseif change=='dirty-script'then s.scripts['Base.9mmClip'].getItemConfigValue='Foreign'
 else action.isValidStart=function()error('foreign guard invoked')end end
 local descriptor,source=s.definitions.inspect(action)
 assert(source=='toolkit.bulk'and descriptor and descriptor.unknownOutputs and not descriptor.edit,
  'unsupported '..change..' lost original bulk ownership')
 local head=s.action(s.magazine(),true);head.action={}
 local q=s.f.queue(head,action)
 assert(s.policy.evaluateCancel(q,action,true).allowed,'unsupported '..change..' lost untouched pending cancellation')
end

for _,slot in ipairs({'class','base','root','reload','proof','hidden-action'})do
 local s=setup();local action=s.action(s.magazine(),true);local calls=0
 local function foreign()calls=calls+1;error('foreign lookup invoked')end
 if slot=='class'then ISUnloadBulletsFromMagazine.__index=foreign
 elseif slot=='base'then ISBaseTimedAction.__index=foreign
 elseif slot=='root'then ISBaseObject.__index=foreign
 elseif slot=='reload'then ISReloadWeaponAction.__index=foreign
 elseif slot=='proof'then local proof=require('PZSurvivorToolkit/SourceProof');proof.nativeActionClassChain=nil;setmetatable(proof,{__index=foreign})
 else setmetatable(action,{__metatable=ISUnloadBulletsFromMagazine,__index=foreign})end
 assert(not s.adapter.matches(action)and calls==0,'foreign '..slot..' lookup executed while proving binding')
end

-- Plain module/receipt owners have already passed actual-metatable checks.
-- Unrelated growth must neither hit own()'s action-only bound nor enumerate
-- their entries during binding/inspection; inherited action slots still use it.
do
 local s=setup(nil,true);local item=s.magazine();local action,entry=s.action(item,true)
 local proof=require('PZSurvivorToolkit/SourceProof')
 for _,owner in ipairs({PZSurvivorToolkit,s.bulk,proof})do
  for index=1,256 do owner['unrelatedBindingField'..index]=true end
 end
 s.watchPlain(action.toolkitMagazineUnloadGuard);s.watchPlain(entry);s.watchAction(action)
 assert(s.bulk.magazineUnloadBinding(action,action.isValidStart),'unrelated module growth disabled owned binding')
 assert(s.adapter.inspect(action),'unrelated module growth disabled exact contract')
 assert(s.bindingScans.plain==0 and s.bindingScans.action>0,
  'binding enumerated a proven-plain owner or lost own-vs-inherited action proof')
end

-- The common bulk dispatcher also sees firearm unloads/weapon upgrades.
-- Wrong-class rejection reads no magazine proof slots or inherited Type.
do
 local s=setup();local proof=require('PZSurvivorToolkit/SourceProof')
 local original=proof.own;local proofReads,foreignReads=0,0
 proof.own=function(...)proofReads=proofReads+1;return original(...)end
 local foreign=setmetatable({},{__index=function()foreignReads=foreignReads+1;error('foreign bulk lookup invoked')end})
 assert(not s.adapter.matches(foreign)and not s.adapter.inspect(foreign))
 for _,name in ipairs({'ISUnloadBulletsFromFirearm','ISRemoveWeaponUpgrade'})do
  s.f.native('shared/TimedActions/'..name..'.lua')
  local other=s.f.action(_G[name],{})
  assert(not s.adapter.matches(other)and not s.adapter.inspect(other),'other native bulk family was inspected')
 end
 assert(not s.adapter.matches(false)and not s.adapter.inspect(42))
 assert(proofReads==0 and foreignReads==0,'unrelated bulk action paid magazine proof/inherited lookup')
 proof.own=original
end

-- Source/helper mismatches do not steal ownership from the conservative bulk
-- behavior. Native and owned starts both preserve native empty completion.
for _,file in ipairs({'ISUnloadBulletsFromMagazine.lua','ISReloadWeaponAction.lua','BulkFirearms.lua','ActionQueueFirearms.lua'})do
 local s=setup(file);local action=s.action(s.magazine(),true)
 assert(not s.adapter.matches(action),'changed source still owned: '..file)
 local contract,source=s.definitions.inspect(action)
 assert(source=='toolkit.bulk'and contract.unknownOutputs,'changed source lost conservative bulk fallback')
end
do
 local s=setup();local head=s.action(s.magazine(),true);head.action={}
 local item=s.magazine();local a,b=s.action(item,true),s.action(item,true)
 local q=s.f.queue(head,a,b)
 local moveContext={}
 local move=s.policy.evaluateMove(q,b,a,false,moveContext)
 assert(moveContext.editFallback==nil,'positive move fell back to legacy')
 assert(move.allowed,'repeated pending magazine must preserve native empty completion')
 local direct=s.action(s.magazine(0));assert(s.adapter.inspect(direct),'native direct empty no-op was rejected')
 local emptyOwned=s.action(s.magazine(),true);emptyOwned.magazine.count=0
 local descriptor=assert(s.adapter.inspect(emptyOwned))
 local model=PZSurvivorToolkit.ActionQueueEditModel
 assert(model.evaluate({{action=emptyOwned,edit=descriptor.edit}}).status=='allowed','owned native empty no-op was rejected')
 local original=s.action(s.magazine(),true);local guard=original.toolkitMagazineUnloadGuard
 local calls=0
 for key in pairs(guard)do guard[key]=function()calls=calls+1;error('foreign receipt invoked')end end
 assert(not s.bulk.magazineUnloadBinding(original,original.isValidStart)and calls==0,'inspection invoked a foreign receipt')
end

-- Actual native events, not a made-up complete debit: output one physical item
-- per event, duplicate events after zero do nothing, Host client pays nothing.
for _,mode in ipairs({'sp','client','server'})do
 local s=setup();local item=s.magazine(2);local action=s.action(item)
 s.mode(mode=='client',mode=='server');action.netAction={forceComplete=function()end}
 if mode=='server'then action:serverStart();assert(#s.scheduled==3)end
 action:animEvent('RemoveBullet');action.unloadedThisLoop=false;action:animEvent('RemoveBullet')
 action.unloadedThisLoop=false;action:animEvent('RemoveBullet');assert(action:complete())
 local created,sent,synced=s.counts()
 if mode=='client'then assert(item.count==2 and created==0 and sent==0 and synced==0)
 else assert(item.count==0 and created==2 and sent==2 and synced==2)end
 assert(item:getContainer()==s.root and s.root:getItemWithID(item:getID())==item,'persistent magazine was replaced/depleted')
end

-- Execute the native empty lifecycle separately from planning. Host client
-- requests completion; authority's empty events create/debit nothing.
for _,mode in ipairs({'sp','client','server'})do
 local s=setup();local item=s.magazine();local action=s.action(item,true)
 item.count=0;s.mode(mode=='client',mode=='server')
 assert(action:isValidStart()and action:isValid(),'execution admission rejected canonical empty magazine')
 local completed=0
 action.action={forceComplete=function()completed=completed+1 end}
 action.netAction={forceComplete=function()completed=completed+1 end}
 if mode=='server'then
  action:serverStart();assert(#s.scheduled==3,'native Host empty action lost event schedule')
  action:animEvent('RemoveBullet');action:animEvent('unloadFinished');action:animEvent('RemoveBullet')
 else action:start()end
 assert(completed==1 and action:complete(),'native empty lifecycle did not complete')
 local created,sent,synced=s.counts()
 assert(item.count==0 and created==0 and sent==0 and synced==0
  and s.root:getItemWithID(item:getID())==item,'empty native action changed resources')
end

-- Native progression must accept a retained, now-empty magazine as the same
-- no-op the vanilla action accepts. Reusing the menu's loaded-only filter at
-- start otherwise makes native onCompleted reset this independent tail.
for _,enabled in ipairs({false,true})do
 local s=setup();local item=s.magazine(2)
 local first=s.action(item,true);local repeated=s.action(item,true)
 local tail=s.action(s.magazine(3),true)
 local q=s.f.queue(first,repeated,tail)
 PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
 local starts,warnings={},0
 DebugType={Action={warn=function()warnings=warnings+1 end}}
 LuaTimedActionNew={new=function(body,actor)
  assert(actor==s.actor)
  local handle={body=body}
  handle.isStarted=function()return true end
  handle.finished=function()return handle.forceCompleted==true end
  handle.isForceComplete=function()return handle.forceCompleted==true end
  handle.forceComplete=function()handle.forceCompleted=true end
  handle.hasStalled=function()return false end
  handle.getTable=function()return body end
  return handle
 end}
 s.actor.setTimedActionToRetrigger=function()end
 s.actor.StartAction=function(_,handle)starts[#starts+1]=handle.body end
 first.action={isStarted=function()return true end,finished=function()return true end,
  isForceComplete=function()return false end,hasStalled=function()return false end,getTable=function()return first end}
 first.toolkitQueueOperation.toolkitStarted=true
 first:animEvent('RemoveBullet')
 first.updateLoadBulletsTime=.95;first:updateLoadingTime()
 first:animEvent('RemoveBullet');first:animEvent('unloadFinished')
 assert(first:complete())
 local created,sent,synced=s.counts()
 assert(item.count==0 and created==2 and sent==2 and synced==2,'first native unload did not pay exactly once')
 assert(not repeated.action and not repeated.started and repeated.ammoCountStart==nil,
  'retained repeat had already entered native execution')
 q:onCompleted(first)
 assert(q.current==repeated and q.queue[1]==repeated and q.queue[2]==tail and warnings==0,
  'empty-magazine start rejection cleared independent tail (queue='..tostring(enabled)..
  ', remaining='..tostring(#q.queue)..', native-reset-warnings='..tostring(warnings)..')')
 assert(starts[1]==repeated and #starts==1,'native retained no-op did not start exactly once')
 repeated:start()
 assert(repeated.action.forceCompleted==true,'native empty magazine did not request forceComplete')
 assert(repeated:complete())
 q:onCompleted(repeated)
 assert(q.current==tail and q.queue[1]==tail and #q.queue==1 and starts[2]==tail and #starts==2,
  'empty native no-op failed to preserve/start independent tail')
 local afterCreated,afterSent,afterSynced=s.counts()
 assert(item.count==0 and tail.magazine.count==3 and afterCreated==created and afterSent==sent and afterSynced==synced,
  'empty completion replayed paid effects or fabricated outputs')
end


-- Native-only firearm callbacks: selected companion wrapper delegation is a
-- separate native-bank proof. Reuse the item/actor/queue doubles above; the UI
-- producer's equip request is not executed in this admission-only source slice.
local function gunHandle(body)
 local handle={body=body}
 handle.isStarted=function()return true end
 handle.finished=function()return handle.forceCompleted==true end
 handle.isForceComplete=handle.finished
 handle.forceComplete=function()handle.forceCompleted=true end
 handle.hasStalled=function()return false end
 handle.getTable=function()return body end
 handle.setActionAnim=function()end;handle.setAnimVariable=function()end
 handle.setOverrideHandModelsObject=function()end
 return handle
end
local function gunEngine(s,started)
 LuaTimedActionNew={new=function(body,actor)assert(actor==s.actor);return gunHandle(body)end}
 s.actor.setTimedActionToRetrigger=function()end;s.actor.setIsFarming=function()end
 s.actor.clearVariable=function(_,key)assert(key=='isUnloading');s.actor.clearedUnload=true end
 s.actor.StartAction=function(_,handle)started[#started+1]=handle.body end
 ISLogSystem={logAction=function()end}
end
for _,enabled in ipairs({false,true})do
 local s=setup(nil,nil,true);local gun=s.firearm(2)
 local first=s.action(gun,true);local repeated=s.action(gun,true);local tail=s.action(s.magazine(3),true)
 local q=s.f.queue(first,repeated,tail);local started,warnings={},0
 PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
 DebugType={Action={warn=function()warnings=warnings+1 end}};gunEngine(s,started)
 first.action=gunHandle(first);first.toolkitQueueOperation.toolkitStarted=true
 first:start();first:animEvent('playReloadSound');first:animEvent('playReloadSound')
 first:animEvent('unloadFinished');first:update();assert(first:complete())
 local made,sent,magazineSync=s.counts();local weaponSync=s.weaponSyncs()
 assert(gun.count==0 and made==2 and sent==2 and magazineSync==0 and weaponSync==2,'first gun unload did not pay exactly once')
 assert(repeated.action==nil and repeated.ammoCountStart==nil,'retained empty gun was already allocated')
 q:onCompleted(first)
 assert(q.current==repeated and q.queue[1]==repeated and q.queue[2]==tail and warnings==0 and started[1]==repeated,
  'native empty-gun start refusal wiped independent tail: queue='..tostring(enabled))
 repeated:start();assert(repeated.ammoCountStart==0 and not repeated.action.forceCompleted,'native gun animation was fast-forwarded')
 repeated:update();assert(gun.jobDelta~=gun.jobDelta and not repeated.action.forceCompleted,'native transient NaN/update behavior changed')
 repeated:animEvent('playReloadSound');repeated:animEvent('unloadFinished');repeated:update()
 assert(repeated.action.forceCompleted and gun.jobDelta~=gun.jobDelta and repeated:complete())
 repeated:perform()
 assert(gun.jobDelta==0 and s.actor.clearedUnload and q.current==tail and q.queue[1]==tail and #q.queue==1
  and started[2]==tail and #started==2,'native empty gun cleanup/progression lost tail')
 local afterMade,afterSent,afterMagazineSync=s.counts()
 assert(afterMade==made and afterSent==sent and afterMagazineSync==magazineSync and s.weaponSyncs()==weaponSync
  and gun.count==0 and gun.chamber and gun.spent==2 and tail.magazine.count==3,'empty gun replayed/altered paid resources')
end
for _,mode in ipairs({'sp','client','server'})do
 local s=setup(nil,nil,true);local gun=s.firearm(2);local action=s.action(gun,true)
 gun.count=0;s.mode(mode=='client',mode=='server')
 assert(action:isValidStart()and action:isValid(),'native execution admission rejected retained empty gun')
 local started={};gunEngine(s,started);action.action=gunHandle(action)
 local serverCompleted=0;action.netAction={forceComplete=function()serverCompleted=serverCompleted+1 end}
 if mode=='server'then
  action:serverStart();assert(#s.scheduled==2)
  action:animEvent('playReloadSound');action:animEvent('unloadFinished')
  assert(serverCompleted==1 and not action.action.forceCompleted,'server empty completion lost native authority')
 else
  action:start();action:update();assert(gun.jobDelta~=gun.jobDelta and not action.action.forceCompleted)
  action:animEvent('playReloadSound');action:animEvent('unloadFinished');action:update()
  assert(action.action.forceCompleted and gun.jobDelta~=gun.jobDelta)
  s.f.queue(action);action:perform();assert(gun.jobDelta==0 and s.actor.clearedUnload)
 end
 assert(action:complete())
 local made,sent,magazineSync=s.counts()
 assert(gun.count==0 and made==0 and sent==0 and magazineSync==0 and s.weaponSyncs()==0
  and gun.chamber and gun.spent==2,'empty '..mode..' gun invented output or changed chamber/spent state')
end

if TestCoverage then TestCoverage('source-contract','passed')end
print('Magazine source-bound pending edits, owned guard binding, active footprints and native incremental conservation passed.')
