# frozen_string_literal: true

module Extensions
  module ActiveRecord
    module Relation
      def fail_all_with(error)
        return unless klass.ancestors.include?(SolidQueue::Job)

        transaction do
          update_all(finished_at: Time.current)
          find_each do |job|
            job.create_failed_execution!(error: error)
          end
        end
      end
    end
  end
end

ActiveRecord::Relation.include(Extensions::ActiveRecord::Relation)