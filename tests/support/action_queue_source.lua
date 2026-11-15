-- Actual source proofs for isolated native-action fixtures. This supplies no
-- actor, action, permission or execution double.
toolkitLuaMetatableMatches=assert(loadfile(ProjectRoot..'/tests/support/source_binding.lua'))()
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined+1 end
getGameFilesInput=function(path)
    local filename=NativeActionRoot..'/'..path:gsub('^media/lua/','')
    local text
    if NativeReadText then text=NativeReadText(filename)
    else
        local file,reason=io.open(filename)
        if not file then error(reason)end
        text=file:read('*a');file:close()
    end
    text=text:gsub('\r','')
    local position=1
    return {close=function()end,readLine=function()
        if position>#text then return end
        local boundary=text:find('\n',position,true)or #text+1
        local line=text:sub(position,boundary-1);position=boundary+1;return line
    end}
end
local proof=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
local previous=require
require=function(name)
    if name=='PZSurvivorToolkit/SourceProof'then return proof end
    return previous(name)
end
return proof
