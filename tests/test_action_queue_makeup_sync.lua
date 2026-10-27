-- Execute the full native action/definitions; doubles cover Java API state.
if not NativeActionRoot then print('Native makeup output sync SKIP (requires game sources).');return end
next=nil
local modulePath=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/server/PZSurvivorToolkit/MakeupOutputSync.lua'
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function reader(text)
 local offset=1
 return {close=function()end,readLine=function()
  if offset>#text then return end
  local stop=text:find('\n',offset,true)or #text+1
  local line=text:sub(offset,stop-1);offset=stop+1;return line
 end}
end
local function list(values)
 return {size=function()return #values end,get=function(_,i)return values[i+1]end}
end
local nativeBody=assert(read(NativeActionRoot..'/shared/TimedActions/ISApplyMakeUp.lua'):match('function ISApplyMakeUp:complete%(%)(.-)\nend'))
local correctedBody=assert(read(modulePath):match('local function correctedComplete%(self%)(.-)\nend'))
local oldArgument='sendAddItemToContainer(self.character:getInventory(), self.item);'
local newArgument='sendAddItemToContainer(self.character:getInventory(), makeUpSelected);'
local first,last=assert(nativeBody:find(oldArgument,1,true))
assert(not nativeBody:find(oldArgument,last+1,true),'native packet argument is no longer unique')
local expected=nativeBody:sub(1,first-1)..newArgument..nativeBody:sub(last+1)
assert(correctedBody:gsub('%s+',' ')==expected:gsub('%s+',' '),'corrected body differs from native beyond its one packet argument')
local function setup(options)
 options=options or{}
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 f.native('shared/Definitions/MakeUpDefinitions.lua');f.native('shared/TimedActions/ISApplyMakeUp.lua')
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 getGameFilesInput=function(path)
  local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
  if options.changedSource and path:find(options.changedSource,1,true)then text=text..'-- unsupported source\n'end
  return reader(text)
 end
 local server,client=options.server~=false,options.client==true
 isServer=function()return server end;isClient=function()return client end
 local actor=f.player;actor.class='IsoPlayer';actor.worn={};actor.writes=0
 local recursiveCalls=0
 local function square(x,y,z)
  local value={x=x,y=y,z=z,objects={}}
  function value:getX()return self.x end;function value:getY()return self.y end;function value:getZ()return self.z end
  function value:getObjects()return list(self.objects)end;function value:getStaticMovingObjects()return list({})end
  function value:isBlockedTo()return options.wall==true end
  return value
 end
 local current,worldSquare=square(0,0,0),square(1,0,0)
 function actor:getCurrentSquare()return current end
 function actor:canAccessContainer(container)return container~=options.deniedContainer end
 getCell=function()return {getGridSquare=function(_,x,y,z)
  if worldSquare.x==x and worldSquare.y==y and worldSquare.z==z then return worldSquare end
 end}end
 getVehicleById=function()end
 SafeHouse={isSafehouseAllowLoot=function()return options.safehouse~=false end}
 local function outer(item)
  recursiveCalls=recursiveCalls+1
  local container=item:getContainer()
  for _=1,64 do
   if not container then return end
   local holder=container:getContainingItem()
   if not holder or not holder:getContainer()then return container end
   container=holder:getContainer()
  end
  error('recursive outer traversal reached malformed ancestry')
 end
 local function methods(container)
  container.class='ItemContainer';container.values={}
  function container:getItems()return list(self.values)end
  function container:getParent()return self.parent end
  function container:getContainingItem()return self.holder end
  function container:getVehiclePart()return self.part end
  function container:getSourceGrid()return self.square end
  function container:getItemById(id)for _,item in ipairs(self.values)do if item:getID()==id then return item end end end
  function container:isInCharacterInventory(player)
   recursiveCalls=recursiveCalls+1
   local cursor=self
   for _=1,64 do
    if cursor==player:getInventory()then return true end
    local holder=cursor:getContainingItem();cursor=holder and holder:getContainer()
    if not cursor then return false end
   end
   error('inventory ancestry reached malformed chain')
  end
  function container:getItemWithIDRecursiv(id)
   recursiveCalls=recursiveCalls+1
   local function search(cursor,depth)
    assert(depth<=32,'unsafe recursive item lookup preceded ancestry admission')
    for _,value in ipairs(cursor.values)do
     if value:getID()==id then return value end
     if value.class=='InventoryContainer'then local found=search(value:getInventory(),depth+1);if found then return found end end
    end
   end
   return search(self,1)
  end
  return container
 end
 local root=methods(actor.inventory);root.adds=0;root.removals=0
 function root:getParent()return actor end
 function root:getContainingItem()end
 function root:getItems()return list(self.values)end
 function root:getItemById(id)for _,item in ipairs(self.values)do if item:getID()==id then return item end end end
 function root:contains(item)for _,value in ipairs(self.values)do if value==item then return true end end;return false end
 function root:AddItem(item)
  self.adds=self.adds+1
  if options.noAdd then return end
  self.values[#self.values+1]=item;item.container=self
  if options.duplicateRef then self.values[#self.values+1]=item end
  if options.onAdd then options.onAdd(item)end
 end
 function root:Remove(item)
  self.removals=self.removals+1
  for i,value in ipairs(self.values)do if value==item then table.remove(self.values,i);item.container=nil;return end end
 end
 function actor:getWornItem(slot)return self.worn[slot]end
 function actor:setWornItem(slot,item)self.writes=self.writes+1;self.worn[slot]=item end
 local nativeInstanceof=instanceof
 instanceof=function(value,name)return type(value)=='table'and value.class=='Clothing'and name=='InventoryItem'or nativeInstanceof(value,name)end
 local scriptText=read(NativeActionRoot:gsub('/media/lua/?$','')..'/media/scripts/generated/items/clothing.txt')
 local locations,scripts={},{}
 for name,body in scriptText:gmatch('item%s+(MakeUp_[%w_]+)%s*{(.-)}')do
  local slot=assert(body:match('BodyLocation%s*=%s*([%w_:]+)'));locations[slot]=locations[slot]or{}
  scripts['Base.'..name]={class='Item',slot=locations[slot],getFullName=function()return'Base.'..name end,
   getBodyLocation=function(self)return self.slot end,getLuaCreate=function()return options.luaCreate end,
   getItemConfigKey=function()return options.configKey end,getItemConfig=function()return options.config end}
 end
 ItemBodyLocation={MAKE_UP_FULL_FACE=locations['base:makeup_fullface'],MAKE_UP_EYES=locations['base:makeup_eyes'],
  MAKE_UP_EYES_SHADOW=locations['base:makeup_eyesshadow'],MAKE_UP_LIPS=locations['base:makeup_lips']}
 local manager={class='ScriptManager',FindItem=function(_,kind)return scripts[kind]end}
 getScriptManager=function()return manager end
 local made,attempts=0,0
 local function item(kind,id)
  local script=assert(scripts[kind]);local value={class='Clothing',kind=kind,id=id,slot=script.slot}
  function value:getID()return self.id end;function value:getFullType()return self.kind end
  function value:getContainer()return self.container end;function value:getBodyLocation()return self.slot end
  function value:getScriptItem()return script end
  return value
 end
 instanceItem=function(kind)
  attempts=attempts+1
  if options.factoryError then error('native factory failed')end
  made=made+1;return item(kind,1000+made)
 end
 local kit=f.item('Base.MakeupEyes');kit.uses=5;kit.container=root
 function kit:getOutermostContainer()return outer(self)end;function kit:getWorldItem()end
 function kit:getContainer()return self.container end;function kit:getMakeUpType()return'All'end
 function kit:getCurrentUses()return self.uses end;function kit:Use()self.uses=self.uses-1 end
 root.values[1]=kit
 local function move(destination)
  local source=kit.container
  if source and source.values then for i=#source.values,1,-1 do if source.values[i]==kit then table.remove(source.values,i)end end end
  kit.container=destination
  if destination then destination.values[#destination.values+1]=kit end
 end
 local bagID=100
 local function bag(parent)
  bagID=bagID+1
  local holder={class='InventoryContainer',id=bagID,container=parent}
  local inventory=methods({holder=holder})
  function holder:getID()return self.id end;function holder:getContainer()return self.container end
  function holder:getInventory()return inventory end;function holder:getWorldItem()return self.world end
  function holder:getOutermostContainer()return outer(self)end
  if parent then parent.values[#parent.values+1]=holder end
  return inventory,holder
 end
 local function worldContainer()
  local container=methods({square=worldSquare})
  local object={class='IsoObject',getSquare=function()return worldSquare end,
   getContainerCount=function()return 1 end,getContainerByIndex=function(_,index)if index==0 then return container end end}
  container.parent=object;worldSquare.objects[#worldSquare.objects+1]=object
  return container,object
 end
 local function worldBag()
  local container,holder=bag()
  local object={class='IsoWorldInventoryObject',getSquare=function()return worldSquare end,getItem=function()return holder end}
  holder.world=object;worldSquare.objects[#worldSquare.objects+1]=object
  return container,holder
 end
 local packets={add={},remove={},clothing={},stats={},order={}}
 sendAddItemToContainer=function(container,value)
  assert(container==root)
  if value~=kit then assert(root:getItemById(value:getID())==value and value:getContainer()==root,
   'cosmetic add packet preceded its actual root insertion')end
  packets.add[#packets.add+1]=value
  packets.order[#packets.order+1]={kind='add',item=value}
 end
 sendRemoveItemFromContainer=function(_,value)packets.remove[#packets.remove+1]=value;packets.order[#packets.order+1]={kind='remove',item=value}end
 sendClothing=function(_,_,value)
  packets.clothing[#packets.clothing+1]=value;packets.order[#packets.order+1]={kind='clothing',item=value}
  assert(actor:getWornItem(value:getBodyLocation())==value,'clothing packet preceded actual wear')
  if options.clothingError then error('native clothing send failed')end
 end
 sendItemStats=function(value)packets.stats[#packets.stats+1]=value;packets.order[#packets.order+1]={kind='stats',item=value}end
 local java={}
 getClassSimpleName=function(value)return java[value]and'LuaJavaInvoker'or type(value)=='table'and value.class or'LuaClosure'end
 for _,name in ipairs({'isServer','isClient','instanceof','getClassSimpleName','getScriptManager','instanceItem',
  'sendAddItemToContainer','sendRemoveItemFromContainer','sendClothing','sendItemStats','getCell','getVehicleById'})do java[_G[name]]=true end
 local access=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemAccess.lua'))()
 local nativeRequire=require
 require=function(module)if module=='PZSurvivorToolkit/ItemAccess'then return access end;return nativeRequire(module)end
 if options.foreignAccess then access[options.foreignAccess]=function()return kit end end
 java[SafeHouse.isSafehouseAllowLoot]=true
 local native=ISApplyMakeUp.complete
 if options.foreign then ISApplyMakeUp[options.foreign]=function()end end
 local before=ISApplyMakeUp.complete
 if not options.unpatched then assert(loadfile(modulePath))()end
 local wrapped=ISApplyMakeUp.complete
 local action=ISApplyMakeUp:new(actor,kit,'Base.MakeUp_LipsRed')
 local function old()
  local value=item('Base.MakeUp_LipsBlue',500);value.container=root;root.values[#root.values+1]=value;actor.worn[value.slot]=value;return value
 end
 return {actor=actor,root=root,kit=kit,action=action,packets=packets,options=options,old=old,item=item,
  native=native,before=before,wrapped=wrapped,access=access,move=move,bag=bag,worldContainer=worldContainer,worldBag=worldBag,
  worldSquare=worldSquare,current=current,recursiveCalls=function()return recursiveCalls end,invoke=function()return wrapped(action)end,
  made=function()return made end,attempts=function()return attempts end,mode=function(s,c)server,client=s,c end}
end
local baseline=setup({unpatched=true})
assert(baseline.invoke()==true)
local output=baseline.actor:getWornItem(ItemBodyLocation.MAKE_UP_LIPS)
assert(output and baseline.root:contains(output)and #baseline.packets.add==1 and baseline.packets.add[1]==baseline.kit
 and baseline.kit.uses==4,'native source no longer demonstrates wrong kit-only inventory notification')
for _,replacing in ipairs({false,true})do
 local s=setup();local previous=replacing and s.old()or nil
 local duration=ISApplyMakeUp.getDuration
 assert(s.invoke()==true)
 output=s.actor:getWornItem(ItemBodyLocation.MAKE_UP_LIPS)
 assert(s.made()==1 and s.attempts()==1 and s.kit.uses==4 and s.root.adds==1 and s.actor.writes==1)
 assert(#s.packets.add==1 and s.packets.add[1]==output and s.root:contains(output)
  and output:getContainer()==s.root and #s.packets.clothing==1 and #s.packets.stats==1,
  'corrected body replayed native completion or sent another item')
 assert(#s.packets.remove==(replacing and 1 or 0)and(not previous or not s.root:contains(previous)))
 assert(ISApplyMakeUp.getDuration==duration,'correction changed native duration')
 assert(s.packets.order[1].kind=='add'and s.packets.order[1].item==output
  and s.packets.order[#s.packets.order-1].kind=='clothing'and s.packets.order[#s.packets.order-1].item==output
  and s.packets.order[#s.packets.order].kind=='stats','new output add did not precede clothing in native packet order')
end
-- These sources remain in place and incur the exact native one-use cost. The
-- output is always inserted into the actor's root before its clothing packet.
for _,placement in ipairs({'worn bag','nested carried bag','world object','world bag'})do
 local s=setup();local source,holder
 if placement=='worn bag'then source,holder=s.bag(s.root);s.actor.worn.Bag=holder
 elseif placement=='nested carried bag'then local outer=s.bag(s.root);source=s.bag(outer)
 elseif placement=='world object'then source=s.worldContainer()
 else source=s.worldBag()end
 s.move(source)
 assert(s.access.admit(s.actor,s.access.locate(s.kit,s.actor))==s.kit,'fixture did not establish native ItemAccess permission: '..placement)
 assert(s.invoke()==true)
 local cosmetic=s.actor:getWornItem(ItemBodyLocation.MAKE_UP_LIPS)
 assert(s.made()==1 and s.attempts()==1 and s.kit.uses==4 and s.kit:getContainer()==source
  and source:getItemById(s.kit:getID())==s.kit and #s.packets.add==1 and s.packets.add[1]==cosmetic
  and s.root:contains(cosmetic)and #s.packets.clothing==1 and #s.packets.stats==1,
  'eligible '..placement..' did not correct exactly one native output packet')
 assert(s.packets.order[1].kind=='add'and s.packets.order[1].item==cosmetic
  and s.packets.order[#s.packets.order-1].kind=='clothing','nested output notification did not precede clothing')
end
for _,options in ipairs({{server=false},{server=false,client=true},{server=true,client=true},
 {changedSource='ISApplyMakeUp.lua'},{changedSource='MakeUpDefinitions.lua'},
 {foreignAccess='admit'},{foreignAccess='locate'},{foreign='update'},{foreign='extraHelper'}})do
 local s=setup(options);assert(s.wrapped==s.before,'unsupported realm/source/class installed completion override')
 s.invoke();assert(#s.packets.add<=1,'unsupported completion received an extra inventory packet')
end
local function rejected(change,label)
 local s=setup();change(s);s.invoke()
 assert(#s.packets.add==1 and s.packets.add[1]==s.kit and s.kit.uses==4 and s.attempts()==1,
  'foreign completion gained correction or native completion was replayed: '..(label or 'guard'))
end
rejected(function(s)s.action.onCompleteFunc=function()end end)
rejected(function(s)s.action.update=function()end end)
rejected(function()ISApplyMakeUp.update=function()end end)
rejected(function()ISApplyMakeUp.complete=function()error('foreign complete must not be called by saved wrapper')end end)
rejected(function()ISApplyMakeUp.extraHelper=function()end end)
rejected(function()ISApplyMakeUp={}end)
rejected(function()ItemBodyLocation.MAKE_UP_LIPS={}end)
rejected(function(s)s.kit.container={}end)
rejected(function(s)s.root.getParent=function()return{}end end)
rejected(function(s)s.options.luaCreate='Unknown.Callback'end)
rejected(function(s)s.options.configKey='Unknown.Config'end)
rejected(function(s)s.options.config={}end)
rejected(function(s)s.mode(false,false)end)
rejected(function(s)s.root.values[#s.root.values+1]=s.kit end)
-- Admission must reject malformed identity/ancestry before invoking recursive
-- native searches: recursive ID lookup cannot establish exact chain membership.
local function malformed(change,label)
 rejected(function(s)
  local calls=s.recursiveCalls();change(s)
  local invoke=s.invoke
  s.invoke=function()local result=invoke();assert(s.recursiveCalls()==calls,'unsafe recursive API reached: '..label);return result end
 end,label)
end
malformed(function(s)s.root.values={}end,'missing kit reference')
malformed(function(s)local duplicate=s.item('Base.MakeUp_LipsBlue',s.kit:getID());duplicate.container=s.root;s.root.values[#s.root.values+1]=duplicate end,'duplicate kit ID')
malformed(function(s)s.kit.id='invalid'end,'noninteger kit ID')
malformed(function(s)s.kit.id=2147483648 end,'out of range kit ID')
malformed(function(s)local source=s.bag(s.root);s.move(source);source.values={}end,'missing nested kit')
malformed(function(s)local source=s.bag(s.root);s.move(source);source.values[#source.values+1]=s.kit end,'duplicate nested kit reference')
malformed(function(s)local source=s.bag(s.root);s.move(source);source.getItemById=function()return s.item('Base.MakeUp_LipsBlue',s.kit:getID())end end,'foreign direct lookup')
malformed(function(s)local source,holder=s.bag(s.root);s.move(source);holder.id=0/0 end,'noninteger holder ID')
malformed(function(s)local source,holder=s.bag(s.root);s.move(source);holder.id=2147483648 end,'out of range holder ID')
malformed(function(s)local source,holder=s.worldBag();s.move(source);holder.id=2147483648 end,'out of range world holder ID')
malformed(function(s)local source,holder=s.worldBag();s.move(source);holder.world.getItem=function()return s.item('Base.MakeUp_LipsBlue',holder.id)end end,'forged world holder')
malformed(function(s)local source,holder=s.bag(s.root);s.move(source);s.root.values={}end,'missing holder')
malformed(function(s)local source,holder=s.bag(s.root);s.move(source);s.root.values[#s.root.values+1]=holder end,'duplicate holder reference')
malformed(function(s)local source,holder=s.bag(s.root);s.move(source);local _,other=s.bag(s.root);other.id=holder.id end,'duplicate holder ID')
malformed(function(s)local source,holder=s.bag(s.root);s.move(source);local foreign=s.bag(s.root);holder.getInventory=function()return foreign end end,'forged inventory backreference')
malformed(function(s)local source,holder=s.bag(s.root);s.move(source);holder.container=source;source.values[#source.values+1]=holder end,'cyclic holder chain')
malformed(function(s)local source=s.root;for _=1,34 do source=s.bag(source)end;s.move(source)end,'overdeep chain')
malformed(function(s)local source=s.bag(s.root);s.move(source);source.holder.class='InventoryItem'end,'unsupported holder class')
rejected(function(s)local source=s.bag(s.root);local nested=s.bag(source);s.move(nested);s.options.deniedContainer=source end,'inaccessible ancestor')
rejected(function(s)local source=s.worldContainer();s.move(source);s.worldSquare.x=3 end,'distant world source')
rejected(function(s)local source=s.worldBag();s.move(source);s.options.wall=true end,'world wall')
rejected(function(s)local source=s.worldContainer();s.move(source);s.options.safehouse=false end,'safehouse loot denial')
rejected(function(s)local source=s.worldBag();s.move(source);s.options.deniedContainer=source end,'inaccessible world bag')
rejected(function(s)
 local foreign=s.worldContainer();local imposter=s.item('Base.MakeUp_LipsBlue',s.kit:getID());imposter.container=foreign
 function imposter:getOutermostContainer()return foreign end;function imposter:getWorldItem()end
 foreign.values[1]=imposter
 local source=s.worldContainer();s.move(source)
 end,'foreign world lookup identity')
for _,method in ipairs({'locate','resolve','integer','validLocator','sameLocation','admit'})do
 rejected(function(s)local original=s.access[method];s.access[method]=function(...)return original(...)end end,'changed ItemAccess.'..method)
end
rejected(function(s)setmetatable(s.access,{})end,'changed ItemAccess table metatable')
rejected(function()SafeHouse={}end,'changed SafeHouse owner')
rejected(function()local nativeAllow=SafeHouse.isSafehouseAllowLoot;SafeHouse.isSafehouseAllowLoot=function(...)return nativeAllow(...)end end,'changed SafeHouse helper')
for _,global in ipairs({'getCell','getVehicleById'})do
 rejected(function()local original=_G[global];_G[global]=function(...)return original(...)end end,'changed '..global)
end
rejected(function(s)local nativeFactory=instanceItem;instanceItem=function(kind)return nativeFactory(kind)end end)
rejected(function(s)local nativeNotify=sendAddItemToContainer;sendAddItemToContainer=function(...)return nativeNotify(...)end end)
rejected(function(s)local nativeClothing=sendClothing;sendClothing=function(...)return nativeClothing(...)end end)
rejected(function(s)setmetatable(MakeUpDefinitions.makeup[1].makeuptypes,{__index=function()return false end})end)
local invalid=setup();invalid.action.type='Base.NotAMakeup'
assert(invalid.invoke()==false and invalid.kit.uses==5 and invalid.attempts()==0 and #invalid.packets.add==0,
 'failed native completion gained output, cost or packet')
invalid=setup();invalid.kit.getMakeUpType=function()return'Unsupported'end
assert(invalid.invoke()==false and invalid.kit.uses==5 and invalid.attempts()==0 and #invalid.packets.add==0,
 'corrected native compatibility rejection gained output, cost or packet')
for _,stage in ipairs({'factory','clothing'})do
 local s=setup();s.options[stage=='factory'and'factoryError'or'clothingError']=true
 local ok,message=pcall(s.invoke)
 assert(not ok and tostring(message):find(stage=='factory'and'native factory failed'or'native clothing send failed',1,true)
  and s.attempts()==1 and s.kit.uses==5 and #s.packets.add==(stage=='factory'and 0 or 1),
  'native failure was replayed, suppressed or received an output correction')
end
print('Native makeup output sync: exact one-argument correction, carried/world ancestry admission, output-before-clothing, native costs and closed unsupported paths passed.')
