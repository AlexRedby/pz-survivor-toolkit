# Exact, pinned current-main modpack setup. Dot-sourced by Launch-Trial.ps1.
function Read-TrialModMetadata([string]$Path) {
    Assert-NoReparsePoint $Path
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*#' -or -not $line.Contains('=')) { continue }
        $parts = $line -split '=', 2
        $values[$parts[0].Trim()] = $parts[1].Trim()
    }
    return $values
}

function Get-TrialModVersion($Metadata) {
    if ($Metadata.ContainsKey('modversion')) { return $Metadata['modversion'] }
    if ($Metadata.ContainsKey('version')) { return $Metadata['version'] }
    return ''
}

function Get-TrialModInfo([string]$Root) {
    Assert-NoReparsePoint $Root
    # B42 ignores legacy root metadata. The engine defaults to 42.0, picks
    # the greatest compatible major/minor, and ignores patch components.
    $selected = Join-Path $Root '42.0'; $minimum = 42000
    foreach ($child in @(Get-ChildItem -LiteralPath $Root -Directory -Force)) {
        Assert-NoReparsePoint $child.FullName
        if ($child.Name -notmatch '^\d+(?:\.\d+)*$') { continue }
        $parts = $child.Name.Split('.')
        $minor = 0
        if ($parts.Count -gt 1) { $minor = [Math]::Min([int]$parts[1], 999) }
        $value = [int]$parts[0] * 1000 + $minor
        if ($value -ge $minimum -and $value -le 42021) { $selected = $child.FullName; $minimum = $value }
    }
    foreach ($layer in @($selected, (Join-Path $Root 'common'))) {
        $info = Join-Path $layer 'mod.info'
        if (Test-Path -LiteralPath $info -PathType Leaf) {
            $metadata = Read-TrialModMetadata $info
            if ($metadata.ContainsKey('id')) { return [pscustomobject]@{ Root = (Get-FullPath $Root); Info = $info; Metadata = $metadata } }
        }
    }
    return $null
}

function Get-TrialTreeFiles([string]$Root) {
    Assert-NoReparsePoint $Root
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Missing packaged/private mod directory: $Root" }
    $files = [ordered]@{}
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked mod content: $($item.FullName)" }
        if ($item.PSIsContainer) { continue }
        $name = $item.FullName.Substring((Get-FullPath $Root).Length + 1).Replace('\', '/')
        $files[$name] = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return [pscustomobject]$files
}

function Assert-TrialTreeFiles([string]$Root, $Expected) {
    $actual = Get-TrialTreeFiles $Root
    $names = @($actual.PSObject.Properties.Name)
    if ($names.Count -ne @($Expected.PSObject.Properties).Count) { throw "Changed mod file set: $Root" }
    foreach ($entry in $Expected.PSObject.Properties) {
        Assert-TrialEntryName $entry.Name
        if ($entry.Value -isnot [string] -or $entry.Value -cnotmatch '^[a-f0-9]{64}$') { throw "Invalid mod hash: $($entry.Name)" }
        $found = $actual.PSObject.Properties[$entry.Name]
        if (-not $found -or $found.Name -cne $entry.Name -or $found.Value -cne $entry.Value) { throw "Changed mod file: $Root/$($entry.Name)" }
    }
}

function Read-TrialPack([string]$Package) {
    $path = Join-Path $Package 'pack-manifest.json'
    Assert-NoReparsePoint $path
    $pack = [IO.File]::ReadAllText($path) | ConvertFrom-Json
    if ($pack.format -ne 1 -or $pack.main_revision -cnotmatch '^[a-f0-9]{40}$') { throw 'Invalid current-main pack manifest.' }
    Assert-TrialStrings $pack.mod_ids 'pack mod_ids'
    Assert-TrialStrings $pack.workshop_ids 'pack workshop_ids'
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $pack.mod_ids) {
        if ($id -cnotmatch '^[A-Za-z0-9_.-]+$' -or $id -in @('.', '..', 'PZDrivingBench', 'PZDrivingOptimizerBridge') -or -not $seen.Add($id)) { throw "Invalid/duplicate pack Mod ID: $id" }
    }
    foreach ($id in @('ZombieBuddy', 'PZSurvivorToolkit', 'PZToolkitJavaPatches')) {
        if ($id -cnotin $pack.mod_ids) { throw "Current-main pack lacks $id" }
    }
    $seen.Clear()
    foreach ($id in $pack.workshop_ids) { if ($id -cnotmatch '^\d+$' -or -not $seen.Add($id)) { throw "Invalid/duplicate Workshop item ID: $id" } }
    if (@($pack.repository_mods.PSObject.Properties.Name).Count -ne 2) { throw 'Pack must pin exactly the two repository mods.' }
    foreach ($id in @('PZSurvivorToolkit', 'PZToolkitJavaPatches')) {
        $entry = $pack.repository_mods.PSObject.Properties[$id]
        if (-not $entry -or -not $entry.Value.PSObject.Properties['files'] -or @($entry.Value.files.PSObject.Properties).Count -eq 0) { throw "Pack lacks file hashes for $id" }
        $root = Join-Path $Package ('mods/' + $id)
        Assert-TrialTreeFiles $root $entry.Value.files
        $info = Get-TrialModInfo $root
        if (-not $info -or $info.Metadata['id'] -cne $id -or (Get-TrialModVersion $info.Metadata) -cne $entry.Value.version) { throw "Packaged repository mod identity/version mismatch: $id" }
    }
    return $pack
}

