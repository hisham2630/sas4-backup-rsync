#!/bin/bash
#
# SAS4 hourly database backup + rsync to remote storage.
# Independent of vendor /opt/sas4/scripts/backup.sh (no GDrive, no FreeRADIUS restart).
#

set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/sas4-backup-rsync.conf}"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  if [[ -n "${LOG_FILE:-}" ]]; then
    echo "$msg" >> "$LOG_FILE"
  fi
}

die() {
  log "ERROR: $*"
  exit 1
}

cleanup() {
  local rc=$?
  rm -f "${SCRIPT_LOCK_FILE:-/tmp/sas4-rsync-backup.lock}"
  if [[ $rc -ne 0 ]]; then
    log "Exited with status $rc"
  fi
}

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config: $CONFIG_FILE (see config/sas4-backup-rsync.conf.example)" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-/var/backups/sas4-rsync}"
LOCAL_RETENTION_DAYS="${LOCAL_RETENTION_DAYS:-7}"
REMOTE_RETENTION_DAYS="${REMOTE_RETENTION_DAYS:-30}"
VENDOR_LOCK_FILE="${VENDOR_LOCK_FILE:-/tmp/sas_backup.lock}"
SCRIPT_LOCK_FILE="${SCRIPT_LOCK_FILE:-/tmp/sas4-rsync-backup.lock}"
LOG_FILE="${LOG_FILE:-/var/log/sas4-backup-rsync.log}"
SAS4_CONFIG_INI="${SAS4_CONFIG_INI:-/opt/sas4/etc/config.ini}"
SAS4_VERSION_INI="${SAS4_VERSION_INI:-/opt/sas4/etc/version.ini}"
SAS4_SASCONFIG="${SAS4_SASCONFIG:-/opt/sas4/scripts/sasconfig.sh}"

: "${REMOTE_BACKUP_HOST:?REMOTE_BACKUP_HOST is required in $CONFIG_FILE}"
: "${REMOTE_BACKUP_PORT:?REMOTE_BACKUP_PORT is required in $CONFIG_FILE}"
: "${REMOTE_BACKUP_USER:?REMOTE_BACKUP_USER is required in $CONFIG_FILE}"
: "${REMOTE_BACKUP_PATH:?REMOTE_BACKUP_PATH is required in $CONFIG_FILE}"
: "${SSH_IDENTITY_FILE:?SSH_IDENTITY_FILE is required in $CONFIG_FILE}"

trap cleanup EXIT

mkdir -p "$(dirname "$LOG_FILE")" "$LOCAL_BACKUP_DIR"
touch "$LOG_FILE" 2>/dev/null || true

if [[ -e "$VENDOR_LOCK_FILE" ]]; then
  log "Vendor backup in progress ($VENDOR_LOCK_FILE); skipping this run."
  exit 0
fi

if [[ -e "$SCRIPT_LOCK_FILE" ]]; then
  log "Previous rsync backup still running ($SCRIPT_LOCK_FILE); skipping."
  exit 0
fi

touch "$SCRIPT_LOCK_FILE"

for f in "$SAS4_CONFIG_INI" "$SAS4_VERSION_INI" "$SAS4_SASCONFIG"; do
  [[ -f "$f" ]] || die "Required SAS4 file not found: $f"
done

[[ -f "$SSH_IDENTITY_FILE" ]] || die "SSH key not found: $SSH_IDENTITY_FILE"

command -v mysqldump >/dev/null 2>&1 || die "mysqldump not found in PATH"
command -v rsync >/dev/null 2>&1 || die "rsync not found in PATH"
command -v ssh >/dev/null 2>&1 || die "ssh not found in PATH"

DB_NAME=$(grep -E '^db_name=' "$SAS4_CONFIG_INI" | awk -F= '{print $2}' | tr -d '[:space:]')
DB_HOST=$(grep -E '^db_host=' "$SAS4_CONFIG_INI" | awk -F= '{print $2}' | tr -d '[:space:]')
DB_USERNAME=$(grep -E '^db_username=' "$SAS4_CONFIG_INI" | awk -F= '{print $2}' | tr -d '[:space:]')
DB_PASSWORD=$(grep -E '^db_password=' "$SAS4_CONFIG_INI" | awk -F= '{print $2}' | tr -d '[:space:]')

[[ -n "$DB_NAME" && -n "$DB_HOST" && -n "$DB_USERNAME" ]] || die "Could not read database settings from $SAS4_CONFIG_INI"

SAS_VERSION=$(grep -E '^version=' "$SAS4_VERSION_INI" 2>/dev/null | awk -F= '{print $2}' | tr -d '[:space:]')
if [[ -z "$SAS_VERSION" ]]; then
  SAS_VERSION=$(awk -F= '{print $2}' "$SAS4_VERSION_INI" | tr -d '[:space:]' | head -n1)
fi

mkdir -p "$LOCAL_BACKUP_DIR"

d=$(date +%d%m%y-%H_%M_%S)
FILENAME="sas4_v${SAS_VERSION}_.sql.${d}"
DUMP_PATH="${LOCAL_BACKUP_DIR}/${FILENAME}"
ARCHIVE_PATH="${DUMP_PATH}.gz"

BACKUP_SESSIONS=$("$SAS4_SASCONFIG" backup_sessions 2>/dev/null || true)
IGNORE_SESSIONS="--ignore-table=${DB_NAME}.radacct1 --ignore-table=${DB_NAME}.radacct"
if [[ -n "$BACKUP_SESSIONS" && "$BACKUP_SESSIONS" -eq 1 ]]; then
  IGNORE_SESSIONS=""
fi

log "Starting mysqldump for database ${DB_NAME} -> ${ARCHIVE_PATH}"
mysqldump --single-transaction=TRUE --skip-lock-tables \
  -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" \
  $IGNORE_SESSIONS "$DB_NAME" > "$DUMP_PATH"

gzip -f "$DUMP_PATH"
chmod 644 "$ARCHIVE_PATH"

SSH_OPTS=(
  -p "$REMOTE_BACKUP_PORT"
  -i "$SSH_IDENTITY_FILE"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=30
)

log "Ensuring remote directory ${REMOTE_BACKUP_PATH}"
ssh "${SSH_OPTS[@]}" "${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}" \
  "mkdir -p '${REMOTE_BACKUP_PATH}'"

RSYNC_SSH="ssh -p ${REMOTE_BACKUP_PORT} -i ${SSH_IDENTITY_FILE} -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"

log "Rsync ${ARCHIVE_PATH} -> ${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/"
rsync -avz --partial -e "$RSYNC_SSH" \
  "$ARCHIVE_PATH" \
  "${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/"

log "Pruning local backups older than ${LOCAL_RETENTION_DAYS} days in ${LOCAL_BACKUP_DIR}"
find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f -name '*.gz' -mtime "+${LOCAL_RETENTION_DAYS}" -delete

log "Pruning remote backups older than ${REMOTE_RETENTION_DAYS} days in ${REMOTE_BACKUP_PATH}"
ssh "${SSH_OPTS[@]}" "${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}" \
  "find '${REMOTE_BACKUP_PATH}' -maxdepth 1 -type f -name '*.gz' -mtime +${REMOTE_RETENTION_DAYS} -delete"

log "Backup completed: ${ARCHIVE_PATH}"
exit 0
