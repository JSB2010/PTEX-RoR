class AddAdminRoleToUsers < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
      ALTER TABLE users ADD CONSTRAINT users_role_check 
        CHECK (role IN ('Student', 'Teacher', 'Admin'));
    SQL

    # Create initial admin user if none exists
    unless User.exists?(role: 'Admin')
      User.create!(
        email: 'admin@ptex.edu',
        username: 'ptexadmin',
        password: 'adminpassword123',
        first_name: 'System',
        last_name: 'Administrator',
        role: 'Admin'
      )
    end
  end

  def down
    execute <<-SQL
      ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
      ALTER TABLE users ADD CONSTRAINT users_role_check 
        CHECK (role IN ('Student', 'Teacher'));
    SQL

    User.where(role: 'Admin').delete_all
  end
end
