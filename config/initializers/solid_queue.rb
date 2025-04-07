# frozen_string_literal: true

require 'yaml'
require 'socket'
require 'erb'

# We always want to initialize SolidQueue for the 'rails server' command
# The script that starts the server will handle starting the SolidQueue processes

# Configure ActiveJob adapter
if ENV['ACTIVE_JOB_ADAPTER'] == 'inline' || ENV['SKIP_SOLID_QUEUE'] == 'true'
  Rails.logger.info "Using inline adapter for ActiveJob as requested by environment variables"
  Rails.application.config.active_job.queue_adapter = :inline
else
  Rails.application.config.active_job.queue_adapter = :solid_queue
end

# Load and parse queue configuration
QUEUE_CONFIG = begin
  config_file = Rails.root.join('config', 'queue.yml')
  if File.exist?(config_file)
    YAML.load_file(config_file, aliases: true)[Rails.env].deep_symbolize_keys
  else
    { polling_interval: 1.0, concurrency: 5, queues: ['default'] }
  end
end

module SolidQueue
  mattr_accessor :logger
  mattr_accessor :error_handlers
  mattr_accessor :process_heartbeat_interval
  mattr_accessor :stale_process_threshold

  self.logger = Rails.logger
  self.error_handlers = []
  self.process_heartbeat_interval = 15.seconds
  self.stale_process_threshold = 5.minutes

  def self.on_fork(&block)
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
    logger.info("Worker process forked", pid: Process.pid)
  end

  def self.error_handler(&block)
    error_handlers << block
  end

  def self.notify_error(error, context = {})
    error_handlers.each do |handler|
      begin
        handler.call(error, context)
      rescue => e
        logger.error "Error handler failed: #{e.class} - #{e.message}"
      end
    end
  end

  if defined?(Sentry)
    error_handler do |error, context|
      Sentry.set_context('solid_queue', context)
      Sentry.capture_exception(error)
    end
  end

  # Connection handling module
  module ConnectionHandling
    def with_connection_handling
      pool = ActiveRecord::Base.connection_pool
      pool.with_connection { yield }
    rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
      Rails.logger.error "Database connection error: #{e.message}"
      ActiveRecord::Base.connection_pool.disconnect!
      ActiveRecord::Base.establish_connection
      retry
    end
  end

  # Add to Worker and Dispatcher
  if defined?(SolidQueue::Worker)
    SolidQueue::Worker.class_eval do
      prepend ConnectionHandling
    end
  end

  if defined?(SolidQueue::Dispatcher)
    SolidQueue::Dispatcher.class_eval do
      prepend ConnectionHandling
    end
  end
end

