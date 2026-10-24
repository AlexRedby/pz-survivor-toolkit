require "ISUI/ISComboBox"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Custom = require "PZSurvivorToolkit/TagCustomization"
local Client = require "PZSurvivorToolkit/TagCustomizationClient"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Catalog = require "PZSurvivorToolkit/TagEditor"
local Editor = ISCollapsableWindowJoypad:derive("PZSTItemTagEditor")
local function text(key) return getText("UI_PZST_TagEdit_" .. key) end
local function contains(values,id)
    for _, value in ipairs(values) do if value == id then return true end end
    return false
end
local function merge(original,changes,reset)
    local out = {}
    if not reset then for id,value in pairs(original or {}) do out[id]=value end end
    for id,value in pairs(changes or {}) do out[id]=value ~= "default" and value or nil end
    return out
end
local function apply(base,delta)
    local out = {}
    for _,id in ipairs(base) do if delta[id] ~= "remove" then out[#out+1]=id end end
    for id,value in pairs(delta) do if value == "add" and not contains(out,id) then out[#out+1]=id end end
    return out
end

-- Native stacks carry a leading representative; CleanUI can explicitly omit it.
function Editor.itemsIn(rows)
    local items,seen = {},{}
    local function add(item)
        if instanceof(item,"InventoryItem") and not seen[item] then items[#items+1],seen[item]=item,true end
    end
    for _,row in ipairs(rows or {}) do
        if instanceof(row,"InventoryItem") then add(row)
        elseif row.type ~= "separator" then
            local first = row.cleanUILargeStackOptimized and 1 or row.cleanUIFirstActualIndex or 2
            for index=first,#(row.items or {}) do add(row.items[index]) end
        end
    end
    return items
end

function Editor:close() Catalog.finish(self) end
function Editor:scope() return self.scopeCombo:getOptionData(self.scopeCombo.selected) end
function Editor:draft() return self.drafts[self:scope()] end

function Editor:targets()
    if self:scope() == "item" then return self.items end
    local out,seen={},{}
    for _,item in ipairs(self.items) do
        local fullType=item:getFullType()
        if not seen[fullType] then out[#out+1],seen[fullType]=item,true end
    end
    return out
end

function Editor:state(id)
    local draft = self:draft()
    if draft.changes[id] then return draft.changes[id] end
    if draft.reset then return "default" end
    local state
    for _,item in ipairs(self:targets()) do
        local delta = self:scope() == "type" and Custom.typeDelta(item:getFullType()) or Custom.itemDelta(item)
        local value=(delta or {})[id] or "default"
        if state and state ~= value then return "mixed" end
        state=value
    end
    return state or "default"
end

function Editor:effective(item)
    local draft = self:draft()
    local typeDelta,itemDelta=Custom.typeDelta(item:getFullType()) or {},Custom.itemDelta(item) or {}
    if self:scope() == "type" then typeDelta=merge(typeDelta,draft.changes,draft.reset)
    else itemDelta=merge(itemDelta,draft.changes,draft.reset) end
    return apply(apply(Tags.automaticForItem(item),typeDelta),itemDelta)
end

function Editor:presence(id)
    local present=self.presentCounts[id] or 0
    return present == #self.items and "Present" or present == 0 and "Absent" or "Mixed"
end

function Editor:cycle(row,reverse)
    if self.pending or not row or not row.id then return end
    local state=self:state(row.id)
    local nextState
    if reverse then nextState=state == "default" and "remove" or state == "remove" and "add" or "default"
    else nextState=state == "add" and "remove" or state == "remove" and "default" or "add" end
    self:draft().changes[row.id]=nextState
    self.status=nil; self:refreshPreview()
end

function Editor:resetAssignments()
    if self.pending then return end
    self:draft().reset,self:draft().changes=true,{}
    self.status=nil; self:refreshPreview()
end

function Editor:reload()
    if self.pending then return end
    self.drafts={item={changes={}},type={changes={}}}
    self.baseRevision=Custom.getRevision()
    self.status=nil; self:reloadList(); self:refreshPreview()
end

function Editor:changeScope()
    if self.pending then self.scopeCombo.selected=self.lastScope; return end
    self.lastScope=self.scopeCombo.selected
    self.status=nil; self:refreshPreview()
end

function Editor:reloadList()
    local query=(self.search:getInternalText() or ""):lower()
    self.list:clear()
    local entries={}
    for _,id in ipairs(Tags.allIds(self.items)) do entries[#entries+1]={id=id,label=Tags.label(id)} end
    table.sort(entries,function(a,b) return a.label < b.label end)
    for _,row in ipairs(entries) do
        if row.label:lower():find(query,1,true) then self.list:addItem(row.label,row) end
    end
    self.lastQuery=query
end

function Editor:refreshPreview()
    self.preview:clear()
    self.presentCounts={}
    for _,item in ipairs(self.items) do
        local names={}
        for _,id in ipairs(self:effective(item)) do
            if Custom.isActive(id) then
                names[#names+1]=Tags.label(id)
                self.presentCounts[id]=(self.presentCounts[id] or 0)+1
            end
        end
        table.sort(names)
        local label=item:getName() .. ": " .. table.concat(names,", ")
        self.preview:addItem(label,label,label)
    end
end

function Editor:openCatalog()
    if not self.pending and not self.toolkitTagClosed then return Catalog.open({playerNum=self.playerNum,owner=self,items=self.items}) end
end

function Editor:save()
    if self.toolkitTagClosed or self.pending then return end
    local draft=self:draft()
    if not draft.reset and not Custom.hasEntries(draft.changes) then self.status=text("NoChanges"); return end
    self.pending,self.status=true,text("Saving"); self.saveButton:setEnable(false)
    local completed=false
    local function result(status,payload)
        completed=true
        if self.toolkitTagClosed then return end
        self.pending=false; self.saveButton:setEnable(true)
        if status == "accepted" then self:close()
        else self.status=text(status == "conflict" and "Conflict" or "Rejected") end
    end
    local request,reason=Client.assign(self.playerNum,self.items,self:scope(),draft.changes,draft.reset == true,
        result,self.baseRevision)
    if not request and not completed then result("rejected",{reason=reason}) end
end

function Editor:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local w,h=self.width,self.height
    self.scopeCombo=ISComboBox:new(12,34,w-24,26,self,Editor.changeScope)
    self.scopeCombo:initialise(); self.scopeCombo:instantiate()
    self.scopeCombo:addOptionWithData(text("ScopeItem"),"item")
    self.scopeCombo:addOptionWithData(text("ScopeType"),"type")
    self.scopeCombo.selected,self.lastScope=1,1; self:addChild(self.scopeCombo)
    self.search=ISTextEntryBox:new("",12,94,w-154,26)
    self.search:initialise(); self.search:instantiate(); self.search:setTooltip(text("Search")); self:addChild(self.search)
    self.catalogButton=Catalog.button(self,w-142,94,130,text("Catalog"),Editor.openCatalog)
    local previewHeight=math.max(60,math.floor((h-270)*0.28))
    local previewTop=h-100-previewHeight
    self.list=ISScrollingListBox:new(12,128,w-24,previewTop-156)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=getTextManager():getFontHeight(UIFont.Small)+12
    self.list.font,self.list.joypadParent=UIFont.Small,self
    Catalog.configureList(self,self.list,Editor.cycle)
    self.list:setOnMouseDownFunction(self,Editor.cycle)
    self.list.onRightMouseUp=function(list)
        local row=list.items[list.mouseoverselected]; if row then self:cycle(row.item,true) end
    end
    self.list.doDrawItem=function(list,y,row)
        if y+list:getYScroll()+row.height < 0 or y+list:getYScroll() >= list.height then return y+row.height end
        local style=Visuals.get(row.item.id)
        local state=self:state(row.item.id)
        local choices={default="Automatic",add="Add",remove="Remove",mixed="Mixed"}
        if self:draft().changes[row.item.id] then list:drawRect(0,y,list.width,row.height,0.2,0.3,0.5,0.7) end
        if style.texture then list:drawTextureScaledAspect(style.texture,6,y+4,20,20,1,style.r,style.g,style.b) end
        local label=text(choices[state]) .. " / " .. text(self:presence(row.item.id)) .. ": " .. row.text
        list:drawText(UIStyle.fit(label,list.width-56),32,y+5,1,1,1,1,UIFont.Small)
        return y+row.height
    end
    self:addChild(self.list)
    self.preview=ISScrollingListBox:new(12,previewTop,w-24,previewHeight)
    self.preview:initialise(); self.preview:instantiate(); self.preview.itemheight=getTextManager():getFontHeight(UIFont.Small)+10
    self.preview.font,self.preview.joypadParent=UIFont.Small,self
    Catalog.configureList(self,self.preview)
    self.preview.doDrawItem=function(list,y,row)
        list:drawText(UIStyle.fit(row.text,list.width-28),8,y+5,0.9,0.9,0.9,1,UIFont.Small)
        return y+row.height
    end
    self:addChild(self.preview)
    self.resetButton=Catalog.button(self,12,h-70,160,text("ResetAssignments"),Editor.resetAssignments)
    self.reloadButton=Catalog.button(self,178,h-70,110,text("Reload"),Editor.reload)
    self.cancelButton=Catalog.button(self,w-224,h-38,100,getText("UI_Cancel"),Editor.close)
    self.saveButton=Catalog.button(self,w-112,h-38,100,text("Save"),Editor.save)
    self:reloadList(); self:refreshPreview()
end

function Editor:prerender()
    if Catalog.ownerClosed(self) then self:close(); return end
    if self.reassertTop then self.reassertTop=false; self:bringToTop() end
    if (self.search:getInternalText() or ""):lower() ~= self.lastQuery then self:reloadList() end
    if self.lastRevision ~= Tags.revision() then
        self.lastRevision=Tags.revision(); self:reloadList(); self:refreshPreview()
    end
    ISCollapsableWindowJoypad.prerender(self)
    self:drawText(UIStyle.fit(text(self:scope() == "item" and "ScopeHintItem" or "ScopeHintType"),self.width-24),12,68,
        0.9,0.8,0.6,1,UIFont.Small)
    self:drawText(text("Preview"),12,self.preview.y-23,0.9,0.9,0.9,1,UIFont.Small)
    self:drawText(UIStyle.fit(self.status or text("AssignmentHint"),self.width-24),12,self.height-96,0.9,0.8,0.6,1,UIFont.Small)
    self:drawText(UIStyle.fit(text("Shared"),self.width-248),12,self.height-32,0.8,0.8,0.8,1,UIFont.Small)
end

function Editor:onGainJoypadFocus(data)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self,data)
    if self.joypadConfigured then return end
    self.joypadConfigured=true
    self:insertNewLineOfButtons(self.scopeCombo)
    self:insertNewLineOfButtons(self.search,self.catalogButton)
    self:insertNewLineOfButtons(self.list)
    self:insertNewLineOfButtons(self.preview)
    self:insertNewLineOfButtons(self.resetButton,self.reloadButton)
    self:insertNewLineOfButtons(self.cancelButton,self.saveButton)
    self.joypadIndexY,self.joypadIndex=1,1; self:restoreJoypadFocus(data)
end

function Editor:onJoypadDown(key,data)
    if key == Joypad.BButton and not self.scopeCombo.expanded then self:close(); return end
    ISCollapsableWindowJoypad.onJoypadDown(self,key,data)
end

function Editor.open(options)
    options=options or {}
    local items=Editor.itemsIn(options.items or options.rows)
    if #items == 0 then return nil,text("NoItems") end
    local w,h=math.min(760,getCore():getScreenWidth()-24),math.min(720,getCore():getScreenHeight()-24)
    local window=Editor:new((getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-h)/2,w,h)
    window.items,window.title=items,text("Assign")
    window.drafts={item={changes={}},type={changes={}}}
    window.baseRevision,window.lastRevision=Custom.getRevision(),Tags.revision()
    return Catalog.attach(window,options,"toolkitItemTagEditor")
end

function Editor.fillMenu(playerNum,context,rows)
    if not Tags.enabled() then return end
    local items=Editor.itemsIn(rows)
    if #items == 0 then return end
    local option=context:addOption(text("Assign"),{playerNum=playerNum,items=items},Editor.open)
    option.pzstCategory,option.pzstKey="transfer","editItemTags"
    local catalog=context:addOption(text("Catalog"),{playerNum=playerNum,items=items},Catalog.open)
    catalog.pzstCategory,catalog.pzstKey="transfer","manageTags"
end

Events.OnFillInventoryObjectContextMenu.Add(Editor.fillMenu)
return Editor
