require 'test_helper'

class MetricsExporterServiceTest < ActiveSupport::TestCase
  def setup
    @course = courses(:math)
    @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
    @redis.flushdb
    Rails.cache.clear
    MetricsExporterService.reset_metrics
  end

  test "exports course calculation time metrics" do
    # Simulate calculation time
    today = Date.current.to_s
    Rails.cache.write(
      "metrics:course:#{@course.id}:daily_avg_calculation_time:#{today}",
      150.0
    )

    MetricsExporterService.collect_metrics
    
    metric = Prometheus::Client.registry.get(:course_calculation_time_seconds)
    value = metric.get(labels: { course_name: @course.name })
    assert_in_delta 0.15, value, 0.001 # Converting ms to seconds
  end

  test "exports cache hit/miss metrics" do
    today = Date.current.to_s
    Rails.cache.write("metrics:course:#{@course.id}:cache_hits:#{today}", 10)
    Rails.cache.write("metrics:course:#{@course.id}:cache_misses:#{today}", 5)

    MetricsExporterService.collect_metrics

    hits = Prometheus::Client.registry.get(:course_cache_hits_total)
    misses = Prometheus::Client.registry.get(:course_cache_misses_total)

    assert_equal 10, hits.get(labels: { course_name: @course.name })
    assert_equal 5, misses.get(labels: { course_name: @course.name })
  end

  test "exports calculation error metrics" do
    error_key = "metrics:statistics_errors:#{Time.current.to_i}"
    Rails.cache.write(error_key, 1)
    Rails.cache.write("#{error_key}:tags", {
      course_id: @course.id,
      error_type: "RuntimeError"
    })

    MetricsExporterService.collect_metrics

    errors = Prometheus::Client.registry.get(:course_calculation_errors_total)
    value = errors.get(labels: {
      course_name: @course.name,
      error_type: "RuntimeError"
    })
    
    assert_equal 1, value
  end

  test "handles missing metrics gracefully" do
    assert_nothing_raised do
      MetricsExporterService.collect_metrics
    end
  end

  test "resets metrics correctly" do
    # Add some test metrics
    today = Date.current.to_s
    Rails.cache.write(
      "metrics:course:#{@course.id}:daily_avg_calculation_time:#{today}",
      150.0
    )
    
    MetricsExporterService.collect_metrics
    MetricsExporterService.reset_metrics

    metric = Prometheus::Client.registry.get(:course_calculation_time_seconds)
    value = metric.get(labels: { course_name: @course.name })
    assert_nil value, "Metric should be reset to nil"
  end

  def teardown
    @redis.flushdb
    Rails.cache.clear
    MetricsExporterService.reset_metrics
  end
end