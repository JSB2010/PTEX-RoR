namespace :health do
  desc "Check the health of the application"
  task :check => :environment do
    puts "Checking application health..."

    # Check PostgreSQL
    puts "\nChecking PostgreSQL..."
    begin
      # Get the current database name
      db_name = ActiveRecord::Base.connection.current_database
      puts "  Database: #{db_name}"

      # Get connection count
      result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = '#{db_name}'")
      connections = result.first["count"].to_i

      # Get max connections
      max_connections_result = ActiveRecord::Base.connection.execute("SHOW max_connections")
      max_connections = max_connections_result.first["max_connections"].to_i

      # Calculate percentage
      percentage = (connections.to_f / max_connections) * 100

      puts "  Connections: #{connections}/#{max_connections} (#{percentage.round(1)}%)"

      if percentage > 80
        puts "  WARNING: PostgreSQL connections are high (#{percentage.round(1)}%)"
      else
        puts "  PostgreSQL connections are OK"
      end

      # Check for long-running queries
      long_queries = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT pid, now() - query_start AS duration, state, query
        FROM pg_stat_activity
        WHERE state != 'idle' AND now() - query_start > interval '5 seconds'
        ORDER BY duration DESC;
      SQL

      if long_queries.count > 0
        puts "  WARNING: Found #{long_queries.count} long-running queries"
        long_queries.each do |query|
          puts "    PID: #{query['pid']}, Duration: #{query['duration']}, State: #{query['state']}"
          puts "    Query: #{query['query'][0..100]}..."
        end
      else
        puts "  No long-running queries found"
      end
    rescue => e
      puts "  ERROR: #{e.message}"
    end

    # Check Redis
    puts "\nChecking Redis..."
    begin
      redis = Redis.new
      redis_info = redis.info
      puts "  Redis version: #{redis_info['redis_version']}"
      puts "  Connected clients: #{redis_info['connected_clients']}"
      puts "  Used memory: #{redis_info['used_memory_human']}"
      puts "  Redis is OK"
    rescue => e
      puts "  ERROR: #{e.message}"
    end

    # Check SolidQueue
    puts "\nChecking SolidQueue..."
    begin
      if defined?(SolidQueue)
        # Check for active processes
        workers = SolidQueue::Process.where(kind: ["Worker", "DirectWorker"])
                                   .where("last_heartbeat_at > ?", 5.minutes.ago)
                                   .count

        dispatcher = SolidQueue::Process.where(kind: "Dispatcher")
                                      .where("last_heartbeat_at > ?", 5.minutes.ago)
                                      .exists?

        puts "  Active workers: #{workers}"
        puts "  Dispatcher running: #{dispatcher}"

        if workers > 0 && dispatcher
          puts "  SolidQueue is OK"
        else
          puts "  WARNING: SolidQueue is not running properly"
        end

        # Check for failed jobs
        failed_jobs = SolidQueue::Job.where.not(failed_at: nil).count
        if failed_jobs > 0
          puts "  WARNING: Found #{failed_jobs} failed jobs"
        else
          puts "  No failed jobs found"
        end

        # Check for pending jobs
        pending_jobs = SolidQueue::Job.where(finished_at: nil, failed_at: nil).count
        puts "  Pending jobs: #{pending_jobs}"
      else
        puts "  SolidQueue is not defined"
      end
    rescue => e
      puts "  ERROR: #{e.message}"
    end

    # Check disk space
    puts "\nChecking disk space..."
    begin
      df_output = `df -h #{Rails.root}`.split("\n")[1]
      if df_output
        parts = df_output.split
        capacity = parts[4]
        total = parts[1]
        used = parts[2]
        available = parts[3]

        puts "  Disk space: #{used}/#{total} (#{capacity} used)"
        puts "  Available: #{available}"

        if capacity.to_i > 90
          puts "  WARNING: Disk space is critically low (#{capacity} used)"
        else
          puts "  Disk space is OK"
        end
      end
    rescue => e
      puts "  ERROR: #{e.message}"
    end

    puts "\nHealth check completed!"
  end
end
