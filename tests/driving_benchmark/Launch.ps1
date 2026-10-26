[CmdletBinding()]
param(
    [ValidateSet('CurrentMods', 'Vanilla')][string]$Profile = 'CurrentMods',
    [string]$GameDir,
    [string]$SourceProfile = (Join-Path $env:USERPROFILE 'Zomboid'),
    [switch]$Menu,
    [switch]$RefreshMods
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:OwnerText = 'PZDrivingBench profile v1'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Assert-NoReparsePoint([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Symbolic links and junctions are not supported here: $($item.FullName)"
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Assert-SeparatePaths([string]$Source, [string]$Destination) {
    $a = (Get-FullPath $Source) + [IO.Path]::DirectorySeparatorChar
    $b = (Get-FullPath $Destination) + [IO.Path]::DirectorySeparatorChar
    if ($a.StartsWith($b, [StringComparison]::OrdinalIgnoreCase) -or
        $b.StartsWith($a, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source profile and isolated profile must not overlap.'
    }
}

function Copy-SafeTree([string]$Source, [string]$Destination) {
    Assert-NoReparsePoint $Source
    Assert-NoReparsePoint $Destination
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force -Recurse)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Cannot copy linked content: $($item.FullName)"
        }
    }
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
    }
}

function Get-ProfileLock([string]$Cache) {
    Assert-NoReparsePoint $Cache
    $marker = Join-Path $Cache '.pz-driving-bench-owner'
    Assert-NoReparsePoint $marker
    if (Test-Path -LiteralPath $Cache) {
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
            ([IO.File]::ReadAllText($marker).Trim() -cne $script:OwnerText)) {
            throw "Refusing to use a foreign existing profile: $Cache"
        }
    } else {
        [IO.Directory]::CreateDirectory($Cache) | Out-Null
        [IO.File]::WriteAllText($marker, $script:OwnerText, $script:Utf8)
    }
    $lockPath = Join-Path $Cache '.pz-driving-bench-lock'
    Assert-NoReparsePoint $lockPath
    try {
        return [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "This profile is already in use, or cannot be locked: $Cache"
    }
}

function Initialize-Profile([string]$Cache, [string]$Source, [string]$Mode, [string]$Package, [switch]$RefreshMods) {
    Assert-SeparatePaths $Source $Cache
    Assert-NoReparsePoint $Source
    # Existing owned profiles may be edited by the user; refuse redirects before any writes.
    foreach ($item in @(Get-ChildItem -LiteralPath $Cache -Force -Recurse)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Linked profile content is unsafe: $($item.FullName)"
        }
    }
    $complete = Join-Path $Cache '.pz-driving-bench-initialized'
    $fresh = -not (Test-Path -LiteralPath $complete)
    if ($RefreshMods -and $Mode -ne 'CurrentMods') { throw '-RefreshMods requires CurrentMods.' }
    $sourceSelection = Join-Path $Source 'mods/default.txt'
    if ($RefreshMods -and -not (Test-Path -LiteralPath $sourceSelection -PathType Leaf)) {
        throw "Cannot refresh mods: source selection is missing: $sourceSelection"
    }
    if ($fresh) {
        foreach ($name in @('options.ini', 'keys.ini')) {
            $path = Join-Path $Source $name
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Assert-NoReparsePoint $path
                Copy-Item -LiteralPath $path -Destination (Join-Path $Cache $name) -Force
            }
        }
    }
    $mods = Join-Path $Cache 'mods'
    [IO.Directory]::CreateDirectory($mods) | Out-Null
    if ($fresh -or $RefreshMods) {
        if ($Mode -eq 'CurrentMods') {
            $sourceMods = Join-Path $Source 'mods'
            if (Test-Path -LiteralPath $sourceMods -PathType Container) {
                Assert-NoReparsePoint $sourceMods
                foreach ($mod in @(Get-ChildItem -LiteralPath $sourceMods -Directory -Force)) {
                    if ($mod.Name -ne 'PZDrivingBench') {
                        Copy-SafeTree $mod.FullName (Join-Path $mods $mod.Name)
                    }
                }
                $selection = $sourceSelection
                if (Test-Path -LiteralPath $selection -PathType Leaf) {
                    Assert-NoReparsePoint $selection
                    Copy-Item -LiteralPath $selection -Destination (Join-Path $mods 'default.txt') -Force
                } else {
                    Write-Warning 'No source mods/default.txt found; enable your Workshop mods in the isolated profile menu.'
                }
            } else {
                Write-Warning 'No source mods folder found; CurrentMods has no imported selection.'
            }
        }
        [IO.File]::WriteAllText($complete, $Mode, $script:Utf8)
    }
    $targetMod = Join-Path $Cache 'mods/PZDrivingBench'
    Copy-SafeTree (Join-Path $Package 'mods/PZDrivingBench') $targetMod
    $selection = Join-Path $Cache 'mods/default.txt'
    $content = "VERSION = 1,`nmods`n{`n}`nmaps`n{`n}`n"
    if ($Mode -eq 'CurrentMods' -and (Test-Path -LiteralPath $selection -PathType Leaf)) {
        $content = [IO.File]::ReadAllText($selection)
    }
    $modsBlock = [regex]::new('(?s)\bmods\s*\{([^{}]*)\}')
    if (-not $modsBlock.IsMatch($content)) { throw 'Unsupported mods/default.txt format; expected a B42 mods block.' }
    $block = $modsBlock.Match($content)
    if (-not [regex]::IsMatch($block.Groups[1].Value, '(?m)^\s*mod\s*=\s*PZDrivingBench\s*,')) {
        $replacement = $block.Value.TrimEnd('}') + "    mod = PZDrivingBench,`n}"
        $content = $content.Substring(0, $block.Index) + $replacement + $content.Substring($block.Index + $block.Length)
    }
    [IO.File]::WriteAllText($selection, $content, $script:Utf8)
    # B42.21 GameWindow.init calls resetDefaultModsForNewRelease("42_00")
    # before loading default.txt. This is an intentionally prepared B42 list:
    # without the native release marker, first boot erases it, including the starter.
    $resetMarker = Join-Path $mods 'reset-mods-42_00.txt'
    if (-not (Test-Path -LiteralPath $resetMarker)) {
        [IO.File]::WriteAllText($resetMarker, 'Prepared Build 42 benchmark mod selection.', $script:Utf8)
    }
    $selected = @([regex]::Matches($modsBlock.Match($content).Groups[1].Value, '(?m)^\s*mod\s*=\s*([^,\r\n]+),') |
        ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ -ne 'PZDrivingBench' })
    Write-Host ("Selected source mods: {0} (+ driving starter)." -f $selected.Count)
    if ($Mode -eq 'CurrentMods' -and $selected.Count -eq 0) {
        Write-Warning 'Only the driving starter is selected. This is effectively vanilla. Open with -Menu to enable your mods; a joined Host selection is not imported.'
    }
    [IO.Directory]::CreateDirectory((Join-Path $Cache 'Server')) | Out-Null
    foreach ($preset in @(Get-ChildItem -LiteralPath (Join-Path $Package 'Server') -File)) {
        $destination = Join-Path $Cache ('Server/' + $preset.Name)
        if (-not (Test-Path -LiteralPath $destination)) {
            Assert-NoReparsePoint $preset.FullName
            Copy-Item -LiteralPath $preset.FullName -Destination $destination
        }
    }
}

