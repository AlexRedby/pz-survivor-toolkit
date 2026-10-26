# Shared diagnostics for the exact client owned by Launch-Trial.ps1. Windows PowerShell 5.1.
. (Join-Path $PSScriptRoot 'TrialNvidia.ps1')
. (Join-Path $PSScriptRoot 'TrialHotkey.ps1')
. (Join-Path $PSScriptRoot 'TrialCapFrameX.ps1')
. (Join-Path $PSScriptRoot 'TrialTelemetry.ps1')
. (Join-Path $PSScriptRoot 'TrialReadiness.ps1')
. (Join-Path $PSScriptRoot 'TrialWpr.ps1')
function Write-TrialDiagnosticJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 14), $script:Utf8)
}

function Save-TrialWprReceipt($Context, [string]$RunDirectory) {
    $relative=$null
    if ($Context.Directory) { $relative='WPR/' + [IO.Path]::GetFileName($Context.Directory) }
    Write-TrialDiagnosticJson (Join-Path $RunDirectory 'wpr-capture.json') ([ordered]@{format=1;relativeDirectory=$relative;receipt=$Context.Status})
}


# Optional recorder failures cannot replace the independently validated JFR/CX result.
function Get-TrialWprIntegrationFailures($Context) {
    $property=$Context.PSObject.Properties['IntegrationFailures']
    if ($property) { return @($property.Value) }
    return @()
}
function Set-TrialWprIntegrationFailure($Context,[string]$Stage) {
    $failures=@(Get-TrialWprIntegrationFailures $Context)
    if ($Stage -and $failures -notcontains $Stage) { $failures+=,$Stage }
    $Context | Add-Member -NotePropertyName IntegrationFailures -NotePropertyValue $failures -Force
    $copy=[ordered]@{}
    foreach ($property in $Context.Status.PSObject.Properties) { $copy[$property.Name]=$property.Value }
    $copy['status']='Unavailable'
    if ($copy['startedUtc'] -or $copy['stoppedUtc'] -or $Context.Status.status -in @('Recording','Complete','Incomplete') -or
        @($failures | Where-Object {$_ -in @('Start','Complete','Stop')}).Count) { $copy['status']='Incomplete' }
    $copy['reason']='Integration'+$failures[0]+'Failed'
    $copy['integrationFailures']=$failures
    $cleanup=$Context.PSObject.Properties['IntegrationCleanupStatus']
    if ($cleanup) { $copy['integrationCleanupStatus']=$cleanup.Value }
    $Context.Status=[pscustomobject]$copy
}
function Stop-TrialWprHelperAfterFailure($Context) {
    $workerProperty=$Context.PSObject.Properties['Worker']
    if (-not $workerProperty -or -not $workerProperty.Value) { return }
    $attempt=$Context.PSObject.Properties['IntegrationCleanupAttempted']
    if ($attempt -and $attempt.Value) { return }
    $Context | Add-Member -NotePropertyName IntegrationCleanupAttempted -NotePropertyValue $true -Force
    $worker=$workerProperty.Value
    $cleanup='HelperStopSignalFailed'
    try {
        # Bypass Complete's terminal-status early return. Signal before querying
        # helper metadata, so a failed HasExited query cannot leave it tracing.
        Send-TrialWprRequest $Context 'stop'
        $Context | Add-Member -NotePropertyName StopSent -NotePropertyValue $true -Force
        $watch=[Diagnostics.Stopwatch]::StartNew(); $reported=0
        while (-not $worker.HasExited -and $watch.Elapsed.TotalSeconds -lt 110) {
            if ([int]$watch.Elapsed.TotalSeconds -ge ($reported+5)) {
                $reported=[int]$watch.Elapsed.TotalSeconds
                Write-Host ('WPR cleanup after an optional failure ('+$reported+'s); JFR/frames are preserved.')
            }
            Start-Sleep -Milliseconds 100
        }
        $cleanup='HelperCompletionTimeout'
        if ($worker.HasExited) { $cleanup='HelperExited' }
        $null=Get-TrialWprStatus $Context
    } catch { $cleanup='HelperStopSignalOrWaitFailed' }
    $Context | Add-Member -NotePropertyName IntegrationCleanupStatus -NotePropertyValue $cleanup -Force
}
function Invoke-TrialOptionalWprOperation($Context,[string]$Operation,[string]$RunDirectory) {
    $ErrorActionPreference='Stop'
    # A failed preparation/receipt remains partial even if a later helper receipt
    # validates a saved trace. Do not start an optional recorder after that failure.
    $synthetic=$Context.PSObject.Properties['IntegrationSynthetic']
    if ($Operation -ne 'Receipt' -and $synthetic -and $synthetic.Value) { return }
    if ($Operation -eq 'Start' -and @(Get-TrialWprIntegrationFailures $Context).Count) { return }
    try {
        switch ($Operation) {
            'Start' { $null=Start-TrialWprCapture $Context }
            'Complete' { $null=Complete-TrialWprCapture $Context }
            'Stop' { $null=Stop-TrialWprCapture $Context }
            'Receipt' { Save-TrialWprReceipt $Context $RunDirectory }
            default { throw 'Unsupported optional recorder operation.' }
        }
    } catch {
        Stop-TrialWprHelperAfterFailure $Context
        Set-TrialWprIntegrationFailure $Context $Operation
        Write-Warning ('Optional WPR '+$Operation+' failed. JFR/CapFrameX capture continues; preserve this run.')
    }
    if (@(Get-TrialWprIntegrationFailures $Context).Count) { Set-TrialWprIntegrationFailure $Context '' }
}

