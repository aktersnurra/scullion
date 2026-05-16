#!/usr/bin/env bash
# Usage: ./deploy/deploy.sh user@host
# Builds a release locally and ships it to the server.
set -euo pipefail

TARGET="${1:?usage: $0 user@host}"
DEPLOY_DIR=/opt/tore
APP=tore

echo "==> Building assets"
MIX_ENV=prod mix assets.deploy

echo "==> Building release"
MIX_ENV=prod mix release --overwrite

RELEASE_TAR="_build/prod/rel/${APP}/${APP}-$(grep 'version:' mix.exs | head -1 | grep -oP '[\d.]+').tar.gz"
if [[ ! -f "$RELEASE_TAR" ]]; then
  RELEASE_SRC="_build/prod/rel/${APP}"
else
  RELEASE_SRC="$RELEASE_TAR"
fi

echo "==> Uploading to ${TARGET}:${DEPLOY_DIR}"
ssh "$TARGET" "mkdir -p ${DEPLOY_DIR}"
rsync -az --delete "$RELEASE_SRC/" "${TARGET}:${DEPLOY_DIR}/"

echo "==> Running migrations"
ssh "$TARGET" "
  set -a && source /etc/tore/env && set +a
  ${DEPLOY_DIR}/bin/${APP} eval 'Tore.Release.migrate()'
"

echo "==> Restarting service"
ssh "$TARGET" "systemctl restart ${APP}"
ssh "$TARGET" "systemctl status ${APP} --no-pager"

echo "==> Done"
