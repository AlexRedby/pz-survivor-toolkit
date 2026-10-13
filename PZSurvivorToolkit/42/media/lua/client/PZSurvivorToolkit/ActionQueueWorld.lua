require "PZSurvivorToolkit/ActionQueueOperations"
require "TimedActions/ISQueueActionsAction"
require "ISUI/ISDisassembleMenu"
require "Moveables/ISMoveablesAction"

local Toolkit = PZSurvivorToolkit
local World = {}
Toolkit.ActionQueueWorld = World
local commandMarker = {}
local commandCallbacks = {}
local resumeMarker = {}
local nativeTryBuild
local buildTokens = {}

local function startCommand(action)
    action:beginAddingActions()
    action.addActionsFunction(action.character, unpack(action.args))
    action:endAddingActions()
    -- An invalid future target skips this command without native forceStop clearing the remaining queue.
    action:forceComplete()
end

local function command(character, callback, snapshot, kind, name)
    local action = ISQueueActionsAction:new(character, callback, snapshot)
    action.start = startCommand
    action.toolkitWorldCommand = commandMarker
    action.toolkitWorldOperation = kind
    action.toolkitWorldDismantle = kind == "dismantle"
    action.toolkitWorldTarget = snapshot.object
    action.toolkitWorldName = name
    if snapshot.item then
        action.craftRecipe = snapshot.item.craftRecipe
        action.toolkitWorldX, action.toolkitWorldY, action.toolkitWorldZ = snapshot.x, snapshot.y, snapshot.z
        action.toolkitWorldMinX, action.toolkitWorldMinY = snapshot.minX, snapshot.minY
        action.toolkitWorldWidth, action.toolkitWorldHeight, action.toolkitWorldLayers = snapshot.width, snapshot.height, snapshot.layers
    end
    commandCallbacks[callback] = true
    return action
end

function World.isDeferredAction(action)
    return action and action.Type == "ISQueueActionsAction" and action.toolkitWorldCommand == commandMarker
        and action.start == startCommand and commandCallbacks[action.addActionsFunction] == true
end
World.isCommand = World.isDeferredAction

local function pending(character)
    local queue = ISTimedActionQueue.queues[character]
    return Toolkit.Settings.actionQueue() and queue and #queue.queue > 0
end

local function defer(character, callback, snapshot)
    return Toolkit.ActionQueueOperations.run(function()
        return ISTimedActionQueue.add(command(character, callback, snapshot, "dismantle", snapshot.moveProps.name))
    end)
end

local function scrapFromCursor(character, target)
    if not target.square:getObjects():contains(target.object) or not target.moveProps:canScrapObject(character) then return end
    if not ISMoveableDefinitions.cheat and not target.moveProps:walkToAndEquip(character, target.square, "scrap", target.origSpriteName) then return end
    if target.object:getProperties():has(IsoFlagType.solidfloor) then
        local adjacent = AdjacentFreeTileFinder.Find(target.square, character)
        if adjacent then ISTimedActionQueue.add(ISWalkToTimedAction:new(character, adjacent)) end
    end
    ISTimedActionQueue.add(ISMoveablesAction:new(character, target.square, "scrap", target.origSpriteName,
        target.object, target.direction, nil, target.cursor))
end

-- shortcut: mod-specific cursor state needs its own adapter; only audited native placement types are deferred.
local legacyBuilds = {
    ISWoodenWall = true, ISWoodenDoor = true, ISWoodenDoorFrame = true, ISWoodenFloor = true,
    ISWoodenStairs = true, ISWoodenContainer = true, ISSimpleFurniture = true,
    ISDoubleTileFurniture = true, ISDoubleDoor = true, ISLightSource = true, ISCompost = true,
}

local function shallowCopy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function barricadeTarget(face, x, y, z)
    local facing = face:getFaceName()
    if facing == "s" then y = y + 1 elseif facing == "e" then x = x + 1 end
    local square = getCell():getGridSquare(x, y, z)
    if not square then return end
    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        local valid = instanceof(object, "IsoDoor") or instanceof(object, "IsoWindow") or instanceof(object, "IsoWindowFrame")
            or (instanceof(object, "IsoThumpable") and (object:isDoor() or object:isWindow()))
        if valid and object:getNorth() == (facing == "n" or facing == "s") then return object end
    end
end

