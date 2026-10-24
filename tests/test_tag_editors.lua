-- Contract tests for draft isolation, stale edits and physical selection identity.
PZSurvivorToolkit={}
UIFont={Small=1,Medium=2}
Joypad={AButton=1,BButton=2}
getText=function(key) return key end
getTextManager=function() return {getFontHeight=function() return 16 end,
    MeasureStringX=function(_,_,value) return #value*8 end} end
local screenWidth,screenHeight=1600,900
getCore=function() return {getScreenWidth=function() return screenWidth end,getScreenHeight=function() return screenHeight end} end
getSpecificPlayer=function() end
getTexture=function(key) if key == 'Item_Missing' then return nil end return {key=key} end
ColorInfo={new=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end}
instanceof=function(item,class) return type(item)=='table' and item.inventoryItem and class=='InventoryItem' end
Events={OnFillInventoryObjectContextMenu={Add=function(callback) Events.callback=callback end}}
local Base={}
function Base:derive() local class={};setmetatable(class,{__index=self});return class end
function Base:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h,visible=true,items={}}, {__index=self}) end
function Base:initialise() end
function Base:instantiate() if self.built then return end;self.built=true;if self.createChildren then self:createChildren() end end
function Base:createChildren() end
function Base:addChild() end
function Base:addToUIManager() self:instantiate();self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:destroy() self:removeFromUIManager() end
function Base:removeSelf() self:removeFromUIManager() end
function Base:prerender() end
function Base:setVisible(value) self.visible=value end
function Base:getIsVisible() return self.visible end
function Base:setTooltip(value) self.tooltip=value end
function Base:setTitle(value) self.title=value end
function Base:setEnable(value) self.enable=value end
function Base:setImage(value) self.image=value end
function Base:forceImageSize() end
function Base:setMaxTextLength() end
function Base:setEditable(value) self.editable=value end
function Base:unfocus() self.focused=false end
function Base:hidePopup() self.popup.visible=false end
function Base:drawText() end
function Base:bringToTop() self.raised=true end
function Base:getAbsoluteX() return self.x end
function Base:getAbsoluteY() return self.y end
function Base:getHeight() return self.height end
function Base:setX(x) self.x=x end
function Base:setY(y) self.y=y end
function Base:setPickedFunc(callback) self.picked=callback end
function Base:setInitialColor(value) self.initialColor=value end
function Base:clear() self.items={} end
function Base:addItem(label,item) self.items[#self.items+1]={text=label,item=item,height=self.itemheight,index=#self.items+1} end
function Base:setOnMouseDownFunction(target,callback) self.target,self.onmousedown=target,callback end
function Base:setOnMouseDoubleClick(target,callback) self.doubleTarget,self.doubleCallback=target,callback end
function Base:addOptionWithData(label,value) self.options=self.options or {};self.options[#self.options+1]={label=label,value=value} end
function Base:getOptionData(index) return self.options[index].value end
ISCollapsableWindowJoypad,ISScrollingListBox,ISComboBox,ISPanel=Base,Base:derive(),Base:derive(),Base:derive()
ISButton=Base:derive()
ISLabel=Base:derive()
function ISLabel:new(x,y,h,label)
    local value=Base.new(self,x,y,0,h);value.name=label;return value
end
function ISButton:new(x,y,w,h,title,target,callback)
    local value=Base.new(self,x,y,w,h);value.title,value.target,value.callback=title,target,callback;return value
end
ISTextEntryBox=Base:derive()
function ISTextEntryBox:new(value,x,y,w,h) local entry=Base.new(self,x,y,w,h);entry.value=value;return entry end
function ISTextEntryBox:getInternalText() return self.value end
function ISTextEntryBox:setText(value) self.value=value end
ISColorPickerHSB=Base:derive()
ISModalDialog=Base:derive()
function ISModalDialog:new(x,y,w,h,label,yesno,target,callback)
    local modal=Base.new(self,x,y,w,h);modal.target,modal.callback=target,callback;return modal
end
local revision=4
local definitions={['custom:one']={name='My tag',color={r=.2,g=.4,b=.6},icon='Item_Hammer'}}
local active={'food','tool','custom:one'}
local typeDeltas={['Base.Hammer']={food='add'}}
local Custom={}
function Custom.hasEntries(value)for _ in pairs(value)do return true end;return false end
next=nil -- Native Kahlua has no next global.
function Custom.getRevision() return revision end
function Custom.definition(id) return definitions[id] end
function Custom.customIds() return {'custom:one'} end
function Custom.isActive(id) for _,value in ipairs(active) do if value==id then return true end end return id:sub(1,9)=='category:' end
function Custom.typeDelta(fullType) return typeDeltas[fullType] or {} end
function Custom.itemDelta(item) return item.delta or {} end
local Tags={enabled=function() return true end,allIds=function(items) local out={};for _,id in ipairs(active)do out[#out+1]=id end;for _,item in ipairs(items or {})do for _,id in ipairs(item.base)do local found=false;for _,saved in ipairs(out)do if saved==id then found=true end end;if not found then out[#out+1]=id end end end;return out end}
function Tags.label(id) return definitions[id] and definitions[id].name or id end
function Tags.defaultLabel(id) return id end
function Tags.automaticForItem(item) return item.base end
function Tags.revision() return tostring(revision) .. ":0" end
local Visuals={}
function Visuals.defaults() return {r=.8,g=.8,b=.8,icon='Item_Default'} end
function Visuals.get(id)
    local definition=definitions[id] or {};local color=definition.color or Visuals.defaults()
    return {r=color.r,g=color.g,b=color.b,icon=definition.icon or 'Item_Default',texture=getTexture(definition.icon or 'Item_Default')}
end
local lastRequest,requests= nil,0
local Client={}
function Client.edit(playerNum,id,definition,callback,baseRevision)
    requests=requests+1;lastRequest={kind='edit',playerNum=playerNum,id=id,value=definition,callback=callback,revision=baseRevision};return requests
end
function Client.assign(playerNum,items,scope,changes,reset,callback,baseRevision)
    requests=requests+1;lastRequest={kind='assign',playerNum=playerNum,items=items,scope=scope,changes=changes,
        reset=reset,callback=callback,revision=baseRevision};return requests
end
local scripts={
    {getIcon=function() return 'Hammer' end,getDisplayName=function() return 'Hammer' end},
    {getIcon=function() return 'Hammer' end,getDisplayName=function() return 'Duplicate' end},
    {getIcon=function() return 'Missing' end,getDisplayName=function() return 'Missing texture' end}}
getScriptManager=function() return {getAllItems=function() return {size=function() return #scripts end,get=function(_,i) return scripts[i+1] end} end} end
local modules={['PZSurvivorToolkit/ItemTags']=Tags,['PZSurvivorToolkit/TagCustomization']=Custom,
    ['PZSurvivorToolkit/TagCustomizationClient']=Client,['PZSurvivorToolkit/TagVisuals']=Visuals}
require=function(name)
    assert(not name:find('BetterContainers',1,true),'tag editor loaded BetterContainers')
    if name:sub(1,5)=='ISUI/' or name=='PZSurvivorToolkit' then return end
    if not modules[name] then modules[name]=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua') end
    return modules[name]
end
local Catalog=require('PZSurvivorToolkit/TagEditor')
local Assignment=require('PZSurvivorToolkit/ItemTagEditor')
local Icons=require('PZSurvivorToolkit/TagIconPicker')
local catalog=Catalog.open({playerNum=0})
assert(catalog.added and catalog.width<=1600 and catalog.height<=900)
catalog:select({id='custom:one'})
catalog.nameEntry:setText('Draft name');catalog.draft.color.r=.95
assert(definitions['custom:one'].name=='My tag' and definitions['custom:one'].color.r==.2,'draft mutated live definition')
catalog:select({id='food'});catalog:select({id='custom:one'})
assert(catalog.nameEntry.value=='Draft name','switching tags lost draft')
catalog:save()
assert(lastRequest.value.name=='Draft name' and lastRequest.revision==4)
assert(catalog.nameEntry.editable==false and catalog.newButton.enable==false,'pending request left mutable draft controls active')
lastRequest.callback('conflict',{})
assert(catalog.draft.name=='Draft name' and catalog.added and catalog.status:find('Conflict'),'conflict lost catalog draft')
revision=5;catalog:reloadDraft()
assert(catalog.draft.name=='My tag' and catalog.baseRevision==5,'explicit reload did not refresh draft revision')
catalog:select({id='food'});catalog:chooseColor()
catalog.toolkitColorPicker.picked(nil,{r=.1,g=.2,b=.3});catalog:save()
assert(lastRequest.value.name==nil and lastRequest.value.color.r==.1,'color edit froze built-in translated name')
lastRequest.callback('rejected',{});assert(catalog.added and catalog.draft.color.r==.1,'rejection lost draft')
local priorRequest=lastRequest
catalog:resetDefinition();assert(lastRequest==priorRequest,'reset changed live state before Save')
catalog:save();assert(lastRequest.value.name==false and lastRequest.value.color==false,'reset did not clear built-in overrides')
lastRequest.callback('rejected',{})
catalog:select({id='custom:one'});catalog:deleteDefinition()
local modal=catalog.confirmation;modal.callback(catalog,{internal='YES'})
assert(lastRequest.value.deleted==nil,'confirmed deletion changed live state before Save')
catalog:save()
assert(lastRequest.value==false,'delete did not request authoritative removal')
lastRequest.callback('accepted',{});assert(catalog.added,'catalog closed after accepted write')
catalog:newTag();catalog.nameEntry:setText('New');catalog:save()
assert(lastRequest.id==nil and lastRequest.value.name=='New','new tag did not request server identity')
local accepted=lastRequest.callback;catalog:close();accepted('accepted',{id='custom:new'})
assert(catalog.toolkitTagClosed and not catalog.added,'late acceptance reopened closed catalog')
local before=requests;catalog=Catalog.open();catalog:newTag();catalog.nameEntry:setText('Unsaved');catalog:close()
assert(requests==before,'cancel submitted a definition')

local function item(id,delta)
    return {inventoryItem=true,id=id,base={'tool'},delta=delta,getFullType=function() return 'Base.Hammer' end,
        getName=function() return 'Hammer '..id end}
end
local a,b,c=item(1,{food='remove',['custom:one']='add'}),item(2,{food='add'}),item(3,{})
local rows={{items={a,a,b}},{type='separator',items={c}},a,{items={c},cleanUILargeStackOptimized=true}}
local selected=Assignment.itemsIn(rows)
assert(#selected==3 and selected[1]==a and selected[2]==b and selected[3]==c,'native/CleanUI rows lost physical identity or duplicated items')
assert(#Assignment.itemsIn({{items={a,b,c},cleanUIFirstActualIndex=3}})==1,'CleanUI explicit first index ignored')
local window=Assignment.open({items={a,b}})
assert(window:scope()=='item' and window:state('food')=='mixed' and window:presence('food')=='Mixed')
window:cycle({id='tool'})
assert(window:draft().changes.tool=='add' and a.delta.food=='remove' and a.delta['custom:one']=='add' and a.delta.tool==nil,
    'assignment draft changed live item')
window:cycle({id='tool'});assert(window:draft().changes.tool=='remove' and window:presence('tool')=='Absent')
window:save()
assert(lastRequest.scope=='item' and lastRequest.changes.tool=='remove' and lastRequest.changes.food==nil
    and lastRequest.changes['custom:one']==nil,'mixed untouched overrides were erased')
lastRequest.callback('conflict',{})
assert(window.added and window:draft().changes.tool=='remove','conflict erased assignment patch')
window.scopeCombo.selected=2;window:changeScope()
assert(window:state('food')=='add' and #window:targets()==1,'type targets not deduplicated')
window:resetAssignments();window:cycle({id='custom:one'});window:save()
assert(lastRequest.scope=='type' and lastRequest.reset and lastRequest.changes['custom:one']=='add','reset did not retain later draft patches')
lastRequest.callback('rejected',{})
window.scopeCombo.selected=1;window:changeScope()
assert(window:draft().changes.tool=='remove','scope switch lost item draft')
window:reload();assert(not Custom.hasEntries(window:draft().changes) and not window:draft().reset,'reload kept stale patches')
window:save();assert(window.status:find('NoChanges'))
window:openCatalog();local child=window.toolkitTagEditor
assert(child and window.dimmer.visible)
window:close();assert(child.toolkitTagClosed and not child.added,'closing owner leaked nested editor')

local entries=Icons.entries();local found,missing=0,false
for _,entry in ipairs(entries) do
    if entry.icon=='Item_Hammer' then found=found+1 end
    if entry.icon=='Item_Missing' then missing=entry.texture==nil and entry.label=='Missing texture' end
end
assert(found==1 and missing,'script icons not deduplicated or missing texture lacks text fallback')
catalog=Catalog.open();catalog:chooseIcon()
assert(catalog.toolkitIconPicker and catalog.dimmer.visible,'icon picker did not reuse native popup')
assert(catalog.toolkitIconPicker.searchCaption=='UI_PZST_TagEdit_SearchIcons'
    and catalog.toolkitIconPicker.searchLabel.name=='UI_PZST_TagEdit_SearchIcons'
    and catalog.toolkitIconPicker.search.tooltip=='UI_PZST_TagEdit_SearchIcons',
    'tag icon search caption was overwritten by its native label widget')
assert(catalog.toolkitIconPicker.search.y==54 and catalog.toolkitIconPicker.list.y==86,
    'shared icon popup lost its visible search label layout')
catalog.toolkitIconPicker.onPick('Item_Hammer');catalog.toolkitIconPicker:close()
assert(catalog.draft.icon=='Item_Hammer' and not catalog.dimmer.visible)
local defaultPopup=require('PZSurvivorToolkit/ContainerIconPicker').openEntries(catalog,function()end,entries)
assert(defaultPopup.searchLabel.name=='UI_PZST_ContainerIconSearch'
    and defaultPopup.search.tooltip=='UI_PZST_ContainerIconSearch'
    and defaultPopup.defaultButton.title=='UI_PZST_ContainerDefault'
    and defaultPopup.selectButton.title=='UI_PZST_ContainerSelectIcon',
    'shared icon popup lost localized container captions')
defaultPopup:close()
catalog:close()
local options={}
local context={addOption=function(_,label,target,callback) local option={label=label,target=target,callback=callback};options[#options+1]=option;return option end}
Assignment.fillMenu(0,context,{{items={a,a,b}}})
assert(#options==2 and options[1].pzstKey=='editItemTags' and options[2].pzstKey=='manageTags')
options[1].callback(options[1].target)
screenWidth,screenHeight=800,600
window=Assignment.open({items={a}});catalog=Catalog.open()
assert(window.x>=0 and window.y>=0 and window.list.height>40 and window.preview.height>=60)
assert(catalog.x>=0 and catalog.y>=0 and catalog.list.height>40,'small screen layout escaped viewport')
window:close();catalog:close()
print('Tag editors: isolated drafts, mixed patches, conflicts, shared scope, icon catalogue and native controls OK')

local unknownItem=item(99,{});unknownItem.base={'category:Mod.InstanceOnly'}
local unknownWindow=Assignment.open({items={unknownItem}})
local found=false
for _,row in ipairs(unknownWindow.list.items)do if row.item.id=='category:Mod.InstanceOnly' then found=true end end
assert(found,'assignment editor omitted selected item automatic fallback tag')
unknownWindow:cycle({id='category:Mod.InstanceOnly'});unknownWindow:cycle({id='category:Mod.InstanceOnly'})
unknownWindow:save()
assert(lastRequest.changes['category:Mod.InstanceOnly']=='remove','unknown automatic tag removal was not sent')
lastRequest.callback('rejected',{})
local unknownCatalog=unknownWindow:openCatalog()
assert(unknownCatalog.tagItems[1]==unknownItem,'assignment catalog lost exact item category context')
unknownCatalog:select({id='category:Mod.InstanceOnly'});unknownCatalog.nameEntry:setText('Edited fallback');unknownCatalog:save()
assert(lastRequest.id=='category:Mod.InstanceOnly' and lastRequest.value.name=='Edited fallback','fallback tag definition editing failed')
unknownWindow:close()

-- A definition saved from the assignment window is a known own transaction.
-- Advance only through that accepted revision, preserving both scope drafts.
revision=10
local parent=Assignment.open({items={a}})
parent:cycle({id='tool'})
parent.scopeCombo.selected=2;parent:changeScope();parent:cycle({id='food'})
parent.scopeCombo.selected=1;parent:changeScope()
local itemDraft,typeDraft=parent.drafts.item,parent.drafts.type
local ownedCatalog=parent:openCatalog()
ownedCatalog:newTag();ownedCatalog.nameEntry:setText('Own new tag');ownedCatalog:save()
assert(lastRequest.revision==10)
revision=12 -- Another world edit arrived after our accepted revision 11.
lastRequest.callback('accepted',{id='custom:created',revision=11})
assert(parent.baseRevision==11 and parent.drafts.item==itemDraft and parent.drafts.type==typeDraft
    and itemDraft.changes.tool=='add' and typeDraft.changes.food=='remove',
    'own catalog save lost assignment drafts or rebased across a concurrent world edit')
ownedCatalog:close();parent:save()
assert(lastRequest.kind=='assign' and lastRequest.revision==11,'assignment did not use its own accepted catalog revision')
parent:close()

revision=20
parent=Assignment.open({items={a}});parent:cycle({id='tool'})
itemDraft=parent.drafts.item
revision=21 -- Parent predates the catalog draft, so it already needs a conflict.
ownedCatalog=parent:openCatalog();ownedCatalog:newTag();ownedCatalog.nameEntry:setText('Stale parent tag');ownedCatalog:save()
assert(lastRequest.revision==21)
revision=22;lastRequest.callback('accepted',{revision=22})
assert(parent.baseRevision==20 and parent.drafts.item==itemDraft and itemDraft.changes.tool=='add',
    'catalog save silently rebased an already-stale parent assignment')
parent:close()
print('Tag editors: own catalog acceptance advances only a fresh parent revision and preserves assignment drafts')
