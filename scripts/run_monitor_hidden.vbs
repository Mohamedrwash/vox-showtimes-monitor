' Hidden wrapper - runs the Vox showtimes monitor with no console window.
' Used by the Windows Task Scheduler "VoxShowtimesMonitor" task.
Set shell = CreateObject("WScript.Shell")
shell.Run "wsl.exe -d Ubuntu -u root bash /mnt/c/Users/Medo/vox-showtimes-monitor/src/vox-monitor.sh", 0, False