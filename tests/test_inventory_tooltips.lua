-- Source-backed contract checks: run with the actual B42 renderer and VHS module.
local nativeRoot = NativeTooltipLuaRoot or NativePlantingLuaRoot
if not nativeRoot or not NativeVHSTooltipRoot then
    print('Inventory media tooltip: native/VHS sources absent; source-backed checks skipped.')
    return
end
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
package.path = root .. '?.lua;' .. NativeVHSTooltipRoot .. '/?.lua;' .. package.path
local function load(name) return assert(loadfile(root .. 'PZSurvivorToolkit/' .. name .. '.lua'))() end
local function event()
    local callbacks = {}
    return {Add = function(callback) callbacks[#callbacks + 1] = callback end,
        fire = function() for _, callback in ipairs(callbacks) do callback() end end}
end
local player, active = {}, true
local translations = {
    ['Media.Test'] = 'Woodcraft episode',
    IGUI_perks_Carpentry = 'Carpentry with an intentionally long translated skill name',
    IGUI_XP_Skills = 'Skills', Tooltip_Literature_LearnedRecipes = 'Recipes: ',
}
getText = function(key) return translations[key] or key end
getRecipeDisplayName = function(key)
    if key == 'RecipeOne' then return 'A deliberately long translated recipe for the tooltip width' end
    return key
end
ResourceLocation = {of = function(name) return {toString = function() return name end} end}
UIFont = {Small = 'Small', Medium = 'Medium', Large = 'Large'}
getPlayer = function() return player end
getActivatedMods = function() return {contains = function(_, id) return active and id == 'VHSSkillNameInTooltip' end} end
getMouseX = function() return 620 end
getMouseY = function() return 460 end
getPlayerScreenLeft = function() return 0 end
getPlayerScreenTop = function() return 0 end
getCore = function() return {getScreenWidth = function() return 640 end,
    getScreenHeight = function() return 480 end, getOptionTooltipFont = function() return 'Small' end} end
getTextManager = function() return {MeasureStringX = function(_, _, text) return #text * 6 end} end
DebugType = {General = 'General'}
DebugLog = {log = function() end}
local function target()
    local value = {width = 150, height = 40, padBottom = 5, padLeft = 5, padTop = 5,
        layouts = {}, texts = {}, nativeCalls = {}}
    for _, field in ipairs({'Width', 'Height', 'X', 'Y'}) do
        local key = string.lower(field)
        value['get' .. field] = function(self) return self[key] or 0 end
        value['set' .. field] = function(self, number) self[key] = number end
    end
    value.getFont = function() return UIFont.Small end
    value.getLineSpacing = function() return 18 end
    value.setCharacter = function(self, character) self.character = character end
    value.getCharacter = function(self) return self.character end
    value.setMeasureOnly = function(self, flag) self.measureOnly = flag end
    value.DrawText = function(self, font, text, x, y, r, g, b, a)
        self.texts[#self.texts + 1] = {text = text, x = x, y = y, color = {r,g,b,a},
            measureOnly = self.measureOnly, font = font}
    end
    value.beginLayout = function(self)
        local layout = {rows = {}, target = self, measureOnly = self.measureOnly, minLabelWidth = 0}
        self.layouts[#self.layouts + 1] = layout
        layout.addItem = function(layout)
            local entry = {}
            layout.rows[#layout.rows + 1] = entry
            entry.setLabel = function(row, text, r, g, b, a) row.label, row.labelColor = text, {r,g,b,a} end
            entry.setValue = function(row, text, r, g, b, a) row.value, row.valueColor = text, {r,g,b,a} end
            return entry
        end
        layout.setMinLabelWidth = function(layout, width) layout.minLabelWidth = width end
        layout.render = function(layout, x, y, destination)
            assert(destination == self)
            for _, row in ipairs(layout.rows) do
                local labelWidth = #(row.label or '') * 6
                local valueX = x + math.max(labelWidth, layout.minLabelWidth)
                self.width = math.max(self.width, x + labelWidth + 5, valueX + #(row.value or '') * 6 + 5)
                if row.label then self:DrawText(self:getFont(), row.label, x, y, unpack(row.labelColor)) end
                if row.value then self:DrawText(self:getFont(), row.value, valueX, y, unpack(row.valueColor)) end
                y = y + self:getLineSpacing()
            end
            return y
        end
        return layout
    end
    value.endLayout = function(self, layout) assert(layout.target == self) end
    return value
end
local methods = {}
methods.DoTooltip = function(item, destination)
    destination.nativeCalls[#destination.nativeCalls + 1] = {item = item, measureOnly = destination.measureOnly}
    destination:setWidth(150); destination:setHeight(40)
    if item.onNative then item.onNative(destination) end
    if item.throw then error('native media tooltip failure') end
    return 'native-result'
end
local function item(fullType, name)
    return setmetatable({getFullType = function() return fullType or 'Base.VHS_Retail' end,
        getDisplayName = function() return name or 'Woodcraft episode' end,
        IsClothing = function() return fullType == 'Base.TestClothing' end,
        getBodyLocation = function() return nil end}, {__index = methods})
end
local function window(value, destination)
    return setmetatable({item = value, tooltip = destination or target(), followMouse = false, x = 100, y = 100,
        backgroundColor = {a = 0.5, r = 0, g = 0, b = 0}, borderColor = {a = 1, r = 1, g = 1, b = 1}, backgrounds = {},
        getX = function(self) return self.x end, getY = function(self) return self.y end,
        setX = function(self, number) self.x = number end, setY = function(self, number) self.y = number end,
        getWidth = function(self) return self.width or 0 end, getHeight = function(self) return self.height or 0 end,
        setWidth = function(self, number) self.width = number end, setHeight = function(self, number) self.height = number end,
        drawRect = function(self, x, y, w, h, a) self.backgrounds[#self.backgrounds + 1] = {width = w, height = h, alpha = a} end,
        drawRectBorder = function() end}, {__index = ISToolTipInv})
end
local function reset()
    ISPanel = {derive = function() return {} end}
    package.loaded['ISUI/ISPanel'] = true
    dofile(nativeRoot .. '/client/ISUI/ISToolTipInv.lua')
    package.loaded['ISUI/ISToolTipInv'] = true
    ISContextMenu = {}
    Events = {OnGameStart = event()}
    for _, name in ipairs({'SVSIT_main', 'SVSIT_logic', 'SVSIT_parser', 'SVSIT_data', 'SVSIT_translate',
        'PZSurvivorToolkit/InventoryTooltip', 'PZSurvivorToolkit/InventoryMediaTooltip'}) do package.loaded[name] = nil end
    RecMedia = {test = {itemDisplayName = 'Media.Test', lines = {
        {codes = 'CRP=3'}, {codes = 'CRP=7'}, {codes = 'RCP=Base.RecipeOne'}, {codes = 'RCP=Base.RecipeOne'},
    }}, empty = {itemDisplayName = 'Empty episode', lines = {{codes = 'BOR=3'}}}}
    dofile(NativeVHSTooltipRoot .. '/SVSIT_main.lua')
end
local function install()
    local service = load('InventoryTooltip')
    package.loaded['PZSurvivorToolkit/InventoryTooltip'] = service
    local media = load('InventoryMediaTooltip')
    package.loaded['PZSurvivorToolkit/InventoryMediaTooltip'] = media
    media.install()
    return service, media
end
local function maxBottom(destination)
    local bottom = 0
    for _, text in ipairs(destination.texts) do
        if not text.measureOnly then bottom = math.max(bottom, text.y + destination:getLineSpacing()) end
    end
    return bottom
end

-- Execute upstream unchanged to reproduce the disagreement with native sizing.
reset(); Events.OnGameStart.fire()
local upstream = window(item()); upstream:render()
assert(upstream.height < maxBottom(upstream.tooltip), 'upstream reproduction stopped exposing its unmeasured appended text')
ISContextMenu.instance = {visibleCheck = true}
local upstreamHidden = window(item()); upstreamHidden:render()
assert(#upstreamHidden.tooltip.texts > 0 and #upstreamHidden.tooltip.nativeCalls == 0,
    'upstream reproduction stopped exposing its context-menu visibility bypass')
print('Inventory media tooltip: actual upstream sizing and inherited-render guard bypass reproduced.')

reset(); local _, media = install()
assert(ISToolTipInv._vhsHooked, 'must suppress only the upstream render installer before game start')
local ownedRender = ISToolTipInv.render
media.install(); assert(ownedRender == ISToolTipInv.render, 'install must be idempotent')
Events.OnGameStart.fire()
assert(ownedRender == ISToolTipInv.render, 'upstream must still build its data without adding its old render wrapper')
local logic = require 'SVSIT_logic'
assert(#logic.RecMedia.test.skillTexts == 1 and #logic.RecMedia.test.recipeTexts == 1,
    'upstream parsing, deduplication and localization must remain the data owner')
local expectedSkill, expectedRecipe = logic.RecMedia.test.skillTexts[1], logic.RecMedia.test.recipeTexts[1]
local owned = window(item()); owned:setCharacter(player); owned:render()
assert(#owned.tooltip.nativeCalls == 2 and owned.tooltip.nativeCalls[1].measureOnly
    and not owned.tooltip.nativeCalls[2].measureOnly, 'must retain native measure/draw passes')
assert(owned.width == owned.tooltip.width and owned.height == owned.tooltip.height and owned.height >= maxBottom(owned.tooltip))
local seen, measured, drawn = {}, 0, 0
for _, text in ipairs(owned.tooltip.texts) do
    assert(text.font == UIFont.Small)
    assert(text.x + #text.text * 6 <= owned.width, 'native measured width excludes appended text')
    if text.measureOnly then measured = measured + 1
    else drawn = drawn + 1; seen[text.text] = text end
end
assert(measured == 4 and drawn == 4 and owned.height == 40 + 4 * owned.tooltip:getLineSpacing(),
    'each native pass must contain exactly the existing two sections at native line spacing')
assert(seen['- ' .. expectedSkill] and seen['- ' .. expectedRecipe], 'must render existing upstream texts unchanged')
assert(seen['Skills: '] or seen['Skills:'], 'skill section heading disappeared')
local skillLine = seen['- ' .. expectedSkill]
assert(skillLine.color[1] == 1 and skillLine.color[2] == 1 and skillLine.color[3] == 1)
local heading = seen['Skills: '] or seen['Skills:']
assert(heading.color[1] == 1 and heading.color[2] == 1 and heading.color[3] == 0)
assert(owned.backgroundColor.a == 0.5 and owned.borderColor.a == 1)
assert(#owned.backgrounds == 1 and owned.backgrounds[1].height == owned.height)
assert(logic.RecMedia.test.skillTexts[1] == expectedSkill and logic.RecMedia.test.recipeTexts[1] == expectedRecipe)

-- Exercise the inherited renderer guard, even though current B42 leaves this
-- legacy singleton unset. Real hover visibility belongs to the inventory pane's
-- updateTooltip lifecycle and is checked by the native fixture.
ISContextMenu.instance = {visibleCheck = true}
local hidden = window(item()); hidden:render()
assert(#hidden.tooltip.texts == 0 and #hidden.tooltip.nativeCalls == 0 and #hidden.backgrounds == 0)
ISContextMenu.instance = nil
local anchor = window(item()); anchor.anchorBottomLeft = {x = 100, y = 400}; anchor:render()
assert(anchor.y == 400 - anchor.height, 'must preserve native bottom anchor with the complete tooltip height')
local edge = window(item()); edge.followMouse = true; edge:render()
assert(edge.x >= 0 and edge.y >= 0 and edge.x + edge.width < 640 and edge.y + edge.height < 480)
local clothing = window(item('Base.TestClothing')); clothing:render()
assert(#clothing.tooltip.nativeCalls == 2 and #clothing.tooltip.layouts == 0, 'VHS integration must not swallow unrelated clothing')
for _, value in ipairs({item(nil, 'Empty episode'), item('Base.NotVideo'), item(nil, 'Unknown episode')}) do
    local plain = window(value); plain:render()
    assert(plain.height == 40 and #plain.tooltip.layouts == 0 and #plain.tooltip.nativeCalls == 2)
end

-- Cleanup concerns both a failed native call and direct calls after that failure.
local brokenItem, brokenTarget = item(), target(); brokenItem.throw = true
local broken = window(brokenItem, brokenTarget)
assert(not pcall(broken.render, broken))
assert(broken.backgroundColor.a == 0.5 and broken.borderColor.a == 1, 'errors must not leave alpha changes')
brokenItem.throw = false
assert(brokenItem:DoTooltip(brokenTarget) == 'native-result' and #brokenTarget.layouts == 0,
    'failed rendering leaked the scoped provider into direct item calls')
broken:render(); assert(#brokenTarget.layouts > 0)
local append, appendFailureTarget = media.append, target()
media.append = function() error('media append failure') end
local appendFailure = window(item(), appendFailureTarget)
local ok, message = pcall(appendFailure.render, appendFailure)
assert(not ok and tostring(message):find('media append failure', 1, true))
assert(appendFailure.backgroundColor.a == 0.5 and appendFailure.borderColor.a == 1)
media.append = append
local layoutCount = #appendFailureTarget.layouts
appendFailure.item:DoTooltip(appendFailureTarget)
assert(#appendFailureTarget.layouts == layoutCount, 'failed provider append leaked its context')
appendFailure:render(); assert(#appendFailureTarget.layouts > layoutCount)

-- An unavailable mod and a wrapper already installed by upstream are left alone.
reset(); active = false
local absentRender = ISToolTipInv.render; install()
assert(ISToolTipInv.render == absentRender and not ISToolTipInv._vhsHooked)
active = true
reset(); Events.OnGameStart.fire()
local lateRender = ISToolTipInv.render; install()
assert(ISToolTipInv.render == lateRender, 'late install must not stack another owner over an existing VHS wrapper')
print('Inventory media tooltip: upstream data, native sizing/placement/visibility, guards and error cleanup passed.')
