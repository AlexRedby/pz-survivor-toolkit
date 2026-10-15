require "PZSurvivorToolkit/Settings"
local Planner = require "PZSurvivorToolkit/CraftPlanner"
local Recipes = require "PZSurvivorToolkit/CraftChainRecipes"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISInventoryItem"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
require "ISUI/ISContextMenu"
require "Entity/ISUI/CraftRecipe/ISCraftRecipePanel"

local Chains = {}
PZSurvivorToolkit.CraftChains = Chains
local Settings = PZSurvivorToolkit.Settings
local View = ISPanel:derive("PZSTCraftPlanView")
local views = {}
local function text(id, ...) return getText("UI_PZST_CraftChain" .. id, ...) end
local function height() return math.max(26, getTextManager():getFontHeight(UIFont.Small) + 8) end
local function plain(value) return tostring(value):gsub("[<>]", "") end
local function itemName(fullType)
    local item = getScriptManager():getItem(fullType)
    return item and item:getDisplayName() or fullType, item
end
local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function samePlan(first, second)
    if not first or not second or first.target ~= second.target or first.count ~= second.count
        or #first.steps ~= #second.steps then return false end
    for i, step in ipairs(first.steps) do
        local other = second.steps[i]
        if step.recipe.id ~= other.recipe.id then return false end
        for key, choice in pairs(step.inputs) do
            local nextChoice = other.inputs[key]
            if not nextChoice or choice.fullType ~= nextChoice.fullType or choice.amount ~= nextChoice.amount then return false end
            local ids, nextIds = {}, {}
            for _, id in ipairs(choice.resourceIds) do ids[id] = true end
            for _, id in ipairs(nextChoice.resourceIds) do nextIds[id] = true end
            for id in pairs(ids) do if not nextIds[id] then return false end end
            for id in pairs(nextIds) do if not ids[id] then return false end end
        end
        for key in pairs(other.inputs) do if not step.inputs[key] then return false end end
    end
    for key, count in pairs(first.consumed) do if second.consumed[key] ~= count then return false end end
    for key in pairs(second.consumed) do if not first.consumed[key] then return false end end
    return true
end

local function fit(value, width)
    if getTextManager():MeasureStringX(UIFont.Small, value) <= width then return value end
    while #value > 0 do
        local index = #value
        while index > 1 and value:byte(index) >= 128 and value:byte(index) < 192 do index = index - 1 end
        value = value:sub(1, index - 1)
        if getTextManager():MeasureStringX(UIFont.Small, value .. "...") <= width then return value .. "..." end
    end
    return ""
end

