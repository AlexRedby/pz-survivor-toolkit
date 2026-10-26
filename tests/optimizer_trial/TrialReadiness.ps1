# Read-only saved-file evidence. No settings are changed and no live sensor state is inferred.
# Verified schema: CapFrameX v1.9.1.5, commit 9f488ea6c39e33ec25c6ebfae1c4a1c4063c3026:
# source/CapFrameX.Configuration/CapFrameXConfiguration.cs (UseSensorLogging)
# source/CapFrameX.Sensor/SensorConfig.cs (identifier -> boolean selection files)
# source/CapFrameX.Data.Session/Classes/{SessionRun,SessionSensorData,SessionSensorData2}.cs
# https://github.com/CXWorld/CapFrameX/tree/9f488ea6c39e33ec25c6ebfae1c4a1c4063c3026
function Get-TrialReadinessProperty($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Read-TrialReadinessJson([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{status='Unknown'; data=$null; reason='File unavailable.'}
    }
    try {
        $value = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $value -or $value -isnot [pscustomobject]) { throw 'Expected a JSON object.' }
        return [pscustomobject]@{status='Read'; data=$value; reason=$null}
    } catch { return [pscustomobject]@{status='Unknown'; data=$null; reason='Unreadable or unsupported JSON object.'} }
}

function Get-TrialSavedOptions([string]$OptionsPath) {
    $values = [ordered]@{}
    $duplicates = @()
    $readStatus = 'Unknown'
    $sha256 = $null
    try {
        if (-not $OptionsPath -or -not (Test-Path -LiteralPath $OptionsPath -PathType Leaf)) { throw 'File unavailable.' }
        # Hash and parse the same byte snapshot, even if the game saves settings concurrently.
        $bytes = [IO.File]::ReadAllBytes($OptionsPath)
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $sha256 = ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
        finally { $hash.Dispose() }
        $text = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
        foreach ($line in ($text -split '\r?\n')) {
            if ($line -match '^\s*([^#;=]+?)\s*=(.*)$') {
                $key=$matches[1].Trim(); $value=$matches[2].Trim()
                if ($values.Contains($key)) { $duplicates += $key }
                $values[$key]=$value
            }
        }
        if ($values.Count -gt 0 -and $duplicates.Count -eq 0) { $readStatus='Read' }
    } catch { }
    $checks = @()
    foreach ($setting in @(@('width','2560'), @('height','1440'), @('vsync','false'), @('frameRate',$null))) {
        $key=$setting[0]; $expected=$setting[1]; $actual=$null; $status='Unknown'
        if ($values.Contains($key)) {
            $actual=$values[$key]
            $supported = $actual -match '^\d+$'
            if ($key -eq 'vsync') { $supported = $actual -cmatch '^(true|false)$' }
            if ($supported -and $duplicates -notcontains $key) {
                $status='Mismatch'
                if ($key -eq 'frameRate') { $status='Recorded' }
                elseif ($actual -ceq $expected) { $status='Matches' }
            }
        }
        $checks += [pscustomobject]@{key=$key; expected=$expected; actual=$actual; status=$status}
    }
    $targetStatus='Matches'
    if (@($checks | Where-Object {$_.status -eq 'Mismatch'}).Count) { $targetStatus='Mismatch' }
    elseif ($readStatus -ne 'Read' -or @($checks | Where-Object {$_.status -eq 'Unknown'}).Count) { $targetStatus='Unknown' }
    return [pscustomobject]@{
        status=$readStatus; source='Saved options.ini snapshot; live game settings are not queried.'
        sha256=$sha256; values=[pscustomobject]$values; duplicateKeys=@($duplicates)
        targetStatus=$targetStatus; targetChecks=@($checks)
    }
}

function Get-TrialSensorSelection([string]$Path) {
    $read=Read-TrialReadinessJson $Path
    $selected=@(); $disabled=@(); $invalid=@()
    if ($read.status -eq 'Read') {
        foreach ($property in $read.data.PSObject.Properties) {
            if ($property.Value -isnot [bool]) { $invalid += $property.Name }
            elseif ($property.Value) { $selected += $property.Name }
            else { $disabled += $property.Name }
        }
    }
    $status=$read.status
    if ($invalid.Count) { $status='Unknown' }
    return [pscustomobject]@{file=[IO.Path]::GetFileName($Path); status=$status; selected=@($selected); disabled=@($disabled); invalidKeys=@($invalid)}
}

