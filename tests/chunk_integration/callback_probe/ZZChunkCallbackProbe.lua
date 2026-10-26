-- Test-only startup census: capture ends before ordinary gameplay starts.
Events.OnGameStart.Add(function() chunkCallbackProbeFinish() end)
