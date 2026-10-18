require = function() end
ISCollapsableWindow = {derive = function() return {} end}
UIFont = {Small = 1}
getTextManager = function() return {getFontHeight = function() return 14 end} end
local language = "EN"
local messages = {EN = "Can't be repaired.", RU = "Нельзя починить."}
function getText(key) return key == "IGUI_garment_CantRepair" and messages[language] or key end

local Menu = {}; Menu.__index = Menu
function Menu:addOption(name, target, callback, ...)
    local option = {name = name, target = target, onSelect = callback}
    for index = 1, select('#', ...) do option['param' .. index] = select(index, ...) end
    self.options[#self.options + 1] = option
    return option
end
function Menu:getNew() return setmetatable({options = {}}, Menu) end
function Menu:addSubMenu(option, child) option.child = child end
local lastMenu, coordinates
ISContextMenu = {get = function(player, x, y)
    coordinates = {player, x, y}
    lastMenu = Menu:getNew()
    return lastMenu
end}
ISInventoryPaneContextMenu = {addToolTip = function() return {} end}
for _, name in ipairs({'repairClothing', 'repairAllClothing', 'removePatch', 'removeAllPatches'}) do
    ISInventoryPaneContextMenu[name] = function() end
end
Perks = {Tailoring = 1}; ItemTag = {THREAD = 1, SEWING_NEEDLE = 2}
Clothing = {getScratchDefenseFromItem = function() return 1 end, getBiteDefenseFromItem = function() return 1 end}
ISRemovePatch = {chanceToGetPatchBack = function() return 1 end}
local supplies, hasSupplies, lookups = {}, false, 0
for _, name in ipairs({'Thread', 'Needle', 'RippedSheets', 'DenimStrips', 'LeatherStrips'}) do
    supplies[name] = {getDisplayName = function() return name end, getType = function() return name end}
end
local inventory = {getItemFromType = function(_, name)
    lookups = lookups + 1
    return hasSupplies and supplies[name] or nil
end, getItemFromTag = function() end, getFirstTagRecurse = function() end, getItemCount = function() return 2 end}
local character = {getPlayerNum = function() return 0 end, getInventory = function() return inventory end,
    getPerkLevel = function() return 1 end}
local fabricType, patch, hole
local patchData = {getScratchDefense = function() return 1 end, getBiteDefense = function() return 1 end}
local garment = {getFabricType = function() return fabricType end, getPatchType = function() return patch end,
    getPatchesNumber = function() return 2 end, getHolesNumber = function() return 2 end,
    getVisual = function() return {getHole = function() return hole and 1 or 0 end} end,
    canFullyRestore = function() return false end}
local part = {}
local sentinel = {}
ISGarmentUI = {doContextMenu = function() return sentinel end}
if NativeGarmentSource then assert(loadstring(NativeGarmentSource))() end
local native, calls = ISGarmentUI.doContextMenu, 0
ISGarmentUI.doContextMenu = function(self, p, x, y)
    assert(p == part and x == 123 and y == 456)
    calls = calls + 1
    return native(self, p, x, y)
end
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ClothingRepairMenu.lua')
local ui = setmetatable({chr = character, clothing = garment, parts = {part, part}}, {__index = ISGarmentUI})
for _, lang in ipairs({'EN', 'RU'}) do
    language = lang
    for _, suppliesPresent in ipairs({false, true}) do
        hasSupplies = suppliesPresent
        fabricType, patch, hole = nil, nil, true
        calls, lookups = 0, 0
        local context = ui:doContextMenu(part, 123, 456)
        assert(context == lastMenu and #context.options == 1 and calls == 0 and lookups == 0)
        assert(coordinates[1] == 0 and coordinates[2] == 123 and coordinates[3] == 456)
        local option = context.options[1]
        assert(option.name == messages[lang] and option.notAvailable and not option.onSelect and not option.child)
        assert(option.toolTip.description == messages[lang], 'never advise supplies for an unrepairable garment')
        for _, case in ipairs({'hole', 'padding', 'patch', 'unrepairable-with-patch'}) do
            fabricType = case ~= 'unrepairable-with-patch' and 'Cotton' or nil
            patch = (case == 'patch' or case == 'unrepairable-with-patch') and patchData or nil
            hole = case == 'hole'
            calls = 0
            local context = ui:doContextMenu(part, 123, 456)
            assert(calls == 1, 'preserve native repair and existing patch removal')
            if not NativeGarmentSource then assert(context == sentinel)
            elseif patch then
                assert(#context.options == 2 and context.options[1].onSelect == ISInventoryPaneContextMenu.removePatch)
                assert(context.options[1].notAvailable == (not hasSupplies and true or nil))
            elseif not hasSupplies then
                assert(context.options[1].notAvailable and context.options[1].toolTip.description == 'ContextMenu_CantRepair')
            else
                local header = context.options[1]
                assert(header.name == (hole and 'ContextMenu_PatchHole' or 'ContextMenu_AddPadding'))
                assert(#header.child.options == 6)
                local action = header.child.options[1]
                assert(action.onSelect == ISInventoryPaneContextMenu.repairClothing and action.target == character)
                assert(action.param1 == garment and action.param2 == part and action.param3 == supplies.RippedSheets
                    and action.param4 == supplies.Thread and action.param5 == supplies.Needle)
            end
        end
    end
end
print('PASS unrepairable clothing message with/without supplies, EN/RU, native repair/padding and patch removal'
    .. (NativeGarmentSource and ' (installed garment UI)' or ' (delegation checks)'))
