[CmdletBinding()]
param([string]$ControlCapture, [string]$OptimizedCapture, [string]$PackageRoot)

# This collector reads receipts only. It never starts or stops a game process.
function Assert-TrialResultPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'A result path is empty. Run Collect-results.cmd from the existing trial package.' }
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked/reparse result path is not allowed: $cursor" }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $full
}

function Read-TrialResultJson([string]$Path) {
    $null = Assert-TrialResultPath $Path
    try { return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop) }
    catch { throw "Cannot read JSON ${Path}: $($_.Exception.Message)" }
}

function Get-TrialResultProperty($Object, [string]$Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.PSObject.Properties[$Name].Value }
    return $null
}

function ConvertTo-TrialResultUtc($Value) {
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
}

function Get-TrialBufferedGameContext($Run, $Diagnostic) {
    $policy=Get-TrialResultProperty $Run.Receipt 'gameContextPolicy'
    $summary=[pscustomobject]@{format=2;status='Unavailable';reason='MissingWorldEndFlush';world=$null;file=$null;samples=0;dropped=0;firstSampleTsMs=$null;lastSampleTsMs=$null;maximumGapMs=$null;frameIntervalCovered=$false}
    # Older archives retain their original console evidence and acceptance rules.
    if (-not $policy) { $summary.status='Legacy'; $summary.reason='BufferedFlushNotRequiredForLegacyRun'; return $summary }
    try {
        if ($policy -cne 'BufferedWorldExitV2') { throw 'UnsupportedGameContextPolicy' }
        $world=[string](Get-TrialResultProperty $Run.Receipt 'TrialWorld')
        if ($world -cnotmatch '^PZDrivingBench-OptimizerTrial-[A-Za-z0-9-]{1,72}$' -or $world.Length -gt 100) { throw 'MissingTrialWorldIdentity' }
        $summary.world=$world
        $text=''; $begins=@()
        foreach ($name in @('session-console.txt','stdout.txt')) {
            $path=Assert-TrialResultPath (Join-Path $Run.Directory $name)
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $text=[IO.File]::ReadAllText($path)
            $begins=@([regex]::Matches($text,'(?m)\[OptimizerTrial\] drive telemetry flush begin format=2 world=([A-Za-z0-9-]+) samples=(\d+) dropped=(\d+) reason=(MainMenu|PostSaveExit|Disconnect|WorldExit)[\t ]*\r?$'))
            if ($begins.Count) { $summary.file=$name; break }
        }
        if (-not $begins.Count) { return $summary }
        # Only the final world batch in this process may qualify; a previous
        # world or initial-menu output cannot satisfy the receipt's unique ID.
        $begin=$begins[-1]
        if ($begin.Groups[1].Value -cne $world) { throw 'GameContextWorldMismatch' }
        if ($begin.Groups[4].Value -cin @('Disconnect','WorldExit') -and
            $world -cnotmatch '^PZDrivingBench-OptimizerTrial-MP-[A-Fa-f0-9]{32}$') { throw 'InvalidMultiplayerGameContextIdentity' }
        $summary.samples=[int]$begin.Groups[2].Value; $summary.dropped=[long]$begin.Groups[3].Value
        if ($summary.samples -lt 1 -or $summary.samples -gt 1800) { throw 'InvalidGameContextSampleCount' }
        $tail=$text.Substring($begin.Index+$begin.Length)
        $end=[regex]::Match($tail,'(?m)\[OptimizerTrial\] drive telemetry flush end format=2 world=([A-Za-z0-9-]+) samples=(\d+) dropped=(\d+) status=(Complete|Incomplete)[\t ]*\r?$')
        if (-not $end.Success) { throw 'MissingWorldEndFlushCommit' }
        if ($end.Groups[1].Value -cne $world -or [int]$end.Groups[2].Value -ne $summary.samples -or [long]$end.Groups[3].Value -ne $summary.dropped) { throw 'GameContextFlushIdentityMismatch' }
        $body=$tail.Substring(0,$end.Index)
        $samples=@([regex]::Matches($body,'(?m)\[OptimizerTrial\] drive sample tsMs=(\d+) [^\r\n]*'))
        if ($samples.Count -ne $summary.samples) { throw 'GameContextFlushSampleCountMismatch' }
        $previous=$null; $maximumGap=0L
        foreach ($sample in $samples) {
            if ($sample.Length -gt 1024) { throw 'OversizedGameContextSample' }
            $timestamp=[long]$sample.Groups[1].Value
            if ($null -ne $previous) {
                if ($timestamp -le $previous) { throw 'GameContextTimestampOrderInvalid' }
                $maximumGap=[Math]::Max($maximumGap,$timestamp-$previous)
            } else { $summary.firstSampleTsMs=$timestamp }
            $previous=$timestamp
        }
        $summary.lastSampleTsMs=$previous; $summary.maximumGapMs=$maximumGap
        $start=Get-TrialResultProperty $Diagnostic 'frameRequestedUtc'
        $ack=Get-TrialResultProperty $Diagnostic 'frameAcknowledgedUtc'
        $seconds=Get-TrialResultProperty $Diagnostic 'capFrameXSeconds'
        if (-not $start -or -not $ack -or $seconds -le 0) { throw 'GameContextCaptureIntervalUnavailable' }
        $first=([DateTimeOffset](ConvertTo-TrialResultUtc $start)).ToUnixTimeMilliseconds()
        $last=([DateTimeOffset](ConvertTo-TrialResultUtc $ack)).ToUnixTimeMilliseconds()+[long]($seconds*1000)
        $summary.frameIntervalCovered=($summary.firstSampleTsMs -le $first -and $summary.lastSampleTsMs -ge $last)
        if ($summary.dropped -gt 0) { throw 'GameContextBufferTruncated' }
        if ($end.Groups[4].Value -cne 'Complete' -or $body.Contains('[OptimizerTrial] drive telemetry disabled')) { throw 'GameContextObserverFailed' }
        if (-not $summary.frameIntervalCovered) { throw 'GameContextDoesNotCoverFrameInterval' }
        $summary.status='Complete'; $summary.reason=$null
    } catch { $summary.status='Incomplete'; $summary.reason=$_.Exception.Message }
    return $summary
}

