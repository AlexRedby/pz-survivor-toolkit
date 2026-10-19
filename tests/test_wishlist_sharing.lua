if not NativeWishlistGameRoot then
    print("SKIP wishlist player picker: supply --game for native combo/filter source")
    return
end

-- Exercise native filtering, hit testing and selection with only rendering/Java UI doubled.
PZSurvivorToolkit = {}
require = function(name)
    if name == "PZSurvivorToolkit/UIStyle" then
        return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua")
    end
end
string.trim = function(value) return value:match("^%s*(.-)%s*$") end
string.contains = function(value, part) return value:find(part, 1, true) ~= nil end
UIFont = {Small = 1}
getText = function(key) return key end
getTextManager = function() return {getFontHeight = function() return 14 end,
    MeasureStringX = function(_, _, value) return #value * 7 end} end
getCore = function() return {getScreenHeight = function() return 1080 end} end
getSoundManager = function() return {playUISound = function() end} end
getTexture = function() return {getWidthOrig = function() return 16 end} end
UITransition = {new = function() return {} end}
Events = {OnMainMenuEnter = {Add = function() end}}

local classes, Base = {}, {}
function Base:derive(name)
    local class = setmetatable({}, {__index = self}); class.__index = class
    classes[name] = class
    return class
end
function Base:new(x, y, width, height)
    return setmetatable({x=x, y=y, width=width, height=height, items={}, options={}, selected=0,
        visible=true, itemheight=24, borderColor={}, backgroundColor={}, vscroll={setHeight=function() end}}, self)
end
Base.__index = Base
function Base:initialise() end
function Base:instantiate() if self.createChildren then self:createChildren() end end
function Base:addChild(child) child.parent = self end
function Base:titleBarHeight() return 20 end
function Base:getBottom() return self.y + self.height end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
function Base:getAbsoluteX() return self.x end
function Base:getAbsoluteY() return self.y end
function Base:getYScroll() return 0 end
function Base:setYScroll() end
function Base:setScrollHeight() end
function Base:setAlwaysOnTop() end
function Base:setCapture() end
function Base:ensureVisible() end
function Base:setFont() self.fontHgt, self.itemheight = 14, 22 end
function Base:isVisible() return self.visible end
Base.isReallyVisible = Base.isVisible
function Base:isMouseOver() return true end
function Base:isMouseOverScrollBar() return false end
function Base:focus() self.focused = true end
function Base:unfocus() self.focused = false end
function Base:selectAll() end
function Base:setText(value) self.value = value end
function Base:getInternalText() return self.value or "" end
function Base:addToUIManager() self.managed = true end
function Base:removeFromUIManager() self.managed = false end
function Base:drawText() end
function Base:drawRect() end
function Base:drawRectBorder() end
for _, name in ipairs({"X", "Y", "Width", "Height", "Visible", "Enable"}) do
    Base["set" .. name] = function(self, value) self[name:lower()] = value end
end
function Base:clear() self.items = {} end
function Base:size() return #self.items end
function Base:addItem(label, data)
    self.items[#self.items + 1] = {text=label, item=data, index=#self.items + 1, height=self.itemheight}
end
function Base:removeItem(label)
    for i, row in ipairs(self.items) do if row.text == label then table.remove(self.items, i); return end end
end
function Base:addOption(label) self.options[#self.options + 1] = label end
function Base:setSelected(_, value) self.checked = value end
function Base:isSelected() return self.checked end
function Base:prerender() end

ISPanel, ISPanelJoypad = Base, Base
local native = NativeWishlistGameRoot .. "/media/lua/client/ISUI/"
dofile(native .. "ISScrollingListBox.lua")
local rowAt = ISScrollingListBox.rowAt
ISScrollingListBox = Base:derive("List")
ISScrollingListBox.rowAt = rowAt
function ISScrollingListBox:prerender()
    local y = 0
    for _, row in ipairs(self.items) do
        local bottom = self:doDrawItem(y, row, false)
        row.height, y = bottom - y, bottom
    end
end
ISTextEntryBox = Base:derive("Entry")
function ISTextEntryBox:new(value, x, y, width, height)
    local entry = Base.new(self, x, y, width, height); entry.value = value; return entry
end
dofile(native .. "ISComboBox.lua")
ISCollapsableWindow = Base:derive("Window")
ISButton, ISTickBox = Base:derive("Button"), Base:derive("TickBox")

local function player(name) return {getUsername = function() return name end} end
local online = {player("Alice"), player("Bob.Case"), player("Other"), player("Bob.Case")}
local multiplayer, saved = true
isClient = function() return multiplayer end
getOnlinePlayers = function() return {size=function() return #online end, get=function(_, i) return online[i+1] end} end
getSpecificPlayer = function() return online[1] end
Faction = {getPlayerFaction = function() return {} end}
PZSurvivorWishlist = {Client={edit=function(_, action, args) assert(action == "share"); saved=args end}}
dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorWishlist/UI.lua")
local sharing = classes.PZSWSharing:new(0, 0, 510, 410)
sharing.playerNum, sharing.listId = 0, "Alice"
sharing.source = {owner="Alice", members={Offline=true}, faction="Friends"}
sharing:initialise()
local combo = sharing.selector
local function has(name)
    for _, row in ipairs(sharing.list.items) do if row.item == name then return true end end
    return false
end
local function open(query)
    combo:onMouseDown(1, 1); combo:onMouseUp(1, 1)
    assert(combo.expanded and combo.editor.focused and combo:getOptionData(combo.selected) == nil)
    combo.editor:setText(query); combo.editor:onTextChange(); combo.popup:prerender()
end
local function choose(query, expected)
    open(query)
    local visible = 0
    for _, row in ipairs(combo.popup.items) do if row.height > 0 then visible=visible+1; assert(row.text == expected) end end
    assert(visible == 1, "native filtering must expose only the matching account")
    combo.popup:onMouseUp(1, 1)
    assert(combo:getOptionData(combo.selected) == expected and not combo.editor.focused)
end

sharing:prerender()
assert(#combo.options == 3 and not sharing.addButton.enable, "exclude self, duplicates and existing members")
open("no such player"); sharing:addMember()
assert(#sharing.list.items == 1, "typing must not create a member")
combo:onMouseDownOutside(0, 0); sharing:addMember()
assert(#sharing.list.items == 1)
choose("bob.c", "Bob.Case")
open("Other"); combo:onMouseDownOutside(0, 0); sharing:addMember()
assert(not has("Bob.Case") and not has("Other"), "cancelled search must not reuse the old recipient")
choose("bob.c", "Bob.Case"); sharing:prerender(); assert(sharing.addButton.enable)
sharing:addMember()
assert(has("Bob.Case") and has("Offline") and #sharing.list.items == 2, "preserve exact case and offline grants")
assert(#combo.options == 2, "staged members are no longer candidates")
choose("other", "Other")
online = {player("Alice"), player("Bob.Case"), player("NewPlayer")}
sharing:addMember(); assert(not has("Other"), "departed candidates cannot be added")
choose("new", "NewPlayer")
sharing:addMember(); assert(has("NewPlayer"), "reopening refreshes online candidates")
sharing.list.selected = 2; sharing:removeMember(); assert(not has("Bob.Case"))
choose("bob.c", "Bob.Case"); sharing:addMember(); assert(has("Bob.Case"))
open("bob"); sharing:save()
assert(saved.listId == "Alice" and saved.faction and #saved.members == 3 and has("Offline"))
assert(not sharing.visible and not sharing.managed and not combo.editor.focused and not combo.popup.managed,
    "closing releases the native popup and its editor focus")
multiplayer = false; sharing:refreshPlayers()
assert(#combo.options == 1 and combo:getOptionData(combo.selected) == nil, "single player has no remote candidates")
combo.expanded, combo.popup.managed, combo.popup.parentCombo = true, true, {}
sharing:close()
assert(combo.popup.managed, "closing Wishlist must not remove another control's shared popup")
print("PASS wishlist sharing: native search/selection, exact identities, live roster, retained grants and popup cleanup")
