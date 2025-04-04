class AddGradePerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Add composite index for grade queries on course and letter grade
    add_index :grades, [:course_id, :letter_grade]
    
    # Add composite index for GPA calculations
    add_index :grades, [:user_id, :letter_grade]
    
    # Add index for filtering by grade ranges
    add_index :grades, :letter_grade
    
    # Add partial index for incomplete grades
    add_index :grades, :numeric_grade, 
              name: 'index_grades_incomplete',
              where: "numeric_grade = 0.0"
  end
end