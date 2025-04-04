# frozen_string_literal: true

module SolidQueue
  class BlockedExecution < ApplicationRecord
    self.table_name = "solid_queue_blocked_executions"
    
    belongs_to :job, class_name: 'SolidQueue::Job'
    
    validates :job_id, uniqueness: true
    validates :queue_name, :concurrency_key, :expires_at, presence: true

    scope :expired, -> { where('expires_at <= ?', Time.current) }
  end
end