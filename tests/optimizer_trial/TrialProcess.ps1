# Keep disk writes away from the native game's stdout/stderr handles.
function Initialize-TrialProcess {
    if (-not ('PZTrial.TrialProcessCapture' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'TrialProcess.cs') -ErrorAction Stop
    }
}

function Start-TrialProcess($Plan, $Logs) {
    foreach ($path in @($Logs.Stdout, $Logs.Stderr)) {
        if (Get-Command Assert-NoReparsePoint -ErrorAction SilentlyContinue) { Assert-NoReparsePoint $path }
        if (Test-Path -LiteralPath $path) { throw "Refusing to replace an existing trial log: $path" }
    }
    Initialize-TrialProcess
    return [PZTrial.TrialProcessCapture]::Start($Plan.Java, $Plan.WorkingDirectory,
        $Plan.CommandLine, $Logs.Stdout, $Logs.Stderr, (16 * 1024 * 1024))
}

function Complete-TrialProcess($Capture, [int]$TimeoutMilliseconds = 15000) {
    return $Capture.Complete($TimeoutMilliseconds)
}
