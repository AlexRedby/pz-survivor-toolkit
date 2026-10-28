if not NativeActionRoot then print('Grooming native contracts SKIP.');return end
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local loaded={}
local Proof,SupplyUse
require=function(name)
 if name=='PZSurvivorToolkit/DrainableSupplyUse'then
  SupplyUse=SupplyUse or assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..name..'.lua'))()
  return SupplyUse
 end
 if name=='PZSurvivorToolkit/ActionQueueGroomingCosts'then return assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua'))()end
 if name=='PZSurvivorToolkit/TextResolverProof'then return assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua'))()end
 if name=='PZSurvivorToolkit/ActionQueueGroomingPending'then return assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua'))()end
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
 assert(name=='ISCutHair'or name=='ISTrimBeard'or name=='ISDyeHair');registrations=registrations+1;if name=='ISCutHair'then inspect=callback end
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
assert(grooming.install(policy,resources)and registrations==3,'reviewed native haircut did not install')
assert(grooming.install(policy,resources)and registrations==3,'repeated install registered twice')
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

local function denied(reason,missing)
 local installed={}
 local freshPolicy={registerNative=function(name,callback)installed[name]=callback end}
 assert(not module().install(freshPolicy,resources),reason)
 for _,name in ipairs({'ISCutHair','ISTrimBeard','ISDyeHair'})do
  assert((installed[name]==nil)==(missing==nil or missing==name),reason..': wrong independent profile '..name)
 end
end
for _,name in ipairs({'ISCutHair','ISTrimBeard','ISDyeHair'})do
 altered='media/lua/shared/TimedActions/'..name..'.lua';denied('changed source installed: '..name,name);altered=nil
end
altered='media/lua/shared/TimedActions/ISBaseTimedAction.lua';denied('changed native base installed');altered=nil
getGameFilesInput=nil;denied('missing source reader installed');getGameFilesInput=reader
getFilenameOfClosure=nil;denied('missing closure metadata installed');getFilenameOfClosure=filename
local nativeNew=ISCutHair.new
ISCutHair.new=function()end;denied('foreign constructor installed','ISCutHair');ISCutHair.new=nativeNew
local nativeHelper=ISCutHair.stopSound
ISCutHair.stopSound=function()end;denied('foreign helper installed','ISCutHair');ISCutHair.stopSound=nativeHelper
ISCutHair.forceCancel=function()end;denied('own unreviewed forceCancel installed','ISCutHair');ISCutHair.forceCancel=nil

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

-- Every reviewed family must retain the same waiting-only boundary independently.
require 'TimedActions/ISTrimBeard'
require 'TimedActions/ISDyeHair'
local family={}
local familyPolicy={registerNative=function(name,callback)family[name]=callback end}
assert(module().install(familyPolicy,resources),'reviewed grooming family did not install')
for _,spec in ipairs({{name='ISTrimBeard',field='item',duration=300},{name='ISDyeHair',field='hairDye',duration=120}})do
 local callback=assert(family[spec.name],'waiting grooming contract missing: '..spec.name)
 local class=_G[spec.name]
 local body=spec.name=='ISTrimBeard'and class:new(player,'',tool)or class:new(player,tool,true)
 local contract=assert(callback(body))
 assert(body.maxTime==spec.duration and contract.cancelWaiting and contract.cancelOperation and not contract.knownInputs
  and contract.items[42]and contract.itemTypes['Base.Scissors']and contract.targets[player],spec.name..': exact waiting input missing')
 for _,field in ipairs({'action','toolkitNativeTransaction','toolkitNativeKind'})do
  body[field]={};contract=assert(callback(body));assert(not contract.cancelWaiting and not contract.cancelOperation,spec.name..': allocated episode allowed');body[field]=nil
 end
 for _,field in ipairs({'start','complete','perform','forceCancel','getDuration'})do
  body[field]=function()end;assert(not callback(body),spec.name..': modified instance allowed');body[field]=nil
 end
 body.onStartFunc=function()end;assert(not callback(body),spec.name..': custom callback allowed');body.onStartFunc=nil
 local complete=class.complete;class.complete=function()end;assert(not callback(body),spec.name..': changed class allowed');class.complete=complete
