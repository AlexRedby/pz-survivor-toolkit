-- Native Java lookup timings only: this is not a receipt-latency or FPS test.
-- Fixture owns all supplied detached containers/items and their eventual cleanup.
local Lookup = {}
Lookup.__index = Lookup
local CALLS, WARMUPS, SAMPLES = 512, 2, 9

local function count(container, seen)
    assert(instanceof(container, 'ItemContainer'), 'lookup fixture needs a native ItemContainer')
    local items, total = container:getItems(), 0
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        assert(instanceof(item, 'InventoryItem') and item:getContainer() == container,
            'lookup fixture contains a detached/non-native item')
        local id = item:getID()
        assert(not seen[id], 'lookup fixture has duplicate IDs or repeated objects')
        seen[id] = item
        total = total + 1
        if instanceof(item, 'InventoryContainer') then
            total = total + count(item:getItemContainer(), seen)
        end
    end
    return total
end

local function validate(self)
    local root, nested = self.container, self.nestedContainer
    assert(root:getItems():size() == 2 and nested:getItems():size() == self.expectedCount,
        'lookup fixture cardinality changed')
    assert(root:getItems():get(0) == self.firstItem and self.firstItem:getContainer() == root,
        'first-present must be the first root object')
    local bag = root:getItems():get(1)
    assert(instanceof(bag, 'InventoryContainer') and bag:getItemContainer() == nested,
        'lookup fixture needs one nested bag after the first root object')
    assert(nested:getItems():get(self.expectedCount - 1) == self.lastItem,
        'last-nested must be the final nested object')
    assert(self.emptyContainer:getItems():isEmpty(), 'lookup empty control is not empty')
    local seen = {}
    local total = count(root, seen)
    assert(total == self.expectedCount + 2 and not seen[self.missingId],
        'lookup fixture recursive count or missing ID changed')
    assert(root:getItemById(self.firstItem:getID()) == self.firstItem
        and root:getItemById(self.lastItem:getID()) == self.lastItem
        and root:getItemById(self.missingId) == nil, 'native recursive lookup identity differs')
    -- Compare every ID/object pair after the measurements; detect mutation, not just count drift.
    if self.objects then
        for id, item in pairs(self.objects) do assert(seen[id] == item, 'lookup fixture object changed') end
    else self.objects = seen end
    return total
end

function Lookup.new(spec)
    assert(type(spec) == 'table' and type(spec.log) == 'function', 'lookup log callback required')
    local self = setmetatable({container=spec.container, nestedContainer=spec.nestedContainer,
        firstItem=spec.firstItem, lastItem=spec.lastItem, emptyContainer=spec.emptyContainer,
        expectedCount=spec.expectedCount or 4800, missingId=-2147483648,
        report={}, round=1, caseIndex=1, done=false}, Lookup)
    assert(self.expectedCount == 4800, 'receipt profile requires 4800 actual nested objects')
    assert(instanceof(self.emptyContainer, 'ItemContainer'), 'native empty control required')
    self.log = spec.log
    self.recursiveObjects = validate(self)
    self.cases = {
        {name='missing', container=self.container, id=self.missingId},
        {name='first-present', container=self.container, id=self.firstItem:getID(), expected=self.firstItem},
        {name='last-nested', container=self.container, id=self.lastItem:getID(), expected=self.lastItem},
        {name='empty-control', container=self.emptyContainer, id=self.missingId},
    }
    for _, case in ipairs(self.cases) do case.elapsed = {}; case.matches = 0 end
    return self
end

local function summarize(self, case)
    local sorted, total, zeros = {}, 0, 0
    for i, elapsed in ipairs(case.elapsed) do
        sorted[i], total = elapsed, total + elapsed
        if elapsed == 0 then zeros = zeros + 1 end
    end
    table.sort(sorted)
    local row = {case=case.name, native=true, clock='getTimestampMs', resolutionMs=1,
        nestedObjects=self.expectedCount, rootObjects=2, recursiveObjects=self.recursiveObjects,
        firstId=self.firstItem:getID(), lastId=self.lastItem:getID(), missingId=self.missingId,
        requestedId=case.id, emptyObjects=0, batchCalls=CALLS, warmupBatches=WARMUPS,
        measuredBatches=SAMPLES, measuredCalls=CALLS*SAMPLES, matchedCalls=case.matches,
        elapsedMs=case.elapsed, totalElapsedMs=total, minBatchMs=sorted[1],
        medianBatchMs=sorted[math.ceil(SAMPLES/2)], p95BatchMs=sorted[math.ceil(SAMPLES*.95)],
        maxBatchMs=sorted[#sorted], zeroMsBatches=zeros, meanMsPerCall=total/(CALLS*SAMPLES),
        objectsPreserved=true, fpsMeasurement=false, receiptLatencyMeasurement=false}
    self.report[#self.report + 1] = row
    self.log('LOOKUP', row)
end

function Lookup:tick()
    if self.done then return true end
    local case = self.cases[self.caseIndex]
    local matches = 0
    local started = getTimestampMs()
    for _ = 1, CALLS do
        -- Invoke the real Java method each time; do not model traversal or cache its result.
        if case.container:getItemById(case.id) == case.expected then matches = matches + 1 end
    end
    local elapsed = getTimestampMs() - started
    assert(elapsed >= 0 and matches == CALLS, 'lookup clock/result changed during batch')
    if self.round > WARMUPS then
        case.elapsed[#case.elapsed + 1] = elapsed
        case.matches = case.matches + matches
    end
    self.caseIndex = self.caseIndex + 1
    if self.caseIndex > #self.cases then
        self.caseIndex, self.round = 1, self.round + 1
    end
    if self.round > WARMUPS + SAMPLES then
        validate(self)
        for _, result in ipairs(self.cases) do summarize(self, result) end
        self.done = true
    end
    return self.done
end

return Lookup