local function buildSnapshot(cursor, x, y, z)
    -- Only Lua placement state is copied; inventory items, scripts and squares retain native identity.
    local item = shallowCopy(cursor)
    setmetatable(item, getmetatable(cursor, true))
    item.modData = shallowCopy(cursor.modData or {})
    item.spriteCache = shallowCopy(cursor.spriteCache or {})
    item.dragNilAfterPlace, item.blockAfterPlace, item.blockBuild = false, false, false
    if cursor.buildPanelLogic then
        local logic = BuildLogic.new(cursor.character or getSpecificPlayer(cursor.player), nil, nil)
        logic:setContainers(ISInventoryPaneContextMenu.getContainers(cursor.character or getSpecificPlayer(cursor.player)))
        logic:setRecipe(cursor.craftRecipe)
        logic:copyManualInputsFrom(cursor.buildPanelLogic)
        item.buildPanelLogic = logic
    end
    local face = item.Type == "ISBuildIsoEntity" and item:getFace()
    local width, height, layers = face and face:getWidth() or 1, face and face:getHeight() or 1, face and face:getzLayers() or 1
    local minX, minY = x, y
    if item.Type == "ISWoodenStairs" or item.Type == "ISDoubleTileFurniture" then
        local length = item.Type == "ISWoodenStairs" and 3 or 2
        if item.north then height, minY = length, y - length + 1 else width, minX = length, x - length + 1 end
        if item.Type == "ISWoodenStairs" then layers = 2 end
    elseif item.Type == "ISDoubleDoor" then
        if item.north then width = 4 else height, minY = 4, y - 3 end
    end
    local script = face and item.objectInfo:getScript()
    local barricade = script and script:getOnCreate() == "BuildRecipeCode.barricade.OnCreate"
    return {item = item, x = x, y = y, z = z, minX = minX, minY = minY, width = width, height = height, layers = layers,
        object = barricade and barricadeTarget(face, x, y, z) or nil, barricade = barricade}
end

local function trackBuild(action, snapshot)
    if not action then return end
    action.toolkitWorldResume = {marker = resumeMarker, owner = action, snapshot = snapshot, item = action.item,
        x = action.x, y = action.y, z = action.z, north = action.north, spriteName = action.spriteName,
        complete = action.onCompleteFunc, target = action.onCompleteTarget,
        cancel = action.onCancelFunc, cancelTarget = action.onCancelTarget}
    action.toolkitWorldOperation = "build"
    action.toolkitWorldTarget = snapshot.object
    action.toolkitWorldName = snapshot.item.name
    action.toolkitWorldX, action.toolkitWorldY, action.toolkitWorldZ = snapshot.x, snapshot.y, snapshot.z
    action.toolkitWorldMinX, action.toolkitWorldMinY = snapshot.minX, snapshot.minY
    action.toolkitWorldWidth, action.toolkitWorldHeight, action.toolkitWorldLayers = snapshot.width, snapshot.height, snapshot.layers
end

local function buildFromSnapshot(character, target)
    local snapshot = buildSnapshot(target.item, target.x, target.y, target.z)
    if target.barricade and snapshot.object ~= target.object then return end
    local item = snapshot.item
    local square = getCell():getGridSquare(target.x, target.y, target.z)
    if not square then return end
    item.containers = ISInventoryPaneContextMenu.getContainers(character)
    if item.buildPanelLogic then
        item.buildPanelLogic:setContainers(item.containers)
        item.buildPanelLogic:updateFloorContainer()
        if not character:isBuildCheat() and not ISBuildMenu.cheat
            and not item.buildPanelLogic:canPerformCurrentRecipe() then return end
    end
    item:getSprite()
    if not item:isValid(square, item.north) then return end
    local action = nativeTryBuild(item, target.x, target.y, target.z)
    if action and item.Type == "ISBuildIsoEntity" and item.objectInfo:getScript():getTimedActionOnIsValid() then
        action.onIsValid = item.objectInfo:getScript():getTimedActionOnIsValid()
    end
    trackBuild(action, snapshot)
    return action
end

function World.targetGone(action)
    local saved = action and action.toolkitWorldResume
    return saved ~= nil and saved.marker == resumeMarker and saved.owner == action
        and action.Type == "ISMoveablesAction" and action.mode == "scrap"
        and action.object == saved.snapshot.object and action.square == saved.snapshot.square
        and action.moveProps == saved.snapshot.moveProps and not action:isValidObject()
end

local function ownedBuild(action, saved)
    return saved and saved.marker == resumeMarker and saved.owner == action and action.Type == "ISBuildAction"
        and action.item == saved.item and action.x == saved.x and action.y == saved.y and action.z == saved.z
        and action.north == saved.north and action.spriteName == saved.spriteName
        and action.onCompleteFunc == saved.complete and action.onCompleteTarget == saved.target
        and action.onCancelFunc == saved.cancel and action.onCancelTarget == saved.cancelTarget
        and (not saved.complete or saved.complete == ISBuildingObject.onActionComplete)
        and (not saved.cancel or saved.cancel == ISBuildingObject.onActionComplete)
end

