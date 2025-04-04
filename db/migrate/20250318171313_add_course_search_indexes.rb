class AddCourseSearchIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :courses, [:name, :level]
    add_index :courses, "LOWER(name) varchar_pattern_ops"
    add_index :courses, [:user_id, :level]
  end
end