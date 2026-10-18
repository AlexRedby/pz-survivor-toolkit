local module = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryTags.lua'
local enabled, starts, toggles = true, {}, {}
local tags = {'Food', 'Cooking', 'Perishable'}
local labels = {Food='Food', Cooking='Cooking', Perishable='Perishable'}
PZSurvivorToolkit = {}
local Tags = {enabled=function() return enabled end, forItem=function(item) return item.tags end,
    label=function(id) return labels[id] end}
local foodIcon, clockIcon = {}, {}
local styles = {Food={r=0.4,g=0.8,b=0.3,texture=foodIcon}, Cooking={r=0.5,g=0.4,b=0.2},
    Perishable={r=0.4,g=0.8,b=0.3,texture=clockIcon}}
local neutral = {r=0.5,g=0.5,b=0.5}
require = function(name)
    if name == "PZSurvivorToolkit/InventoryClasses" then
        return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua")
    end
    if name == 'PZSurvivorToolkit/ItemTags' then return Tags end
    if name == 'PZSurvivorToolkit/TagVisuals' then return {get=function(id) return styles[id] or neutral end} end
end
Events = {OnGameStart={Add=function(callback) starts[#starts+1]=callback end}}
CleanUI_RegisterInventoryUiToggleCallback = function(callback) toggles[#toggles+1]=callback end
getText = function(key)
    return ({IGUI_ItemCat_foodCookingPerishable='Food; Cooking; Perishable',
        IGUI_invpanel_Category='Category',UI_PZSurvivorToolkit_item_tags_header='Tags'})[key] or key
end
getTextManager = function() return {MeasureStringX=function(_, _, text) return #text*6 end} end
local contextVisible = false
getPlayerContextMenu = function() return {isAnyVisible=function() return contextVisible end} end
ISToolTip = {new=function()
    return {initialise=function() end, setDescription=function(self,value) self.description=value end,
        setVisible=function(self,value) self.visible=value end, addToUIManager=function(self) self.added=true end,
        removeFromUIManager=function(self) self.added=false end, bringToTop=function() end}
end}

-- Keep the game's category draw statements so the adapter is tested against
-- both native and CleanUI alignment/caching calls, including real sources when available.
local nativeSource = NativeInventoryPaneSource or [[
                        elseif item:getDisplayCategory() then -- display the custom category set in items.txt
                            self:drawText(getText("IGUI_ItemCat_" .. item:getDisplayCategory()), self.column3+8+xoff, (y*self.itemHgt)+self.headerHgt+textDY+yoff, 0.6, 0.6, 0.8, 1.0, self.font);
                        else
                            self:drawText(getText("IGUI_ItemCat_" .. item:getCategory()), self.column3+8+xoff, (y*self.itemHgt)+self.headerHgt+textDY+yoff, 0.6, 0.6, 0.8, 1.0, self.font);
                        end
]]
local nativeBlock = assert(nativeSource:match('elseif item:getDisplayCategory%(%) then(.-)\n%s*end'))
local nativeCategory = assert(loadstring('return function(self,item,y) local xoff,yoff=0,0; local textDY=(self.itemHgt-self.fontHgt)/2; if item:getDisplayCategory() then '..nativeBlock..' end end'))()
local cleanSource = CleanUIInventoryPaneSource or [[
                                local categoryKey = item:getDisplayCategory() or item:getCategory()
                                local categoryText = CleanUI_getCachedCategoryText(categoryKey)
                                local truncatedCategory = CleanUI_getCachedTruncatedText(v, "_cleanUICategoryTextCache", categoryText, maxCategoryWidth, self.font)
                                if categoryAlign == "1" then
                                    local leftBoundary = self.column3 + self.padding + xoff
                                    self:drawText(truncatedCategory, leftBoundary, categoryTextY, categoryColor.r, categoryColor.g, categoryColor.b, categoryColor.a, self.font)
                                else
                                    self:drawTextRight(truncatedCategory, categoryRightBoundary + xoff, categoryTextY, categoryColor.r, categoryColor.g, categoryColor.b, categoryColor.a, self.font)
                                end
]]
CleanUI_getCachedCategoryText = function(key) return getText('IGUI_ItemCat_'..key) end
CleanUI_getCachedTruncatedText = function(group, field, text, width)
    local value = text:sub(1,math.max(0,math.floor(width/6)))
    group[field] = {value=value}
    return value
end
local cleanBlock = assert(cleanSource:match('(local categoryKey = item:getDisplayCategory%(%) or item:getCategory%(%).-)\n%s*end'))
local cleanCategory = assert(loadstring('return function(self,item,y) local v=self.items[y+1]; local xoff=0; local categoryAlign=self.align; local maxCategoryWidth=self.categoryRight-self.column3-self.padding; local categoryRightBoundary=self.categoryRight; local categoryTextY=y*self.itemHgt+self.headerHgt+(self.itemHgt-self.fontHgt)/2; local categoryColor={r=1,g=1,b=1,a=1}; '..cleanBlock..' end end'))()

local function item(key, itemTags)
    return {key=key, tags=itemTags, job=0, getDisplayCategory=function(self) return self.key end,
        getCategory=function() return 'Food' end, getJobDelta=function(self) return self.job end}
end
local itemA = item('foodCookingPerishable', tags)
local itemB = item('ThirdPartyExactKey', {})
local function class(clean)
    local c = {}
    function c:drawText(text,x,y,r,g,b,a,font)
        self.draws[#self.draws+1] = {text=text,x=x,y=y,font=font,right=false}
    end
    function c:drawTextRight(text,x,y,r,g,b,a,font)
        self.draws[#self.draws+1] = {text=text,x=x,y=y,font=font,right=true}
    end
    function c:drawRect(x,y,width,height,a,r,g,b)
        assert(width >= 0 and height >= 0, 'negative chip geometry')
        assert(x >= self.column3 and x+width <= self.categoryRight, 'chip escaped category column')
        self.rects[#self.rects+1] = {x=x,y=y,width=width,height=height,r=r,g=g,b=b}
    end
    function c:drawTextureScaledAspect(texture,x,y,width,height)
        assert(x >= self.column3 and x+width <= self.categoryRight, 'icon escaped category column')
        assert(width > 0 and height > 0 and width == height, 'invalid icon size')
        self.icons[#self.icons+1]={texture=texture,width=width}
    end
    function c:renderdetails(dragged, token)
        self.nativeCalls = self.nativeCalls + 1
        if self.fail then error('native failure') end
        if dragged then self:drawText('dragged',12,12); return token end
        -- Native fills self.items before drawing the group category. The item
        -- name deliberately equals the category label, outside its column.
        self.items = {}
        for index,group in ipairs(self.itemslist) do
            self.items[index] = group
            local value, y = group.items[1], index-1
            local textY = y*self.itemHgt+self.headerHgt+(self.itemHgt-self.fontHgt)/2
            self:drawText(getText('IGUI_ItemCat_'..(value.key or 'Food')), self.column2+8, textY)
            if value.job > 0 then
                self:drawText('Working',self.column3+(clean and self.padding or 8),textY)
            elseif not self._cleanUICategoryCollapsed then
                (clean and cleanCategory or nativeCategory)(self,value,y)
            end
            if clean then
                self:drawTextRight('Rarity',self.categoryRight+45,textY)
                self:drawTextRight('1.25',self.width-8,textY)
            end
        end
        if self.expanded then
            self.items[#self.items+1] = itemA
            self:drawText('condition',self.column3+8,self.headerHgt+2*self.itemHgt+(self.itemHgt-self.fontHgt)/2)
        end
        return token
    end
    function c:updateTooltip() self.nativeTooltips=self.nativeTooltips+1; return 'native tooltip' end
    return c
end
ISInventoryPane, CleanUI_Clean_ISInventoryPane, CleanUI_Vanilla_ISInventoryPane = class(false), class(true), class(false)
local native, enhanced, vanilla = ISInventoryPane, CleanUI_Clean_ISInventoryPane, CleanUI_Vanilla_ISInventoryPane
local adapter = dofile(module)
starts[1]()
assert(#toggles == 1)
local renderers = {native.renderdetails, enhanced.renderdetails, vanilla.renderdetails}
adapter.install(); toggles[1]()
assert(native.renderdetails == renderers[1] and enhanced.renderdetails == renderers[2] and vanilla.renderdetails == renderers[3], 'double installation')
local function pane(c, clean)
    local groups = {{items={itemA},cat=itemA.key,rawcategory=itemA.key},{items={itemB},cat=itemB.key,rawcategory=itemB.key}}
    return setmetatable({mode='details',itemslist=groups,items={},column2=30,column3=160,width=430,
        categoryRight=clean and 330 or 422,cleanUIItemIconSize=clean and 32 or nil,padding=5,
        _cleanUIRarityMetricsCache=clean and {value={categoryRight=330}} or nil,
        itemHgt=24,fontHgt=12,headerHgt=20,font='Small',draws={},rects={},icons={},align='2',nativeCalls=0,nativeTooltips=0,
        typeHeader={title='Category',setTitle=function(self,title) self.title=title end},
        isVScrollBarVisible=function() return false end,player=0,isReallyVisible=function(self) return not self.hidden end,
        isMouseOver=function(self) return not self.outside end,getMouseX=function(self) return self.mouseX or 170 end,
        getMouseY=function(self) return self.mouseY or 25 end,getYScroll=function(self) return self.scroll or 0 end}, {__index=c})
end
local function reset(p) p.draws,p.rects,p.icons={},{},{} end
local function has(p,text)
    for _,draw in ipairs(p.draws) do if draw.text == text then return true end end
    return false
end
for _,case in ipairs({{native,false},{enhanced,true},{vanilla,false}}) do
    local p = pane(case[1],case[2])
    local originalText,originalRight = p.drawText,p.drawTextRight
    assert(p:renderdetails(false,'render result') == 'render result')
    assert(p.drawText == originalText and p.drawTextRight == originalRight and rawget(p,'drawText') == nil, 'draw wrapper leaked')
    assert(has(p,'Food') and has(p,'Cooking'), 'missing tag chips')
    assert(#p.icons>0 and p.icons[1].texture==foodIcon, 'semantic icon missing')
    assert(p.rects[1].g>p.rects[1].r, 'food family color missing')
    assert(p.toolkitTagRows[1].drawnChips > 0, 'tag metadata reported no chip draws')
    assert(p.typeHeader.title == 'Tags', 'category header was not renamed')
    p.typeHeader.title='Category (A-Z)'; p:renderdetails(false)
    assert(p.typeHeader.title == 'Tags (A-Z)', 'sort suffix lost')
    p.typeHeader.title='Category'; p:renderdetails(false)
    assert(has(p,'Food; Cooking; Perishable'), 'matching item name disappeared')
    assert(has(p,'IGUI_ItemCat_ThirdPartyExactKey'), 'unknown category altered')
    for _,group in ipairs(p.itemslist) do
        assert(group.cat == group.items[1].key and group.rawcategory == group.items[1].key, 'category state changed')
    end
    assert(itemA:getDisplayCategory() == 'foodCookingPerishable', 'Java item category was replaced')
    p.expanded=true; reset(p); p:renderdetails(false)
    assert(has(p,'condition'), 'expanded item details changed'); p.expanded=nil
    itemA.job=0.5; reset(p); p:renderdetails(false)
    assert(has(p,'Working') and #p.rects == 0, 'job progress replaced with chips'); itemA.job=0
    if case[2] then
        assert(has(p,'Rarity') and has(p,'1.25'), 'other columns suppressed')
        p.align='1'; reset(p); p:renderdetails(false)
        assert(has(p,'Food'), 'left-aligned CleanUI missing')
        p._cleanUICategoryCollapsed=true; reset(p); p:renderdetails(false)
        assert(#p.rects == 0, 'collapsed category drew chips')
        p._cleanUICategoryCollapsed=nil
    end
    p.itemHgt,p.fontHgt=42,24
    reset(p); p:renderdetails(false)
    assert(#p.rects > 0 and p.icons[1].width==16, 'scaled row lost chips/icons')
    p.itemHgt,p.fontHgt=24,12
    if case[2] then p._cleanUIRarityMetricsCache.value.categoryRight=220 else p.width=228 end
    p.categoryRight=220
    reset(p); p:renderdetails(false)
    assert(has(p,'+2') or has(p,'+3'), 'no compact overflow')
    assert(not has(p,'Perishable'), 'long label escaped narrow column')
    assert(p:updateTooltip() == 'native tooltip' and p.nativeTooltips == 1, 'native tooltip replaced')
    assert(p.toolkitTagTooltip.visible and p.toolkitTagTooltip.description == 'Food <LINE> Cooking <LINE> Perishable')
    contextVisible=true; p:updateTooltip(); assert(not p.toolkitTagTooltip.visible); contextVisible=false
    p.outside=true; p:updateTooltip(); assert(not p.toolkitTagTooltip.added); p.outside=false
    p.scroll=-30; p.mouseY=25; p:updateTooltip(); assert(not p.toolkitTagTooltip.visible, 'tooltip over header after scroll'); p.scroll=0
    if case[2] then p._cleanUIRarityMetricsCache.value.categoryRight=170 else p.width=178 end
    p.categoryRight=170
    reset(p); p:renderdetails(false)
    assert(#p.rects == 0 and #p.icons==0, 'tiny column overflowed')
    assert(p.toolkitTagRows[1].drawnChips == 0, 'tiny-column metadata falsely reported chip draws')
    enabled=false; reset(p); p:renderdetails(false)
    assert(#p.rects == 0 and p.toolkitTagRows == nil and not p.toolkitTagTooltip.visible, 'live disable failed')
    assert(p.typeHeader.title == 'Category', 'disabled header not restored')
    enabled=true
    p.mode='icons'; reset(p); p:renderdetails(false); assert(#p.rects == 0, 'icon mode modified'); p.mode='details'
    reset(p); p:renderdetails(true); assert(has(p,'dragged') and #p.rects == 0, 'drag rendering modified')
    p.fail=true
    assert(not pcall(p.renderdetails,p,false))
    assert(p.drawText == originalText and p.drawTextRight == originalRight, 'error leaked draw wrappers')
end
-- A later class and repeated live CleanUI swaps get exactly one wrapper each.
ISInventoryPane=class(false)
toggles[1]()
local later=ISInventoryPane.renderdetails
ISInventoryPane=enhanced; toggles[1]()
assert(ISInventoryPane.renderdetails == renderers[2])
ISInventoryPane=vanilla; toggles[1]()
assert(ISInventoryPane.renderdetails == renderers[3])
ISInventoryPane=class(false); adapter.install()
assert(later ~= ISInventoryPane.renderdetails)
print('Inventory tag checks passed: native/CleanUI, exact categories, clipped chips, overflow tooltip, errors, live toggles.')
