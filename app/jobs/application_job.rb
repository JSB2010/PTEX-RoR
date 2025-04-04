class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
  
  # Retry database connection errors with exponential backoff
  retry_on ActiveRecord::ConnectionNotEstablished, wait: :exponentially_longer, attempts: 5
  
  # Handle database timeout errors
  retry_on ActiveRecord::ConnectionTimeoutError, wait: :exponentially_longer, attempts: 3
  
  # Retry on general database errors with a delay
  retry_on ActiveRecord::StatementInvalid, wait: 5.seconds, attempts: 3
  
  # Handle transient Redis errors
  retry_on Redis::ConnectionError, wait: :exponentially_longer, attempts: 3
  retry_on Redis::TimeoutError, wait: 5.seconds, attempts: 3
  
  # Global error handling
  rescue_from StandardError do |exception|
    # Log the error
    Rails.logger.error(
      error: {
        job: self.class.name,
        arguments: arguments,
        error: {
          class: exception.class.name,
          message: exception.message,
          backtrace: exception.backtrace&.first(5)
        }
      }.to_json
    )
    
    # Report to error monitoring service if configured
    Sentry.capture_exception(exception) if defined?(Sentry)
    
    # Re-raise the error for the job to handle or fail
    raise
  end

  private

  def handle_job_error(error)
    case error
    when ActiveRecord::RecordNotFound
      # Skip retries for missing records
      nil
    when Redis::BaseError
      # Skip retries for Redis errors in development
      raise if Rails.env.development?
      retry_job wait: 5.seconds if attempts < 3
    else
      retry_job wait: (attempts ** 4) + 2 if attempts < 3
    end
  end
end
