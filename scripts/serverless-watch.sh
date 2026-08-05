#!/usr/bin/env bash
# serverless-watch.sh — the always-on voxwatch watcher.
# Runs on GitHub Actions (see .github/workflows/watcher.yml), NOT on your PC.
#
#   1. Reads visitor tracks from Supabase (film + chosen day)
#   2. Fetches each film's Vox page and parses showtimes per day
#   3. Publishes an ntfy alert to the film's public topic (and the private
#      mirror) the first time the chosen day has showtimes
#   4. Writes site/data/showtimes.json (+ site/data/notified.json dedupe)
#      and the workflow commits them, so the site always shows live data
#
# Env: SUPABASE_URL, SUPABASE_KEY (anon), NTFY_MIRROR (optional),
#      DEFAULT_CINEMA, NTFY_SERVER. MOCK_TRACKS (optional file) bypasses
#      Supabase for local testing.
set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL env missing}"
: "${SUPABASE_KEY:?SUPABASE_KEY env missing}"
DEFAULT_CINEMA="${DEFAULT_CINEMA:-City Centre Almaza}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_MIRROR="${NTFY_MIRROR:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_FILE="$ROOT/site/data/showtimes.json"
NOTIFIED_FILE="$ROOT/site/data/notified.json"
TMP_DIR="${TMPDIR:-/tmp}/voxwatch.$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

fetch_url() {
    local url="$1" body code
    body=$(curl -s --max-time 30 -w 'HTTP_CODE:%{http_code}' "$url")
    code=$(echo "$body" | sed -n 's/.*HTTP_CODE:\([0-9]*\)$/\1/p')
    body=$(echo "$body" | sed 's/HTTP_CODE:[0-9]*$//')
    if [ -z "$code" ] || [ "$code" != "200" ] || [ -z "$body" ]; then
        return 1
    fi
    echo "$body"
}

json_escape() { sed 's/\\/\\\\/g; s/"/\\"/g' <<< "$1"; }

# extract_available <html> <cinema> — per line: TIME|FORMAT|booking-url
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

# ---------- load tracks ----------

if [ -n "${MOCK_TRACKS:-}" ]; then
    log "using mock tracks: $MOCK_TRACKS"
    tracks_json=$(cat "$MOCK_TRACKS")
else
    tracks_json=$(curl -sf --max-time 30 \
        -H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY" \
        "$SUPABASE_URL/rest/v1/tracks?select=id,slug,title,url,cinema,day,topic,client_id&order=created_at.asc") \
        || { log "ERROR: supabase tracks fetch failed"; exit 1; }
fi

track_count=$(jq -r 'length' <<< "$tracks_json")
log "tracks: $track_count"
if [ "$track_count" -eq 0 ]; then
    log "no tracks — nothing to do (site data left as-is)"
    exit 0
fi

# ---------- fetch every unique film once ----------

films_json=""
avail_dir="$TMP_DIR/avail"
mkdir -p "$avail_dir"

while IFS= read -r film; do
    slug=$(jq -r '.slug' <<< "$film")
    title=$(jq -r '.title' <<< "$film")
    url=$(jq -r '.url' <<< "$film")
    cinema=$(jq -r '.cinema' <<< "$film")
    topic=$(jq -r '.topic' <<< "$film")
    [ -n "$cinema" ] || cinema="$DEFAULT_CINEMA"

    html=$(fetch_url "$url") || { log "$slug: unreachable — skipping"; continue; }

    day_tabs=$(echo "$html" | grep -o 'href="/movies/[^"]*?d&#x3D;[0-9]\{8\}#showtimes">[^<]*</a>' \
        | sed 's/.*d&#x3D;\([0-9]*\)#showtimes">\([^<]*\)<\/a>/\1|\2/')
    if [ -z "$day_tabs" ]; then
        log "$slug: no day tabs found"
        continue
    fi

    days_json=""
    first_day=1
    avail_tsv="$avail_dir/$slug.tsv"
    : > "$avail_tsv"

    while IFS='|' read -r ddate label; do
        [ -n "$ddate" ] || continue
        day_html=$(fetch_url "$url?d=$ddate") || { log "$slug: day $ddate fetch failed"; continue; }
        avail=$(extract_available "$day_html" "$cinema")
        if [ -n "$avail" ]; then
            times_json=""
            first_t=1
            times_list=""
            while IFS= read -r l; do
                t=$(echo "$l" | cut -d'|' -f1)
                frm=$(echo "$l" | cut -d'|' -f2)
                link=$(echo "$l" | cut -d'|' -f3)
                if [ $first_t -eq 0 ]; then times_json="${times_json},"; fi
                times_json="${times_json}{\"time\":\"$(json_escape "$t")\",\"format\":\"$(json_escape "$frm")\",\"booking\":\"$(json_escape "$link")\"}"
                first_t=0
                if [ -n "$times_list" ]; then times_list="${times_list}, "; fi
                times_list="${times_list}$t [$frm]"
            done <<< "$avail"
            if [ $first_day -eq 0 ]; then days_json="${days_json},"; fi
            days_json="${days_json}{\"date\":\"$ddate\",\"label\":\"$(json_escape "$label")\",\"times\":[$times_json]}"
            first_day=0
            echo "$ddate|$label|$times_list" >> "$avail_tsv"
            log "$slug: $ddate ($label): $times_list"
        else
            log "$slug: $ddate ($label): no showtimes"
        fi
    done <<< "$day_tabs"

    if [ -z "$days_json" ]; then
        continue
    fi
    if [ -n "$films_json" ]; then films_json="${films_json},"; fi
    films_json="${films_json}{\"slug\":\"$(json_escape "$slug")\",\"title\":\"$(json_escape "$title")\",\"cinema\":\"$(json_escape "$cinema")\",\"url\":\"$(json_escape "$url")\",\"topic\":\"$(json_escape "$topic")\",\"watched\":true,\"checked_at\":\"$(date '+%Y-%m-%dT%H:%M:%S%z')\",\"days\":[$days_json]}"
done < <(jq -c 'group_by(.slug) | map(.[0]) | .[]' <<< "$tracks_json")

if [ -z "$films_json" ]; then
    log "no film data parsed — site data left as-is"
    exit 0
fi

last_synced=$(date '+%Y-%m-%dT%H:%M:%S%z')
echo "{\"last_synced\":\"$last_synced\",\"films\":[$films_json]}" > "$DATA_FILE"
log "wrote $DATA_FILE"

# ---------- notifications (dedupe per slug|day per booking) ----------
#
# Two kinds of alert per track, each with its own dedupe key:
#   slug|day                -> public film topic (voxwatch-<slug>), once per booking
#   u:<client_id>|slug|day  -> that visitor's browser topic (voxwatch-u-<client_id>)
# A visitor only gets a browser ping for their own chosen day.
#
# The stored value is the booking signature (day + exact showtimes). A ping is
# sent only when the signature changes — i.e. when a NEW booking appears. The
# same old booking never re-pings. Keys are deleted when the day goes dark, so
# a booking that comes back (or gains new showtimes) alerts again.
# (Legacy keys store a YYYYMMDD date — treated as already sent.)

if [ ! -f "$NOTIFIED_FILE" ]; then
    echo "{}" > "$NOTIFIED_FILE"
fi
new_notified=$(cat "$NOTIFIED_FILE")
changed=0

notify() { # <msg> <title> <click-url> <topic>
    local msg="$1" title="$2" click="$3" topic="$4" code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
        -H "Title: $title" -H "Priority: high" -H "Tags: ticket" \
        -H "Click: $click" \
        -d "$msg" "$NTFY_SERVER/$topic/publish") || code=000
    if [ "$code" = "200" ]; then
        log "ntfy sent (topic=$topic)"
        return 0
    fi
    log "ntfy FAILED (topic=$topic, http=$code)"
    return 1
}

while IFS= read -r tr; do
    slug=$(jq -r '.slug' <<< "$tr")
    day=$(jq -r '.day' <<< "$tr")
    title=$(jq -r '.title' <<< "$tr")
    url=$(jq -r '.url' <<< "$tr")
    topic=$(jq -r '.topic' <<< "$tr")
    client_id=$(jq -r '.client_id // ""' <<< "$tr")
    [ -n "$topic" ] || topic="voxwatch-$slug"
    user_topic=""
    [ -n "$client_id" ] && user_topic="voxwatch-u-$client_id"
    key="$slug|${day:-any}"
    user_key="u:$client_id|$slug|${day:-any}"

    avail_tsv="$avail_dir/$slug.tsv"
    if [ ! -f "$avail_tsv" ]; then
        log "notify: $key — no parsed data, skipping"
        continue
    fi

    # chosen day matches a line? '' (any) = first available day
    if [ -n "$day" ]; then
        hit=$(grep -m 1 "^$day|" "$avail_tsv" || true)
    else
        hit=$(head -n 1 "$avail_tsv" || true)
    fi

    if [ -z "$hit" ]; then
        new_notified=$(jq --arg k "$key" 'del(.[$k])' <<< "$new_notified")
        if [ -n "$user_topic" ]; then
            new_notified=$(jq --arg k "$user_key" 'del(.[$k])' <<< "$new_notified")
        fi
        changed=1
        log "notify: $key — not available yet"
        continue
    fi

    label=$(echo "$hit" | cut -d'|' -f2)
    times=$(echo "$hit" | cut -d'|' -f3)
    msg="🎬 $title is available on $label at $times"

    # signature = booking identity (day + exact showtimes list); the day label
    # is excluded so "Tomorrow" -> "Today" label drift never re-triggers.
    sig=$(echo "$hit" | cut -d'|' -f1,3)

    already_notified() {
        local k="$1" old
        old=$(jq -r --arg k "$k" '.[$k] // ""' <<< "$new_notified")
        if [ -n "$old" ]; then
            [ "$old" = "$sig" ] && return 0
            [[ "$old" =~ ^[0-9]{8}$ ]] && return 0   # legacy per-day keys
        fi
        return 1
    }

    # public film topic: once per booking
    if already_notified "$key"; then
        log "notify: $key — same booking already notified"
    elif notify "$msg" "$title — available $label" "$url" "$topic"; then
        new_notified=$(jq --arg k "$key" --arg v "$sig" '.[$k] = $v' <<< "$new_notified")
        changed=1
        if [ -n "$NTFY_MIRROR" ]; then
            notify "$msg" "$title — available $label" "$url" "$NTFY_MIRROR" || true
        fi
    fi

    # this visitor's browser topic: once per booking
    if [ -n "$user_topic" ]; then
        if already_notified "$user_key"; then
            log "notify: $user_key — same booking already notified"
        elif notify "$msg" "$title — available $label" "$url" "$user_topic"; then
            new_notified=$(jq --arg k "$user_key" --arg v "$sig" '.[$k] = $v' <<< "$new_notified")
            changed=1
        fi
    fi
done < <(jq -c '.[]' <<< "$tracks_json")

if [ "$changed" = "1" ]; then
    echo "$new_notified" > "$NOTIFIED_FILE"
    log "wrote $NOTIFIED_FILE"
fi

log "done"
