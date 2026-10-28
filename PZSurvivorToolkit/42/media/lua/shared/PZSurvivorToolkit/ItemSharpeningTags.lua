-- Native sharpening subjects, independent of the player's tools or workstation.
-- Reading InventoryItem.isSharpenable/getSharpness can clamp the stored value;
-- use the existing attribute directly so classification never changes the item.
local Sharpening = {}

local function attribute(container)
    if not container or not container.getAttribute or not Attribute or not Attribute.Sharpness then return nil end
    local value = container:getAttribute(Attribute.Sharpness)
    if value == nil then return false end
    return true, value
end

-- Physical subjects follow isSharpenable's tag/attribute/current-max comparison
-- plus the native crafting input's broken-item guard. Kept inputs permit favorite
-- items. The dull threshold is irrelevant: any missing sharpness can be restored.
-- A script has no current condition or sharpness; its second result preserves
-- both sharpenable and fully sharpened/broken states when metadata proves them.
function Sharpening.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    local source = item or script
    if not source or not source.hasTag or not ItemTag or not ItemTag.SHARPENABLE then return nil end
    local tagged = source:hasTag(ItemTag.SHARPENABLE)
    if tagged == false then return false end
    if tagged ~= true then return nil end
    if item then
        if not item.isBroken then return nil end
        local broken = item:isBroken()
        if broken == true then return false end
        if broken ~= false or not item.getAttributes then return nil end
        local container = item:getAttributes()
        if container == nil then return false end
        local present, value = attribute(container)
        if present == false then return false end
        if present ~= true or not value.getFloatValue or not item.getMaxSharpness then return nil end
        local sharpness, maximum = value:getFloatValue(), item:getMaxSharpness()
        if type(sharpness) ~= "number" or type(maximum) ~= "number"
            or sharpness ~= sharpness or maximum ~= maximum then return nil end
        -- getSharpness only normalizes values above the current maximum.
        -- applyMaxSharpness then uses setSharpness, which also clamps to [0,1].
        -- Preserve that result locally, even for unusual imported attributes.
        if sharpness > maximum then sharpness = math.max(0, math.min(1, maximum)) end
        return sharpness < maximum
    end
    if not script.getComponentScriptFor or not ComponentType or not ComponentType.Attributes then return nil end
    local component = script:getComponentScriptFor(ComponentType.Attributes)
    if component == nil then return false end
    if not component.getTemplateContainer then return nil end
    local container = component:getTemplateContainer()
    if container == nil then return nil end
    local present = attribute(container)
    if present == false then return false end
    if present then return nil, {false, true} end
    return nil
end

return Sharpening
