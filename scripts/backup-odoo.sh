#!/bin/bash
# Odoo demo + production backup script
# Runs nightly via cron (/etc/config/crontab):  0 3 * * *
# Writes to /share/CACHEDEV3_DATA/OdooIQ-Backups/
# Retention: 14 daily / 12 weekly / 12 monthly DB; 4 weekly / 4 monthly filestore
set -uo pipefail

DOCKER=/share/CACHEDEV3_DATA/.qpkg/container-station/bin/system-docker
ROOT=/share/CACHEDEV3_DATA/OdooIQ-Backups
SITES="alfacore southbrook sapienzium porterly tribancs odooiq quattroporte odooai"

TODAY=$(date +%Y%m%d)
WEEK=$(date +%Y-W%V)
MONTH=$(date +%Y-%m)
DOW=$(date +%u)
DOM=$(date +%d)
RUN_LOG=$ROOT/_meta/logs/backup-${TODAY}.log
START_TS=$(date +%s)

mkdir -p $ROOT/_meta/logs
exec > >(tee -a "$RUN_LOG") 2>&1

echo "==================================================="
echo " backup-odoo.sh — $(date)"
echo " today=$TODAY week=$WEEK month=$MONTH dow=$DOW dom=$DOM"
echo "==================================================="

MANIFEST_TMP=$(mktemp)
printf '{"run_date":"%s","host":"OdooIQ (192.168.68.108)","sites":{' "$(date -Iseconds)" > $MANIFEST_TMP
FIRST=1

for S in $SITES ; do
  echo ""
  echo "----- $S -----"
  SBASE=$ROOT/$S
  mkdir -p $SBASE/db/daily $SBASE/db/weekly $SBASE/db/monthly
  mkdir -p $SBASE/filestore/weekly $SBASE/filestore/monthly
  mkdir -p $SBASE/config/latest

  DB_SIZE=0
  DB_SHA="missing"
  FS_SIZE=0

  # 1. DAILY DB DUMP
  DAILY=$SBASE/db/daily/${S}-${TODAY}.sql.gz
  if $DOCKER ps --filter "name=^${S}-postgres$" --format "{{.Names}}" | grep -q "^${S}-postgres$" ; then
    echo "  dumping ${S}..."
    $DOCKER exec ${S}-postgres pg_dump -U odoo -d $S 2>/dev/null | gzip > $DAILY
    DB_SIZE=$(stat -c%s $DAILY 2>/dev/null || echo 0)
    DB_SHA=$(sha256sum $DAILY | cut -c1-12)
    echo "    daily: ${S}-${TODAY}.sql.gz (${DB_SIZE}B sha=${DB_SHA})"
    [ "$DOW" = "7" ] && cp $DAILY $SBASE/db/weekly/${S}-${WEEK}.sql.gz && echo "    weekly copy: ${S}-${WEEK}.sql.gz"
    [ "$DOM" = "01" ] && cp $DAILY $SBASE/db/monthly/${S}-${MONTH}.sql.gz && echo "    monthly copy: ${S}-${MONTH}.sql.gz"
  else
    echo "  SKIP: ${S}-postgres container not running"
  fi

  # 2. WEEKLY FILESTORE TAR (Sundays)
  if [ "$S" = "alfacore" ]; then FILESTORE_SRC=/share/CACHEDEV3_DATA/Container/odoo/odoo-data/filestore; else FILESTORE_SRC=/share/CACHEDEV3_DATA/Container/$S/odoo-data/filestore; fi
  if [ "$DOW" = "7" ] && [ -d $FILESTORE_SRC ] ; then
    FS_TAR=$SBASE/filestore/weekly/${S}-filestore-${TODAY}.tar.gz
    echo "  filestore tar..."
    TBASE=/share/CACHEDEV3_DATA/Container/$S; [ "$S" = "alfacore" ] && TBASE=/share/CACHEDEV3_DATA/Container/odoo; tar czf $FS_TAR -C $TBASE odoo-data/filestore 2>/dev/null || true
    FS_SIZE=$(stat -c%s $FS_TAR 2>/dev/null || echo 0)
    echo "    weekly filestore: ${S}-filestore-${TODAY}.tar.gz (${FS_SIZE}B)"
    [ "$DOM" = "01" ] && cp $FS_TAR $SBASE/filestore/monthly/${S}-filestore-${MONTH}.tar.gz && echo "    monthly filestore copy"
  fi

  # 3. CONFIG SNAPSHOT (always; secrets redacted)
  if [ "$S" = "alfacore" ]; then CFG_SRC=/share/CACHEDEV3_DATA/Container/odoo; else CFG_SRC=/share/CACHEDEV3_DATA/Container/$S; fi
  if [ -f $CFG_SRC/docker-compose.yml ] ; then
    cp $CFG_SRC/docker-compose.yml $SBASE/config/latest/docker-compose.yml
    sed -E -e 's/^(admin_passwd[[:space:]]*=).*/\1 REDACTED/' \
           -e 's/^(db_password[[:space:]]*=).*/\1 REDACTED/' \
           $CFG_SRC/config/odoo.conf > $SBASE/config/latest/odoo.conf 2>/dev/null || true
  fi

  # 4. RETENTION
  find $SBASE/db/daily       -name "${S}-20*.sql.gz" -mtime +14  -delete 2>/dev/null || true
  find $SBASE/db/weekly      -name "${S}-*-W*.sql.gz" -mtime +84  -delete 2>/dev/null || true
  find $SBASE/db/monthly     -name "${S}-*.sql.gz"   -mtime +366 -delete 2>/dev/null || true
  find $SBASE/filestore/weekly  -name "${S}-filestore-*.tar.gz" -mtime +28  -delete 2>/dev/null || true
  find $SBASE/filestore/monthly -name "${S}-filestore-*.tar.gz" -mtime +124 -delete 2>/dev/null || true

  # 5. COUNT for manifest
  CNT_DD=$(find $SBASE/db/daily        -name "*.sql.gz" 2>/dev/null | wc -l)
  CNT_DW=$(find $SBASE/db/weekly       -name "*.sql.gz" 2>/dev/null | wc -l)
  CNT_DM=$(find $SBASE/db/monthly      -name "*.sql.gz" 2>/dev/null | wc -l)
  CNT_FW=$(find $SBASE/filestore/weekly  -name "*.tar.gz" 2>/dev/null | wc -l)
  CNT_FM=$(find $SBASE/filestore/monthly -name "*.tar.gz" 2>/dev/null | wc -l)

  [ $FIRST -eq 0 ] && printf ',' >> $MANIFEST_TMP
  FIRST=0
  printf '"%s":{"db_daily":%d,"db_weekly":%d,"db_monthly":%d,"fs_weekly":%d,"fs_monthly":%d,"latest_db_bytes":%d,"latest_db_sha12":"%s","latest_fs_bytes":%d}' \
    "$S" "$CNT_DD" "$CNT_DW" "$CNT_DM" "$CNT_FW" "$CNT_FM" "$DB_SIZE" "$DB_SHA" "$FS_SIZE" \
    >> $MANIFEST_TMP
done

END_TS=$(date +%s)
DUR=$((END_TS - START_TS))
TOTAL_BYTES=$(du -sb $ROOT 2>/dev/null | cut -f1)
printf '},"total_bytes":%d,"duration_sec":%d}\n' "$TOTAL_BYTES" "$DUR" >> $MANIFEST_TMP
mv $MANIFEST_TMP $ROOT/_meta/manifest.json

echo ""
echo "==================================================="
echo " done — duration ${DUR}s  total ${TOTAL_BYTES}B"
echo "==================================================="
