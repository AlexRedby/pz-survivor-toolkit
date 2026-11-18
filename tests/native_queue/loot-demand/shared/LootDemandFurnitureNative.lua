local config = require 'QueueTestSelection'
if config.suite ~= 'loot-demand' or config.cases[1] ~= 'furniture' then return end

require 'LootDemandBank'
require 'FurniturePushPull/FurniturePushPull_Actions'
require 'LootDemandFurniture'

local B = LootDemandBank
local rootSprite = 'trashcontainers_01_13'
local partnerSprite = 'trashcontainers_01_12'
local memberSprites = {partnerSprite, rootSprite}

local function check(value, message)
    assert(value, 'native orange furniture: ' .. message)
end

local function discard(object)
    if object and object:getSquare() then
        object:getSquare():transmitRemoveItemFromSquare(object)
    end
end

local function actionFor(class, player, object, destination, mode)
    local square = object:getSquare()
    local back = player:getSquare()
    return setmetatable({
        character = player,
        mode = mode,
        sourceX = square:getX(), sourceY = square:getY(), sourceZ = square:getZ(),
        spriteName = object:getSprite():getName(),
        destX = destination:getX(), destY = destination:getY(), destZ = destination:getZ(),
        backX = back:getX(), backY = back:getY(), backZ = back:getZ(),
    }, {__index = class})
end

