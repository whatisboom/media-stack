#!/usr/bin/env python3
"""
Media Compressor Service
Automatically compresses seeded media files using HEVC (x265) to save storage space.
"""

import os
import sys
import json
import subprocess
import logging
import fcntl
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional
import requests

# Configuration from environment variables
CONFIG = {
    'downloads_dir': Path(os.getenv('DOWNLOADS_DIR', '/data/Downloads')),
    'movies_dir': Path(os.getenv('MOVIES_DIR', '/data/Movies')),
    'shows_dir': Path(os.getenv('SHOWS_DIR', '/data/Shows')),
    'crf': int(os.getenv('COMPRESSION_CRF', '23')),
    'preset': os.getenv('COMPRESSION_PRESET', 'slow'),
    'dry_run': os.getenv('DRY_RUN', 'false').lower() == 'true',
    'discord_webhook': os.getenv('DISCORD_WEBHOOK_URL', ''),
    'plex_url': os.getenv('PLEX_URL', 'http://plex:32400'),
    'plex_token': os.getenv('PLEX_CLAIM', ''),  # Optional
    'min_compression_ratio': float(os.getenv('MIN_COMPRESSION_RATIO', '0.8')),  # Only keep if <80% original size
}

# Video file extensions to process
VIDEO_EXTENSIONS = {'.mkv', '.mp4', '.avi', '.mov', '.m4v', '.wmv'}

# Setup logging (JSON format for structured logs)
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/logs/compressor.log', mode='a')
    ]
)
logger = logging.getLogger(__name__)


def send_discord_notification(message: str, is_error: bool = False):
    """Send notification to Discord webhook."""
    if not CONFIG['discord_webhook']:
        return

    try:
        payload = {
            'content': f"{'❌' if is_error else '✅'} **Media Compressor**\n{message}"
        }
        requests.post(CONFIG['discord_webhook'], json=payload, timeout=10)
    except Exception as e:
        logger.warning(f"Failed to send Discord notification: {e}")


def find_video_files(directory: Path) -> List[Path]:
    """Find all video files in a directory recursively."""
    video_files = []
    if not directory.exists():
        logger.warning(f"Directory does not exist: {directory}")
        return video_files

    for file_path in directory.rglob('*'):
        if file_path.is_file() and file_path.suffix.lower() in VIDEO_EXTENSIONS:
            video_files.append(file_path)

    return video_files


def find_matching_media_file(downloads_file: Path) -> Optional[Path]:
    """Find matching file in Movies or Shows directory by filename."""
    filename = downloads_file.name

    # Search in Movies
    for media_file in CONFIG['movies_dir'].rglob(filename):
        if media_file.is_file():
            return media_file

    # Search in Shows
    for media_file in CONFIG['shows_dir'].rglob(filename):
        if media_file.is_file():
            return media_file

    return None


def get_file_size_gb(file_path: Path) -> float:
    """Get file size in GB."""
    return file_path.stat().st_size / (1024 ** 3)


def get_video_codec(file_path: Path) -> Optional[str]:
    """Get video codec name using ffprobe."""
    try:
        result = subprocess.run(
            ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
             '-show_entries', 'stream=codec_name',
             '-of', 'default=noprint_wrappers=1:nokey=1', str(file_path)],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            return result.stdout.strip().lower()
        return None
    except Exception as e:
        logger.error(f"Failed to get codec for: {file_path} - {e}")
        return None


def get_video_duration(file_path: Path) -> Optional[float]:
    """Get video duration in seconds using ffprobe."""
    try:
        result = subprocess.run(
            ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
             '-of', 'default=noprint_wrappers=1:nokey=1', str(file_path)],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0 and result.stdout.strip():
            return float(result.stdout.strip())
        return None
    except Exception as e:
        logger.error(f"Failed to get duration for: {file_path} - {e}")
        return None


def verify_video_playable(file_path: Path) -> bool:
    """Verify video file is playable using ffprobe."""
    duration = get_video_duration(file_path)
    return duration is not None and duration > 0


