class AddMethodNameToSolidQueueJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :solid_queue_jobs, :method_name, :string
  end
end