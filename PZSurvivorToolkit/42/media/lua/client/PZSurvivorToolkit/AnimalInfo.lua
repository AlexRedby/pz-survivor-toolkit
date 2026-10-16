require "ISUI/Animal/ISAnimalUI"

local function deadInHutch(self)
    return self.animal and self.animal:getHealth() <= 0 and self.animal:getHutch()
end

local function containsAnimal(hutch, animal)
    if hutch:getAnimal(animal:getData():getHutchPosition()) == animal then return true end
    for index = 0, hutch:getMaxNestBox() do
        if hutch:getAnimalInNestBox(index) == animal then return true end
    end
    return false
end

local prerender = ISAnimalUI.prerender
function ISAnimalUI:prerender()
    local hutch = deadInHutch(self)
    if not hutch then return prerender(self) end
    local square = hutch:getSquare()
    if not square or not containsAnimal(hutch, self.animal)
            or (not AnimalContextMenu.cheat and square:DistToProper(self.chr) > 4) then
        self:close()
        return
    end

    -- Native prerender closes dead animals before drawing their still-available hutch data.
    ISCollapsableWindowJoypad.prerender(self)
    local size = self.animal:getData():getSize()
    self.avatarPanel:setZoom(self.avatarDefinition.zoom * size)
    self.avatarPanel:setXOffset(self.avatarDefinition.xoffset * size)
    self.avatarPanel:setYOffset(self.avatarDefinition.yoffset * size)
    self:updateAvatar()
    local x, y, w, h = self.avatarX, self.avatarY, self.avatarWidth, self.avatarHeight
    self:drawRectBorder(x - 2, y - 2, w + 4, h + 4, 1, 0.3, 0.3, 0.3)
    self:drawTextureScaled(self.avatarBackgroundTexture, x, y, w, h, 1, 0.4, 0.4, 0.4)
end

local render = ISAnimalUI.render
function ISAnimalUI:render()
    if self.toolkitAnimalInfoButtons then
        for button, enabled in pairs(self.toolkitAnimalInfoButtons) do button:setEnable(enabled) end
        self.toolkitAnimalInfoButtons = nil
    end
    local result = render(self)
    if deadInHutch(self) then
        self.toolkitAnimalInfoButtons = {}
        for _, button in ipairs({self.renameBtn, self.feedBtn, self.milkAnimalBtn, self.ageBtn, self.genderBtn}) do
            self.toolkitAnimalInfoButtons[button] = button.enable
            button:setEnable(false)
        end
    end
    return result
end
