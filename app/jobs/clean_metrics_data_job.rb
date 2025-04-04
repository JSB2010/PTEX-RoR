class CleanMetricsDataJob < ApplicationJob
  queue_as :maintenance

  def perform(options = {})
    Rails.logger.info "Starting metrics cleanup at #{Time.current}"

    cleanup_old_metrics
    cleanup_orphaned_tags
    compact_course_metrics

    Rails.logger.info "Cleanup completed at #{Time.current}"
  end

  private

  def cleanup_old_metrics
    cutoff_time = 1.week.ago.to_i
    pattern = "metrics:*:#{(cutoff_time / 300) - 1}"
    Rails.cache.delete_matched(pattern)
  end

  def cleanup_orphaned_tags
    metric_keys = Rails.cache.redis.keys("metrics:*").reject { |k| k.end_with?(":tags") }
    tag_keys = Rails.cache.redis.keys("metrics:*:tags")
    
    tag_keys.each do |tag_key|
      metric_key = tag_key.sub(/:tags$/, '')
      Rails.cache.delete(tag_key) unless metric_keys.include?(metric_key)
    end
  end

  def compact_course_metrics
    Course.find_each do |course|
      # Compact hits/misses into daily totals
      compact_counter_metrics(course, "cache_hits")
      compact_counter_metrics(course, "cache_misses")
      
      # Compact calculation times into averages
      compact_calculation_metrics(course)
    end
  end

  def compact_counter_metrics(course, metric_type)
    key_pattern = "metrics:course:#{course.id}:#{metric_type}"
    total = 0
    
    Rails.cache.redis.keys("#{key_pattern}:*").each do |key|
      value = Rails.cache.read(key).to_i
      total += value
      Rails.cache.delete(key)
    end
    
    daily_key = "#{key_pattern}:#{Date.current.to_s}"
    Rails.cache.write(daily_key, total, expires_in: 30.days)
  end

  def compact_calculation_metrics(course)
    pattern = "metrics:statistics_calculation_time:*"
    cutoff_time = 24.hours.ago.to_i / 300
    
    metrics = Rails.cache.redis.keys(pattern).select do |key|
      timestamp = key.split(':').last.to_i
      timestamp < cutoff_time
    end

    return if metrics.empty?

    values = metrics.map { |key| Rails.cache.read(key).to_f }
    avg = values.sum / values.size
    
    Rails.cache.write(
      "metrics:course:#{course.id}:daily_avg_calculation_time:#{Date.current.to_s}",
      avg.round(2),
      expires_in: 30.days
    )
    
    metrics.each { |key| Rails.cache.delete(key) }
  end
end