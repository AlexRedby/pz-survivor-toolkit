# Optional Windows recorder. Importing is inert; only the helper is elevated.
# WPR syntax/instance isolation: https://learn.microsoft.com/windows-hardware/test/wpt/wpr-command-line-options
function ConvertTo-TrialWprUtc($Value) {
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime() }
    return [DateTime]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}
function Assert-TrialWprPath([string]$Path) {
    $ErrorActionPreference='Stop'
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'WPR paths must not contain reparse points.' }
        }
        $parent=[IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }; $current=$parent
    }
}
function Write-TrialWprJson([string]$Path, $Value) {
    $ErrorActionPreference='Stop'
    Assert-TrialWprPath $Path
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 10))
    # Atomic publication prevents the helper/launcher reading a half-written signal.
    $temporary=$Path+'.pending'
    Assert-TrialWprPath $temporary
    [IO.File]::WriteAllBytes($temporary,$bytes)
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) } else { [IO.File]::Move($temporary,$Path) }
}
function Read-TrialWprJson([string]$Path) {
    $ErrorActionPreference='Stop'
    Assert-TrialWprPath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $limit=131072
    if ([IO.Path]::GetFileName($Path) -eq 'wpr-status.json') { $limit=524288 }
    if ((Get-Item -LiteralPath $Path).Length -gt $limit) { throw 'WPR control/receipt is too large.' }
    return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop)
}
function Get-TrialWprSystemDirectory {
    return [Environment]::GetFolderPath([Environment+SpecialFolder]::System)
}
function Get-TrialWprTool {
    # Never execute an untrusted PATH candidate from the elevated helper.
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' ) { return $null }
    $system=Get-TrialWprSystemDirectory
    if (-not $system) { return $null }
    $tool=Join-Path $system 'wpr.exe'
    Assert-TrialWprPath $tool
    if (Test-Path -LiteralPath $tool -PathType Leaf) { return [IO.Path]::GetFullPath($tool) }
    return $null
}
function Get-TrialWprStatus($Context) {
    if (-not $Context.Worker) { return $Context.Status }
    try {
        $receipt=Read-TrialWprJson $Context.StatusPath
        if ($receipt -and $receipt.captureId -eq $Context.CaptureId -and $receipt.instanceName -eq $Context.InstanceName -and
            $receipt.targetPid -eq $Context.TargetPid -and (ConvertTo-TrialWprUtc $receipt.processStartUtc).Ticks -eq (ConvertTo-TrialWprUtc $Context.ProcessStartUtc).Ticks -and
            $receipt.helperPid -eq $Context.Worker.Id -and (ConvertTo-TrialWprUtc $receipt.helperStartUtc).Ticks -eq (ConvertTo-TrialWprUtc $Context.WorkerStartUtc).Ticks) {
            if (-not $Context.LocalFailure -or $receipt.status -in @('Complete','Unavailable','Incomplete')) { $Context.Status=$receipt; $Context.LocalFailure=$null }
        }
    } catch { }
    return $Context.Status
}
function Send-TrialWprRequest($Context,[string]$Action) {
    $ErrorActionPreference='Stop'
    if ($Action -notin @('start','stop')) { throw 'Unsupported WPR signal.' }
    Assert-TrialWprPath $Context.Directory
    $path=Join-Path $Context.Directory ($Action+'.request.json')
    if (-not (Test-Path -LiteralPath $path)) {
        Write-TrialWprJson $path ([ordered]@{captureId=$Context.CaptureId;action=$Action;targetPid=$Context.TargetPid;requestedUtc=[DateTime]::UtcNow.ToString('o')})
    }
}
function Wait-TrialWprState($Context,[string[]]$States,[int]$Seconds) {
    $watch=[Diagnostics.Stopwatch]::StartNew(); $reported=0
    do {
        $status=Get-TrialWprStatus $Context
        if ($status.status -in $States) { return $status }
        if ($Context.Worker -and $Context.Worker.HasExited) { break }
        if ([int]$watch.Elapsed.TotalSeconds -ge ($reported+5)) { $reported=[int]$watch.Elapsed.TotalSeconds; Write-Host ('WPR helper: waiting for '+($States -join '/')+' ('+$reported+'s). Other diagnostic files are preserved.') }
        Start-Sleep -Milliseconds 100
    } while ($watch.Elapsed.TotalSeconds -lt $Seconds)
    return (Get-TrialWprStatus $Context)
}
function Initialize-TrialWprCapture([string]$Directory,$Process,$Plan) {
    $ErrorActionPreference='Stop'
    $identity=(ConvertTo-TrialWprUtc $Plan.ProcessStartUtc)
    $null=Assert-JfrTargetProcess $Process $Plan.Java $identity
    Assert-TrialWprPath $Directory
    $captureId=[Guid]::NewGuid().ToString('N')
    $run=Join-Path $Directory $captureId
    [IO.Directory]::CreateDirectory($run) | Out-Null
    $status=[pscustomobject][ordered]@{format=1;captureId=$captureId;instanceName=('PZTrial_'+$captureId);targetPid=$Process.Id;
        processStartUtc=$Plan.ProcessStartUtc;status='Requested';reason=$null;requestedUtc=[DateTime]::UtcNow.ToString('o');
        startRequestedUtc=$null;startedUtc=$null;stopRequestedUtc=$null;stoppedUtc=$null;helperPid=$null;helperStartUtc=$null;
        profiles=@('GeneralProfile','GPU');loggingMode='File';traceFile='drive.etl';traceBytes=$null;traceSha256=$null;headerValidated=$false;
        limitations='System-wide ETW with file-writing overhead. No heap/allocation profile. Lost-event evidence remains raw/localized; zero loss is not inferred.'}
    $context=[pscustomobject]@{Directory=$run;CaptureId=$captureId;InstanceName=$status.instanceName;TargetPid=$Process.Id;
        ProcessStartUtc=$Plan.ProcessStartUtc;ExpectedExecutable=$Plan.Java;TargetProcess=$Process;StatusPath=(Join-Path $run 'wpr-status.json');
        Status=$status;LocalFailure=$null;Worker=$null;WorkerStartUtc=$null;StartSent=$false;StopSent=$false}
    Write-TrialWprJson $context.StatusPath $status
    try {
        $tool=Get-TrialWprTool
        if (-not $tool) { $status.reason='WprUnavailable'; $status.status='Unavailable'; return $context }
        $parent=Get-Process -Id $PID -ErrorAction Stop
        $seconds=180
        if ($Plan.PSObject.Properties['WprDurationSeconds']) { $seconds=[int]$Plan.WprDurationSeconds }
        $seconds=[Math]::Max(30,[Math]::Min(240,$seconds))
        $control=[ordered]@{format=1;captureId=$captureId;targetPid=$Process.Id;processStartUtc=$Plan.ProcessStartUtc;expectedExecutable=[IO.Path]::GetFullPath($Plan.Java);
            parentPid=$PID;parentStartUtc=$parent.StartTime.ToUniversalTime().ToString('o');parentExecutable=$parent.Path;
            captureSeconds=$seconds;prepareSeconds=900;maximumTempBytes=2147483648}
        $controlPath=Join-Path $run 'control.json'
        Write-TrialWprJson $controlPath $control
        $hash=(Get-FileHash -LiteralPath $controlPath -Algorithm SHA256).Hash
        $helper=Join-Path $PSScriptRoot 'TrialWprWorker.ps1'
        Assert-TrialWprPath $helper
        $shell=Join-Path (Get-TrialWprSystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
        Assert-TrialWprPath $shell
        # Windows paths cannot contain double quotes; no command string is evaluated.
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -Directory "'+$run+'" -ControlHash '+$hash
        $context.Worker=Start-Process -FilePath $shell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        $context.WorkerStartUtc=$context.Worker.StartTime.ToUniversalTime().ToString('o')
        $null=Wait-TrialWprState $context @('Ready','Unavailable','Incomplete') 20
        if ($context.Status.status -eq 'Requested') { Set-TrialWprLocalFailure $context 'Unavailable' 'HelperReadinessTimeout'; Send-TrialWprRequest $context 'stop' }
    } catch {
        $status.status='Unavailable'
        $status.reason='HelperStartFailedOrUacDeclined'
        if ($context.Worker) {
            # Retain the owned handle/context even if querying its start time or
            # readiness failed after UAC. Prevent a late Ready receipt starting ETW.
            Set-TrialWprLocalFailure $context 'Unavailable' 'HelperInitializationFailed'
            try { Send-TrialWprRequest $context 'stop'; $context.StopSent=$true } catch { }
        }
    } finally {
        # Once the worker is running it is the only receipt writer.
        if (-not $context.Worker) { Write-TrialWprJson $context.StatusPath $status }
    }
    return $context
}
function Start-TrialWprCapture($Context) {
    $status=Get-TrialWprStatus $Context
    if ($status.status -ne 'Ready' -or $Context.StartSent) { return $status }
    try {
        $null=Assert-JfrTargetProcess $Context.TargetProcess $Context.ExpectedExecutable (ConvertTo-TrialWprUtc $Context.ProcessStartUtc)
        Send-TrialWprRequest $Context 'start'; $Context.StartSent=$true
        $status=Wait-TrialWprState $Context @('Recording','Unavailable','Incomplete','Complete') 20
        if ($status.status -eq 'Ready') { Send-TrialWprRequest $Context 'stop'; $Context.StopSent=$true; Set-TrialWprLocalFailure $Context 'Incomplete' 'HelperStartAcknowledgementTimeout' }
    } catch { $null=Stop-TrialWprCapture $Context }
    return (Get-TrialWprStatus $Context)
}
function Set-TrialWprLocalFailure($Context,[string]$State,[string]$Reason) {
    # Do not race the helper's authoritative receipt writer. Later terminal
    # receipts may replace this honest launcher-side timeout state.
    $local=$Context.Status | ConvertTo-Json -Depth 14 | ConvertFrom-Json
    $local.status=$State; $local.reason=$Reason
    $Context.Status=$local; $Context.LocalFailure=$Reason
}
function Complete-TrialWprCapture($Context) {
    if (-not $Context) { return $null }
    $status=Get-TrialWprStatus $Context
    if (-not $Context.Worker -or $status.status -in @('Complete','Unavailable','Incomplete')) { return $status }
    if (-not $Context.StopSent) { Send-TrialWprRequest $Context 'stop'; $Context.StopSent=$true }
    $status=Wait-TrialWprState $Context @('Complete','Unavailable','Incomplete') 110
    if ($status.status -notin @('Complete','Unavailable','Incomplete')) { Set-TrialWprLocalFailure $Context 'Incomplete' 'HelperCompletionTimeout' }
    return $Context.Status
}
function Stop-TrialWprCapture($Context) { return (Complete-TrialWprCapture $Context) }
