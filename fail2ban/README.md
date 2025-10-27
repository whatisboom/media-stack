# Fail2ban Configuration

Fail2ban monitors service logs for authentication failures and automatically bans malicious IP addresses using iptables.

## Structure

```
fail2ban/
├── jail.local          # Jail definitions (which services to monitor)
└── filters/            # Log pattern filters for each service
    ├── radarr.conf
    ├── sonarr.conf
    ├── prowlarr.conf
    ├── overseerr.conf
    └── plex.conf
```

## Configuration

**jail.local**: Defines monitoring rules for each service
- **bantime**: How long to ban an IP (3600s = 1 hour)
- **findtime**: Time window to count failures (600s = 10 minutes)
- **maxretry**: Number of failures before ban (5)

**filters/*.conf**: Define regex patterns to match authentication failures in logs

## Deployment

The fail2ban container:
1. Runs with `network_mode: host` to access host iptables
2. Requires `NET_ADMIN` and `NET_RAW` capabilities for firewall management
3. Mounts log directories read-only from host and containers
4. Auto-loads configurations from `./configs/fail2ban` after first run

## First-Time Setup

On first run, the linuxserver fail2ban container creates default configs in `./configs/fail2ban/`.

Copy custom configurations:
```bash
# After first container start
cp ./fail2ban/jail.local ./configs/fail2ban/jail.local
cp ./fail2ban/filters/* ./configs/fail2ban/filter.d/

# Restart to apply
docker compose restart fail2ban
```

## Monitoring

Check ban status:
```bash
# View currently banned IPs
docker exec fail2ban fail2ban-client status

# View specific jail status
docker exec fail2ban fail2ban-client status radarr

# Unban an IP
docker exec fail2ban fail2ban-client set radarr unbanip <IP_ADDRESS>
```

## Notes

- Fail2ban requires host network mode to modify iptables rules
- Filters are basic patterns and may need tuning based on actual log formats
- Services must generate logs that fail2ban can monitor
- Consider adjusting `maxretry` and `bantime` based on your security needs
