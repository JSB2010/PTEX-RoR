require "test_helper"

class GradeTest < ActiveSupport::TestCase
  def setup
    @student = users(:student)
    @teacher = users(:teacher)
    @course = Course.create!(name: "Test Course", teacher: @teacher, level: "Regular")
    @grade = Grade.new(user: @student, course: @course, numeric_grade: 85.5)
  end

  test "should be valid with valid attributes" do
    assert @grade.valid?
  end

  test "should require a numeric grade" do
    @grade.numeric_grade = nil
    assert_not @grade.valid?
  end

  test "should require numeric grade to be non-negative" do
    @grade.numeric_grade = -1
    assert_not @grade.valid?
  end

  test "should handle extra credit scores above 100" do
    @grade.numeric_grade = 105.5
    @grade.save
    assert_equal 'A++', @grade.letter_grade
  end

  test "should calculate correct letter grades" do
    grade_mappings = {
      105 => 'A++', 100 => 'A+', 98.5 => 'A+', 
      95 => 'A', 91.5 => 'A-', 88.5 => 'B+',
      85 => 'B', 81.5 => 'B-', 78.5 => 'C+',
      75 => 'C', 71.5 => 'C-', 68.5 => 'D+',
      65 => 'D', 55 => 'F', 0 => 'F'
    }

    grade_mappings.each do |numeric, letter|
      @grade.numeric_grade = numeric
      @grade.save
      assert_equal letter, @grade.letter_grade, 
        "Expected #{numeric} to be #{letter}, got #{@grade.letter_grade}"
    end
  end

  test "should handle edge cases" do
    @grade.numeric_grade = 100.01
    @grade.save
    assert_equal 'A++', @grade.letter_grade, "Score just over 100 should be A++"
    
    @grade.numeric_grade = 96.99
    @grade.save
    assert_equal 'A', @grade.letter_grade, "Edge case of 96.99 should be A"
  end

  test "should update cached values when grade changes" do
    @grade.save
    original_cache_key = @grade.cache_key_with_version
    
    @grade.update(numeric_grade: 95)
    assert_not_equal original_cache_key, @grade.cache_key_with_version,
      "Cache key should change when grade is updated"
  end

  test "belongs to user and course" do
    grade = grades(:one)
    assert_respond_to grade, :user
    assert_respond_to grade, :course
  end
end
