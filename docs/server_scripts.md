# Server Scripts

This document provides an overview of the server scripts in the application.

## Overview

The application includes several scripts for starting the Rails server with different options:

- `bin/rails server`: The standard Rails server command (without SolidQueue)
- `bin/rails-server-with-solid-queue`: A script that starts the Rails server with SolidQueue

## Scripts

### `bin/rails server`

The standard Rails server command. This command has been modified to use the `bin/rails-server-original` script, which starts the Rails server without SolidQueue.

```bash
bin/rails server
```

### `bin/rails-server-with-solid-queue`

A script that starts the Rails server with SolidQueue. This script starts PostgreSQL, Redis, and SolidQueue, and then starts the Rails server.

```bash
bin/rails-server-with-solid-queue
```

## Environment Variables

- `SKIP_SOLID_QUEUE`: Set to `true` to skip starting SolidQueue

## Troubleshooting

### PostgreSQL Connection Issues

If you're experiencing PostgreSQL connection issues:

1. Check if PostgreSQL is running:
   ```bash
   pg_isready
   ```

2. Start PostgreSQL if it's not running:
   ```bash
   brew services start postgresql@14
   ```

3. Check for too many connections:
   ```bash
   psql -U jbarkin28 -d postgres -c "SELECT count(*) FROM pg_stat_activity;"
   ```

4. Kill idle connections:
   ```bash
   psql -U jbarkin28 -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND (now() - state_change) > interval '5 minutes';"
   ```

### Redis Issues

If you're experiencing Redis issues:

1. Check if Redis is running:
   ```bash
   redis-cli ping
   ```

2. Start Redis if it's not running:
   ```bash
   brew services start redis
   ```

### SolidQueue Issues

If you're experiencing SolidQueue issues:

1. Check if SolidQueue processes are running:
   ```bash
   ps aux | grep solid_queue
   ```

2. Kill any existing SolidQueue processes:
   ```bash
   pkill -f solid_queue_monitor.rb
   ```

3. Clean up stale processes in the database:
   ```bash
   bin/rails runner "SolidQueue::Process.where(hostname: Socket.gethostname).destroy_all"
   ```

4. Start SolidQueue:
   ```bash
   bin/rails-server-with-solid-queue
   ```

## Best Practices

1. **Use `bin/rails server` for Development**: When you don't need background job processing, use the standard Rails server command.

2. **Use `bin/rails-server-with-solid-queue` for Full Environment**: When you need background job processing, use the script that starts the Rails server with SolidQueue.

3. **Monitor PostgreSQL Connections**: Keep an eye on PostgreSQL connections and clean up idle connections when necessary.

4. **Monitor Disk Space**: Keep an eye on disk space usage and clean up log files when necessary.

5. **Monitor SolidQueue Processes**: Keep an eye on SolidQueue processes and clean up stale processes when necessary.
