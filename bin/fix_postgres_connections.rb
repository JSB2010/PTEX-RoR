#!/usr/bin/env ruby
# Script to fix PostgreSQL connection issues by terminating idle connections

require_relative '../config/environment'

# Get the current database name
db_name = ActiveRecord::Base.connection.current_database

puts "Fixing PostgreSQL connection issues for database: #{db_name}"

# Query to find idle connections
idle_connections_query = <<-SQL
  SELECT 
    pid, 
    application_name,
    usename,
    client_addr,
    state,
    backend_start,
    xact_start,
    query_start,
    state_change,
    wait_event_type,
    wait_event
  FROM 
    pg_stat_activity 
  WHERE 
    datname = '#{db_name}' 
    AND pid <> pg_backend_pid()
    AND state = 'idle'
    AND (now() - state_change) > interval '5 minutes'
  ORDER BY 
    state_change;
SQL

# Query to terminate idle connections
terminate_idle_connections_query = <<-SQL
  SELECT 
    pg_terminate_backend(pid) 
  FROM 
    pg_stat_activity 
  WHERE 
    datname = '#{db_name}' 
    AND pid <> pg_backend_pid()
    AND state = 'idle'
    AND (now() - state_change) > interval '5 minutes';
SQL

# Query to terminate idle in transaction connections
terminate_idle_in_transaction_query = <<-SQL
  SELECT 
    pg_terminate_backend(pid) 
  FROM 
    pg_stat_activity 
  WHERE 
    datname = '#{db_name}' 
    AND pid <> pg_backend_pid()
    AND state = 'idle in transaction'
    AND (now() - state_change) > interval '30 minutes';
SQL

# Get the current connection count
connection_count_query = <<-SQL
  SELECT count(*) FROM pg_stat_activity WHERE datname = '#{db_name}';
SQL

# Execute the queries
begin
  # Get the current connection count
  connection_count = ActiveRecord::Base.connection.execute(connection_count_query).first["count"]
  puts "Current connection count: #{connection_count}"

  # Get idle connections
  idle_connections = ActiveRecord::Base.connection.execute(idle_connections_query)
  puts "Found #{idle_connections.count} idle connections that have been idle for more than 5 minutes"

  # Terminate idle connections
  terminated = ActiveRecord::Base.connection.execute(terminate_idle_connections_query)
  puts "Terminated #{terminated.count} idle connections"

  # Terminate idle in transaction connections
  terminated_in_transaction = ActiveRecord::Base.connection.execute(terminate_idle_in_transaction_query)
  puts "Terminated #{terminated_in_transaction.count} idle in transaction connections"

  # Get the new connection count
  new_connection_count = ActiveRecord::Base.connection.execute(connection_count_query).first["count"]
  puts "New connection count: #{new_connection_count}"
  puts "Reduced connections by: #{connection_count - new_connection_count}"
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n")
end
