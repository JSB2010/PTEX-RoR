# frozen_string_literal: true

require 'solid_queue'

module SolidQueue
  class DispatcherRunner
    DISPATCH_BATCH_SIZE = 100
    MAX_ERRORS = 50
    ERROR_RESET_INTERVAL = 300 # 5 minutes

    def initialize
      @error_count = 0
      @last_error_reset = Time.current
      @metrics = {
        dispatched_jobs: 0,
        failed_dispatches: 0,
        last_dispatch_time: nil
      }
    end

    def run
      # Ensure clean database connections
      ActiveRecord::Base.connection_pool.disconnect!
      ActiveRecord::Base.establish_connection

      @running = true
      @process = register_process

      setup_signal_handlers
      run_dispatcher_loop
    ensure
      cleanup
    end

    private

    def register_process
      SolidQueue::Process.create!(
        kind: "Dispatcher",
        name: "dispatcher-#{SecureRandom.hex(6)}",
        hostname: Socket.gethostname,
        pid: Process.pid,
        metadata: {
          batch_size: DISPATCH_BATCH_SIZE,
          started_at: Time.current
        }
      )
    end

    def setup_signal_handlers
      Signal.trap("TERM") { handle_shutdown_signal("TERM") }
      Signal.trap("INT") { handle_shutdown_signal("INT") }
    end

    def handle_shutdown_signal(signal)
      Rails.logger.info "Dispatcher received #{signal} signal, shutting down..."
      @running = false
    end

    def run_dispatcher_loop
      Rails.logger.info "Starting SolidQueue dispatcher process..."
      
      while @running
        begin
          heartbeat
          dispatch_jobs
          report_metrics if should_report_metrics?
          sleep(ENV.fetch('SOLID_QUEUE_POLLING_INTERVAL', 0.1).to_f)
        rescue => e
          handle_error(e)
        end
      end
    end

    def dispatch_jobs
      results = []
      
      ActiveRecord::Base.transaction do
        results.concat(dispatch_scheduled_jobs)
        results.concat(dispatch_recurring_jobs)
        results.concat(cleanup_stale_jobs)
      end

      process_dispatch_results(results)
    end

    def dispatch_scheduled_jobs
      SolidQueue::ScheduledExecution
        .where('scheduled_at <= ?', Time.current)
        .limit(DISPATCH_BATCH_SIZE)
        .with_advisory_lock
        .map { |execution| ready_execution(execution) }
    end

    def dispatch_recurring_jobs
      SolidQueue::RecurringExecution
        .where('next_run_at <= ?', Time.current)
        .limit(DISPATCH_BATCH_SIZE)
        .with_advisory_lock
        .map { |execution| ready_execution(execution) }
    end

    def cleanup_stale_jobs
      expired = Time.current - 24.hours
      SolidQueue::Job
        .where('finished_at < ? OR failed_at < ?', expired, expired)
        .limit(DISPATCH_BATCH_SIZE)
        .destroy_all
    end

    def ready_execution(execution)
      SolidQueue::ReadyExecution.create!(
        job: execution.job,
        queue_name: execution.queue_name
      )
      execution.destroy
      @metrics[:dispatched_jobs] += 1
      @metrics[:last_dispatch_time] = Time.current
    rescue => e
      Rails.logger.error "Failed to ready execution #{execution.id}: #{e.message}"
      @metrics[:failed_dispatches] += 1
      nil
    end

    def heartbeat
      @process.update!(last_heartbeat_at: Time.current)
    end

    def handle_error(error)
      Rails.logger.error "Dispatcher error: #{error.class} - #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      @error_count += 1
      if Time.current - @last_error_reset >= ERROR_RESET_INTERVAL
        @error_count = 0 
        @last_error_reset = Time.current
      end

      if @error_count >= MAX_ERRORS
        Rails.logger.error "Error threshold exceeded, shutting down dispatcher..."
        @running = false
      end
      
      sleep(1) # Prevent tight error loops
    end

    def should_report_metrics?
      @metrics[:last_report_time].nil? || 
        Time.current - @metrics[:last_report_time] >= 60 # Report every minute
    end

    def report_metrics
      Rails.logger.info "Dispatcher metrics: dispatched=#{@metrics[:dispatched_jobs]} failed=#{@metrics[:failed_dispatches]}"
      @metrics[:last_report_time] = Time.current
    end

    def cleanup
      @process&.deregister if @process&.persisted?
      ActiveRecord::Base.connection_pool.disconnect!
    end
  end
end

# Start the dispatcher if this file is run directly
if __FILE__ == $0
  SolidQueue::DispatcherRunner.new.run
end