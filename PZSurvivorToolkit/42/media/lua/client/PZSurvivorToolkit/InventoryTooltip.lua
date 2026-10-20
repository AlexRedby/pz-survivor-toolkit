require "ISUI/ISToolTipInv"
local Tooltip = {}
local providers, registered = {}, {}
local contexts, installed = {}, {}

function Tooltip.register(id, describe, append)
    if registered[id] then return end
    registered[id] = true
    providers[#providers + 1] = {describe = describe, append = append}
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
