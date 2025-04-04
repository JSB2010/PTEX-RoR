require "test_helper"

class StatisticsMetricsTest < ActiveSupport::TestCase
  def setup
    @teacher = users(:teacher)
    @course = Course.create!(name: "Test Course", teacher: @teacher, level: "Regular")
    
    # Create test grades with a known distribution
    @grades = [95, 87, 82, 75, 65].each_with_index do |score, i|
      student = User.create!(
        email: "student#{i}@example.com",
        password: "password123",
        first_name: "Student",
        last_name: "#{i}",
        role: "Student"
      )
      Grade.create!(user: student, course: @course, numeric_grade: score)
    end

    Rails.cache.clear
  end

  test "tracks calculation time for all statistical methods" do
    [:class_average, :passing_rate, :grade_distribution].each do |method|
      metric_logged = false
      
      assert_changes -> { metric_logged } do
        @course.send(method)
        log_entry = Rails.logger.messages.last
        metric_data = JSON.parse(log_entry)
        metric_logged = metric_data["metric"]["name"] == "statistics_calculation_time" &&
                       metric_data["metric"]["tags"]["calculation_type"] == method.to_s
      end
    end
  end

  test "uses cached values efficiently" do
    # First call should calculate
    initial_average = @course.class_average
    initial_logs = Rails.logger.messages.size
    
    # Second call should use cache
    cached_average = @course.class_average
    assert_equal initial_average, cached_average
    assert_equal initial_logs, Rails.logger.messages.size
    
    # Verify cache hit was tracked
    cache_hits = Rails.cache.read("metrics:course:#{@course.id}:cache_hits").to_i
    assert_equal 1, cache_hits, "Should track cache hit"
  end

  test "calculates correct statistics" do
    # Test class average
    expected_average = 80.8 # (95 + 87 + 82 + 75 + 65) / 5
    assert_in_delta expected_average, @course.class_average, 0.1
    
    # Test passing rate
    expected_passing = 80.0 # 4 out of 5 are passing (>=60)
    assert_in_delta expected_passing, @course.passing_rate, 0.1
    
    # Test grade distribution
    distribution = @course.grade_distribution
    assert_equal 1, distribution["A"]
    assert_equal 1, distribution["B+"]
    assert_equal 1, distribution["B-"]
    assert_equal 1, distribution["C"]
    assert_equal 1, distribution["D"]
  end

  test "invalidates cache when grades change" do
    original_average = @course.class_average
    
    # Add a new grade
    student = User.create!(
      email: "new_student@example.com",
      password: "password123",
      first_name: "New",
      last_name: "Student",
      role: "Student"
    )
    Grade.create!(user: student, course: @course, numeric_grade: 100)
    
    new_average = @course.class_average
    assert_not_equal original_average, new_average,
      "Average should be recalculated after new grade"
  end

  test "tracks errors in statistics calculations" do
    # Simulate an error in calculation
    Grade.stub :average, -> { raise StandardError, "Test error" } do
      assert_raises StandardError do
        @course.class_average
      end
      
      log_entry = Rails.logger.messages.last
      metric_data = JSON.parse(log_entry)
      
      assert_equal "statistics_errors", metric_data["metric"]["name"]
      assert_equal "StandardError", metric_data["metric"]["tags"]["error_type"]
      assert_equal "Test error", metric_data["metric"]["tags"]["error_message"]
    end
  end

  test "includes performance context in metrics" do
    @course.class_average
    
    log_entry = Rails.logger.messages.last
    metric_data = JSON.parse(log_entry)
    
    assert metric_data["metric"]["tags"].key?("course_id"), 
           "Should include course_id in metric tags"
    assert metric_data["metric"]["tags"].key?("calculation_type"), 
           "Should include calculation_type in metric tags"
    assert metric_data["metric"]["tags"].key?("student_count"), 
           "Should include student_count in metric tags"
    assert metric_data["metric"]["value"].is_a?(Numeric), 
           "Should track calculation time as number"
  end

  test "handles concurrent access to statistics" do
    threads = 3.times.map do
      Thread.new do
        @course.class_average
      end
    end

    results = threads.map(&:value)
    assert_equal 1, results.uniq.size, 
                 "All concurrent requests should return the same value"
  end
end