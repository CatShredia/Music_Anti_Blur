#!/usr/bin/env bash
# Admin multipart upload of a catalog source, then Hangfire transcode.
# Usage: bash devops/upload-catalog-source.sh /path/to/file.mp3
set -euo pipefail
FILE="${1:?path to audio file}"
API_BASE="${API_BASE:-http://127.0.0.1:5080}"
TRACK_ID="${TRACK_ID:-d1111111-1111-4111-8111-111111111111}"
LOGIN="${LOGIN:-admin}"
PASSWORD="${PASSWORD:-AdminPassword123}"

if [[ ! -f "$FILE" ]]; then
  echo "file not found: $FILE" >&2
  exit 1
fi

SIZE="$(wc -c < "$FILE" | tr -d ' ')"
HASH="$(sha256sum "$FILE" | awk '{print $1}')"
EXT="${FILE##*.}"
case "${EXT,,}" in
  mp3) CT="audio/mpeg" ;;
  m4a|mp4) CT="audio/mp4" ;;
  flac) CT="audio/flac" ;;
  wav) CT="audio/wav" ;;
  ogg) CT="audio/ogg" ;;
  *) CT="application/octet-stream" ;;
esac

TOKEN="$(curl -sS -X POST "$API_BASE/api/v1/auth/login" -H 'Content-Type: application/json' \
  -d "{\"identifierType\":\"login\",\"identifier\":\"$LOGIN\",\"password\":\"$PASSWORD\"}" | python -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')"
IDEM="$(python -c 'import uuid; print(uuid.uuid4())')"
NAME="$(basename "$FILE")"
INIT="$(curl -sS -X POST "$API_BASE/api/v1/admin/tracks/$TRACK_ID/uploads" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Idempotency-Key: $IDEM" \
  -d "{\"fileName\":\"$NAME\",\"sizeBytes\":$SIZE,\"contentType\":\"$CT\",\"checksumSha256\":\"$HASH\"}")"
GEN="$(python -c 'import json,sys; print(json.load(sys.stdin)["generationId"])' <<<"$INIT")"
PART_SIZE="$(python -c 'import json,sys; print(json.load(sys.stdin)["partSizeBytes"])' <<<"$INIT")"
PART_COUNT="$(python -c 'import json,sys; print(json.load(sys.stdin)["partCount"])' <<<"$INIT")"
echo "generation $GEN parts $PART_COUNT x $PART_SIZE"

PARTS_JSON="["
for n in $(seq 1 "$PART_COUNT"); do
  START=$(( (n-1) * PART_SIZE ))
  TMP="$(mktemp)"
  dd if="$FILE" of="$TMP" bs=1 skip="$START" count="$PART_SIZE" status=none
  URL="$(curl -sS -X POST "$API_BASE/api/v1/admin/tracks/$TRACK_ID/uploads/$GEN/parts" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"partNumbers\":[$n]}" | python -c 'import json,sys; print(json.load(sys.stdin)["parts"][0]["url"])')"
  ETAG="$(curl -sS -D - -o /dev/null -X PUT "$URL" --data-binary @"$TMP" | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')"
  rm -f "$TMP"
  echo "uploaded part $n etag $ETAG"
  if [[ $n -gt 1 ]]; then PARTS_JSON+=","; fi
  PARTS_JSON+="{\"partNumber\":$n,\"etag\":$ETAG}"
done
PARTS_JSON+="]"

IDEM2="$(python -c 'import uuid; print(uuid.uuid4())')"
curl -sS -X POST "$API_BASE/api/v1/admin/tracks/$TRACK_ID/uploads/$GEN/complete" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Idempotency-Key: $IDEM2" \
  -d "{\"parts\":$PARTS_JSON}" >/dev/null

for i in $(seq 1 60); do
  sleep 2
  ST="$(curl -sS "$API_BASE/api/v1/admin/tracks/$TRACK_ID/uploads/$GEN" -H "Authorization: Bearer $TOKEN")"
  STATUS="$(python -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$ST")"
  echo "status $STATUS"
  if [[ "$STATUS" == "ready" ]]; then
    curl -sS -X POST "$API_BASE/api/v1/tracks/$TRACK_ID/playback-url" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d '{"sourcePreference":"catalog","qualityPreference":"auto","localAvailable":false}'
    echo
    exit 0
  fi
  if [[ "$STATUS" == "failed" || "$STATUS" == "cancelled" ]]; then
    echo "$ST" >&2
    exit 1
  fi
done
echo "timed out waiting for transcode" >&2
exit 1