function Resolve-TrialJfrTools([string]$Package, [string]$Game, [string]$Directory) {
    $saved = Join-Path $Package 'Diagnostics/jdk-directory.txt'
    Assert-NoReparsePoint $saved
    $explicit = [bool]$Directory
    if (-not $Directory -and (Test-Path -LiteralPath $saved -PathType Leaf)) { $Directory = [IO.File]::ReadAllText($saved).Trim() }
    $found = Get-JfrTools $Directory $Game
    if (-not $found -and -not $explicit) {
        Write-Host 'Before launching: JDK 25 tools are needed for BOTH captures. Keep the game Java runtime unchanged.'
        Write-Host 'Use the same extracted Windows x64 JDK 25 as for the earlier JFR recording.'
        $Directory = Read-Host 'JDK 25 folder containing bin\jcmd.exe (or pass -JdkDir)'
        $found = Get-JfrTools $Directory $Game
    }
    if (-not $found) { throw 'JDK 25 jcmd/jfr not found. No game was launched. Supply -JdkDir with the extracted JDK folder.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($saved)) | Out-Null
    $homePath = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($found.Jcmd))
    [IO.File]::WriteAllText($saved, $homePath, $script:Utf8)
    return $found
}

function Read-TrialCim([string]$Class, [string[]]$Properties, [string]$Filter = '') {
    try {
        $parameters = @{ClassName=$Class; ErrorAction='Stop'; OperationTimeoutSec=2}
        if ($Filter) { $parameters.Filter = $Filter }
        $rows = @(Get-CimInstance @parameters | Select-Object -Property $Properties)
        return [pscustomobject]@{status='Available'; data=$rows; error=$null}
    } catch { return [pscustomobject]@{status='Unavailable'; data=@(); error=$_.Exception.Message} }
}

function Get-TrialHardware {
    # Deliberately omit serial numbers, host/account names, network details and the environment.
    return [ordered]@{
        collectedUtc=[DateTime]::UtcNow.ToString('o')
        os=(Read-TrialCim 'Win32_OperatingSystem' @('Caption','Version','BuildNumber','OSArchitecture','TotalVisibleMemorySize'))
        cpu=(Read-TrialCim 'Win32_Processor' @('Name','NumberOfCores','NumberOfLogicalProcessors','MaxClockSpeed'))
        memoryModules=(Read-TrialCim 'Win32_PhysicalMemory' @('Capacity','Speed','ConfiguredClockSpeed','DeviceLocator'))
        video=(Read-TrialCim 'Win32_VideoController' @('Name','DriverVersion','CurrentHorizontalResolution','CurrentVerticalResolution','CurrentRefreshRate'))
        limitations='Reported Windows display values may differ from the game framebuffer; CIM clock/performance values are coarse counters, not a thermal diagnosis. GPU counters and sensors can be unavailable.'
    }
}

