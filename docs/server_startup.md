# Server Startup Scripts

This document provides an overview of the server startup scripts in the application.

## Overview

The application includes several scripts for starting the Rails server with different options:

- `bin/rails server`: The standard Rails server command
- `bin/rails-server-simple`: A simple script that starts the Rails server without SolidQueue
- `bin/rails-server-final`: A comprehensive script that starts all necessary services

## Scripts

### `bin/rails server`

The standard Rails server command. This command has been modified to use the `bin/rails-server-simple` script.

### `bin/rails-server-simple`

A simple script that starts the Rails server without SolidQueue. This is useful for development when you don't need background job processing.

```bash
bin/rails-server-simple
```

### `bin/rails-server-final`

A comprehensive script that starts all necessary services, including PostgreSQL, Redis, and SolidQueue. This script is useful for development when you need all services running.

```bash
bin/rails-server-final
```

Options:
- `--skip-solid-queue`: Skip starting SolidQueue

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
   bin/start_solid_queue
   ```

## Best Practices

1. **Use `bin/rails-server-simple` for Development**: When you don't need background job processing, use the simple script to start the Rails server.

2. **Use `bin/rails-server-final` for Full Environment**: When you need all services running, use the comprehensive script.

3. **Monitor PostgreSQL Connections**: Keep an eye on PostgreSQL connections and clean up idle connections when necessary.

4. **Monitor Disk Space**: Keep an eye on disk space usage and clean up log files when necessary.

5. **Monitor SolidQueue Processes**: Keep an eye on SolidQueue processes and clean up stale processes when necessary.
