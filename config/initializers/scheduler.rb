require 'rufus-scheduler'

# Only run scheduler in production and skip for console, tests, and rake tasks
return unless Rails.env.production?
return if defined?(Rails::Console) || Rails.env.test? || File.split($PROGRAM_NAME).last == 'rake'

scheduler = Rufus::Scheduler.singleton

# Configure error handling for scheduled jobs
scheduler.stderr_logger = Rails.logger

scheduler.on_error do |job, error|
  Sentry.capture_exception(error, extra: { job: job.id, job_class: job.class.name }) if defined?(Sentry)
  Rails.logger.error(
    error: {
      job_id: job.id,
      job_class: job.class.name,
      error: {
        class: error.class.name,
        message: error.message,
        backtrace: error.backtrace&.first(5)
      }
    }.to_json
  )
end

# Schedule metrics cleanup job to run every 6 hours
scheduler.every '6h', overlap: false, first_in: '1m', timeout: '5m' do
  Rails.logger.info("Starting scheduled metrics cleanup")
  CleanMetricsDataJob.perform_later
end

# Recalculate course averages nightly during low-traffic hours
scheduler.cron '0 2 * * *', overlap: false, timeout: '30m' do
  Rails.logger.info("Starting nightly course average recalculation")
  Course.find_each do |course|
    RecalculateCourseAveragesJob.perform_later(course.id)
  end
end

# Monitor job queue health every 5 minutes
scheduler.every '5m', overlap: false, timeout: '30s' do
  begin
    stats = {
      timestamp: Time.current.iso8601,
      queues: SolidQueue::Queue.all.map { |q| [q.name, q.size] }.to_h,
      failed: SolidQueue::Job.where(executions: { failed_at: nil }).count,
      ready: SolidQueue::Job.ready.count,
      scheduled: SolidQueue::Job.scheduled.count,
      active_processes: SolidQueue::Process.active.count
    }

    Rails.logger.info("Queue stats: #{stats.to_json}")

    # Alert on potential issues
    if stats[:failed] > 50 || stats[:ready] > 1000
      Rails.logger.warn("Queue metrics exceeded thresholds: #{stats.to_json}")
      Sentry.capture_message("Queue metrics exceeded thresholds", 
        level: 'warning',
        extra: stats
      ) if defined?(Sentry)
    end
  rescue => e
    Rails.logger.error("Failed to collect queue stats: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end

# Clear expired cache entries daily
scheduler.cron '15 3 * * *', overlap: false, timeout: '1h' do
  Rails.logger.info("Starting daily cache cleanup")
  begin
    Rails.cache.cleanup
  rescue => e
    Rails.logger.error("Cache cleanup failed: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end

# Health check for scheduler
scheduler.every '1h', first_in: '1m', timeout: '30s' do
  Rails.logger.info(
    scheduler: {
      uptime: Time.now - scheduler.started_at,
      jobs: scheduler.jobs.size,
      threads: scheduler.work_threads.size,
      processed: scheduler.processed_count
    }.to_json
  )
end

# Schedule initial cleanup
CleanMetricsDataJob.perform_later

# Log scheduler startup
Rails.logger.info("Scheduler initialized with #{scheduler.jobs.size} jobs")

# Add this with your other scheduler jobs
scheduler.cron '0 4 * * *', overlap: false, timeout: '10m' do
  Rails.logger.info("Starting daily log cleanup")
  begin
    CleanupLogsJob.perform_later
  rescue => e
    Rails.logger.error("Log cleanup failed: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