function Save-TrialJvmSnapshot($Tools, $Process, $Plan, [string]$Directory) {
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    foreach ($command in @('VM.version','VM.flags','VM.command_line','GC.heap_info')) {
        $null = Assert-JfrTargetProcess $Process $Plan.Java ([DateTime]::Parse($Plan.ProcessStartUtc).ToUniversalTime())
        $result = Invoke-JfrTool $Tools.Jcmd @([string]$Process.Id,$command)
        [IO.File]::WriteAllText((Join-Path $Directory ($command.Replace('.','-')+'.txt')), $result.Output, $script:Utf8)
        if ($result.Code -ne 0) { Write-Warning "Optional snapshot $command unavailable; recording can still proceed." }
    }
}

function Send-TrialCaptureSignal([string]$Stage) {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { return }
    try {
        if ($Stage -eq 'Started') { [Console]::Beep(1100,200) }
        elseif ($Stage -eq 'FramesDone') { [Console]::Beep(650,150); [Console]::Beep(650,150) }
        elseif ($Stage -eq 'Complete') { 1..3 | ForEach-Object { [Console]::Beep(1300,100) } }
        elseif ($Stage -eq 'Failed') { [Console]::Beep(350,600) }
    } catch { } # Audio is advisory; receipts/logs are authoritative.
}

