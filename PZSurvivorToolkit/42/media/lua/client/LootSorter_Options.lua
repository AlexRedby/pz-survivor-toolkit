-- LootSorter: in-game settings (Options -> Mods) for the search range and carry load.
-- Uses B42's native PZAPI.ModOptions -- auto-persists to ModOptions.ini and is rendered by the
-- vanilla options screen (MainOptions). Slider values are copied into LootSorter.MAX_TILES /
-- MAX_LEVELS / MAX_LOAD_FRACTION at the start of each sort, so changes take effect on the next
-- distribution.
LootSorter = LootSorter or {}
local CraftState = require "PZSurvivorToolkit/QuartermasterCraftState"

if PZAPI and PZAPI.ModOptions and not LootSorter._optionsAdded then
    LootSorter._optionsAdded = true
    local opt = PZAPI.ModOptions:create("LootSorter", "Quartermaster")
    opt:addSlider("maxTiles", "Walk range (tiles)", 5, 200, 5, LootSorter.MAX_TILES or 50,
        "How far the character will walk to reach a designated box.")
    opt:addSlider("maxLevels", "Floors up / down", 0, 20, 1, LootSorter.MAX_LEVELS or 3,
        "Also search this many floors above AND below the player (0 = current floor only).")
    -- These labels spell out "percent" because neither form of the symbol is safe on every build:
    -- 42.20.1+ formats them through getText, where a lone percent sign throws and blanks the main
    -- menu, while older builds do not format at all, so the doubled escape would show up verbatim.
    opt:addSlider("maxLoadPercent", "Max carry load (percent of capacity)", 50, 400, 1,
        math.floor((LootSorter.MAX_LOAD_FRACTION or 0.99) * 100),
        "How much of the character's max carry weight a haul trip will load up to. 100 percent is the normal safe limit. Above 100 percent intentionally overburdens the character to carry more per trip -- slower, and past ~150 percent takes ongoing HP damage while hauling (PZ's own Heavy Load moodle tiers: 100/125/150/175 percent). Default 99 percent: fill up almost to the safe limit, no overburden.")

    -- Fallback toggle for craft-from-boxes. The PRIMARY control is the "Storage" checkbox in the craft
    -- window; this covers the case where that checkbox isn't reachable/available (e.g. its widget hook
    -- was disabled after an error). Read separately from applyOptions() below -- see the note there.
    local craftOpt = opt:addTickBox("craftFromBoxes", "Craft from designated boxes",
        LootSorter.craftFromBoxes or false,
        "The character hauls a recipe's ingredients from your designated boxes, then crafts. It fetches everything the batch needs in one trip, so a large batch can leave you overburdened. Same as the Storage checkbox in the crafting menu.")

    -- copy current slider values into the live config
    function LootSorter.applyOptions()
        local o = PZAPI.ModOptions and PZAPI.ModOptions:getOptions("LootSorter")
        if not o then return end
        local t = o:getOption("maxTiles");  if t then LootSorter.MAX_TILES  = t:getValue() end
        local l = o:getOption("maxLevels"); if l then LootSorter.MAX_LEVELS = l:getValue() end
        local p = o:getOption("maxLoadPercent")
        if p then LootSorter.MAX_LOAD_FRACTION = p:getValue() / 100 end
    end

    -- craftFromBoxes is applied SEPARATELY (not in applyOptions): applyOptions runs at the start of
    -- every sort, and reading the tickbox there would overwrite the in-menu checkbox's live state.
    -- This runs only at game start and when the options screen is applied.
    function LootSorter.applyCraftOption()
        local o = PZAPI.ModOptions and PZAPI.ModOptions:getOptions("LootSorter")
        local c = o and o:getOption("craftFromBoxes")
        if c then CraftState.setEnabled(c:getValue()) end
    end
    -- MainOptions calls onChangeApply BEFORE it writes the new value into option.value, so use the
    -- value it passes here. Re-reading getValue() would return the OLD value -- the option applied one
    -- step behind (enabling it in the options screen appeared to do nothing).
    craftOpt.onChangeApply = function(_opt, value)
        CraftState.setEnabled(value)
    end

    -- Load persisted values at session start. MainOptions only calls :load() when its panel is
    -- opened, so without this a saved setting wouldn't apply until you visited the options screen.
    Events.OnGameStart.Add(function()
        pcall(function() PZAPI.ModOptions:load() end)
        LootSorter.applyOptions()
        LootSorter.applyCraftOption()
    end)
end
