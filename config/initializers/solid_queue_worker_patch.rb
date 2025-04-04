# frozen_string_literal: true

# Custom worker patch to improve job processing and logging
module SolidQueue
  class Worker
    attr_reader :thread_pool

    def initialize(queues:, threads:, polling_interval:, name:, batch_size: nil, logger: nil)
      @queues = queues
      @thread_count = threads
      @polling_interval = polling_interval
      @batch_size = batch_size || 100
      @name = name
      @logger = logger || Rails.logger
      @running = true
      @thread_pool = Concurrent::FixedThreadPool.new(threads)
    end

    def start
      @threads = @thread_count.times.map do |i|
        Thread.new do
          while @running
            begin
              process_next_batch
            rescue => e
              @logger.error("Worker thread #{i} error: #{e.message}")
              sleep @polling_interval
            end
          end
        end
      end
      @threads.each(&:join)
    end

    def stop
      @running = false
      @threads&.each(&:exit)
      @thread_pool.shutdown
    end

    private

    def process_next_batch
      jobs = fetch_jobs
      return sleep(@polling_interval) if jobs.empty?

      jobs.each do |job|
        @thread_pool.post do
          begin
            @logger.info("Processing job #{job.id} (#{job.class_name})")
            perform_job(job)
            job.update!(finished_at: Time.current)
          rescue => error
            @logger.error("Error processing job #{job.id}: #{error.message}")
            @logger.error(error.backtrace.join("\n"))
            job.mark_as_failed(error.inspect)
          ensure
            job.claimed_execution&.destroy
          end
        end
      end
    end

    def fetch_jobs
      SolidQueue::Job.transaction do
        ready_jobs = if @queues.include?("*")
          SolidQueue::ReadyExecution.claim(@batch_size)
        else
          @queues.flat_map { |queue| SolidQueue::ReadyExecution.claim(@batch_size, queue) }
        end
        ready_jobs.map(&:job)
      end
    end

    def perform_job(job)
      Rails.application.reloader.wrap do
        @logger.info("Starting job execution for #{job.class_name} (ID: #{job.id})")
        
        if job.active_job_id.present?
          perform_active_job(job)
        else
          perform_plain_job(job)
        end
      end
    rescue => e
      @logger.error("Job execution failed: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
      raise
    end

    def perform_active_job(job)
      @logger.info("Processing ActiveJob: #{job.class_name} with ID #{job.active_job_id}")
      serialized_job = {
        "job_class" => job.class_name,
        "job_id" => job.active_job_id,
        "provider_job_id" => job.id,
        "queue_name" => job.queue_name || "default",
        "priority" => nil,
        "arguments" => JSON.parse(job.arguments || "[]"),
        "executions" => 0,
        "exception_executions" => {},
        "locale" => I18n.locale || "en",
        "timezone" => Time.zone&.name || "UTC",
        "enqueued_at" => Time.current.iso8601(6),
        "scheduled_at" => nil
      }

      @logger.info("Job data prepared: #{serialized_job.inspect}")
      
      Rails.application.executor.wrap do
        job_instance = job.class_name.constantize.new
        # Set up logging context before job execution
        ActiveSupport::TaggedLogging.new(Rails.logger).tagged(
          job_instance.class.name,
          job.active_job_id
        ) do
          job_instance.deserialize(serialized_job)
          job_instance.perform_now
        end
      end
      
      @logger.info("Successfully completed job #{job.id}")
    end

    def perform_plain_job(job)
      args = JSON.parse(job.arguments || "[]")
      klass = job.class_name.constantize
      method_name = job.method_name || "perform"

      if method_name && klass.respond_to?(method_name)
        klass.public_send(method_name, *args)
      elsif klass.instance_methods.include?(:perform)
        klass.new.perform(*args)
      else
        raise NoMethodError, "No '#{method_name}' method found on #{job.class_name}"
      end
    end
  end
end