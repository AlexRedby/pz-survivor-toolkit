-- The normal classification hook owns retention ordering even without BC,
-- tags or inventory filters. Exercise the actual grouping/order/row helpers.
package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/?.lua;'..package.path
local callbacks={}
-- CleanUI invokes subscribers immediately while mods are still loading.
CleanUI_RegisterInventoryUiToggleCallback=function(fn)callbacks.toggle=fn;fn()end
Events={}
for _,name in ipairs({'OnGameBoot','OnGameStart','OnCreatePlayer'})do
 Events[name]={Add=function(fn)callbacks[name]=fn end}
end
function table.wipe(t)for key in pairs(t)do t[key]=nil end end
instanceof=function(value,kind)return kind=='InventoryItem' and value and value.getFullType~=nil end
local originalRequire=require
require=function(name)
 if name=='ISUI/ISInventoryPane'then return end
 if name=='PZSurvivorToolkit/ItemCategories'then return {prepareContainer=function()end}end
 if name=='PZSurvivorToolkit/LegacyItemCategories'then return {reset=function()end}end
 if name=='PZSurvivorToolkit/ItemTags'then return {enabled=function()return false end}end
 if name=='PZSurvivorToolkit/ItemRetention'then
  return {isRetained=function(item)return item.kept==true end}
 end
 return originalRequire(name)
end
local function item(id)return {id=id,getFullType=function()return 'Base.Thread'end,
 getDisplayCategory=function()return 'same'end,getUnequippedWeight=function()return 1 end}end
local a,b,c=item(1),item(2),item(3)
local function class(headerless)
 local class={MAX_ITEMS_IN_STACK_TO_RENDER=50}
 function class:restoreSelection(saved)
  require("PZSurvivorToolkit/InventoryRows").restoreSelection(self,saved)
 end
 function class:saveSelection(saved)
  for _,value in pairs(self.selected)do
   if value.items then saved[value.items[1]]='group' else saved[value]='item'end
  end
  return saved
 end
 function class:refreshContainer()
  local saved=self:saveSelection({})
  self.itemslist={{name='thread',cat='same',items=headerless and {a,b,c}or {a,a,b,c},
   cleanUIFirstActualIndex=headerless and 1 or 2}}
  table.wipe(self.selected)
  self:restoreSelection(saved)
  return 'native'
 end
 return class
end
ISInventoryPane=class(false)
CleanUI_Clean_ISInventoryPane=class(true)
dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/ToolkitItemCategories.lua')
-- BC installs a direct restore replacement after Toolkit's top-level load.
-- Keep this as a replacement, not a forwarding decorator: that is the native
-- lifecycle which previously erased Toolkit's early split hook.
local laterRestores=0
for _,class in ipairs({ISInventoryPane,CleanUI_Clean_ISInventoryPane})do
 class.restoreSelection=function(pane,saved)
  laterRestores=laterRestores+1
  require("PZSurvivorToolkit/InventoryRows").restoreSelection(pane,saved)
 end
end
callbacks.OnGameBoot()
for _,class in ipairs({ISInventoryPane,CleanUI_Clean_ISInventoryPane})do
 a.kept,b.kept,c.kept=false,false,false
 local pane=setmetatable({inventory={},items={},itemslist={},collapsed={thread=false},selected={},mode='details'},
  {__index=class})
 -- Begin with an expanded physical selection, then mark a different copy.
 pane.selected={[3]=b};c.kept=true
 assert(pane:refreshContainer()=='native')
 assert(#pane.itemslist==2 and pane.itemslist[1].items[1]==c,'No-BC hook did not split and prioritize retained copies')
 local count=0
 for _,value in pairs(pane.selected)do count=count+1;assert(value==b,'No-BC ordering changed exact selection')end
 assert(count==1)
 -- The group selection must remain exact when a release merges both rows.
 pane.selected={[1]=pane.itemslist[1]};c.kept=false
 pane:refreshContainer()
 assert(#pane.itemslist==1,'Released copies failed to merge')
 count=0
 for _,value in pairs(pane.selected)do count=count+1;assert(value==c,'Release widened selected group')end
 assert(count==1)
end
assert(laterRestores>0,'Native replacement restore was bypassed')
print('Inventory order: actual standalone native/headerless classification hooks split/prioritize retained copies and preserve exact selection on release with tags/BC absent.')
