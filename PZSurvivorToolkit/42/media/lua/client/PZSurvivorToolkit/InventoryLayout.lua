require "ISUI/ISInventoryPane"

local function install()
    local paneClass = CleanUI_Clean_ISInventoryPane or ISInventoryPane
    if paneClass.PZSurvivorToolkitLayoutInstalled then return end
    paneClass.PZSurvivorToolkitLayoutInstalled = true
    local renderdetails = paneClass.renderdetails
    paneClass.renderdetails = function(self, doDragged, ...)
        if self.cleanUIItemIconSize then
            local arrowSize = math.min(15, 8 + getCore():getOptionFontSizeReal() * 2)
            -- Native arrows are centred between x=2 and the icon: leave a 2px gap.
            local minimum = math.ceil((self.itemHgt + self.cleanUIItemIconSize) / 2) + arrowSize + 6
            if self.column2 < minimum then
                self.column3 = self.column3 + minimum - self.column2
                self.column2 = minimum
                self:onResize()
            end
        end
        return renderdetails(self, doDragged, ...)
    end
end

Events.OnGameStart.Add(install)
