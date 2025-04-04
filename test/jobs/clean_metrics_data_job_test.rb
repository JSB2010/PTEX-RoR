require 'test_helper'

class CleanMetricsDataJobTest < ActiveJob::TestCase
  def setup
    @course = courses(:math)
    @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
    @redis.flushdb
    Rails.cache.clear
  end

  test "removes metrics older than 24 hours" do
    assert_equal 5, count_total_metrics
    
    perform_enqueued_jobs do
      CleanMetricsDataJob.perform_later
    end

    assert_equal 2, count_total_metrics, "Should only keep recent metrics"
    
    # Verify old metrics are gone
    old_keys = @redis.keys("metrics:*:#{@old_time}")
    assert_empty old_keys, "Should remove all old metrics"
    
    # Verify recent metrics remain
    recent_keys = @redis.keys("metrics:*:#{@recent_time}")
    assert_equal 2, recent_keys.size, "Should keep recent metrics"
  end

  test "logs cleanup results" do
    logs = capture_logs do
      perform_enqueued_jobs do
        CleanMetricsDataJob.perform_later
      end
    end

    cleanup_log = JSON.parse(logs.string.lines.last)
    assert cleanup_log['cleanup'].key?('remaining_keys'), "Should log remaining keys count"
    assert_equal 2, cleanup_log['cleanup']['remaining_keys'], "Should report correct number of remaining keys"
  end

  test "cleans up old metrics" do
    # Create old and new metrics
    old_time = 2.weeks.ago.to_i / 300
    new_time = Time.current.to_i / 300
    
    Rails.cache.write("metrics:test:#{old_time}", "old_value")
    Rails.cache.write("metrics:test:#{new_time}", "new_value")
    
    CleanMetricsDataJob.perform_now
    
    assert_nil Rails.cache.read("metrics:test:#{old_time}"), "Old metric should be deleted"
    assert_not_nil Rails.cache.read("metrics:test:#{new_time}"), "New metric should be retained"
  end

  test "cleans up orphaned tags" do
    # Create a metric with tags
    Rails.cache.write("metrics:test:1", "value")
    Rails.cache.write("metrics:test:1:tags", { type: "test" })
    
    # Create orphaned tags
    Rails.cache.write("metrics:test:2:tags", { type: "orphaned" })
    
    CleanMetricsDataJob.perform_now
    
    assert_not_nil Rails.cache.read("metrics:test:1:tags"), "Valid tags should be retained"
    assert_nil Rails.cache.read("metrics:test:2:tags"), "Orphaned tags should be deleted"
  end

  test "compacts course metrics" do
    # Simulate multiple cache hits/misses
    5.times do |i|
      Rails.cache.write("metrics:course:#{@course.id}:cache_hits:detail:#{i}", 1)
      Rails.cache.write("metrics:course:#{@course.id}:cache_misses:detail:#{i}", 1)
    end
    
    CleanMetricsDataJob.perform_now
    
    today = Date.current.to_s
    hits = Rails.cache.read("metrics:course:#{@course.id}:cache_hits:#{today}")
    misses = Rails.cache.read("metrics:course:#{@course.id}:cache_misses:#{today}")
    
    assert_equal 5, hits, "Should compact hits into daily total"
    assert_equal 5, misses, "Should compact misses into daily total"
    
    # Verify original detailed metrics were cleaned up
    5.times do |i|
      assert_nil Rails.cache.read("metrics:course:#{@course.id}:cache_hits:detail:#{i}")
      assert_nil Rails.cache.read("metrics:course:#{@course.id}:cache_misses:detail:#{i}")
    end
  end

  test "compacts calculation times into daily averages" do
    # Create calculation time metrics
    times = [100, 150, 200, 250, 300]
    times.each_with_index do |time, i|
      key = "metrics:statistics_calculation_time:#{(25.hours.ago.to_i / 300) - i}"
      Rails.cache.write(key, time)
    end
    
    CleanMetricsDataJob.perform_now
    
    today = Date.current.to_s
    avg_time = Rails.cache.read(
      "metrics:course:#{@course.id}:daily_avg_calculation_time:#{today}"
    )
    
    expected_avg = times.sum / times.size
    assert_in_delta expected_avg, avg_time, 0.01, "Should store correct daily average"
  end

  test "handles empty metrics gracefully" do
    assert_nothing_raised do
      CleanMetricsDataJob.perform_now
    end
  end

  private

  def add_test_metric(type, timestamp, tags, value)
    key = "metrics:#{type}:#{timestamp}"
    @redis.hset(key, tags.to_json, value)
  end

  def count_total_metrics
    @redis.keys("metrics:*").size
  end

  def capture_logs
    old_logger = Rails.logger
    log_output = StringIO.new
    Rails.logger = Logger.new(log_output)
    yield
    log_output
  ensure
    Rails.logger = old_logger
  end

  def teardown
    @redis.flushdb
    Rails.cache.clear
  end
end