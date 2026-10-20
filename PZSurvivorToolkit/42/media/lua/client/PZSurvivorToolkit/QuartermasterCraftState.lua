-- One live preference and invalidation stream for every crafting window.
local State = {}
local revision = 0
LootSorter = LootSorter or {}
LootSorter.craftFromBoxes = LootSorter.craftFromBoxes or false

function State.revision()
    return revision
end

function State.invalidate()
    revision = revision + 1
end

function State.setEnabled(value)
    local enabled = value and true or false
    if LootSorter.craftFromBoxes ~= enabled then
        LootSorter.craftFromBoxes = enabled
        State.invalidate()
    end
    -- The craft-window control and Mod Options edit the same persisted preference.
    pcall(function()
        local options = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions("LootSorter")
        local option = options and options:getOption("craftFromBoxes")
        if option then option:setValue(enabled) end
    end)
end

return State
