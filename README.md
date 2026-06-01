# SAS4 hourly rsync backup

Independent hourly MySQL backup for Snono SAS4 RADIUS systems: local `mysqldump`, rsync to a remote storage server, retention pruning. Does not modify vendor `/opt/sas4/scripts/backup.sh`.

## Quick start

1. [SSH setup](docs/SSH-SETUP.md)
2. [Deploy on SAS4 server](docs/DEPLOY.md)

## Layout

- `scripts/sas4-backup-rsync.sh` — main script (install to `/usr/local/bin/`)
- `config/sas4-backup-rsync.conf.example` — copy to `/etc/sas4-backup-rsync.conf`
- `backup.sh` — vendor reference only (do not deploy over `/opt/sas4/scripts/backup.sh`)
