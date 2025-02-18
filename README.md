Live Log and Log Filter Usage Guide

live_log.bat

The live_log.bat file is designed to be run directly. It will keep a terminal window open and continuously display any player activity in your vicinity.

By default, it assumes that Star Citizen is installed at C:\Games\StarCitizen\LIVE.
If your installation is located elsewhere, right-click the file and edit the path in Notepad to match your installation directory.

log_filter.ps1

The log_filter.ps1 file is the actual program that processes the logs. However, to make it easier to run, the log_filter.bat file is provided, so you can simply double-click it to execute the program.
Running the Log Filter

When you run the log_filter.bat file, it will prompt you to select a log file.
Drag any Star Citizen log file into the terminal window and press Enter.
The program will parse the log and generate a CSV file containing only the relevant player kills and deaths.

Uploading to the Kill Log Channel

Once you have the CSV file:

Go to your kill_log channel.
Use the !add_log command to upload the CSV file.
The bot will parse the file, extract the ORG members' data, and add it to the database, where it can be viewed in the kill_logs channel.

Downloading from GitHub

Navigate to the GitHub repository where the files are hosted.
Click on the green "Code" button and then select "Download ZIP".
Extract the contents of the ZIP file to a directory of your choice.
Follow the instructions above to run the .bat and .ps1 files.