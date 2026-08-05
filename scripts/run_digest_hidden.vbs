' Hidden wrapper - runs the Vox showtimes daily digest with no console window.
' Used by the Windows Task Scheduler "VoxShowtimesDigest" task.
Set shell = CreateObject("WScript.Shell")
shell.Run "wsl.exe -d Ubuntu -u root bash /mnt/c/Users/Medo/vox-showtimes-monitor/src/vox-monitor.sh digest", 0, False