-- Recipe lists are mutable shared native objects. Their identity and size do
-- not validate an index after script reload or deferred input resolution.
local Catalog = {}

function Catalog.currentRevision()
    local bridge = toolkitRecipeCatalogRevision
    local value = bridge and bridge()
    if type(value) == "number" and value >= 0 and value < math.huge then return value, bridge end
    return nil, bridge
end

function Catalog.newContext()
    local managers = {}
    local revision, bridge, revisionReady
    return {
        recipes = function(_, manager, method)
            local values = managers[manager]
            if not values then values = {}; managers[manager] = values end
            if values[method] == nil then
                values[method] = manager[method] and manager[method](manager) or false
            end
            return values[method] or nil
        end,
        revision = function()
            if not revisionReady then
                local value
                value, bridge = Catalog.currentRevision()
                if value ~= nil then
                    revision = value
                else
                    -- An absent/unsupported bridge cannot certify reuse across
                    -- operations. Keep batching within this operation only.
                    revision = {}
                end
                revisionReady = true
            end
            return revision, bridge
        end,
    }
end

return Catalog
