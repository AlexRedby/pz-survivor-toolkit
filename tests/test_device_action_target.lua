-- Actual installed Lua constructors/delegates, with explicit world/DeviceData
-- doubles. Packet argument reconstruction is modeled; no Host transport runs.
if not NativeActionRoot then
 if TestCoverage then TestCoverage('source-contract','skipped','Exact device target requires --game or --native-action-root.')end
 return
end
local modulePath=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/DeviceActionTarget.lua'
local function setup(changed,foreign)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 f.native('shared/TimedActions/ISDeviceBatteryAction.lua')
 f.native('shared/TimedActions/ISDeviceMediaAction.lua')
 f.native('shared/RadioCom/ISRadioAction.lua')
 local oldInstance=instanceof
 instanceof=function(value,name)
  return oldInstance(value,name)or name=='IsoWaveSignal'and type(value)=='table'
   and(value.class=='IsoTelevision'or value.class=='IsoRadio')
 end
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 getGameFilesInput=function(path)
  local filename=NativeActionRoot..'/'..path:gsub('^media/lua/','')
  local text
  if NativeReadText then text=NativeReadText(filename)
  else local input=assert(io.open(filename));text=input:read('*a');input:close()end
  text=text:gsub('\r','')
  if changed then text=text..'-- unsupported source\n'end
  local position=1
  return {close=function()end,readLine=function()
   if position>#text then return end
   local boundary=text:find('\n',position,true)or #text+1
   local line=text:sub(position,boundary-1);position=boundary+1;return line
  end}
 end
 f.container=function()
  local value={class='ItemContainer',items={}}
  value.getItems=function(self)
   return {size=function()return #self.items end,get=function(_,index)return self.items[index+1]end}
  end
  value.getItemById=function(self,id)
   for _,item in ipairs(self.items)do if item:getID()==id then return item end end
  end
  value.getItemWithID=function(self,id)
   for _,item in ipairs(self.items)do if item:getID()==id then return item end end
  end
  return value
 end
 local root=f.container();f.player.inventory=root
 local nextID=0
 f.battery=function()
  nextID=nextID+1
  local item={class='DrainableComboItem',id=nextID,container=root,fullType='Base.Battery'}
  item.getID=function(self)return self.id end
  item.getFullType=function(self)return self.fullType end
  item.getContainer=function(self)return self.container end
  item.getMediaType=function()return 1 end
  root.items[#root.items+1]=item
  return item
 end
 local constructors={media=ISDeviceMediaAction.new,battery=ISDeviceBatteryAction.new,radio=ISRadioAction.new}
 local original={parameter=ISDeviceBatteryAction.getDeviceDataParameter,resolve=ISDeviceBatteryAction.getDeviceDataFromParameter,
  media=ISDeviceMediaAction.isValid,battery=ISDeviceBatteryAction.isValid}
 if foreign then PZSurvivorToolkit.DeviceActionTarget=foreign end
 local target=assert(loadfile(modulePath))()
 local function square()
  local value={class='IsoGridSquare',objects={}}
  value.getObjects=function(self)return {size=function()return #self.objects end,get=function(_,i)return self.objects[i+1]end}end
  value.getDeviceData=function(self)
   if self.vehicleData then return self.vehicleData end
   for _,object in ipairs(self.objects)do if instanceof(object,'IsoWaveSignal')then return object.data end end
  end
  return value
 end
 local function device(place,kind)
  local value={class=kind or 'IsoTelevision',square=place}
  local data={parent=value,media=false,battery=false,debits=0}
  value.data=data
  value.getSquare=function(self)return self.square end
  value.getDeviceData=function(self)return self.data end
  value.getObjectIndex=function(self)
   if self.square then for i,object in ipairs(self.square.objects)do if object==self then return i-1 end end end
   return -1
  end
  data.getParent=function(self)return self.parent end
  data.hasMedia=function(self)return self.media end
  data.getMediaType=function()return 1 end
  data.getIsBatteryPowered=function()return true end
  data.getHasBattery=function(self)return self.battery end
  data.addMediaItem=function(self,item)self.debits=self.debits+1;self.media=true;self.input=item end
  data.addBattery=function(self,item)
   -- Model the native direct-container debit; no transfer to pockets occurs.
   local container=item:getContainer();assert(container)
   for index,candidate in ipairs(container.items)do
    if candidate==item then table.remove(container.items,index);break end
   end
   self.debits=self.debits+1;self.battery=true;self.input=item;item.container=nil
  end
  place.objects[#place.objects+1]=value
  return value,data
 end
 return f,target,square,device,constructors,original
end
for _,kind in ipairs({'IsoTelevision','IsoRadio'})do
 for _,vehicleShadow in ipairs({false,true})do
  local f,target,square,device,constructors=setup()
  assert(target.isInstalled())
  local place=square();local first,firstData=device(place,kind);local selected,data=device(place,kind)
  if vehicleShadow then place.vehicleData={}end
  local item=f.battery()
  local parameter=ISDeviceBatteryAction:getDeviceDataParameter(f.player,selected,'IsoObject')
  assert(parameter==selected,'selected world object identity was reduced to its square')
  local media=ISDeviceMediaAction:new(f.player,false,item,parameter)
  local battery=ISDeviceBatteryAction:new(f.player,false,item,parameter)
  local radio=ISRadioAction:new('SetVolume',f.player,selected,.25)
  assert(media.deviceData==data and battery.deviceData==data and radio.deviceData==data)
  assert(media:isValid()and battery:isValid()and target.matches(parameter,selected,data))
  assert(not target.matches(parameter,first,firstData))
  assert(ISDeviceMediaAction.new==constructors.media and ISDeviceBatteryAction.new==constructors.battery
   and ISRadioAction.new==constructors.radio,'native constructor identity changed')
  -- Native NetTimedAction serializes the names in new's prototype, then calls
  -- that original constructor server-side. Reconstruct that argument contract.
  for _,action in ipairs({media,battery})do
   local rebuilt=getmetatable(action):new(action.character,action.isRemove,action.secondaryItem,action.parameter)
   assert(rebuilt.parameter==selected and rebuilt.deviceData==data and rebuilt:isValid())
  end
  place.objects={selected,first}
  assert(media:isValid()and battery:isValid()and target.matches(parameter,selected,data),'reorder changed selected device')
  assert(media:complete()and battery:complete())
  assert(data.debits==2 and data.input==item and firstData.debits==0,'native costs/effects targeted wrong device')
  data.media,data.battery=false,false
  place.objects={first}
  assert(not media:isValid()and not battery:isValid()and not target.matches(parameter,selected,data))
  local stale=ISDeviceMediaAction:new(f.player,false,item,parameter)
  local staleBattery=ISDeviceBatteryAction:new(f.player,false,item,parameter)
  assert(stale.deviceData==nil and staleBattery.deviceData==nil)
  assert(not stale:isValid()and not staleBattery:isValid(),'removed parameter reached native nil dereference')
  stale:complete();staleBattery:complete()
  assert(data.debits==2 and firstData.debits==0,'removed target fell back to neighbour')
 end
end
-- Replacement data and stale reverse links cannot inherit an existing command.
do
 local f,target,square,device=setup();local place=square();local selected,data=device(place)
 local action=ISDeviceMediaAction:new(f.player,true,nil,selected)
 data.media=true;selected.data={getParent=function()return selected end}
 assert(not action:isValid()and not target.matches(selected,selected,data))
 selected.data=data;data.parent={}
 assert(not action:isValid()and not target.matches(selected,selected,data))
 data.parent=selected;selected.square=square()
 assert(not action:isValid(),'foreign square without live membership accepted')
end
-- Native inventory IDs, vehicle squares and legacy square parameters are kept.
do
 local f,target,square,device=setup();local place=square();local selected,data=device(place)
 local itemData={};local item={getID=function()return 19 end,getDeviceData=function()return itemData end}
 f.player.inventory.getItemWithID=function(_,id)if id==19 then return item end end
 assert(ISDeviceBatteryAction:getDeviceDataParameter(f.player,item,'InventoryItem')==19)
 assert(ISDeviceBatteryAction:getDeviceDataFromParameter(f.player,19)==itemData)
 local vehicle={getSquare=function()return place end};place.vehicleData={}
 assert(ISDeviceBatteryAction:getDeviceDataParameter(f.player,vehicle,'VehiclePart')==place)
 assert(ISDeviceBatteryAction:getDeviceDataFromParameter(f.player,place)==place.vehicleData)
 assert(not target.matches(place,selected,data),'vehicle shadow must retain native legacy resolution')
 place.vehicleData=nil
 assert(target.matches(place,selected,data))
 local nextDevice=device(place);place.objects={nextDevice,selected}
 assert(not target.matches(place,selected,data),'legacy square lost its original exact data')
end
-- Battery costs require an exact direct container member on every native route.
-- Bags and nearby containers retain native direct debit without a pockets rule.
for _,route in ipairs({'world','inventory','vehicle'})do
 for _,loss in ipairs({'missing','vanished','loose-floor','proxy','detached','wrong-type','wrong-class'})do
  local f,target,square,device=setup();local place=square();local selected,data=device(place,'IsoRadio')
  local parameter=selected
  if route=='inventory'then
   parameter=91
   local directLookup=f.player.inventory.getItemWithID
   f.player.inventory.getItemWithID=function(self,id)
    if id==91 then return {getDeviceData=function()return data end}end
    return directLookup(self,id)
   end
  elseif route=='vehicle'then parameter=place end
  local item=f.battery()
  local action=ISDeviceBatteryAction:new(f.player,false,item,parameter)
  assert(action:isValid(),'available exact battery input was rejected')
  if loss=='missing'then action.secondaryItem=nil
  elseif loss=='vanished'then item.container=nil
  elseif loss=='loose-floor'then
   -- Native IsoWorldInventoryObject construction clears item.container;
   -- ContainerID.collectFloorItems does not restore that backlink on Host.
   item.container=nil;item.getWorldItem=function()return {class='IsoWorldInventoryObject',item=item}end
  elseif loss=='proxy'then f.player.inventory.items={f.battery()};f.player.inventory.items[1].id=item.id
  elseif loss=='detached'then
   f.player.inventory.items={}
   f.player.inventory.getItemById=function()return item end -- Recursive/backlink lookup alone is insufficient.
  elseif loss=='wrong-type'then item.fullType='OtherMod.Battery'
  else item.class='InventoryItem'end
  assert(not action:isValid(),'unsafe battery input accepted: '..route..'/'..loss)
  action:invoke();action:complete()
  assert(data.debits==0 and not data.battery,'rejected input reached native battery effect')
 end
 local f,target,square,device=setup();local place=square();local selected,data=device(place,'IsoRadio')
 data.battery=true
 local calls=0;data.getBattery=function(self)calls=calls+1;self.battery=false end
 local parameter=selected
 if route=='inventory'then
  parameter=91
  local directLookup=f.player.inventory.getItemWithID
  f.player.inventory.getItemWithID=function(self,id)
   if id==91 then return {getDeviceData=function()return data end}end
   return directLookup(self,id)
  end
 elseif route=='vehicle'then parameter=place end
 local removing=ISDeviceBatteryAction:new(f.player,true,nil,parameter)
 assert(removing:isValid())
 removing.secondaryItem=f.battery()
 assert(not removing:isValid());removing:invoke();assert(calls==0)
 removing.secondaryItem=nil
 assert(removing:isValid()and removing:complete()and calls==1 and not data.battery)
end
-- Native drag/drop may supply a bag or nearby-container battery directly.
-- Those routes debit that exact source and acquire no queue-edit root authority.
for _,route in ipairs({'world','inventory','vehicle'})do
 for _,source in ipairs({'root','bag','nearby-container'})do
  local f,target,square,device=setup();local place=square();local selected,data=device(place,'IsoRadio')
  local parameter=selected
  if route=='inventory'then
   parameter=91
   local directLookup=f.player.inventory.getItemWithID
   f.player.inventory.getItemWithID=function(self,id)
    if id==91 then return {getDeviceData=function()return data end}end
    return directLookup(self,id)
   end
  elseif route=='vehicle'then parameter=place end
  local item=f.battery();local container=f.player.inventory
  if source~='root'then
   container=f.container();f.player.inventory.items={};item.container=container;container.items={item}
  end
  local action=ISDeviceBatteryAction:new(f.player,false,item,parameter)
  assert(action:isValid(),'native direct-container battery route rejected: '..route..'/'..source)
  assert(action:complete()and data.debits==1 and data.input==item and data.battery)
  assert(item:getContainer()==nil and #container.items==0,'native model failed to debit exact battery source')
  assert(container==f.player.inventory or #f.player.inventory.items==0,'battery was transferred to pockets')
 end
end
-- Native getItemWithID is direct, returns the first ID match and does not
-- walk nested bags. Exact direct input remains required, including stale IDs.
for _,case in ipairs({'direct','duplicate-before','duplicate-after','nested-only','nested-duplicate-before'})do
 local f,target,square,device=setup();local place=square();local selected,data=device(place,'IsoRadio')
 local item=f.battery();local root=f.player.inventory
 local proxy=f.battery();proxy.id=item.id
 local bag={class='InventoryContainer',id=-1,items={}}
 bag.getID=function(self)return self.id end
 if case=='duplicate-before'then root.items={proxy,item}
 elseif case=='duplicate-after'then root.items={item,proxy}
 elseif case=='nested-only'then bag.items={item};root.items={bag}
 elseif case=='nested-duplicate-before'then bag.items={proxy};root.items={bag,item}
 else root.items={item}end
 -- A recursive lookup could find the item in a bag even when the item's
 -- container backlink claims root; it cannot establish direct membership.
 local function recursive(container,id)
  for _,value in ipairs(container.items)do
   if value:getID()==id then return value end
   if value.items then local found=recursive(value,id);if found then return found end end
  end
 end
 root.getItemById=function(self,id)return recursive(self,id)end
 local oldAccepted=root:getItemById(item:getID())==item
 if oldAccepted then
  oldAccepted=false
  for _,value in ipairs(root.items)do if value==item then oldAccepted=true;break end end
 end
 local expected=case~='duplicate-before'and case~='nested-only'
 if case~='nested-duplicate-before'then assert(oldAccepted==expected,'original guard comparison changed')
 else assert(not oldAccepted,'recursive lookup unexpectedly ignored earlier nested ID collision')end
 -- The production guard must not invoke recursive lookup or bridge each
 -- direct list item through getItems after the native direct lookup exists.
 root.getItemById=function()error('recursive battery lookup must not run')end
 root.getItems=function()error('Lua direct membership scan must not run')end
 local calls,directLookup=0,root.getItemWithID
 root.getItemWithID=function(self,id)calls=calls+1;return directLookup(self,id)end
 local action=ISDeviceBatteryAction:new(f.player,false,item,selected)
 assert(action:isValid()==expected,'direct native battery guard edge case: '..case)
 assert(calls==1,'battery guard repeated the direct native lookup')
end
-- Binding exports carry captured delegates and authorize only owned replacements.
do
 local f,target,_,_,_,original=setup()
 local helper,np,nr,rp,rr=target.binding()
 local media,nmv,gmv,battery,nbv,gbv=target.validityBinding()
 assert(helper==ISDeviceBatteryAction and np==original.parameter and nr==original.resolve)
 assert(media==ISDeviceMediaAction and battery==helper and nmv==original.media and nbv==original.battery)
 for _,entry in ipairs({{helper,'getDeviceDataParameter',rp},{helper,'getDeviceDataFromParameter',rr},
  {media,'isValid',gmv},{helper,'isValid',gbv}})do assert(target.authorizes(unpack(entry)))end
 assert(not target.authorizes(helper,'isValid',function()end))
 assert(assert(loadfile(modulePath))()==target,'shared auto-load/require reentry replaced owned module')
 local originalWorld,calls=target.world,0
 target.world=function()calls=calls+1;error('foreign world callback must not execute')end
 assert(not target.matches({}, {}, {})and calls==0,'matching invoked a changed public callback')
 target.world=originalWorld
 getGameFilesInput=function()return nil end
 assert(not target.authorizes(helper,'getDeviceDataParameter',rp),'lost source proof retained adoption permission')
end
do
 local _,target,_,_,_,original=setup(true)
 assert(not target.isInstalled()and ISDeviceBatteryAction.getDeviceDataParameter==original.parameter
  and ISDeviceMediaAction.isValid==original.media,'changed native source was patched')
end
do
 local calls=0
 local foreign={authorizes=function()calls=calls+1;error('foreign module must not execute')end}
 local _,target=setup(false,foreign)
 assert(not target.isInstalled()and calls==0 and PZSurvivorToolkit.DeviceActionTarget==foreign)
end
if TestCoverage then TestCoverage('source-contract','passed')end
print('Exact world device target: native constructors, selected binding, stale rejection and unchanged native routes passed; Host transport not executed.')

-- A removed native NetObject decodes to nil before the server constructor.
-- Both constructors still return an action; validity/complete must reject its
-- absent DeviceData without dereferencing nil or invoking an effect.
do
 local f,target=setup()
 assert(target.isInstalled())
 for _,class in ipairs({ISDeviceMediaAction,ISDeviceBatteryAction})do
  for _,remove in ipairs({false,true})do
   local action=class:new(f.player,remove,not remove and f.battery()or nil,nil)
   assert(action.deviceData==nil and not action:isValid())
   assert(action:complete(),'native complete remains a no-effect completion for invalid decoded targets')
  end
 end
end
