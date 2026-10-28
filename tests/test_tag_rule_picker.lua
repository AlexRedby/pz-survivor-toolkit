local enabled, applied, firstSelected = true, nil, nil
PZSurvivorToolkit = {Settings={itemTags=function() return enabled end}}
getText=function(key) return key end
getTextOrNull=function() end
UIFont={Small=1}
Joypad={AButton=1,BButton=2,XButton=3,YButton=4}
local measurements, draws, projections = 0, 0, 0
getTextManager=function() return {getFontHeight=function() return 16 end,
    MeasureStringX=function(_,_,value) measurements=measurements+1;return #value*8 end} end
local screenWidth=800
getCore=function() return {getScreenWidth=function() return screenWidth end,getScreenHeight=function() return 600 end} end
local Base={}
function Base:new(x,y,width,height)
    return setmetatable({x=x,y=y,width=width,height=height,items={},visible=true,scroll=0,selected=1}, {__index=self})
end
function Base:derive() local result={};setmetatable(result,{__index=self});return result end
function Base:initialise() end
function Base:instantiate() if self.createChildren then self:createChildren() end end
function Base:createChildren() end
function Base:prerender() end
function Base:addChild() end
function Base:addToUIManager() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:unfocus() self.focused=false end
function Base:hidePopup() self.popup.visible=false end
function Base:setVisible(value) self.visible=value end
function Base:getIsVisible() return self.visible end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
function Base:getYScroll() return self.scroll end
function Base:setYScroll(value) self.scroll=value end
function Base:setScrollHeight(value) self.scrollHeight=value end
function Base:getScrollHeight() return self.scrollHeight or self.count*self.itemheight end
function Base:getMouseX() return self.mouseX or 130 end
function Base:setTooltip(value) self.tooltip=value end
function Base:setTitle(value) self.title=value end
function Base:setEnable(value) self.enable=value end
function Base:drawText() draws=draws+1 end
function Base:drawRect() draws=draws+1 end
function Base:drawRectBorder() draws=draws+1 end
function Base:drawTextureScaledAspect() draws=draws+1 end
function Base:clear() self.items={};self.count=0;self.selected=1;self.scroll=0 end
function Base:addItem(label,item)
    self.items[#self.items+1]={text=label,item=item,height=self.itemheight,index=#self.items+1};self.count=#self.items
end
function Base:setOnMouseDownFunction(target,callback) self.target,self.onmousedown=target,callback end
function Base:addOptionWithData(label,data) self.options=self.options or {};self.options[#self.options+1]={label=label,data=data};self.selected=self.selected or 1 end
function Base:getOptionData(index) return self.options[index].data end
function Base:onGainJoypadFocus() end
function Base:insertNewLineOfButtons(...) self.focusRows=self.focusRows or {};self.focusRows[#self.focusRows+1]={...} end
function Base:restoreJoypadFocus() end
function Base:prevVisibleIndex(index) return index>1 and index-1 or -1 end
function Base:nextVisibleIndex(index) return index<#self.items and index+1 or -1 end
function Base:ensureVisible(index) self.ensured=index end
ISCollapsableWindowJoypad,ISScrollingListBox,ISComboBox,ISPanel=Base,Base:derive(),Base:derive(),Base:derive()
ISButton=Base:derive()
function ISButton:new(x,y,w,h,title,target,callback) local b=Base.new(self,x,y,w,h);b.title,b.target,b.callback=title,target,callback;return b end
ISTextEntryBox=Base:derive()
function ISTextEntryBox:new(value,x,y,w,h) local entry=Base.new(self,x,y,w,h);entry.value=value;return entry end
function ISTextEntryBox:getInternalText() return self.value end
local cache={}
require=function(name)
    if name:sub(1,5)=='ISUI/' then return end
    if name=='PZSurvivorToolkit/TagVisuals' then return {get=function() return {} end} end
    if cache[name] then return cache[name] end
    local side=(name=='PZSurvivorToolkit/UIStyle' or name=='PZSurvivorToolkit/TagRuleTagPicker') and 'client' or 'shared'
    cache[name]=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'..side..'/'..name..'.lua')
    return cache[name]
end
local Tags=require 'PZSurvivorToolkit/ItemTags'
local forScript=Tags.forScriptItem
Tags.forScriptItem=function(script) projections=projections+1;return forScript(script) end
local Picker=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TagRulePicker.lua')
local original={mode='all',include={'mechanics'},exclude={'vehiclepart'}}
local owner={getIsVisible=function() return true end,dimmer=Base:new(0,0,1,1)}
owner.dimmer.visible=false
local function open(options)
    options=options or {};options.owner=options.owner or owner
    options.onApply=options.onApply or function(rule,first) applied=rule;firstSelected=first end
    return Picker.open(options)
end
local picker=open({rule=original,categories={'mechanicsVehiclePart','foodPerishable'}})
assert(picker.added and owner.toolkitRulePicker==picker and owner.dimmer.visible)
assert(#picker.conditions==1 and #picker.conditions[1]==2 and picker.conditions[1][2].excluded)
assert(not picker.preview and not picker.entries,'editor eagerly built a catalogue or retained example items')
assert(picker.rule~=original and picker.rule.exclude~=original.exclude,'draft aliases saved rule')
picker:addGroup('perishable',false)
assert(Tags.matchesRule({'mechanics'},picker.rule) and not Tags.matchesRule({'mechanics','vehiclepart'},picker.rule))
assert(Tags.matchesRule({'perishable','vehiclepart'},picker.rule),'branch exclusion escaped into another OR group')
assert(picker.rule.groups and #picker.rule.groups==2)
picker:toggleCondition(1,2)
assert(Tags.matchesRule({'mechanics','vehiclepart'},picker.rule) and not Tags.matchesRule({'mechanics'},picker.rule))
picker:toggleCondition(1,2)
assert(not picker:addCondition(1,'mechanics',true) and #picker.conditions[1]==2,'duplicate contradictory tag accepted')
assert(#original.include==1 and original.exclude[1]=='vehiclepart','draft mutated saved rule')
picker:apply()
assert(applied.groups and firstSelected=='perishable' and not picker.added and not owner.dimmer.visible)
assert(not owner.toolkitRulePicker,'closed editor retained owner reference')
local any={mode='any',include={'food','mechanics'},exclude={'vehiclepart'}}
picker=open({rule=any});assert(#picker.conditions==2 and picker.conditions[1][2].excluded and picker.conditions[2][2].excluded)
picker:apply();assert(applied.mode=='any' and #applied.include==2 and applied.exclude[1]=='vehiclepart','legacy ANY changed meaning')
assert(firstSelected==nil,'reopening invented a first selection')
local large={mode='any',include={},exclude={}}
for index=1,64 do
    large.include[index]='category:include'..index..string.rep('a',100)
    large.exclude[index]='category:exclude'..index..string.rep('б',50)
end
local caption=Picker.summary(large)
assert(#caption<=323 and caption:sub(-3)=='...','large rule caption is unbounded')
assert(#large.include==64 and #large.exclude==64,'caption changed stored rule')
picker=open({rule=original,selectedTag='mechanics'});picker:removeCondition(1,1);picker:addCondition(1,'food',false)
picker:apply();assert(firstSelected=='food','removed tag remained an appearance suggestion')
picker=open();picker:addCondition(1,'mechanics');picker:addCondition(1,'food')
picker:removeCondition(1,1);picker:addCondition(1,'mechanics');picker:apply()
assert(firstSelected=='food','removed and re-added tag recovered its obsolete selection order')
picker=open({rule=original});picker:clearRule()
assert(#picker.conditions==0 and not Tags.ruleActive(picker.rule) and not picker.validationMessage)
picker:apply();assert(not Tags.ruleActive(applied),'clear did not remove filtering')

local function script(category) return {getDisplayCategory=function() return category end,
    getFullName=function() return 'Base.'..category end} end
local scripts={script('mechanicsVehiclePart'),script('foodPerishable'),script('Tool')}
picker=open({scriptItems=scripts,rule=original})
local before=projections
picker:addGroup('food');picker:toggleCondition(1,1);picker:prerender()
assert(projections==before,'ordinary rule edits reprojected the script catalogue')
local entries=picker:catalogEntries()
assert(projections==before+#scripts,'chooser did not prepare script tags exactly once')
local byId={};for _,entry in ipairs(entries) do byId[entry.id]=entry end
assert(byId.food and byId.perishable and byId.tool and byId.vehiclepart,'tag catalogue incomplete')
assert(byId.perishable.families.food,'property family missing')
picker:addCondition(2,'tool');picker:catalogEntries()
assert(projections==before+#scripts,'second chooser opening rebuilt immutable script projections')
picker:changeCondition(1,1)
local chooser=assert(picker.tagChoice)
assert(picker.dimmer.visible and chooser.added)
chooser.search.value='perish';chooser:prerender()
assert(#chooser.list.items==1 and chooser.list.items[1].item.id=='perishable','chooser search failed')
chooser:choose(chooser.list.items[1].item)
assert(not picker.tagChoice and not picker.dimmer.visible and picker.conditions[1][1].id=='perishable')
local oldDraws,oldMeasurements=draws,measurements
Picker.drawRow(picker.list,10000,picker.list.items[2])
cache['PZSurvivorToolkit/TagRuleTagPicker'].drawRow(chooser.list,10000,chooser.list.items[1])
assert(draws==oldDraws and measurements==oldMeasurements,'offscreen rows still measure or draw')
picker:chooseTag(function() error('cancel selected a tag') end)
chooser=picker.tagChoice;chooser.search.focused=true;chooser.group.expanded=true
chooser.group.popup={parentCombo=chooser.group,visible=true}
picker:close()
assert(not chooser.added and not chooser.search.focused and not chooser.group.popup.visible,'owner close leaked chooser focus/popup')
picker=open({scriptItems=scripts});picker:catalogEntries();assert(projections==before+2*#scripts,'reopen reused a stale script projection');picker:close()
local item={category='Tool',getDisplayCategory=function(self) return self.category end}
picker=open({items={item}});entries=picker:catalogEntries();assert(entries[1])
item.category='medicalTreatment';entries=picker:catalogEntries()
byId={};for _,entry in ipairs(entries)do byId[entry.id]=true end
assert(byId.medical and not byId.tool,'chooser reused stale live instance categories');picker:close()
picker=open({scriptItems={},rule=original});entries=picker:catalogEntries()
assert(#entries==2,'saved missing tags cannot be edited');picker:close()

local restoredFocus
JoypadState={players={{focus=owner}}}
setJoypadFocus=function(player,focus)
    restoredFocus=focus;JoypadState.players[player+1].focus=focus
    if focus and focus.onGainJoypadFocus then focus:onGainJoypadFocus(JoypadState.players[player+1]) end
end
updateJoypadFocus=function(data) if data.focus.onGainJoypadFocus then data.focus:onGainJoypadFocus(data) end end
picker=open({player=0,rule=original,categories={'foodPerishable','mechanicsVehiclePart'}})
assert(restoredFocus==picker and #picker.focusRows==3,'controller cannot reach main controls')
local data=JoypadState.players[1]
for i=1,10 do picker:addCondition(1,'category:extra'..i,false) end
picker.list.onJoypadDownInParent(picker.list,Joypad.AButton,data)
picker.list.selected=3;picker.list.scroll=-10
picker.list.onJoypadDown(picker.list,Joypad.XButton,data)
assert(not picker.conditions[1][2].excluded and picker.list.selected==3 and picker.list.scroll==-10,'toggle lost condition focus/scroll')
picker.list.onJoypadDown(picker.list,Joypad.XButton,data)
assert(picker.conditions[1][2].excluded,'consecutive controller toggles changed different rows')
picker.list.onJoypadDown(picker.list,Joypad.AButton,data)
assert(picker.tagChoice and restoredFocus==picker.tagChoice,'controller could not open tag choice')
chooser=picker.tagChoice;chooser:close();assert(restoredFocus==picker,'chooser did not restore parent focus')
picker.list.selected=3;picker.list.onJoypadDown(picker.list,Joypad.YButton,data)
assert(#picker.conditions[1]==11,'controller remove failed')
picker.list.onJoypadDown(picker.list,Joypad.BButton,data)
picker:onJoypadDown(Joypad.BButton,data)
assert(not picker.added and restoredFocus==owner,'main editor did not restore owner focus')

picker=open({rule=original});picker.list.mouseX=50;picker:clickRow(picker.list.items[3].item)
assert(not picker.conditions[1][2].excluded,'polarity hit target failed')
picker.list.mouseX=picker.list.width-40;picker:clickRow(picker.list.items[3].item)
assert(#picker.conditions[1]==1,'remove hit target failed')
for i=2,64 do assert(picker:addGroup('category:group'..i)) end
assert(not picker:addGroup('food') and #picker.conditions==64 and picker.validationMessage,'group bound failed')
picker:close()
local second=open();local third=open();assert(not second.added and owner.toolkitRulePicker==third,'reopen leaked editor')
owner.removed=true;third:apply();assert(not third.added,'removed owner accepted Apply');owner.removed=nil
picker=open();enabled=false;picker:prerender();assert(not picker.added and not open(),'disabled tags kept an editor alive')
print('Tag rule editor checks passed: grouped drafts, legacy rules, selected rows, lazy catalogues, clipping, chooser lifetime, mouse/controller and limits.')
