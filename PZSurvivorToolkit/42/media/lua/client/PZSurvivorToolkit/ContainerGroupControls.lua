require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISContextMenu"
local Groups = require "PZSurvivorToolkit/ContainerGroups"
local Appearance = require "PZSurvivorToolkit/ContainerAppearanceControls"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Controls = {}
local function text(key) return getText("UI_PZST_ContainerGroup" .. key) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function Controls.snapshot(picker)
    local config = LootSorter.snapshotDesignation({cats = picker.selectedCats, items = picker.selectedItems,
        presets = picker.selectedPresets, priority = picker.priority, noDuplicates = picker.noDuplicates})
    config.pzstTagRule = nil
    config.appearance = Appearance.snapshot(picker)
    -- An empty name and an absent optional name have the same storage meaning.
    local name = config.appearance.name
    if name then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
    config.appearance.name = name ~= "" and name or nil
    return {configuration = config, rule = copy(picker.toolkitTagRule)}
end

local function focusMenu(picker, menu)
    if picker.grabbedJoypad then
        menu.origin, menu.mouseOver = picker, 1
        setJoypadFocus(picker.playerNum, menu)
    end
    return menu
end

function Controls.select(picker, record)
    if picker.toolkitTagSaving or picker.toolkitTagClosed then return end
    picker.containerGroupCreating, picker.containerGroupScope = false, "local"
    picker.containerGroupUnresolved = false
    picker.containerGroupRecord = copy(record)
    if record then
        local config = copy(record.configuration)
        picker.selectedCats, picker.selectedItems, picker.selectedPresets = config.cats, config.items, config.presets
        picker.selection = picker.mode == "items" and picker.selectedItems
            or picker.mode == "presets" and picker.selectedPresets or picker.selectedCats
        picker:setPriority(config.priority)
        picker.noDuplicates, picker.toolkitTagRule = config.noDuplicates, copy(record.rule)
        picker.toolkitTagRuleTouched = true
        Appearance.setValue(picker, config.appearance)
    end
    picker.containerGroupBaseline = Controls.snapshot(picker)
    picker.needRebuild = true
    picker:layout()
    if picker.joypadConfigured then picker:configJoypad() end
end

function Controls.createGroup(picker)
    if picker.toolkitTagSaving or picker.toolkitTagClosed then return end
    picker.containerGroupCreating, picker.containerGroupRecord = true, nil
    picker.containerGroupUnresolved = false
    picker:layout()
    if picker.joypadConfigured then picker:configJoypad() end
end

function Controls.setScope(picker, scope)
    if picker.toolkitTagSaving then return end
    picker.containerGroupScope = scope
    Controls.refresh(picker)
end

function Controls.openScope(picker)
    if picker.toolkitTagSaving then return end
    local menu = ISContextMenu.get(picker.playerNum or 0, picker.groupScope:getAbsoluteX(),
        picker.groupScope:getAbsoluteY() + picker.groupScope:getHeight())
    menu:addOption(text("OnlyContainer"), picker, Controls.setScope, "local")
    local option = menu:addOption(text("EntireGroup"), picker, Controls.setScope, "group")
    if not Groups.canEdit(picker.containerGroupRecord, getSpecificPlayer(picker.playerNum or 0)) then
        option.notAvailable = true
    end
    return focusMenu(picker, menu)
end

function Controls.openMenu(picker)
    if picker.toolkitTagSaving then return end
    local menu = ISContextMenu.get(picker.playerNum or 0, picker.groupSelect:getAbsoluteX(),
        picker.groupSelect:getAbsoluteY() + picker.groupSelect:getHeight())
    menu:addOption(text("Own"), picker, Controls.select)
    if Groups.synced() then
        menu:addOption(text("Create"), picker, Controls.createGroup)
        local records, names = Groups.list(), {}
        for _, record in ipairs(records) do
            local name = record.configuration.appearance.name
            names[name] = (names[name] or 0) + 1
        end
        for _, record in ipairs(records) do
            local name = record.configuration.appearance.name
            local label = names[name] > 1 and (name .. " (" .. record.id .. ")") or name
            menu:addOption(label, picker, Controls.select, record)
        end
    else
        local option = menu:addOption(text("Syncing"), nil, nil)
        option.notAvailable = true
    end
    return focusMenu(picker, menu)
end

