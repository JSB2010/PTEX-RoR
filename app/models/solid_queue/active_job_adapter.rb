# frozen_string_literal: true

module ActiveJob
  module QueueAdapters
    class SolidQueueAdapter
      def enqueue(job)
        Rails.logger.info("[SolidQueue::ActiveJobAdapter] Enqueueing job: #{job.class.name}")
        enqueue_at(job, nil)
      end

      def enqueue_at(job, timestamp)
        Rails.logger.info("[SolidQueue::ActiveJobAdapter] Enqueueing job at timestamp: #{timestamp}")
        job_data = {
          queue_name: job.queue_name,
          class_name: job.class.name,
          active_job_id: job.job_id,
          arguments: job.serialize['arguments'],
          scheduled_at: timestamp
        }

        Rails.logger.info("[SolidQueue::ActiveJobAdapter] Job data: #{job_data}")

        SolidQueue::Job.transaction do
          solid_job = SolidQueue::Job.create!(job_data)

          if timestamp
            solid_job.create_scheduled_execution!(
              queue_name: job.queue_name,
              scheduled_at: timestamp,
              priority: job.priority || 0
            )
          else
            solid_job.create_ready_execution!(
              queue_name: job.queue_name,
              priority: job.priority || 0
            )
          end

          job.provider_job_id = solid_job.id
          Rails.logger.info("[SolidQueue::ActiveJobAdapter] Job enqueued with ID: #{solid_job.id}")
        end
      end
    end
  end
end