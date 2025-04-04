namespace :db do
  namespace :maintenance do
    desc "Perform database maintenance tasks"
    task :optimize => :environment do
      puts "Starting database maintenance tasks..."
      
      # Get the current database name
      db_name = ActiveRecord::Base.connection.current_database
      puts "Database: #{db_name}"
      
      # Vacuum analyze tables
      puts "\nVacuuming and analyzing tables..."
      tables = ActiveRecord::Base.connection.tables
      tables.each do |table|
        puts "Vacuuming and analyzing #{table}..."
        ActiveRecord::Base.connection.execute("VACUUM ANALYZE #{table};")
      end
      
      # Clean up SolidQueue tables
      puts "\nCleaning up SolidQueue tables..."
      if ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")
        # Delete old completed jobs (older than 7 days)
        count = ActiveRecord::Base.connection.execute("DELETE FROM solid_queue_jobs WHERE finished_at IS NOT NULL AND finished_at < NOW() - INTERVAL '7 days';").cmd_tuples
        puts "  Deleted #{count} old completed jobs"
      end
      
      if ActiveRecord::Base.connection.table_exists?("solid_queue_processes")
        # Delete stale processes
        count = ActiveRecord::Base.connection.execute("DELETE FROM solid_queue_processes WHERE last_heartbeat_at < NOW() - INTERVAL '1 hour';").cmd_tuples
        puts "  Deleted #{count} stale processes"
      end
      
      if ActiveRecord::Base.connection.table_exists?("solid_queue_failed_executions")
        # Get count of failed jobs
        failed_count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM solid_queue_failed_executions;").first["count"]
        puts "  Found #{failed_count} failed jobs"
      end
      
      # Clean up idle connections
      puts "\nCleaning up idle connections..."
      begin
        # Kill idle connections that have been idle for more than 5 minutes
        count = ActiveRecord::Base.connection.execute(<<-SQL).cmd_tuples
          SELECT pg_terminate_backend(pid) 
          FROM pg_stat_activity 
          WHERE datname = '#{db_name}' 
          AND pid <> pg_backend_pid()
          AND state = 'idle'
          AND (now() - state_change) > interval '5 minutes';
        SQL
        puts "  Terminated #{count} idle connections"
      rescue => e
        puts "  Error cleaning up idle connections: #{e.message}"
      end
      
      puts "\nDatabase maintenance completed!"
    end
    
    desc "Schedule regular database maintenance"
    task :schedule => :environment do
      if Rails.env.development?
        puts "Scheduling database maintenance tasks..."
        
        # Create a cron job to run the maintenance task daily
        cron_job = "0 3 * * * cd #{Rails.root} && bin/rails db:maintenance:optimize >> log/database_maintenance.log 2>&1"
        
        # Add the cron job
        system("(crontab -l 2>/dev/null | grep -v 'db:maintenance:optimize'; echo '#{cron_job}') | crontab -")
        
        puts "Database maintenance scheduled to run daily at 3:00 AM"
      else
        puts "This task is only available in development mode"
      end
    end
  end
end
