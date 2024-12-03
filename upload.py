#!/usr/bin/env python3
"""
TUS Resumable File Upload Script with Progress Display
"""

import sys
import os
import time
from tusclient import client

def upload_with_progress(file_path, tus_url):
    """Upload file with manual progress tracking using stop_at"""
    tus_client = client.TusClient(tus_url)

    # Create uploader
    uploader = tus_client.uploader(
        file_path,
        chunk_size=1024 * 1024  # 1 MB chunks
    )

    file_size = os.path.getsize(file_path)
    total_uploaded = 0

    print(f"File size: {file_size / (1024**3):.2f} GB")
    print("Starting upload...")
    print("-" * 50)

    start_time = time.time()

    # Upload in segments and track progress
    while total_uploaded < file_size:
        # Calculate next stopping point (show progress every 10MB or at end)
        next_stop = min(total_uploaded + (10 * 1024 * 1024), file_size)

        # Upload up to next_stop bytes
        uploader.upload(stop_at=next_stop)

        # Update progress
        total_uploaded = next_stop
        percent = (total_uploaded / file_size) * 100

        # Calculate speed
        elapsed = time.time() - start_time
        if elapsed > 0:
            speed_mb = (total_uploaded / (1024 * 1024)) / elapsed
            eta_seconds = ((file_size - total_uploaded) / (1024 * 1024)) / speed_mb if speed_mb > 0 else 0

            # Progress bar
            bar_length = 30
            filled = int(bar_length * total_uploaded // file_size)
            bar = '█' * filled + '░' * (bar_length - filled)

            print(f"\r{bar} {percent:.1f}% | {total_uploaded/(1024**2):.1f}/{file_size/(1024**2):.1f} MB | "
                  f"{speed_mb:.1f} MB/s | ETA: {eta_seconds:.0f}s", end='', flush=True)
        else:
            print(f"\rProgress: {percent:.1f}% ({total_uploaded}/{file_size} bytes)", end='', flush=True)

    print("\n" + "-" * 50)
    print("Upload complete!")

def main():
    if len(sys.argv) != 3:
        print("Usage: python tus_upload.py <file_path> <tus_api_url>")
        print("Example: python tus_upload.py ./myvideo.mp4 http://localhost:8080/files/")
        sys.exit(1)

    file_path = sys.argv[1]
    tus_url = sys.argv[2]

    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' not found.")
        sys.exit(1)

    if not tus_url.endswith('/'):
        tus_url += '/'

    print(f"Uploading: {file_path}")
    print(f"TUS Server: {tus_url}")
    print("-" * 50)

    try:
        upload_with_progress(file_path, tus_url)
        print(f"SUCCESS: File uploaded to {tus_url}")
    except ImportError:
        print("ERROR: 'tuspy' library not installed.")
        print("Please install it with: pip install tuspy")
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR: Upload failed - {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
