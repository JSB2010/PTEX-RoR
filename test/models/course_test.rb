require "test_helper"

class CourseTest < ActiveSupport::TestCase
  def setup
    @teacher = users(:teacher)
    @student = users(:student)
    @course = Course.new(name: "Test Course", teacher: @teacher, level: "Regular")
  end

  test "should be valid with valid attributes" do
    assert @course.valid?
  end

  test "should require a name" do
    @course.name = nil
    assert_not @course.valid?
  end

  test "should require a teacher" do
    @course.teacher = nil
    assert_not @course.valid?
  end

  test "should require a valid level" do
    @course.level = nil
    assert_not @course.valid?

    @course.level = "Invalid"
    assert_not @course.valid?

    valid_levels = ["Regular", "Honors", "AP"]
    valid_levels.each do |level|
      @course.level = level
      assert @course.valid?, "#{level} should be a valid course level"
    end
  end

  test "should have correct GPA boost based on level" do
    @course.level = "Regular"
    assert_equal 0.0, @course.gpa_boost

    @course.level = "Honors"
    assert_equal 0.5, @course.gpa_boost

    @course.level = "AP"
    assert_equal 1.0, @course.gpa_boost
  end

  test "should have many grades" do
    @course.save
    grade = Grade.create!(user: @student, course: @course, numeric_grade: 85)
    assert_includes @course.grades, grade
  end

  test "should have many students through grades" do
    @course.save
    Grade.create!(user: @student, course: @course, numeric_grade: 85)
    assert_includes @course.students, @student
  end

  test "should belong to teacher" do
    assert_equal @teacher, @course.teacher
  end

  test "should calculate class average" do
    @course.save
    Grade.create!(user: @student, course: @course, numeric_grade: 85)
    Grade.create!(user: users(:student_two), course: @course, numeric_grade: 95)
    
    expected_average = 90.0
    assert_equal expected_average, @course.class_average
  end

  test "should handle empty class average" do
    @course.save
    assert_equal 0.0, @course.class_average
  end
end