# Cleanup stale processes and initialize SolidQueue on application boot
Rails.application.config.after_initialize do
  # Only run in server mode, not in console or tests
  if (defined?(Rails::Server) || defined?(Puma)) && !Rails.env.test? && !defined?(Rails::Console)
    begin
      # Initialize SolidQueue in a separate thread to avoid blocking the main thread
      Thread.new do
        begin
          # Give Rails a moment to finish initializing
          sleep 3

          # Clean up stale processes
          if defined?(SolidQueue::Process) && ActiveRecord::Base.connection.table_exists?('solid_queue_processes')
            Rails.logger.info "Cleaning up stale SolidQueue processes..."

            # First, clean up any orphaned processes from this host
            hostname = Socket.gethostname
            Rails.logger.info "Cleaning up processes for host: #{hostname}"

            # Clean up processes from this host
            SolidQueue::Process.where(hostname: hostname).find_each do |process|
              Rails.logger.info "Deregistering stale process: #{process.name} (#{process.id})"
              process.deregister
            end

            # Clean up old processes from any host
            SolidQueue::Process.where('last_heartbeat_at < ?', 5.minutes.ago).find_each do |process|
              Rails.logger.info "Deregistering old process: #{process.name} (#{process.id})"
              process.deregister
            end

            # Clean up claimed executions with no process
            orphaned_count = SolidQueue::ClaimedExecution
              .joins('LEFT JOIN solid_queue_processes ON solid_queue_processes.id = process_id')
              .where('solid_queue_processes.id IS NULL')
              .delete_all
            Rails.logger.info "Cleaned up #{orphaned_count} orphaned executions"

            # Clean up expired blocked executions
            expired_count = SolidQueue::BlockedExecution.where('expires_at < ?', Time.current).delete_all
            Rails.logger.info "Cleaned up #{expired_count} expired blocked executions"

            # Process any ready jobs that might be stuck
            ready_count = SolidQueue::ReadyExecution.count
            if ready_count > 0
              Rails.logger.info "Found #{ready_count} ready jobs waiting to be processed"
            end
          end

          # Check disk space before starting
          begin
            df_output = `df -h #{Rails.root}`
            if df_output.present? && df_output.split("\n").length > 1
              disk_info = df_output.split("\n")[1].split(/\s+/)
              disk_usage_percent = disk_info[4].to_i

              if disk_usage_percent >= 90
                Rails.logger.warn "Disk space is critically low (#{disk_usage_percent}% used). This may cause issues with SolidQueue."
                Rails.logger.info "Cleaning up log files..."
                system("find #{Rails.root}/log -name \"*.log\" -size +10M -exec truncate -s 0 {} \;")

                Rails.logger.info "Cleaning up tmp directory..."
                system("find #{Rails.root}/tmp -type f -name \"*.log\" -o -name \"*.pid\" -o -name \"*.lock\" -mtime +1 -delete")
              end
            else
              Rails.logger.warn "Could not determine disk usage. Skipping disk space check."
            end
          rescue => e
            Rails.logger.error "Error checking disk space: #{e.message}"
          end

          # Start SolidQueue with proper error handling
          Rails.logger.info "Starting SolidQueue processes..."

          # First, check if database is available
          database_available = false
          begin
            # Try a simple query to check if database is available
            ActiveRecord::Base.connection.execute("SELECT 1")
            database_available = true
          rescue => e
            Rails.logger.warn "Database not available: #{e.message}"
            Rails.logger.warn "Will start SolidQueue in no-db mode"
          end

          if database_available
            # Use the resilient script if database is available
            script_path = File.join(Rails.root, 'bin', 'resilient-solid-queue')
          else
            # Use the no-db script if database is not available
            script_path = File.join(Rails.root, 'bin', 'no-db-solid-queue')
          end

          if File.exist?(script_path)
            # Make sure the script is executable
            File.chmod(0755, script_path) rescue nil

            # Start the script in a separate process
            pid = Process.spawn(script_path,
                               out: File.join(Rails.root, 'log', 'solid_queue.log'),
                               err: File.join(Rails.root, 'log', 'solid_queue.log'))
            Process.detach(pid)

            # Write PID to file
            pid_dir = File.join(Rails.root, 'tmp', 'pids')
            FileUtils.mkdir_p(pid_dir)
            File.write(File.join(pid_dir, 'solid_queue.pid'), pid.to_s)

            # Wait a moment for the processes to start
            sleep 5

            Rails.logger.info "SolidQueue started with PID: #{pid}"
          else
            Rails.logger.error "SolidQueue script not found at #{script_path}. SolidQueue will not be started."
          end
        rescue => e
          Rails.logger.error "Error initializing SolidQueue: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      # Register shutdown hook
      at_exit do
        # Only clean up if this is the main thread
        if Thread.current == Thread.main
          begin
            Rails.logger.info "Shutting down SolidQueue processes..."

            # Use the resilient stop script
            stop_script = File.join(Rails.root, 'bin', 'stop-resilient-solid-queue')
            if File.exist?(stop_script)
              # Make sure the script is executable
              File.chmod(0755, stop_script) rescue nil

              # Run the script
              system(stop_script)
            else
              # Fallback to manual cleanup

              # First try to kill processes using PID files
              pid_dir = File.join(Rails.root, 'tmp', 'pids')
              ['solid_queue.pid', 'solid_queue_dispatcher.pid', 'solid_queue_worker.pid'].each do |pid_file|
                full_path = File.join(pid_dir, pid_file)
                if File.exist?(full_path)
                  begin
                    pid = File.read(full_path).to_i
                    if pid > 0
                      begin
                        Process.kill('TERM', pid)
                        Rails.logger.info "Sent TERM signal to process #{pid} (#{pid_file})"
                        # Give it a moment to shut down gracefully
                        sleep 1
                      rescue Errno::ESRCH
                        Rails.logger.info "Process #{pid} not found"
                      end
                    end
                  rescue => e
                    Rails.logger.error "Error killing process from #{pid_file}: #{e.message}"
                  end
                end
              end

              # Then use pkill as a fallback
              system("pkill -f 'SolidQueue::' || true")
              system("pkill -f 'solid_queue:' || true")

              # Clean up any orphaned SolidQueue processes in the database
              if defined?(SolidQueue) && defined?(SolidQueue::Process)
                begin
                  SolidQueue::Process.where(hostname: Socket.gethostname).destroy_all
                rescue => e
                  Rails.logger.error "Error cleaning up SolidQueue processes in database: #{e.message}"
                end
              end
            end
          rescue => e
            # Log error but don't prevent shutdown
            Rails.logger.error "Error cleaning up SolidQueue processes: #{e.message}"
          end
        end
      end
    rescue => e
      Rails.logger.error "Error setting up SolidQueue: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end