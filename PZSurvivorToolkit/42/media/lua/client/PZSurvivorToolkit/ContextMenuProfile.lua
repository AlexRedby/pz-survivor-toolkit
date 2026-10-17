local Profile = {}
local file = "PZSurvivorToolkit_ContextMenus.ini"

local function encode(value)
    return tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
end
local function decode(value)
    return value:gsub("%%0A", "\n"):gsub("%%0D", "\r"):gsub("%%7C", "|"):gsub("%%25", "%%")
end
local function validKey(value)
    return type(value) == "string" and #value > 0 and #value <= 1024
end
local function validScope(value)
    return value == "*" or (type(value) == "string" and #value <= 160 and value:find(".", 1, true) and not value:find("[%c|]"))
end
local function cleanName(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if #value == 0 or #value > 256 or value:find("%c") then return nil end
    return value
end
local function copy(values)
    local out = {}; for i, value in ipairs(values or {}) do out[i] = value end; return out
end

function Profile.new(Rules)
    local self = {entries = {}, overrides = {}, items = {}, scoped = {}, customGroups = {}, names = {}, orders = {}, layouts = {}, discovered = {}, revision = 0}
    local preferencesRevision, actualLayouts = 0, {}
    local builtin = {root = true, hidden = true}
    for _, id in ipairs(Rules.groups) do builtin[id] = true end
    local function allowed(id) return builtin[id] or self.customGroups[id] ~= nil end
    local function scopeOf(scope) return scope or "*" end
    local function changed()
        preferencesRevision = preferencesRevision + 1
        self.revision = self.revision + 1
        self.save()
        if self.settingsChanged then self.settingsChanged() end
    end
    function self.isCustomGroup(id) return self.customGroups[id] ~= nil end
    function self.defaultGroupName(id) return getText("UI_PZSurvivorToolkit_context_group_" .. id) end
    function self.groupIds()
        local out = copy(Rules.groups)
        local custom = {}; for id in pairs(self.customGroups) do custom[#custom + 1] = id end
        table.sort(custom, function(a, b) return tonumber(a:match("%d+$")) < tonumber(b:match("%d+$")) end)
        for _, id in ipairs(custom) do out[#out + 1] = id end
        return out
    end
    function self.hasGroupName(id, scope)
        scope = scopeOf(scope)
        return (self.names[scope] and self.names[scope][id]) or (self.names["*"] and self.names["*"][id])
    end
    function self.groupName(id, scope)
        local name = self.hasGroupName(id, scope)
        if name then return name end
        local layout = self.layouts[scopeOf(scope)]
        if layout then
            for _, row in ipairs(layout.root or {}) do if row.key == "group:" .. id then return row.label end end
        end
        return self.customGroups[id] or self.defaultGroupName(id)
    end
    function self.getOverride(key, scope)
        local scoped = self.scoped[scopeOf(scope)]
        if scoped and scoped[key] ~= nil then return scoped[key] end
        return self.overrides[key]
    end
    function self.setOverride(key, category, scope)
        scope = scopeOf(scope)
        if not validKey(key) or not validScope(scope) or (category ~= nil and not allowed(category)) then return false end
        local target = self.overrides
        if scope ~= "*" then self.scoped[scope] = self.scoped[scope] or {}; target = self.scoped[scope] end
        target[key] = category; changed(); return true
    end
    function self.createGroup(name, scope)
        name = cleanName(name)
        if not name or not validScope(scopeOf(scope)) then return nil end
        local count = 0; for _ in pairs(self.customGroups) do count = count + 1 end
        if count >= 64 then return nil end
        local index = 1; while self.customGroups["custom:" .. index] do index = index + 1 end
        local id = "custom:" .. index; self.customGroups[id] = name
        changed(); return id
    end
    function self.renameGroup(id, name, scope)
        name, scope = cleanName(name), scopeOf(scope)
        if not name or not validScope(scope) or not allowed(id) or id == "root" or id == "hidden" then return false end
        self.names[scope] = self.names[scope] or {}; self.names[scope][id] = name
        changed(); return true
    end
    function self.deleteGroup(id)
        if not self.customGroups[id] then return false end
        self.customGroups[id] = nil
        for key, category in pairs(self.overrides) do if category == id then self.overrides[key] = nil end end
        for _, overrides in pairs(self.scoped) do
            for key, category in pairs(overrides) do if category == id then overrides[key] = nil end end
        end
        for _, names in pairs(self.names) do names[id] = nil end
        for _, parents in pairs(self.orders) do
            parents[id] = nil
            for parent, keys in pairs(parents) do
                local kept = {}; for _, key in ipairs(keys) do if key ~= "group:" .. id then kept[#kept + 1] = key end end
                parents[parent] = kept
            end
        end
        changed(); return true
    end
    function self.getOrder(scope, parent)
        scope = scopeOf(scope); parent = parent or "root"
        return copy((self.orders[scope] and self.orders[scope][parent]) or (self.orders["*"] and self.orders["*"][parent]))
    end
    function self.setOrder(scope, parent, keys)
        scope = scopeOf(scope)
        if not validScope(scope) or not validKey(parent) or type(keys) ~= "table" or #keys > 512 then return false end
        local seen = {}
        for _, key in ipairs(keys) do if not validKey(key) or seen[key] then return false end; seen[key] = true end
        self.orders[scope] = self.orders[scope] or {}; self.orders[scope][parent] = copy(keys)
        changed(); return true
    end
    local function orderRows(rows, scope, parent)
        local ranks = {}; for i, key in ipairs(self.getOrder(scope, parent)) do ranks[key] = i end
        for i, row in ipairs(rows) do row.position = i end
        local function before(a, b)
            local x, y = ranks[a.key], ranks[b.key]
            if x and y then return x < y end
            if x or y then return x ~= nil end
            return a.position < b.position
        end
        local start = 1
        for boundary = 1, #rows + 1 do
            if boundary > #rows or rows[boundary].kind == "title" then
                local segment = {}; for i = start, boundary - 1 do segment[#segment + 1] = rows[i] end
                table.sort(segment, before)
                for i, row in ipairs(segment) do rows[start + i - 1] = row end
                start = boundary + 1
            end
        end
        return rows
    end
    function self.getLayout(scope, parent)
        scope, parent = scopeOf(scope), parent or "root"
        local actual = actualLayouts[scope]
        if actual and actual.version == preferencesRevision then
            local rows = {}
            for _, row in ipairs(actual.layout[parent] or {}) do
                rows[#rows + 1] = {key = row.key, label = row.label, kind = row.kind, category = row.category}
            end
            return rows
        end
        local layout = self.layouts[scope] or {}
        local root, groups, seen = {}, {}, {}
        local function add(row, originalParent)
            if seen[row.key] then return end; seen[row.key] = true
            local category = self.getOverride(row.key, scope) or originalParent
            if category == "hidden" then return end
            local out = {key = row.key, label = row.label, kind = "action", category = category}
            if category == "root" then root[#root + 1] = out
            else
                if not groups[category] then
                    groups[category] = {}
                    root[#root + 1] = {key = "group:" .. category, label = self.groupName(category, scope), kind = "group", category = category}
                end
                groups[category][#groups[category] + 1] = out
            end
        end
        for _, row in ipairs(layout.root or {}) do
            if row.kind == "title" then
                root[#root + 1] = {key = row.key, label = row.label, kind = "title", category = "root"}
            elseif row.kind == "group" then
                for _, child in ipairs(layout[row.category] or {}) do add(child, row.category) end
            else add(row, "root") end
        end
        -- Hidden defaults can be explicitly restored without reopening the native menu.
        for _, row in ipairs(self.getEntries(scope)) do
            if not seen[row.key] and self.getOverride(row.key, scope) then add(row, row.category or "root") end
        end
        return orderRows(parent == "root" and root or (groups[parent] or {}), scope, parent)
    end
    function self.moveEntry(scope, parent, key, delta)
        if delta ~= -1 and delta ~= 1 then return false end
        local rows = self.getLayout(scope, parent); local at
        for i, row in ipairs(rows) do if row.key == key then at = i; break end end
        if not at or not rows[at + delta] or rows[at].kind == "title" or rows[at + delta].kind == "title" then return false end
        rows[at], rows[at + delta] = rows[at + delta], rows[at]
        local keys = {}; for i, row in ipairs(rows) do keys[i] = row.key end
        return self.setOrder(scope, parent, keys)
    end
    function self.getEntries(scope)
        scope = scopeOf(scope)
        local entries = scope == "*" and self.entries or (self.discovered[scope] or {})
        local actual = actualLayouts[scope]
        local parents = actual and actual.version == preferencesRevision and actual.parents or {}
        local out = {}
        for key, entry in pairs(entries) do out[#out + 1] = {key = key, label = entry.label, category = parents[key] or self.getOverride(key, scope) or entry.category or "root"} end
        table.sort(out, function(a, b) return a.label < b.label or (a.label == b.label and a.key < b.key) end)
        return out
    end
    function self.record(scope, key, label, category)
        scope = scopeOf(scope)
        local old = self.entries[key]
        if not old or old.label ~= label or old.category ~= category then
            self.entries[key] = {key = key, label = label, category = category}; self.revision = self.revision + 1
        end
        if scope ~= "*" then
            self.discovered[scope] = self.discovered[scope] or {}
            local prior = self.discovered[scope][key]
            if not prior or prior.label ~= label or prior.category ~= category then
                self.discovered[scope][key] = {key = key, label = label, category = category}; self.revision = self.revision + 1
            end
        end
    end
    function self.captureLayout(scope, layout)
        scope = scopeOf(scope)
        self.layouts[scope] = layout
        local entries = scope == "*" and self.entries or (self.discovered[scope] or {})
        for parent, rows in pairs(layout) do
            for _, row in ipairs(rows) do
                if row.kind ~= "group" and entries[row.key] then entries[row.key].category = parent end
            end
        end
        self.revision = self.revision + 1
    end
    function self.captureActualLayout(scope, layout)
        local parents = {}
        for parent, rows in pairs(layout) do
            for _, row in ipairs(rows) do if row.kind == "action" then parents[row.key] = parent end end
        end
        actualLayouts[scopeOf(scope)] = {version = preferencesRevision, layout = layout, parents = parents}
    end
    function self.hasChanges(scope)
        for _ in pairs(self.overrides) do return true end
        for _ in pairs(self.names["*"] or {}) do return true end
        for _ in pairs(self.orders["*"] or {}) do return true end
        scope = scopeOf(scope)
        for _ in pairs(self.scoped[scope] or {}) do return true end
        for _ in pairs(self.names[scope] or {}) do return true end
        for _ in pairs(self.orders[scope] or {}) do return true end
        return false
    end
    function self.reset(scope)
        scope = scopeOf(scope)
        if scope == "*" then self.overrides, self.scoped, self.names, self.orders, self.customGroups = {}, {}, {}, {}, {}
        else self.scoped[scope], self.names[scope], self.orders[scope] = nil, nil, nil end
        changed()
    end
    function self.save()
        local writer = getFileWriter(file, true, false)
        if not writer then return false end
        local function line(...)
            local fields = {}; for i = 1, select('#', ...) do fields[i] = encode(select(i, ...)) end
            writer:write(table.concat(fields, "|") .. "\n")
        end
        for id, name in pairs(self.customGroups) do line("G", id, name) end
        for key, entry in pairs(self.entries) do line("E", key, entry.label, entry.category) end
        for key, id in pairs(self.overrides) do line("R", key, id) end
        for scope, name in pairs(self.items) do line("I", scope, name) end
        for scope, entries in pairs(self.discovered) do
            for key, entry in pairs(entries) do line("D", scope, key, entry.label, entry.category) end
        end
        for scope, rules in pairs(self.scoped) do for key, id in pairs(rules) do line("P", scope, key, id) end end
        for scope, names in pairs(self.names) do for id, name in pairs(names) do line("N", scope, id, name) end end
        for scope, parents in pairs(self.orders) do
            for parent, keys in pairs(parents) do for index, key in ipairs(keys) do line("O", scope, parent, index, key) end end
        end
        writer:close(); return true
    end
    local reader = getFileReader(file, false)
    if reader then
        local pending = {}
        while true do
            local raw = reader:readLine(); if not raw then break end
            if #raw <= 8192 then
                local fields = {}; for value in (raw .. "|"):gmatch("(.-)|") do fields[#fields + 1] = decode(value) end
                pending[#pending + 1] = fields
                if fields[1] == "G" and fields[2] and fields[2]:match("^custom:%d+$") and cleanName(fields[3]) then self.customGroups[fields[2]] = fields[3] end
            end
        end
        reader:close()
        for _, row in ipairs(pending) do
            local kind, a, b, c, d = unpack(row)
            if kind == "E" and validKey(a) and validKey(b) then self.entries[a] = {key = a, label = b, category = allowed(c) and c or nil}
            elseif kind == "R" and validKey(a) and allowed(b) then self.overrides[a] = b
            elseif kind == "I" and validScope(a) and a ~= "*" and cleanName(b) then self.items[a] = b
            elseif kind == "D" and validScope(a) and validKey(b) and validKey(c) then
                self.discovered[a] = self.discovered[a] or {}; self.discovered[a][b] = {key = b, label = c, category = allowed(d) and d or nil}
            elseif kind == "P" and validScope(a) and a ~= "*" and validKey(b) and allowed(c) then
                self.scoped[a] = self.scoped[a] or {}; self.scoped[a][b] = c
            elseif kind == "N" and validScope(a) and allowed(b) and b ~= "root" and b ~= "hidden" and cleanName(c) then
                self.names[a] = self.names[a] or {}; self.names[a][b] = c
            elseif kind == "O" and validScope(a) and validKey(b) and tonumber(c) and validKey(d) then
                local index = tonumber(c)
                if index >= 1 and index <= 512 and index == math.floor(index) then
                    self.orders[a] = self.orders[a] or {}; self.orders[a][b] = self.orders[a][b] or {}; self.orders[a][b][index] = d
                end
            end
        end
        for _, parents in pairs(self.orders) do
            for parent, keys in pairs(parents) do
                local out, seen = {}, {}
                for i = 1, 512 do local key = keys[i]; if key and not seen[key] then out[#out + 1] = key; seen[key] = true end end
                parents[parent] = out
            end
        end
    end
    return self
end
return Profile
