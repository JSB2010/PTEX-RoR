require "test_helper"

class GradeHistoryTest < ActiveSupport::TestCase
  def setup
    @student = users(:student)
    @teacher = users(:teacher)
    @course = Course.create!(name: "Test Course", teacher: @teacher, level: "Regular")
    @grade = Grade.create!(user: @student, course: @course, numeric_grade: 85.5)
  end

  test "should track grade changes in history" do
    original_grade = @grade.numeric_grade
    
    # Make multiple changes
    updates = [90.0, 92.5, 88.0]
    updates.each do |new_grade|
      @grade.update!(numeric_grade: new_grade)
    end

    history = @grade.recent_changes
    assert_equal 3, history.length
    
    # Check the most recent change
    last_change = history.last
    assert_equal 92.5, last_change["from"]
    assert_equal 88.0, last_change["to"]
  end

  test "should limit history to last 10 changes" do
    # Make 12 changes
    12.times do |i|
      @grade.update!(numeric_grade: 80.0 + i)
    end

    history = @grade.recent_changes
    assert_equal 10, history.length
    
    # First change should be the third update (since we keep last 10)
    first_stored = history.first
    assert_equal 82.0, first_stored["to"]
  end

  test "should maintain history across cache clears" do
    @grade.update!(numeric_grade: 90.0)
    Rails.cache.clear
    
    history = @grade.recent_changes
    assert_empty history, "History should start fresh after complete cache clear"
    
    @grade.update!(numeric_grade: 95.0)
    new_history = @grade.recent_changes
    assert_equal 1, new_history.length
    assert_equal 90.0, new_history.last["from"]
    assert_equal 95.0, new_history.last["to"]
  end
end