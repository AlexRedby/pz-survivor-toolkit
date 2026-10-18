require 'ISUI/Animal/ISAnimalContextMenu'
require 'PZSurvivorToolkit/AnimalInfo'
require 'PZSurvivorToolkit/ActionQueueAnimals'
require 'TimedActions/Animals/ISButcherAnimal'
require 'TimedActions/ISEquipWeaponAction'
local Setup = require 'QueueAnimalFixSetup'
local entered, starting, started = false, false, false
local phase, since, deadline, frame = 'startup', 0, nil, 0
local player, hutch, dead, live, window, observation
local bodies, head, tail, outputs, seenButchers = {}, nil, nil, {}, {}

local function log(message) print('[ANIMAL_FIX_TEST] '..message) end
local function transition(nextPhase)
    phase, since = nextPhase, getTimestampMs()
    log('PHASE '..phase)
end
local function fail(reason)
    if phase == 'failed' then return end
    phase = 'failed'
    print('[QUEUE_TEST] FAIL animal-fixes '..tostring(reason))
end
local function shot(name)
    getCore():TakeFullScreenshot('animal-fixes-'..name..'.png')
    log('SCREENSHOT_REQUEST animal-fixes-'..name..'.png')
end

Events.OnMainMenuEnter.Add(function() entered = true end)
Events.OnPreUIDraw.Add(function()
    frame = frame + 1
    if started and isIngameState() and isGamePaused() then setGameSpeed(1) end
    if not entered or starting or isIngameState() then return end
    starting = true
    local ok, reason = pcall(function()
        assert(not isClient() and not isServer(), 'fresh singleplayer fixture required')
        getCore():setOptionPauseOnFocusloss(false)
        getWorld():setGameMode('Sandbox'); getWorld():setWorld('QueueAnimalFixes')
        getWorld():setMap('Muldraugh, KY')
        MainScreen.instance:setDefaultSandboxVars()
        getSandboxOptions():getOptionByName('Zombies'):setValue(6)
        getSandboxOptions():toLua()
        local current, active = ActiveMods.getById('currentGame'), getActivatedMods()
        current:getMods():clear()
        for i = 0, active:size() - 1 do current:getMods():add(active:get(i)) end
        MainScreen.instance.createWorld = true
        MapSpawnSelect.instance.selectedRegion = {points = {unemployed = {{posX=10835,posY=10144,posZ=0}}}}
        MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
        MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
    end)
    if not ok then fail(reason) end
end)
Events.OnGameStart.Add(function()
    started = true
    deadline = getTimestampMs() + 300000
    log('GAME_START version='..getCore():getVersion())
end)

local function openInfo(animal, label)
    local originalNew, captured = ISAnimalUI.new, nil
    ISAnimalUI.new = function(...)
        captured = originalNew(...)
        return captured
    end
    local ok, reason = pcall(AnimalContextMenu.onAnimalInfo, animal, player)
    ISAnimalUI.new = originalNew
    assert(ok, reason)
    window = assert(captured, 'native info callback did not construct ISAnimalUI')
    observation = {prerenders=0, renders=0, lastFrame=-1, label=label}
    local observed = observation
    local prerender, render = window.prerender, window.render
    window.prerender = function(self)
        local success, error = pcall(prerender, self)
        if not success then fail(label..' prerender '..tostring(error)); return end
        observed.prerenders = observed.prerenders + 1
    end
    window.render = function(self)
        local success, error = pcall(render, self)
        if not success then fail(label..' render '..tostring(error)); return end
        if self:isVisible() and observed.lastFrame ~= frame then
            observed.renders = observed.renders + 1
            observed.lastFrame = frame
        end
    end
    transition(label..'-info')
end

