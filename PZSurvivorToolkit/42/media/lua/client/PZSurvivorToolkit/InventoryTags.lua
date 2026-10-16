require "ISUI/ISInventoryPane"
require "ISUI/ISToolTip"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Visuals = require "PZSurvivorToolkit/TagVisuals"

local InventoryTags = {}
PZSurvivorToolkit.InventoryTags = InventoryTags
local installed, widths = {}, {}

local function measure(font, text)
    local cache = widths[font]
    if not cache then cache = {}; widths[font] = cache end
    if not cache[text] then cache[text] = getTextManager():MeasureStringX(font, text) end
    return cache[text]
end

local function categoryBounds(pane)
    local padding = pane.cleanUIItemIconSize and pane.padding or 8
    local left, right = pane.column3 + padding, (pane.column4 or pane.width) - padding
    if pane.cleanUIItemIconSize then
        local rarity = pane._cleanUIRarityMetricsCache
        local weight = pane._cleanUIWeightMetricsCache
        local state = pane._cleanUIColumnBoundaryCache
        right = rarity and rarity.value and rarity.value.categoryRight
            or weight and weight.value and weight.value.categoryRight
            or state and state.state and state.state.contentRight or right
    elseif pane:isVScrollBarVisible() then
        right = right - pane.vscroll:getWidth()
    end
    return left, math.min(right, pane.width - 1)
end

local function pill(pane, draw, text, x, y, width, height, textY, font, style, iconSize)
    style = style or Visuals.get()
    local r, g, b = style.r * 0.30, style.g * 0.30, style.b * 0.30
    pane:drawRect(x + 2, y, width - 4, height, 0.95, r, g, b)
    pane:drawRect(x + 1, y + 1, 1, height - 2, 0.95, r, g, b)
    pane:drawRect(x, y + 2, 1, height - 4, 0.95, r, g, b)
    pane:drawRect(x + width - 2, y + 1, 1, height - 2, 0.95, r, g, b)
    pane:drawRect(x + width - 1, y + 2, 1, height - 4, 0.95, r, g, b)
    local textX = x + 4
    if style.texture then
        pane:drawTextureScaledAspect(style.texture, textX, y + (height - iconSize) / 2,
            iconSize, iconSize, 1, 1, 1, 1)
        textX = textX + iconSize + 3
    end
    draw(pane, text, textX, textY, 0.94, 0.94, 0.94, 1, font)
end

