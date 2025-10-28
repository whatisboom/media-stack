# Transcoding & Disk Space Management Research

**Research Date**: 2025-10-28
**Current Setup**: Mac Mini M4, Samsung T5 (626GB media), TRaSH Guides compliant
**Goal**: Minimize disk space while maintaining torrent seeding for tracker requirements

---

## The Challenge

Current setup uses **hardlinks** (TRaSH Guides compliant), meaning files don't duplicate when moved from `/data/Downloads` to `/data/Movies` or `/data/Shows`. However, we must keep original files seeding until private tracker requirements are met, which prevents transcoding during the seeding period.

**Key Constraint**: Private trackers (TorrentDay) require seeding to maintain ratio. Transcoding changes file hash and breaks seeding.

---

## Solution Categories

### 1. Automated Transcoding Tools

#### Tdarr (Most Popular)

**Best for**: Advanced users, distributed processing, complex workflows

**Key Features**:
- Distributed processing across multiple devices (nodes/workers)
- Plugin system with extensive community library
- Can save 40-50% space (H.264 → H.265)
- GPU acceleration support (NVIDIA, AMD, Intel)
- Library-specific transcode rules
- Integration with Radarr/Sonarr via custom scripts (tdarr_inform)

**Drawbacks**:
- Steeper learning curve
- Freemium/proprietary (not fully open source)
- More complex initial setup

**Resources**:
- Docs: https://docs.tdarr.io/
- GitHub: https://github.com/HaveAGitGat/Tdarr
- Docker: `ghcr.io/haveagitgat/tdarr`

---

#### Unmanic (Simpler Alternative)

**Best for**: Beginners, straightforward transcoding needs

**Key Features**:
- Much easier setup than Tdarr
- Web UI for configuration
- Real-time file monitoring via inotify
- Custom FFmpeg commands with full control
- Pre-init scripts for FFmpeg version selection
- Scheduled scanning and automated queue processing

**Drawbacks**:
- Less advanced features than Tdarr
- Previously limited to older FFmpeg (AV1 support may be limited)
- No distributed processing

**Resources**:
- GitHub: https://github.com/Josh5/unmanic
- Docker: `josh5/unmanic`

---

#### FileFlows (Modern Alternative)

**Best for**: Visual workflow builders, modern UI, latest codecs

**Key Features**:
- Visual workflow builder (node-based)
- AV1, HEVC, H.264 support with VMAF optimization
- GPU acceleration (NVIDIA, AMD, Intel)
- Scalable to multiple nodes
- Latest version: 25.10 (Oct 2025)
- Fully open source

**Drawbacks**:
- Newer project (less mature than Tdarr)
- Smaller community/plugin ecosystem

**Resources**:
- Website: https://fileflows.com/
- Docker: Available on Docker Hub

---

### 2. Intelligent Seeding Management

#### Prunerr (Critical Companion Tool)

**Purpose**: Manages torrent deletion ONLY when disk space is low, respecting private tracker requirements

**Key Features**:
- Moves completed downloads to `/seeding/` directory
- Monitors disk space continuously
- Deletes public torrents first
- Protects private tracker items until seeding requirements met
- Maximizes tracker ratio and bonuses
- Won't delete currently imported media (detects by hardlink count)
- Configurable per-tracker seeding rules
- Bandwidth priority adjustments
- Automatic verification of corrupt files
- Blacklisting of stalled/archive downloads

**Integration**: Works with Radarr/Sonarr + download clients (qBittorrent, Transmission, Deluge via adapter)

**Perfect for**: Private tracker users needing intelligent space management

**Resources**:
- PyPI: https://pypi.org/project/prunerr/
- GitHub: https://github.com/rpatterson/prunerr

**Alternative Tools**:
- **autoremove-torrents**: Rule-based torrent removal (GitHub: jerrymakesjelly/autoremove-torrents)
- **Shrinkarr**: Size/date-based deletion (GitHub: Dan6erbond/shrinkarr)

---

### 3. Built-in Plex Solutions

#### Plex Optimize

**How it works**: Creates optimized versions alongside originals via Plex UI

**Storage Impact**: Takes additional space (less than original, but still significant)

