# qnap/ops — cross-cutting ops for the QNAP infrastructure

This repo captures everything that doesn't fit cleanly into a single Odoo stack repo:
the shared Caddyfile, the alfacore compose (which routes ALL sites), the central
backup + recovery scripts, and the QNAP autorun hook.

## Contents

| Path | Source on QNAP | Purpose |
|---|---|---|
| `caddy/Caddyfile` | `/share/CACHEDEV3_DATA/Container/odoo/config/Caddyfile` | Reverse-proxy config for all 8 stacks (alfacore + 7 demos) + Forgejo `/git/*` routing |
| `alfacore/docker-compose.yml` | `/share/CACHEDEV3_DATA/Container/odoo/docker-compose.yml` | alfacore stack including the multi-attached caddy container (9 docker networks) |
| `scripts/backup-odoo.sh` | `/share/CACHEDEV3_DATA/Container/scripts/backup-odoo.sh` | Nightly cron 3 AM — pg_dump + filestore tar + config snapshot, 14/12/12 retention |
| `scripts/offsite-sync.sh` | `/share/CACHEDEV3_DATA/Container/scripts/offsite-sync.sh` | rsync to second QNAP — currently disabled (`exit 0` early-return); enable when secondary arrives |
| `scripts/boot-start-stacks.sh` | `/share/CACHEDEV3_DATA/Container/scripts/boot-start-stacks.sh` | Post-reboot recovery — waits for docker daemon, runs compose up -d on every stack, re-attaches caddy to forgejo-net |
| `qnap/autorun.sh` | `/etc/config/autorun.sh` | QNAP boot hook — calls boot-start-stacks.sh after a 180s delay |

## Redeploying

Each file maps 1-to-1 to its QNAP path (table above). To restore from this repo
after a fresh install:

```bash
ssh admin@192.168.68.108

# caddy + alfacore compose
sudo cp caddy/Caddyfile      /share/CACHEDEV3_DATA/Container/odoo/config/Caddyfile
sudo cp alfacore/docker-compose.yml /share/CACHEDEV3_DATA/Container/odoo/docker-compose.yml

# scripts
sudo mkdir -p /share/CACHEDEV3_DATA/Container/scripts
sudo cp scripts/*.sh /share/CACHEDEV3_DATA/Container/scripts/
sudo chmod +x /share/CACHEDEV3_DATA/Container/scripts/*.sh

# autorun (careful — this is system-wide)
sudo cp qnap/autorun.sh /etc/config/autorun.sh
sudo chmod +x /etc/config/autorun.sh

# Reload caddy + start everything
sudo /share/CACHEDEV3_DATA/.qpkg/container-station/bin/system-docker exec alfacore-caddy \
  caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

/share/CACHEDEV3_DATA/Container/scripts/boot-start-stacks.sh
```

## QNAP-specific gotchas captured here

1. **Container Station's auto-restart is unreliable after a dirty reboot.** Containers exit
   with code 255 because docker daemon has stale network IDs and port allocations from the
   crash. `boot-start-stacks.sh` exists to clean this up via `compose up -d` after a
   reset, which forces docker to use the current network state.
2. **QNAP busybox has no `numfmt`** — backup-odoo.sh avoids it and prints raw byte counts.
3. **`ls glob_with_no_match` returns non-zero** which kills scripts under `set -o pipefail`.
   backup-odoo.sh uses `find -name "*.ext" | wc -l` for counting instead.
4. **`alfacore` site dir is `/share/.../Container/odoo/` (legacy name), not `/share/.../alfacore/`.**
   backup-odoo.sh has a per-site mapping that handles this.

Snapshot date: 2026-05-26.
