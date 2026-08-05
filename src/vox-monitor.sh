#!/bin/bash

# ============================================================
#  Vox Showtimes Monitor - multi-film
# ------------------------------------------------------------
#  Watches ANY number of Vox Cinemas movie pages and alerts
#  when showtimes become available.
#
#  - Each film in movies.conf gets its own public ntfy topic
#      (voxwatch-<slug>) that site visitors can subscribe to.
#  - Config-driven: works for ANY movie and ANY cinema.
#  - Multi-platform notifications (all optional, most free):
#      Pushover | Telegram | Discord | Email | ntfy.sh | Gotify
#  - State tracking between runs (no duplicate alerts).
#  - Writes site/data/showtimes.json so the website stays live.
#  - Failure handling + heartbeat + optional daily digest.
#
#  Usage:
#      ./vox-monitor.sh            # run one monitoring pass
#      ./vox-monitor.sh digest     # send daily digest
#      ./vox-monitor.sh -h         # help
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${VOX_CONF:-$SCRIPT_DIR/monitor.conf}"
if [ ! -f "$CONF_FILE" ] && [ -f "$SCRIPT_DIR/../monitor.conf" ]; then
    CONF_FILE="$SCRIPT_DIR/../monitor.conf"
fi
MOVIES_FILE="${VOX_MOVIES:-$SCRIPT_DIR/movies.conf}"
if [ ! -f "$MOVIES_FILE" ] && [ -f "$SCRIPT_DIR/../movies.conf" ]; then
    MOVIES_FILE="$SCRIPT_DIR/../movies.conf"
fi

if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: Configuration not found at $CONF_FILE"
    echo "Run: cp monitor.conf.example monitor.conf  then edit it."
    exit 1
fi
if [ ! -f "$MOVIES_FILE" ]; then
    echo "ERROR: Film list not found at $MOVIES_FILE"
    echo "Run: cp movies.conf.example movies.conf  then add the films you want to watch."
    exit 1
fi

# shellcheck disable=SC1090
source "$CONF_FILE"

# State / log files live next to the script
LOG_FILE="$SCRIPT_DIR/vox_showtimes.log"
HEARTBEAT_FILE="$SCRIPT_DIR/.heartbeat"
JSON_TMP="$SCRIPT_DIR/.json_tmp"
SITE_DATA_DIR="${SITE_DATA_DIR:-$SCRIPT_DIR/../site/data}"

# ---------- helpers --------------------------------------------------

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

fetch_url() {
    local url="$1" body code
    body=$(curl -s --max-time 30 -w 'HTTP_CODE:%{http_code}' "$url")
    code=$(echo "$body" | sed -n 's/.*HTTP_CODE:\([0-9]*\)$/\1/p')
    body=$(echo "$body" | sed 's/HTTP_CODE:[0-9]*$//')
    if [ -z "$code" ] || [ "$code" != "200" ] || [ -z "$body" ]; then
        return 1
    fi
    echo "$body"
    return 0
}

