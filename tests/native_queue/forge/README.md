# Forge Simple Blade: real Host regression

Run through the shared `tools/check_action_queue.py` preparation, launch and report path. The Windows route is limited to one-client Host and owns its client/child with a Job Object; it never signals a discovered user process. Use fresh output folders, explicit unused ports, the installed B42.21 game and JDK 25+. No live save/profile is copied or changed.

## Scenario

`handcraft,forge,forge-shift` is one ordered session with the full selected mod set:

1. Click the selected hand-crafting UI's real craft button for native **Saw Logs**. Verify one exact log debit and three new planks on the server.
2. Create a native Primitive Forge through `GameEntityFactory`, open its actual entity/workstation window and click **Forge Simple Blade** (`Base.Forge_Crude_Blade`). Verify its charcoal/iron debit, one new blade and the exact surviving tool IDs.
3. Create the same forge after another fixture-owned object on its square. Remove that earlier object using the native replicated removal, wait for the client's object index to shift, then repeat the same forge recipe through the same UI.

No action duration, recipe callback, network ID or completion result is replaced. The fixture tags its own forge to select that exact replicated object, not an unrelated generic crafting surface. Native durations are 1150 for Saw Logs and 1000 for Forge Simple Blade. A sustained 100% stall is recorded before fixture-only cancellation cleanup. Client results must match independent server receipts and require idle native actions and crafting owner. This exercises programmatic UI button dispatch, not physical mouse input.

## Run

Create a JSON config with `mp_host: true`, `preload_toolkit_fonts: true` and explicit `mod_sources` for the Toolkit and Java mod roots. Pin a pre-fix Java mod for the baseline, then the candidate in another config; keep Toolkit, Workshop files and fixture bytes unchanged. Keep the output run directory on the same drive as the game so the early-font JAR can use a game-relative path. Example from PowerShell, with local paths supplied in variables:

```powershell
py -3 tools/check_action_queue.py run $Output --suite forge `
  --cases handcraft,forge,forge-shift --kind mp --mode toolkit --mods selected `
  --game $Game --jdk $Jdk --workshop $Workshop --config $Config `
  --ports 19353 19354 --timeout 660 --resource-wait 0
```

Allow the outer shell more than 660 seconds, or disable its timeout. Preparation copies/seals all selected mods, fixture sources, native Lua/scripts and initial settings; a retry requires a new output directory. The Windows client and native `CoopServer` use the game's bundled runtime, isolated approvals and silent/VOIP-disabled settings. Preserve `report.json`, `coverage.json`, `execution.json`, manifests and complete client/server logs outside Git.

The native Java `CraftBenchChecks` and `MedicalTimedActionChecks` cover decoder guards and their neighboring medical path. Current gameplay evidence belongs to each run's report; old local run summaries are not maintained here.
