# ============================================================
# Vox Showtimes Monitor - Linux/macOS installer (cron based)
# ------------------------------------------------------------
# Usage:  bash install-cron.sh
# Adds two cron jobs:
#   */5 * * * *  vox-monitor.sh          (monitor every 5 min)
#   0 9 * * *    vox-monitor.sh digest   (daily digest at 9am)
# ============================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR="$SCRIPT_DIR/src/vox-monitor.sh"

[ -f "$SCRIPT_DIR/monitor.conf" ] || {
    echo "Missing monitor.conf - create it first:"
    echo "  cp monitor.conf.example monitor.conf"
    exit 1
}
chmod +x "$MONITOR"

# Remove any previous entries, then re-add (idempotent)
crontab -l 2>/dev/null | grep -v "vox-monitor.sh" | crontab -
{ crontab -l 2>/dev/null; echo "*/5 * * * * $MONITOR"; echo "0 9 * * * $MONITOR digest"; } | crontab -

echo "Done. Current crontab:"
crontab -l | grep vox-monitor