def compress_video(input_path: Path, output_path: Path) -> bool:
    """
    Compress video using ffmpeg with HEVC (x265) and track progress.
    Returns True if successful, False otherwise.
    """
    # Get duration for progress tracking
    duration = get_video_duration(input_path)
    if duration:
        logger.info(f"Compressing: {input_path} (duration: {duration/60:.1f} min) -> {output_path}")
    else:
        logger.info(f"Compressing: {input_path} -> {output_path}")

    cmd = [
        'ffmpeg',
        '-i', str(input_path),
        '-c:v', 'libx265',
        '-preset', CONFIG['preset'],
        '-crf', str(CONFIG['crf']),
        '-c:a', 'copy',  # Copy audio without re-encoding
        '-c:s', 'copy',  # Copy subtitles
        '-xerror',  # Exit immediately on any error
        '-err_detect', 'aggressive',  # Detect encoding errors
        '-progress', 'pipe:2',  # Output progress to stderr
        '-y',  # Overwrite output file
        str(output_path)
    ]

    try:
        start_time = datetime.now()
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        last_progress_log = 0
        for line in process.stderr:
            # Parse ffmpeg progress output (format: "out_time_ms=123456789")
            if duration and 'out_time_ms=' in line:
                try:
                    time_ms = int(line.split('out_time_ms=')[1].strip())
                    current_time = time_ms / 1_000_000  # Convert microseconds to seconds
                    progress_pct = (current_time / duration) * 100

                    # Log progress every 10%
                    if int(progress_pct / 10) > last_progress_log:
                        last_progress_log = int(progress_pct / 10)
                        elapsed = (datetime.now() - start_time).total_seconds()
                        if progress_pct > 0:
                            eta_seconds = (elapsed / progress_pct) * (100 - progress_pct)
                            logger.info(
                                f"Progress: {progress_pct:.1f}% | "
                                f"Elapsed: {elapsed/60:.1f}m | "
                                f"ETA: {eta_seconds/60:.1f}m"
                            )
                except (ValueError, IndexError):
                    pass

        process.wait()

        if process.returncode != 0:
            stderr_output = process.stderr.read() if process.stderr else ""
            logger.error(f"FFmpeg failed: {stderr_output}")
            return False

        total_time = (datetime.now() - start_time).total_seconds()
        logger.info(f"Compression completed in {total_time/60:.1f} minutes")
        return True
    except Exception as e:
        logger.error(f"Compression error: {e}")
        return False


