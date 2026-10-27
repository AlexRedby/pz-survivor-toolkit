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
 local env=setmetatable({PZSurvivorToolkit={},ItemTag={DO_HAIRDO={}}},{__index=_G})
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
 local id=0
 local function script(kind,tag)
  local value={class='Item',kind=kind,tag=tag}
  function value:getFullName()return self.kind end
  function value:hasTag(t)return self.tag and t==env.ItemTag.DO_HAIRDO or false end
  scripts[#scripts+1]=value
  return value
 end
 local function container(owner)
  local value={class='ItemContainer',owner=owner,items=list()}
  function value:getItems()return self.items end
  function value:getContainingItem()return self.owner end
  function value:getParent()return self.parent end
  return value
 end
 local root=container();local actor={class='IsoPlayer',inventory=root};root.parent=actor
 function actor:getInventory()return self.inventory end
 function actor:getPrimaryHandItem()return self.primary end
 function actor:getSecondaryHandItem()return self.secondary end
 function actor:isFemale()return false end
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
 env.require=function()end
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
 local env=setmetatable({PZSurvivorToolkit={}},{__index=function(_,key)
  if key=='getClassSimpleName'or key=='instanceof'or key=='getScriptManager'or key=='ItemTag'then return nil end
  return _G[key]
 end});local costs=assert(setfenv(assert(loadfile(modulePath)),env))()
 assert(costs==env.PZSurvivorToolkit.ActionQueueGroomingCosts,'missing globals broke harmless bootstrap')
 assert(not costs.apply({hairStyle='Spike'},{},{},function()return true end))
end
string.contains=oldContains
print('PASS native paid hair late selectors/costs, complete future inputs, ancestry and atomic fail-closed inspection')

next=savedNext
