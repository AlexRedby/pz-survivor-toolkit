if not NativeActionRoot then print('Grooming native contracts SKIP.');return end
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local loaded={}
local Proof
require=function(name)
 if name=='PZSurvivorToolkit/SourceProof'then
  Proof=Proof or assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
  return Proof
 end
 if loaded[name]then return end
 loaded[name]=true
 local path=name=='ISBaseObject'and 'shared/ISBaseObject.lua'or 'shared/'..name..'.lua'
 return assert(loadstring(read(NativeActionRoot..'/'..path),'@media/lua/'..path))()
end
require 'TimedActions/ISCutHair'
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
local altered
getGameFilesInput=function(path)
 local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
 if altered==path then text=text..'\n-- changed source\n'end
 local position=1
 return {close=function()end,readLine=function()
  if position>#text then return end
  local boundary=text:find('\n',position,true)or #text+1
  local line=text:sub(position,boundary-1);position=boundary+1;return line
 end}
end
local reader,filename=getGameFilesInput,getFilenameOfClosure
local function module()
 return assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueGrooming.lua'))()
end
local registrations,inspect=0
local policy={registerNative=function(name,callback)
 assert(name=='ISCutHair');registrations=registrations+1;inspect=callback
end}
local resources=function(action)
 local result={items={},itemTypes={},targets={}}
 if action.item then result.items[action.item.id]=true;result.itemTypes[action.item.kind]=true end
 return result
end
local player={isTimedActionInstant=function()return false end}
local tool={id=42,kind='Base.Scissors'}
local function action(style,item)return ISCutHair:new(player,style,item,300)end
local function hasEntry(values)for _ in pairs(values)do return true end;return false end
local grooming=module()
assert(grooming.install(policy,resources)and registrations==1,'reviewed native haircut did not install')
assert(grooming.install(policy,resources)and registrations==1,'repeated install registered twice')
for _,style in ipairs({'CrewCut','MohawkFan','GreasedBack'})do
 for _,item in ipairs({tool,false})do
  local a=action(style,item or nil);local contract=assert(inspect(a))
  assert(contract.cancelWaiting and contract.cancelOperation and not contract.knownInputs
   and not contract.preparation and not contract.preparationFinish and contract.interrupt=='finish-step'
   and contract.targets[player],'waiting haircut granted wrong permission/resource contract')
  assert((item and contract.items[42]and contract.itemTypes['Base.Scissors'])or(not item and not hasEntry(contract.items)))
  local forceCancel=ISBaseTimedAction.forceCancel
  a:forceCancel();assert(a.action==nil and a.hairStyle==style and a.forceCancel==forceCancel,'waiting removal changed native action')
  a.action={isStarted=function()return false end}
  contract=assert(inspect(a));assert(not contract.cancelWaiting and not contract.cancelOperation and not contract.preparationFinish,
   'allocated native haircut gained cancellation rights')
  a.action.isStarted=function()return true end
  contract=assert(inspect(a));assert(not contract.cancelWaiting and not contract.cancelOperation,'started haircut gained cancellation rights')
 end
end
local a=action('CrewCut',tool)
for _,field in ipairs({'onStartFunc','onCancelFunc','onCompleteFunc','onFailFunc','retriggerLastAction','additionalTest'})do
 a[field]=function()end;assert(not inspect(a),'custom callback retained waiting rights: '..field);a[field]=nil
end
for _,field in ipairs({'new','start','stop','perform','complete','stopSound'})do
 local original=ISCutHair[field]
 ISCutHair[field]=function()end;assert(not inspect(a),'changed class callback retained rights: '..field)
 ISCutHair[field]=original
 a[field]=function()end;assert(not inspect(a),'changed instance callback retained rights: '..field);a[field]=nil
end
ISCutHair.unreviewedHelper=function()end;assert(not inspect(a),'new class helper retained rights');ISCutHair.unreviewedHelper=nil
local originalClass=ISCutHair;ISCutHair={};assert(not inspect(a),'replacement class retained rights');ISCutHair=originalClass
local cancel=ISBaseTimedAction.forceCancel
ISBaseTimedAction.forceCancel=function()end;assert(not inspect(a),'replaced base forceCancel retained rights');ISBaseTimedAction.forceCancel=cancel
assert(inspect(a),'restored native methods did not restore exact matching')
a.toolkitNativeTransaction=7;assert(not inspect(a).cancelWaiting,'retired native episode gained waiting rights');a.toolkitNativeTransaction=nil

local function denied(reason)
 local before=registrations
 assert(not module().install(policy,resources)and registrations==before,reason)
end
for _,path in ipairs({'media/lua/shared/TimedActions/ISCutHair.lua','media/lua/shared/TimedActions/ISBaseTimedAction.lua'})do
 altered=path;denied('changed source installed: '..path);altered=nil
end
getGameFilesInput=nil;denied('missing source reader installed');getGameFilesInput=reader
getFilenameOfClosure=nil;denied('missing closure metadata installed');getFilenameOfClosure=filename
local nativeNew=ISCutHair.new
ISCutHair.new=function()end;denied('foreign constructor installed');ISCutHair.new=nativeNew
local nativeHelper=ISCutHair.stopSound
ISCutHair.stopSound=function()end;denied('foreign helper installed');ISCutHair.stopSound=nativeHelper
ISCutHair.forceCancel=function()end;denied('own unreviewed forceCancel installed');ISCutHair.forceCancel=nil

-- Native control: complete still dynamically looks up Hairgel twice for GreasedBack.
string.contains=string.contains or function(value,part)return value:find(part,1,true)~=nil end
local uses,visualSync,resets,growth=0,0,0,0
local gel={UseAndSync=function()uses=uses+1 end}
local visual={setHairModel=function(self,value)self.hair=value end,getNonAttachedHair=function()return nil end}
local inventory={getItemFromType=function(_,kind)if kind=='Hairgel'then return gel end end}
local controlPlayer={getInventory=function()return inventory end,isFemale=function()return false end,
 getHumanVisual=function()return visual end,resetModel=function()resets=resets+1 end,
 resetHairGrowingTime=function()growth=growth+1 end}
getHairStylesInstance=function()return {FindMaleStyle=function()return {getName=function()return 'GreasedBack'end,isAttachedHair=function()return false end}end}end
sendHumanVisual=function(p)assert(p==controlPlayer);visualSync=visualSync+1 end
local nativeComplete=ISCutHair.complete
local control=ISCutHair:new(controlPlayer,'GreasedBack',nil,300)
assert(control:complete()and uses==2 and visual.hair=='GreasedBack'and visualSync==1 and resets==1 and growth==1,
 'waiting-only contract changed native GreasedBack completion/costs')
assert(ISCutHair.complete==nativeComplete and ISCutHair.forceCancel==cancel,'grooming contract replaced gameplay callbacks')
print('PASS native source-bound waiting-only haircut contract, mutation/fallback denial and unchanged GreasedBack costs')
