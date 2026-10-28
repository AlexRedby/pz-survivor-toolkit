local savedNext=next;next=nil -- Native Kahlua does not provide Lua 5.1's next iterator.
if not NativeActionRoot then print('Grooming costs native contracts SKIP.');return end
local modulePath=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueGroomingCosts.lua'
local nativePath=NativeActionRoot..'/shared/TimedActions/ISCutHair.lua'
local nativeSource
if NativeReadText then nativeSource=NativeReadText(nativePath)
else local file=assert(io.open(nativePath));nativeSource=file:read('*a');file:close()end
local oldContains=string.contains
string.contains=function(self,part)return self:find(part,1,true)~=nil end
local function fixture(style)
 local env=setmetatable({PZSurvivorToolkit={},ItemTag={DO_HAIRDO={}},ItemType={DRAINABLE={}}},{__index=_G})
 local java={};local effects={uses={},resets=0,sync=0,events=0}
 local function invoker(fn)java[fn]=true;return fn end
 env.getClassSimpleName=invoker(function(value)return java[value]and'LuaJavaInvoker'or type(value)=='table'and value.class or'Unknown'end)
 env.instanceof=invoker(function(value,kind)
  if type(value)~='table'then return false end
  return value.class==kind or kind=='InventoryItem'and(value.class=='DrainableComboItem'or value.class=='InventoryContainer'or value.class=='Food')
 end)
 local function list(values)
  return {class='ArrayList',values=values or{},size=function(self)return #self.values end,get=function(self,i)return self.values[i+1]end}
 end
 local scripts={};local catalog=list(scripts);local manager={class='ScriptManager',getAllItems=function()effects.catalogCalls=(effects.catalogCalls or 0)+1;return catalog end}
 local currentManager=manager
 env.getScriptManager=invoker(function()return currentManager end)
 env.isServer=invoker(function()return false end)
 local id=0
 local function script(kind,tag)
  local value={class='Item',kind=kind,tag=tag}
  function value:getFullName()return self.kind end
  function value:hasTag(t)return self.tag and t==env.ItemTag.DO_HAIRDO or false end
  function value:getItemType()return env.ItemType.DRAINABLE end
  function value:hasComponents()return self.components or false end
  function value:getObsolete()return false end
  function value:getLuaCreate()return self.create end
  function value:getItemConfigKey()return self.configKey end
  function value:getItemConfig()return self.config end
  function value:getReplaceOnUse()return self.replaceUse end
  function value:getReplaceOnDeplete()return self.replaceDeplete end
  function value:isDisappearOnUse()return self.disappear~=false end
  function value:getActualWeight()return .5 end
  scripts[#scripts+1]=value
  return value
 end
 local function container(owner)
  local value={class='ItemContainer',owner=owner,items=list()}
  function value:getItems()return self.items end
  function value:getContainingItem()return self.owner end
  function value:getParent()return self.parent end
  function value:getItemById(wanted)
   for _,item in ipairs(self.items.values)do if item.id==wanted then return item end end
  end
  return value
 end
 local root=container();local actor={class='IsoPlayer',inventory=root};root.parent=actor
 function actor:getInventory()return self.inventory end
 function actor:getPrimaryHandItem()return self.primary end
 function actor:getSecondaryHandItem()return self.secondary end
 function actor:isFemale()return false end
 function actor:isEquipped(item)return self.primary==item or self.secondary==item end
 local worn={class='WornItems'}
 function worn:contains(item)return self.item==item end
 function actor:getWornItems()return worn end
 function manager:FindItem(kind)for _,item in ipairs(scripts)do if item.kind==kind then return item end end end
 local visual={}
 function visual:getNonAttachedHair()return nil end
 function visual:setNonAttachedHair()effects.resets=effects.resets+1 end
 function visual:setHairModel(name)self.hair=name end
 function actor:getHumanVisual()return visual end
 function actor:resetModel()effects.resets=effects.resets+1 end
 function actor:resetHairGrowingTime()effects.resets=effects.resets+1 end
 local function add(kind,tag,uses,destination)
  id=id+1
  local value={class='DrainableComboItem',id=id,kind=kind,script=script(kind,tag),uses=uses or 5,weight=.5,emptyWeight=0}
  function value:isBroken()return self.broken or false end
  function value:getID()return self.id end
  function value:getType()return self.kind:match('[^.]+$')end
  function value:getFullType()return self.kind end
  function value:getScriptItem()return self.script end
  function value:hasTag(t)return self.script:hasTag(t)end
  function value:getContainer()return self.container end
  function value:getWorldItem()return self.world end
  function value:getReplaceOnDeplete()return self.replacement end
  function value:getWeightEmpty()return self.emptyWeight end
  function value:getActualWeight()return self.weight end
  function value:getCurrentUses()return self.uses end
  function value:getUses()return self.uses end
  function value:hasComponents()return self.components or false end
  function value:getReplaceOnUse()return self.replaceUse end
  function value:getLuaCreate()return self.create end
  function value:isDisappearOnUse()return self.disappear~=false end
  function value:isKeepOnDeplete()return self.keep or false end
  function value:getAttachedSlot()return self.attachedSlot or -1 end
  function value:getAttachedToModel()return self.attachedModel end
  function value:getAttachedSlotType()return self.attachedType end
  function value:isActivated()return self.activated or false end
  function value:getIsCraftingConsumed()return self.crafting or false end
  function value:getEquipParent()return self.equipParent end
  function value:isUseWhileEquiped()return self.autoEquipped or false end
  function value:isUseWhileUnequiped()return self.autoUnequipped or false end
  function value:UseAndSync()
   effects.uses[#effects.uses+1]=self
   self.uses=self.uses-1
   if self.uses<=0 then
    local values=self.container.items.values
    for i=#values,1,-1 do if values[i]==self then table.remove(values,i)end end
    self.container=nil
   end
  end
  value.container=destination or root
  table.insert(value.container.items.values,value)
  return value
 end
 local function bag(destination)
  local value=add('Base.Bag',false,1,destination);value.class='InventoryContainer';value.inventory=container(value)
  function value:getInventory()return self.inventory end
  return value
 end
 local function first(container,predicate)
  for _,item in ipairs(container.items.values)do if predicate(item)then return item end end
  for _,item in ipairs(container.items.values)do
   if item.class=='InventoryContainer'then local found=first(item.inventory,predicate);if found then return found end end
  end
 end
 function root:getItemFromType(kind,broken,recurse)
  assert(broken and recurse,'native selector flags changed')
  return first(self,function(item)return item:getType()==kind and not item.broken end)
 end
 function root:getFirstTagRecurse(tag)return first(self,function(item)return item:hasTag(tag)end)end
 local function carried(item,who)
  if who~=actor or item.callback then return false end
  local c,seen=item.container,{}
  while c and not seen[c]do
   seen[c]=true
   if c.callback then return false end
   if c==root then return true end
   c=c.owner and c.owner.container
  end
  return false
 end
 local policy={addContainerResources=function(result,c)
  local seen={}
  while c and not seen[c]do
   seen[c]=true
   if c.callback then result.knownInputs=false;return end
   if c.owner then
    result.containerOwners[c.owner.id]=true;result.itemTypes[c.owner.kind]=true
    c=c.owner.container
   else return end
  end
 end}
 env.getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 local shared=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/'
 local proof=assert(setfenv(assert(loadfile(shared..'SourceProof.lua')),env))()
 local supply=assert(setfenv(assert(loadfile(shared..'DrainableSupplyUse.lua')),env))()
 env.require=function(name)
  if name=='PZSurvivorToolkit/SourceProof'then return proof end
  if name=='PZSurvivorToolkit/DrainableSupplyUse'then return supply end
 end
 env.ISBaseTimedAction={derive=function(_,name)return {Type=name}end}
 env.getHairStylesInstance=function()
  return {FindMaleStyle=function(_,name)return {getName=function()return name end,isAttachedHair=function()return false end}end}
 end
 env.sendHumanVisual=function()effects.sync=effects.sync+1 end
 env.triggerEvent=function()effects.events=effects.events+1 end
 local costs=assert(setfenv(assert(loadfile(modulePath)),env))()
 assert(env.PZSurvivorToolkit.ActionQueueGroomingCosts==costs)
 assert(setfenv(assert(loadstring(nativeSource,'@'..nativePath)),env))()
 local action=setmetatable({character=actor,hairStyle=style},{__index=env.ISCutHair})
 local function resources()return {items={[999]=true},itemTypes={},targets={},containerOwners={},knownInputs=false}end
 local s={env=env,costs=costs,actor=actor,action=action,add=add,bag=bag,script=script,policy=policy,carried=carried,effects=effects,root=root,resources=resources}
 function s:apply(result,context)return costs.apply(action,result or resources(),policy,carried,context)end
 function s:noEffects()
  assert(#effects.uses==0 and effects.resets==0 and effects.sync==0 and effects.events==0,'inspection ran gameplay effects')
 end
 s.supply,s.proof,s.worn=supply,proof,worn
 function s:hold(item,which)
  actor.primary=(which=='primary'or which=='both')and item or nil
  actor.secondary=(which=='secondary'or which=='both')and item or nil
  item.equipParent=actor
 end
 function s:changeManager()currentManager={class='ScriptManager'}end
 return s
end
local function unchanged(before,after)
 for name,value in pairs(before)do
  if type(value)=='table'then
   assert(after[name]==value,'denial replaced resource map')
   local n=0;for _ in pairs(value)do n=n+1 end
   assert(n==(name=='items'and 1 or 0),'denial leaked partial resources: '..name)
  else assert(after[name]==value,'denial changed resource flags')end
 end
 assert(after.dynamicInputs==nil and after.dynamicInputsByType==nil,'denial leaked selector maps')
end
-- Every live candidate and future script alternative belongs to the footprint;
-- none is chosen even when a higher-priority candidate already exists.
do
 local s=fixture('MohawkFan');local tag=s.add('Mod.Tagged',true);local spray=s.add('Base.Hairspray2',true)
 local b=s.bag();local gel=s.add('Other.Hairgel',true,4,b.inventory);s.script('Mod.FutureHair',true)
 local unrelated=s.add('Base.Book',false);local result=s.resources()
 assert(s:apply(result))
 assert(result.dynamicInputsByType.Hairgel and result.dynamicInputsByType.Hairspray2)
 assert(result.dynamicInputs['Mod.FutureHair']and result.dynamicInputs['Mod.Tagged'])
 for _,item in ipairs({tag,spray,gel})do assert(result.items[item.id]and result.itemTypes[item.kind])end
 assert(result.containerOwners[b.id]and not result.items[unrelated.id])
 s:noEffects()
 assert(s.action:complete()and s.effects.uses[1]==gel and #s.effects.uses==1,'native Hairgel priority changed')
end
for _,which in ipairs({'spray','tag'})do
 local s=fixture('Spike');local tag=s.add('Mod.Tagged',true);local spray=which=='spray'and s.add('Base.Hairspray2',true)or nil
 assert(s:apply());s:noEffects();assert(s.action:complete())
 assert(s.effects.uses[1]==(spray or tag)and #s.effects.uses==1,'native spray/tag fallback changed')
end
do
 local s=fixture('GreasedBack');local first=s.add('Base.Hairgel',true,1);local second=s.add('Mod.Hairgel',true,4)
 local result=s.resources();assert(s:apply(result)and result.items[first.id]and result.items[second.id]);s:noEffects()
 assert(s.action:complete()and #s.effects.uses==2 and s.effects.uses[1]==first and s.effects.uses[2]==second)
 assert(first.container==nil and second.uses==3,'native second lookup did not switch depleted Hairgel')
end
for _,style in ipairs({'Buffont','GreasedSide'})do
 local s=fixture(style);local gel=s.add('Base.Hairgel',true);local spray=s.add('Base.Hairspray2',true)
 local result=s.resources();assert(s:apply(result));s:noEffects()
 assert(result.dynamicInputs==nil,'single short-type selector gained a tag fallback')
 local target=style=='Buffont'and spray or gel
 assert(result.items[target.id]and not result.items[(target==gel and spray or gel).id])
 assert(s.action:complete()and s.effects.uses[1]==target and #s.effects.uses==1)
end
do
 local s=fixture('MohawkFan');local broken=s.add('Mod.Tagged',true);broken.broken=true
 local result=s.resources();assert(s:apply(result)and result.items[broken.id]);s:noEffects()
 assert(s.action:complete()and s.effects.uses[1]==broken,'tag fallback incorrectly filtered broken item')
end
do
 local s=fixture('MohawkFan');local gel=s.add('Base.Hairgel',true);local context={}
 local result=s.resources();assert(s:apply(result,context)and s.effects.catalogCalls==1)
 local later=s.add('Mod.Later',true)
 result=s.resources();assert(s:apply(result,context)and s.effects.catalogCalls==1 and result.items[later.id],
  'context cache retained candidates or rescanned unchanged catalog boundary')
 s.script('Mod.FutureContext',true)
 local secondContext={}
 result=s.resources();assert(s:apply(result,secondContext)and result.dynamicInputs['Mod.FutureContext']and s.effects.catalogCalls==2,
  'new context reused stale tag metadata')
 s.script('Mod.FutureUncached',true)
 result=s.resources();assert(s:apply(result)and result.dynamicInputs['Mod.FutureUncached']and s.effects.catalogCalls==3,
  'no-context inspection reused stale tag metadata')
 result=s.resources();assert(s:apply(result,context)and result.dynamicInputs['Mod.FutureUncached']and s.effects.catalogCalls==4,
  'alternating contexts retained an unbounded or stale catalog snapshot')
 result=s.resources();assert(s:apply(result,secondContext)and s.effects.catalogCalls==5,
  'previous context was retained after another evaluation')
 s:noEffects();assert(gel.uses==5 and later.uses==5)
end
do
 local s=fixture('Spike');s.script('Mod.AbsentTagged',true)
 local result=s.resources();assert(s:apply(result)and result.dynamicInputs['Mod.AbsentTagged']
  and result.dynamicInputsByType.Hairgel and result.dynamicInputsByType.Hairspray2,
  'optional missing current input lost future selector dependencies')
 s:noEffects();assert(s.action:complete()and #s.effects.uses==0,'native absent optional supplies changed')
end
for _,mutation in ipairs({'class','replace','weight-empty','world','held-primary','held-secondary','callback','stale','weight','script','late-callback','tag-owner','tag-value','getter','manager','classifier','instanceof','cycle','script-class','script-fullname','script-duplicate','inspection-error'})do
 local s=fixture('MohawkFan');local good=s.add('Base.Hairgel',true);local bad=s.add('Mod.Tagged',true)
 if mutation=='class'then bad.class='Food'
 elseif mutation=='replace'then bad.replacement='Mod.CallbackOutput'
 elseif mutation=='weight-empty'then bad.emptyWeight=.2
 elseif mutation=='world'then bad.world={}
 elseif mutation=='held-primary'then s.actor.primary=bad
 elseif mutation=='held-secondary'then s.actor.secondary=bad
 elseif mutation=='callback'then bad.callback=true
 elseif mutation=='stale'then bad.container=nil
 elseif mutation=='weight'then bad.weight=0/0
 elseif mutation=='script'then bad.script=s.script('Other.Script',true)
 elseif mutation=='late-callback'then s.policy.addContainerResources=function(result)result.knownInputs=false end
 elseif mutation=='tag-owner'then s.env.ItemTag={DO_HAIRDO=s.env.ItemTag.DO_HAIRDO}
 elseif mutation=='tag-value'then s.env.ItemTag.DO_HAIRDO={}
 elseif mutation=='getter'then s.env.getScriptManager=function()error('foreign getter executed')end
 elseif mutation=='manager'then s:changeManager()
 elseif mutation=='classifier'then s.env.getClassSimpleName=function()error('foreign classifier executed')end
 elseif mutation=='instanceof'then s.env.instanceof=function()error('foreign classifier executed')end
 elseif mutation=='cycle'then local bag=s.bag();bag.inventory=s.root
 elseif mutation=='script-class'then s.script('Mod.Unknown',true).class='Unknown'
 elseif mutation=='script-fullname'then s.script('InvalidFullName',true)
 elseif mutation=='script-duplicate'then s.script('Base.Hairgel',true)
 elseif mutation=='inspection-error'then bad.getWeightEmpty=function()error('unsupported native getter')end end
 local result=s.resources();local before={};for name,value in pairs(result)do before[name]=value end
 local accepted,reason=s:apply(result)
 assert(not accepted and type(reason)=='string'and reason~='','unproved candidate admitted or denial lacks reason: '..mutation)
 if mutation=='inspection-error'then assert(reason=='inspection-error')end
 unchanged(before,result);s:noEffects()
 assert(good.uses==5 and bad.uses==5,'denied inspection consumed input')
end
do
 local s=fixture('MohawkFlat');assert(s:apply());s:noEffects();assert(s.action:complete()and #s.effects.uses==0)
 local env=setmetatable({PZSurvivorToolkit={},require=function()end},{__index=function(_,key)
  if key=='getClassSimpleName'or key=='instanceof'or key=='getScriptManager'or key=='ItemTag'then return nil end
  return _G[key]
 end});local costs=assert(setfenv(assert(loadfile(modulePath)),env))()
 assert(costs==env.PZSurvivorToolkit.ActionQueueGroomingCosts,'missing globals broke harmless bootstrap')
 assert(not costs.apply({hairStyle='Spike'},{},{},function()return true end))
end
-- Held candidates survive the entire completion, including fresh repeated
-- selectors. Inspect the real shared proof; do not choose/reserve a winner.
for _,spec in ipairs({{'MohawkFan','Base.Hairgel',1},{'MohawkFan','Base.Hairspray2',1},
 {'Buffont','Base.Hairspray2',1},{'GreasedSide','Base.Hairgel',1},{'GreasedBack','Base.Hairgel',2},
 {'MohawkBuffontGreased','Base.Hairgel',2},{'MohawkBuffontGreased','Base.Hairspray2',2},
 {'MohawkBuffontGreased','Mod.Wax',1},{'GreasedBack','Base.Hairspray2',1}})do
 local style,kind,budget=unpack(spec)
 for _,hand in ipairs({'primary','secondary','both'})do
  for _,uses in ipairs({budget,budget+1})do
   local s=fixture(style);local item=s.add(kind,true,uses);s:hold(item,hand)
   local result=s.resources();local before={};for name,value in pairs(result)do before[name]=value end
   local accepted,reason=s:apply(result)
   assert(accepted==(uses>budget),'held whole-style budget mismatch: '..style..' '..hand..' '..uses..' '..tostring(reason))
   s:noEffects();assert(item.uses==uses and item.container==s.root,'inspection changed held supply')
   if accepted then
    assert(result.items[item.id]and result.itemTypes[kind],'held candidate lost resource footprint')
    local primary,secondary=s.actor.primary,s.actor.secondary
    assert(s.action:complete()and #s.effects.uses>=1,'native held style did not execute')
    assert(item.uses>0 and item.container==s.root and s.actor.primary==primary and s.actor.secondary==secondary,
     'retained native use changed ownership or hands')
   else unchanged(before,result)end
  end
 end
end
do
 local s=fixture('GreasedBack');local item=s.add('Base.Hairgel',true,5);s:hold(item,'both')
 for _,value in ipairs({{},{budget=false},{budget=0},{budget=-1},{budget=.5},{budget=0/0},
  {budget=math.huge},{budget=-math.huge},{budget='1'},{budget={}}})do
  assert(not s.supply.supportsRetainedHeld(s.actor,item,value.budget),'invalid whole-use budget admitted')
 end
 assert(s.supply.supportsRetainedHeld(s.actor,item,4)and not s.supply.supportsRetainedHeld(s.actor,item,5),
  'retained-use proof did not require at least one surviving charge')
 s:noEffects()
end
for _,mutation in ipairs({'deplete','negative','nan','nested','world','duplicate-id','stale-parent','worn','auto-equipped','auto-unequipped',
 'components','create','replace-use','script-config','script-components','attached','activated','crafting','helper','closure',
 'other-hand-nested','other-hand-stale'})do
 local s=fixture('GreasedBack');local item=s.add('Base.Hairgel',true,5);s:hold(item,'primary')
 if mutation=='deplete'then item.uses=2
 elseif mutation=='negative'then item.uses=-1
 elseif mutation=='nan'then item.uses=0/0
 elseif mutation=='nested'then
  table.remove(s.root.items.values,1);local bag=s.bag();item.container=bag.inventory;table.insert(bag.inventory.items.values,item)
 elseif mutation=='world'then item.world={}
 elseif mutation=='duplicate-id'then s.add('Mod.Tagged',true).id=item.id
 elseif mutation=='stale-parent'then item.equipParent={}
 elseif mutation=='worn'then s.worn.item=item
 elseif mutation=='auto-equipped'then item.autoEquipped=true
 elseif mutation=='auto-unequipped'then item.autoUnequipped=true
 elseif mutation=='components'then item.components=true
 elseif mutation=='create'then item.create='Mod.Create'
 elseif mutation=='replace-use'then item.replaceUse='Mod.Replacement'
 elseif mutation=='script-config'then item.script.configKey='Mod.Config'
 elseif mutation=='script-components'then item.script.components=true
 elseif mutation=='attached'then item.attachedSlot=0
 elseif mutation=='activated'then item.activated=true
 elseif mutation=='crafting'then item.crafting=true
 elseif mutation=='helper'then s.supply.supportsRetainedHeld=function()error('foreign retained proof executed')end
 elseif mutation=='closure'then s.proof.closure=function()error('foreign closure proof executed')end
 elseif mutation=='other-hand-nested'or mutation=='other-hand-stale'then
  local other=s.add('Base.Hammer',false,5,mutation=='other-hand-nested'and s.bag().inventory or nil)
  s.actor.secondary=other;other.equipParent=mutation=='other-hand-stale'and{}or s.actor
 end
 local result=s.resources();local before={};for name,value in pairs(result)do before[name]=value end
 assert(not s:apply(result),'unsafe held candidate admitted: '..mutation);unchanged(before,result);s:noEffects()
end
print('PASS actual shared held drainable proof, whole-style budgets and unchanged native costs; unsafe/changed candidates fail atomically')
string.contains=oldContains
print('PASS native paid hair late selectors/costs, complete future inputs, ancestry and atomic fail-closed inspection')

next=savedNext
