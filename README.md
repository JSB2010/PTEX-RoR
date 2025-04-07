# PTEX-RoR Application

This is a Ruby on Rails application with PostgreSQL, Redis, and SolidQueue for background job processing.

## System Requirements

* Ruby 3.2.2
* PostgreSQL 14
* Redis 7.0+

## Getting Started

### Starting the Server

To start the server with all components (web server, PostgreSQL, Redis, and SolidQueue), use:

```bash
bin/start-all
```

This will:
1. Start PostgreSQL if it's not running
2. Start Redis if it's not running
3. Start SolidQueue for background job processing
4. Start the Rails web server

You can also use the standard Rails server command, but you'll need to start the other components manually:

```bash
# Start PostgreSQL
brew services start postgresql@14

# Start Redis
brew services start redis

# Start SolidQueue
bin/start-solid-queue

# Start Rails server
bin/rails server
```

## Services

### SolidQueue

SolidQueue is used for background job processing. It consists of two components:

1. Dispatcher - Schedules jobs to be executed
2. Worker - Executes the jobs

You can start SolidQueue using the `bin/start-solid-queue` script.

### PostgreSQL

The application uses PostgreSQL for the database. Make sure PostgreSQL is installed and running.

### Redis

Redis is used for caching and as a backend for SolidQueue. Make sure Redis is installed and running.

## Troubleshooting

If you encounter issues with the server not starting properly, try these steps:

1. Make sure PostgreSQL is running: `pg_isready`
2. Make sure Redis is running: `redis-cli ping`
3. Kill any existing SolidQueue processes: `pkill -f "SolidQueue"`
4. Start the server using the `bin/start-all` script
