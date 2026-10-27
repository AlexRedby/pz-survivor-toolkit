-- Window-owned projection: receiving data, sorting and searching have separate lifetimes.
-- No world/container reads and no networking belong in this module.
local View = {}
View.__index = View

function View.new(describe, tags)
    return setmetatable({describe = describe, tags = tags, rows = {}, sorts = {}, tagOptions = {}}, View)
end

function View:setPayload(payload)
    local revision = self.tags.revision and self.tags.revision() or 0
    if self.payload == payload and self.tagRevision == revision then return false end
    self.payload, self.sorts, self.tagRevision = payload, {}, revision
    local totals, options = {}, {}
    for id, container in pairs(payload and payload.containers or {}) do
        for key, entry in pairs(container.entries or {}) do
            local row = totals[key]
            if not row then
                local name, category, tags = self.describe(entry)
                row = {key = key, ft = entry.ft, name = name, cat = category, tags = tags or {}, n = 0, locations = {}}
                row.search = string.lower(name)
                totals[key] = row
                for _, tag in ipairs(row.tags) do options[tag] = true end
            end
            row.n = row.n + entry.n
            row.locations[#row.locations + 1] = {id = id, container = container, n = entry.n}
        end
    end
    self.rows, self.tagOptions = {}, {}
    for _, row in pairs(totals) do self.rows[#self.rows + 1] = row end
    for tag in pairs(options) do self.tagOptions[#self.tagOptions + 1] = tag end
    table.sort(self.tagOptions, function(a, b)
        local left, right = self.tags.label(a), self.tags.label(b)
        return left == right and a < b or left < right
    end)
    return true
end

function View:select(query, tag, sortBy, asc)
    sortBy = sortBy or "count"
    local sortKey = sortBy .. (asc and ":asc" or ":desc")
    local ordered = self.sorts[sortKey]
    if not ordered then
        ordered = {}
        for i, row in ipairs(self.rows) do ordered[i] = row end
        table.sort(ordered, function(a, b)
            local left, right
            if sortBy == "count" then left, right = a.n, b.n
            elseif sortBy == "cat" then left, right = a.cat, b.cat
            else left, right = a.name, b.name end
            if left == right then
                if a.name == b.name then return a.key < b.key end
                return a.name < b.name
            end
            if asc then return left < right end
            return left > right
        end)
        self.sorts[sortKey] = ordered
    end
    local selected, count = {}, 0
    query = string.lower(query or "")
    for _, row in ipairs(ordered) do
        if (query == "" or row.search:find(query, 1, true))
            and (not tag or self.tags.matches(row.tags, {tag}, "all")) then
            selected[#selected + 1], count = row, count + row.n
        end
    end
    return selected, count
end

return View
