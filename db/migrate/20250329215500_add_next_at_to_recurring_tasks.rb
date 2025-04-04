class AddNextAtToRecurringTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :solid_queue_recurring_tasks, :next_at, :datetime
    add_index :solid_queue_recurring_tasks, :next_at
  end
end