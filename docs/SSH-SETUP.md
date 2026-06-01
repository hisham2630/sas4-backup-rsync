# SSH setup for SAS4 rsync backup

The hourly backup script connects from your **SAS4 server** to your **storage server** using SSH key authentication (no passwords in cron).

## Prerequisites

- Root (or deploy user) on both servers
- Storage server reachable on port `22` from SAS4
- Remote directory: `/opt/Storage/SAS4/sas4-db`

## 1. Generate key on the SAS4 server

Run on the **SAS4** machine:

```bash
ssh-keygen -t ed25519 -f /root/.ssh/sas4_backup_storage -C "sas4-rsync-backup" -N ""
chmod 600 /root/.ssh/sas4_backup_storage
chmod 644 /root/.ssh/sas4_backup_storage.pub
```

Use a passphrase only if you run backups via `ssh-agent`; unattended cron needs an empty passphrase.

## 2. Install the public key on the storage server

```bash
ssh-copy-id -i /root/.ssh/sas4_backup_storage.pub -p 22 root@YOUR_STORAGE_SERVER_IP
```

If `ssh-copy-id` is unavailable:

```bash
cat /root/.ssh/sas4_backup_storage.pub | ssh -p 22 root@YOUR_STORAGE_SERVER_IP \
  'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

## 3. Prepare remote directory

On the **storage server**:

```bash
mkdir -p /opt/Storage/SAS4/sas4-db
chmod 700 /opt/Storage/SAS4/sas4-db
```

## 4. Test connection

On the **SAS4** server:

```bash
ssh -i /root/.ssh/sas4_backup_storage -p 22 -o BatchMode=yes root@YOUR_STORAGE_SERVER_IP \
  "mkdir -p /opt/Storage/SAS4/sas4-db && echo OK"
```

You should see `OK` with no password prompt.

## 5. Point config at the key

In `/etc/sas4-backup-rsync.conf`:

```bash
SSH_IDENTITY_FILE="/root/.ssh/sas4_backup_storage"
```

## Optional: restrict key on storage server

Edit `~root/.ssh/authorized_keys` on the storage server and prefix the key line:

```
from="YOUR.SAS4.PUBLIC.IP",command="/bin/true",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA...
```

For rsync over SSH you need a normal login shell (not `command="/bin/true"`). A practical restriction is `from="SAS4_IP"` only:

```
from="203.0.113.10" ssh-ed25519 AAAA... sas4-rsync-backup
```

Remove `command=` restrictions unless you use a dedicated `rrsync` wrapper.

## Troubleshooting

| Symptom | Check |
|--------|--------|
| Permission denied (publickey) | Key path in config; `authorized_keys` permissions (600); correct user |
| Host key verification failed | First connect accepts key (`StrictHostKeyChecking=accept-new` in script) |
| Connection timed out | Firewall, `REMOTE_BACKUP_PORT`, routing to your storage host |
| Could not create directory | `mkdir -p` on storage server; disk space; SELinux/AppArmor |
