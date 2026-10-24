require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
require "ISUI/ISPanel"
require "ISUI/ISColorPickerHSB"
require "ISUI/ISModalDialog"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Custom = require "PZSurvivorToolkit/TagCustomization"
local Client = require "PZSurvivorToolkit/TagCustomizationClient"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Editor = ISCollapsableWindowJoypad:derive("PZSTTagEditor")
local function text(key) return getText("UI_PZST_TagEdit_" .. key) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end

-- Shared lifecycle for the two tag windows and their nested native popups.
function Editor.button(owner, x, y, w, label, callback)
    local button = ISButton:new(x, y, w, 26, label, owner, callback)
    button:initialise(); button:instantiate(); UIStyle.button(button); owner:addChild(button)
    return button
end

function Editor.attach(window, options, ownerKey)
    window.playerNum = options.playerNum or options.player or 0
    if type(window.playerNum) ~= "number" then window.playerNum = window.playerNum:getPlayerNum() end
    window.owner, window.ownerKey = options.owner, ownerKey
    if window.owner and window.owner[ownerKey] then window.owner[ownerKey]:close() end
    window.background, window.backgroundColor = true, {r=0.04,g=0.04,b=0.04,a=1}
    window.resizable = false
    window:initialise(); window:instantiate(); window:addToUIManager()
    window.dimmer = ISPanel:new(0, 0, window.width, window.height)
    window.dimmer:initialise(); window.dimmer:instantiate()
    window.dimmer.backgroundColor = {r=0,g=0,b=0,a=0.5}
    window:addChild(window.dimmer); window.dimmer:setVisible(false)
    if window.owner then
        window.owner[ownerKey] = window
        local dimmer = window.owner.dimmer
        if dimmer then
            window.ownerDimmerVisible, window.ownerDimmerMouseDown = dimmer:getIsVisible(), dimmer.onMouseDown
            dimmer:setVisible(true)
            dimmer.onMouseDown = function() window.reassertTop = true; return true end
        end
    end
    local joypad = JoypadState and JoypadState.players[window.playerNum + 1]
    if joypad and setJoypadFocus then
        window.previousFocus, window.grabbedJoypad = joypad.focus, true
        setJoypadFocus(window.playerNum, window)
    end
    return window
end

function Editor.finish(window)
    if window.toolkitTagClosed then return end
    window.toolkitTagClosed = true
    for _, field in ipairs({"toolkitTagEditor", "toolkitItemTagEditor"}) do
        if window[field] then window[field]:close() end
    end
    for _, field in ipairs({"search", "nameEntry"}) do if window[field] then window[field]:unfocus() end end
    if window.scopeCombo and window.scopeCombo.expanded then
        local combo = window.scopeCombo
        if combo.popup and combo.popup.parentCombo == combo then combo:hidePopup() end
        combo.expanded = false
    end
    for _, field in ipairs({"list", "preview"}) do
        local list = window[field]
        if list and list.tooltipUI then list.tooltipUI:setVisible(false); list.tooltipUI:removeFromUIManager() end
    end
    if window.toolkitIconPicker then window.toolkitIconPicker:close() end
    if window.toolkitColorPicker then window.toolkitColorPicker:removeSelf() end
    if window.confirmation then window.confirmation:destroy(); window.confirmation = nil end
    window:setVisible(false); window:removeFromUIManager()
    local owner = window.owner
    if owner and owner[window.ownerKey] == window then
        owner[window.ownerKey] = nil
        if owner.dimmer then
            owner.dimmer:setVisible(window.ownerDimmerVisible)
            owner.dimmer.onMouseDown = window.ownerDimmerMouseDown
        end
    end
    if window.grabbedJoypad then setJoypadFocus(window.playerNum, window.previousFocus) end
    window.previousFocus, window.grabbedJoypad = nil, false
end

function Editor.ownerClosed(window)
    local owner=window.owner
    return owner and (owner.toolkitTagClosed or owner.removed
        or (owner.getIsVisible and not owner:getIsVisible()))
end

function Editor.configureList(window,list,onChoose)
    list.joypadParent=window
    list.setJoypadFocused=function(control,focused) control.joypadFocused=focused end
    list.onJoypadDownInParent=function(control,key,data)
        if key ~= Joypad.AButton then return false end
        data.focus=control; updateJoypadFocus(data)
        if (control.selected or 0) < 1 then control.selected=1 end
        return true
    end
    list.onJoypadDirUp=function(control)
        control.selected=control:prevVisibleIndex(control.selected)
        if control.selected <= 0 then control.selected=control:prevVisibleIndex(control.count+1) end
        control:ensureVisible(control.selected)
    end
    list.onJoypadDirDown=function(control)
        control.selected=control:nextVisibleIndex(control.selected)
        if control.selected == -1 then control.selected=control:nextVisibleIndex(0) end
        control:ensureVisible(control.selected)
    end
    list.onJoypadDown=function(control,key,data)
        if key == Joypad.AButton and onChoose then
            local row=control.items[control.selected]; if row then onChoose(window,row.item) end
        elseif key == Joypad.BButton then data.focus=window; updateJoypadFocus(data)
        else ISScrollingListBox.onJoypadDown(control,key,data) end
    end
