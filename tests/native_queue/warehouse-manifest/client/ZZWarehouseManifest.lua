local selection = require 'QueueTestSelection'
if selection.cases[1] ~= 'snapshot' then return end
local F = require 'WarehouseManifestFixture'
local Client = require 'PZSurvivorToolkit/ManifestClient'
local JSON = require 'QueueHealthEvents'
local started, initialized, done, phase, since, nextAt = false, false, false, 'prepare', 0, 0
local role, packet, state, boxes, win, initialRevision, changedRevision, finished, trace
local transferGo, transferAction, transferProgress, transferSent
local function emit(event, value) print('[WAREHOUSE_MANIFEST] ' .. event .. ' ' .. JSON.encode(value)) end
local function standard(event, extra)
 local value = extra or {}; value.event = event; value.suite = 'warehouse-manifest'; value.actor = role
 value.kind = selection.kind; value.mode = selection.mode
 print('[QUEUE_CHECK] ' .. JSON.encode(value))
end
local function openMenu()
 local menu = ISContextMenu.get(0, 30, 30)
 LootSorter.onInvContext(0, menu, {assert(instanceItem('Quartermaster.StorageManifest'))})
 local chosen, count
 count = 0
 for _, option in ipairs(menu.options) do
  if option.onSelect == LootSorter.toggleManifest then chosen = option; count = count + 1 end
 end
 assert(count == 1 and chosen.target == 0, 'Actual native inventory menu lacks the single Manifest callback')
 chosen.onSelect(chosen.target); menu:closeAll()
 win = assert(LootSorter._manifestWin, 'Inventory menu did not open warehouse window')
 assert(win:isVisible() and win.locations and win.tagPicker, 'Warehouse UI children absent')
 trace = {text = {}, color = false}
 local drawText, drawTexture = win.locations.drawText, win.locations.drawTextureScaled
 win.locations.drawText = function(list, text, ...)
  trace.text[text] = true
  return drawText(list, text, ...)
 end
 win.locations.drawTextureScaled = function(list, texture, x, y, w, h, a, r, g, b)
  if r == F.appearance.color.r and g == F.appearance.color.g and b == F.appearance.color.b then trace.color = true end
  return drawTexture(list, texture, x, y, w, h, a, r, g, b)
 end
 emit('MENU', {role = role, nativeCallback = true})