end
print('PASS waiting trim/dye cancellation shares exact source and episode guards')

-- Execute unchanged native completions: shaving restores natural beard colour;
-- dye reads its current fluid colour and spends exactly 0.5, clamped at zero.
local natural={natural=true}
local applied={hair=false,beard=false,beardModel='Long',resets=0,growth=0,sync=0,stats=0,events=0}
local appearance={setHairColor=function(_,value)applied.hair=value end,
 setBeardColor=function(_,value)applied.beard=value end,
 setBeardModel=function(_,value)applied.beardModel=value end,getNaturalBeardColor=function()return natural end}
local actor={getHumanVisual=function()return appearance end,isTimedActionInstant=function()return false end,
 resetModel=function()applied.resets=applied.resets+1 end,resetBeardGrowingTime=function()applied.growth=applied.growth+1 end}
isServer=function()return false end
sendHumanVisual=function(value)assert(value==actor);applied.sync=applied.sync+1 end
triggerEvent=function(name,value)assert(name=='OnClothingUpdated'and value==actor);applied.events=applied.events+1 end
local trim=ISTrimBeard:new(actor,nil,tool)
assert(trim:complete()and applied.beardModel==''and applied.beard==natural and applied.growth==1 and applied.sync==1,
 'native shave did not retain its natural-colour effect')
ImmutableColor={new=function(r,g,b,a)return {r=r,g=g,b=b,a=a}end}
for _,beard in ipairs({true,false})do
 for _,amount in ipairs({.75,.25})do
  local current={r=.12,g=.34,b=.56}
  local fluid={getColor=function()return {getR=function()return current.r end,getG=function()return current.g end,getB=function()return current.b end}end,
   getAmount=function()return amount end,adjustAmount=function(_,value)applied.amount=value end}
  local dye={getFluidContainer=function()return fluid end}
  sendItemStats=function(value)assert(value==dye);applied.stats=applied.stats+1 end
  local body=ISDyeHair:new(actor,dye,beard)
  current={r=.67,g=.45,b=.23}
  assert(body:complete()and applied.amount==math.max(0,amount-.5),'native dye fluid cost changed')
  local color=beard and applied.beard or applied.hair
  assert(color.r==current.r and color.g==current.g and color.b==current.b and color.a==1,'native dye stopped using current fluid colour')
 end
end
assert(applied.sync==5 and applied.stats==4 and applied.events==5,'native cosmetic synchronization changed')
assert(family.ISApplyMakeUp==nil,'unreviewed makeup preview gained waiting deletion')
print('PASS native shave colour reset and hair/beard dye current-fluid colour, exact cost and synchronization')

-- A native subclass constructor dynamically calls its base constructor. Pin
-- that dependency too: an unreviewed wrapper can have already mutated the actor.
local baseNew=ISBaseTimedAction.new
ISBaseTimedAction.new=function(self,character)
 character.constructorEffects=(character.constructorEffects or 0)+1
 return baseNew(self,character)
end
local constructed=ISCutHair:new(player,'CrewCut',tool)
assert(player.constructorEffects==1 and constructed.action==nil,'base-constructor effect reproduction did not run')
denied('modified base constructor with an actual prior actor effect installed')
assert(not family.ISCutHair(constructed)and not family.ISTrimBeard(ISTrimBeard:new(player,'',tool))
 and not family.ISDyeHair(ISDyeHair:new(player,tool,false)),'modified base constructor retained reviewed waiting capabilities')
ISBaseTimedAction.new=baseNew
print('PASS dynamic native base-constructor provenance rejects already-mutated grooming bodies')