local function currentBuild(action)
    local queue = action and ISTimedActionQueue.queues[action.character]
    return queue and queue.current == action and queue.queue[1] == action and action.started == true and action.action ~= nil
end

function World.canResume(action)
    local saved = action and action.toolkitWorldResume
    if not saved or saved.marker ~= resumeMarker or saved.owner ~= action then return false end
    if action.Type == "ISMoveablesAction" then
        return action.mode == "scrap" and action.object == saved.snapshot.object
            and action.square == saved.snapshot.square and action:isValidObject()
    end
    if not ownedBuild(action, saved) then return false end
    if isClient() then
        local ack = saved.server
        return currentBuild(action) and ack ~= nil and ack.transaction == action.transactionId
            and ack.state == "started", "move_world_transaction"
    end
    return true
end

function World.buildAcknowledgement(action)
    if isClient() and action.Type == "ISBuildAction" and World.canResume(action) then
        return action.toolkitWorldResume.server
    end
end

function World.buildState(action, acknowledgement)
    local saved = action and action.toolkitWorldResume
    if type(acknowledgement) == "table" and ownedBuild(action, saved) and acknowledgement == saved.server
        and acknowledgement.transaction == action.transactionId then return acknowledgement.state end
end

function World.resume(action, acknowledgement)
    if acknowledgement then
        if World.buildState(action, acknowledgement) ~= "canceled" then return end
    elseif not World.canResume(action) then return end
    local saved = action.toolkitWorldResume.snapshot
    if action.Type == "ISMoveablesAction" then
        return command(action.character, action.toolkitWorldResume.callback, shallowCopy(saved), "dismantle", saved.moveProps.name)
    end
    local snapshot = buildSnapshot(saved.item, saved.x, saved.y, saved.z)
    snapshot.object = saved.object
    return command(action.character, buildFromSnapshot, snapshot, "build", saved.item.name)
end

local function serverBuildState(module, commandName, args)
    if module ~= "PZSurvivorToolkitBuild" or commandName ~= "State" or not isClient() or type(args) ~= "table"
        or type(args.player) ~= "number" or type(args.transaction) ~= "number"
        or args.transaction < -128 or args.transaction > 127 or args.transaction % 1 ~= 0
        or type(args.token) ~= "string" or #args.token ~= 36
        or not args.token:match("^%x+%-%x+%-%x+%-%x+%-%x+$")
        or args.token:sub(9, 9) ~= "-" or args.token:sub(14, 14) ~= "-"
        or args.token:sub(19, 19) ~= "-" or args.token:sub(24, 24) ~= "-"
        or (args.state ~= "started" and args.state ~= "canceled" and args.state ~= "completed") then return end
    for character, queue in pairs(ISTimedActionQueue.queues) do
        if getSpecificPlayer(character:getPlayerNum()) == character and character:getOnlineID() == args.player then
            local action = queue.current
            local saved = action and action.toolkitWorldResume
            if not currentBuild(action) or not ownedBuild(action, saved) or action.transactionId ~= args.transaction then return end
            local ack = saved.server
            if args.state == "started" then
                local playerNum = character:getPlayerNum()
                local tokens = buildTokens[playerNum] or {}
                -- Server ACKs share native BuildAction's ordered channel; an old started cannot cross native Done/id reuse.
                if ack or tokens[args.transaction] == args.token then return end
                tokens[args.transaction] = args.token
                buildTokens[playerNum] = tokens
                saved.server = {transaction = args.transaction, token = args.token, state = "started"}
            elseif ack and ack.token == args.token and ack.transaction == args.transaction and ack.state == "started" then
                ack.state = args.state
            end
            return
        end
    end
end

Events.OnServerCommand.Add(serverBuildState)

local function containsSquare(build, square)
    if not square then return false end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local minX, minY = build.toolkitWorldMinX or build.toolkitWorldX, build.toolkitWorldMinY or build.toolkitWorldY
    return x >= minX and x < minX + (build.toolkitWorldWidth or 1)
        and y >= minY and y < minY + (build.toolkitWorldHeight or 1)
        and z >= build.toolkitWorldZ and z < build.toolkitWorldZ + (build.toolkitWorldLayers or 1)
end

local function intersectsObject(build, other)
    local targets = {other.toolkitWorldTarget, other.object, other.moveProps and other.moveProps.object,
        other.generator, other.charger, other.isoObject}
    for i = 1, 6 do
        local object = targets[i]
        if object and instanceof(object, "IsoObject") then
            if object == build.toolkitWorldTarget then return true end
            local square = object:getSquare()
            if containsSquare(build, square) then return true end
            local props = other.moveProps
            if square and props and props.object == object and props.getSpriteGridTopLeft and props.getMultiTileSquares then
                local x, y = props:getSpriteGridTopLeft(square:getX(), square:getY())
                local squares = props:getMultiTileSquares(x, y, square:getZ())
                for _, tile in ipairs(squares or {}) do if containsSquare(build, tile) then return true end end
            end
        end
    end
    return false
