# frozen_string_literal: true

module SolidQueue
  module RelationMethods
    def fail_all_with(error)
      transaction do
        # Only update the jobs table, not the executions
        if self.klass == SolidQueue::Job
          update_all(finished_at: Time.current, failed_at: Time.current)
        end

        find_each do |record|
          if record.is_a?(SolidQueue::Job)
            record.create_failed_execution!(error: error)
          elsif record.respond_to?(:job)
            # For executions, update the associated job
            job = record.job
            job.update!(finished_at: Time.current, failed_at: Time.current)
            job.create_failed_execution!(error: error)
          end
        end
      end
    end
  end
end

ActiveRecord::Relation.include(SolidQueue::RelationMethods)