require "PZSurvivorToolkit/ActionQueueOperations"
require "TimedActions/ISQueueActionsAction"
require "ISUI/ISDisassembleMenu"
require "Moveables/ISMoveablesAction"

local Toolkit = PZSurvivorToolkit

local function pending(character)
    local queue = ISTimedActionQueue.queues[character]
    return Toolkit.Settings.actionQueue() and queue and #queue.queue > 0
end

local function defer(character, callback, snapshot)
    return Toolkit.ActionQueueOperations.run(function()
        local action = ISQueueActionsAction:new(character, callback, snapshot)
        action.toolkitWorldDismantle = true
        action.toolkitWorldTarget = snapshot.object
        action.toolkitWorldName = snapshot.moveProps.name
        return ISTimedActionQueue.add(action)
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

-- The game loads the server-side cursor class after client Lua.
local function install()
    if ISMoveableCursor.toolkitQueueInstalled then return end
    ISMoveableCursor.toolkitQueueInstalled = true
    local disassemble, create = ISDisassembleMenu.disassemble, ISMoveableCursor.create
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