def process_file(downloads_file: Path) -> Dict:
    """
    Process a single file: find matching media file, compress, and replace.
    Returns statistics about the operation.
    """
    stats = {
        'file': str(downloads_file),
        'success': False,
        'original_size_gb': 0.0,
        'compressed_size_gb': 0.0,
        'space_saved_gb': 0.0,
        'error': None
    }

    # Find matching file in media directories
    media_file = find_matching_media_file(downloads_file)
    if not media_file:
        logger.info(f"No matching media file found for: {downloads_file.name}")
        stats['error'] = 'No matching media file'
        return stats

    original_size = get_file_size_gb(media_file)
    stats['original_size_gb'] = original_size

    logger.info(f"Found match: {downloads_file.name} -> {media_file}")
    logger.info(f"Original size: {original_size:.2f} GB")

    # Check if already HEVC-encoded (skip re-encoding for minimal gains)
    video_codec = get_video_codec(media_file)
    if video_codec in ('hevc', 'h265'):
        logger.info(f"Skipping already HEVC-encoded file (codec: {video_codec}): {media_file.name}")
        stats['error'] = f'Already HEVC ({video_codec})'
        return stats

    # Get original duration for verification later
    original_duration = get_video_duration(media_file)
    if not original_duration:
        logger.warning(f"Could not get duration for: {media_file}")

    # Create temporary compressed file (preserve extension for ffmpeg)
    temp_output = media_file.parent / f".{media_file.stem}.tmp{media_file.suffix}"

    if CONFIG['dry_run']:
        logger.info(f"[DRY RUN] Would compress: {media_file}")
        stats['success'] = True
        stats['compressed_size_gb'] = original_size * 0.5  # Estimate 50% compression
        stats['space_saved_gb'] = original_size * 0.5
        return stats

    # Compress video
    if not compress_video(media_file, temp_output):
        stats['error'] = 'Compression failed'
        if temp_output.exists():
            temp_output.unlink()
        return stats

    # Comprehensive verification
    # 1. Check duration matches (detect truncated files)
    compressed_duration = get_video_duration(temp_output)
    if not compressed_duration:
        logger.error(f"Compressed file has no duration: {temp_output}")
        stats['error'] = 'Compressed file has no duration'
        if temp_output.exists():
            temp_output.unlink()
        return stats

    if original_duration and abs(compressed_duration - original_duration) > 5:
        logger.error(
            f"Duration mismatch: original {original_duration:.1f}s, "
            f"compressed {compressed_duration:.1f}s"
        )
        stats['error'] = 'Duration mismatch (file truncated)'
        if temp_output.exists():
            temp_output.unlink()
        return stats

    # 2. Verify codec is HEVC
    compressed_codec = get_video_codec(temp_output)
    if compressed_codec not in ('hevc', 'h265'):
        logger.error(f"Wrong codec: expected hevc, got {compressed_codec}")
        stats['error'] = f'Wrong codec: {compressed_codec}'
        if temp_output.exists():
            temp_output.unlink()
        return stats

    # 3. Decode test - actually play a 10-second sample
    try:
        result = subprocess.run(
            ['ffmpeg', '-v', 'error', '-i', str(temp_output),
             '-t', '10', '-f', 'null', '-'],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0 or result.stderr:
            logger.error(f"Decode test failed: {result.stderr}")
            stats['error'] = 'Decode test failed'
            if temp_output.exists():
                temp_output.unlink()
            return stats
    except Exception as e:
        logger.error(f"Decode test error: {e}")
        stats['error'] = f'Decode test error: {e}'
        if temp_output.exists():
            temp_output.unlink()
        return stats

    compressed_size = get_file_size_gb(temp_output)
    stats['compressed_size_gb'] = compressed_size
    stats['space_saved_gb'] = original_size - compressed_size

    # Check if compression achieved sufficient reduction
    compression_ratio = compressed_size / original_size
    if compression_ratio > CONFIG['min_compression_ratio']:
        logger.warning(
            f"Compression ratio {compression_ratio:.2f} exceeds threshold "
            f"{CONFIG['min_compression_ratio']}. Keeping original."
        )
        temp_output.unlink()
        stats['error'] = f'Insufficient compression ({compression_ratio:.2%})'
        return stats

    logger.info(f"Compressed size: {compressed_size:.2f} GB ({compression_ratio:.1%})")
    logger.info(f"Space saved: {stats['space_saved_gb']:.2f} GB")

    # Atomically replace original with compressed version
    try:
        media_file.unlink()  # Delete original
        temp_output.rename(media_file)  # Rename temp to original name

        # Delete file from Downloads (now that media file is safely replaced)
        if downloads_file.exists():
            downloads_file.unlink()
            logger.info(f"Deleted from Downloads: {downloads_file}")

        stats['success'] = True
        logger.info(f"Successfully replaced: {media_file}")

        # Send per-file progress notification to Discord
        send_discord_notification(
            f"Compressed: **{media_file.name}**\n"
            f"Original: {original_size:.2f} GB → Compressed: {compressed_size:.2f} GB\n"
            f"Space saved: **{stats['space_saved_gb']:.2f} GB** ({compression_ratio:.1%})"
        )

    except Exception as e:
        logger.error(f"Failed to replace file: {e}")
        stats['error'] = f'Failed to replace: {e}'
        if temp_output.exists():
            temp_output.unlink()
        return stats

    return stats


def trigger_plex_scan():
    """Trigger Plex library scan (best effort)."""
    if not CONFIG['plex_token']:
        logger.info("No Plex token configured, skipping library scan")
        return

    try:
        url = f"{CONFIG['plex_url']}/library/sections/all/refresh"
        headers = {'X-Plex-Token': CONFIG['plex_token']}
        response = requests.get(url, headers=headers, timeout=10)

        if response.status_code == 200:
            logger.info("Triggered Plex library scan")
        else:
            logger.warning(f"Failed to trigger Plex scan: {response.status_code}")
    except Exception as e:
        logger.warning(f"Failed to trigger Plex scan: {e}")


def main():
    """Main compression workflow."""
    # Acquire lock to prevent concurrent runs
    lock_file = Path('/tmp/compressor.lock')
    lock_fd = None

    try:
        lock_fd = open(lock_file, 'w')
        fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock_fd.write(f"{os.getpid()}\n{datetime.now().isoformat()}\n")
        lock_fd.flush()
    except IOError:
        logger.warning("Another compression process is already running. Exiting.")
        sys.exit(0)

    try:
        start_time = datetime.now()
        logger.info("=" * 60)
        logger.info(f"Media Compressor started at {start_time}")
        logger.info(f"Configuration: CRF={CONFIG['crf']}, Preset={CONFIG['preset']}, DryRun={CONFIG['dry_run']}")
        logger.info("=" * 60)

        # Find all video files in Downloads
        downloads_videos = find_video_files(CONFIG['downloads_dir'])
        logger.info(f"Found {len(downloads_videos)} video files in Downloads")

        if not downloads_videos:
            logger.info("No videos to process")
            send_discord_notification("No videos found in Downloads directory")
            return

        # Process each file
        results = []
        total_space_saved = 0.0
        successful_compressions = 0

        for video_file in downloads_videos:
            logger.info(f"\nProcessing: {video_file.name}")
            stats = process_file(video_file)
            results.append(stats)

            if stats['success']:
                successful_compressions += 1
                total_space_saved += stats['space_saved_gb']

        # Summary
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds() / 60

        logger.info("=" * 60)
        logger.info("Compression Summary")
        logger.info("=" * 60)
        logger.info(f"Total files processed: {len(results)}")
        logger.info(f"Successful compressions: {successful_compressions}")
        logger.info(f"Total space saved: {total_space_saved:.2f} GB")
        logger.info(f"Duration: {duration:.1f} minutes")

        # Discord notification
        if successful_compressions > 0:
            dry_run_prefix = "🔍 [DRY RUN] " if CONFIG['dry_run'] else ""
            message = (
                f"{dry_run_prefix}Compressed {successful_compressions}/{len(results)} video files\n"
                f"Space saved: **{total_space_saved:.2f} GB**\n"
                f"Duration: {duration:.1f} min"
            )
            send_discord_notification(message)

            # Trigger Plex scan
            trigger_plex_scan()

        # Log detailed results
        logger.info("\nDetailed Results:")
        for result in results:
            logger.info(json.dumps(result))

        logger.info("=" * 60)
        logger.info("Media Compressor finished")
        logger.info("=" * 60)

    finally:
        # Release lock
        if lock_fd:
            try:
                fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
                lock_fd.close()
                lock_file.unlink()
            except Exception as e:
                logger.warning(f"Failed to release lock: {e}")


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        send_discord_notification(f"Fatal error: {e}", is_error=True)
        sys.exit(1)
