require "PZSurvivorWishlist"
require "ISUI/ISButton"
require "ISUI/ISContextMenu"
require "Entity/ISUI/CraftRecipe/ISCraftRecipePanel"
require "Entity/ISUI/CraftRecipe/ISWidgetInput"
require "Entity/ISUI/BuildRecipe/ISBuildRecipePanel"

local W = PZSurvivorWishlist
local Crafting = {}
W.Crafting = Crafting

local function enabled()
    return W.Settings.craftingEnabled()
end

local function validType(fullType)
    return type(fullType) == "string" and #fullType <= 128 and fullType:match("^[^%s%.]+%.[^%s]+$") ~= nil
end

local function listEach(list, callback)
    if not list then return end
    for i = 0, list:size() - 1 do callback(list:get(i)) end
end

local function choicesFor(list, amount, note)
    local choices, seen = {}, {}
    listEach(list, function(item)
        local fullType = item:getFullName()
        if validType(fullType) and not seen[fullType] then
            local count = amount(item, fullType)
            if count > 0 then
                choices[#choices + 1] = { fullType = fullType, amount = math.ceil(count),
                    name = item:getDisplayName(), note = note and note(item) }
                seen[fullType] = true
            end
        end
    end)
    return choices
end

-- getInputCount returns uses for drainables, so subtract only item-count inputs.
-- Applied ScriptItems retain the per-type scale used by the native recipe engine.
local function appliedUnits(logic, input, fullType)
    local units = 0
    listEach(logic:getSatisfiedInputItems(input), function(item)
        local appliedType = item:getFullName()
        if (not input:isExclusive() or appliedType == fullType) and not input:isUsesPartialItem(item) then
            local scale = input:getRelativeScale(appliedType)
            if scale and scale > 0 then units = units + 1 / scale end
        end
    end)
    return units
end

function Crafting.inputChoices(logic, input, force)
    if not logic or not input or input:isAutomationOnly() or input:getResourceType() ~= ResourceType.Item
            or input:isAcceptsAnyItem() or (not force and logic:isInputSatisfied(input)) then return {} end
    local fluidContainer = input:hasConsumeFromItem()
    if fluidContainer and not force and logic:getSatisfiedInputItems(input):size() > 0 then return {} end
    return choicesFor(input:getPossibleInputItems(), function(item, fullType)
        -- Fluids and uses cannot be converted to a guaranteed number of containers/items.
        if fluidContainer or input:isUsesPartialItem(item) then return 1 end
        local amount = input:getAmount(fullType)
        if not force then amount = amount - appliedUnits(logic, input, fullType) * input:getRelativeScale(fullType) end
        return math.max(0, amount)
    end, function(item)
        if fluidContainer then return "UI_PZSW_OneContainer" end
        if input:isUsesPartialItem(item) then return "UI_PZSW_OneUsableItem" end
    end)
end

function Crafting.missing(logic)
    local groups = {}
    local recipe = logic and logic:getRecipe()
    if not recipe then return groups end
    listEach(recipe:getInputs(), function(input)
        local choices = Crafting.inputChoices(logic, input, false)
        if #choices > 0 then groups[#groups + 1] = choices end
    end)
    return groups
end

function Crafting.results(logic)
    local results, seen = {}, {}
    local recipe = logic and logic:getRecipe()
    if not recipe then return results end
    local function output(script)
        if not script or seen[script] or script:isAutomationOnly() then return end
        seen[script] = true
        output(script:getCreateToItemScript())
        if script:getResourceType() ~= ResourceType.Item then return end
        local uses = script:isCreateUses()
        local amount = script:getAmount()
        if script:isVariableAmount() then
            amount = math.min(amount * logic:getVariableInputRatio(), script:getMaxAmount())
        end
        local choices = choicesFor(script:getPossibleResultItems(), function() return uses and 1 or amount end,
            function() return uses and "UI_PZSW_OneUsableItem" or nil end)
        if #choices > 0 then results[#results + 1] = choices end
    end
    listEach(recipe:getOutputs(), output)
    listEach(recipe:getInputs(), function(input)
        if not input:isAutomationOnly() and not input:isKeep() then output(input:getCreateToItemScript()) end
    end)
    return results
end

local function label(choice)
    local text = getText("UI_PZSW_ItemCount", choice.name or choice.fullType, choice.amount)
    if choice.note then text = text .. " (" .. getText(choice.note) .. ")" end
    return text
end

