-- Diagnostic-only inner spans in the disposable benchmark snapshot.
-- Protected calls add observer overhead; use these spans to locate work, not as a baseline.
local config = require "QueueTestSelection"
assert(config.options and config.options.callback_profile == true
    and config.options.callback_detail_profile == true,
    "Callback details require explicit callback_profile and callback_detail_profile")
assert(type(drivingPerfCallbackEnter) == "function"
    and type(drivingPerfCallbackExit) == "function", "Missing native callback detail bridge")
assert(PZDrivingCallbackCall == nil, "Callback detail helper already exists")

local function pack(...)
    return { n = select("#", ...), ... }
end

function PZDrivingCallbackCall(fn, ...)
    local token = drivingPerfCallbackEnter(fn)
    local result = pack(pcall(fn, ...))
    drivingPerfCallbackExit(token)
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end

local installed = false
local function install()
    if installed then return end
    local D = PZSurvivorToolkit and PZSurvivorToolkit.VehicleLightDashboard
    local targets = {
        { D, "bind", "Toolkit.VehicleLightDashboard.bind" },
        { YourDash, "InstallCompactTooltipTree", "YourDash.InstallCompactTooltipTree" },
        { ISVehicleDashboard, "_YourDashSportEnsureControls", "ISVehicleDashboard._YourDashSportEnsureControls" },
        { ISVehicleDashboard, "_YourDashSportPositionControls", "ISVehicleDashboard._YourDashSportPositionControls" },
        { ISVehicleDashboard, "_YourDashFinalizeWearOrder", "ISVehicleDashboard._YourDashFinalizeWearOrder" },
        { ISVehicleDashboard, "checkEngineFull", "ISVehicleDashboard.checkEngineFull" },
    }
    -- Validate the whole selected pack before changing any function table.
    for _, target in ipairs(targets) do
        assert(type(target[1]) == "table" and type(target[1][target[2]]) == "function",
            "Missing diagnostic callback target: " .. target[3])
    end
    for _, target in ipairs(targets) do
        local original = target[1][target[2]]
        target[1][target[2]] = function(...)
            return PZDrivingCallbackCall(original, ...)
        end
    end
    installed = true
    print("[DRIVING_PERF] CALLBACK_DETAILS_INSTALLED functions=6")
end

Events.OnGameStart.Add(function()
    local ok, problem = pcall(install)
    if not ok then
        print("[DRIVING_PERF] FAIL callback-detail-install: " .. tostring(problem))
        error(problem, 0)
    end
end)
