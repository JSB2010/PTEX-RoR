# PTEX-RoR Application

A comprehensive Ruby on Rails school management system with PostgreSQL, Redis, and Sidekiq for reliable background job processing.

## System Requirements

* Ruby 3.2.2
* PostgreSQL 14+
* Redis 7.0+
* Node.js (for asset compilation)

## Features

* **Student Management**: Complete student enrollment and tracking
* **Course Management**: Course creation, scheduling, and management
* **Grade Management**: Grade entry, calculation, and reporting
* **Background Jobs**: Reliable job processing with Sidekiq
* **Performance Optimized**: Query optimization, caching, and monitoring
* **Security**: Rate limiting, error handling, and security best practices

## Getting Started

### Quick Start

To start the server with all components (web server, PostgreSQL, Redis, and Sidekiq), use:

```bash
bin/start-all
```

This will:
1. Start PostgreSQL if it's not running
2. Start Redis if it's not running
3. Start Sidekiq for background job processing
4. Start the Rails web server

### Manual Setup

You can also start components individually:

```bash
# Start PostgreSQL
brew services start postgresql@14

# Start Redis
brew services start redis

# Start Sidekiq for background jobs
bundle exec sidekiq
# or
./bin/sidekiq

# Start Rails server
bin/rails server
```

## Services

### Sidekiq

Sidekiq is used for reliable background job processing. It provides:

1. **Fast job processing** with Redis backend
2. **Web interface** for monitoring at `/admin/sidekiq`
3. **Retry logic** for failed jobs
4. **Scheduled jobs** support

You can start Sidekiq using `bundle exec sidekiq` or `./bin/sidekiq`.

### PostgreSQL

The application uses PostgreSQL for the database. Make sure PostgreSQL is installed and running.

### Redis

Redis is used for caching and as the backend for Sidekiq job storage. Make sure Redis is installed and running.

## Environment Variables

Create a `.env` file in the root directory with the following variables:

```bash
# Database
DATABASE_URL=postgresql://username:password@localhost/ptex_ror_development

# Redis
REDIS_URL=redis://localhost:6379/0

# Sidekiq
SIDEKIQ_CONCURRENCY=5

# Security
SECRET_KEY_BASE=your_secret_key_here

# Rate Limiting
THROTTLE_REQUESTS_PER_MINUTE=300
TRUSTED_NETWORKS=192.168.1.0/24,10.0.0.0/8

# Performance
RAILS_MAX_THREADS=5
STATEMENT_CACHE_SIZE=1000
PREPARED_STATEMENTS_CACHE_SIZE=1000
```

## Development Commands

```bash
# Start all services
bin/start-all

# Start Sidekiq only
bundle exec sidekiq

# Check Sidekiq status
rake sidekiq:status

# Run tests
bin/rails test

# Security scan
bin/brakeman

# Code style check
bundle exec rubocop
```

## Monitoring

* **Sidekiq Web UI**: Visit `/admin/sidekiq` to monitor background jobs
* **Application Logs**: Check `log/development.log` for application logs
* **Sidekiq Logs**: Sidekiq logs are integrated with Rails logs

## Troubleshooting

If you encounter issues with the server not starting properly, try these steps:

1. Make sure PostgreSQL is running: `pg_isready`
2. Make sure Redis is running: `redis-cli ping`
3. Kill any existing Sidekiq processes: `pkill -f "sidekiq"`
4. Start the server using the `bin/start-all` script
5. Check logs in `log/development.log` for detailed error messages
