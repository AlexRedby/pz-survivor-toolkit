local selection = require 'QueueTestSelection'
local case = selection.cases[1]
if case ~= 'persist-seed' and case ~= 'persist-reload' then return end
if not isServer() then return end
local P = require 'WarehouseManifestPersistence'
local F = require 'WarehouseManifestFixture'
local Authority = require 'PZSurvivorToolkit/ManifestAuthority'
local JSON = require 'QueueHealthEvents'
local players, sent, arrived, seen = {}, {}, {}, {}
local meta, stage, authority, startedAt, stageAt, done, cold
local oldPeer, oldOnlineID, disconnected
local function emit(event, value) print('[WAREHOUSE_PERSIST] ' .. event .. ' ' .. JSON.encode(value)) end
local function fail(problem) done = true; print('[WAREHOUSE_PERSIST] FAIL server ' .. tostring(problem)) end
local function both(values) return values.client1 and values.client2 end
local function sendAll(command, value)
 for _, player in pairs(players) do sendServerCommand(player, P.module, command, value) end
end
local function travel(nextStage, point)
 stage, stageAt, authority, arrived, seen = nextStage, getTimestampMs(), nil, {}, {}
 -- Do not retain native world-object/square/container handles across this boundary.
 sendAll('Travel', {stage = stage, point = point})
end
local function restored()
 if case ~= 'persist-reload' or cold or done then return end
 local ok, problem = pcall(function()
  meta = assert(ModData.get(P.STORE), 'Native world has no persistence fixture descriptor')
  assert(meta.schema == 1 and meta.stage == 'readyForReload' and meta.savedSamples, 'World is not a completed warehouse seed')
  cold = assert(P.current(Authority.getStore(), meta, 'cold', false, meta.savedSamples), 'Persisted last-known samples/counts were not restored before sampling')
  emit('COLD', cold)
 end)
 if not ok then fail(problem) end
end
Events.OnInitGlobalModData.Add(restored)
Events.OnServerStarted.Add(restored)
Events.OnClientCommand.Add(function(module, command, player, args)
 if module ~= P.module or done then return end
 local ok, problem = pcall(function()
  local role = player:getUsername(); assert(role == 'client1' or role == 'client2', 'Unexpected persistence actor')
  if command == 'Prepare' and args.reconnect then
   assert(role == 'client2' and stage == 'rejoining' and disconnected and player ~= oldPeer, 'Rejoin lacks native disconnect/new-player proof')
   players.client2, sent.client2 = player, nil
   stage, stageAt, authority, arrived, seen = 'rejoined', getTimestampMs(), nil, {client1 = true}, {}
   emit('REJOIN', {oldOnlineID = oldOnlineID, newOnlineID = player:getOnlineID(), newPlayer = true})
  elseif command == 'Prepare' then
   assert(not players[role], 'Duplicate persistence actor'); players[role] = player
   startedAt = startedAt or getTimestampMs()
   if role == 'client1' then
    if case == 'persist-seed' then
     assert(not meta, 'Duplicate persistence seed'); meta = P.prepare(player)
     emit('PREPARED', {packet = meta.packet, home = meta.home, away = meta.away})
     stage = 'initial'
    else
     assert(cold and meta, 'Reload did not capture native cold store'); stage = 'restored'
     emit('PREPARED', {packet = meta.packet, home = meta.home, away = meta.away})
    end
    stageAt = getTimestampMs()
   end
  elseif command == 'Arrived' then
   assert(players[role] == player and args.stage == stage and not arrived[role], 'Unexpected persistence arrival')
   arrived[role] = true
  elseif command == 'Seen' then
   assert(players[role] == player and authority and args.stage == stage and not seen[role], 'Unexpected persistence state receipt')
   seen[role] = true
  else error('Unknown persistence command ' .. tostring(command)) end
 end)
 if not ok then fail(problem) end
end)
Events.OnTick.Add(function()
 if done or not meta or not stage then return end
 local ok, problem = pcall(function()
  assert(getTimestampMs() - startedAt < 600000 and getTimestampMs() - stageAt < 120000, 'Persistence authority timeout stage=' .. stage)
  for role, player in pairs(players) do
   if not sent[role] and not (stage == 'rejoining' and role == 'client2') then
    sent[role] = true
    sendServerCommand(player, P.module, 'Prepared', {role = role, packet = meta.packet, home = meta.home,
     away = meta.away, tokens = meta.tokens, staleIds = meta.staleIds, stage = stage, savedSamples = meta.savedSamples})
   end
  end
  if stage == 'rejoining' then
   local present, online = false, getOnlinePlayers()
   for i = 0, online:size() - 1 do if online:get(i) == oldPeer then present = true end end
   if not present and not disconnected then
    disconnected = true; emit('DISCONNECTED', {oldOnlineID = oldOnlineID, oldPlayerAbsent = true})
   end
   return
  end
  if not both(arrived) then return end
  assert(players.client1:getOnlineID() ~= players.client2:getOnlineID(), 'Persistence actors share native identity')
  local loaded = stage == 'initial' or stage == 'revisited' or stage == 'rejoined'
  local point = loaded and meta.home or meta.away
  if not P.near(players.client1, point) or not P.near(players.client2, point) then return end
  if not authority then
   if loaded then
    if not P.native(meta, players.client1) or not P.native(meta, players.client2) then return end
   elseif not P.absent(meta.packet) then return end
   local expected = stage == 'restored' and meta.savedSamples or nil
   local result = P.current(Authority.getStore(), meta, stage, loaded, expected)
   if not result then return end
   if stage == 'revisited' then
    for i, sample in ipairs(result.samples) do if sample <= meta.unloadedSamples[i] then return end end
   end
   authority = result
   result.worldAbsent, result.nativeIds = not loaded, loaded
   if stage == 'unloaded' then meta.unloadedSamples = result.samples end
   if stage == 'restored' then meta.unloadedSamples = meta.savedSamples end
   if stage == 'saved' then meta.savedSamples = result.samples; meta.stage = 'readyForReload' end
   emit('AUTHORITY', result)
   sendAll('Phase', {stage = stage, loaded = loaded, samples = result.samples, packet = meta.packet, staleIds = meta.staleIds})
  end
  if not both(seen) then return end
  if stage == 'initial' then travel('unloaded', meta.away)
  elseif stage == 'unloaded' or stage == 'restored' then travel('revisited', meta.home)
  elseif stage == 'revisited' and case == 'persist-seed' then
   stage, stageAt, authority = 'rejoining', getTimestampMs(), nil
   oldPeer, oldOnlineID = players.client2, players.client2:getOnlineID()
   emit('RECONNECT', {oldOnlineID = oldOnlineID})
   sendServerCommand(players.client2, P.module, 'Reconnect', {})
  elseif stage == 'rejoined' then travel('saved', meta.away)
  else
   if case == 'persist-seed' then
    emit('PERSISTED', {schema = Authority.getStore().schema, samples = meta.savedSamples,
     counts = F.counts('initial'), ids = meta.packet.ids, boxes = meta.packet.boxes, loaded = false, completedAt = getTimestampMs()})
   else
    assert(P.native(meta, players.client1), 'Reload exact native IDs changed before cleanup')
    local boxes = assert(P.reacquire(meta)); F.cleanup({boxes = boxes})
    meta.stage = 'reloadVerified'; emit('CLEANUP', {ownedObjects = 2})
   end
   sendAll('Done', {}); done = true
  end
 end)
 if not ok then fail(problem) end
end)
