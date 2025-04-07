# Optimization Guide

This document provides information about the optimizations that have been implemented to improve the performance and reduce the resource usage of the application.

## Table of Contents

1. [Database Connection Pooling](#database-connection-pooling)
2. [Memory Limits](#memory-limits)
3. [Request Throttling](#request-throttling)
4. [Database Query Optimization](#database-query-optimization)
5. [Caching](#caching)
6. [Asset Handling](#asset-handling)
7. [Logging](#logging)
8. [Background Jobs](#background-jobs)
9. [Puma Configuration](#puma-configuration)
10. [Server Startup](#server-startup)

## Database Connection Pooling

The database connection pool has been optimized to improve performance and reduce resource usage:

- **Pool Size**: The pool size has been set to 5 connections by default, which is sufficient for most development environments. In production, it's set to match the number of threads.
- **Checkout Timeout**: The checkout timeout has been reduced to 3 seconds to prevent long-running queries from blocking the pool.
- **Reaping Frequency**: The reaping frequency has been increased to 30 seconds to reduce the overhead of checking for stale connections.
- **Idle Timeout**: The idle timeout has been increased to 60 seconds to reduce the overhead of creating new connections.
- **Prepared Statements**: Prepared statements have been disabled to reduce connection overhead.
- **Statement Timeout**: The statement timeout has been set to 30 seconds to prevent long-running queries from blocking the pool.
- **Lock Timeout**: The lock timeout has been set to 5 seconds to prevent deadlocks.
- **Idle Transaction Timeout**: The idle transaction timeout has been set to 1 minute to prevent idle transactions from blocking the pool.

## Memory Limits

Memory limits have been implemented to reduce memory usage:

- **Malloc Limit**: The malloc limit has been set to 64MB to prevent memory leaks.
- **Heap Init Slots**: The initial heap slots have been increased to 600,000 to reduce GC frequency.
- **Heap Growth Factor**: The heap growth factor has been set to 1.25 to reduce memory usage.
- **Heap Free Slots Ratio**: The heap free slots ratio has been set to 0.20 to reduce memory usage.
- **Heap Free Slots Goal Ratio**: The heap free slots goal ratio has been set to 0.40 to reduce memory usage.
- **Old Objects Limit**: The old objects limit has been set to 250,000 to reduce memory usage.
- **Incremental GC**: Incremental GC has been enabled to reduce GC pauses.
- **Incremental Marking**: Incremental marking has been enabled to reduce GC pauses.
- **Periodic GC**: Periodic GC has been enabled to clean up memory every 5 minutes.
- **Memory Monitoring**: Memory usage is monitored every 15 minutes, and GC is forced if memory usage exceeds 500MB.

## Request Throttling

Request throttling has been implemented to prevent overloading the server:

- **Global Rate Limit**: The global rate limit has been set to 300 requests per minute per IP.
- **Login Rate Limit**: The login rate limit has been set to 5 requests per 20 seconds per IP.
- **Failed Login Rate Limit**: The failed login rate limit has been set to 3 requests per 5 minutes per IP.
- **Email Rate Limit**: The email rate limit has been set to 5 requests per 20 seconds per email.
- **Password Reset Rate Limit**: The password reset rate limit has been set to 3 requests per 15 minutes per IP.
- **Grade Update Rate Limit**: The grade update rate limit has been set to 30 requests per minute per IP.
- **Bulk Operation Rate Limit**: The bulk operation rate limit has been set to 10 requests per 5 minutes per IP.
- **API Rate Limit**: The API rate limit has been set to 300 requests per minute for authenticated users and 60 requests per minute for anonymous users.
- **Health Endpoint Rate Limit**: The health endpoint rate limit has been set to 30 requests per minute per IP.

## Database Query Optimization

Database queries have been optimized to improve performance:

- **Query Cache**: The query cache has been enabled in all environments.
- **Slow Query Logging**: Slow queries are logged in development and production.
- **N+1 Query Detection**: N+1 queries are detected and logged in development.
- **Index Hints**: Index hints can be added to queries to improve performance.
- **Query Timeout**: Query timeouts can be added to prevent long-running queries.
- **Query Priority**: Query priority can be set to low for background jobs.
- **Statement Cache**: The statement cache size has been increased to 1000 to improve performance.
- **Prepared Statement Cache**: The prepared statement cache size has been increased to 1000 to improve performance.

## Caching

Caching has been optimized to improve performance:

- **Redis Cache**: Redis is used for caching in development and production.
- **Cache Namespace**: The cache namespace has been set to `ptex:cache:#{Rails.env}` to prevent cache key collisions.
- **Cache Expiry**: The cache expiry has been set to 1 hour in development and 7 days in production.
- **Cache Compression**: Cache compression has been enabled to reduce memory usage.
- **Cache Compression Threshold**: The cache compression threshold has been set to 1KB to reduce memory usage.
- **Cache Pool Size**: The cache pool size has been set to 5 in development and 10 in production.
- **Cache Pool Timeout**: The cache pool timeout has been set to 5 seconds to prevent blocking.
- **Cache Error Handling**: Cache errors are logged to prevent application crashes.
- **HTTP Caching**: HTTP caching has been enabled to improve performance.
- **Low-Level Caching**: Low-level caching has been enabled to improve performance.
- **Template Caching**: Template caching has been enabled to improve performance.

## Asset Handling

Asset handling has been optimized to improve performance:

- **Asset Compression**: Asset compression has been enabled to reduce file size.
- **Asset Digest**: Asset digest has been enabled to improve caching.
- **Asset Version**: The asset version has been set to 1.0 to improve caching.
- **Asset Host**: The asset host can be configured to improve performance.
- **Asset Cache Buster**: The asset cache buster has been set to 50MB to improve performance.
- **Asset Paths**: Additional asset paths have been added to improve organization.
- **Asset Precompilation**: Additional asset types have been added to the precompilation list.
- **Asset Debugging**: Asset debugging has been disabled to improve performance.
- **Asset Quiet**: Asset quiet has been enabled to reduce log noise.
- **Asset Prefix**: The asset prefix can be configured to improve organization.
- **Asset CDN**: The asset CDN can be configured to improve performance.
- **Asset Gzip**: Asset gzip has been enabled to reduce file size.
- **Asset Source Maps**: Asset source maps have been disabled to improve performance.
- **Asset Cache Headers**: Asset cache headers have been set to 1 year to improve caching.

## Logging

Logging has been optimized to reduce disk usage:

- **Log Level**: The log level has been set to info by default.
- **Log Formatter**: The log formatter has been customized to include timestamps.
- **Log Rotation**: Log rotation has been enabled to reduce disk usage.
- **Log Filtering**: Sensitive parameters are filtered from logs.
- **Log Silencing**: Asset logs have been silenced to reduce log noise.
- **Log Tagging**: Logs are tagged with request ID, IP, and user agent.
- **Log Compression**: Logs older than 1 day are compressed to reduce disk usage.
- **Log Cleanup**: Logs older than 30 days are deleted to reduce disk usage.

## Background Jobs

Background jobs have been optimized to improve performance:

- **Dispatcher Concurrency**: The dispatcher concurrency has been set to 5 threads.
- **Worker Concurrency**: The worker concurrency has been set to 5 threads.
- **Polling Interval**: The polling interval has been set to 1 second.
- **Heartbeat Interval**: The heartbeat interval has been set to 60 seconds.
- **Failed Job Retention**: Failed jobs are retained for 30 days.
- **Successful Job Retention**: Successful jobs are retained for 1 day.
- **Process Termination Timeout**: The process termination timeout has been set to 30 seconds.
- **Queue Concurrency**: The queue concurrency has been set to 5 for default, 2 for mailers, and 1 for low priority.
- **Maximum Attempts**: The maximum number of attempts has been set to 3.
- **Error Handling**: Errors are reported to Honeybadger if available.
- **Metrics**: Metrics are reported to Prometheus if available.
- **Cleanup**: Old jobs, executions, and processes are cleaned up periodically.

## Puma Configuration

Puma has been optimized to improve performance:

- **Thread Count**: The thread count has been set to 1-5 in development and 4-8 in production.
- **Worker Count**: The worker count has been set to 0 in development and CPU count - 1 in production.
- **Preload App**: The app is preloaded in production to reduce memory usage.
- **Database Connection Handling**: Database connections are closed before forking and re-established after forking.
- **Redis Connection Handling**: Redis connections are initialized after forking and closed on worker shutdown.
- **Worker Timeout**: The worker timeout has been set to 60 seconds.
- **Worker Boot Timeout**: The worker boot timeout has been set to 60 seconds.
- **Request Timeout**: The request timeout has been set to 30 seconds.
- **Persistent Timeout**: The persistent timeout has been set to 20 seconds.
- **First Data Timeout**: The first data timeout has been set to 30 seconds.
- **Low Latency Mode**: Low latency mode can be enabled to improve performance.
- **Thread Pool Size**: The thread pool size has been set to 16.
- **Backlog**: The backlog has been set to 1024.
- **TCP Mode**: TCP mode can be enabled to improve performance.
- **Worker Check Interval**: The worker check interval has been set to 5 seconds.
- **Out of Band GC**: Out of band GC can be enabled to improve performance.

## Server Startup

The server startup process has been optimized to improve reliability:

- **PostgreSQL Check**: PostgreSQL is checked and started if necessary.
- **Redis Check**: Redis is checked and started if necessary.
- **Log Cleanup**: Large log files are truncated to reduce disk usage.
- **PID Cleanup**: Stale PID files are cleaned up to prevent conflicts.
- **Process Cleanup**: Existing Rails processes are killed to prevent conflicts.
- **Environment Variables**: Environment variables are set to optimize performance.
- **Caching**: Caching is enabled in development to improve performance.
- **Error Handling**: Errors are handled gracefully to prevent crashes.
- **Logging**: Detailed logs are provided to aid in debugging.
- **Timeouts**: Timeouts are added to prevent hanging.
- **Fallbacks**: Fallbacks are provided for when components fail.

## Usage

To start the server with all optimizations, simply run:

```bash
rails server
```

This will start the server with all the optimizations described above.

## Environment Variables

The following environment variables can be used to customize the optimizations:

- `RAILS_MAX_THREADS`: The maximum number of threads (default: 5 in development, 8 in production)
- `RAILS_MIN_THREADS`: The minimum number of threads (default: 1 in development, 4 in production)
- `WEB_CONCURRENCY`: The number of workers (default: 0 in development, CPU count - 1 in production)
- `REDIS_URL`: The URL of the Redis server (default: redis://localhost:6379/1)
- `REDIS_POOL_SIZE`: The size of the Redis connection pool (default: 5 in development, 10 in production)
- `REDIS_POOL_TIMEOUT`: The timeout for the Redis connection pool (default: 5 seconds)
- `CACHE_EXPIRES_IN`: The expiry time for cached items (default: 1 hour in development, 7 days in production)
- `CACHE_MAX_AGE`: The max-age for HTTP cache headers (default: 3600 seconds in development, 86400 seconds in production)
- `STATEMENT_TIMEOUT`: The timeout for database statements (default: 30 seconds)
- `LOCK_TIMEOUT`: The timeout for database locks (default: 5 seconds)
- `IDLE_TRANSACTION_TIMEOUT`: The timeout for idle transactions (default: 60 seconds)
- `MALLOC_LIMIT`: The malloc limit (default: 64MB)
- `GC_HEAP_INIT_SLOTS`: The initial heap slots (default: 600,000)
- `GC_HEAP_GROWTH_FACTOR`: The heap growth factor (default: 1.25)
- `GC_HEAP_FREE_SLOTS_MIN_RATIO`: The heap free slots min ratio (default: 0.20)
- `GC_HEAP_FREE_SLOTS_GOAL_RATIO`: The heap free slots goal ratio (default: 0.40)
- `GC_OLD_OBJECTS_LIMIT`: The old objects limit (default: 250,000)
- `GC_INTERVAL_SECONDS`: The interval for periodic GC (default: 300 seconds)
- `MEMORY_LOG_INTERVAL_SECONDS`: The interval for memory logging (default: 900 seconds)
- `MEMORY_THRESHOLD_MB`: The threshold for forced GC (default: 500MB)
- `THROTTLE_REQUESTS_PER_MINUTE`: The global rate limit (default: 300 requests per minute)
- `THROTTLE_LOGIN_REQUESTS_PER_MINUTE`: The login rate limit (default: 5 requests per minute)
- `THROTTLE_API_REQUESTS_PER_MINUTE`: The API rate limit (default: 120 requests per minute)
- `THROTTLE_HEALTH_REQUESTS_PER_MINUTE`: The health endpoint rate limit (default: 30 requests per minute)
- `THROTTLE_LOGIN_ATTEMPTS_PER_EMAIL`: The email rate limit (default: 5 requests per 5 minutes)
- `STATEMENT_CACHE_SIZE`: The statement cache size (default: 1000)
- `PREPARED_STATEMENTS_CACHE_SIZE`: The prepared statement cache size (default: 1000)
- `ASSET_CACHE_LIMIT`: The asset cache limit (default: 50MB)
- `ASSET_CACHE_MAX_AGE`: The asset cache max age (default: 31536000 seconds)
- `LOG_LEVEL`: The log level (default: info)
- `LOG_FILES`: The number of log files to keep (default: 10)
- `LOG_FILE_SIZE`: The maximum size of each log file (default: 100MB)
- `LOG_COMPRESSION_INTERVAL`: The interval for log compression (default: 86400 seconds)
- `LOG_CLEANUP_INTERVAL`: The interval for log cleanup (default: 604800 seconds)
- `SOLID_QUEUE_DISPATCHER_CONCURRENCY`: The dispatcher concurrency (default: 5)
- `SOLID_QUEUE_WORKER_CONCURRENCY`: The worker concurrency (default: 5)
- `SOLID_QUEUE_POLLING_INTERVAL`: The polling interval (default: 1 second)
- `SOLID_QUEUE_HEARTBEAT_INTERVAL`: The heartbeat interval (default: 60 seconds)
- `SOLID_QUEUE_FAILED_JOB_RETENTION`: The failed job retention period (default: 30 days)
- `SOLID_QUEUE_SUCCESSFUL_JOB_RETENTION`: The successful job retention period (default: 1 day)
- `SOLID_QUEUE_PROCESS_TERMINATION_TIMEOUT`: The process termination timeout (default: 30 seconds)
- `SOLID_QUEUE_DEFAULT_CONCURRENCY`: The default queue concurrency (default: 5)
- `SOLID_QUEUE_MAILERS_CONCURRENCY`: The mailers queue concurrency (default: 2)
- `SOLID_QUEUE_LOW_PRIORITY_CONCURRENCY`: The low priority queue concurrency (default: 1)
- `SOLID_QUEUE_MAX_ATTEMPTS`: The maximum number of attempts (default: 3)
- `SOLID_QUEUE_CLEANUP_INTERVAL`: The interval for SolidQueue cleanup (default: 86400 seconds)
- `WORKER_TIMEOUT`: The worker timeout (default: 60 seconds)
- `WORKER_BOOT_TIMEOUT`: The worker boot timeout (default: 60 seconds)
- `REQUEST_TIMEOUT`: The request timeout (default: 30 seconds)
- `PERSISTENT_TIMEOUT`: The persistent timeout (default: 20 seconds)
- `FIRST_DATA_TIMEOUT`: The first data timeout (default: 30 seconds)
- `THREAD_POOL_SIZE`: The thread pool size (default: 16)
- `BACKLOG`: The backlog (default: 1024)
- `WORKER_CHECK_INTERVAL`: The worker check interval (default: 5 seconds)
- `PUMA_LOW_LATENCY`: Enable low latency mode (default: false)
- `TCP_MODE`: Enable TCP mode (default: false)
- `OUT_OF_BAND_GC`: Enable out of band GC (default: false)
- `SKIP_MIGRATION_CHECK`: Skip migration check (default: true)
- `SKIP_SOLID_QUEUE`: Skip SolidQueue (default: true in development)
- `ASSET_HOST`: The asset host (default: nil)
- `ASSET_PREFIX`: The asset prefix (default: nil)
- `ASSET_CDN`: The asset CDN (default: nil)
- `TRUSTED_IPS`: Comma-separated list of trusted IPs (default: nil)
