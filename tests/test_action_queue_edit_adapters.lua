if not NativeActionRoot then print('Radio edit adapters SKIP (pass --native-action-root).'); return end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local value = file:read('*a'); file:close(); return value:gsub('\r', '')
end
local function reader(text)
    local position = 1
    return {close = function() end, readLine = function()
        if position > #text then return end
        local boundary = text:find('\n', position, true) or #text + 1
        local value = text:sub(position, boundary - 1); position = boundary + 1; return value
    end}
end
local function setup(foreign, changedSource)
    local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
    f.native('shared/RadioCom/ISRadioAction.lua')
    isClient, isServer = function() return false end, function() return false end
    getFilenameOfClosure = NativeFilenameOfClosure or function(callback) return debug.getinfo(callback, 'S').source end
    local state = {changed = changedSource, readers = 0}
    getGameFilesInput = function(path)
        state.readers = state.readers + 1
        local text = read(NativeActionRoot .. '/' .. path:gsub('^media/lua/', ''))
        if state.changed and path:find(state.changed, 1, true) then text = text .. '-- unreviewed source\n' end
        return reader(text)
    end
    if foreign == 'base' then ISBaseTimedAction.invoke = function() error('foreign inherited helper must not execute') end
    elseif foreign then ISRadioAction.performSetVolume = function() error('foreign helper must not execute') end end
    local adapters = f.project('ActionQueueEditAdapters')
    local model = f.project('ActionQueueEditModel')
    f.player.class = 'IsoPlayer'
    f.player.setIsFarming = function() end
    f.player.playSound = function() state.sounds = (state.sounds or 0) + 1 end
    ISLogSystem = {logAction = function() end}
    -- Keep the upstream perform boundary, and explicitly model only Java getters/setters.
    ISTimedActionQueue.queues[f.player] = {onCompleted = function() state.completed = (state.completed or 0) + 1 end}
    local function device(kind)
        local object = {class = kind or 'IsoTelevision'}
        local square = {class = 'IsoGridSquare'}
        local data = {class = 'DeviceData', on = true, power = 1, volume = 0.5, channel = 200,
            mic = false, minimum = 100, maximum = 1000, writes = 0}
        object.getObjectIndex = function(self) return self.gone and -1 or 0 end
        object.getSquare = function(self) return not self.noSquare and square or nil end
        object.getDeviceData = function() return data end
        data.getParent = function(self) return self.wrongParent or object end
        data.isIsoDevice = function(self) return not self.portable end
        data.isVehicleDevice = function(self) return self.vehicle or false end
        data.getIsTurnedOn = function(self) return self.on end
        data.getPower = function(self) return self.power end
        data.getDeviceVolume = function(self) return self.volume end
        data.getChannel = function(self) return self.channel end
        data.getMicIsMuted = function(self) return self.mic end
        data.getMinChannelRange = function(self) return self.minimum end
        data.getMaxChannelRange = function(self) return self.maximum end
        data.getIsTelevision = function() return object.class == 'IsoTelevision' end
        data.getIsBatteryPowered = function(self) return self.batteryPowered or false end
        data.canBePoweredHere = function(self) return self.powerable ~= false end
        data.setIsTurnedOn = function(self, value) self.on = value; self.writes = self.writes + 1 end
        data.stopOrTriggerSoundByName = function() state.sounds = (state.sounds or 0) + 1 end
        data.playSoundSend = function() state.sounds = (state.sounds or 0) + 1 end
        data.setDeviceVolume = function(self, value) self.volume = math.max(0, math.min(1, value)); self.writes = self.writes + 1 end
        data.setMicIsMuted = function(self, value) self.mic = value; self.writes = self.writes + 1 end
        data.setChannel = function(self, value)
            if value >= self.minimum and value <= self.maximum then self.channel = value; self.writes = self.writes + 1 end
        end
        return object, data
    end
    local object, data = device()
    local function action(mode, value, target)
        local result = ISRadioAction:new(mode, f.player, target or object, value)
        result.toolkitQueueOperation = {}
        return result
    end
    local function entry(action)
        return {action = action, edit = assert(adapters.radio(action), 'native pending setter must be described')}
    end
    return {f = f, adapters = adapters, model = model, state = state, object = object, data = data,
        device = device, action = action, entry = entry}
end

