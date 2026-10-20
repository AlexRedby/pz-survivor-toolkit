require "ISUI/ISToolTipInv"
local Tooltip = {}
local providers, registered = {}, {}
local contexts, installed = {}, {}

function Tooltip.register(id, describe, append)
    if registered[id] then return end
    registered[id] = true
    providers[#providers + 1] = {describe = describe, append = append}
end

-- Custom content owners can supply adjacent blocks without owning another
-- placement pipeline. Measure the complete window before context/anchor
-- positioning; native inventory panes still own tooltip visibility/lifetime.
function Tooltip.renderBlocks(panel, blocks, style)
    if ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
    local target, sizes = panel.tooltip, {}
    local padding, gap = style.padding or 0, style.gap or 0
    local width, height = 0, 0
    target:setMeasureOnly(true)
    local ok, err = pcall(function()
        for i, block in ipairs(blocks) do
            target:setWidth(50)
            block(target)
            local w, h = target:getWidth() + padding, target:getHeight()
            sizes[i] = {x = width, w = w, h = h}
            width = width + w + gap
            height = math.max(height, h)
        end
    end)
    target:setMeasureOnly(false)
    if not ok then error(err) end
    width = width - gap

    local mx, my = getMouseX() + 24, getMouseY() + 24
    if not panel.followMouse then
        mx, my = panel:getX(), panel:getY()
        if panel.anchorBottomLeft then mx, my = panel.anchorBottomLeft.x, panel.anchorBottomLeft.y - height end
    end
    local core = getCore()
    panel:setWidth(width)
    panel:setHeight(height)
    panel:setX(math.max(0, math.min(mx, core:getScreenWidth() - width - 1)))
    panel:setY(math.max(0, math.min(my, core:getScreenHeight() - height - 1)))
    local menu = panel.contextMenu
    if menu and menu.joyfocus then
        panel:setX(getPlayerScreenLeft(menu.player) + 60)
        panel:setY(getPlayerScreenTop(menu.player) + 60)
    elseif menu and menu.currentOptionRect then
        panel:adjustPositionToAvoidOverlap(menu.currentOptionRect)
        -- The native helper offsets self.x by -11 for its mouse tooltip. A
        -- menu-owned window uses the returned rectangle as its outer frame.
        panel:setX(target:getX())
        panel:setY(target:getY())
    elseif panel.followMouse and not menu then
        target:setX(panel:getX())
        target:setY(panel:getY())
        panel:adjustPositionToAvoidOverlap({x = mx - 48, y = my - 48, width = 48, height = 48})
        -- Use the helper's outer rectangle, including its left-edge clamp.
        panel:setX(target:getX())
        panel:setY(target:getY())
    end

    local bg, border = panel.backgroundColor, panel.borderColor
    for i, block in ipairs(blocks) do
        local size = sizes[i]
        panel:drawRect(size.x, 0, size.w, size.h, style.alpha or bg.a, bg.r, bg.g, bg.b)
        panel:drawRectBorder(size.x, 0, size.w, size.h, border.a, border.r, border.g, border.b)
        target:setX(panel:getX() + size.x + padding)
        target:setY(panel:getY())
        target:setWidth(50)
        block(target)
    end
end

-- Extend the exact native item/tooltip pair in both measurement and drawing.
-- Other renderers retain their visibility, placement and background decisions.
local function observeItem(item)
    local meta = getmetatable(item)
    local methods = meta and meta.__index
    if not methods or installed[methods] or not methods.DoTooltip then return end
    local native = methods.DoTooltip
    methods.DoTooltip = function(value, target, ...)
        local context = contexts[target]
        if not context or context.item ~= value then return native(value, target, ...) end
        -- Inherited class methods may already forward through a wrapped parent.
        context.depth = context.depth + 1
        local ok, result = pcall(native, value, target, ...)
        context.depth = context.depth - 1
        if not ok then error(result) end
        if context.depth == 0 then
            for _, section in ipairs(context.sections) do section.append(target, section.state) end
        end
        return result
    end
    installed[methods] = true
end

function Tooltip.install()
    if Tooltip.installed then return end
    Tooltip.installed = true
    local setCharacter, render = ISToolTipInv.setCharacter, ISToolTipInv.render
    ISToolTipInv.setCharacter = function(self, character)
        self.toolkitTooltipCharacter = character
        return setCharacter(self, character)
    end
    ISToolTipInv.render = function(self, ...)
        if not self.item then return render(self, ...) end
        local player = (self.tooltip.getCharacter and self.tooltip:getCharacter())
            or self.toolkitTooltipCharacter or self.chr or getPlayer()
        local sections = {}
        for _, provider in ipairs(providers) do
            local state = provider.describe(player, self.item)
            if state then sections[#sections + 1] = {state = state, append = provider.append} end
        end
        if #sections == 0 then return render(self, ...) end
        observeItem(self.item)
        local previous = contexts[self.tooltip]
        contexts[self.tooltip] = {item = self.item, sections = sections, depth = 0}
        local ok, result = pcall(render, self, ...)
        contexts[self.tooltip] = previous
        if not ok then error(result) end
        return result
    end
end

return Tooltip
