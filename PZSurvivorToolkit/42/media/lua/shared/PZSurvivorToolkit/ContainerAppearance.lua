-- World-container appearance uses Better Containers' existing user/global storage.
-- Keep access here pure: its vanilla-name setter transmits the entire object ModData.
local Appearance = {}
local Groups = require "PZSurvivorToolkit/ContainerGroups"
PZSurvivorToolkit.ContainerAppearance = Appearance

local function text(value)
    if type(value) ~= "string" then return nil end
    local result = value:gsub("^%s+", ""):gsub("%s+$", "")
    return result ~= "" and result or nil
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Appearance.available()
    if EURY_CONTAINERS then return true end
    local mods = getActivatedMods and getActivatedMods()
    if not mods then return false end
    if mods.contains and (mods:contains("EURY_CONTAINERS") or mods:contains("\\EURY_CONTAINERS")) then return true end
    if not mods.size or not mods.get then return false end
    for i = 0, mods:size() - 1 do
        if tostring(mods:get(i)):gsub("[\\/%s]", "") == "EURY_CONTAINERS" then return true end
    end
    return false
end

-- Invalid edits are refused rather than silently deleting an existing setting.
function Appearance.normalize(payload)
    if type(payload) ~= "table" then return nil end
    local out = {}
    if payload.name ~= nil then
        if type(payload.name) ~= "string" or #payload.name > 256 then return nil end
        out.name = text(payload.name)
    end
    if payload.icon ~= nil then
        local icon = payload.icon
        if type(icon) == "string" then icon = {kind = "item", value = icon} end
        if type(icon) ~= "table" then return nil end
        local kind, value = text(icon.kind), text(icon.value)
        if not kind or not value or #kind > 32 or #value > 512 then return nil end
        out.icon = {kind = kind, value = value}
    end
    if payload.color ~= nil then
        local color = payload.color
        if type(color) ~= "table" then return nil end
        local r, g, b, a = color.r, color.g, color.b, color.a
        if r == nil and g == nil and b == nil and a == nil then r, g, b, a = color[1], color[2], color[3], color[4] end
        if a == nil then a = 1 end
        if not finite(r) or not finite(g) or not finite(b) or not finite(a)
            or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 or a < 0 or a > 1 then return nil end
        out.color = {r = r, g = g, b = b, a = a}
    end
    return out
end

local function backend()
    if not Appearance.available() then return nil end
    local ok, module = pcall(require, "BetterContainers/Customize/ModData")
    return ok and type(module) == "table" and module or nil
end

function Appearance.read(obj, ci, player)
    local group = Groups.resolve(obj, ci)
    if group then return group.configuration.appearance or {} end
    local md = obj and obj:getModData()
    if not md then return {} end
    local api, out = backend()
    if api then
        -- BC's getter repairs a malformed _global node even with create=false.
        -- A shallow read view keeps opening/refusing an editor free of mutations.
        local view = {}
        for key, value in pairs(md) do view[key] = value end
        if type(md.BetterContainers) == "table" then
            local root = {}
            for key, value in pairs(md.BetterContainers) do root[key] = value end
            if type(root.customize) == "table" then
                local customize = {}
                for key, value in pairs(root.customize) do customize[key] = value end
                root.customize = customize
            end
            view.BetterContainers = root
        end
        local owner = {getModData = function() return view end}
        local payload = api.getEffective(owner, player and player:getUsername(), ci)
        if payload then
            -- BC owns legacy read sanitization. In particular, it accepts legacy
            -- colors outside the bounds offered by the current editor.
            out = {name = payload.name}
            if payload.icon then out.icon = {kind = payload.icon.kind, value = payload.icon.value} end
            if payload.color then
                local color = payload.color
                out.color = {r = color.r, g = color.g, b = color.b, a = color.a}
            end
        end
    end
    out = out or {}
    if out.name == nil then
        local container = obj:getContainerByIndex(ci)
        local kind = container and container:getType()
        local name = (kind and text(md[kind .. "_customContainerName"]))
            or text(md["container_" .. tostring(ci) .. "_customContainerName"])
        local default = kind and getTextOrNull and getTextOrNull("IGUI_ContainerTitle_" .. kind)
        if name ~= default then out.name = name end
    end
    return out
end

-- Called only after all authority checks. Does not publish or invoke native setters.
function Appearance.apply(obj, ci, player, payload)
    local md = obj:getModData()
    local api = backend()
    if api then
        -- Match BC Network.applyPayload while publishing only once in our authority.
        api.setUser(obj, player:getUsername(), payload, ci)
        api.setGlobal(obj, payload, ci)
    end
    local container = obj:getContainerByIndex(ci)
    local kind = container and container:getType()
    md["container_" .. tostring(ci) .. "_customContainerName"] = payload.name
    if kind then md[kind .. "_customContainerName"] = payload.name end
end

return Appearance
