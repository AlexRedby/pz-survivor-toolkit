param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'WprChecks'))
# No game, Java, CapFrameX, driver or system settings are changed by this probe.
. (Join-Path $PSScriptRoot 'TrialWpr.ps1')
function Write-TrialWprInstallHint {
    Write-Host 'Install the Windows Performance Toolkit component of Windows ADK (build 19650 or later), then rerun Test-WPR.cmd.'
    Write-Host 'Use the standard installation directory; keep the complete Toolkit installation, not a copied wpr.exe.'
    Write-Host 'Official download and supported Windows versions: https://learn.microsoft.com/windows-hardware/get-started/adk-install'
    Write-Host 'Known stop error 0x80010106: https://devblogs.microsoft.com/performance-diagnostics/wpr-start-and-stop-commands/'
}
function Invoke-TrialWprSelfTest([string]$Directory,[int]$Seconds=10) {
    $ErrorActionPreference='Stop'
    if ($Seconds -lt 5 -or $Seconds -gt 20) { throw 'Self-test duration must be between 5 and 20 seconds.' }
    Assert-TrialWprPath $Directory
    $Directory=[IO.Path]::GetFullPath($Directory)
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $run=Join-Path $Directory ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($run) | Out-Null
    $result=[ordered]@{format=1;scope='RecorderSelfTest';status='Failed';reason=$null;error=$null;seconds=$Seconds;
        startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null;directory=$run;receipt=$null;traceVerified=$false;
        limitation='No game benchmark. A saved ETL verifies this recorder path, not overhead, lost-event completeness or a fix for game stutters.'}
    $context=$null
    try {
        $process=Get-Process -Id $PID -ErrorAction Stop
        $plan=[pscustomobject]@{Java=$process.Path;ProcessStartUtc=$process.StartTime.ToUniversalTime().ToString('o');WprDurationSeconds=30}
        Write-Host 'Checking installed WPR. Only the recorder helper requests administrator access.'
        $context=Initialize-TrialWprOwnedCapture (Join-Path $run 'WPR') $process $plan
        $state=Get-TrialWprStatus $context
        if ($state.status -ne 'Ready') { $result.reason=$state.reason }
        else {
            Write-Host ('WPR: '+$state.tool.Source+' '+$state.tool.Version+' ('+$state.tool.Path+')')
            Send-TrialWprRequest $context 'start'; $context.StartSent=$true
            $state=Wait-TrialWprState $context @('Recording','Unavailable','Incomplete','Complete') 20
            if ($state.status -ne 'Recording') { $result.reason='SelfTestStartFailed' }
            else {
                Write-Host ('Recording a '+$Seconds+'-second check; no game run is needed.')
                Start-Sleep -Seconds $Seconds
                Write-Host 'Saving and validating the ETL. This can take longer than recording.'
            }
        }
    } catch { $result.error=$_.Exception.Message; $result.reason='SelfTestFailed' }
    finally {
        if ($context) {
            try {
                $state=Complete-TrialWprCapture $context
                $result.receipt=$state
                if (-not $result.reason) { $result.reason=$state.reason }
                if ($state.status -eq 'Complete' -and $state.headerValidated -and $state.cleanupState -eq 'Absent' -and -not $result.error -and -not $result.reason) {
                    $trace=Join-Path $context.Directory 'drive.etl'; Assert-TrialWprPath $trace
                    if ((Get-Item -LiteralPath $trace).Length -eq $state.traceBytes -and $state.traceBytes -gt 512 -and
                        (Get-FileHash -LiteralPath $trace -Algorithm SHA256).Hash -eq $state.traceSha256) {
                        $result.traceVerified=$true; $result.status='Passed'
                    } else { $result.reason='SelfTestTraceIntegrityFailed' }
                }
            } catch { $result.error=$_.Exception.Message; $result.reason='SelfTestCompletionFailed' }
        }
        if ($result.status -ne 'Passed' -and -not $result.reason) { $result.reason='SelfTestIncomplete' }
        $result.finishedUtc=[DateTime]::UtcNow.ToString('o')
        Write-TrialWprJson (Join-Path $run 'result.json') $result
        # Small diagnostic attachment; leave the potentially large ETL in place.
        # Preserve every raw helper receipt/command result and selected tool identity.
        $files=@(Get-ChildItem -LiteralPath $run -Recurse -File | Where-Object { $_.Extension -eq '.json' })
        foreach ($file in $files) { Assert-TrialWprPath $file.FullName }
        Compress-Archive -LiteralPath @($files | ForEach-Object FullName) -DestinationPath (Join-Path $run 'WPR-check-result.zip') -ErrorAction Stop
    }
    Write-Host ('Result: '+$result.status+' '+$result.reason)
    Write-Host ('Send this small report: '+(Join-Path $run 'WPR-check-result.zip'))
    if ($result.status -ne 'Passed') {
        if ($result.reason -in @('WprUpgradeRequired','WprUnavailable')) { Write-TrialWprInstallHint }
        Write-Host 'Keep this result folder. Do not repeat a driving benchmark to troubleshoot WPR.'
    }
    return [pscustomobject]$result
}
if ($MyInvocation.InvocationName -ne '.') {
    try { $result=Invoke-TrialWprSelfTest $OutputDirectory; if ($result.status -ne 'Passed') { exit 1 } }
    catch { Write-Host ('WPR check failed: '+$_.Exception.Message); exit 1 }
}
