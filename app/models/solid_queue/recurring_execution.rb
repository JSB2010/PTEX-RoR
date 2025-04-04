# frozen_string_literal: true

module SolidQueue
  class RecurringExecution < ApplicationRecord
    self.table_name = "solid_queue_recurring_executions"
    
    belongs_to :job, class_name: 'SolidQueue::Job'
    belongs_to :recurring_task, class_name: 'SolidQueue::RecurringTask', foreign_key: :task_key, primary_key: :key
    
    validates :job_id, uniqueness: true
    validates :task_key, :run_at, presence: true
    validates :task_key, uniqueness: { scope: :run_at }

    scope :due, -> { where('run_at <= ?', Time.current) }
  end
end