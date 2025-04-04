class AddSeedPasswordToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :seed_password, :string
    add_index :users, :seed_password
  end
end