do
    local s = setup()
    local a, b = s.action('SetVolume', 0.25), s.action('SetVolume', 0.75)
    assert(s.model.evaluate({s.entry(a), s.entry(b)}).status == 'allowed')
    assert(s.model.evaluate({s.entry(b), s.entry(a)}).status == 'allowed', 'different final volume is legal')
    assert(s.state.readers == 2, 'repeated inspection pins each native file only once')
    for i = 1, 20 do assert(s.adapters.radio(a) and s.adapters.radio(b)) end
    assert(s.state.readers == 2, 'UI row inspection must reuse the source proof')
    assert(s.data.writes == 0 and not s.state.completed and not s.state.sounds, 'inspection/projection cannot execute native effects')
    assert(a:isValid() and b:isValid()); a:perform(); b:perform()
    assert(s.data.volume == 0.75 and s.data.writes == 2 and s.state.completed == 2, 'native original order retains both setter effects')
    s.data.volume, s.data.writes = 0.5, 0
    b:perform(); a:perform()
    assert(s.data.volume == 0.25 and s.data.writes == 2 and s.state.completed == 4, 'native reordered actions produce the requested final state')
    s.data.writes = 0
    assert(s.model.evaluate({s.entry(b)}).status == 'allowed')
    a:forceCancel(); b:perform()
    assert(s.data.volume == 0.75 and s.data.writes == 1, 'pending cancellation preserves the surviving native action')
    for _, value in ipairs({-5, 5}) do
        local action = s.action('SetVolume', value)
        local expected = value < 0 and 0 or 1
        assert(s.adapters.radio(action).resources[1].effects[1].set == expected)
        action:perform(); assert(s.data.volume == expected, 'projection matches native clamped volume')
    end
    local mute, unmute = s.action('MuteMicrophone', true), s.action('MuteMicrophone', false)
    assert(s.entry(unmute).edit.resources[1].effects[1].set == false, 'false is a setter value')
    assert(s.model.evaluate({s.entry(mute), s.entry(unmute)}).status == 'allowed')
    mute:perform(); unmute:perform(); assert(s.data.mic == false)
    unmute:perform(); mute:perform(); assert(s.data.mic == true)
    local one, two = s.action('SetChannel', 300), s.action('SetChannel', 400)
    assert(s.model.evaluate({s.entry(two), s.entry(one)}).status == 'allowed')
    two:start(); two:perform(); one:start(); one:perform()
    assert(s.data.channel == 300 and s.state.sounds > 0, 'upstream tuning start/perform keeps native audio effects')
    local radio = s.device('IsoRadio')
    assert(s.adapters.radio(s.action('SetVolume', 0.5, radio)), 'fixed world radio shares the supported device contract')
end

-- Production order: Policy captures the adapter before Queue replaces inherited begin/stop.
do
    local s = setup()
    local inheritedBegin, inheritedStop = ISBaseTimedAction.begin, ISBaseTimedAction.stop
    local previousRequire = require
    require = function(module)
        if module == 'PZSurvivorToolkit/ActionQueueEditAdapters' then return s.adapters end
        if module == 'PZSurvivorToolkit/ActionQueueEditModel' then return s.model end
        if module == 'PZSurvivorToolkit/ActionQueuePolicy' then return PZSurvivorToolkit.ActionQueuePolicy end
        return previousRequire(module)
    end
    s.f.project('ActionQueueOperations'); s.f.project('ActionQueueDefinitions')
    local policy = s.f.project('ActionQueuePolicy')
    s.f.project('ActionQueueLabels'); s.f.project('ActionQueue')
    local action = s.action('SetVolume', 0.25)
    assert(ISBaseTimedAction.begin ~= inheritedBegin and ISBaseTimedAction.stop ~= inheritedStop,
        'fixture loads the actual inherited queue hooks')
    assert(s.adapters.radio(action), 'owned begin/stop adoption keeps the pending radio adapter available')
    assert(policy.inspect(action).edit, 'actual Queue/Policy integration retains the edit descriptor')
    assert(not s.adapters.adoptBase('perform', ISBaseTimedAction.perform, ISBaseTimedAction.perform),
        'adoption cannot authorize other lifecycle hooks')
    for _, name in ipairs({'begin', 'stop'}) do
        local previous = ISBaseTimedAction[name]
        local foreign = function() error('foreign inherited hook must not execute') end
        ISBaseTimedAction[name] = foreign
        assert(not s.adapters.adoptBase(name, previous, foreign), 'foreign inherited wrapper cannot be adopted')
        assert(not s.adapters.radio(action), 'foreign inherited hook revokes the adapter: ' .. name)
        ISBaseTimedAction[name] = previous
        assert(s.adapters.radio(action), 'restoring the owned hook restores the adapter')
        assert(not s.adapters.adoptBase(name, name == 'begin' and inheritedBegin or inheritedStop, previous),
            'an already adopted boundary cannot be adopted from a stale previous callback')
    end
    assert(s.data.writes == 0, 'actual Queue load and policy inspection execute no radio effects')
