class AddCoursesCountToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :courses_count, :integer, default: 0, null: false
    
    # Reset counter cache for existing records
    say_with_time 'Updating counter cache for existing users...' do
      User.find_each do |user|
        User.reset_counters(user.id, :courses)
      end
    end
  end
  
  def down
    remove_column :users, :courses_count
  end
end
