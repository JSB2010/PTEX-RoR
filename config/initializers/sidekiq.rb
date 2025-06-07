# frozen_string_literal: true

# Simple, clean Sidekiq configuration
Rails.application.configure do
  # Configure ActiveJob adapter
  if ENV['ACTIVE_JOB_ADAPTER'] == 'inline' || ENV['SKIP_SIDEKIQ'] == 'true'
    Rails.logger.info "Using inline adapter for ActiveJob"
    config.active_job.queue_adapter = :inline
  else
    Rails.logger.info "Using Sidekiq adapter for ActiveJob"
    config.active_job.queue_adapter = :sidekiq
  end
end

