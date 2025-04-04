#!/usr/bin/env ruby
# Script to monitor PostgreSQL connections

require_relative '../config/environment'

# Function to get connection information
def get_connection_info
  # Get the current database name
  db_name = ActiveRecord::Base.connection.current_database
  
  # Get connection count
  result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = '#{db_name}'")
  connections = result.first["count"].to_i
  
  # Get max connections
  max_connections_result = ActiveRecord::Base.connection.execute("SHOW max_connections")
  max_connections = max_connections_result.first["max_connections"].to_i
  
  # Calculate percentage
  percentage = (connections.to_f / max_connections) * 100
  
  # Get idle connections
  idle_result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = '#{db_name}' AND state = 'idle'")
  idle_connections = idle_result.first["count"].to_i
  
  # Get active connections
  active_result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = '#{db_name}' AND state = 'active'")
  active_connections = active_result.first["count"].to_i
  
  # Get long-running queries
  long_queries = ActiveRecord::Base.connection.execute(<<-SQL)
    SELECT pid, now() - query_start AS duration, state, query
    FROM pg_stat_activity
    WHERE state != 'idle' AND now() - query_start > interval '5 seconds'
    ORDER BY duration DESC;
  SQL
  
  {
    database: db_name,
    connections: connections,
    max_connections: max_connections,
    percentage: percentage.round(1),
    idle_connections: idle_connections,
    active_connections: active_connections,
    long_queries: long_queries.count
  }
end

# Function to kill idle connections
def kill_idle_connections
  # Get the current database name
  db_name = ActiveRecord::Base.connection.current_database
  
  # Kill idle connections that have been idle for more than 5 minutes
  result = ActiveRecord::Base.connection.execute(<<-SQL)
    SELECT pg_terminate_backend(pid) 
    FROM pg_stat_activity 
    WHERE datname = '#{db_name}' 
    AND pid <> pg_backend_pid()
    AND state = 'idle'
    AND (now() - state_change) > interval '5 minutes';
  SQL
  
  result.count
end

# Parse command line arguments
require 'optparse'

options = {
  interval: 5,
  count: nil,
  kill_idle: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  
  opts.on("-i", "--interval SECONDS", Integer, "Interval between checks (default: 5)") do |i|
    options[:interval] = i
  end
  
  opts.on("-c", "--count COUNT", Integer, "Number of checks to perform (default: infinite)") do |c|
    options[:count] = c
  end
  
  opts.on("-k", "--kill-idle", "Kill idle connections if percentage is high") do
    options[:kill_idle] = true
  end
  
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

puts "Monitoring PostgreSQL connections..."
puts "Press Ctrl+C to stop"
puts

count = 0
loop do
  count += 1
  break if options[:count] && count > options[:count]
  
  info = get_connection_info
  
  puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}: #{info[:connections]}/#{info[:max_connections]} connections (#{info[:percentage]}%)"
  puts "  Active: #{info[:active_connections]}, Idle: #{info[:idle_connections]}, Long-running queries: #{info[:long_queries]}"
  
  if info[:percentage] > 80 && options[:kill_idle]
    killed = kill_idle_connections
    puts "  WARNING: High connection percentage. Killed #{killed} idle connections."
  end
  
  sleep options[:interval]
end
