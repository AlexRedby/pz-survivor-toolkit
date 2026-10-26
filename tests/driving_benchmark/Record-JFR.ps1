[CmdletBinding()]
param(
    [string]$JdkDir,
    [int]$GamePid = 0,
    [string]$ExpectedExecutablePath,
    [DateTime]$ExpectedStartUtc = [DateTime]::MinValue,
    [ValidateRange(120, 300)][int]$DurationSeconds = 120
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:JfrUtf8 = New-Object System.Text.UTF8Encoding($false)

function Quote-JfrToolArgument([string]$Value) {
    # Windows CreateProcess quoting, including embedded quotes/trailing backslashes.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    return '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
}

function Invoke-JfrTool([string]$Tool, [string[]]$ToolArguments) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Tool
    $start.Arguments = (@($ToolArguments | ForEach-Object { Quote-JfrToolArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Cannot start tool: $Tool" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) {
            # Only our diagnostic tool is terminated, never the game.
            $process.Kill()
            throw "Diagnostic tool timed out after 20 seconds: $Tool"
        }
        return [pscustomobject]@{Code=$process.ExitCode; Output=($stdout.Result + $stderr.Result).Trim()}
    } finally { $process.Dispose() }
}

function Require-JfrToolSuccess($Result, [string]$Action) {
    if ($Result.Code -ne 0) { throw ($Action + ": " + $Result.Output) }
}

function Assert-JfrTargetProcess($Process, [string]$ExpectedExecutablePath, [DateTime]$ExpectedStartUtc) {
    # The launcher supplies identity captured from its own newly started client.
    # A PID alone is insufficient: Windows may reuse it after that client exits.
    if (-not $Process -or $Process.Id -le 0 -or -not $ExpectedExecutablePath -or
        $ExpectedStartUtc -eq [DateTime]::MinValue -or $ExpectedStartUtc.Kind -ne [DateTimeKind]::Utc) {
        throw 'A target process, expected executable and UTC launch time are required.'
    }
    $expectedPath = [IO.Path]::GetFullPath($ExpectedExecutablePath)
    $comparison = [StringComparison]::Ordinal
    if ([Environment]::OSVersion.Platform -eq 'Win32NT') { $comparison = [StringComparison]::OrdinalIgnoreCase }
    try {
        $Process.Refresh()
        if ($Process.HasExited) { throw 'The owned client exited.' }
        # Re-open the PID instead of trusting cached Process properties.
        $current = Get-Process -Id $Process.Id -ErrorAction Stop
        try {
            $current.Refresh()
            if ($current.HasExited) { throw 'The selected client exited.' }
            $path = [IO.Path]::GetFullPath($current.Path)
            $started = $current.StartTime.ToUniversalTime()
            if (-not [string]::Equals($path, $expectedPath, $comparison)) {
                throw 'Executable does not match the owned client launch.'
            }
            if ($started.Ticks -ne $ExpectedStartUtc.Ticks) {
                throw 'Launch time does not match the owned client (stale or reused PID).'
            }
            return [pscustomobject]@{Pid=$current.Id; ExecutablePath=$path; StartUtc=$started}
        } finally { $current.Dispose() }
    } catch {
        throw ('JFR target identity check failed: ' + $_.Exception.Message)
    }
}

function Get-JfrTools([string]$Directory, [string]$GameDirectory) {
    $candidates = @()
    if ($Directory) {
        $Directory = $Directory.Trim().Trim('"')
        $candidates += Join-Path $Directory 'bin/jcmd.exe'
    } else {
        if ($GameDirectory) { $candidates += Join-Path $GameDirectory 'jre64/bin/jcmd.exe' }
        if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin/jcmd.exe' }
        $onPath = Get-Command jcmd.exe -ErrorAction SilentlyContinue
        if ($onPath) { $candidates += $onPath.Source }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $candidate = (Resolve-Path -LiteralPath $candidate).Path
        $jfr = Join-Path ([IO.Path]::GetDirectoryName($candidate)) 'jfr.exe'
        if (-not (Test-Path -LiteralPath $jfr -PathType Leaf)) { continue }
        $version = Invoke-JfrTool $candidate @('-J-version')
        if ($version.Code -eq 0 -and $version.Output -match 'version "25(?:[."]|-)') {
            return [pscustomobject]@{Jcmd=$candidate; Jfr=$jfr; Version=$version.Output}
        }
    }
    return $null
}

function Start-JfrDrivingCapture([string]$Jcmd, [int]$TargetId, [string]$RunDirectory,
                                 [string]$Name, [ValidateRange(1, 300)][int]$Seconds,
                                 [ValidateRange(1, 60)][int]$DelaySeconds = 10,
                                 $TargetProcess = $null, [string]$ExpectedExecutablePath,
                                 [DateTime]$ExpectedStartUtc = [DateTime]::MinValue) {
    $validateIdentity = $null -ne $TargetProcess -or $ExpectedExecutablePath -or $ExpectedStartUtc -ne [DateTime]::MinValue
    $identity = $null
    if ($validateIdentity) {
        $identity = Assert-JfrTargetProcess $TargetProcess $ExpectedExecutablePath $ExpectedStartUtc
        if ($identity.Pid -ne $TargetId) { throw 'Recording PID does not match the owned client.' }
    }
    if ($Name -notmatch '^[A-Za-z0-9_]+$') { throw 'Invalid recording name.' }
    $RunDirectory = [IO.Path]::GetFullPath($RunDirectory)
    if ($RunDirectory.Contains('"') -or $RunDirectory.Contains([string][char]10) -or $RunDirectory.Contains([string][char]13)) {
        throw 'Output path contains unsupported characters.'
    }
    if (Test-Path -LiteralPath $RunDirectory) { throw "Recording directory already exists: $RunDirectory" }
    [IO.Directory]::CreateDirectory($RunDirectory) | Out-Null
    $version = Invoke-JfrTool $Jcmd @([string]$TargetId, 'VM.version')
    Require-JfrToolSuccess $version 'Cannot attach to the selected game'
    if ($version.Output -notmatch '(?:JDK|VM) version 25[.]') { throw ("Expected the Build 42.21 Java 25 runtime. " + $version.Output) }
    [IO.File]::WriteAllText((Join-Path $RunDirectory 'java-version.txt'), $version.Output, $script:JfrUtf8)
    $recording = Join-Path $RunDirectory 'drive.jfr'
    $commandFile = Join-Path $RunDirectory 'start-command.txt'
    # -f preserves diagnostic quotes in Windows PowerShell 5.1, including spaces/apostrophes.
    $command = 'JFR.start name=' + $Name + ' settings=profile delay=' + $DelaySeconds +
        's duration=' + $Seconds + 's disk=true dumponexit=true maxsize=256m filename="' + $recording + '"'
    [IO.File]::WriteAllText($commandFile, $command + [Environment]::NewLine, $script:JfrUtf8)
    $requested = [DateTime]::UtcNow
    if ($validateIdentity) { $null = Assert-JfrTargetProcess $TargetProcess $ExpectedExecutablePath $ExpectedStartUtc }
    $start = Invoke-JfrTool $Jcmd @([string]$TargetId, '-f', $commandFile)
    Require-JfrToolSuccess $start 'JFR.start failed'
    if ($validateIdentity) { $null = Assert-JfrTargetProcess $TargetProcess $ExpectedExecutablePath $ExpectedStartUtc }
    $check = Invoke-JfrTool $Jcmd @([string]$TargetId, 'JFR.check', ('name=' + $Name))
    Require-JfrToolSuccess $check 'JFR.check failed'
    if ($check.Output -notmatch ('\bname=' + [regex]::Escape($Name) + '\b')) {
        throw ("Recording was not acknowledged. " + $start.Output + [Environment]::NewLine + $check.Output)
    }
    $metadata = [ordered]@{
        targetPid=$TargetId; requestedUtc=$requested.ToString('o'); acknowledgedUtc=[DateTime]::UtcNow.ToString('o'); name=$Name
        delaySeconds=$DelaySeconds; durationSeconds=$Seconds; settings='profile'
        recording=$recording; startResponse=$start.Output; checkResponse=$check.Output
    }
    if ($identity) {
        $metadata.targetExecutable = $identity.ExecutablePath
        $metadata.targetStartUtc = $identity.StartUtc.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $RunDirectory 'capture.json'),
        ($metadata | ConvertTo-Json -Depth 4), $script:JfrUtf8)
    return [pscustomobject]@{File=$recording; Directory=$RunDirectory
        ExpectedEnd=[DateTime]::UtcNow.AddSeconds($DelaySeconds + $Seconds + 2)
        EarliestEnd=$requested.AddSeconds($DelaySeconds + $Seconds)}
}

