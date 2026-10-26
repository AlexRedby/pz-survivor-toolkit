# CapFrameX CXRemote, verified against 1.9.1.5 (also available since 1.5.6).
# Source: https://github.com/CXWorld/CapFrameX/tree/9f488ea6c39e33ec25c6ebfae1c4a1c4063c3026
# CaptureController selects an OS process BY NAME, not PID. Keep the unique-name
# gate immediately before POST. No synthetic input, settings changes or retries.
# Dot-source after Record-JFR.ps1; importing this file has no side effects.
function Get-TrialFrameProperty($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Assert-TrialFramePath([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw 'CapFrameX capture paths must not contain symbolic links or junctions.'
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Read-TrialFrameStream([IO.FileStream]$Stream) {
    # The caller keeps BOTH output handles open with FileShare.Read through
    # validation. On Windows this refuses any concurrent writable handle.
    $reader = [IO.StreamReader]::new($Stream, [Text.Encoding]::UTF8, $true, 4096, $true)
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $Stream.Position = 0
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($hasher.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
    return [pscustomobject]@{ Text = $text; Sha256 = $hash }
}

function Invoke-TrialFrameRequest($Client, [string]$Method, [string]$Route, $Payload = $null) {
    $base = [Uri]([string]$Client.BaseUri)
    if ($base.Scheme -ne 'http' -or $base.Host -notin @('localhost', '127.0.0.1', '[::1]', '::1') -or
        $base.UserInfo -or $base.Query -or $base.Fragment -or $base.AbsolutePath -ne '/' -or
        $Route -notin @('/api/version', '/api/processes', '/api/capture')) {
        throw 'CapFrameX requests require an uncredentialed localhost HTTP endpoint.'
    }
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $handler.AllowAutoRedirect = $false
    $http = [Net.Http.HttpClient]::new($handler)
    $http.Timeout = [TimeSpan]::FromSeconds(3)
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), [Uri]::new($base, $Route))
    $response = $null
    try {
        if ($null -ne $Payload) {
            $request.Content = [Net.Http.StringContent]::new(($Payload | ConvertTo-Json -Depth 8 -Compress),
                [Text.Encoding]::UTF8, 'application/json')
        }
        $response = $http.SendAsync($request).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw ('CapFrameX returned HTTP ' + [int]$response.StatusCode + '. ' + $body)
        }
        if (-not $body -or $body.Length -gt 1048576) { throw 'Invalid CapFrameX response body.' }
        return ($body | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        # POST may have reached CX even when its response times out. The caller
        # must preserve the directory and never retry or stop an unowned capture.
        $suffix = ''
        if ($Method -eq 'POST') { $suffix = ' Capture start outcome may be unknown; do not retry or stop another capture.' }
        throw ('CapFrameX request failed: ' + $_.Exception.Message + $suffix)
    } finally {
        if ($response) { $response.Dispose() }
        $request.Dispose()
        $http.Dispose()
    }
}

function Get-TrialProcessImageSource {
    return @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace PZTrialProcessImage {
    public static class Reader {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, bool inherit, uint processId);
        [DllImport("kernel32.dll", EntryPoint = "QueryFullProcessImageNameW", CharSet = CharSet.Unicode,
            ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder path, ref uint size);
        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
        public static string Read(uint processId) {
            // Limited image queries work across target bitness without enumerating modules.
            IntPtr process = OpenProcess(0x1000, false, processId);
            if (process == IntPtr.Zero) return null;
            try {
                StringBuilder path = new StringBuilder(32768);
                uint size = (uint)path.Capacity;
                if (!QueryFullProcessImageName(process, 0, path, ref size)) return null;
                return path.ToString();
            } finally { CloseHandle(process); }
        }
    }
}
'@
}

function Get-TrialLimitedProcessImage([int]$ProcessId) {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return $null }
    if (-not ('PZTrialProcessImage.Reader' -as [type])) {
        Add-Type -TypeDefinition (Get-TrialProcessImageSource) -ErrorAction Stop
    }
    return [PZTrialProcessImage.Reader]::Read([uint32]$ProcessId)
}

function Get-TrialCapFrameXExecutable($Process) {
    $path = $null
    try { $path = $Process.Path } catch { }
    if (-not $path) {
        # Get-Process.Path can be empty, e.g. 32-bit PowerShell inspecting a 64-bit client.
        # No elevation, process-memory access or module enumeration is requested.
        try { $path = Get-TrialLimitedProcessImage $Process.Id } catch { }
    }
    return $path
}

function Get-TrialCapFrameX([ValidateRange(0, 65535)][int]$Port = 0, [string]$Directory) {
    $running = @(Get-Process -Name CapFrameX -ErrorAction SilentlyContinue)
    if ($running.Count -ne 1) { throw 'Start exactly one CapFrameX instance before launching the trial.' }
    $configPath = $null
    $config = $null
    $executable = Get-TrialCapFrameXExecutable $running[0]
    $executableDirectory = $null
    if ($executable) { $executableDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($executable)) }
    if ($Directory) {
        $Directory = [IO.Path]::GetFullPath($Directory.Trim().Trim('"')).TrimEnd([char[]]@('/', '\'))
        if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw 'The supplied -CapFrameXDir folder does not exist.' }
        $comparison = [StringComparison]::Ordinal
        if ([Environment]::OSVersion.Platform -eq 'Win32NT') { $comparison = [StringComparison]::OrdinalIgnoreCase }
        if ($executableDirectory -and -not [string]::Equals($Directory, $executableDirectory.TrimEnd([char[]]@('/', '\')), $comparison)) {
            throw 'The supplied -CapFrameXDir differs from the running CapFrameX folder.'
        }
        $executableDirectory = $Directory
    }
    if ($executableDirectory) {
        $appData = $env:APPDATA
        if (-not $appData) { $appData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData) }
        if ($appData) { $configPath = Join-Path $appData 'CapFrameX/Configuration/AppSettings.json' }
        $portablePath = Join-Path $executableDirectory 'portable.json'
        if (Test-Path -LiteralPath $portablePath -PathType Leaf) {
            try { $portable = Get-Content -LiteralPath $portablePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
            catch { throw 'Cannot read CapFrameX portable.json safely; fix the configuration before capturing.' }
            if ($null -ne $portable -and (Get-TrialFrameProperty $portable 'portable' $true)) {
                $portableDirectory = [string](Get-TrialFrameProperty (Get-TrialFrameProperty $portable 'paths') 'config' './Portable/Config')
                if ([string]::IsNullOrWhiteSpace($portableDirectory)) { $portableDirectory = './Config' }
                if (-not [IO.Path]::IsPathRooted($portableDirectory)) {
                    $portableDirectory = Join-Path $executableDirectory $portableDirectory
                }
                $configPath = Join-Path ([IO.Path]::GetFullPath($portableDirectory)) 'AppSettings.json'
            }
        }
    }
    # A missing image path does not mean the running application/API is absent.
    # Without a known directory, do not consume a possibly stale installed config.
    # Probe only the explicit port or the documented default; never scan ports.
    if ($configPath -and (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        try { $config = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'Cannot read CapFrameX AppSettings.json safely; fix it before capturing.' }
        if ((Get-TrialFrameProperty $config 'UseAggregation' $false) -and
            (Get-TrialFrameProperty $config 'SaveAggregationOnly' $false)) {
            throw 'CapFrameX SaveAggregationOnly is enabled with UseAggregation; disable it before this trial.'
        }
    } else { $configPath = $null }
    if ($Port -eq 0) {
        $configuredPort = [string](Get-TrialFrameProperty $config 'WebservicePort' '1337')
        $parsedPort = 0
        if (-not [int]::TryParse($configuredPort, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
            throw 'Invalid CapFrameX WebservicePort. Supply -CapFrameXPort explicitly.'
        }
        $Port = $parsedPort
    }
    $client = [pscustomobject]@{ BaseUri = 'http://localhost:' + $Port; Version = $null; ConfigPath = $configPath }
    try { $versionResponse = Invoke-TrialFrameRequest $client 'GET' '/api/version' }
    catch {
        if (-not $executableDirectory) {
            throw ('CapFrameX is running, but its EXE path is unavailable and the local API at port ' + $Port + ' could not be reached. Supply -CapFrameXDir with the portable folder, or -CapFrameXPort with its configured port. ' + $_.Exception.Message)
        }
        throw
    }
    $versionText = [string](Get-TrialFrameProperty $versionResponse 'Version')
    $version = $null
    if (-not [Version]::TryParse($versionText, [ref]$version) -or $version -lt [Version]'1.5.6') {
        throw 'The selected endpoint is not a supported CapFrameX CXRemote API (1.5.6 or newer required).'
    }
    $client.Version = $versionText
    return $client
}

function Assert-TrialCapFrameXTarget($Client, $Process, [string]$ExpectedExecutablePath, [DateTime]$ExpectedStartUtc) {
    $identity = Assert-JfrTargetProcess $Process $ExpectedExecutablePath $ExpectedStartUtc
    $javaProcesses = @(Get-Process -Name java -ErrorAction SilentlyContinue)
    if ($javaProcesses.Count -ne 1 -or $javaProcesses[0].Id -ne $Process.Id) {
        throw 'CapFrameX captures by name: exactly one java process must exist, and it must be the owned trial client.'
    }
    $eligible = @(Invoke-TrialFrameRequest $Client 'GET' '/api/processes')
    if (-not ($eligible -ccontains 'java')) { throw 'The owned java process is not capture-eligible in CapFrameX yet.' }
    # Recheck identity and uniqueness after the HTTP read, immediately before POST.
    $null = Assert-JfrTargetProcess $Process $ExpectedExecutablePath $ExpectedStartUtc
    $javaProcesses = @(Get-Process -Name java -ErrorAction SilentlyContinue)
    if ($javaProcesses.Count -ne 1 -or $javaProcesses[0].Id -ne $Process.Id) {
        throw 'The java process identity became ambiguous before CapFrameX capture.'
    }
    return $identity
}

function Start-TrialFrameCapture($Client, $Process, [string]$ExpectedExecutablePath, [DateTime]$ExpectedStartUtc,
    [string]$Directory, [ValidateRange(1, 300)][int]$Seconds, [string]$Token) {
    if ([string]::IsNullOrWhiteSpace($Token) -or [string]::IsNullOrWhiteSpace($Directory)) {
        throw 'A unique capture token and new capture directory are required.'
    }
    $directoryPath = [IO.Path]::GetFullPath($Directory)
    Assert-TrialFramePath $directoryPath
    if (Test-Path -LiteralPath $directoryPath) { throw 'CapFrameX capture directory must be new; existing captures are preserved.' }
    $null = Assert-TrialCapFrameXTarget $Client $Process $ExpectedExecutablePath $ExpectedStartUtc
    $null = New-Item -ItemType Directory -Path $directoryPath -ErrorAction Stop
    # REST builds new CaptureOptions: CaptureDelay defaults to zero. GUI delay
    # settings are not copied. JsonCsv is the enum NAME, not the UI's JSON + CSV.
    $requestedUtc = [DateTime]::UtcNow.ToString('o')
    $answer = Invoke-TrialFrameRequest $Client 'POST' '/api/capture' ([ordered]@{
        ProcessName = 'java'; CaptureTime = $Seconds; CaptureFileMode = 'JsonCsv';
        RecordDirectory = $directoryPath; Comment = $Token
    })
    if ((Get-TrialFrameProperty $answer 'Message') -cne 'Capture started') {
        throw 'CapFrameX did not acknowledge capture start. Outcome may be unknown; preserve the capture directory and do not retry.'
    }
    return [pscustomobject][ordered]@{ directory = $directoryPath; token = $Token; targetPid = [int]$Process.Id;
        processName = 'java'; seconds = $Seconds; requestedUtc = $requestedUtc; acknowledgedUtc = [DateTime]::UtcNow.ToString('o') }
}

function Complete-TrialFrameCapture($Receipt) {
    # Nonblocking: no sleeps, network calls, capture stops, renames or deletions.
    # REST acknowledgements do not prove frames were written. JSON contains no
    # PID; the accompanying raw CSV's ProcessID is the authoritative frame PID.
    Assert-TrialFramePath $Receipt.directory
    if (-not (Test-Path -LiteralPath $Receipt.directory -PathType Container)) { return $null }
    $jsonFiles = @(Get-ChildItem -LiteralPath $Receipt.directory -Filter '*.json' -File -ErrorAction Stop)
    $csvFiles = @(Get-ChildItem -LiteralPath $Receipt.directory -Filter '*.csv' -File -ErrorAction Stop)
    if ($jsonFiles.Count -gt 1 -or $csvFiles.Count -gt 1) { throw 'Multiple CapFrameX output files found in the owned capture directory.' }
    if ($jsonFiles.Count -ne 1 -or $csvFiles.Count -ne 1) { return $null }
    Assert-TrialFramePath $jsonFiles[0].FullName
    Assert-TrialFramePath $csvFiles[0].FullName
    $jsonStream = $null
    $csvStream = $null
    try {
        try {
            $jsonStream = [IO.FileStream]::new($jsonFiles[0].FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $csvStream = [IO.FileStream]::new($csvFiles[0].FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $jsonSnapshot = Read-TrialFrameStream $jsonStream
            $csvSnapshot = Read-TrialFrameStream $csvStream
        } catch { return $null } # Writer may still hold or be filling an output.
        try { $session = $jsonSnapshot.Text | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
        $info = Get-TrialFrameProperty $session 'Info'
        if ((Get-TrialFrameProperty $info 'Comment') -cne $Receipt.token) { throw 'CapFrameX output token does not match this capture.' }
        $expectedName = $Receipt.processName + '.exe'
        if ((Get-TrialFrameProperty $info 'ProcessName') -ine $expectedName) { throw 'CapFrameX JSON process name does not match the owned capture.' }
        $runs = @(Get-TrialFrameProperty $session 'Runs')
        if ($runs.Count -gt 1) { throw 'Unexpected multiple runs in the CapFrameX output.' }
        if ($runs.Count -ne 1) { return $null }
        $data = Get-TrialFrameProperty $runs[0] 'CaptureData'
        $frames = @(Get-TrialFrameProperty $data 'MsBetweenPresents')
        $times = @(Get-TrialFrameProperty $data 'TimeInSeconds')
        if (-not $frames.Count -or $times.Count -ne $frames.Count) { return $null }
        $durationMs = 0.0
        foreach ($frame in $frames) {
            $number = 0.0
            if ($null -eq $frame -or -not [double]::TryParse([string]$frame, [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or [double]::IsNaN($number) -or
                [double]::IsInfinity($number) -or $number -lt 0) { throw 'Invalid CapFrameX frametime data.' }
            $durationMs += $number
        }
        $duration = $durationMs / 1000.0
        if ($duration -le 0 -or $duration -lt ([double]$Receipt.seconds - 1.0)) { return $null }
        if ($duration -gt ([double]$Receipt.seconds + 5.0)) { throw 'CapFrameX capture duration exceeds this session window.' }
        $lines = @($csvSnapshot.Text -split '\r?\n' | Where-Object { $_.Trim() })
        if ($lines.Count -and $lines[0] -eq '//Ignore=true') { $lines = @($lines | Select-Object -Skip 1) }
        if ($lines.Count -lt 2) { return $null }
        try { $rows = @($lines | ConvertFrom-Csv -ErrorAction Stop) } catch { return $null }
        if (-not $rows.Count) { return $null }
        if ($null -eq $rows[0].PSObject.Properties['ProcessID']) { throw 'CapFrameX raw CSV has no ProcessID column.' }
        foreach ($row in $rows) {
            $framePid = 0
            if (-not [int]::TryParse([string](Get-TrialFrameProperty $row 'ProcessID'), [ref]$framePid)) { return $null }
            if ($framePid -ne [int]$Receipt.targetPid) { throw 'CapFrameX raw CSV contains frames from the wrong PID.' }
            $application = Get-TrialFrameProperty $row 'Application'
            if ($null -ne $application -and ([string]$application).Trim() -ine $expectedName) {
                throw 'CapFrameX raw CSV process name does not match the owned capture.'
            }
        }
        if ($rows.Count -lt $frames.Count) { return $null } # A partially written CSV is not a completed capture.
        return [pscustomobject][ordered]@{ Json = $jsonFiles[0].FullName; Csv = $csvFiles[0].FullName;
            Token = $Receipt.token; TargetPid = [int]$Receipt.targetPid; ProcessName = $Receipt.processName;
            DurationSeconds = $duration; FrameCount = $frames.Count; CsvFrameCount = $rows.Count;
            JsonSha256 = $jsonSnapshot.Sha256; CsvSha256 = $csvSnapshot.Sha256 }
    } finally {
        if ($csvStream) { $csvStream.Dispose() }
        if ($jsonStream) { $jsonStream.Dispose() }
    }
}
