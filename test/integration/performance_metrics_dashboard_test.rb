require 'test_helper'

class PerformanceMetricsDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @teacher = users(:teacher)
    @course = courses(:math)
    @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
    @redis.flushdb
    sign_in @teacher
  end

  test "displays performance metrics dashboard for teachers" do
    # Generate some test metrics
    simulate_course_activity
    
    get performance_metrics_path
    assert_response :success
    
    # Verify all metric sections are present
    assert_select '.cache-stats', 1
    assert_select '.calculation-stats', 1
    assert_select '.error-stats', 1
    assert_select '.course-performance', 1
  end

  test "updates metrics in real-time via AJAX" do
    simulate_course_activity
    
    # Initial request
    get performance_metrics_path(format: :json)
    assert_response :success
    initial_metrics = JSON.parse(response.body)
    
    # Generate new metrics
    simulate_grade_update
    
    # Refresh request
    get performance_metrics_path(format: :json)
    assert_response :success
    updated_metrics = JSON.parse(response.body)
    
    # Verify metrics were updated
    refute_equal initial_metrics['metrics']['calculation_times'],
                updated_metrics['metrics']['calculation_times']
  end

  test "enforces access control" do
    sign_out @teacher
    student = users(:student)
    sign_in student
    
    get performance_metrics_path
    assert_redirected_to root_path
    assert_equal 'Access denied.', flash[:alert]
  end

  test "caches and invalidates metrics appropriately" do
    simulate_course_activity
    
    # First request should miss cache
    get performance_metrics_path(format: :json)
    assert_response :success
    
    # Second request should hit cache
    get performance_metrics_path(format: :json)
    assert_response :success
    
    cache_hits = @redis.keys("metrics:statistics_cache_hit:*").size
    assert cache_hits.positive?, "Should record cache hits"
  end

  private

  def simulate_course_activity
    # Simulate calculation time metrics
    3.times do
      @course.class_average
      @course.passing_rate
      @course.grade_distribution
    end
  end

  def simulate_grade_update
    student = users(:student)
    Grade.create!(
      user: student,
      course: @course,
      numeric_grade: 85
    )
    @course.class_average
  end

  def teardown
    @redis.flushdb
  end
end