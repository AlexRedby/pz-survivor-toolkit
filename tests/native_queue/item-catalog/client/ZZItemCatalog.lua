local config = require 'QueueTestSelection'
local Catalog = require 'ItemCatalog'
local Categories = require 'PZSurvivorToolkit/ItemCategories'
local Tags = require 'PZSurvivorToolkit/ItemTags'
require 'ISUI/ISPanel'

assert(config.suite == 'item-catalog' and config.kind == 'sp', 'Disposable catalogue selection required')
local entered, starting, started, failed, ready = false, false, false, false, false
local phase, cursor, scripts, groups, crates, record, indexFile = 'items', 1, nil, {}, nil, nil, nil
local created, skipped = 0, 0
local originX, originY, level = 10825, 10142, 7
local minX, minY, width, height, floorCursor, crateCursor
local hud, readyFrames = nil, 0
local function tr(key) return getText('UI_PZST_ItemCatalog' .. key) end
local function guarded()
    assert(not isClient() and not isServer() and getWorld():getWorld() == Catalog.world,
        'Refusing catalogue edits outside the isolated single-player save')
end
local function label(category) return getTextOrNull('IGUI_ItemCat_' .. category) or category end
local function status(message) if hud then hud.message = message end end
local function itemDescription(item)
    local ids, names = Tags.forItem(item), {}
    for _, id in ipairs(ids) do names[#names + 1] = Tags.label(id) end
    return item:getDisplayName() .. ' | ' .. item:getFullType() .. ' | '
        .. (item:getDisplayCategory() or '') .. ' | ' .. table.concat(names, ', ')
end

Events.OnMainMenuEnter.Add(function() entered = true end)
Events.OnPreUIDraw.Add(function()
    if not entered or starting or isIngameState() then return end
    starting = true
    if config.options and config.options.world_template then
        MainScreen.continueLatestSave('Sandbox', Catalog.world)
        return
    end
    getWorld():setGameMode('Sandbox'); getWorld():setWorld(Catalog.world); getWorld():setMap('Muldraugh, KY')
    MainScreen.instance:setDefaultSandboxVars()
    getSandboxOptions():getOptionByName('Zombies'):setValue(6)
    getSandboxOptions():toLua()
    local current, active = ActiveMods.getById('currentGame'), getActivatedMods()
    current:getMods():clear()
    for i = 0, active:size() - 1 do current:getMods():add(active:get(i)) end
    MainScreen.instance.createWorld = true
    MapSpawnSelect.instance.selectedRegion = {points = {unemployed = {{posX = originX, posY = originY, posZ = 0}}}}
    MainScreen.instance.charCreationProfession:onOptionMouseDown({internal = 'NEXT'})
    MainScreen.instance.charCreationMain:onOptionMouseDown({internal = 'NEXT'})
end)

local function finish()
    if indexFile then indexFile:close(); indexFile = nil end
    status(tr('Ready'))
    getPlayer():teleportTo(minX + 1.5, minY + 1.5, level)
    getPlayer():getInventory():setDrawDirty(true)
    getPlayerLoot(0):refreshBackpacks()
    if getPlayerInfoPanel(0) then getPlayerInfoPanel(0):setVisible(false) end
    ready = true
    print('[ITEM_CATALOG] READY items=' .. record.items .. ' crates=' .. #record.crates .. ' skipped=' .. record.skipped)
end

local function initialize()
    guarded()
    local player = getPlayer()
    player:setGodMod(true); player:setGhostMode(true)
    getGameTime():setTimeOfDay(12)
    if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
    hud = ISPanel:new(65, 35, math.min(1100, getCore():getScreenWidth() - 90), 62)
    hud:initialise(); hud:addToUIManager()
    hud.message = tr('Preparing')
    hud.prerender = function(self)
        self:drawRect(0, 0, self.width, self.height, .85, .06, .06, .06)
        self:drawText(self.message, 10, 6, 1, 1, 1, 1, UIFont.Small)
        self:drawText(tr('Instructions'), 10, 32, .8, .8, .8, 1, UIFont.Small)
    end
    local saved = ModData.get('PZSTItemCatalog')
    if saved then
        assert(saved.version == Catalog.version and saved.complete, 'Incomplete catalogue save; create a fresh stand')
        record = saved
        minX, minY, width, height = saved.minX, saved.minY, saved.width, saved.height
        finish()
    else
        scripts, skipped = Catalog.list(getScriptManager():getAllItems())
        -- Native Lua file IO permits only its allowlisted extensions. The launcher
        -- exports these tab-separated contents as .tsv outside the game process.
        indexFile = assert(getFileWriter('item-catalog.txt', true, false), 'Cannot open catalogue index')
        indexFile:write('crate\tname\tfullType\tcategory\ttags\n')
    end
    started = true
end
Events.OnGameStart.Add(function()
    local ok, problem = pcall(initialize)
    if not ok then
        failed = true
        if indexFile then indexFile:close(); indexFile = nil end
        status(tostring(problem)); print('[ITEM_CATALOG] FAIL ' .. tostring(problem))
    end
end)

local function preflightPlatform()
    crates, width, height = Catalog.pack(groups, label)
    minX, minY = originX - math.floor(width / 2), originY - math.floor(height / 2)
    local cell = getCell()
    -- Validate all tiles before creating the platform; never clear existing map objects.
    for x = minX, minX + width - 1 do for y = minY, minY + height - 1 do
        assert(cell:getChunkForGridSquare(x, y, 0) and cell:getGridSquare(x, y, 0), 'Catalogue ground chunks not loaded')
        local square = cell:getGridSquare(x, y, level)
        assert(not square or square:getObjects():size() == 0, 'Unexpected object in catalogue platform footprint')
    end end
    floorCursor, crateCursor, phase = 0, 1, 'floor'
    record = ModData.getOrCreate('PZSTItemCatalog')
    record.version, record.complete = Catalog.version, false
    record.minX, record.minY, record.width, record.height = minX, minY, width, height
    record.items, record.skipped, record.crates = created, skipped, {}
end

local function populate()
    guarded()
    if phase == 'items' then
        for _ = 1, 16 do
            local entry = scripts[cursor]
            if not entry then preflightPlatform(); return end
            cursor = cursor + 1
            local ok, item = pcall(instanceItem, entry.fullType)
            if ok and item then
                Categories.prepareItem(item)
                local category = item:getDisplayCategory() or 'Generic'
                groups[category] = groups[category] or {}
                groups[category][#groups[category] + 1] = item
                created = created + 1
            else
                skipped = skipped + 1
                print('[ITEM_CATALOG] SKIP item=' .. entry.fullType .. ' reason=' .. tostring(item))
            end
        end
        status(tr('Items') .. ' ' .. (cursor - 1) .. '/' .. #scripts)
    elseif phase == 'floor' then
        local cell, chunks = getCell(), {}
        for _ = 1, 32 do
            if floorCursor >= width * height then phase = 'crates'; break end
            local x, y = minX + floorCursor % width, minY + math.floor(floorCursor / width)
            local square = cell:getGridSquare(x, y, level) or cell:createNewGridSquare(x, y, level, true)
            assert(square, 'Could not create catalogue floor tile')
            cell:setCacheGridSquare(x, y, level, square)
            assert(square:addFloor('carpentry_02_57'), 'Could not add catalogue floor')
            chunks[cell:getChunkForGridSquare(x, y, 0)] = true
            floorCursor = floorCursor + 1
        end
        for chunk in pairs(chunks) do cell:setCacheChunk(chunk) end
        status(tr('Floor') .. ' ' .. floorCursor .. '/' .. width * height)
    elseif phase == 'crates' then
        local spec = crates[crateCursor]
        if not spec then
            record.complete = true
            scripts, groups, crates = nil, nil, nil
            finish(); return
        end
        local square = assert(getCell():getGridSquare(minX + spec.dx, minY + spec.dy, level))
        local obj = IsoThumpable.new(getCell(), square, 'carpentry_01_16', false, {})
        obj:setBlockAllTheSquare(true); obj:setIsContainer(true)
        local container = assert(obj:getContainer())
        container:setType('crate'); container:setCapacity(100); container:setExplored(true)
        local name = string.format('%03d', crateCursor) .. ' | ' .. spec.label
        local data = obj:getModData()
        data.PZSTItemCatalogCrate = {number = crateCursor, name = name}
        data.crate_customContainerName = name
        data.container_0_customContainerName = name
        square:AddSpecialObject(obj)
        for _, item in ipairs(spec.items) do
            container:AddItem(item)
            assert(item:getContainer() == container, 'Catalogue item did not enter its crate')
            local ids = Tags.forItem(item)
            indexFile:write(crateCursor .. '\t' .. Catalog.tsv(item:getDisplayName()) .. '\t'
                .. Catalog.tsv(item:getFullType()) .. '\t' .. Catalog.tsv(spec.category) .. '\t'
                .. Catalog.tsv(table.concat(ids, ',')) .. '\n')
        end
        record.crates[#record.crates + 1] = {x = square:getX(), y = square:getY(), name = name}
        crateCursor = crateCursor + 1
        status(tr('Crates') .. ' ' .. #record.crates .. '/' .. #crates)
    end
end

Events.OnTick.Add(function()
    if not started or failed or not isIngameState() then return end
    if ready then
        readyFrames = readyFrames + 1
        if readyFrames == 10 then getCore():TakeFullScreenshot('item-catalog-ready.png') end
        local player = getPlayer()
        if player:getZ() ~= level or player:getX() < minX + .5 or player:getY() < minY + .5
            or player:getX() >= minX + width - .5 or player:getY() >= minY + height - .5 then
            player:teleportTo(minX + 1.5, minY + 1.5, level)
        end
        return
    end
    local ok, problem = pcall(populate)
    if not ok then
        failed = true
        if indexFile then indexFile:close(); indexFile = nil end
        status(tostring(problem)); print('[ITEM_CATALOG] FAIL ' .. tostring(problem))
    end
end)

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    if not ready or getWorld():getWorld() ~= Catalog.world then return end
    local unique, lines = {}, {}
    local function add(item)
        if item and not unique[item:getFullType()] then
            unique[item:getFullType()] = true; lines[#lines + 1] = itemDescription(item)
        end
    end
    for _, value in ipairs(items) do
        if instanceof(value, 'InventoryItem') then add(value)
        elseif value.items then for _, item in ipairs(value.items) do add(item) end end
    end
    if #lines > 0 then
        context:addOption(tr('Copy'), nil,
            function() Clipboard.setClipboard(table.concat(lines, '\n')) end)
    end
end)
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, objects, test)
    if test or not ready or getWorld():getWorld() ~= Catalog.world then return end
    for _, obj in ipairs(objects) do
        local data = obj:getModData().PZSTItemCatalogCrate
        if data then context:addOption(data.name, nil, function() Clipboard.setClipboard(data.name) end); break end
    end
end)
Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_F6 and ready and isIngameState() and getWorld():getWorld() == Catalog.world then
        getPlayer():teleportTo(minX + 1.5, minY + 1.5, level)
    end
end)
