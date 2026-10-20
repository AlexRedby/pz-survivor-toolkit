local Boundary = require "PZSurvivorToolkit/InventoryTooltip"
local ClothingTooltip = {}

function ClothingTooltip.appendFlags(target, item)
    local player = target:getCharacter()
    if not player or not item:isNoRecipes(player) then return end
    -- BCI's copied item header asks ScriptItem for this per-instance flag.
    -- Use the native label/layout (including its translated line breaks).
    local layout = target:beginLayout()
    local color = getCore():getBadHighlitedColor()
    layout:addItem():setLabel(getText("Tooltip_NoRecipes_More"), color:getR(), color:getG(), color:getB(), 1)
    local bottom = target.padBottom or 5
    local y = layout:render(target.padLeft or 5, target:getHeight() - bottom, target)
    target:endLayout(layout)
    target:setHeight(y + bottom)
end

function ClothingTooltip.install()
    if ClothingTooltip.installed or not getActivatedMods():contains("EURY_CLOTHINGINFO") then return end
    require "BCI/Patches/TooltipInv"
    local controller = EuryTooltipController
    local clothing = controller.providers.BetterClothingInfo
    local renderMain, renderControlled = clothing.renderMain, controller.renderControlled
    clothing.renderMain = function(self, ctx)
        renderMain(self, ctx)
        if self:isClothing(ctx) then ClothingTooltip.appendFlags(ctx.tooltip, ctx.item) end
    end
    controller.renderControlled = function(self, panel, provider, ctx)
        -- Other owners/row providers keep their own composition contract. The
        -- selected pack uses BCI's clothing body and optional comparison only.
        if provider ~= clothing or not clothing:isClothing(ctx) or #self:collectRowGroups(ctx) > 0 then
            return renderControlled(self, panel, provider, ctx)
        end
        ctx.ownerProvider = provider
        local blocks = {function() provider:renderMain(ctx) end}
        local side = provider:getSidePanel(ctx)
        if side and side.render then blocks[#blocks + 1] = side.render end
        return Boundary.renderBlocks(panel, blocks, {
            padding = provider:getPadX(ctx), gap = provider.attachedGap, alpha = self.backgroundAlpha,
        })
    end
    ClothingTooltip.installed = true
end

return ClothingTooltip
