require "ISUI/ISTextBox"
require "ISUI/ISModalDialog"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Presets = require "PZSurvivorToolkit/TagFilterPresets"
local Menu = {}

local function text(key) return getText("UI_PZST_TagPreset" .. key) end
local function visible(owner)
    return owner and not owner.removed and (not owner.getIsVisible or owner:getIsVisible())
        and (not owner.isReallyVisible or owner:isReallyVisible())
end
local function valid(context)
    local owner = context.owner
    return PZSurvivorToolkit.Settings.inventoryFilters() and Tags.enabled() and visible(owner)
        and owner.inventory == context.inventory and context.character ~= nil
        and getSpecificPlayer(context.player) == context.character
        and (not owner.parent or not owner.parent.inventoryPane or owner.parent.inventoryPane == owner)
end
local function focus(modal, context)
    local joypad = JoypadState.players[context.player + 1]
    if joypad then modal.prevFocus = joypad.focus; setJoypadFocus(context.player, modal) end
end
local function errorText(error)
    return text(error or "WriteFailed")
end
local function showError(context, error)
    if not valid(context) then return end
    local modal = ISModalDialog:new(0, 0, 400, 160, errorText(error), false, nil, nil, context.player)
    modal:initialise(); modal:addToUIManager(); focus(modal, context)
    return modal
end
local function apply(context, rule)
    if not valid(context) then return end
    local copy, error = Tags.normalizeRule(rule)
    if not copy then return showError(context, error and "InvalidRule") end
    context.onApply(copy)
end
local function accept(context, button)
    local modal = button.parent
    modal:showErrorMessage(false)
    if button.internal ~= "OK" or not valid(context) then return end
    local ok, error = Presets.save(modal.entry:getText(), context.rule)
    if not ok then
        modal:showErrorMessage(true, errorText(error))
        -- ISTextBox returns controller focus before invoking its callback.
        if JoypadState.players[context.player + 1] then setJoypadFocus(context.player, modal) end
        modal.entry:focus()
    end
end
local function save(context)
    if not valid(context) or not Tags.ruleActive(context.rule) then return end
    local modal = ISTextBox:new(0, 0, 440, 160, text("Prompt"), "", context, accept, context.player)
    modal:initialise()
    modal.maxChars, modal.noEmpty = 48, true
    modal.entry.onCommandEntered = function()
        modal:updateButtons()
        if modal.yes:isEnabled() then modal:onClick(modal.yes) end
    end
    modal:addToUIManager(); modal.entry:focus(); focus(modal, context)
    return modal
end
local function remove(context, name)
    if not valid(context) then return end
    local ok, error = Presets.remove(name)
    if not ok then return showError(context, error) end
end

function Menu.add(menu, options)
    if not PZSurvivorToolkit.Settings.inventoryFilters() or not Tags.enabled() then return end
    local context = {owner=options.owner, player=options.player, inventory=options.owner.inventory,
        character=getSpecificPlayer(options.player), rule=Tags.normalizeRule(options.rule), onApply=options.onApply}
    local root = menu:addOption(text("Saved"))
    root.pzstKey = "tagPresets"
    local submenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(root, submenu)
    local entries, error = Presets.list()
    if not entries then
        local failed = submenu:addOption(errorText(error), context, showError, error)
        failed.pzstKey = "tagPresetError"
        return root
    end
    for _, entry in ipairs(entries) do
        local option = submenu:addOption(entry.name, context, apply, entry.rule)
        option.pzstKey = "tagPreset:" .. entry.name
    end
    if #entries == 0 then
        local empty = submenu:addOption(text("Empty"))
        empty.notAvailable = true
    end
    local create = submenu:addOption(text("Save"), context, save)
    create.pzstKey, create.notAvailable = "tagPresetSave", not Tags.ruleActive(context.rule)
    local delete = submenu:addOption(text("Delete"))
    delete.pzstKey, delete.notAvailable = "tagPresetDelete", #entries == 0
    if #entries > 0 then
        local deletion = ISContextMenu:getNew(submenu)
        submenu:addSubMenu(delete, deletion)
        for _, entry in ipairs(entries) do
            local option = deletion:addOption(entry.name, context, remove, entry.name)
            option.pzstKey = "tagPresetDelete:" .. entry.name
        end
    end
    return root
end

return Menu