local function submit(playerNum, entries)
    if not enabled() or #entries == 0 then return end
    local clean = {}
    for _, entry in ipairs(entries) do clean[#clean + 1] = { fullType = entry.fullType, amount = entry.amount } end
    W.Client.addItems(playerNum, clean)
end

-- Commit a batch only after each ambiguous input has one explicit choice.
function Crafting.choose(playerNum, groups, entries, index)
    if not enabled() then return end
    entries, index = entries or {}, index or 1
    while groups[index] and #groups[index] == 1 do
        entries[#entries + 1] = groups[index][1]
        index = index + 1
    end
    if not groups[index] then submit(playerNum, entries); return end
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    local heading = context:addOption(getText("UI_PZSW_ChooseIngredient"), nil, nil)
    heading.notAvailable = true
    for _, choice in ipairs(groups[index]) do
        context:addOption(label(choice), playerNum, function(num, selected)
            entries[#entries + 1] = selected
            Crafting.choose(num, groups, entries, index + 1)
        end, choice)
    end
    return context
end

function Crafting.openMenu(panel)
    if not enabled() or not panel.player then return end
    local playerNum = panel.player:getPlayerNum()
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    for _, group in ipairs(Crafting.results(panel.logic)) do
        for _, choice in ipairs(group) do
            context:addOption(getText("UI_PZSW_AddResult") .. ": " .. label(choice), playerNum,
                function(num, selected) submit(num, { selected }) end, choice)
        end
    end
    local groups = Crafting.missing(panel.logic)
    local missing = context:addOption(getText("UI_PZSW_AddMissing"), playerNum, Crafting.choose, groups)
    missing.notAvailable = #groups == 0
    context:addOption(getText("UI_PZSW_Open"), playerNum, W.Client.open)
    return context
end

function Crafting.openInput(widget)
    if not enabled() or widget.displayAsOutput or not widget.player then return end
    local choices = Crafting.inputChoices(widget.logic, widget.inputScript, true)
    if #choices == 0 then return end
    local context = ISContextMenu.get(widget.player:getPlayerNum(), getMouseX(), getMouseY())
    for _, choice in ipairs(choices) do
        context:addOption(getText("UI_PZSW_AddIngredient") .. ": " .. label(choice), widget.player:getPlayerNum(),
            function(num, selected) submit(num, { selected }) end, choice)
    end
    return context
end

local function buttonHeight()
    return getTextManager():getFontHeight(UIFont.Small) + 8
end

local function newButton(panel)
    local button = ISButton:new(0, 0, 10, buttonHeight(), getText("UI_PZSW_CraftWishlist"), panel, Crafting.openMenu)
    button:initialise()
    button:instantiate()
    button.font = UIFont.Small
    local original = button.prerender
    button.prerender = function(self)
        self:setEnable(enabled() and panel.logic and panel.logic:getRecipe() ~= nil)
        local list = W.Client.selected(panel.player:getPlayerNum())
        self.tooltip = list and getText("UI_PZSW_AddTo", list.owner) or getText("UI_PZSW_Open")
        original(self)
    end
    button:setVisible(enabled())
    panel.pzswEnabled = enabled()
    panel.pzswButton = button
    return button
end

local function tableButton(panel, tableLayout)
    if not panel.player or not panel.logic then return end
    if panel.rootTable and not panel.logic:getRecipe() then panel.pzswButton = nil; return end
    local button = newButton(panel)
    local row = tableLayout:addRow()
    row:setVisible(enabled(), true)
    button.pzswRow = row
    tableLayout:setElement(0, row:index(), button)
    if panel.xuiRecalculateLayout then panel:xuiRecalculateLayout() end
end

local function ncButton(panel)
    if panel.pzswButton then return end
    panel:addChild(newButton(panel))
end

local function ncLayout(panel, width, height)
    local button = panel.pzswButton
    if button then
        button:setX(0)
        button:setY(height - buttonHeight())
        button:setWidth(width)
    end
end

local function cookLayout(panel)
    local reserve = enabled() and buttonHeight() + 4 or 0
    local delta = reserve - (panel.pzswReserve or 0)
    panel.pzswReserve = reserve
    local inputs = panel.craftInputPanel
    inputs:setHeight(inputs.height - delta)
    inputs.scrollPanel:setHeight(inputs.scrollPanel.height - delta)
    for _, child in ipairs({ panel.recipeInfoPanel, panel.craftoutputPanel, panel.craftActionPanel }) do
        child:setY(child.y - delta)
    end
    local button = panel.pzswButton
    button:setX(panel.rightAreaX)
    button:setY(panel.craftoutputPanel.y + panel.craftoutputPanel.height + 4)
    button:setWidth(panel.craftActionPanel.x + panel.craftActionPanel.width - panel.rightAreaX)
end

local function cookButton(panel)
    if panel.pzswButton or not panel.craftInputPanel then return end
    if panel.craftInputPanel.height <= (buttonHeight() + 4) * 2 then return end
    panel:addChild(newButton(panel))
    cookLayout(panel)
end

local function refreshButton(panel)
    local button, active = panel.pzswButton, enabled()
    if not button or panel.pzswEnabled == active then return end
    panel.pzswEnabled = active
    button:setVisible(active)
    if button.pzswRow then button.pzswRow:setVisible(active, true) end
    if panel.craftInputPanel and panel.craftInputPanel.scrollPanel then
        cookLayout(panel)
    elseif panel.rootTable then
        panel:xuiRecalculateLayout()
    elseif panel.calculateLayout then
        panel:calculateLayout(panel.width, panel.height)
    end
end

local function pack(...) return { n = select("#", ...), ... } end
local hooked = setmetatable({}, { __mode = "k" })
local reported = {}
local function after(class, method, callback)
    if not class or hooked[class] and hooked[class][method] then return end
    local original = class[method]
    if type(original) ~= "function" then return end
    hooked[class] = hooked[class] or {}
    hooked[class][method] = true
    class[method] = function(self, ...)
        local result = pack(original(self, ...))
        local ok, error = pcall(callback, self, ...)
        if not ok and not reported[method] then
            reported[method] = true
            print("[PZSurvivorWishlist] crafting " .. method .. ": " .. tostring(error))
        end
        return unpack(result, 1, result.n)
    end
end

local function inputHooks(class)
    local function click(widget)
        local now = getTimestampMs()
        if widget.pzswMenuAt and now - widget.pzswMenuAt < 100 then return end
        widget.pzswMenuAt = now
        Crafting.openInput(widget)
    end
    after(class, "onRightMouseUp", click)
    after(class, "onRightMouseUpOutside", function(widget)
        if widget:isMouseOver() then click(widget) end
    end)
end

-- Project Cook evolved food already uses the inventory menu for actual ingredients.
-- Append its explicit result to that same menu without changing selection/actions.
local function evolvedResult(slot)
    if not enabled() or not slot.EvoPanel then return end
    local panel = slot.EvoPanel
    local recipe, base = panel:getRecipe(), panel:getBaseItem()
    if not recipe or not base then return end
    local fullType = recipe:getResultItem()
    if type(fullType) ~= "string" then return end
    if not fullType:find(".", 1, true) then fullType = base:getModule() .. "." .. fullType end
    if not validType(fullType) then return end
    local item = ScriptManager.instance:getItem(fullType)
    if not item then return end
    local context = getPlayerContextMenu(panel.player:getPlayerNum())
    if context then
        context:addOption(getText("UI_PZSW_AddResult") .. ": " .. item:getDisplayName(), panel.player:getPlayerNum(),
            function(num) submit(num, { { fullType = fullType, amount = 1 } }) end)
    end
end

function Crafting.install()
    for _, class in ipairs({ ISCraftRecipePanel, ISBuildRecipePanel }) do
        after(class, "createDynamicChildren", function(panel) tableButton(panel, panel.rootTable) end)
    end
    inputHooks(ISWidgetInput)
    inputHooks(NC_CraftInput_Slot)
    inputHooks(NB_BuildingInput_Slot)
    inputHooks(PJCK_CraftInput_Slot)
    after(NC_CellBaseCraft, "createChildren", ncButton)
    -- Reserve a row from NC's scrollable input area; its other controls keep their sizes.
    if NC_CellBaseCraft and not NC_CellBaseCraft.pzswLayoutWrapped then
        local original = NC_CellBaseCraft.layoutChildren
        if type(original) == "function" then
            NC_CellBaseCraft.pzswLayoutWrapped = true
            NC_CellBaseCraft.layoutChildren = function(panel, width, height)
                local reserve = panel.pzswButton and enabled() and buttonHeight() + 4 or 0
                local result = pack(original(panel, width, height - reserve))
                ncLayout(panel, width, height)
                return unpack(result, 1, result.n)
            end
        end
    end
    after(NB_BuildingInfoPanel, "createChildren", function(panel) tableButton(panel, panel) end)
    after(PJCK_HandCraftPanel, "createChildren", cookButton)
    -- Project Cook loads its handcraft classes lazily when that tab is first opened.
    after(PJCK_Window, "createHandCraftPanel", function(window)
        Crafting.install()
        if window.HandCraftPanel and window.HandCraftPanel.logic then cookButton(window.HandCraftPanel) end
    end)
    after(PJCK_ItemSlot, "showItemContextMenu", evolvedResult)
    after(PJCK_BaseItemSlot, "showBaseItemActionMenu", evolvedResult)
    for _, class in pairs({ ISCraftRecipePanel, ISBuildRecipePanel, NC_CellBaseCraft, NB_BuildingInfoPanel, PJCK_HandCraftPanel }) do
        after(class, "prerender", refreshButton)
    end
end

Events.OnGameStart.Add(Crafting.install)
return Crafting