# Extract available showtimes for a given cinema from a day page.
# Output per line: "TIME|FORMAT|https://.../booking/ID"
extract_available() {
    local html="$1" cinema="$2"
    echo "$html" | awk -v c="$cinema" '
        index($0, "<h3 class=\"highlight\">" c "</h3>") { incin=1; next }
        /<h3 class="highlight">/ && incin { exit }
        incin && /<strong>/ {
            line=$0; sub(/^[ \t]*/, "", line); sub(/<[^>]*>/, "", line); sub(/<[^>]*>$/, "", line)
            format=line; gsub(/[ \t]/, "", format)
        }
        incin && /<a class="action showtime"/ {
            link="";time=""
            if (match($0, /href="[^"]*"/)) link=substr($0, RSTART+6, RLENGTH-7)
            if (match($0, />[^<]*<\/a>/)) { t=substr($0, RSTART+1, RLENGTH-5); gsub(/^[ \t]+|[ \t]+$/, "", t); time=t }
            if (link!="" && time!="") print time "|" format "|" link
        }
    '
}

# ---------- notification channels -----------------------------------

send_pushover() {
    [ "${USE_PUSHOVER:-false}" != true ] && return 1
    [ -n "${PUSHOVER_USER_KEY:-}" ] && [ -n "${PUSHOVER_API_TOKEN:-}" ] || { log_message "Pushover credentials missing"; return 1; }
    local res
    res=$(curl -s --max-time 30 \
        --form-string "token=$PUSHOVER_API_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "message=$1" \
        --form-string "title=$2" \
        --form-string "priority=1" \
        --form-string "sound=pushover" \
        ${3:+--form-string "url=$3"} \
        --form-string "url_title=Book now" \
        "https://api.pushover.net/1/messages.json")
    if echo "$res" | grep -q '"status":1'; then
        log_message "Pushover sent"
        return 0
    else
        log_message "Pushover failed: $res"
        return 1
    fi
}

send_telegram() {
    [ "${USE_TELEGRAM:-false}" != true ] && return 1
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || { log_message "Telegram credentials missing"; return 1; }
    curl -s --max-time 30 \
        --data "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$1" \
        "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" > /dev/null
    log_message "Telegram sent"
    return 0
}

send_discord() {
    [ "${USE_DISCORD:-false}" != true ] && return 1
    [ -n "${DISCORD_WEBHOOK_URL:-}" ] || { log_message "Discord webhook missing"; return 1; }
    local payload
    payload=$(printf '{"content": "%s"}' "$1")
    curl -s --max-time 30 -X POST -H "Content-Type: application/json" -d "$payload" \
        "$DISCORD_WEBHOOK_URL" > /dev/null
    log_message "Discord sent"
    return 0
}

send_email() {
    [ "${USE_EMAIL:-false}" != true ] && return 1
    [ -n "${EMAIL_ADDRESS:-}" ] || { log_message "Email address missing"; return 1; }
    if command -v mail > /dev/null 2>&1; then
        echo -e "$1" | mail -s "$2" "$EMAIL_ADDRESS"
        log_message "Email sent"
        return 0
    fi
    log_message "mail binary not available - email not sent"
    return 1
}

# ntfy.sh - FREE, no account needed. The 4th arg overrides the topic:
# per-film public topics (voxwatch-<slug>) are what site visitors subscribe to.
send_ntfy() {
    [ "${USE_NTFY:-false}" != true ] && return 1
    local topic="${4:-${NTFY_TOPIC:-}}"
    [ -n "$topic" ] || { log_message "ntfy topic missing"; return 1; }
    local srv="${NTFY_SERVER:-https://ntfy.sh}"
    curl -s --max-time 30 \
        -H "Title: $2" \
        -H "Priority: ${NTFY_PRIORITY:-high}" \
        -H "Tags: ${NTFY_TAGS:-ticket}" \
        ${3:+-H "Click: $3"} \
        -d "$1" "$srv/$topic/publish" > /dev/null
    log_message "ntfy sent (topic=$topic)"
    return 0
}

send_gotify() {
    [ "${USE_GOTIFY:-false}" != true ] && return 1
    [ -n "${GOTIFY_TOKEN:-}" ] || { log_message "GOTIFY_TOKEN missing"; return 1; }
    local srv="${GOTIFY_SERVER:-http://localhost:8080}"
    curl -s --max-time 30 -X POST \
        "$srv/message?token=$GOTIFY_TOKEN" \
        -F "title=$2" \
        -F "message=$1" \
        -F "priority=${GOTIFY_PRIORITY:-5}" > /dev/null
    log_message "Gotify sent"
    return 0
}

play_local_alert() {
    echo -e "\a\a\a\a\a"
    sleep 0.5
    echo -e "\a\a\a\a\a"
}

# notify_all <message> <title> <url> [public-topic]
# Publishes to every enabled owner channel, then to the film's public
# ntfy topic (what visitors subscribe to), mirrored to the private
# NTFY_TOPIC if one is configured.
notify_all() {
    local topic="${4:-}"
    [ -z "$topic" ] && topic="${NTFY_TOPIC:-}"
    local ok=1
    send_pushover "$1" "$2" "$3" && ok=0
    send_telegram "$1" "$2"
    send_discord "$1" "$2"
    send_email "$1" "$2"
    send_gotify "$1" "$2"
    send_ntfy "$1" "$2" "$3" "$topic" && ok=0
    if [ "${USE_NTFY:-false}" = true ] && [ -n "${NTFY_TOPIC:-}" ] && [ "$topic" != "${NTFY_TOPIC:-}" ]; then
        send_ntfy "$1" "$2" "$3" ""
    fi
    [ $ok -ne 0 ] && { play_local_alert; echo -e "$1" >> "$LOG_FILE"; }
}

# ---------- film list -------------------------------------------------

SLUGS=()
NAMES=()
CINEMAS=()
URLS=()

load_movies() {
    while IFS='|' read -r slug name cinema url; do
        slug=$(echo "$slug" | tr -d ' \r')
        name=$(echo "$name" | tr -d '\r')
        cinema=$(echo "$cinema" | tr -d '\r')
        url=$(echo "$url" | tr -d ' \r')
        case "$slug" in ''|'#'*) continue ;; esac
        [ -n "$name" ] && [ -n "$cinema" ] && [ -n "$url" ] || continue
        SLUGS+=("$slug")
        NAMES+=("$name")
        CINEMAS+=("$cinema")
        URLS+=("$url")
    done < "$MOVIES_FILE"
    if [ "${#SLUGS[@]}" -eq 0 ]; then
        echo "ERROR: no films found in $MOVIES_FILE"
        echo "Format per line: slug|display-name|cinema|url"
        exit 1
    fi
}

# ---------- heartbeat -------------------------------------------------

check_heartbeat() {
    [ -f "$HEARTBEAT_FILE" ] || { echo "$(date +%s)" > "$HEARTBEAT_FILE"; return 0; }
    local last now
    last=$(cat "$HEARTBEAT_FILE")
    now=$(date +%s)
    if [ $(( now - last )) -gt "${HEARTBEAT_TIMEOUT:-900}" ]; then
        local lastrun
        lastrun=$(date -d "@$last" '+%Y-%m-%d %H:%M:%S')
        log_message "HEARTBEAT missed runs (last $lastrun)"
        notify_all "⚠️ showtime watcher missed runs!\nLast successful: $lastrun" \
            "voxwatch Monitor Alert" ""
    fi
    echo "$now" > "$HEARTBEAT_FILE"
}

# ---------- per-film check --------------------------------------------

# check_film <slug> <name> <cinema> <url>
# Runs one monitoring pass for a film and writes its JSON snippet to
# $JSON_TMP/<slug>.json on success.
check_film() {
    local slug="$1" name="$2" cinema="$3" url="$4"
    local known_file="$SCRIPT_DIR/.known_showtimes_$slug"
    local fail_flag="$SCRIPT_DIR/.fail_flag_$slug"
    local topic="voxwatch-$slug"
    local html today tomorrow day_tabs ddate label
    local current_summary current_sig first_link
    local day_html avail times_day link frm t

    log_message "$name: starting check (url=$url, cinema=$cinema)"

    html=$(fetch_url "$url")
    if [ -z "$html" ]; then
        log_message "$name: ERROR site unreachable"
        if [ ! -f "$fail_flag" ] || [ $(( $(date +%s) - $(stat -c %Y "$fail_flag" 2>/dev/null || echo 0) )) -gt 1800 ]; then
            notify_all "⚠️ Cannot reach $url\nSite may be down or blocking. Will retry." \
                "$name - Site Unreachable" "$url" "$topic"
            touch "$fail_flag"
        fi
        return 1
    fi
    rm -f "$fail_flag"

    today=$(date +%Y%m%d)
    tomorrow=$(date -d "+1 day" +%Y%m%d)

    # Discover the day tabs for THIS movie's page.
    day_tabs=$(echo "$html" | grep -o 'href="/movies/[^"]*?d&#x3D;[0-9]\{8\}#showtimes">[^<]*</a>' \
        | sed 's/.*d&#x3D;\([0-9]*\)#showtimes">\([^<]*\)<\/a>/\1|\2/')

    current_summary=""
    current_sig=""
    first_link=""

    local days_json=""
    local first_day=1

    while IFS='|' read -r ddate label; do
        [ -z "$ddate" ] && continue
        if [ "${IGNORE_TODAY_TOMORROW:-true}" = true ] && [ "$ddate" -le "$tomorrow" ]; then
            log_message "$name: ignoring $label ($ddate) today/tomorrow"
            continue
        fi

        day_html=$(fetch_url "$url?d=$ddate")
        [ -z "$day_html" ] && { log_message "$name: failed to fetch day $ddate"; continue; }

        avail=$(extract_available "$day_html" "$cinema")
        if [ -n "$avail" ]; then
            times_day=""
            while IFS= read -r l; do
                t=$(echo "$l" | cut -d'|' -f1)
                frm=$(echo "$l" | cut -d'|' -f2)
                link=$(echo "$l" | cut -d'|' -f3)
                [ -z "$first_link" ] && first_link="$link"
                current_summary="${current_summary}${label} ($ddate): ${t} [${frm}]\n"
                times_day="${times_day}$([ -n "$times_day" ] && echo ','){\"time\":\"$(json_escape "$t")\",\"format\":\"$(json_escape "$frm")\",\"booking\":\"$(json_escape "$link")\"}"
            done <<< "$avail"
            days_json="${days_json}$([ $first_day -eq 0 ] && echo ','){\"date\":\"$ddate\",\"label\":\"$(json_escape "$label")\",\"times\":[$times_day]}"
            first_day=0
            current_sig="${current_sig}%$ddate=$(echo "$avail" | cut -d'|' -f1 | sort | tr '\n' ',' | sed 's/,$//')"
            log_message "$name: day $ddate ($label): AVAILABLE"
        else
            days_json="${days_json}$([ $first_day -eq 0 ] && echo ','){\"date\":\"$ddate\",\"label\":\"$(json_escape "$label")\",\"times\":[]}"
            first_day=0
            current_summary="${current_summary}${label} ($ddate): no showtimes yet\n"
            current_sig="${current_sig}%$ddate=none"
            log_message "$name: day $ddate ($label): none"
        fi
    done <<< "$day_tabs"

    if [ -z "$current_sig" ]; then
        current_summary="No future showtimes posted yet\n"
        current_sig="none"
    fi
    current_sig="$(printf '%s' "$current_sig" | tr '\n' ' ')"
    log_message "$name: summary: $current_sig"

    if [ ! -f "$known_file" ]; then
        echo "$current_sig" > "$known_file"
        log_message "$name: initialized state"
        notify_all "🎬 Monitoring $name at $cinema (day-by-day):\n$current_summary" \
            "$name Monitor Started" "$first_link" "$topic"
    else
        local known_sig
        known_sig=$(cat "$known_file")
        if [ "$current_sig" != "$known_sig" ]; then
            log_message "$name: CHANGE detected (old: $known_sig)"
            notify_all "🎬 NEW SHOWTIME SCHEDULE - $name at $cinema\n\n$current_summary" \
                "$name Showtimes Update" "$first_link" "$topic"
            echo "$current_sig" > "$known_file"
            log_message "$name: state updated"
        else
            log_message "$name: no change"
        fi
    fi

    # Site data snippet (kept from the previous run if this check failed,
    # so a transient outage never blanks the website).
    {
        printf '{"slug":"%s","title":"%s","cinema":"%s","url":"%s","topic":"%s","watched":true,"checked_at":"%s","days":[%s]}' \
            "$slug" "$(json_escape "$name")" "$(json_escape "$cinema")" "$(json_escape "$url")" \
            "$topic" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$days_json"
    } > "$JSON_TMP/$slug.json"

    log_message "$name: check completed"
    return 0
}

# ---------- site data -------------------------------------------------

write_site_data() {
    [ "${WRITE_SITE_DATA:-true}" != true ] && return 0
    mkdir -p "$SITE_DATA_DIR" || { log_message "cannot create $SITE_DATA_DIR"; return 1; }
    local films_json="" fjson first=1 i
    for i in "${!SLUGS[@]}"; do
        fjson="$JSON_TMP/${SLUGS[$i]}.json"
        [ -f "$fjson" ] || continue
        [ $first -eq 1 ] || films_json="$films_json,"
        first=0
        films_json="$films_json$(cat "$fjson")"
    done
    {
        printf '{\n  "last_synced": "%s",\n  "films": [\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
        printf '%s\n' "$films_json" | sed 's/^{/    {/'
        printf '  ]\n}\n'
    } > "$SITE_DATA_DIR/.showtimes.tmp"
    mv "$SITE_DATA_DIR/.showtimes.tmp" "$SITE_DATA_DIR/showtimes.json"
    log_message "site data written: $SITE_DATA_DIR/showtimes.json"
}

# ---------- digest ----------------------------------------------------

run_digest() {
    [ "${ENABLE_DIGEST:-true}" != true ] && exit 0
    local today tomorrow i slug name cinema url topic digest_file d html avail times
    today=$(date +%Y%m%d)
    tomorrow=$(date -d "+1 day" +%Y%m%d)

    for i in "${!SLUGS[@]}"; do
        slug="${SLUGS[$i]}"
        name="${NAMES[$i]}"
        cinema="${CINEMAS[$i]}"
        url="${URLS[$i]}"
        topic="voxwatch-$slug"
        digest_file="$SCRIPT_DIR/.last_digest_$slug"
        [ -f "$digest_file" ] && [ "$(cat "$digest_file")" = "$today" ] && continue

        local msg=""
        for d in "$today" "$tomorrow"; do
            html=$(fetch_url "$url?d=$d")
            [ -z "$html" ] && { msg="${msg}Day $d: unreachable\n"; continue; }
            avail=$(extract_available "$html" "$cinema")
            if [ -n "$avail" ]; then
                times=$(echo "$avail" | cut -d'|' -f1 | sort | tr '\n' ',' | sed 's/,$//')
                msg="${msg}Day $d: $times\n"
            else
                msg="${msg}Day $d: none available\n"
            fi
        done

        echo "$today" > "$digest_file"
        notify_all "📅 DAILY DIGEST - $name at $cinema\n\n$msg" \
            "$name Daily Digest" "$url" "$topic"
    done
}

# ---------- main ------------------------------------------------------

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Vox Showtimes Monitor (multi-film)"
    echo "  (no args) run one monitoring pass over movies.conf"
    echo "  digest    send the daily digest for all films"
    exit 0
fi

load_movies
mkdir -p "$JSON_TMP"

[ "${1:-}" = "digest" ] && { run_digest; rm -rf "$JSON_TMP"; exit 0; }

log_message "Starting multi-film check (${#SLUGS[@]} films)"
check_heartbeat

for i in "${!SLUGS[@]}"; do
    check_film "${SLUGS[$i]}" "${NAMES[$i]}" "${CINEMAS[$i]}" "${URLS[$i]}"
done

write_site_data
rm -rf "$JSON_TMP"
log_message "Check completed"
exit 0
