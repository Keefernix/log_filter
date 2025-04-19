@echo off
cd /d "F:\Games\StarCitizen\LIVE"
powershell -Command "Get-Content 'game.log' -Tail 0 -Wait | ? { $_ -match '\[Actor\]'"