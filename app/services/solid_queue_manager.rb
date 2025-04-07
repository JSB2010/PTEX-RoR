# frozen_string_literal: true

# Service to manage SolidQueue operations and status
class SolidQueueManager
  # Cache status results for 30 seconds to reduce database queries
  CACHE_EXPIRY = 30.seconds
  @status_cache = {}
  @last_cache_time = nil

  class << self
    # Get the status of SolidQueue
    def status
      # Return cached status if available and not expired
      if @last_cache_time && Time.now - @last_cache_time < CACHE_EXPIRY
        return @status_cache
      end

      begin
        # Check if SolidQueue is defined
        unless defined?(SolidQueue)
          return cache_status({
            status: "warning",
            error: "SolidQueue is not defined",
            queues: [],
            active_workers: 0,
            dispatcher_running: false
          })
        end

        # Check if SolidQueue tables exist
        unless table_exists?("solid_queue_processes")
          return cache_status({
            status: "warning",
            error: "SolidQueue tables not found",
            queues: [],
            active_workers: 0,
            dispatcher_running: false
          })
        end

        # Get queue information - use a single query instead of multiple
        queues = get_queue_info

        # Get process information - use a single query instead of multiple
        process_info = get_process_info

        # Determine status
        status = if !process_info[:dispatcher_running] || process_info[:worker_count] == 0
                   "error"
                 elsif process_info[:pg_connections] && process_info[:pg_connections][:warning]
                   "warning"
                 elsif process_info[:disk_space] && process_info[:disk_space][:warning]
                   "warning"
                 else
                   "ok"
                 end

        # Build and cache the response
        cache_status({
          status: status,
          queues: queues,
          active_workers: process_info[:worker_count],
          dispatcher_running: process_info[:dispatcher_running],
          pg_connections: process_info[:pg_connections],
          disk_space: process_info[:disk_space]
        })
      rescue => e
        Rails.logger.error "Error checking SolidQueue status: #{e.message}"
        cache_status({
          status: "error",
          error: "Error checking status: #{e.message}",
          queues: [],
          active_workers: 0,
          dispatcher_running: false
        })
      end
    end

    # Initialize SolidQueue with optimized settings
    def initialize_solid_queue
      # Don't start in production without explicit configuration
      return false if Rails.env.production? && !ENV['ALLOW_AUTO_START_SOLID_QUEUE']

      # Check if SolidQueue is already running
      return true if status[:dispatcher_running] && status[:active_workers] > 0

      # Clean up any stale processes first
      clean_stale_processes

      # Start SolidQueue
      Rails.logger.info "Starting SolidQueue with optimized settings..."

      # Start the dispatcher with reduced concurrency
      dispatcher_pid = start_dispatcher

      # Start a single worker with reduced concurrency
      worker_pids = start_workers(1) # Start with just 1 worker to reduce resource usage

      # Return success if either dispatcher or workers started
      !!(dispatcher_pid || worker_pids&.any?)
    rescue => e
      Rails.logger.error "Failed to initialize SolidQueue: #{e.message}"
      false
    end

    # Start the SolidQueue dispatcher with optimized settings
    def start_dispatcher
      Rails.logger.info "Starting SolidQueue dispatcher with optimized settings..."

      # Use Rails runner with optimized settings
      pid = spawn("cd #{Rails.root} && bundle exec rails runner 'SolidQueue::Dispatcher.new(concurrency: 1, polling_interval: 5).start'",
                  out: File.join(Rails.root, 'log', 'solid_queue_dispatcher.log'),
                  err: File.join(Rails.root, 'log', 'solid_queue_dispatcher.log'))
      Process.detach(pid)

      # Save the PID for later cleanup
      File.write(File.join(Rails.root, 'tmp', 'pids', 'solid_queue_dispatcher.pid'), pid.to_s)

      Rails.logger.info "SolidQueue dispatcher started with PID #{pid}"
      pid
    end

    # Start SolidQueue workers with optimized settings
    def start_workers(count = 1)
      Rails.logger.info "Starting #{count} SolidQueue workers with optimized settings..."

      pids = []
      count.times do |i|
        # Use Rails runner with optimized settings
        pid = spawn("cd #{Rails.root} && bundle exec rails runner 'SolidQueue::Worker.new(concurrency: 1).start'",
                    out: File.join(Rails.root, 'log', "solid_queue_worker_#{i}.log"),
                    err: File.join(Rails.root, 'log', "solid_queue_worker_#{i}.log"))
        Process.detach(pid)
        pids << pid

        # Save the PID for later cleanup
        File.write(File.join(Rails.root, 'tmp', 'pids', "solid_queue_worker_#{i}.pid"), pid.to_s)
      end

      Rails.logger.info "SolidQueue workers started with PIDs #{pids.join(', ')}"
      pids
    end

    # Clean up stale processes
    def clean_stale_processes
      begin
        # Clean up stale processes in the database
        if defined?(SolidQueue::Process) && table_exists?("solid_queue_processes")
          ActiveRecord::Base.connection.execute("DELETE FROM solid_queue_processes WHERE last_heartbeat_at < NOW() - INTERVAL '1 hour'")
          Rails.logger.info "Cleaned up stale SolidQueue processes in the database"
        end

        # Kill any existing SolidQueue processes
        system('pkill -f "SolidQueue::Dispatcher"')
        system('pkill -f "SolidQueue::Worker"')
        Rails.logger.info "Cleaned up any existing SolidQueue processes"
      rescue => e
        Rails.logger.error "Failed to clean up stale SolidQueue processes: #{e.message}"
      end
    end

    # Stop all SolidQueue processes
    def stop_all
      Rails.logger.info "Stopping all SolidQueue processes..."

      # Find all SolidQueue processes
      return false unless table_exists?("solid_queue_processes")

      # Mark all processes for shutdown
      ActiveRecord::Base.connection.execute("UPDATE solid_queue_processes SET shutdown = true")

      # Wait for processes to shut down (with timeout)
      shutdown_complete = false
      10.times do
        count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM solid_queue_processes WHERE last_heartbeat_at > NOW() - INTERVAL '30 seconds'")
        if count.to_i == 0
          shutdown_complete = true
          break
        end
        sleep 1
      end

      # Force remove any remaining processes
      unless shutdown_complete
        Rails.logger.warn "Forcefully removing SolidQueue processes that didn't shut down gracefully"
        ActiveRecord::Base.connection.execute("DELETE FROM solid_queue_processes")
      end

      # Kill any remaining processes
      system('pkill -f "SolidQueue::Dispatcher"')
      system('pkill -f "SolidQueue::Worker"')

      # Remove PID files
      Dir.glob(File.join(Rails.root, 'tmp', 'pids', 'solid_queue_*.pid')).each do |pid_file|
        File.delete(pid_file) if File.exist?(pid_file)
      end

      true
    rescue => e
      Rails.logger.error "Error stopping SolidQueue processes: #{e.message}"
      false
    end

    private

    # Cache the status response
    def cache_status(status_hash)
      @status_cache = status_hash
      @last_cache_time = Time.now
      status_hash
    end

    # Check if a table exists safely
    def table_exists?(table_name)
      ActiveRecord::Base.connection.table_exists?(table_name)
    rescue
      false
    end

    # Get queue information efficiently
    def get_queue_info
      return [] unless table_exists?("solid_queue_queues") && table_exists?("solid_queue_jobs")

      # Get all queues with job counts in a single query
      queue_data = ActiveRecord::Base.connection.select_all("""
        SELECT q.name, q.paused, COUNT(j.id) as job_count
        FROM solid_queue_queues q
        LEFT JOIN solid_queue_jobs j ON j.queue_name = q.name
        GROUP BY q.name, q.paused
      """)

      queue_data.map do |row|
        {
          name: row['name'],
          size: row['job_count'].to_i,
          paused: row['paused'] == 't' || row['paused'] == true
        }
      end
    rescue => e
      Rails.logger.error "Error getting queue info: #{e.message}"
      []
    end

    # Get process information efficiently
    def get_process_info
      result = {
        worker_count: 0,
        dispatcher_running: false,
        pg_connections: check_pg_connections,
        disk_space: check_disk_space
      }

      return result unless table_exists?("solid_queue_processes")

      # Get process counts in a single query
      process_data = ActiveRecord::Base.connection.select_one("""
        SELECT
          COUNT(CASE WHEN kind = 'worker' AND last_heartbeat_at > NOW() - INTERVAL '5 minutes' THEN 1 END) as worker_count,
          COUNT(CASE WHEN kind = 'dispatcher' AND last_heartbeat_at > NOW() - INTERVAL '5 minutes' THEN 1 END) as dispatcher_count
        FROM solid_queue_processes
      """)

      result[:worker_count] = process_data['worker_count'].to_i
      result[:dispatcher_running] = process_data['dispatcher_count'].to_i > 0

      result
    rescue => e
      Rails.logger.error "Error getting process info: #{e.message}"
      result
    end

    # Check PostgreSQL connection count
    def check_pg_connections
      # Use a cached value if checked recently
      return @pg_connections_cache if @pg_connections_cache && @pg_connections_cache_time && Time.now - @pg_connections_cache_time < 60

      begin
        # Get current connection count and max connections in a single query
        result = ActiveRecord::Base.connection.select_one("""
          SELECT
            (SELECT COUNT(*) FROM pg_stat_activity) as connection_count,
            (SELECT setting FROM pg_settings WHERE name = 'max_connections') as max_connections
        """)

        connections = result['connection_count'].to_i
        max_connections = result['max_connections'].to_i

        # Calculate percentage
        percentage = max_connections > 0 ? (connections.to_f / max_connections) * 100 : 0

        # Cache the result
        @pg_connections_cache = {
          current: connections,
          max: max_connections,
          percentage: percentage.round(1),
          warning: percentage > 80
        }
        @pg_connections_cache_time = Time.now

        @pg_connections_cache
      rescue => e
        Rails.logger.error "Error checking PostgreSQL connections: #{e.message}"
        nil
      end
    end

    # Check disk space
    def check_disk_space
      # Use a cached value if checked recently
      return @disk_space_cache if @disk_space_cache && @disk_space_cache_time && Time.now - @disk_space_cache_time < 300

      begin
        # Get disk space for the database directory
        db_path = Rails.root.join('db').to_s
        df_output = `df -h #{db_path}`.split("\n")[1]
        parts = df_output.split

        # Parse output
        capacity = parts[4].gsub('%', '').to_i

        # Cache the result
        @disk_space_cache = {
          path: db_path,
          percentage: capacity,
          warning: capacity > 80
        }
        @disk_space_cache_time = Time.now

        @disk_space_cache
      rescue => e
        Rails.logger.error "Error checking disk space: #{e.message}"
        nil
      end
    end
  end
end
