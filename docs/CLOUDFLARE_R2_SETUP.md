# Cloudflare R2 Cloud Backup Setup

This guide walks you through setting up free cloud backups using Cloudflare R2.

## Why Cloudflare R2?

- **Free tier:** 10GB storage (plenty for ~150MB of backups)
- **Zero egress fees:** Download your backups anytime without charges
- **S3-compatible:** Works with standard tools like rclone
- **Fast:** Cloudflare's global network ensures quick uploads/downloads

## Prerequisites

- Cloudflare account (free)
- `rclone` installed (for S3-compatible uploads)
- Terminal access to run commands

## Step 1: Create Cloudflare Account

1. Go to https://dash.cloudflare.com/sign-up
2. Create a free account with your email
3. Verify your email address

## Step 2: Enable R2 Storage

1. Log in to https://dash.cloudflare.com
2. In the left sidebar, click **R2 Object Storage**
3. Click **Purchase R2 Plan**
4. Select the **Free** plan
   - 10 GB storage
   - 1M Class A operations/month
   - 10M Class B operations/month
   - Unlimited egress
5. Add a payment method (required but won't be charged for free tier usage)
6. Confirm the plan

## Step 3: Create R2 Bucket

1. In the R2 dashboard, click **Create bucket**
2. Enter bucket name: `media-stack-backups` (or your preferred name)
3. Location: **Automatic** (Cloudflare chooses optimal location)
4. Click **Create bucket**

## Step 4: Generate R2 API Token

1. In R2 dashboard, click **Manage R2 API Tokens** (top right)
2. Click **Create API token**
3. Configure token:
   - **Token name:** `media-stack-backup-script`
   - **Permissions:**
     - ✅ Object Read & Write
     - ❌ Admin (not needed)
   - **Specify bucket(s):** Select `media-stack-backups`
   - **Client IP Address Filtering:** Leave blank (or add your home IP for extra security)
   - **TTL:** Never expire (or set expiration date)
4. Click **Create API Token**
5. **IMPORTANT:** Copy and save these values (shown only once):
   - **Access Key ID:** (looks like: `a1b2c3d4e5f6...`)
   - **Secret Access Key:** (looks like: `xyz123abc456...`)
   - **Endpoint URL:** (looks like: `https://ACCOUNT_ID.r2.cloudflarestorage.com`)

## Step 5: Install rclone

### macOS
```bash
brew install rclone
```

### Linux (Ubuntu/Debian)
```bash
sudo apt install rclone
```

### Other Platforms
Download from: https://rclone.org/downloads/

## Step 6: Configure rclone for R2

1. Run the interactive configuration:
   ```bash
   rclone config
   ```

2. Create new remote:
   ```
   n) New remote
   name> r2
   ```

3. Choose storage type:
   ```
   Storage> s3
   ```

4. Choose S3 provider:
   ```
   provider> Cloudflare
   ```

5. Enter authentication method:
   ```
   env_auth> 1 (Enter AWS credentials in the next step)
   ```

6. Enter your R2 credentials (from Step 4):
   ```
   access_key_id> [paste your Access Key ID]
   secret_access_key> [paste your Secret Access Key]
   ```

7. Region:
   ```
   region> auto
   ```

8. Endpoint (from Step 4):
   ```
   endpoint> [paste your R2 endpoint URL]
   Example: https://abc123def456.r2.cloudflarestorage.com
   ```

9. Location constraint:
   ```
   location_constraint> [press Enter to leave blank]
   ```

10. ACL:
    ```
    acl> private
    ```

11. Skip advanced config:
    ```
    Edit advanced config? n
    ```

12. Confirm configuration:
    ```
    y) Yes this is OK
    ```

13. Quit config:
    ```
    q) Quit config
    ```

## Step 7: Test rclone Connection

List your R2 buckets:
```bash
rclone lsd r2:
```

Expected output:
```
          -1 2024-10-26 23:00:00        -1 media-stack-backups
```

Test uploading a file:
```bash
echo "test" > /tmp/test.txt
rclone copy /tmp/test.txt r2:media-stack-backups/
```

Verify upload:
```bash
rclone ls r2:media-stack-backups/
```

Clean up test file:
```bash
rclone delete r2:media-stack-backups/test.txt
rm /tmp/test.txt
```

## Step 8: Update Backup Script Configuration

Add R2 configuration to your `.env` file:

```bash
# Cloudflare R2 Cloud Backup
REMOTE_BACKUP_PATH="r2:media-stack-backups"
```

## Step 9: Test Backup with Remote Sync

Run a backup with remote sync enabled:
```bash
cd /Users/brandon/projects/torrents
./backup/backup.sh --remote-sync
```

Expected output:
```
=== Media Stack Backup ===
[... backup creation ...]
Syncing to remote location...
  Remote: r2:media-stack-backups
  ✓ Synced via rclone
```

## Step 10: Verify Cloud Backup

Check files in R2:
```bash
rclone ls r2:media-stack-backups/
```

You should see your backup file:
```
  6400000 media-stack-backup_20241026_230813.tar.gz
```

Download and verify (optional):
```bash
rclone copy r2:media-stack-backups/media-stack-backup_20241026_230813.tar.gz /tmp/
tar tzf /tmp/media-stack-backup_20241026_230813.tar.gz | head -10
```

## Monthly Automated Cloud Backup

Add to crontab for monthly backups with cloud sync:

```bash
crontab -e
```

**Note:** The backup container now handles automated backups via its built-in cron.
Configure `BACKUP_SCHEDULE=0 3 * * 1` in `.env` instead of using host cron.

For reference, the old manual cron approach was:
```bash
# No longer needed - backup container handles this automatically
# 0 3 1 * * cd /Users/brandon/projects/torrents && ./backup/backup.sh --remote-sync >> logs/backup.log 2>&1
```

This runs on the 1st of each month at 3:00 AM.

## Monitoring R2 Usage

1. Go to https://dash.cloudflare.com
2. Click **R2 Object Storage**
3. Click **Usage** tab

You'll see:
- Storage used (should be ~150MB after 12 monthly backups)
- Operations count
- Egress (always $0)

**Free tier limits:**
- ✅ Storage: 10 GB (you'll use ~0.15 GB)
- ✅ Class A ops: 1M/month (you'll use ~12/month)
- ✅ Class B ops: 10M/month (minimal usage)

## Troubleshooting

### Error: "Failed to create file system for r2:"

**Cause:** rclone not configured correctly

**Solution:**
1. Run `rclone config` again
2. Delete the `r2` remote: `d) Delete remote`
3. Recreate following Step 6

### Error: "AccessDenied: Access Denied"

**Cause:** API token doesn't have correct permissions

**Solution:**
1. Go to R2 dashboard → Manage R2 API Tokens
2. Delete old token
3. Create new token with **Object Read & Write** permission
4. Update rclone config with new credentials: `rclone config`

### Error: "NoSuchBucket: The specified bucket does not exist"

**Cause:** Bucket name mismatch or doesn't exist

**Solution:**
1. Check bucket exists: `rclone lsd r2:`
2. Update `.env` with correct bucket name
3. Or create bucket: R2 dashboard → Create bucket

### Slow Upload Speed

**Cause:** Cloudflare routes to optimal location automatically

**Solution:**
- This is normal for first upload
- Subsequent uploads use Cloudflare's cache and are faster
- 6MB backup typically uploads in 5-10 seconds

## Cost Management

With the free tier:
- **Monthly backups:** 12 uploads/year = 12 Class A operations (well within 1M limit)
- **Storage:** 12 backups × 6MB = 72MB (well within 10GB limit)
- **Downloads:** Unlimited and free
- **Total cost:** $0/year ✅

## Security Best Practices

1. **Rotate API tokens annually:**
   - Create new token
   - Update rclone config
   - Delete old token

2. **Restrict by IP (optional):**
   - Edit API token in R2 dashboard
   - Add your home IP address
   - Prevents access from other locations

3. **Enable bucket lifecycle (optional):**
   - R2 dashboard → Select bucket → Settings
   - Add lifecycle rule to auto-delete backups older than 12 months
   - This prevents the bucket from filling up over time

4. **Test restores regularly:**
   ```bash
   # Download latest backup
   rclone copy r2:media-stack-backups/media-stack-backup_LATEST.tar.gz /tmp/

   # Verify extraction
   tar tzf /tmp/media-stack-backup_LATEST.tar.gz
   ```

## Additional Commands

```bash
# List all backups in R2
rclone ls r2:media-stack-backups/

# Download specific backup
rclone copy r2:media-stack-backups/media-stack-backup_20241026_230813.tar.gz ./

# Delete old backup (manual cleanup)
rclone delete r2:media-stack-backups/media-stack-backup_20240101_030000.tar.gz

# Check R2 bucket size
rclone size r2:media-stack-backups/

# Sync local backups to R2 (upload new, delete removed)
rclone sync ./backups/ r2:media-stack-backups/
```

## Next Steps

- ✅ Cloud backups configured
- ✅ Free tier (no costs)
- ✅ Automated monthly backups (optional)
- ✅ Zero egress fees for restores

For disaster recovery procedures, see: [DISASTER_RECOVERY.md](../DISASTER_RECOVERY.md)