function Get-TrialModCandidates([string]$Directory, [string]$Kind, [string]$ItemId = '') {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return }
    Assert-NoReparsePoint $Directory
    foreach ($root in @(Get-ChildItem -LiteralPath $Directory -Directory -Force)) {
        $info = Get-TrialModInfo $root.FullName
        if ($info) {
            $version = Get-TrialModVersion $info.Metadata
            [pscustomobject]@{ Id = $info.Metadata['id']; Root = $info.Root; Info = $info.Info; Kind = $Kind; WorkshopId = $ItemId; Version = $version; Metadata = $info.Metadata }
        }
    }
}

function Resolve-TrialPack([string]$Package, [string]$Source, [string]$Workshop,
    [ValidateSet('SinglePlayer','Multiplayer')][string]$SessionType = 'SinglePlayer') {
    $pack = Read-TrialPack $Package
    $workshopMods = @(); $localMods = @(Get-TrialModCandidates (Join-Path $Source 'mods') 'LocalFallback')
    $absentItems = @()
    if ($Workshop) {
        Assert-NoReparsePoint $Workshop
        if (Test-Path -LiteralPath $Workshop -PathType Container) {
            foreach ($item in @(Get-ChildItem -LiteralPath $Workshop -Directory -Force)) {
                if ($item.Name -match '^\d+$') { $workshopMods += @(Get-TrialModCandidates (Join-Path $item.FullName 'mods') 'Workshop' $item.Name) }
            }
        }
    }
    foreach ($id in $pack.workshop_ids) { if (-not $Workshop -or -not (Test-Path -LiteralPath (Join-Path $Workshop $id) -PathType Container)) { $absentItems += $id } }
    $sources = @(); $missing = @()
    $sourceIds = @($pack.mod_ids) + @('PZDrivingBench', 'PZDrivingOptimizerBridge')
    $ids = @($sourceIds | Where-Object { $SessionType -eq 'SinglePlayer' -or $_ -cne 'PZDrivingBench' })
    # Keep the complete private source inventory: Initialize-Profile copies the
    # packaged starter directory even when its callbacks must remain inactive.
    foreach ($id in $sourceIds) {
        if ($id -cin @('PZSurvivorToolkit', 'PZToolkitJavaPatches', 'PZDrivingBench', 'PZDrivingOptimizerBridge')) {
            $matches = @(Get-TrialModCandidates (Join-Path $Package 'mods') 'Package' | Where-Object { $_.Id -ceq $id })
        } else {
            $matches = @($workshopMods | Where-Object { $_.Id -ceq $id })
            if (-not $matches.Count) { $matches = @($localMods | Where-Object { $_.Id -ceq $id }) }
        }
        if ($matches.Count -gt 1) { throw "Ambiguous compatible mod roots for ${id}: $($matches.Root -join '; ')" }
        if (-not $matches.Count) { $missing += $id; continue }
        $sources += $matches[0]
    }
    if ($missing.Count) {
        $links = @($absentItems | ForEach-Object { "https://steamcommunity.com/sharedfiles/filedetails/?id=$_" })
        throw "Missing compatible Build 42.21 Mod IDs: $($missing -join ', '). Missing Workshop item IDs: $($absentItems -join ', '). Install/update the required items through Steam, or supply their local sources. Workshop links: $($links -join ' ')"
    }
    foreach ($sourceMod in $sources) {
        if ($sourceMod.Id -cnotin $ids) { continue }
        if (-not $sourceMod.Metadata.ContainsKey('require')) { continue }
        foreach ($dependency in $sourceMod.Metadata['require'].Split(',')) {
            # B42.21 ChooseGameInfo.readModInfo removes backslashes before
            # splitting require=; native metadata uses require=\ZombieBuddy.
            $dependency = $dependency.Replace('\', '').Trim()
            if ($dependency -and $dependency -cnotin $ids) { throw "Selected mod $($sourceMod.Id) requires unselected Mod ID $dependency" }
        }
    }
    $private = @()
    foreach ($sourceMod in $sources) {
        if ($sourceMod.Kind -eq 'Workshop') { continue }
        $private += [pscustomobject]@{ Id = $sourceMod.Id; Files = (Get-TrialTreeFiles $sourceMod.Root) }
    }
    return [pscustomobject]@{ Pack = $pack; ManifestHash = (Get-FileHash -LiteralPath (Join-Path $Package 'pack-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant(); Session = $SessionType; Ids = $ids; Sources = $sources; Private = $private }
}

function Get-TrialSelectionText($Ids) {
    return "VERSION = 1,`nmods`n{`n" + (($Ids | ForEach-Object { "    mod = $_,`n" }) -join '') + "}`nmaps`n{`n}`n"
}

function Initialize-TrialProfile([string]$Cache, [string]$Source, [string]$Package, $Resolved) {
    if (-not $Resolved) { throw 'Resolve the current-main pack before initializing its profile.' }
    Assert-SeparatePaths $Source $Cache
    Assert-NoReparsePoint $Cache
    $receiptPath = Join-Path $Cache '.pz-optimizer-pack.json'
    $selection = Join-Path $Cache 'mods/default.txt'
    $content = Get-TrialSelectionText $Resolved.Ids
    foreach ($item in @(Get-ChildItem -LiteralPath $Cache -Recurse -Force -ErrorAction SilentlyContinue)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked profile content: $($item.FullName)" }
    }
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
        if ($receipt.format -ne 1 -or $receipt.manifest_sha256 -cne $Resolved.ManifestHash) { throw "Existing profile belongs to a different pack. Extract the new package into a new folder: $Cache" }
        if (-not (Test-Path -LiteralPath $selection -PathType Leaf) -or [IO.File]::ReadAllText($selection) -cne $content) { throw "Modified exact pack selection; refusing to overwrite: $selection" }
        if (-not (Test-Path -LiteralPath (Join-Path $Cache 'mods/reset-mods-42_00.txt') -PathType Leaf)) { throw 'Pack release-reset marker is missing; refusing to change existing profile.' }
        if (@($receipt.private_mods).Count -ne @($Resolved.Private).Count) { throw 'Private pack source set changed; use a new package folder.' }
        foreach ($privateMod in $Resolved.Private) {
            $saved = @($receipt.private_mods | Where-Object { $_.Id -ceq $privateMod.Id })
            if ($saved.Count -ne 1) { throw "Private pack source changed: $($privateMod.Id)" }
            Assert-TrialTreeFiles (Join-Path $Cache ('mods/' + $privateMod.Id)) $privateMod.Files
            Assert-TrialTreeFiles (Join-Path $Cache ('mods/' + $privateMod.Id)) $saved[0].Files
        }
        $expected = @($Resolved.Private | ForEach-Object { $_.Id })
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $Cache 'mods') -Directory -Force)) {
            if ($directory.Name -cnotin $expected) { throw "Unexpected local mod could shadow Workshop: $($directory.FullName)" }
        }
        return
    }
    # Never upgrade or rewrite a previous trial in place, including partial imports.
    if (Test-Path -LiteralPath (Join-Path $Cache '.pz-driving-bench-initialized')) { throw "Existing initialized trial has no current-main pack receipt. Extract into a new folder: $Cache" }
    foreach ($relative in @('mods', 'Lua', 'Server', 'Saves', 'TrialRuns')) {
        if (Test-Path -LiteralPath (Join-Path $Cache $relative)) { throw "Existing trial content has no pack receipt; use a new folder: $Cache/$relative" }
    }
    # This copies settings and the starter, never the stale source selection/mods.
    Initialize-Profile $Cache $Source 'Vanilla' $Package
    foreach ($sourceMod in $Resolved.Sources) {
        if ($sourceMod.Kind -ne 'Workshop') { Copy-SafeTree $sourceMod.Root (Join-Path $Cache ('mods/' + $sourceMod.Id)) }
    }
    foreach ($privateMod in $Resolved.Private) { Assert-TrialTreeFiles (Join-Path $Cache ('mods/' + $privateMod.Id)) $privateMod.Files }
    [IO.File]::WriteAllText($selection, $content, $script:Utf8)
    $receipt = [pscustomobject]@{ format = 1; main_revision = $Resolved.Pack.main_revision; manifest_sha256 = $Resolved.ManifestHash; mod_ids = $Resolved.Ids; sources = @($Resolved.Sources | Select-Object Id, Kind, Root, Info, Version, WorkshopId); private_mods = $Resolved.Private }
    [IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 12), $script:Utf8)
}
