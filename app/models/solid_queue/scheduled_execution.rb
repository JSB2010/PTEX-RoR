# frozen_string_literal: true

module SolidQueue
  class ScheduledExecution < ApplicationRecord
    self.table_name = "solid_queue_scheduled_executions"
    
    belongs_to :job, class_name: 'SolidQueue::Job'
    
    validates :job_id, uniqueness: true
    validates :queue_name, :scheduled_at, presence: true

    scope :due, -> { where('scheduled_at <= ?', Time.current) }

    def self.dispatch_next_batch(limit, now = Time.current)
      transaction do
        to_dispatch = where("scheduled_at <= ?", now)
          .order(scheduled_at: :asc, priority: :desc, job_id: :asc)
          .limit(limit)
          .to_a

        where(id: to_dispatch).delete_all

        to_dispatch.each do |execution|
          ReadyExecution.create!(
            job: execution.job,
            queue_name: execution.queue_name,
            priority: execution.priority
          )
        end

        to_dispatch
      end
    end
  end
end