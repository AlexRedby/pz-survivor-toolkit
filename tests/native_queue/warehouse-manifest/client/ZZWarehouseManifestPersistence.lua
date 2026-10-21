local selection = require 'QueueTestSelection'
local case = selection.cases[1]
if case ~= 'persist-seed' and case ~= 'persist-reload' then return end
local P = require 'WarehouseManifestPersistence'
local F = require 'WarehouseManifestFixture'
local Client = require 'PZSurvivorToolkit/ManifestClient'
local JSON = require 'QueueHealthEvents'
local FLAG = 'warehouse-manifest-rejoin.txt'
local function flag()
 local reader = getFileReader(FLAG, false); if not reader then return end
 local value = reader:readLine(); reader:close(); return value
end
local function writeFlag(value)
 local writer = assert(getFileWriter(FLAG, true, false)); writer:write(value); writer:close()
end
local resuming = flag() == 'pending'
local started, initialized, done, since, stage, meta, role, target, arrived, phase, win, readyAt
local reconnecting, finished, sent, setupLogged = false, false, false, resuming
local exitRequestedAt, exitPhase
local function emit(event, value) print('[WAREHOUSE_PERSIST] ' .. event .. ' ' .. JSON.encode(value)) end
local function standard(event, extra)
 local value = extra or {}; value.event, value.suite, value.actor = event, 'warehouse-manifest', role
 value.kind, value.mode = selection.kind, selection.mode
 print('[QUEUE_CHECK] ' .. JSON.encode(value))
end
local function open()
 if LootSorter._manifestWin then LootSorter._manifestWin:close() end
 LootSorter.toggleManifest(0); win = assert(LootSorter._manifestWin, 'Persistence window did not open')
end
local function initialize()
 if initialized then return true end
 local player = getPlayer(); local actor = player and player:getUsername()
 if not player or player:isDead() or not player:getSquare() or not isClient() or player:getOnlineID() < 0
  or actor ~= 'client1' and actor ~= 'client2' then
  assert(getTimestampMs() - since < 30000, 'Persistence native actor readiness timeout'); return false
 end
 role, initialized = actor, true
 assert(PZSurvivorToolkit.Settings.actionQueue(), 'Wrong persistence queue feature mode')
 player:setGodMod(true); player:setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 if not setupLogged then
  setupLogged = true
  emit('SETUP', {case = case, role = role, language = Translator.getLanguage():name(), onlineID = player:getOnlineID()})
  standard('setup', {cases = selection.cases, expected = 1, nativeDurations = true, queueEnabled = true})
 else
  assert(resuming and role == 'client2', 'Unexpected repeated persistence setup')
  emit('REJOIN', {role = role, onlineID = player:getOnlineID(), nativeConnected = true})
 end
 sendClientCommand(P.module, 'Prepare', {reconnect = resuming})
 return true
end
Events.OnGameStart.Add(function() started, since, initialized = true, getTimestampMs(), false end)
local function connectAgain()
 if not resuming or reconnecting or isIngameState() then return end
 if not MainScreen or not MainScreen.instance or not ConnectToServer or not ConnectToServer.instance then return end
 if MainScreen.instance.inGame ~= false or not MainScreen.instance:isVisible() then return end
 if flag() ~= 'pending' then return end
 resuming, reconnecting = true, true
 started, initialized, meta, target, stage, phase, win, arrived, sent = false, false, nil, nil, nil, nil, nil, false, false
 ConnectToServer.instance:connect(MainScreen.instance, 'Warehouse persistence rejoin', 'client2',
  'smoke-local-only', '127.0.0.1', '', tostring(selection.port), '', false, true, 1)
