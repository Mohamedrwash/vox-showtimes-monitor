#!/bin/bash

# ============================================================
#  Vox Showtimes Monitor - multi-film + visitor picks
# ------------------------------------------------------------
#  Watches ANY number of Vox Cinemas movie pages and alerts
#  when showtimes become available.
#
#  - Each film in movies.conf gets its own public ntfy topic
#      (voxwatch-<slug>) that site visitors can subscribe to.
#  - Visitor picks: site publishes PICK/UNPICK to a control
#      topic; monitor polls it and dynamically adds/removes
#      films to the watchlist.
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
CONTROL_LAST_ID_FILE="$SCRIPT_DIR/.control_last_id"
PICKED_FILE="$SCRIPT_DIR/.picked_slugs"
JSON_TMP="$SCRIPT_DIR/.json_tmp.$$"
SITE_DATA_DIR="${SITE_DATA_DIR:-$SCRIPT_DIR/../site/data}"
CATALOG_FILE="${SITE_DATA_DIR}/catalog.json"

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

# ---------- control topic (visitor picks) -----------------------------

# poll_control_topic
# Fetches messages from the ntfy control topic since the last seen
# message (time-based cursor, ntfy v2 message ids are not sortable).
# Updates CONTROL_LAST_ID_FILE ("<time> <id>") and prints commands:
#   PICK slug
#   UNPICK slug
poll_control_topic() {
    [ "${USE_NTFY:-false}" != true ] && return 0
    [ -n "${CONTROL_TOPIC:-}" ] || return 0
    [ -n "${NTFY_SERVER:-}" ] || return 0

    local since=0 cur_id=""
    if [ -f "$CONTROL_LAST_ID_FILE" ]; then
        read -r since cur_id < "$CONTROL_LAST_ID_FILE" 2>/dev/null
        [[ "$since" =~ ^[0-9]+$ ]] || since=0
    fi

    # poll=1 makes ntfy return the replay and close the stream.
    # since=<time> is inclusive, so the cursor message is re-delivered
    # and must be skipped by id.
    local url="${NTFY_SERVER}/${CONTROL_TOPIC}/json?poll=1&since=${since}"

    local resp
    resp=$(curl -s --max-time 20 "$url")
    [ -z "$resp" ] && return 0

    # Parse JSON: each message has "id" (string), "time" (unix seconds),
    # "message" (body). Expected body: "PICK slug" or "UNPICK slug".
    echo "$resp" | awk -v since="$since" -v cur_id="$cur_id" '
        BEGIN { RS="}"; max_time=since; max_id=cur_id }
        {
            id=""; t=""
            if (match($0, /"id":"([^"]+)"/, m)) id=m[1]
            if (match($0, /"time":([0-9]+)/, m)) t=m[1]
            if (t != "" && (t > max_time || (t == max_time && id != max_id))) {
                max_time=t; max_id=id
            }
        }
        /"message":/ {
            if (t == "" || id == "") next
            if (t < since || (t == since && id == cur_id)) next
            msg=$0
            gsub(/.*"message":"/, "", msg)
            gsub(/".*/, "", msg)
            if (msg ~ /^PICK /) {
                slug=substr(msg, 6)
                gsub(/[ \t\r\n]/, "", slug)
                if (slug != "") print "PICK " slug
            }
            else if (msg ~ /^UNPICK /) {
                slug=substr(msg, 8)
                gsub(/[ \t\r\n]/, "", slug)
                if (slug != "") print "UNPICK " slug
            }
        }
        END { if (max_time > since || (max_time == since && max_id != cur_id)) print "LAST " max_time " " max_id }
    ' | while IFS= read -r line; do
        case "$line" in
            PICK\ *) echo "PICK ${line#PICK }" ;;
            UNPICK\ *) echo "UNPICK ${line#UNPICK }" ;;
            LAST\ *) echo "${line#LAST }" > "$CONTROL_LAST_ID_FILE" ;;
        esac
    done
}

