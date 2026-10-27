-- Bucket hashes bound the path; exact identity inside each journal prevents cross-save collisions.
local Identity = {}
function Identity.valid(world)
    return type(world) == "string" and #world > 0 and #world <= 512
end
function Identity.encode(world)
    -- Kahlua string.byte uses UTF-16 code units. Keep the original units, without normalization.
    return (world:gsub(".", function(char) return string.format("%04x", string.byte(char)) end))
end
function Identity.prefix(world)
    local first, second = 0, 1
    for index = 1, #world do
        local unit = string.byte(world, index)
        first = (first * 33 + unit) % 2147483647
        second = (second * 65599 + unit) % 2147483629
    end
    return string.format("PZSurvivorWishlist/v3/%d-%.0f-%.0f/", #world, first, second)
end
function Identity.legacyPrefix(world)
    local encoded, parts = Identity.encode(world), {"PZSurvivorWishlist"}
    for index = 1, #encoded, 80 do parts[#parts + 1] = encoded:sub(index, index + 79) end
    return table.concat(parts, "/") .. "/"
end
return Identity