**Limitations**:
- Deleting original also deletes optimized version
- Doubles storage temporarily during optimization
- Not ideal for seeding workflow

**Workaround**: Move optimized file to read-only location, delete original, restore

**Verdict**: Not recommended for this use case

---

## Recommended Workflow Strategy

### Two-Phase Approach (Balanced)

#### Phase 1: Seeding Protection (Prunerr)

```
Download → Radarr/Sonarr imports (hardlink) → Keep seeding until ratio met
                                                      ↓
                                              Prunerr monitors disk space
                                                      ↓
                                         Only deletes when space is low
                                         (public first, then private by priority)
```

**Benefits**:
- No transcoding complexity
- Respects tracker requirements automatically
- Maximizes seeding time when space available
- Deletes intelligently when needed

#### Phase 2: Post-Seeding Transcoding (Tdarr/Unmanic/FileFlows)

```
After seeding requirements met → Transcode to H.265/AV1 → Save 40-50% space
                                        ↓
                                 Delete original seed
                                        ↓
                           Keep transcoded in library
```

**Benefits**:
- Maximum space savings
- Maintains quality (visually lossless with proper settings)
- Automated workflow

---

## Implementation Approaches

### Option A: Conservative (Recommended to Start)

1. Install **Prunerr** only
2. Configure seeding requirements per tracker
3. Let it manage deletion intelligently
4. Monitor space savings
5. Add transcoding later if still needed

**When to use**: Current disk space manageable, want simplicity

### Option B: Aggressive (Maximum Space Savings)

1. Install **Prunerr** + **Tdarr/Unmanic/FileFlows**
2. Create separate `/data/Seeding` directory
3. Workflow:
   - Radarr/Sonarr imports → media library (hardlink)
   - Prunerr moves to `/data/Seeding` until requirements met
   - Post-seeding: Transcode with Tdarr/Unmanic
   - Delete original seeding copy
   - Keep transcoded version in library

**When to use**: Disk space critical, large library, dedicated server with GPU

---

## Mac Mini M4 Specific Considerations

### Current Hardware

**Good News**:
- Apple Silicon has excellent hardware video encoding (Video Toolbox)
- H.265/HEVC encoding is native and very efficient on M-series chips
- Docker Desktop for Mac supports ARM64 containers
- Mac handles real-time transcoding for Plex playback effortlessly

**Challenges**:
- Docker on macOS has limited GPU passthrough compared to Linux
- Hardware encoding in Docker containers may require specific configurations
- Performance will be good, but not as optimized as native Linux with GPU passthrough
- Video Toolbox access from Docker is more complex than native Linux GPU integration

### Testing Encoding Performance

Test H.265 encoding speed on Mac Mini M4:

```bash
# Test hardware encoding with Video Toolbox
ffmpeg -i /path/to/test-movie.mkv -c:v hevc_videotoolbox -b:v 5M test-output.mkv

# Compare with software encoding
ffmpeg -i /path/to/test-movie.mkv -c:v libx265 -preset medium -crf 23 test-output-sw.mkv
```

---

## Future Server Build Recommendations

When building a dedicated server, prioritize:

### CPU Options

**Intel CPU with Quick Sync Video** (Recommended)
- Excellent transcoding performance
- Widely supported in Tdarr/Plex/FFmpeg
- Power efficient for hardware encoding
- Examples: Intel i5-12500, i7-12700

**AMD CPU**
- Strong software encoding performance
- Requires discrete GPU for hardware encoding
- Better for raw compute tasks

### GPU Options

**NVIDIA GPU** (Best Overall)
- Best Docker/Tdarr support
- Most plugins and community support
- NVENC encoder widely compatible
- Examples: RTX 3060 (good value), RTX 4000 series

**Intel Quick Sync** (Most Efficient)
- Built into Intel CPU (no discrete GPU needed)
- Excellent quality/speed/power ratio
- Supported by most tools

**AMD GPU**
- Growing support for VCE/AMF
- Less mature Docker integration
- Good for specific use cases

### Operating System

**Linux** (Strongly Recommended)
- Best Docker GPU integration
- Native hardware acceleration passthrough
- Most stable for 24/7 operation
- Ubuntu 22.04/24.04 or Debian 12 recommended

---

