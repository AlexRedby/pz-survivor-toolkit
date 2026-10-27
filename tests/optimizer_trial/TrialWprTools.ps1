# Bounded WPR discovery. Importing this file never probes or executes a tool.
# Microsoft recommends WPT 19650+ for WPR start/stop fixes:
# https://devblogs.microsoft.com/performance-diagnostics/wpr-start-and-stop-commands/
function Test-TrialWprWindows {
    return ([Environment]::OSVersion.Platform -eq 'Win32NT')
}
function Get-TrialWprProgramFilesDirectories {
    # Do not use PATH, the current directory, or caller-supplied environment paths.
    foreach ($folder in @([Environment+SpecialFolder]::ProgramFilesX86,[Environment+SpecialFolder]::ProgramFiles)) {
        $directory=[Environment]::GetFolderPath($folder)
        if ($directory) { $directory }
    }
}
function Get-TrialWprToolCandidates {
    if (-not (Test-TrialWprWindows)) { return }
    $seen=@{}
    foreach ($directory in @(Get-TrialWprProgramFilesDirectories)) {
        if (-not $directory) { continue }
        $path=[IO.Path]::GetFullPath((Join-Path $directory 'Windows Kits/10/Windows Performance Toolkit/wpr.exe'))
        if (-not $seen.ContainsKey($path)) {
            $seen[$path]=$true
            [pscustomobject]@{Path=$path;Source='ADK'}
        }
    }
    $system=Get-TrialWprSystemDirectory
    if ($system) {
        $path=[IO.Path]::GetFullPath((Join-Path $system 'wpr.exe'))
        if (-not $seen.ContainsKey($path)) { [pscustomobject]@{Path=$path;Source='System'} }
    }
}
function Get-TrialWprFileVersionInfo([string]$Path) {
    return [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
}
function Get-TrialWprFileMetadata([string]$Path) {
    $ErrorActionPreference='Stop'
    $result=[pscustomobject][ordered]@{Path=$Path;Version=$null;Sha256=$null;SignatureStatus=$null;Publisher=$null;
        FileVersion=$null;ProductVersion=$null;Eligible=$false;Reason='WprUnavailable'}
    try {
        $result.Path=[IO.Path]::GetFullPath($Path)
        Assert-TrialWprPath $result.Path
        if (-not (Test-Path -LiteralPath $result.Path -PathType Leaf)) { $result.Reason='ToolMissing'; return $result }
        $version=Get-TrialWprFileVersionInfo $result.Path
        $result.FileVersion=[string]$version.FileVersion
        $result.ProductVersion=[string]$version.ProductVersion
        $parts=@()
        foreach ($name in @('FileMajorPart','FileMinorPart','FileBuildPart','FilePrivatePart')) {
            $part=0
            if (-not $version.PSObject.Properties[$name] -or
                -not [int]::TryParse([string]$version.$name,[ref]$part) -or $part -lt 0) {
                $result.Reason='UnknownVersion'; return $result
            }
            $parts+= $part
        }
        if (($parts | Measure-Object -Sum).Sum -eq 0) { $result.Reason='UnknownVersion'; return $result }
        $result.Version=($parts -join '.')
        $result.Sha256=(Get-FileHash -LiteralPath $result.Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $signature=Get-AuthenticodeSignature -LiteralPath $result.Path -ErrorAction Stop
        $result.SignatureStatus=[string]$signature.Status
        if ($signature.SignerCertificate) { $result.Publisher=[string]$signature.SignerCertificate.Subject }
        if ($result.SignatureStatus -ne 'Valid' -or
            $result.Publisher -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
            $result.Reason='UntrustedPublisher'; return $result
        }
        $result.Eligible=$true; $result.Reason=$null
    } catch { $result.Reason='ToolValidationFailed' }
    return $result
}
function Get-TrialWprToolMetadata([string]$Path,[string]$Source) {
    $ErrorActionPreference='Stop'
    $result=[pscustomobject][ordered]@{Path=$Path;Source=$Source;Version=$null;Sha256=$null;SignatureStatus=$null;Publisher=$null;
        FileVersion=$null;ProductVersion=$null;Eligible=$false;Reason='UntrustedToolPath';WprControl=$null}
    try {
        if (-not (Test-TrialWprWindows)) { $result.Reason='WprUnavailable'; return $result }
        $result.Path=[IO.Path]::GetFullPath($Path)
        $allowed=$false
        foreach ($candidate in @(Get-TrialWprToolCandidates)) {
            if ($Source -ceq $candidate.Source -and [string]::Equals($result.Path,$candidate.Path,[StringComparison]::OrdinalIgnoreCase)) { $allowed=$true; break }
        }
        if (-not $allowed) { return $result }
        $file=Get-TrialWprFileMetadata $result.Path
        foreach ($name in @('Version','Sha256','SignatureStatus','Publisher','FileVersion','ProductVersion','Eligible','Reason')) { $result.$name=$file.$name }
        if ($result.Eligible -and [version]$result.Version -lt [version]'10.0.19650.0') { $result.Eligible=$false; $result.Reason='WprUpgradeRequired' }
        # This is adjacent-file evidence only, not evidence of the DLL actually loaded.
        $control=Join-Path ([IO.Path]::GetDirectoryName($result.Path)) 'wprcontrol.dll'
        if (Test-Path -LiteralPath $control -PathType Leaf) { $result.WprControl=Get-TrialWprFileMetadata $control }
    } catch { $result.Eligible=$false; $result.Reason='ToolValidationFailed' }
    return $result
}
function Get-TrialWprToolSelection {
    $candidates=@()
    if (Test-TrialWprWindows) {
        foreach ($candidate in @(Get-TrialWprToolCandidates)) { $candidates+=Get-TrialWprToolMetadata $candidate.Path $candidate.Source }
    }
    $selected=$null
    foreach ($candidate in $candidates) { if ($candidate.Eligible) { $selected=$candidate; break } }
    $reason='WprUnavailable'
    if ($selected) { $reason=$null }
    elseif (@($candidates | Where-Object { $_.Reason -eq 'WprUpgradeRequired' }).Count -gt 0) { $reason='WprUpgradeRequired' }
    return [pscustomobject]@{Selected=$selected;Candidates=@($candidates);Reason=$reason}
}
function Get-TrialWprTool {
    $selection=Get-TrialWprToolSelection
    if ($selection.Selected) { return $selection.Selected.Path }
    return $null
}