end

-- Native mute/unmute retain their strict state dependency in the projection.
do
    local s = setup()
    local mute, unmute = s.action('MuteVolume'), s.action('UnMuteVolume', 0.4)
    assert(s.adapters.radio(mute) and s.adapters.radio(unmute))
    assert(s.model.evaluate({s.entry(mute), s.entry(unmute)}).status == 'allowed')
    assert(s.model.evaluate({s.entry(unmute), s.entry(mute)}).status == 'denied')
    assert(mute:isValid() and not unmute:isValid(), 'unmuting audible native volume is invalid')
    mute:perform(); assert(s.data.volume == 0 and unmute:isValid())
    unmute:perform(); assert(s.data.volume == 0.4 and mute:isValid())
    s.data.on = false
    for _, action in ipairs({s.action('SetVolume', 0.5), s.action('SetChannel', 300), s.action('MuteMicrophone', false)}) do
        assert(not action:isValid())
        assert(s.model.evaluate({s.entry(action)}).status == 'denied', 'projection retains native powered/on requirements')
    end
    s.data.on, s.data.power = true, 0
    assert(s.model.evaluate({s.entry(s.action('SetVolume', 0.5))}).status == 'denied')
end

do
    local s = setup()
    local action = s.action('SetVolume', 0.5)
    for _, field in ipairs({'onStartFunc', 'onCompleteFunc', 'onCancelFunc', 'onFailFunc', 'additionalTest', 'performSetVolume', 'customHelper'}) do
        action[field] = function() error('foreign callback must not execute') end
        assert(not s.adapters.radio(action), 'foreign action hook rejects ' .. field); action[field] = nil
    end
    for _, field in ipairs({'perform', 'isValid', 'start', 'complete', 'performSetVolume', 'startSetVolume'}) do
        local previous = ISRadioAction[field]
        ISRadioAction[field] = function() error('foreign class helper must not execute') end
        assert(not s.adapters.radio(action), 'changed helper rejects ' .. field); ISRadioAction[field] = previous
    end
    local previous = ISBaseTimedAction.perform
    ISBaseTimedAction.perform = function() error('foreign base perform must not execute') end
    assert(not s.adapters.radio(action)); ISBaseTimedAction.perform = previous
    local filename = getFilenameOfClosure
    getFilenameOfClosure = function(callback)
        if callback == ISRadioAction.performSetVolume then return '@foreign.lua' end
        return filename(callback)
    end
    assert(not s.adapters.radio(action), 'source identity is required beyond method equality')
    getFilenameOfClosure = filename
    s.state.changed = 'ISRadioAction.lua'
    assert(s.adapters.radio(action) and s.state.readers == 2, 'disk changes do not replace already loaded callbacks or repeat hashing')
    local input = getGameFilesInput
    getGameFilesInput = nil; assert(not s.adapters.radio(action)); getGameFilesInput = input
    getFilenameOfClosure = nil; assert(not s.adapters.radio(action)); getFilenameOfClosure = filename
    assert(s.adapters.radio(action), 'restored proof APIs restore permission')
    assert(s.data.writes == 0 and not s.state.completed and not s.state.sounds)
end
do
    local s = setup()
    local action = s.action('SetVolume', 0.5)
    local input, filename = getGameFilesInput, getFilenameOfClosure
    getGameFilesInput = nil; assert(not s.adapters.radio(action)); getGameFilesInput = input
    getFilenameOfClosure = nil; assert(not s.adapters.radio(action)); getFilenameOfClosure = filename
    assert(s.state.readers == 0 and s.adapters.radio(action) and s.state.readers == 2,
        'unavailable proof APIs do not permanently reject a later source check')
end
for _, source in ipairs({'ISRadioAction.lua', 'ISBaseTimedAction.lua'}) do
    local s = setup(false, source)
    local action = s.action('SetVolume', 0.5)
    assert(not s.adapters.radio(action), 'changed source cannot acquire a fresh adapter proof')
    local readers = s.state.readers
    s.state.changed = nil
    assert(not s.adapters.radio(action) and s.state.readers == readers, 'failed source proof is cached for this module instance')