function Invoke-TrialDiagnostics($Process, $Plan, $Tools, [int]$DurationSeconds = 120, [int]$DelaySeconds = 1,
                                 $FrameClient = $null, [int]$FrameSeconds = 90, [switch]$SkipWpr) {
    $root=$Plan.Logs.Directory
    $statusPath=Join-Path $root 'diagnostics.json'
    Assert-NoReparsePoint $root
    if (Test-Path -LiteralPath $statusPath) { throw 'This run already has diagnostics; do not overwrite an earlier capture.' }
    $identityUtc=[DateTime]::Parse($Plan.ProcessStartUtc).ToUniversalTime()
    $status=[ordered]@{format=1; diagnosticsVersion=3; extendedStatus='Preparing'; mode=$Plan.Mode; targetPid=$Process.Id; processStartUtc=$Plan.ProcessStartUtc; status='Preparing'; jfrFile='JFR/drive.jfr'; durationSeconds=$DurationSeconds; delaySeconds=$DelaySeconds; capFrameXSeconds=$FrameSeconds; startedUtc=$null; finishedUtc=$null; samples=0; unavailableCounters=@{}; error=$null}
    Write-TrialDiagnosticJson $statusPath $status
    $writer=$null; $wpr=$null
    $frameStatus=[ordered]@{format=1;status='Preparing';mode=$Plan.Mode;targetPid=$Process.Id;triggeredUtc=$null;request=$null;result=$null;error=$null}
    $frameStatusPath=Join-Path $root 'frame-capture.json'
    Write-TrialDiagnosticJson $frameStatusPath $frameStatus
    try {
        if (-not $FrameClient) { throw 'CapFrameX preflight is required before automatic capture.' }
        $status['capFrameXVersion']=$FrameClient.Version
        $null=Assert-JfrTargetProcess $Process $Plan.Java $identityUtc
        Write-Host 'Preparing diagnostics: one-time hardware/JVM snapshot, then WPR helper. No capture has started.'
        Write-TrialDiagnosticJson (Join-Path $root 'hardware.json') (Get-TrialHardware)
        Save-TrialJvmSnapshot $Tools $Process $Plan (Join-Path $root 'JVM')
        $nativeTelemetryIssue=Initialize-TrialNativeTelemetry
        $nvidiaTool=Get-TrialNvidiaTool
        $status['telemetryPolicy']=[ordered]@{format=2;timedCimQueries=$false;nativeApiIssue=$nativeTelemetryIssue;nvidiaMinimumIntervalSeconds=5;disableAfterCostMs=250;perCoreAndGpuEngines='WPR and CapFrameX; no CIM polling'}
        if ($SkipWpr) {
            $wpr=[pscustomobject]@{Directory=$null;Status=[pscustomobject]@{status='Unavailable';reason='ExplicitlyDisabled'}}
        } else {
            $wpr=[pscustomobject]@{Directory=$null;IntegrationSynthetic=$true;Status=[pscustomobject]@{status='Unavailable';reason='PreparationFailed';targetPid=$Process.Id;processStartUtc=$Plan.ProcessStartUtc}}
            try {
                $preparedWpr=Initialize-TrialWprCapture (Join-Path $root 'WPR') $Process $Plan
                if (-not $preparedWpr -or -not $preparedWpr.PSObject.Properties['Status']) { throw 'Missing optional recorder context.' }
                $wpr=$preparedWpr
            }
            catch {
                Stop-TrialWprHelperAfterFailure $wpr
                Set-TrialWprIntegrationFailure $wpr 'Prepare'
                Write-Warning 'Optional WPR preparation failed. JFR/CapFrameX capture continues.'
            }
        }
        Invoke-TrialOptionalWprOperation $wpr 'Receipt' $root
        Write-Host ('WPR preparation: ' + $wpr.Status.status + '. Only the recorder helper requests elevation.')
        $options=Join-Path $Plan.Cache 'options.ini'
        Assert-NoReparsePoint $options
        $readiness=Get-TrialCaptureReadiness $FrameClient $options
        Write-TrialCaptureReadiness $readiness
        Write-TrialDiagnosticJson (Join-Path $root 'capture-readiness-before.json') $readiness
        Assert-TrialCapFrameXTarget $FrameClient $Process $Plan.Java $identityUtc | Out-Null
        $status.status='WaitingForHotkey'
        Write-TrialDiagnosticJson $statusPath $status
        Write-Host ''
        Write-Host 'READY FOR CAPTURE. In the game, press Ctrl+Shift+F8 once when ready to drive.'
        Write-Host 'JFR, CapFrameX and available WPR will start automatically. A high tone means START DRIVING.'
        $trigger=Wait-TrialCaptureHotkey $Process $Plan.Java $identityUtc
        $frameStatus.triggeredUtc=$trigger.Utc
        $status['triggeredUtc']=$trigger.Utc
        Write-TrialDiagnosticJson $frameStatusPath $frameStatus
        $options=Join-Path $Plan.Cache 'options.ini'
        Assert-NoReparsePoint $options
        if (Test-Path -LiteralPath $options -PathType Leaf) { Copy-Item -LiteralPath $options -Destination (Join-Path $root 'game-options.ini') }
        $readiness=Get-TrialCaptureReadiness $FrameClient (Join-Path $root 'game-options.ini')
        Write-TrialDiagnosticJson (Join-Path $root 'capture-readiness.json') $readiness
        Write-TrialCaptureReadiness $readiness
        $null=Assert-JfrTargetProcess $Process $Plan.Java $identityUtc
        if (-not $SkipWpr) { Invoke-TrialOptionalWprOperation $wpr 'Start' $root }
        Invoke-TrialOptionalWprOperation $wpr 'Receipt' $root
        $name='PZTrial_'+$Plan.Mode+'_'+[Guid]::NewGuid().ToString('N')
        $capture=Start-JfrDrivingCapture $Tools.Jcmd $Process.Id (Join-Path $root 'JFR') $name $DurationSeconds $DelaySeconds -TargetProcess $Process -ExpectedExecutablePath $Plan.Java -ExpectedStartUtc $identityUtc
        $status.status='Arming'; $status.startedUtc=[DateTime]::UtcNow.ToString('o')
        $status['expectedEndUtc']=$capture.ExpectedEnd.ToString('o')
        Write-TrialDiagnosticJson $statusPath $status
        # Start frames only after JFR's delayed start; its attach/setup is outside the frame capture.
        Start-Sleep -Seconds ($DelaySeconds + 1)
        $null=Assert-JfrTargetProcess $Process $Plan.Java $identityUtc
        if (($capture.EarliestEnd - [DateTime]::UtcNow).TotalSeconds -lt ($FrameSeconds + 8)) {
            throw 'JFR startup took too long to safely cover the complete frame capture; no frame recording started.'
        }
        $frameStatus.request=[ordered]@{directory=(Join-Path $root 'CapFrameX');token=$name;targetPid=$Process.Id;processName='java';seconds=$FrameSeconds;preparedUtc=[DateTime]::UtcNow.ToString('o')}
        Write-TrialDiagnosticJson $frameStatusPath $frameStatus
        $frameStatus.request=Start-TrialFrameCapture $FrameClient $Process $Plan.Java $identityUtc (Join-Path $root 'CapFrameX') $FrameSeconds $name
        $frameStatus.status='Started'
        Write-TrialDiagnosticJson $frameStatusPath $frameStatus
        if ([DateTime]::Parse($frameStatus.request.acknowledgedUtc).ToUniversalTime().AddSeconds($FrameSeconds) -gt $capture.EarliestEnd) {
            throw 'CapFrameX acknowledged too late for full JFR coverage. Existing recordings are preserved; no automatic retry or stop was sent.'
        }
        $status.status='Recording'
        $status['frameRequestedUtc']=$frameStatus.request.requestedUtc
        $status['frameAcknowledgedUtc']=$frameStatus.request.acknowledgedUtc
        Write-TrialDiagnosticJson $statusPath $status
        $framesReadyAfter=[DateTime]::Parse($frameStatus.request.acknowledgedUtc).ToUniversalTime().AddSeconds($FrameSeconds)
        Send-TrialCaptureSignal 'Started'
        Write-Host 'CAPTURING. Drive now. Two low tones mean frames saved; keep the game open until three high tones / DIAGNOSTICS DONE.'
        $writer=New-Object IO.StreamWriter((Join-Path $root 'telemetry.jsonl'), $false, $script:Utf8)
        $state=@{PreviousTick=0L; PreviousCpu=0.0; Unavailable=@{}; NvidiaTool=$nvidiaTool}
        while ([DateTime]::UtcNow -lt $capture.ExpectedEnd) {
            $null=Assert-JfrTargetProcess $Process $Plan.Java $identityUtc
            $sample=Get-TrialTelemetry $Process $state (($status.samples % 2) -eq 0)
            $writer.WriteLine(($sample | ConvertTo-Json -Depth 8 -Compress))
            $writer.Flush(); $status.samples++
            if (-not $frameStatus.result -and [DateTime]::UtcNow -ge $framesReadyAfter) {
                $frames=Complete-TrialFrameCapture $frameStatus.request
                if ($frames) {
                    $frameStatus.result=$frames; $frameStatus.status='Complete'
                    Write-TrialDiagnosticJson $frameStatusPath $frameStatus
                    Send-TrialCaptureSignal 'FramesDone'
                    Write-Host 'FRAMES SAVED. You can stop driving; keep the game open while JFR finishes.'
                }
            }
            Start-Sleep -Milliseconds 1000
        }
        $writer.Dispose(); $writer=$null
        $null=Assert-JfrTargetProcess $Process $Plan.Java $identityUtc
        $status.unavailableCounters=$state.Unavailable
        # JFR may preallocate an empty file; completion is based on the acknowledged end and readable data.
        $summary=$null
        for ($attempt=0; $attempt -lt 5; $attempt++) {
            if (Test-Path -LiteralPath $capture.File -PathType Leaf) {
                $summary=Invoke-JfrTool $Tools.Jfr @('summary',$capture.File)
                if ($summary.Code -eq 0 -and $summary.Output -and (Get-Item -LiteralPath $capture.File).Length -gt 0) { break }
            }
            Start-Sleep -Seconds 1
        }
        if ($null -eq $summary -or $summary.Code -ne 0 -or -not $summary.Output -or -not (Test-Path -LiteralPath $capture.File -PathType Leaf) -or (Get-Item -LiteralPath $capture.File).Length -le 0) { throw 'JFR did not finish as a readable recording. Existing files are preserved.' }
        [IO.File]::WriteAllText((Join-Path $root 'JFR/summary.txt'),$summary.Output,$script:Utf8)
        for ($attempt=0; -not $frameStatus.result -and $attempt -lt 10; $attempt++) {
            $frames=Complete-TrialFrameCapture $frameStatus.request
            if ($frames) {
                $frameStatus.result=$frames; $frameStatus.status='Complete'
                Write-TrialDiagnosticJson $frameStatusPath $frameStatus
                break
            }
            Start-Sleep -Seconds 1
        }
        if (-not $frameStatus.result) { throw 'CapFrameX did not save a validated JSON/CSV pair for this exact game. Existing data is preserved.' }
        if ($frameStatus.result) {
            $sensorCoverage=Get-TrialRecordedSensors $frameStatus.result.Json
            Write-TrialDiagnosticJson (Join-Path $root 'sensor-coverage.json') $sensorCoverage
        }
        if (-not $SkipWpr) {
            Write-Host 'Frames and JFR saved. Finishing the owned WPR trace; keep this window open.'
            Invoke-TrialOptionalWprOperation $wpr 'Complete' $root
        }
        Invoke-TrialOptionalWprOperation $wpr 'Receipt' $root
        $status.extendedStatus='Partial'
        if ($wpr.Status.status -eq 'Complete') { $status.extendedStatus='Complete' }
        $status['wprStatus']=$wpr.Status.status
        $status.status='Complete'; $status.finishedUtc=[DateTime]::UtcNow.ToString('o')
        Write-TrialDiagnosticJson $statusPath $status
    } catch {
        $status.status='Incomplete'; $status.error=$_.Exception.Message; $status.finishedUtc=[DateTime]::UtcNow.ToString('o')
        if ($frameStatus.status -ne 'Complete') { $frameStatus.status='Incomplete'; $frameStatus.error=$status.error }
        Write-TrialDiagnosticJson $frameStatusPath $frameStatus
        Send-TrialCaptureSignal 'Failed'
        Write-TrialDiagnosticJson $statusPath $status
        Write-Warning ('DIAGNOSTICS INCOMPLETE: '+$status.error+' Files are preserved; exit normally and send the logs.')
    } finally {
        if ($null -ne $writer) { $writer.Dispose() }
        if ($null -ne $wpr) {
            try {
                if (-not $SkipWpr) { Invoke-TrialOptionalWprOperation $wpr 'Stop' $root }
                Invoke-TrialOptionalWprOperation $wpr 'Receipt' $root
                $status['wprStatus']=$wpr.Status.status
                $status['wprIntegrationFailures']=@(Get-TrialWprIntegrationFailures $wpr)
                if ($status.status -eq 'Complete' -and $wpr.Status.status -ne 'Complete') { $status.extendedStatus='Partial' }
            } catch {
                $status['wprStatus']='Incomplete'; $status['wprIntegrationFailures']=@('Finalization')
                if ($status.status -eq 'Complete') { $status.extendedStatus='Partial' }
                Write-Warning 'Optional WPR finalization failed. JFR/frames are preserved.'
            }
            try { Write-TrialDiagnosticJson $statusPath $status }
            catch { Write-Warning 'Final WPR summary could not be saved. Preserve this run and helper receipt.' }
        }
    }
    if ($status.status -eq 'Complete') {
        Send-TrialCaptureSignal 'Complete'
        Write-Host ('DIAGNOSTICS DONE. Frames/JFR saved; WPR: ' + $wpr.Status.status + '. Exit normally, then run Collect-results.cmd after both modes.')
        if ($status.extendedStatus -ne 'Complete') { Write-Warning 'WPR evidence is partial/unavailable. Keep this run; do not repeat before analysis.' }
    }
    return [pscustomobject]$status
}