end

function Editor.confirm(window, message, accept)
    if window.confirmation then return end
    local w, h = math.min(420, getCore():getScreenWidth() - 40), 170
    local modal = ISModalDialog:new((getCore():getScreenWidth()-w)/2, (getCore():getScreenHeight()-h)/2,
        w, h, message, true, window, function(_, button)
            window.confirmation = nil
            if not window.toolkitTagClosed then
                window.dimmer:setVisible(false)
                if window.grabbedJoypad then setJoypadFocus(window.playerNum, window) end
                if button.internal == "YES" then accept() end
            end
        end, window.playerNum)
    window.confirmation = modal
    modal:initialise(); modal:addToUIManager()
    window.dimmer:setVisible(true)
    window.dimmer.onMouseDown = function() modal:bringToTop(); return true end
    if window.grabbedJoypad then setJoypadFocus(window.playerNum, modal) end
    return modal
end

function Editor:close() Editor.finish(self) end
function Editor:isCustom(id)
    for _, custom in ipairs(Custom.customIds()) do if id == custom then return true end end
    return false
end

function Editor:stash()
    if self.draft then self.draft.name = self.nameEntry:getInternalText() or "" end
end

function Editor:select(row)
    if self.pending or not row then return end
    if self.toolkitColorPicker then self.toolkitColorPicker:removeSelf(); self.toolkitColorPicker=nil end
    if self.toolkitIconPicker then self.toolkitIconPicker:close() end
    self:stash()
    local key = row.id or "__new"
    local draft = self.drafts[key]
    if not draft then
        local id = row.id
        local definition = id and Custom.definition(id) or {}
        local visual = id and Visuals.get(id) or Visuals.defaults("custom")
        local label = id and Tags.label(id) or ""
        draft = {id=id, name=label, originalName=label, definition=copy(definition or {}),
            color={r=visual.r,g=visual.g,b=visual.b}, icon=visual.icon,
            baseRevision=Custom.getRevision(), custom=not id or self:isCustom(id)}
        self.drafts[key] = draft
    end
    self.draft, self.selectedId, self.baseRevision = draft, row.id, draft.baseRevision
    self.nameEntry:setText(draft.name)
    self.status = nil
    self:refreshControls()
end

function Editor:newTag() self:select({}) end

function Editor:refreshControls()
    local draft = self.draft
    if not draft then return end
    local texture = draft.icon and getTexture(draft.icon)
    self.iconButton:setImage(texture); self.iconButton:setTitle(texture and "" or text("Icon"))
    self.colorButton.backgroundColor = {r=draft.color.r,g=draft.color.g,b=draft.color.b,a=0.8}
    self.deleteButton:setEnable(draft.id ~= nil and draft.custom and not draft.deleted and not self.pending)
    self.resetButton:setEnable(draft.id ~= nil and not draft.custom and not self.pending)
    self.saveButton:setEnable(not self.pending)
    self.reloadButton:setEnable(not self.pending and draft.id ~= nil)
    self.newButton:setEnable(not self.pending)
    self.iconButton:setEnable(not self.pending and not draft.deleted)
    self.colorButton:setEnable(not self.pending and not draft.deleted)
    self.nameEntry:setEditable(not self.pending and not draft.deleted)
end

