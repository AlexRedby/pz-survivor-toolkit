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
 local root=actor.inventory;root.class='ItemContainer';root.values={};root.adds=0;root.removals=0
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
 function kit:getContainer()return self.container end;function kit:getMakeUpType()return'All'end
 function kit:getCurrentUses()return self.uses end;function kit:Use()self.uses=self.uses-1 end
 root.values[1]=kit
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
  'sendAddItemToContainer','sendRemoveItemFromContainer','sendClothing','sendItemStats'})do java[_G[name]]=true end
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
  native=native,before=before,wrapped=wrapped,invoke=function()return wrapped(action)end,
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
for _,options in ipairs({{server=false},{server=false,client=true},{server=true,client=true},
 {changedSource='ISApplyMakeUp.lua'},{changedSource='MakeUpDefinitions.lua'},{foreign='update'},{foreign='extraHelper'}})do
 local s=setup(options);assert(s.wrapped==s.before,'unsupported realm/source/class installed completion override')
 s.invoke();assert(#s.packets.add<=1,'unsupported completion received an extra inventory packet')
end
local function rejected(change)
 local s=setup();change(s);s.invoke()
 assert(#s.packets.add==1 and s.packets.add[1]==s.kit and s.kit.uses==4 and s.attempts()==1,
  'foreign completion gained correction or native completion was replayed')
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
print('Native makeup output sync: exact one-argument body correction, output-before-clothing, costs and closed unsupported paths passed.')
