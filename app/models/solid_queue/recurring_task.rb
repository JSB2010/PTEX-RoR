# frozen_string_literal: true

module SolidQueue
  class RecurringTask < ApplicationRecord
    self.table_name = "solid_queue_recurring_tasks"

    has_many :executions, 
      class_name: 'SolidQueue::RecurringExecution',
      foreign_key: :task_key,
      primary_key: :key,
      dependent: :destroy

    validates :key, presence: true, uniqueness: true
    validates :schedule, presence: true
    validates :class_name, presence: true

    before_create :set_initial_next_at
    after_save :update_next_at, if: :schedule_changed?

    def calculate_next_run
      return nil unless schedule.present?
      cron = Fugit::Cron.parse(schedule)
      return nil unless cron
      
      # Use Fugit's native UTC time output
      next_time = cron.next_time.utc
      Time.find_zone('UTC').at(next_time.year, next_time.month, next_time.day, 
                              next_time.hour, next_time.min, next_time.sec)
    rescue => e
      Rails.logger.error("Error calculating next run time: #{e.message}")
      nil
    end

    def schedule_next_execution
      return unless next_at && next_at <= Time.current
      
      transaction do
        # Check if we already have an execution scheduled for this time
        return if executions.exists?(run_at: next_at)
        
        job = SolidQueue::Job.create!(
          queue_name: queue_name || 'default',
          class_name: class_name,
          method_name: method_name,
          arguments: arguments,
          scheduled_at: next_at,
          priority: priority
        )

        executions.create!(
          job: job,
          run_at: next_at
        )

        # Update next_at after creating execution
        update_next_at
      end
    end

    private

    def set_initial_next_at
      self.next_at = calculate_next_run
    end

    def update_next_at
      # Only update if we can calculate a valid next time
      if (next_time = calculate_next_run)
        update_column(:next_at, next_time)
      end
    end
  end
end