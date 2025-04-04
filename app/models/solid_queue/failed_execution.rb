# frozen_string_literal: true

module SolidQueue
  class FailedExecution < ApplicationRecord
    self.table_name = "solid_queue_failed_executions"
    
    belongs_to :job, class_name: 'SolidQueue::Job'
    
    validates :error, presence: true
    validates :job_id, uniqueness: true

    after_create :mark_job_as_failed

    private

    def mark_job_as_failed
      job.update_column(:finished_at, Time.current) if job.finished_at.nil?
    end
  end
end