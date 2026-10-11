param([Parameter(Mandatory = $true)][string]$Game)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This launcher requires Windows.' }
$Game = (Resolve-Path -LiteralPath $Game).Path
foreach ($file in @('ProjectZomboid64.exe', 'ProjectZomboid64.json', 'ZombieBuddy.jar', 'zbNative.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Game $file) -PathType Leaf)) {
        throw "Missing $file in $Game. Install the ZombieBuddy loader first."
    }
}
if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Start Steam first.' }

$previous = @{}
foreach ($name in @('JDK_JAVA_OPTIONS', 'SteamAppId', 'SteamGameId')) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
if ($previous.JDK_JAVA_OPTIONS -match 'zbNative|ZombieBuddy') {
    throw 'Remove the existing ZombieBuddy setting from JDK_JAVA_OPTIONS to avoid loading it twice.'
}
$agent = '-agentpath:"' + (Join-Path $Game 'zbNative.dll') + '"'
$vmArgs = (Get-Content -LiteralPath (Join-Path $Game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json).vmArgs
try {
    $env:JDK_JAVA_OPTIONS = ($previous.JDK_JAVA_OPTIONS + ' ' + $agent).Trim()
    $env:SteamAppId = '108600'
    $env:SteamGameId = '108600'
    $parameters = @{FilePath = (Join-Path $Game 'ProjectZomboid64.exe'); WorkingDirectory = $Game}
    if (-not ($vmArgs -match 'zbNative|ZombieBuddy')) { $parameters.ArgumentList = @($agent, '--') }
    # The native client uses its launcher arguments; Host's java.exe inherits JDK_JAVA_OPTIONS.
    Start-Process @parameters
} finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
