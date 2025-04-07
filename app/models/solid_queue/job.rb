# frozen_string_literal: true

module SolidQueue
  class Job < ApplicationRecord
    self.table_name = "solid_queue_jobs"

    # Include necessary modules
    include GlobalID::Identification

    # Associations
    has_one :failed_execution, class_name: 'SolidQueue::FailedExecution', dependent: :destroy
    has_one :ready_execution, class_name: 'SolidQueue::ReadyExecution', dependent: :destroy
    has_one :scheduled_execution, class_name: 'SolidQueue::ScheduledExecution', dependent: :destroy
    has_one :claimed_execution, class_name: 'SolidQueue::ClaimedExecution', dependent: :destroy
    has_one :blocked_execution, class_name: 'SolidQueue::BlockedExecution', dependent: :destroy
    has_one :recurring_execution, class_name: 'SolidQueue::RecurringExecution', dependent: :destroy

    # Validations
    validates :queue_name, :class_name, presence: true

    # Scopes for job states
    scope :ready, -> { joins(:ready_execution) }
    scope :scheduled, -> { joins(:scheduled_execution) }
    scope :claimed, -> { joins(:claimed_execution) }
    scope :blocked, -> { joins(:blocked_execution) }
    scope :recurring, -> { joins(:recurring_execution) }
    scope :active, -> { where(finished_at: nil) }
    scope :finished, -> { where.not(finished_at: nil) }
    scope :failed, -> { where.not(failed_at: nil) }
    scope :succeeded, -> { where.not(finished_at: nil).where(failed_at: nil) }

    def mark_as_failed(error)
      transaction do
        update!(finished_at: Time.current, failed_at: Time.current)
        create_failed_execution!(error: error)
      end
    end

    def retry_job
      return false unless failed_execution
      transaction do
        failed_execution.destroy
        update!(finished_at: nil, failed_at: nil)
      end
      true
    end

    def self.fail_all_with(error)
      where(nil).find_each do |job|
        job.mark_as_failed(error)
      end
    end

    # Add relation methods
    def self.method_missing(method_name, *args, &block)
      if method_name == :fail_all_with
        fail_all_with(*args)
      else
        super
      end
    end

    def self.respond_to_missing?(method_name, include_private = false)
      method_name == :fail_all_with || super
    end
  end
end