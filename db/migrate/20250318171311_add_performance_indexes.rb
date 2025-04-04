class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :grades, [:user_id, :numeric_grade]
    add_index :grades, [:course_id, :numeric_grade]
    add_index :users, :role
  end
end