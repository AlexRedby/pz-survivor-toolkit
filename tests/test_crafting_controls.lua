next = nil -- Native Kahlua does not expose this Lua standard-library global.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local Controls = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/CraftingControls.lua")
local enabled = {plan = true, wishlist = true}
local creates, updates = {plan = 0, wishlist = 0}, {plan = 0, wishlist = 0}
local function button(id, height)
    return {id = id, height = height,
        setVisible = function(self, value) self.visible = value end,
        setX = function(self, value) self.x = value end,
        setY = function(self, value) self.y = value end,
        setWidth = function(self, value) self.width = value end}
end
local function spec(id, order, height)
    return {order = order, field = id .. "Button", rowField = id .. "Row",
        enabled = function() return enabled[id] end,
        create = function(panel)
            if not panel.player then return end
            creates[id] = creates[id] + 1
            return button(id, height)
        end,
        update = function(panel, control, active)
            updates[id] = updates[id] + 1
            control.enabled = active and panel.logic:getRecipe() ~= nil
            if id == "plan" and not active then panel.view = nil end
        end,
        visible = function(panel) return id ~= "plan" or not panel.view end,
        layout = id == "plan" and function(panel, width, height)
            if panel.view then panel.view.width, panel.view.height = width, height end
        end or nil}
end
-- File load order must not determine toolbar order.
Controls.register("wishlist", spec("wishlist", 20, 20))
Controls.register("plan", spec("plan", 10, 26))
local function rootTable()
    return {rows = {}, elements = {},
        addRow = function(self)
            local row = {number = #self.rows + 1,
                index = function(row) return row.number end,
                setVisible = function(row, value) row.visible = value end}
            self.rows[#self.rows + 1] = row
            return row
        end,
        setElement = function(self, _, index, element) self.elements[index] = element end}
end
local nativeCreates, nativePre = 0, 0
ISCraftRecipePanel = {
    createDynamicChildren = function(panel)
        nativeCreates = nativeCreates + 1
        panel.rootTable = rootTable()
        return "native", nil, 7
    end,
    prerender = function() nativePre = nativePre + 1; return "render", nil, 8 end}
NC_CellBaseCraft = nil
Controls.install(); Controls.install()
local recipe = {}
local function panel()
    return {player = {}, width = 500, height = 400, children = {}, relayouts = 0,
        logic = {getRecipe = function() return recipe end},
        addChild = function(self, child) self.children[#self.children + 1] = child end,
        xuiRecalculateLayout = function(self) self.relayouts = self.relayouts + 1 end,
        calculateLayout = function(self, width, height)
            self.relayouts = self.relayouts + 1
            return NC_CellBaseCraft.layoutChildren(self, width, height)
        end}
end
local native = panel()
local a, b, c = ISCraftRecipePanel.createDynamicChildren(native)
check(a == "native" and b == nil and c == 7 and nativeCreates == 1, "native create runs once and retains nil results")
check(native.rootTable.elements[1] == native.planButton and native.rootTable.elements[2] == native.wishlistButton,
    "native buttons follow explicit order despite reversed registration")
check(native.planButton.planRow == native.rootTable.rows[1] and native.wishlistButton.wishlistRow == native.rootTable.rows[2],
    "consumer row aliases refer to the managed rows")
check(native.relayouts == 1 and native.planButton.visible and native.wishlistButton.visible,
    "native controls share one initial relayout")
local previousButton, previousTable = native.planButton, native.rootTable
ISCraftRecipePanel.createDynamicChildren(native)
check(native.rootTable ~= previousTable and native.planButton ~= previousButton and #native.rootTable.rows == 2,
    "native rebuild replaces controls instead of retaining old rows")
recipe = nil
ISCraftRecipePanel.createDynamicChildren(native)
check(not native.planButton and not native.wishlistButton and #native.rootTable.rows == 0,
    "empty recipe rebuild clears previous consumer fields")
recipe = {}
ISCraftRecipePanel.createDynamicChildren(native)
native.relayouts = 0
enabled.plan, enabled.wishlist = false, false
a, b, c = ISCraftRecipePanel.prerender(native)
check(a == "render" and b == nil and c == 8 and nativePre == 1, "native render tuple and call count survive wrapping")
check(native.relayouts == 1 and not native.planButton.visible and not native.planButton.planRow.visible
    and not native.wishlistButton.visible and not native.wishlistButton.wishlistRow.visible,
    "both native toggles update button and row visibility in one relayout")
ISCraftRecipePanel.prerender(native)
check(native.relayouts == 1, "unchanged visibility does not rebuild native layout")
enabled.plan, enabled.wishlist = true, true
ISCraftRecipePanel.prerender(native)
check(native.relayouts == 2 and native.planButton.enabled and native.planButton.visible,
    "reenabling restores native controls")

-- Neat may appear after the first install; only its newly available hooks are added.
local neatCreates, neatLayouts, neatPre = 0, 0, 0
NC_CellBaseCraft = {
    createChildren = function() neatCreates = neatCreates + 1; return "created", nil, 9 end,
    layoutChildren = function(self, width, height)
        neatLayouts = neatLayouts + 1
        self.baseWidth, self.baseHeight = width, height
        return "layout", nil, 5
    end,
    prerender = function() neatPre = neatPre + 1; return "neat-render", nil, 6 end}
Controls.install(); Controls.install()
local neat = panel()
a, b, c = NC_CellBaseCraft.createChildren(neat)
check(a == "created" and b == nil and c == 9 and neatCreates == 1 and #neat.children == 2,
    "late Neat hooks create each control once and preserve native results")
NC_CellBaseCraft.createChildren(neat)
check(neatCreates == 2 and #neat.children == 2, "repeated Neat creation does not duplicate controls")
a, b, c = NC_CellBaseCraft.layoutChildren(neat, 500, 400)
check(a == "layout" and b == nil and c == 5 and neatLayouts == 1 and neat.baseHeight == 346,
    "one native layout receives total content height")
check(neat.planButton.y == 350 and neat.planButton.width == 500 and neat.wishlistButton.y == 380
    and neat.wishlistButton.y + neat.wishlistButton.height == 400,
    "ordered footers share the reserved area and retain the total panel height")
neat.view = {}
neat.relayouts = 0
a, b, c = NC_CellBaseCraft.prerender(neat)
check(a == "neat-render" and b == nil and c == 6 and neatPre == 1 and neat.relayouts == 1,
    "opening the embedded view triggers one layout through prerender")
check(not neat.planButton.visible and neat.wishlistButton.visible and neat.baseHeight == 376
    and neat.view.height == 376 and neat.view.width == 500,
    "embedded view gets content height after the remaining Wishlist footer")
NC_CellBaseCraft.prerender(neat)
check(neat.relayouts == 1, "stable embedded view does not relayout every frame")
enabled.plan, enabled.wishlist = false, false
NC_CellBaseCraft.prerender(neat)
check(not neat.view and neat.baseHeight == 400 and neat.relayouts == 2
    and not neat.planButton.visible and not neat.wishlistButton.visible,
    "update closes a disabled view before one shared toggle layout")
enabled.plan, enabled.wishlist = true, true
NC_CellBaseCraft.prerender(neat)
check(neat.baseHeight == 346 and neat.relayouts == 3 and neat.planButton.visible and neat.wishlistButton.visible,
    "both footers return through one shared relayout")
neat.view = {}
NC_CellBaseCraft.layoutChildren(neat, 500, 400)
check(neat.view.height == 376 and not neat.planButton.visible,
    "direct layout also observes embedded-view visibility without a render first")
local noPlayer = panel(); noPlayer.player = nil
NC_CellBaseCraft.createChildren(noPlayer)
check(#noPlayer.children == 0 and not noPlayer.planButton and not noPlayer.wishlistButton,
    "creators can reject an unavailable player")
check(creates.plan == creates.wishlist and updates.plan > creates.plan,
    "both consumers receive creation and render updates")
print("Crafting controls checks passed: " .. checks)