end
do
    local s = setup(true)
    assert(not s.adapters.radio(s.action('SetVolume', 0.5)), 'preinstalled foreign mode helper is not a trusted baseline')
end
do
    local s = setup('base')
    assert(not s.adapters.radio(s.action('SetVolume', 0.5)), 'preinstalled foreign inherited helper is not a trusted baseline')
end

do
    local s = setup()
    for _, mode in ipairs({'TogglePlayMedia', 'AddHeadphones', 'RemoveHeadphones'}) do
        assert(not s.adapters.radio(s.action(mode, 0.5)), 'unsupported effect retains the existing policy: ' .. mode)
    end
    for _, value in ipairs({false, {}, 0 / 0, math.huge}) do assert(not s.adapters.radio(s.action('SetVolume', value))) end
    for _, value in ipairs({0, 1, 'false'}) do assert(not s.adapters.radio(s.action('MuteMicrophone', value))) end
    for _, value in ipairs({99, 1001, 200.5, 2147483648, math.huge}) do assert(not s.adapters.radio(s.action('SetChannel', value))) end
    for _, change in ipairs({'started', 'native', 'operation', 'duration', 'flags', 'gone', 'square', 'parent', 'binding', 'portable', 'vehicle', 'foreign-kind'}) do
        local object, data = s.device()
        local action = s.action('SetVolume', 0.5, object)
        if change == 'started' then action.started = true
        elseif change == 'native' then action.action = {}
        elseif change == 'operation' then action.toolkitQueueOperation.toolkitStarted = true
        elseif change == 'duration' then action.maxTime = 0
        elseif change == 'flags' then action.stopOnWalk = true
        elseif change == 'gone' then object.gone = true
        elseif change == 'square' then object.noSquare = true
        elseif change == 'parent' then data.wrongParent = {}
        elseif change == 'binding' then action.deviceData = s.data
        elseif change == 'portable' then data.portable = true
        elseif change == 'vehicle' then data.vehicle = true
        else object.class = 'Radio' end
        assert(not s.adapters.radio(action), 'unsupported pending/resource state rejects ' .. change)
    end
end

-- Mains-powered TV controls use native powerability, preserve toggles and setter prerequisites.
do
    local s = setup()
    local power, volume = s.action('ToggleOnOff'), s.action('SetVolume', 0.25)
    s.data.on = false
    assert(s.adapters.radioCallbacksTrusted(power) and s.adapters.radioCallbacksTrusted(s.action('TogglePlayMedia')))
    assert(s.model.evaluate({s.entry(power), s.entry(volume)}).status == 'allowed')
    assert(s.model.evaluate({s.entry(volume), s.entry(power)}).status == 'denied')
    assert(s.model.evaluate({s.entry(volume), {action=power, edit=s.adapters.radio(power), snapshotOnly=true}}).status == 'denied',
        'cancelling a required power-on must not retain the setter')
    power:perform(); volume:perform()
    assert(s.data.on and s.data.volume == 0.25, 'native power and setter callbacks retain their effects')
    assert(s.model.evaluate({s.entry(power), s.entry(volume)}).status == 'denied', 'setter after native power-off is invalid')
    s.data.powerable = false
    assert(s.model.evaluate({s.entry(power)}).status == 'denied', 'charge cannot replace missing mains electricity')
    s.data.powerable = true; s.data.power = 0; s.data.on = false
    assert(s.model.evaluate({s.entry(power)}).status == 'allowed', 'native mains powerability does not require battery charge')
    assert(s.model.evaluate({s.entry(power), s.entry(volume)}).status == 'denied', 'setter retains native getPower predicate')
    s.data.batteryPowered = true
    assert(not s.adapters.radio(power), 'battery-backed variants retain the conservative power contract')
    local radio = s.device('IsoRadio')
    assert(not s.adapters.radio(s.action('ToggleOnOff', nil, radio)), 'power expansion remains TV-only')
    power.performToggleOnOff = function() error('foreign control callback') end
    assert(not s.adapters.radioCallbacksTrusted(power) and not s.adapters.radio(power))
end

print('Radio pending edit adapters: upstream setter order/effects, native prerequisites, legacy barriers, source/helper guards and pure inspection passed.')