local function wrap(value, width)
    local lines, line = {}, ""
    for word in value:gmatch("%S+") do
        local candidate = line == "" and word or line .. " " .. word
        if line ~= "" and getTextManager():MeasureStringX(UIFont.Small, candidate) > width then
            lines[#lines + 1], line = line, word
        else line = candidate end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function patch(ui, name, x, y, width, h, shade, alpha)
    if not ui.neat then return false end
    local texture = NinePatchTexture.getSharedTexture("media/ui/Neat_Crafting/" .. name .. ".png")
    if not texture then return false end
    texture:render(ui:getAbsoluteX() + x, ui:getAbsoluteY() + y + ui:getYScroll(), width, h,
        shade, shade, shade, alpha)
    return true
end

local function drawRow(list, y, item)
    local row, h = item.item, item.height
    if y + list:getYScroll() + h < 0 or y + list:getYScroll() >= list.height then return y + h end
    local width, fh = list.width - 18, getTextManager():getFontHeight(UIFont.Small)
    if row.kind == "section" then
        if not patch(list, "Panel/InnerTitle_BG", 0, y, width, h - 3, 0.2, 0.9) then
            list:drawRect(0, y, width, h - 3, 0.8, 0.16, 0.16, 0.16)
        end
        list:drawText(fit(row.name, width - 12), 6, y + 5, 0.85, 0.85, 0.85, 1, UIFont.Small)
    elseif row.kind == "notice" then
        for i, line in ipairs(row.lines) do
            list:drawText(fit(line, width - 12), 6, y + 4 + (i - 1) * fh, 0.95, 0.76, 0.44, 1, UIFont.Small)
        end
    else
        local iconSize = math.min(34, h - 12)
        local alpha = list.neat and NC_UserConfig.getSlotAlpha(0.8) or 0.8
        if not patch(list, "Button/SlotBG_IconSide", 0, y, h - 4, h - 4, 0.15, alpha) then
            list:drawRect(0, y, width, h - 4, alpha, 0.13, 0.13, 0.13)
        end
        patch(list, "Button/SlotBG_LEFT", h - 4, y, width - h + 4, h - 4, 0.15, alpha)
        patch(list, "Button/SlotBoarder", 0, y, width, h - 4, 0.24, alpha)
        if row.script then ISInventoryItem.renderScriptItemIcon(list, row.script, 4, y + 4, 1, iconSize, iconSize) end
        local x, right = 42, width - 7
        local count = row.amount and ("x" .. row.amount) or ""
        local name = row.step and (row.step .. ". " .. row.name) or row.name
        list:drawText(fit(name, right - x - getTextManager():MeasureStringX(UIFont.Small, count) - 7),
            x, y + 5, 0.95, 0.95, 0.95, 1, UIFont.Small)
        list:drawTextRight(count, right, y + 5, 0.55, 0.9, 0.5, 1, UIFont.Small)
        list:drawText(fit(row.detail or "", right - x), x, y + fh + 7, 0.68, 0.68, 0.68, 1, UIFont.Small)
        if row.kind == "input" then
            list:drawText(fit(row.mode .. " - " .. text("Choose"), right - x), x, y + fh * 2 + 9,
                0.75, 0.84, 0.94, 1, UIFont.Small)
        end
    end
    return y + h
end

local function hideListTooltip(list)
    if list.tooltipUI then list.tooltipUI:setVisible(false); list.tooltipUI:removeFromUIManager() end
end

function View:createChildren()
    local h = height()
    local function button(label, callback)
        local control = ISButton:new(0, 0, 100, h, label, self, callback)
        control:initialise(); control:instantiate(); self:addChild(control)
        return control
    end
    self.back = button(self.cell and text("Back") or getText("UI_btn_close"), View.close)
    self.quantity = ISTextEntryBox:new("1", 0, 0, 44, h)
    self.quantity:initialise(); self.quantity:instantiate()
    self.quantity:setOnlyNumbers(true)
    self.quantity:setTooltip(text("Quantity"))
    self:addChild(self.quantity)
    self.recalculate = button(text("Recalculate"), View.refresh)
    self.preview = ISScrollingListBox:new(0, 0, 100, 100)
    self.preview:initialise(); self.preview:instantiate()
    -- Keep the scrollbar inside this manually sized viewport.
    self.preview.vscroll:setAnchorLeft(true); self.preview.vscroll:setAnchorRight(false)
    self.preview.vscroll:setAnchorTop(true); self.preview.vscroll:setAnchorBottom(false)
    self.preview.neat, self.preview.font, self.preview.selected = self.cell ~= nil, UIFont.Small, 0
    self.preview.backgroundColor = {r=0, g=0, b=0, a=0}
    self.preview.doDrawItem = drawRow
    self.preview:setOnMouseDownFunction(self, View.openChoices)
    self:addChild(self.preview)
    self.start = button(text("Start"), View.startPlan)
    self.start.tooltip = text("Explanation")
    self:layout(self.width, self.height)
    self:refresh()
end

function View:layout(width, panelHeight)
    self:setWidth(width); self:setHeight(panelHeight)
    local h, gap = height(), 4
    self.back:setX(gap); self.back:setY(gap); self.back:setWidth(math.max(88,
        getTextManager():MeasureStringX(UIFont.Small, self.back.title) + 16))
    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, text("Runs")) + 12
    self.quantity:setX(labelWidth); self.quantity:setY(h + 8); self.quantity:setHeight(h)
    self.recalculate:setX(labelWidth + 48); self.recalculate:setY(h + 8)
    self.recalculate:setWidth(math.max(50, width - labelWidth - 52))
    self.preview:setX(gap); self.preview:setY(h * 2 + 14)
    self.preview:setWidth(width - gap * 2); self.preview:setHeight(math.max(20, panelHeight - h * 3 - 22))
    self.preview.vscroll:setX(self.preview.width - self.preview.vscroll.width)
    self.preview.vscroll:setHeight(self.preview.height)
    self.start:setX(gap); self.start:setY(panelHeight - h - gap); self.start:setWidth(width - gap * 2)
    self:layoutRows()
end

function View:layoutRows()
    local fh = getTextManager():getFontHeight(UIFont.Small)
    for _, item in ipairs(self.preview.items) do
        local row = item.item
        if row.kind == "notice" then row.lines = wrap(row.name, self.preview.width - 30) end
        item.height = row.kind == "section" and fh + 14
            or row.kind == "notice" and #row.lines * fh + 12
            or row.kind == "input" and math.max(58, fh * 3 + 18) or math.max(46, fh * 2 + 16)
    end