function Test-TrialCaptureFrames($Object, [int]$Depth = 0) {
    if ($null -eq $Object -or $Depth -gt 32) { return $false }
    if ($Object -is [System.Collections.IList]) {
        foreach ($entry in $Object) { if (Test-TrialCaptureFrames $entry ($Depth + 1)) { return $true } }
        return $false
    }
    if ($Object -isnot [pscustomobject]) { return $false }
    foreach ($property in $Object.PSObject.Properties) {
        # CapFrameX exports have used several timing-array names. Require actual
        # positive numeric samples, without depending on unrelated metadata.
        if ($property.Name -match '^(MsBetweenPresents|FrametimeMs|Frametime|Frametimes|FrameTimes|FrameTimeInMs)$') {
            foreach ($sample in @($property.Value)) {
                if ($sample -is [ValueType] -and $sample -isnot [bool] -and [double]$sample -gt 0) { return $true }
            }
        }
        if (Test-TrialCaptureFrames $property.Value ($Depth + 1)) { return $true }
    }
    return $false
}

function Read-TrialCapture([string]$Path, [string]$Mode) {
    $pathValue = $Path.Trim().Trim('"')
    if ($pathValue -eq '-') { return [pscustomobject]@{ Path = $null; Mode = $Mode; OriginalBasename = $null; Sha256 = $null; CsvPath=$null; CsvSha256=$null; Automatic=$false; Issues=@(); Unverified=@() } }
    if (-not [IO.Path]::IsPathRooted($pathValue)) { throw "$Mode CapFrameX selection must be a full path." }
    $full = Assert-TrialResultPath $pathValue
    if ([IO.Path]::GetExtension($full) -ine '.json') { throw "$Mode capture must be a CapFrameX JSON file." }
    $json = Read-TrialResultJson $full
    if (-not (Test-TrialCaptureFrames $json)) { throw "$Mode JSON has no recognized nonempty CapFrameX frame timing array: $full" }
    return [pscustomobject]@{ Path = $full; Mode = $Mode; OriginalBasename = [IO.Path]::GetFileName($full); Sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant(); CsvPath=$null; CsvSha256=$null; Automatic=$false; Issues=@(); Unverified=@() }
}

function Test-TrialAutomaticResult($Run) {
    return ((Get-TrialResultProperty $Run.Receipt 'automaticCapFrameX') -eq $true -or
            (Test-Path -LiteralPath (Join-Path $Run.Directory 'frame-capture.json')))
}

function Get-TrialUnverifiedFrameFiles($Run, $Receipt, $Capture) {
    try {
        $directory = Assert-TrialResultPath (Join-Path $Run.Directory 'CapFrameX')
        $request = Get-TrialResultProperty $Receipt 'request'
        $requestedDirectory = [string](Get-TrialResultProperty $request 'directory')
        $comparison = [StringComparison]::Ordinal
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $comparison = [StringComparison]::OrdinalIgnoreCase }
        if (-not [IO.Path]::IsPathRooted($requestedDirectory) -or
            @($requestedDirectory -split '[\\/]' | Where-Object { $_ -eq '..' }).Count -or
            -not [string]::Equals((Assert-TrialResultPath $requestedDirectory), $directory, $comparison) -or
            (Get-TrialResultProperty $request 'targetPid') -ne (Get-TrialResultProperty $Run.Receipt 'Pid') -or
            (Get-TrialResultProperty $request 'processName') -cne 'java' -or
            (Get-TrialResultProperty $request 'seconds') -ne 90 -or -not (Get-TrialResultProperty $request 'token')) {
            throw 'Unverified capture request does not belong to this run'
        }
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            $Capture.Issues += 'Missing unverified CapFrameX output directory'
            return
        }
        $files = @(Get-ChildItem -LiteralPath $directory -File -Force -Filter 'CapFrameX-java.exe-*.json*' -ErrorAction Stop |
            Where-Object { $_.Name -cmatch '^CapFrameX-java[.]exe-[^\\/]+[.]json(?:[.]csv)?\z' } | Sort-Object Name)
        if (-not @($files | Where-Object { $_.Name -cmatch '[.]json\z' }).Count) { $Capture.Issues += 'Missing unverified CapFrameX JSON export' }
        if (-not @($files | Where-Object { $_.Name -cmatch '[.]json[.]csv\z' }).Count) { $Capture.Issues += 'Missing unverified CapFrameX CSV export' }
        $included = 0
        foreach ($file in $files) {
            if ($included -ge 16) { $Capture.Issues += 'Unverified CapFrameX export limit reached (16 files)'; break }
            try {
                $full = Assert-TrialResultPath $file.FullName
                if ($file.Length -gt 268435456) { throw 'Export exceeds the 256 MiB preservation limit' }
                $included++
                $full
            } catch { $Capture.Issues += ('Unverified CapFrameX export omitted: ' + $file.Name + ': ' + $_.Exception.Message) }
        }
    } catch { $Capture.Issues += ('Unverified CapFrameX exports unavailable: ' + $_.Exception.Message) }
}

