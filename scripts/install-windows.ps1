# ============================================================
# Vox Showtimes Monitor - Windows installer
# ------------------------------------------------------------
# Requires: WSL with Ubuntu (any distro) already installed.
#
# Usage (as your user, in PowerShell):
#   powershell -ExecutionPolicy Bypass -File install-windows.ps1
#
# Creates two Task Scheduler tasks (run invisibly):
#   VoxShowtimesMonitor  every 5 minutes
#   VoxShowtimesDigest   daily at 09:00
#
# To stop everything:  schtasks /change /tn VoxShowtimesMonitor /disable
# ============================================================

$ErrorActionPreference = "Stop"
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbsMonitor  = Join-Path $base "run_monitor_hidden.vbs"
$vbsDigest   = Join-Path $base "run_digest_hidden.vbs"

if (-not (Test-Path $vbsMonitor)) { throw "Not found: $vbsMonitor" }
if (-not (Test-Path $vbsDigest)) { throw "Not found: $vbsDigest" }

Write-Host "Creating VoxShowtimesMonitor (every 5 min)..."
schtasks /create /tn "VoxShowtimesMonitor" `
  /tr "wscript.exe $vbsMonitor" `
  /sc MINUTE /mo 5 /f | Out-Host

Write-Host "Creating VoxShowtimesDigest (daily 09:00)..."
schtasks /create /tn "VoxShowtimesDigest" `
  /tr "wscript.exe $vbsDigest" `
  /sc DAILY /st 09:00 /f | Out-Host

Write-Host ""
Write-Host "Done. Verify with:"
Write-Host "  schtasks /query /tn VoxShowtimesMonitor /v /fo LIST"
Write-Host "  schtasks /query /tn VoxShowtimesDigest /v /fo LIST"