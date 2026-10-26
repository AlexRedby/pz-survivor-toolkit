# Compatible with Windows PowerShell 5.1. The caller verifies the hash before promotion.
function Save-TrialDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Destination,
        [long]$ExpectedBytes = 0,
        [int]$IdleTimeoutSeconds = 60,
        [int]$TotalTimeoutSeconds = 900
    )
    $limit = [long](256 * 1024 * 1024)
    if ($ExpectedBytes -lt 0 -or $ExpectedBytes -gt $limit) { throw 'Download expected size must be between 0 and 256 MiB.' }
    if ($IdleTimeoutSeconds -lt 1 -or $TotalTimeoutSeconds -lt 1) { throw 'Download timeouts must be positive seconds.' }
    $source = $null
    if (-not [Uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$source)) { throw 'Download source must be an absolute URL.' }
    $fixture = $source.Scheme -eq 'http' -and $source.IsLoopback
    function Test-TrialDownloadUri($value) {
        if ($value.UserInfo -or $value.Fragment) { return $false }
        if ($fixture) {
            return $value.Scheme -eq 'http' -and $value.IsLoopback -and $value.Authority -eq $source.Authority
        }
        return $value.Scheme -eq 'https' -and $value.IsDefaultPort -and (
            $value.Host -eq 'github.com' -or $value.Host -eq 'api.github.com' -or
            $value.Host -eq 'release-assets.githubusercontent.com' -or
            $value.Host -eq 'objects.githubusercontent.com' -or
            $value.Host -eq 'github-releases.githubusercontent.com')
    }
    if (-not (Test-TrialDownloadUri $source)) { throw 'Download source must use official GitHub HTTPS (HTTP loopback is reserved for isolated fixtures).' }
    $pathRoot = [IO.Path]::GetPathRoot($Destination)
    if (-not [IO.Path]::IsPathRooted($Destination) -or $pathRoot.EndsWith(':') -or
        ([IO.Path]::DirectorySeparatorChar -eq '\' -and $pathRoot -eq '\')) {
        throw 'Download destination must be an absolute path.'
    }
    $path = [IO.Path]::GetFullPath($Destination)
    $parent = [IO.Path]::GetDirectoryName($path)
    if (-not $parent -or -not [IO.Directory]::Exists($parent) -or [IO.Directory]::Exists($path)) { throw 'Download destination requires an existing parent directory and a new file name.' }
    # Refuse links/junctions in the existing path, including the final destination.
    $ancestor = $parent
    while ($ancestor) {
        if (([IO.File]::GetAttributes($ancestor) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Download destination must not traverse a link or junction.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if ([IO.File]::Exists($path)) { throw 'Download destination already exists; refusing to overwrite it.' }
    Add-Type -AssemblyName System.Net.Http
    $state = @{ Bytes = [long]0; Length = [long]$ExpectedBytes; Clock = [Diagnostics.Stopwatch]::StartNew(); LastActivity = 0.0; LastReport = -5.0 }
    function Write-TrialDownloadStatus {
        $now = $state.Clock.Elapsed.TotalSeconds
        if ($now - $state.LastReport -ge 5) {
            $size = '{0:N0} bytes' -f $state.Bytes
            if ($state.Length -gt 0) { $size = '{0:N0}/{1:N0} bytes ({2:N1}%)' -f $state.Bytes, $state.Length, (100.0 * $state.Bytes / $state.Length) }
            Write-Host ('Download: {0}; elapsed {1:N0}s; waiting {2:N0}s' -f $size, $now, ($now - $state.LastActivity))
            $state.LastReport = $now
        }
    }
    function Wait-TrialDownloadTask($task, [string]$phase) {
        while (-not $task.IsCompleted) {
            Write-TrialDownloadStatus
            $now = $state.Clock.Elapsed.TotalSeconds
            if ($now -ge $TotalTimeoutSeconds) { throw ('Download total timeout during {0} after {1:N0} bytes ({2}s limit).' -f $phase, $state.Bytes, $TotalTimeoutSeconds) }
            if ($now - $state.LastActivity -ge $IdleTimeoutSeconds) { throw ('Download inactivity timeout during {0} after {1:N0} bytes ({2}s without data).' -f $phase, $state.Bytes, $IdleTimeoutSeconds) }
            Start-Sleep -Milliseconds 100
        }
        if ($state.Clock.Elapsed.TotalSeconds -ge $TotalTimeoutSeconds) { throw ('Download total timeout after {0:N0} bytes ({1}s limit).' -f $state.Bytes, $TotalTimeoutSeconds) }
        return $task.GetAwaiter().GetResult()
    }
    $handler = $null; $client = $null; $response = $null; $stream = $null; $file = $null; $cancel = $null; $request = $null
    try {
        $file = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $handler = New-Object Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $false
        $client = New-Object Net.Http.HttpClient($handler)
        $client.Timeout = [Threading.Timeout]::InfiniteTimeSpan
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('PZSurvivorToolkit-Trial/1.0')
        $cancel = New-Object Threading.CancellationTokenSource
        $cancel.CancelAfter([TimeSpan]::FromSeconds($TotalTimeoutSeconds))
        $current = $source
        for ($redirects = 0; $redirects -le 5; $redirects++) {
            $request = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Get, $current)
            $task = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cancel.Token)
            $response = Wait-TrialDownloadTask $task 'response headers'
            $request.Dispose(); $request = $null
            $code = [int]$response.StatusCode
            if ($code -in @(301, 302, 303, 307, 308)) {
                if ($redirects -eq 5 -or -not $response.Headers.Location) { throw 'Download redirect limit exceeded or redirect location missing.' }
                $next = New-Object Uri($current, $response.Headers.Location)
                if (-not (Test-TrialDownloadUri $next)) { throw 'Download redirect rejected: expected an approved HTTPS asset host.' }
                $response.Dispose(); $response = $null
                $current = $next
                continue
            }
            if (-not $response.IsSuccessStatusCode) { throw ('Download server returned HTTP {0}.' -f $code) }
            break
        }
        $headerLength = $response.Content.Headers.ContentLength
        if ($null -ne $headerLength) {
            if ($headerLength -gt $limit) { throw 'Download Content-Length exceeds the 256 MiB limit.' }
            if ($ExpectedBytes -gt 0 -and $headerLength -ne $ExpectedBytes) { throw ('Download Content-Length {0} does not match expected {1} bytes.' -f $headerLength, $ExpectedBytes) }
            $state.Length = [long]$headerLength
        }
        $state.LastActivity = $state.Clock.Elapsed.TotalSeconds
        $stream = Wait-TrialDownloadTask ($response.Content.ReadAsStreamAsync()) 'opening body'
        $buffer = New-Object byte[] 65536
        while ($true) {
            $read = Wait-TrialDownloadTask ($stream.ReadAsync($buffer, 0, $buffer.Length, $cancel.Token)) 'response body'
            if ($read -eq 0) { break }
            if ($state.Bytes + $read -gt $limit) { throw 'Download body exceeds the 256 MiB limit.' }
            if ($state.Length -gt 0 -and $state.Bytes + $read -gt $state.Length) { throw 'Download body exceeds the expected byte count.' }
            $file.Write($buffer, 0, $read)
            $state.Bytes += $read
            $state.LastActivity = $state.Clock.Elapsed.TotalSeconds
            Write-TrialDownloadStatus
        }
        if (($null -ne $headerLength -and $state.Bytes -ne $headerLength) -or ($ExpectedBytes -gt 0 -and $state.Bytes -ne $ExpectedBytes)) { throw ('Download length mismatch: received {0} bytes; expected {1}.' -f $state.Bytes, $state.Length) }
        $file.Flush()
        Write-Host ('Download complete: {0:N0} bytes in {1:N1}s.' -f $state.Bytes, $state.Clock.Elapsed.TotalSeconds)
        return [pscustomobject]@{ Bytes = $state.Bytes; ElapsedSeconds = $state.Clock.Elapsed.TotalSeconds }
    } catch {
        # Do not expose signed redirect URLs or credentials from framework exception text.
        if ($_.Exception.Message -like 'Download *') { throw }
        if (($cancel -and $cancel.IsCancellationRequested) -or $state.Clock.Elapsed.TotalSeconds -ge $TotalTimeoutSeconds) {
            throw ('Download total timeout after {0:N0} bytes ({1}s limit).' -f $state.Bytes, $TotalTimeoutSeconds)
        }
        throw ('Download failed after {0:N0} bytes ({1:N1}s); the connection was interrupted or the destination could not be written.' -f $state.Bytes, $state.Clock.Elapsed.TotalSeconds)
    } finally {
        if ($cancel) { $cancel.Cancel() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        if ($request) { $request.Dispose() }
        if ($client) { $client.Dispose() } elseif ($handler) { $handler.Dispose() }
        if ($cancel) { $cancel.Dispose() }
        if ($file) { $file.Dispose() }
        $state.Clock.Stop()
    }
}
