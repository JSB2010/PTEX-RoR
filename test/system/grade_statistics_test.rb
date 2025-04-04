require "application_system_test_case"

class GradeStatisticsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  def setup
    @teacher = users(:teacher)
    @student = users(:student)
    @course = Course.create!(name: "Test Course", teacher: @teacher, level: "Regular")
    @grade = Grade.create!(user: @student, course: @course, numeric_grade: 85.5)
  end

  test "teacher can view course statistics" do
    sign_in @teacher
    visit course_path(@course)

    assert_selector "h1", text: "Test Course"
    assert_selector ".statistics-dashboard"
    
    within(".statistics-dashboard") do
      assert_text "Total Students"
      assert_text "1" # One student
      assert_text "Class Average"
      assert_text "85.5%" # Initial grade
      assert_text "Passing Rate"
      assert_text "100%" # Above passing threshold
    end
  end

  test "statistics update in real-time when grades change" do
    sign_in @teacher
    visit course_path(@course)

    within("form[action*='update_grade']") do
      fill_in "grade[numeric_grade]", with: "95.5"
      click_button "Update"
    end

    # Wait for AJAX update
    assert_selector ".toast", text: "Grade updated successfully"
    
    within(".statistics-dashboard") do
      assert_text "Class Average"
      assert_text "95.5%"
    end
  end

  test "student can view their grade history" do
    sign_in @student
    
    # Create some grade history
    @grade.update!(numeric_grade: 90.0)
    @grade.update!(numeric_grade: 95.0)
    
    visit course_path(@course)
    
    assert_selector ".grade-history"
    assert_text "85.5% → 90.0%"
    assert_text "90.0% → 95.0%"
  end

  test "extra credit grades are properly displayed" do
    sign_in @teacher
    visit course_path(@course)

    within("form[action*='update_grade']") do
      fill_in "grade[numeric_grade]", with: "105.0"
      click_button "Update"
    end

    assert_selector ".letter-grade", text: "A++"
    
    within(".statistics-dashboard") do
      assert_text "Class Average"
      assert_text "105.0%"
    end
  end

  test "grade distribution chart updates correctly" do
    sign_in @teacher
    
    # Create a range of grades
    students = {
      "A" => 95.0,
      "B" => 85.0,
      "C" => 75.0,
      "D" => 65.0,
      "F" => 55.0
    }
    
    students.each do |letter, score|
      student = User.create!(
        email: "student_#{letter}@example.com",
        password: "password123",
        first_name: "Student",
        last_name: letter,
        role: "Student"
      )
      Grade.create!(user: student, course: @course, numeric_grade: score)
    end
    
    visit course_path(@course)
    
    within(".grade-distribution") do
      students.each do |letter, _|
        assert_selector ".grade-bar", text: /#{letter}/
      end
    end
  end
end