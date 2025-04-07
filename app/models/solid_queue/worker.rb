# frozen_string_literal: true

module SolidQueue
  class Worker
    include SolidQueue::Processes::Registrable
    include SolidQueue::Processes::Runnable

    attr_reader :thread_pool, :logger

    MAX_ERROR_COUNT = 100
    ERROR_RESET_INTERVAL = 300 # 5 minutes

    def initialize(queues:, threads:, polling_interval:, name:, logger: nil, batch_size: 100)
      @queues = Array(queues)
      @thread_count = threads.to_i
      @polling_interval = polling_interval.to_f
      @batch_size = batch_size.to_i
      @name = name
      @logger = logger || Rails.logger
      @running = true
      @thread_pool = Concurrent::FixedThreadPool.new(@thread_count)
      @error_counts = Concurrent::Hash.new(0)
      @last_error_reset = Time.current
      @metrics = {
        processed_jobs: 0,
        failed_jobs: 0,
        last_job_time: nil
      }
    end

    def start
      @logger.info "Starting SolidQueue worker #{@name} with #{@thread_count} threads"
      register_process("worker")

      @threads = @thread_count.times.map do |i|
        Thread.new do
          Thread.current.name = "worker-#{i}"
          while @running
            begin
              process_next_batch
              report_metrics if should_report_metrics?
            rescue => e
              handle_error(e)
            end
          end
        end
      end

      @threads.each(&:join)
    ensure
      cleanup
    end

    def stop
      @logger.info "Stopping SolidQueue worker..."
      @running = false
      @threads&.each { |t| t.exit }
      @thread_pool.shutdown
      @thread_pool.wait_for_termination(5)
      deregister_process
    end

    private

    def process_next_batch
      jobs = fetch_jobs
      return sleep(@polling_interval) if jobs.empty?

      jobs.each do |job|
        @thread_pool.post do
          perform_single_job(job)
        end
      end
    end

    def perform_single_job(job)
      @logger.info("Processing job #{job.id} (#{job.class_name})")
      start_time = Time.current

      begin
        perform_job(job)
        job.update!(finished_at: Time.current, failed_at: nil)
        log_success(job, start_time)
        @metrics[:processed_jobs] += 1
        @metrics[:last_job_time] = Time.current
      rescue => error
        handle_job_error(job, error)
        @metrics[:failed_jobs] += 1
      ensure
        cleanup_job(job)
      end
    end

    def perform_job(job)
      if job.active_job_id.present?
        perform_active_job(job)
      else
        perform_plain_job(job)
      end
    end

    def perform_active_job(job)
      active_job = job.class_name.constantize.new
      active_job.deserialize(
        "job_class" => job.class_name,
        "job_id" => job.active_job_id,
        "provider_job_id" => job.id,
        "queue_name" => job.queue_name,
        "arguments" => job.arguments
      )
      active_job.perform_now
    end

    def perform_plain_job(job)
      args = JSON.parse(job.arguments || "[]")
      klass = job.class
      # Perform the job with the given arguments
    end

    def handle_job_error(job, error)
      @logger.error("Job #{job.id} failed: #{error.class} - #{error.message}")
      @logger.error(error.backtrace.join("\n"))

      job.update!(
        error_message: error.message,
        error_class: error.class.name,
        failed_at: Time.current,
        error_backtrace: error.backtrace&.join("\n")
      )

      # Track error count for circuit breaking
      track_error
    end

    def track_error
      reset_error_counts if should_reset_error_counts?

      @error_counts[Thread.current.name] += 1
      if @error_counts[Thread.current.name] >= MAX_ERROR_COUNT
        @logger.error "Thread #{Thread.current.name} exceeded error threshold, stopping..."
        Thread.current.exit
      end
    end

    def should_reset_error_counts?
      Time.current - @last_error_reset >= ERROR_RESET_INTERVAL
    end

    def reset_error_counts
      @error_counts.clear
      @last_error_reset = Time.current
    end

    def should_report_metrics?
      @metrics[:last_report_time].nil? ||
        Time.current - @metrics[:last_report_time] >= 60 # Report every minute
    end

    def report_metrics
      @logger.info "Worker metrics: processed=#{@metrics[:processed_jobs]} failed=#{@metrics[:failed_jobs]}"
      @metrics[:last_report_time] = Time.current
    end

    def cleanup_job(job)
      ActiveRecord::Base.clear_active_connections!
    end

    def fetch_jobs
      SolidQueue::ReadyExecution
        .where(queue_name: @queues)
        .limit(@batch_size)
        .with_advisory_lock
        .includes(:job)
        .to_a
        .map(&:job)
        .compact
    rescue => e
      @logger.error "Error fetching jobs: #{e.message}"
      []
    end
  end
end