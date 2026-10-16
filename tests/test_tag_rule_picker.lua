local applied, enabled = nil, true
PZSurvivorToolkit = {Settings={itemTags=function() return enabled end}}
getText=function(key) return key end
getTextOrNull=function() end
UIFont={Small=1}
Joypad={AButton=1,BButton=2}
getTextManager=function() return {getFontHeight=function() return 16 end,MeasureStringX=function(_,_,value) return #value*8 end} end
local screenWidth=800
getCore=function() return {getScreenWidth=function() return screenWidth end,getScreenHeight=function() return 600 end} end
local Base={}
function Base:new(x,y,width,height)
    return setmetatable({x=x,y=y,width=width,height=height,items={},visible=true}, {__index=self})
end
function Base:derive() local result={};setmetatable(result,{__index=self});return result end
function Base:initialise() end
function Base:instantiate() if self.createChildren then self:createChildren() end end
function Base:createChildren() end
function Base:prerender() end
function Base:addChild() end
function Base:addToUIManager() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:setVisible(value) self.visible=value end
function Base:getIsVisible() return self.visible end
function Base:setTooltip(value) self.tooltip=value end
function Base:setTitle(value) self.title=value end
function Base:drawText() end
function Base:clear() self.items={} end
function Base:addItem(label,item) self.items[#self.items+1]={text=label,item=item,height=self.itemheight,index=#self.items+1} end
function Base:setOnMouseDownFunction(target,callback) self.target,self.onmousedown=target,callback end
function Base:addOptionWithData(label,data) self.options=self.options or {};self.options[#self.options+1]={label=label,data=data};self.selected=self.selected or 1 end
function Base:getOptionData(index) return self.options[index].data end
ISCollapsableWindowJoypad,ISScrollingListBox,ISComboBox=Base,Base:derive(),Base:derive()
ISButton=Base:derive()
function ISButton:new(x,y,w,h,title,target,callback) local b=Base.new(self,x,y,w,h);b.title,b.target,b.callback=title,target,callback;return b end
ISTextEntryBox=Base:derive()
function ISTextEntryBox:new(value,x,y,w,h) local entry=Base.new(self,x,y,w,h);entry.value=value;return entry end
function ISTextEntryBox:getText() return self.value end
local cache={}
require=function(name)
    if name:sub(1,5)=='ISUI/' then return end
    if name=='PZSurvivorToolkit/TagVisuals' then return {get=function() return {} end} end
    if name=='PZSurvivorToolkit/UIStyle' then return {button=function() end} end
    if cache[name] then return cache[name] end
    cache[name]=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..name..'.lua')
    return cache[name]
end
local Picker=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TagRulePicker.lua')
local original={mode='all',include={'food'},exclude={}}
local owner={getIsVisible=function() return true end,dimmer=Base:new(0,0,1,1)}
owner.dimmer.visible=false
local picker=Picker.open({player=0,owner=owner,rule=original,categories={'foodPerishable_ingredient','foodNonPerishable_ingredient','Tool','ModCat'},onApply=function(rule) applied=rule end})
assert(picker and picker.added and owner.toolkitRulePicker==picker and owner.dimmer.visible)
assert(picker.matchCount==2 and picker.rule~=original and picker.rule.include~=original.include,'draft aliases saved rule')
local rows={}
for _,row in ipairs(picker.entries) do rows[row.id]=row end
assert(rows.food.bucket==1 and rows.ingredient.bucket==2 and rows['category:ModCat'].bucket==3,'tags not grouped')
picker:cycle(rows.ingredient)
assert(picker:state('ingredient')=='Include' and picker.matchCount==2)
picker:cycle(rows.ingredient)
assert(picker:state('ingredient')=='Exclude' and picker.matchCount==0,'excluded tag still matches')
picker:cycle(rows.ingredient)
assert(picker:state('ingredient')=='Neutral' and picker.matchCount==2)
picker:cycle(rows.ingredient,true)
assert(picker:state('ingredient')=='Exclude','reverse cycle failed')
picker:clearRule()
assert(picker.matchCount==4 and #picker.rule.include==0 and #picker.rule.exclude==0,'clear did not reset draft')
picker:cycle(rows.tool);picker:cycle(rows.food);picker:toggleMode()
assert(picker.rule.mode=='any' and picker.matchCount==3,'all/any toggle failed')
assert(#original.include==1 and original.include[1]=='food' and #original.exclude==0,'draft changed original before apply')
picker.search.value='ingredient';picker:prerender()
assert(#picker.list.items==2 and picker.list.items[2].item.id=='ingredient','tag search failed')
picker:apply()
assert(applied.mode=='any' and #applied.include==2 and not picker.added and not owner.toolkitRulePicker and not owner.dimmer.visible,'apply or owner cleanup failed')
local item={getDisplayCategory=function() return 'Tool' end,getCategory=function() return 'Tool' end,getName=function() return 'Hammer' end}
picker=Picker.open({rule={mode='all',include={'tool'},exclude={}},categories={'Tool'},items={item,item},onApply=function() error('cancel applied changes') end})
assert(picker.matchCount==2 and picker.preview.items[1].text=='Hammer','actual item preview missing')
picker:clearRule();picker:close()
assert(applied.mode=='any','cancel altered previously applied rule')
picker=Picker.open({categories={'Tool'},rule={mode='all',include={'food'},exclude={}},onApply=function() end})
assert(picker.matchCount==0 and picker.preview.items[1].item==false,'empty preview missing')
local saved
for _,entry in ipairs(picker.entries) do if entry.id=='food' then saved=entry end end
assert(saved,'orphaned saved tag cannot be removed')
local second=Picker.open({owner=owner,categories={'Tool'},onApply=function() end})
local third=Picker.open({owner=owner,categories={'Tool'},onApply=function() end})
assert(not second.added and owner.toolkitRulePicker==third,'reopening leaked picker')
owner.getIsVisible=function() return false end;third:prerender()
assert(not third.added,'picker outlived parent')
screenWidth=580
picker=Picker.open({categories={'Tool'},onApply=function() end})
assert(picker.width==556 and picker.preview.y>picker.list.y+picker.list.height and picker.preview.height>=40,'small-screen lists overlap')
enabled=false;picker:prerender()
assert(not picker.added,'disabled tags left picker open')
assert(not Picker.open({categories={'Tool'},onApply=function() end}),'disabled tags opened picker')
print('Tag rule picker checks passed: drafts, tri-state, grouping, search, preview, apply/cancel and lifetime.')
enabled=true
local restoredFocus
function Base:onGainJoypadFocus() end
function Base:insertNewLineOfButtons(...) self.focusRows=self.focusRows or {};self.focusRows[#self.focusRows+1]={...} end
function Base:restoreJoypadFocus() end
function Base:prevVisibleIndex(index) return index>1 and index-1 or -1 end
function Base:nextVisibleIndex(index) return index<#self.items and index+1 or -1 end
function Base:ensureVisible() end
JoypadState={players={{focus=owner}}}
owner.getIsVisible=function() return true end
setJoypadFocus=function(player,focus)
    restoredFocus=focus;JoypadState.players[player+1].focus=focus
    if focus and focus.onGainJoypadFocus then focus:onGainJoypadFocus(JoypadState.players[player+1]) end
end
updateJoypadFocus=function(data) if data.focus.onGainJoypadFocus then data.focus:onGainJoypadFocus(data) end end
picker=Picker.open({player={getPlayerNum=function() return 0 end},owner=owner,categories={'Tool','Food'},onApply=function() end})
assert(restoredFocus==picker and #picker.focusRows==6,'controller cannot reach picker controls')
local data=JoypadState.players[1]
picker.list.onJoypadDownInParent(picker.list,Joypad.AButton,data)
assert(data.focus==picker.list,'controller cannot enter tag list')
picker.list.count=#picker.list.items
picker.list.onJoypadDirDown(picker.list)
assert(#picker.rule.include==0 and #picker.rule.exclude==0,'controller navigation changed selection')
picker.list.onJoypadDown(picker.list,Joypad.AButton,data)
assert(#picker.rule.include==1,'controller cannot cycle tag')
picker.list.onJoypadDown(picker.list,Joypad.BButton,data)
assert(data.focus==picker,'controller cannot leave tag list')
picker:onJoypadDown(Joypad.BButton,data)
assert(restoredFocus==owner and not picker.added,'controller focus did not return to owner')
print('Tag rule picker controller checks passed.')
picker=Picker.open({categories={'Tool','Food'},onApply=function() error('removed owner applied') end,owner=owner})
picker.rule.include={}
for id in pairs(cache['PZSurvivorToolkit/ItemTagSchema'].labels) do
    if id~='tool' and #picker.rule.include<64 then picker.rule.include[#picker.rule.include+1]=id end
end
picker:cycle({id='tool'})
assert(#picker.rule.include==64 and picker:state('tool')=='Neutral' and picker.validationMessage,'tag list limit silently broke Apply')
owner.removed=true;picker:apply()
assert(not picker.added,'removed parent accepted child Apply')
print('Tag rule picker limit and removed-owner checks passed.')
