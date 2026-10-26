# Optional, read-only NVIDIA telemetry. Dot-source; no process starts on import.
# Query/CSV semantics: https://docs.nvidia.com/deploy/nvidia-smi/index.html
# Metric examples: https://nvidia.custhelp.com/app/answers/detail/a_id/3751
# Unsupported device metrics remain NVIDIA's N/A, never fabricated numbers.
function Get-TrialNvidiaTool {
    $command = Get-Command 'nvidia-smi.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) { return $command.Source }
    $candidates = @()
    foreach ($windowsRoot in @($env:SystemRoot, $env:WINDIR)) {
        if ($windowsRoot) { $candidates += Join-Path $windowsRoot 'System32/nvidia-smi.exe' }
    }
    foreach ($programRoot in @($env:ProgramW6432, $env:ProgramFiles)) {
        if ($programRoot) { $candidates += Join-Path $programRoot 'NVIDIA Corporation/NVSMI/nvidia-smi.exe' }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    return $null
}

function Read-TrialNvidiaSample([string]$Tool) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $fields = @('timestamp', 'index', 'name', 'driver_version', 'pstate', 'temperature.gpu',
        'utilization.gpu', 'utilization.memory', 'memory.used', 'memory.total',
        'clocks.current.graphics', 'clocks.current.memory', 'power.draw')
    $sample = [pscustomobject][ordered]@{ status = 'Unavailable'; csv = $null; unavailableReason = 'ToolMissing';
        exitCode = $null; elapsedMs = 0; unavailableFields = @($fields) }
    $process = $null
    try {
        if (-not $Tool -or -not (Test-Path -LiteralPath $Tool -PathType Leaf)) { return $sample }
        $sample.unavailableReason = 'StartFailed'
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $Tool
        $start.Arguments = '--query-gpu=' + ($fields -join ',') + ' --format=csv'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $start
        if (-not $process.Start()) { return $sample }
        # Drain BOTH streams asynchronously before waiting, so full stderr/stdout
        # pipes cannot block the sampled process. No loop or management flags.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        # Reserve cleanup time inside the total 2-second sampling budget.
        $remaining = [Math]::Max(0, 1800 - [int]$watch.ElapsedMilliseconds)
        if (-not $process.WaitForExit($remaining)) {
            $sample.unavailableReason = 'Timeout'
            try { if (-not $process.HasExited) { $process.Kill() } } catch { }
            return $sample
        }
        $sample.exitCode = $process.ExitCode
        $remaining = [Math]::Max(0, 1900 - [int]$watch.ElapsedMilliseconds)
        $streams = [Threading.Tasks.Task[]]@($stdout, $stderr)
        if (-not [Threading.Tasks.Task]::WaitAll($streams, $remaining)) {
            $sample.unavailableReason = 'Timeout'
            # Only this owned process may be killed; never a GPU/game process.
            try { if (-not $process.HasExited) { $process.Kill() } } catch { }
            return $sample
        }
        if ($sample.exitCode -ne 0) { $sample.unavailableReason = 'QueryFailed'; return $sample }
        $csv = $stdout.Result
        if (-not $csv.Trim()) { $sample.unavailableReason = 'EmptyOutput'; return $sample }
        if ($csv.Length -gt 131072) { $sample.unavailableReason = 'OutputTooLarge'; return $sample }
        if ($watch.ElapsedMilliseconds -ge 1950) { $sample.unavailableReason = 'Timeout'; return $sample }
        $sample.unavailableReason = 'InvalidOutput'
        $rows = @($csv | ConvertFrom-Csv -ErrorAction Stop)
        if (-not $rows.Count -or @($rows[0].PSObject.Properties).Count -ne $fields.Count) { return $sample }
        $unavailable = @()
        foreach ($row in $rows) {
            foreach ($property in $row.PSObject.Properties) {
                if ([string]$property.Value -match '^\s*(\[?N/A\]?|\[?Not Supported\]?)\s*$') {
                    $unavailable += $property.Name.Trim()
                }
            }
        }
        $sample.status = 'Available'
        $sample.csv = $csv
        $sample.unavailableReason = $null
        $sample.unavailableFields = @($unavailable | Select-Object -Unique)
        return $sample
    } catch {
        # Errors are optional evidence, never a failed game capture. Do not copy
        # exception/command text that could contain local account or host paths.
        return $sample
    } finally {
        $watch.Stop()
        $sample.elapsedMs = [int]$watch.ElapsedMilliseconds
        if ($process) { $process.Dispose() }
    }
}