function Editor:reloadList()
    local query = (self.search:getInternalText() or ""):lower()
    self.list:clear()
    local entries = {}
    for _, id in ipairs(Tags.allIds(self.tagItems)) do entries[#entries+1] = {id=id,label=Tags.label(id)} end
    table.sort(entries, function(a,b) return a.label < b.label end)
    for _, row in ipairs(entries) do
        if row.label:lower():find(query,1,true) then self.list:addItem(row.label,row) end
    end
    self.lastQuery = query
end

function Editor:reloadDraft()
    if self.pending or not self.draft then return end
    local id = self.draft.id
    self.drafts[id or "__new"] = nil
    self.draft = nil
    if id and not Custom.isActive(id) then self:newTag() else self:select({id=id}) end
    self:reloadList()
end

function Editor:chooseIcon()
    if self.toolkitTagClosed or self.pending or self.draft.deleted then return end
    local draft=self.draft
    require("PZSurvivorToolkit/TagIconPicker").open(self, function(icon)
        if self.toolkitTagClosed or self.pending or self.draft ~= draft then return end
        draft.icon = icon or Visuals.defaults(draft.id or "custom").icon
        draft.iconTouched = true
        self:refreshControls()
    end)
end

function Editor:chooseColor()
    if self.toolkitTagClosed or self.pending or self.draft.deleted then return end
    if self.toolkitColorPicker then self.toolkitColorPicker:removeSelf() end
    local draft=self.draft
    local color = draft.color
    local popup = ISColorPickerHSB:new(0,0,ColorInfo.new(color.r,color.g,color.b,1))
    popup:initialise()
    popup.keepOnScreen, popup.pickedTarget, popup.resetFocusTo = true, self, self
    popup:setX(self.colorButton:getAbsoluteX()); popup:setY(self.colorButton:getAbsoluteY()+26)
    popup:setPickedFunc(function(_, rgb)
        if not self.toolkitTagClosed and not self.pending and self.draft == draft then
            draft.color = {r=rgb.r,g=rgb.g,b=rgb.b}; draft.colorTouched = true
            self:refreshControls()
        end
        popup:removeSelf()
    end)
    popup:addToUIManager(); popup:setInitialColor(ColorInfo.new(color.r,color.g,color.b,1))
    self.toolkitColorPicker = popup
    if self.grabbedJoypad then setJoypadFocus(self.playerNum,popup) end
end

function Editor:submit(value)
    if self.toolkitTagClosed or self.pending or not self.draft then return end
    self.pending, self.status = true, text("Saving")
    self:refreshControls()
    local draft = self.draft
    local owner = self.owner
    local completed = false
    local function result(status,payload)
        completed = true
        -- This accepted definition edit is the only known change since a fresh
        -- parent draft. Keep its assignment patches, advancing only that revision.
        local acceptedRevision = payload and payload.revision
        if status == "accepted" and owner and not owner.toolkitTagClosed
            and owner.baseRevision == draft.baseRevision and acceptedRevision == draft.baseRevision + 1 then
            owner.baseRevision = acceptedRevision
        end
        if self.toolkitTagClosed then return end
        self.pending = false
        if status == "accepted" then
            self.drafts[draft.id or "__new"] = nil
            self.draft = nil
            local id = payload and payload.id or draft.id
            if id and Custom.isActive(id) then self:select({id=id}) else self:newTag() end
            self:reloadList(); self.status = text("Saved")
        else self.status = text(status == "conflict" and "Conflict" or "Rejected") end
        self:refreshControls()
    end
    local request, reason = Client.edit(self.playerNum,draft.id,value,result,draft.baseRevision)
    if not request and not completed then result("rejected",{reason=reason}) end
end

function Editor:save()
    if not self.draft then return end
    if self.draft.deleted then self:submit(false); return end
    self:stash()
    local draft = self.draft
    if not draft.name:find("%S") then self.status = text("NameRequired"); return end
    local definition = copy(draft.definition)
    if draft.custom or draft.name ~= draft.originalName then definition.name = draft.name end
    if draft.colorTouched or not draft.id then definition.color = copy(draft.color) end
    if draft.iconTouched then definition.icon = draft.icon or false
    elseif not draft.id then definition.icon = draft.icon end
    self:submit(definition)
end

function Editor:resetDefinition()
    if not self.pending and self.draft and self.draft.id and not self.draft.custom then
        local draft=self.draft
        local style=Visuals.defaults(draft.id)
        draft.name=Tags.defaultLabel(draft.id)
        draft.originalName=draft.name
        draft.definition={name=false,color=false,icon=false}
        draft.color={r=style.r,g=style.g,b=style.b}; draft.icon=style.icon
        draft.colorTouched,draft.iconTouched=false,false
        self.nameEntry:setText(draft.name)
        self.status=text("ResetPending"); self:refreshControls()
    end
end

function Editor:deleteDefinition()
    if not self.pending and self.draft and self.draft.id and self.draft.custom then
        Editor.confirm(self,text("ConfirmDelete"),function()
            self.draft.deleted=true; self.status=text("DeletePending"); self:refreshControls()
        end)
    end
end

function Editor:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local w,h = self.width,self.height
    self.search = ISTextEntryBox:new("",12,34,w-138,26)
    self.search:initialise(); self.search:instantiate(); self.search:setTooltip(text("Search")); self:addChild(self.search)
    self.newButton = Editor.button(self,w-114,34,102,text("New"),Editor.newTag)
    self.list = ISScrollingListBox:new(12,68,w-24,h-316)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight = getTextManager():getFontHeight(UIFont.Small)+12
    self.list.font,self.list.joypadParent = UIFont.Small,self
    Editor.configureList(self,self.list,Editor.select)
    self.list:setOnMouseDownFunction(self,Editor.select)
    self.list.doDrawItem = function(list,y,row)
        if y+list:getYScroll()+row.height < 0 or y+list:getYScroll() >= list.height then return y+row.height end
        local style = Visuals.get(row.item.id)
        if row.item.id == self.selectedId then list:drawRect(0,y,list.width,row.height,0.35,0.3,0.5,0.7) end
        if style.texture then list:drawTextureScaledAspect(style.texture,6,y+4,20,20,1,style.r,style.g,style.b) end
        list:drawText(UIStyle.fit(row.text,list.width-56),32,y+5,1,1,1,1,UIFont.Small)
        return y+row.height
    end
    self:addChild(self.list)
    self.nameEntry = ISTextEntryBox:new("",12,h-214,w-24,26)
    self.nameEntry:initialise(); self.nameEntry:instantiate(); self.nameEntry:setMaxTextLength(80)
    self.nameEntry.font = UIFont.Medium; self:addChild(self.nameEntry)
    local bw=(w-42)/4
    self.iconButton=Editor.button(self,12,h-180,bw,text("Icon"),Editor.chooseIcon); self.iconButton:forceImageSize(22,22)
    self.colorButton=Editor.button(self,18+bw,h-180,bw,text("Color"),Editor.chooseColor)
    self.resetButton=Editor.button(self,24+bw*2,h-180,bw,text("ResetDefinition"),Editor.resetDefinition)
    self.deleteButton=Editor.button(self,30+bw*3,h-180,bw,text("Delete"),Editor.deleteDefinition)
    self.reloadButton=Editor.button(self,12,h-42,110,text("Reload"),Editor.reloadDraft)
    self.cancelButton=Editor.button(self,w-224,h-42,100,getText("UI_Cancel"),Editor.close)
    self.saveButton=Editor.button(self,w-112,h-42,100,text("Save"),Editor.save)
    self:reloadList()
    if self.list.items[1] then self:select(self.list.items[1].item) else self:newTag() end
end

function Editor:prerender()
    if Editor.ownerClosed(self) then self:close(); return end
    if self.reassertTop then self.reassertTop=false; self:bringToTop() end
    if (self.search:getInternalText() or ""):lower() ~= self.lastQuery then self:reloadList() end
    if self.lastRevision ~= Tags.revision() then
        self.lastRevision=Tags.revision(); self:reloadList()
    end
    ISCollapsableWindowJoypad.prerender(self)
    self:drawText(text("Name"),12,self.height-238,1,1,1,1,UIFont.Small)
    local draft=self.draft
    if draft then
        local texture=draft.icon and getTexture(draft.icon)
        if texture then self:drawTextureScaledAspect(texture,12,self.height-146,24,24,1,draft.color.r,draft.color.g,draft.color.b) end
        self:drawText(UIStyle.fit(self.nameEntry:getInternalText() or "",self.width-56),44,self.height-143,
            draft.color.r,draft.color.g,draft.color.b,1,UIFont.Small)
    end
    self:drawText(UIStyle.fit(self.status or text("CatalogHint"),self.width-24),12,self.height-106,0.9,0.8,0.6,1,UIFont.Small)
    self:drawText(UIStyle.fit(text("Shared"),self.width-24),12,self.height-78,0.8,0.8,0.8,1,UIFont.Small)
end

function Editor:onGainJoypadFocus(data)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self,data)
    if self.joypadConfigured then return end
    self.joypadConfigured=true
    self:insertNewLineOfButtons(self.search,self.newButton)
    self:insertNewLineOfButtons(self.list)
    self:insertNewLineOfButtons(self.nameEntry)
    self:insertNewLineOfButtons(self.iconButton,self.colorButton,self.resetButton,self.deleteButton)
    self:insertNewLineOfButtons(self.reloadButton,self.cancelButton,self.saveButton)
    self.joypadIndexY,self.joypadIndex=1,1; self:restoreJoypadFocus(data)
end

function Editor:onJoypadDown(key,data)
    if key == Joypad.BButton then self:close(); return end
    ISCollapsableWindowJoypad.onJoypadDown(self,key,data)
end

function Editor.open(options)
    options = options or {}
    local w,h = math.min(620,getCore():getScreenWidth()-24),math.min(680,getCore():getScreenHeight()-24)
    local window=Editor:new((getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-h)/2,w,h)
    window.tagItems = options.items
    window.drafts,window.title,window.lastRevision = {},text("Catalog"),Tags.revision()
    return Editor.attach(window,options,"toolkitTagEditor")
end

return Editor
