if isClient() then return end
local Retention = require "PZSurvivorToolkit/ItemRetention"
local requests = setmetatable({}, {__mode="k"})

local Access = require "PZSurvivorToolkit/ItemAccess"
local integer, validLocator = Access.integer, Access.validLocator

function Retention.applyRequest(player, args)
    if not player or player:isDead() or not player:getCurrentSquare() or type(args) ~= "table"
        or not integer(args.request, 2147483647) or args.request < 1
        or type(args.retained) ~= "boolean" or type(args.items) ~= "table" then return end
    local count = 0
    for index, locator in pairs(args.items) do
        count = count + 1
        if count > Retention.MAX_ITEMS or not integer(index, Retention.MAX_ITEMS)
            or index < 1 or not validLocator(locator) then return end
    end
    for index = 1, count do if args.items[index] == nil then return end end
    if count == 0 then return end
    -- Native commands are connection-bound to this actor. The high-water mark
    -- additionally prevents a delayed/repeated old set from undoing a newer set.
    if args.request <= (requests[player] or 0) then return end
    requests[player] = args.request
    local accepted, seen = {}, {}
    for _, locator in ipairs(args.items) do
        local item = Access.admit(player, locator)
        if item and not seen[item] then
            seen[item] = true
            Retention.apply(item, args.retained)
            accepted[#accepted + 1] = locator
            -- Native ContainerID sync preserves the rest of the item ModData.
            if item:getContainer() then syncItemModData(player, item) end
        end
    end
    if isServer() then
        -- This narrow state packet also covers loose world items (no native
        -- ContainerID) and gives owner/observer clients one cache invalidation.
        if #accepted > 0 then
            sendServerCommand(Retention.MODULE, "State", {owner=player:getOnlineID(),
                retained=args.retained, items=accepted})
        end
        sendServerCommand(player, Retention.MODULE, "Result", {request=args.request,
            accepted=#accepted, rejected=count-#accepted})
    end
    return #accepted
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module == Retention.MODULE and command == "Set" then Retention.applyRequest(player, args) end
end)
return Retention
