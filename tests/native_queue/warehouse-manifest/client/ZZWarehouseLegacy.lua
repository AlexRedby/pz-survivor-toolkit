local selection = require 'QueueTestSelection'
local case = selection.cases[1]
if case ~= 'legacy-seed' and case ~= 'legacy-reload' then return end
local JSON = require 'QueueHealthEvents'
local META, FAR, LABEL = 'PZSTWarehouseLegacyFixture', '7000,7000,0', 'Legacy remote nails'
local started, done, since, phase, meta, cold = false, false, 0, 'prepare', nil, false
local function emit(event, value) print('[WAREHOUSE_LEGACY] ' .. event .. ' ' .. JSON.encode(value)) end
local function standard(event, value)
 value = value or {}; value.event = event; value.suite = 'warehouse-manifest'; value.actor = 'client1'
 value.kind = 'sp'; value.mode = 'toolkit'; print('[QUEUE_CHECK] ' .. JSON.encode(value))
end
local function coord(square) return square:getX() .. ',' .. square:getY() .. ',' .. square:getZ() end
local function nativeCrate()
 local sq = getCell():getGridSquare(meta.x, meta.y, meta.z)
 if not sq then return end
 local found
 local objects = sq:getObjects()
 for i = 0, objects:size() - 1 do
  local obj = objects:get(i)
  if obj:hasModData() and obj:getModData().PZSTWarehouseLegacyFixture then assert(not found, 'Duplicate saved fixture crate'); found = obj end
 end
 if not found then return end
 local items, wanted = found:getContainer():getItems(), {}
 for _, id in ipairs(meta.ids) do wanted[id] = true end
 assert(items:size() == #meta.ids, 'Saved crate item count differs')
 for i = 0, items:size() - 1 do
  local item = items:get(i)
  assert(wanted[item:getID()] and item:getFullType() == 'Base.Nails', 'Original native item identity lost or duplicated')
  wanted[item:getID()] = nil
 end
 for _ in pairs(wanted) do error('Saved item identity missing') end
 return found
end
Events.OnInitGlobalModData.Add(function()
 if case ~= 'legacy-reload' then return end
 local ok, problem = pcall(function()
  meta = ModData.getOrCreate(META)
  assert(meta.proof == 'v1-world' and #meta.ids == 4, 'Original saved fixture metadata missing')
  local store = ModData.getOrCreate('LootSorter_Manifest')
  assert(store.schema ~= 2 and store.boxes and store.boxes[FAR][LABEL].n == 5, 'Save was not a legacy v1 Manifest')
  assert(store.boxes[meta.key][meta.label].n == 4, 'Saved loaded legacy contents differ')
  cold = true; emit('COLD', {schema = store.schema or 0, ids = meta.ids, far = 5, loaded = 4})
 end)
 if not ok then done = true; print('[WAREHOUSE_LEGACY] FAIL cold ' .. tostring(problem)) end
end)
Events.OnGameStart.Add(function() started, since = true, getTimestampMs() end)
local function seed(player)
 assert(LootSorter.manifestReconcile and not PZSurvivorToolkit.ManifestAuthority, 'Seed requires actual pre-Host Toolkit sources')
 assert(not getCell():getGridSquare(7000, 7000, 0), 'Remote legacy location unexpectedly loaded')
 local origin, square = player:getSquare()
 for dx = -2, 2 do for dy = -2, 2 do
  local sq = getCell():getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
  if not square and (dx ~= 0 or dy ~= 0) and sq and sq:canStand() and sq:isFree(true) and sq:getObjects():size() <= 1 then square = sq end
 end end
 assert(square, 'No free native fixture tile')
 local obj = IsoThumpable.new(getCell(), square, 'carpentry_01_16', false, {})
 obj:setIsContainer(true); obj:setCanPassThrough(true)
 local container = assert(obj:getContainer()); container:setType('crate'); container:setCapacity(100); container:setExplored(true)
 obj:getModData().PZSTWarehouseLegacyFixture = true
 square:AddSpecialObject(obj)
 meta = ModData.getOrCreate(META)
 meta.x, meta.y, meta.z, meta.key, meta.proof, meta.ids = square:getX(), square:getY(), square:getZ(), coord(square), 'v1-world', {}
 for i = 1, 4 do local item = assert(container:AddItem('Base.Nails')); meta.ids[i] = item:getID() end
 meta.label = container:getItems():get(0):getDisplayName()
 LootSorter.setBoxItems(obj, 0, {[meta.label] = true})
 LootSorter.manifestReconcile()
 local store = ModData.getOrCreate('LootSorter_Manifest')
 assert(store.schema ~= 2 and store.boxes[meta.key][meta.label].n == 4, 'Original Manifest did not snapshot native crate')
 store.boxes[FAR] = {[LABEL] = {ft = 'Base.Nails', cat = 'Material', n = 5}}
 assert(nativeCrate())
 save(true) -- The same native world-save entry point used by vanilla single-player sleep.
 emit('SAVED', {schema = store.schema or 0, ids = meta.ids, far = 5, loaded = 4})
 phase, since = 'saved', getTimestampMs()
end
local function reload()
 assert(cold, 'No original disk-store receipt before authority migration')
 local obj = nativeCrate(); if not obj then return end
 if not LootSorter._manifestWin then LootSorter.toggleManifest(0) end
 local payload = PZSurvivorToolkit.ManifestClient.getState(0).payload
 if not payload or payload.schema ~= 2 then return end
 local remote, loaded = 0, 0
 for _, record in pairs(payload.containers) do
  if record.key == FAR then
   assert(record.legacy and not record.loaded and record.sampledAt == 0, 'Unvisited legacy age/freshness was invented')
   for _, entry in pairs(record.entries) do if entry.ft == 'Base.Nails' then remote = remote + entry.n end end
  elseif record.key == meta.key then
   if record.legacy then return end
   assert(record.loaded and record.sampledAt > 0, 'Revisited native crate was not refreshed')
   for _, entry in pairs(record.entries) do if entry.ft == 'Base.Nails' then loaded = loaded + entry.n end end
  end
 end
 if remote ~= 5 or loaded ~= 4 then return end
 local shown = 0
 for _, row in ipairs(LootSorter._manifestWin.listBox.items) do if row.item.ft == 'Base.Nails' then shown = shown + row.item.n end end
 if shown ~= 9 then return end
 emit('RESTORED', {schema = 2, ids = meta.ids, far = remote, loaded = loaded, ui = shown, unknownAge = true, native = true})
 getCore():TakeFullScreenshot('warehouse-manifest-legacy-reload.png')
 LootSorter._manifestWin:close(); phase = 'complete'
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState() then return end
 local ok, problem = pcall(function()
  assert(not isClient() and not isServer(), 'Legacy save migration requires native SP')
  assert(getTimestampMs() - since < 90000, 'Legacy fixture deadline ' .. phase)
  local player = getPlayer(); if not player or not player:getSquare() then return end
  if phase == 'prepare' then
   player:setGodMod(true); player:setGhostMode(true)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
   standard('setup', {cases = {case}, expected = 1, nativeDurations = true, queueEnabled = true})
   emit('SETUP', {case = case, role = 'client1'})
   phase = case == 'legacy-seed' and 'seed' or 'reload'
  elseif phase == 'seed' then seed(player)
  elseif phase == 'reload' then reload()
  elseif phase == 'saved' and getTimestampMs() - since > 1500 then phase = 'complete'
  elseif phase == 'complete' then
   standard('case', {id = case, status = 'passed', persistedNativeIds = true})
   standard('complete', {passed = 1, failed = 0, skipped = 0})
   emit('COMPLETE', {case = case, role = 'client1'}); done = true
  end
 end)
 if not ok then done = true; print('[WAREHOUSE_LEGACY] FAIL ' .. tostring(problem)) end
end)
