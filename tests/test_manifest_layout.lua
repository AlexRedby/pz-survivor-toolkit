-- Exercise the real window layout, not a second copy of its geometry calculations.
UIFont = {Small = 'small'}
local fh, font, screenHeight = 16, {}, 900
getTextManager = function() return {
    getFontHeight = function() return fh end,
    getFontFromEnum = function() return font end,
} end
getCore = function() return {getScreenHeight = function() return screenHeight end} end
local status = 'The warehouse remembers the last known contents of unloaded containers.'
getText = function(key, a, b)
    if key:find('Totals') then return 'Shown: ' .. a .. ', total: ' .. b end
    return status
end
LootSorter = {addOrReplaceHandler = function() end}
Events = {OnMainMenuEnter = {}}
require = function() return {} end
local class
ISCollapsableWindowJoypad = {derive = function() class = {}; return class end}
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/LootSorter_Manifest.lua')
local function widget(w, h)
    return {width = w or 0, height = h or 0, x = 0, y = 0, items = {{height = 24}},
        setX = function(s, v) s.x = v end, setY = function(s, v) s.y = v end,
        getX = function(s) return s.x end, getY = function(s) return s.y end,
        setWidth = function(s, v) s.width = v end, setHeight = function(s, v) s.height = v end,
        getWidth = function(s) return s.width end, getHeight = function(s) return s.height end,
        setScrollHeight = function(s, v) s.scrollHeight = v end}
end
local win = widget(640, 600)
setmetatable(win, {__index = class})
win.titleBarHeight = function() return 24 end
win.resizeWidgetHeight = function() return fh / 2 + 5 end
for _, key in ipairs({'filterEntry', 'tagPicker', 'btnItem', 'btnCat', 'btnCount', 'listBox', 'locations', 'footer'}) do
    win[key] = widget()
end
local paginations = 0
win.footer.setText = function(s, text) s.text = text end
-- Native RichTextPanel wraps the footer; this double supplies measured wrapped height.
win.footer.paginate = function(s)
    paginations = paginations + 1
    local text = s.text:gsub('<[^>]+>', '')
    local lines = math.ceil(#text * fh / 2 / s.width) + 1
    s.height = lines * fh
end
local function check()
    win:updateFooter()
    local footer, locations, list = win.footer, win.locations, win.listBox
    assert(footer.y + footer.height <= win.height - win:resizeWidgetHeight() - 8,
        'footer glyphs would be overpainted by the native resize strip')
    assert(locations.y + locations.height < footer.y, 'locations overlap the footer')
    assert(list.y + list.height < win.locationsHeadingY, 'item list covers the location heading')
    assert(win.locationsHeadingY + fh < locations.y, 'heading overlaps location rows')
    assert(list.height >= list.itemheight and locations.height >= locations.itemheight,
        'both lists must retain a visible row and native scrolling')
    assert(list.itemheight >= fh + 4 and locations.itemheight >= fh * 2 + 4,
        'large fonts escape their single/two-line rows')
    assert(locations.items[1].height == locations.itemheight and locations.scrollHeight == locations.itemheight,
        'font reflow must update existing entries and scrollbar extent')
    assert(win.filterEntry.height > fh and win.btnCount.height > fh, 'controls clip their text')
    local warm = paginations
    win:updateFooter()
    assert(paginations == warm, 'unchanged footer must not paginate every frame')
end
check()
win.width, win.height = 480, 440; check()
assert(win.footer.height > fh * 2, 'narrow footer must wrap rather than truncate')
status = string.rep('Last known warehouse state. ', 8); check()
for _, height in ipairs({19, 26, 33, 38}) do
    fh, font = height, {}
    win.width, win.height = 640, 440; check()
    win.width, win.height = 1000, 850; check()
end
win.shownCount, win.totalCount = 4, 125
check()
assert(win.footer.text:find('125'), 'changed totals must update the footer')
print('Warehouse layout: resize strip, wrapping, default/minimum/large sizes, font heights, scroll extents and cached reflow passed.')

-- A large font on a shorter screen can show fewer location rows, retaining scrolling.
status = 'Shared warehouse | unloaded areas show last known contents'
screenHeight, win.width, win.height = 600, 480, 440
check()
assert(win.height <= screenHeight, 'minimum size must not exceed the screen')