function Test-GameDirectory([string]$Path) {
    return ($Path -and (Test-Path -LiteralPath (Join-Path $Path 'ProjectZomboid64.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path 'projectzomboid.jar') -PathType Leaf))
}

function Find-GameDirectory([string]$Requested) {
    if ($Requested) {
        if (-not (Test-GameDirectory $Requested)) { throw "Not a Windows Project Zomboid game directory: $Requested" }
        return Get-FullPath $Requested
    }
    $steamRoots = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $registry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($registry) {
            foreach ($property in @('SteamPath', 'InstallPath')) {
                if ($registry.PSObject.Properties[$property]) { $steamRoots += $registry.$property }
            }
        }
    }
    if (${env:ProgramFiles(x86)}) { $steamRoots += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    $libraries = @($steamRoots)
    foreach ($steam in $steamRoots) {
        $vdf = Join-Path $steam 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s*"([^"\r\n]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    foreach ($library in ($libraries | Select-Object -Unique)) {
        $candidate = Join-Path $library 'steamapps/common/ProjectZomboid'
        if (Test-GameDirectory $candidate) { return Get-FullPath $candidate }
    }
    $answer = Read-Host 'Folder containing ProjectZomboid64.exe and projectzomboid.jar'
    if (-not (Test-GameDirectory $answer)) { throw 'Project Zomboid was not found.' }
    return Get-FullPath $answer
}

function Invoke-DrivingBenchmark {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This launcher requires Windows.' }
    if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Start Steam and sign in first.' }
    $game = Find-GameDirectory $GameDir
    $package = Get-FullPath $PSScriptRoot
    $source = Get-FullPath $SourceProfile
    $cache = Join-Path $package ('Profiles/' + $Profile)
    Assert-SeparatePaths $source $cache
    Assert-SeparatePaths $game $cache
    $lock = Get-ProfileLock $cache
    try {
        Initialize-Profile $cache $source $Profile $package -RefreshMods:$RefreshMods
        $lua = Join-Path $cache 'Lua'
        [IO.Directory]::CreateDirectory($lua) | Out-Null
        $runMarker = Join-Path $lua 'DrivingBench-run.txt'
        if ($Menu) {
            [IO.File]::WriteAllText($runMarker, '', $script:Utf8)
        } else {
            $run = 'PZDrivingBench-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N')
            [IO.File]::WriteAllText($runMarker, $run + "`n", $script:Utf8)
            Write-Host "Fresh benchmark world: $run"
        }
        Write-Host "Profile and logs: $cache"
        # Start-Process joins ArgumentList; quote the entire cachedir argument explicitly.
        $arguments = '"-cachedir=' + $cache + '" -novoip'
        $previousApp = $env:SteamAppId
        $previousGame = $env:SteamGameId
        try {
            $env:SteamAppId = '108600'
            $env:SteamGameId = '108600'
            $process = Start-Process -FilePath (Join-Path $game 'ProjectZomboid64.exe') -WorkingDirectory $game -ArgumentList $arguments -PassThru
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw "Project Zomboid exited with code $($process.ExitCode). See $cache" }
        } finally {
            $env:SteamAppId = $previousApp
            $env:SteamGameId = $previousGame
        }
    } finally {
        $lock.Dispose()
    }
}

# Dot-sourcing exposes safe helper functions for focused tests without launching the game.
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-DrivingBenchmark } catch { Write-Error $_; exit 1 }
}
