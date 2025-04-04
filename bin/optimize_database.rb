#!/usr/bin/env ruby
# Script to optimize the PostgreSQL database

require_relative '../config/environment'

puts "Optimizing PostgreSQL database..."

# Get the current database name
db_name = ActiveRecord::Base.connection.current_database
puts "Database: #{db_name}"

# Check for bloated tables
puts "\nChecking for bloated tables..."
bloated_tables_sql = <<-SQL
  SELECT
    schemaname || '.' || tablename AS table_name,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename) - pg_relation_size(schemaname || '.' || tablename)) AS index_size,
    ROUND(100 * pg_relation_size(schemaname || '.' || tablename) / pg_total_relation_size(schemaname || '.' || tablename)) AS table_percent
  FROM pg_tables
  WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
  ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
  LIMIT 10;
SQL

bloated_tables = ActiveRecord::Base.connection.execute(bloated_tables_sql)
bloated_tables.each do |table|
  puts "#{table['table_name']}: Total Size: #{table['total_size']}, Table Size: #{table['table_size']}, Index Size: #{table['index_size']}, Table %: #{table['table_percent']}%"
end

# Check for unused indexes
puts "\nChecking for unused indexes..."
unused_indexes_sql = <<-SQL
  SELECT
    schemaname || '.' || relname AS table,
    indexrelname AS index,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
    idx_scan as index_scans
  FROM pg_stat_user_indexes ui
  JOIN pg_index i ON ui.indexrelid = i.indexrelid
  WHERE NOT indisunique AND idx_scan < 50 AND pg_relation_size(relid) > 5 * 8192
  ORDER BY pg_relation_size(i.indexrelid) / NULLIF(idx_scan, 0) DESC NULLS FIRST,
  pg_relation_size(i.indexrelid) DESC;
SQL

unused_indexes = ActiveRecord::Base.connection.execute(unused_indexes_sql)
unused_indexes.each do |index|
  puts "#{index['table']}.#{index['index']}: Size: #{index['index_size']}, Scans: #{index['index_scans']}"
end

# Check for missing indexes
puts "\nChecking for missing indexes..."
missing_indexes_sql = <<-SQL
  SELECT
    relname AS table,
    seq_scan - idx_scan AS too_much_seq,
    CASE
      WHEN seq_scan - idx_scan > 0 THEN 'Missing Index?'
      ELSE 'OK'
    END AS verdict,
    pg_size_pretty(pg_relation_size(relname::regclass)) AS table_size
  FROM pg_stat_user_tables
  WHERE pg_relation_size(relname::regclass) > 80000
  ORDER BY too_much_seq DESC;
SQL

missing_indexes = ActiveRecord::Base.connection.execute(missing_indexes_sql)
missing_indexes.each do |table|
  puts "#{table['table']}: Too Many Sequential Scans: #{table['too_much_seq']}, Verdict: #{table['verdict']}, Size: #{table['table_size']}"
end

# Check for slow queries
puts "\nChecking for slow queries..."
slow_queries_sql = <<-SQL
  SELECT
    substring(query, 1, 100) AS short_query,
    round(total_time::numeric, 2) AS total_time,
    calls,
    round(mean_time::numeric, 2) AS mean_time,
    round((100 * total_time / sum(total_time::numeric) OVER ())::numeric, 2) AS percentage
  FROM pg_stat_statements
  ORDER BY total_time DESC
  LIMIT 10;
SQL

begin
  slow_queries = ActiveRecord::Base.connection.execute(slow_queries_sql)
  slow_queries.each do |query|
    puts "Query: #{query['short_query']}, Total Time: #{query['total_time']}ms, Calls: #{query['calls']}, Mean Time: #{query['mean_time']}ms, Percentage: #{query['percentage']}%"
  end
rescue => e
  puts "Error checking slow queries: #{e.message}"
  puts "You may need to enable the pg_stat_statements extension."
end

# Vacuum analyze tables
puts "\nVacuuming and analyzing tables..."
tables = ActiveRecord::Base.connection.tables
tables.each do |table|
  puts "Vacuuming and analyzing #{table}..."
  ActiveRecord::Base.connection.execute("VACUUM ANALYZE #{table};")
end

# Optimize SolidQueue tables
puts "\nOptimizing SolidQueue tables..."
solid_queue_tables = [
  "solid_queue_jobs",
  "solid_queue_processes",
  "solid_queue_ready_executions",
  "solid_queue_claimed_executions",
  "solid_queue_blocked_executions",
  "solid_queue_failed_executions",
  "solid_queue_semaphores",
  "solid_queue_pauses"
]

solid_queue_tables.each do |table|
  if ActiveRecord::Base.connection.table_exists?(table)
    puts "Optimizing #{table}..."
    
    # Vacuum analyze
    ActiveRecord::Base.connection.execute("VACUUM ANALYZE #{table};")
    
    # Clean up old records
    if table == "solid_queue_jobs"
      # Delete old completed jobs (older than 7 days)
      count = ActiveRecord::Base.connection.execute("DELETE FROM #{table} WHERE finished_at IS NOT NULL AND finished_at < NOW() - INTERVAL '7 days';").cmd_tuples
      puts "  Deleted #{count} old completed jobs"
    end
    
    if table == "solid_queue_processes"
      # Delete stale processes
      count = ActiveRecord::Base.connection.execute("DELETE FROM #{table} WHERE last_heartbeat_at < NOW() - INTERVAL '1 hour';").cmd_tuples
      puts "  Deleted #{count} stale processes"
    end
  end
end

puts "\nDatabase optimization completed!"