end
local function selectDefault()
 local found
 for i, item in ipairs(win.listBox.items) do
  if item.item.key == F.identity(packet) then win.listBox.selected = i; found = item.item end
 end
 if not found then return end
 local custom
 for _, item in ipairs(win.listBox.items) do if item.item.key == F.identity(packet, true) then custom = item.item end end
 if phase ~= 'transferred' and phase ~= 'transferred-shot' then
  assert(custom and custom.name == F.custom, 'Custom item name not rendered separately')
 else assert(not custom, 'Withdrawn custom item remained in the warehouse window') end
 local defaultName = assert(getScriptManager():FindItem(F.ft)):getDisplayName()
 assert(found.name == defaultName, 'Default item label is not localized from its full type')
 assert(#found.locations == 2 and (not custom or #custom.locations == 1), 'Per-container location rows missing')
 win.selectedKey = nil; win:updateLocations()
 assert(#win.locations.items == 2, 'Native location widget lacks both sources')
 return defaultName
end
local function searchIsLocal()
 local rpc, cell, gather, calls = LootSorter.callServer, getCell, LootSorter.gatherBoxes, 0
 LootSorter.callServer = function(...) calls = calls + 1; return rpc(...) end
 getCell = function(...) calls = calls + 1; return cell(...) end
 LootSorter.gatherBoxes = function(...) calls = calls + 1; return gather(...) end
 local ok, problem = pcall(function()
  local query = F.custom
  win.filterEntry:setText(query); win.filterText = string.lower(query); win:rebuild(); win:updateLocations()
  local withdrawn = phase == 'transferred' or phase == 'transferred-shot'
  assert(#win.listBox.items == (withdrawn and 0 or 1), 'Native search count differs')
  if not withdrawn then assert(win.listBox.items[1].item.key == F.identity(packet, true), 'Native search did not select custom item') end
  win:setSort('name'); win:setSort('count')
  win.filterEntry:setText(''); win.filterText = ''; win:rebuild(); selectDefault()
 end)
 LootSorter.callServer, getCell, LootSorter.gatherBoxes = rpc, cell, gather
 assert(ok, problem); assert(calls == 0, 'Search/sort read world inventory or requested network data')
 return true
end
local function observed(which)
 local payload = Client.getState(0).payload
 local result = F.snapshot(payload, packet, which)
 if not result or not F.native(boxes, packet, which) then return end
 if which == 'changed' and result.revision <= initialRevision then return end
 if which == 'transferred' and result.revision <= changedRevision then return end
 local defaultName = selectDefault(); if not defaultName then return end
 local counts = F.counts(which)
 local defaultRow, customRow
 for _, item in ipairs(win.listBox.items) do
  if item.item.key == F.identity(packet) then defaultRow = item.item else customRow = item.item end
 end
 assert(defaultRow.n == counts[1] + counts[2] and (customRow and customRow.n or 0) == counts[3] + counts[4], 'Open window aggregate did not converge')
 result.role, result.language, result.defaultName, result.customName = role, Translator.getLanguage():name(), defaultName, F.custom
 result.appearance, result.locations, result.nativeItems = true, true, true
 return result
end
local function capture(which, result)
 assert(trace.color and trace.text[F.appearance.name] and trace.text['Warehouse fixture B'], 'Native location appearance never rendered')
 for _, point in ipairs(packet.boxes) do
  local position, drawn = point.x .. ', ' .. point.y .. ', ' .. point.z, false
  for text in pairs(trace.text) do if text:find(position, 1, true) then drawn = true end end
  assert(drawn, 'Native location coordinates never rendered')
 end
 result.rendered, result.searchLocal = true, searchIsLocal()
 emit('SNAPSHOT', result)
 getCore():TakeFullScreenshot('warehouse-manifest-' .. which .. '.png')
 emit('SHOT', {role = role, phase = which})
end
Events.OnServerCommand.Add(function(module, command, args)
 if module ~= F.module then return end
 if command == 'Prepared' then packet, role = args.target, args.role
 elseif command == 'Changed' then packet.addedIds, packet.changedAt = args.addedIds, args.changedAt
 elseif command == 'TransferGo' then transferGo = true
 elseif command == 'Transferred' then packet.transferAt = args.transferAt
 elseif command == 'Done' then finished = true end
end)
Events.OnGameStart.Add(function()
 started, since = true, getTimestampMs()
end)
local function initialize()
 if initialized then return true end
 local player = getPlayer()
 local actor = player and (selection.kind == 'sp' and 'client1' or player:getUsername())
 local ready = player and not player:isDead() and player:getSquare()
  and (selection.kind ~= 'mp' or isClient() and player:getOnlineID() >= 0)
  and (actor == 'client1' or actor == 'client2')
 if not ready then
  assert(getTimestampMs() - since < 30000, 'Warehouse fixture actor readiness timeout: ' .. tostring(actor))
  return false
 end
 role = actor
 assert(PZSurvivorToolkit.Settings.actionQueue(), 'Wrong queue feature mode')
 assert(not LootSorter._manifestXferHooked and not LootSorter.manifestTransferHooks, 'Obsolete Manifest transfer hooks remain')
 player:setGodMod(true); player:setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 emit('SETUP', {role = role, language = Translator.getLanguage():name(), kind = selection.kind, queueEnabled = true})
 standard('setup', {cases = selection.cases, expected = 1, nativeDurations = true, queueEnabled = true})
 initialized = true
 return true
end
local function tick()
 local player = getPlayer()
 if phase == 'prepare' then
  if isClient() then sendClientCommand(F.module, 'Prepare', {})
  else state, packet = F.prepare(player); emit('PREPARED', packet) end
  phase = 'resolve'
 elseif phase == 'resolve' then
  if not packet then return end
  if math.abs(player:getX() - packet.boxes[1].x) > 3 or math.abs(player:getY() - packet.boxes[1].y) > 3 then
   player:teleportTo(packet.boxes[1].x + 1.5, packet.boxes[1].y + .5, packet.boxes[1].z); return
  end
  boxes = F.resolve(packet); if not boxes then return end
  openMenu(); phase = 'initial'
 elseif phase == 'initial' or phase == 'changed' or phase == 'transferred' then
  local result = observed(phase); if not result then return end
  if phase == 'initial' then initialRevision = result.revision
  elseif phase == 'changed' then changedRevision = result.revision end
  trace = {text = {}, color = false}; phase = phase .. '-shot'; nextAt = getTimestampMs() + 1200
 elseif phase == 'initial-shot' then
  local result = assert(observed('initial'), 'Initial snapshot changed before native capture')
  capture('initial', result)
  if isClient() then sendClientCommand(F.module, 'InitialSeen', {})
  else
   emit('AUTHORITY', assert(F.native(boxes, packet, 'initial')))
   emit('MUTATED', F.mutate(state))
  end
  phase = 'changed'
 elseif phase == 'changed-shot' then
  local result = assert(observed('changed'), 'Changed snapshot changed before native capture')
  capture('changed', result)
  if isClient() then sendClientCommand(F.module, 'ChangedSeen', {})
  else emit('AUTHORITY', assert(F.native(boxes, packet, 'changed'))); transferGo = true end
  phase = 'transfer'
 elseif phase == 'transfer' then
  if role == 'client1' and transferGo and not transferAction then
   local item = assert(boxes[2]:getContainer():getItemById(packet.ids[4]))
   assert(luautils.walkAdj(player, boxes[2]:getSquare(), true), 'Native approach to withdrawal crate refused')
   transferAction = ISInventoryTransferAction:new(player, item, boxes[2]:getContainer(), player:getInventory())
   ISTimedActionQueue.add(transferAction)
  end
  if transferAction and transferAction:isStarted() and transferAction:getJobDelta() > 0 then transferProgress = true end
  if transferAction and not transferSent and player:getInventory():getItemById(packet.ids[4]) then
   assert(transferProgress, 'Native withdrawal had no observed action progress'); transferSent = true
   emit('TRANSFER', {id = packet.ids[4], source = packet.boxes[2].id, destination = 'client1', progress = true})
   if isClient() then sendClientCommand(F.module, 'TransferDone', {})
   else
    packet.transferAt = getTimestampMs()
    assert(F.native(boxes, packet, 'transferred', player), 'Native SP withdrawal endpoint differs')
    emit('TRANSFER_AUTHORITY', {id = packet.ids[4], source = packet.boxes[2].id, destination = 'client1', unique = true})
   end
  end
  if packet.transferAt then phase = 'transferred' end
 elseif phase == 'transferred-shot' then
  local result = assert(observed('transferred'), 'Withdrawn snapshot changed before native capture')
  capture('transferred', result); win:close()
  assert(not LootSorter._manifestWin, 'Warehouse close retained the native window')
  if isClient() then sendClientCommand(F.module, 'TransferredSeen', {})
  else
   emit('AUTHORITY', assert(F.native(boxes, packet, 'transferred', player))); F.cleanup(state)
   emit('CLEANUP', {ownedObjects = 2}); finished = true
  end
  phase = 'finish'
 elseif phase == 'finish' and finished then
  standard('case', {id = 'snapshot', status = 'passed', authoritativeCounts = true, peerConvergence = selection.kind == 'mp'})
  standard('complete', {passed = 1, failed = 0, skipped = 0})
  emit('COMPLETE', {case = 'snapshot', role = role}); done = true
 end
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState() or getTimestampMs() < nextAt then return end
 local ok, problem = pcall(function()
  assert(getTimestampMs() - since < 180000, 'Timeout phase=' .. phase)
  if initialize() then tick() end
 end)
 if not ok then done = true; print('[WAREHOUSE_MANIFEST] FAIL ' .. tostring(role) .. ' ' .. tostring(problem)) end
end)
