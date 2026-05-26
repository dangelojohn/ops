#!/bin/bash
# Off-site rsync to second QNAP. DISABLED by default.
#
# EDIT ME WHEN SECOND QNAP ARRIVES:
#   1. Set OFFSITE_HOST to the second QNAP's IP/hostname
#   2. Ensure SSH key auth admin@OFFSITE_HOST → no password prompts
#   3. Ensure /share/CACHEDEV3_DATA/OdooIQ-Backups/ exists on the second QNAP
#   4. Remove the "exit 0" line below
#   5. Optionally enable cron entry:  30 4 * * *  /share/.../scripts/offsite-sync.sh

OFFSITE_HOST="REPLACE_WITH_SECOND_QNAP_IP_OR_HOSTNAME"
OFFSITE_USER="admin"
OFFSITE_PATH="/share/CACHEDEV3_DATA/OdooIQ-Backups/"
LOCAL_PATH="/share/CACHEDEV3_DATA/OdooIQ-Backups/"

# DISABLED — remove this exit when ready
echo "offsite-sync.sh is disabled. Edit script when second QNAP arrives."
exit 0

LOG=/share/CACHEDEV3_DATA/OdooIQ-Backups/_meta/logs/offsite-$(date +%Y%m%d).log
exec > >(tee -a "$LOG") 2>&1

echo "=== offsite sync $(date) ==="
rsync -avz --delete --partial \
  -e "ssh -o StrictHostKeyChecking=accept-new" \
  "$LOCAL_PATH" \
  "${OFFSITE_USER}@${OFFSITE_HOST}:${OFFSITE_PATH}"
echo "=== done $(date) ==="
