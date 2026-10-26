-- Only the portable launcher's one-shot marker can request automatic world creation.
local entered, starting, attempted = false, false, false
local runName
Events.OnMainMenuEnter.Add(function()
    if attempted then return end
    attempted = true
    local reader = getFileReader("DrivingBench-run.txt", false)
    if not reader then return end
    local line = reader:readLine()
    reader:close()
    if type(line) ~= "string" or #line > 100 or not line:match("^PZDrivingBench%-%w[%w%-]*$") then return end
    runName, entered = line, true
end)
Events.OnPreUIDraw.Add(function()
    if not entered or starting or isIngameState() or isClient() then return end
    starting = true
    local ok, problem = pcall(function()
        getWorld():setGameMode("Sandbox")
        getWorld():setWorld(runName)
        getWorld():setMap("Muldraugh, KY")
        MainScreen.instance:setDefaultSandboxVars()
        local current, active = ActiveMods.getById("currentGame"), getActivatedMods()
        current:getMods():clear()
        for i=0, active:size()-1 do current:getMods():add(active:get(i)) end
        MainScreen.instance.createWorld = true
        MapSpawnSelect.instance.selectedRegion = {points={unemployed={{posX=10818,posY=10118,posZ=0}}}}
        MainScreen.instance.charCreationProfession:onOptionMouseDown({internal="NEXT"})
        MainScreen.instance.charCreationMain:onOptionMouseDown({internal="NEXT"})
        print("[PZDrivingBench] NEW_WORLD " .. runName)
    end)
    if not ok then print("[PZDrivingBench] FAIL autostart " .. tostring(problem)) end
end)