local function drawTags(pane, draw, text, x, y, font, rightAligned)
    local left, right = categoryBounds(pane)
    if pane._cleanUICategoryCollapsed or x ~= (rightAligned and right or left) then return false end
    local row = math.floor((y - pane.headerHgt) / pane.itemHgt) + 1
    local group = pane.items and pane.items[row]
    if type(group) ~= "table" or not group.items or group.type == "separator" then return false end
    local item = group.items[1]
    if not item or item:getJobDelta() > 0 then return false end
    local key = item:getDisplayCategory() or item:getCategory()
    local cached = group._cleanUICategoryTextCache
    local categoryText = cached and cached.value or getText("IGUI_ItemCat_" .. key)
    if text ~= categoryText then return false end
    local tags = Tags.forItem(item)
    if not tags or #tags == 0 then return false end
    local top = pane.headerHgt + (row - 1) * pane.itemHgt
    local height = math.min(pane.itemHgt - 2, pane.fontHgt + 4)
    local iconSize = math.max(0, math.min(16, height - 4))
    local labels, sizes, styles, fullWidth = {}, {}, {}, 0
    for i, id in ipairs(tags) do
        labels[i] = Tags.label(id)
        styles[i] = Visuals.get(id, tags)
        sizes[i] = measure(font, labels[i]) + 8 + (styles[i].texture and iconSize + 3 or 0)
        fullWidth = fullWidth + sizes[i] + (i > 1 and 3 or 0)
    end
    local available, count, used = math.max(0, right - left), #labels, fullWidth
    local overflow
    while count > 0 and used > available do
        count = count - 1
        used = 0
        for i = 1, count do used = used + sizes[i] + 3 end
        overflow = "+" .. (#labels - count)
        used = used + measure(font, overflow) + 8
    end
    if used > available then count, overflow, used = 0, nil, 0 end
    local chipY = top + (pane.itemHgt - height) / 2
    local cursor = rightAligned and right - used or left
    for i = 1, count do
        pill(pane, draw, labels[i], cursor, chipY, sizes[i], height, y, font, styles[i], iconSize)
        cursor = cursor + sizes[i] + 3
    end
    if overflow then pill(pane, draw, overflow, cursor, chipY, measure(font, overflow) + 8, height, y, font) end
    pane.toolkitTagRows[row] = {left = left, right = right, drawnChips = count + (overflow and 1 or 0),
        description = table.concat(labels, " <LINE> ")}
    return true
end

local function hideTooltip(pane)
    local tooltip = pane.toolkitTagTooltip
    if tooltip then tooltip:setVisible(false); tooltip:removeFromUIManager() end
end

local function updateHeader(pane)
    local header = pane.typeHeader
    if not header then return end
    if Tags.enabled() and pane.mode == "details" then
        if header.title ~= pane.toolkitTagHeaderRendered then
            pane.toolkitTagHeaderOriginal = header.title
        end
        local original = pane.toolkitTagHeaderOriginal or ""
        local category = getText("IGUI_invpanel_Category")
        local suffix = original:sub(1, #category) == category and original:sub(#category + 1) or ""
        local title = getText("UI_PZSurvivorToolkit_item_tags_header") .. suffix
        if header.title ~= title then header:setTitle(title) end
        pane.toolkitTagHeaderRendered = title
    else
        if pane.toolkitTagHeaderRendered and header.title == pane.toolkitTagHeaderRendered then
            header:setTitle(pane.toolkitTagHeaderOriginal)
        end
        pane.toolkitTagHeaderOriginal, pane.toolkitTagHeaderRendered = nil, nil
    end
end

local function updateTooltip(pane)
    updateHeader(pane)
    if not Tags.enabled() or pane.mode ~= "details" or not pane:isReallyVisible() or not pane:isMouseOver()
        or pane.doController or pane.dragging or pane.draggingMarquis then hideTooltip(pane); return end
    local context = getPlayerContextMenu(pane.player)
    if context and context:isAnyVisible() then hideTooltip(pane); return end
    local x, y = pane:getMouseX(), pane:getMouseY()
    local row = math.floor((y - pane.headerHgt) / pane.itemHgt) + 1
    local hit = pane.toolkitTagRows and pane.toolkitTagRows[row]
    if not hit or x < hit.left or x > hit.right or y + pane:getYScroll() < pane.headerHgt then
        hideTooltip(pane); return
    end
    local tooltip = pane.toolkitTagTooltip
    if not tooltip then
        tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip.owner = pane
        pane.toolkitTagTooltip = tooltip
    end
    tooltip:setDescription(hit.description)
    tooltip:setVisible(true)
    tooltip:addToUIManager()
    tooltip:bringToTop()
end

local function install(class)
    if not class or installed[class] then return end
    installed[class] = true
    local render, tooltip = class.renderdetails, class.updateTooltip
    class.renderdetails = function(pane, dragged, ...)
        if dragged or pane.mode ~= "details" or not Tags.enabled() then
            if not dragged then pane.toolkitTagRows = nil; hideTooltip(pane) end
            local result = render(pane, dragged, ...)
            updateHeader(pane)
            return result
        end
        pane.toolkitTagRows = {}
        local savedText, savedRight = rawget(pane, "drawText"), rawget(pane, "drawTextRight")
        local draw, drawRight = pane.drawText, pane.drawTextRight
        pane.drawText = function(self, text, x, y, r, g, b, a, font)
            if not drawTags(self, draw, text, x, y, font or self.font, false) then
                return draw(self, text, x, y, r, g, b, a, font)
            end
        end
        pane.drawTextRight = function(self, text, x, y, r, g, b, a, font)
            if not drawTags(self, draw, text, x, y, font or self.font, true) then
                return drawRight(self, text, x, y, r, g, b, a, font)
            end
        end
        -- Restore the instance methods even when the native renderer raises an error.
        local ok, result = pcall(render, pane, dragged, ...)
        pane.drawText, pane.drawTextRight = savedText, savedRight
        if not ok then error(result) end
        updateHeader(pane)
        return result
    end
    class.updateTooltip = function(pane, ...)
        local result = tooltip(pane, ...)
        updateTooltip(pane)
        return result
    end
end

function InventoryTags.install()
    install(ISInventoryPane)
    install(CleanUI_Clean_ISInventoryPane)
    install(CleanUI_Vanilla_ISInventoryPane)
end

Events.OnGameStart.Add(function()
    InventoryTags.install()
    if CleanUI_RegisterInventoryUiToggleCallback then
        CleanUI_RegisterInventoryUiToggleCallback(InventoryTags.install)
    end
end)

return InventoryTags
