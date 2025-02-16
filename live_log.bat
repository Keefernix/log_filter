@echo off
cd /d "C:\Games\StarCitizen\LIVE"
powershell -Command "Get-Content 'game.log' -Tail 0 -Wait | Select-String '\[Actor\]'"
