-- Resolve shared appearance at the existing presentation boundary. Unloaded
-- members need no fan-out writes; their first inventory refresh reads the group.
local existing = PZSurvivorToolkit.ContainerGroupAppearance
if existing then return existing end

local Groups = require "PZSurvivorToolkit/ContainerGroups"
local Appearance = require "PZSurvivorToolkit/ContainerAppearance"
local View = {}
PZSurvivorToolkit.ContainerGroupAppearance = View
local installed = false
local refreshing = false

function View.install()
    if installed then return true end
    if not Appearance.available() then return false end
    local ok, backend = pcall(require, "BetterContainers/Customize/ModData")
    if not ok or type(backend) ~= "table" or type(backend.getEffective) ~= "function" then return false end
    local original = backend.getEffective
    backend.getEffective = function(obj, username, ci, ...)
        -- Match Better Containers' accepted index forms, including numeric strings.
        local index = math.max(0, math.floor(tonumber(ci) or 0))
        local group = Groups.resolve(obj, index)
        if group then return group.configuration.appearance or {} end
        return original(obj, username, ci, ...)
    end
    installed = true
    return true
end

-- Vanilla also reads custom names directly. Project just the group name onto
-- current buttons after the normal refresh, without modifying object ModData.
function View.refreshNames(page, phase)
    if phase ~= "end" or not page then return end
    for _, button in ipairs(page.backpacks or {}) do
        local container = button.inventory
        local obj = container and container.getParent and container:getParent()
        if obj and obj.getContainerCount and obj.getContainerByIndex then
            for ci = 0, (obj:getContainerCount() or 0) - 1 do
                if obj:getContainerByIndex(ci) == container then
                    local group = Groups.resolve(obj, ci)
                    if group then
                        local appearance = group.configuration.appearance or {}
                        local name = appearance.name
                        if name == nil or name == "" then
                            -- Ignore a stale materialized custom name when a shared
                            -- appearance deliberately restores the native default.
                            local kind = container:getType()
                            local display = container.getDisplayType and container:getDisplayType()
                            name = getTextOrNull("IGUI_ContainerTitle_" .. kind)
                                or (display and getTextOrNull("IGUI_ContainerTitle_" .. display))
                                or "!Needs IGUI_ContainerTitle defined for: " .. kind
                        end
                        button.name, button.tooltip = name, name
                        if page.selectedButton == button then page.title = name end
                    end
                    break
                end
            end
        end
    end
end

function View.refresh()
    if refreshing or not getNumActivePlayers then return end
    refreshing = true
    local ok, problem = pcall(function()
        for index = 0, getNumActivePlayers() - 1 do
            for _, getter in ipairs({getPlayerInventory, getPlayerLoot}) do
                local page = getter and getter(index)
                if page and page.refreshBackpacks then page:refreshBackpacks() end
            end
        end
    end)
    refreshing = false
    if not ok then error(problem) end
end

View.install()
Groups.onChanged(View.refresh)
Events.OnGameStart.Add(View.install)
Events.OnRefreshInventoryWindowContainers.Add(View.refreshNames)
return View
