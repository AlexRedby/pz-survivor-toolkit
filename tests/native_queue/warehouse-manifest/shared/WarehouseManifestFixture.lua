-- Disposable native world objects; only the SP/Host authority creates or mutates them.
local Model = require 'PZSurvivorToolkit/ManifestModel'
local Appearance = require 'PZSurvivorToolkit/ContainerAppearance'
local F = {module = 'WarehouseManifestTest', ft = 'Base.Nails', custom = 'Warehouse custom nails'}
F.appearance = {name = 'Warehouse fixture A', icon = {kind = 'item', value = 'Base.Nails'},
 color = {r = .25, g = .5, b = .75, a = 1}}
function F.identity(packet, custom) return Model.identity(F.ft, custom and F.custom or nil, packet.category) end
function F.coord(square) return square:getX() .. ',' .. square:getY() .. ',' .. square:getZ() end
local function descriptor(object)
 local square = object:getSquare()
 local point = {x = square:getX(), y = square:getY(), z = square:getZ(), object = object:getObjectIndex(), ci = 0}
 point.key = F.coord(square); point.id = point.key .. '/' .. point.object .. '/0'
 return point
end
function F.prepare(player)
 assert(LootSorter.isAuthority(), 'Only authority may prepare warehouse objects')
 local origin, squares = assert(player:getSquare()), {}
 for dx = -2, 2 do for dy = -2, 2 do
  local square = getCell():getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
  if #squares < 2 and (dx ~= 0 or dy ~= 0) and square and square:canStand()
   and square:isFree(true) and square:getObjects():size() <= 1 then squares[#squares + 1] = square end
 end end
 assert(#squares == 2, 'Two free loaded warehouse fixture tiles are required')
 local state = {boxes = {}, ids = {}}
 local packet = {boxes = {}, ids = state.ids, category = assert(Model.item(assert(instanceItem(F.ft))).cat)}
 for i, square in ipairs(squares) do
  local object = IsoThumpable.new(getCell(), square, 'carpentry_01_16', false, {})
  object:setIsContainer(true); object:setBlockAllTheSquare(true)
  local container = assert(object:getContainer()); container:setType('crate'); container:setCapacity(100); container:setExplored(true)
  object:getModData().PZSTWarehouseManifestFixture = true
  object:getModData().LSBoxItems = {['0'] = {['Warehouse fixture designation'] = true}}
  square:AddSpecialObject(object)
  Appearance.apply(object, 0, player, i == 1 and F.appearance or {name = 'Warehouse fixture B'})
  state.boxes[i], packet.boxes[i] = object, descriptor(object)
  assert(LootSorter.serverFns.addCoord(player, {key = packet.boxes[i].key}) == 'ok', 'Authority coordinate registration refused')
  if isServer() then object:transmitCompleteItemToClients(); object:transmitModData() end
 end
 for i = 1, 3 do
  local container = state.boxes[i == 3 and 2 or 1]:getContainer()
  local item = assert(container:AddItem(F.ft)); state.ids[i] = item:getID()
  if isServer() then sendAddItemToContainer(container, item) end
 end
 local custom = assert(state.boxes[1]:getContainer():AddItem(F.ft))
 custom:setName(F.custom); custom:setCustomName(true); state.ids[4] = custom:getID()
 if isServer() then sendAddItemToContainer(state.boxes[1]:getContainer(), custom) end
 state.packet = packet
 return state, packet
end
function F.resolve(packet)
 local boxes = {}
 for i, point in ipairs(packet.boxes) do
  local square = getCell():getGridSquare(point.x, point.y, point.z)
  if not square or point.object >= square:getObjects():size() then return end
  local object = square:getObjects():get(point.object)
  if not object or not object:hasModData() or not object:getModData().PZSTWarehouseManifestFixture then return end
  boxes[i] = object
 end
 return boxes
end
function F.counts(phase)
 if phase == 'initial' then return {2, 1, 1, 0} end
 return phase == 'changed' and {1, 3, 0, 1} or {1, 3, 0, 0}
end
function F.native(boxes, packet, phase, player)
 local expected = phase == 'initial' and {{packet.ids[1], packet.ids[2], packet.ids[4]}, {packet.ids[3]}}
  or {{packet.ids[2]}, {packet.ids[3], packet.ids[4], packet.addedIds[1], packet.addedIds[2]}}
 if phase == 'transferred' then expected[2] = {packet.ids[3], packet.addedIds[1], packet.addedIds[2]} end
 for i, object in ipairs(boxes) do
  local items, wanted = object:getContainer():getItems(), {}
  for _, id in ipairs(expected[i]) do wanted[id] = true end
  if items:size() ~= #expected[i] then return end
  for j = 0, items:size() - 1 do
   local item = items:get(j)
   if not wanted[item:getID()] or item:getFullType() ~= F.ft then return end
   assert((item:getID() == packet.ids[4]) == item:isCustomName(), 'Native custom-name flag changed')
   if item:isCustomName() then assert(item:getName() == F.custom, 'Native custom name changed') end
   wanted[item:getID()] = nil
  end
  for _ in pairs(wanted) do return end
 end
 if phase == 'transferred' and player then
  local custom = player:getInventory():getItemById(packet.ids[4])
  if not custom or custom:getFullType() ~= F.ft or custom:getName() ~= F.custom then return end
 end
 return {phase = phase, counts = F.counts(phase), ids = packet.ids, addedIds = packet.addedIds or {}}
end
function F.mutate(state)
 assert(LootSorter.isAuthority() and F.native(state.boxes, state.packet, 'initial'), 'Mutation needs exact initial authority state')
 local source, dest = state.boxes[1]:getContainer(), state.boxes[2]:getContainer()
 local removed, custom = assert(source:getItemById(state.ids[1])), assert(source:getItemById(state.ids[4]))
 source:Remove(removed); source:Remove(custom)
 if isServer() then sendRemoveItemFromContainer(source, removed); sendRemoveItemFromContainer(source, custom) end
 dest:AddItem(custom)
 if isServer() then sendAddItemToContainer(dest, custom) end
 state.packet.addedIds = {}
 for i = 1, 2 do
  local item = assert(dest:AddItem(F.ft)); state.packet.addedIds[i] = item:getID()
  if isServer() then sendAddItemToContainer(dest, item) end
 end
 state.packet.changedAt = getTimestampMs()
 assert(F.native(state.boxes, state.packet, 'changed'), 'Authority mutation did not conserve expected identities')
 return {removedId = removed:getID(), customId = custom:getID(), addedIds = state.packet.addedIds,
  changedAt = state.packet.changedAt}
end
function F.snapshot(payload, packet, phase)
 if phase ~= 'initial' and not packet.changedAt then return end
 if phase == 'transferred' and not packet.transferAt then return end
 if not payload or payload.schema ~= Model.SCHEMA or type(payload.revision) ~= 'number' then return end
 local counts, samples = F.counts(phase), {}
 for i, point in ipairs(packet.boxes) do
  local record = payload.containers[point.id]
  if not record or not record.loaded or not record.sampledAt or record.sampledAt <= 0 then return end
  if phase ~= 'initial' and record.sampledAt < (phase == 'transferred' and packet.transferAt or packet.changedAt) then return end
  for _, key in ipairs({'id', 'key', 'x', 'y', 'z', 'object', 'ci'}) do
   assert(record[key] == point[key], 'Manifest location identity differs: ' .. key)
  end
  assert(record.kind == 'crate' and record.name == (i == 1 and F.appearance.name or 'Warehouse fixture B'), 'Manifest appearance/name differs')
  if i == 1 then
   assert(record.icon and record.icon.kind == 'item' and record.icon.value == F.ft, 'Manifest icon differs')
   for key, value in pairs(F.appearance.color) do assert(record.color and record.color[key] == value, 'Manifest color differs') end
  end
  local default, custom = record.entries[F.identity(packet)], record.entries[F.identity(packet, true)]
  if (default and default.n or 0) ~= counts[i] or (custom and custom.n or 0) ~= counts[i + 2] then return end
  for key, entry in pairs(record.entries) do
   assert(entry.ft == F.ft and entry.key == key and entry.cat == packet.category, 'Manifest entry identity/category differs')
   assert(key == F.identity(packet) and entry.name == nil
    or key == F.identity(packet, true) and entry.name == F.custom, 'Manifest leaked a localized default or changed custom label')
  end
  samples[i] = record.sampledAt
 end
 return {phase = phase, revision = payload.revision, samples = samples, counts = counts}
end
function F.cleanup(state)
 for _, object in ipairs(state.boxes) do
  assert(object:getModData().PZSTWarehouseManifestFixture, 'Refusing foreign warehouse cleanup')
  object:getSquare():transmitRemoveItemFromSquare(object)
 end
end
return F