end

function View:live()
    return not self.closed and Settings.craftChains() and getSpecificPlayer(self.player:getPlayerNum()) == self.player
        and not self.player:isDead() and not self.player:isAsleep()
end

function View:build()
    if not self:live() or self.panel.logic:getRecipe() ~= self.target then return nil, text("Unavailable") end
    local count = tonumber(self.quantity:getText())
    if not count or count ~= math.floor(count) or count < 1 or count > 100 then return nil, text("quantity") end
    local model, target, context = Recipes.collect(self.panel, self.overrides)
    if not model then return nil, target end
    self.model, self.targetId = model, target
    local plan, reason, missing = Planner.plan(model, target, count)
    if not plan then return nil, text(reason, missing and itemName(missing) or "") end
    return plan, context
end

function View:showPlan(plan, context, notice)
    self.plan, self.context = plan, context
    if plan then self.lastPlan = plan end
    self.plannedQuantity = self.quantity:getText()
    hideListTooltip(self.preview)
    self:closeChoices()
    self.preview:clear()
    local function add(row)
        self.preview:addItem(row.name, row, plain(row.name) .. (row.amount and (" x" .. row.amount) or "")
            .. (row.detail and (" <LINE> " .. plain(row.detail)) or ""))
    end
    local function section(name) add({kind="section", name=name}) end
    local function item(kind, fullType, amount, detail)
        local name, script = itemName(fullType)
        add({kind=kind, fullType=fullType, amount=amount, name=name, script=script, detail=detail})
    end
    if notice then add({kind="notice", name=notice}) end
    if plan then
        local target = plan.steps[#plan.steps].recipe
        section(text("Result"))
        for _, fullType in ipairs(sortedKeys(target.outputs)) do
            item("output", fullType, target.outputs[fullType] * plan.count, text("FinalResult"))
        end
        section(text("Materials"))
        for _, fullType in ipairs(sortedKeys(plan.consumed)) do
            item("material", fullType, plan.consumed[fullType], text("Consumed"))
        end
        local tools = {}
        for _, step in ipairs(plan.steps) do
            local perStep = {}
            for _, input in ipairs(step.recipe.inputs) do
                if input.keep then
                    local choice = step.inputs[input.index]
                    perStep[choice.fullType] = (perStep[choice.fullType] or 0) + choice.amount
                end
            end
            for fullType, amount in pairs(perStep) do tools[fullType] = math.max(tools[fullType] or 0, amount) end
        end
        if #sortedKeys(tools) > 0 then
            section(text("Tools"))
            for _, fullType in ipairs(sortedKeys(tools)) do item("tool", fullType, tools[fullType], text("Retained")) end
        end
        section(text("Steps", #plan.steps))
        for i, step in ipairs(plan.steps) do
            local results, inputNames = {}, {}
            local types = sortedKeys(step.recipe.outputs)
            for _, fullType in ipairs(types) do results[#results + 1] = step.recipe.outputs[fullType] .. " x " .. itemName(fullType) end
            for _, input in ipairs(step.recipe.inputs) do
                local choice = step.inputs[input.index]
                inputNames[#inputNames + 1] = choice.amount .. " x " .. itemName(choice.fullType)
            end
            local _, script = itemName(types[1])
            local row = {kind="step", step=i, name=step.recipe.name, script=script, detail=table.concat(results, ", ")}
            self.preview:addItem(row.name, row, plain(row.name) .. " <LINE> " .. plain(text("StepInputs") .. ": "
                .. table.concat(inputNames, ", ")) .. " <LINE> " .. plain(text("Result") .. ": " .. row.detail))
            self:addInputs(step.recipe, step.inputs)
        end
    elseif self.model then
        section(text("AdjustChoices"))
        local seen = {}
        local function inputs(recipe)
            if not recipe or seen[recipe.id] then return end
            seen[recipe.id] = true
            section(recipe.name)
            self:addInputs(recipe)
        end
        for _, step in ipairs(self.lastPlan and self.lastPlan.steps or {}) do inputs(self.model.recipes[step.recipe.id]) end
        inputs(self.model.recipes[self.targetId])
    end
    self:layoutRows()
    self.preview:setYScroll(0)
    self.start:setEnable(plan ~= nil)
end

function View:available(input, fullType)
    local amount = 0
    for _, resource in ipairs(self.model and self.model.resources or {}) do
        if resource.fullType == fullType and self.model.accepts(input, resource) then amount = amount + 1 end
    end
    return amount
end

function View:addInputs(recipe, selected)
    for _, input in ipairs(recipe.inputs) do
        local choice = selected and selected[input.index] or input.choices[1]
        local name, script = itemName(choice.fullType)
        local detail = selected and text("Allocation", choice.amount, #choice.resourceIds, choice.generated)
            or text("Availability", choice.amount, self:available(input, choice.fullType))
        local row = {kind="input", recipeId=recipe.id, inputIndex=input.index, fullType=choice.fullType,
            name=name, script=script, amount=choice.amount, detail=detail,
            mode=input.preference and text("Selected") or text("Auto")}
        self.preview:addItem(name, row, plain(recipe.name) .. " <LINE> " .. plain(detail) .. " <LINE> "
            .. plain(input.keep and text("Retained") or text("Consumed")) .. " <LINE> " .. plain(text("ChoiceScope")))
    end
end

function View:closeChoices()
    local menu = self.choiceMenu
    if menu and menu.options[1] and menu.options[1].target == self then menu:hideAndChildren() end
    self.choiceMenu = nil
end

function View:selectInput(selection)
    if not self:live() or self.panel.logic:getRecipe() ~= self.target then return end
    local recipe = self.model and self.model.recipes[selection.recipeId]
    if not recipe then return end
    local valid = false
    for _, input in ipairs(recipe.inputs) do
        if input.index == selection.inputIndex then
            valid = selection.fullType == false
            for _, choice in ipairs(input.allChoices or input.choices) do
                if choice.fullType == selection.fullType then valid = true end
            end
        end
    end
    if not valid then return end
    self.overrides[recipe.id] = self.overrides[recipe.id] or {}
    self.overrides[recipe.id][selection.inputIndex] = selection.fullType
    if selection.fullType == false and recipe.id ~= self.targetId then
        self.overrides[recipe.id][selection.inputIndex] = nil
        local remaining = false
        for _ in pairs(self.overrides[recipe.id]) do remaining = true; break end
        if not remaining then self.overrides[recipe.id] = nil end
    end
    local scroll = self.preview:getYScroll()
    self:refresh()
    self.preview:setYScroll(scroll)
end

function View:openChoices(row)
    if row.kind ~= "input" or not self:live() or self.panel.logic:getRecipe() ~= self.target then return end
    local recipe = self.model and self.model.recipes[row.recipeId]
    if not recipe then return end
    local input
    for _, candidate in ipairs(recipe.inputs) do if candidate.index == row.inputIndex then input = candidate; break end end
    if not input then return end
    self:closeChoices()
    hideListTooltip(self.preview)
    local menu = ISContextMenu.get(self.player:getPlayerNum(), getMouseX(), getMouseY())
    self.choiceMenu = menu
    local function option(label, fullType, script)
        local result = menu:addOption(label, self, View.selectInput,
            {recipeId=recipe.id, inputIndex=input.index, fullType=fullType})
        if script then result.iconTexture = script:getNormalTexture() end
        menu:setOptionChecked(result, input.preference == (fullType or nil))
    end
    option(text("Auto"), false)
    local choices = {}
    for _, choice in ipairs(input.allChoices or input.choices) do
        local name, script = itemName(choice.fullType)
        choices[#choices + 1] = {choice=choice, name=name, script=script,
            available=self:available(input, choice.fullType)}
    end
    table.sort(choices, function(a, b)
        if (a.available > 0) ~= (b.available > 0) then return a.available > 0 end
        if a.name ~= b.name then return a.name < b.name end
        return a.choice.fullType < b.choice.fullType
    end)
    for _, candidate in ipairs(choices) do
        option(candidate.name .. " (" .. text("Availability", candidate.choice.amount, candidate.available) .. ")",
            candidate.choice.fullType, candidate.script)
    end
end

function View:refresh()
    local plan, context = self:build()
    self:showPlan(plan, plan and context or nil, not plan and context or nil)
end

function View:startPlan()
    local fresh, context = self:build()
    if not fresh then self:showPlan(nil, nil, context); return end
    if not samePlan(self.plan, fresh) then self:showPlan(fresh, context, text("ReviewChanged")); return end
    if Recipes.enqueue(self.player, fresh, context) then self:close() end
end

function View:prerender()
    if not self:live() or self.cell and self.panel.logic:getRecipe() ~= self.target then self:close(); return end
    self.start:setEnable(self.plan ~= nil and self.plannedQuantity == self.quantity:getText()
        and self.panel.logic:getRecipe() == self.target)
    if not patch(self, "Panel/ContentPanel_BG", 0, 0, self.width, self.height, 0.1,
        self.cell and NC_UserConfig.getInnerPanelAlpha(NCConfig.slotPanelBackgroundAlpha) or 1) then ISPanel.prerender(self) end
    local labelX = self.back.x + self.back.width + 8
    self:drawText(fit(text("Title"), self.width - labelX - 4), labelX, 8, 0.9, 0.9, 0.9, 1, UIFont.Small)
    self:drawText(text("Runs"), 4, height() + 12, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function View:close()
    if self.closed then return end
    self.closed = true
    self.quantity:unfocus()
    self:closeChoices()
    hideListTooltip(self.preview)
    self:setVisible(false)
    if self.cell then
        local cell = self.cell
        cell:removeChild(self)
        cell.pzstPlanView = nil
        for child, visible in pairs(self.hiddenChildren) do child:setVisible(visible) end
        cell.pzstPlanButton:setVisible(Settings.craftChains())
        cell:calculateLayout(cell.width, cell.height)
    elseif self.window then
        self.window:setVisible(false)
        self.window:removeFromUIManager()
    end
    self.plan, self.context, self.lastPlan, self.model, self.overrides = nil, nil, nil, nil, nil
    if views[self.player] == self then views[self.player] = nil end
end

local function closeOwner(panel)
    if not panel or not panel.logic then return end
    for _, view in pairs(views) do
        if view.panel.logic == panel.logic then view:close() end
    end
end

function Chains.open(panel)
    if not Settings.craftChains() or not panel or not panel.logic or not panel.logic:getRecipe() then return end
    local player = panel.logic:getPlayer()
    if views[player] then views[player]:close() end
    local cell = panel.cellBaseCraft or panel.HandCraftPanel and panel
    local view = View:new(0, 0, 100, 100)
    view.panel, view.player, view.target = panel, player, panel.logic:getRecipe()
    view.overrides = {}
    view.cell, view.neat = cell, cell ~= nil
    view.backgroundColor = {r=0.06, g=0.06, b=0.06, a=1}
    views[player] = view
    if cell then
        local handcraft = cell.HandCraftPanel
        handcraft.logic:setShowManualSelectInputs(false)
        handcraft.logic:setManualSelectInputScriptFilter(nil)
        handcraft:closeInputSwitchPanel(); handcraft:closeOutputSwitchPanel()
        local owner = handcraft.MainPanel
        if owner and not owner.setJoypadFocusElement then owner = owner.parent end
        if owner and owner.HandCraftPanel == handcraft and owner.setJoypadFocusElement then
            owner:setJoypadFocusElement(nil)
        end
        for _, group in ipairs({cell.craftInputPanel.inputItems, cell.craftResultPanel.craftoutputPanel.outputItems}) do
            for _, slot in ipairs(group) do if slot.removeTooltip then slot:removeTooltip() end end
        end
        view.hiddenChildren = {}
        for _, child in ipairs({cell.craftInputPanel, cell.recipeInfoPanel, cell.craftResultPanel}) do
            view.hiddenChildren[child] = child:getIsVisible()
            child:setVisible(false)
        end
        cell.pzstPlanView = view
        cell.pzstPlanButton:setVisible(false)
        view:initialise(); view:instantiate(); cell:addChild(view)
        cell:calculateLayout(cell.width, cell.height)
    else
        local width = math.min(600, getCore():getScreenWidth() - 24)
        local windowHeight = math.min(600, getCore():getScreenHeight() - 24)
        local window = ISCollapsableWindow:new((getCore():getScreenWidth() - width) / 2,
            (getCore():getScreenHeight() - windowHeight) / 2, width, windowHeight)
        window.title, window.resizable, window.backgroundColor = text("Title"), false, view.backgroundColor
        view.window = window
        window.close = function() view:close() end
        window:initialise(); window:instantiate()
        view:setX(8); view:setY(window:titleBarHeight() + 4)
        view:initialise(); view:instantiate(); window:addChild(view)
        view:layout(width - 16, windowHeight - view.y - 8)
        window:addToUIManager(); window:setVisible(true); window:bringToTop()
    end
    return view
end

local function newButton(panel)
    local button = ISButton:new(0, 0, 10, height(), text("Title"), panel, Chains.open)
    button:initialise(); button:instantiate()
    button.tooltip = text("ButtonTooltip")
    button:setVisible(Settings.craftChains())
    panel.pzstPlanButton, panel.pzstPlanEnabled = button, Settings.craftChains()
    return button
end

local hooked = {}
local function pack(...) return {n=select("#", ...), ...} end
local function after(class, method, callback)
    if not class or not class[method] then return end
    hooked[class] = hooked[class] or {}
    if hooked[class][method] then return end
    hooked[class][method] = true
    local original = class[method]
    class[method] = function(self, ...)
        local result = pack(original(self, ...))
        callback(self, ...)
        return unpack(result, 1, result.n)
    end
end

function Chains.install()
    after(ISHandCraftPanel, "OnCloseWindow", closeOwner)
    after(ISCraftRecipePanel, "createDynamicChildren", function(panel)
        panel.pzstPlanButton = nil
        if not panel.logic or not panel.logic:getRecipe() then return end
        local button, row = newButton(panel), panel.rootTable:addRow()
        button.pzstRow = row
        row:setVisible(Settings.craftChains(), true)
        panel.rootTable:setElement(0, row:index(), button)
        panel:xuiRecalculateLayout()
    end)
    after(NC_CellBaseCraft, "createChildren", function(panel) panel:addChild(newButton(panel)) end)
    if NC_CellBaseCraft and not NC_CellBaseCraft.pzstPlanLayout then
        local original = NC_CellBaseCraft.layoutChildren
        NC_CellBaseCraft.pzstPlanLayout = true
        NC_CellBaseCraft.layoutChildren = function(panel, width, panelHeight)
            local button, view = panel.pzstPlanButton, panel.pzstPlanView
            local reserve = button and Settings.craftChains() and not view and height() + 4 or 0
            local result = pack(original(panel, width, panelHeight - reserve))
            if button then button:setX(0); button:setY(panelHeight - height()); button:setWidth(width) end
            if view then view:layout(width, panelHeight) end
            return unpack(result, 1, result.n)
        end
    end
    after(NC_HandCraftPanel, "onLogicRecipeChanged", function(panel)
        local view = panel.cellBaseCraft and panel.cellBaseCraft.pzstPlanView
        if view and view.target ~= panel.logic:getRecipe() then view:close() end
    end)
    for _, class in pairs({NC_HandcraftWindow, NC_EntityWindow}) do
      after(class, "close", function(window) closeOwner(window.HandCraftPanel) end)
      if not class.pzstPlanInputGuard then
        class.pzstPlanInputGuard = true
        -- Neat's input/output navigation otherwise still exposes hidden native slots.
        for _, method in ipairs({"getJoypadInputEntries", "getJoypadOutputEntries"}) do
            local original = class[method]
            if original then
                class[method] = function(window, ...)
                    local cell = window.HandCraftPanel and window.HandCraftPanel.cellBaseCraft
                    if cell and cell.pzstPlanView then return {} end
                    return original(window, ...)
                end
            end
        end
        local original = class.onJoypadDown
        if original then
            class.onJoypadDown = function(window, button, ...)
                local cell = window.HandCraftPanel and window.HandCraftPanel.cellBaseCraft
                if cell and cell.pzstPlanView and button == Joypad.BButton then
                    cell.pzstPlanView:close(); return
                end
                return original(window, button, ...)
            end
        end
      end
    end
    for _, class in pairs({ISCraftRecipePanel, NC_CellBaseCraft}) do
        after(class, "prerender", function(panel)
            local button, enabled = panel.pzstPlanButton, Settings.craftChains()
            if not button then return end
            if panel.pzstPlanView and not enabled then panel.pzstPlanView:close() end
            button:setEnable(enabled and panel.logic and panel.logic:getRecipe() ~= nil)
            if panel.pzstPlanEnabled == enabled then return end
            panel.pzstPlanEnabled = enabled
            button:setVisible(enabled and not panel.pzstPlanView)
            if button.pzstRow then
                button.pzstRow:setVisible(enabled, true)
                panel:xuiRecalculateLayout()
            else panel:calculateLayout(panel.width, panel.height) end
        end)
    end
end

local function closeViews(player)
    for owner, view in pairs(views) do
        if not player or owner == player then view:close() end
    end
end

Events.OnGameStart.Add(Chains.install)
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() closeViews() end) end
if Events.OnGameExit then Events.OnGameExit.Add(function() closeViews() end) end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(closeViews) end
return Chains
