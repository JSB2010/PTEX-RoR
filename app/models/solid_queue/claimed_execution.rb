# frozen_string_literal: true

module SolidQueue
  class ClaimedExecution < ApplicationRecord
    self.table_name = "solid_queue_claimed_executions"
    
    belongs_to :job, class_name: 'SolidQueue::Job'
    belongs_to :process, class_name: 'SolidQueue::Process', optional: true

    scope :orphaned, -> { 
      joins("LEFT JOIN solid_queue_processes ON solid_queue_processes.id = solid_queue_claimed_executions.process_id")
        .where("solid_queue_processes.id IS NULL OR solid_queue_processes.last_heartbeat_at < ?", 30.seconds.ago) 
    }

    validates :job_id, uniqueness: true
  end
end