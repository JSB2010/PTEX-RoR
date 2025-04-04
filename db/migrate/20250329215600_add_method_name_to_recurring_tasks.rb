class AddMethodNameToRecurringTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :solid_queue_recurring_tasks, :method_name, :string
  end
end