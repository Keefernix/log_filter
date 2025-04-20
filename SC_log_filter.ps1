while ($true) 
{
    # Prompt user for multiple log file names
    $logFiles = (Read-Host "Enter the path to the log file (e.g., C:\Games\StarCitizen\LIVE\logbackups\Game Build(9508788) 07 Feb 25 (19 38 41).log)") -split '" "'
    $logFiles = $logFiles | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim('"') }

    # If the user entered 'exit', break the loop and exit
    if ($logFiles -contains "exit") 
    {
        Write-Host "Exiting the script."
        break
    }

    Write-Host "Log files: $($logFiles -join ', ')"

    # Validate the file paths
    $logFiles = $logFiles | Where-Object { Test-Path $_ }
    if ($logFiles.Count -eq 0) 
    {
        Write-Host "The specified file is not valid or does not exist. Please enter a valid path."
        $logFiles = (Read-Host "Enter the path to the log file (e.g., C:\Games\StarCitizen\LIVE\logbackups\Game Build(9508788) 07 Feb 25 (19 38 41).log)") -split '" "'
        $logFiles = $logFiles | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim('"') }
    }

    try 
    {
        foreach ($filePath in $logFiles) 
        {
            $reader = [System.IO.StreamReader]::new($filePath)
        
            $firstTimestamp = $null
            $lastTimestamp = $null
            $version = "v4.20"
            $easternTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
            $vehicleDestructionEvents = @{}
            $csvData = @()
            $entityData = @()
            $csvDataNormalized = @()
            $entityDataNormalized = @()

            function AdjustTime($utcDateTime) 
            {
                if ($utcDateTime.Kind -ne [System.DateTimeKind]::Utc) {
                    $utcDateTime = [System.DateTime]::SpecifyKind($utcDateTime, [System.DateTimeKind]::Utc)
                }
                $easternDateTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcDateTime, $easternTimeZone)
                $roundedSeconds = [math]::Round($easternDateTime.Second / 5) * 5
                return $easternDateTime.AddSeconds($roundedSeconds - $easternDateTime.Second)
            }
        
            while ($line = $reader.ReadLine()) 
            {
                # Extract timestamps on every relevant line
                if ($line -match "<(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)>") 
                {
                    $timestamp = [datetime]::ParseExact($matches[1], "yyyy-MM-ddTHH:mm:ss.fffZ", $null).ToUniversalTime()
                    if (-not $firstTimestamp) { $firstTimestamp = $timestamp }
                    $lastTimestamp = $timestamp
                }
        
                # Vehicle destruction detection
                if ($line -match "<Vehicle Destruction> CVehicle::OnAdvanceDestroyLevel:" -and $line -notmatch "_NPC_|NPC_Archetypes|_pet_|PU_Human|Kopion_|PU_Pilots-|AIModule_|vlk_juvenile_") 
                {
                    if ($line -match "<Vehicle Destruction> CVehicle::OnAdvanceDestroyLevel: Vehicle '([^']+)' \[.*?\] in zone '.*?' .*? driven by '([^']+)' \[.*?\] advanced from destroy level (\d) to (\d) caused by '([^']+)'") 
                    {
                        $vehicleId = $matches[1]
                        $fromLevel = [int]$matches[3]
                        $toLevel = [int]$matches[4]
                        $playerName = $matches[5]
        
                        if ($fromLevel -eq 0 -and $toLevel -eq 1) {
                            $vehicleDestructionEvents[$vehicleId] = $playerName
                        }
                    }
                }
                
                # Kill event parsing
                if ($line -match "<Actor Death>" -and $line -notmatch "_NPC_|NPC_Archetypes|_pet_|PU_Human|Kopion_|PU_Pilots-|AIModule_|vlk_juvenile_") 
                {
                    if ($line -match "<Actor Death> CActor::Kill: '([^']+)' \[\d+\] in zone '([^']+)' killed by '([^']+)' \[\d+\] using '([^']+)' \[Class.*?\] with damage type '([^']+)' ") 
                    {
                        if ($matches.Count -gt 5) 
                        {
                            $playerKilled = $matches[1]
                            $zone = $matches[2]
                            $playerKiller = $matches[3]
                            $weaponUsed = $matches[4]
                            $damageType = $matches[5]
                        }
        
                        $associatedPlayer = $vehicleDestructionEvents.GetEnumerator() | Where-Object { $_.Key -eq $zone }
        
                        if ($associatedPlayer) 
                        {
                            if ($associatedPlayer.Value -ne $playerKiller) 
                            {
                                if ($damageType -eq "VehicleDestruction") { $weaponUsed = $playerKiller }
                                $playerKiller = $associatedPlayer.Value
                                if ($damageType -eq "suicide") 
                                {
                                    $damageType = "Suicide (Shot Down)"
                                    $weaponUsed = "Despair"
                                }
                                if ($damageType -eq "crash") 
                                {
                                    $damageType = "Crash (Shot Down)"
                                    $weaponUsed = "Gravity"
                                }
                            }
                        }
        
                        # Adjust and format the timestamp
                        $adjustedLogTime = AdjustTime $timestamp
                        $adjustedLogTime = $adjustedLogTime.ToString("MM/dd/yyyy h:mm:ss tt")
        
                        # Cleanup fields
                        $zone = $zone -replace "_\d{13}", "" -replace "_01", ""
                        $weaponUsed = $weaponUsed -replace "_\d{13}", "" -replace "_01", ""
                        $damageType = $damageType -replace "_\d{13}", "" -replace "_01", ""
        
                        $csvData += [PSCustomObject]@{
                            date_time      = $adjustedLogTime
                            player_killed  = $playerKilled
                            zone           = $zone
                            player_killer  = $playerKiller
                            weapon_used    = $weaponUsed
                            damage_type    = $damageType
                        }
                    }
                }
            }
            $reader.Close()
        
            if ($firstTimestamp -and $lastTimestamp) 
            {
                $firstTimestamp = AdjustTime $firstTimestamp
                $lastTimestamp = AdjustTime $lastTimestamp
                $formattedFirstTimestamp = $firstTimestamp.ToString("MM-dd_HH-mm")
                $formattedLastTimestamp = $lastTimestamp.ToString("MM-dd_HH-mm")
                $outputFileName = "${formattedFirstTimestamp}_to_${formattedLastTimestamp}_${version}.csv"
                Remove-Item $outputFileName -ErrorAction SilentlyContinue
                # Export CSV here if needed
            } else 
            {
                Write-Host "No valid timestamps found in the log file."
                exit
            }

            # Export the parsed data to CSV
            if ($csvData.Count -gt 0 -or $entityData.Count -gt 0) 
            {
                # Normalize kills data
                $csvDataNormalized = $csvData | ForEach-Object {
                    [PSCustomObject]@{
                        type          = "kill"
                        date_time     = $_.date_time
                        player_killed = $_.player_killed
                        zone          = $_.zone
                        player_killer = $_.player_killer
                        weapon_used   = $_.weapon_used
                        damage_type   = $_.damage_type
                    }
                }

                # Normalize entity data
                $entityData = $entityData | Sort-Object entity, owner_geid -Unique
                $entityData = $entityData | Where-Object { $_.owner_geid -ne "Unknown" }
                $entityDataNormalized = $entityData | ForEach-Object {
                    [PSCustomObject]@{
                        type          = "entity"
                        date_time     = ""
                        player_killed = ""
                        zone          = ""
                        player_killer = ""
                        weapon_used   = ""
                        damage_type   = ""
                    }
                }

                # Merge and export
                $combinedData = @()
                $combinedData += $csvDataNormalized
                $combinedData += $entityDataNormalized
                $combinedData | Export-Csv -NoTypeInformation -Path $outputFileName
                Write-Host "Merged data saved to $outputFileName"
            } 
            else 
            {
                # Add a fake record to the CSV file so it's not empty
                $csvData += [PSCustomObject]@{
                    date_time        = "no kills found"
                    player_killed   = "none"
                    zone            = "none"
                    player_killer   = "none"
                    weapon_used     = "none"
                    damage_type     = "none"
                }
                $csvData | Export-Csv -Path $outputFileName -NoTypeInformation
                Write-Host "No valid logs found. A blank CSV file has been created to log time played."
            }
        }
    } 
    catch 
    {
        Write-Host "Error opening file: $_"
        exit
    }
}
