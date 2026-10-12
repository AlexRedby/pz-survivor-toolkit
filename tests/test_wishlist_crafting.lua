local path = ProjectRoot .. "/PZSurvivorWishlist/42/media/lua/client/PZSurvivorWishlist/Crafting.lua"
local tests = 0
local function check(value, message) assert(value, message); tests = tests + 1 end
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local function item(fullType, uses)
    return { getFullName = function() return fullType end, getDisplayName = function() return fullType end, uses = uses }
end
local function input(items, amount, options)
    options = options or {}
    return {
        isAutomationOnly = function() return options.automated end,
        getResourceType = function() return options.resource or "item" end,
        isAcceptsAnyItem = function() return options.any end,
        hasConsumeFromItem = function() return options.fluidContainer end,
        isUsesPartialItem = function(_, it) return it.uses == true end,
        isExclusive = function() return options.exclusive == true end,
        isKeep = function() return options.keep == true end,
        getPossibleInputItems = function() return list(items) end,
        getAmount = function(_, fullType) return options.amounts and options.amounts[fullType] or amount end,
        getRelativeScale = function(_, fullType) return options.amounts and options.amounts[fullType] / amount or 1 end,
        getCreateToItemScript = function() return options.create end,
    }
end
local function output(items, amount, options)
    options = options or {}
    return {
        isAutomationOnly = function() return options.automated end,
        getResourceType = function() return options.resource or "item" end,
        isCreateUses = function() return options.uses end,
        isVariableAmount = function() return options.variable end,
        getAmount = function() return amount end,
        getMaxAmount = function() return options.max or amount end,
        getPossibleResultItems = function() return list(items) end,
        getCreateToItemScript = function() return options.create end,
    }
end
local function logic(inputs, outputs)
    local recipe = { getInputs = function() return list(inputs) end, getOutputs = function() return list(outputs or {}) end }
    return { getRecipe = function() return recipe end, getSatisfiedInputItems = function(_, it) return list(it.applied or {}) end,
        isInputSatisfied = function(_, it) return it.satisfied == true end, getVariableInputRatio = function() return 2 end }
end

