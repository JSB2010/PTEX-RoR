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
      # Clean up stale processes
      if defined?(SolidQueue::Process) && ActiveRecord::Base.connection.table_exists?('solid_queue_processes')
        Rails.logger.info "Cleaning up stale SolidQueue processes..."

        # Clean up processes from this host
        SolidQueue::Process.where(hostname: Socket.gethostname).find_each do |process|
          Rails.logger.info "Deregistering stale process: #{process.name} (#{process.id})"
          process.deregister
        end

        # Clean up old processes from any host
        SolidQueue::Process.where('last_heartbeat_at < ?', 5.minutes.ago).find_each do |process|
          Rails.logger.info "Deregistering old process: #{process.name} (#{process.id})"
          process.deregister
        end

        # Clean up claimed executions with no process
        SolidQueue::ClaimedExecution
          .joins('LEFT JOIN solid_queue_processes ON solid_queue_processes.id = process_id')
          .where('solid_queue_processes.id IS NULL')
          .delete_all

        # Clean up expired blocked executions
        SolidQueue::BlockedExecution.where('expires_at < ?', Time.current).delete_all
      end

      # Start SolidQueue processes in a background thread
      Thread.new do
        # Give Rails a moment to finish initializing
        sleep 3
        begin
          Rails.logger.info "Starting SolidQueue processes..."

          # Check disk space before starting
          disk_info = `df -h #{Rails.root}`.split("\n")[1].split(/\s+/)
          disk_usage_percent = disk_info[4].to_i

          if disk_usage_percent >= 90
            Rails.logger.warn "Disk space is critically low (#{disk_usage_percent}% used). This may cause issues with SolidQueue."
            Rails.logger.info "Cleaning up log files..."
            system("find #{Rails.root}/log -name \"*.log\" -size +10M -exec truncate -s 0 {} \;")

            Rails.logger.info "Cleaning up tmp directory..."
            system("find #{Rails.root}/tmp -type f -name \"*.log\" -o -name \"*.pid\" -o -name \"*.lock\" -mtime +1 -delete")
          end

          # Start SolidQueue with proper error handling
          pid = Process.spawn("#{Rails.root}/bin/start_solid_queue",
                             out: File.join(Rails.root, 'log', 'solid_queue.log'),
                             err: File.join(Rails.root, 'log', 'solid_queue.log'))
          Process.detach(pid)

          # Write PID to file
          pid_dir = File.join(Rails.root, 'tmp', 'pids')
          FileUtils.mkdir_p(pid_dir)
          File.write(File.join(pid_dir, 'solid_queue.pid'), pid.to_s)

          Rails.logger.info "SolidQueue started with PID: #{pid}"
        rescue => e
          Rails.logger.error "Failed to start SolidQueue: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      # Register shutdown hook
      at_exit do
        # Only clean up if this is the main thread
        if Thread.current == Thread.main
          begin
            Rails.logger.info "Shutting down SolidQueue processes..."
            system("bundle exec rake solid_queue:stop")
            # Clean up any orphaned SolidQueue processes
            if defined?(SolidQueue) && defined?(SolidQueue::Process)
              SolidQueue::Process.where(hostname: Socket.gethostname).destroy_all
            end
          rescue => e
            # Log error but don't prevent shutdown
            Rails.logger.error "Error cleaning up SolidQueue processes: #{e.message}"
          end
        end
      end
    rescue => e
      Rails.logger.error "Error initializing SolidQueue: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end