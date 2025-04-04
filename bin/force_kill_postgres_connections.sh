#!/bin/bash
# Script to forcefully kill all PostgreSQL connections

echo "Forcefully killing all PostgreSQL connections..."

# Kill all PostgreSQL processes
pkill -9 postgres

# Wait for PostgreSQL to shut down
sleep 2

# Restart PostgreSQL
echo "Restarting PostgreSQL..."
brew services restart postgresql@14

# Wait for PostgreSQL to start up
echo "Waiting for PostgreSQL to start up..."
sleep 5

echo "PostgreSQL has been restarted."
