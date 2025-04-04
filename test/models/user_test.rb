require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @teacher = users(:teacher)
    @student = users(:student)
  end

  test "should validate role" do
    user = User.new(
      email: "test@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    )
    assert user.valid?
    assert_equal 'Student', user.role, "Should default to Student role"
  end

  test "should identify teacher role correctly" do
    assert @teacher.teacher?
    assert_not @student.teacher?
  end

  test "should identify student role correctly" do
    assert @student.student?
    assert_not @teacher.student?
  end

  test "should calculate weighted GPA correctly with course boosts" do
    course_regular = Course.create!(name: "Regular Course", teacher: @teacher, level: "Regular")
    course_honors = Course.create!(name: "Honors Course", teacher: @teacher, level: "Honors")
    course_ap = Course.create!(name: "AP Course", teacher: @teacher, level: "AP")

    # Create grades that will test all aspects of GPA calculation
    Grade.create!(user: @student, course: course_regular, numeric_grade: 90) # A- = 3.7
    Grade.create!(user: @student, course: course_honors, numeric_grade: 87)  # B+ = 3.3 + 0.5 = 3.8
    Grade.create!(user: @student, course: course_ap, numeric_grade: 85)      # B = 3.0 + 1.0 = 4.0

    expected_gpa = (3.7 + 3.8 + 4.0) / 3.0
    assert_in_delta expected_gpa, @student.weighted_gpa, 0.01
  end

  test "should calculate unweighted GPA correctly" do
    course_regular = Course.create!(name: "Regular Course", teacher: @teacher, level: "Regular")
    course_honors = Course.create!(name: "Honors Course", teacher: @teacher, level: "Honors")
    course_ap = Course.create!(name: "AP Course", teacher: @teacher, level: "AP")

    Grade.create!(user: @student, course: course_regular, numeric_grade: 90) # A- = 3.7
    Grade.create!(user: @student, course: course_honors, numeric_grade: 87)  # B+ = 3.3
    Grade.create!(user: @student, course: course_ap, numeric_grade: 85)      # B = 3.0

    expected_gpa = (3.7 + 3.3 + 3.0) / 3.0
    assert_in_delta expected_gpa, @student.unweighted_gpa, 0.01
  end

  test "should handle GPA calculation with no grades" do
    new_student = User.create!(
      email: "new@example.com",
      password: "password123",
      first_name: "New",
      last_name: "Student"
    )
    
    assert_equal 0.0, new_student.weighted_gpa
    assert_equal 0.0, new_student.unweighted_gpa
  end

  test "should find honors and AP courses correctly" do
    course_regular = Course.create!(name: "Regular Course", teacher: @teacher, level: "Regular")
    course_honors = Course.create!(name: "Honors Course", teacher: @teacher, level: "Honors")
    course_ap = Course.create!(name: "AP Course", teacher: @teacher, level: "AP")

    Grade.create!(user: @student, course: course_regular, numeric_grade: 85)
    Grade.create!(user: @student, course: course_honors, numeric_grade: 90)
    Grade.create!(user: @student, course: course_ap, numeric_grade: 88)

    honors_ap = @student.honors_ap_courses
    assert_equal 2, honors_ap.count
    assert_includes honors_ap.pluck(:name), "Honors Course"
    assert_includes honors_ap.pluck(:name), "AP Course"
    refute_includes honors_ap.pluck(:name), "Regular Course"
  end

  test "teacher should have courses" do
    course = Course.create!(name: "Teacher Course", teacher: @teacher, level: "Regular")
    assert_includes @teacher.courses, course
  end

  test "student should have grades" do
    grade = Grade.create!(user: @student, course: Course.create!(name: "Course", teacher: @teacher, level: "Regular"), numeric_grade: 85)
    assert_includes @student.grades, grade
  end

  test "should generate unique usernames" do
    user1 = User.create!(
      email: "john.smith@example.com",
      password: "password123",
      first_name: "John",
      last_name: "Smith"
    )
    assert_equal "jsmith", user1.username

    user2 = User.create!(
      email: "jane.smith@example.com",
      password: "password123",
      first_name: "Jane",
      last_name: "Smith"
    )
    assert_equal "jsmith1", user2.username
  end

  test "should find user by username or email for authentication" do
    user = User.create!(
      email: "auth.test@example.com",
      password: "password123",
      first_name: "Auth",
      last_name: "Test"
    )

    found_by_email = User.find_for_database_authentication(login: user.email)
    found_by_username = User.find_for_database_authentication(login: user.username)

    assert_equal user, found_by_email
    assert_equal user, found_by_username
  end
end
