#!/usr/bin/env bash
# Script to check if SolidQueue is running and restart it if needed

cd "$(dirname "$0")/.."
APP_ROOT=$(pwd)
PID_DIR="$APP_ROOT/tmp/pids"
LOG_DIR="$APP_ROOT/log"

# Function to log messages with timestamps
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_DIR/solid_queue_monitor_check.log"
}

log "Checking SolidQueue status..."

# Check if PID file exists
if [ ! -f "$PID_DIR/solid_queue_monitor.pid" ]; then
  log "PID file not found. SolidQueue may not be running."
  log "Attempting to start SolidQueue..."
  "$APP_ROOT/bin/start_solid_queue"
  exit 0
fi

# Read PID from file
PID=$(cat "$PID_DIR/solid_queue_monitor.pid")

# Check if process is running
if ! ps -p $PID > /dev/null; then
  log "SolidQueue process (PID: $PID) is not running."
  log "Attempting to start SolidQueue..."
  "$APP_ROOT/bin/start_solid_queue"
  exit 0
fi

# Check if process is responsive
# We'll check if there have been any heartbeats in the last 5 minutes
LAST_HEARTBEAT=$(find "$LOG_DIR/solid_queue_monitor.log" -mmin -5 2>/dev/null)
if [ -z "$LAST_HEARTBEAT" ]; then
  log "SolidQueue process (PID: $PID) has not updated its log in the last 5 minutes."
  log "Killing unresponsive process and restarting..."
  kill -9 $PID 2>/dev/null
  sleep 2
  "$APP_ROOT/bin/start_solid_queue"
  exit 0
fi

# Check PostgreSQL connections
PG_CONNECTIONS=$(psql -U jbarkin28 -d postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
PG_MAX_CONNECTIONS=$(psql -U jbarkin28 -d postgres -t -c "SHOW max_connections;" 2>/dev/null | tr -d ' ')

if [ -n "$PG_CONNECTIONS" ] && [ -n "$PG_MAX_CONNECTIONS" ]; then
  PERCENTAGE=$(($PG_CONNECTIONS * 100 / $PG_MAX_CONNECTIONS))
  
  if [ $PERCENTAGE -gt 80 ]; then
    log "WARNING: PostgreSQL connections are high ($PERCENTAGE%)."
    log "Cleaning up idle connections..."
    
    # Kill idle connections
    psql -U jbarkin28 -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND (now() - state_change) > interval '5 minutes';"
  fi
fi

# Check disk space
DISK_SPACE=$(df -k "$APP_ROOT" | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$DISK_SPACE" -gt 90 ]; then
  log "WARNING: Disk space is critically low (${DISK_SPACE}% used)"
  log "Cleaning up log files..."
  "$APP_ROOT/bin/clean_logs.sh"
fi

log "SolidQueue check completed. Process is running normally."
