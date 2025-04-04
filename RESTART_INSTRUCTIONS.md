# PostgreSQL Connection Issue Fix

It seems that PostgreSQL is having issues with shared memory, which is preventing it from starting properly. The most reliable way to fix this is to restart your computer, which will clear all shared memory.

## Steps to Fix the Issue

1. **Save your work** and close any open applications.
2. **Restart your computer**.
3. After restart, open Terminal and run the following commands:

```bash
# Check if PostgreSQL is running
pg_isready

# If it's not running, start it
brew services start postgresql@14

# Wait a few seconds for PostgreSQL to start
sleep 5

# Check if it's running now
pg_isready

# Start the Rails server
cd /Users/jbarkin28/PTEX-RoR
bin/rails server
```

## If Issues Persist After Restart

If you still have issues after restarting, try the following:

1. **Completely uninstall and reinstall PostgreSQL**:

```bash
# Stop PostgreSQL
brew services stop postgresql@14

# Uninstall PostgreSQL
brew uninstall postgresql@14

# Remove PostgreSQL data directory
rm -rf /opt/homebrew/var/postgresql@14

# Install PostgreSQL again
brew install postgresql@14

# Start PostgreSQL
brew services start postgresql@14

# Initialize the database
initdb /opt/homebrew/var/postgresql@14

# Start PostgreSQL service
brew services start postgresql@14

# Create the database
createdb ptex_development

# Start the Rails server
cd /Users/jbarkin28/PTEX-RoR
bin/rails server
```

## Alternative Solution: Use a Different Database

If you continue to have issues with PostgreSQL, you could consider using a different database for development, such as SQLite:

1. Update your Gemfile to include SQLite:

```ruby
gem 'sqlite3'
```

2. Update your database.yml file:

```yaml
development:
  adapter: sqlite3
  database: db/development.sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
```

3. Run bundle install and migrate the database:

```bash
bundle install
bin/rails db:migrate
```

4. Start the Rails server:

```bash
bin/rails server
```
