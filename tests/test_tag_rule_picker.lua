isClient=function()return false end
ModData={getOrCreate=function()return {} end}
local applied, enabled, firstSelected = nil, true, nil
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
function Base:unfocus() self.focused=false end
function Base:hidePopup() self.popup.visible=false end
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
    if name=='PZSurvivorToolkit/UIStyle' then
        return dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua')
    end
    if cache[name] then return cache[name] end
    cache[name]=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..name..'.lua')
    return cache[name]
end
local Picker=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TagRulePicker.lua')
local original={mode='all',include={'food'},exclude={}}
local owner={getIsVisible=function() return true end,dimmer=Base:new(0,0,1,1)}
owner.dimmer.visible=false
local picker=Picker.open({player=0,owner=owner,rule=original,categories={'foodPerishable_ingredient','foodNonPerishable_ingredient','Tool','ModCat'},onApply=function(rule,first) applied=rule;firstSelected=first end})
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
assert(firstSelected=='tool' and applied.include[1]=='food','normalized rule sorted away actual click order')
picker=Picker.open({rule={include={'food'},exclude={}},selectedTag='food',categories={'Tool'},
    onApply=function(_,first) firstSelected=first end})
picker:cycle({id='tool'});picker:cycle({id='food'});picker:apply()
assert(firstSelected=='tool','removed initial tag still supplied the suggestion')
picker=Picker.open({rule=original,categories={'Tool'},onApply=function(_,first) firstSelected=first end})
picker:apply();assert(firstSelected==nil,'reapplying an old rule guessed selection order')
picker=Picker.open({owner=owner,categories={'Tool'},onApply=function() end})
picker.search.focused=true
picker.group.expanded=true
picker.group.popup={parentCombo=picker.group,visible=true}
picker:close()
assert(not picker.search.focused and not picker.group.popup.visible and not picker.group.expanded,
    'closed picker retained keyboard focus or an owned popup')
picker=Picker.open({owner=owner,categories={'Tool'},onApply=function() end})
picker.group.expanded=true
picker.group.popup={parentCombo={},visible=true}
picker:close()
assert(picker.group.popup.visible,'closing a picker hid another control\'s shared popup')
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

local function scriptItem(fullType, category, name, recipe)
    return {getFullName=function() return fullType end,getDisplayCategory=function() return category end,
        getDisplayName=function() return name end,getDoubleClickRecipe=function() return recipe end}
end
local function inventoryItem(script)
    return {category=script:getDisplayCategory(),getScriptItem=function() return script end,
        getFullType=function() return script:getFullName() end,getDisplayCategory=function(self) return self.category end,
        getName=function() return script:getDisplayName() end}
end
local function javaList(values)
    return {size=function() return #values end,get=function(_,index) return values[index+1] end}
end
farming_vegetableconf={props={Sunflower={seedName='Base.SunflowerSeeds'}}}
local sunflower=scriptItem('Base.SunflowerSeeds','foodNonPerishable_candySnack','Sunflower seeds')
local candy=scriptItem('Base.Candy','foodNonPerishable_candySnack','Candy')
local full=scriptItem('Base.CarrotBagSeed2','farmingSeed','Full seed packet','OpenPacketOfSeeds')
local empty=scriptItem('Base.CarrotBagSeed2_Empty','farmingSeed','Empty seed packet')
ScriptManager={instance={getCraftRecipe=function()
    return {getInputs=function() return javaList({{getPossibleInputItems=function() return javaList({full}) end}}) end,
        getOutputs=function() return javaList({{getPossibleResultItems=function() return javaList({empty}) end}}) end}
end}}
local seedRule={mode='all',include={'seed'},exclude={}}
local live=inventoryItem(sunflower)
picker=Picker.open({categories={'foodNonPerishable_candySnack'},items={live},rule=seedRule,onApply=function() end})
rows={}
for _,row in ipairs(picker.entries) do rows[row.id]=row end
assert(rows.seed and rows.seed.bucket==2 and rows.farming and rows.food,
    'inventory-only sunflower did not expose item-specific seed choice')
assert(rows.seed.families.food and rows.seed.families.farming,'dual-use item lost a family filter')
assert(picker.matchCount==1 and picker.preview.items[1].text=='Sunflower seeds','item-aware seed preview is empty')
picker:close()
picker=Picker.open({categories={'farmingSeed'},items={inventoryItem(candy)},onApply=function() end})
for _,row in ipairs(picker.entries) do assert(row.id~='seed','coarse category contaminated item choices') end
picker:close()
picker=Picker.open({items={live,inventoryItem(candy),inventoryItem(full),inventoryItem(empty)},rule=seedRule,onApply=function() end})
assert(picker.matchCount==2,'inventory preview counted candy or empty seed packet')
picker.rule={mode='all',include={'food','seed'},exclude={}};picker:refreshPreview()
assert(picker.matchCount==1 and picker.preview.items[1].text=='Sunflower seeds','all preview lost food/seed intersection')
picker.rule={mode='any',include={'food','seed'},exclude={'food'}};picker:refreshPreview()
assert(picker.matchCount==1 and picker.preview.items[1].text=='Full seed packet','any/exclude preview included food')
picker.rule={mode='all',include={'food','seed'},exclude={}}
live.category='medicalTreatment';picker:refreshPreview()
assert(picker.matchCount==0,'inventory preview reused stale instance category')
live.category='foodNonPerishable_candySnack';picker:close()
picker=Picker.open({categories={'Tool'},scriptItems={sunflower,candy,full,empty},rule=seedRule,onApply=function() end})
rows={}
for _,row in ipairs(picker.entries) do rows[row.id]=row end
assert(rows.seed and rows.food and rows.farming and not rows.tool,'script item choices used category fallback')
assert(picker.matchCount==2 and picker.preview.items[1].text=='Full seed packet'
    and picker.preview.items[2].text=='Sunflower seeds','script catalog seed preview counted candy/empty or used inventory names')
picker.rule={mode='all',include={'food','seed'},exclude={}};picker:refreshPreview()
assert(picker.matchCount==1 and picker.preview.items[1].text=='Sunflower seeds','script preview lost dual role')
picker:close()
picker=Picker.open({categories={'Tool'},scriptItems={},onApply=function() end})
assert(#picker.entries==0 and picker.matchCount==0,'empty script catalog fell back to coarse categories')
picker:close()
print('Item-aware tag picker checks passed: item/script choices, seed packets, dynamic preview and independent food/seed roles.')

-- A script retains its vanilla loot category while the provider supplies the
-- inventory category. Choices and preview must agree with the item in the bag.
local thread=scriptItem('Base.Thread','Material','Thread')
local stone=scriptItem('Base.LargeStone','Material','Stone')
OrganizedCategories={getScriptInventoryDisplayCategory=function(script)
    if script==thread then return 'craftingTailoring_material' end
end}
picker=Picker.open({scriptItems={thread,stone},rule={mode='all',include={'tailoring'},exclude={}},onApply=function() end})
rows={}
for _,row in ipairs(picker.entries) do rows[row.id]=row end
assert(rows.tailoring and picker.matchCount==1 and picker.preview.items[1].text=='Thread',
    'script rule picker omitted tailoring or previewed an unrelated material')
assert(thread:getDisplayCategory()=='Material','picker rewrote script loot category')
picker:close()
OrganizedCategories=nil