end

function World.sharesTarget(first, second)
    if not first or not second then return false end
    if first.toolkitWorldX == nil then
        return second.toolkitWorldX ~= nil and intersectsObject(second, first)
    end
    if second.toolkitWorldX == nil then return intersectsObject(first, second) end
    if first.toolkitWorldTarget and first.toolkitWorldTarget == second.toolkitWorldTarget then return true end
    local ax, ay = first.toolkitWorldMinX or first.toolkitWorldX, first.toolkitWorldMinY or first.toolkitWorldY
    local bx, by = second.toolkitWorldMinX or second.toolkitWorldX, second.toolkitWorldMinY or second.toolkitWorldY
    return ax < bx + (second.toolkitWorldWidth or 1) and bx < ax + (first.toolkitWorldWidth or 1)
        and ay < by + (second.toolkitWorldHeight or 1) and by < ay + (first.toolkitWorldHeight or 1)
        and first.toolkitWorldZ < second.toolkitWorldZ + (second.toolkitWorldLayers or 1)
        and second.toolkitWorldZ < first.toolkitWorldZ + (first.toolkitWorldLayers or 1)
end

-- The game loads the server-side cursor class after client Lua.
local function install()
    if ISMoveableCursor.toolkitQueueInstalled then return end
    ISMoveableCursor.toolkitQueueInstalled = true
    nativeTryBuild = ISBuildingObject.tryBuild
    ISBuildingObject.tryBuild = function(cursor, x, y, z)
        local character = cursor.character or getSpecificPlayer(cursor.player)
        if not Toolkit.Settings.actionQueue() or cursor.skipBuildAction
            or (cursor.Type ~= "ISBuildIsoEntity" and not legacyBuilds[cursor.Type]) then
            return Toolkit.ActionQueueOperations.run(nativeTryBuild, cursor, x, y, z)
        end
        local snapshot = buildSnapshot(cursor, x, y, z)
        if not pending(character) then
            local action = Toolkit.ActionQueueOperations.run(nativeTryBuild, cursor, x, y, z)
            trackBuild(action, snapshot)
            return action
        end
        if cursor.dragNilAfterPlace then getCell():setDrag(nil, cursor.player) end
        return Toolkit.ActionQueueOperations.run(function()
            return ISTimedActionQueue.add(command(character, buildFromSnapshot, snapshot, "build", cursor.name))
        end)
    end
    local disassemble, create = ISDisassembleMenu.disassemble, ISMoveableCursor.create
    local newMoveable = ISMoveablesAction.new
    ISMoveablesAction.new = function(self, character, square, mode, origSpriteName, object, direction, item, moveCursor)
        local action = newMoveable(self, character, square, mode, origSpriteName, object, direction, item, moveCursor)
        if Toolkit.Settings.actionQueue() and mode == "scrap" and action.moveProps then
            action.toolkitWorldResume = {marker = resumeMarker, owner = action, callback = moveCursor and scrapFromCursor or disassemble,
                snapshot = {moveProps = action.moveProps, square = square, object = object,
                    origSpriteName = origSpriteName, direction = direction, cursor = moveCursor}}
        end
        return action
    end
    ISDisassembleMenu.disassemble = function(character, target)
        if not pending(character)
            or not target or not target.moveProps or not target.square or not target.object then
            return Toolkit.ActionQueueOperations.run(disassemble, character, target)
        end
        -- Native deferred expansion rechecks tools and movement after the preceding operation.
        local snapshot = {moveProps = target.moveProps, square = target.square, object = target.object}
        return defer(character, disassemble, snapshot)
    end

    ISMoveableCursor.create = function(cursor, x, y, z, north, sprite)
        if ISMoveableCursor.mode[cursor.player] ~= "scrap" or not pending(cursor.character)
            or cursor:cannotCreate(x, y, z) then
            return Toolkit.ActionQueueOperations.run(create, cursor, x, y, z, north, sprite)
        end
        local props = cursor.currentMoveProps
        local object = props:findOnSquare(cursor.currentSquare, props.spriteName)
        if not object then return Toolkit.ActionQueueOperations.run(create, cursor, x, y, z, north, sprite) end
        local target = {moveProps = props, square = cursor.currentSquare, object = object,
            origSpriteName = cursor.origSpriteName, direction = props:getFaceDirectionFromSpriteName(props.sprite:getName()), cursor = cursor}
        cursor.cursorFacing, cursor.joypadFacing, cursor.objectListCache = nil, nil, nil
        return defer(cursor.character, scrapFromCursor, target)
    end
end

Events.OnGameStart.Add(install)
