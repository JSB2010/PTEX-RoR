require 'test_helper'

class CourseStatisticsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @teacher = users(:teacher)
    @course = Course.create!(name: "Test Course", teacher: @teacher, level: "Regular")
    
    # Create test data
    @students = 5.times.map do |i|
      student = User.create!(
        email: "student#{i}@example.com",
        password: "password123",
        first_name: "Student",
        last_name: "#{i}",
        role: "Student"
      )
      Grade.create!(user: student, course: @course, numeric_grade: 80 + i)
      student
    end

    Rails.cache.clear
    sign_in @teacher
  end

  test "statistics endpoint uses caching" do
    # First request should be a cache miss
    get stats_course_path(@course, format: :json)
    assert_response :success
    first_response = JSON.parse(response.body)

    # Record cache hit rate before second request
    initial_hits = read_cache_hits

    # Second request should be a cache hit
    get stats_course_path(@course, format: :json)
    assert_response :success
    second_response = JSON.parse(response.body)

    # Verify responses match
    assert_equal first_response, second_response
    
    # Verify cache was hit
    assert_operator read_cache_hits, :>, initial_hits, "Cache hits should increase"
  end

  test "cache invalidation on grade updates" do
    # Get initial stats
    get stats_course_path(@course, format: :json)
    assert_response :success
    initial_stats = JSON.parse(response.body)

    # Update a grade
    grade = @course.grades.first
    patch update_grade_course_path(@course, 
          student_id: grade.user_id, 
          grade: { numeric_grade: 95.0 },
          format: :json)
    assert_response :success

    # Stats should be recalculated
    get stats_course_path(@course, format: :json)
    assert_response :success
    updated_stats = JSON.parse(response.body)

    assert_not_equal initial_stats["class_average"], 
                     updated_stats["class_average"],
                     "Statistics should be recalculated after grade update"
  end

  test "concurrent access handling" do
    # Simulate concurrent requests
    threads = 5.times.map do
      Thread.new do
        get stats_course_path(@course, format: :json)
        JSON.parse(response.body)
      end
    end

    # Collect results
    results = threads.map(&:value)

    # All requests should return the same data
    assert_equal 1, results.uniq.length, 
                 "All concurrent requests should return consistent data"
  end

  test "rate limiting for statistics endpoint" do
    # Make requests up to the limit
    60.times do
      get stats_course_path(@course, format: :json)
      assert_response :success
    end

    # Next request should be rate limited
    get stats_course_path(@course, format: :json)
    assert_response :too_many_requests
  end

  test "tracks performance metrics" do
    initial_metric_count = count_performance_metrics

    get stats_course_path(@course, format: :json)
    assert_response :success

    assert_operator count_performance_metrics, :>, initial_metric_count,
                   "Performance metrics should be tracked"
  end

  private

  def read_cache_hits
    $redis.with { |conn| conn.get("cache_hits").to_i }
  end

  def count_performance_metrics
    $redis.with do |conn|
      conn.keys("metrics:statistics_calculation_time:*").size
    end
  end
end