# frozen_string_literal: true

class MetricsExporterService
  class << self
    def collect_metrics
      @registry ||= Prometheus::Client.registry
      
      collect_course_metrics
      collect_job_metrics
      collect_cache_metrics
      collect_system_metrics
      collect_calculation_metrics

      true # Return true to indicate successful collection
    rescue => e
      Rails.logger.error("Prometheus metrics collection failed: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
      false
    end

    def reset_metrics
      @registry ||= Prometheus::Client.registry
      @registry.metrics.each(&:reset)
    end

    private

    def collect_course_metrics
      @registry.get(:course_total)&.set(Course.count)
      
      Course.find_each do |course|
        today = Date.current.to_s
        calc_time_key = "metrics:course:#{course.id}:daily_avg_calculation_time:#{today}"
        
        if (calc_time = Rails.cache.read(calc_time_key))
          @registry.get(:course_calculation_time_seconds)&.set(
            calc_time / 1000.0, # Convert ms to seconds
            labels: { course_name: course.name }
          )
        end
      end
    end

    def collect_job_metrics
      total_jobs = SolidQueue::Job.count
      @registry.get(:job_count)&.set(total_jobs)
      
      failed_count = SolidQueue::Job.joins(:failed_execution).count
      @registry.get(:failed_jobs_total)&.set(failed_count)

      # Add queue-specific metrics
      SolidQueue::Job.distinct.pluck(:queue_name).each do |queue_name|
        pending = SolidQueue::Job.where(queue_name: queue_name, finished_at: nil).count
        @registry.get(:job_queue_size)&.set(
          pending,
          labels: { queue_name: queue_name }
        )
      end
    end

    def collect_cache_metrics
      today = Date.current.to_s
      total_hits = 0
      total_misses = 0

      Course.find_each do |course|
        hits = Rails.cache.read("metrics:course:#{course.id}:cache_hits:#{today}").to_i
        misses = Rails.cache.read("metrics:course:#{course.id}:cache_misses:#{today}").to_i
        
        total_hits += hits
        total_misses += misses
      end

      total = total_hits + total_misses
      ratio = total.zero? ? 0 : (total_hits.to_f / total * 100)
      @registry.get(:cache_hit_ratio)&.set(ratio)
    end

    def collect_system_metrics
      memory = `ps -o rss= -p #{Process.pid}`.to_i * 1024 # Convert KB to bytes
      @registry.get(:memory_usage_bytes)&.set(memory)
    end

    def collect_calculation_metrics
      error_pattern = "metrics:statistics_errors:*"
      error_keys = []
      
      # Get Redis connection from the pool and fetch keys
      Rails.cache.redis.with do |redis_conn|
        error_keys = redis_conn.keys(error_pattern)
      end

      error_keys.each do |key|
        count = Rails.cache.read(key)
        tags = Rails.cache.read("#{key}:tags")
        next unless count && tags

        course = Course.find_by(id: tags[:course_id])
        next unless course

        @registry.get(:course_calculation_errors_total)&.set(
          count,
          labels: {
            course_name: course.name,
            error_type: tags[:error_type]
          }
        )
      end
    end
  end
end