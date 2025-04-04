# Server Management Scripts

This directory contains scripts to help manage the Rails server and its dependencies.

## Available Scripts

### Main Scripts

- `rails server` or `rails s` - Start the Rails server with automatic service checks
- `start-all` - Start all required services (PostgreSQL, Redis, etc.)
- `health-check` - Check the health of all services
- `db-init` - Initialize the database if it doesn't exist

### Helper Scripts

- `check-db-connection` - Check if the database connection is working
- `rails-server-auto` - The main script that powers `rails server`

## Usage Examples

### Starting the Server

```bash
# Start the Rails server with automatic service checks
bin/rails server

# Or use the shorthand
bin/rails s
```

### Starting All Services

```bash
# Start PostgreSQL, Redis, and initialize the database
bin/start-all
```

### Checking System Health

```bash
# Check if all services are running properly
bin/health-check
```

### Initializing the Database

```bash
# Create the database and run migrations if needed
bin/db-init
```

## Troubleshooting

If you encounter issues with the Rails server:

1. Run `bin/health-check` to see which services are not running
2. Run `bin/start-all` to start all required services
3. Try starting the server again with `bin/rails server`

If you still have issues, check the logs in the `log/` directory for more information.