local function memberMap(object)
    local props = assert(FurniturePushPull.getMoveableData(object), 'orange moveable props missing')
    local members = assert(FurniturePushPull.getFurnitureMembers(object, props), 'orange grid missing')
    check(props.isMultiSprite and #members == 2, 'actual orange sprite grid differs')
    local result = {}
    for _, member in ipairs(members) do
        result[member.sprite:getName()] = member.object
    end
    check(result[rootSprite] and result[partnerSprite], 'expected orange members missing')
    return result, props, members
end

local function assertItems(object, expected)
    local container = assert(object:getContainer())
    check(container:isExplored(), 'moved member became unexplored')
    check(container:getItems():size() == #expected, 'member count changed')
    for _, item in ipairs(expected) do
        check(container:contains(item) and item:getContainer() == container,
            'exact member item ownership changed')
    end
    return container
end

local function createFixture(player, owned)
    local origin = player:getSquare()
    local offsets = {{1, 0}, {-1, 0}, {0, 1}, {1, -1}, {-1, -1}, {0, -2}}
    for _, offset in ipairs(offsets) do
        local square = getCell():getGridSquare(
            origin:getX() + offset[1], origin:getY() + offset[2], origin:getZ())
        local partner = square and getCell():getGridSquare(square:getX(), square:getY() + 1, square:getZ())
        if square and partner and square:getFloor() and partner:getFloor()
            and not FurniturePushPull.sameSquare(partner, origin) then
            local created = {}
            for _, part in ipairs({{square, rootSprite}, {partner, partnerSprite}}) do
                local object = IsoObject.new(getCell(), part[1], assert(getSprite(part[2])))
                object:createContainersFromSpriteProperties()
                part[1]:AddTileObject(object)
                created[#created + 1] = object
                owned[#owned + 1] = object
            end
            local root = created[1]
            local sources, props, members = memberMap(root)
            local weight, strength, duration, cost = FurniturePushPull.getBalance(player, props, members)
            local plan, reason, diagnostic = FurniturePushPull.getMovePlan(player, root, 'push')
            print('[LOOT_FURNITURE] ORANGE_PLAN admitted=' .. tostring(plan ~= nil)
                .. ' weight=' .. weight .. ' strength=' .. strength .. ' duration=' .. duration
                .. ' cost=' .. cost .. ' source=' .. FurniturePushPull.squareKey(square)
                .. ' reason=' .. tostring(reason) .. ' diagnostic=' .. tostring(diagnostic))
            if plan then
                if isServer() then
                    for _, object in ipairs(created) do object:transmitCompleteItemToClients() end
                end
                return root, plan, sources
            end
            for _, object in ipairs(created) do discard(object) end
        end
    end
    error('native orange furniture: no admitted adjacent geometry; see ORANGE_PLAN reasons')
end

local function awaitSingleplayerPush(destination)
    if isClient() or isServer() then return end
    local started = getTimestampMs()
    local deadline = started + 10000
    print('[LOOT_FURNITURE] SP_PUSH_QUEUED')
    while not FurniturePushPull.findObject(
        destination:getX(), destination:getY(), destination:getZ(), rootSprite) do
        check(getTimestampMs() < deadline, 'native delayed SP push did not commit before deadline')
        coroutine.yield()
    end
    print('[LOOT_FURNITURE] SP_PUSH_NATIVE_COMMITTED elapsed_ms=' .. (getTimestampMs() - started))
end

function B.runFurniture(player)
    local owned = {}
    for _, scenario in ipairs({'empty', 'owned-pending', 'populated'}) do
        local empty = scenario == 'empty'
        local ownedPending = scenario == 'owned-pending'
        local root, plan, sources = createFixture(player, owned)
        local source = root:getSquare()
        local byContainer, rows = {}, {}
        for name, object in pairs(sources) do
            local container = assert(object:getContainer())
            check(container:getType() == 'dumpster' and lootDemandPending(container),
                'member is not a pending world dumpster')
            lootDemandAutomatic(object, false)
            check(lootDemandPending(container) and container:isEmpty(), 'member automatically filled early')
            local row = {calls = 0, expected = {}}
            rows[name], byContainer[container] = row, row
            if ownedPending then
                local item = assert(container:AddItem('Base.Nails'))
                item:getModData().lootFurnitureOwned = 'preexisting'
                row.owned, row.expected = item, {item}
                check(not container:isExplored() and lootDemandPending(container),
                    'owned insertion changed pending state before demand')
            end
        end

        local function onFill(room, kind, container)
            local row = byContainer[container]
            if not row then return end
            row.calls = row.calls + 1
            check(row.calls == 1, 'member native fill repeated')
            if empty then
                while container:getItems():size() > 0 do
                    container:Remove(container:getItems():get(container:getItems():size() - 1))
                end
            else
                local item = assert(container:AddItem('Base.Nails'))
                item:getModData().lootFurnitureOwned = 'callback-owned'
                if not ownedPending then row.owned = item end
                assert(container:AddItem('Base.Pen'))
            end
            row.expected = {}
            for index = 0, container:getItems():size() - 1 do
                row.expected[#row.expected + 1] = container:getItems():get(index)
            end
        end
        Events.OnFillContainer.Add(onFill)

        local push = actionFor(ISFurniturePushPullEffortAction, player, root, plan.destination, 'push')
        check(push:isValid(), 'actual orange push validation refused')
        check(push:complete(), 'actual orange push completion refused')
        awaitSingleplayerPush(plan.destination)
        local placed = assert(FurniturePushPull.findObject(
            plan.destination:getX(), plan.destination:getY(), plan.destination:getZ(), rootSprite))
        local placedMap = memberMap(placed)
        for name, object in pairs(placedMap) do
            owned[#owned + 1] = object
            local row = assert(rows[name])
            check(row.calls == 1, 'member not filled exactly once')
            local container = assertItems(object, row.expected)
            row.fingerprint = lootDemandFingerprint(container)
            check(empty and #row.expected == 0 or not empty and #row.expected >= 2,
                'member native fill inventory shape differs')
            if row.owned then
                local marker = ownedPending and 'preexisting' or 'callback-owned'
                check(container:contains(row.owned) and row.owned:getModData().lootFurnitureOwned == marker,
                    'member owned sentinel changed')
            end
        end

        local pull = actionFor(ISFurniturePullCommitAction, player, placed, source, 'pull')
        check(pull:isValid(), 'actual orange pull validation refused')
        check(pull:complete(), 'actual orange pull completion refused')
        local returned = assert(FurniturePushPull.findObject(
            source:getX(), source:getY(), source:getZ(), rootSprite))
        local returnedMap = memberMap(returned)
        local retained, entries, fingerprints, overlays = {}, {}, {}, {}
        for _, name in ipairs(memberSprites) do
            local object, row = assert(returnedMap[name]), assert(rows[name])
            owned[#owned + 1] = object
            local container = assertItems(object, row.expected)
            check(lootDemandFingerprint(container) == row.fingerprint, 'member recursive tree changed on pull')
            local before = row.calls
            check(lootDemandEnsure(container, player) and row.calls == before, 'moved member refilled')
            local square, overlaySprite = object:getSquare(), object:getOverlaySprite()
            local overlay = overlaySprite and overlaySprite:getName() or ''
            print('[LOOT_FURNITURE] ORANGE_MEMBER scenario=' .. scenario .. ' sprite=' .. name
                .. ' items=' .. #row.expected .. ' fills=' .. row.calls
                .. ' fingerprint=' .. row.fingerprint .. ' overlay=' .. overlay)
            retained[object] = true
            entries[#entries + 1] = {
                x = square:getX(), y = square:getY(), z = square:getZ(), index = object:getObjectIndex(),
                sprite = name, count = #row.expected, fingerprint = row.fingerprint, overlay = overlay,
            }
            fingerprints[#fingerprints + 1] = name .. '=' .. row.fingerprint
            overlays[#overlays + 1] = name .. '=' .. overlay
        end
        if isServer() and scenario == 'populated' then
            B.furnitureReplicated = {
                objects = retained, entries = entries, seen = false,
                fingerprint = table.concat(fingerprints, ';'), overlay = table.concat(overlays, ';'),
            }
        end
        Events.OnFillContainer.Remove(onFill)
        for _, object in ipairs(owned) do
            if not (B.furnitureReplicated and B.furnitureReplicated.objects[object]) then discard(object) end
        end
        owned = {}
        if ownedPending then
            print('[LOOT_FURNITURE] OWNED_PENDING_PRESERVED bothMembers=true')
        else
            print('[LOOT_FURNITURE] PASS mode=' .. (isServer() and 'host-authority' or 'sp')
                .. ' empty=' .. tostring(empty) .. ' sprite=' .. rootSprite .. ' multipart=true exactOwned=true')
        end
    end
    return true
end

function B.furnitureProbeInfo()
    return {entries = assert(B.furnitureReplicated).entries}
end

function B.verifyFurniture(args)
    local row = assert(B.furnitureReplicated)
    for _, entry in ipairs(row.entries) do
        local object = assert(FurniturePushPull.findObject(entry.x, entry.y, entry.z, entry.sprite))
        local container, overlay = assert(object:getContainer()), object:getOverlaySprite()
        check(lootDemandFingerprint(container) == entry.fingerprint,
            'authority member changed before client verification')
        check((overlay and overlay:getName() or '') == entry.overlay,
            'authority overlay changed before client verification')
    end
    check(args.fingerprint == row.fingerprint, 'native client both-member trees differ')
    check(args.overlay == row.overlay, 'native client both-member overlays differ')
    row.seen = true
    print('[LOOT_FURNITURE] PASS host-native-client-content-overlay fingerprint=' .. args.fingerprint
        .. ' overlay=' .. args.overlay)
end
