#!/bin/bash
# update-catalog.sh — rebuild site/data/catalog.json from the Vox homepage.
# Pairs each /movies/<slug> link with its <h3> title inside the What's On section.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_FILE="${CATALOG_FILE:-$SCRIPT_DIR/../site/data/catalog.json}"
TMP="$(mktemp)"

curl -s --max-time 40 "https://egy.voxcinemas.com" -o "$TMP"
if [ ! -s "$TMP" ]; then echo "catalog: homepage fetch failed" >&2; exit 1; fi

awk '
  /<h2 class="highlight">What[^<]*On<\/h2>/ { in_whatson = 1 }
  in_whatson && /href="\/movies\/(whatson|comingsoon)"/ { next }
  in_whatson && /href="\/movies\/([a-z0-9-]+)"/ {
    match($0, /href="\/movies\/([a-z0-9-]+)"/, m)
    links[i++] = m[1]
  }
  in_whatson && /<h3>([^<]+)<\/h3>/ {
    match($0, /<h3>([^<]+)<\/h3>/, t)
    titles[j++] = t[1]
  }
  in_whatson && /<h2 / && i > 0 { exit }
  END {
    printf "{\"updated\":\"%s\",\"films\":[\n", strftime("%Y-%m-%dT%H:%M:%S%z")
    n = (i < j) ? i : j
    for (k = 0; k < n; k++) {
      printf "{\"slug\":\"%s\",\"title\":\"%s\",\"url\":\"https://egy.voxcinemas.com/movies/%s\",\"topic\":\"voxwatch-%s\"}%s\n",
        links[k], titles[k], links[k], links[k], (k == n-1 ? "" : ",")
    }
    printf "]}\n"
  }
' "$TMP" > "${CATALOG_FILE}.tmp" || { echo "catalog: parse failed" >&2; exit 1; }

mv "${CATALOG_FILE}.tmp" "$CATALOG_FILE"
echo "catalog written: $CATALOG_FILE ($(grep -c '"slug"' "$CATALOG_FILE") films)"
rm -f "$TMP"
