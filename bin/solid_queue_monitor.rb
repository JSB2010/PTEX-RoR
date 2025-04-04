#!/usr/bin/env ruby
# Enhanced monitor script to ensure SolidQueue processes stay alive

require_relative '../config/environment'
require 'socket'

class SolidQueueSupervisor
  HEARTBEAT_INTERVAL = 10.seconds
  RECONNECT_INTERVAL = 5.seconds
  MAX_RETRY_ATTEMPTS = 3

  def initialize
    @hostname = Socket.gethostname
    @logger = Rails.logger
    @running = true
    @retry_count = 0
    @worker_process = nil
    @dispatcher_process = nil
    @worker = nil
    @dispatcher = nil
    @threads = []

    # Load queue configuration
    @config = load_queue_config

    # Set up signal handlers
    setup_signal_handlers
  end

  def start
    @logger.info "Starting SolidQueue supervisor..."

    # Clean up any stale processes
    cleanup_stale_processes

    # Register and start processes
    register_processes
    start_processes

    # Wait for all threads to finish (they should run forever)
    @logger.info "SolidQueue supervisor running, waiting for threads"
    @threads.each(&:join)
  rescue => e
    @logger.error "Supervisor error: #{e.message}"
    @logger.error e.backtrace.join("\n")

    if @retry_count < MAX_RETRY_ATTEMPTS
      @retry_count += 1
      @logger.info "Retrying in #{RECONNECT_INTERVAL} seconds (attempt #{@retry_count}/#{MAX_RETRY_ATTEMPTS})..."
      sleep RECONNECT_INTERVAL
      retry
    else
      @logger.error "Maximum retry attempts reached. Exiting."
      exit(1)
    end
  end

  private

  def load_queue_config
    config_file = Rails.root.join('config', 'queue.yml')
    if File.exist?(config_file)
      begin
        YAML.load_file(config_file, aliases: true)[Rails.env].deep_symbolize_keys
      rescue ArgumentError => e
        if e.message.include?('aliases')
          # Fall back to loading without aliases
          @logger.warn "Failed to load queue.yml with aliases, falling back to loading without aliases"
          YAML.load_file(config_file)[Rails.env].deep_symbolize_keys
        else
          raise
        end
      end
    else
      { polling_interval: 1.0, concurrency: 1, queues: ['default'] }
    end
  end

  def setup_signal_handlers
    # Handle process shutdown
    Signal.trap("INT") do
      handle_shutdown("INT")
    end

    Signal.trap("TERM") do
      handle_shutdown("TERM")
    end
  end

  def handle_shutdown(signal)
    @logger.info "Received #{signal} signal, shutting down..."
    @running = false

    # Deregister processes
    deregister_processes

    # Kill threads
    @threads.each { |t| t.exit if t.alive? }

    exit(0)
  end

  def cleanup_stale_processes
    @logger.info "Cleaning up stale processes..."

    # Clean up processes from this host
    SolidQueue::Process.where(hostname: @hostname).find_each do |process|
      @logger.info "Deregistering stale process: #{process.name} (#{process.id})"
      process.deregister
    end

    # Clean up old processes from any host
    SolidQueue::Process.where('last_heartbeat_at < ?', 5.minutes.ago).find_each do |process|
      @logger.info "Deregistering old process: #{process.name} (#{process.id})"
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

  def check_disk_space
    begin
      df_output = `df -k #{Rails.root}`.split("\n")[1]
      if df_output
        capacity = df_output.split[4].to_i
        @logger.info "Checking disk space... (#{capacity}% used)"

        if capacity > 90
          @logger.warn "Disk space is critically low (#{capacity}% used). This may cause issues with the application."
          # Clean up log files
          @logger.info "Cleaning up log files..."
          system("find #{Rails.root}/log -name \"*.log\" -size +10M -exec truncate -s 0 {} \;")

          @logger.info "Cleaning up tmp directory..."
          system("find #{Rails.root}/tmp -type f -name \"*.log\" -o -name \"*.pid\" -o -name \"*.lock\" -mtime +1 -delete")
        end
      end
      return capacity if df_output
    rescue => e
      @logger.error "Error checking disk space: #{e.message}"
    end
    return nil
  end

  def check_postgres_connections
    begin
      result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity")
      connections = result.first["count"].to_i

      max_connections_result = ActiveRecord::Base.connection.execute("SHOW max_connections")
      max_connections = max_connections_result.first["max_connections"].to_i

      percentage = (connections.to_f / max_connections) * 100
      @logger.info "PostgreSQL connections: #{connections}/#{max_connections} (#{percentage.round(1)}%)"

      if percentage > 80
        @logger.warn "PostgreSQL connections are high (#{percentage.round(1)}%). This may cause issues with the application."

        # Kill idle connections older than 10 minutes
        @logger.info "Killing idle connections older than 10 minutes..."
        ActiveRecord::Base.connection.execute(
          "SELECT pg_terminate_backend(pid) FROM pg_stat_activity " +
          "WHERE state = 'idle' AND (now() - state_change) > interval '10 minutes'"
        )
      end

      return percentage
    rescue => e
      @logger.error "Error checking PostgreSQL connections: #{e.message}"
    end
    return nil
  end

  def register_processes
    @logger.info "Registering SolidQueue processes..."

    # Register worker process
    @worker_process = SolidQueue::Process.register(
      kind: "Worker",
      name: "worker-#{SecureRandom.hex(8)}",
      hostname: @hostname,
      pid: Process.pid,
      metadata: {
        queues: @config[:queues] || ["default", "mailers", "active_storage", "maintenance"],
        polling_interval: @config[:polling_interval] || 2.0,
        batch_size: @config[:batch_size] || 50,
        threads: @config[:concurrency] || 1
      }
    )

    # Register dispatcher process
    @dispatcher_process = SolidQueue::Process.register(
      kind: "Dispatcher",
      name: "dispatcher-#{SecureRandom.hex(8)}",
      hostname: @hostname,
      pid: Process.pid,
      metadata: {
        polling_interval: @config[:polling_interval] || 2.0,
        batch_size: @config[:batch_size] || 50
      }
    )

    @logger.info "Registered worker: #{@worker_process.name} (#{@worker_process.id})"
    @logger.info "Registered dispatcher: #{@dispatcher_process.name} (#{@dispatcher_process.id})"
  end

  def start_processes
    begin
      # Check disk space before starting processes
      check_disk_space

      # Check PostgreSQL connections
      check_postgres_connections

      # Register processes if they don't exist
      register_worker_process if @worker_process.nil?
      register_dispatcher_process if @dispatcher_process.nil?

      # Create worker instance with reduced concurrency if disk space is low
      threads = @config[:concurrency] || 1
      if defined?(capacity) && capacity && capacity > 90
        threads = 1
        @logger.warn "Reducing worker concurrency to 1 due to low disk space"
      end

      @worker = SolidQueue::Worker.new(
        queues: @config[:queues] || ["default", "mailers", "active_storage", "maintenance"],
        polling_interval: @config[:polling_interval] || 2.0,
        batch_size: @config[:batch_size] || 50,
        threads: threads,
        name: @worker_process.name
      )

      # Create dispatcher instance
      @dispatcher = SolidQueue::Dispatcher.new(
        polling_interval: @config[:polling_interval] || 2.0,
        batch_size: @config[:batch_size] || 50,
        name: @dispatcher_process.name
      )

      # Start heartbeat thread
      @threads << Thread.new do
        Thread.current.name = "heartbeat"
        Thread.current.abort_on_exception = true
        run_heartbeat_thread
      end

      # Start worker thread
      @threads << Thread.new do
        Thread.current.name = "worker"
        Thread.current.abort_on_exception = true
        run_worker_thread
      end

      # Start dispatcher thread
      @threads << Thread.new do
        Thread.current.name = "dispatcher"
        Thread.current.abort_on_exception = true
        run_dispatcher_thread
      end
    rescue => e
      @logger.error "Error starting SolidQueue processes: #{e.message}"
      @logger.error e.backtrace.join("\n")
      raise
    end

    # Start monitoring thread
    @threads << Thread.new do
      Thread.current.name = "monitor"
      Thread.current.abort_on_exception = true
      run_monitor_thread
    end
  end

  def run_heartbeat_thread
    @logger.info "Starting heartbeat thread"

    while @running
      begin
        current_time = Time.current
        @worker_process.update!(last_heartbeat_at: current_time)
        @dispatcher_process.update!(last_heartbeat_at: current_time)

        # Log heartbeat every minute
        if (current_time.to_i % 60) < HEARTBEAT_INTERVAL
          @logger.debug "Heartbeat: #{current_time}"
        end

        sleep HEARTBEAT_INTERVAL
      rescue => e
        @logger.error "Heartbeat error: #{e.message}"
        @logger.error e.backtrace.join("\n")

        # Try to reconnect to the database
        begin
          ActiveRecord::Base.connection_pool.disconnect!
          ActiveRecord::Base.establish_connection
          @logger.info "Reconnected to database"
        rescue => reconnect_error
          @logger.error "Failed to reconnect: #{reconnect_error.message}"
        end

        sleep RECONNECT_INTERVAL
      end
    end
  end

  def run_worker_thread
    @logger.info "Starting worker thread"

    begin
      @worker.start
    rescue => e
      @logger.error "Worker error: #{e.message}"
      @logger.error e.backtrace.join("\n")
      raise # Let the supervisor handle the retry
    end
  end

  def run_dispatcher_thread
    @logger.info "Starting dispatcher thread"

    begin
      @dispatcher.start
    rescue => e
      @logger.error "Dispatcher error: #{e.message}"
      @logger.error e.backtrace.join("\n")
      raise # Let the supervisor handle the retry
    end
  end

  def run_monitor_thread
    @logger.info "Starting monitor thread"

    while @running
      begin
        # Check if worker and dispatcher are still registered and active
        worker_active = SolidQueue::Process.exists?(@worker_process.id)
        dispatcher_active = SolidQueue::Process.exists?(@dispatcher_process.id)

        unless worker_active && dispatcher_active
          @logger.error "Process registration lost. Worker: #{worker_active}, Dispatcher: #{dispatcher_active}"
          raise "Process registration lost"
        end

        sleep 30 # Check every 30 seconds
      rescue => e
        @logger.error "Monitor error: #{e.message}"
        @logger.error e.backtrace.join("\n")
        sleep RECONNECT_INTERVAL
      end
    end
  end

  def deregister_processes
    if @worker_process
      @logger.info "Deregistering worker: #{@worker_process.name}"
      @worker_process.deregister rescue nil
    end

    if @dispatcher_process
      @logger.info "Deregistering dispatcher: #{@dispatcher_process.name}"
      @dispatcher_process.deregister rescue nil
    end
  end
end

# Start the supervisor
SolidQueueSupervisor.new.start