function Get-TrialAutomaticCapture($Run, [string]$Mode) {
    $capture = [pscustomobject]@{ Path=$null; CsvPath=$null; Mode=$Mode; OriginalBasename=$null; Sha256=$null; CsvSha256=$null; Automatic=$true; Issues=@(); Unverified=@() }
    $wrapper = Join-Path $Run.Directory 'frame-capture.json'
    if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
        $capture.Issues += 'Missing automatic frame-capture.json'
        return $capture
    }
    try {
        $receipt = Read-TrialResultJson $wrapper
        if ((Get-TrialResultProperty $receipt 'format') -ne 1 -or
            (Get-TrialResultProperty $receipt 'mode') -ine $Mode -or
            (Get-TrialResultProperty $receipt 'targetPid') -ne (Get-TrialResultProperty $Run.Receipt 'Pid')) {
            throw 'Automatic CapFrameX receipt does not match this run mode/PID'
        }
        if ((Get-TrialResultProperty $receipt 'status') -cne 'Complete') {
            $capture.Issues += 'Automatic CapFrameX receipt did not complete; raw exports are unverified'
            $capture.Unverified = @(Get-TrialUnverifiedFrameFiles $Run $receipt $capture)
            return $capture
        }
        $request = Get-TrialResultProperty $receipt 'request'
        $result = Get-TrialResultProperty $receipt 'result'
        $directory = Assert-TrialResultPath (Join-Path $Run.Directory 'CapFrameX')
        $comparison = [StringComparison]::Ordinal
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $comparison = [StringComparison]::OrdinalIgnoreCase }
        $requestedDirectory = [string](Get-TrialResultProperty $request 'directory')
        if (-not [IO.Path]::IsPathRooted($requestedDirectory) -or
            @($requestedDirectory -split '[\\/]' | Where-Object { $_ -eq '..' }).Count -or
            -not [string]::Equals((Assert-TrialResultPath $requestedDirectory), $directory, $comparison) -or
            (Get-TrialResultProperty $request 'targetPid') -ne (Get-TrialResultProperty $Run.Receipt 'Pid') -or
            (Get-TrialResultProperty $request 'processName') -cne 'java' -or
            (Get-TrialResultProperty $request 'seconds') -ne 90 -or
            -not (Get-TrialResultProperty $request 'token') -or $null -eq $result) {
            throw 'Automatic CapFrameX request does not belong to this run'
        }
        # These timestamps bind the start acknowledgement to the wrapper. They are
        # checked as UTC values, but no timing/route equivalence is inferred here.
        foreach ($utc in @((Get-TrialResultProperty $receipt 'triggeredUtc'),
                           (Get-TrialResultProperty $request 'requestedUtc'),
                           (Get-TrialResultProperty $request 'acknowledgedUtc'))) {
            if (-not $utc) { throw 'Missing automatic CapFrameX capture timestamp' }
            $null = ConvertTo-TrialResultUtc $utc
        }
        if ((Get-TrialResultProperty $result 'DurationSeconds') -le 0 -or
            (Get-TrialResultProperty $result 'FrameCount') -le 0 -or
            (Get-TrialResultProperty $result 'CsvFrameCount') -le 0) {
            throw 'Automatic CapFrameX capture has no verified frames/duration'
        }
    } catch {
        $capture.Issues += ('Invalid automatic CapFrameX receipt: ' + $_.Exception.Message)
        return $capture
    }
    foreach ($kind in @('Json', 'Csv')) {
        try {
            $path = [string](Get-TrialResultProperty $result $kind)
            if (-not [IO.Path]::IsPathRooted($path) -or @($path -split '[\\/]' | Where-Object { $_ -eq '..' }).Count) {
                throw 'Capture path must be an absolute path without traversal'
            }
            $full = Assert-TrialResultPath $path
            # Allow only the exact receipt file, directly inside this run's capture
            # directory. Never scan that directory or follow another run's output.
            if (-not [string]::Equals([IO.Path]::GetDirectoryName($full), $directory, $comparison)) {
                throw 'Capture path is outside this run CapFrameX directory'
            }
            $extension = '.json'; if ($kind -eq 'Csv') { $extension = '.csv' }
            if ([IO.Path]::GetExtension($full) -ine $extension -or -not (Test-Path -LiteralPath $full -PathType Leaf) -or
                (Get-Item -LiteralPath $full -Force).Length -le 0) { throw ('Missing/empty ' + $kind + ' capture') }
            $expectedHash = [string](Get-TrialResultProperty $result ($kind + 'Sha256'))
            $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($expectedHash -notmatch '^[a-fA-F0-9]{64}$' -or $hash -cne $expectedHash.ToLowerInvariant()) { throw ($kind + ' SHA256 mismatch') }
            if ($kind -eq 'Json') {
                $checked = Read-TrialCapture $full $Mode
                $capture.Path=$full; $capture.OriginalBasename=$checked.OriginalBasename; $capture.Sha256=$hash
            } else { $capture.CsvPath=$full; $capture.CsvSha256=$hash }
        } catch { $capture.Issues += ('Invalid automatic CapFrameX ' + $kind + ': ' + $_.Exception.Message) }
    }
    return $capture
}

function Get-LatestTrialResult([string]$RunsRoot, [string]$Mode) {
    $null = Assert-TrialResultPath $RunsRoot
    $candidates = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $RunsRoot -Directory -Force -ErrorAction Stop)) {
        $null = Assert-TrialResultPath $directory.FullName
        $path = Join-Path $directory.FullName 'launch.json'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $receipt = Read-TrialResultJson $path
        if ((Get-TrialResultProperty $receipt 'Mode') -ine $Mode) { continue }
        $started = Get-TrialResultProperty $receipt 'ProcessStartUtc'
        $sortTime = $directory.CreationTimeUtc
        if ($started) {
            try { $sortTime = (ConvertTo-TrialResultUtc $started) }
            catch { throw "Invalid ProcessStartUtc in $path" }
        }
        $candidates += [pscustomobject]@{ Directory = $directory.FullName; Receipt = $receipt; SortTime = $sortTime; Name = $directory.Name }
    }
    $selected = $candidates | Sort-Object SortTime, Name -Descending | Select-Object -First 1
    if (-not $selected) { throw "No $Mode launch receipt found in $RunsRoot" }
    $exitCode = Get-TrialResultProperty $selected.Receipt 'JavaExitCode'
    $finished = Get-TrialResultProperty $selected.Receipt 'finishedUtc'
    if ($null -eq $exitCode -or -not $finished) { throw "Latest $Mode run is still open/incomplete. Exit the game and wait for its launcher to finish: $($selected.Directory)" }
    $targetPid = Get-TrialResultProperty $selected.Receipt 'Pid'
    if ($targetPid) {
        $process = Get-Process -Id ([int]$targetPid) -ErrorAction SilentlyContinue
        if ($process) {
            $started = Get-TrialResultProperty $selected.Receipt 'ProcessStartUtc'
            $matching = $true
            if ($started) {
                try { $matching = [Math]::Abs(($process.StartTime.ToUniversalTime() - (ConvertTo-TrialResultUtc $started)).TotalSeconds) -lt 2 }
                catch { $matching = $true }
            }
            if ($matching) { throw "Latest $Mode game process is still running (PID $targetPid). Close it and wait for its launcher." }
        }
    }
    return $selected
}