local enabled, sent, menus, now = true, {}, {}, 1000
PZSurvivorWishlist = { Settings = { craftingEnabled = function() return enabled end },
    Client = { addItems = function(num, entries) sent[#sent + 1] = { num = num, entries = entries } end,
        selected = function() return { owner = "Survivor" } end, open = function() end } }
require = function() end
ResourceType = { Item = "item" }
getText = function(key, ...) return key .. ":" .. table.concat({ ... }, ",") end
UIFont = { Small = 1 }
getTextManager = function() return { getFontHeight = function() return 12 end } end
getTimestampMs = function() return now end
getMouseX, getMouseY = function() return 10 end, function() return 20 end
local event
Events = { OnGameStart = { Add = function(callback) event = callback end } }
ISContextMenu = { get = function(num)
    local context = { playerNum = num, options = {} }
    function context:addOption(text, target, callback, argument)
        local option = { text = text, target = target, callback = callback, argument = argument }
        self.options[#self.options + 1] = option
        return option
    end
    menus[#menus + 1] = context
    return context
end }
getPlayerContextMenu = function() return menus[#menus] end
local function click(option) return option.callback(option.target, option.argument) end
local methods = {}
for _, name in ipairs({ "X", "Y", "Width", "Height", "Visible", "Enable" }) do
    methods["set" .. name] = function(self, value) self[name:lower()] = value end
end
ISButton = { new = function(_, x, y, width, height, title, target, callback)
    local button = { x = x, y = y, width = width, height = height, title = title, target = target, onclick = callback,
        initialise = function() end, instantiate = function() end, prerender = function() end }
    return setmetatable(button, { __index = methods })
end }
local function tableLayout()
    local t = { rows = 0, elements = {} }
    function t:addRow()
        self.rows = self.rows + 1
        return { index = function() return self.rows - 1 end, setVisible = function(self, value) self.visible = value end }
    end
    function t:setElement(_, row, value) self.elements[row] = value end
    return t
end
local player = { getPlayerNum = function() return 1 end }
local called = 0
ISCraftRecipePanel = { createDynamicChildren = function(self)
    called = called + 1; self.rootTable = tableLayout(); return "recipe", nil, 7
end, prerender = function() end }
ISBuildRecipePanel = { createDynamicChildren = ISCraftRecipePanel.createDynamicChildren, prerender = function() end }
ISWidgetInput = { onRightMouseUp = function() called = called + 1; return "click", nil, 9 end,
    onRightMouseUpOutside = function() return "outside" end }
NC_CraftInput_Slot, NB_BuildingInput_Slot, PJCK_CraftInput_Slot = nil, nil, nil
NC_CellBaseCraft, NB_BuildingInfoPanel, PJCK_HandCraftPanel, PJCK_ItemSlot, PJCK_BaseItemSlot = nil, nil, nil, nil, nil
local C = dofile(path)
event()
check(C == PZSurvivorWishlist.Crafting, "module is exported and installs without optional mods")
local nails, boards, branch, tape = item("Base.Nails"), item("Base.Plank"), item("Base.Branch"), item("Base.Tape", true)
local inp = input({ nails }, 4)
local l = logic({ inp })
inp.applied = { nails, nails }
check(C.inputChoices(l, inp, false)[1].amount == 2, "missing count subtracts accessible applied items")
check(C.inputChoices(l, inp, true)[1].amount == 4, "RMB adds the full requested ingredient count")
inp.satisfied = true
check(#C.missing(l) == 0, "satisfied inputs are not wished")
inp.satisfied = false
local alternatives = input({ boards, branch }, 1, { amounts = { ["Base.Plank"] = 2, ["Base.Branch"] = 4 } })
alternatives.applied = { branch }
local al = C.inputChoices(logic({ alternatives }), alternatives, false)
check(al[1].amount == 2 and al[2].amount == 3, "mixed alternatives use relative scale and round only final piece counts")
alternatives = input({ boards, branch }, 1, { exclusive = true, amounts = { ["Base.Plank"] = 2, ["Base.Branch"] = 4 } })
alternatives.applied = { branch }
al = C.inputChoices(logic({ alternatives }), alternatives, false)
check(al[1].amount == 2 and al[2].amount == 3, "exclusive choices receive only their own type's contribution")
local useInput = input({ tape }, 20)
check(C.inputChoices(logic({ useInput }), useInput, false)[1].amount == 1, "20 uses do not become 20 rolls")
check(C.inputChoices(logic({ useInput }), useInput, false)[1].note == "UI_PZSW_OneUsableItem", "uses caveat shown")
local fluid = input({ boards }, 10, { fluidContainer = true })
check(C.inputChoices(logic({ fluid }), fluid, false)[1].note == "UI_PZSW_OneContainer", "container is distinct from litres")
fluid.applied = { boards }
check(#C.inputChoices(logic({ fluid }), fluid, false) == 0, "an existing fluid container is not listed as a missing item")
for _, options in ipairs({ { resource = "fluid" }, { resource = "energy" }, { any = true }, { automated = true } }) do
    local special = input({ boards }, 100, options)
    check(#C.inputChoices(logic({ special }), special, true) == 0, "unlistable resource skipped")
end
local bad = input({ item("invalid"), nails, nails }, 1)
check(#C.inputChoices(logic({ bad }), bad, true) == 1, "invalid types and duplicate choices excluded")
local created = output({ nails }, 2)
local converted = input({ boards }, 1, { create = created })
local keep = input({ boards }, 1, { keep = true, create = created })
local result = C.results(logic({ converted, keep }, { created, output({ tape }, 20, { uses = true }),
    output({ branch }, 2, { variable = true, max = 3 }), output({ nails }, 30, { resource = "fluid" }) }))
check(#result == 3 and result[1][1].amount == 2, "item result and converted input deduplicated")
check(result[2][1].amount == 1 and result[3][1].amount == 3, "uses result and variable recipe counts bounded")

sent = {}
local groupA = { { fullType = "Base.Nails", amount = 2, name = "Nails" } }
local groupB = { { fullType = "Base.Plank", amount = 1 }, { fullType = "Base.Branch", amount = 3 } }
local menu = C.choose(1, { groupA, groupB })
check(#sent == 0 and #menu.options == 3, "ambiguous batch waits; cancellation sends nothing")
click(menu.options[3])
check(#sent == 1 and sent[1].num == 1 and #sent[1].entries == 2 and sent[1].entries[2].fullType == "Base.Branch", "one chosen alternative and unambiguous entries submitted atomically")
check(sent[1].entries[1].name == nil, "display metadata stays out of server requests")
enabled = false
C.choose(1, { groupA }); C.openMenu({ player = player, logic = l })
check(#sent == 1, "disabled integration cannot send commands")
enabled = true
local panel = { player = player, logic = l, xuiRecalculateLayout = function() end }
local first, second, third = ISCraftRecipePanel.createDynamicChildren(panel)
check(first == "recipe" and second == nil and third == 7, "native panel return tuple retained")
check(panel.rootTable.rows == 1 and panel.pzswButton.onclick == C.openMenu, "native button placed in table row")
ISCraftRecipePanel.createDynamicChildren(panel)
check(panel.rootTable.rows == 1, "rebuild creates one new button, not accumulated rows")
panel.pzswButton:prerender()
check(panel.pzswButton.tooltip == "UI_PZSW_AddTo:Survivor", "target list owner appears on the button")
enabled = false; ISCraftRecipePanel.prerender(panel)
check(panel.pzswButton.visible == false and panel.pzswButton.pzswRow.visible == false, "parent hides button and row when integration disabled")
enabled = true; ISCraftRecipePanel.prerender(panel)
check(panel.pzswButton.visible == true and panel.pzswButton.pzswRow.visible == true, "parent restores hidden row when reenabled")
local widget = { player = player, logic = l, inputScript = inp, isMouseOver = function() return true end }
local before = #menus
first, second, third = ISWidgetInput.onRightMouseUp(widget)
ISWidgetInput.onRightMouseUpOutside(widget)
check(first == "click" and second == nil and third == 9 and #menus == before + 1, "callbacks retained and duplicate event route opens one menu")
now = now + 200
widget.displayAsOutput = true
ISWidgetInput.onRightMouseUp(widget)
check(#menus == before + 1, "returned input output widget does not offer ingredient menu")
widget.displayAsOutput = nil
NC_CraftInput_Slot = { onRightMouseUp = function() return true end, onRightMouseUpOutside = function() return false end }
NB_BuildingInput_Slot = { onRightMouseUp = function() return "build" end, onRightMouseUpOutside = function() end }
PJCK_CraftInput_Slot = { onRightMouseUp = function() return "cook" end, onRightMouseUpOutside = function() end }
NC_CellBaseCraft = { createChildren = function() return "created" end, prerender = function() end,
    layoutChildren = function(self, width, height) self.layoutHeight = height; return "layout", nil, 5 end }
NB_BuildingInfoPanel = { createChildren = function() return "nb" end, prerender = function() end }
PJCK_HandCraftPanel = { createChildren = function() return "pj" end, prerender = function() end }
C.install(); C.install()
now = now + 200
check(NC_CraftInput_Slot.onRightMouseUp(widget) == true, "NC callback preserved")
now = now + 200
check(NB_BuildingInput_Slot.onRightMouseUp(widget) == "build", "NB callback preserved")
now = now + 200
check(PJCK_CraftInput_Slot.onRightMouseUp(widget) == "cook", "Project Cook callback preserved")
local nc = { player = player, logic = l, addChild = function() end }
check(NC_CellBaseCraft.createChildren(nc) == "created", "NC creates its native controls first")
first, second, third = NC_CellBaseCraft.layoutChildren(nc, 500, 400)
check(nc.layoutHeight == 376 and nc.pzswButton.y == 380 and nc.pzswButton.width == 500,
    "NC reserves a bottom toolbar without overlapping its other controls")
check(first == "layout" and second == nil and third == 5, "NC layout return tuple preserved")
local nb = tableLayout(); nb.player, nb.logic = player, l
check(NB_BuildingInfoPanel.createChildren(nb) == "nb" and nb.rows == 1, "NB adds separate table row")
if NativeWishlistWorkshopRoot then
    local nbSourcePath = NativeWishlistWorkshopRoot .. "/3536052310/mods/Neat_Building_UIOnly/42.15/media/lua/client/Neat_Building/nb_buildingpanel.lua"
    local f = assert(io.open(nbSourcePath, "r")); local source = f:read("*a"); f:close()
    NB_BuildingPanel = {}
    local method = assert(source:match("(function NB_BuildingPanel:showBuildingInfoPanel.-)\nfunction NB_BuildingPanel:closeBuildingInfoPanel"))
    assert(loadstring(method))()
    local linked, managed = nil, false
    NB_BuildingInfoPanel.new = function(_, x, y, width, height, parent)
        linked = tableLayout()
        linked.player, linked.logic = parent.player, parent.logic
        linked.initialise = function(self) NB_BuildingInfoPanel.createChildren(self) end
        linked.addToUIManager = function() managed = true end
        linked.setVisible = function(self, value) self.visible = value end
        linked.onRecipeChanged = function() end
        return linked
    end
    local window = { player = player, logic = l, getChildren = function() return {} end }
    NB_BuildingPanel.showBuildingInfoPanel(window)
    check(managed and window.BuildingInfoPanel == linked and linked.pzswButton ~= nil,
        "native Neat Building creates wishlist on detached UI-manager info panel")
    check(window.pzswButton == nil and #window:getChildren() == 0,
        "Neat Building fixture must inspect linked BuildingInfoPanel, not only window children")
end
local function geometry(x, y, w, h) return setmetatable({ x = x, y = y, width = w, height = h }, { __index = methods }) end
local cook = { player = player, logic = l, rightAreaX = 100, addChild = function() end,
    craftInputPanel = geometry(100, 10, 300, 180), recipeInfoPanel = geometry(100, 194, 300, 60),
    craftoutputPanel = geometry(100, 258, 170, 100), craftActionPanel = geometry(276, 258, 124, 100) }
cook.craftInputPanel.scrollPanel = geometry(0, 20, 300, 150)
check(PJCK_HandCraftPanel.createChildren(cook) == "pj" and cook.pzswButton.y == 338,
    "Project Cook reserves toolbar by shrinking input viewport")
check(cook.craftInputPanel.scrollPanel.height == 126 and cook.pzswButton.width == 300,
    "Project Cook keeps output and action sizes")
enabled = false; PJCK_HandCraftPanel.prerender(cook)
check(cook.craftInputPanel.scrollPanel.height == 150 and cook.craftActionPanel.y == 258 and not cook.pzswButton.visible,
    "disabling Project Cook integration restores viewport and native action positions")
enabled = true; PJCK_HandCraftPanel.prerender(cook)
check(cook.craftInputPanel.scrollPanel.height == 126 and cook.pzswButton.visible, "reenabling Project Cook restores button space")
PJCK_HandCraftPanel, PJCK_CraftInput_Slot = nil, nil
PJCK_Window = { createHandCraftPanel = function(self)
    PJCK_HandCraftPanel = { createChildren = function() end, prerender = function() end }
    PJCK_CraftInput_Slot = { onRightMouseUp = function() return "lazy" end, onRightMouseUpOutside = function() end }
    self.HandCraftPanel = cook
    cook.pzswButton, cook.pzswReserve = nil, nil
    cook.craftInputPanel.height, cook.craftInputPanel.scrollPanel.height = 180, 150
    cook.recipeInfoPanel.y, cook.craftoutputPanel.y, cook.craftActionPanel.y = 194, 258, 258
    return "tab"
end }
C.install()
check(PJCK_Window.createHandCraftPanel({}) == "tab" and cook.pzswButton ~= nil, "first lazy-loaded Project Cook tab receives controls")
now = now + 200
check(PJCK_CraftInput_Slot.onRightMouseUp(widget) == "lazy", "lazy-loaded Project Cook slots are hooked")

-- Evolved cooking appends to the same existing inventory menu; ingredient action remains native.
PJCK_ItemSlot = { showItemContextMenu = function() ISContextMenu.get(1); return "evolved" end }
ScriptManager = { instance = { getItem = function(_, fullType) return fullType == "Base.Soup" and item(fullType) or nil end } }
local evo = { player = player, getRecipe = function() return { getResultItem = function() return "Soup" end } end,
    getBaseItem = function() return { getModule = function() return "Base" end } end }
C.install()
check(PJCK_ItemSlot.showItemContextMenu({ EvoPanel = evo }) == "evolved" and #menus[#menus].options == 1,
    "evolved recipe result joins original inventory menu")
sent = {}; click(menus[#menus].options[1])
check(sent[1].entries[1].fullType == "Base.Soup" and sent[1].entries[1].amount == 1,
    "evolved result resolves the selected base item's module")

if NativeWishlistGameRoot then
    local f = assert(io.open(NativeWishlistGameRoot .. "/media/lua/client/ISUI/ISContextMenu.lua", "r"))
    local source = f:read("*a"); f:close()
    local method = assert(source:match("(function ISContextMenu:onMouseUp.-)\nfunction ISContextMenu:onMouseWheel"))
    assert(loadstring(method))()
    -- Real mouse callback with a pooled context-menu double: native closes before invoking the selected action.
    local pool = { options = {}, mouseOver = 2, visible = true, player = 1,
        getScrollHeight = function() return 0 end, getScrollAreaHeight = function() return 100 end,
        getIsVisible = function(self) return self.visible end,
        closeAll = function(self) self.visible = false end }
    function pool:addOption(text, target, callback, argument)
        local option = { text = text, target = target, onSelect = callback, param1 = argument }
        self.options[#self.options + 1] = option
        return option
    end
    ISContextMenu.get = function() pool.options = {}; pool.visible = true; return pool end
    sent = {}
    C.choose(1, { groupB, groupB })
    ISContextMenu.onMouseUp(pool, 0, 0)
    check(pool.visible and #sent == 0 and #pool.options == 3, "native click does not close the next pooled alternative chooser")
    ISContextMenu.onMouseUp(pool, 0, 0)
    check(#sent == 1 and #sent[1].entries == 2, "second native click commits exactly the chosen alternatives")
end
print("Wishlist crafting checks passed: " .. tests)
