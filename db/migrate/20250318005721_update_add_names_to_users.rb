class UpdateAddNamesToUsers < ActiveRecord::Migration[8.0]
  def up
    # Set default values for existing users based on their username
    User.where(first_name: nil).find_each do |user|
      # Extract first letter as first name and rest as last name from username
      first_initial = user.username[0]
      last_name = user.username[1..]
      user.update_columns(
        first_name: first_initial.upcase,
        last_name: last_name.capitalize
      )
    end

    # Now make the columns non-null
    change_column_null :users, :first_name, false
    change_column_null :users, :last_name, false
  end

  def down
    change_column_null :users, :first_name, true
    change_column_null :users, :last_name, true
  end
end