function Copy-TrialResultFile([string]$Source, [string]$Destination) {
    $null = Assert-TrialResultPath $Source
    $null = Assert-TrialResultPath $Destination
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination)) | Out-Null
    [IO.File]::Copy($Source, $Destination, $false)
}

function Get-TrialWprTempInventory([string]$Directory) {
    # Metadata only. Raw temporary traces can be multi-gigabyte, incomplete and
    # still changing; never mistake this inventory for a usable/captured ETL.
    $entries=@(); $issues=@(); $visited=0
    $root=Join-Path $Directory 'temp'
    try {
        $null=Assert-TrialResultPath $root
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { return [pscustomobject]@{files=@();issues=@()} }
        $queue=New-Object 'Collections.Generic.Queue[string]'
        $queue.Enqueue($root)
        while ($queue.Count -gt 0 -and $visited -lt 256) {
            $folder=$queue.Dequeue()
            foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop | Select-Object -First (257-$visited))) {
                $visited++
                if ($visited -gt 256) { $issues+='WPR temporary inventory entry limit reached'; break }
                try {
                    $path=Assert-TrialResultPath $item.FullName
                    if ($item.PSIsContainer) { $queue.Enqueue($path); continue }
                    if ($item.Extension -ine '.etl') { continue }
                    $relative='temp/'+$path.Substring($root.Length+1).Replace('\','/')
                    $entries+=@([pscustomobject]@{relativePath=$relative;bytes=$item.Length;included=$false;verification='Unverified temporary ETL; retained only in the original run folder'})
                } catch { $issues+='Unsafe/unreadable WPR temporary entry omitted' }
            }
        }
        if ($queue.Count -gt 0) { $issues+='WPR temporary inventory traversal incomplete' }
    } catch { $issues+='WPR temporary inventory unavailable' }
    return [pscustomobject]@{files=@($entries);issues=@($issues)}
}

