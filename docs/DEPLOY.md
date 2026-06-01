# Deploy SAS4 hourly rsync backup

Deploy on the **SAS4 RADIUS server**. Vendor `/opt/sas4/scripts/backup.sh` is **not** modified.

## 1. SSH

Complete [SSH-SETUP.md](SSH-SETUP.md) before installing the script.

## 2. Install files

From this repository on the SAS4 server:

```bash
install -m 755 scripts/sas4-backup-rsync.sh /usr/local/bin/sas4-backup-rsync.sh
install -m 600 config/sas4-backup-rsync.conf.example /etc/sas4-backup-rsync.conf
```

Edit `/etc/sas4-backup-rsync.conf` if host, path, or key location differ.

```bash
mkdir -p /var/backups/sas4-rsync
chmod 700 /var/backups/sas4-rsync
touch /var/log/sas4-backup-rsync.log
chmod 600 /var/log/sas4-backup-rsync.log
```

## 3. First manual run

```bash
/usr/local/bin/sas4-backup-rsync.sh
tail -20 /var/log/sas4-backup-rsync.log
ls -lh /var/backups/sas4-rsync/
```

On the storage server:

```bash
ls -lh /opt/Storage/SAS4/sas4-db/
```

## 4. Cron (hourly)

```bash
crontab -e
```

Add:

```cron
5 * * * * /usr/local/bin/sas4-backup-rsync.sh
```

The script writes to `/var/log/sas4-backup-rsync.log` itself. To capture stderr only in cron, use:

```cron
5 * * * * /usr/local/bin/sas4-backup-rsync.sh 2>> /var/log/sas4-backup-rsync.log
```

Runs at **:05** each hour to reduce collisions with other jobs at `:00`.

## 5. Test vendor lock skip

While simulating vendor backup:

```bash
touch /tmp/sas_backup.lock
/usr/local/bin/sas4-backup-rsync.sh
echo exit: $?
rm /tmp/sas_backup.lock
```

Expected: log message about vendor backup in progress, exit code `0`.

## 6. Retention dry-run (optional)

Before relying on automatic deletion:

```bash
find /var/backups/sas4-rsync -maxdepth 1 -type f -name '*.gz' -mtime +7 -ls
ssh -i /root/.ssh/sas4_backup_storage -p 22 root@YOUR_STORAGE_SERVER_IP \
  "find /opt/Storage/SAS4/sas4-db -maxdepth 1 -type f -name '*.gz' -mtime +30 -ls"
```

Defaults: **7 days** local, **30 days** remote (see config).

## Coexistence with vendor backup

| | Vendor `backup.sh` | This script |
|--|-------------------|-------------|
| Schedule | Daily (your existing cron) | Hourly |
| GDrive | Yes (if enabled) | No |
| FreeRADIUS restart | Yes | No |
| Local path | `/mnt/backup/files/` (mounted partition) | `/var/backups/sas4-rsync/` |
| Lock | `/tmp/sas_backup.lock` | `/tmp/sas4-rsync-backup.lock` |

If both run at once, this script **skips** when `/tmp/sas_backup.lock` exists.

## Troubleshooting

| Issue | Action |
|-------|--------|
| Missing config | Copy example to `/etc/sas4-backup-rsync.conf` |
| mysqldump fails | Check `config.ini` credentials; MySQL reachable from host |
| rsync fails | Re-run SSH test; verify `REMOTE_*` in config |
| Disk full on `/var` | Lower `LOCAL_RETENTION_DAYS`; check dump sizes |
| Large logs | `logrotate` for `/var/log/sas4-backup-rsync.log` |

### Logrotate example

`/etc/logrotate.d/sas4-backup-rsync`:

```
/var/log/sas4-backup-rsync.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

## Uninstall

```bash
crontab -e   # remove the hourly line
rm -f /usr/local/bin/sas4-backup-rsync.sh /etc/sas4-backup-rsync.conf
rm -f /tmp/sas4-rsync-backup.lock
# Optionally remove local backups and SSH key
```
