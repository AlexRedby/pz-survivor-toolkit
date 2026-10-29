# Launch-time, read-only Windows storage diagnostics. Windows PowerShell 5.1.
# Public entry point: Get-TrialStorageReport -Paths @(@{Role='Game';Id='game';Path=$game}, ...)
$script:TrialStorageHelperPath=$PSCommandPath
# Keep upstream/selected-source and actual-runtime records separate in the caller.
# No object IDs, volume GUIDs, serial numbers, CIM objects or exception text are returned.
# Microsoft contracts: GetFinalPathNameByHandleW, CreateFileW directory handles,
# IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS and VOLUME_DISK_EXTENTS; Get-Disk -Number.
# https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew
# https://learn.microsoft.com/windows/win32/fileio/naming-a-volume
# https://learn.microsoft.com/windows/win32/api/winioctl/ni-winioctl-ioctl_volume_get_volume_disk_extents
# https://learn.microsoft.com/powershell/module/storage/get-disk

function Get-TrialStorageProperty($Value, [string]$Name) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $null
    }
    $property=$Value.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Protect-TrialStoragePath([string]$Path) {
    if (-not $Path) { return $null }
    # Windows accepts mixed separators. Compare normalized forms before any projection.
    $comparisonPath=$Path.Replace('/','\')
    if ($comparisonPath.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase) -or
        ($comparisonPath.StartsWith('\\') -and -not $comparisonPath.StartsWith('\\?\'))) { return '<network-path>' }
    if ($comparisonPath.StartsWith('\\?\Volume{', [StringComparison]::OrdinalIgnoreCase)) { return '<volume-path>' }
    if ($comparisonPath.StartsWith('\\?\')) { $Path=$Path.Substring(4); $comparisonPath=$comparisonPath.Substring(4) }
    $prefixes=@($env:USERPROFILE, [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile))
    foreach ($prefix in $prefixes) {
        if (-not $prefix) { continue }
        $homePrefix=$prefix.TrimEnd([char[]]'\/').Replace('/','\')
        if ($comparisonPath.Equals($homePrefix, [StringComparison]::OrdinalIgnoreCase)) { return '%USERPROFILE%' }
        if ($comparisonPath.StartsWith($homePrefix+'\', [StringComparison]::OrdinalIgnoreCase)) { return '%USERPROFILE%'+$Path.Substring($homePrefix.Length) }
    }
    return $Path
}

function Initialize-TrialStorageNative {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return 'NotWindows' }
    try {
        if (-not ('PZTrialStorage.Native' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;
namespace PZTrialStorage {
    [StructLayout(LayoutKind.Sequential)] public struct DiskExtent {
        public uint DiskNumber;
        public long StartingOffset, ExtentLength;
    }
    [StructLayout(LayoutKind.Sequential)] public struct VolumeExtents {
        public uint Count;
        public DiskExtent First;
    }
    public sealed class PathResult {
        public string FinalPath;
        public string ResolutionStatus="Unavailable", MappingStatus="Unavailable", Reason;
        public uint[] DiskNumbers=new uint[0];
    }
    public static class Native {
        const uint OpenExisting=3, ShareAll=7, BackupSemantics=0x02000000;
        const uint VolumeDiskExtents=0x00560000;
        const int MaxExtents=1024;
        [DllImport("kernel32.dll", EntryPoint="CreateFileW", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
        static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security,
            uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", EntryPoint="GetFinalPathNameByHandleW", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
        static extern uint GetFinalPath(SafeFileHandle file, StringBuilder path, uint size, uint flags);
        [DllImport("kernel32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool DeviceIoControl(SafeFileHandle device, uint code, IntPtr input, uint inputSize,
            [Out] byte[] output, uint outputSize, out uint returned, IntPtr overlapped);
        static string Final(SafeFileHandle file, uint flags) {
            int capacity=512;
            for(int attempt=0;attempt<4 && capacity<=32768;attempt++) {
                StringBuilder value=new StringBuilder(capacity);
                uint count=GetFinalPath(file,value,(uint)capacity,flags);
                if(count==0) return null;
                if(count<(uint)capacity) return value.ToString();
                if(count>=32768) return null;
                capacity=(int)count+1;
            }
            return null;
        }
        static bool Network(string value) {
            return value!=null && (value.StartsWith(@"\\?\UNC\",StringComparison.OrdinalIgnoreCase)
                || (value.StartsWith(@"\\",StringComparison.Ordinal) && !value.StartsWith(@"\\?\",StringComparison.Ordinal)));
        }
        // Separate bounded parser permits protocol/layout tests without opening Windows devices.
        public static uint[] ParseDiskExtents(byte[] data, int returned) {
            int offset=Marshal.OffsetOf(typeof(VolumeExtents),"First").ToInt32();
            int size=Marshal.SizeOf(typeof(DiskExtent));
            if(data==null || returned<offset || returned>data.Length) throw new InvalidDataException();
            uint count=BitConverter.ToUInt32(data,0);
            if(count==0 || count>MaxExtents || (long)offset+(long)size*count>returned) throw new InvalidDataException();
            HashSet<uint> unique=new HashSet<uint>();
            for(int i=0;i<(int)count;i++) unique.Add(BitConverter.ToUInt32(data,offset+i*size));
            uint[] result=new uint[unique.Count]; unique.CopyTo(result); Array.Sort(result); return result;
        }
        static uint[] Disks(string volume) {
            // Opening without the trailing slash obtains the volume, not its root directory.
            using(SafeFileHandle file=CreateFile(volume.TrimEnd('\\'),0,ShareAll,IntPtr.Zero,OpenExisting,0,IntPtr.Zero)) {
                if(file.IsInvalid) return null;
                int offset=Marshal.OffsetOf(typeof(VolumeExtents),"First").ToInt32();
                int size=Marshal.SizeOf(typeof(DiskExtent));
                int capacity=offset+size;
                for(int attempt=0;attempt<4;attempt++) {
                    byte[] data=new byte[capacity]; uint returned;
                    bool ok=DeviceIoControl(file,VolumeDiskExtents,IntPtr.Zero,0,data,(uint)data.Length,out returned,IntPtr.Zero);
                    if(ok) return ParseDiskExtents(data,checked((int)returned));
                    int error=Marshal.GetLastWin32Error();
                    if(error!=234 || returned<4) return null;
                    uint count=BitConverter.ToUInt32(data,0);
                    if(count==0 || count>MaxExtents) return null;
                    int needed=checked(offset+size*(int)count);
                    if(needed<=capacity) return null;
                    capacity=needed;
                }
                return null;
            }
        }
        public static PathResult Read(string path) {
            PathResult result=new PathResult();
            try {
                if(String.IsNullOrWhiteSpace(path) || path.IndexOf('\0')>=0 ||
                    !(Regex.IsMatch(path,@"^[a-zA-Z]:[\\/]") || path.StartsWith(@"\\",StringComparison.Ordinal))) {
                    result.Reason="InvalidPath"; return result;
                }
                if(Network(path)) { result.FinalPath="<network-path>"; result.Reason="NetworkStorageUnavailable"; return result; }
                // Do not use FILE_FLAG_OPEN_REPARSE_POINT: the handle must follow junctions.
                using(SafeFileHandle file=CreateFile(path,0,ShareAll,IntPtr.Zero,OpenExisting,BackupSemantics,IntPtr.Zero)) {
                    if(file.IsInvalid) { result.Reason="PathOpenUnavailable"; return result; }
                    string resolved=Final(file,0); // FILE_NAME_NORMALIZED | VOLUME_NAME_DOS
                    if(resolved==null) { result.Reason="FinalPathUnavailable"; return result; }
                    if(Network(resolved)) { result.FinalPath="<network-path>"; result.Reason="NetworkStorageUnavailable"; return result; }
                    result.FinalPath=resolved; result.ResolutionStatus="Available";
                    string guidPath=Final(file,1); // VOLUME_NAME_GUID stays internal; never serialized.
                    Match volume=Regex.Match(guidPath ?? "",@"^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\",RegexOptions.IgnoreCase);
                    if(!volume.Success) { result.Reason="VolumeIdentityUnavailable"; return result; }
                    uint[] numbers=Disks(volume.Value);
                    if(numbers==null || numbers.Length==0) { result.Reason="VolumeDiskExtentsUnavailable"; return result; }
                    result.DiskNumbers=numbers; result.MappingStatus="Available"; return result;
                }
            } catch { result.Reason="NativeStorageUnavailable"; return result; }
        }
    }
}
'@ -ErrorAction Stop
        }
        return $null
    } catch { return 'NativeInitializationUnavailable' }
}

# Providers remain separate so portable protocol tests need no Windows or hardware.
function Read-TrialStoragePath([string]$Path) {
    return [PZTrialStorage.Native]::Read($Path)
}

function Read-TrialStorageDisk([uint32]$Number) {
    try {
        # This is an OS-visible disk; virtual/RAID backing hardware is not established.
        # Do not join MSFT_PhysicalDisk.DeviceId to this number or infer media from bus/model.
        $disk=@(Get-Disk -Number $Number -ErrorAction Stop)
        if ($disk.Count -ne 1 -or [uint32]$disk[0].Number -ne $Number) { throw 'Disk metadata not unique' }
        return [pscustomobject]@{Status='Available';Model=[string]$disk[0].Model;FriendlyName=[string]$disk[0].FriendlyName;BusType=[string]$disk[0].BusType;Reason=$null}
    } catch { return [pscustomobject]@{Status='Unavailable';Model=$null;FriendlyName=$null;BusType=$null;Reason='DiskMetadataUnavailable'} }
}

function Get-TrialStorageReportInline {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Paths)
    $rows=@(); $diskCache=@{}; $unavailable=$null
    try { $unavailable=Initialize-TrialStorageNative } catch { $unavailable='NativeInitializationUnavailable' }
    foreach ($record in @($Paths)) {
        $rawPath=Get-TrialStorageProperty $record 'Path'
        $role=Get-TrialStorageProperty $record 'Role'; $id=Get-TrialStorageProperty $record 'Id'
        if ($role -isnot [string] -or $role -match '[\x00-\x1f]' -or $role.Length -gt 128) { $role=$null }
        if ($id -isnot [string] -or $id -match '[\x00-\x1f]' -or $id.Length -gt 128) { $id=$null }
        $row=[ordered]@{Role=$role;Id=$id;Path=$null;FinalPath=$null;ResolutionStatus='Unavailable';MappingStatus='Unavailable';Disks=@();Reason=$null}
        if ($rawPath -isnot [string] -or -not $rawPath -or $rawPath -match '[\x00-\x1f]') {
            $row.Reason='InvalidPathRecord'; $rows+=,[pscustomobject]$row; continue
        }
        $row.Path=Protect-TrialStoragePath $rawPath
        if ($row.Path -eq '<network-path>') { $row.Reason='NetworkStorageUnavailable'; $rows+=,[pscustomobject]$row; continue }
        if ($unavailable) { $row.Reason=$unavailable; $rows+=,[pscustomobject]$row; continue }
        try {
            $resolved=Read-TrialStoragePath $rawPath
            $row.FinalPath=Protect-TrialStoragePath ([string](Get-TrialStorageProperty $resolved 'FinalPath'))
            $row.ResolutionStatus=[string](Get-TrialStorageProperty $resolved 'ResolutionStatus')
            $row.MappingStatus=[string](Get-TrialStorageProperty $resolved 'MappingStatus')
            $row.Reason=Get-TrialStorageProperty $resolved 'Reason'
            if ($row.FinalPath -in @('<network-path>','<volume-path>')) { $row.MappingStatus='Unavailable'; $row.ResolutionStatus='Unavailable'; $row.Reason='NetworkOrPrivateVolumePathUnavailable' }
            if ($row.MappingStatus -eq 'Available') {
                foreach ($number in @((Get-TrialStorageProperty $resolved 'DiskNumbers') | Sort-Object -Unique)) {
                    if ($null -eq $number -or [uint64]$number -gt [uint32]::MaxValue) { throw 'Invalid disk number' }
                    $key=[string][uint32]$number
                    if (-not $diskCache.ContainsKey($key)) { $diskCache[$key]=Read-TrialStorageDisk ([uint32]$number) }
                    $disk=$diskCache[$key]
                    # Project only these fields. Never serialize provider/CIM/native objects.
                    $row.Disks+=,[pscustomobject]@{Number=[uint32]$number;Status=(Get-TrialStorageProperty $disk 'Status');Model=(Get-TrialStorageProperty $disk 'Model');FriendlyName=(Get-TrialStorageProperty $disk 'FriendlyName');BusType=(Get-TrialStorageProperty $disk 'BusType');MediaType='Unknown';MediaTypeReason='NoProvenPhysicalMediaAssociation';Reason=(Get-TrialStorageProperty $disk 'Reason')}
                }
                if (-not $row.Disks.Count) { $row.MappingStatus='Unavailable'; $row.Reason='VolumeDiskExtentsUnavailable' }
            }
        } catch { $row.ResolutionStatus='Unavailable'; $row.MappingStatus='Unavailable'; $row.Disks=@(); $row.Reason='StorageProbeUnavailable' }
        $rows+=,[pscustomobject]$row
    }
    return [pscustomobject]@{Format=1;CollectedUtc=[DateTime]::UtcNow.ToString('o');Status='Collected';Source='Win32FinalPathAndVolumeDiskExtents';Paths=@($rows);MediaTypePolicy='UnknownWithoutProvenPhysicalMediaAssociation'}
}

function ConvertTo-TrialStorageLabel($Value) {
    if ($Value -is [string] -and $Value.Length -le 128 -and $Value -notmatch '[\x00-\x1f]') { return $Value }
    return $null
}

function ConvertTo-TrialStorageFact($Value) {
    if ($Value -is [string] -and $Value.Length -le 256 -and $Value -notmatch '[\x00-\x1f]') { return $Value }
    return $null
}

function New-TrialStorageUnavailableReport([object[]]$Paths, [string]$Reason, [string]$Status='Unavailable') {
    $rows=@()
    foreach ($record in $Paths) {
        $role=$null; $id=$null; $path=$null
        try {
            $role=ConvertTo-TrialStorageLabel (Get-TrialStorageProperty $record 'Role')
            $id=ConvertTo-TrialStorageLabel (Get-TrialStorageProperty $record 'Id')
            $inputPath=Get-TrialStorageProperty $record 'Path'
            if ($inputPath -is [string] -and $inputPath -notmatch '[\x00-\x1f]') { $path=Protect-TrialStoragePath $inputPath }
        } catch { }
        $rows+=,[pscustomobject]@{Role=$role;Id=$id;Path=$path;FinalPath=$null;ResolutionStatus='Unavailable';MappingStatus='Unavailable';Disks=@();Reason=$Reason}
    }
    return [pscustomobject]@{Format=1;CollectedUtc=[DateTime]::UtcNow.ToString('o');Status=$Status;Source='Win32FinalPathAndVolumeDiskExtents';Paths=@($rows);MediaTypePolicy='UnknownWithoutProvenPhysicalMediaAssociation';Reason=$Reason}
}

function ConvertFrom-TrialStorageWorkerReport($Report, [object[]]$Paths) {
    # Rebuild the public schema. Raw child JSON, provider objects and extra fields never escape.
    $sourceRows=@(Get-TrialStorageProperty $Report 'Paths')
    if ((Get-TrialStorageProperty $Report 'Format') -ne 1 -or $sourceRows.Count -ne $Paths.Count -or
        (Get-TrialStorageProperty $Report 'Status') -ne 'Collected') { throw 'Invalid worker report' }
    $safe=New-TrialStorageUnavailableReport $Paths 'StorageProbeUnavailable'
    $safe.Status='Collected'; $safe.Reason=$null
    $allowedReasons=@('InvalidPath','NetworkStorageUnavailable','PathOpenUnavailable','FinalPathUnavailable',
        'VolumeIdentityUnavailable','VolumeDiskExtentsUnavailable','NativeStorageUnavailable','NotWindows',
        'NativeInitializationUnavailable','InvalidPathRecord','NetworkOrPrivateVolumePathUnavailable','StorageProbeUnavailable')
    for ($index=0;$index -lt $sourceRows.Count;$index++) {
        $sourceRow=$sourceRows[$index]; $row=$safe.Paths[$index]
        $resolution=[string](Get-TrialStorageProperty $sourceRow 'ResolutionStatus')
        $mapping=[string](Get-TrialStorageProperty $sourceRow 'MappingStatus')
        if ($resolution -notin @('Available','Unavailable') -or $mapping -notin @('Available','Unavailable')) { throw 'Invalid worker status' }
        $row.ResolutionStatus=$resolution; $row.MappingStatus=$mapping
        $reason=Get-TrialStorageProperty $sourceRow 'Reason'; $row.Reason=$null
        if ($null -ne $reason) {
            $row.Reason='StorageProbeUnavailable'
            if ($reason -is [string] -and $reason -in $allowedReasons) { $row.Reason=$reason }
        }
        $finalPath=Get-TrialStorageProperty $sourceRow 'FinalPath'
        if ($null -ne $finalPath -and ($finalPath -isnot [string] -or $finalPath.Length -gt 32768 -or $finalPath -match '[\x00-\x1f]')) { throw 'Invalid final path' }
        $row.FinalPath=Protect-TrialStoragePath $finalPath
        if ($row.Path -eq '<network-path>' -or $row.FinalPath -in @('<network-path>','<volume-path>')) {
            $row.FinalPath=$null; $row.ResolutionStatus='Unavailable'; $row.MappingStatus='Unavailable'; $row.Reason='NetworkOrPrivateVolumePathUnavailable'
        }
        $seen=@{}
        if ($row.MappingStatus -eq 'Available') {
            foreach ($disk in @(Get-TrialStorageProperty $sourceRow 'Disks')) {
                $number=Get-TrialStorageProperty $disk 'Number'
                if ($null -eq $number -or [string]$number -notmatch '^\d{1,10}$' -or [uint64]$number -gt [uint32]::MaxValue) { throw 'Invalid worker disk number' }
                $key=[string][uint32]$number
                if ($seen.ContainsKey($key)) { throw 'Duplicate worker disk' }; $seen[$key]=$true
                $status=Get-TrialStorageProperty $disk 'Status'
                if ($status -notin @('Available','Unavailable')) { throw 'Invalid worker disk status' }
                $diskReason=$null
                if ($status -eq 'Unavailable') { $diskReason='DiskMetadataUnavailable' }
                $row.Disks+=,[pscustomobject]@{Number=[uint32]$number;Status=$status;Model=(ConvertTo-TrialStorageFact (Get-TrialStorageProperty $disk 'Model'));FriendlyName=(ConvertTo-TrialStorageFact (Get-TrialStorageProperty $disk 'FriendlyName'));BusType=(ConvertTo-TrialStorageFact (Get-TrialStorageProperty $disk 'BusType'));MediaType='Unknown';MediaTypeReason='NoProvenPhysicalMediaAssociation';Reason=$diskReason}
            }
            if (-not $row.Disks.Count) { throw 'Missing worker disks' }
        }
    }
    return $safe
}

function Remove-TrialStorageTemporaryDirectory([string]$Directory) {
    [IO.Directory]::Delete($Directory,$true)
    return $true
}

function Complete-TrialStorageWorker($Worker, [bool]$Started, [string]$Directory) {
    $workerStatus='NotStarted'; $filesStatus='NotCreated'
    # Only the exact Process returned by our Start() is eligible for termination.
    if ($Worker) {
        if ($Started) {
            $workerStatus='Unconfirmed'
            try {
                if ($Worker.HasExited) { $workerStatus='Exited' }
                else {
                    $Worker.Kill()
                    if ($Worker.WaitForExit(1000)) { $workerStatus='Stopped' }
                }
            } catch { }
        }
        try { $Worker.Dispose() } catch { }
    }
    if ($Directory) {
        $filesStatus='Unconfirmed'
        try { if (Remove-TrialStorageTemporaryDirectory $Directory) { $filesStatus='Removed' } } catch { }
    }
    return [pscustomobject]@{WorkerCleanup=$workerStatus;TemporaryFilesCleanup=$filesStatus}
}

function Get-TrialStorageReport {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Paths, [ValidateRange(1,60)][int]$TimeoutSeconds=15)
    $directory=$null; $worker=$null; $started=$false; $report=$null
    $cleanup=[pscustomobject]@{WorkerCleanup='Unconfirmed';TemporaryFilesCleanup='Unconfirmed'}
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        if (@($Paths).Count -gt 1024) { throw 'Too many paths' }
        $records=@()
        foreach ($record in $Paths) {
            $records+=,[pscustomobject]@{Role=(Get-TrialStorageProperty $record 'Role');Id=(Get-TrialStorageProperty $record 'Id');Path=(Get-TrialStorageProperty $record 'Path')}
        }
        $directory=Join-Path ([IO.Path]::GetTempPath()) ('pz-trial-storage-'+[Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($directory)
        $request=Join-Path $directory 'request.json'; $response=Join-Path $directory 'response.json'
        $utf8=New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($request,(@{Paths=@($records)} | ConvertTo-Json -Depth 6 -Compress),$utf8)
        $helperLiteral="'"+$script:TrialStorageHelperPath.Replace("'","''")+"'"
        $requestLiteral="'"+$request.Replace("'","''")+"'"; $responseLiteral="'"+$response.Replace("'","''")+"'"
        $command=@"
`$ErrorActionPreference='Stop'
`$ProgressPreference='SilentlyContinue'
try {
    . $helperLiteral
    `$request=[IO.File]::ReadAllText($requestLiteral) | ConvertFrom-Json
    `$value=Get-TrialStorageReportInline -Paths @(`$request.Paths)
    [IO.File]::WriteAllText($responseLiteral,(`$value | ConvertTo-Json -Depth 12 -Compress),(New-Object Text.UTF8Encoding(`$false)))
} catch { }
"@
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $info.Arguments='-NoProfile -NonInteractive '
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $info.Arguments+='-ExecutionPolicy Bypass ' }
        $info.Arguments+='-EncodedCommand '+$encoded
        $info.UseShellExecute=$false; $info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
        $worker=New-Object Diagnostics.Process; $worker.StartInfo=$info
        $started=$worker.Start()
        if (-not $started) { throw 'Worker did not start' }
        # Drain and discard child streams asynchronously: no raw exception/identity text is logged.
        $worker.BeginOutputReadLine(); $worker.BeginErrorReadLine()
        $remaining=[Math]::Max(0,[int]($TimeoutSeconds*1000-$watch.ElapsedMilliseconds))
        if (-not $worker.WaitForExit($remaining)) {
            $report=New-TrialStorageUnavailableReport $Paths 'StorageProbeTimeout' 'Timeout'
        } elseif ($worker.ExitCode -ne 0 -or -not [IO.File]::Exists($response) -or (New-Object IO.FileInfo($response)).Length -gt 4194304) {
            $report=New-TrialStorageUnavailableReport $Paths 'StorageWorkerUnavailable'
        } else {
            $decoded=[IO.File]::ReadAllText($response) | ConvertFrom-Json
            $report=ConvertFrom-TrialStorageWorkerReport $decoded $Paths
        }
    } catch { $report=New-TrialStorageUnavailableReport $Paths 'StorageWorkerUnavailable' }
    finally {
        try { $cleanup=Complete-TrialStorageWorker $worker $started $directory } catch { }
    }
    $watch.Stop()
    $report | Add-Member -NotePropertyName WorkerCleanup -NotePropertyValue $cleanup.WorkerCleanup -Force
    $report | Add-Member -NotePropertyName TemporaryFilesCleanup -NotePropertyValue $cleanup.TemporaryFilesCleanup -Force
    $report | Add-Member -NotePropertyName ElapsedMs -NotePropertyValue $watch.Elapsed.TotalMilliseconds -Force
    return $report
}
