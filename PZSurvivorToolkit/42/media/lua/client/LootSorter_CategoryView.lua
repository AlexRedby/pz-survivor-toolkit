-- LootSorter: a read-only window listing every item that belongs to one DisplayCategory, opened by
-- right-clicking a category in the designation picker (or Y/triangle on a controller). Purely
-- informational -- nothing here writes a designation -- so a category like "Household" can be read
-- before it is ticked.
require "ISUI/ISCollapsableWindow"
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

LootSorter = LootSorter or {}

local CategoryView = ISCollapsableWindowJoypad:derive("LootSorterCategoryView")
local ICON = 18

function CategoryView:createChildren()
    ISCollapsableWindow.createChildren(self)

    self.filter = ISTextEntryBox:new("", 10, 0, 10, 22)
    self.filter:initialise(); self.filter:instantiate()
    self.filter.font = UIFont.Medium
    self:addChild(self.filter)
    self.filter:setTooltip("Type to filter the list")
    self.lastFilter = nil

    self.listbox = ISScrollingListBox:new(10, 0, 10, 10)
    self.listbox.itemheight = 22
    self.listbox.drawBorder = true
    self.listbox.target = self
    self.listbox.doDrawItem = CategoryView.doDrawItem
    self.listbox.joypadParent = self
    -- Same controller model as the picker's list: up/down pass OVER this row by default, A enters it
    -- for scrolling and B leaves. Without overriding setJoypadFocused a focused list captures input
    -- and traps up/down, so the filter row above becomes unreachable.
    self.listbox.setJoypadFocused = function(listbox, focused)
        listbox.joypadFocused = focused
    end
    self.listbox.onJoypadDownInParent = function(listbox, button, joypadData)
        if button == Joypad.AButton then
            listbox.joypadFocused = true
            joypadData.focus = listbox
            updateJoypadFocus(joypadData)
            if (listbox.selected or 0) < 1 and listbox.count > 0 then listbox.selected = 1 end
            return true
        end
        return false
    end
    self.listbox.onJoypadDown = function(listbox, button, joypadData)
        if button == Joypad.BButton then
            listbox.joypadFocused = false
            joypadData.focus = listbox.joypadParent
            updateJoypadFocus(joypadData)
            return
        end
        ISPanelJoypad.onJoypadDown(listbox, button, joypadData)
    end
    self.listbox.onJoypadDirUp = function(listbox)
        listbox.selected = listbox:prevVisibleIndex(listbox.selected)
        if listbox.selected <= 0 then listbox.selected = listbox:prevVisibleIndex(listbox.count + 1) end
        getSoundManager():playUISound("UISelectListItem")
        listbox:ensureVisible(listbox.selected)
    end
    self.listbox.onJoypadDirDown = function(listbox)
        listbox.selected = listbox:nextVisibleIndex(listbox.selected)
        if listbox.selected == -1 then listbox.selected = listbox:nextVisibleIndex(0) end
        getSoundManager():playUISound("UISelectListItem")
        listbox:ensureVisible(listbox.selected)
    end
    self.listbox:initialise(); self.listbox:instantiate()
    self:addChild(self.listbox)

    self:layout()
    self:rebuild()
end

function CategoryView:layout()
    local pad, gap = 10, 6
    local width, height = self:getWidth(), self:getHeight()
    local innerWidth = width - pad * 2
    local top = self:titleBarHeight() + 8

    self.filter:setX(pad); self.filter:setY(top); self.filter:setWidth(innerWidth)

    local listY = top + 22 + gap
    self.listbox:setX(pad); self.listbox:setY(listY); self.listbox:setWidth(innerWidth)
    self.listbox:setHeight(math.max(40, (height - 12) - listY))
end

-- OSK-aware, like the picker: while a controller's on-screen keyboard is editing our filter box, read
-- its live buffer so the list filters per keystroke instead of only on Enter.
function CategoryView:currentFilter()
    if OnScreenKeyboard and OnScreenKeyboard.IsVisible() and OnScreenKeyboard.instance
        and OnScreenKeyboard.instance.textEntryBox == self.filter then
        return OnScreenKeyboard.GetCurrentText() or ""
    end
    return self.filter:getInternalText() or ""
end

function CategoryView:rebuild()
    local text = string.lower(self:currentFilter())
    self.listbox:clear()
    for _, entry in ipairs(self.entries) do
        if text == "" or string.find(string.lower(entry.name), text, 1, true) then
            self.listbox:addItem(entry.name, entry)
        end
    end
    self.lastFilter = text
end

