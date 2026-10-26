local realPrint = print
local function check(ids, fragment)
    local messages, callback = {}, nil
    print = function(message) messages[#messages + 1] = message end
    package.loaded.PZOptimizerTrialExpectedMods = {revision=string.rep("a",40),ids={"Toolkit","Dependency","Trial"}}
    Events = {OnGameStart={Add=function(f) callback=f end}}
    function getActivatedMods()
        return {size=function() return #ids end, get=function(_,i) return ids[i+1] end,
            contains=function(_,id) for _,v in ipairs(ids) do if id==v then return true end end return false end}
    end
    dofile("tests/optimizer_trial/PZOptimizerTrialPack.lua")
    assert(callback)
    callback()
    assert(#messages==1 and messages[1]:find(fragment,1,true),table.concat(messages,"\n"))
end
check({"Toolkit","Dependency","Trial"},"pack active revision="..string.rep("a",40).." count=3")
check({"Toolkit","Trial"},"PACK_MISMATCH missing=Dependency")
check({"Toolkit","Dependency","Trial","OldOptimizer"},"unexpected=OldOptimizer")
print = realPrint
print("OPTIMIZER_PACK_RUNTIME_CHECKS_PASS exact-set missing-dependency unexpected-mod")
