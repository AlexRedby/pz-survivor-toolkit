-- Native world-backed evidence only. Keep primitives across chunk unload/reload.
local selection = require 'QueueTestSelection'
if selection.cases[1] ~= 'persist-seed' and selection.cases[1] ~= 'persist-reload' then return end
local F = require 'WarehouseManifestFixture'
local Model = require 'PZSurvivorToolkit/ManifestModel'
local P = {module = 'WarehouseManifestPersistenceTest', STORE = 'PZSTWarehouseManifestPersistenceFixture'}
function P.point(player)
 return {x = math.floor(player:getX()), y = math.floor(player:getY()), z = math.floor(player:getZ())}
end
function P.absent(packet)
 local cell = getCell()
 for _, point in ipairs(packet.boxes) do
  if cell:getGridSquare(point.x, point.y, point.z) ~= nil then return false end
 end
 return true
end
function P.receipt(payload, packet, stage, loaded, expectedSamples)
 if not payload or payload.schema ~= Model.SCHEMA or type(payload.revision) ~= 'number' then return end
 local samples, ages, now = {}, {}, getTimestampMs()
 for i, point in ipairs(packet.boxes) do
  local record = payload.containers[point.id]
  if not record or record.loaded ~= loaded or not record.sampledAt or record.sampledAt <= 0 then return end
  for _, key in ipairs({'id', 'key', 'x', 'y', 'z', 'object', 'ci'}) do
   assert(record[key] == point[key], 'Persisted Manifest location identity differs: ' .. key)
  end
  assert(record.kind == 'crate' and record.name == (i == 1 and F.appearance.name or 'Warehouse fixture B'), 'Persisted appearance differs')
  if i == 1 then
   assert(record.icon and record.icon.kind == 'item' and record.icon.value == F.ft, 'Persisted icon differs')
   for key, value in pairs(F.appearance.color) do assert(record.color and record.color[key] == value, 'Persisted color differs') end
  end
  for key, entry in pairs(record.entries) do
   assert(entry.ft == F.ft and entry.key == key and entry.cat == packet.category, 'Persisted item key/category differs')
   assert(key == F.identity(packet) and entry.name == nil
    or key == F.identity(packet, true) and entry.name == F.custom, 'Persisted custom/default names differ')
   F.assertIdentity(entry, packet.identities[key == F.identity(packet) and 'default' or 'custom'], 'Persisted Manifest')
  end
  local default, custom = record.entries[F.identity(packet)], record.entries[F.identity(packet, true)]
  local counts = F.counts('initial')
  if (default and default.n or 0) ~= counts[i] or (custom and custom.n or 0) ~= counts[i + 2] then return end
  if expectedSamples and record.sampledAt ~= expectedSamples[i] then return end
  samples[i], ages[i] = record.sampledAt, now - record.sampledAt
  if ages[i] < 0 or not loaded and ages[i] < 500 then return end
 end
 return {stage = stage, revision = payload.revision, loaded = loaded, samples = samples, ages = ages,
  observedAt = now, counts = F.counts('initial')}
end
function P.prepare(player)
 assert(LootSorter.isAuthority(), 'Only native authority may seed persistence')
 local home = P.point(player)
 local state, packet = F.prepare(player)
 local meta = ModData.getOrCreate(P.STORE)
 for key in pairs(meta) do meta[key] = nil end
 meta.schema, meta.packet, meta.home, meta.tokens = 2, packet, home, {}
 for i, object in ipairs(state.boxes) do
  local token = 'WarehousePersistence:' .. tostring(packet.ids[1]) .. ':' .. tostring(i)
  meta.tokens[i] = token; object:getModData().PZSTWarehousePersistenceToken = token
  if isServer() then object:transmitModData() end
 end
 meta.away, meta.stage = {x = home.x + 600, y = home.y + 200, z = 0}, 'seed'
 return meta, state.boxes
end
function P.reacquire(meta)
 local boxes = {}
 for i, point in ipairs(meta.packet.boxes) do
  local square = getCell():getGridSquare(point.x, point.y, point.z)
  if not square then return end
  local found
  for j = 0, square:getObjects():size() - 1 do
   local object = square:getObjects():get(j)
   if object and object:hasModData() and object:getModData().PZSTWarehousePersistenceToken == meta.tokens[i] then
    assert(not found, 'Duplicate stable warehouse fixture token'); found = object
   end
  end
  if not found then return end
  local index = found:getObjectIndex()
  local id = point.key .. '/' .. index .. '/0'
  if id ~= point.id then
   meta.staleIds = meta.staleIds or {}; meta.staleIds[point.id] = true
   point.object, point.id = index, id
  end
  boxes[i] = found
 end
 return boxes
end
function P.current(payload, meta, stage, loaded, expectedSamples)
 if not payload or type(payload.containers) ~= 'table' then return end
 for id in pairs(meta.staleIds or {}) do
  local active = false
  for _, point in ipairs(meta.packet.boxes) do if point.id == id then active = true end end
  if not active and payload.containers[id] then return end
 end
 return P.receipt(payload, meta.packet, stage, loaded, expectedSamples)
end
function P.native(meta, player)
 local boxes = P.reacquire(meta)
 if not boxes or not F.native(boxes, meta.packet, 'initial') then return end
 -- The fixture seed has no withdrawals. Every exact ID must occur only in its crate.
 for _, id in ipairs(meta.packet.ids) do
  if player and player:getInventory():getItemById(id) then return end
 end
 return true
end
function P.near(player, point)
 return player:getSquare() and player:getZ() == point.z
  and math.abs(player:getX() - point.x) < 5 and math.abs(player:getY() - point.y) < 5
end
return P
