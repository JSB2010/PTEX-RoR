#!/bin/bash
# Script to kill all PostgreSQL connections to the development database

DB_NAME="ptex_development"
echo "Killing all connections to $DB_NAME database..."

# Create a SQL file to terminate connections
cat > /tmp/terminate_connections.sql << EOF
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE datname = '$DB_NAME' 
AND pid <> pg_backend_pid();
EOF

# Execute the SQL file
psql -U jbarkin28 -d postgres -f /tmp/terminate_connections.sql

# Remove the temporary file
rm /tmp/terminate_connections.sql

echo "All connections terminated."

# Restart the PostgreSQL server
echo "Restarting PostgreSQL server..."
brew services restart postgresql@14

echo "Waiting for PostgreSQL to restart..."
sleep 5

# Check if PostgreSQL is running
psql -U jbarkin28 -d postgres -c "SELECT 1" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "PostgreSQL restarted successfully."
else
  echo "Failed to restart PostgreSQL. Please restart it manually."
fi
