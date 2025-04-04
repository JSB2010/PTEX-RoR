#!/bin/bash
# Script to clean up log files

set -e

cd "$(dirname "$0")/.."
APP_ROOT=$(pwd)
LOG_DIR="$APP_ROOT/log"

echo "Cleaning up log files..."

# Clean up large log files
for log_file in "$LOG_DIR"/*.log; do
  # Skip if no log files match the pattern
  [ -e "$log_file" ] || continue

  # Get file size
  size=$(du -m "$log_file" 2>/dev/null | cut -f1) || size=0

  if [ "$size" -gt 10 ]; then
    echo "Cleaning up large log file: $log_file ($size MB)"
    cat /dev/null > "$log_file" 2>/dev/null || echo "Failed to clean $log_file"
  fi
done

# Clean up tmp directory
echo "Cleaning up tmp directory..."
find "$APP_ROOT/tmp" -type f -name "*.pid" -delete 2>/dev/null || echo "No PID files to clean"
find "$APP_ROOT/tmp" -type f -name "*.lock" -delete 2>/dev/null || echo "No lock files to clean"
find "$APP_ROOT/tmp/cache" -type f -delete 2>/dev/null || echo "No cache files to clean"

echo "Log cleanup completed!"
exit 0
