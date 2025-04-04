class UpdateGradesTableForCourseAssociation < ActiveRecord::Migration[8.0]
  def up
    # First add the course_id column as nullable
    add_reference :grades, :course, null: true, foreign_key: true
    
    # Remove the old course column
    remove_column :grades, :course, :string
    
    # Clean up any existing grades without courses
    Grade.where(course_id: nil).delete_all
    
    # Now make course_id non-nullable
    change_column_null :grades, :course_id, false
  end

  def down
    add_column :grades, :course, :string
    remove_reference :grades, :course
  end
end
