# frozen_string_literal: true

# Service to manage SolidQueue operations and status
class SolidQueueManager
  class << self
    # Get the status of SolidQueue
    def status
      begin
        # Check if SolidQueue is defined
        unless defined?(SolidQueue)
          return {
            status: "warning",
            error: "SolidQueue is not defined",
            queues: [],
            active_workers: 0,
            dispatcher_running: false
          }
        end

        # Check if SolidQueue tables exist
        unless ActiveRecord::Base.connection.table_exists?("solid_queue_processes")
          return {
            status: "warning",
            error: "SolidQueue tables not found",
            queues: [],
            active_workers: 0,
            dispatcher_running: false
          }
        end

        # Check for active processes
        active_processes = SolidQueue::Process.where('last_heartbeat_at > ?', 5.minutes.ago).count

        # Get queue information
        queues = SolidQueue::Queue.all.map do |queue|
          {
            name: queue.name,
            size: SolidQueue::Job.where(queue_name: queue.name).count,
            paused: queue.paused
          }
        end

        # Check for dispatcher process
        dispatcher_running = SolidQueue::Process.where('last_heartbeat_at > ?', 5.minutes.ago)
                                              .where(kind: 'dispatcher')
                                              .exists?

        # Check for worker processes
        worker_count = SolidQueue::Process.where('last_heartbeat_at > ?', 5.minutes.ago)
                                        .where(kind: 'worker')
                                        .count

        # Check PostgreSQL connection count
        pg_connections = check_pg_connections

        # Check disk space
        disk_space = check_disk_space

        # Determine status
        status = if !dispatcher_running || worker_count == 0
                   "error"
                 elsif pg_connections && pg_connections[:warning]
                   "warning"
                 elsif disk_space && disk_space[:warning]
                   "warning"
                 else
                   "ok"
                 end

        {
          status: status,
          queues: queues,
          active_workers: worker_count,
          dispatcher_running: dispatcher_running,
          pg_connections: pg_connections,
          disk_space: disk_space,
          pg_recommendations: pg_recommendations
        }
      rescue => e
        Rails.logger.error "Error checking SolidQueue status: #{e.message}"
        {
          status: "error",
          error: "Error checking status: #{e.message}",
          queues: [],
          active_workers: 0,
          dispatcher_running: false
        }
      end
    end

    # Initialize SolidQueue
    def initialize_solid_queue
      # Don't start in production without explicit configuration
      return false if Rails.env.production? && !ENV['ALLOW_AUTO_START_SOLID_QUEUE']

      # Check if SolidQueue is already running
      return true if status[:dispatcher_running] && status[:active_workers] > 0

      # Start SolidQueue
      Rails.logger.info "Starting SolidQueue..."

      # Start the dispatcher
      start_dispatcher

      # Start workers
      start_workers(2) # Start with 2 workers by default

      true
    rescue => e
      Rails.logger.error "Failed to initialize SolidQueue: #{e.message}"
      false
    end

    # Start the SolidQueue dispatcher
    def start_dispatcher
      Rails.logger.info "Starting SolidQueue dispatcher..."

      # Check if solid_queue command exists
      if command_exists?("solid_queue")
        # Use a separate process for the dispatcher
        pid = spawn("cd #{Rails.root} && bundle exec solid_queue dispatcher", out: File.join(Rails.root, 'log', 'solid_queue_dispatcher.log'), err: File.join(Rails.root, 'log', 'solid_queue_dispatcher.log'))
        Process.detach(pid)

        Rails.logger.info "SolidQueue dispatcher started with PID #{pid}"
        pid
      else
        # Fall back to using Rails runner
        Rails.logger.info "solid_queue command not found, using Rails runner instead"
        pid = spawn("cd #{Rails.root} && bundle exec rails runner 'SolidQueue::Dispatcher.new.start'", out: File.join(Rails.root, 'log', 'solid_queue_dispatcher.log'), err: File.join(Rails.root, 'log', 'solid_queue_dispatcher.log'))
        Process.detach(pid)

        Rails.logger.info "SolidQueue dispatcher started with Rails runner (PID #{pid})"
        pid
      end
    end

    # Start SolidQueue workers
    def start_workers(count = 2)
      Rails.logger.info "Starting #{count} SolidQueue workers..."

      pids = []
      count.times do |i|
        if command_exists?("solid_queue")
          # Use solid_queue command
          pid = spawn("cd #{Rails.root} && bundle exec solid_queue worker", out: File.join(Rails.root, 'log', "solid_queue_worker_#{i}.log"), err: File.join(Rails.root, 'log', "solid_queue_worker_#{i}.log"))
        else
          # Fall back to using Rails runner
          Rails.logger.info "solid_queue command not found, using Rails runner instead"
          pid = spawn("cd #{Rails.root} && bundle exec rails runner 'SolidQueue::Worker.new.start'", out: File.join(Rails.root, 'log', "solid_queue_worker_#{i}.log"), err: File.join(Rails.root, 'log', "solid_queue_worker_#{i}.log"))
        end
        Process.detach(pid)
        pids << pid
      end

      Rails.logger.info "SolidQueue workers started with PIDs #{pids.join(', ')}"
      pids
    end

    # Check if a command exists
    def command_exists?(command)
      system("which #{command} > /dev/null 2>&1")
    end

    # Stop all SolidQueue processes
    def stop_all
      Rails.logger.info "Stopping all SolidQueue processes..."

      # Find all SolidQueue processes
      processes = SolidQueue::Process.all

      # Mark them for shutdown
      processes.each do |process|
        process.update(shutdown: true)
      end

      # Wait for processes to shut down
      30.times do
        break if SolidQueue::Process.where('last_heartbeat_at > ?', 30.seconds.ago).count == 0
        sleep 1
      end

      # Force kill any remaining processes
      remaining = SolidQueue::Process.all
      if remaining.any?
        Rails.logger.warn "Forcefully removing #{remaining.count} SolidQueue processes that didn't shut down gracefully"
        remaining.delete_all
      end

      true
    rescue => e
      Rails.logger.error "Error stopping SolidQueue processes: #{e.message}"
      false
    end

    private

    # Check PostgreSQL connection count
    def check_pg_connections
      begin
        # Get current connection count
        result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity")
        connections = result.first["count"].to_i

        # Get max connections
        max_connections_result = ActiveRecord::Base.connection.execute("SHOW max_connections")
        max_connections = max_connections_result.first["max_connections"].to_i

        # Calculate percentage
        percentage = (connections.to_f / max_connections) * 100

        {
          current: connections,
          max: max_connections,
          percentage: percentage.round(1),
          warning: percentage > 80
        }
      rescue => e
        Rails.logger.error "Error checking PostgreSQL connections: #{e.message}"
        nil
      end
    end

    # Check disk space
    def check_disk_space
      begin
        # Get disk space for the database directory
        db_path = Rails.root.join('db').to_s
        df_output = `df -h #{db_path}`.split("\n")[1]
        parts = df_output.split

        # Parse output
        capacity = parts[4].gsub('%', '').to_i

        {
          path: db_path,
          percentage: capacity,
          warning: capacity > 80
        }
      rescue => e
        Rails.logger.error "Error checking disk space: #{e.message}"
        nil
      end
    end

    # PostgreSQL recommendations for SolidQueue
    def pg_recommendations
      {
        max_connections: 200,
        shared_buffers: "25% of RAM",
        work_mem: "16MB",
        maintenance_work_mem: "256MB",
        effective_cache_size: "75% of RAM",
        synchronous_commit: "off",
        wal_buffers: "16MB",
        checkpoint_timeout: "15min",
        random_page_cost: 1.1,
        effective_io_concurrency: 200
      }
    end
  end
end
