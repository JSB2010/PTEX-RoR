class AddGradesCountToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :grades_count, :integer, default: 0

    # Reset counter cache
    User.find_each do |user|
      User.reset_counters(user.id, :grades)
    end
  end

  def down
    remove_column :users, :grades_count
  end
end
