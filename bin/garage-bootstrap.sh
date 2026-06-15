#!/usr/bin/env sh
set -eu

# CLI flags + runtime output verified live against dxflrs/garage:v2.3.0:
#   - `garage node id -q` prints "<hex>@<addr>" (we take the part before '@')
#   - `garage layout show` prints "Current cluster layout version: <N>"
#     (0 = unassigned; >=1 = applied) — the guard below matches >=1
GARAGE="docker compose exec -T garage /garage"
KEY_NAME="tore-dev"
BUCKET="tore-recipes"   # only bucket with a live writer (see spec Image storage policy)

: "${GARAGE_ACCESS_KEY_ID:?set GARAGE_ACCESS_KEY_ID in .env}"
: "${GARAGE_SECRET_ACCESS_KEY:?set GARAGE_SECRET_ACCESS_KEY in .env}"

# 1. Cluster layout — assign this single node if no layout version applied yet.
if ! $GARAGE layout show 2>/dev/null | grep -qE "layout version: [1-9]"; then
  NODE_ID=$($GARAGE node id -q 2>/dev/null | cut -d@ -f1)
  $GARAGE layout assign -z dc1 -c 1G "$NODE_ID"
  $GARAGE layout apply --version 1
fi

# 2. Access key — import the chosen .env creds only if our named key is absent.
if ! $GARAGE key list 2>/dev/null | grep -q "$KEY_NAME"; then
  $GARAGE key import --yes -n "$KEY_NAME" "$GARAGE_ACCESS_KEY_ID" "$GARAGE_SECRET_ACCESS_KEY"
fi

# 3. Bucket — create + grant (guarded; create is a no-op if it already exists).
$GARAGE bucket create "$BUCKET" 2>/dev/null || true
$GARAGE bucket allow --read --write "$BUCKET" --key "$KEY_NAME" 2>/dev/null || true

echo "Garage bootstrap complete."
