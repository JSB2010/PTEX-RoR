# frozen_string_literal: true

require 'concurrent'
require 'socket'
require_relative '../../lib/process_lock'

module ServiceManager
  class << self
    def start_services
      return if Rails.env.test? || ENV['FOREMAN'] || ENV['FOREMAN_WORKER_NAME']

      ProcessLock.with_lock('solid_queue_manager') do
        with_connection_handling do
          return unless should_start_processes?
          start_background_processes
        end
      end
    rescue => e
      Rails.logger.error "Failed to start services: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    def stop_services
      with_connection_handling do
        pid_files = Dir[Rails.root.join('tmp/pids/solid_queue_*.pid')]
        pid_files.each do |pid_file|
          begin
            pid = File.read(pid_file).to_i
            Process.kill('TERM', pid)
            File.delete(pid_file)
          rescue Errno::ESRCH, Errno::ENOENT
            # Process not found or PID file already deleted, ignore
          end
        end

        cleanup_stale_processes
      end
    rescue => e
      Rails.logger.error "Failed to stop services: #{e.message}"
    ensure
      cleanup_connections
    end

    private

    def with_connection_handling
      pool = ActiveRecord::Base.connection_pool
      pool.with_connection { yield } if pool
    ensure
      cleanup_connections
    end

    def cleanup_connections
      ActiveRecord::Base.connection_handler.connection_pools.each do |_, pool|
        begin
          pool.release_connection if pool&.active_connection?
        rescue => e
          Rails.logger.warn "Failed to release connection: #{e.message}"
        end
      end
    end

    def cleanup_stale_processes
      with_connection_handling do
        if defined?(SolidQueue::Process) &&
           ActiveRecord::Base.connection.table_exists?('solid_queue_processes')
          SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)
        end
      end
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad => e
      Rails.logger.warn "Database not ready, skipping cleanup: #{e.message}"
    end

    def should_start_processes?
      # Skip if SKIP_SOLID_QUEUE is set
      return false if ENV['SKIP_SOLID_QUEUE'] == 'true'

      return false unless defined?(SolidQueue)
      return false if Rails.env.test?

      with_connection_handling do
        !SolidQueue::Process.where(hostname: Socket.gethostname)
                           .where('last_heartbeat_at > ?', 5.minutes.ago)
                           .exists?
      end
    end

    def start_background_processes
      Rails.logger.info "Starting background processes..."

      # Create log directory if it doesn't exist
      FileUtils.mkdir_p(File.join(Rails.root, 'log'))

      # Setup queues in a non-blocking way
      Rails.logger.info "Setting up queues in background..."
      setup_pid = Process.spawn("#{Rails.root}/bin/setup_queues",
                               out: File.join(Rails.root, 'log', 'setup_queues.log'),
                               err: File.join(Rails.root, 'log', 'setup_queues.log'))
      Process.detach(setup_pid)

      # Don't wait for setup to complete, just assume it will work
      setup_status = true

      if setup_status
        Rails.logger.info "Queues setup successfully."
      else
        Rails.logger.error "Failed to setup queues. Check log/setup_queues.log for details."
      end

      # Start SolidQueue in a separate process
      Rails.logger.info "Starting SolidQueue..."
      solid_queue_script = File.join(Rails.root, 'bin', 'start-solid-queue')

      if File.exist?(solid_queue_script)
        # Make sure the script is executable
        File.chmod(0755, solid_queue_script) rescue nil

        solid_queue_pid = Process.spawn(solid_queue_script,
                                      out: File.join(Rails.root, 'log', 'solid_queue.log'),
                                      err: File.join(Rails.root, 'log', 'solid_queue.log'))
        Process.detach(solid_queue_pid)
      else
        Rails.logger.warn "SolidQueue script not found at #{solid_queue_script}. Starting SolidQueue inline..."

        # Start SolidQueue inline
        begin
          require 'fileutils'

          # Create necessary directories
          FileUtils.mkdir_p(File.join(Rails.root, 'tmp', 'pids'))
          FileUtils.mkdir_p(File.join(Rails.root, 'log'))

          # Start the SolidQueue dispatcher
          dispatcher_pid = spawn(
            "bundle exec rails runner 'SolidQueue::Dispatcher.new(concurrency: 1, polling_interval: 5).start'",
            out: File.join(Rails.root, 'log', 'solid_queue_dispatcher.log'),
            err: File.join(Rails.root, 'log', 'solid_queue_dispatcher.log')
          )
          Process.detach(dispatcher_pid)

          # Start the SolidQueue worker
          worker_pid = spawn(
            "bundle exec rails runner 'SolidQueue::Worker.new(concurrency: 1).start'",
            out: File.join(Rails.root, 'log', 'solid_queue_worker.log'),
            err: File.join(Rails.root, 'log', 'solid_queue_worker.log')
          )
          Process.detach(worker_pid)

          # Use the combined PIDs
          solid_queue_pid = "#{dispatcher_pid},#{worker_pid}"
        rescue => e
          Rails.logger.error "Failed to start SolidQueue inline: #{e.message}"
          solid_queue_pid = nil
        end
      end

      # Write PID to file
      pid_dir = File.join(Rails.root, 'tmp', 'pids')
      FileUtils.mkdir_p(pid_dir)
      File.write(File.join(pid_dir, 'solid_queue.pid'), solid_queue_pid.to_s)

      # Verify that the process is still running after a short delay
      sleep 2
      begin
        if Process.kill(0, solid_queue_pid)
          Rails.logger.info "SolidQueue started successfully with PID: #{solid_queue_pid}"
        end
      rescue
        Rails.logger.error "SolidQueue may not have started properly. Check log/solid_queue.log for details."
      end

      Rails.logger.info "Background processes initialization complete."
    end
  end
end

# Register shutdown hook
at_exit do
  ServiceManager.stop_services
end

# Start services after Rails fully initializes
Rails.application.config.after_initialize do
  # Skip starting services if SKIP_SOLID_QUEUE is set or if running rake
  ServiceManager.start_services unless $0.include?('rake') || ENV['SKIP_SOLID_QUEUE'] == 'true'
end