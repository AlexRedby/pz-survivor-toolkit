local enabled, tagsEnabled = true, true
PZSurvivorToolkit = {Settings={contextMenus=function() return enabled end,itemTags=function() return tagsEnabled end}}
UIFont={Small=1}
getText=function(key) return key end
getTextManager=function()
    return {getFontHeight=function() return 16 end, MeasureStringX=function(_,_,value) return #value*8 end}
end
getCore=function() return {getScreenWidth=function() return 784 end, getScreenHeight=function() return 564 end} end
getFileReader=function() end
getFileWriter=function() return {write=function() end,close=function() end} end
local Base={}
function Base:new(x,y,width,height)
    return setmetatable({x=x,y=y,width=width,height=height,items={},options={},selected=0,children={}}, {__index=self})
end
function Base:derive() return setmetatable({}, {__index=self}) end
function Base:initialise() end
function Base:instantiate() if self.createChildren then self:createChildren() end end
function Base:createChildren() end
function Base:prerender() end
function Base:addChild(child) self.children[#self.children+1]=child end
function Base:addToUIManager() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:setVisible(value) self.visible=value end
function Base:setTooltip(value) self.tooltip=value end
function Base:setPlaceholderText(value) self.placeholder=value end
function Base:setEnable(value) self.enable=value end
function Base:bringToTop() self.raised=true end
function Base:drawText() end
function Base:drawRect() end
function Base:clear() self.items,self.options,self.selected={},{},0 end
function Base:addItem(label,item)
    self.items[#self.items+1]={text=label,item=item,index=#self.items+1}
end
function Base:setOnMouseDownFunction(target,callback) self.target,self.onmousedown=target,callback end
function Base:addOptionWithData(label,data) self.options[#self.options+1]={label=label,data=data};if self.selected==0 then self.selected=1 end end
function Base:getOptionData(index) return self.options[index].data end
ISCollapsableWindow,ISScrollingListBox,ISComboBox=Base,Base:derive(),Base:derive()
function ISComboBox:setToolTipMap(value) self.tooltip=value end
ISButton=Base:derive()
function ISButton:new(x,y,w,h,title,target,callback)
    local button=Base.new(self,x,y,w,h);button.title,button.target,button.callback=title,target,callback;return button
end
ISTextEntryBox=Base:derive()
function ISTextEntryBox:new(value,x,y,w,h) local entry=Base.new(self,x,y,w,h);entry.value=value;return entry end
function ISTextEntryBox:getText() return self.value end
function ISTextEntryBox:setText(value) self.value=value end

local client=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/'
local shared=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'
local sharedModules={}
local function sharedRequire(name)
    if not sharedModules[name] then sharedModules[name]=assert(loadfile(shared..name..'.lua'))() end
    return sharedModules[name]
end
require=sharedRequire
local Tags=sharedRequire('PZSurvivorToolkit/ItemTags')
local Schema=sharedRequire('PZSurvivorToolkit/ItemTagSchema')
local Organizer=dofile(client..'ContextMenuProfile.lua').new({groups={'equipment','research'}},Tags)
Organizer.rememberItem('Base.Hammer','Hammer',{'tool'})
Organizer.rememberItem('Base.Book','Book',{'literature'})
Organizer.lastItemType='Base.Hammer'
local pickerOptions, lastPicker
local Picker={open=function(options)
    pickerOptions=options
    lastPicker={close=function(self) self.closed=true;if options.owner.toolkitRulePicker==self then options.owner.toolkitRulePicker=nil end end}
    options.owner.toolkitRulePicker=lastPicker
    return lastPicker
end}
local root={{key='inspect',label='Inspect',kind='action'},{key='group:equipment',label='Equipment',kind='group',category='equipment'}}
local equipment={{key='equip',label='Equip',kind='action'},{key='unequip',label='Unequip',kind='action'}}
for _,scope in ipairs({'*','Base.Hammer'}) do
    Organizer.record(scope,'inspect','Inspect','root')
    Organizer.record(scope,'equip','Equip','equipment')
    Organizer.record(scope,'unequip','Unequip','equipment')
    Organizer.captureLayout(scope,{root=root,equipment=equipment})
end
Organizer.record('Base.Book','read','Read','research')
Organizer.captureLayout('Base.Book',{root={{key='group:research',label='Reading',kind='group',category='research'}},research={{key='read',label='Read',kind='action'}}})
require=function(name)
    if name:sub(1,5)=='ISUI/' then return end
    if name=='PZSurvivorToolkit/ContextMenus' then return Organizer end
    if name=='PZSurvivorToolkit/UIStyle' then return {button=function() end} end
    if name=='PZSurvivorToolkit/TagRulePicker' then return Picker end
    if name=='PZSurvivorToolkit/ItemTags' then return Tags end
    if name=='PZSurvivorToolkit/ItemTagSchema' then return Schema end
    error('unexpected dependency '..name)
end
local Editor=dofile(client..'ContextMenuEditor.lua')
local editor=Editor.show()
assert(editor.width==760 and editor.height==540 and editor.added,'small screen size/lifetime')
local drawn, measures = {}, 0
function editor.list:drawText(label) drawn[#drawn+1]=label end
local manager=getTextManager
getTextManager=function()
    return {MeasureStringX=function(_,_,label)
        measures=measures+1;assert(measures<1000,'long translated label never finishes clipping')
        return #label*8
    end}
end
editor.list:doDrawItem(0,{index=0,item={label=string.rep('Кастрюля',20),category='root'}})
getTextManager=manager
assert(#drawn==2 and drawn[1]:sub(-3)=='...' and #drawn[1]*8<=editor.list.width-28,'long translated label not clipped')
assert(not drawn[1]:gsub('[\194-\244][\128-\191]+',''):find('[\128-\255]'),'clipping split a UTF-8 character')
for _,child in ipairs(editor.children) do
    assert(child.x>=0 and child.y>=0 and child.x+child.width<=editor.width and child.y+child.height<=editor.height,'control outside window')
end
assert(editor.scopeID=='*' and editor.previewID=='Base.Hammer' and #editor.list.items==4,'scope must default to all items independently of preview')
assert(Editor.show()==editor and editor.raised,'editor duplicated')
local function option(combo,id)
    for index=1,#combo.options do if combo:getOptionData(index)==id then combo.selected=index;return end end
    error('missing option '..tostring(id))
end
local function row(list,key)
    for index,value in ipairs(list.items) do if value.item.key==key then list.selected=index;return value.item end end
    error('missing row '..key)
end
option(editor.scope,'Base.Hammer');editor:changeScope()
editor:selectEntry(row(editor.list,'equip'))
option(editor.destination,'root');editor:applyEntry()
assert(Organizer.getOverride('equip','Base.Hammer')=='root' and Organizer.getOverride('equip','Base.Book')==nil,'item rule leaked')
option(editor.destination,false);editor:applyEntry()
assert(Organizer.getOverride('equip','Base.Hammer')==nil,'automatic did not remove item rule')
option(editor.parent,'equipment');editor:changeParent()
row(editor.orderList,'unequip');editor:moveUp()
assert(editor.orderList.items[1].item.key=='unequip' and editor.orderList.selected==1,'action order/selection lost')
editor:moveDown()
assert(editor.orderList.items[2].item.key=='unequip','action move down failed')
option(editor.parent,'root');editor:changeParent()
row(editor.orderList,'group:equipment');editor:selectOrderEntry()
assert(editor.renameButton.enable and not editor.deleteButton.enable,'built-in group controls invalid')
editor.groupName:setText('Weapons');editor:renameGroup()
assert(Organizer.groupName('equipment','Base.Hammer')=='Weapons' and Organizer.groupName('equipment','*')~='Weapons','rename scope leaked')
editor:moveUp()
assert(editor.orderList.items[1].item.key=='group:equipment','group reorder failed')
editor.groupName:setText('');editor:createGroup()
assert(editor.status and #Organizer.groupIds()==2,'invalid group created')
editor.groupName:setText('Favorites');editor:createGroup()
local group=editor.parentID
assert(Organizer.isCustomGroup(group) and editor.status==nil and editor.parent:getOptionData(editor.parent.selected)==group,'group creation/navigation failed')
editor:selectEntry(row(editor.list,'inspect'));option(editor.destination,group);editor:applyEntry()
assert(editor.orderList.items[1].item.key=='inspect','custom group layout stale')
editor:selectOrderEntry()
assert(editor.deleteButton.enable,'custom group cannot be deleted')
editor.groupName:setText('My favorites');editor:renameGroup()
assert(Organizer.groupName(group,'Base.Hammer')=='My favorites','custom rename failed')
editor:deleteGroup()
assert(not Organizer.isCustomGroup(group) and Organizer.getOverride('inspect','Base.Hammer')==nil and editor.parentID=='root','custom deletion did not clear placement')
editor:resetScope()
assert(Organizer.groupName('equipment','Base.Hammer')~='Weapons' and #Organizer.getOrder('Base.Hammer','root')==0,'item reset left edits')
option(editor.scope,'Base.Book');editor:changeScope()
assert(#editor.list.items==1 and editor.list.items[1].item.key=='read','item discovery was not scoped')
option(editor.scope,'*');editor:changeScope()
assert(not editor.resetButton.enable,'global scope exposed item reset')
editor.search:setText('equip');editor:prerender()
assert(#editor.list.items==2,'action search failed')
editor.search:setText('');editor:prerender()
editor:selectEntry(row(editor.list,'inspect'));option(editor.destination,'hidden');editor:applyEntry()
assert(Organizer.getOverride('inspect','Base.Book')=='hidden','global rule not inherited')
editor.groupName:setText('Temporary');editor:createGroup();editor:resetRules()
assert(Organizer.getOverride('inspect','*')==nil and #Organizer.groupIds()==2 and #Organizer.getOrder('Base.Hammer','equipment')==0,'all reset left changes')
Organizer.captureLayout('*',{root={
    {key='before-title',label='Before',kind='action'},
    {key='section-title',label='Section',kind='title'},
    {key='after-title',label='After',kind='action'},
}})
option(editor.preview,false);editor:changePreview()
editor:reload()
row(editor.orderList,'before-title');editor:updateButtons()
assert(not editor.downButton.enable,'move down enabled across a native title')
row(editor.orderList,'after-title');editor:updateButtons()
assert(not editor.upButton.enable,'move up enabled across a native title')
row(editor.orderList,'section-title');editor:updateButtons()
assert(not editor.upButton.enable and not editor.downButton.enable,'native title can be moved')
local toolRule={mode='all',include={'tool'},exclude={}}
editor.profileName:setText('');editor:createTagProfile()
assert(not pickerOptions and editor.status,'blank profile name opened picker')
editor.profileName:setText('Tools');editor:createTagProfile()
local categoryCount=0;for _ in pairs(Schema.categories) do categoryCount=categoryCount+1 end
assert(pickerOptions.owner==editor and #pickerOptions.categories==categoryCount,'profile picker omitted undiscovered categories')
pickerOptions.onApply({mode='all',include={},exclude={}});lastPicker:close()
assert(#Organizer.tagProfiles==0 and editor.status,'empty filter created a profile')
editor:createTagProfile();pickerOptions.onApply(toolRule);lastPicker:close()
local toolsProfile=editor.scopeID
assert(Organizer.getTagProfile(toolsProfile).name=='Tools' and editor.previewID=='Base.Hammer','profile creation did not choose a matching example')
editor.profileName:setText('Hand tools');editor:renameTagProfile()
assert(Organizer.getTagProfile(toolsProfile).name=='Hand tools','profile rename failed')
editor:editTagProfile()
assert(pickerOptions.rule.include[1]=='tool','saved profile filter not loaded')
pickerOptions.onApply({mode='any',include={'tool','crafting'},exclude={}});lastPicker:close()
assert(Organizer.getTagProfile(toolsProfile).rule.mode=='any','profile filter update failed')
editor.profileName:setText('Other tools');editor:createTagProfile();pickerOptions.onApply(toolRule);lastPicker:close()
local otherProfile=editor.scopeID
assert(editor.profileUpButton.enable and not editor.profileDownButton.enable,'profile priority boundaries incorrect')
editor:raiseTagProfile()
assert(Organizer.tagProfiles[1].id==otherProfile and not editor.profileUpButton.enable and editor.profileDownButton.enable,'profile higher priority not saved')
editor:lowerTagProfile()
assert(Organizer.tagProfiles[2].id==otherProfile,'profile lower priority not saved')
Organizer.setOverride('equip','hidden','*')
option(editor.scope,'Base.Hammer');editor:changeScope()
editor:selectEntry(row(editor.list,'equip'))
assert(editor.destination:getOptionData(editor.destination.selected)==false,'inherited placement shown as an own override')
option(editor.preview,'Base.Book');editor:changePreview()
assert(editor.scopeID=='Base.Hammer' and editor.previewID=='Base.Book','example selection changed rule scope')
option(editor.scope,otherProfile);editor:changeScope();editor:deleteTagProfile()
assert(not Organizer.getTagProfile(otherProfile) and editor.scopeID=='*','profile deletion or scope fallback failed')
tagsEnabled=false;editor:updateButtons();pickerOptions=nil
assert(not editor.profileCreateButton.enable,'profile creation enabled with tags off')
editor:createTagProfile()
assert(pickerOptions==nil,'disabled tags opened picker')
tagsEnabled=true;editor.profileName:setText('Closing test');editor:createTagProfile()
local childPicker=lastPicker
enabled=false;editor:prerender()
assert(not editor.added and not Editor.show() and childPicker.closed,'disabled editor or child picker remained open')
print('Context menu editor checks passed: scopes, previews, tag profiles, inheritance, ordering, group CRUD, search and resets.')
