local Storage = require "PZSurvivorToolkit/ModOptionsStorage"
local Settings = {}
local markerPath = "PZSurvivorToolkitCartControls.ini"
local markerVersion = "PushCartInteract=1"
local configuredBinding

-- Called while SaucedCarts still has its file-load default, before ModOptions:load().
function Settings.configureDefault(binding)
    if not binding or configuredBinding == binding then return end
    configuredBinding = binding
    binding.defaultkey = Keyboard.KEY_E
    if binding:getValue() == Keyboard.KEY_V then binding:setValue(Keyboard.KEY_E) end
end

-- Called on game start, after native ModOptions has restored the user's choice.
function Settings.migrate(binding)
    if not binding or type(binding.getValue) ~= "function" or type(binding.setValue) ~= "function" then
        return false, "binding_missing"
    end
    local complete = Storage.matches(markerPath, markerVersion)
    if complete == nil then return false, "marker_read" end
    if complete then return true, "already_migrated" end
    local previous = binding:getValue()
    if previous == Keyboard.KEY_V then
        binding:setValue(Keyboard.KEY_E)
        if not Storage.save({["keybind|SaucedCarts|PushCart|"] = tostring(Keyboard.KEY_E)}) then
            binding:setValue(previous)
            return false, "binding_save"
        end
    end
    -- Also finish the decision for custom/disabled keys so a later chosen V is
    -- never confused with the old default. Those choices need no options save.
    if not Storage.mark(markerPath, markerVersion) then return false, "marker_write" end
    return true, previous == Keyboard.KEY_V and "migrated" or "preserved"
end

return Settings