function CategoryView:prerender()
    ISCollapsableWindow.prerender(self)
    if self.configJoypadLater then self.configJoypadLater = false; self:configJoypad() end
    if self._lastWidth ~= self:getWidth() or self._lastHeight ~= self:getHeight() then
        self._lastWidth, self._lastHeight = self:getWidth(), self:getHeight()
        self:layout()
    end
    if OnScreenKeyboard and OnScreenKeyboard.IsVisible() and OnScreenKeyboard.instance
        and OnScreenKeyboard.instance.textEntryBox == self.filter then
        local live = OnScreenKeyboard.GetCurrentText() or ""
        if self.filter:getInternalText() ~= live then self.filter:setText(live) end
    end
    local text = string.lower(self:currentFilter())
    if text ~= self.lastFilter then self:rebuild() end
end

function CategoryView.doDrawItem(self, y, item, alt)
    local entry = item.item
    local height = item.height
    -- Off-screen rows draw nothing: the list box calls this for every row every frame (see the same
    -- guard in the picker), and a big category is hundreds of them.
    local scroll = self:getYScroll()
    if y + scroll + height < 0 or y + scroll >= self:getHeight() then return y + height end
    if self.selected == item.index then
        self:drawRect(0, y, self:getWidth(), height - 1, 0.3, 0.7, 0.7, 0.7)
    end
    local texture = LootSorter.itemTexture(entry.fullType)
    if texture then self:drawTextureScaled(texture, 6, y + 2, ICON, ICON, 1.0) end
    local fontHeight = getTextManager():getFontHeight(UIFont.Medium)
    self:drawText(entry.name, 6 + ICON + 8, y + (height - fontHeight) / 2, 1, 1, 1, 1, UIFont.Medium)
    return y + height
end

function CategoryView:configJoypad()
    local joypadData = getJoypadData(self.playerNum)
    self:clearISButtons()
    if not joypadData then return end
    self:clearJoypadFocus(joypadData)
    self.joypadIndexY = 1
    self.joypadIndex = 1
    self.joypadButtonsY = {}
    self.joypadButtons = {}
    self.allJoypadButtons = {}   -- reset too: insertNewLineOfButtons APPENDS to this (else it leaks)
    self.joypadConfigured = true
    self:insertNewLineOfButtons(self.filter)     -- A opens the on-screen keyboard
    self:insertNewLineOfButtons(self.listbox)    -- A enters to scroll, B leaves
    self.joypadIndexY = self:getMinVisibleRow()
    self:restoreJoypadFocus(joypadData)
end

function CategoryView:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    if not self.joypadConfigured then self.configJoypadLater = true end
end

function CategoryView:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        self:closeView()
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

function CategoryView:closeView()
    -- Hand the pad back to whatever had it (the picker), never nil: focusing nil leaves the controller
    -- on nothing and the still-open picker goes dead until it is reopened.
    local restore = self.grabbedJoypad and self.prevFocus or nil
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.grabbedJoypad then setJoypadFocus(self.playerNum, restore); self.grabbedJoypad = false end
    LootSorter._categoryView = nil
end
-- The title-bar X calls self:close(); route it through closeView so it releases joypad focus too.
CategoryView.close = CategoryView.closeView

function CategoryView:new(x, y, width, height)
    local o = ISCollapsableWindowJoypad:new(x, y, width, height)
    setmetatable(o, self); self.__index = self
    o.entries = {}
    o.resizable = true
    o.minimumWidth = 260
    o.minimumHeight = 240
    return o
end

-- Entry point from the picker's category context menu.
function LootSorter.openCategoryView(category, playerNum, parent)
    if not category then return end
    if LootSorter._categoryView then LootSorter._categoryView:closeView() end
    local entries = LootSorter.getItemsInCategory(category)
    local width, height = 387, 557
    -- Offset from centre so it doesn't land exactly on the picker it was opened from.
    local view = CategoryView:new(getCore():getScreenWidth() / 2 - width / 2 + 200,
                                  getCore():getScreenHeight() / 2 - height / 2, width, height)
    view.entries = entries
    view.title = category .. " (" .. #entries .. " item" .. (#entries == 1 and "" or "s") .. ")"
    view.playerNum = playerNum or 0
    view:initialise()
    view:addToUIManager()
    local player = getSpecificPlayer(view.playerNum)
    if player and player:getJoypadBind() ~= -1 then
        view.prevFocus = parent                  -- B returns to the picker
        setJoypadFocus(view.playerNum, view)
        view.grabbedJoypad = true
    end
    LootSorter._categoryView = view
end