# get_catalog_info <slug>
# Reads catalog.json and prints "title|url" for a slug, or empty if not found.
get_catalog_info() {
    local slug="$1"
    [ -f "$CATALOG_FILE" ] || return 1
    awk -v s="$slug" '
        BEGIN { RS="}"; FS="\n" }
        /"slug":/ && index($0, s) {
            title=""
            url=""
            for (i=1; i<=NF; i++) {
                f=$i
                if (f ~ /"title":/) {
                    gsub(/.*"title":"/, "", f)
                    gsub(/".*/, "", f)
                    title=f
                }
                g=$i
                if (g ~ /"url":/) {
                    gsub(/.*"url":"/, "", g)
                    gsub(/".*/, "", g)
                    url=g
                }
            }
            if (title != "" && url != "") {
                print title "|" url
            }
            exit
        }
    ' "$CATALOG_FILE"
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
    local msg ok=1
    msg=$(echo -e "$1")
    send_pushover "$msg" "$2" "$3" && ok=0
    send_telegram "$msg" "$2"
    send_discord "$msg" "$2"
    send_email "$msg" "$2"
    send_gotify "$msg" "$2"
    send_ntfy "$msg" "$2" "$3" "$topic" && ok=0
    if [ "${USE_NTFY:-false}" = true ] && [ -n "${NTFY_TOPIC:-}" ] && [ "$topic" != "${NTFY_TOPIC:-}" ]; then
        send_ntfy "$msg" "$2" "$3" ""
    fi
    [ $ok -ne 0 ] && { play_local_alert; echo -e "$1" >> "$LOG_FILE"; }
}

# ---------- film list -------------------------------------------------

SLUGS=()
NAMES=()
CINEMAS=()
URLS=()
PICKED_SLUGS=()
PICKED_NAMES=()
PICKED_CINEMAS=()
PICKED_URLS=()

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

# load_picked / save_picked
# Persist the visitor-picked watchlist so picks survive across runs
# (the control-topic cursor only carries NEW messages).
load_picked() {
    [ -f "$PICKED_FILE" ] || return 0
    while IFS='|' read -r slug name cinema url; do
        slug=$(echo "$slug" | tr -d ' \r')
        name=$(echo "$name" | tr -d '\r')
        cinema=$(echo "$cinema" | tr -d '\r')
        url=$(echo "$url" | tr -d ' \r')
        case "$slug" in ''|'#'*) continue ;; esac
        PICKED_SLUGS+=("$slug")
        PICKED_NAMES+=("$name")
        PICKED_CINEMAS+=("$cinema")
        PICKED_URLS+=("$url")
    done < "$PICKED_FILE"
}

save_picked() {
    local tmp="$PICKED_FILE.tmp"
    : > "$tmp"
    for i in "${!PICKED_SLUGS[@]}"; do
        echo "${PICKED_SLUGS[$i]}|${PICKED_NAMES[$i]}|${PICKED_CINEMAS[$i]}|${PICKED_URLS[$i]}" >> "$tmp"
    done
    mv "$tmp" "$PICKED_FILE"
}

# process_control_topic
# Polls the control topic, updates PICKED_* arrays based on PICK/UNPICK.
process_control_topic() {
    while IFS=' ' read -r cmd slug; do
        case "$cmd" in
            PICK)
                if [ -z "$slug" ]; then continue; fi
                # Skip if already in movies.conf
                local found=0
                for s in "${SLUGS[@]}"; do [ "$s" = "$slug" ] && found=1; done
                for s in "${PICKED_SLUGS[@]}"; do [ "$s" = "$slug" ] && found=1; done
                [ $found -eq 1 ] && { log_message "PICK $slug: already in watchlist"; continue; }

                # Look up title/url from catalog
                local info
                info=$(get_catalog_info "$slug")
                if [ -z "$info" ]; then
                    log_message "PICK $slug: not in catalog.json"
                    continue
                fi
                local name cinema
                name=$(echo "$info" | cut -d'|' -f1)
                local url
                url=$(echo "$info" | cut -d'|' -f2)
                cinema="${DEFAULT_CINEMA:-City Centre Almaza}"

                PICKED_SLUGS+=("$slug")
                PICKED_NAMES+=("$name")
                PICKED_CINEMAS+=("$cinema")
                PICKED_URLS+=("$url")
                log_message "PICK $slug: added to watchlist ($name @ $cinema)"
                ;;
            UNPICK)
                if [ -z "$slug" ]; then continue; fi
                local idx=-1
                for i in "${!PICKED_SLUGS[@]}"; do
                    if [ "${PICKED_SLUGS[$i]}" = "$slug" ]; then
                        idx=$i
                        break
                    fi
                done
                [ $idx -eq -1 ] && { log_message "UNPICK $slug: not in picked list"; continue; }
                unset PICKED_SLUGS[$idx]
                unset PICKED_NAMES[$idx]
                unset PICKED_CINEMAS[$idx]
                unset PICKED_URLS[$idx]
                log_message "UNPICK $slug: removed from watchlist"
                ;;
        esac
    done < <(poll_control_topic)

    # Compact arrays (remove gaps from unset)
    PICKED_SLUGS=("${PICKED_SLUGS[@]}")
    PICKED_NAMES=("${PICKED_NAMES[@]}")
    PICKED_CINEMAS=("${PICKED_CINEMAS[@]}")
    PICKED_URLS=("${PICKED_URLS[@]}")
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
    # Also include picked films
    for i in "${!PICKED_SLUGS[@]}"; do
        fjson="$JSON_TMP/${PICKED_SLUGS[$i]}.json"
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

    # Also digest for picked films
    for i in "${!PICKED_SLUGS[@]}"; do
        slug="${PICKED_SLUGS[$i]}"
        name="${PICKED_NAMES[$i]}"
        cinema="${PICKED_CINEMAS[$i]}"
        url="${PICKED_URLS[$i]}"
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
    echo "Vox Showtimes Monitor (multi-film + visitor picks)"
    echo "  (no args) run one monitoring pass over movies.conf + picks"
    echo "  digest    send the daily digest for all films"
    exit 0
fi

# Single-instance guard: skip if another run is in progress.
exec 9>"/tmp/voxmonitor.$(id -u).lock"
flock -n 9 || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] another instance running; skipping"; exit 0; }

load_movies
load_picked
process_control_topic
save_picked
mkdir -p "$JSON_TMP"

[ "${1:-}" = "digest" ] && { run_digest; rm -rf "$JSON_TMP"; exit 0; }

log_message "Starting multi-film check (${#SLUGS[@]} films + ${#PICKED_SLUGS[@]} picked)"
check_heartbeat

for i in "${!SLUGS[@]}"; do
    check_film "${SLUGS[$i]}" "${NAMES[$i]}" "${CINEMAS[$i]}" "${URLS[$i]}"
done

for i in "${!PICKED_SLUGS[@]}"; do
    check_film "${PICKED_SLUGS[$i]}" "${PICKED_NAMES[$i]}" "${PICKED_CINEMAS[$i]}" "${PICKED_URLS[$i]}"
done

write_site_data
rm -rf "$JSON_TMP"
log_message "Check completed"
exit 0