## Estimated Space Savings

### Current Setup (Hardlinks Only)
- **Space usage**: 1x file size (626GB)
- **Seeding**: Full quality files
- **Efficiency**: Excellent (no duplication)

### With Prunerr (Intelligent Deletion)
- **Space freed**: 20-40% (depends on seeding requirements)
- **Strategy**: Removes oldest/public torrents first
- **Keeps**: Private tracker items until ratio met
- **Estimated**: 626GB → 375-500GB

### With Prunerr + Tdarr (Full Workflow)
- **Space freed**: 50-70% total
- **H.264 → H.265**: 40-50% smaller files
- **Proper encoding**: Minimal quality loss (CRF 18-22)
- **Estimated**: 626GB → 190-310GB

### Codec Comparison
- **H.264 (current)**: 100% size, universal compatibility
- **H.265/HEVC**: 40-50% smaller, excellent compatibility (2023+)
- **AV1**: 50-60% smaller, growing compatibility, slower encoding

---

## Implementation Timeline

### Phase 0: Monitoring & Metrics (Do This First)

**Before adding complexity, understand actual needs**

```bash
# Check current media size
docker exec radarr du -sh /data/Movies
docker exec sonarr du -sh /data/Shows

# Check download client seeding stats
docker exec deluge deluge-console "info"

# Create monitoring script
cat > scripts/space-report.sh << 'EOF'
#!/bin/bash
echo "=== Disk Usage Report ==="
echo "Date: $(date)"
echo ""
df -h /Volumes/Samsung_T5
echo ""
echo "=== Top 20 Largest Files ==="
docker exec deluge find /data/Downloads -type f -exec du -h {} + | sort -rh | head -20
EOF
chmod +x scripts/space-report.sh
```

**Track weekly**:
1. Total disk usage
2. Media library size growth
3. Download folder size
4. Seeding ratios per tracker

**Decision point**: Implement Phase 1 when disk usage > 80% consistently

---

### Phase 1: Prunerr Implementation (When Space Gets Tight)

**Trigger**: Disk usage consistently > 80%

**Setup Steps**:
1. Add Prunerr service to `docker-compose.yml`
2. Configure tracker-specific seeding requirements
3. Set disk space thresholds
4. Enable Radarr/Sonarr integration
5. Test with dry-run mode first

**Configuration Example**:
```yaml
# Config snippet (not full docker-compose)
prunerr:
  image: rpatterson/prunerr
  volumes:
    - ./configs/prunerr:/config
    - /Volumes/Samsung_T5:/data
  networks:
    - automation
    - download
  environment:
    - PUID=1000
    - PGID=1000
```

**Expected Results**:
- Automated deletion when space low
- Protected private tracker seeding
- 20-40% space freed

---

### Phase 2: Tdarr Integration (After Server Build)

**Trigger**: After moving to dedicated Linux server with GPU

**Why Wait**:
- Better GPU support on Linux
- Mac Mini M4 handles Plex transcoding fine (real-time)
- Batch transcoding makes more sense with larger library
- More mature tooling and plugins on Linux

**Setup Steps**:
1. Add Tdarr server and node to `docker-compose.yml`
2. Configure GPU passthrough (NVIDIA/Intel QSV)
3. Set up library paths
4. Import community plugins
5. Create transcoding flows (H.264 → H.265)
6. Configure Radarr/Sonarr notifications (tdarr_inform)
7. Test on small batch first

**Tdarr-Specific Advantages**:
- Distributed processing (Mac Mini as worker node possible)
- Extensive H.265/AV1 plugins
- Can target specific quality/size goals
- Handles HDR/DV properly
- Health check library integrity
- Integration with Radarr/Sonarr

**Expected Results**:
- 40-50% additional space savings
- Automated transcoding workflow
- Minimal quality loss

---

## Docker Integration Notes

### Network Configuration

All tools fit into existing network architecture:

```yaml
# Network placement
prunerr:
  networks:
    - automation  # For Radarr/Sonarr API access
    - download    # For Deluge management

tdarr-server:
  networks:
    - automation  # For Radarr/Sonarr integration
    - media       # For Plex library access

tdarr-node:
  networks:
    - automation  # To communicate with tdarr-server
```

