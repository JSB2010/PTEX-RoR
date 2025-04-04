# frozen_string_literal: true

# Active Job adapter for SolidQueue
module ActiveJob
  module QueueAdapters
    class SolidQueueAdapter
      def enqueue(job)
        job_data = {
          queue_name: job.queue_name,
          class_name: job.class.name,
          active_job_id: job.job_id,
          arguments: job.serialize.to_json,
          priority: job.priority || 0
        }

        SolidQueue::Job.transaction do
          solid_job = SolidQueue::Job.create!(job_data)
          solid_job.create_ready_execution!(
            queue_name: job.queue_name,
            priority: job.priority || 0
          )
          job.provider_job_id = solid_job.id
        end
      end

      def enqueue_at(job, timestamp)
        job_data = {
          queue_name: job.queue_name,
          class_name: job.class.name,
          active_job_id: job.job_id,
          arguments: job.serialize.to_json,
          priority: job.priority || 0,
          scheduled_at: timestamp
        }

        SolidQueue::Job.transaction do
          solid_job = SolidQueue::Job.create!(job_data)
          solid_job.create_scheduled_execution!(
            queue_name: job.queue_name,
            scheduled_at: timestamp,
            priority: job.priority || 0
          )
          job.provider_job_id = solid_job.id
        end
      end
    end
  end
end