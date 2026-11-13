-- Shared source-backed Equip fixture; native effects remain explicit doubles.
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local f=assert(io.open(path));local value=f:read('*a');f:close();return value:gsub('\r','')
end
local function setup(changed,host)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 f.native('shared/ISBaseObject.lua');f.native('shared/TimedActions/ISBaseTimedAction.lua')
 -- Recreate the reader after the base reload, as in one coherent native VM.
 f.native('shared/TimedActions/ISReadABook.lua')
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
 toolkitEquipNativeQuiet=nil;toolkitEquipNativePreparedQuiet=nil;toolkitEquipEventDispatchApiMatches=nil
 if host then
  toolkitEquipNativeQuiet=function(actor,items)
   assert(actor==f.player and #items==1);certificate.quietItems=items
   if certificate.quietCallback then certificate.quietCallback()end
   return certificate.quiet~=false
  end
  toolkitEquipNativePreparedQuiet=function(actor,items,source)
   assert(actor==f.player and #items==1 and items[1]:getContainer()==source)
   certificate.quietItems=items;certificate.quietSource=source
   if certificate.quietCallback then certificate.quietCallback()end
   return certificate.quiet~=false
  end
  local quiet,prepared=toolkitEquipNativeQuiet,toolkitEquipNativePreparedQuiet
  toolkitEquipEventDispatchApiMatches=function(callback)return callback==quiet or callback==prepared end
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
  sourceText=function(path)return read(NativeActionRoot..'/'..path)end,
  mode=function(c,s)client,server=c,s end}
end
return setup
