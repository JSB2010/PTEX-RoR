module StatisticsMetrics
  extend ActiveSupport::Concern

  class_methods do
    def track_metric(name, value, tags = {})
      Rails.logger.info(
        metric: {
          name: name,
          value: value,
          tags: tags,
          timestamp: Time.current
        }.to_json
      )

      metric_key = "metrics:#{name}:#{Time.current.to_i / 300}"
      cache_key = "#{name}:#{tags.to_json}"

      Rails.cache.write_multi({
        metric_key => value,
        "#{metric_key}:tags" => tags
      }, expires_in: 1.day)
    end
  end

  private

  def measure_performance
    start_time = Time.current
    result = yield
    duration = (Time.current - start_time) * 1000 # Convert to milliseconds

    self.class.track_metric('statistics_calculation_time', duration, {
      course_id: id,
      calculation_type: caller_locations(1,1)[0].label,
      student_count: students.count
    })

    result
  end

  def track_cache_hit(hit)
    metric_name = hit ? 'cache_hits' : 'cache_misses'
    
    self.class.track_metric("statistics_#{metric_name}", 1, {
      course_id: id,
      cache_key: "#{cache_key_with_version}/stats"
    })

    # Update aggregate counters atomically
    Rails.cache.increment("metrics:course:#{id}:#{metric_name}")
  end

  def with_error_handling
    yield
  rescue StandardError => e
    self.class.track_metric('statistics_errors', 1, {
      course_id: id,
      error_type: e.class.name,
      error_message: e.message
    })
    raise
  end
end