function Get-TrialWprResult($Run, $Capture) {
    $result=[pscustomobject]@{status='Unknown'; directory=$null; statusPath=$null; path=$null; sha256=$null; bytes=$null; verified=$false; captureCoverage='Unknown'; reason=$null; saveFailure=$null; cleanupState='Unknown'; profileState='Unknown'; profileSha256=$null; observedTempBytes=$null; temporaryFiles=@(); issues=@()}
    $wrapperPath=Join-Path $Run.Directory 'wpr-capture.json'
    if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) { $result.issues += 'Missing wpr-capture.json'; return $result }
    try {
        $wrapper=Read-TrialResultJson $wrapperPath
        $relative=[string](Get-TrialResultProperty $wrapper 'relativeDirectory')
        if ((Get-TrialResultProperty $wrapper 'format') -ne 1 -or $relative -cnotmatch '^WPR/([a-f0-9]{32})$') { throw 'Invalid WPR relativeDirectory' }
        $captureId=$matches[1]
        $directory=Assert-TrialResultPath (Join-Path $Run.Directory $relative)
        $receipt=Get-TrialResultProperty $wrapper 'receipt'
        $statusPath=Join-Path $directory 'wpr-status.json'
        $saved=$null
        if (Test-Path -LiteralPath $statusPath -PathType Leaf) { $saved=Read-TrialResultJson $statusPath }
        foreach ($identity in @($receipt,$saved)) {
            if ($null -eq $identity) {
                if ($null -eq $receipt) { throw 'Missing WPR receipt' }
                continue
            }
            $started=Get-TrialResultProperty $identity 'processStartUtc'
            $runStarted=Get-TrialResultProperty $Run.Receipt 'ProcessStartUtc'
            if ((Get-TrialResultProperty $identity 'format') -ne 1 -or
                (Get-TrialResultProperty $identity 'targetPid') -ne (Get-TrialResultProperty $Run.Receipt 'Pid') -or
                -not $started -or -not $runStarted -or (ConvertTo-TrialResultUtc $started) -ne (ConvertTo-TrialResultUtc $runStarted) -or
                (Get-TrialResultProperty $identity 'captureId') -cne $captureId -or
                (Get-TrialResultProperty $identity 'instanceName') -cne ('PZTrial_'+$captureId) -or
                (Get-TrialResultProperty $identity 'traceFile') -cne 'drive.etl' -or
                (Get-TrialResultProperty $identity 'loggingMode') -cne 'File') { throw 'WPR receipt identity/path/logging mode does not match this run' }
        }
        $result.directory=$relative
        $result.status=[string](Get-TrialResultProperty $receipt 'status')
        foreach ($field in @('reason','saveFailure','cleanupState','profileState','profileSha256','observedTempBytes')) {
            $value=Get-TrialResultProperty $receipt $field
            if ($null -ne $value) { $result.$field=$value }
        }
        if ($saved) { $result.statusPath=$statusPath } else { $result.issues += 'Missing WPR wpr-status.json' }
        if ($result.status -notin @('Complete','Unavailable','Incomplete')) { $result.issues += 'WPR did not reach a final status' }
        if ($result.status -ne 'Complete') {
            $temporary=Get-TrialWprTempInventory $directory
            $result.temporaryFiles=@($temporary.files); $result.issues+=@($temporary.issues)
        }
        $path=Assert-TrialResultPath (Join-Path $directory 'drive.etl')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path -Force).Length -le 0) {
            $result.issues += 'Missing/empty WPR drive.etl'; return $result
        }
        $bytes=(Get-Item -LiteralPath $path -Force).Length
        $expected=[string](Get-TrialResultProperty $receipt 'traceSha256')
        if ($result.status -eq 'Complete' -and $expected) {
            if ($expected -cnotmatch '^[a-f0-9]{64}$' -or
                (Get-TrialResultProperty $receipt 'headerValidated') -isnot [bool] -or
                (Get-TrialResultProperty $receipt 'headerValidated') -ne $true -or
                (Get-TrialResultProperty $receipt 'traceBytes') -ne $bytes -or
                -not (Get-TrialResultProperty $receipt 'stoppedUtc')) { throw 'Invalid completed WPR header/hash/bytes/stop receipt' }
            $null=ConvertTo-TrialResultUtc (Get-TrialResultProperty $receipt 'stoppedUtc')
            if (-not $saved) { throw 'Completed WPR lacks its saved status receipt' }
            foreach ($field in @('status','traceFile','traceSha256','traceBytes','headerValidated','startedUtc','stopRequestedUtc','stoppedUtc','profileSha256','cleanupState','profileState')) {
                if ((Get-TrialResultProperty $saved $field) -cne (Get-TrialResultProperty $receipt $field)) { throw ('WPR wrapper/status mismatch: '+$field) }
            }
            $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -cne $expected) { throw 'WPR SHA256 mismatch' }
            $result.path=$path; $result.sha256=$hash; $result.bytes=$bytes; $result.verified=$true
            if ($Capture.Automatic -and $Capture.Path -and $Capture.CsvPath -and -not $Capture.Issues.Count) {
                # A final ETL can be valid yet end before the frame recording, e.g.
                # a helper watchdog stop. Bind coverage to the validated CX receipt.
                try {
                    $frames=Read-TrialResultJson (Join-Path $Run.Directory 'frame-capture.json')
                    $request=Get-TrialResultProperty $frames 'request'
                    $requested=Get-TrialResultProperty $request 'requestedUtc'
                    $ack=Get-TrialResultProperty $request 'acknowledgedUtc'
                    $began=Get-TrialResultProperty $receipt 'startedUtc'
                    $stopRequested=Get-TrialResultProperty $receipt 'stopRequestedUtc'
                    $ended=Get-TrialResultProperty $receipt 'stoppedUtc'
                    if (-not $requested -or -not $ack -or -not $began -or -not $stopRequested -or -not $ended) { throw 'Missing WPR/CapFrameX coverage timestamps' }
                    $first=ConvertTo-TrialResultUtc $requested
                    $last=(ConvertTo-TrialResultUtc $ack).AddSeconds([double](Get-TrialResultProperty $request 'seconds'))
                    # The stop command can stop events immediately, then spend a long
                    # time merging ETL. Successful command completion is not coverage.
                    $conservativeEnd=ConvertTo-TrialResultUtc $stopRequested
                    if ($conservativeEnd -gt (ConvertTo-TrialResultUtc $ended)) { throw 'WPR stop request is after successful stop completion' }
                    if ((ConvertTo-TrialResultUtc $began) -gt $first -or $conservativeEnd -lt $last) { throw 'WPR does not cover the full requested-through-acknowledged-plus-duration CapFrameX interval' }
                    $result.captureCoverage='Complete'
                } catch { $result.issues += ('WPR capture coverage is incomplete/unknown: '+$_.Exception.Message) }
            }
        } else {
            if ($bytes -gt 2147483648) { throw 'Unverified WPR trace exceeds the 2 GiB preservation limit' }
            $result.path=$path; $result.bytes=$bytes
            $result.sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            $result.issues += 'WPR trace is an unverified partial recording; no valid completed trace receipt'
        }
    } catch {
        $result.path=$null; $result.verified=$false
        $result.issues += ('Invalid/unavailable WPR evidence: '+$_.Exception.Message)
    }
    return $result
}

