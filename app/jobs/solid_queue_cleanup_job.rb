# frozen_string_literal: true

class SolidQueueCleanupJob < ApplicationJob
  queue_as :maintenance
  PROCESS_TIMEOUT = 30.seconds

  def perform
    Rails.logger.info "Starting SolidQueue cleanup at #{Time.current}"

    cleanup_metrics = {
      stale_processes: cleanup_stale_processes,
      stale_executions: cleanup_stale_executions,
      orphaned_jobs: cleanup_orphaned_jobs,
      failed_jobs: analyze_failed_jobs
    }

    Rails.logger.info "Cleanup complete: #{cleanup_metrics.inspect}"

    # Alert if there are concerning patterns
    alert_on_issues(cleanup_metrics)
  end

  private

  def cleanup_stale_processes
    count = 0
    SolidQueue::Process.where('last_heartbeat_at < ?', PROCESS_TIMEOUT.ago).find_each do |process|
      process.deregister
      count += 1
    end
    count
  end

  def cleanup_stale_executions
    SolidQueue::Job.transaction do
      claimed_count = SolidQueue::ClaimedExecution
        .joins('LEFT JOIN solid_queue_processes ON solid_queue_processes.id = process_id')
        .where('solid_queue_processes.id IS NULL OR solid_queue_processes.last_heartbeat_at < ?', PROCESS_TIMEOUT.ago)
        .count

      blocked_count = SolidQueue::BlockedExecution
        .where('expires_at < ?', Time.current)
        .count

      # Move stale claimed jobs back to ready state
      SolidQueue::ClaimedExecution
        .joins('LEFT JOIN solid_queue_processes ON solid_queue_processes.id = process_id')
        .where('solid_queue_processes.id IS NULL OR solid_queue_processes.last_heartbeat_at < ?', PROCESS_TIMEOUT.ago)
        .find_each do |execution|
          begin
            SolidQueue::Job.transaction do
              execution.job.create_ready_execution!(
                queue_name: execution.job.queue_name,
                priority: execution.job.priority
              )
              execution.destroy
            end
          rescue => e
            Rails.logger.error "Error reclaiming job #{execution.job_id}: #{e.message}"
          end
        end

      # Clean up expired blocked executions
      SolidQueue::BlockedExecution
        .where('expires_at < ?', Time.current)
        .destroy_all

      { claimed: claimed_count, blocked: blocked_count }
    end
  end

  def cleanup_orphaned_jobs
    count = 0
    SolidQueue::Job
      .where('created_at < ?', 1.day.ago)
      .where(finished_at: nil)
      .where.not(id: SolidQueue::ReadyExecution.select(:job_id))
      .where.not(id: SolidQueue::ScheduledExecution.select(:job_id))
      .where.not(id: SolidQueue::ClaimedExecution.select(:job_id))
      .where.not(id: SolidQueue::BlockedExecution.select(:job_id))
      .find_each do |job|
        job.update!(finished_at: Time.current, failed_at: Time.current)
        job.create_failed_execution!(error: "Job orphaned and marked as failed by cleanup")
        count += 1
      end
    count
  end

  def analyze_failed_jobs
    failed_jobs = SolidQueue::Job
      .where('failed_at > ?', 24.hours.ago)
      .group(:class_name)
      .count

    # Record failure rates for monitoring
    failed_jobs.each do |class_name, count|
      Rails.cache.write(
        "solid_queue:failure_rate:#{class_name}:#{Date.current}",
        count,
        expires_in: 7.days
      )
    end

    failed_jobs
  end

  def alert_on_issues(metrics)
    return unless defined?(Sentry)

    total_failed = metrics[:failed_jobs].values.sum
    if total_failed > 50
      Sentry.capture_message(
        "High number of failed jobs in last 24h: #{total_failed}",
        level: 'warning',
        extra: {
          failed_jobs: metrics[:failed_jobs],
          cleanup_metrics: metrics
        }
      )
    end

    if metrics[:orphaned_jobs] > 10
      Sentry.capture_message(
        "High number of orphaned jobs: #{metrics[:orphaned_jobs]}",
        level: 'warning',
        extra: { cleanup_metrics: metrics }
      )
    end
  end
end