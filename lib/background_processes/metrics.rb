module BackgroundProcesses
  module Metrics
    class << self
      def track_job_execution(job_class, queue, status, duration)
        tags = {
          job_class: job_class.to_s,
          queue: queue,
          status: status
        }

        StatsD.increment("jobs.executed", tags: tags)
        StatsD.timing("jobs.duration", duration, tags: tags) if duration

        record_queue_metrics(queue)
      end

      def track_error(job_class, queue, error)
        tags = {
          job_class: job_class.to_s,
          queue: queue,
          error: error.class.to_s
        }

        StatsD.increment("jobs.errors", tags: tags)
      end

      def track_retry(job_class, queue, attempt)
        tags = {
          job_class: job_class.to_s,
          queue: queue,
          attempt: attempt
        }

        StatsD.increment("jobs.retries", tags: tags)
      end

      private

      def record_queue_metrics(queue)
        queue_size = SolidQueue::Job.where(queue_name: queue).count
        StatsD.gauge("queue.size", queue_size, tags: { queue: queue })
      end
    end
  end
end