# Prompt user for multiple log file names
$logFiles = (Read-Host "Enter the path to the log file (e.g., C:\Games\StarCitizen\LIVE\logbackups\Game Build(9508788) 07 Feb 25 (19 38 41).log)") -split '" "'
$logFiles = $logFiles | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim('"') }

Write-Host "Log files: $($logFiles -join ', ')"

# Validate the file paths
$logFiles = $logFiles | Where-Object { Test-Path $_ }
if ($logFiles.Count -eq 0) {
    Write-Host "The specified file is not valid or does not exist. Please enter a valid path."
    $logFiles = (Read-Host "Enter the path to the log file (e.g., C:\Games\StarCitizen\LIVE\logbackups\Game Build(9508788) 07 Feb 25 (19 38 41).log)") -split '" "'
    $logFiles = $logFiles | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim('"') }
}

try 
{
    # Process each log file
    foreach ($filePath in $logFiles) {
        # Open the log file for reading
        $reader = [System.IO.StreamReader]::new($filePath)

        # Initialize variables
        $firstTimestamp = $null
        $lastTimestamp = $null
        $version = "v3.0"

        # Eastern Time Zone Information
        $easternTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")

        # First pass: Extract timestamps from all lines
        while ($line = $reader.ReadLine()) 
        {
            if ($line -match "<(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)>") 
            {
                $timestamp = $matches[1]
                if (-not $firstTimestamp) 
                {
                    $firstTimestamp = [datetime]::ParseExact($timestamp, "yyyy-MM-ddTHH:mm:ss.fffZ", $null).ToUniversalTime()
                }
                $lastTimestamp = [datetime]::ParseExact($timestamp, "yyyy-MM-ddTHH:mm:ss.fffZ", $null).ToUniversalTime()
            }
        }

        # Close the reader after first pass
        $reader.Close()

        # Convert to Eastern Time and round seconds to nearest 5-second interval
        function AdjustTime($utcDateTime) 
        {
            # Ensure input is in UTC
            if ($utcDateTime.Kind -ne [System.DateTimeKind]::Utc) {
                $utcDateTime = [System.DateTime]::SpecifyKind($utcDateTime, [System.DateTimeKind]::Utc)
            }
        
            # Convert the UTC time to Eastern Time Zone
            $easternTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
            $easternDateTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcDateTime, $easternTimeZone)
        
            # Round seconds to the nearest 5
            $roundedSeconds = [math]::Round($easternDateTime.Second / 5) * 5
        
            # Create a new DateTime with the adjusted seconds (but keep it as a DateTime, not string)
            $adjustedDateTime = $easternDateTime.AddSeconds($roundedSeconds - $easternDateTime.Second)
        
            # Return the DateTime object (you can format it as needed later, but keep it in DateTime)
            return $adjustedDateTime
        }

        # Format the timestamps as mm-dd_hh-mm (replacing colons and "T" and "Z")
        if ($firstTimestamp -and $lastTimestamp) 
        {
            # Adjust timestamps
            $firstTimestamp = AdjustTime $firstTimestamp
            $lastTimestamp = AdjustTime $lastTimestamp

            # Extract and format the first timestamp as MM-dd_HH-mm
            $formattedFirstTimestamp = $firstTimestamp.ToString("MM-dd_HH-mm")
            # Extract and format the last timestamp as MM-dd_HH-mm
            $formattedLastTimestamp = $lastTimestamp.ToString("MM-dd_HH-mm")
        } 
        else 
        {
            Write-Host "No valid timestamps found in the log file."
            exit
        }

        # Build the output file name using the first and last timestamps
        $outputFileName = "${formattedFirstTimestamp}_to_${formattedLastTimestamp}_${version}.csv"

        # Remove the previous output file, if it exists
        Remove-Item $outputFileName -ErrorAction SilentlyContinue

        # Reopen the file for filtering
        $reader = [System.IO.StreamReader]::new($filePath)

        # Store vehicle destruction events and the associated player (who brought the vehicle from 0-1)
        $vehicleDestructionEvents = @{}

        # Second pass: Filter lines and parse relevant data
        $csvData = @()
        while ($line = $reader.ReadLine()) 
        {
            # Parse vehicle destruction level advance event
            if ($line -match "<Vehicle Destruction> CVehicle::OnAdvanceDestroyLevel: Vehicle '([^']+)' \[.*?\] in zone '.*?' .*? driven by '([^']+)' \[.*?\] advanced from destroy level (\d) to (\d) caused by '([^']+)'")
            {
                $vehicleId = $matches[1]
                $fromLevel = [int]$matches[3]
                $toLevel = [int]$matches[4]
                $playerName = $matches[5]

                # If the vehicle advanced from level 0 to 1, store the player
                if ($fromLevel -eq 0 -and $toLevel -eq 1) 
                {
                    $vehicleDestructionEvents[$vehicleId] = $playerName
                }
            }

            # Parse kill event
            if ($line -match "<Actor Death>" -and $line -notmatch "_NPC_" -and $line -notmatch "NPC_Archetypes" -and $line -notmatch "_pet_" -and $line -notmatch "PU_Human" -and $line -notmatch "Kopion_" -and $line -notmatch "PU_Pilots-" -and $line -notmatch "AIModule_")
            {
                if ($line -match "<Actor Death> CActor::Kill: '([^']+)' \[\d+\] in zone '([^']+)' killed by '([^']+)' \[\d+\] using '([^']+)' \[Class.*?\] with damage type '([^']+)' ") 
                {
                    if ($matches.Count -gt 5) {
                        $playerKilled = $matches[1]
                        $zone = $matches[2]
                        $playerKiller = $matches[3]
                        $weaponUsed = $matches[4]
                        $damageType = $matches[5]
                    } 
                
                    # Check if the zone of the kill matches the vehicle destruction zone
                    $associatedPlayer = $vehicleDestructionEvents.GetEnumerator() | Where-Object { $_.Key -eq $zone }
                
                    # If we have a vehicle destruction event for this vehicle
                    if ($associatedPlayer) {
                        # Ensure the player killer isn't the same as the player who caused the vehicle destruction level to progress
                        if ($associatedPlayer.Value -ne $playerKiller) {
                            # Credit the player who advanced the vehicle to level 1, if the damage type matches vehicle destruction
                            if ($damageType -eq "VehicleDestruction") {
                                $weaponUsed = $playerKiller  # Credit the player who advanced the vehicle
                            }
                        
                            # Now, assign the credit to the correct player (who advanced the vehicle from level 0 to 1)
                            $playerKiller = $associatedPlayer.Value  # Assign the correct player who gets the credit

                            # Additional checks if damageType is "suicide" or "crash"
                            if ($damageType -eq "suicide") {
                                $damageType = "Suicide (Shot Down)"
                                $weaponUsed = "Despair"
                            }
                            if ($damageType -eq "crash") {
                                $damageType = "Crash (Shot Down)"
                                $weaponUsed = "Gravity"
                            }
                        }
                    }
                

                    # Format the timestamp to MM/dd - HH:mm
                    if ($line -match "<(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)>") 
                    {
                        $logTime = [datetime]::ParseExact($matches[1], "yyyy-MM-ddTHH:mm:ss.fffZ", $null).ToUniversalTime()
                        $adjustedLogTime = AdjustTime $logTime
                        #$formattedLogDate = $adjustedLogTime.ToString("MM-dd")
                        #$formattedLogTime = $adjustedLogTime.ToString("HH:mm:ss")
                    }

                    # Trim '_01' and '_<digits>' from player, zone, weapon, and damage type fields
                    $zone = $zone -replace "_\d{13}", "" -replace "_01", ""
                    $weaponUsed = $weaponUsed -replace "_\d{13}", "" -replace "_01", ""
                    $damageType = $damageType -replace "_\d{13}", "" -replace "_01", ""
                    $adjustedLogTime = $adjustedLogTime.ToString("MM/dd/yyyy h:mm:ss tt")
                    # Create a custom object to hold the data
                    $csvData += [PSCustomObject]@{
                        date_time        = $adjustedLogTime
                        player_killed   = $playerKilled
                        zone            = $zone
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
        if ($csvData.Count -gt 0) {
            $csvData | Export-Csv -Path $outputFileName -NoTypeInformation
            Write-Host "Filtered and parsed data has been saved to $outputFileName"
        } else {
            Write-Host "No valid logs found. No file created."
        }

            & $MyInvocation.MyCommand.Path
    }
} 
catch 
{
    Write-Host "Error opening file: $_"
    exit
}