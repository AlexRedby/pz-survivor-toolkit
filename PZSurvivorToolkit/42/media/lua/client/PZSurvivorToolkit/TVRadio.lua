require "PZSurvivorToolkit/Settings"

local Toolkit = PZSurvivorToolkit
local TVRadio = {}
Toolkit.TVRadio = TVRadio

local function isVHS(item)
    return item:isRecordedMedia() and item:getMediaType() == 1
end

local function availableTapes(player)
    -- Rebuild the native loot list: range, walls, vehicles, safehouses and locks.
    getPlayerLoot(player:getPlayerNum()):refreshBackpacks()
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    local tapes, seen = {}, {}
    for i = 0, containers:size() - 1 do
        local container = containers:get(i)
        local items = container:getAllEvalRecurse(isVHS, ArrayList.new())
        for j = 0, items:size() - 1 do
            local item = items:get(j)
            local source = item:getContainer()
            if isVHS(item) and source and not seen[item]
                and not source:getOutermostContainer():isLockedToCharacter(player) then
                seen[item] = true
                tapes[#tapes + 1] = item
            end
        end
    end
    return tapes
end

local function installVHS()
    local class = RWMMergedTV
    if not class or TVRadio.tvClass == class then return end
    TVRadio.tvClass = class
    local addMedia, addMediaAux, bumper, createChildren = class.addMedia, class.addMediaAux,
        class.onBumperContext, class.createChildren
    class.addMedia = function(self, ...)
        if not Toolkit.Settings.improveVHSControls() then return addMedia(self, ...) end
        if self.deviceData:hasMedia() then return self:removeMedia() end
        local playerNum = self.player:getPlayerNum()
        local choices = {}
        for _, item in ipairs(availableTapes(self.player)) do
            choices[#choices + 1] = {item = item, watched = item:hasBeenSeen(self.player), name = item:getDisplayName()}
        end
        if #choices == 0 then return end
        local menu = ISContextMenu.get(playerNum, self.slotVHS:getAbsoluteX(), self.slotVHS:getAbsoluteY())
        table.sort(choices, function(a, b)
            if a.watched ~= b.watched then return not a.watched end
            return a.name < b.name
        end)
        for _, choice in ipairs(choices) do
            local option = menu:addOption(choice.name, self, self.addMediaAux, choice.item)
            if choice.watched then option.iconTexture = getTexture("media/ui/Tick_Mark-10.png") end
        end
        menu.mouseOver = 1
        if JoypadState.players[playerNum + 1] then
            menu.origin = JoypadState.players[playerNum + 1].focus
            setJoypadFocus(playerNum, menu)
        end
    end
    class.onBumperContext = function(self, ...)
        if Toolkit.Settings.improveVHSControls() and not self.deviceData:hasMedia() then
            return self:addMedia()
        end
        return bumper(self, ...)
    end
    class.addMediaAux = function(self, item, ...)
        if not Toolkit.Settings.improveVHSControls() then return addMediaAux(self, item, ...) end
        if not self.player or not self.deviceData or self.deviceData:hasMedia() then return end
        for _, candidate in ipairs(availableTapes(self.player)) do
            if candidate == item then return RWMMedia.addMediaAux(self, item) end
        end
    end
    class.createChildren = function(self, ...)
        local result = createChildren(self, ...)
        local slot = self.slotVHS
        local mouseUp, prerender = slot.onMouseUp, slot.prerender
        local hoverColor, tooltip = slot.backgroundColorMouseOver, slot.tooltip
        -- Vanilla drag parsing handles individual items and expanded/collapsed stacks.
        slot.functionTarget, slot.mouseEnabled = self, true
        slot.onVerifyItem = function(panel, item) return not panel.deviceData:hasMedia() and isVHS(item) end
        slot.onItemDropped = function(panel, items) panel:addMediaAux(items[1]) end
        slot.onMouseUp = function(button, x, y)
            if Toolkit.Settings.improveVHSControls() and ISMouseDrag.dragging then
                button.pressed = false
                button.boxOccupied = self.deviceData:hasMedia()
                return ISItemDropBox.onMouseUp(button, x, y)
            end
            return mouseUp(button, x, y)
        end
        slot.prerender = function(button, ...)
            local enabled = Toolkit.Settings.improveVHSControls()
            button.tooltip = enabled and getText("UI_PZSurvivorToolkit_vhs_slot_tooltip") or tooltip
            button.backgroundColorMouseOver = hoverColor
            if enabled and ISMouseDrag.dragging then
                local valid = ISItemDropBox.hasValidItemInDrag(button)
                button.backgroundColorMouseOver = valid
                    and {r = 0.1, g = 0.45, b = 0.1, a = 0.7} or {r = 0.5, g = 0.1, b = 0.1, a = 0.7}
            end
            return prerender(button, ...)
        end
        return result
    end
end

local function updateCloseButton(window)
    local button = window.closeButton
    if not button then return end
    local keepOpen = Toolkit.Settings.keepMediaWindowOpen()
    button:setVisible(keepOpen)
    if keepOpen then
        button:setX(window:getWidth() - button:getWidth() - 3)
        button:setY(3)
        button:bringToTop()
    end
end

function TVRadio.settingsChanged()
    local class = TVRadio.windowClass
    if not class then return end
    for _, instances in ipairs({class.instances, class.instancesIso}) do
        for _, window in pairs(instances) do updateCloseButton(window) end
    end
end

local function install()
    if not getActivatedMods():contains("TVRadio_ReInvented") or not ISRadioWindow then return end
    installVHS()
    local class = ISRadioWindow
    if TVRadio.windowClass == class then return end
    TVRadio.windowClass = class
    local activate, prerender, outside = class.activate, class.prerender, class.onMouseDownOutside
    class.activate = function(...)
        local window = activate(...)
        if window then updateCloseButton(window) end
        return window
    end
    class.prerender = function(self, ...)
        local result = prerender(self, ...)
        updateCloseButton(self)
        return result
    end
    class.onMouseDownOutside = function(self, ...)
        if Toolkit.Settings.keepMediaWindowOpen() then return end
        return outside(self, ...)
    end
end

-- Both upstream mods replace the window class; wrap the final class after loading.
Events.OnGameStart.Add(install)
