class AddFailedAtToSolidQueueJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :solid_queue_jobs, :failed_at, :datetime
    add_index :solid_queue_jobs, :failed_at
  end
end
