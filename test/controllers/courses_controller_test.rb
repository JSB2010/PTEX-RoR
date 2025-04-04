require "test_helper"

class CoursesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @teacher = users(:teacher)
    @student = users(:student)
    @course = Course.create!(name: "Test Course", teacher: @teacher, level: "Regular")
    @grade = Grade.create!(user: @student, course: @course, numeric_grade: 85.5)
  end

  test "should get index for teacher" do
    sign_in @teacher
    get courses_url
    assert_response :success
    assert_select "h1", "Your Courses"
  end

  test "should get index for student" do
    sign_in @student
    get courses_url
    assert_response :success
    assert_select "h1", "Your Courses"
  end

  test "should handle search" do
    sign_in @teacher
    get courses_url, params: { search: "Test" }
    assert_response :success
    assert_select ".course-card", count: 1
  end

  test "should filter by level" do
    Course.create!(name: "AP Course", teacher: @teacher, level: "AP")
    sign_in @teacher
    
    get courses_url, params: { level: "AP" }
    assert_response :success
    assert_select ".course-card", count: 1
    assert_select ".course-name", "AP Course"
  end

  test "should cache course list" do
    sign_in @teacher
    
    # First request should miss cache
    get courses_url
    assert_response :success
    
    # Second request should hit cache
    Rails.cache.expects(:fetch).returns([@course])
    get courses_url
    assert_response :success
  end

  test "should invalidate cache on course update" do
    sign_in @teacher
    
    # Initial request
    get courses_url
    assert_response :success
    
    # Update course
    @course.update!(name: "Updated Course")
    
    # Cache should be invalidated
    Rails.cache.expects(:fetch).once
    get courses_url
    assert_response :success
  end

  test "should protect teacher-only actions" do
    sign_in @student
    
    # Try to create a course
    post courses_url, params: { course: { name: "New Course", level: "Regular" } }
    assert_redirected_to courses_path
    assert_equal 'You must be a teacher to perform this action.', flash[:alert]
    
    # Try to edit a course
    patch course_url(@course), params: { course: { name: "Updated" } }
    assert_redirected_to courses_path
    assert_equal 'You must be a teacher to perform this action.', flash[:alert]
  end

  test "should handle grade updates" do
    sign_in @teacher
    
    patch update_grade_course_path(@course), params: {
      student_id: @student.id,
      grade: { numeric_grade: 95.5 }
    }
    
    assert_redirected_to @course
    @grade.reload
    assert_equal 95.5, @grade.numeric_grade
    assert_equal "A", @grade.letter_grade
  end

  test "should handle extra credit grades" do
    sign_in @teacher
    
    patch update_grade_course_path(@course), params: {
      student_id: @student.id,
      grade: { numeric_grade: 105.0 }
    }
    
    assert_redirected_to @course
    @grade.reload
    assert_equal 105.0, @grade.numeric_grade
    assert_equal "A++", @grade.letter_grade
  end

  test "should track grade history" do
    sign_in @teacher
    
    # Make multiple grade updates
    [90.0, 95.0, 105.0].each do |score|
      patch update_grade_course_path(@course), params: {
        student_id: @student.id,
        grade: { numeric_grade: score }
      }
    end
    
    @grade.reload
    history = @grade.recent_changes
    assert_equal 3, history.length
    assert_equal 95.0, history.last["from"]
    assert_equal 105.0, history.last["to"]
  end
end
