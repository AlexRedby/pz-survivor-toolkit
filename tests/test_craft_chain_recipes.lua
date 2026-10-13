local testNext = next
next = nil -- Native Kahlua does not expose this Lua standard-library global.
require = function() end
local function list(values)
    local result = {values = values or {}}
    function result:size() return #self.values end
    function result:get(i) return self.values[i + 1] end
    function result:add(value) self.values[#self.values + 1] = value end
    function result:contains(value)
        for _, item in ipairs(self.values) do if item == value then return true end end
        return false
    end
    return result
end
ArrayList = {new = function() return list() end}
ResourceType = {Item = "Item", Fluid = "Fluid"}
getText = function(key) return key end
local queued, messages, grouped = {}, {}, 0
HaloTextHelper = {addBadText = function(_, value) messages[#messages + 1] = value end}
local container = {}
local inventory = {}
local enabled = true
local player = {isDead = function(self) return self.dead end,
    isAsleep = function(self) return self.asleep end, getPlayerNum = function() return 0 end,
    getInventory = function() return inventory end}
local currentPlayer = player
getSpecificPlayer = function() return currentPlayer end
local function scriptItem(fullType)
    return {getFullName = function() return fullType end, getCount = function() return 1 end}
end
local itemId = 0
local function item(fullType, opts)
    itemId = itemId + 1
    local value = opts or {}
    value.fullType, value.id = fullType, itemId
    function value:getID() return self.id end
    function value:getFullType() return self.fullType end
    function value:getContainer() return self.container or container end
    return value
end
local function input(fullType, keep, alternatives)
    local value = {fullType = fullType, keep = keep, alternatives = alternatives or {fullType}}
    function value:getResourceType() return self.fluid and ResourceType.Fluid or ResourceType.Item end
    function value:isVariableAmount() return self.variable == true end
    function value:hasConsumeFromItem() return false end
    function value:hasCreateToItem() return false end
    function value:isReplace() return self.replace == true end
    function value:isApplyOnTick() return false end
    function value:isKeep() return self.keep == true end
    function value:getPossibleInputItems()
        local items = {}
        for _, name in ipairs(self.alternatives) do items[#items + 1] = scriptItem(name) end
        return list(items)
    end
    function value:getAmount(name) return self.amounts and self.amounts[name] or 1 end
    function value:isUsesPartialItem() return self.partial == true end
    function value:canUseItem(candidate, p)
        assert(p == player)
        if candidate.invalid then return false end
        for _, name in ipairs(self.alternatives) do if candidate.fullType == name then return true end end
        return false
    end
    return value
end
local function output(fullType, amount)
    local value = {fullType = fullType, amount = amount or 1}
    function value:getResourceType() return self.fluid and ResourceType.Fluid or ResourceType.Item end
    function value:getPossibleResultItems() return list({scriptItem(self.fullType)}) end
    function value:isVariableAmount() return self.variable == true end
    function value:getChance() return self.chance or 1 end
    function value:isReplaceInput() return false end
    function value:hasCreateToItem() return false end
    function value:isApplyOnTick() return false end
    function value:getOriginalLine() return self.mapped and "item 1 mapper:Thing" or "item 1 " .. self.fullType end
    function value:getAmount() return self.amount end
    function value:getIntAmount() return self.amount end
    return value
end
local function recipe(name, inputs, outputs)
    local value = {id = name, inputs = inputs, outputs = outputs, source = "inputs {} outputs {}"}
    function value:getName() return self.id end
    function value:getTranslationName() return self.id end
    function value:getLoadedScriptBodies() return list({"recipes.txt", self.source}) end
    function value:hasOnTickInputs() return false end
    function value:hasOnTickOutputs() return false end
    function value:getInputs() return list(self.inputs) end
    function value:getOutputs() return list(self.outputs) end
    function value:getIndexForIO(slot)
        for i, candidate in ipairs(self.inputs) do if candidate == slot then return i - 1 end end
    end
    function value:isAnySurfaceCraft() return self.surface == true end
    function value:isCanBeDoneFromFloor() return self.floor == true end
    return value
end
local saw = recipe("SawLogs", {input("Base.Log"), input("Base.Saw", true)}, {output("Base.Plank", 3)})
local spoon = recipe("Spoon", {input("Base.Plank"), input("Base.Knife", true)}, {output("Base.Spoon")})
local nativeRecipes, nativeItems = {saw, spoon}, {}
CraftRecipeManager = {isValidRecipeForCharacter = function(value) return not value.unavailable end}
getScriptManager = function() return {getAllCraftRecipes = function() return list(nativeRecipes) end} end
ISInventoryPaneContextMenu = {getContainers = function() return list({container}) end}
local surface = {getSquare = function() return {} end}
local lastSelectedRecipe
HandcraftLogic = {new = function(p, bench, object)
    assert(p == player)
    local logic = {bench = bench, object = object, selections = {}, listeners = {}}
    function logic:getPlayer() return p end
    function logic:getCraftBench() return self.bench end
    function logic:getIsoObject() return self.object end
    function logic:setContainers(containers) self.containers = containers end
    function logic:getAllItems() return list(nativeItems) end
    function logic:setRecipe(value)
        self.recipe = value; lastSelectedRecipe = value
        for _, listener in ipairs(self.listeners) do
            if listener.event == "onRecipeChanged" then listener.fn(listener.target, value) end
        end
    end
    function logic:addEventListener(event, fn, target)
        assert(event == "onRecipeChanged" or event == "onManualSelectChanged")
        self.listeners[#self.listeners + 1] = {event = event, fn = fn, target = target}
    end
    function logic:setLastSelectedRecipe(value) self.lastRecipe = value; lastSelectedRecipe = value end
    function logic:getRecipe() return self.recipe end
    function logic:isCharacterInRangeOfWorkbench() return self.object and not self.object.far end
    function logic:hasRequiredWorkstation() return not self.recipe.workstation or self.bench == "bench" end
    function logic:setManualSelectInputs(manual)
        self.manual = manual
        for _, listener in ipairs(self.listeners) do
            if listener.event == "onManualSelectChanged" then listener.fn(listener.target, manual) end
        end
    end
    function logic:isManualSelectInputs() return self.manual end
    function logic:clearManualInputs() self.selections = {} end
    function logic:setManualInputsFor(slot, items)
        self.selections[slot] = items
        return not slot.rejectManual
    end
    function logic:getManualInputsFor(slot) return self.selections[slot] or list() end
    function logic:getManualSelectInputScriptFilter() return self.inputFilter end
    function logic:offerInputItem(value)
        local items = self.selections[self.inputFilter] or list()
        items:add(value)
        self.selections[self.inputFilter] = items
    end
    function logic:removeInputItem(value)
        for slot, items in pairs(self.selections) do
            local remaining = list()
            for _, candidate in ipairs(items.values) do if candidate ~= value then remaining:add(candidate) end end
            self.selections[slot] = remaining
        end
    end
    function logic:canPerformCurrentRecipe() return self.manual and not self.recipe.rejectNative end
    function logic:getRecipeData()
        return {containsInputItem = function(_, value)
            for _, items in pairs(self.selections) do if items:contains(value) then return true end end
            return false
        end, getAllInputItems = function()
            local items = list()
            for _, slot in ipairs(self.recipe.inputs) do
                for _, selected in ipairs(self.selections[slot].values) do items:add(selected) end
            end
            return items
        end, getAllPutBackInputItems = function()
            local items = list()
            for _, slot in ipairs(self.recipe.inputs) do
                if slot.keep then
                    for _, selected in ipairs(self.selections[slot].values) do items:add(selected) end
                end
            end
            return items
        end}
    end
    function logic:isUsingRecipeAtHandBenefit() return self.recipe.book ~= nil end
    function logic:getUsingRecipeAtHandItem() return self.recipe.book end
    return logic
end}
ISCraftInventoryPanel = {onListItemClicked = function(self, row)
    self.clicks = (self.clicks or 0) + 1
    if self.logic:getRecipeData():containsInputItem(row.inventoryItem) then
        self.logic:removeInputItem(row.inventoryItem)
        if row.isUsedItems then self.logic:offerInputItem(row.inventoryItem) end
    else
        self.logic:offerInputItem(row.inventoryItem)
    end
end}
local Bulk = {safeItem = function(_, value) return not value.protected end,
    transfer = function(_, value) queued[#queued + 1] = {Type = "transfer", item = value} end}
PZSurvivorToolkit = {BulkActions = Bulk, Settings = {craftChains = function() return enabled end},
    ActionQueueOperations = {run = function(fn) grouped = grouped + 1; fn() end}}
ISTimedActionQueue = {add = function(action) queued[#queued + 1] = action end}
local forceCancel = function() end
ISQueueActionsAction = {new = function(_, p, fn, step, context, initialIds)
    return {Type = "ISQueueActionsAction", character = p, addActionsFunction = fn,
        args = {step, context, initialIds}, forceCancel = forceCancel}
end}
ISHandcraftAction = {FromLogic = function(logic)
    assert(logic.manual, "native automatic ingredient selection must remain disabled")
    return {Type = "ISHandcraftAction", craftRecipe = logic.recipe, selections = logic.selections}
end}
ISEntityUI = {WalkToEntity = function(_, object) return object and not object.walkBlocked end}
ISCraftingUI = {ReturnItemsToOriginalContainer = function(p, items)
    assert(p == player)
    for _, value in ipairs(items) do
        queued[#queued + 1] = {Type = "return", item = value, srcContainer = inventory, destContainer = value:getContainer()}
    end
end}
dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/CraftChainRecipes.lua")
local api = PZSurvivorToolkit.CraftChainRecipes
local panel = {logic = HandcraftLogic.new(player, nil, surface)}
panel.logic:setRecipe(spoon)
nativeItems = {item("Base.Log"), item("Base.Saw", {protected = true}), item("Base.Knife", {protected = true})}
local model, target, context = api.collect(panel)
assert(target == "Spoon" and model.recipes.SawLogs and context.surface == surface)
assert(#model.resources == 3 and model.accepts(model.recipes.SawLogs.inputs[2], model.resources[2]))
assert(lastSelectedRecipe == spoon, "scanning other recipes must restore the UI selection")
assert(not model.accepts(model.recipes.SawLogs.inputs[1], {fullType = "Base.Log", item = item("Base.Log", {protected = true})}))
assert(not model.accepts(model.recipes.SawLogs.inputs[1], {fullType = "Base.Log", item = item("Base.Log", {invalid = true})}))
local plan = {initialIds = {}, steps = {
    {recipe = model.recipes.SawLogs, inputs = {
        [0] = {fullType = "Base.Log", amount = 1, resourceIds = {nativeItems[1]:getID()}, generated = 0},
        [1] = {fullType = "Base.Saw", amount = 1, resourceIds = {nativeItems[2]:getID()}, generated = 0}}},
    {recipe = model.recipes.Spoon, inputs = {
        [0] = {fullType = "Base.Plank", amount = 1, resourceIds = {}, generated = 1},
        [1] = {fullType = "Base.Knife", amount = 1, resourceIds = {nativeItems[3]:getID()}, generated = 0}}},
}}
for _, value in ipairs(nativeItems) do plan.initialIds[value:getID()] = true end
local function execute(step) return api.addStep(player, step, context, plan.initialIds) end
local function bindExactInputs(step)
    for _, choice in pairs(step.inputs) do
        if choice.generated == 0 then
            choice.resourceIds = {}
            for _, value in ipairs(nativeItems) do
                if value:getFullType() == choice.fullType then
                    choice.resourceIds[#choice.resourceIds + 1] = value:getID()
                    plan.initialIds[value:getID()] = true
                    if #choice.resourceIds == choice.amount then break end
                end
            end
        end
    end
end
assert(api.enqueue(player, plan, context) and grouped == 1 and #queued == 2)
for _, action in ipairs(queued) do
    assert(action.toolkitCraftPlanCancellation and action.addActionsFunction == api.addStep and action.forceCancel == forceCancel)
end
local first, last = queued[1], queued[2]
queued = {}
first.addActionsFunction(player, unpack(first.args))
assert(#queued == 4 and queued[3].Type == "ISHandcraftAction" and queued[4].Type == "return")
assert(queued[3].selections[saw.inputs[1]]:get(0) == nativeItems[1])
assert(queued[4].item == nativeItems[2] and queued[4].destContainer == container,
    "kept shelf tool must return to its exact original container after crafting")
nativeItems = {nativeItems[2], nativeItems[3], item("Base.Plank", {container = inventory}),
    item("Base.Plank", {container = inventory}), item("Base.Plank", {container = inventory})}
queued = {}
last.addActionsFunction(player, unpack(last.args))
assert(#queued == 3 and queued[2].selections[spoon.inputs[1]]:get(0) == nativeItems[3], "deferred step must find newly created material")
assert(queued[3].item == nativeItems[2] and queued[3].Type == "return")
-- Exact selected IDs win over inventory order; a lost object cannot silently consume its same-type neighbour.
local unselectedLog, selectedLog, selectedSaw=item("Base.Log"), item("Base.Log"), item("Base.Saw")
nativeItems={unselectedLog, selectedLog, selectedSaw}
plan.steps[1].inputs[0].resourceIds={selectedLog:getID()};plan.steps[1].inputs[1].resourceIds={selectedSaw:getID()}
for _, value in ipairs(nativeItems) do plan.initialIds[value:getID()]=true end
queued={};execute(plan.steps[1]);assert(queued[1].item==selectedLog and queued[3].selections[saw.inputs[1]]:get(0)==selectedLog)
nativeItems={unselectedLog, selectedSaw};queued={};execute(plan.steps[1])
assert(#queued==0, "a vanished exact selected ID must fail before transferring an unselected replacement")
-- Generated slots may not spend original stock reserved for another step or newly arriving shared-container items.
local originalPlank, newPlank, reservedKnife=item("Base.Plank", {container=inventory}),
    item("Base.Plank", {container=inventory}), item("Base.Knife")
plan.initialIds[originalPlank:getID()]=true;plan.initialIds[reservedKnife:getID()]=true
plan.steps[2].inputs[1].resourceIds={reservedKnife:getID()}
nativeItems={originalPlank, reservedKnife, newPlank};queued={};execute(plan.steps[2])
assert(queued[2].Type=="ISHandcraftAction" and queued[2].selections[spoon.inputs[1]]:get(0)==newPlank)
nativeItems={originalPlank, reservedKnife};queued={};execute(plan.steps[2]);assert(#queued==0)
nativeItems={reservedKnife,item("Base.Plank")};queued={};execute(plan.steps[2])
assert(#queued==0, "a new matching item from another player's shared container cannot substitute for our output")
-- Recipe books return too; one book serving as both a kept input and recipe-at-hand is transferred once.
saw.book = item("Base.Saw"); nativeItems = {item("Base.Log"), saw.book}
bindExactInputs(plan.steps[1]);queued = {};execute(plan.steps[1])
assert(#queued == 4 and queued[4].item == saw.book, "a kept recipe book must not queue duplicate guarded pickups or returns")
saw.book = item("Base.RecipeBook");queued = {};execute(plan.steps[1])
assert(#queued == 6 and queued[4].Type == "ISHandcraftAction" and queued[6].item == saw.book)
saw.book = nil
nativeItems = {item("Base.Log"), item("Base.Saw", {container = inventory})}
bindExactInputs(plan.steps[1]);queued = {};execute(plan.steps[1])
assert(#queued == 2 and queued[2].Type == "ISHandcraftAction", "already carried tools need no pickup or return")
saw.floor = true;nativeItems[2].container = nil;queued = {};execute(plan.steps[1])
assert(#queued == 1 and queued[1].Type == "ISHandcraftAction", "floor crafting must not add pickup or return transactions")
saw.floor = nil
-- The entire selection is validated before any transfer or walking action is added.
nativeItems = {item("Base.Plank", {container = inventory}), item("Base.Knife", {invalid = true})}
bindExactInputs(plan.steps[2])
queued = {}
local failuresBefore = #messages
execute(plan.steps[2])
assert(#queued == 0 and #messages == failuresBefore + 1)
nativeItems[2].invalid = false
spoon.rejectNative = true
execute(plan.steps[2])
assert(#queued == 0)
spoon.rejectNative = false
spoon.surface, surface.walkBlocked = true, true
execute(plan.steps[2])
assert(#queued == 0, "failed surface navigation must not enqueue pickups")
surface.walkBlocked = nil
for _, state in ipairs({"disabled", "asleep", "dead", "replaced"}) do
    enabled = state ~= "disabled"
    player.asleep, player.dead = state == "asleep", state == "dead"
    currentPlayer = state == "replaced" and {} or player
    assert(not api.enqueue(player, plan, context))
    execute(plan.steps[2])
    assert(#queued == 0, "disabled or stale player must not continue the chain")
end
enabled, player.asleep, player.dead, currentPlayer = true, false, false, player
local originalSource = spoon.source
for _, source in ipairs({"OnCreate = thing", "onTest = other", "OnStart=third", "OnUpdate = fourth", "OnFailed = fifth"}) do
    spoon.source = source
    local failed, message = api.collect(panel)
    assert(not failed and message == "UI_PZST_CraftChainUnsupportedCallbacks")
    assert(lastSelectedRecipe == spoon)
end
spoon.source = originalSource
for _, flag in ipairs({"variable", "partial", "fluid", "replace"}) do
    spoon.inputs[1][flag] = true
    local failed, message = api.collect(panel)
    assert(not failed and message == "UI_PZST_CraftChainUnsupportedInputs")
    assert(lastSelectedRecipe == spoon)
    spoon.inputs[1][flag] = nil
end
for _, change in ipairs({{mapped = true}, {chance = 0.5}, {variable = true}, {fluid = true}, {amount = 0.5}}) do
    local key, value = testNext(change)
    local prior = spoon.outputs[1][key]
    spoon.outputs[1][key] = value
    local failed, message = api.collect(panel)
    assert(not failed and message == "UI_PZST_CraftChainUnsupportedOutputs")
    assert(lastSelectedRecipe == spoon)
    spoon.outputs[1][key] = prior
end
spoon.inputs[1].alternatives = {"Base.Plank", "Base.Branch"}
spoon.inputs[1].amounts = {["Base.Plank"] = 1, ["Base.Branch"] = 2}
panel.logic:setManualSelectInputs(true)
local branch, branch2, plank = item("Base.Branch"), item("Base.Branch"), item("Base.Plank")
nativeItems = {branch, branch2, plank}
panel.logic.selections[spoon.inputs[1]] = list({branch})
-- Native and Neat Crafting enable manual mode but fill it automatically.
model = api.collect(panel)
assert(#model.recipes.Spoon.inputs[1].choices == 2 and not model.recipes.Spoon.inputs[1].preference,
    "untouched auto-populated native selections impose no material or ID restriction")
local nativePicker = setmetatable({logic = panel.logic}, {__index = ISCraftInventoryPanel})
panel.logic.inputFilter = spoon.inputs[1]
api.install(); api.install()
panel.logic.selections[spoon.inputs[1]] = list()
nativePicker:onListItemClicked({inventoryItem = branch})
assert(nativePicker.clicks == 1, "repeated installation must not duplicate native callbacks")
model = api.collect(panel)
assert(#model.recipes.Spoon.inputs[1].choices == 1 and model.recipes.Spoon.inputs[1].choices[1].amount == 2)
local manualSlot = model.recipes.Spoon.inputs[1]
assert(manualSlot.preference == "Base.Branch" and manualSlot.nativeSelection and manualSlot.preferredIds[branch:getID()])
assert(not manualSlot.selectedIds and #manualSlot.allChoices == 2)
assert(model.accepts(manualSlot, {fullType = "Base.Branch", item = branch2})
    and model.accepts(manualSlot, {fullType = "Base.Branch"}),
    "a partial native choice can be completed and its material remains usable on repeated crafts")
panel.logic.selections[spoon.inputs[1]] = list({plank})
assert(api.collect(panel).recipes.Spoon.inputs[1].preferredIds[branch:getID()],
    "later automatic population must not rewrite the user's original item choice")
panel.logic.selections[spoon.inputs[1]] = list({branch})
local cleared = api.collect(panel, {Spoon = {[0] = false}}).recipes.Spoon.inputs[1]
assert(#cleared.choices == 2 and not cleared.preference and not cleared.preferredIds and not cleared.nativeSelection,
    "explicit Auto clears imported native intent")
local replaced = api.collect(panel, {Spoon = {[0] = "Base.Plank"}}).recipes.Spoon.inputs[1]
assert(#replaced.choices == 1 and replaced.preference == "Base.Plank" and not replaced.preferredIds)
local intermediate = api.collect(panel, {SawLogs = {[0] = "Base.Log"}}).recipes.SawLogs.inputs[1]
assert(intermediate.preference == "Base.Log", "overrides apply to intermediate recipes too")
for _, overrides in ipairs({{Spoon = {[0] = "Base.Unknown"}}, {Spoon = {[33] = false}}, {Missing = {[0] = false}},
    {Spoon = {[0] = true}}, {Spoon = "invalid"}}) do
    local invalid, message = api.collect(panel, overrides)
    assert(not invalid and message == "UI_PZST_CraftChainUnsupportedSelection", "invalid overrides fail closed")
end
nativeItems = {branch2, plank}
local failed, message = api.collect(panel)
assert(not failed and message == "UI_PZST_CraftChainUnsupportedSelection",
    "a vanished originally selected ID cannot silently become its same-type neighbour")
assert(api.collect(panel, {Spoon = {[0] = false}}), "Auto can clear a vanished imported choice")
nativeItems = {branch, branch2, plank}
branch.protected = true
failed, message = api.collect(panel)
assert(not failed and message == "UI_PZST_CraftChainUnsupportedSelection")
branch.protected, branch.invalid = nil, true
failed, message = api.collect(panel)
assert(not failed and message == "UI_PZST_CraftChainUnsupportedSelection")
branch.invalid = nil
-- Neat Crafting is optional and can appear after module loading.
assert(NC_InputSwitch_Panel == nil)
NC_InputSwitch_Panel = {
    onItemSelected = function(self, selectedItem)
        if self.logic:getRecipeData():containsInputItem(selectedItem) then
            self.logic:removeInputItem(selectedItem)
        else
            self.logic:offerInputItem(selectedItem)
        end
    end,
    onItemGroupDoubleClick = function(self, index, preferredItem)
        if index ~= 1 then return false end
        self.logic.selections[self.logic.inputFilter] = list({preferredItem, branch2})
        return true
    end,
}
api.install(); api.install()
local neatPicker = setmetatable({logic = panel.logic}, {__index = NC_InputSwitch_Panel})
neatPicker:onItemSelected(plank)
local failed, message = api.collect(panel)
assert(not failed and message == "UI_PZST_CraftChainUnsupportedSelection")
assert(lastSelectedRecipe == spoon, "early manual-selection failure must restore the UI selection")
assert(neatPicker:onItemGroupDoubleClick(1, branch))
manualSlot = api.collect(panel).recipes.Spoon.inputs[1]
assert(manualSlot.preferredIds[branch:getID()] and manualSlot.preferredIds[branch2:getID()])
assert(not neatPicker:onItemGroupDoubleClick(2, plank))
assert(api.collect(panel).recipes.Spoon.inputs[1].preference == "Base.Branch")
local otherSpoon = recipe("Spoon", {input("Base.Branch")}, {output("Base.Spoon")})
panel.logic:setRecipe(otherSpoon)
panel.logic:setRecipe(spoon)
assert(not api.collect(panel).recipes.Spoon.inputs[1].preference,
    "leaving and returning to a recipe resets intent even when recipe names are identical")
assert(#panel.logic.listeners == 2, "collection must attach only one recipe and manual-mode reset listener per logic")
panel.logic.selections[spoon.inputs[1]] = list()
neatPicker:onItemSelected(branch)
-- The UI callback after a removal represents an empty (Auto) selection.
neatPicker:onItemSelected(branch)
assert(not api.collect(panel).recipes.Spoon.inputs[1].preference)
neatPicker:onItemSelected(branch)
assert(api.collect(panel).recipes.Spoon.inputs[1].preference == "Base.Branch")
panel.logic:setManualSelectInputs(false)
panel.logic:setManualSelectInputs(true)
assert(not api.collect(panel).recipes.Spoon.inputs[1].preference,
    "manual off/on without an intervening collection must discard the earlier picker preference")
panel.logic.selections[spoon.inputs[1]] = list()
neatPicker:onItemSelected(branch)
panel.logic:setManualSelectInputs(false)
assert(not api.collect(panel).recipes.Spoon.inputs[1].preference, "automatic mode clears an earlier picker preference")
spoon.outputs[1].amount=1001
failed,message=api.collect(panel)
assert(not failed and message=="UI_PZST_CraftChainUnsupportedOutputs", "giant mod output cannot bypass the planner search budget")
spoon.outputs[1].amount=1;spoon.inputs[1].amounts["Base.Plank"]=1001
failed,message=api.collect(panel)
assert(not failed and message=="UI_PZST_CraftChainUnsupportedInputs")
spoon.inputs[1].amounts["Base.Plank"]=1
nativeItems={};for i=1,10001 do nativeItems[i]=item("Base.Plank") end
failed,message=api.collect(panel)
assert(not failed and message=="UI_PZST_CraftChaincomplex" and lastSelectedRecipe==spoon)
queued={};execute(plan.steps[2])
assert(#queued==0, "oversized changed inventory must fail before any native item transaction")
print("Craft chain native adapter checks passed: contracts, protection, deferred inputs, atomic preflight, deterministic recipe filtering and manual choices.")
