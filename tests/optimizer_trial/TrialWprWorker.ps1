param([string]$Directory,[string]$ControlHash)
# Elevated recorder only. The game and launcher retain their original token.
. (Join-Path $PSScriptRoot 'TrialWpr.ps1')
function Invoke-TrialWprCommand([string]$Tool,[string[]]$Arguments,[int]$TimeoutSeconds=15) {
    $process=$null; $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=$Tool
        $start.Arguments=($Arguments | ForEach-Object { if ($_ -match '["\r\n]') { throw 'Invalid recorder argument.' }; '"'+$_+'"' }) -join ' '
        $start.UseShellExecute=$false; $start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process; $process.StartInfo=$start
        if (-not $process.Start()) { throw 'Recorder did not start.' }
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds*1000)) {
            # Kill only this command client, never another recorder or game.
            try { $process.Kill() } catch { }
            return [pscustomobject]@{exitCode=$null;timedOut=$true;output='CommandTimeout';elapsedMs=[int]$watch.ElapsedMilliseconds}
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),1000)) { throw 'Recorder output timeout.' }
        $output=$stdout.Result+"`n"+$stderr.Result
        # Eight bounded command results plus JSON escaping fit the 512 KiB
        # receipt cap even for localized output. Never derive identities from
        # incomplete output (a cut session name could falsely query as absent).
        $truncated=($output.Length -gt 8192)
        if ($truncated) { $output=$output.Substring(0,8192) }
        return [pscustomobject]@{exitCode=$process.ExitCode;timedOut=$false;output=$output;outputTruncated=$truncated;elapsedMs=[int]$watch.ElapsedMilliseconds}
    } catch { return [pscustomobject]@{exitCode=$null;timedOut=$false;output='CommandFailed';elapsedMs=[int]$watch.ElapsedMilliseconds} }
    finally { if ($process) { $process.Dispose() } }
}
function Test-TrialWprIdentity([int]$ProcessId,[string]$Executable,$StartUtc) {
    try {
        $process=Get-Process -Id $ProcessId -ErrorAction Stop
        return (-not $process.HasExited -and [string]::Equals([IO.Path]::GetFullPath($process.Path),[IO.Path]::GetFullPath($Executable),[StringComparison]::OrdinalIgnoreCase) -and
            $process.StartTime.ToUniversalTime().Ticks -eq (ConvertTo-TrialWprUtc $StartUtc).Ticks)
    } catch { return $false }
}
function Test-TrialWprElevated {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-TrialWprTrace([string]$Path) {
    Assert-TrialWprPath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -le 512) { return $false }
    # OpenTrace reads/validates EVENT_TRACE_LOGFILE's ETL header without decoding
    # events. Its first member is LogFileName on both x86/x64. Reserve a zeroed
    # block larger than the structure; no callbacks or ProcessTrace are used.
    # https://learn.microsoft.com/windows/win32/api/evntrace/nf-evntrace-opentracew
    if (-not ('PZTrialEtw.Header' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PZTrialEtw {
 public static class Header {
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="OpenTraceW", SetLastError=true)]
  static extern ulong OpenTrace(IntPtr logfile);
  [DllImport("advapi32.dll")] static extern uint CloseTrace(ulong handle);
  public static bool Valid(string path) {
   IntPtr name=Marshal.StringToHGlobalUni(path), block=Marshal.AllocHGlobal(4096);
   try {
    Marshal.Copy(new byte[4096],0,block,4096); Marshal.WriteIntPtr(block,name);
    ulong handle=OpenTrace(block);
    if (handle==UInt64.MaxValue) return false;
    return CloseTrace(handle)==0;
   } finally { Marshal.FreeHGlobal(block); Marshal.FreeHGlobal(name); }
  }
 }
}
'@ -ErrorAction Stop
    }
    return [PZTrialEtw.Header]::Valid($Path)
}
function Assert-TrialWprControl([string]$Root,[string]$Hash) {
    Assert-TrialWprPath $Root
    if ([IO.Path]::GetFileName($Root) -notmatch '^[a-f0-9]{32}$' -or $Hash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid owned recorder directory/hash.' }
    $path=Join-Path $Root 'control.json'
    Assert-TrialWprPath $path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Hash) { throw 'Recorder control identity changed.' }
    $config=Read-TrialWprJson $path
    if ($config.format -ne 1 -or $config.captureId -ne [IO.Path]::GetFileName($Root) -or
        $config.captureSeconds -lt 30 -or $config.captureSeconds -gt 240 -or $config.prepareSeconds -ne 900 -or
        $config.profileSha256 -notmatch '^[a-fA-F0-9]{64}$' -or $config.maximumTempBytes -ne 2147483648 -or $config.targetPid -le 0 -or $config.parentPid -le 0) { throw 'Invalid recorder control.' }
    return $config
}
function Read-TrialWprSignal([string]$Root,[string]$Action,$Config) {
    $signal=Read-TrialWprJson (Join-Path $Root ($Action+'.request.json'))
    if (-not $signal) { return $null }
    if ($signal.captureId -ne $Config.captureId -or $signal.action -ne $Action -or $signal.targetPid -ne $Config.targetPid) { throw 'Recorder signal identity changed.' }
    $requested=(ConvertTo-TrialWprUtc $signal.requestedUtc)
    if ($requested -gt [DateTime]::UtcNow.AddSeconds(5) -or $requested -lt [DateTime]::UtcNow.AddMinutes(-20)) { throw 'Recorder signal timestamp invalid.' }
    return $signal
}
function Get-TrialWprTempBytes([string]$Root) {
    Assert-TrialWprPath $Root
    $total=0L
    # WPR receives this fixed, precreated directory. Walk only non-reparse entries.
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop)) {
        Assert-TrialWprPath $item.FullName
        if ($item.PSIsContainer) { $total+=Get-TrialWprTempBytes $item.FullName } else { $total+=$item.Length }
    }
    return $total
}
function Test-TrialWprNamedInstanceHelp($Result) {
    # Only a completed, successful help query can advertise the option. Match
    # an option declaration, not an error sentence mentioning "instancename".
    # Descriptions may be localized; command tokens and their syntax are not.
    return ($null -ne $Result -and -not $Result.timedOut -and $null -ne $Result.exitCode -and
        $Result.exitCode -eq 0 -and $Result.output -match '(?im)^[\t ]*-instancename(?:[\t ]+(?:[-:]|<[^>\r\n]+>)(?:[\t ]|$)|[\t ]*\r?$)')
}
function Get-TrialWprOwnedCollectors($Result,[string]$Instance) {
    if ($Instance -notmatch '^PZTrial_[a-f0-9]{32}$' -or $null -eq $Result -or $Result.timedOut -or $Result.outputTruncated -or $null -eq $Result.exitCode -or $Result.exitCode -ne 0) { return @() }
    # Labels may be localized. Accept only whole, bounded names in the exact
    # WPR namespace observed for this owned instance, never a substring/name
    # inferred from a failed command or another instance's output.
    $pattern='(?m)^[\t ]*[^:\r\n]+:[\t ]*(WPR_initiated_'+[regex]::Escape($Instance)+'_[A-Za-z0-9][A-Za-z0-9 _-]{0,127})[\t ]*\r?$'
    return @([regex]::Matches([string]$Result.output,$pattern) | ForEach-Object { $_.Groups[1].Value.TrimEnd() } | Select-Object -Unique)
}
function Get-TrialWprCollectorQueryCode([string]$Name) {
    # Read-only query of one exact, previously observed owned ETW collector.
    # Never StopTrace/ControlTrace STOP, global enumeration or wildcard lookup.
    # https://learn.microsoft.com/windows/win32/api/evntrace/nf-evntrace-controltracew
    if (-not ('PZTrialEtw.Collector' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PZTrialEtw {
 public static class Collector {
  [StructLayout(LayoutKind.Sequential)] struct Wnode {
   public uint BufferSize, ProviderId;
   public ulong HistoricalContext;
   public long TimeStamp;
   public Guid Guid;
   public uint ClientContext, Flags;
  }
  [StructLayout(LayoutKind.Sequential)] struct Properties {
   public Wnode Wnode;
   public uint BufferSize, MinimumBuffers, MaximumBuffers, MaximumFileSize;
   public uint LogFileMode, FlushTimer, EnableFlags;
   public int AgeLimit;
   public uint NumberOfBuffers, FreeBuffers, EventsLost, BuffersWritten, LogBuffersLost, RealTimeBuffersLost;
   public IntPtr LoggerThreadId;
   public uint LogFileNameOffset, LoggerNameOffset;
  }
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="ControlTraceW")]
  static extern uint ControlTrace(ulong handle, string name, IntPtr properties, uint controlCode);
  public static uint Query(string name) {
   int size=Marshal.SizeOf(typeof(Properties)), length=size+4096;
   IntPtr block=Marshal.AllocHGlobal(length);
   try {
    Marshal.Copy(new byte[length],0,block,length);
    Properties p=new Properties(); p.Wnode.BufferSize=(uint)length;
    p.LoggerNameOffset=(uint)size; p.LogFileNameOffset=(uint)(size+2048);
    Marshal.StructureToPtr(p,block,false);
    return ControlTrace(0,name,block,0); // EVENT_TRACE_CONTROL_QUERY
   } finally { Marshal.FreeHGlobal(block); }
  }
 }
}
'@ -ErrorAction Stop
    }
    return [PZTrialEtw.Collector]::Query($Name)
}
function Get-TrialWprCollectorState([string[]]$Names,[string]$Instance) {
    $queries=@(); $state='Absent'
    if (-not $Names -or $Instance -notmatch '^PZTrial_[a-f0-9]{32}$') { return [pscustomobject]@{state='Unknown';queries=@()} }
    foreach ($name in $Names) {
        if ($name -cnotmatch ('^WPR_initiated_'+[regex]::Escape($Instance)+'_[A-Za-z0-9][A-Za-z0-9 _-]{0,127}$')) { return [pscustomobject]@{state='Unknown';queries=@()} }
    }
    foreach ($name in $Names) {
        $code=$null
        try { $code=Get-TrialWprCollectorQueryCode $name } catch { }
        $queries+=@([ordered]@{name=$name;queryCode=$code})
        # ERROR_WMI_INSTANCE_NOT_FOUND=4201 means this exact session is absent.
        # Access denied, malformed output, command failure and timeout are unknown.
        if ($null -ne $code -and $code -eq 0) { $state='Active' }
        elseif ($null -eq $code -or $code -ne 4201) { if ($state -ne 'Active') { $state='Unknown' } }
    }
    return [pscustomobject]@{state=$state;queries=$queries}
}
function Test-TrialWprNoProfiles($Result) {
    # Captured system WPR 10.0.19041 HRESULT 0xc5583000. Language independent.
    # This proves only WPR's profile state, never absence of orphan ETW collectors.
    return ($null -ne $Result -and -not $Result.timedOut -and $null -ne $Result.exitCode -and $Result.exitCode -eq -984076288)
}
function Invoke-TrialWprWorker([string]$Root,[string]$Hash) {
    $ErrorActionPreference='Stop'
    $config=Assert-TrialWprControl $Root $Hash
    $statusPath=Join-Path $Root 'wpr-status.json'
    $status=Read-TrialWprJson $statusPath
    if ($status.captureId -ne $config.captureId -or $status.targetPid -ne $config.targetPid -or $status.processStartUtc -ne $config.processStartUtc -or $status.status -ne 'Requested' -or $status.instanceName -ne ('PZTrial_'+$config.captureId)) { throw 'Recorder receipt identity changed.' }
    $helper=Get-Process -Id $PID
    $status.helperPid=$PID; $status.helperStartUtc=$helper.StartTime.ToUniversalTime().ToString('o')
    $status | Add-Member -NotePropertyName evidence -NotePropertyValue @()
    $status | Add-Member -NotePropertyName maximumCaptureSeconds -NotePropertyValue $config.captureSeconds
    $status | Add-Member -NotePropertyName maximumTempBytes -NotePropertyValue $config.maximumTempBytes
    $status | Add-Member -NotePropertyName stopCause -NotePropertyValue $null
    $status | Add-Member -NotePropertyName saveFailure -NotePropertyValue $null
    $status | Add-Member -NotePropertyName cleanupState -NotePropertyValue 'NotRequired'
    $status | Add-Member -NotePropertyName profileState -NotePropertyValue 'Unknown'
    $status | Add-Member -NotePropertyName observedTempBytes -NotePropertyValue 0
    $status | Add-Member -NotePropertyName profileSha256 -NotePropertyValue $config.profileSha256
    $status | Add-Member -NotePropertyName lostEvents -NotePropertyValue $null
    $status | Add-Member -NotePropertyName elapsedMs -NotePropertyValue 0
    $watch=[Diagnostics.Stopwatch]::StartNew(); $closed=$false; $attempted=$false; $started=$false; $tool=$null; $ownedCollectors=@()
    $instance=$status.instanceName; $trace=Join-Path $Root 'drive.etl'; $temp=Join-Path $Root 'temp'
    try {
        if (-not (Test-TrialWprElevated)) { $status.reason='HelperNotElevated'; return }
        $tool=Get-TrialWprTool
        if (-not $tool) { $status.reason='WprUnavailable'; return }
        # Test support BEFORE any session operation; no default-instance fallback.
        $advanced=Invoke-TrialWprCommand $tool @('-help','advanced')
        $status.evidence+=@([ordered]@{stage='NamedInstanceSupport';result=$advanced})
        if (-not (Test-TrialWprNamedInstanceHelp $advanced)) {
            # The captured 10.0.19041 CoreSystem build returns nonzero for
            # "advanced" with general help including -instancename. Retry the documented
            # read-only general-help form, never a session operation as a probe.
            $general=Invoke-TrialWprCommand $tool @('-help')
            $status.evidence+=@([ordered]@{stage='NamedInstanceSupportGeneralHelp';result=$general})
            if (-not (Test-TrialWprNamedInstanceHelp $general)) { $status.reason='NamedInstancesUnsupported'; return }
        }
        $profile=Get-TrialWprProfile
        if ($profile.Sha256 -ne $config.profileSha256) { $status.reason='ProfileIdentityChanged'; return }
        $details=Invoke-TrialWprCommand $tool @('-profiledetails',$profile.Selector,'-filemode')
        $status.evidence+=@([ordered]@{stage='ProfileDetails';result=$details})
        if ($null -eq $details.exitCode -or $details.exitCode -ne 0 -or $details.timedOut -or $details.outputTruncated) { $status.reason='ProfilesUnavailable'; return }
        foreach ($keyword in @('CSwitch','ReadyThread','SampledProfile','DPC','Interrupt','DiskIO','HardFaults')) {
            if ($details.output -notmatch ('(?i)\b'+$keyword+'\b')) { $status.reason='RequiredProfileCoverageUnavailable'; return }
        }
        foreach ($provider in @('(?:Microsoft-Windows-DxgKrnl|802ec45a-1e99-4b83-9920-87c98277ba9d)','(?:Microsoft-Windows-DXGI|ca11c036-0102-4a2d-a6ad-f03cfed5d3c9)','(?:Microsoft-Windows-Dwm-Core|9e9bba3c-2e38-40cb-99f4-9e8281425164)')) {
            if ($details.output -notmatch ('(?i)(?<![A-Za-z0-9-])'+$provider+'(?![A-Za-z0-9-])')) { $status.reason='RequiredGraphicsCoverageUnavailable'; return }
        }
        [IO.Directory]::CreateDirectory($temp) | Out-Null
        Assert-TrialWprPath $temp
        $status.profiles=@('PZTrial.light')
        $status.status='Ready'; Write-TrialWprJson $statusPath $status
        $prepared=[DateTime]::UtcNow
        while ($true) {
            $null=Assert-TrialWprControl $Root $Hash
            if (-not (Test-TrialWprIdentity $config.parentPid $config.parentExecutable $config.parentStartUtc)) { $status.reason='ParentExitedBeforeCapture'; return }
            if (-not (Test-TrialWprIdentity $config.targetPid $config.expectedExecutable $config.processStartUtc)) { $status.reason='TargetIdentityLostBeforeCapture'; return }
            if (Read-TrialWprSignal $Root 'stop' $config) { $status.reason='StoppedBeforeCapture'; return }
            $signal=Read-TrialWprSignal $Root 'start' $config
            if ($signal) { $status.startRequestedUtc=$signal.requestedUtc; break }
            if (([DateTime]::UtcNow-$prepared).TotalSeconds -ge $config.prepareSeconds) { $status.reason='PreparationWatchdog'; return }
            Start-Sleep -Milliseconds 100
        }
        if ((Get-TrialWprProfile).Sha256 -ne $config.profileSha256) { $status.reason='ProfileIdentityChanged'; return }
        $attempted=$true
        $start=Invoke-TrialWprCommand $tool @('-start',$profile.Selector,'-filemode','-recordtempto',$temp,'-instancename',$instance) 15
        $status.evidence+=@([ordered]@{stage='Start';result=$start})
        if ($null -eq $start.exitCode -or $start.exitCode -ne 0 -or $start.timedOut) { $status.reason='StartFailedOrTimedOut'; return }
        $started=$true
        $status.startedUtc=[DateTime]::UtcNow.ToString('o'); $status.status='Recording'
        Write-TrialWprJson $statusPath $status
        while ($true) {
            $null=Assert-TrialWprControl $Root $Hash
            $signal=Read-TrialWprSignal $Root 'stop' $config
            if ($signal) { $status.stopRequestedUtc=$signal.requestedUtc; $status.stopCause='Requested'; break }
            if (-not (Test-TrialWprIdentity $config.parentPid $config.parentExecutable $config.parentStartUtc)) { $status.stopCause='ParentExited'; break }
            if (-not (Test-TrialWprIdentity $config.targetPid $config.expectedExecutable $config.processStartUtc)) { $status.stopCause='TargetIdentityLost'; break }
            if (([DateTime]::UtcNow-(ConvertTo-TrialWprUtc $status.startedUtc)).TotalSeconds -ge $config.captureSeconds) { $status.stopCause='CaptureWatchdog'; break }
            if (($status.observedTempBytes=(Get-TrialWprTempBytes $temp)) -ge $config.maximumTempBytes) { $status.stopCause='SizeWatchdog'; break }
            Start-Sleep -Milliseconds 250
        }
    } catch { $status.reason='RecorderValidationOrCommandFailed'; if ($attempted) { $status.stopCause='ValidationFailure' } }
    finally {
        # A start command can time out AFTER the session started. Always attempt
        # to save only our unpredictable named instance, never -cancel/global stop.
        if ($attempted -and $tool) {
            try {
                Assert-TrialWprPath $Root; Assert-TrialWprPath $trace
                $before=Invoke-TrialWprCommand $tool @('-status','collectors','-details','-instancename',$instance) 8
                $status.evidence+=@([ordered]@{stage='CollectorsBeforeStop';result=$before})
                $ownedCollectors=@(Get-TrialWprOwnedCollectors $before $instance)
                if (-not $status.stopRequestedUtc) { $status.stopRequestedUtc=[DateTime]::UtcNow.ToString('o') }
                $stop=Invoke-TrialWprCommand $tool @('-stop',$trace,'-skipPdbGen','-instancename',$instance) 80
                $status.evidence+=@([ordered]@{stage='Stop';result=$stop})
                if ($stop.exitCode -eq 0 -and -not $stop.timedOut) {
                    $closed=$true
                    $status.profileState='Absent'; $status.cleanupState='Stopped'
                    $status.stoppedUtc=[DateTime]::UtcNow.ToString('o')
                    if (Test-TrialWprTrace $trace) {
                        $status.headerValidated=$true
                        $status.traceBytes=(Get-Item -LiteralPath $trace).Length
                        $status.traceSha256=(Get-FileHash -LiteralPath $trace -Algorithm SHA256).Hash.ToLowerInvariant()
                        $status.status='Complete'
                        if (-not $started -or $status.stopCause -in @('ParentExited','TargetIdentityLost','ValidationFailure','SizeWatchdog','CaptureWatchdog')) { $status.status='Incomplete' }
                    } else { $status.status='Incomplete'; $status.reason='TraceHeaderInvalid' }
                } else {
                    $status.status='Incomplete'; $status.reason='OwnedSessionSaveFailed'; $status.saveFailure='OwnedSessionSaveFailed'
                }
            } catch { $status.status='Incomplete'; $status.reason='OwnedSessionSaveOrValidationFailed'; $status.saveFailure='OwnedSessionSaveOrValidationFailed' }
        } else { $status.status='Unavailable' }
        if ($attempted -and $tool -and -not $closed) {
            # Saving failed/timed out (including invalid output-path validation).
            # Preserve partial files and cancel only our exact owned instance.
            $cleanup=Invoke-TrialWprCommand $tool @('-cancel','-instancename',$instance) 8
            $status.evidence+=@([ordered]@{stage='OwnedSessionCleanup';result=$cleanup})
            if (Test-TrialWprNoProfiles $cleanup) { $status.profileState='Absent' }
            elseif ($null -ne $cleanup.exitCode -and $cleanup.exitCode -eq 0 -and -not $cleanup.timedOut) { $status.profileState='Absent' }
            $after=Invoke-TrialWprCommand $tool @('-status','collectors','-details','-instancename',$instance) 8
            $status.evidence+=@([ordered]@{stage='CollectorsAfterCleanup';result=$after})
            if (Test-TrialWprNoProfiles $after) { $status.profileState='Absent' }
            $afterNames=@(Get-TrialWprOwnedCollectors $after $instance)
            if ($afterNames.Count -gt 0) { $ownedCollectors=@(@($ownedCollectors)+@($afterNames) | Select-Object -Unique); $status.profileState='Active' }
            $verified=Get-TrialWprCollectorState $ownedCollectors $instance
            $status.cleanupState=$verified.state
            $status.evidence+=@([ordered]@{stage='OwnedCollectorsAfterCleanup';result=$verified})
        }
        $status.elapsedMs=[int]$watch.ElapsedMilliseconds
        Write-TrialWprJson $statusPath $status
    }
    return $status
}
if ($MyInvocation.InvocationName -ne '.') { $null=Invoke-TrialWprWorker $Directory $ControlHash }
