class AddLevelToCourses < ActiveRecord::Migration[8.0]
  def change
    add_column :courses, :level, :string
  end
end