function New-TrialResultsBundle {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$PackageRoot,
          [string]$ControlCapture,
          [string]$OptimizedCapture)
    $ErrorActionPreference = 'Stop'
    $root = Assert-TrialResultPath $PackageRoot
    $runs = Join-Path $root 'Profiles/OptimizerTrial/TrialRuns'
    # Validate every input before creating the staging directory or output archive.
    $selected = @((Get-LatestTrialResult $runs 'Control'), (Get-LatestTrialResult $runs 'Optimized'))
    $captures = @()
    $selections = @($ControlCapture, $OptimizedCapture)
    for ($index = 0; $index -lt 2; $index++) {
        $mode = @('Control', 'Optimized')[$index]
        if ($selections[$index]) { $captures += Read-TrialCapture $selections[$index] $mode }
        else { $captures += Get-TrialAutomaticCapture $selected[$index] $mode }
    }
    if ($captures[0].Path -and $captures[1].Path -and ($captures[0].Path -eq $captures[1].Path -or $captures[0].Sha256 -eq $captures[1].Sha256)) {
        if (-not $captures[0].Automatic -and -not $captures[1].Automatic) { throw 'Select two different CapFrameX captures, one for each mode.' }
        foreach ($capture in $captures) {
            if ($capture.Automatic) { $capture.Issues += 'Control and Optimized CapFrameX captures are identical' }
        }
    }
    $diagnostics = Assert-TrialResultPath (Join-Path $root 'Diagnostics')
    [IO.Directory]::CreateDirectory($diagnostics) | Out-Null
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N')
    $stage = Join-Path $diagnostics ('.collect-' + $id)
    $archive = Join-Path $diagnostics ('PZDriving-Comparison-' + $id + '.zip')
    $utf8 = New-Object Text.UTF8Encoding($false)
    $runSummaries = @(); $missingPackage = @(); $readinessSnapshots=@(); $comparisonWarnings=@()
    try {
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        for ($index = 0; $index -lt 2; $index++) {
            $mode = @('Control', 'Optimized')[$index]
            $run = $selected[$index]; $receipt = $run.Receipt; $issues = @(); $included = @(); $diagnostic=$null
            $relativeFiles = @('launch.json', 'diagnostics.json', 'telemetry.jsonl', 'hardware.json', 'game-options.ini', 'session-console.txt', 'stdout.txt', 'stderr.txt')
            foreach ($relative in $relativeFiles) {
                $source = Join-Path $run.Directory $relative
                if (Test-Path -LiteralPath $source -PathType Leaf) {
                    Copy-TrialResultFile $source (Join-Path $stage ('Runs/' + $mode + '/' + $relative))
                    $included += $relative
                } else { $issues += "Missing $relative" }
            }
            $frameWrapper = Join-Path $run.Directory 'frame-capture.json'
            if (Test-Path -LiteralPath $frameWrapper -PathType Leaf) {
                try {
                    Copy-TrialResultFile $frameWrapper (Join-Path $stage ('Runs/' + $mode + '/frame-capture.json'))
                    $included += 'frame-capture.json'
                } catch { $issues += 'Unsafe/unavailable frame-capture.json was not copied' }
            }
            # Fixed filenames only: no accidental saves, account/config exports,
            # source profiles or unrelated files placed alongside diagnostics.
            foreach ($folder in @('JFR', 'JVM')) {
                $artifactRoot = Join-Path $run.Directory $folder
                $null = Assert-TrialResultPath $artifactRoot
                $artifactNames = @('drive.jfr', 'capture.json', 'summary.txt', 'java-version.txt', 'start-command.txt')
                if ($folder -eq 'JVM') { $artifactNames = @('VM-version.txt', 'VM-flags.txt', 'VM-command_line.txt', 'GC-heap_info.txt') }
                foreach ($name in $artifactNames) {
                    $source = Join-Path $artifactRoot $name
                    if (Test-Path -LiteralPath $source -PathType Leaf) {
                        Copy-TrialResultFile $source (Join-Path $stage ('Runs/' + $mode + '/' + $folder + '/' + $name))
                        $included += $folder + '/' + $name
                    }
                }
            }
            foreach ($required in @('JFR/drive.jfr', 'JFR/capture.json')) {
                $artifact = Join-Path $run.Directory $required
                if (-not (Test-Path -LiteralPath $artifact -PathType Leaf) -or (Get-Item -LiteralPath $artifact).Length -eq 0) { $issues += "Missing/empty $required" }
            }
            $diagnosticFile = Join-Path $run.Directory 'diagnostics.json'
            if (Test-Path -LiteralPath $diagnosticFile -PathType Leaf) {
                try {
                    $diagnostic = Read-TrialResultJson $diagnosticFile
                    if ((Get-TrialResultProperty $diagnostic 'format') -ne 1) { $issues += 'Unsupported diagnostics receipt format' }
                    if ((Get-TrialResultProperty $diagnostic 'status') -cne 'Complete') { $issues += 'Diagnostics did not complete' }
                    if ((Get-TrialResultProperty $diagnostic 'mode') -ine $mode) { $issues += 'Diagnostics mode mismatch' }
                    if ((Get-TrialResultProperty $diagnostic 'targetPid') -ne (Get-TrialResultProperty $receipt 'Pid')) { $issues += 'Diagnostics PID mismatch' }
                    if ((Get-TrialResultProperty $diagnostic 'jfrFile') -cne 'JFR/drive.jfr') { $issues += 'Diagnostics JFR artifact mismatch' }
                    $diagnosticStart = Get-TrialResultProperty $diagnostic 'processStartUtc'
                    $runStart = Get-TrialResultProperty $receipt 'ProcessStartUtc'
                    if (-not $diagnosticStart -or -not $runStart -or (ConvertTo-TrialResultUtc $diagnosticStart) -ne (ConvertTo-TrialResultUtc $runStart)) { $issues += 'Diagnostics process start mismatch' }
                } catch { $issues += 'Unreadable/invalid diagnostics receipt (preserved for analysis)' }
            }
            $diagnosticVersion=Get-TrialResultProperty $diagnostic 'diagnosticsVersion'
            $newArtifacts=@('capture-readiness-before.json','capture-readiness.json','sensor-coverage.json','wpr-capture.json')
            $artifactReferences=[ordered]@{}
            $readiness=$null
            foreach ($relative in $newArtifacts) {
                $source=Join-Path $run.Directory $relative
                $artifactReferences[$relative]=$null
                if (Test-Path -LiteralPath $source -PathType Leaf) {
                    try {
                        $value=Read-TrialResultJson $source
                        Copy-TrialResultFile $source (Join-Path $stage ('Runs/'+$mode+'/'+$relative))
                        $included += $relative
                        $artifactReferences[$relative]='Runs/'+$mode+'/'+$relative
                        if ((Get-TrialResultProperty $value 'format') -ne 1) { $issues += ('Unsupported '+$relative+' format') }
                        if ($relative -eq 'capture-readiness.json') { $readiness=$value }
                    } catch { $issues += ('Unsafe/unreadable '+$relative+' was not copied') }
                } elseif ($diagnosticVersion -ge 3) { $issues += ('Missing '+$relative) }
            }
            $readinessSnapshots += $readiness
            if ($readiness) {
                $gameOptions=Get-TrialResultProperty $readiness 'gameOptions'
                if ((Get-TrialResultProperty $gameOptions 'targetStatus') -cne 'Matches') {
                    $comparisonWarnings += ($mode+' saved target settings are mismatched/unknown; inspect capture-readiness.json and the between-run settings comparison. No specific FPS limit is required. Live gameplay settings are not proven.')
                }
            }
            $wprSummary=[pscustomobject]@{status='NotRequested'; receiptFile=$null; statusFile=$null; file=$null; sha256=$null; bytes=$null; verified=$false; verification='Header receipt, file bytes and SHA256 integrity only; captureCoverage is checked separately.'; captureCoverage='Unknown'; reason=$null; saveFailure=$null; cleanupState='Unknown'; profileState='Unknown'; profileSha256=$null; observedTempBytes=$null; temporaryFiles=@(); unverifiedFiles=@()}
            if ($diagnosticVersion -ge 3 -or (Test-Path -LiteralPath (Join-Path $run.Directory 'wpr-capture.json') -PathType Leaf)) {
                if ($diagnosticVersion -ge 3) {
                    if ((Get-TrialResultProperty $diagnostic 'extendedStatus') -cne 'Complete') { $issues += 'Extended diagnostics did not complete' }
                    if ((Get-TrialResultProperty $diagnostic 'wprStatus') -cne 'Complete') { $issues += 'WPR diagnostics did not complete' }
                }
                $wpr=Get-TrialWprResult $run $captures[$index]
                $issues += @($wpr.issues)
                $wprSummary.status=$wpr.status
                $wprSummary.captureCoverage=$wpr.captureCoverage
                $wprSummary.temporaryFiles=@($wpr.temporaryFiles)
                foreach ($field in @('reason','saveFailure','cleanupState','profileState','profileSha256','observedTempBytes')) { $wprSummary.$field=$wpr.$field }
                $wprSummary.receiptFile=$artifactReferences['wpr-capture.json']
                if ($wpr.statusPath) {
                    $relative='Runs/'+$mode+'/'+$wpr.directory+'/wpr-status.json'
                    try {
                        Copy-TrialResultFile $wpr.statusPath (Join-Path $stage $relative)
                        $wprSummary.statusFile=$relative; $included += $wpr.directory+'/wpr-status.json'
                    } catch { $issues += 'WPR status receipt unavailable during collection' }
                }
                if ($wpr.path) {
                    $relative='Runs/'+$mode+'/'+$wpr.directory+'/drive.etl'
                    $destination=Join-Path $stage $relative
                    try {
                        Copy-TrialResultFile $wpr.path $destination
                        if ((Get-Item -LiteralPath $destination).Length -ne $wpr.bytes -or
                            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $wpr.sha256) { throw 'WPR trace changed during collection' }
                        $included += $wpr.directory+'/drive.etl'
                        $wprSummary.file=$relative; $wprSummary.sha256=$wpr.sha256; $wprSummary.bytes=$wpr.bytes; $wprSummary.verified=$wpr.verified
                        if (-not $wpr.verified) { $wprSummary.unverifiedFiles=@([pscustomobject]@{file=$relative;sha256=$wpr.sha256;bytes=$wpr.bytes;assignment='Unverified partial WPR trace'}) }
                    } catch {
                        if (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
                        $issues += 'WPR trace unavailable/changed during collection and was omitted'
                    }
                }
                if (-not $wprSummary.verified -and -not $wpr.issues.Count) { $issues += 'WPR trace was not verified' }
            }
            $exitCode = Get-TrialResultProperty $receipt 'JavaExitCode'
            if ($null -eq $exitCode -or $exitCode -ne 0) { $issues += 'Game exit was not successful' }
            if ((Get-TrialResultProperty $receipt 'Activation') -notin @('Verified', 'ControlVerified')) { $issues += 'Full-pack activation was not verified' }
            $gameContext=Get-TrialBufferedGameContext $run $diagnostic
            if ($gameContext.status -notin @('Complete','Legacy')) { $issues += ('Buffered game context '+$gameContext.status+': '+$gameContext.reason) }
            $capture = $captures[$index]
            $captureRelative = $null; $csvRelative = $null; $unverifiedFiles = @(); $assignment = 'Explicitly unavailable (-)'
            if ($capture.Automatic) {
                $assignment = 'Automatic run receipt'
                $issues += @($capture.Issues)
                foreach ($source in @($capture.Unverified)) {
                    $relative = 'Runs/' + $mode + '/CapFrameX-unverified/' + [IO.Path]::GetFileName($source)
                    $destination = Join-Path $stage $relative
                    try {
                        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
                        Copy-TrialResultFile $source $destination
                        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) { throw 'Export changed during collection' }
                        $included += 'CapFrameX-unverified/' + [IO.Path]::GetFileName($source)
                        $unverifiedFiles += [pscustomobject]@{file=$relative; sha256=$hash; assignment='Unverified partial export'}
                    } catch {
                        if (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
                        $issues += ('Unverified CapFrameX export unavailable/changed during collection: ' + [IO.Path]::GetFileName($source))
                    }
                }
                foreach ($kind in @('Json', 'Csv')) {
                    $source=$capture.Path; $hash=$capture.Sha256
                    if ($kind -eq 'Csv') { $source=$capture.CsvPath; $hash=$capture.CsvSha256 }
                    if (-not $source) { continue }
                    $relative = 'Runs/' + $mode + '/CapFrameX/' + [IO.Path]::GetFileName($source)
                    $destination = Join-Path $stage $relative
                    try {
                        Copy-TrialResultFile $source $destination
                        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) {
                            throw 'File changed during collection'
                        }
                    } catch {
                        if (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
                        $issues += ('Automatic CapFrameX ' + $kind + ' unavailable/changed during collection and was omitted')
                        continue
                    }
                    $included += 'CapFrameX/' + [IO.Path]::GetFileName($source)
                    if ($kind -eq 'Json') { $captureRelative=$relative } else { $csvRelative=$relative }
                }
            } elseif ($capture.Path) {
                $assignment = 'Explicit user selection'
                $captureRelative = 'CapFrameX/' + $mode.ToLowerInvariant() + '.json'
                $captureDestination = Join-Path $stage $captureRelative
                Copy-TrialResultFile $capture.Path $captureDestination
                if ((Get-FileHash -LiteralPath $captureDestination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $capture.Sha256) { throw "$mode CapFrameX file changed during collection; close its editor and collect again." }
            } else { $issues += 'CapFrameX capture explicitly unavailable' }
            $runSummaries += [pscustomobject]@{ mode = $mode; runId = $run.Name; processStartUtc = (Get-TrialResultProperty $receipt 'ProcessStartUtc'); status = $(if ($issues.Count) { 'Incomplete' } else { 'Complete' }); issues = @($issues); files = @($included); diagnosticArtifacts=[pscustomobject]$artifactReferences; wpr=$wprSummary; gameContext=$gameContext; capFrameX = [pscustomobject]@{ file = $captureRelative; originalBasename = $capture.OriginalBasename; sha256 = $capture.Sha256; csvFile = $csvRelative; csvSha256 = $capture.CsvSha256; assignment = $assignment; unverifiedFiles = @($unverifiedFiles); sensorCoverageFile=$artifactReferences['sensor-coverage.json'] } }
        }
        $settingsComparison=[pscustomobject]@{status='Unknown'; differences=@(); reason='Saved capture readiness snapshots unavailable.'}
        if ($readinessSnapshots.Count -eq 2 -and $null -ne $readinessSnapshots[0] -and $null -ne $readinessSnapshots[1]) {
            try {
                $readinessScript=Join-Path $PSScriptRoot 'TrialReadiness.ps1'
                $null=Assert-TrialResultPath $readinessScript
                . $readinessScript
                $settingsComparison=Compare-TrialCaptureSettings $readinessSnapshots[0] $readinessSnapshots[1]
            } catch { $settingsComparison.reason='Saved option comparison unavailable; preserve and inspect capture-readiness.json.' }
        }
        if ($settingsComparison.status -ne 'Matches') { $comparisonWarnings += ('Control/Optimized saved game settings comparison: '+$settingsComparison.status+'. '+$settingsComparison.reason) }
        foreach ($name in @('pack-manifest.json', 'build-receipt.json', 'candidate-manifest.json', 'verification.txt')) {
            $source = Join-Path $root $name
            if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-TrialResultFile $source (Join-Path $stage $name) }
            else { $missingPackage += $name }
        }
        # Optional for legacy packages; the receipt records the profile hash actually used.
        $profileSource=Join-Path $root 'PZTrial.wprp'
        if (Test-Path -LiteralPath $profileSource -PathType Leaf) { Copy-TrialResultFile $profileSource (Join-Path $stage 'PZTrial.wprp') }
        $status = 'Complete'
        if ($missingPackage.Count -or @($runSummaries | Where-Object { $_.status -ne 'Complete' }).Count) { $status = 'Incomplete' }
        $summary = [pscustomobject]@{ format = 1; createdUtc = [DateTime]::UtcNow.ToString('o'); status = $status; runs = $runSummaries; missingPackageFiles = @($missingPackage); settingsComparison=$settingsComparison; comparisonWarnings=@($comparisonWarnings); captureAlignment = 'CapFrameX assignments and saved options are recorded per run; live settings, capture timing and gameplay/route equivalence require analysis. WPR uses file mode with recording overhead; zero lost events are not inferred.' }
        [IO.File]::WriteAllText((Join-Path $stage 'comparison.json'), ($summary | ConvertTo-Json -Depth 16), $utf8)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        # CreateFromDirectory uses CreateNew: never replace an existing archive.
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $archive)
        return [pscustomobject]@{ Path = $archive; Summary = $summary }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $ErrorActionPreference = 'Stop'
        # Resolve at execution time before any Join-Path. Never fall back to the
        # caller's working directory: it may contain results from another trial.
        if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot = $PSScriptRoot }
        if ([string]::IsNullOrWhiteSpace($PackageRoot) -and $MyInvocation.MyCommand.Path) {
            $PackageRoot = [IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
        }
        if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
            throw 'Cannot determine the trial package directory. Run Collect-results.cmd beside Collect-TrialResults.ps1, or specify -PackageRoot.'
        }
        $PackageRoot = Assert-TrialResultPath $PackageRoot
        if (-not $ControlCapture -and -not (Test-TrialAutomaticResult (Get-LatestTrialResult (Join-Path $PackageRoot 'Profiles/OptimizerTrial/TrialRuns') 'Control'))) { $ControlCapture = Read-Host 'Drag the Control CapFrameX JSON here (full path), or enter - if unavailable, then press Enter' }
        if (-not $OptimizedCapture -and -not (Test-TrialAutomaticResult (Get-LatestTrialResult (Join-Path $PackageRoot 'Profiles/OptimizerTrial/TrialRuns') 'Optimized'))) { $OptimizedCapture = Read-Host 'Drag the Optimized CapFrameX JSON here (full path), or enter - if unavailable, then press Enter' }
        $result = New-TrialResultsBundle -PackageRoot $PackageRoot -ControlCapture $ControlCapture -OptimizedCapture $OptimizedCapture
        Write-Host "$($result.Summary.status) result bundle: $($result.Path)"
        if ($result.Summary.status -ne 'Complete') { Write-Warning 'INCOMPLETE: available logs were preserved. See comparison.json for missing/failed evidence; this is not a successful comparison.' }
        Write-Host 'Send this one ZIP for analysis. Nothing was uploaded automatically.'
    } catch {
        [Console]::Error.WriteLine('Collection failed: ' + $_.Exception.Message)
        if ($_.InvocationInfo.PositionMessage) { [Console]::Error.WriteLine($_.InvocationInfo.PositionMessage) }
        if ($_.ScriptStackTrace) { [Console]::Error.WriteLine($_.ScriptStackTrace) }
        exit 1
    }
}
