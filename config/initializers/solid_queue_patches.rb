# frozen_string_literal: true

module SolidQueue
  class Process < ActiveRecord::Base
    self.table_name = "solid_queue_processes"

    validates :kind, :name, presence: true

    def self.register(kind:, name:, metadata: {}, pid: nil, hostname: nil, supervisor: nil)
      create!(
        kind: kind,
        name: name,
        hostname: hostname || Socket.gethostname,
        pid: pid || ::Process.pid,
        last_heartbeat_at: Time.current,
        metadata: metadata.is_a?(String) ? metadata : metadata.to_json
      )
    end

    def deregister
      destroy if persisted?
    end

    def heartbeat!
      update!(last_heartbeat_at: Time.current)
    end

    def metadata
      value = super
      return {} if value.nil?
      value.is_a?(String) ? JSON.parse(value) : value
    end
  end

  # Base module for common process functionality
  module ProcessManagement
    def setup_signal_handlers
      @stop_signal_received = false
      trap("TERM") { @stop_signal_received = true }
      trap("INT") { @stop_signal_received = true }
    end

    def should_stop?
      @stop_signal_received
    end

    def cleanup
      deregister_process
      ActiveRecord::Base.connection_pool.disconnect!
    end

    def register_process(kind)
      @process_record = SolidQueue::Process.register(
        kind: kind,
        name: @name || "#{kind}_#{SecureRandom.hex(6)}",
        metadata: {}
      )
    end

    def deregister_process
      @process_record&.deregister
    end

    def heartbeat
      return unless @process_record
      @process_record.heartbeat!
    rescue => e
      Rails.logger.error "Heartbeat error: #{e.message}"
    end
  end

  # Safe database connection handling
  module SafeDatabase
    def with_safe_connection
      ActiveRecord::Base.connection_pool.disconnect!
      ActiveRecord::Base.establish_connection
      yield
    ensure
      ActiveRecord::Base.connection_pool.disconnect!
    end
  end

  # Job processing improvements
  module JobProcessing
    def process_job(job)
      return unless job

      serialized_args = job.arguments.is_a?(String) ? JSON.parse(job.arguments) : job.arguments
      job.update(arguments: serialized_args.to_json) unless job.arguments.is_a?(String)

      super
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse job arguments: #{e.message}"
      job.fail!("Invalid job arguments: #{e.message}")
    rescue => e
      Rails.logger.error "Job processing error: #{e.message}\n#{e.backtrace.join("\n")}"
      job.fail!("#{e.class}: #{e.message}")
    end
  end

  # Worker process improvements
  class Worker
    prepend ProcessManagement
    prepend JobProcessing

    alias_method :original_initialize, :initialize
    def initialize(queues: ["default"], threads: 5, polling_interval: 0.1, name: nil)
      @name = name
      original_initialize(queues: queues, threads: threads, polling_interval: polling_interval)
    end

    def start
      setup_signal_handlers
      @logger = Rails.logger

      ActiveRecord::Base.connection_pool.with_connection do
        register_process("worker")
        @logger.info "Starting SolidQueue worker #{@name} with queues=#{@queues.inspect}"

        until should_stop?
          begin
            heartbeat
            poll
            sleep(1) unless should_stop?
          rescue => e
            @logger.error "Worker error: #{e.message}\n#{e.backtrace.join("\n")}"
            sleep(1) unless should_stop?
          end
        end
      end
    ensure
      cleanup
    end

    def poll
      @thread_pool.ready_workers.each do |worker|
        next unless job = next_job

        begin
          job.arguments = JSON.parse(job.arguments) if job.arguments.is_a?(String)
          worker.perform(job)
        rescue JSON::ParserError => e
          @logger.error "Failed to parse job arguments: #{e.message}"
          job.fail!("Invalid job arguments: #{e.message}")
        rescue => e
          @logger.error "Job processing error: #{e.message}"
          job.fail!("#{e.class}: #{e.message}")
        end
      end
    end
  end

  # Dispatcher process improvements
  class Dispatcher
    prepend ProcessManagement
    prepend SafeDatabase

    # Simple initialize method that works with all SolidQueue versions
    def initialize(polling_interval: 0.1, batch_size: 100, name: nil, **kwargs)
      @name = name
      @polling_interval = polling_interval
      @batch_size = batch_size
      @logger = Rails.logger
      @running = true
    end

    def start
      setup_signal_handlers
      @logger = Rails.logger

      ActiveRecord::Base.connection_pool.with_connection do
        register_process("dispatcher")
        @logger.info "Starting SolidQueue dispatcher #{@name} with interval=#{@polling_interval}"

        until should_stop?
          begin
            heartbeat
            poll
            sleep(1) unless should_stop?
          rescue => e
            @logger.error "Dispatcher error: #{e.message}\n#{e.backtrace.join("\n")}"
            sleep(1) unless should_stop?
          end
        end
      end
    ensure
      cleanup
    end

    def poll(batch = nil)
      return [] if should_stop?

      begin
        results = []

        # Handle method name differences between SolidQueue versions
        if respond_to?(:dispatch_scheduled_jobs)
          results.concat(dispatch_scheduled_jobs)
        elsif respond_to?(:dispatch_scheduled)
          results.concat(dispatch_scheduled)
        end

        if respond_to?(:dispatch_recurring_jobs)
          results.concat(dispatch_recurring_jobs)
        elsif respond_to?(:dispatch_recurring)
          results.concat(dispatch_recurring)
        end

        if respond_to?(:cleanup_stale_jobs)
          results.concat(cleanup_stale_jobs)
        end

        sleep(@polling_interval) if results.empty? && !should_stop?
        results
      rescue => e
        @logger.error "Dispatcher poll error: #{e.message}\n#{e.backtrace.join("\n")}"
        []
      end
    end
  end
end