# Health System Documentation

This document provides an overview of the health monitoring system in the application.

## Overview

The health system provides comprehensive monitoring of the application's components, including:

- Database (PostgreSQL)
- Redis
- Job System (SolidQueue)
- Disk Space
- Network
- Memory
- System Information

## Endpoints

### `/health`

The main health endpoint that returns a JSON response with detailed information about the system's health. This endpoint can also render an HTML view when accessed via a web browser.

### `/health/dashboard`

A visual dashboard that displays the health information in a user-friendly format. This dashboard automatically refreshes every 30 seconds.

## Command Line Tools

### Database Monitoring

```bash
bin/monitor_db_connections.rb
```

Options:
- `-i, --interval SECONDS`: Interval between checks (default: 5)
- `-c, --count COUNT`: Number of checks to perform (default: infinite)
- `-k, --kill-idle`: Kill idle connections if percentage is high
- `-h, --help`: Show help message

### SolidQueue Monitoring

```bash
bin/monitor_solid_queue.rb
```

Options:
- `-i, --interval SECONDS`: Interval between checks (default: 5)
- `-c, --count COUNT`: Number of checks to perform (default: infinite)
- `-r, --restart`: Restart SolidQueue if it's not running properly
- `-h, --help`: Show help message

### Database Optimization

```bash
bin/optimize_database.rb
```

This script performs various database optimization tasks:
- Checks for bloated tables
- Identifies unused indexes
- Detects missing indexes
- Analyzes slow queries
- Vacuums and analyzes tables
- Optimizes SolidQueue tables

### Health Check

```bash
bin/rails health:check
```

This rake task performs a comprehensive health check of the system and outputs the results to the console.

### Database Maintenance

```bash
bin/rails db:maintenance:optimize
```

This rake task performs database maintenance tasks:
- Vacuums and analyzes tables
- Cleans up SolidQueue tables
- Removes old completed jobs
- Deletes stale processes
- Terminates idle connections

To schedule this task to run daily:

```bash
bin/rails db:maintenance:schedule
```

## Server Startup

The application includes a custom server wrapper that handles all startup logic:

```bash
bin/rails server
```

This command will:
1. Check if PostgreSQL is running and start it if needed
2. Check if Redis is running and start it if needed
3. Check disk space and clean up log files if needed
4. Check PostgreSQL connections and clean up idle connections if needed
5. Configure the database connection pool
6. Start SolidQueue
7. Start the Rails server

Additional options:
- `--optimize-db`: Optimize the database before starting the server
- `--skip-solid-queue`: Skip starting SolidQueue

## Monitoring and Maintenance

### PostgreSQL Connection Management

The application includes a PostgreSQL connection manager that:
- Configures the connection pool based on the environment
- Periodically cleans up idle connections
- Monitors connection usage
- Provides recommendations for PostgreSQL optimization

### SolidQueue Management

The application includes a SolidQueue manager that:
- Initializes SolidQueue processes
- Cleans up stale processes and orphaned executions
- Processes ready jobs
- Monitors SolidQueue status
- Automatically restarts SolidQueue if it crashes

### Disk Space Monitoring

The application monitors disk space usage and:
- Warns when disk space is running low
- Automatically cleans up log files
- Provides detailed information about disk space usage

## Troubleshooting

### PostgreSQL Connection Issues

If you're experiencing PostgreSQL connection issues:

1. Check the current connection status:
   ```bash
   bin/monitor_db_connections.rb
   ```

2. Kill idle connections:
   ```bash
   bin/monitor_db_connections.rb --kill-idle
   ```

3. Restart PostgreSQL:
   ```bash
   brew services restart postgresql@14
   ```

### SolidQueue Issues

If you're experiencing SolidQueue issues:

1. Check the current status:
   ```bash
   bin/monitor_solid_queue.rb
   ```

2. Restart SolidQueue:
   ```bash
   bin/monitor_solid_queue.rb --restart
   ```

3. Clean up SolidQueue tables:
   ```bash
   bin/rails db:maintenance:optimize
   ```

### Disk Space Issues

If you're experiencing disk space issues:

1. Clean up log files:
   ```bash
   bin/clean_logs.sh
   ```

2. Check disk space usage:
   ```bash
   df -h
   ```

3. Find large files:
   ```bash
   find /path/to/directory -type f -size +10M | xargs ls -lh
   ```

## Best Practices

1. **Regular Monitoring**: Check the health dashboard regularly to identify potential issues before they become critical.

2. **Database Maintenance**: Run the database maintenance task daily to keep the database optimized.

3. **Connection Management**: Keep an eye on PostgreSQL connections and clean up idle connections when necessary.

4. **Disk Space Management**: Monitor disk space usage and clean up log files regularly.

5. **Job System Monitoring**: Monitor SolidQueue status and restart it if necessary.

## Recommendations for Further Improvements

1. **Upgrade PostgreSQL**: Consider upgrading to PostgreSQL 15 or 16, which have better connection handling and performance improvements.

2. **Implement Connection Pooling**: Consider using a connection pooler like PgBouncer to manage PostgreSQL connections more efficiently.

3. **Optimize Database Queries**: Review and optimize database queries to reduce the number of connections needed.

4. **Implement Monitoring**: Set up monitoring for PostgreSQL connections, disk space, and SolidQueue processes to detect issues before they become critical.

5. **Implement Automatic Scaling**: Consider implementing automatic scaling of SolidQueue workers based on job queue size and system resources.
