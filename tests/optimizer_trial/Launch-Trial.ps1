[CmdletBinding()]
param(
    [ValidateSet('Optimized', 'Control')][string]$Mode = 'Optimized',
    [ValidateSet('SinglePlayer','Multiplayer')][string]$Session = 'SinglePlayer',
    [string]$GameDir,
    [string]$WorkshopRoot,
    [string]$JdkDir,
    [ValidateRange(0,65535)][int]$CapFrameXPort = 0,
    [string]$CapFrameXDir,
    [string]$OptimizerZip,
    [string]$SourceProfile = (Join-Path $env:USERPROFILE 'Zomboid'),
    [switch]$SkipWpr,
    [switch]$Menu,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
# The package carries the existing starter/profile helpers alongside this launcher.
$helper = Join-Path $PSScriptRoot 'Launch.ps1'
if (-not (Test-Path -LiteralPath $helper)) { $helper = Join-Path $PSScriptRoot '../driving_benchmark/Launch.ps1' }
. $helper -GameDir $GameDir -SourceProfile $SourceProfile -Menu:$Menu
$jfrHelper = Join-Path $PSScriptRoot 'Record-JFR.ps1'
if (-not (Test-Path -LiteralPath $jfrHelper)) { $jfrHelper = Join-Path $PSScriptRoot '../driving_benchmark/Record-JFR.ps1' }
. $jfrHelper -JdkDir $JdkDir
. (Join-Path $PSScriptRoot 'TrialDiagnostics.ps1')
. (Join-Path $PSScriptRoot 'TrialDownload.ps1')

function Assert-TrialStrings($Values, [string]$Name) {
    if ($Values -isnot [Array]) { throw "$Name must be an array of strings." }
    foreach ($value in $Values) {
        if ($value -isnot [string] -or -not $value -or $value.Contains([char]0) -or $value.Contains("`n") -or $value.Contains("`r")) {
            throw "$Name contains an invalid string."
        }
    }
}

function ConvertTo-WindowsArgument([string]$Value) {
    # CommandLineToArgvW/JDK quoting; Start-Process otherwise joins arguments unsafely.
    $result = New-Object Text.StringBuilder
    [void]$result.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$result.Append(('\' * ($slashes * 2 + 1)))
        } else { [void]$result.Append(('\' * $slashes)) }
        $slashes = 0
        [void]$result.Append($character)
    }
    [void]$result.Append(('\' * ($slashes * 2)))
    [void]$result.Append('"')
    return $result.ToString()
}

function Read-TrialLaunchConfig([string]$Path, [version]$WindowsVersion = [Environment]::OSVersion.Version) {
    Assert-NoReparsePoint $Path
    $config = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    foreach ($property in $config.PSObject.Properties.Name) {
        if ($property -cnotin @('mainClass', 'classpath', 'vmArgs', 'windows')) { throw "Unsupported launcher JSON field: $property" }
    }
    foreach ($required in @('mainClass', 'classpath', 'vmArgs')) {
        if (-not $config.PSObject.Properties[$required]) { throw "Missing launcher JSON field: $required" }
    }
    if ($config.mainClass -cnotin @('zombie/gameStates/MainScreenState', 'zombie.gameStates.MainScreenState')) {
        throw 'Only the native MainScreenState client entry point is supported.'
    }
    Assert-TrialStrings $config.classpath 'classpath'
    Assert-TrialStrings $config.vmArgs 'vmArgs'
    $vm = @($config.vmArgs)
    $selectedVersion = $null
    if ($config.PSObject.Properties['windows']) {
        if ($config.windows -isnot [pscustomobject]) { throw 'windows must contain version-specific vmArgs objects.' }
        foreach ($property in $config.windows.PSObject.Properties) {
            if ($property.Name -notmatch '^\d+\.\d+(\.\d+){0,2}$') { throw "Unsupported Windows version key: $($property.Name)" }
            $version = [version]$property.Name
            $entry = $property.Value
            if ($entry -isnot [pscustomobject] -or @($entry.PSObject.Properties.Name).Count -ne 1 -or -not $entry.PSObject.Properties['vmArgs']) {
                throw "Unsupported Windows launcher fields for $version"
            }
            Assert-TrialStrings $entry.vmArgs "windows.$version.vmArgs"
            if ($version -le $WindowsVersion -and ($null -eq $selectedVersion -or $version -gt $selectedVersion)) {
                $selectedVersion = $version
            }
        }
        if ($null -ne $selectedVersion) { $vm += @($config.windows.PSObject.Properties | Where-Object { [version]$_.Name -eq $selectedVersion } | ForEach-Object { $_.Value.vmArgs }) }
    }
    return [pscustomobject]@{ MainClass = $config.mainClass.Replace('/', '.'); Classpath = @($config.classpath); VmArgs = $vm; WindowsVersion = [string]$selectedVersion }
}

function Get-TrialWindowsVersion {
    # .NET Framework OSVersion can report a compatibility version; query the OS directly.
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if (-not $operatingSystem -or $operatingSystem.Version -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') { throw 'Cannot determine the real Windows version for native JVM/GC selection.' }
    return [version]$operatingSystem.Version
}

function Assert-TrialEnvironment {
    foreach ($name in @('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'JAVA_OPTS', 'CLASSPATH')) {
        if ([Environment]::GetEnvironmentVariable($name)) { throw "Unsupported inherited Java setting: $name. Use a clean terminal for the trial." }
    }
}

function Assert-TrialGame([string]$Game, $Config) {
    Assert-NoReparsePoint $Game
    foreach ($relative in @('projectzomboid.jar', 'ZombieBuddy.jar', 'jre64/bin/java.exe')) {
        $path = Join-Path $Game $relative
        Assert-NoReparsePoint $path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required installed game/loader file missing: $path" }
    }
    foreach ($relative in @('pzopt', 'pzopt.jar', 'pzopt-files.txt', 'pzopt-installed.txt', 'pzopt.properties')) {
        if (Test-Path -LiteralPath (Join-Path $Game $relative)) { throw "Existing optimizer installation/configuration must be removed first: $relative" }
    }
    foreach ($relative in @('zombie', 'org/lwjglx', 'se/krka', 'fmod/fmod')) {
        $path = Join-Path $Game $relative
        if (Test-Path -LiteralPath $path) {
            Assert-NoReparsePoint $path
            foreach ($item in @(Get-ChildItem -LiteralPath $path -Force -Recurse)) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Extension -ieq '.class') { throw "Existing loose/linked game class overrides: $($item.FullName)" }
            }
        }
    }
    if (@(Get-ChildItem -LiteralPath $Game -File | Where-Object { $_.Name -match '(?i)(PZOptim|PZO[-_.])' }).Count) { throw 'Existing PZO/optimizer files found in the game directory.' }
    $hasZb = $false; $usesNative = $false
    foreach ($argument in $Config.VmArgs) {
        if ($argument -match '^(?i)(@|-cp$|-classpath$|--class-path|-jar$|--module|-Djava\.class\.path=|-Dpzopt\.|-Dpz\.optimizerTrial\.)') { throw "Unsupported launcher VM argument: $argument" }
        $loader = $false
        if ($argument.StartsWith('-javaagent:', [StringComparison]::OrdinalIgnoreCase)) {
            if ($argument -notmatch '^(?i)-javaagent:(.+?\.jar)(?:=(.*))?$') { throw "Unsupported Java agent: $argument" }
            $jar = $Matches[1].Trim('"')
            if (-not [IO.Path]::IsPathRooted($jar)) { $jar = Join-Path $Game $jar }
            if ((Get-FullPath $jar) -ine (Get-FullPath (Join-Path $Game 'ZombieBuddy.jar'))) { throw "Unsupported Java agent: $argument" }
            $loader = $true
        } elseif ($argument.StartsWith('-agentlib:', [StringComparison]::OrdinalIgnoreCase)) {
            if ($argument -notmatch '^(?i)-agentlib:zbNative(?:=.*)?$') { throw "Unsupported native Java agent: $argument" }
            $loader = $true; $usesNative = $true
        } elseif ($argument.StartsWith('-agentpath:', [StringComparison]::OrdinalIgnoreCase)) {
            if ($argument -notmatch '^(?i)-agentpath:(.+?\.dll)(?:=(.*))?$') { throw "Unsupported native Java agent path: $argument" }
            $dll = $Matches[1].Trim('"')
            if (-not [IO.Path]::IsPathRooted($dll)) { $dll = Join-Path $Game $dll }
            if ((Get-FullPath $dll) -ine (Get-FullPath (Join-Path $Game 'zbNative.dll'))) { throw "Unsupported native Java agent path: $argument" }
            $loader = $true; $usesNative = $true
        }
        if ($loader) {
            if ($hasZb) { throw 'Duplicate ZombieBuddy loaders in launcher JSON; keep exactly one native or Java agent.' }
            if ($argument -match '(?i)patches_jar=|pzopt|PZOptim') { throw "Unsupported ZombieBuddy agent settings: $argument" }
            $hasZb = $true
        }
    }
    # Official zbNative Agent_OnLoad proxies instrument.dll and loads ZombieBuddy.jar itself.
    # It is one complete loader; adding -javaagent as well would initialize it twice.
    if ($usesNative -or -not $hasZb) {
        $dll = Join-Path $Game 'zbNative.dll'
        Assert-NoReparsePoint $dll
        if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw "Installed ZombieBuddy native loader missing: $dll" }
    }
    foreach ($entry in $Config.Classpath) {
        if ($entry -match '(?i)pzopt|PZOptim' -or $entry.Contains('*')) { throw "Unsupported launcher classpath: $entry" }
        $path = $entry
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $Game $path }
        Assert-NoReparsePoint $path
        if (-not (Test-Path -LiteralPath $path)) { throw "Launcher classpath entry missing: $entry" }
    }
    if (-not $hasZb) { $Config.VmArgs = @($Config.VmArgs) + '-agentlib:zbNative' }
}

function Assert-TrialNoHarness([string]$Root) {
    foreach ($relative in @('pzopt-harness.txt', 'Lua/pzopt-harness.txt', 'pzopt/benchmark/plan.properties', 'pzopt.properties')) {
        if (Test-Path -LiteralPath (Join-Path $Root $relative)) { throw "Optimizer harness/configuration is not allowed in this trial: $Root/$relative" }
    }
}

function Get-TrialHash([IO.Stream]$Stream) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Assert-TrialEntryName([string]$Name) {
    if (-not $Name -or $Name.StartsWith('/') -or $Name.Contains('\') -or $Name.Contains(':') -or $Name -match '(^|/)(\.|\.\.)(/|$)' -or $Name.Contains([char]0)) { throw "Unsafe archive/resource path: $Name" }
}

function Read-TrialManifest([string]$Path) {
    Assert-NoReparsePoint $Path
    $manifest = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    foreach ($name in @('release_url', 'release_sha256', 'selected_files', 'native_guards')) {
        if (-not $manifest.PSObject.Properties[$name]) { throw "Candidate manifest lacks $name" }
    }
    if ($manifest.release_url -notmatch '^https://github\.com/xD3I/PZ_Optimization/releases/download/[^/]+/[^/]+$' -or $manifest.release_sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Candidate must pin an official release URL and SHA-256.' }
    foreach ($kind in @('selected_files', 'native_guards')) {
        if ($manifest.$kind -isnot [pscustomobject] -or @($manifest.$kind.PSObject.Properties).Count -eq 0) { throw "Empty/invalid manifest $kind" }
        foreach ($property in $manifest.$kind.PSObject.Properties) {
            Assert-TrialEntryName $property.Name
            if ($property.Value -isnot [string] -or $property.Value -notmatch '^[a-f0-9]{64}$') { throw "Invalid manifest hash for $($property.Name)" }
            if ($kind -eq 'selected_files' -and $property.Name -cnotmatch '^pzopt/.+\.(class|properties)$') {
                $family = ($property.Name -split '\$', 2)[0] -replace '\.class$', ''
                if ($property.Name -cnotmatch '\.class$' -or $family -cnotin @(
                    'org/lwjglx/input/Mouse',
                    'org/lwjglx/opengl/Display',
                    'se/krka/kahlua/j2se/KahluaTableImpl',
                    'zombie/Lua/LuaEventManager',
                    'zombie/MovingObjectUpdateScheduler',
                    'zombie/MovingObjectUpdateSchedulerUpdateBucket',
                    'zombie/WorldSoundManager',
                    'zombie/characters/IsoGameCharacter',
                    'zombie/characters/IsoZombie',
                    'zombie/characters/SurvivorDesc',
                    'zombie/characters/action/ActionContext',
                    'zombie/characters/action/conditions/CharacterVariableCondition',
                    'zombie/core/SpriteRenderer',
                    'zombie/core/opengl/IOpenGLState',
                    'zombie/core/opengl/ShaderUniformSetter',
                    'zombie/core/opengl/ShaderUnit',
                    'zombie/core/opengl/VBORenderer',
                    'zombie/core/properties/PropertyContainer',
                    'zombie/core/skinnedmodel/DeadBodyAtlas',
                    'zombie/core/skinnedmodel/ModelManager',
                    'zombie/core/skinnedmodel/advancedanimation/AnimationSet',
                    'zombie/core/skinnedmodel/animation/AnimationPlayer',
                    'zombie/core/skinnedmodel/model/Model',
                    'zombie/core/skinnedmodel/model/ModelInstance',
                    'zombie/core/skinnedmodel/model/ModelSlotRenderData',
                    'zombie/core/textures/ImageData',
                    'zombie/core/textures/MultiTextureFBO2',
                    'zombie/core/textures/TextureCombiner',
                    'zombie/core/textures/TextureDraw',
                    'zombie/input/ControllerStateCache',
                    'zombie/input/GameKeyboard',
                    'zombie/input/KeyboardState',
                    'zombie/input/KeyboardStateCache',
                    'zombie/input/MouseState',
                    'zombie/input/MouseStateCache',
                    'zombie/iso/IsoChunk',
                    'zombie/iso/IsoChunkMap',
                    'zombie/iso/IsoGridSquare',
                    'zombie/iso/IsoMovingObject',
                    'zombie/iso/IsoObject',
                    'zombie/iso/IsoPuddles',
                    'zombie/iso/IsoWorld',
                    'zombie/iso/LightingJNI',
                    'zombie/iso/fboRenderChunk/FBORenderCell',
                    'zombie/iso/fboRenderChunk/FBORenderCutaways',
                    'zombie/iso/fboRenderChunk/FBORenderTrees',
                    'zombie/iso/objects/IsoLightSwitch',
                    'zombie/iso/sprite/IsoSprite',
                    'zombie/iso/weather/fx/WeatherFxMask',
                    'zombie/iso/worldgen/WorldGenUtils',
                    'zombie/tileDepth/TileDepthTexture',
                    'zombie/vispoly/VisibilityPolygon2'
                )) { throw "File is outside the reviewed allowlist: $($property.Name)" }
            }
            if ($kind -eq 'native_guards' -and $property.Name -cnotmatch '\.class$') { throw 'Native guards must be class resources.' }
        }
    }
    foreach ($required in @('zombie/iso/worldgen/WorldGenUtils.class', 'zombie/core/skinnedmodel/advancedanimation/AnimationSet.class')) {
        if (-not $manifest.selected_files.PSObject.Properties[$required]) { throw "Required selected class missing: $required" }
    }
    if ($manifest.PSObject.Properties['format'] -and $manifest.format -eq 2) {
        if (-not $manifest.PSObject.Properties['native_absences']) { throw 'Missing absence guards.' }
        foreach ($name in $manifest.native_absences) {
            Assert-TrialEntryName $name
            if ($name -cnotmatch '\.class$' -or -not $manifest.selected_files.PSObject.Properties[$name] -or $manifest.native_guards.PSObject.Properties[$name]) { throw "Invalid absence guard: $name" }
        }
    }
    return $manifest
}

function Assert-TrialNativeGuards([string]$Jar, $Guards) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Jar)
    try {
        foreach ($property in $Guards.PSObject.Properties) {
            $entry = $archive.GetEntry($property.Name)
            if ($null -eq $entry) { throw "Native game class missing: $($property.Name)" }
            $stream = $entry.Open()
            try { if ((Get-TrialHash $stream) -cne $property.Value) { throw "Unsupported native game bytes: $($property.Name)" } }
            finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
}

function Assert-TrialClasspathGuards([string]$Game, $Classpath, $Guards) {
    # Validate the resource the AppClassLoader will actually choose, not just the native JAR.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $remaining = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($property in $Guards.PSObject.Properties) { [void]$remaining.Add($property.Name) }
    foreach ($entry in $Classpath) {
        if ($remaining.Count -eq 0) { break }
        $path = $entry
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $Game $path }
        Assert-NoReparsePoint $path
        if (Test-Path -LiteralPath $path -PathType Container) {
            foreach ($resource in @($remaining)) {
                $file = Join-Path $path $resource
                Assert-NoReparsePoint $file
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
                $stream = [IO.File]::OpenRead($file)
                try { $hash = Get-TrialHash $stream } finally { $stream.Dispose() }
                if ($hash -cne $Guards.PSObject.Properties[$resource].Value) { throw "Effective classpath shadows protected native class: $resource in $path" }
                [void]$remaining.Remove($resource)
            }
        } else {
            $archive = [IO.Compression.ZipFile]::OpenRead($path)
            try {
                foreach ($resource in @($remaining)) {
                    $found = $archive.GetEntry($resource)
                    if ($null -eq $found) { continue }
                    $stream = $found.Open()
                    try { $hash = Get-TrialHash $stream } finally { $stream.Dispose() }
                    if ($hash -cne $Guards.PSObject.Properties[$resource].Value) { throw "Effective classpath shadows protected native class: $resource in $path" }
                    [void]$remaining.Remove($resource)
                }
            } finally { $archive.Dispose() }
        }
    }
    if ($remaining.Count) { throw "Protected classes missing from effective classpath: $($remaining -join ', ')" }
}

function Assert-TrialNativeAbsences([string]$Game, $Classpath, $Absences) {
    # These nine nested classes were added by the pinned optimizer and have no stock bytes.
    # Require their absence in every original classpath entry rather than skipping a hash guard.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($entry in $Classpath) {
        $path = $entry
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $Game $path }
        Assert-NoReparsePoint $path
        if (Test-Path -LiteralPath $path -PathType Container) {
            foreach ($name in $Absences) {
                if (Test-Path -LiteralPath (Join-Path $path $name)) { throw "Unexpected pre-existing optimizer class: $name in $path" }
            }
        } else {
            $archive = [IO.Compression.ZipFile]::OpenRead($path)
            try { foreach ($name in $Absences) { if ($null -ne $archive.GetEntry($name)) { throw "Unexpected pre-existing optimizer class: $name in $path" } } }
            finally { $archive.Dispose() }
        }
    }
}

function Expand-TrialCandidate([string]$Zip, [string]$Overlay, $Manifest) {
    Assert-NoReparsePoint $Zip
    Assert-NoReparsePoint $Overlay
    if ((Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Manifest.release_sha256) { throw 'Official optimizer ZIP SHA-256 mismatch.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $entries = New-Object 'Collections.Generic.Dictionary[string,System.IO.Compression.ZipArchiveEntry]' ([StringComparer]::Ordinal)
        $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $archive.Entries) {
            Assert-TrialEntryName $entry.FullName
            if (-not $seen.Add($entry.FullName)) { throw "Duplicate archive entry: $($entry.FullName)" }
            if ((($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw "Linked archive entry: $($entry.FullName)" }
            $entries.Add($entry.FullName, $entry)
        }
        foreach ($property in $Manifest.selected_files.PSObject.Properties) {
            if (-not $entries.ContainsKey($property.Name)) { throw "Selected archive resource missing: $($property.Name)" }
            $stream = $entries[$property.Name].Open()
            try { if ((Get-TrialHash $stream) -cne $property.Value) { throw "Selected resource SHA-256 mismatch: $($property.Name)" } }
            finally { $stream.Dispose() }
        }
        # Never tolerate extra or modified files in a reused overlay.
        if (Test-Path -LiteralPath $Overlay) {
            foreach ($item in @(Get-ChildItem -LiteralPath $Overlay -Force -Recurse)) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked overlay content: $($item.FullName)" }
                $name = $item.FullName.Substring((Get-FullPath $Overlay).Length + 1).Replace('\', '/')
                if ($item.PSIsContainer) {
                    $prefix = $name + '/'
                    if (-not @($Manifest.selected_files.PSObject.Properties.Name | Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) }).Count) { throw "Unexpected overlay directory: $name" }
                    continue
                }
                $expected = $Manifest.selected_files.PSObject.Properties[$name]
                if (-not $expected -or $expected.Name -cne $name -or (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected.Value) { throw "Unexpected or modified overlay file: $name" }
            }
        }
        foreach ($property in $Manifest.selected_files.PSObject.Properties) {
            $destination = Join-Path $Overlay $property.Name
            Assert-NoReparsePoint $destination
            if (Test-Path -LiteralPath $destination) { continue }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            $inputStream = $entries[$property.Name].Open()
            try {
                $output = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $inputStream.CopyTo($output) } finally { $output.Dispose() }
            } finally { $inputStream.Dispose() }
        }
    } finally { $archive.Dispose() }
}

function Get-TrialCandidate([string]$Package, $Manifest, [string]$SourceZip) {
    $candidate = Join-Path $Package 'Candidate'
    Assert-NoReparsePoint $candidate
    [IO.Directory]::CreateDirectory($candidate) | Out-Null
    $zip = Join-Path $candidate 'official-classes.zip'
    Assert-NoReparsePoint $zip
    if (-not (Test-Path -LiteralPath $zip)) {
        $temporary = Join-Path $candidate ([Guid]::NewGuid().ToString('N') + '.download')
        $statusPath = Join-Path $candidate 'last-download.json'
        Assert-NoReparsePoint $statusPath
        $state = [ordered]@{startedUtc=[DateTime]::UtcNow.ToString('o');status='Preparing';bytes=0;source='Official release';partialFile=[IO.Path]::GetFileName($temporary);error=$null}
        $tls = [Net.ServicePointManager]::SecurityProtocol
        try {
            if ($SourceZip) {
                $source = Get-FullPath ($SourceZip.Trim().Trim('"'))
                Assert-NoReparsePoint $source
                if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'The supplied -OptimizerZip file does not exist.' }
                Write-Host '[Optimizer] Checking the browser-downloaded ZIP SHA-256...'
                if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Manifest.release_sha256) { throw 'The supplied optimizer ZIP does not match the pinned official SHA-256.' }
                $state.source='Explicit local ZIP'
                [IO.File]::Copy($source,$temporary,$false)
            } else {
                $expected = 0L
                if ($Manifest.PSObject.Properties['release_bytes']) { $expected = [long]$Manifest.release_bytes }
                $state.status='Downloading'
                Write-TrialDiagnosticJson $statusPath $state
                Write-Host ('[Optimizer] Downloading official ZIP. Expected bytes: ' + $expected)
                [Net.ServicePointManager]::SecurityProtocol = $tls -bor [Net.SecurityProtocolType]::Tls12
                $null = Save-TrialDownload $Manifest.release_url $temporary -ExpectedBytes $expected
                Write-Host '[Optimizer] Download finished. Checking ZIP SHA-256...'
            }
            $state.bytes=(Get-Item -LiteralPath $temporary).Length
            $state.status='Verifying'
            Write-TrialDiagnosticJson $statusPath $state
            if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Manifest.release_sha256) { throw 'Downloaded official ZIP SHA-256 mismatch. The partial file is preserved and will not be used.' }
            [IO.File]::Move($temporary,$zip)
            $state.status='Verified'; $state.partialFile=$null
            Write-TrialDiagnosticJson $statusPath $state
        } catch {
            $state.status='Failed'; $state.error=$_.Exception.Message
            if (Test-Path -LiteralPath $temporary -PathType Leaf) { $state.bytes=(Get-Item -LiteralPath $temporary).Length }
            Write-TrialDiagnosticJson $statusPath $state
            Write-Host ('[Optimizer] Failed after ' + $state.bytes + ' bytes. Details: ' + $statusPath)
            Write-Host '[Optimizer] Browser fallback: place the pinned official ZIP at Candidate\official-classes.zip, or use -OptimizerZip with its path.'
            throw
        } finally { [Net.ServicePointManager]::SecurityProtocol = $tls }
    } else { Write-Host '[Optimizer] Reusing cached official-classes.zip; no download. Checking SHA-256 and selected resources...' }
    $overlay = Join-Path $candidate 'overlay'
    Write-Host ('[Optimizer] Validating archive and preparing ' + @($Manifest.selected_files.PSObject.Properties).Count + ' selected files...')
    Expand-TrialCandidate $zip $overlay $Manifest
    Write-Host '[Optimizer] Archive and selected files verified. Optimizer preparation complete.'
    return [pscustomobject]@{ Zip = (Get-FullPath $zip); Overlay = (Get-FullPath $overlay); Profile = $Manifest.profile }
}

. (Join-Path $PSScriptRoot 'Pack.ps1')

function Write-TrialOptimizerArguments([string]$Cache, $Profile) {
    if (-not $Profile -or $Profile.id -cne 'xd3i-b42.21-d1bbdcf-bounded-v1' -or $Profile.properties -isnot [pscustomobject]) { throw 'Unsupported optimizer trial profile.' }
    if (@($Profile.properties.PSObject.Properties).Count -ne 770) { throw 'Incomplete or extended optimizer property inventory.' }
    $lines = @('-Dpz.optimizerTrial.profile=' + $Profile.id)
    foreach ($property in $Profile.properties.PSObject.Properties) {
        # These are controlled ASCII property values, not arbitrary JVM arguments or file paths.
        if ($property.Name -cnotmatch '^[A-Za-z][A-Za-z0-9]*$' -or $property.Value -isnot [string] -or $property.Value -cnotmatch '^[A-Za-z0-9.,_/-]*$') { throw "Unsafe optimizer property: $($property.Name)" }
        $lines += '-Dpzopt.' + $property.Name + '=' + $property.Value
    }
    $path = Join-Path $Cache 'optimizer-profile.args'
    Assert-NoReparsePoint $path
    [IO.Directory]::CreateDirectory($Cache) | Out-Null
    [IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), $script:Utf8)
    return $path
}

