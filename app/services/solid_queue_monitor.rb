# frozen_string_literal: true

class SolidQueueMonitor
  HEALTH_CHECK_INTERVAL = 30  # seconds
  PROCESS_TIMEOUT = 30.seconds
  MAX_RESTART_ATTEMPTS = 3

  class << self
    def start
      new.start
    end
  end

  def initialize
    @restart_attempts = 0
    @running = true
    @config = load_configuration
  end

  def start
    Rails.logger.info "Starting SolidQueue monitor..."
    setup_signal_handlers

    register_processes

    while @running
      with_connection_handling do
        check_health
        cleanup_stale_processes
      end
      sleep HEALTH_CHECK_INTERVAL
    end
  rescue => e
    Rails.logger.error "Monitor error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    retry if should_retry?
  ensure
    cleanup
  end

  private

  def with_connection_handling
    ActiveRecord::Base.connection_pool.with_connection { yield }
  ensure
    ActiveRecord::Base.clear_active_connections!
  end

  def cleanup
    with_connection_handling do
      @worker_process&.deregister if @worker_process&.persisted?
      @dispatcher_process&.deregister if @dispatcher_process&.persisted?
    end
  end

  def load_configuration
    config_file = Rails.root.join('config', 'queue.yml')
    if File.exist?(config_file)
      YAML.load_file(config_file, aliases: true)[Rails.env].deep_symbolize_keys
    else
      {
        polling_interval: 0.5,
        concurrency: 5,
        queues: ['default', 'mailers', 'active_storage', 'maintenance'],
        dispatcher: {
          polling_interval: 0.5,
          batch_size: 100
        }
      }
    end
  rescue => e
    Rails.logger.error "Failed to load queue configuration: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Return default configuration if loading fails
    {
      polling_interval: 0.5,
      concurrency: 5,
      queues: ['default'],
      dispatcher: {
        polling_interval: 0.5,
        batch_size: 100
      }
    }
  end

  def register_processes
    Rails.logger.info "Registering SolidQueue processes..."

    with_connection_handling do
      @worker_process = SolidQueue::Process.register(
        kind: "Worker",
        name: "worker-#{SecureRandom.hex(6)}",
        metadata: {
          queues: @config[:queues],
          polling_interval: @config[:polling_interval],
          batch_size: @config[:batch_size],
          threads: @config[:concurrency]
        }.to_json
      )

      @dispatcher_process = SolidQueue::Process.register(
        kind: "Dispatcher",
        name: "dispatcher-#{SecureRandom.hex(6)}",
        metadata: {
          polling_interval: @config.dig(:dispatcher, :polling_interval),
          batch_size: @config.dig(:dispatcher, :batch_size)
        }.to_json
      )

      Rails.logger.info "Registered worker process: #{@worker_process.name}"
      Rails.logger.info "Registered dispatcher process: #{@dispatcher_process.name}"
    end
  end

  def check_health
    Rails.logger.info "Performing health check..."

    worker_count = SolidQueue::Process.where(kind: "Worker")
                                    .where("last_heartbeat_at > ?", PROCESS_TIMEOUT.ago)
                                    .count

    dispatcher_count = SolidQueue::Process.where(kind: "Dispatcher")
                                        .where("last_heartbeat_at > ?", PROCESS_TIMEOUT.ago)
                                        .count

    if worker_count == 0 || dispatcher_count == 0
      Rails.logger.error "Missing processes - Workers: #{worker_count}, Dispatchers: #{dispatcher_count}"
      attempt_restart if should_attempt_restart?
    end

    # Check for stuck jobs with proper connection handling
    stuck_jobs = SolidQueue::Job.joins(:claimed_execution)
                               .where("solid_queue_jobs.created_at < ?", 1.hour.ago)
                               .where(finished_at: nil)
                               .where(failed_at: nil)
                               .limit(100)  # Limit to prevent memory issues

    if stuck_jobs.any?
      Rails.logger.warn "Found #{stuck_jobs.count} potentially stuck jobs"
      stuck_jobs.each do |job|
        Rails.logger.info "Stuck job: #{job.id} (#{job.class_name})"
      end
    end
  end

  def cleanup_stale_processes
    count = SolidQueue::Process.where("last_heartbeat_at < ?", PROCESS_TIMEOUT.ago).destroy_all.count
    Rails.logger.info "Cleaned up #{count} stale processes" if count > 0
  end

  def should_attempt_restart?
    @restart_attempts < MAX_RESTART_ATTEMPTS
  end

  def attempt_restart
    @restart_attempts += 1
    Rails.logger.info "Attempting to restart SolidQueue processes (attempt #{@restart_attempts}/#{MAX_RESTART_ATTEMPTS})"

    system("bundle exec rake solid_queue:stop")
    sleep 2
    system("bundle exec rake solid_queue:start")
  end

  def should_retry?
    true
  end

  def setup_signal_handlers
    Signal.trap("TERM") { @running = false }
    Signal.trap("INT") { @running = false }
  end
end

