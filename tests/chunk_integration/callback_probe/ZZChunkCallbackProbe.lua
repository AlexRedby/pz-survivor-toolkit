-- Manual fixtures explicitly delimit their one capture interval after startup.
Events.OnGameStart.Add(function()
    if chunkCallbackProbeCaptureMode() == "startup" then chunkCallbackProbeFinish() end
end)