local function checkInfo(isDead)
    assert(window:isVisible(), observation.label..' native info closed itself')
    assert(window.animal == (isDead and dead or live), 'info target changed')
    assert(hutch:getAnimal(dead:getData():getHutchPosition()) == dead
        and dead:getHealth() <= 0 and dead:getHutch() == hutch, 'dead hen left actual hutch')
    assert(live:getHealth() > 0 and live:getHutch() == hutch, 'live hen left actual hutch')
    if observation.renders > 2 then
        if isDead then
            for _, button in ipairs({window.renameBtn, window.feedBtn, window.milkAnimalBtn,
                    window.ageBtn, window.genderBtn}) do
                assert(button.enable == false, 'dead animal mutation button enabled after native render')
            end
        else
            assert(window.renameBtn.enable == true, 'live animal rename disabled')
        end
    end
    if observation.renders >= 8 and getTimestampMs() - since >= 4000 and not observation.shot then
        assert(observation.prerenders >= observation.renders, 'render count exceeds prerender count')
        log('RENDERED '..observation.label..' distinctFrames='..observation.renders
            ..' actualIsoHutch=true nativeCallback=true')
        shot(isDead and 'dead-info' or 'live-info')
        observation.shot = true
    end
    return observation.shot and getTimestampMs() - since >= 8000
end

local function observeEquip(action, label)
    local complete = action.complete
    action.complete = function(self, ...)
        local result = complete(self, ...)
        assert(result == true and self.character:getPrimaryHandItem() == self.item,
            label..' native equip did not complete')
        self.fixtureComplete = true
        log('NATIVE_COMPLETE '..label)
        return result
    end
    return action
end

