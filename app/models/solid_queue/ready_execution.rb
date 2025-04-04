# frozen_string_literal: true

module SolidQueue
  class ReadyExecution < ApplicationRecord
    self.table_name = "solid_queue_ready_executions"
    
    belongs_to :job, class_name: 'SolidQueue::Job'
    
    validates :job_id, uniqueness: true
    validates :queue_name, presence: true

    def self.claim(limit, queue_name = nil, _unused = nil)
      # Handle case when limit is an array (which happens with SolidQueue 1.1.4)
      limit = if limit.is_a?(Array)
        limit.first.to_i rescue 100
      else
        limit.to_i
      end
      
      return [] if limit < 1
      
      transaction do
        to_claim = if queue_name
          where(queue_name: queue_name).order(priority: :desc, job_id: :asc).limit(limit)
        else
          order(priority: :desc, job_id: :asc).limit(limit)
        end
        
        claimed = to_claim.to_a
        where(id: claimed).delete_all
        claimed
      end
    end
  end
end