function Get-TrialCaptureReadiness($FrameClient, [string]$OptionsPath) {
    $options=Get-TrialSavedOptions $OptionsPath
    $configPath=[string](Get-TrialReadinessProperty $FrameClient 'ConfigPath')
    $read=Read-TrialReadinessJson $configPath
    $enabled=$null; $loggingStatus='Unknown'; $selection=@()
    if ($read.status -eq 'Read') {
        $saved=Get-TrialReadinessProperty $read.data 'UseSensorLogging'
        if ($saved -is [bool]) {
            $enabled=$saved; $loggingStatus='Disabled'
            if ($saved) { $loggingStatus='Enabled' }
        }
    }
    if ($configPath) {
        $directory=[IO.Path]::GetDirectoryName($configPath)
        foreach ($name in @('SensorEntryConfiguration.json','SensorEntryConfigurationStable.json')) {
            $selection += Get-TrialSensorSelection (Join-Path $directory $name)
        }
    }
    $summary=@('Saved game options: '+$options.targetStatus+' (suggested 2560x1440, VSync off).')
    foreach ($check in $options.targetChecks) {
        if ($check.key -eq 'frameRate' -and $check.status -eq 'Recorded') {
            $summary += ('Saved FPS limit: '+$check.actual+'. Keep it the same across paired runs; this limit does not explain hitches below it.')
        } elseif ($check.status -notin @('Matches','Recorded')) {
            $actual=[string]$check.actual
            if (-not $actual) { $actual='unknown' }
            if ($check.key -eq 'frameRate') {
                $summary += 'Saved FPS limit is unknown; note the current value and keep it the same across paired runs.'
            } else {
                $summary += ('Check the game settings before capture: '+$check.key+'='+$actual+'; suggested '+$check.expected+'.')
            }
        }
    }
    $summary += ('CapFrameX saved sensor logging: '+$loggingStatus+'. Source configuration is advisory; confirm actual sensors in the completed recording.')
    if ($loggingStatus -ne 'Enabled') { $summary += 'In CapFrameX, check sensor logging and select the needed CPU/GPU sensors before recording.' }
    $selectedCount=0
    foreach ($file in $selection) { $selectedCount += @($file.selected).Count }
    $summary += ('Saved sensor selection entries: '+$selectedCount+' (identifier and stable-identifier files may overlap). Check CPU/GPU sensor selections in CapFrameX if none are listed; unavailable metadata does not block capture.')
    $summary += 'Missing or unsupported CPU/GPU load, clocks, temperatures, power, RAM/VRAM and limit sensors remain unknown; they do not block capture.'
    return [pscustomobject]@{
        format=1; collectedUtc=[DateTime]::UtcNow.ToString('o'); gameOptions=$options
        capFrameX=[pscustomobject]@{
            version=(Get-TrialReadinessProperty $FrameClient 'Version'); configStatus=$read.status
            savedSensorLoggingStatus=$loggingStatus; savedUseSensorLogging=$enabled; selectionFiles=@($selection)
            liveSensorLoggingStatus='Unknown'; evidence='Saved source configuration only; running settings and hardware support are unknown until recorded.'
        }
        summary=@($summary)
    }
}

function Write-TrialCaptureReadiness($Readiness) {
    foreach ($line in @($Readiness.summary)) { Write-Host ('CAPTURE CHECK: '+$line) }
}

function Compare-TrialCaptureSettings($Reference, $Candidate) {
    # Accept the complete readiness objects saved in capture-readiness.json.
    $before=Get-TrialReadinessProperty $Reference 'gameOptions'
    $after=Get-TrialReadinessProperty $Candidate 'gameOptions'
    $changes=@()
    if ((Get-TrialReadinessProperty $before 'status') -ne 'Read' -or
        (Get-TrialReadinessProperty $after 'status') -ne 'Read') {
        return [pscustomobject]@{status='Unknown'; differences=@(); reason='Both saved option snapshots must be readable and unambiguous.'}
    }
    $left=Get-TrialReadinessProperty $before 'values'; $right=Get-TrialReadinessProperty $after 'values'
    $names=@(@($left.PSObject.Properties.Name)+@($right.PSObject.Properties.Name) | Sort-Object -Unique)
    foreach ($name in $names) {
        $a=Get-TrialReadinessProperty $left $name; $b=Get-TrialReadinessProperty $right $name
        if ($a -cne $b) { $changes += [pscustomobject]@{key=$name; reference=$a; candidate=$b} }
    }
    $status='Matches'
    if ($changes.Count) { $status='Mismatch' }
    return [pscustomobject]@{status=$status; differences=@($changes); reason='All parsed saved options compared; runtime state and driver overrides are not queried.'}
}

function Get-TrialSensorCategory([string]$Name, [string]$Type, [string]$Identifier) {
    $label=$Name+' '+$Identifier
    $device=$null
    if ($label -match '(?i)gpu|nvidia|radeon|geforce') { $device='gpu' }
    elseif ($label -match '(?i)cpu|intelcpu|amdcpu') { $device='cpu' }
    if ($label -match '(?i)limit|throttl' -and $device) { return $device+'Limits' }
    if ($device) {
        switch ($Type) {
            'Load' { return $device+'Load' }
            'Clock' { return $device+'Clock' }
            'Temperature' { return $device+'Temperature' }
            'Power' { return $device+'Power' }
        }
    }
    if ($Type -in @('Data','SmallData') -and $label -match '(?i)vram|dedicated|gpu.*memory') { return 'vramUsage' }
    if ($Type -in @('Data','SmallData') -and $label -match '(?i)ram|memory.*used') { return 'ramUsage' }
    return $null
}