function Invoke-JfrDrivingCapture {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This entry point requires Windows.' }
    $explicitIdentity = $ExpectedExecutablePath -or $ExpectedStartUtc -ne [DateTime]::MinValue
    if ($explicitIdentity) {
        if ($GamePid -le 0) { throw 'Explicit launch identity requires -GamePid.' }
        # Only an exact launch identity permits a java.exe client. Never scan Java processes.
        $games = @(Get-Process -Id $GamePid -ErrorAction Stop)
        $null = Assert-JfrTargetProcess $games[0] $ExpectedExecutablePath $ExpectedStartUtc
    } else {
        $games = @(Get-Process -Name ProjectZomboid64 -ErrorAction SilentlyContinue)
        if ($GamePid) { $games = @($games | Where-Object { $_.Id -eq $GamePid }) }
    }
    if ($games.Count -eq 0) { throw 'Start the game normally, load the driving world, then run Record-JFR.cmd.' }
    if ($games.Count -gt 1) {
        $games | Select-Object Id, MainWindowTitle | Format-Table | Out-Host
        throw 'More than one game client found. Run Record-JFR.cmd -GamePid NUMBER for the intended client.'
    }
    $game = $games[0]
    $targetPath = $game.Path
    $targetStartUtc = $game.StartTime.ToUniversalTime()
    if ($explicitIdentity) {
        $targetPath = $ExpectedExecutablePath
        $targetStartUtc = $ExpectedStartUtc
    }
    $gameDirectory = $null
    try { $gameDirectory = [IO.Path]::GetDirectoryName($game.Path) } catch {}
    $tools = Get-JfrTools $JdkDir $gameDirectory
    if (-not $tools -and -not $JdkDir) {
        Write-Host 'JDK 25 tools are needed. Download a Windows x64 JDK ZIP from https://www.azul.com/downloads/'
        Write-Host 'Extract it; keep the game runtime as it is.'
        $directory = Read-Host 'Paste the extracted JDK 25 folder (it contains bin\jcmd.exe)'
        $tools = Get-JfrTools $directory $gameDirectory
    }
    if (-not $tools) { throw 'JDK 25 not found. Specify -JdkDir "C:\path\to\extracted-jdk-25".' }
    Write-Host ("Game client PID: {0}. JDK tools: {1}" -f $game.Id, $tools.Jcmd)
    Write-Host 'Load the world and sit in the car before continuing.'
    Write-Host 'After Enter: return to the game, wait 10 seconds, start CapFrameX and drive for 90 seconds.'
    Read-Host 'Press Enter when ready' | Out-Null
    $name = 'PZDrive_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N')
    $directory = Join-Path $PSScriptRoot ('JFR/' + $name)
    $game.Refresh()
    if ($game.HasExited) { throw 'The selected game client exited. Start it again before recording.' }
    $capture = Start-JfrDrivingCapture $tools.Jcmd $game.Id $directory $name $DurationSeconds `
        -TargetProcess $game -ExpectedExecutablePath $targetPath -ExpectedStartUtc $targetStartUtc
    Write-Host 'JFR armed. Return to the game now. Keep the game running until the recording finishes.'
    Write-Host ("Files: {0}" -f $capture.Directory)
    while ([DateTime]::UtcNow -lt $capture.ExpectedEnd) {
        $game.Refresh()
        if ($game.HasExited) { break }
        $null = Assert-JfrTargetProcess $game $targetPath $targetStartUtc
        Start-Sleep -Seconds 1
    }
    if (-not (Test-Path -LiteralPath $capture.File -PathType Leaf)) {
        # Allow the target JVM a short final write after recording/normal exit.
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            Start-Sleep -Seconds 1
            if (Test-Path -LiteralPath $capture.File -PathType Leaf) { break }
        }
    }
    if (-not (Test-Path -LiteralPath $capture.File -PathType Leaf)) {
        throw ("No recording file yet. Keep the game open and check this folder: " + $capture.Directory)
    }
    $summary = Invoke-JfrTool $tools.Jfr @('summary', $capture.File)
    Require-JfrToolSuccess $summary 'Recording exists but is not readable'
    [IO.File]::WriteAllText((Join-Path $capture.Directory 'summary.txt'), $summary.Output, $script:JfrUtf8)
    Write-Host 'DONE: JFR is saved and readable. Send drive.jfr and capture.json with the matching CapFrameX JSON.'
    Write-Host $capture.Directory
}

# Dot-source only for focused tests; the normal entry point never changes game/profile files.
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-JfrDrivingCapture } catch {
        Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}
