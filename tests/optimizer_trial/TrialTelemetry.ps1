# Cheap, read-only process/system snapshots. No CIM query runs inside the capture.
# Native API contracts: Microsoft GlobalMemoryStatusEx, GetProcessIoCounters and
# GetProcessMemoryInfo/PROCESS_MEMORY_COUNTERS_EX. Page faults are NOT disk reads.
function Initialize-TrialNativeTelemetry {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return 'NotWindows' }
    try {
        if (-not ('PZTrialTelemetry.Native' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace PZTrialTelemetry {
    [StructLayout(LayoutKind.Sequential)] public struct Memory {
        public uint Length, Load;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile;
        public ulong TotalVirtual, AvailableVirtual, AvailableExtended;
    }
    [StructLayout(LayoutKind.Sequential)] public struct Io {
        public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ProcessMemory {
        public uint Size, PageFaultCount;
        public UIntPtr PeakWorkingSet, WorkingSet, PeakPagedPool, PagedPool;
        public UIntPtr PeakNonPagedPool, NonPagedPool, PagefileUsage, PeakPagefileUsage, PrivateUsage;
    }
    public static class Native {
        [DllImport("kernel32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GlobalMemoryStatusEx(ref Memory value);
        [DllImport("kernel32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetProcessIoCounters(IntPtr handle, out Io value);
        [DllImport("psapi.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetProcessMemoryInfo(IntPtr handle, ref ProcessMemory value, uint size);
        public static Memory ReadMemory() {
            Memory value=new Memory(); value.Length=(uint)Marshal.SizeOf(typeof(Memory));
            if (!GlobalMemoryStatusEx(ref value)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return value;
        }
        public static Io ReadIo(IntPtr handle) {
            Io value; if (!GetProcessIoCounters(handle, out value)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return value;
        }
        public static uint ReadFaults(IntPtr handle) {
            ProcessMemory value=new ProcessMemory(); value.Size=(uint)Marshal.SizeOf(typeof(ProcessMemory));
            if (!GetProcessMemoryInfo(handle, ref value, value.Size)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return value.PageFaultCount;
        }
    }
}
'@ -ErrorAction Stop
        }
        return $null
    } catch { return 'NativeApiInitializationFailed' }
}

function Read-TrialNativeCounter([string]$Kind, $Process) {
    try {
        if (-not ('PZTrialTelemetry.Native' -as [type])) { throw 'Native API unavailable' }
        $data=$null
        if ($Kind -eq 'systemMemory') {
            $m=[PZTrialTelemetry.Native]::ReadMemory()
            # TotalPageFile is the commit limit available to this process, not disk paging activity.
            $data=[ordered]@{physicalTotalBytes=$m.TotalPhysical;physicalAvailableBytes=$m.AvailablePhysical;memoryLoadPercent=$m.Load;processCommitLimitBytes=$m.TotalPageFile;processCommitAvailableBytes=$m.AvailablePageFile}
        } elseif ($Kind -eq 'io') {
            $io=[PZTrialTelemetry.Native]::ReadIo($Process.Handle)
            $data=[ordered]@{readBytes=$io.ReadBytes;writeBytes=$io.WriteBytes;otherBytes=$io.OtherBytes;readOperations=$io.ReadOperations;writeOperations=$io.WriteOperations}
        } elseif ($Kind -eq 'pageFaults') {
            $data=[ordered]@{total=[PZTrialTelemetry.Native]::ReadFaults($Process.Handle);meaning='Soft and hard faults combined; not disk paging proof'}
        } else { throw 'Unknown counter' }
        return [pscustomobject]@{status='Available';source='Win32';data=$data;error=$null}
    } catch { return [pscustomobject]@{status='Unavailable';source='Win32';data=$null;error='NativeCounterUnavailable'} }
}

function Get-TrialTelemetry($Process, $State, [bool]$IncludeSystem) {
    $started=[Diagnostics.Stopwatch]::GetTimestamp()
    $Process.Refresh()
    $now=[Diagnostics.Stopwatch]::GetTimestamp()
    $cpu=$Process.TotalProcessorTime.TotalSeconds
    $elapsed=($now-$State.PreviousTick)/[double][Diagnostics.Stopwatch]::Frequency
    $cores=$null
    if ($State.PreviousTick -gt 0 -and $elapsed -gt 0) { $cores=($cpu-$State.PreviousCpu)/$elapsed }
    $State.PreviousTick=$now; $State.PreviousCpu=$cpu
    $sample=[ordered]@{
        format=2;utc=[DateTime]::UtcNow.ToString('o');targetPid=$Process.Id
        process=[ordered]@{cpuSeconds=$cpu;cpuCoresUsed=$cores;workingSetBytes=$Process.WorkingSet64;privateBytes=$Process.PrivateMemorySize64;threads=$Process.Threads.Count;handles=$Process.HandleCount}
        counters=[ordered]@{}
    }
    if ($IncludeSystem) {
        foreach ($kind in @('systemMemory','io','pageFaults')) {
            if ($State.Unavailable.ContainsKey($kind)) { continue }
            $timer=[Diagnostics.Stopwatch]::StartNew()
            $value=Read-TrialNativeCounter $kind $Process
            $timer.Stop()
            $value | Add-Member -NotePropertyName elapsedMs -NotePropertyValue $timer.Elapsed.TotalMilliseconds -Force
            $sample.counters[$kind]=$value
            if ($value.status -ne 'Available') { $State.Unavailable[$kind]=$value.error }
            elseif ($timer.Elapsed.TotalMilliseconds -gt 250) { $State.Unavailable[$kind]='DisabledAfterSlowSample' }
        }
        # WPR/CX own per-core and GPU engine detail; no duplicate WMI providers.
        # NVIDIA is a fallback at most once per 5s, disabled after one slow call.
        $utc=[DateTime]::UtcNow
        if (-not $State.Unavailable.ContainsKey('nvidia') -and
            (-not $State.ContainsKey('NextNvidiaUtc') -or $utc -ge $State.NextNvidiaUtc)) {
            $nvidia=Read-TrialNvidiaSample $State.NvidiaTool
            $sample.counters['nvidia']=$nvidia
            $State.NextNvidiaUtc=$utc.AddSeconds(5)
            if ($nvidia.status -ne 'Available') { $State.Unavailable['nvidia']=$nvidia.unavailableReason }
            elseif ($nvidia.elapsedMs -gt 250) { $State.Unavailable['nvidia']='DisabledAfterSlowSample' }
        }
    }
    $sample['sampleCostMs']=([Diagnostics.Stopwatch]::GetTimestamp()-$started)*1000.0/[Diagnostics.Stopwatch]::Frequency
    return $sample
}
