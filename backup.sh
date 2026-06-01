#!/bin/bash

export DB_NAME=`cat /opt/sas4/etc/config.ini | grep db_name | awk -F= '{print $2}'`
export DB_HOST=`cat /opt/sas4/etc/config.ini | grep db_host | awk -F= '{print $2}'`
export DB_USERNAME=`cat /opt/sas4/etc/config.ini | grep db_username | awk -F= '{print $2}'`
export DB_PASSWORD=`cat /opt/sas4/etc/config.ini | grep db_password | awk -F= '{print $2}'`

if [ -e "/tmp/sas_backup.lock" ]; then
exit 1
fi
PARTITION=`/opt/sas4/scripts/sasconfig.sh backup_partition`
mkdir -p /mnt/backup
sudo mount -U $PARTITION /mnt/backup
mkdir -p /mnt/backup/files
d=`date +%d%m%y-%H_%M_%S`
export SAS_VERSION=`cat /opt/sas4/etc/version.ini | awk -F= '{print $2}'`
export FILENAME="sas4_v$SAS_VERSION""_.sql.$d"

touch /tmp/sas_backup.lock
BACKUP_SESSIONS=`/opt/sas4/scripts/sasconfig.sh backup_sessions`
IGNORE_SESSIONS="--ignore-table=$DB_NAME.radacct1 --ignore-table=$DB_NAME.radacct"
if [ -n "$BACKUP_SESSIONS" ] && [ "$BACKUP_SESSIONS" -eq "1" ]; then
 IGNORE_SESSIONS=""
fi
mysqldump --single-transaction=TRUE --skip-lock-tables -h $DB_HOST -u $DB_USERNAME -p$DB_PASSWORD $IGNORE_SESSIONS $DB_NAME >> /mnt/backup/files/$FILENAME
echo "mysqldump --single-transaction=TRUE --skip-lock-tables -h $DB_HOST -u $DB_USERNAME -p$DB_PASSWORD $IGNORE_SESSIONS $DB_NAME >> /mnt/backup/files/$FILENAME"
gzip "/mnt/backup/files/$FILENAME"
chmod 666 "/mnt/backup/files/$FILENAME.gz"
USE_GDRIVE=`/opt/sas4/scripts/sasconfig.sh backup_upload_gdrive`
if [ -n "$USE_GDRIVE" ] && [ "$USE_GDRIVE" -eq "1" ]; then
 echo "uploading to google drive"
 /opt/sas4/bin/rclone --config=/opt/sas4/site/admin/backend/storage/app/rclone.conf copy /mnt/backup/files/$FILENAME.gz gdrive:
fi

sudo umount /mnt/backup
rm /tmp/sas_backup.lock
systemctl restart freeradius

exit 0
