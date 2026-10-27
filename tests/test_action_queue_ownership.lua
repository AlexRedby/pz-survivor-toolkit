-- Reuse the existing behavior vectors with the game's table lookup contract.
-- This checks Lua ownership, not rendering, packets or live-game scheduling.
-- Native JVM checks retain the actual engine rawget. Only Lua 5.1 needs
-- this bounded emulation to expose the same inherited-member mistakes.
if not NativeFilenameOfClosure then
    local stockRawget=rawget
    rawget=function(value,key)
        local member=stockRawget(value,key)
        if member~=nil then return member end
        local parent=getmetatable(value)
        if type(parent)=="table" then return rawget(parent,key) end
        return nil
    end
end
NativeKahluaTableLookup=true
local cases={
    OwnershipRadio="test_action_queue_edit_adapters.lua",
    OwnershipItems="test_action_queue_item_edit_adapters.lua",
    OwnershipMedia="test_action_queue_media.lua",
    OwnershipRecovery="test_action_queue_recovery_adapters.lua",
    OwnershipGenerators="test_action_queue_generators.lua",
    OwnershipApproach="test_action_queue_vegetation.lua",
    OwnershipHealth="test_action_queue_health.lua",
    OwnershipLifecycle="test_action_queue_lifecycle.lua",
    OwnershipSettlement="test_action_queue_settlement.lua",
    OwnershipGrooming="test_action_queue_grooming.lua",
    OwnershipTextBinding="test_action_queue_text_binding.lua",
    OwnershipGroomingPending="test_action_queue_grooming_pending.lua",
    OwnershipGroomingCosts="test_action_queue_grooming_costs.lua",
    OwnershipGroomingActive="test_action_queue_grooming_active.lua",
    OwnershipAnimalStops="test_action_queue_animal_stops.lua",
}
for flag,name in pairs(cases)do
    if _G[flag]then
        assert(NativeActionRoot,"ownership behavior vectors require native sources")
        assert(loadfile(ProjectRoot.."/tests/"..name))()
        print("Kahlua ownership vectors passed: "..flag)
        return
    end
end
local Proof=assert(loadfile(ProjectRoot.."/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua"))()
local parent={callback=function()end,flag=true};parent.__index=parent
local child=setmetatable({value=false},parent)
assert(rawget(child,"callback")==parent.callback,"fixture does not model Kahlua inherited rawget")
assert(type(Proof.own)=="function","shared owned-member lookup missing")
assert(Proof.own(child,"callback")==nil and Proof.own(child,"flag")==nil,"inherited fields were treated as owned")
assert(Proof.own(child,"value")==false,"owned false value was lost")
assert(select("#",Proof.own(child,"absent"))==1,"absent owned field must return one explicit nil")
child.callback=parent.callback
assert(Proof.own(child,"callback")==parent.callback,"owned native alias was lost")
print("Kahlua owned-member lookup preserves absence, false and explicit aliases.")