end
Events.OnMainMenuEnter.Add(connectAgain)
Events.OnPreUIDraw.Add(connectAgain)
Events.OnServerCommand.Add(function(module, command, args)
 if module ~= P.module then return end
 if command == 'Prepared' then
  assert(args.role == role, 'Persistence server assigned another native actor')
  meta = {packet = args.packet, home = args.home, away = args.away, tokens = args.tokens, staleIds = args.staleIds}
  stage = args.stage; target = (stage == 'restored') and meta.away or meta.home
  arrived, sent, phase, readyAt = false, false, nil, nil
 elseif command == 'Travel' then
  stage, target, arrived, sent, phase, readyAt = args.stage, args.point, false, false, nil, nil
 elseif command == 'Phase' then
  stage, phase, sent, readyAt = args.stage, args, false, nil
  meta.packet, meta.staleIds = args.packet, args.staleIds
 elseif command == 'Reconnect' then
  assert(role == 'client2' and case == 'persist-seed', 'Only seed observer may reconnect')
  assert(not exitRequestedAt, 'Duplicate persistence native exit request')
  exitRequestedAt, exitPhase = getTimestampMs(), 'pause'
 elseif command == 'Done' then finished = true end
end)
-- Use the game's pause-menu path, which owns hiding game UI before the disconnect fade.
-- A packet callback only requests this transition; native UI runs on a later engine tick.
local function exitTick()
 if not exitRequestedAt or done then return end
 local ok, problem = pcall(function()
  assert(getTimestampMs() - exitRequestedAt < 30000, 'Persistence native pause/exit timeout')
  local menu = assert(MainScreen and MainScreen.instance, 'Native pause menu unavailable')
  assert(isIngameState() and menu.inGame == true, 'Native pause exit requested outside the game')
  if exitPhase == 'pause' then
   if win then win:close(); win = nil end
   if not menu:isVisible() then
    assert(type(ToggleEscapeMenu) == 'function' and KeybindId and Keyboard, 'Native pause binding unavailable')
    local key = getCore():getKey(KeybindId.MAIN_MENU)
    if key == 0 then key = Keyboard.KEY_ESCAPE end
    assert(type(key) == 'number', 'Native pause binding is not a key')
    ToggleEscapeMenu(key)
   end
   exitPhase = 'exit'
   return
  end
  if not menu:isVisible() then return end
  if isQuitCooldown and isQuitCooldown() then return end
  local option = assert(menu.exitOption, 'Native pause Exit option unavailable')
  assert(option.internal == 'EXIT' and type(option.onMouseDown) == 'function', 'Native pause Exit callback unavailable')
  writeFlag('pending'); emit('DISCONNECT', {role = role, onlineID = getPlayer():getOnlineID(), nativeExitToMenu = true})
  started, initialized, resuming, reconnecting = false, false, true, false
  meta, target, stage, phase, exitRequestedAt, exitPhase = nil, nil, nil, nil, nil, nil
  option.onMouseDown(option, 0, 0)
 end)
 if not ok then done = true; print('[WAREHOUSE_PERSIST] FAIL ' .. tostring(role) .. ' ' .. tostring(problem)) end
end
Events.OnTickEvenPaused.Add(exitTick)
local function tick()
 if not initialize() or not meta then return end
 local player = getPlayer()
 if target and not arrived then
  if not P.near(player, target) then player:teleportTo(target.x + .5, target.y + .5, target.z); return end
  arrived = true
  if not win then open() end
  sendClientCommand(P.module, 'Arrived', {stage = stage})
 end
 if phase and not sent then
  if phase.loaded then
   if not P.native(meta, player) then return end
  elseif not P.absent(meta.packet) then return end
  local expectedSamples
  if not phase.loaded then expectedSamples = phase.samples end
  local result = P.current(Client.getState(0).payload, meta, stage, phase.loaded, expectedSamples)
  if not result then return end
  local sum = 0
  for _, row in ipairs(win.listBox.items) do sum = sum + row.item.n end
  if sum ~= 4 or #win.listBox.items ~= 2 then return end
  readyAt = readyAt or getTimestampMs(); if getTimestampMs() - readyAt < 800 then return end
  result.role, result.language, result.worldAbsent, result.nativeIds, result.windowCount = role, Translator.getLanguage():name(), not phase.loaded, phase.loaded, sum
  emit('STATE', result)
  getCore():TakeFullScreenshot('warehouse-persist-' .. stage .. '.png'); emit('SHOT', {role = role, stage = stage})
  if stage == 'rejoined' and role == 'client2' then writeFlag('verified') end
  sent = true; sendClientCommand(P.module, 'Seen', {stage = stage})
 end
 if finished then
  if win then win:close(); win = nil end
  standard('case', {id = case, status = 'passed', persistedCounts = true})
  standard('complete', {passed = 1, failed = 0, skipped = 0})
  emit('COMPLETE', {case = case, role = role}); done = true
 end
end
Events.OnTick.Add(function()
 if not started or done or exitRequestedAt or not isIngameState() then return end
 local ok, problem = pcall(function()
  assert(getTimestampMs() - since < 600000, 'Persistence native client timeout stage=' .. tostring(stage)); tick()
 end)
 if not ok then done = true; print('[WAREHOUSE_PERSIST] FAIL ' .. tostring(role) .. ' ' .. tostring(problem)) end
end)
