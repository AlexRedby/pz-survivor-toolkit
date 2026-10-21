local selection = require 'QueueTestSelection'
if selection.kind ~= 'mp' then return end
local F = require 'WarehouseManifestFixture'
local Authority = require 'PZSurvivorToolkit/ManifestAuthority'
local JSON = require 'QueueHealthEvents'
local players, initial, changed, transferred, sent = {}, {}, {}, {}, {}
local state, packet, mutated, transferGo, transferRequestedAt, transferDone, final, done, since
local function emit(event, value) print('[WAREHOUSE_MANIFEST] ' .. event .. ' ' .. JSON.encode(value)) end
Events.OnClientCommand.Add(function(module, command, player, args)
 if module ~= F.module then return end
 local ok, problem = pcall(function()
  local role = player:getUsername(); assert(role == 'client1' or role == 'client2', 'Unexpected warehouse fixture actor')
  if command == 'Prepare' then
   assert(not players[role], 'Duplicate warehouse actor preparation'); players[role] = player; since = since or getTimestampMs()
   if role == 'client1' then
    assert(not state, 'Duplicate warehouse fixture preparation'); state, packet = F.prepare(player); emit('PREPARED', packet)
   end
  elseif command == 'InitialSeen' then
   assert(players[role] == player and state and not initial[role] and not mutated, 'Invalid initial observer receipt')
   initial[role] = true
  elseif command == 'ChangedSeen' then
   assert(players[role] == player and mutated and not changed[role], 'Invalid changed observer receipt'); changed[role] = true
  elseif command == 'TransferDone' then
   assert(role == 'client1' and transferGo and not transferRequestedAt, 'Invalid transfer completion')
   transferRequestedAt = getTimestampMs()
  elseif command == 'TransferredSeen' then
   assert(players[role] == player and transferDone and not transferred[role], 'Invalid withdrawal observer receipt'); transferred[role] = true
  else error('Unknown warehouse fixture command ' .. tostring(command)) end
 end)
 if not ok then done = true; print('[WAREHOUSE_MANIFEST] FAIL server ' .. tostring(problem)) end
end)
Events.OnTick.Add(function()
 if done or not state then return end
 local ok, problem = pcall(function()
  assert(getTimestampMs() - since < 180000, 'Warehouse authority timeout')
  for role, player in pairs(players) do
   if not sent[role] then sent[role] = true; sendServerCommand(player, F.module, 'Prepared', {target = packet, role = role}) end
  end
  if transferRequestedAt and not transferDone then
   if F.native(state.boxes, packet, 'transferred', players.client1) then
    packet.transferAt = getTimestampMs(); transferDone = true
    emit('TRANSFER_AUTHORITY', {id = packet.ids[4], source = packet.boxes[2].id, destination = 'client1', unique = true})
    for _, peer in pairs(players) do sendServerCommand(peer, F.module, 'Transferred', {transferAt = packet.transferAt}) end
   else assert(getTimestampMs() - transferRequestedAt < 30000, 'Native Host withdrawal endpoint/identity never converged') end
  end
  if initial.client1 and initial.client2 and not mutated then
   assert(players.client1:getOnlineID() ~= players.client2:getOnlineID(), 'Host clients share native identity')
   if not F.snapshot(Authority.getStore(), packet, 'initial') then return end
   emit('AUTHORITY', assert(F.native(state.boxes, packet, 'initial')))
   local mutation = F.mutate(state); emit('MUTATED', mutation); mutated = true
   for _, player in pairs(players) do sendServerCommand(player, F.module, 'Changed', mutation) end
  elseif mutated and changed.client1 and changed.client2 and not transferGo then
   if not F.snapshot(Authority.getStore(), packet, 'changed') then return end
   emit('AUTHORITY', assert(F.native(state.boxes, packet, 'changed'))); transferGo = true
   sendServerCommand(players.client1, F.module, 'TransferGo', {})
  elseif transferDone and transferred.client1 and transferred.client2 and not final then
   if not F.snapshot(Authority.getStore(), packet, 'transferred') then return end
   emit('AUTHORITY', assert(F.native(state.boxes, packet, 'transferred', players.client1))); final = true
   F.cleanup(state); emit('CLEANUP', {ownedObjects = 2})
   for _, player in pairs(players) do sendServerCommand(player, F.module, 'Done', {}) end
   done = true
  end
 end)
 if not ok then done = true; print('[WAREHOUSE_MANIFEST] FAIL server tick ' .. tostring(problem)) end
end)
