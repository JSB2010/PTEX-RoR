# frozen_string_literal: true

ActiveSupport.on_load(:active_job) do
  class ApplicationJob < ActiveJob::Base
    # Add retry functionality
    retry_on StandardError, wait: :exponentially_longer, attempts: 3
    
    around_perform do |_job, block|
      ActiveRecord::Base.connection_pool.with_connection do
        block.call
      end
    ensure
      ActiveRecord::Base.connection_pool.release_connection if ActiveRecord::Base.connection_pool.active_connection?
    end

    rescue_from StandardError do |error|
      Rails.logger.error "Job failed: #{self.class.name} (#{job_id})"
      Rails.logger.error "Error: #{error.class} - #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      # Log to Sentry if available
      if defined?(Sentry)
        Sentry.set_context('job', {
          job_class: self.class.name,
          job_id: job_id,
          queue_name: queue_name,
          arguments: arguments
        })
        Sentry.capture_exception(error)
      end
      
      raise # Re-raise to let SolidQueue handle the failure
    end

    before_perform do |job|
      Rails.logger.info "Starting job: #{job.class.name} (#{job.job_id})"
      Rails.logger.info "Arguments: #{job.arguments.inspect}"
      @job_start_time = Time.current
    end

    after_perform do |job|
      duration = Time.current - @job_start_time
      Rails.logger.info "Completed job: #{job.class.name} (#{job.job_id}) in #{duration.round(2)}s"
    end
  end
end