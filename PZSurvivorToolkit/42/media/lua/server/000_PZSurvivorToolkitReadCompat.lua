-- SP loads server mods after client policies; resolve the reviewed wrapper before MPFF auto-loads it.
if PZSurvivorToolkit and PZSurvivorToolkit.ActionQueueCompat then
    PZSurvivorToolkit.ActionQueueCompat.installReadFix()
end
