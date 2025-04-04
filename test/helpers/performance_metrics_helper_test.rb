require 'test_helper'

class PerformanceMetricsHelperTest < ActionView::TestCase
  test "cache_performance_class returns correct classes" do
    assert_equal 'bg-success', cache_performance_class(85)
    assert_equal 'bg-info', cache_performance_class(65)
    assert_equal 'bg-warning', cache_performance_class(45)
    assert_equal 'bg-danger', cache_performance_class(35)
  end

  test "format_error_type formats error types correctly" do
    assert_equal 'Database Connection Error', format_error_type('database_connection_error')
    assert_equal 'Cache Miss', format_error_type('cache_miss')
  end

  test "format_calculation_time formats time correctly" do
    assert_equal '500.0ms', format_calculation_time(500)
    assert_equal '2.50s', format_calculation_time(2500)
    assert_equal 'N/A', format_calculation_time(nil)
  end

  test "cache_hit_rate_badge returns correct badge" do
    assert_match /bg-success.*Excellent/m, cache_hit_rate_badge(85)
    assert_match /bg-info.*Good/m, cache_hit_rate_badge(65)
    assert_match /bg-warning.*Fair/m, cache_hit_rate_badge(45)
    assert_match /bg-danger.*Poor/m, cache_hit_rate_badge(35)
  end

  test "format_memory_usage formats bytes correctly" do
    assert_equal '1.00 KB', format_memory_usage(1024)
    assert_equal '1.00 MB', format_memory_usage(1024 * 1024)
    assert_equal '1.00 GB', format_memory_usage(1024 * 1024 * 1024)
    assert_equal '0 B', format_memory_usage(nil)
    assert_equal '0 B', format_memory_usage(0)
  end

  test "relative_time_in_words formats time correctly" do
    assert_match /ago/, relative_time_in_words(5.minutes.ago)
    assert_match /ago/, relative_time_in_words(2.hours.ago)
    assert_match /\d{2}:\d{2}/, relative_time_in_words(2.days.ago)
  end

  test "performance_status_icon returns correct icon" do
    assert_match /bi-check-circle-fill.*text-success/m, performance_status_icon('ok')
    assert_match /bi-exclamation-triangle-fill.*text-warning/m, performance_status_icon('warning')
    assert_match /bi-x-circle-fill.*text-danger/m, performance_status_icon('critical')
    assert_match /bi-question-circle-fill.*text-muted/m, performance_status_icon('unknown')
  end

  test "memory_usage_indicator shows correct percentage and status" do
    assert_match /bg-success.*width: 50%/m, memory_usage_indicator(500, 1000)
    assert_match /bg-warning.*width: 75%/m, memory_usage_indicator(750, 1000)
    assert_match /bg-danger.*width: 90%/m, memory_usage_indicator(900, 1000)
  end
end