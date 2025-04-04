require "test_helper"

class GradeValidatorTest < ActiveSupport::TestCase
  def setup
    @student = users(:student)
    @teacher = users(:teacher)
    @course = Course.create!(name: "Test Course", teacher: @teacher, level: "Regular")
    @grade = Grade.create!(user: @student, course: @course, numeric_grade: 85.5)
  end

  test "should allow normal grade changes" do
    @grade.numeric_grade = 90.0
    assert @grade.valid?
  end

  test "should not allow huge grade changes" do
    @grade.numeric_grade = 150.0
    assert_not @grade.valid?
    assert_includes @grade.errors[:numeric_grade], "cannot be changed by more than 50.0 points at once"
  end

  test "should allow extra credit above 100" do
    @grade.update!(numeric_grade: 102.5)
    assert @grade.valid?
    assert_equal "A++", @grade.letter_grade
  end

  test "should not allow decreasing extra credit grades" do
    @grade.update!(numeric_grade: 105.0)
    @grade.numeric_grade = 100.0
    assert_not @grade.valid?
    assert_includes @grade.errors[:numeric_grade], "cannot decrease an extra credit grade"
  end

  test "should allow increasing extra credit grades" do
    @grade.update!(numeric_grade: 105.0)
    @grade.numeric_grade = 107.0
    assert @grade.valid?
  end

  test "should properly round grades" do
    @grade.numeric_grade = 89.999
    @grade.save
    assert_equal 90.0, @grade.numeric_grade.to_f
    assert_equal "A-", @grade.letter_grade
  end

  test "should handle edge cases around grade boundaries" do
    edge_cases = {
      96.99 => "A",
      97.00 => "A+",
      92.99 => "A-",
      93.00 => "A",
      89.99 => "B+",
      90.00 => "A-"
    }

    edge_cases.each do |numeric, expected_letter|
      @grade.numeric_grade = numeric
      @grade.save
      assert_equal expected_letter, @grade.letter_grade,
        "Expected #{numeric} to be #{expected_letter}, got #{@grade.letter_grade}"
    end
  end

  test "should properly cache and invalidate cached values" do
    Rails.cache.write("#{@grade.user.cache_key_with_version}/gpa", 3.5)
    Rails.cache.write("#{@grade.course.cache_key_with_version}/average", 85.0)
    
    @grade.update!(numeric_grade: 95.0)
    
    assert_nil Rails.cache.read("#{@grade.user.cache_key_with_version}/gpa")
    assert_nil Rails.cache.read("#{@grade.course.cache_key_with_version}/average")
  end
end