function Controls.create(picker)
    if picker.targetKind == "preset" then return end
    picker.containerGroupOriginalLink = Groups.link(picker.targetObj, picker.targetCI)
    picker.containerGroupScope = "local"
    picker.groupSelect = ISButton:new(10, 0, 100, 26, "", picker, Controls.openMenu)
    picker.groupScope = ISButton:new(10, 0, 100, 26, "", picker, Controls.openScope)
    picker.groupHint = ISLabel:new(10, 0, 20, "", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    for _, child in ipairs({picker.groupSelect, picker.groupScope, picker.groupHint}) do
        child:initialise(); child:instantiate(); picker:addChild(child)
    end
    local record = Groups.resolve(picker.targetObj, picker.targetCI)
    picker.containerGroupUnresolved = picker.containerGroupOriginalLink ~= nil and record == nil
    if record then
        Controls.select(picker, record)
    else
        picker.containerGroupBaseline = Controls.snapshot(picker)
    end
end

function Controls.refresh(picker)
    if not picker.groupSelect then return end
    if picker.containerGroupUnresolved and Groups.synced() and picker.containerGroupBaseline
        and equal(Controls.snapshot(picker), picker.containerGroupBaseline) then
        Controls.select(picker, Groups.resolve(picker.targetObj, picker.targetCI))
        return
    end
    local record, creating = picker.containerGroupRecord, picker.containerGroupCreating
    local title = creating and text("New") or record and record.configuration.appearance.name or text("Own")
    if picker.containerGroupOriginalLink and not Groups.synced() then title = text("Syncing") end
    if picker.containerGroupUnresolved and Groups.synced() then title = text("Reload") end
    picker.groupSelect:setTitle(UIStyle.fit(text("Label") .. ": " .. title, picker.groupSelect:getWidth() - 20, UIFont.Small))
    picker.groupSelect:setTooltip(title)
    picker.groupScope:setVisible(record ~= nil)
    picker.groupScope:setTitle(text(picker.containerGroupScope == "group" and "EntireGroup" or "OnlyContainer"))
    picker.groupScope:setTooltip(text(Groups.canEdit(record, getSpecificPlayer(picker.playerNum or 0))
        and "EntireHint" or "CannotEdit"))
    local hint = text(creating and "CreateHint" or record and
        (picker.containerGroupScope == "group" and "EntireHint" or "DetachHint") or "OwnHint")
    picker.groupHint:setName(UIStyle.fit(hint, picker:getWidth() - 20, UIFont.Small))
    picker.groupHint:setTooltip(hint)
end

function Controls.layout(picker, top)
    if not picker.groupSelect then return top end
    local rowH = math.max(26, getTextManager():getFontHeight(UIFont.Small) + 8)
    local width = picker:getWidth() - 20
    picker.groupSelect:setX(10); picker.groupSelect:setY(top)
    picker.groupSelect:setWidth(width); picker.groupSelect:setHeight(rowH)
    top = top + rowH + 6
    if picker.containerGroupRecord then
        picker.groupScope:setX(10); picker.groupScope:setY(top)
        picker.groupScope:setWidth(width); picker.groupScope:setHeight(rowH)
        top = top + rowH + 6
    end
    picker.groupHint:setX(10); picker.groupHint:setY(top); picker.groupHint:setHeight(rowH)
    Controls.refresh(picker)
    return top + rowH + 6
end

-- Called once per submitted draft. Every table sent to the authority is detached from the UI.
function Controls.prepare(picker, snapshot)
    if not picker.groupSelect then return true end
    if picker.containerGroupOriginalLink and not Groups.synced() then return false, text("Syncing") end
    if picker.containerGroupUnresolved then return false, text("Reload") end
    local record = picker.containerGroupRecord
    if picker.containerGroupCreating or record or picker.containerGroupOriginalLink then
        local draft = Controls.snapshot(picker)
        snapshot.appearance = draft.configuration.appearance
        if picker.containerGroupCreating then
            if not snapshot.appearance.name then return false, text("NameRequired") end
            snapshot.groupOperation = {mode = "create"}
        elseif record then
            if equal(draft, picker.containerGroupBaseline) then
                snapshot.groupOperation = {mode = "join", id = record.id}
            elseif picker.containerGroupScope == "group" then
                if not Groups.canEdit(record, getSpecificPlayer(picker.playerNum or 0)) then return false, text("CannotEdit") end
                if not snapshot.appearance.name then return false, text("NameRequired") end
                snapshot.groupOperation = {mode = "update", id = record.id, baseRevision = record.rev}
            else snapshot.groupOperation = {mode = "detach"} end
        else snapshot.groupOperation = {mode = "detach"} end
    end
    return true
end

return Controls
