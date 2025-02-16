# Prompt user for the log file name
$filePath = Read-Host "Enter the path to the log file (e.g., C:\Games\StarCitizen\LIVE\logbackups\Game Build(9508788) 07 Feb 25 (19 38 41).log)"

# Remove surrounding quotes if they exist
$filePath = $filePath.Trim('"')

# Validate the file path
if (-not (Test-Path $filePath)) {
    Write-Host "The specified file does not exist. Please enter a valid path."
    $filePath = Read-Host "Enter the path to the log file (e.g., C:\Games\StarCitizen\LIVE\logbackups\Game Build(9508788) 07 Feb 25 (19 38 41).log)"
    $filePath = $filePath.Trim('"')  # Reapply the trimming to the new input
}

# Open the specified log file for reading
try {
    $reader = [System.IO.StreamReader]::new($filePath)
} catch {
    Write-Host "Error opening file: $_"
    exit
}

$filteredLines = @()
$firstTimestamp = $null
$lastTimestamp = $null

# First pass: Extract timestamps from all lines
while ($line = $reader.ReadLine()) {
    if ($line -match "<(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)>") {
        $timestamp = $matches[1]
        if (-not $firstTimestamp) {
            $firstTimestamp = [datetime]::ParseExact($timestamp, "yyyy-MM-ddTHH:mm:ss.fffZ", $null)
        }
        $lastTimestamp = [datetime]::ParseExact($timestamp, "yyyy-MM-ddTHH:mm:ss.fffZ", $null)
    }
}

# Close the reader after first pass
$reader.Close()

# Format the timestamps as mm-dd_hh-mm (replacing colons and "T" and "Z")
if ($firstTimestamp -and $lastTimestamp) {
    # Extract and format the first timestamp as MM-dd_HH-mm
    $formattedFirstTimestamp = $firstTimestamp.ToString("MM-dd_HH-mm")
    # Extract and format the last timestamp as MM-dd_HH-mm
    $formattedLastTimestamp = $lastTimestamp.ToString("MM-dd_HH-mm")
} else {
    Write-Host "No valid timestamps found in the log file."
    exit
}

# Build the output file name using the first and last timestamps
$outputFileName = "${formattedFirstTimestamp}_to_${formattedLastTimestamp}.csv"

# Remove the previous output file, if it exists
Remove-Item $outputFileName -ErrorAction SilentlyContinue

# Reopen the file for filtering
$reader = [System.IO.StreamReader]::new($filePath)

# Second pass: Filter lines and parse relevant data
$csvData = @()
while ($line = $reader.ReadLine()) {
    if ($line -match "<Actor Death>" -and $line -notmatch "_NPC_" -and $line -notmatch "NPC_Archetypes" -and $line -notmatch "_pet_" -and $line -notmatch "PU_Human" -and $line -notmatch "Kopion_" -and $line -notmatch "PU_Pilots-" -and $line -notmatch "with damage type 'Suicide'" -and $line -notmatch "AIModule_") {
        
        # Parse the kill event data
        if ($line -match "CActor::Kill: '(.*?)' \[\d+\] in zone '(.*?)' killed by '(.*?)' \[\d+\] using '(.*?)' \[Class.*?\] with damage type '(.*?)'") {
            $playerKilled = $matches[1]
            $zone = $matches[2]
            $playerKiller = $matches[3]
            $weaponUsed = $matches[4]
            $damageType = $matches[5]

            # Format the timestamp to MM/dd - HH:mm
            if ($line -match "<(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)>") {
                $logTime = [datetime]::ParseExact($matches[1], "yyyy-MM-ddTHH:mm:ss.fffZ", $null)
                $formattedLogDate = $logTime.ToString("MM/dd")
                $formattedLogTime = $logTime.ToString("HH:mm")
            }

            # Trim '_01' and '_<digits>' from player, zone, weapon and damage type fields
            $playerKilled = $playerKilled
            $zone = $zone -replace "_\d{13}", "" -replace "_01", ""
            $playerKiller = $playerKiller
            $weaponUsed = $weaponUsed -replace "_\d{13}", "" -replace "_01", ""
            $damageType = $damageType -replace "_\d{13}", "" -replace "_01", ""

	    # Generate unique ID based on a mixture of elements (timestamp, players, zone, weapon)
            $uniqueID = "{0}_{1}_{2}_{3}_{4}" -f $formattedLogDate, $formattedLogTime, $playerKilled, $zone, $weaponUsed

            # Create a custom object to hold the data
            $csvData += [PSCustomObject]@{
		id	       = $uniqueID
                date           = $formattedLogDate
                time           = $formattedLogTime
                player_killed   = $playerKilled
                zone           = $zone
                player_killer   = $playerKiller
                weapon_used     = $weaponUsed
                damage_type     = $damageType
            }
        }
    }
}

# Close the reader after filtering
$reader.Close()

# Export the parsed data to CSV
$csvData | Export-Csv -Path $outputFileName -NoTypeInformation

Write-Host "Filtered and parsed data has been saved to $outputFileName"