local function beginGround()
    assert(#ISTimedActionQueue.getTimedActionQueue(player).queue == 0, 'initial queue is not empty')
    assert(not player:isTimedActionInstant(), 'instant timed actions invalidate native duration test')
    local square = player:getSquare()
    bodies = {Setup.corpse(square), Setup.corpse(square)}
    for _, fullType in ipairs({'Base.ChickenWhole', 'Base.ChickenFoot', 'Base.Chicken_Hen_Brown_Head'}) do
        outputs[fullType] = Setup.count(player, fullType)
    end
    local inventory = player:getInventory()
    local knife = assert(inventory:AddItem('Base.HuntingKnife'), 'missing native butcher knife')
    assert(knife:hasTag(ItemTag.BUTCHER_ANIMAL) and not knife:isBroken(), 'invalid native butcher knife')
    local hammer = assert(inventory:AddItem('Base.Hammer'))
    local screwdriver = assert(inventory:AddItem('Base.Screwdriver'))
    head = observeEquip(ISEquipWeaponAction:new(player, hammer, 180, true, false), 'head')
    tail = observeEquip(ISEquipWeaponAction:new(player, screwdriver, 50, true, false), 'tail')
    ISTimedActionQueue.add(head)
    transition('head-running')
end

local function tick()
    if not started or phase == 'failed' or phase == 'done' then return end
    assert(getTimestampMs() < deadline, 'fixture overall 300s deadline')
    if not player then
        player = getPlayer()
        if not player or not player:getSquare() then player = nil; return end
        assert(not isClient() and not isServer(), 'fixture requires SP authority')
        assert(PZSurvivorToolkit.Settings.actionQueue(), 'Toolkit action queue is disabled')
        player:setGodMod(true); player:setGhostMode(true)
        getGameTime():setTimeOfDay(12)
        if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
        AnimalContextMenu.cheat = false
        hutch = Setup.hutchNear(player)
        local sq = hutch:getSquare()
        dead, live = Setup.hen(sq), Setup.hen(sq)
        dead:getData():setPreferredHutchPosition(0)
        live:getData():setPreferredHutchPosition(1)
        assert(hutch:addAnimalInside(dead), 'native hutch rejected dead-test hen')
        assert(hutch:addAnimalInside(live), 'native hutch rejected live hen')
        hutch:killAnimal(dead)
        assert(hutch:getDeadBody(dead:getData():getHutchPosition()), 'native hutch death missing IsoDeadBody')
        log('SETUP player='..player:getX()..','..player:getY()..' hutch='..sq:getX()..','..sq:getY()
            ..' deadPosition='..dead:getData():getHutchPosition()..' livePosition='..live:getData():getHutchPosition())
        openInfo(dead, 'dead')
    elseif phase == 'dead-info' then
        if checkInfo(true) then window:close(); window:removeFromUIManager(); openInfo(live, 'live') end
    elseif phase == 'live-info' then
        if checkInfo(false) then
            window:close(); window:removeFromUIManager()
            print('[QUEUE_TEST] PASS animal-info')
            beginGround()
        end
    elseif phase == 'head-running' then
        local queue = ISTimedActionQueue.getTimedActionQueue(player)
        assert(getTimestampMs() - since < 15000, 'native head did not start within 15s')
        assert(queue.queue[1] == head, 'unrelated native head disappeared before append')
        if queue.current ~= head or not head.action or not head:isStarted() then return end
        local knife = player:getInventory():getFirstTagEvalRecurse(ItemTag.BUTCHER_ANIMAL,
            function(item) return not item:isBroken() end)
        for _, body in ipairs(bodies) do AnimalContextMenu.onButcherAnimal(body, player, knife) end
        ISTimedActionQueue.add(tail)
        assert(queue.queue[1] == head and queue.queue[#queue.queue] == tail,
            'butchering append replaced unrelated native head or tail')
        assert(#queue.queue == 4, 'expected head, two deferred butcher commands, tail')
        log('APPENDED nativeHeadRetained=true nativeTailRetained=true corpses=2 queue='..#queue.queue)
        transition('butchering')
    elseif phase == 'butchering' then
        local queue = ISTimedActionQueue.getTimedActionQueue(player)
        assert(getTimestampMs() - since < 180000, 'normal-duration butcher queue did not drain within 180s')
        if not outputs.shot and getTimestampMs() - since >= 500 then
            shot('queue'); outputs.shot = true
        end
        for _, action in ipairs(queue.queue) do
            if action.Type == 'ISButcherAnimal' then
                -- Native create scales maxTime for moodles, wounds and body temperature.
                assert(action:getDuration() == 900 - action.perkLevel * 20 and action.maxTime > 1,
                    'butchering did not retain normal native duration')
                if not seenButchers[action.body] then
                    log('DURATION base='..action:getDuration()..' actualMax='..action.maxTime)
                end
                seenButchers[action.body] = true
            end
        end
        if #queue.queue ~= 0 then
            if not tail.fixtureComplete then assert(queue:indexOf(tail) >= 1, 'native tail was discarded') end
            return
        end
        assert(head.fixtureComplete and tail.fixtureComplete, 'unrelated native actions did not both complete')
        assert(player:getPrimaryHandItem() == tail.item, 'native tail equip effect is missing')
        for _, body in ipairs(bodies) do
            assert(seenButchers[body], 'native ISButcherAnimal was never queued for a corpse')
            assert(body:getStaticMovingObjectIndex() == -1, 'hen corpse not consumed by native butchering')
        end
        for fullType, expected in pairs({['Base.ChickenWhole']=2, ['Base.ChickenFoot']=4,
                ['Base.Chicken_Hen_Brown_Head']=2}) do
            local gained = Setup.count(player, fullType) - outputs[fullType]
            assert(gained == expected, 'native output mismatch '..fullType..' gained='..gained)
            log('OUTPUT '..fullType..' gained='..gained)
        end
        print('[QUEUE_TEST] PASS ground-butchering')
        transition('capture-flush')
    elseif phase == 'capture-flush' and getTimestampMs() - since >= 3000 then
        phase = 'done'
        log('COMPLETE')
    end
end

Events.OnTick.Add(function()
    local ok, reason = pcall(tick)
    if not ok then fail(reason) end
end)