function New-TrialPlan([string]$Game, [string]$Cache, [string]$TrialMode, $Config, $Candidate,
    [ValidateSet('SinglePlayer','Multiplayer')][string]$SessionType = 'SinglePlayer') {
    $classpath = @($Config.Classpath)
    $vm = @($Config.VmArgs)
    $profile = $null; $profileArgs = $null
    if ($TrialMode -eq 'Optimized') {
        $classpath = @($Candidate.Overlay) + $classpath
        $profile = $Candidate.Profile
        $profileArgs = Write-TrialOptimizerArguments $Cache $profile
        $vm += @(('@' + $profileArgs), '-Dpz.optimizerTrial.prewarm=true', ('-Dpz.optimizerTrial.sourceZip=' + $Candidate.Zip), ('-Dpz.optimizerTrial.cachedir=' + $Cache), ('-Dpz.optimizerTrial.overlay=' + $Candidate.Overlay), ('-Dpz.optimizerTrial.mode=' + $SessionType.ToLowerInvariant()))
    } else { $vm += '-Dpz.optimizerTrial.prewarm=false' }
    $arguments = @($vm) + @('-cp', ($classpath -join ';'), $Config.MainClass, ('-cachedir=' + $Cache), '-novoip')
    return [pscustomobject]@{ Mode = $TrialMode; Session = $SessionType; Java = (Join-Path $Game 'jre64/bin/java.exe'); WorkingDirectory = $Game; Cache = $Cache; OptimizerProfile = $profile; OptimizerArguments = $profileArgs; WindowsVmVersion = $Config.WindowsVersion; VmArgs = $vm; Classpath = $classpath; MainClass = $Config.MainClass; Arguments = $arguments; CommandLine = (($arguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '); Pid = $null; JavaExitCode = $null; Activation = 'CheckedOnly'; Logs = $null; Readiness = $null; ProcessStartUtc = $null; FinishedUtc = $null; Diagnostics = $null; automaticCapFrameX = $true; gameContextPolicy = 'BufferedWorldExitV2'; TrialWorld = $null }
}

function New-TrialRunName {
    return 'PZDrivingBench-OptimizerTrial-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N')
}

function Test-TrialWorldReady([string]$Text) {
    # The starter verifies the actual driver and engine. Context samples stay
    # in memory until world exit and cannot be a console-based readiness gate.
    return $Text.Contains('[PZDrivingBench] READY driver=true engine=true')
}

function New-TrialSessionLogs([string]$Cache) {
    $directory = Join-Path $Cache ('TrialRuns/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
    Assert-NoReparsePoint $directory
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $console = Join-Path $Cache 'console.txt'
    Assert-NoReparsePoint $console
    if (Test-Path -LiteralPath $console) {
        Move-Item -LiteralPath $console -Destination (Join-Path $directory 'previous-console.txt')
    }
    return [pscustomobject]@{ Directory = $directory; Stdout = (Join-Path $directory 'stdout.txt'); Stderr = (Join-Path $directory 'stderr.txt'); Console = $console; Receipt = (Join-Path $directory 'launch.json') }
}

function Read-TrialSessionText($Logs) {
    $text = New-Object Text.StringBuilder
    # previous-console.txt is intentionally excluded: it belongs to an earlier process.
    foreach ($path in @($Logs.Stdout, $Logs.Stderr, $Logs.Console)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                try {
                    $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
                    try { [void]$text.AppendLine($reader.ReadToEnd()) } finally { $reader.Dispose() }
                } finally { $stream.Dispose() }
            }
            catch [IO.IOException] { } # The game may briefly hold its fresh console file exclusively.
        }
    }
    return $text.ToString()
}

function Get-TrialPackActivation([string]$Text, [string]$Revision, [int]$ExpectedCount = 69) {
    # Lua print is prefixed by the native logger (for example LOG : Lua f:0>).
    $active = $Text -match ('(?m)^[^\r\n]*\[OptimizerTrial\] pack active revision=' + [regex]::Escape($Revision) + ' count=' + $ExpectedCount + '[ \t\r]*$')
    $failed = $Text -match '\[OptimizerTrial\] PACK_MISMATCH'
    $missing = @()
    if (-not $active) { $missing += 'current-main full modpack activation' }
    if ($Revision) {
        if (-not $Text.Contains('[PZToolkitJavaPatches] Experimental B42.21 patch:')) { $missing += 'current-main Toolkit Java patches activation' }
        if ($Text -match '(?im)^.*PZToolkitJavaPatches.*(?:blocked|denied)|^.*(?:blocked|denied).*PZToolkitJavaPatches') { $failed = $true }
    }
    return [pscustomobject]@{ Ready = ($missing.Count -eq 0 -and -not $failed); Failed = [bool]$failed; Missing = $missing }
}

function Get-TrialReadiness([string]$Text, [string]$PackRevision = '', [int]$ExpectedCount = 69,
    [ValidateSet('SinglePlayer','Multiplayer')][string]$SessionType = 'SinglePlayer') {
    $missing = @(); $packFailed = $false
    if ($PackRevision) {
        $packState = Get-TrialPackActivation $Text $PackRevision $ExpectedCount
        $missing += @($packState.Missing)
        $packFailed = $packState.Failed
    }
    foreach ($marker in @(
        ('[OptimizerTrial] prewarm armed; awaiting OnGameBoot; mode=' + $SessionType.ToLowerInvariant()),
        '[OptimizerTrial] official cache and preload active',
        '[OptimizerTrial] extended active profile=xd3i-b42.21-d1bbdcf-bounded-v1 tileBatch=true bakeScheduler=true occlusionRetain=true chunkHandoffDivisor=8',
        '[OptimizerTrial] OnGameBoot animation preload started',
        '[OptimizerTrial] animation preload joined; animal preload started'
    )) {
        if (-not $Text.Contains($marker)) { $missing += $marker }
    }
    if ($SessionType -eq 'Multiplayer' -and -not $Text.Contains('[OptimizerTrial] bridge ready mode=multiplayer client=true server=false session=1')) { $missing += 'connected multiplayer bridge lifecycle' }
    if ($SessionType -eq 'Multiplayer' -and -not $Text.Contains('[OptimizerTrial] animal drain invoked mode=multiplayer client=true server=false')) { $missing += 'connected multiplayer animal drain' }
    if ($Text -notmatch '\[OptimizerTrial\] bake scheduler used frames=[1-9][0-9]* grants=[1-9][0-9]*') { $missing += 'actual chunk bake grants used' }
    if ($Text -notmatch '\[OptimizerTrial\] tile batch used starts=[1-9][0-9]* merged=[1-9][0-9]* stamped=[1-9][0-9]*') { $missing += 'actual merged tile draws with a usable patched shader' }
    if ($Text -notmatch 'anim sets preloaded in \d+(?:[.,]\d+)? s') { $missing += 'official animation preload completion' }
    $parsed = [regex]::Matches($Text, 'animalPreload: (\d+) animation sets, (\d+) action groups parsed')
    $handoffs = [regex]::Matches($Text, 'animalPreload: (\d+) action groups handed to the game, (\d+) it had loaded first')
    $groups = $null; $handed = $null
    if ($parsed.Count -eq 0) { $missing += 'official animal parse completion' }
    else { $groups = [long]$parsed[$parsed.Count - 1].Groups[2].Value }
    if ($handoffs.Count -eq 0) { $missing += 'official action-group handoff' }
    else {
        $last = $handoffs[$handoffs.Count - 1]
        $handed = [long]$last.Groups[1].Value + [long]$last.Groups[2].Value
        if ($null -ne $groups -and $handed -lt $groups) { $missing += "action-group handoff incomplete ($handed/$groups)" }
    }
    $failed = $Text -match '\[OptimizerTrial\] PACK_MISMATCH|\[OptimizerTrial\] prewarm disabled:|(?im)^.*PZDrivingOptimizerBridge.*(?:blocked|denied)|(?im)^.*(?:blocked|denied).*PZDrivingOptimizerBridge|overrides disabled, running stock behaviour'
    $failed = $failed -or $packFailed
    return [pscustomobject]@{ Ready = ($missing.Count -eq 0 -and -not $failed); Failed = [bool]$failed; Missing = @($missing); ActionGroups = $groups; HandedOff = $handed }
}

function Get-TrialRunReadiness([string]$Text,
    [ValidateSet('Optimized','Control')][string]$TrialMode,
    [string]$PackRevision, [int]$ExpectedCount,
    [ValidateSet('SinglePlayer','Multiplayer')][string]$SessionType,
    [string]$ContextId = '', [switch]$Menu, [bool]$PreviousFailure = $false) {
    if ($TrialMode -eq 'Optimized') {
        $state = Get-TrialReadiness $Text $PackRevision $ExpectedCount -SessionType $SessionType
    } else {
        $state = Get-TrialPackActivation $Text $PackRevision $ExpectedCount
    }
    $missing = @($state.Missing)
    if ($TrialMode -eq 'Control' -and -not $Text.Contains('[OptimizerTrial] bridge inactive: explicit opt-in absent')) {
        $missing += 'verified inactive bridge lifecycle'
    }
    if ($SessionType -eq 'Multiplayer') {
        $contextPattern = '(?m)^[^\r\n]*\[OptimizerTrial\] multiplayer context ready world=' + [regex]::Escape($ContextId) + '[ \t\r]*$'
        if (-not $ContextId -or $Text -notmatch $contextPattern) { $missing += 'connected multiplayer context observer' }
    } elseif (-not $Menu -and -not (Test-TrialWorldReady $Text)) {
        $missing += 'single-player starter world and car readiness'
    }
    $failurePattern = '\[PZDrivingBench\] FAIL |\[OptimizerTrial\] (?:prewarm disabled:|drive telemetry disabled|telemetry flush failed)|(?im)^.*PZDrivingOptimizerBridge.*(?:blocked|denied)|^.*(?:blocked|denied).*PZDrivingOptimizerBridge'
    $failed = [bool]$state.Failed -or $PreviousFailure -or $Text -match $failurePattern
    $groups = $null; $handed = $null
    if ($TrialMode -eq 'Optimized') { $groups = $state.ActionGroups; $handed = $state.HandedOff }
    return [pscustomobject]@{ Ready = ($missing.Count -eq 0 -and -not $failed); Failed = [bool]$failed;
        Missing = @($missing); ActionGroups = $groups; HandedOff = $handed }
}

function Save-TrialPlan($Plan, [string]$Path) {
    $json = $Plan | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($Path, $json, $script:Utf8)
    if ($null -ne $Plan.Logs) { [IO.File]::WriteAllText($Plan.Logs.Receipt, $json, $script:Utf8) }
}

function Invoke-OptimizerTrial {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This launcher requires Windows.' }
    Assert-TrialEnvironment
    $game = Find-GameDirectory $GameDir
    $package = Get-FullPath $PSScriptRoot
    Assert-TrialNoHarness $game
    $windowsVersion = Get-TrialWindowsVersion
    $config = Read-TrialLaunchConfig (Join-Path $game 'ProjectZomboid64.json') -WindowsVersion $windowsVersion
    Assert-TrialGame $game $config
    $manifest = Read-TrialManifest (Join-Path $package 'candidate-manifest.json')
    # This happens before any foreign Java code, including the bridge or optimizer, can initialize.
    Assert-TrialNativeGuards (Join-Path $game 'projectzomboid.jar') $manifest.native_guards
    Assert-TrialClasspathGuards $game $config.Classpath $manifest.native_guards
    Assert-TrialNativeAbsences $game $config.Classpath $manifest.native_absences
    $cache = Join-Path $package 'Profiles/OptimizerTrial'
    Assert-SeparatePaths $game $cache
    Assert-SeparatePaths (Get-FullPath $SourceProfile) $cache
    $workshop = $WorkshopRoot
    if (-not $workshop) { $workshop = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($game))) 'workshop/content/108600' }
    # Resolve every required mod before profile lock creation or initialization writes.
    $resolved = Resolve-TrialPack $package (Get-FullPath $SourceProfile) $workshop -SessionType $Session
    $jfrTools = $null; $frameClient = $null
    if (-not $Menu) {
        $jfrTools = Resolve-TrialJfrTools $package $game $JdkDir
        $frameClient = Get-TrialCapFrameX $CapFrameXPort -Directory $CapFrameXDir
    }
    $lock = Get-ProfileLock $cache
    try {
        Initialize-TrialProfile $cache (Get-FullPath $SourceProfile) $package $resolved
        Assert-TrialNoHarness $cache
        $candidate = $null
        if ($Mode -eq 'Optimized') { $candidate = Get-TrialCandidate $package $manifest -SourceZip $OptimizerZip }
        $plan = New-TrialPlan $game $cache $Mode $config $candidate -SessionType $Session
        $plan.automaticCapFrameX = -not $Menu
        $plan | Add-Member -NotePropertyName Pack -NotePropertyValue ([pscustomobject]@{ MainRevision = $resolved.Pack.main_revision; ModIds = $resolved.Ids; Sources = @($resolved.Sources | Select-Object Id, Kind, Root, Info, Version, WorkshopId) })
        Write-Host ("Pinned candidate pack {0}: {1} active mods; session={2}." -f $resolved.Pack.main_revision, $resolved.Ids.Count, $Session)
        foreach ($sourceMod in $resolved.Sources) { Write-Host ("  {0}: {1}, version={2}, Workshop={3}, source={4}" -f $sourceMod.Id, $sourceMod.Kind, $sourceMod.Version, $sourceMod.WorkshopId, $sourceMod.Root) }
        $log = Join-Path $cache ('launch-' + $Mode.ToLowerInvariant() + '.json')
        Save-TrialPlan $plan $log
        Write-Host "Checked $Mode trial. Profile and logs: $cache"
        if (-not $Menu) { Write-Host 'CapFrameX remote control is ready. The capture will be bound to the launched game PID.' }
        else { Write-Host 'MENU: launch without automatic recording; CapFrameX, recording JDK and WPR are not required.' }
        if ($CheckOnly) { Write-Host 'Setup checks only; game startup and activation have not been verified.'; return }
        if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Start Steam and sign in first.' }
        if ($Session -eq 'Multiplayer') { Write-Host 'MULTIPLAYER: open Host or Join from the game menu. No starter world, teleport or vehicle spawn. Restart the game before each connection/recording.' }
        elseif (-not $Menu) { Write-Host 'SINGLE PLAYER: one game process; creating a fresh test world with a ready car. Run Control and Optimized sequentially, closing the game between runs.' }
        $lua = Join-Path $cache 'Lua'
        [IO.Directory]::CreateDirectory($lua) | Out-Null
        $run = ''
        if (-not $Menu -and $Session -eq 'SinglePlayer') { $run = New-TrialRunName }
        $contextId = $run
        if ($Session -eq 'Multiplayer') { $contextId = 'PZDrivingBench-OptimizerTrial-MP-' + [Guid]::NewGuid().ToString('N') }
        $plan.TrialWorld = $contextId
        [IO.File]::WriteAllText((Join-Path $lua 'OptimizerTrial-context-id.txt'), $contextId + "`n", $script:Utf8)
        [IO.File]::WriteAllText((Join-Path $lua 'DrivingBench-run.txt'), $run + "`n", $script:Utf8)
        $sessionLogs = New-TrialSessionLogs $cache
        $plan.Logs = $sessionLogs
        $plan.Activation = 'Pending'
        Save-TrialPlan $plan $log
        $previousPath = $env:PATH; $previousApp = $env:SteamAppId; $previousGame = $env:SteamGameId
        try {
            $env:PATH = $game + ';' + (Join-Path $game 'win64') + ';' + (Join-Path $game 'jre64/bin') + ';' + $previousPath
            $env:SteamAppId = '108600'; $env:SteamGameId = '108600'
            $process = Start-Process -FilePath $plan.Java -WorkingDirectory $game -ArgumentList $plan.CommandLine -RedirectStandardOutput $sessionLogs.Stdout -RedirectStandardError $sessionLogs.Stderr -PassThru
            # Retain the process handle before waiting (Windows PowerShell 5.1 ExitCode handling).
            $null = $process.Handle
            $plan.Pid = $process.Id
            $plan.ProcessStartUtc = $process.StartTime.ToUniversalTime().ToString('o')
            Save-TrialPlan $plan $log
            Write-Host "Game java.exe PID: $($process.Id)"
            $readyAnnounced = $false; $failureAnnounced = $false
            if ($Menu) { Write-Host 'MENU: automatic world creation and recording are disabled.' }
            elseif ($Mode -eq 'Optimized') { Write-Host 'Wait for READY, then press Ctrl+Shift+F8 IN THE GAME. Exit normally after DIAGNOSTICS DONE.' }
            else { $plan.Activation = 'ControlPending'; Save-TrialPlan $plan $log; Write-Host 'CONTROL: candidate disabled. Wait for the test world and full-pack READY.' }
            while ($true) {
                $exited = $process.WaitForExit(1000)
                # Stop reading full logs after READY so the launcher adds no polling I/O during capture.
                if (-not $readyAnnounced -and -not $failureAnnounced) {
                    $sessionText = Read-TrialSessionText $sessionLogs
                    $state = Get-TrialRunReadiness $sessionText $Mode $resolved.Pack.main_revision $resolved.Ids.Count $Session -ContextId $contextId -Menu:$Menu -PreviousFailure $failureAnnounced
                    $plan.Readiness = $state
                    if ($state.Failed) {
                        $failureAnnounced = $true; $plan.Activation = 'Incomplete'
                        Save-TrialPlan $plan $log
                        Write-Warning "INCOMPLETE: $Mode activation failed. Do not capture this run. Logs: $($sessionLogs.Directory)"
                    } elseif ($state.Ready) {
                        $readyAnnounced = $true; $plan.Activation = 'Ready'
                        Save-TrialPlan $plan $log
                        if ($Mode -eq 'Optimized') { Write-Host "READY: full pack + bounded render/chunk profile + cache/preloads verified; $($state.HandedOff)/$($state.ActionGroups) action groups accounted for. Client and optimizer ready." }
                        else { Write-Host 'READY CONTROL: full pinned candidate modpack activation verified. Client ready.' }
                        if (-not $Menu -and -not $exited) {
                            $plan.Diagnostics = Invoke-TrialDiagnostics $process $plan $jfrTools -FrameClient $frameClient -SkipWpr:$SkipWpr
                            Save-TrialPlan $plan $log
                        }
                    }
                }
                if ($exited) { break }
            }
            $process.Refresh()
            $plan.JavaExitCode = $process.ExitCode
            $plan.Readiness = Get-TrialRunReadiness (Read-TrialSessionText $sessionLogs) $Mode $resolved.Pack.main_revision $resolved.Ids.Count $Session -ContextId $contextId -Menu:$Menu -PreviousFailure $failureAnnounced
            if ($Mode -eq 'Optimized') {
                if (-not $plan.Readiness.Ready) {
                    $plan.Activation = 'Incomplete'; Save-TrialPlan $plan $log
                    throw "INCOMPLETE Optimized trial; activation was not verified. Missing: $($plan.Readiness.Missing -join '; '). Bridge failure: $($plan.Readiness.Failed). Logs: $($sessionLogs.Directory); fresh console: $($sessionLogs.Console)"
                }
                $plan.Activation = 'Verified'; Save-TrialPlan $plan $log
            } else {
                if (-not $plan.Readiness.Ready) {
                    $plan.Activation = 'Incomplete'; Save-TrialPlan $plan $log
                    throw "INCOMPLETE Control trial; full pinned candidate modpack activation was not verified. Logs: $($sessionLogs.Directory)"
                }
                $plan.Activation = 'ControlVerified'; Save-TrialPlan $plan $log
            }
            Save-TrialPlan $plan $log
            if ($process.ExitCode -ne 0) { throw "Project Zomboid exited with code $($process.ExitCode). See $($sessionLogs.Directory)" }
        } finally {
            # Snapshot this run's console before the next launch rotates the shared console.txt.
            if ($null -ne $plan.Pid) {
                try {
                    $process.Refresh()
                    if ($process.HasExited) {
                        $plan.FinishedUtc = [DateTime]::UtcNow.ToString('o')
                        $plan.JavaExitCode = $process.ExitCode
                        if (Test-Path -LiteralPath $sessionLogs.Console -PathType Leaf) {
                            Assert-NoReparsePoint $sessionLogs.Console
                            Copy-Item -LiteralPath $sessionLogs.Console -Destination (Join-Path $sessionLogs.Directory 'session-console.txt')
                        }
                        Save-TrialPlan $plan $log
                    }
                } catch { Write-Warning ('Cannot finalize session logs: '+$_.Exception.Message) }
            }
            $env:PATH = $previousPath; $env:SteamAppId = $previousApp; $env:SteamGameId = $previousGame
        }
    } finally { $lock.Dispose() }
}
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-OptimizerTrial } catch { Write-Error $_; exit 1 }
}
