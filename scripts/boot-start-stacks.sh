#!/bin/bash
# Run after QNAP boot to ensure all Odoo + Forgejo + Caddy stacks are up.
# Container Station's auto-restart can leave stacks in a broken state after
# a dirty reboot. This script forces a clean `compose up -d` for each stack
# and starts the standalone cloudflared container.
set +e

DOCKER=/share/CACHEDEV3_DATA/.qpkg/container-station/bin/system-docker
ROOT=/share/CACHEDEV3_DATA/Container
LOG=/share/CACHEDEV3_DATA/OdooIQ-Backups/_meta/logs/boot-recovery-$(date +%Y%m%d-%H%M%S).log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo "==================================================="
echo " boot-start-stacks.sh — $(date)"
echo " uptime: $(uptime)"
echo "==================================================="

# Wait for Container Station's docker daemon to be fully up
echo "--- waiting for docker daemon socket ---"
for i in $(seq 1 30); do
  if sudo $DOCKER ps >/dev/null 2>&1 ; then
    echo "  docker ready after ${i}0s"; break
  fi
  sleep 10
done

# Order matters: forgejo + per-site postgres first, then odoo, then caddy
STACKS="forgejo southbrook sapienzium porterly tribancs odooiq quattroporte odooai odoo"
for S in $STACKS ; do
  DIR=$ROOT/$S
  if [ -f "$DIR/docker-compose.yml" ]; then
    echo "--- $S ---"
    cd "$DIR" && sudo $DOCKER compose up -d 2>&1 | tail -3
  fi
done

# Standalone cloudflared (not in any compose)
echo "--- cloudflared ---"
sudo $DOCKER start cloudflared 2>&1 | tail -2

# Ensure caddy is on forgejo-net (the post-reboot recreation sometimes loses this)
echo "--- ensure caddy on forgejo-net ---"
if ! sudo $DOCKER inspect alfacore-caddy --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | grep -q forgejo-net; then
  sudo $DOCKER network connect forgejo-net alfacore-caddy 2>&1 | tail -2
fi

echo "--- final state ---"
sudo $DOCKER ps --format "{{.Names}}\t{{.Status}}" | grep -v "Exited" | head -25
echo "==================================================="
echo " done at $(date)"
echo "==================================================="