### Volume Mounts

Maintain TRaSH Guides compliance:

```yaml
# All services mount parent directory
volumes:
  - /Volumes/Samsung_T5:/data

# This ensures /data/Downloads, /data/Movies, /data/Shows
# appear as same filesystem (hardlinks work)
```

### GPU Passthrough (Linux)

**NVIDIA GPU**:
```yaml
tdarr-node:
  runtime: nvidia
  environment:
    - NVIDIA_VISIBLE_DEVICES=all
```

**Intel Quick Sync**:
```yaml
tdarr-node:
  devices:
    - /dev/dri:/dev/dri
```

---

## Tool Comparison Matrix

| Feature | Tdarr | Unmanic | FileFlows | Prunerr |
|---------|-------|---------|-----------|---------|
| **Primary Purpose** | Transcode | Transcode | Transcode | Seeding Mgmt |
| **Distributed Processing** | ✅ Yes | ❌ No | ✅ Yes | N/A |
| **GPU Acceleration** | ✅ Yes | ✅ Yes | ✅ Yes | N/A |
| **Plugin System** | ✅ Extensive | ⚠️ Limited | ✅ Good | N/A |
| **Visual Workflows** | ❌ No | ❌ No | ✅ Yes | N/A |
| **Learning Curve** | High | Low | Medium | Low |
| **Servarr Integration** | ✅ Via Scripts | ❌ Manual | ⚠️ Limited | ✅ Native |
| **Disk Space Mgmt** | ❌ No | ❌ No | ❌ No | ✅ Primary |
| **Private Tracker Aware** | ❌ No | ❌ No | ❌ No | ✅ Yes |
| **Open Source** | ⚠️ Freemium | ✅ Yes | ✅ Yes | ✅ Yes |
| **Docker Support** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **Active Development** | ✅ Active | ✅ Active | ✅ Active | ✅ Active |

---

## Decision Matrix

### When to Use Prunerr

✅ **Use Prunerr when**:
- Disk usage > 80% consistently
- Manually deleting torrents becomes frequent
- Using private trackers with seeding requirements
- Want to maximize seeding time when space available
- Need intelligent, automated deletion

❌ **Don't use Prunerr when**:
- Unlimited disk space
- Only using public trackers (less critical)
- Prefer manual torrent management

---

### When to Use Tdarr

✅ **Use Tdarr when**:
- Library size > 500 movies or disk > 90%
- Have dedicated Linux server with GPU
- Need distributed processing
- Want advanced automation and plugins
- Time investment justified by space savings

❌ **Don't use Tdarr when**:
- Current space fits comfortably
- Running on Mac (limited GPU passthrough)
- Small library (< 200 items)
- Prefer simpler tools

---

### When to Use Unmanic

✅ **Use Unmanic when**:
- First time setting up transcoding
- Want simple, straightforward workflow
- Single-server setup sufficient
- Don't need complex plugins
- Prefer easier learning curve

❌ **Don't use Unmanic when**:
- Need distributed processing
- Require advanced automation
- Want extensive plugin ecosystem
- Running multiple processing nodes

---

## Tracker Seeding Requirements

### TorrentDay (Current Tracker)

**Research needed**:
- Minimum ratio requirement
- Seed time requirements
- Hit-and-run rules
- Bonus point system

**Action**: Document in tracker-specific config file for Prunerr

### Configuration Template

```yaml
# prunerr.yml (example structure)
trackers:
  torrentday:
    min_ratio: 1.0        # Update with actual requirement
    min_seed_time: 72h    # Update with actual requirement
    priority: high        # Protect from deletion
```

---

## Monitoring & Metrics

### Key Metrics to Track

1. **Disk Usage**
   - Total media library size
   - Download folder size
   - Growth rate per week

2. **Seeding Stats**
   - Active torrents count
   - Average ratio
   - Oldest seeding torrent
   - Total upload/download

3. **Transcoding Stats** (when implemented)
   - Files processed per day
   - Space saved
   - Average encoding time
   - Quality checks (VMAF scores)

### Monitoring Script

