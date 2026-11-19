local Recovery = require 'PZSurvivorToolkit/ActionQueueGeneratorRecovery'
Events.OnClientCommand.Add(function(module, command, actor, args)
    if module ~= 'PZSurvivorToolkitGenerator' or not isServer() or type(args) ~= 'table' then return end
    -- OnClientCommand supplies the authenticated player; actor/object references
    -- are never accepted from command arguments.
    if command == 'Arm' then Recovery.arm(actor, args)
    elseif command == 'Cancel' then Recovery.cancel(actor, args.episode) end
end)
