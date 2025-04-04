# frozen_string_literal: true

module SolidQueue
  module RelationMethods
    def fail_all_with(error)
      transaction do
        update_all(finished_at: Time.current)
        find_each do |job|
          job.create_failed_execution!(error: error)
        end
      end
    end
  end
end

ActiveRecord::Relation.include(SolidQueue::RelationMethods)