function Get-TrialRecordedSensors([string]$JsonPath) {
    $read=Read-TrialReadinessJson $JsonPath
    $inventory=@(); $coverage=[ordered]@{}
    $categories=@('cpuLoad','cpuClock','cpuTemperature','cpuPower','cpuLimits','gpuLoad','gpuClock','gpuTemperature','gpuPower','gpuLimits','ramUsage','vramUsage')
    foreach ($category in $categories) { $coverage[$category]=[pscustomobject]@{status='Unknown'; sensors=@(); finiteSamples=0} }
    $runs=@(Get-TrialReadinessProperty $read.data 'Runs' @())
    $runIndex=0
    foreach ($run in $runs) {
        $data=Get-TrialReadinessProperty $run 'SensorData2'
        $entries=@()
        if ($null -ne $data -and $data -is [pscustomobject]) {
            foreach ($property in $data.PSObject.Properties) {
                if ($property.Name -in @('MeasureTime','BetweenMeasureTime')) { continue }
                $entry=$property.Value
                $values=@()
                if ($entry -is [pscustomobject]) {
                    $valuesProperty=$entry.PSObject.Properties['Values']
                    if ($null -ne $valuesProperty -and $valuesProperty.Value -is [array]) { $values=$valuesProperty.Value }
                }
                $entries += [pscustomobject]@{id=$property.Name; name=(Get-TrialReadinessProperty $entry 'Name'); type=(Get-TrialReadinessProperty $entry 'Type'); values=$values; schema='SensorData2'}
            }
        } else {
            # Legacy fields are defined by SessionSensorData.cs, not guessed from array positions.
            $legacy=Get-TrialReadinessProperty $run 'SensorData'
            $map=@(@('CpuUsage','CPU Total','Load'),@('CpuMaxThreadUsage','CPU Max Thread','Load'),@('CpuMaxClock','CPU Max','Clock'),@('CpuPower','CPU Package','Power'),@('CpuTemp','CPU Package','Temperature'),@('GpuUsage','GPU Core','Load'),@('GpuClock','GPU Core','Clock'),@('GpuPower','GPU Power','Power'),@('GpuTemp','GPU Core','Temperature'),@('RamUsage','RAM Game Used','Data'),@('VRamUsage','Dedicated','SmallData'),@('VRamUsageGB','Dedicated','Data'),@('GPUPowerLimit','GPU Power Limit','Factor'))
            foreach ($field in $map) {
                if ($legacy -is [pscustomobject]) {
                    $valuesProperty=$legacy.PSObject.Properties[$field[0]]
                    if ($null -ne $valuesProperty -and $valuesProperty.Value -is [array]) {
                        $entries += [pscustomobject]@{id=$field[0]; name=$field[1]; type=$field[2]; values=$valuesProperty.Value; schema='SensorData'}
                    }
                }
            }
        }
        foreach ($entry in $entries) {
            $finite=0; $total=0
            foreach ($value in @($entry.values)) {
                $total++
                # JSON.NET serializes unavailable NaN/Infinity as strings. Reject strings,
                # null and booleans; numeric zero is valid evidence (including inactive limits).
                if ($null -eq $value -or $value -is [string] -or $value -is [bool] -or $value -is [pscustomobject]) { continue }
                if ($value -is [ValueType]) {
                    $number=[double]$value
                    if (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) { $finite++ }
                }
            }
            $category=Get-TrialSensorCategory ([string]$entry.name) ([string]$entry.type) ([string]$entry.id)
            $status='Unknown'
            if ($finite -gt 0) { $status='Recorded' }
            $inventory += [pscustomobject]@{run=$runIndex; id=$entry.id; name=$entry.name; type=$entry.type; schema=$entry.schema; category=$category; status=$status; finiteSamples=$finite; totalSamples=$total}
            if ($category -and $finite -gt 0) {
                $coverage[$category].status='Recorded'; $coverage[$category].sensors += $entry.id
                $coverage[$category].finiteSamples += $finite
            }
        }
        $runIndex++
    }
    $status='Unknown'
    if (@($inventory | Where-Object {$_.finiteSamples -gt 0}).Count) { $status='Recorded' }
    return [pscustomobject]@{
        format=1; status=$status; jsonStatus=$read.status; runs=$runs.Count
        coverage=[pscustomobject]$coverage; sensors=@($inventory)
        limitation='Recorded means at least one finite sample, not complete time coverage or proof that limits/throttling occurred. Missing, unsupported and unavailable sensors remain unknown.'
    }
}