```bash
#!/bin/bash
# scripts/media-stack-report.sh

echo "=== Media Stack Report ==="
echo "Generated: $(date)"
echo ""

echo "=== Disk Usage ==="
df -h /Volumes/Samsung_T5 | tail -1
echo ""

echo "=== Media Library Sizes ==="
echo -n "Movies: "
docker exec radarr du -sh /data/Movies | cut -f1
echo -n "Shows: "
docker exec sonarr du -sh /data/Shows | cut -f1
echo -n "Downloads: "
docker exec deluge du -sh /data/Downloads | cut -f1
echo ""

echo "=== Deluge Stats ==="
docker exec gluetun deluge-console "info" 2>/dev/null | grep -E "(Total|Ratio)"
echo ""

echo "=== Largest Files in Download Folder ==="
docker exec deluge find /data/Downloads -type f -size +5G -exec du -h {} + | sort -rh | head -10
```

---

## Quality Settings Reference

### Recommended CRF Values

**H.265/HEVC Encoding**:
- CRF 18: Visually lossless (large files)
- CRF 20: Excellent quality (recommended for movies)
- CRF 22: Good quality (recommended for TV shows)
- CRF 24: Acceptable quality (maximum compression)

**AV1 Encoding**:
- CRF 24: Visually lossless
- CRF 28: Excellent quality
- CRF 32: Good quality

### TRaSH Guides Quality Profiles

Reference: https://trash-guides.info/Radarr/Radarr-Quality-Settings-File-Size/

**Already configured in current setup**:
- Proper quality profiles
- Reasonable file sizes
- No need to change unless transcoding

---

## Future Considerations

### When Storage Expands

If upgrading to larger drive (2TB+):
- Re-evaluate need for transcoding
- May prefer keeping original quality
- Use Prunerr only for cleanup
- Focus on quality over space savings

### When Building Server

Priority checklist:
- [ ] Linux OS (Ubuntu 22.04/24.04)
- [ ] Intel CPU with Quick Sync OR NVIDIA GPU
- [ ] Docker GPU passthrough tested
- [ ] Tdarr Docker setup
- [ ] GPU encoding benchmarks
- [ ] Migrate configs from Mac Mini

### Alternative: Cloud Transcoding

**Not recommended because**:
- Expensive for large libraries
- Privacy concerns (uploading media)
- Bandwidth requirements
- Ongoing costs vs one-time setup

---

## Resources & Documentation

### Official Documentation
- **Tdarr**: https://docs.tdarr.io/
- **TRaSH Guides**: https://trash-guides.info/
- **Servarr Wiki**: https://wiki.servarr.com/
- **FFmpeg Documentation**: https://ffmpeg.org/documentation.html

### Community Resources
- **Tdarr Plugins**: https://github.com/HaveAGitGat/Tdarr_Plugins
- **Tdarr Subreddit**: https://reddit.com/r/Tdarr
- **Servarr Discord**: https://discord.gg/servarr

### Docker Images
- **Tdarr**: `ghcr.io/haveagitgat/tdarr`
- **Unmanic**: `josh5/unmanic`
- **Prunerr**: `rpatterson/prunerr`
- **FileFlows**: `revenz/fileflows`

---

## Summary & Recommendations

### For Current Mac Mini M4 Setup

**✅ Keep doing**:
- Hardlinks (TRaSH Guides compliant)
- VPN-protected seeding
- Current quality profiles

**📊 Add next**:
- Monitoring script (track space trends)
- Document tracker seeding requirements
- Baseline metrics collection

**🎯 Future consideration**:
- Prunerr (when disk > 80%)
- Transcoding (after server build)

### Current Verdict

**Your setup is already well-optimized.** Add complexity only when data shows it's needed.

**Decision Timeline**:
1. **Now**: Monitor and collect metrics
2. **When 80% full**: Implement Prunerr
3. **After server build**: Add Tdarr with GPU

**Space Reality**: 626GB on Samsung T5 is manageable. Don't over-engineer until necessary.

---

## Changelog

- **2025-10-28**: Initial research and documentation
  - Evaluated Tdarr, Unmanic, FileFlows
  - Researched Prunerr for seeding management
  - Documented Mac Mini M4 considerations
  - Created implementation timeline

---

**Next Steps**: Monitor disk usage weekly, revisit when space becomes constrained or when building dedicated server.
