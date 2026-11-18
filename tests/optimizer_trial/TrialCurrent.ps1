# Isolated current-build upstream runtime. The legacy B42.21 profile remains readable
# for its original packages; no old class overlay is admitted by this path.
function Read-CurrentTrialManifest([string]$Path) {
    Assert-NoReparsePoint $Path
    $manifest = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    if ($manifest.format -ne 1 -or $manifest.game_version -cne '42.22.2' -or
        $manifest.upstream_revision -cnotmatch '^fad5786285a0b9c28ed804544ce01ba49fc5f197$') {
        throw 'Unsupported current upstream trial manifest.'
    }
    if ($manifest.native_guards -isnot [pscustomobject] -or @($manifest.native_guards.PSObject.Properties).Count -eq 0) {
        throw 'Current upstream trial requires native bytecode guards.'
    }
    foreach ($entry in $manifest.native_guards.PSObject.Properties) {
        Assert-TrialEntryName $entry.Name
        if ($entry.Name -cnotmatch '\.class$' -or $entry.Value -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid current native guard.' }
    }
    if ($manifest.release_url -notmatch '^https://github\.com/xD3I/PZ_Optimization/releases/download/[^/]+/[^/]+$' -or
        $manifest.release_sha256 -cne 'ba125a3f05cc04617c3f49217e1f07e99efe3dfa0ddaa4f34beb5020f35973c4' -or
        $manifest.release_size -ne 35562840) { throw 'Current trial must pin the reviewed official release.' }
    if ($manifest.selected_files -isnot [pscustomobject] -or @($manifest.selected_files.PSObject.Properties).Count -eq 0) { throw 'Missing current runtime files.' }
    foreach ($entry in $manifest.selected_files.PSObject.Properties) {
        Assert-TrialEntryName $entry.Name
        if ($entry.Name -cnotmatch '^pzopt/.+\.(class|jar|properties)$' -or $entry.Value -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid current runtime file.' }
    }
    $runtime = $manifest.runtime
    if ($runtime.kind -cne 'javaagent' -or $runtime.path -cne 'pzopt/agent/pzopt-agent.jar' -or
        -not $manifest.selected_files.PSObject.Properties[$runtime.path] -or $runtime.properties -isnot [pscustomobject]) {
        throw 'Current upstream runtime must pin an isolated Java agent.'
    }
    foreach ($entry in $runtime.properties.PSObject.Properties) {
        if ($entry.Name -cnotmatch '^[A-Za-z][A-Za-z0-9]*$' -or $entry.Value -isnot [string] -or
            $entry.Value -cnotmatch '^[A-Za-z0-9.,_/-]*$') { throw 'Unsafe upstream runtime property.' }
    }
    Assert-TrialStrings $runtime.ready_markers 'current runtime ready_markers'
    if ($runtime.ready_markers.Count -eq 0) { throw 'Missing current runtime activation evidence.' }
    $script:TrialGameVersion = [version]$manifest.game_version
    return $manifest
}

function Get-CurrentTrialCandidate([string]$Package, $Manifest, [string]$SourceZip) {
    # Reuse the verified download/extraction transport, never its legacy launch plan.
    $transport = [pscustomobject]@{ release_url = $Manifest.release_url; release_sha256 = $Manifest.release_sha256;
        release_bytes = $Manifest.release_size; selected_files = $Manifest.selected_files; profile = $null }
    $candidate = Get-TrialCandidate $Package $transport -SourceZip $SourceZip
    return [pscustomobject]@{ Agent = (Join-Path $candidate.Overlay $Manifest.runtime.path);
        Root = $candidate.Overlay; Zip = $candidate.Zip; Manifest = $Manifest }
}

function Get-CurrentTrialProbe([string]$Package) {
    $path = Join-Path $Package 'TrialProbe.jar'
    $receiptPath = Join-Path $Package 'build-receipt.json'
    Assert-NoReparsePoint $path; Assert-NoReparsePoint $receiptPath
    $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
    $manifestPath = Join-Path $Package 'current-trial-manifest.json'
    Assert-NoReparsePoint $manifestPath
    if ($receipt.candidate_manifest_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $receipt.candidate_manifest_sha256) {
        throw 'Current runtime manifest differs from its build receipt.'
    }
    if ($receipt.trial_probe_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $receipt.trial_probe_sha256) {
        throw 'Current runtime observation agent is missing or has changed.'
    }
    return [pscustomobject]@{ Path = (Get-FullPath $path); Sha256 = $receipt.trial_probe_sha256 }
}

function Get-CurrentTrialCache([string]$Root, [ValidateSet('Optimized','Control')][string]$TrialMode,
    [ValidateSet('SinglePlayer','Multiplayer')][string]$SessionType = 'SinglePlayer') {
    # The starter is active only in SP. Keep each exact selection and save scope stable.
    return Join-Path (Join-Path $Root $SessionType) $TrialMode
}

function Write-CurrentTrialArguments([string]$Cache, $Properties) {
    $path = Join-Path $Cache 'current-optimizer.args'
    Assert-NoReparsePoint $path
    [IO.Directory]::CreateDirectory($Cache) | Out-Null
    $lines = @($Properties.PSObject.Properties | ForEach-Object { '-Dpzopt.' + $_.Name + '=' + $_.Value })
    [IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), $script:Utf8)
    return $path
}

function New-CurrentTrialPlan([string]$Game, [string]$Cache, [string]$TrialMode, $Config, $Candidate,
    [ValidateSet('SinglePlayer','Multiplayer')][string]$SessionType, $Manifest, [string]$Package, $Probe = (Get-CurrentTrialProbe $Package)) {
    # Reuse native launcher/collector shape without ever selecting legacy overlays.
    $plan = New-TrialPlan $Game $Cache Control $Config $null -SessionType $SessionType
    $plan.Mode = $TrialMode
    $vm = @('-javaagent:' + $probe.Path) + @($Config.VmArgs)
    if (@($Config.VmArgs | Where-Object { $_ -match '^(?i)-Duser\.home=' }).Count) { throw 'Native user.home override conflicts with isolated current trial.' }
    $vm += @(('-Dpz.optimizerTrial.arm=' + $TrialMode), ('-Dpz.optimizerTrial.mode=' + $SessionType.ToLowerInvariant()),
        ('-Duser.home=' + (Join-Path $Cache 'RuntimeHome')))
    if ($TrialMode -eq 'Optimized') {
        if (-not $Candidate) { throw 'Current optimized runtime was not verified.' }
        $plan.OptimizerArguments = Write-CurrentTrialArguments $Cache $Manifest.runtime.properties
        $vm += '@' + $plan.OptimizerArguments
        $vm = @('-javaagent:' + $Candidate.Agent) + $vm
        $plan.Classpath = @($plan.Classpath) + @($Candidate.Root)
    }
    $arguments = @($vm) + @('-cp', ($plan.Classpath -join ';'), $Config.MainClass, ('-cachedir=' + $Cache), '-novoip')
    $plan.VmArgs = $vm; $plan.Arguments = $arguments
    $plan.CommandLine = (($arguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' ')
    $plan.OptimizerProfile = if ($TrialMode -eq 'Optimized') { $Manifest.runtime } else { $null }
    $plan | Add-Member -NotePropertyName CurrentRuntime -NotePropertyValue ([pscustomobject]@{
        GameVersion = $Manifest.game_version; UpstreamRevision = $Manifest.upstream_revision;
        Kind = $Manifest.runtime.kind; ProbeSha256 = $probe.Sha256; AgentSha256 = $Manifest.selected_files.PSObject.Properties[$Manifest.runtime.path].Value; Enabled = ($TrialMode -eq 'Optimized')
    })
    return $plan
}

function Get-CurrentTrialReadiness([string]$Text, [string]$TrialMode, [string]$PackRevision,
    [int]$ExpectedCount, [string]$SessionType, [string]$ContextId, [switch]$Menu,
    [bool]$PreviousFailure, $Manifest) {
    $missing = @()
    $packPattern = '(?m)^[^\r\n]*\[OptimizerTrial\] pack active revision=' + [regex]::Escape($PackRevision) + ' count=' + $ExpectedCount + '[ \t\r]*$'
    if (-not $PackRevision -or $Text -notmatch $packPattern) { $missing += 'current full modpack activation' }
    if (-not $Text.Contains('[PZToolkitJavaPatches] Experimental B42.22.2 patch:')) { $missing += 'current Toolkit Java patches activation' }
    $markers = @(('[OptimizerTrial] current bridge ready mode=' + $TrialMode), ('[OptimizerTrial] effective classes verified mode=' + $TrialMode))
    if ($TrialMode -eq 'Optimized') { $markers += @($Manifest.runtime.ready_markers) }
    foreach ($marker in $markers) {
        if ($Text -notmatch ('(?m)^[^\r\n]*' + [regex]::Escape($marker) + '[ \t\r]*$')) { $missing += $marker }
    }
    if ($SessionType -eq 'Multiplayer') {
        $contextPattern = '(?m)^[^\r\n]*\[OptimizerTrial\] multiplayer context ready world=' + [regex]::Escape($ContextId) + '[ \t\r]*$'
        if (-not $ContextId -or $Text -notmatch $contextPattern) { $missing += 'connected multiplayer context observer' }
    } elseif (-not $Menu -and -not (Test-TrialWorldReady $Text)) { $missing += 'single-player starter world and car readiness' }
    $failurePattern = '\[PZDrivingBench\] FAIL |\[OptimizerTrial\] (?:PACK_MISMATCH|current bridge failed|effective classes failed|current runtime disabled:|drive telemetry disabled|telemetry flush failed)|(?im)^.*(?:PZDrivingOptimizerBridge|PZToolkitJavaPatches).*(?:blocked|denied)|^.*(?:blocked|denied).*(?:PZDrivingOptimizerBridge|PZToolkitJavaPatches)'
    return [pscustomobject]@{ Ready = ($missing.Count -eq 0 -and -not $PreviousFailure -and $Text -notmatch $failurePattern);
        Failed = ($PreviousFailure -or $Text -match $failurePattern); Missing = @($missing); ActionGroups = $null; HandedOff = $null }
}
