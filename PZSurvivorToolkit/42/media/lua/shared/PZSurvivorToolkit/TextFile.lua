local TextFile = {}

function TextFile.readLines(path, limit, maxLine)
    local reader = getFileReader(path, true)
    if not reader then error("Cannot read file: " .. path) end
    local ok, result = pcall(function()
        local values, size = {}, 0
        while true do
            local line = reader:readLine()
            if line == nil then break end
            if type(line) ~= "string" or (maxLine and #line > maxLine) then error("Invalid line in " .. path) end
            size = size + #line + 1
            if size > limit then error("File exceeds storage limit: " .. path) end
            values[#values + 1] = line
        end
        return values
    end)
    local closed, closeError = pcall(function() reader:close() end)
    if not ok then error(result) end
    if not closed then error(closeError) end
    return result
end

function TextFile.write(path, text)
    local writer = getFileWriter(path, true, false)
    if not writer then error("Cannot write file: " .. path) end
    local written, writeError = pcall(function() writer:write(text) end)
    local closed, closeError = pcall(function() writer:close() end)
    if not written then error(writeError) end
    if not closed then error(closeError) end
end

return TextFile
